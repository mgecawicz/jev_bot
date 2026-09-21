// ============================================================
//  CONFIG — every knob for the arena, the bots and Jev lives here.
//  Change a value and hit Run. Press R while running to regenerate
//  the arena with the current settings.
// ============================================================

// ---------- TypeSafe / Jev ----------
// Paste your key between the quotes. If it is left empty the sketch also
// checks the TYPESAFE_API_KEY environment variable, then data/typesafe_api_key.txt.
String TYPESAFE_API_KEY = "";
String JEV_MODEL        = "jev-latest";
String JEV_ENDPOINT     = "https://api.typesafe.ai/v1/systemone";
String QUESTIONS_FILE   = "questions.json";   // lives in data/ — the question set Jev answers every step
int    REQUEST_TIMEOUT_MS = 15000;
int    MAX_RETRIES        = 4;                // retries on 429 / 529 / 5xx with exponential backoff
boolean USE_JEV           = true;             // false → RandomBrain baseline, makes zero API calls
boolean LOG_DECISIONS     = true;             // one console line per decision
boolean LOG_REQUEST_JSON  = false;            // full request + response bodies (verbose; toggle with L)
// true → pick the action by sampling Jev's probability distribution instead of
// taking the most likely option. Adds exploration; useful if a bot gets stuck.
boolean SAMPLE_ACTION_FROM_PROBABILITIES = false;
// Safety net against loops: when the last STUCK_AFTER actions were all turns or
// blocked moves (no actual progress), sample the action from Jev's distribution
// for that step instead of taking the most likely option.
boolean SAMPLE_WHEN_STUCK = true;
int     STUCK_AFTER       = 4;

// ---------- Arena ----------
int   ARENA_WIDTH   = 900;
int   ARENA_HEIGHT  = 680;
int   SIDEBAR_WIDTH = 340;
int   OBSTACLE_COUNT      = 14;
float OBSTACLE_MIN_RADIUS = 18;
float OBSTACLE_MAX_RADIUS = 55;
int   TREASURE_COUNT      = 10;
float TREASURE_RADIUS     = 8;
boolean RESPAWN_TREASURE  = true;    // a new treasure appears whenever one is collected, so the hunt never ends
long  RANDOM_SEED         = 0;       // 0 → a different arena every run; any other value → reproducible layout

// ---------- Bots ----------
int   BOT_COUNT   = 2;               // + / - while running adds or removes bots
float BOT_RADIUS  = 12;
float FIELD_OF_VIEW_DEGREES = 100;   // total width of the vision cone
float VIEW_DISTANCE         = 240;   // how far the bot can see, in pixels
int   RAYS_PER_SECTOR       = 3;     // the cone is split into 5 named sectors; each gets this many rays
float MOVE_SHORT  = 30;              // pixels — "short" move
float MOVE_LONG   = 90;              // pixels — "long" move
// Turn sizes are tied to the sector width (FOV / 5) so the criteria in
// questions.json stay literally true: a slight turn brings the left/right
// sector into the centre, a sharp turn brings far_left/far_right into the centre.
float TURN_SLIGHT = FIELD_OF_VIEW_DEGREES / 5;       // degrees — one sector
float TURN_SHARP  = FIELD_OF_VIEW_DEGREES * 2 / 5;   // degrees — two sectors
float MOVE_SPEED  = 3.0;             // pixels per frame while executing a move
float TURN_SPEED  = 4.0;             // degrees per frame while executing a turn
int   HISTORY_LENGTH   = 6;          // how many past actions Jev gets to see
int   ERROR_COOLDOWN_MS = 2500;      // pause before asking again after a failed request

// ---------- Display ----------
boolean SHOW_VISION_CONE = false;    // toggle with V: shade the bot's field of view
boolean SHOW_RAYS        = false;    // toggle with Y: draw every ray, coloured by what it hits
