-- Flight path (taxi) situation.
-- Events catch the start/end quickly; the 2 s poll is a fallback because UnitOnTaxi isn't always
-- true yet when PLAYER_CONTROL_LOST fires.
local _, ns = ...

ns.Engine:RegisterSituation({
	key = "taxi",
	name = "Flight path",
	events = { "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED", "TAXIMAP_CLOSED", "PLAYER_ENTERING_WORLD" },
	poll = 2,
	Evaluate = function()
		return ns.Compat:IsOnTaxi()
	end,
})
