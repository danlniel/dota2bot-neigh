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

## Sequencing gate

Phase order and the Q1/Q2 decision matrix live in the implementation plan.
Nothing is implemented until the user approves this spec; item 3 additionally
waits for the playtest's `vm=` evidence.
