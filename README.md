# Jev Bot Arena

A Processing sketch where little robots hunt treasure in an arena full of
obstacles. Each bot can drive forward or backward and turn, and it sees a cone
in front of it. Its brain is **Jev**, TypeSafe AI's System One model
(https://docs.typesafe.ai): every step the bot sends what it sees plus its
recent actions as `state`, Jev answers a small set of typed questions, and
the answers drive the bot. This loops forever. The goal is to collect as much
treasure as possible.

## Run it

1. Open `jev_bot.pde` in Processing 4.
2. Put your TypeSafe API key in **one** of these places:
   - `Config.pde` → `TYPESAFE_API_KEY = "..."`
   - the `TYPESAFE_API_KEY` environment variable
   - a file `data/typesafe_api_key.txt` (git-ignored)
3. Hit Run.

Keys while running:

| key | action |
| --- | --- |
| `SPACE` | pause / resume |
| `R` | regenerate the arena with the current config |
| `V` | toggle vision cones |
| `Y` | toggle rays (coloured by what they hit) |
| `+` / `-` | add / remove a bot |
| `L` | toggle logging of the full request/response JSON to the console |

Without a key the arena still draws but the bots stay idle and a banner tells
you what to do. To check the arena without spending any tokens, set
`USE_JEV = false` (a random-action baseline) or run the self-test from a
terminal, which uses the random brain, saves `selftest.png` and exits:

```
/Applications/Processing.app/Contents/MacOS/Processing cli --sketch="$PWD" --output=/tmp/jev_bot_build --force --run selftest
```

## Make it yours

Everything tunable is in `Config.pde`: arena size, obstacle count and size,
treasure count and respawn, number of bots, field of view, view distance,
move and turn lengths, history length, model name, retries, logging.

The questions Jev answers are in `data/questions.json`. Edit them freely; the
file is sent to the API verbatim (minified), so what you write is exactly what
Jev reads. The sketch expects three Choice questions to exist:

| id | options | used when |
| --- | --- | --- |
| `action` | `forward` `backward` `turn_left` `turn_right` | always |
| `turn_amount` | `slight` `sharp` | the action is a turn |
| `move_amount` | `short` `long` | the action is forward / backward |

`turn_amount` and `move_amount` are *speculative*: they are asked in the same
request as `action` (all questions run in parallel) and the code only reads
the one that applies. That is TypeSafe's fan-out pattern — one round trip per
decision.

## What Jev sees

Jev is strong at common-sense judgement and weak at raw numbers, counting and
multi-hop comparisons, so `Perception.pde` does all of that in code and hands
Jev words plus a few pre-computed facts:

Every request is `{ "state": …, "model": "jev-latest", "questions": … }`,
with `questions` being `data/questions.json` verbatim. Here is a real `state`,
captured on a bot's very first step — it spawned facing a wall, with an
obstacle off to its right and no treasure in sight:

```json
{
  "legend": {
    "view": "The bot looks forward through a cone split into five sectors, listed from the bot's left to its right: far_left, left, center, right, far_right. center is straight ahead. The bot cannot see behind itself. A sector that shows clear has nothing within sight range.",
    "target_treasure": "The one treasure the bot should go for right now: the closest one it can see, with the sector it is in, how far away it is, and whether the straight path to it is clear. path clear means nothing in that sector is nearer than the treasure, so the bot can turn to face it and drive straight at it. path blocked means a wall, obstacle or bot is in the way; the bot should not steer toward it yet but explore around the obstruction until the path is clear. none means no treasure is in sight.",
    "more_open_side": "Computed by code: which way to turn when a turn is needed for any reason other than facing the target treasure. Normally the half of the view with more room, left (far_left and left) or right (right and far_right). Once the bot has started turning one way with no treasure in sight it keeps pointing the same way, so the bot completes the turn instead of swinging back.",
    "repetition": "A fact computed by the bot's own code about its recent actions. Anything other than none means the bot is stuck in a loop and must break it.",
    "distance": {
      "very_close": "Any forward move, even a short one, would collide with it. For treasure in the center sector: a short forward move collects it.",
      "close": "A short forward move fits in front of it; a long forward move would collide with it.",
      "far": "Both a short and a long forward move fit in front of it."
    }
  },
  "view": {
    "far_left": {
      "sees": "wall",
      "distance": "close"
    },
    "left": {
      "sees": "wall",
      "distance": "close"
    },
    "center": {
      "sees": "wall",
      "distance": "close"
    },
    "right": {
      "sees": "wall",
      "distance": "far"
    },
    "far_right": {
      "sees": "obstacle",
      "distance": "close"
    }
  },
  "target_treasure": "none",
  "more_open_side": "right",
  "repetition": "none",
  "last_action": "none",
  "recent_actions_newest_first": []
}
```

Jev's answer to this state (replayed to check): `turn_right` with probability
1.0, `sharp` at 0.96 — no target, `view.center` is `close`, so priority 6
applies and `more_open_side` says right.

- **`view`** — the cone is split into five named sectors; each reports the
  nearest thing its rays hit (`clear`, `wall`, `obstacle`, `another_bot`).
  Rays are cast against shapes inflated by the bot's radius, so a hit distance
  is exactly how far the bot can *drive* that way before touching something.
- **distance words** are defined by what the bot can do: `very_close` = any
  forward move collides, `close` = a short move fits but a long one doesn't,
  `far` = both fit. The legend spells this out so `questions.json` can state
  conditions literally.
- **`target_treasure`** — code picks *one* treasure (closest reachable; must be
  inside the cone, in range, not hidden behind an obstacle). `path` says
  whether anything in its sector is nearer than the treasure. A blocked target
  is not steered toward; the bot explores until the path clears.
- **`more_open_side`** — which half of the view has more room. Once the bot has
  started turning with no reachable target it keeps pointing the same way, so
  a turn is completed instead of swinging back.
- **`repetition`** — a loop detector: all turns for four actions, bouncing
  forward/backward, three reverses in a row, or forward blocked twice. The
  questions tell Jev how to break each one.
- **history** — the last `HISTORY_LENGTH` actions with results (`moved`,
  `turned`, `blocked_by_wall`, `blocked_by_obstacle`, `blocked_by_another_bot`,
  `collected_treasure`), newest first, plus `last_action` on its own.

What comes back, per bot, every step — a real response from `jev-1.13.0`:

```json
{
  "model": "jev-1.13.0",
  "answers": {
    "action": {
      "type": "choice",
      "choice": "forward",
      "probabilities": { "forward": 0.55, "backward": 0, "turn_left": 0.45, "turn_right": 0 },
      "confidence": 0.4
    },
    "turn_amount": {
      "type": "choice",
      "choice": "slight",
      "probabilities": { "slight": 0.99, "sharp": 0.01 },
      "confidence": 0.98
    },
    "move_amount": {
      "type": "choice",
      "choice": "long",
      "probabilities": { "short": 0.01, "long": 0.99 },
      "confidence": 0.99
    }
  },
  "usage": { "input_tokens": 2591, "output_tokens": 108 }
}
```

Here the bot drives `forward` `long`, but note the `action` confidence of 0.4:
Jev was nearly split between going forward and turning left (0.55 vs 0.45),
while it was certain about the two speculative amounts. The code takes the
`choice` as given; the distribution and confidence are there for the HUD and
for the stuck-sampling safety net.

The sidebar shows the full `action` distribution and confidence for each bot.
Safety nets in `Config.pde`: `SAMPLE_WHEN_STUCK` samples the action from that
distribution (instead of taking the argmax) whenever the bot is looping or has
made no progress for `STUCK_AFTER` actions; `SAMPLE_ACTION_FROM_PROBABILITIES`
does it on every step.

## Debugging a loop

Press `L` to log every request and response. When a bot loops, copy one
logged `→` body into a file and replay it:

```
curl -s -X POST https://api.typesafe.ai/v1/systemone \
  -H "Authorization: Bearer $TYPESAFE_API_KEY" -H "Content-Type: application/json" \
  --data @state.json | python3 -m json.tool
```

Then read the state the way Jev does — literally — and ask which criterion
matched. Every loop found so far was a state-design problem, not a model one:
two treasures both matching "treasure in sector X"; two different
`very_close` words in one state (the target's and the view's); asking Jev to
count open sectors; rules that fought over a blocked target. The fix each time
was to compute the fact in code and give it a name.

## Files

| file | what |
| --- | --- |
| `jev_bot.pde` | setup, main loop, HUD, keyboard, API-key lookup |
| `Config.pde` | every tunable value |
| `Arena.pde` | walls, obstacles, treasure, collision geometry |
| `Bot.pde` | the robot: idle → perceive → ask → execute loop, movement, history |
| `Perception.pde` | ray casting and the semantic state Jev reads |
| `Brain.pde` | `Brain` interface, `JevBrain` (async, thread pool), `RandomBrain` baseline |
| `JevClient.pde` | the HTTP call to `POST /v1/systemone`, retries, answer parsing |
| `JsonOut.pde` | tiny ordered JSON writer (Processing's `JSONObject` scrambles key order) |
| `data/questions.json` | the question set |

## Cost

A request is roughly 1.5k tokens. At Jev's list price ($0.042 per million
input tokens; output is free) that is about $0.00007 per decision — two bots
running for an hour is a few cents. The sidebar keeps a running total.
