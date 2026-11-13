-- Dead or ghost.
local _, ns = ...
local L = ns.L

ns.Engine:RegisterSituation({
	key = "dead",
	name = L["Dead / ghost"],
	events = { "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST" },
	Evaluate = function()
		return ns.Compat:IsDeadOrGhost()
	end,
})
