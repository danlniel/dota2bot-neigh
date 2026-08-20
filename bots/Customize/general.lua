--[[
This is a place for you to customize the Open Hyper AI bots.

1. When modiftying this file, be VERY careful to the spelling, punctuation and variable names - it's very easy to cause 
   syntax errors and mess up the entire logic for all bots, and could be hard for you to debug.
2. In the case you saw the bots having some random names or picks (heroes not what you have set or without "OHA" name suffix), 
   that means you had made some mistakes/errors while modifying this file. 
3. In any case this file got messed up and caused the bots to malfunction, you can try to restore the file. Either you have a 
   copy to replace, or resubscribe the script, or download from github.
4. To avoid these customize files from getting overridden by workshop updates, you can copy 
   the entire Customize folder to under: <Steam\steamapps\common\dota 2 beta\game\dota\scripts\vscripts\game>
   and then modify the settings in <Steam\steamapps\common\dota 2 beta\game\dota\scripts\vscripts\game\Customize> directory.
5. Note there is a list of known to-be-improved (aka weak) heroes, check out [Appendix - 2] on the bottom of this file.

- Workshop: https://steamcommunity.com/sharedfiles/filedetails/?id=3246316298
- Github: https://github.com/forest0xia/dota2bot-OpenHyperAI
--]]


-- The variable to hold the settings. Only modify if you know exactly what you are doing.
local Customize = { }

-- Set it to true to turn on ALL of the custom settings in this file, or set it to false to turn off the settings.
Customize.Enable = true

-- Set the localization code to make bots speak the specific language when possible (not guaranteed to 100% localized). 
-- Currently supprot: "en" for "English", "zh" for "中文", "ru" for Russian, "ja" for Japanese
-- https://en.wikipedia.org/wiki/List_of_ISO_639_language_codes
Customize.Localization = "en"

-- To ban some heroes for bots - Set the heroes you DO NOT want the bots to pick. Use hero internal names.
-- Hero name ref: https://github.com/forest0xia/dota2bot-OpenHyperAI/discussions/71
-- Please note that it is not 100% guaranteed that the banned hero will not be picked; for example if you banned too many heroes 
-- like near 100% of the heroes, bots will need to randomly pick heroes regardless of the ban list to continue the game.
Customize.Ban = {
    'example_npc_dota_hero_internal_name_to_ban',
}

--[[
1. To pick heroes for the Radiant bots. You have to use hero's internal name.
2. Hero internal name ref: https://github.com/forest0xia/dota2bot-OpenHyperAI/discussions/71
3. Don't need to provide a value for all 5 bots, any empty/missing value will fallback to a Random value.
4. The position is ranked by the order of the names you put in the below list, pos 1 - 5, from top to down.
5. There are sample team picks in Appendix section below. 
6. Check Appendix to ensure you DO NOT pick more than 1 "weak" heroes in a team for your game experience.
--]]
Customize.Radiant_Heros = {
    'Random',
    'Random',
}

-- Same notes as above for picking heroes but for the Dire side.
Customize.Dire_Heros = {
    'Random',
}

--[[
1. To allow bots to randomly pick heroes that can be the same/repeated. 
2. WARNING: Setting this to true CAN reduce the gaming experience due to the fact some heroes are kind of weak or buggy
   at the moment (listed below) and are intentionally having reduced chances to get picked by bots. Setting this to true
   may cause the bots to pick multiple weak heroes. See Appendix below about "weak" heroes.
--]]
Customize.Allow_Repeated_Heroes = false

-- The max number of weak heroes allowed in a team the bots can pick.
-- Note: 0 blocks weak-listed heroes entirely, INCLUDING human `!pick` commands
-- and preset lineups (the cap check is `count >= cap`, and 0 >= 0 always).
-- Keep at 1 to limit bots to one weak hero while leaving human picks working.
Customize.Weak_Hero_Cap = 1

-- The weak penalty curve for bots picking weak heroes:
--   { type="linear", k=0.25 }         ->  penalty = max(0, 1 - k * (weakPicked/cap))
--   { type="quad",   k=1.0 }          ->  penalty = (1 - min(1, weakPicked/cap))^2
--   { type="exp",    base=0.6 }       ->  penalty = base^(weakPicked)  (more weak -> smaller)
Customize.Weak_Penalty = { type = "exp", base = 0.6 }

-- Exact match on unit names by default; set Customize.Strict_Ban_Match = false to allow guarded substring matches (length ≥ 6).
Customize.Strict_Ban_Match = true

-- To allow bots do trash talking in different scenarios: got fb, killing a human, etc. Disable this also disables GPT chat.
Customize.Allow_Trash_Talk = true

