# 4. ML Dataset Features — give the model something to learn from

## Problem

The `/policy` snapshot (`bots/FunLib/ml_bridge.lua` → `BuildSnapshot`) carries
only per-player kills/deaths. The trained model can only ever learn
"kills in → Commit_Margin out". Everything else it could learn — lineup
aggression timing, farm-vs-fight tradeoffs, when discipline pays — needs
features we aren't logging.

## Design

Extend `BuildSnapshot` with cheap bots-VM data (all verified API patterns
already used elsewhere in the codebase):

```lua
players = {
  { team='ally', hero='npc_dota_hero_lion',        -- GetSelectedHeroName(id)
    kills=…, deaths=…, assists=…,                  -- GetHeroKills/Deaths/Assists
    level=…,                                       -- from team member handle
    networth=…, last_hits=…,                       -- GetNetWorth/GetLastHits (own team)
  }, …
}
towers = { ally=…, enemy=… }                       -- standing tower counts
roshan_alive = J.IsRoshanAlive()
```

Enemy networth isn't queryable from the bots VM — that's fine: the
`/director` payload (addon VM) already has full both-team networth via
`Utilities:HeroStatsInGame`. Join the two streams server-side by client +
timestamp when building training examples.

Server side (`ml/train.py`):
- Features: kill gap, networth gap, avg level gap, tower gap, game time,
  hero-lineup embedding (start simple: sum of per-hero aggression priors from
  a small static table).
- Same target as today (kill-equivalent advantage delta over horizon), same
  linear fit first — more features, not more model, until data volume grows.

## Config

None needed — snapshot grows, wire format is already versionless JSON, old
server ignores unknown fields, old dataset rows keep working (missing
features default to 0 in training).

## Acceptance

- Snapshot builds without errors in-game (console clean, dataset rows show
  the new fields).
- `train.py` runs on mixed old+new rows without crashing.
- After ~20 games: trained model beats the static heuristic on held-out rows
  (train.py prints simple train/holdout error — add that print).

## Risks

- Payload size: ~10 players × a few fields ≈ 2–3 KB — negligible.
- API availability of `GetLastHits`/`GetNetWorth` for own team in bots VM —
  verify in-game; wrap per-field in pcall and default to 0 (never lose the
  whole snapshot to one missing API).
