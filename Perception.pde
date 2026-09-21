// ============================================================
//  PERCEPTION — turns arena geometry into the semantic state Jev reads.
//
//  Jev is a System One model: strong on common-sense judgement, weak on raw
//  numbers. So nothing numeric reaches it. The vision cone is split into five
//  named sectors, every distance is bucketed relative to the bot's own move
//  lengths, and the legend below tells Jev exactly what each word means.
// ============================================================

final String[] SECTOR_NAMES = { "far_left", "left", "center", "right", "far_right" };
final int SECTOR_COUNT = 5;

// Things a ray can report
final String SEES_CLEAR    = "clear";
final String SEES_WALL     = "wall";
final String SEES_OBSTACLE = "obstacle";
final String SEES_BOT      = "another_bot";

// Distance buckets are defined by what the bot can physically do, so the
// legend and the criteria in questions.json can be stated literally.
String distanceBucket(float edgeDistance) {
  if (edgeDistance < MOVE_SHORT) return "very_close";
  if (edgeDistance < MOVE_LONG)  return "close";
  return "far";
}

JsonOut legendJson() {
  JsonOut distance = new JsonOut()
    .put("very_close", "Any forward move, even a short one, would collide with it. For treasure in the center sector: a short forward move collects it.")
    .put("close",      "A short forward move fits in front of it; a long forward move would collide with it.")
    .put("far",        "Both a short and a long forward move fit in front of it.");
  return new JsonOut()
    .put("view", "The bot looks forward through a cone split into five sectors, listed from the bot's left to its right: far_left, left, center, right, far_right. center is straight ahead. The bot cannot see behind itself. A sector that shows clear has nothing within sight range.")
    .put("target_treasure", "The one treasure the bot should go for right now: the closest one it can see, with the sector it is in, how far away it is, and whether the straight path to it is clear. path clear means nothing in that sector is nearer than the treasure, so the bot can turn to face it and drive straight at it. path blocked means a wall, obstacle or bot is in the way; the bot should not steer toward it yet but explore around the obstruction until the path is clear. none means no treasure is in sight.")
    .put("more_open_side", "Computed by code: which way to turn when a turn is needed for any reason other than facing the target treasure. Normally the half of the view with more room, left (far_left and left) or right (right and far_right). Once the bot has started turning one way with no treasure in sight it keeps pointing the same way, so the bot completes the turn instead of swinging back.")
    .put("repetition", "A fact computed by the bot's own code about its recent actions. Anything other than none means the bot is stuck in a loop and must break it.")
    .put("distance", distance);
}

// One ray's result, kept for drawing as well as for the state.
class RayResult {
  float angle;      // absolute, radians
  float t;          // distance from bot centre to the hit (or VIEW_DISTANCE)
  String sees;      // SEES_*
  int sector;
}

class SeenTreasure {
  Treasure treasure;
  float edgeDistance;
  int sector;
}

class Perception {
  ArrayList<RayResult> rays = new ArrayList<RayResult>();
  ArrayList<SeenTreasure> treasures = new ArrayList<SeenTreasure>();
  SeenTreasure target;       // the one treasure Jev is told about
  // per sector: nearest hit
  String[] sectorSees = new String[SECTOR_COUNT];
  float[] sectorEdgeDistance = new float[SECTOR_COUNT];

  Perception(Bot bot, Arena arena, ArrayList<Bot> bots) {
    float fov = radians(FIELD_OF_VIEW_DEGREES);
    float half = fov / 2;
    float sectorWidth = fov / SECTOR_COUNT;
    float rayStep = sectorWidth / RAYS_PER_SECTOR;

    for (int s = 0; s < SECTOR_COUNT; s++) {
      sectorSees[s] = SEES_CLEAR;
      sectorEdgeDistance[s] = Float.MAX_VALUE;
      for (int i = 0; i < RAYS_PER_SECTOR; i++) {
        float rel = -half + (s * RAYS_PER_SECTOR + i + 0.5) * rayStep;
        RayResult r = castRay(bot, bot.heading + rel, arena, bots);
        r.sector = s;
        rays.add(r);
        if (!r.sees.equals(SEES_CLEAR) && r.t < sectorEdgeDistance[s]) {
          sectorEdgeDistance[s] = r.t;
          sectorSees[s] = r.sees;
        }
      }
    }

    // Treasure: inside the cone, within range, and not hidden behind an obstacle.
    for (Treasure t : arena.treasures) {
      float dx = t.x - bot.x, dy = t.y - bot.y;
      float dist = sqrt(dx * dx + dy * dy);
      if (dist - TREASURE_RADIUS > VIEW_DISTANCE) continue;
      float rel = normalizeAngle(atan2(dy, dx) - bot.heading);
      if (abs(rel) > half) continue;
      if (arena.segmentBlocked(bot.x, bot.y, t.x, t.y)) continue;
      SeenTreasure st = new SeenTreasure();
      st.treasure = t;
      st.edgeDistance = max(0, dist - BOT_RADIUS - TREASURE_RADIUS);
      st.sector = constrain(floor((rel + half) / sectorWidth), 0, SECTOR_COUNT - 1);
      treasures.add(st);
    }
    // Pick one target in code so the questions never have to disambiguate
    // between several treasures. Cost = distance plus one short move per
    // sector the bot would have to turn through.
    treasures.sort(new java.util.Comparator<SeenTreasure>() {
      public int compare(SeenTreasure a, SeenTreasure b) { return Float.compare(cost(a), cost(b)); }
    });
    target = treasures.isEmpty() ? null : treasures.get(0);
  }

