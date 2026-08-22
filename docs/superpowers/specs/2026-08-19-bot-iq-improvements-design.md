# Bot IQ Improvements — Design

Date: 2026-08-19
Status: awaiting user review (drafted autonomously while the user runs the
diagnostic playtest; all assumptions are listed below)

## Goal

Make the July-14 FightIQ/ItemIQ features observably work in real games, close
the failure modes found in the 2026-08-19 investigation, and remove the
deployment friction that likely caused the original "seems not working" report.

## Background (evidence from 2026-08-19 investigation)

- Every FightIQ/ItemIQ feature was committed the evening of 2026-07-14; the
  last game the ML server recorded started before the final commits landed.
  The completed feature set has never been playtested.
- `[IQ]` console diagnostics were added in commit `4a3acc6` (behind
  `Customize.FightIQ.Debug`, default on). The user is generating the first
  diagnostic console.log now.
- Two open questions only that playtest can answer:
  - **Q1**: does `ActionImmediate_PurchaseItem` accept composite items
    (Blade Mail, BKB, Force Staff)? Used nowhere else in the codebase.
  - **Q2**: do all bots on a team share one Lua VM? Team focus-fire stores its
    "called target" in `jmz_func.lua` module state and assumes yes; comments
    in the same file contradict each other.

## Assumptions (user away; to be confirmed on return)

1. Scope is the six improvement items discussed on 2026-08-19 (this spec).
2. ~~"Countering Sniper with Blade Mail" means cores should buy Blade Mail
   regardless of primary attribute.~~ **Superseded 2026-08-20:** the user
   questioned this; agreed rule is durability-based (see item 2 design) —
   Blade Mail only where a human would buy it.
3. No implementation starts until the user approves this spec and the plan,
   and the playtest evidence is in (it decides two design branches).
4. The Windows gaming PC uses a standard Steam install; the deploy script must
   still accept an explicit path override.

## Design

### 1. Composite-purchase fallback in reactive buys (`bots/item_purchase_generic.lua`)

**Problem.** `_tryReactiveBuy` direct-purchases composite items. If the engine
rejects that (Q1), Blade Mail/BKB/Force Staff/Glimmer/Pipe silently never
happen; only basic items (Ghost Scepter, Cloak) work.

**Design.** Keep the direct attempt (and its diagnostic print). If the result
is not `PURCHASE_ITEM_SUCCESS`, fall back to component purchase:

- Decompose with `Item.GetBasicItems({itemName})` — the same decomposition the
  main purchase queue uses (built on Valve's `GetItemComponents`, per the
  project rule "never hardcode component arrays").
- Shop gate: only attempt the fallback when every component satisfies
  `not IsItemPurchasedFromSecretShop(comp)` OR the bot is at the secret shop
  (`DistanceFromSecretShop() == 0`). This avoids half-builds stalled on a
  secret-shop component; the reactive trigger simply re-fires later.
- Buy components in one pass (gold is already gated at the full item cost).
  If any purchase fails mid-pass, stop; auto-combine handles the rest and the
  4-second reactive tick retries the remainder. Owned-component dedupe: skip a
  component if the bot already holds it (`FindItemSlot` count vs required
  count, same `_buildRequiredCounts` idea as the main queue).
- Diagnostic prints stay: one line for the direct verdict, one for fallback
  entry, so future logs show which path runs.

**Outcome either way on Q1:** if direct purchase works, the fallback is dead
code kept as safety; if it doesn't, reactive itemization starts working. No
behavior depends on guessing the answer.

### 2. Blade Mail eligibility (`bots/item_purchase_generic.lua`)

**Problem.** Blade Mail is bought only by strength-attribute non-supports;
AGI/INT carries facing Sniper get Ghost Scepter — exactly the "no blademail"
the user observed. But blanket "all cores buy Blade Mail" is bad Dota: the
item's value scales with surviving inside the damage, and a squishy carry
reflects two hits and dies (revised 2026-08-20 with the user).

**Design (durability-based, decided 2026-08-20).** In the Anti_Physical
branch:

- Durable non-support — `GetPrimaryAttribute() == ATTRIBUTE_STRENGTH` OR
  `GetMaxHealth() >= 1600` at trigger time → Blade Mail. Catches tanky
  AGI/Universal bruisers, matching the 32 hero builds that already carry it.
- Support → Ghost Scepter (unchanged).
- Squishy non-support core → buys NOTHING here; falls through to the
  existing Force Staff gap-close branch — the human answer to being
  out-ranged. **Accepted change:** squishy cores stop buying Ghost Scepter
  (ghost form disables their own attacks; it was a questionable buy).

