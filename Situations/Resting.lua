-- Resting: in an inn or a city.
local _, ns = ...

ns.Engine:RegisterSituation({
	key = "resting",
	name = "Resting (inn / city)",
	events = { "PLAYER_UPDATE_RESTING", "ZONE_CHANGED_NEW_AREA" },
	Evaluate = function()
		return ns.Compat:IsResting()
	end,
})
