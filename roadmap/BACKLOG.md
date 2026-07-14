# Improvement Backlog v2 (pro-play + ML + draft + items)

Roadmap items 1–5 are done (see [README.md](README.md)). This is the next wave,
combining a codebase audit of pro-play macro gaps with the ML/draft/item asks.
Ranked by impact-per-effort. Thresholds (when to Rosh, kill-lead for 5-man,
aegis windows) to be sharpened by the pro-play research pass.

## Tier A — biggest impact, smallest code (do first)

### A1. Enemy buyback awareness
**Gap:** zero buyback checks in push/Rosh/ancient decisions. Bots throw 5 heroes
at a rax while the whole enemy team can buy back.
**Signal:** enemy `GetBuyback*` gold/cooldown; **Action:** gate rax/ancient
commitment and Roshan on "enough enemies can't buy back."
**Where:** `aba_push.lua`, `mode_roshan_generic.lua`. Cheap, high value.

### A2. ML model — unblock + strengthen (user #1)
**Blocker:** MLBridge (bots VM) never connected last session — 0 `/policy`
records, so FightIQ live-tuning + fight dataset never ran. **First:** diagnose
the `[MLBridge]` console line (HTTPS-in-bots-VM vs `CreateRemoteHTTPRequest`).
**Then:** the richer features (hero/nw/towers/roshan) are logged but the model
is still a 5-feature linear fit — grow it once real data flows; consider the
director itself becoming ML-driven. **Where:** `ml/`, `bots/FunLib/ml_bridge.lua`.

### A3. Reactive itemization (user #3)
**Gap:** builds are static; only reaction is dust-vs-invis. **Add:** BKB when
enemy has heavy magic/disable, defensive items (Ghost/Glimmer/Force/Pipe) when
behind, detection already present. Enemy-comp-aware insertions into the existing
`sRoleItemsBuyList` flow. **Where:** `item_purchase_generic.lua`, `aba_item.lua`.

### A4. Don't eat free damage from long-range attackers (e.g. Sniper)
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

### B1. Proactive power-spike timing
**Gap:** level checks are floors, never spikes; no aggression window after
BKB/Blink/Aghs completes or at 6/12/18/25. **Signal:** team item-completion
events + level breakpoints; **Action:** temporary team-roam/push desire boost.
**Where:** `mode_team_roam_generic.lua`, `aba_push.lua`, FightIQ.

### B2. Draft: real counter-pick + team-comp completeness (user #2)
**Gap:** matchup synergy/counter data used only as a light nudge. **Add:** weight
candidates hard against the enemy's *actual* picks, and fill comp holes (ensure
stun/lockdown, magic + physical mix, a save, an initiator). **Where:**
`hero_selection.lua` (`GetPositionedPool`/weighting), `aba_matchups.lua`.

### B3. Lane creep control / pulling
**Gap:** no pulling, no equilibrium freezing, minimal deny. Pros starve carries
this way. **Add:** support pull routing at pull timings, freeze near own tower
when ahead. **Where:** `mode_laning_generic.lua`, `mode_farm_generic.lua`.

## Tier C — polish

### C1. Smoke-gank coordination
Smoke is only auto-cast today. Add "smoke the group onto a called target"
routing, tied to the existing team-focus/hunt call system.

### C2. Multi-camp support stacking
Current stacking is single-camp self-serve. Route a support to stack 2–3 camps
at :53–:00; let cores collect big stacks.

## Cross-cutting note
Every scriptable behavior above also becomes a **feature or reward signal** the
ML model (A2) can learn to time — so A2 compounds with everything else.
