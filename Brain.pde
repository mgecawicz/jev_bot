// ============================================================
//  BRAIN — anything that can turn a bot's state into a Decision.
//  JevBrain is the real thing. RandomBrain is a zero-cost baseline so you
//  can check the arena works (and see how much better Jev does than chance).
// ============================================================

import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.ThreadFactory;

interface Brain {
  // Must eventually set bot.pending — synchronously or from another thread.
  void decide(Bot bot, JsonOut state);
  String name();
}

// What the bot does next, plus everything the HUD wants to show about how it was chosen.
class Decision {
  String action     = "forward";     // forward | backward | turn_left | turn_right
  String turnAmount = "slight";      // slight | sharp
  String moveAmount = "short";       // short | long
  float actionConfidence = 0;
  LinkedHashMap<String, Float> actionProbs = new LinkedHashMap<String, Float>();
  String model = "";
  int inputTokens = 0, outputTokens = 0;
  int latencyMs = 0;
  boolean sampled = false;           // action was sampled from the distribution rather than argmax
  String error;                      // non-null → the request failed; message for the HUD/console

  String probsSummary() {
    StringBuilder sb = new StringBuilder("{");
    for (Map.Entry<String, Float> e : actionProbs.entrySet()) {
      if (sb.length() > 1) sb.append(", ");
      sb.append(e.getKey()).append(':').append(String.format("%.2f", e.getValue()));
    }
    return sb.append('}').toString();
  }
}

// ------------------------------------------------------------ Jev
class JevBrain implements Brain {
  JevClient client;
  ExecutorService pool;

  JevBrain(String apiKey, String questionsJson) {
    client = new JevClient(apiKey, questionsJson);
    // daemon threads so closing the sketch never hangs on an in-flight request
    pool = Executors.newCachedThreadPool(new ThreadFactory() {
      public Thread newThread(Runnable r) {
        Thread t = new Thread(r, "jev-request");
        t.setDaemon(true);
        return t;
      }
    });
  }

  void decide(final Bot bot, final JsonOut state) {
    // decided on the main thread, before the request goes out
    final boolean sample = SAMPLE_ACTION_FROM_PROBABILITIES || (SAMPLE_WHEN_STUCK && bot.isStuck());
    pool.submit(new Runnable() {
      public void run() {
        bot.pending = client.ask(state, sample);
      }
    });
  }

  String name() { return "Jev (" + JEV_MODEL + ")"; }
}

// ------------------------------------------------------------ baseline
class RandomBrain implements Brain {
  String[] actions = { "forward", "forward", "forward", "turn_left", "turn_right", "backward" };

  void decide(Bot bot, JsonOut state) {
    Decision d = new Decision();
    d.action = actions[(int) random(actions.length)];
    d.turnAmount = random(1) < 0.5 ? "slight" : "sharp";
    d.moveAmount = random(1) < 0.5 ? "short" : "long";
    d.actionConfidence = 0.25;
    for (String a : new String[] { "forward", "backward", "turn_left", "turn_right" }) d.actionProbs.put(a, 0.25);
    d.model = "random";
    bot.pending = d;
  }

  String name() { return "Random baseline (no API calls)"; }
}
