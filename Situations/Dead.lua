-- Dead or ghost.
local _, ns = ...

ns.Engine:RegisterSituation({
	key = "dead",
	name = "Dead / ghost",
	events = { "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST" },
	Evaluate = function()
		return ns.Compat:IsDeadOrGhost()
	end,
})
