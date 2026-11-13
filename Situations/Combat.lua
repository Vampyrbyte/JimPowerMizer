-- Combat: always the user's own settings (highest priority).
-- PLAYER_REGEN_DISABLED fires slightly before combat lockdown starts, so track it from the
-- events rather than InCombatLockdown().
local _, ns = ...

local inCombat = false

ns.Engine:RegisterSituation({
	key = "combat",
	name = "Combat",
	events = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD" },
	OnEnable = function()
		inCombat = ns.Compat:IsInCombat()
	end,
	OnEvent = function(event)
		if event == "PLAYER_REGEN_DISABLED" then
			inCombat = true
		elseif event == "PLAYER_REGEN_ENABLED" then
			inCombat = false
		elseif event == "PLAYER_ENTERING_WORLD" then
			inCombat = ns.Compat:IsInCombat()
		end
	end,
	Evaluate = function()
		return inCombat
	end,
})