-- To allow bots response with GPT generated text to your chats in global channel. Disable Allow_Trash_Talk can disable this.
Customize.Allow_AI_GPT_Response = true

-- Set the level of bots' trash talks. Disable Allow_Trash_Talk can disable this.
-- 1 => no trash talks from ally bots, no taunt from enemy after it gets a kill. 2 => ally bots also trash talk to you, allow taunt from enemy after it gets a kill.
Customize.Trash_Talk_Level = 3

-- To set the names for the Radiant bots. Don't need to provide a value for all 5 bots, missing names will have a Random value.
Customize.Radiant_Names = {
    'Random',
    'Random',
}

-- Same notes as above for setting the bots' names but for the Dire side.
Customize.Dire_Names = {
    'Random',
}

-- The desire level that the bots will group up and push the same lane.
-- 1 is mild meaning bots will group up only when convenient; 3 is bots will almost always try to push together.
-- Group pushing may increase the difficulty but can reduce the game experience.
Customize.Force_Group_Push_Level = 2

-- The Enhanced Fretbots mode settings:
-- For more about Fretbots mode: https://github.com/forest0xia/dota2bot-OpenHyperAI/discussions/68
-- Note: these settings below will override the pre-defind settings in Fretbots folder.
Customize.Fretbots = {
    -- ADAPTIVE MODE: difficulty is managed automatically by the ML director
    -- (see Customize.ML below). This value is only the starting point; the
    -- director steers it up/down during the game to keep matches close.
    -- If the ML server is unreachable, the game stays at this value and
    -- FretBots' built-in rubber-band (dynamicDifficulty) still applies.
    Default_Difficulty = 5,

    -- Ally bots get the same treatment as enemy bots (fair teams).
    Default_Ally_Scale = 1,

    -- Voting allowed: a chat vote (0-10 at game start) picks the STARTING
    -- difficulty; the ML director still adapts from there during the game.
    -- No vote -> starts at Default_Difficulty above.
    Allow_To_Vote = true,

    -- Set to false disables all sounds from Fretbots mode
    Play_Sounds = true,

    -- Set to play chatwheel taunt sounds when human player died
    Player_Death_Sound = true,
}

-- Make bots think less, 0: fully think through, 1 to 10: think less and less frequently.
-- Bots can become slow or dumb in reaction and decision making if you set this value to a higher number.
-- When doing Local Host, you can potentially improve PC performance (FPS) by setting this to 1 to 10, which sacrifices some bot IQ/performance.
-- This won't be very effective for FPS improvement because Valve has a lot of compute on their side that your PC have to handle for Local Hosting.
Customize.ThinkLess = 0;

