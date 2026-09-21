// ============================================================
//  JEV BOT ARENA
//
//  Little robots hunt treasure in an arena full of obstacles. Each bot can
//  drive forward or backward and turn, and sees a cone in front of it.
//  Its brain is Jev, TypeSafe AI's System One model: every step the bot
//  sends what it sees plus its recent actions as `state`, Jev answers the
//  question set in data/questions.json, and the typed answers drive the bot.
//  Forever.
//
//  Setup:   paste your key into Config.pde (TYPESAFE_API_KEY) and hit Run.
//  Tune:    everything is in Config.pde; the questions are data/questions.json.
//  Keys:    SPACE pause · R new arena · V cone · Y rays · + / - bots · L log JSON
//
//  Self-test (no API key, random brain, saves selftest.png and exits):
//    Processing cli --sketch=<this folder> --run selftest
// ============================================================

Arena arena;
ArrayList<Bot> bots = new ArrayList<Bot>();
Brain brain;
Stats stats = new Stats();
boolean paused = false;
boolean selfTest = false;
String startupError = null;

color[] PALETTE = {
  color(80, 200, 255), color(255, 120, 200), color(140, 255, 140), color(255, 170, 70),
  color(190, 140, 255), color(255, 240, 100), color(100, 255, 220), color(255, 110, 110)
};

void settings() {
  size(ARENA_WIDTH + SIDEBAR_WIDTH, ARENA_HEIGHT);
}

void setup() {
  surface.setTitle("Jev Bot Arena");
  selfTest = args != null && args.length > 0 && args[0].equals("selftest");
  if (selfTest) USE_JEV = false;

  if (RANDOM_SEED != 0) randomSeed(RANDOM_SEED);

  brain = buildBrain();
  arena = new Arena(ARENA_WIDTH, ARENA_HEIGHT);
  resetArena();
}

Brain buildBrain() {
  if (!USE_JEV) return new RandomBrain();

  String key = resolveApiKey();
  if (key == null) {
    startupError = "No TypeSafe API key.\nPaste it into Config.pde (TYPESAFE_API_KEY), set the TYPESAFE_API_KEY\nenvironment variable, or create data/typesafe_api_key.txt. Bots are idle until then.";
    println(startupError);
    return null;
  }
  String[] lines = loadStrings(QUESTIONS_FILE);
  if (lines == null) {
    startupError = "Could not read data/" + QUESTIONS_FILE;
    println(startupError);
    return null;
  }
  String questions = join(lines, "\n");
  try {
    // Parse once to validate and minify; the minified text is sent as-is on every request.
    JSONObject.parse(questions);
    questions = minifyJson(questions);
  } catch (Exception e) {
    startupError = "data/" + QUESTIONS_FILE + " is not valid JSON: " + e.getMessage();
    println(startupError);
    return null;
  }
  return new JevBrain(key, questions);
}

String resolveApiKey() {
  if (TYPESAFE_API_KEY != null && TYPESAFE_API_KEY.trim().length() > 0) return TYPESAFE_API_KEY.trim();
  String env = System.getenv("TYPESAFE_API_KEY");
  if (env != null && env.trim().length() > 0) return env.trim();
  File keyFile = new File(dataPath("typesafe_api_key.txt"));
  if (keyFile.exists()) {
    String[] file = loadStrings(keyFile);
    if (file != null && file.length > 0 && file[0].trim().length() > 0) return file[0].trim();
  }
  return null;
}

// Strip whitespace outside of strings so the request body stays small.
String minifyJson(String s) {
  StringBuilder sb = new StringBuilder();
  boolean inString = false;
  for (int i = 0; i < s.length(); i++) {
    char c = s.charAt(i);
    if (inString) {
      sb.append(c);
      if (c == '\\' && i + 1 < s.length()) sb.append(s.charAt(++i));
      else if (c == '"') inString = false;
    } else if (c == '"') {
      inString = true;
      sb.append(c);
    } else if (!Character.isWhitespace(c)) {
      sb.append(c);
    }
  }
  return sb.toString();
}

void resetArena() {
  arena.generate(OBSTACLE_COUNT, TREASURE_COUNT);
  bots.clear();
  for (int i = 0; i < BOT_COUNT; i++) addBot();
  stats = new Stats();
}

void addBot() {
  int i = bots.size();
  PVector p = arena.freeSpot(BOT_RADIUS * 2, BOT_RADIUS * 3, bots);
  bots.add(new Bot(i, PALETTE[i % PALETTE.length], p.x, p.y, random(TWO_PI), brain));
}

// ------------------------------------------------------------ loop
void draw() {
  if (!paused && brain != null) {
    for (Bot b : bots) b.update(arena, bots);
  }

  background(0);
  arena.draw();
  for (Bot b : bots) b.draw();
  drawSidebar();
  if (startupError != null) drawBanner(startupError);
  else if (paused) drawBanner("PAUSED — press SPACE");

  if (selfTest && frameCount == 90 && !bots.isEmpty() && bots.get(0).perception != null) {
    println("self-test: sample state for bot 1 →");
    println(bots.get(0).perception.toState(bots.get(0)).toJson());
  }
  if (selfTest && frameCount == 600) {
    saveFrame("selftest.png");
    println("self-test: saved selftest.png; treasure collected = " + arena.totalCollected);
    exit();
  }
}

void drawBanner(String msg) {
  noStroke();
  fill(0, 0, 0, 170);
  rect(0, ARENA_HEIGHT / 2 - 48, ARENA_WIDTH, 96);
  fill(255, 120, 120);
  textAlign(CENTER, CENTER);
  textSize(14);
  text(msg, ARENA_WIDTH / 2, ARENA_HEIGHT / 2);
}