`bSquishy` remains for the other branches (Cloak, Glimmer) unchanged.
Future polish (out of scope): Hurricane Pike for ranged carries.

### 3. VM-independent team calls (`bots/FunLib/jmz_func.lua`) — **gated on Q2**

**Problem.** If each bot has its own Lua VM, `teamFocusTarget` module state
never propagates: every bot "calls" privately and team convergence is an
illusion.

**Design (only if the playtest shows distinct `vm=` addresses).** Replace
stored call state with a deterministic pure computation each bot performs
identically:

- Inputs restricted to **team-shared observables**: enemy effective HP,
  disable state, attack range, number of allies already attacking
  (`ally:GetAttackTarget()`), and distance from the **ally centroid** near the
  fight — never distance from the individual bot (that would break
  determinism across bots).
- Time-bucketed stability: candidates are scored once per 3-second bucket
  (`math.floor(DotaTime() / 3)`); all bots agree within a bucket and switch
  targets simultaneously. This replaces `Team_Focus_Window` hysteresis.
- No calls during the laning phase (the old hunt code had this guard; the
  deterministic version keeps it for the whole computation — lane fights
  are already served by the local focus-fire bonuses).
- `J.GetTeamFocusTarget()` keeps its signature; `ConsiderTeamFocus` /
  `ConsiderHuntCall` become selectors feeding the same deterministic scorer,
  so all call sites (targeting bonus, smoke-gank) are untouched.
- If Q2 shows a shared team VM, this item is dropped — current design is
  correct and cheaper.

### 4. Pos-4 smoke stock (`bots/item_purchase_generic.lua`)

**Problem.** Only pos 5 buys Smoke of Deceit, so the C1 smoke-gank depends on
one specific bot having it and being in position — rarely triggerable.

**Design.** Extend the existing pos-5 smoke purchase block to pos 4 with the
same constraints (net worth < 10000, empty-slot requirements, not during
laning phase, no duplicate while one is held). Stock limits already cap
over-buying; the smoke-usage desire logic is position-agnostic and needs no
change.

### 5. One-click deploy script for the Windows PC (`deploy/`)

**Problem.** Deployment is a manual copy of `bots/` into the game's vscripts
folder; a stale copy is the leading suspect in the original complaint and will
recur on every iteration.

**Design.** `deploy/deploy-to-dota.ps1` plus a double-clickable
`deploy/deploy-to-dota.bat` wrapper:

- Locate Steam via registry (`HKCU\Software\Valve\Steam\SteamPath`), parse
  `libraryfolders.vdf` to find the library containing `dota 2 beta`;
  `-DotaPath` parameter overrides everything.
- `git pull --ff-only` in the repo, then `robocopy /MIR` of `bots\` onto
  `...\dota 2 beta\game\dota\scripts\vscripts\bots`. `/MIR` is safe here: that
  folder is wholly owned by these scripts. The script refuses to run if the
  resolved target path does not end in `scripts\vscripts\bots`.
- Print the current git commit and remind the user to look for the
  `[IQ] FightIQ lib loaded (build …)` line in-game.
- Untestable from the Mac; the plan treats the user's first run as the test.

### 6. `GET /report` on the ML server (`ml/server.py`)

**Problem.** Reading the balance report requires SSH into the Pi.

**Design.** Two read-only endpoints beside `/health`:

- `GET /report` → `data/report-latest.txt` as `text/plain` (a friendly
  "no report generated yet" body with 404 when absent).
- `GET /report/history` → `data/report-history.log`, same handling.

No auth (aggregate game stats only, same exposure class as `/health`).
Deployed by rebuilding the `dota2bot-ml` container over the existing SSH
access; verified with `curl https://dota.sunarjodaniel.xyz/report`.

### 7. Proactive gap-close vs a long-range menace (`bots/item_purchase_generic.lua`) — added 2026-08-20

**Problem.** Itemization is purely reactive: a bot only answers Sniper after
it is already being kited. Humans pre-arm from the draft.

**Design.** New branch 0 in `ReactiveItemPurchase` behind
`ItemIQ.Proactive_Gap_Close` (default on): after minute 10, cores check once
whether the enemy drafted a long-range menace (seed list: Sniper, Drow,
Clinkz — via `GetSelectedHeroName` on enemy player IDs) or any seen enemy
shows ≥620 attack range (covers range talents/items). If so and the bot owns
no Blink/Force Staff/Hurricane Pike: ranged cores buy Hurricane Pike, melee
cores buy Force Staff (both through the Task 2 fallback, gold-gated at full
cost so core timings stay intact).

### 8. Hold lockdown for the long-range backliner (`ability_item_usage_generic.lua`) — added 2026-08-20

**Problem.** Bots burn Sheepstick/Orchid on the nearest frontliner; the
counterplay to a fed Sniper is locking HIM down.

