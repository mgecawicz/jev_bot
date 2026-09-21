// ============================================================
//  ARENA — walls, obstacles and treasure.
// ============================================================

class Obstacle {
  float x, y, r;
  Obstacle(float x, float y, float r) { this.x = x; this.y = y; this.r = r; }
}

class Treasure {
  float x, y;
  Treasure(float x, float y) { this.x = x; this.y = y; }
}

class Arena {
  int w, h;
  ArrayList<Obstacle> obstacles = new ArrayList<Obstacle>();
  ArrayList<Treasure> treasures = new ArrayList<Treasure>();
  int totalCollected = 0;

  Arena(int w, int h) { this.w = w; this.h = h; }

  void generate(int obstacleCount, int treasureCount) {
    obstacles.clear();
    treasures.clear();
    totalCollected = 0;

    // Obstacles: keep a corridor at least three bot-widths wide between any two
    // so the arena stays traversable however dense it gets.
    float gap = BOT_RADIUS * 3;
    int attempts = 0;
    while (obstacles.size() < obstacleCount && attempts < obstacleCount * 200) {
      attempts++;
      float r = random(OBSTACLE_MIN_RADIUS, OBSTACLE_MAX_RADIUS);
      float x = random(r + gap, w - r - gap);
      float y = random(r + gap, h - r - gap);
      boolean ok = true;
      for (Obstacle o : obstacles) {
        if (dist(x, y, o.x, o.y) < r + o.r + gap) { ok = false; break; }
      }
      if (ok) obstacles.add(new Obstacle(x, y, r));
    }
    if (obstacles.size() < obstacleCount) {
      println("Arena: only fitted " + obstacles.size() + " of " + obstacleCount + " obstacles — shrink them or enlarge the arena.");
    }

    for (int i = 0; i < treasureCount; i++) spawnTreasure();
  }

  Treasure spawnTreasure() {
    PVector p = freeSpot(TREASURE_RADIUS + BOT_RADIUS, TREASURE_RADIUS + BOT_RADIUS * 2, null);
    Treasure t = new Treasure(p.x, p.y);
    treasures.add(t);
    return t;
  }

  // A random point at least `clearance` from every obstacle edge, `wallMargin`
  // from the walls, and (if bots are given) not on top of another bot.
  PVector freeSpot(float clearance, float wallMargin, ArrayList<Bot> bots) {
    for (int attempt = 0; attempt < 2000; attempt++) {
      float x = random(wallMargin, w - wallMargin);
      float y = random(wallMargin, h - wallMargin);
      if (pointNearObstacle(x, y, clearance)) continue;
      boolean nearBot = false;
      if (bots != null) {
        for (Bot b : bots) if (dist(x, y, b.x, b.y) < BOT_RADIUS * 4) { nearBot = true; break; }
      }
      if (nearBot) continue;
      return new PVector(x, y);
    }
    // Arena is packed solid; fall back to the centre rather than looping forever.
    return new PVector(w / 2, h / 2);
  }

  boolean pointNearObstacle(float x, float y, float clearance) {
    for (Obstacle o : obstacles) if (dist(x, y, o.x, o.y) < o.r + clearance) return true;
    return false;
  }

  // Would a bot-sized circle at (x,y) overlap an obstacle? Returns it, or null.
  Obstacle obstacleHit(float x, float y, float radius) {
    for (Obstacle o : obstacles) if (dist(x, y, o.x, o.y) < o.r + radius) return o;
    return null;
  }

  boolean wallHit(float x, float y, float radius) {
    return x - radius < 0 || y - radius < 0 || x + radius > w || y + radius > h;
  }

  Treasure treasureHit(float x, float y, float radius) {
    for (Treasure t : treasures) if (dist(x, y, t.x, t.y) < TREASURE_RADIUS + radius) return t;
    return null;
  }

  void collect(Treasure t) {
    treasures.remove(t);
    totalCollected++;
    if (RESPAWN_TREASURE) spawnTreasure();
  }

  // Distance along a ray from inside the arena to the first wall, with the
  // walls pulled in by `inset` (the bot's radius) so the result is how far the
  // bot's centre can travel before its body touches the wall.
  float rayToWalls(float ox, float oy, float dx, float dy, float inset) {
    float best = Float.MAX_VALUE;
    if (dx > 0) best = min(best, (w - inset - ox) / dx);
    if (dx < 0) best = min(best, (inset - ox) / dx);
    if (dy > 0) best = min(best, (h - inset - oy) / dy);
    if (dy < 0) best = min(best, (inset - oy) / dy);
    return max(0, best);
  }

  // Does the segment a→b pass through any obstacle? Used for treasure line of sight.
  boolean segmentBlocked(float ax, float ay, float bx, float by) {
    float dx = bx - ax, dy = by - ay;
    float len2 = dx * dx + dy * dy;
    for (Obstacle o : obstacles) {
      float t = len2 == 0 ? 0 : ((o.x - ax) * dx + (o.y - ay) * dy) / len2;
      t = constrain(t, 0, 1);
      float px = ax + dx * t, py = ay + dy * t;
      if (dist(px, py, o.x, o.y) < o.r) return true;
    }
    return false;
  }

  void draw() {
    noStroke();
    fill(0);
    rect(0, 0, w, h);

    // obstacles
    fill(78, 86, 108);
    for (Obstacle o : obstacles) ellipse(o.x, o.y, o.r * 2, o.r * 2);

    // treasure: a plain diamond
    fill(255, 205, 70);
    for (Treasure t : treasures) {
      float r = TREASURE_RADIUS;
      quad(t.x, t.y - r, t.x + r, t.y, t.x, t.y + r, t.x - r, t.y);
    }

    // walls
    noFill();
    stroke(120, 130, 160);
    strokeWeight(2);
    rect(1, 1, w - 2, h - 2);
  }
}
