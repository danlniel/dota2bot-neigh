# Bot IQ Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the FightIQ/ItemIQ features observably work in real games: harden reactive item buys against composite-purchase failure, buy Blade Mail on cores vs Sniper-style harass, widen smoke availability, make team focus-fire VM-independent if needed, and remove deployment/observability friction.

**Architecture:** Pure decision logic moves into small injected-dependency modules under `bots/FunLib/` (testable with plain LuaJIT, no engine), while Valve-API glue stays in the existing generic scripts. Server and deploy tooling are independent single-file changes.

**Tech Stack:** Lua 5.1 (Dota 2 bot VM, LuaJIT-compatible), Python 3 stdlib (`ml/server.py`), PowerShell 5+ (deploy script).

**Spec:** `docs/superpowers/specs/2026-08-19-bot-iq-improvements-design.md`

## Global Constraints

- Lua syntax must be verified with `luajit -bl <file>` — the Mac's `luac` is 5.4 and misses 5.1-only breakage.
- Never hardcode item component arrays; decomposition must flow through Valve's `GetItemComponents` (here via `Item.GetComponentList`). (Project rule from CLAUDE.md.)
- All new diagnostic prints use the `[IQ] ` prefix and are gated on `Customize.FightIQ.Debug == true`.
- Every commit message ends with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.
- Task 7 runs ONLY if Task 1 records "Q2: isolated VMs". Tasks 2–6 are unconditional.
- The repo working branch is `neigh/init-code`; push after each commit is fine (private fork).

---

### Task 1: Playtest evidence gate (analysis, no code)

**Files:**
- Modify: `docs/superpowers/specs/2026-08-19-bot-iq-improvements-design.md` (append evidence section)

**Interfaces:**
- Produces: recorded verdicts **Q1** (composite direct-purchase works: yes/no/not-observed) and **Q2** (team bots share one Lua VM: shared/isolated) in the spec file. Task 7's run/skip decision reads Q2.

The user is running a game with commit `4a3acc6` diagnostics. The console log lives on the gaming PC at `<dota 2 beta>\game\dota\console.log` when Dota is launched with `-condebug` (otherwise ask the user to paste the `[IQ]` lines).

- [ ] **Step 1: Extract the [IQ] lines**

With the log available locally (user sends it or pastes lines):

```bash
grep -F '[IQ]' console.log | head -100
grep -c 'FightIQ lib loaded' console.log
grep -F 'reactive buy' console.log
grep -F 'vm=' console.log | sort -u
```

- [ ] **Step 2: Interpret against the decision matrix**

| Observation | Verdict |
|---|---|
| No `FightIQ lib loaded (build 2026-08-19)` line at all | Stale deploy — STOP, have the user redeploy `bots/` and rerun; do not record verdicts |
| `reactive buy item_X result=N (success=N)` (result equals success value) for a composite item (blade_mail, black_king_bar, force_staff, glimmer_cape, pipe) | Q1 = yes |
| `reactive buy item_<composite> result=M` with M ≠ success value | Q1 = no |
| Only basic items (ghost, cloak) appear, or no reactive-buy lines | Q1 = not observed (fallback from Task 2 covers both answers; note it) |
| 1–2 `FightIQ lib loaded` lines total (one per team) with 1–2 distinct `vm=` addresses | Q2 = shared |
| ~10 load lines with ~10 distinct `vm=` addresses | Q2 = isolated |

- [ ] **Step 3: Record verdicts**

Append to the END of `docs/superpowers/specs/2026-08-19-bot-iq-improvements-design.md`:

```markdown
## Playtest evidence (filled by Task 1)

- Date of playtest: <YYYY-MM-DD>
- Q1 (composite direct purchase): <yes | no | not observed> — evidence: `<paste the exact [IQ] line(s)>`
- Q2 (team VM sharing): <shared | isolated> — evidence: <N> load lines, <M> distinct vm= addresses
- Task 7 decision: <run | skip>
- Other notable [IQ] output: <kite detections / focus calls / smoke-gank lines seen, or "none">
```

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/specs/2026-08-19-bot-iq-improvements-design.md
git commit -m "Record playtest evidence: Q1/Q2 verdicts

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: Reactive-buy component fallback

**Files:**
- Create: `bots/FunLib/reactive_buy.lua`
- Create: `tests/test_reactive_fallback.lua`
- Modify: `bots/item_purchase_generic.lua` (the `_tryReactiveBuy` function, near line 24)

**Interfaces:**
- Consumes: `Item.GetComponentList(itemName) -> {componentNames}` from `bots/FunLib/aba_item.lua:551` (returns `{itemName}` for basic items); Valve globals `IsItemPurchasedFromSecretShop(name) -> bool`, `PURCHASE_ITEM_SUCCESS`.
- Produces: module `reactive_buy` with three PURE functions (no Valve globals — everything injected):
  - `FlattenComponents(itemName, getComponents, nDepth?, tOut?) -> {basicNames}`
  - `CanBuyComponentsNow(tComponents, isSecretShopItem, bAtSecretShop) -> bool`
  - `MissingComponents(tComponents, ownedCounts) -> {names}` where `ownedCounts` is a map `name -> count`.

- [ ] **Step 1: Write the failing test**

Create `tests/test_reactive_fallback.lua`:

```lua
-- Run from repo root: luajit tests/test_reactive_fallback.lua
package.path = package.path .. ';./bots/FunLib/?.lua'
local RB = require('reactive_buy')

-- stub component tree: recipes are leaves, hood nests inside pipe
local tree = {
	item_blade_mail = { 'item_broadsword', 'item_chainmail' },
	item_pipe = { 'item_hood_of_defiance', 'item_headdress', 'item_recipe_pipe' },
	item_hood_of_defiance = { 'item_cloak', 'item_ring_of_health' },
	item_headdress = { 'item_ring_of_regen', 'item_recipe_headdress' },
}
local function getComponents(name)
	return tree[name] or { name }
end

-- flatten: nested composites fully decompose, recipes kept as leaves
local flat = RB.FlattenComponents('item_pipe', getComponents)
assert(#flat == 5, 'expected 5 leaves, got ' .. #flat)
assert(flat[1] == 'item_cloak' and flat[2] == 'item_ring_of_health',
	'hood must decompose depth-first')
assert(flat[5] == 'item_recipe_pipe', 'recipe kept as leaf')

-- flatten: basic item returns itself
local basic = RB.FlattenComponents('item_ghost', getComponents)
assert(#basic == 1 and basic[1] == 'item_ghost')

-- shop gate: a secret-shop component blocks unless at the secret shop
local function isSecret(name) return name == 'item_ring_of_health' end
assert(RB.CanBuyComponentsNow(flat, isSecret, false) == false)
assert(RB.CanBuyComponentsNow(flat, isSecret, true) == true)
assert(RB.CanBuyComponentsNow({ 'item_cloak' }, isSecret, false) == true)

-- missing: owned components are subtracted once each
local missing = RB.MissingComponents(
	{ 'item_broadsword', 'item_chainmail' }, { item_chainmail = 1 })
assert(#missing == 1 and missing[1] == 'item_broadsword')

-- missing: duplicate components need duplicate ownership
missing = RB.MissingComponents(
	{ 'item_ring_of_regen', 'item_ring_of_regen' }, { item_ring_of_regen = 1 })
assert(#missing == 1 and missing[1] == 'item_ring_of_regen')

print('test_reactive_fallback: all assertions passed')
```

- [ ] **Step 2: Run test to verify it fails**

Run: `luajit tests/test_reactive_fallback.lua`
Expected: FAIL — `module 'reactive_buy' not found`

- [ ] **Step 3: Write the module**

Create `bots/FunLib/reactive_buy.lua`:

```lua
-- Reactive itemization purchase mechanics (A3 hardening, design 2026-08-19).
-- Pure functions only: every engine dependency is injected so this file runs
-- under plain LuaJIT for tests. Glue lives in item_purchase_generic.lua.
local M = {}

-- Flatten a composite item into its basic purchasable parts. Recipes come
-- back from getComponents as items with no components, so they stay leaves.
-- getComponents(itemName) -> component list; returns {itemName} for basics.
function M.FlattenComponents(itemName, getComponents, nDepth, tOut)
	nDepth = nDepth or 0
	tOut = tOut or {}
	if nDepth > 4 then -- no real item nests deeper; guards a cyclic table
		tOut[#tOut + 1] = itemName
		return tOut
	end
	local tComps = getComponents(itemName)
	if #tComps == 0 or (#tComps == 1 and tComps[1] == itemName) then
		tOut[#tOut + 1] = itemName
		return tOut
	end
	for _, comp in ipairs(tComps) do
		M.FlattenComponents(comp, getComponents, nDepth + 1, tOut)
	end
	return tOut
end

-- Every component must be buyable where the bot stands, or the fallback
-- would half-build and stall on a secret-shop part.
function M.CanBuyComponentsNow(tComponents, isSecretShopItem, bAtSecretShop)
	for _, comp in ipairs(tComponents) do
		if isSecretShopItem(comp) and not bAtSecretShop then
			return false
		end
	end
	return true
end

-- Components still missing after subtracting what the bot already holds.
function M.MissingComponents(tComponents, ownedCounts)
	local remaining = {}
	for k, v in pairs(ownedCounts) do remaining[k] = v end
	local missing = {}
	for _, comp in ipairs(tComponents) do
		if (remaining[comp] or 0) > 0 then
			remaining[comp] = remaining[comp] - 1
		else
			missing[#missing + 1] = comp
		end
	end
	return missing
end

return M
```

- [ ] **Step 4: Run test to verify it passes**

Run: `luajit tests/test_reactive_fallback.lua`
Expected: `test_reactive_fallback: all assertions passed`

- [ ] **Step 5: Wire into `_tryReactiveBuy`**

In `bots/item_purchase_generic.lua`, add the require next to the existing ones (after line 10, `local Customize = require( GetScriptDirectory()..'/FunLib/custom_loader')`):

```lua
local ReactiveBuy = require( GetScriptDirectory()..'/FunLib/reactive_buy' )
```

Replace the ENTIRE current `_tryReactiveBuy` function (it currently direct-purchases and prints a diagnostic) with:

```lua
local function _tryReactiveBuy(itemName)
	if _reactiveOwnedOrBuilding(itemName) then return false end
	if Item.GetEmptyInventoryAmount(bot) < 1 then return false end
	if bot:GetGold() < GetItemCost(itemName) then return false end
	local iqf = Customize.FightIQ
	local bDebug = iqf ~= nil and iqf.Debug == true
	local nResult = bot:ActionImmediate_PurchaseItem(itemName)
	if bDebug then
		print('[IQ] '..botName..' reactive buy '..itemName..' result='..tostring(nResult)
			..' (success='..tostring(PURCHASE_ITEM_SUCCESS)..') gold='..bot:GetGold())
	end
	if nResult == PURCHASE_ITEM_SUCCESS then return true end

	-- Engine refused the composite: buy its parts instead. Gold was gated at
	-- the full item cost above, so this can't half-build out of poverty; a
	-- mid-pass failure leaves owned parts that MissingComponents skips on the
	-- next 4s tick.
	local tComponents = ReactiveBuy.FlattenComponents(itemName, Item.GetComponentList)
	if #tComponents <= 1 then return false end
	if not ReactiveBuy.CanBuyComponentsNow(tComponents, IsItemPurchasedFromSecretShop,
		bot:DistanceFromSecretShop() == 0) then return false end
	local tOwned = {}
	for slot = 0, 14 do
		local it = bot:GetItemInSlot(slot)
		if it ~= nil then
			local n = it:GetName()
			tOwned[n] = (tOwned[n] or 0) + 1
		end
	end
	local tMissing = ReactiveBuy.MissingComponents(tComponents, tOwned)
	if bDebug then
		print('[IQ] '..botName..' fallback: buying '..#tMissing..' components of '..itemName)
	end
	for _, comp in ipairs(tMissing) do
		if bot:ActionImmediate_PurchaseItem(comp) ~= PURCHASE_ITEM_SUCCESS then
			return false
		end
	end
	return true
end
```

Known accepted edge (documented in spec): a component sitting in inventory for the MAIN build target can be counted as owned here; the main queue's rebuild-missing logic rebuys it later.

- [ ] **Step 6: Syntax-check both files**

Run: `luajit -bl bots/FunLib/reactive_buy.lua > /dev/null && luajit -bl bots/item_purchase_generic.lua > /dev/null && echo SYNTAX-OK`
Expected: `SYNTAX-OK`

- [ ] **Step 7: Commit**

```bash
git add bots/FunLib/reactive_buy.lua tests/test_reactive_fallback.lua bots/item_purchase_generic.lua
git commit -m "A3 hardening: component fallback when composite direct-buy fails

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: Blade Mail on durable heroes; squishy cores gap-close instead

**Files:**
- Modify: `bots/item_purchase_generic.lua` (Anti_Physical branch inside `ReactiveItemPurchase`, near line 41)

**Interfaces:**
- Consumes: `Role.IsSupport(bot)`, `_tryReactiveBuy(itemName)` from Task 2, Valve globals `ATTRIBUTE_STRENGTH`, `bot:GetPrimaryAttribute()`, `bot:GetMaxHealth()`.
- Produces: nothing new — behavior change only.

Rule (spec item 2, revised 2026-08-20): Blade Mail only where it's strong —
heroes tanky enough to stand in the damage (STR primary or ≥1600 max HP).
Squishy cores buy nothing here and fall through to the existing Force Staff
gap-close branch (5) further down `ReactiveItemPurchase`; supports keep
Ghost Scepter.

- [ ] **Step 1: Replace the branch**

Current code:

```lua
	if iq.Anti_Physical ~= false then
		local bKited, kiter = J.IsBeingKitedByLongerRange(bot)
		local bHardHit = bot:WasRecentlyDamagedByAnyHero(2.0) and J.GetHP(bot) < 0.6
		if bKited or bHardHit then
			if bSquishy then
				if _tryReactiveBuy('item_ghost') then return end
			elseif not Role.IsSupport(bot) then
				if _tryReactiveBuy('item_blade_mail') then return end
			end
		end
	end
```

New code:

```lua
	if iq.Anti_Physical ~= false then
		local bKited, kiter = J.IsBeingKitedByLongerRange(bot)
		local bHardHit = bot:WasRecentlyDamagedByAnyHero(2.0) and J.GetHP(bot) < 0.6
		if bKited or bHardHit then
			-- Blade Mail only where it's strong: heroes tanky enough to stand
			-- in the damage while it reflects. Squishy cores skip Ghost (it
			-- disables their own attacks) and fall through to the Force Staff
			-- gap-close branch below — the human answer to being out-ranged.
			local bDurable = bot:GetPrimaryAttribute() == ATTRIBUTE_STRENGTH
				or bot:GetMaxHealth() >= 1600
			if bDurable and not Role.IsSupport(bot) then
				if _tryReactiveBuy('item_blade_mail') then return end
			elseif Role.IsSupport(bot) then
				if _tryReactiveBuy('item_ghost') then return end
			end
		end
	end
```

Note: `bSquishy` stays defined above — the Anti_Magic and Team_Defense branches still use it. The 1600-HP threshold is deliberate: a bruiser hits it around the 12–18 min Blade Mail timing window; a squishy carry doesn't.

- [ ] **Step 2: Syntax-check**

Run: `luajit -bl bots/item_purchase_generic.lua > /dev/null && echo SYNTAX-OK`
Expected: `SYNTAX-OK`

- [ ] **Step 3: Commit**

```bash
git add bots/item_purchase_generic.lua
git commit -m "ItemIQ: Blade Mail on durable heroes, gap-close for squishy cores

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