**Design.** New helper `J.GetLongRangeLockTarget(bot, nCastRange)`: returns
the current team-focus target when it is a valid, not-yet-disabled enemy with
≥550 attack range inside cast range. Sheepstick and Orchid consider-functions
check it FIRST (before their proximity loop) and cast on it at HIGH desire.
Guarded by `FightIQ.Avoid_Long_Range`.

### 9. Stop standing and dying while kited — added 2026-08-20

**Problem (root-caused from the user's report "bot does nothing until
dead").** Two confirmed mechanisms: (a) target-candidate lists are built from
~800-unit scans, so a 950-range Sniper is never a candidate — the bot has no
attackable concept of its killer; (b) the A4 kite-retreat desire tops out at
HIGH (0.75) scaled by HP while laning mode returns 0.9 whenever a last-hit
exists, so retreat loses the mode auction until the bot is nearly dead.

**Design (two one-line-scale edits, both evidence-matched):**
- `mode_laning_generic.lua` GetDesire: when
  `J.GetHP(bot) < 0.55 and J.IsBeingKitedByLongerRange(bot)`, return
  `BOT_MODE_DESIRE_NONE` — a weakened, out-ranged bot stops contesting last
  hits and yields the auction.
- `mode_retreat_generic.lua` A4 block: desire ramp becomes
  `RemapValClamped(botHP, 0.9, 0.35, BOT_MODE_DESIRE_MODERATE,
  BOT_MODE_DESIRE_VERYHIGH)` so disengage actually wins once HP drops.

Deliberately NOT included yet: forcing bots to attack the kiter (fight-back).
With items 7/8, the focus scorer, and these two edits, the observed failure
is addressed; adding aggression without playtest evidence risks feeding.

### 10. Sniper handicap — house-rule hero nerf (`bots/FretBots/`) — added 2026-08-20

**Problem.** Even with behavioral counters, the user finds Sniper oppressive
in their lobby and explicitly requested a hero nerf (magnitudes delegated).

**Design.** A FretBots addon-VM feature (the only layer that can modify hero
stats). New `bots/FretBots/HeroHandicap.lua` with a config table:

```lua
HeroHandicap.settings = {
    npc_dota_hero_sniper = { damagePct = -12, attackRange = -100 },
}
```

Applied via a new Lua modifier `modifier_neigh_handicap`
(`bots/FretBots/modifiers/`, modeled on the existing party-hat modifier):
`MODIFIER_PROPERTY_BASEDAMAGEOUTGOING_PERCENTAGE` −12% and
`MODIFIER_PROPERTY_ATTACK_RANGE_BONUS` −100 (max Take Aim 950 → 850).
Visible debuff (honest), unpurgable, permanent, persists through death.
Applies to ANY hero matching the table — human or bot — so the rule is
symmetric. Hooked on `npc_spawned` (same pattern as `Modifier:Initialize`),
initialized from `FretBots.lua`, announced once in chat. Spells untouched —
the nerf targets the right-click/range identity that causes the frustration.

### 11. Comeback rubber-band — losing bots' economy stops collapsing (`bots/FretBots/`) — added 2026-08-21

**Problem (user report: "their exp and gpm fall if they lose").** Three
compounding causes found: (a) death-bonus ranges were halved 2026-07-11 with
the ML director promised as the upward compensator — but the director has
reached the server in zero games since 2026-07-14; (b) `AwardBonus:GetValue`
halves death bonuses AGAIN below difficulty 5 (quartering the originals);
(c) nothing boosts a losing team — `GetThrottle` only trims bots that are
ahead, and the per-minute catch-up is clamped at ~30–45 gold/min regardless
of deficit.

**Design.** `GameState:GetComebackBoost(team)` — the local mirror of
`GetThrottle`, no server needed: multiplier 1→`maxBoost` (default 2.0)
scaling linearly with the team's total-networth deficit, maxing at a 30%
deficit (`Settings.comeback`, tunable/disable-able). Applied at two points:
the per-minute award ceiling (`adjustedClamp × boost`) so gpm/xpm catch-up
can actually close gaps, and death-bonus values (`GetValue`), where a losing
team also skips the low-difficulty 0.5 cliff. Symmetric: ally bots behind
get it too. Announces once in chat when it exceeds 1.5×. The ahead-throttle
and the ML director are untouched and compose with it.

### 12. Warlock counters: kill the channeler, fight-or-flee the golem — added 2026-08-22

**Problem (user report).** Bots freeze during Upheaval instead of going for
the caster, and ignore the summoned golem while it kills them.

**Root causes.** (a) No targeting path valued channeling enemies — only
Sheepstick/Orchid holders interrupted, and Upheaval avoidance existed only
in the laning phase. (b) `aba_special_units.lua`'s golem logic compared raw
damage against `J.GetHP` FRACTIONS (0..1), so "can kill it" was never true;
the branch was also fully disabled during teamfights and used solo damage
only; nothing anywhere made a bot flee a golem it couldn't kill.

**Design.** Channeling enemies get a 15% max-HP targeting bonus in BOTH
paths (`GetAttackableWeakestUnitFromList` and the deterministic team-focus
scorer, unit-tested) — bots converge on a channeling Warlock. Golem: kill
math fixed to raw health and made team-based (allies within 900); a golem
attacking the bot or an ally that the team can kill yields desire 0.75
regardless of teamfight state; the same fraction bug was fixed in the
dominated-units branch; and a new `J.GetDangerousSummonChasingMe` retreat
hook makes a weakened bot that can't burst the golem alone disengage
instead of feeding it.

## Approaches considered and rejected

- **Wait for Q1 before writing any fallback** — rejected: the fallback is
  correct under both answers and removes the only silent-failure mode.
- **Ghost Scepter and Blade Mail both bought on cores** — rejected (YAGNI):
  one reactive slot per trigger keeps gold discipline; blademail alone matches
  the user's ask.
- **Item 3 via drawing-based or chat-based signaling between VMs** — rejected:
  fragile, spammy; deterministic recomputation needs no channel at all.
- **Full test framework for the Lua codebase** — rejected as scope creep; the
  plan adds a minimal luajit stub harness only for the two logic-dense pieces
  (fallback decomposition, deterministic scorer).

## Testing

- **Unit (new, minimal):** `tests/` luajit harness stubbing the handful of
  Valve globals used (`GetItemCost`, `IsItemPurchasedFromSecretShop`,
  `DotaTime`, unit handles). Covers: fallback component logic (dedupe, shop
  gate, partial-failure stop) and, if built, the deterministic scorer
  (identical output across simulated bots, bucket stability).
- **Syntax:** `luajit -bl` on every touched file (luac on this Mac is 5.4 and
  misses 5.1 cases).
- **In-game:** the `[IQ]` diagnostics are the acceptance test — a playtest
  must show successful reactive buys (result code == success or fallback
  lines), focus/hunt calls, and smoke-gank triggers when the setup occurs.
- **Server:** `curl` the new endpoints through the tunnel after redeploy.

## Success criteria

1. Playtest console shows a durable core (STR or ≥1600 max HP) buying Blade
   Mail against a long-range physical attacker, and squishy cores answering
   with Force Staff instead of Ghost Scepter.
2. Focus/hunt calls demonstrably shared: all bots' targeting converges on the
   called unit (one call line, multiple heroes attacking it).
3. Smoke-gank fires in at least one organic setup per game where conditions
   are met.
4. Deploy = double-click; `[IQ]` build line confirms freshness in-game.
5. `https://dota.sunarjodaniel.xyz/report` serves the latest balance report.
6. Vs a human Sniper: cores show up with Pike/Force Staff by mid-game, a
   sheep/orchid lands on Sniper in fights, and no bot dies in lane standing
   still while being kited (it disengages below ~55% HP instead).

## Playtest evidence log

- **Attempt 1 (2026-08-20, console.8955941909.log):** STALE DEPLOY — game ran
  the July-14 copy. Proof: fork loaded ("Open Neigh AI" welcome,
  custom_loader warn) but zero `[IQ]` lines, no House-rule announce, no
  /director traffic on the Pi despite a full 56-min game. Per the Task 1
  matrix: verdicts NOT recorded. Also observed: ~20 squelched
  "Script Runtime Error: error in error handling" from ~18 min game time —
  diagnose after a real deploy (current build prints identifiable errors).
  Deploy script hardened: robocopy admin hint + post-copy verification of
  FretBots/HeroHandicap.lua.
- **Resolution by assumption (2026-08-20, user directive "I'm ok with
  assumption"):** Q1 = UNRESOLVED and moot — the Task 2 component fallback
  makes reactive buys work under either engine answer. Q2 = UNRESOLVED —
  instead of assuming an answer, Task 7 was BUILT, because the deterministic
  recompute is correct under BOTH VM models (it uses no cross-VM state).
  Plan closed: all 11 tasks done or safely superseded. A future playtest log
  is still useful for confirming behavior in-game and for diagnosing the
  runtime errors seen in attempt 1, but nothing is gated on it anymore.

## Sequencing gate

Phase order and the Q1/Q2 decision matrix live in the implementation plan.
Nothing is implemented until the user approves this spec; item 3 additionally
waits for the playtest's `vm=` evidence.
