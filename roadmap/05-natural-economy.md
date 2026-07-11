# 5. Natural Economy — wean the bots off stat bonuses

> **Status (2026-07-11):**
> - Measurement tool shipped: `python3 ml/report.py` — per game: final
>   kill/networth gap, count+direction of director difficulty changes, and
>   bot-team GPM @15min. This is the gate for every further step.
> - **Step 1 applied**: death-bonus `gold` halved to {50,250}, `levels` to
>   {0.5,1} in `SettingsDefault.lua`. Rationale for going before full
>   in-game validation: the adaptive director now compensates upward
>   automatically if bots underperform, so the mildest cut is safe.
> - **Steps 2–5 remain gated**: play games, run `ml/report.py`, and only
>   proceed when games end balanced with ≤2 director adjustments each.

## Goal

The end state of this roadmap: FretBots bonuses become a light corrective
touch, not the source of difficulty. Bots earn their gold/XP by playing well
(roadmap 1–3), and the adaptive director confirms it by needing smaller and
rarer boosts.

## Prerequisites

Roadmap items 1–3 landed and validated in real games. Do NOT start this
before — cutting bonuses under bots that still dive fog and farm badly just
makes them free wins.

## Method: measured, stepwise reduction

All knobs live in `bots/FretBots/SettingsDefault.lua`. Reduce in steps; after
each step play 2–3 games and check the director's behavior in `ml/data`
(count of difficulty-up adjustments = how much the bots needed help).

Step order (least→most disruptive):

1. **Death bonuses** (`deathBonus.range/chance/clamp`): halve gold + levels
   award ranges. These are the most "unnatural" — free stuff for dying.
2. **Game-start bonuses** (`gameStartBonus`, `gameStartBonusTimesDifficulty`):
   drop to 0 — a fair start, difficulty comes later and adaptively.
3. **GPM/XPM top-ups** (`gpm.clamp`, `xpm.clamp`): reduce max clamps by ~25%
   per step as farming efficiency (roadmap 3) proves out. This is the direct
   trade: natural GPM up → injected GPM down.
4. **Neutral item timing advantage** (`neutralItems.timings` vs
   `timingsDefault`): move toward human-equivalent timings.
5. **Per-bot skill variance** (`skill.variance`): narrow toward 1.0 so bot
   strength is uniform and predictable; difficulty differentiation comes from
   the director, not RNG.

Keep permanently (they're corrective, not inflationary):
- The adaptive director itself (it can also boost *down*, which zeroed
  bonuses can't).
- `dynamicDifficulty` (offline fallback rubber-band).
- The winning-side throttle (`GameState.GetThrottle`).

## Definition of done

At difficulty 5 start, against your normal stack:
- Median game is competitive (ends within ~±10 kill-equivalents) with the
  director making ≤2 adjustments per game, AND
- Death bonuses ≤ half of today's, game-start bonuses = 0, GPM clamps ≥ 25%
  lower than today.

At that point "hard mode" = the director simply starting higher — earned by
the same smart bots, not a different species of stat-cheat bot.
