# Improvement Backlog v2 (pro-play + ML + draft + items)

Roadmap items 1–5 are done (see [README.md](README.md)). This is the next wave,
combining a codebase audit of pro-play macro gaps with the ML/draft/item asks.
Ranked by impact-per-effort. Thresholds (when to Rosh, kill-lead for 5-man,
aegis windows) to be sharpened by the pro-play research pass.

## Tier A — biggest impact, smallest code (do first)

### A1. Enemy buyback awareness — ✅ DONE (2026-07-14)
**Gap:** zero buyback checks in push/Rosh/ancient decisions. Bots threw 5 heroes
at a rax while the whole enemy team could buy back.
**Shipped:** `jmz.GetEffectiveEnemyDefenders(bot, vLoc, r)` = alive enemies near
the objective + dead enemy CORES likely holding buyback (enemy gold isn't
queryable, so buyback is estimated from role via enemy_role_estimation + a
mid-game time gate). `jmz.CountTeamBuybackReady()` reads our own buyback
directly. `aba_push.lua` damps base-dive desire (→0.45) when alive allies ≤
effective defenders AND we lack our own buybacks. Config:
`Customize.FightIQ.Buyback_Awareness` / `Buyback_Min_Time` (default 15 min).
**Note:** research confirmed pros/OpenAI Five time sieges to when enemies can't
buy back. Roshan-side buyback gate deferred (Rosh already gates on alive-enemy
proximity); revisit if needed.

### A2. ML model — unblock + strengthen (user #1) — ❌ IMPOSSIBLE from bots VM (2026-07-14)
**Verdict:** the bot-scripting VM has NO working outbound HTTP. Confirmed across
several games: 1500+ `/director` records from the addon VM (CreateHTTPRequest)
vs exactly 0 from the bots VM under BOTH `CreateHTTPRequest` and
`CreateRemoteHTTPRequest`. Code ran (bots played) + every URL tried + zero
packets = Valve sandboxes the bots VM off the network. `ml_bridge.lua` is now a
no-op shim; FightIQ runs locally from `Customize.FightIQ`. The DIFFICULTY
director (addon VM) is unaffected and still learns from `/director` data.
Live FightIQ tuning + the fight dataset are not achievable without a fragile
cross-VM game-state/chat hack (judged not worth it). Do not reopen.

### A3. Reactive itemization (user #3) — ✅ v1 (2026-07-14)
**Gap:** builds were static; only reaction was dust-vs-invis.
**Shipped v1:** `ReactiveItemPurchase()` in `item_purchase_generic.lua` (runs
each think, ≤1 buy per 4s, gold-gated so it never stalls the main build):
- vs physical right-click / being long-range-kited → squishy heroes buy
  **Ghost Scepter**, durable cores buy **Blade Mail** (this is A4 part 3).
- vs 2+ enemy nukers early + squishy → cheap **Cloak**.
Config: `Customize.ItemIQ` (`Anti_Physical` / `Anti_Magic`).
**Phase 2 — ✅ (2026-07-14):** cores buy **BKB** vs 2+ enemy disablers / 3+
nukers (mid-game+); when behind vs 2+ nukers, durable heroes buy **Pipe** and
supports buy **Glimmer Cape**; vs long-range kiters with no blink, buy **Force
Staff** to close/escape. All gold-gated (never stalls the main build), ≤1
reactive buy per 4s. Config: `ItemIQ.Anti_Disable` / `Team_Defense` / `Gap_Close`.
Comp-aware core-build swaps deferred (large, low marginal value).

