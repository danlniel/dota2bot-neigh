# Dota 2 Bot Scripts - Claude Code Guide

## THIS IS A FORK: read docs/FORK_KNOWLEDGE.md first

`dota2bot-neigh` is a fork of OpenHyperAI. Work on branch `neigh/init-code`.
Bot difficulty comes from **decision quality** (`Customize.FightIQ` / `ItemIQ` /
`FarmIQ` / `LaneIQ` / `DraftIQ`), not FretBots stat boosts. An Orange Pi server
steers difficulty adaptively. **[docs/FORK_KNOWLEDGE.md](docs/FORK_KNOWLEDGE.md)**
has the systems map, hard constraints, server and deploy details, and how to test.

Non-negotiables (details in that file):
- **Bots VM has no HTTP.** Only FretBots (addon VM) can reach the server.
- **Coordinate deterministically.** Every bot computes the same answer from
  shared game state. Don't rely on other bots' Lua fields.
- **Lua 5.1.** Check with `luajit -bl <file>`. Run `for t in tests/*.lua; do luajit "$t"; done`.
- **Know the helper semantics.** `J.GetHP` is a fraction. `J.HasItem` checks the
  main six slots only. A must-have item goes to the front of the purchase queue,
  not into a lump-sum "buy at full gold" check.
- **TS drift.** `Customize/general.lua`, `aba_push.lua`, `aba_site.lua` and
  `aba_role.lua` have fork edits in the Lua only. Edit the Lua directly, and
  never run the TSTL build without first porting those edits to `typescript/`.
- **Never merge `upstream/pr-140-refactor` or other wholesale upstream rewrites.**
  Cherry-pick individual fixes.
- **Shipping behavior changes:** bump the build date in the `jmz_func.lua`
  `IQDebug` load line and the `FretBots.lua` banner. Then push, because the
  gaming PC deploys via `git pull`.

## Project Overview

This is the **dota2bot-OpenHyperAI** project -- Lua bot scripts for Dota 2 that run in custom lobbies. Currently supports Patch 7.41f (7.41b–f audited 2026-10-23) with 127 heroes.

## Key Documentation

- **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** -- Complete codebase architecture, file map, naming conventions, all systems explained
- **[docs/PATCH_UPDATE_GUIDE.md](docs/PATCH_UPDATE_GUIDE.md)** -- Step-by-step runbook for updating when a new Dota 2 patch drops

**Read these docs FIRST before making any changes.** They contain everything needed to make targeted updates without scanning the entire repo.

## Common Tasks

### Check for New Patches

To check if there are patches we haven't updated for:
1. Fetch `https://www.dota2.com/datafeed/patchnoteslist?language=english`
2. Compare latest version against "Last updated for" in `docs/PATCH_UPDATE_GUIDE.md`
3. If newer patch exists, follow the update process below

### Patch Update (most common)

When user says "update for patch X.XX" or provides patch notes:

1. Read `docs/PATCH_UPDATE_GUIDE.md` for the step-by-step process
2. Fetch patch data: `https://www.dota2.com/datafeed/patchnotes?version=X.XX&language=english`
3. Fetch d2vpkr data (shops.txt, neutral_items.txt) for authoritative item/ability names
4. **Categorize changes**: STRUCTURAL (need code) vs NUMBER-ONLY (game API handles) vs TALENT SWAPS
5. **Always verify ability names on Liquipedia** -- patch note summaries can be wrong
6. Follow the checklist in order: items -> hero builds -> abilities -> neutrals -> actives -> map changes
7. **Always update TS sources** for any TS-generated Lua files changed (see ARCHITECTURE.md Section 13)

### Add a New Hero

1. Copy a similar existing hero from `bots/BotLib/` as template
2. Add to `FretBots/HeroNames.lua`, `FunLib/aba_hero_roles_map.lua`, `FunLib/spell_list.lua`
3. See "New Heroes" section in `docs/PATCH_UPDATE_GUIDE.md`

### Fix a Hero's Item Build

1. Read `bots/BotLib/hero_[name].lua`
2. Edit the `sRoleItemsBuyList['pos_N']` arrays
3. Items use `item_[internal_name]` format -- check `FunLib/aba_item.lua` for valid names

### Fix a Hero's Ability Logic

1. Read `bots/BotLib/hero_[name].lua`
2. The `SkillsComplement()` function controls ability casting priority
3. Each ability has a `ConsiderX()` function returning desire + target
4. See "Skill / Ability System" in `docs/ARCHITECTURE.md`

## Important Rules

- **Use `GetItemComponents()` for item recipes** -- don't hardcode component arrays
- **Use `sAbilityList[N]` references** when possible -- resilient to ability renames
- **Always update BOTH neutral item files** (Buff/ AND FretBots/)
- **Verify on Liquipedia** before trusting patch note summaries about ability names
- **Test in-game** after changes -- some things can only be verified at runtime
