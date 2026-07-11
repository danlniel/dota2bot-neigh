# 1. Fog Awareness — stop diving into unseen enemies

## Problem

`J.WeAreStronger` (`bots/FunLib/jmz_func.lua`) — the single gate for
commit/retreat/help decisions — iterates `GetUnitList(UNIT_LIST_ALL)`, which
only contains units the team can currently see. Missing enemies contribute
zero enemy power. Result: bots evaluate a "2v1" as won and dive, when 3
unseen enemies are one smoke away. Humans exploit this constantly; it's the
single most bot-like behavior left.

## Design

Add a **missing-enemy pressure term** inside `J.WeAreStronger`:

1. For each enemy player id (`GetTeamPlayers(GetOpposingTeam())`):
   - alive (`IsHeroAlive(id)`) but NOT found in the visible-unit scan → "missing".
2. For each missing enemy, get last-seen info (`GetHeroLastSeenInfo(id)` —
   returns location + time_since_seen in the bots VM).
   - Seen recently (< 10s) and last position within ~3000 of the bot →
     treat as **near-threat**: add a power estimate to `enemyPower`.
   - Seen 10–25s ago → decayed weight (they could be anywhere nearby).
   - Longer / very far → ignore (probably farming across the map).
3. Power estimate for an unseen enemy: cannot query the handle, so use a
   proxy: average of the *visible* enemies' power terms this scan (or, if none
   visible, average of our own team's) scaled by the recency weight.
4. Keep it cheap: the enemy team is 5 ids; the scan already runs under a 0.5s
   cache.

## Config

```lua
Customize.FightIQ.Fog_Awareness = true,      -- master toggle
Customize.FightIQ.Fog_Recent_Seconds = 10,   -- full-weight window
Customize.FightIQ.Fog_Decay_Seconds = 25,    -- zero-weight beyond this
Customize.FightIQ.Fog_Near_Distance = 3000,  -- last-seen distance that counts
```

ML override: all numeric, so the `/policy` endpoint can tune them live for
free (existing `ApplyOverrides` merges any numeric FightIQ key).

## Acceptance

- Lobby test: stand missing with 2+ allies near a lane bot; pre-change it
  pushes into fog, post-change it backs off until vision re-establishes.
- Bots still take clearly-won fights when all enemies are visible (deadband
  unchanged — verify kill participation doesn't collapse).
- No measurable frame-time regression (the scan stays O(5) extra ids).

## Risks

- `GetHeroLastSeenInfo` availability/shape must be verified in-game first —
  gate everything behind `pcall` + the toggle, like the ult-readiness check.
- Over-caution: if bots stop fighting entirely, lower the near-distance or
  decay window. Tune in `Customize`, not code.