// ------------------------------------------------------------ HUD
void drawSidebar() {
  int x0 = ARENA_WIDTH;
  noStroke();
  fill(20, 22, 32);
  rect(x0, 0, SIDEBAR_WIDTH, height);
  stroke(60, 66, 90);
  line(x0, 0, x0, height);

  int px = x0 + 18;
  int y = 26;
  textAlign(LEFT, TOP);

  fill(255);
  textSize(18);
  text("JEV BOT ARENA", px, y); y += 28;

  fill(160, 170, 200);
  textSize(11);
  text("brain   " + (brain == null ? "none" : brain.name()), px, y); y += 15;
  if (stats.lastModel.length() > 0) { text("served  " + stats.lastModel, px, y); y += 15; }
  text("arena   " + ARENA_WIDTH + "x" + ARENA_HEIGHT + " · " + arena.obstacles.size() + " obstacles · " + arena.treasures.size() + " treasure", px, y); y += 15;
  text(String.format("calls   %d ok · %d failed · avg %d ms", stats.ok, stats.failed, stats.avgLatency()), px, y); y += 15;
  text(String.format("tokens  %,d  (~ $%.4f at $0.042/Mtok)", stats.tokens, stats.tokens * 0.042 / 1e6), px, y); y += 15;
  fill(255, 215, 90);
  textSize(13);
  text("treasure collected: " + arena.totalCollected, px, y); y += 26;

  for (Bot b : bots) {
    y = drawBotCard(b, px, y);
    if (y > height - 90) break;
  }

  // controls
  fill(110, 118, 145);
  textSize(10);
  textAlign(LEFT, BOTTOM);
  text("SPACE pause · R new arena · V cone · Y rays · + / - bots · L log JSON", px, height - 14);
}

int drawBotCard(Bot b, int px, int y) {
  int cardW = SIDEBAR_WIDTH - 36;
  int cardH = 128;
  noStroke();
  fill(28, 31, 44);
  rect(px - 6, y - 6, cardW, cardH, 6);

  fill(b.col);
  ellipse(px + 6, y + 7, 12, 12);
  fill(255);
  textSize(13);
  textAlign(LEFT, TOP);
  text("Bot " + (b.id + 1), px + 18, y);
  textAlign(RIGHT, TOP);
  fill(255, 215, 90);
  text("score " + b.score, px + cardW - 14, y);
  textAlign(LEFT, TOP);
  y += 18;

  fill(170, 180, 210);
  textSize(11);
  String status;
  if (b.phase.equals(PHASE_THINKING))       status = "asking Jev";
  else if (b.phase.equals(PHASE_EXECUTING)) status = b.action + " (" + b.amount + ")";
  else if (b.phase.equals(PHASE_ERROR))     status = "error — retrying shortly";
  else                                      status = "idle";
  text("now    " + status, px, y); y += 14;
  text("last   " + (b.history.isEmpty() ? "—" : b.history.get(0).map.get("action") + " → " + b.lastResult), px, y); y += 16;

  Decision d = b.last;
  if (d != null && d.error != null) {
    fill(255, 110, 110);
    text(snipText(d.error, 46), px, y); y += 14;
    y += 40;
  } else if (d != null) {
    // probability bars for the action choice
    int barX = px + 70, barW = cardW - 70 - 50;
    for (Map.Entry<String, Float> e : d.actionProbs.entrySet()) {
      boolean chosen = e.getKey().equals(d.action);
      fill(chosen ? 255 : 150, chosen ? 255 : 160, chosen ? 255 : 190);
      textSize(10);
      text(e.getKey(), px, y);
      noStroke();
      fill(45, 50, 70);
      rect(barX, y + 2, barW, 8, 2);
      fill(chosen ? b.col : color(110, 120, 150));
      rect(barX, y + 2, barW * constrain(e.getValue(), 0, 1), 8, 2);
      fill(170, 180, 210);
      textAlign(RIGHT, TOP);
      text(String.format("%.2f", e.getValue()), px + cardW - 14, y);
      textAlign(LEFT, TOP);
      y += 12;
    }
    fill(140, 150, 180);
    textSize(10);
    text(String.format("confidence %.2f · turn %s · move %s · %d ms%s", d.actionConfidence, d.turnAmount, d.moveAmount, d.latencyMs,
      d.sampled ? " · sampled (stuck)" : ""), px, y);
    y += 14;
  } else {
    y += 54;
  }
  return y + 16;
}

String snipText(String s, int n) {
  return s.length() > n ? s.substring(0, n) + "…" : s;
}

// ------------------------------------------------------------ stats
class Stats {
  int ok = 0, failed = 0;
  long tokens = 0, latencySum = 0;
  String lastModel = "";

  void track(Decision d) {
    if (d.error != null) { failed++; return; }
    ok++;
    tokens += d.inputTokens + d.outputTokens;
    latencySum += d.latencyMs;
    if (d.model != null && d.model.length() > 0) lastModel = d.model;
  }

  int avgLatency() { return ok == 0 ? 0 : (int) (latencySum / ok); }
}

// ------------------------------------------------------------ keys
void keyPressed() {
  if (key == ' ') paused = !paused;
  else if (key == 'r' || key == 'R') resetArena();
  else if (key == 'v' || key == 'V') SHOW_VISION_CONE = !SHOW_VISION_CONE;
  else if (key == 'y' || key == 'Y') SHOW_RAYS = !SHOW_RAYS;
  else if (key == 'l' || key == 'L') { LOG_REQUEST_JSON = !LOG_REQUEST_JSON; println("request/response logging " + (LOG_REQUEST_JSON ? "on" : "off")); }
  else if (key == '+' || key == '=') { if (bots.size() < PALETTE.length * 2) addBot(); }
  else if (key == '-' || key == '_') { if (bots.size() > 1) bots.remove(bots.size() - 1); }
}
