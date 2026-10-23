# Fork Knowledge Base (dota2bot-neigh)

What this fork adds on top of upstream OpenHyperAI, the hard constraints we
learned the expensive way, and how to verify anything. Upstream docs
(`ARCHITECTURE.md`, `PATCH_UPDATE_GUIDE.md`, `BOT_API_REFERENCE.md`) still
describe the base codebase; this file covers only what's different here.

**Last updated:** 2026-10-23

---

## 1. Repo and upstream

| | |
|---|---|
| Fork | `github.com/danlniel/dota2bot-neigh` (MIT, keep upstream LICENSE + credits) |
| Upstream | `github.com/forest0xia/dota2bot-OpenHyperAI` (remote `upstream`) |
| Working branch | `neigh/init-code` (origin's default branch). `main` mirrors upstream. |
| Remotes | HTTPS. The user's SSH key doesn't work for GitHub. |

**Syncing upstream:** `git fetch upstream && git rev-list --left-right --count upstream/main...HEAD`.
The left number is how far behind we are. As of 2026-10-23, upstream `main` hasn't moved since
`cb814c6` (2026-04-02), so we're 0 behind and 83 ahead. Upstream's
`pr-140-refactor` branch is a 339-file restructure that was never merged to their
main. **Don't merge it.** It would bulldoze every fork system below. Cherry-pick
individual community fixes from upstream PRs instead.

**Before calling a sync safe:** `git merge-base --is-ancestor upstream/main HEAD`
must succeed. Then spot-check that fork markers survive: `Customize.FightIQ` in
`bots/Customize/general.lua`, `bots/FunLib/team_focus.lua`, `bots/FunLib/reactive_buy.lua`,
`bots/FretBots/CounterSwap.lua`, `bots/FretBots/HeroHandicap.lua`.

---

## 2. Hard constraints (read before designing anything)

1. **Two separate Lua VMs load the same `bots/` folder.**
   - **Bots VM** (hero AI: `bot_*.lua`, `mode_*`, `ability_item_usage_*`, `item_purchase_*`, FunLib).
     It has **no working outbound HTTP**. Proven 2026-07-14: 1500+ server records
     from the addon VM, 0 from the bots VM. `FunLib/ml_bridge.lua` is a no-op
     shim. Don't try to revive bots-VM HTTP.
   - **Addon VM** (FretBots: `bots/FretBots.lua` + `bots/FretBots/`).
     `CreateHTTPRequest` works. This VM drives the adaptive-difficulty director.
2. **Cross-bot shared state is unreliable.** Whether one team's bots share a VM
   is unverified. Coordination must be **deterministic from team-shared game
   state**: every bot computes the same answer. Examples are
   `FunLib/team_focus.lua` (focus target) and `ReactiveBuy.IsLockdownBuyer`
   (who buys the anti-carry item). Never rely on a field written onto another
   bot's handle.
3. **Lua 5.1 / LuaJIT.** Syntax-check with `luajit -bl <file> >/dev/null`. The
   Mac's `luac` is 5.4 and misses 5.1-specific errors.
4. **Units gotchas:**
   - `J.GetHP(unit)` returns a **fraction** (0–1), not raw health. A golem bug
     came from comparing damage against it.
   - `J.HasItem(bot, name)` checks the **main six slots only**. Use
     `bot:FindItemSlot(name)` with a slot range when backpack or stash counts.
   - Item usage (`ItemUsageComplement`) scans **main slots plus TP/neutral only**.
     An item in the backpack is never cast. See `PromoteBackpackCounters` in
     `item_purchase_generic.lua`.
5. **Buying composite items:** the main build queue
   (`bot.purchaseListInReverseOrder`, where the LAST entry is next) buys
   **components as gold arrives**. Anything gated on "hold the full item cost at
   once" almost never fires, because the queue spends gold first. For must-have
   situational items, put them at the front of the queue
   (`_queueReactiveItem` → `ReactiveBuy.QueueFront`).
6. **Several TS-generated Lua files have drifted from their TS sources.**
   The fork edited them in Lua only:
   - `Customize/general.lua`: the FightIQ/ItemIQ/FarmIQ/LaneIQ/DraftIQ/ML blocks.
   - `FunLib/aba_push.lua`: A1 buyback awareness, B1 power spikes.
   - `FunLib/aba_site.lua`: C2 multi-camp stacking, invis-scan timing.
   - `FunLib/aba_role.lua`.

   Edit the Lua directly. **Never run the TSTL build** without first porting
   those changes into `typescript/`, or it will silently wipe them.
7. **The game runs on a separate Windows PC.** Dota isn't installed on the
   Mac. Nothing here can be tested in-game from this machine.

---

## 3. Fork systems map

All of these are configured under `Customize.*` in `bots/Customize/general.lua`
and default to on. `Debug = true` (FightIQ) prints `[IQ] …` lines to the console.

| System | What it does | Where |
|---|---|---|
| **FightIQ** | Commit margin (fight only when power ≥ 1.10× enemy), ult-ready bonus, fog awareness, focus fire, deterministic team focus and hunt calls, smoke ganks, deep-solo avoidance, buyback awareness, anti long-range (don't tank Sniper, focus backliners), power-spike windows, channeler priority | `FunLib/jmz_func.lua`, `FunLib/team_focus.lua`, `mode_*_generic.lua` |
| **ItemIQ** | Reactive items: Blade Mail (durable cores) / Ghost (supports) vs physical, Cloak/BKB vs magic and disables, Pipe/Glimmer when behind, Force/Pike vs kiters, proactive Pike/Force vs a drafted Sniper/Drow/Clinkz, **anti right-click carry** (below) | `item_purchase_generic.lua` (`ReactiveItemPurchase`), `FunLib/reactive_buy.lua` |
| **FarmIQ** | Stacking, multi-camp support stacking, lane fallback, `IsCampDangerous` fix | farm mode files |
| **LaneIQ** | Freeze the lane when ahead | laning mode |
| **DraftIQ** | Comp completeness. Bots wait up to 40 s for human picks (55 s deadline, assumes the lobby timer is longer). Post-pick counter swap | `hero_selection.lua`, `FretBots/CounterSwap.lua` |
| **ML director** | Adaptive difficulty. Starts at 5, steered by kill + networth gap, one step per 90 s, 4 min grace | `FretBots.lua` → server `/director` |
| **Comeback rubber-band** | A losing bot team's economy stops collapsing (1→2× at a 30% networth deficit) | `FretBots/GameState.lua` (`GetComebackBoost`), `Settings.comeback` |
| **Sniper handicap** | House rule: −12% base damage, −100 range, applied to human and bot alike | `FretBots/HeroHandicap.lua` |
| **Special counters** | Warlock golem fight-or-flee, invis counters vs late Sand King/Riki | `jmz_func.lua`, `FunLib/aba_special_units.lua` |

### Anti right-click carry (Troll / Ursa / Slark / PA), reworked 2026-10-23

Menace list: `J.tRightclickMenace` in `jmz_func.lua`.

- **Buy:** from minute 12 (`ItemIQ.Anti_Rightclick_Minute`), the mid and offlane
  bots move a counter to the **front of their build**: Halberd if STR, Orchid
  otherwise. The carry steps in when a human holds mid or offlane. The first
  non-STR assigned bot adds Sheepstick past minute 25 if the team has no hex.
  Supports queue a Ghost Scepter. If the team still owns nothing 10 min later,
  any bot core queues one.
- **Use:** `J.GetRightclickMenaceLock(bot, range, kind)` picks the engaged carry
  regardless of the team focus call:
  - Orchid/Bloodthorn **silence before Battle Trance**.
  - Sheep hexes and Halberd disarms while he swings. Trancing Troll goes first.
  - Abyssal stuns **through BKB**. Its cast range is 150 now. The code used
    to say 620, so bots walked into fights to use it.
  - A support uses Ghost the moment the carry swings at it below 75% HP.
- **Retreat:** bots step away from a trancing Troll they can't disable
  (`mode_retreat_generic.lua`). Battle Trance means "damage does not kill you".
- **Why the old version failed:** it fired at 18 min and only lump-bought at
  full gold. Battle Trance scores −1 in `J.ScoreEnemyTarget`, so a trancing
  Troll was never the focus or attack target, and the Orchid/Sheep code only
  locked the focus target. A counter landing in the backpack was never cast.

---

## 4. ML / director server (Orange Pi)

- Container `dota2bot-ml` on `orangepi@192.168.18.200` (passwordless SSH works
  from the Mac). Files are in `/home/orangepi/dota2bot-ml/` and data in `data/`.
  The API key lives only in the Pi's `.env`.
- Public URL: `https://dota.sunarjodaniel.xyz`, via the Pi's existing
  cloudflared tunnel. Add ingress rules there; never create new tunnels.
  LAN URL: `http://192.168.18.200:5544`.
- Endpoints: `GET /health`, `GET /report`, `GET /report/history`,
  `POST /director` (FretBots), `POST /policy` (unused, bots VM can't call it).
- **Health check:**
  ```bash
  curl -s https://dota.sunarjodaniel.xyz/health
  ssh orangepi@192.168.18.200 'docker ps --filter name=dota2bot-ml; ls -la /home/orangepi/dota2bot-ml/data'
  ```
  A new `session-YYYYMMDD.jsonl` appears for every day a game called the
  director. If you played but no file appeared, FretBots didn't run or
  couldn't reach the server. That's also a sign of a stale deploy.
- Model is still `heuristic`. There isn't enough game data to train one.
  Details are in `ml/README.md` and `ml/DEPLOYMENT.md`.

---

## 5. Deploy and judging a playtest

- On the gaming PC, run `deploy/deploy-to-dota.bat` **as administrator**. It does
  a `git pull --ff-only` and then robocopies `bots/` into the Dota vscripts
  folder. **Changes reach the game only after they're pushed to origin.**
- **The server requires the API key.** Without it, `/director` answers 401, and
  FretBots prints `[MLDirector] disabled: server rejected the API key`.
  - The deploy script asks for the key once and saves it to
    `deploy\ml_api_key.txt` (gitignored). It injects the key into the
    **deployed** `general.lua` after every mirror.
  - The repo's `Api_Key` stays `''`. Never commit the key, and never edit
    `general.lua` in the Windows clone: a dirty file breaks
    `git pull --ff-only`, and the script then deploys stale files.
  - To get the key: `ssh orangepi@192.168.18.200 'grep ML_API_KEY /home/orangepi/dota2bot-ml/.env'`.
  - A `vscripts\game\Customize\general.lua` override replaces the whole
    config, key included. The script warns when it finds one.
  - The first deploy after a script change has to run twice. PowerShell runs
    the version it already loaded, and only the second run uses the pulled one.
- **First check in any game log:**
  - `[IQ] FightIQ lib loaded (build YYYY-MM-DD)` must show the expected build.
  - The FretBots banner should end in `[neigh fork YYYY-MM-DD]`.
  - Without these, the game ran stale scripts and proves nothing. That happened
    on 2026-08-20.
  - **Bump both dates when shipping behavior changes**: `jmz_func.lua` (the
    `IQDebug` load line) and `FretBots.lua`.
- Useful `[IQ]` lines: `queued counter item_orchid (pos2)`,
  `backpack -> main: …`, `reactive buy … result=`, focus/hunt/smoke calls,
  kite detections.

---

## 6. Testing

- Pure logic goes in modules with injected engine dependencies
  (`FunLib/reactive_buy.lua`, `FunLib/team_focus.lua`) and is tested with plain
  LuaJIT. Run from the repo root:
  ```bash
  for t in tests/*.lua; do luajit "$t"; done
  python3 tests/test_server_report.py
  ```
- Glue code that touches the engine can only be syntax-checked
  (`luajit -bl`) and checked for global leaks
  (`luajit -bl file.lua | grep GSET`).
- Real behavior needs an in-game playtest by the user.

---

## 7. Open questions only a playtest can answer

- Does `ActionImmediate_PurchaseItem` accept composite items? The component
  fallback in `_tryReactiveBuy` covers both answers. Watch the `result=` codes.
- Does `ReplaceHeroWith` work in a normal lobby for CounterSwap? Look for the
  "Counter-pick: bot swapped" chat line and no `[ARDM]` errors after it.
- DraftIQ's 55 s pick deadline assumes the lobby's pick timer is longer. If
  bots get auto-randomed, lower it.
- ~20 squelched "error in error handling" runtime errors from ~18 min in the
  July build. Check whether they recur.
- Has any post-July build ever been judged in-game? As of 2026-10-23 the server
  has had no director calls since 2026-08-20.

---

## 8. Upstream community PRs: what we took and what we skipped

Reviewed 2026-10-23: #154, #163, #166 (which already contains #154 and #163),
and closed #168.

**Taken** (adapted, each commented with its PR number):
- **Deny filter (#163):** `J.IsDeniableLaneCreep` keeps bots from denying the
  Tidehunter fish. It still allows siege creeps, which the PR's version blocked.
- **Drop/pick-up loop (#166):** bots no longer pick up their own intentional
  drops (consumables, 30-min lotuses).
- **Ward counting (#168):** `Item.GetWardCharges` handles the merged
  `item_ward_dispenser`. That bug went live once pos 5 started buying sentries.
- **Enemy towers (#154):** they now count in `J.WeAreStronger`.

**Skipped, don't re-evaluate without a new reason:**
- **#166 `mode_attack_generic` rewrite:** it fights FightIQ's kite-disengage
  and commit margin.
- **Laning Think-gate removal and invasion-defense desire:** no strength
  check, and it mass-TPs.
- **Help-ally cooldown:** collides with our hunt logic.
- **Powerplay push remap:** halves normal push desire.
- **`aba_defend` overhaul:** "tower HP < max" is permanent.
- **#168 overhauls:** they duplicate FightIQ/FarmIQ, and "never engage
  golem" reverses our Warlock work.

Latent upstream bug, unfixed: `WeightedEnemiesAroundLocation` in `aba_defend`
has `({string.find(...)}) ~= nil` checks that are always true. Fix it in
`aba_defend.ts` if you ever touch that function.

## 9. Where the planning lives

- `roadmap/`: original roadmap items 01–05 and `BACKLOG.md` (v2 backlog, all
  worked through as of 2026-07-14).
- `docs/superpowers/specs/` and `docs/superpowers/plans/`: the 2026-08-19 bot-IQ
  design and plan (all 11 tasks done).
- Commit messages of the form "Spec item N: …" map to that spec.
