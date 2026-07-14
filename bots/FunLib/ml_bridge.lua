-- ML Bridge (bots VM side) — intentionally a no-op shim.
--
-- The bot-scripting VM is sandboxed with no working outbound HTTP (verified:
-- both CreateHTTPRequest and CreateRemoteHTTPRequest are unavailable/blocked
-- here, so the bots VM cannot reach an external model server). FightIQ
-- therefore runs fully locally, reading Customize.FightIQ directly in
-- jmz_func's GetFightIQ(). Server-driven live tuning + the bots-VM dataset are
-- not possible from this VM.
--
-- The difficulty director (adaptive difficulty) lives in the ADDON VM
-- (bots/FretBots.lua), which CAN reach the model server, and is unaffected.
--
-- This shim keeps jmz_func's interface intact:
--   GetEffectiveFightIQ() -> nil  (so GetFightIQ falls back to Customize)
--   Think(bot)            -> no-op

local MLBridge = {}

function MLBridge.GetEffectiveFightIQ()
	return nil
end

function MLBridge.Think(bot)
end

return MLBridge
