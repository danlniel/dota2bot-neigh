# ML Integration

Connects the Lua bots to a local model server so difficulty comes from **decision
quality** instead of stat cranking, and every game collects training data.

## Architecture

```
┌──────────────────────────── Dota 2 (local lobby) ────────────────────────────┐
│                                                                              │
│  bots VM (bot scripts)                 FretBots VM (addon scripts)           │
│  FunLib/ml_bridge.lua                  FretBots/MLDirector.lua               │
│  every 10s: team snapshot ──┐   ┌── every 20s: full hero stats               │
│  applies FightIQ overrides ◄┤   ├─► applies difficulty directive             │
└─────────────────────────────┼───┼──────────────────────────────────────────┘
                              ▼   ▼
                    ml/server.py  (http://127.0.0.1:5544)
                    ├── /policy    → FightIQ params (commit margin, …)
                    ├── /director  → difficulty nudges (flow-band rubber-band)
                    └── ml/data/session-*.jsonl   (dataset, every request)
                              ▲
                    ml/train.py — offline fit → ml/model.json → server loads it
```

Both Lua clients are **fail-safe**: if the server isn't running (or
`CreateHTTPRequest` is unavailable in a VM), they disable themselves after a few
attempts and the static `Customize` values apply. You can always play without
the server.

## Usage

1. Start the server before creating the lobby:
   ```
   python3 ml/server.py
   ```
2. Play games as usual. Snapshots accumulate in `ml/data/`.
3. After a handful of games, train:
   ```
   python3 ml/train.py
   ```
4. Restart the server — it picks up `ml/model.json` automatically.

Knobs live in `bots/Customize/general.lua` under `Customize.ML`
(enable/disable, server URL, API key, intervals, whether the server may change
difficulty mid-game).

## Shared deployment (Docker, e.g. OrangePi)

```
cd ml
docker compose up -d --build
```

Runs on arm64 and amd64. The dataset and trained model persist in `ml/data/`
via the volume. Set `ML_API_KEY` in `docker-compose.yml` if the server is
reachable beyond your LAN, and give players the same value for
`Customize.ML.Api_Key`. Point clients at it via
`Customize.ML.Server = 'http://<your-server-ip>:5544'`.

To retrain on the server: `docker exec dota2bot-ml python3 train.py`
(then `docker restart dota2bot-ml` to load the new model).

Note: requests carry no player identity — the dataset is anonymous game
snapshots. If many people share one server, all their games feed one model.

## What the model controls today

- **`/policy` → FightIQ**: currently `Commit_Margin` — how much power advantage
  bots demand before committing to fights (see `Customize.FightIQ`). The server
  can also override `Ult_Ready_Bonus`, `Ult_Down_Penalty`,
  `Disabled_Power_Scale` — any numeric FightIQ key is applied live.
- **`/director` → difficulty**: keeps the human-vs-bot kill gap inside a flow
  band by nudging FretBots difficulty one step at a time.

## Why this design (research summary)

- The bot-scripting VM has no IO, no C libraries, no threads — in-VM training is
  impossible; async HTTP to an external process is the community-proven bridge
  (d2ai, Nostrademous' Dota2-WebAI both did this from bot scripts).
- Valve's own difficulty tiers are mostly *reaction-time handicaps*, not stat
  boosts — decision quality is the legitimate difficulty lever.
- OpenAI Five used a dedicated Valve API + massive RL infra; not reproducible.
  The realistic path for a solo dev is exactly this: parameter-level policy
  control + offline learning from collected games, upgradeable to per-decision
  models later (the `/policy` interface doesn't change).

## Roadmap ideas

- Richer snapshot features (networth, hero names, tower states) → better models.
- Per-hero aggression multipliers in `/policy` responses.
- Export trained weights as a Lua table for pure-Lua in-VM inference
  (no server needed at play time) — a tiny MLP forward pass is cheap in Lua.
- Imitation targets mined from parsed human replays (OpenDota/Clarity).
