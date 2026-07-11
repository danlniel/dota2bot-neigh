# Bot Intelligence Roadmap

Goal: difficulty comes from **decision quality**, with gold/XP as natural as
possible. Every IQ gain here shrinks the stat bonuses the adaptive director
needs to inject, until FretBots bonuses are a light touch instead of the
main event.

## Sequence

| # | Item | Impact | Risk | Status |
|---|---|---|---|---|
| 1 | [Fog awareness](01-fog-awareness.md) | High — stops naive dives | Low | planned |
| 2 | [Team focus-fire](02-team-focus-fire.md) | High — coordinated kills | Medium | planned |
| 3 | [Farming efficiency](03-farming-efficiency.md) | High — natural GPM | Medium | planned |
| 4 | [ML dataset features](04-ml-dataset-features.md) | Compounding | Low | planned |
| 5 | [Natural economy](05-natural-economy.md) | The end goal | Low | blocked by 1–3 |

Work order: **1 → 2** (same code area, one in-game test session), then **4**
(cheap, do alongside), then **3** (own project), then **5** (gradual, driven
by game results).

## Explicitly skipped (for now)

- **Spell dodging / juking** — hero-specific logic across 127 `BotLib/hero_*.lua`
  files; high regression risk for diffuse gains. Revisit after 1–3.
- **Itemization rework** — `aba_item.lua`/`item_strategy_simple.lua` builds are
  decent; huge surface area. Not the bottleneck.
- **Full RL / neural policy** — confirmed unrealistic for this project
  (OpenAI Five needed a dedicated Valve API + massive infra). The parameter-level
  ML loop (`ml/`) is the practical path and it's already running.

## How each item gets verified

Every change ships behind a `Customize` toggle with the old behavior as
fallback, passes `luac -p`, and is validated in a real lobby:
1. Console has no new errors and no `[MLBridge]/[MLDirector] disabled` lines.
2. The targeted behavior is visibly different (each item's doc lists what to
   watch for).
3. A few games' `ml/data` snapshots confirm the adaptive director needed
   smaller/less frequent difficulty boosts than before the change — that's the
   measurable definition of "smarter".