### A4. Don't eat free damage from long-range attackers (e.g. Sniper) — ✅ parts 1&2 (2026-07-14)
**Shipped:** `jmz.IsBeingKitedByLongerRange(bot)` (enemy out-ranges us by
`Long_Range_Margin`, sits beyond our reach, is hitting us) → `mode_retreat`
breaks away instead of tanking, unless the team is committing (stronger + allies
here to close). Target scoring upweights squishy long-range backliners
(attack range ≥ 550). Config: `FightIQ.Avoid_Long_Range` / `Long_Range_Margin`.
Part 3 (Blade Mail / gap-close itemization) lands with A3 below.
_original notes:_
**Problem (user-reported):** vs a far-out-of-reach Sniper/Drow/etc, bots just
stand and tank auto-attacks doing nothing. Pros never accept free damage — they
disengage out of range, close the gap, or focus the ranged carry.
**Three parts:**
- *Positioning/retreat:* if taking auto-attack damage from an enemy whose attack
  range exceeds ours AND we can't reach them this instant (no mobility up, they
  keep kiting) → break line of sight / retreat out of their range instead of
  standing. Add a "being kited by longer range" check feeding retreat desire.
  **Where:** `mode_retreat_generic.lua`, `utils.lua` positioning.
- *Focus priority:* the team-focus / hunt system (already built) should upweight
  squishy high-attack-range backliners (Sniper/Drow/OD) as kill targets —
  they're the ones melting us and the easiest to burst. **Where:** `jmz_func.lua`
  target scoring + hunt-call selection.
- *Itemization (rides on A3):* buy/use Blade Mail vs heavy right-click carries;
  mobility/gap-close (Blink/Force) or Pipe/BKB to reach or survive them.
**Cheap-ish** — reuses retreat, the focus/hunt call, and the A3 item hooks.

## Tier B — high impact, more effort

### B1. Proactive power-spike timing — ✅ (2026-07-14)
**Shipped:** `jmz.IsInPowerSpikeWindow()` opens a ~25s aggression window when a
teammate crosses a level breakpoint (6/12/18/25) or completes a fight-defining
item (BKB/Blink/Aghs/Manta/Hex/… — curated `POWER_SPIKE_ITEMS`). During it,
`WeAreStronger`'s commit margin is scaled by `Power_Spike_Margin_Scale` (0.9)
and `aba_push`'s desire ceiling rises 0.82→0.92. First observation of each hero
records a baseline (no false spike on script attach). Config:
`FightIQ.Power_Spike` / `Power_Spike_Window` / `Power_Spike_Margin_Scale`.
Safety (power comparison, fog, buyback) still gates — this only nudges.

### B2. Draft: counter-pick + team-comp completeness (user #2) — ✅ comp-completeness (2026-07-14)
**Found:** counter-pick + synergy scoring already existed and IS used
(`ScoreCandidatesForTeam` + weighted-random top-5). **Shipped:** added a
team-comp-completeness term — candidates get a bonus for filling a role the
already-picked allies lack (disabler/initiator/nuker/carry), on the synergy
scale, so drafts stop ending up as five nukers with no stun. Config:
`Customize.DraftIQ.Comp_Completeness`.

### B3. Lane creep control / pulling
**Gap:** no pulling, no equilibrium freezing, minimal deny. Pros starve carries
this way. **Add:** support pull routing at pull timings, freeze near own tower
when ahead. **Where:** `mode_laning_generic.lua`, `mode_farm_generic.lua`.

## Tier C — polish

### C1. Smoke-gank coordination
Smoke is only auto-cast today. Add "smoke the group onto a called target"
routing, tied to the existing team-focus/hunt call system.

### C2. Multi-camp support stacking — ✅ (2026-07-14)
**Shipped:** `jmz.Site.GetNearestStackableCamp` + a farm-Think hook — a support
in the stack window (:50–:58) that's safe (healthy, no enemy within 1600) heads
to the NEAREST stackable camp (not just the one it's farming) and pulls it.
Across successive minute-marks a roaming support covers several camps for the
cores. Config: `FarmIQ.Multi_Stack`. (Realistic scope: opportunistic nearest-camp
per window, not a guaranteed 2–3-camp route in one window — that needs pathing
we can't validate blind.)

## Cross-cutting note
Every scriptable behavior above also becomes a **feature or reward signal** the
ML model (A2) can learn to time — so A2 compounds with everything else.