  float cost(SeenTreasure st) {
    float c = st.edgeDistance + abs(st.sector - SECTOR_COUNT / 2) * MOVE_SHORT;
    if (!pathClear(st)) c += MOVE_LONG;
    return c;
  }

  // Which half of the cone has more room: sum of free travel distance over
  // the two left sectors vs the two right sectors. Ties go left so Jev never
  // has to break one itself.
  //
  // With one exception: if the bot's last action was a turn made while it had
  // no reachable target (none in sight, or path blocked), keep the same
  // direction. In a pocket between an obstacle and a wall the geometrically
  // "open" side flips after every turn, and the bot would swing left-right-left forever.
  String moreOpenSide(Bot bot) {
    boolean noReachableTarget = target == null || !pathClear(target);
    if (noReachableTarget && !bot.history.isEmpty()) {
      String last = bot.pastAction(0);
      if (last.equals("turn_left"))  return "left";
      if (last.equals("turn_right")) return "right";
    }
    float left = 0, right = 0;
    for (RayResult r : rays) {
      if (r.sector < SECTOR_COUNT / 2) left += r.t;
      else if (r.sector > SECTOR_COUNT / 2) right += r.t;
    }
    return right > left ? "right" : "left";
  }

  // Nothing in the treasure's sector is nearer than the treasure itself.
  boolean pathClear(SeenTreasure st) {
    return st.edgeDistance < sectorEdgeDistance[st.sector];
  }

  // Every shape is inflated by the bot's own radius, so `t` is exactly how far
  // the bot can travel in this direction before its body touches something.
  // (A thin ray from the centre would miss obstacles that graze the bot's flank.)
  RayResult castRay(Bot bot, float angle, Arena arena, ArrayList<Bot> bots) {
    RayResult r = new RayResult();
    r.angle = angle;
    r.t = VIEW_DISTANCE;
    r.sees = SEES_CLEAR;
    float dx = cos(angle), dy = sin(angle);

    // walls
    float tw = arena.rayToWalls(bot.x, bot.y, dx, dy, BOT_RADIUS);
    if (tw < r.t) { r.t = tw; r.sees = SEES_WALL; }
    // obstacles
    for (Obstacle o : arena.obstacles) {
      float t = rayToCircle(bot.x, bot.y, dx, dy, o.x, o.y, o.r + BOT_RADIUS);
      if (t >= 0 && t < r.t) { r.t = t; r.sees = SEES_OBSTACLE; }
    }
    // other bots
    for (Bot other : bots) {
      if (other == bot) continue;
      float t = rayToCircle(bot.x, bot.y, dx, dy, other.x, other.y, BOT_RADIUS * 2);
      if (t >= 0 && t < r.t) { r.t = t; r.sees = SEES_BOT; }
    }
    return r;
  }

  // ---- the state Jev sees ----
  JsonOut toState(Bot bot) {
    JsonOut view = new JsonOut();
    for (int s = 0; s < SECTOR_COUNT; s++) {
      JsonOut sector = new JsonOut().put("sees", sectorSees[s]);
      if (!sectorSees[s].equals(SEES_CLEAR)) sector.put("distance", distanceBucket(sectorEdgeDistance[s]));
      view.put(SECTOR_NAMES[s], sector);
    }

    Object targetField = target == null ? "none" : new JsonOut()
      .put("sector", SECTOR_NAMES[target.sector])
      .put("distance", distanceBucket(target.edgeDistance))
      .put("path", pathClear(target) ? "clear" : "blocked");

    JsonOut state = new JsonOut()
      .put("legend", legendJson())
      .put("view", view)
      .put("target_treasure", targetField)
      .put("more_open_side", moreOpenSide(bot))
      .put("repetition", bot.repetition())
      .put("last_action", bot.history.isEmpty() ? "none" : bot.history.get(0))
      .put("recent_actions_newest_first", new ArrayList<JsonOut>(bot.history));
    return state;
  }
}

// ---- geometry helpers ----

float normalizeAngle(float a) {
  while (a > PI)  a -= TWO_PI;
  while (a < -PI) a += TWO_PI;
  return a;
}

// Distance along the ray (ox,oy)+(dx,dy)*t to the first hit with a circle, or -1.
float rayToCircle(float ox, float oy, float dx, float dy, float cx, float cy, float r) {
  float lx = cx - ox, ly = cy - oy;
  float tca = lx * dx + ly * dy;
  if (tca < 0) return -1;
  float d2 = lx * lx + ly * ly - tca * tca;
  float r2 = r * r;
  if (d2 > r2) return -1;
  float thc = sqrt(r2 - d2);
  float t0 = tca - thc;
  return t0 < 0 ? 0 : t0;
}
