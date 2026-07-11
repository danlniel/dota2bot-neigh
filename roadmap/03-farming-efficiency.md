# 3. Farming Efficiency — natural GPM instead of gold bonuses

## Problem

The single biggest reason FretBots needs `gpm/xpm` top-ups: bots waste farm
time. Observable gaps (code: `bots/mode_farm_generic.lua`,
`bots/FunLib/aba_site.lua` — `FindFarmNeutralTarget`, `GetFarmLaneTarget`):

1. **Dead travel time** — after clearing a camp, bots re-evaluate globally and
   often walk across the map instead of chaining to the adjacent camp.
2. **Idle gaps** — between "lane pushed" and "next decision", bots stand still
   for seconds (the idle-state checks in team_roam catch stuck bots, not
   inefficient ones).
3. **No stacking** — bots clear one camp and leave; humans stack on the
   minute mark while passing.
4. **Lane/jungle transitions** — cores sometimes abandon a safe pushed-out
   lane of free creeps to walk to jungle, or vice versa.

## Design (three independent, individually-shippable pieces)

### 3a. Camp chaining
When a farm target dies and the bot is in FARM mode, prefer the nearest
uncleared camp within ~2000 of the current position over a global re-pick.
Implementation: distance-weighted scoring in `FindFarmNeutralTarget` — add a
strong proximity bonus when the bot is already jungling (it currently
re-scores mostly by camp value/safety).

### 3b. Minute-mark stacking
In FARM mode, if game-time is :45–:53 and the bot is within ~1200 of a camp
it can stack (camp table exists in `aba_site`), attack-move through the camp
and pull toward the next farm target. Ship for cores' own triangle first;
support stacking-for-cores is a stretch goal.

### 3c. Idle elimination
Add a farm-mode watchdog: if a bot in FARM/PUSH mode has issued no attack
order for >2.5s and no enemy is near, force-target the nearest last-hittable
creep/camp. Piggyback on the existing `J.CheckBotIdleState` plumbing in
team_roam rather than a new timer.

## Config

```lua
Customize.FarmIQ = {
    Enable = true,
    Chain_Camps = true,
    Stack_Camps = true,
    Idle_Watchdog = true,
}
```

## Measurement (this one is quantifiable)

Add `last_hits` + `gpm` per bot to the `/policy` snapshot (see roadmap 04).
Success = bot cores' natural GPM (bonuses excluded — FretBots logs its awards)
rises 15%+ at the 15-minute mark across a few games, letting `gpm` clamps in
`SettingsDefault.lua` come down equivalently.

## Risks

- Farming bots ignoring fights: all three pieces only apply inside FARM mode;
  mode desires (team_roam/defend/retreat) still preempt as before.
- Stacking griefs a human jungler: only stack camps no human is near (~1500).
- `aba_site` is 54KB of load-bearing map logic — changes must be additive
  scoring bonuses, not rewrites of the target-selection flow.
