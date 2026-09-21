// ============================================================
//  BOT — a little robot that can drive forward/backward and turn.
//
//  Loop, forever:   idle → perceive → ask the brain → execute → idle …
//  The brain answers on a background thread and drops a Decision into
//  `pending`; the main thread picks it up on the next frame.
// ============================================================

final String PHASE_IDLE      = "idle";
final String PHASE_THINKING  = "thinking";
final String PHASE_EXECUTING = "executing";
final String PHASE_ERROR     = "error";

class Bot {
  int id;
  color col;
  float x, y;
  float heading;              // radians; 0 = facing right, turn_left decreases it (counter-clockwise on screen)
  int score = 0;

  String phase = PHASE_IDLE;
  Brain brain;

  // current action being executed
  String action = "";         // forward | backward | turn_left | turn_right
  String amount = "";         // short | long | slight | sharp
  float remaining = 0;        // pixels or radians left to go
  int dir = 1;

  // what Jev sees / said
  Perception perception;
  ArrayList<JsonOut> history = new ArrayList<JsonOut>();   // newest first
  volatile Decision pending;
  Decision last;
  String lastResult = "";
  long thinkStartedAt, errorUntil;
  int decisions = 0;

  Bot(int id, color col, float x, float y, float heading, Brain brain) {
    this.id = id; this.col = col; this.x = x; this.y = y; this.heading = heading; this.brain = brain;
  }

  // ---------------------------------------------------------- update
  void update(Arena arena, ArrayList<Bot> bots) {
    if (phase.equals(PHASE_IDLE)) {
      startThinking(arena, bots);
    } else if (phase.equals(PHASE_THINKING)) {
      Decision d = pending;
      if (d != null) {
        pending = null;
        d.latencyMs = (int) (millis() - thinkStartedAt);
        receive(d);
      }
    } else if (phase.equals(PHASE_EXECUTING)) {
      step(arena, bots);
    } else if (phase.equals(PHASE_ERROR)) {
      if (millis() > errorUntil) phase = PHASE_IDLE;
    }
  }

  void startThinking(Arena arena, ArrayList<Bot> bots) {
    perception = new Perception(this, arena, bots);
    JsonOut state = perception.toState(this);
    phase = PHASE_THINKING;
    thinkStartedAt = millis();
    brain.decide(this, state);          // sets `pending` when done, possibly from another thread
  }

  void receive(Decision d) {
    last = d;
    decisions++;
    stats.track(d);
    if (d.error != null) {
      println("[bot " + id + "] brain error: " + d.error);
      phase = PHASE_ERROR;
      errorUntil = millis() + ERROR_COOLDOWN_MS;
      return;
    }
    action = d.action;
    if (action.equals("turn_left") || action.equals("turn_right")) {
      amount = d.turnAmount;
      remaining = radians(amount.equals("sharp") ? TURN_SHARP : TURN_SLIGHT);
      dir = action.equals("turn_left") ? -1 : 1;
    } else {
      amount = d.moveAmount;
      remaining = amount.equals("long") ? MOVE_LONG : MOVE_SHORT;
      dir = action.equals("forward") ? 1 : -1;
    }
    phase = PHASE_EXECUTING;
    if (LOG_DECISIONS) {
      println(String.format("[bot %d] %-10s %-6s conf=%.2f  %s  %dms  tokens=%d%s",
        id, action, amount, d.actionConfidence, d.probsSummary(), d.latencyMs, d.inputTokens + d.outputTokens,
        d.sampled ? "  [sampled: stuck]" : ""));
    }
  }

  // Move or turn a little each frame until the action is done or something stops it.
  void step(Arena arena, ArrayList<Bot> bots) {
    if (action.startsWith("turn")) {
      float s = min(radians(TURN_SPEED), remaining);
      heading = normalizeAngle(heading + s * dir);
      remaining -= s;
      if (remaining <= 0.0001) finish("turned");
      return;
    }

    float s = min(MOVE_SPEED, remaining);
    float nx = x + cos(heading) * s * dir;
    float ny = y + sin(heading) * s * dir;

    if (arena.wallHit(nx, ny, BOT_RADIUS))               { finish("blocked_by_wall"); return; }
    if (arena.obstacleHit(nx, ny, BOT_RADIUS) != null)   { finish("blocked_by_obstacle"); return; }
    for (Bot other : bots) {
      if (other != this && dist(nx, ny, other.x, other.y) < BOT_RADIUS * 2) { finish("blocked_by_another_bot"); return; }
    }

    x = nx; y = ny;
    remaining -= s;

    Treasure t = arena.treasureHit(x, y, BOT_RADIUS);
    if (t != null) {
      arena.collect(t);
      score++;
      finish("collected_treasure");     // stop here so the bot gets immediate feedback
      return;
    }
    if (remaining <= 0.0001) finish("moved");
  }

