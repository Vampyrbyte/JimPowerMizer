-- Fishing: a fishing pole in the main hand. On Forever you hold the pole to fish, and every catch
-- needs a new cast, so it isn't idle time (each cast also counts as input for the Idle situation).
local _, ns = ...
local L = ns.L

ns.Engine:RegisterSituation({
	key = "fishing",
	name = L["Fishing"],
	events = { "PLAYER_EQUIPMENT_CHANGED", "PLAYER_ENTERING_WORLD" },
	Evaluate = function()
		return ns.Compat:IsFishingPoleEquipped()
	end,
})