In-game acceptance (next playtest): a bruiser harassed by Sniper logs `[IQ] ... reactive buy item_blade_mail ...`; a squishy carry in the same spot logs `item_force_staff`, never `item_ghost`.

---

### Task 4: Pos-4 smoke stock

**Files:**
- Modify: `bots/item_purchase_generic.lua` (Smoke of Deceit purchase block, near line 983)

**Interfaces:**
- Consumes: `J.GetPosition(bot) -> 1..5`.
- Produces: nothing new — behavior change only.

- [ ] **Step 1: Widen the position gate**

Current first line of the block:

```lua
	-- Smoke of Deceit
	if J.GetPosition(bot) == 5 and botWorth < 10000
```

New:

```lua
	-- Smoke of Deceit (pos 4 or 5 — either support can carry the gank smoke)
	if J.GetPosition(bot) >= 4 and botWorth < 10000
```

Everything else in the block (stock checks, charge checks, slot checks) stays untouched — the shared item stock already caps team-wide over-buying.

- [ ] **Step 2: Syntax-check**

Run: `luajit -bl bots/item_purchase_generic.lua > /dev/null && echo SYNTAX-OK`
Expected: `SYNTAX-OK`

- [ ] **Step 3: Commit**

```bash
git add bots/item_purchase_generic.lua
git commit -m "C1 support: pos 4 also stocks Smoke of Deceit

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: `GET /report` and `GET /report/history` on the ML server

**Files:**
- Modify: `ml/server.py` (the `do_GET` method, near line 238)
- Create: `tests/test_server_report.py`

**Interfaces:**
- Consumes: `DATA_DIR` module constant; report files `report-latest.txt` / `report-history.log` written by `Policy._report_and_retrain` (`ml/server.py:142`).
- Produces: `GET /report` and `GET /report/history` returning `text/plain` (200 with file body, or 404 with `no report generated yet\n`).

- [ ] **Step 1: Write the failing test**

Create `tests/test_server_report.py`:

```python
"""Run from repo root: python3 tests/test_server_report.py -v"""
import json
import os
import sys
import tempfile
import threading
import unittest
import urllib.error
import urllib.request


class ReportEndpointTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp()
        os.environ["ML_DATA_DIR"] = cls.tmp
        sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "ml"))
        import server  # imported AFTER env var so DATA_DIR picks it up
        cls.server = server
        from http.server import ThreadingHTTPServer
        cls.httpd = ThreadingHTTPServer(("127.0.0.1", 0), server.Handler)
        cls.port = cls.httpd.server_address[1]
        threading.Thread(target=cls.httpd.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.httpd.shutdown()

    def _get(self, path):
        try:
            with urllib.request.urlopen(f"http://127.0.0.1:{self.port}{path}") as r:
                return r.status, r.read().decode()
        except urllib.error.HTTPError as e:
            return e.code, e.read().decode()

    def test_report_missing_then_present(self):
        code, body = self._get("/report")
        self.assertEqual(code, 404)
        self.assertIn("no report", body)
        with open(os.path.join(self.tmp, "report-latest.txt"), "w") as f:
            f.write("balance report body")
        code, body = self._get("/report")
        self.assertEqual(code, 200)
        self.assertEqual(body, "balance report body")

    def test_history(self):
        with open(os.path.join(self.tmp, "report-history.log"), "w") as f:
            f.write("history body")
        code, body = self._get("/report/history")
        self.assertEqual(code, 200)
        self.assertEqual(body, "history body")

    def test_health_still_works(self):
        code, body = self._get("/health")
        self.assertEqual(code, 200)
        self.assertEqual(json.loads(body)["status"], "ok")


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 tests/test_server_report.py -v`
Expected: `test_report_missing_then_present` and `test_history` FAIL (the 404 JSON body has no "no report" text); `test_health_still_works` passes.

- [ ] **Step 3: Implement the endpoints**

In `ml/server.py`, replace the current `do_GET`:

```python
    def do_GET(self):
        if self.path == "/health":
            self._respond({
                "status": "ok",
                "model": "trained" if self.policy.model else "heuristic",
                "uptime_s": int(time.time() - START_TIME),
            })
        else:
            self._respond({"error": "unknown endpoint"}, 404)
```

with:

```python
    def do_GET(self):
        if self.path == "/health":
            self._respond({
                "status": "ok",
                "model": "trained" if self.policy.model else "heuristic",
                "uptime_s": int(time.time() - START_TIME),
            })
        elif self.path == "/report":
            self._respond_file(os.path.join(DATA_DIR, "report-latest.txt"))
        elif self.path == "/report/history":
            self._respond_file(os.path.join(DATA_DIR, "report-history.log"))
        else:
            self._respond({"error": "unknown endpoint"}, 404)

    def _respond_file(self, path: str):
        """Serve a data file as text/plain; friendly 404 when absent."""
        try:
            with open(path, "rb") as f:
                body = f.read()
            code = 200
        except OSError:
            body = b"no report generated yet\n"
            code = 404
        self.send_response(code)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python3 tests/test_server_report.py -v`
Expected: all 3 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add ml/server.py tests/test_server_report.py
git commit -m "ML server: GET /report and /report/history (read balance report without SSH)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

- [ ] **Step 6: Deploy to the Pi**

First confirm the layout (the container was built from `/home/orangepi/dota2bot-ml`):

```bash
ssh orangepi@192.168.18.200 'ls /home/orangepi/dota2bot-ml'
```

Expected: `server.py`, `Dockerfile`, `docker-compose.yml` (and friends). Then copy the updated file where `server.py` actually sits (adjust if `ls` shows a nested layout) and rebuild:

```bash
scp ml/server.py orangepi@192.168.18.200:/home/orangepi/dota2bot-ml/server.py
ssh orangepi@192.168.18.200 'cd /home/orangepi/dota2bot-ml && docker compose up -d --build'
```

- [ ] **Step 7: Verify through the tunnel**

```bash
curl -s https://dota.sunarjodaniel.xyz/health
curl -s https://dota.sunarjodaniel.xyz/report | head -5
```

Expected: `/health` returns `{"status": "ok", ...}` (uptime resets to a small number); `/report` returns the balance report text (the July one until a new game completes).

---

### Task 6: One-click Windows deploy script

**Files:**
- Create: `deploy/deploy-to-dota.ps1`
- Create: `deploy/deploy-to-dota.bat`
- Modify: `README.md` (install section, after the existing "Copy the repo's `bots/` folder..." instructions near line 51)

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: `deploy-to-dota.bat` (double-clickable) → runs `deploy-to-dota.ps1 [-DotaPath <path>]`.

- [ ] **Step 1: Write the PowerShell script**

Create `deploy/deploy-to-dota.ps1`:

```powershell
# Deploy the repo's bots/ folder into the local Dota 2 install.
# Usage: .\deploy-to-dota.ps1 [-DotaPath "D:\Games\Steam\steamapps\common\dota 2 beta"]
param(
    [string]$DotaPath = ""
)
$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot

function Find-DotaPath {
    $steam = (Get-ItemProperty -Path "HKCU:\Software\Valve\Steam" -Name SteamPath -ErrorAction SilentlyContinue).SteamPath
    if (-not $steam) { throw "Steam not found in registry; pass -DotaPath" }
    $steam = $steam -replace "/", "\"
    $libs = @($steam)
    $libFile = Join-Path $steam "steamapps\libraryfolders.vdf"
    if (Test-Path $libFile) {
        Get-Content $libFile | ForEach-Object {
            if ($_ -match '"path"\s+"([^"]+)"') { $libs += ($Matches[1] -replace "\\\\", "\") }
        }
    }
    foreach ($lib in $libs) {
        $candidate = Join-Path $lib "steamapps\common\dota 2 beta"
        if (Test-Path $candidate) { return $candidate }
    }
    throw "dota 2 beta not found in any Steam library; pass -DotaPath"
}

if (-not $DotaPath) { $DotaPath = Find-DotaPath }
$target = Join-Path $DotaPath "game\dota\scripts\vscripts\bots"
if ($target -notmatch 'scripts\\vscripts\\bots$') {
    throw "refusing to mirror onto '$target' - not a vscripts\bots folder"
}

Write-Host "repo:   $RepoRoot"
Write-Host "target: $target"
git -C $RepoRoot pull --ff-only
$commit = git -C $RepoRoot rev-parse --short HEAD
robocopy (Join-Path $RepoRoot "bots") $target /MIR /NFL /NDL /NJH /NJS | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy failed with exit code $LASTEXITCODE" }
Write-Host "deployed commit $commit"
Write-Host "in-game check: console prints '[IQ] FightIQ lib loaded (build ...)'"
```

- [ ] **Step 2: Write the batch wrapper**

Create `deploy/deploy-to-dota.bat`:

```bat
@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0deploy-to-dota.ps1" %*
pause
```

- [ ] **Step 3: Document in README**

In `README.md`, directly after the existing manual-copy install instructions (the paragraph containing "Copy the repo's `bots/` folder into your Dota 2 vscripts folder"), add:

```markdown
### One-click deploy (Windows)

Double-click `deploy/deploy-to-dota.bat` (or run `deploy/deploy-to-dota.ps1`
from PowerShell). It pulls the latest commit and mirrors `bots/` into your
Dota 2 install — Steam is auto-detected, or pass
`-DotaPath "D:\...\dota 2 beta"` explicitly. After it runs, the in-game
console should print `[IQ] FightIQ lib loaded (build ...)` — that line is the
proof the game loaded the fresh scripts.

The mirror is exact: edits made directly in the game's `vscripts\bots`
folder are overwritten. Change files in the repo (e.g.
`bots/Customize/general.lua`) and redeploy instead.
```

- [ ] **Step 4: Sanity-check the PowerShell parses (best effort on macOS)**

If `pwsh` is installed: `pwsh -NoProfile -Command "[scriptblock]::Create((Get-Content -Raw deploy/deploy-to-dota.ps1)) | Out-Null; 'PARSE-OK'"` — expected `PARSE-OK`.
If `pwsh` is not installed, skip; the user's first run on the PC is the test (script is throw-early and mirrors only after all checks).

- [ ] **Step 5: Commit**

```bash
git add deploy/deploy-to-dota.ps1 deploy/deploy-to-dota.bat README.md
git commit -m "deploy: one-click Windows script mirroring bots/ into the Dota install

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 7: VM-independent team focus (ONLY if Task 1 recorded "Q2: isolated")

**Skip rule:** if the spec's "Playtest evidence" section says `Q2: shared`, mark this task skipped and stop here — the current stored-call design is correct on a shared VM.

**Files:**
- Create: `bots/FunLib/team_focus.lua`
- Create: `tests/test_team_focus.lua`
- Modify: `bots/FunLib/jmz_func.lua` (the "Team focus-fire" section, near lines 3496–3600: replaces `teamFocusTarget`/`teamFocusCallTime` state, `J.GetTeamFocusTarget`, `ConsiderHuntCall`, `J.ConsiderTeamFocus`; keeps `IsNearEnemyTower` and `TOWER_ID_LIST` as-is)

**Interfaces:**
- Consumes: `J.GetAlliesNearLoc(vLoc, nRadius)`, `J.GetEnemiesNearLoc(vLoc, nRadius)`, `J.IsValidHero`, `J.IsSuspiciousIllusion`, `J.CannotBeKilled(nil, unit)`, `J.Utils.IsValidUnit`, local `IsNearEnemyTower(vLoc, nRadius)`, Valve globals `GetTeamPlayers`, `GetTeamMember`, `GetUnitToLocationDistance`, `Vector`, `DotaTime`.
- Produces: module `team_focus` with pure functions
  - `Compute(env, iq) -> enemyHandle | nil`
  - `Bucket(t) -> integer` (3-second buckets)

  and an unchanged-signature `J.GetTeamFocusTarget() -> unit|nil` (all existing call sites — targeting bonus at `jmz_func.lua:3774`, smoke-gank in `ability_item_usage_generic.lua` — keep working untouched). `J.ConsiderTeamFocus(bot)` remains as a cache-warming poll for `mode_team_roam_generic.lua:74`.

**Behavior change (accepted in spec):** hunt candidates are found around the ALLY CENTROID rather than each caller bot, and `Team_Focus_Window` hysteresis is replaced by 3-second buckets. `Team_Focus_Window` stays in the config as a no-op key (removing it would break user-customized copies of `general.lua`).

- [ ] **Step 1: Write the failing test**

Create `tests/test_team_focus.lua`:

```lua
-- Run from repo root: luajit tests/test_team_focus.lua
package.path = package.path .. ';./bots/FunLib/?.lua'
local TF = require('team_focus')

local function unit(name, opts)
	opts = opts or {}
	local u = {}
	u.GetLocation = function() return { x = opts.x or 0, y = opts.y or 0 } end
	u.GetArmor = function() return opts.armor or 0 end
	u.GetHealth = function() return opts.hp or 1000 end
	u.GetMaxHealth = function() return opts.maxhp or 1000 end
	u.GetAttackRange = function() return opts.range or 150 end
	u.GetAttackTarget = function() return opts.attacking end
	u.IsStunned = function() return opts.stunned or false end
	u.IsHexed = function() return false end
	u.IsRooted = function() return false end
	u.IsNightmared = function() return false end
	u.GetUnitName = function() return name end
	u.handle = u -- production wrappers carry the real engine handle here
	return u
end

local function makeEnv(allies, enemies)
	local function near(list, loc, r)
		local t = {}
		for _, u in ipairs(list) do
			local ul = u.GetLocation()
			local dx, dy = ul.x - loc.x, ul.y - loc.y
			if math.sqrt(dx * dx + dy * dy) <= r then t[#t + 1] = u end
		end
		return t
	end
	return {
		vector = function(x, y) return { x = x, y = y } end,
		allies = function() return allies end,
		alliesNear = function(loc, r) return near(allies, loc, r) end,
		enemiesNear = function(loc, r) return near(enemies, loc, r) end,
		isValidTarget = function() return true end,
		nearEnemyTower = function() return false end,
		isLaningPhase = function() return false end,
		distToLoc = function(u, loc)
			local ul = u.GetLocation()
			local dx, dy = ul.x - loc.x, ul.y - loc.y
			return math.sqrt(dx * dx + dy * dy)
		end,
	}
end

-- determinism: identical inputs -> identical target, every call
local a1, a2 = unit('ally1', { x = 0, y = 0 }), unit('ally2', { x = 200, y = 0 })
local e1 = unit('tanky', { x = 500, y = 0, hp = 2000, maxhp = 2000 })
local e2 = unit('squishy', { x = 600, y = 0, hp = 900, maxhp = 900 })
local env = makeEnv({ a1, a2 }, { e1, e2 })
local first = TF.Compute(env, {})
assert(first == e2, 'squishier enemy wins on effective HP')
for i = 1, 5 do
	assert(TF.Compute(env, {}) == first, 'must be deterministic across calls')
end

-- disabled targets are preferred over an otherwise-identical enemy
local d1 = unit('healthy', { x = 500, y = 0 })
local d2 = unit('stunned', { x = 500, y = 100, stunned = true })
assert(TF.Compute(makeEnv({ a1, a2 }, { d1, d2 }), {}) == d2)

-- long-range backliners are preferred over an otherwise-identical melee
local m = unit('melee', { x = 500, y = 0 })
local s = unit('sniper', { x = 500, y = 100, range = 950 })
assert(TF.Compute(makeEnv({ a1, a2 }, { m, s }), {}) == s)

-- hunt mode: no enemy near the group, but an isolated one in reach is called
local far = unit('farmer', { x = 2500, y = 0 })
assert(TF.Compute(makeEnv({ a1, a2 }, { far }), {}) == far)

-- no candidates at all -> nil
assert(TF.Compute(makeEnv({ a1, a2 }, {}), {}) == nil)

-- laning phase -> never any call (guard kept from the old hunt code)
local laneEnv = makeEnv({ a1, a2 }, { e1, e2 })
laneEnv.isLaningPhase = function() return true end
assert(TF.Compute(laneEnv, {}) == nil)

-- buckets: 3-second windows
assert(TF.Bucket(0) == 0 and TF.Bucket(2.9) == 0 and TF.Bucket(3.0) == 1 and TF.Bucket(7.5) == 2)

print('test_team_focus: all assertions passed')
```

- [ ] **Step 2: Run test to verify it fails**

Run: `luajit tests/test_team_focus.lua`
Expected: FAIL — `module 'team_focus' not found`

- [ ] **Step 3: Write the module**

Create `bots/FunLib/team_focus.lua`:

```lua
-- VM-independent team focus target (design 2026-08-19 item 3).
-- Every bot recomputes the SAME call from team-shared observables only, so
-- coordination needs no cross-VM state. Determinism rule: NEVER score with
-- the calling bot's own position or state — only inputs every teammate sees
-- identically (ally centroid, enemy stats, who is already being attacked).
local M = {}

-- 3-second buckets: bots recompute on the same schedule, so they agree
-- within a bucket and switch targets simultaneously.
function M.Bucket(t)
	return math.floor(t / 3)
end

-- env (all functions injected; see TeamFocusEnv in jmz_func.lua):
--   vector(x, y), allies(), alliesNear(loc, r), enemiesNear(loc, r),
--   isValidTarget(u), nearEnemyTower(loc, r), distToLoc(u, loc),
--   isLaningPhase()
function M.Compute(env, iq)
	-- no calls during laning: lane fights are served by the local
	-- focus-fire bonuses, and early "hunt" calls waste smokes
	if env.isLaningPhase() then return nil end
	local tAllies = env.allies()
	if #tAllies < 2 then return nil end
	local x, y = 0, 0
	for _, a in ipairs(tAllies) do
		local v = a.GetLocation()
		x = x + v.x
		y = y + v.y
	end
	local vCentroid = env.vector(x / #tAllies, y / #tAllies)

	-- fight mode: enemies already close to the grouped team.
	local tCandidates = env.enemiesNear(vCentroid, 1600)
	if #tCandidates == 0 then
		-- hunt mode: an isolated, reachable enemy away from towers
		-- (same rules the old stored-call ConsiderHuntCall used).
		for _, e in ipairs(env.enemiesNear(vCentroid, 3000)) do
			if #env.enemiesNear(e.GetLocation(), 1600) <= 1
			and #env.alliesNear(e.GetLocation(), 3500) >= 2
			and not env.nearEnemyTower(e.GetLocation(), 900) then
				tCandidates[#tCandidates + 1] = e
			end
		end
	end

	local best, bestScore = nil, math.huge
	for _, e in ipairs(tCandidates) do
		if env.isValidTarget(e) then
			local nAttackers = 0
			for _, a in ipairs(tAllies) do
				-- compare raw engine handles: GetAttackTarget returns a real
				-- handle, e is a wrapper carrying its handle in .handle
				if a.GetAttackTarget() == e.handle then nAttackers = nAttackers + 1 end
			end
			local fArmor = e.GetArmor()
			local fEffHP = e.GetHealth() / (1 - ((0.06 * fArmor) / (1 + 0.06 * math.abs(fArmor))))
			local score = fEffHP
			if e.IsStunned() or e.IsHexed() or e.IsRooted() or e.IsNightmared() then
				score = score - e.GetMaxHealth() * 0.12
			end
			score = score - nAttackers * e.GetMaxHealth() * 0.08
			if e.GetAttackRange() >= 550 then
				score = score - e.GetMaxHealth() * 0.06
			end
			score = score + env.distToLoc(e, vCentroid) * 0.15
			if score < bestScore then
				best, bestScore = e, score
			end
		end
	end
	return best
end

return M
```

The module uses dot-calls on plain tables (test stubs and the production wrappers from Step 5 both expose that shape); each wrapper carries the real engine handle in `.handle` for identity comparisons and hand-back to callers.

- [ ] **Step 4: Run test to verify it passes**

Run: `luajit tests/test_team_focus.lua`
Expected: `test_team_focus: all assertions passed`

- [ ] **Step 5: Rewire jmz_func.lua**

The module's dot-call style means real Valve handles (colon methods) need a thin adapter. In `bots/FunLib/jmz_func.lua`, replace the whole block from the comment `-- Team focus-fire (roadmap 02)` down to (and including) `function J.ConsiderTeamFocus(bot) ... end` — KEEPING `TOWER_ID_LIST` and `IsNearEnemyTower` (move them ABOVE the new code) — with:

```lua
-- ==============================
-- Team focus-fire (roadmap 02, VM-independent since 2026-08)
-- ==============================
-- Target selection is a deterministic pure function of team-shared game
-- state (bots/FunLib/team_focus.lua): every bot computes the same answer,
-- so no cross-VM shared state is needed. Cached per 3-second bucket.
local TeamFocus = require(GetScriptDirectory()..'/FunLib/team_focus')
local tFocusCache = { bucket = -1, target = nil }

-- team_focus.lua uses dot-calls on plain tables; wrap real handles.
local function _wrapUnit(u)
	return {
		GetLocation = function() return u:GetLocation() end,
		GetArmor = function() return u:GetArmor() end,
		GetHealth = function() return u:GetHealth() end,
		GetMaxHealth = function() return u:GetMaxHealth() end,
		GetAttackRange = function() return u:GetAttackRange() end,
		GetAttackTarget = function() return u:GetAttackTarget() end,
		IsStunned = function() return u:IsStunned() end,
		IsHexed = function() return u:IsHexed() end,
		IsRooted = function() return u:IsRooted() end,
		IsNightmared = function() return u:IsNightmared() end,
		GetUnitName = function() return u:GetUnitName() end,
		handle = u,
	}
end

local function _wrapList(tUnits)
	local t = {}
	for _, u in pairs(tUnits) do
		t[#t + 1] = _wrapUnit(u)
	end
	return t
end

local function TeamFocusEnv()
	return {
		vector = function(x, y) return Vector(x, y, 0) end,
		allies = function()
			local t = {}
			for i = 1, #GetTeamPlayers(GetTeam()) do
				local m = GetTeamMember(i)
				if m ~= nil and m:IsAlive() then t[#t + 1] = _wrapUnit(m) end
			end
			return t
		end,
		alliesNear = function(loc, r) return _wrapList(J.GetAlliesNearLoc(loc, r)) end,
		enemiesNear = function(loc, r)
			local t = {}
			for _, e in pairs(J.GetEnemiesNearLoc(loc, r)) do
				if J.IsValidHero(e) and e:CanBeSeen() and not J.IsSuspiciousIllusion(e) then
					t[#t + 1] = _wrapUnit(e)
				end
			end
			return t
		end,
		isValidTarget = function(w) return not J.CannotBeKilled(nil, w.handle) end,
		nearEnemyTower = function(loc, r) return IsNearEnemyTower(loc, r) end,
		distToLoc = function(w, loc) return GetUnitToLocationDistance(w.handle, loc) end,
		isLaningPhase = function() return J.IsInLaningPhase() end,
	}
end

-- The active called target, or nil if none/invalid. Same signature as the
-- old stored-call version; all call sites unchanged.
function J.GetTeamFocusTarget()
	local iq = GetFightIQ()
	if iq == nil or iq.Team_Focus == false then return nil end
	local nBucket = TeamFocus.Bucket(DotaTime())
	if tFocusCache.bucket ~= nBucket then
		tFocusCache.bucket = nBucket
		local prev = tFocusCache.target
		local w = TeamFocus.Compute(TeamFocusEnv(), iq)
		tFocusCache.target = w ~= nil and w.handle or nil
		if tFocusCache.target ~= nil and tFocusCache.target ~= prev then
			IQDebug('focus target -> '..tFocusCache.target:GetUnitName()
				..' (deterministic, bucket '..nBucket..')')
		end
	end
	local t = tFocusCache.target
	if t == nil or not J.Utils.IsValidUnit(t) or not t:CanBeSeen()
	or J.CannotBeKilled(nil, t) or J.IsSuspiciousIllusion(t) then
		return nil
	end
	return t
end

-- Kept for mode_team_roam_generic.lua:74 — polling warms the bucket cache.
function J.ConsiderTeamFocus(bot)
	J.GetTeamFocusTarget()
end
```

- [ ] **Step 6: Re-run the unit test**

Run: `luajit tests/test_team_focus.lua`
Expected: `test_team_focus: all assertions passed`
(Handle identity works in both worlds: test stubs set `u.handle = u`, production wrappers set `.handle` to the engine handle that `GetAttackTarget()` returns.)

- [ ] **Step 7: Syntax-check the game files**

Run: `luajit -bl bots/FunLib/team_focus.lua > /dev/null && luajit -bl bots/FunLib/jmz_func.lua > /dev/null && echo SYNTAX-OK`
Expected: `SYNTAX-OK`

- [ ] **Step 8: Commit**

```bash
git add bots/FunLib/team_focus.lua tests/test_team_focus.lua bots/FunLib/jmz_func.lua
git commit -m "FightIQ: deterministic VM-independent team focus calls

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

In-game acceptance (next playtest): `[IQ] focus target ->` lines appear, and multiple heroes visibly converge on the named unit.

---

## Final verification (after all tasks)

- [ ] Run every unit test: `luajit tests/test_reactive_fallback.lua && python3 tests/test_server_report.py && luajit tests/test_team_focus.lua` (last one only if Task 7 ran) — all pass.
- [ ] `luajit -bl` on every touched `.lua` file — clean.
- [ ] `git push origin neigh/init-code`.
- [ ] User deploys via `deploy/deploy-to-dota.bat` and plays one game; console shows the new `[IQ]` lines listed in each task's acceptance note.
- [ ] `curl https://dota.sunarjodaniel.xyz/report` returns the fresh balance report after that game completes.
