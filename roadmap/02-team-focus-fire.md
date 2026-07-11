# 2. Team Focus-Fire — five bots, one target

## Problem

Individual target selection is now good (`J.GetAttackableWeakestUnitFromList`
scores by effective HP, disables, ally attention, distance), but each bot
scores independently. In a 5v5, bots often spread damage across 3+ enemies —
nobody dies, then the fight is lost on cooldowns. Research note: coordinated
teamfight execution is the acknowledged unsolved gap in every community
framework (Nostrademous explicitly gave up on it). Even a crude version is a
step nobody else has shipped.

## Design

All five team bots share one Lua VM, so coordination is just a shared table:

1. New module `bots/FunLib/team_focus.lua`:
   - `TeamFocus.Get()` → current called target (unit handle + call time) or nil.
   - `TeamFocus.Consider(bot)` — only the **captain** (first valid bot, same
     pattern as `ml_bridge.lua`) evaluates: if a teamfight is on
     (`J.IsInTeamFight`) pick the best kill target via the existing scoring
     over enemies near the fight location, and "call" it.
   - Call expires after ~6s, on target death, or if the target becomes
     unkillable (`J.CannotBeKilled`, BKB'd + full HP, etc.). Re-call allowed
     after expiry — no thrash mid-window.
2. Consumption — one hook, minimal surface: in
   `J.GetAttackableWeakestUnitFromList`, if a valid called target is in the
   candidate list, apply a large score bonus (not an override — a disabled
   90%-HP called target must not beat an uncalled 5%-HP target next to it).
3. Out-of-range bots ignore the call naturally (candidate lists are built
   from each bot's own radius) — no suicide chases.

## Config

```lua
Customize.FightIQ.Team_Focus = true,
Customize.FightIQ.Team_Focus_Window = 6,     -- seconds a call stays active
Customize.FightIQ.Team_Focus_Bonus = 0.25,   -- score bonus fraction of max HP
```

## Acceptance

- In a staged 5v5 (bot-vs-bot lobby, spectate): when a fight starts, 3+ bots
  visibly converge attacks/spells on one hero within ~2s of each other.
- Kill participation and fight win-rate go up; time-to-first-kill in fights
  goes down (observable by eye; also shows up as the director boosting bots
  less when they're the weaker side).
- No thrash: bots don't ping-pong between two targets mid-fight (window
  enforces this).

## Risks

- Focusing the wrong target (e.g. the tanky initiator) — mitigated because
  the call itself uses the same kill-oriented scoring, and the bonus loses to
  a genuinely almost-dead alternative.
- Support bots wasting saves/disables on the called target instead of peeling —
  out of scope: this only biases ATTACK target selection, not ability logic.
- Illusion heroes (PL, Naga) confusing the call — `IsSuspiciousIllusion` is
  already filtered in the scoring path.