-- Fight IQ: make bots smarter in fights via decision quality instead of Fretbots stat bonuses.
-- All values have safe defaults; set Enable = false to restore original behavior.
Customize.FightIQ = {
    Enable = true,

    -- Print throttled '[IQ] ...' lines to the game console whenever a FightIQ /
    -- ItemIQ feature fires (kite detection, team focus calls, smoke-ganks,
    -- reactive item buys). Launch Dota with -condebug to also get them in
    -- console.log. Set false once satisfied the features work.
    Debug = true,

    -- Bots only commit to fights when their estimated team power exceeds the enemy's by this ratio.
    -- 1.0 = original coin-flip (dives everything); higher = pickier, only fights it's winning.
    -- 1.10 = disciplined: refuses even/losing fights (harder to beat), still commits when ahead.
    -- Dial to taste: raise toward 1.15 for more cautious bots, lower toward 1.03 for aggressive.
    -- Note: fog awareness already adds situational caution when enemies are missing.
    Commit_Margin = 1.10,

    -- Team power weighting for ultimate availability (heroes level 6+ with a non-passive ultimate).
    -- Ready ultimates swing fights; a hero with ult on cooldown is worth less in a fight.
    Ult_Ready_Bonus = 1.12,
    Ult_Down_Penalty = 0.88,

    -- Enemies that are currently disabled (stunned/hexed/nightmared/taunted) count this much
    -- toward enemy team power. Lower = bots punish picked-off or disabled targets harder.
    Disabled_Power_Scale = 0.6,

    -- Focus fire: prefer targets that allies are already attacking, that are disabled,
    -- and judge "weakest" by armor-adjusted effective HP instead of raw HP.
    Focus_Fire = true,

    -- Fog awareness: alive-but-unseen enemies whose last known position is close
    -- count toward enemy power, so bots stop diving into fog (missing = danger).
    Fog_Awareness = true,
    Fog_Recent_Seconds = 10,   -- full threat weight if seen this recently
    Fog_Decay_Seconds = 25,    -- no weight beyond this many seconds unseen
    Fog_Near_Distance = 3000,  -- last-seen distance (to the bot) that counts

    -- Team focus-fire: during teamfights the team captain "calls" one kill
    -- target and all bots' targeting converges on it (bonus, not override).
    Team_Focus = true,
    Team_Focus_Window = 6,     -- seconds a call stays active
    Team_Focus_Bonus = 0.25,   -- targeting bonus as a fraction of target max HP

    -- Group hunting: outside teamfights, bots call isolated enemies and
    -- converge to pick them off together (never under enemy towers).
    Team_Hunt = true,

    -- Smoke-gank: when a pick-off target is called and the grouped team is a
    -- rotation away, use Smoke of Deceit to approach it unseen.
    Smoke_Gank = true,

    -- Back off when deep in enemy territory alone while 2+ enemies are
    -- unaccounted for (the classic gank setup). Applies to camp selection
    -- and retreat desire — bots stop feeding solo pickoffs.
    Avoid_Deep_Solo = true,

    -- Kill lead at which the team plays like it's winning: deep-solo caution
    -- switches off and bots start farming/invading the ENEMY jungle.
    Dominance_Kill_Lead = 6,

    -- Buyback awareness: don't dive enemy rax/ancient into a full set of
    -- buybacks. Enemy buyback is estimated (their gold isn't queryable): a
    -- dead enemy core is treated as a likely defender past Buyback_Min_Time.
    Buyback_Awareness = true,
    Buyback_Min_Time = 15,   -- minutes; before this, buyback rarely matters

    -- Anti long-range (e.g. Sniper): when out-ranged and unable to reach the
    -- attacker, break away instead of tanking free hits; and prioritize
    -- squishy long-range backliners as kill targets.
    Avoid_Long_Range = true,
    Long_Range_Margin = 150,  -- enemy must out-range us by this much to trigger

    -- Power-spike timing: right after a teammate hits a level breakpoint
    -- (6/12/18/25) or completes a fight-defining item, bots look for fights
    -- and objectives (relaxed commit margin + higher push ceiling).
    Power_Spike = true,
    Power_Spike_Window = 25,         -- seconds the aggression window lasts
    Power_Spike_Margin_Scale = 0.9,  -- commit margin multiplier during window
}

-- Farm IQ: make bots farm like players so their gold is earned, not injected.
Customize.FarmIQ = {
    Enable = true,

    -- While clearing a camp near the minute mark, drag the creeps out of the
    -- spawn box so the camp respawns stacked (skipped if a human is nearby).
    Stack_Camps = true,

    -- Supports head to the nearest stackable camp during the stack window
    -- (:50-:58) even if not farming it, covering several camps over the game.
    Multi_Stack = true,

    -- When there is nothing to farm, walk to the nearest safe lane front and
    -- take free creeps instead of idling toward the middle of the map.
    Lane_Fallback = true,
}

-- Lane IQ: laning-phase creep control.
Customize.LaneIQ = {
    -- Freeze / anti-overpush: when healthy and pushing the wave, hang back an
    -- extra margin so the lane freezes on our side instead of shoving under the
    -- enemy tower. Only affects idle positioning (never last-hit/deny).
    Freeze_When_Ahead = true,
    Freeze_Pullback = 250,   -- extra units to hold back when freezing
}

-- Draft IQ: on top of the existing counter-pick/synergy scoring, reward
-- candidates that fill a team-comp hole (lockdown/initiation/magic/physical).
Customize.DraftIQ = {
    Enable = true,
    Comp_Completeness = true,
}

-- Item IQ: reactive itemization on top of each hero's static build. Buys a
-- situational defensive item when the enemy threat calls for it (only when
-- fully affordable, so it never stalls the main build).
Customize.ItemIQ = {
    Enable = true,
    -- vs physical right-click / long range (Sniper/Drow/PA): squishy heroes
    -- grab Ghost Scepter, durable cores grab Blade Mail.
    Anti_Physical = true,
    -- vs 2+ magic nukers early: squishy heroes grab a cheap Cloak.
    Anti_Magic = true,
    -- cores buy BKB vs heavy enemy disable/magic (mid-game+).
    Anti_Disable = true,
    -- when behind vs magic: durable heroes grab Pipe, supports grab Glimmer.
    Team_Defense = true,
    -- vs long-range kiters with no blink: grab a Force Staff to close/escape.
    Gap_Close = true,
    -- proactive: if the enemy DRAFTED a long-range menace (Sniper/Drow/
    -- Clinkz, or any seen enemy with 620+ attack range), cores pre-arm a
    -- gap-close by minute 10 instead of waiting to be kited: ranged cores
    -- buy Hurricane Pike, melee cores buy Force Staff.
    Proactive_Gap_Close = true,
}

-- ML integration: connect the bots to a local model server (see ml/README.md).
-- Run `python3 ml/server.py` before the game; without a server the bridge
-- disables itself after a few attempts and static settings apply.
Customize.ML = {
    Enable = true,

    -- Model server address. NOTE: https works for the FretBots side
    -- (difficulty director) but has NOT worked for the bots-VM bridge
    -- (FightIQ tuning + dataset) in practice — always provide a plain-http
    -- Server_Fallback; the bridge switches to it automatically when the
    -- primary fails.
    Server = 'https://dota.sunarjodaniel.xyz',

    -- Plain-http fallback for the bots-VM bridge (LAN address of the server).
    Server_Fallback = 'http://192.168.18.200:5544',

    -- Optional API key, must match the server's ML_API_KEY. Empty = no auth.
    Api_Key = '',

    -- Seconds between game-state snapshots from the bots VM (FightIQ tuning + dataset).
    Snapshot_Interval = 6,

    -- Seconds between FretBots director updates (adaptive difficulty).
    -- Difficulty changes are additionally rate-limited server-side
    -- (one step per ~60s, two agreeing readings required).
    Director_Interval = 10,

    -- Allow the server to change FretBots difficulty mid-game (rubber-band by model).
    Allow_Difficulty_Control = true,
}

return Customize




--[[

----------------------------------------------------------------------------------------------------
|                                        --- Appendix ---                                          |
----------------------------------------------------------------------------------------------------

[Appendix - 1] -- Some sample team picks: --

    -- -- All Pudges
    -- "npc_dota_hero_pudge",
    -- "npc_dota_hero_pudge",
    -- "npc_dota_hero_pudge",
    -- "npc_dota_hero_pudge",
    -- "npc_dota_hero_pudge",

    -- -- All Spirits/Pandas
    -- "npc_dota_hero_void_spirit",
    -- "npc_dota_hero_storm_spirit",
    -- "npc_dota_hero_ember_spirit",
    -- "npc_dota_hero_brewmaster",
    -- "npc_dota_hero_earth_spirit",

    -- -- Traditional -- --
    -- "npc_dota_hero_chaos_knight",
    -- "npc_dota_hero_sniper",
    -- "npc_dota_hero_axe",
    -- "npc_dota_hero_zuus",
    -- "npc_dota_hero_warlock",

    -- -- Rubick mid, and good team fights -- --
    -- "npc_dota_hero_clinkz",
    -- "npc_dota_hero_rubick",
    -- "npc_dota_hero_enigma",
    -- "npc_dota_hero_earth_spirit",
    -- "npc_dota_hero_techies",

    -- -- Invoker mid, and good team fights -- --
    -- "npc_dota_hero_arc_warden",
    -- 'npc_dota_hero_invoker',
    -- "npc_dota_hero_enigma",
    -- "npc_dota_hero_nyx_assassin",
    -- "npc_dota_hero_zuus",


[Appendix - 2] -- List of to-be-improved (aka weak) heroes, as of 2024/10/20 --

    They are relatively weaker than others and can still get selected by bots, 
    but there SHOULD NOT have more than 1 of those in a team to ensure the bar of gaming experience for human players.

    Those are weak due to:
        1, Some have bugs from Valve side, which I've spent a lot of effrot with to improve and fix things. 
        2, It's not easy to implement the hero in a good way in terms of doing it via coding with the code base we have.
        3, I do not play some of those heroes a lot myself so can't make good bots, 

    It's a matter of time to get everything improved, but I don't have a lot of time to do everything to make bots better. 
    So I put them here, and hopefully make it easy for you to use, or learn, or improve the script. 
    I'd appreciate any actual help from you to make the bots better, and I'm certain we can achieve it by contributing together.

    -- -- List A. Weak ones, meaning they are too far from being able to apply their power:
        'npc_dota_hero_chen',
        'npc_dota_hero_keeper_of_the_light',
        'npc_dota_hero_winter_wyvern',
        'npc_dota_hero_ancient_apparition',
        'npc_dota_hero_phoenix',
        'npc_dota_hero_tinker',
        'npc_dota_hero_pangolier',
        'npc_dota_hero_tusk',
        'npc_dota_hero_morphling',
        'npc_dota_hero_visage',
        'npc_dota_hero_void_spirit',
        'npc_dota_hero_pudge',
        'npc_dota_hero_ember_spirit',

    -- -- List B. Buggy ones, meaning they have bugs on Valves side:
        'npc_dota_hero_muerta',
        'npc_dota_hero_marci',
        'npc_dota_hero_lone_druid',
        'npc_dota_hero_primal_beast',
        'npc_dota_hero_dark_willow',
        'npc_dota_hero_elder_titan',
        'npc_dota_hero_hoodwink',
        'npc_dota_hero_wisp',
]]--
