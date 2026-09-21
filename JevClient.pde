// ============================================================
//  JevClient — one call to TypeSafe's System One endpoint per decision.
//
//  POST https://api.typesafe.ai/v1/systemone
//  { "state": <what the bot sees>, "model": "jev-latest", "questions": <data/questions.json> }
//  → { "answers": { "action": {choice, probabilities, confidence}, ... }, "usage": {...} }
//
//  The questions file is spliced into the body verbatim so its field order is
//  exactly what you wrote. Retries 429 / 529 / 5xx with exponential backoff,
//  honouring a retry-after header when there is one.
// ============================================================

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;

final String[] VALID_ACTIONS = { "forward", "backward", "turn_left", "turn_right" };

class JevClient {
  HttpClient http;
  String apiKey;
  String questionsJson;   // raw text of data/questions.json, minified

  JevClient(String apiKey, String questionsJson) {
    this.apiKey = apiKey;
    this.questionsJson = questionsJson;
    http = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(8)).build();
  }

  // sample=true → pick the action by sampling Jev's probabilities instead of taking the argmax
  Decision ask(JsonOut state, boolean sample) {
    Decision d = new Decision();
    d.sampled = sample;
    String body = "{\"state\":" + state.toJson()
                + ",\"model\":\"" + JEV_MODEL + "\""
                + ",\"questions\":" + questionsJson + "}";
    if (LOG_REQUEST_JSON) println("→ " + body);

    HttpRequest req = HttpRequest.newBuilder(URI.create(JEV_ENDPOINT))
      .header("Authorization", "Bearer " + apiKey)
      .header("Content-Type", "application/json")
      .timeout(Duration.ofMillis(REQUEST_TIMEOUT_MS))
      .POST(HttpRequest.BodyPublishers.ofString(body))
      .build();

    for (int attempt = 0; ; attempt++) {
      String failure;
      long waitMs = (long) (500 * pow(2, attempt) + random(250));
      try {
        HttpResponse<String> res = http.send(req, HttpResponse.BodyHandlers.ofString());
        int code = res.statusCode();
        if (LOG_REQUEST_JSON) println("← " + code + " " + res.body());
        if (code == 200) {
          parse(res.body(), d, sample);
          return d;
        }
        if (code == 429 || code == 529 || code >= 500) {
          failure = "HTTP " + code;
          String ra = res.headers().firstValue("retry-after").orElse(null);
          if (ra != null) {
            try { waitMs = Math.max(waitMs, (long) (Float.parseFloat(ra) * 1000)); } catch (NumberFormatException ignore) {}
          }
        } else {
          // 401 bad key, 422 malformed question, etc. — retrying won't help
          d.error = "HTTP " + code + ": " + snip(res.body(), 300);
          return d;
        }
      } catch (Exception e) {
        failure = e.getClass().getSimpleName() + (e.getMessage() != null ? ": " + e.getMessage() : "");
      }
      if (attempt >= MAX_RETRIES) {
        d.error = failure + " (gave up after " + (attempt + 1) + " attempts)";
        return d;
      }
      try { Thread.sleep(waitMs); } catch (InterruptedException ie) { d.error = "interrupted"; return d; }
    }
  }

  void parse(String body, Decision d, boolean sample) {
    try {
      JSONObject json = JSONObject.parse(body);
      d.model = json.getString("model", "");
      if (json.hasKey("usage")) {
        JSONObject usage = json.getJSONObject("usage");
        d.inputTokens  = usage.getInt("input_tokens", 0);
        d.outputTokens = usage.getInt("output_tokens", 0);
      }
      JSONObject answers = json.getJSONObject("answers");

      JSONObject act = answers.getJSONObject("action");
      JSONObject probs = act.getJSONObject("probabilities");
      for (String a : VALID_ACTIONS) d.actionProbs.put(a, probs.getFloat(a, 0));
      d.actionConfidence = act.getFloat("confidence", 0);
      d.action = sample ? sampleFrom(d.actionProbs) : act.getString("choice");

      d.turnAmount = answers.getJSONObject("turn_amount").getString("choice");
      d.moveAmount = answers.getJSONObject("move_amount").getString("choice");

      if (!isValidAction(d.action)) d.error = "Jev returned an unknown action: " + d.action;
    } catch (Exception e) {
      d.error = "Could not read response: " + e.getMessage() + " — " + snip(body, 200);
    }
  }

  String sampleFrom(LinkedHashMap<String, Float> probs) {
    float r = random(1), acc = 0;
    String lastKey = "forward";
    for (Map.Entry<String, Float> e : probs.entrySet()) {
      acc += e.getValue();
      lastKey = e.getKey();
      if (r < acc) return lastKey;
    }
    return lastKey;
  }

  boolean isValidAction(String a) {
    for (String v : VALID_ACTIONS) if (v.equals(a)) return true;
    return false;
  }

  String snip(String s, int n) {
    if (s == null) return "";
    s = s.replace('\n', ' ');
    return s.length() > n ? s.substring(0, n) + "…" : s;
  }
}