  // ---- repetition detection: done in code, handed to Jev as a literal fact ----
  String pastAction(int i) {            // "turn_left_slight" → "turn_left"
    String full = (String) history.get(i).map.get("action");
    return full.substring(0, full.lastIndexOf('_'));
  }
  String pastResult(int i) { return (String) history.get(i).map.get("result"); }

  String repetition() {
    if (history.size() >= 4) {
      boolean allTurns = true, allMoves = true, sawForward = false, sawBackward = false;
      for (int i = 0; i < 4; i++) {
        String a = pastAction(i);
        if (!a.startsWith("turn")) allTurns = false;
        if (a.equals("forward")) sawForward = true;
        else if (a.equals("backward")) sawBackward = true;
        else allMoves = false;
      }
      if (allTurns) return "the last four actions were all turns, so the bot has not moved";
      if (allMoves && sawForward && sawBackward) return "the last four actions were only forward and backward moves, so the bot is bouncing back and forth";
    }
    if (history.size() >= 3 && pastAction(0).equals("backward") && pastAction(1).equals("backward") && pastAction(2).equals("backward")) {
      return "the bot has reversed three times in a row and cannot see where it is going";
    }
    if (history.size() >= 2 && pastAction(0).equals("forward") && pastResult(0).startsWith("blocked")
        && pastAction(1).equals("forward") && pastResult(1).startsWith("blocked")) {
      return "the last two forward moves were both blocked";
    }
    return "none";
  }

  // True when the bot is looping, or the last STUCK_AFTER actions made no progress.
  boolean isStuck() {
    if (!repetition().equals("none")) return true;
    if (history.size() < STUCK_AFTER) return false;
    for (int i = 0; i < STUCK_AFTER; i++) {
      String r = pastResult(i);
      if (r.equals("moved") || r.equals("collected_treasure")) return false;
    }
    return true;
  }

  void finish(String result) {
    lastResult = result;
    history.add(0, new JsonOut().put("action", action + "_" + amount).put("result", result));
    while (history.size() > HISTORY_LENGTH) history.remove(history.size() - 1);
    phase = PHASE_IDLE;
  }

  // ---------------------------------------------------------- draw
  void draw() {
    drawVision();

    // a small triangle pointing along the heading, with a direction line ahead of it
    pushMatrix();
    translate(x, y);
    rotate(heading);
    float r = BOT_RADIUS;
    stroke(col);
    strokeWeight(1.5);
    line(r, 0, r * 2.4, 0);
    noStroke();
    fill(col);
    triangle(r, 0, -r * 0.8, -r * 0.7, -r * 0.8, r * 0.7);
    popMatrix();

    if (phase.equals(PHASE_ERROR)) {
      noFill();
      stroke(255, 80, 80);
      strokeWeight(2);
      ellipse(x, y, BOT_RADIUS * 2.8, BOT_RADIUS * 2.8);
    }

    fill(255);
    textAlign(CENTER, BOTTOM);
    textSize(11);
    text("B" + (id + 1) + "  " + score, x, y - BOT_RADIUS - 5);
  }

  void drawVision() {
    if (SHOW_VISION_CONE) {
      float fov = radians(FIELD_OF_VIEW_DEGREES);
      noStroke();
      fill(col, 14);
      arc(x, y, VIEW_DISTANCE * 2, VIEW_DISTANCE * 2, heading - fov / 2, heading + fov / 2, PIE);
    }
    if (perception == null) return;

    if (SHOW_RAYS) {
      // a ray ends where the bot's centre would have to stop, one bot-radius short of the surface
      strokeWeight(1);
      for (RayResult r : perception.rays) {
        if (r.sees.equals(SEES_CLEAR))         stroke(col, 40);
        else if (r.sees.equals(SEES_WALL))     stroke(120, 140, 200, 140);
        else if (r.sees.equals(SEES_OBSTACLE)) stroke(255, 110, 90, 160);
        else                                   stroke(255, 255, 255, 160);
        line(x, y, x + cos(r.angle) * r.t, y + sin(r.angle) * r.t);
      }
    }

    // the treasure the bot is going for
    if (perception.target != null) {
      stroke(255, 205, 70, 180);
      strokeWeight(1.5);
      line(x, y, perception.target.treasure.x, perception.target.treasure.y);
    }
  }
}
