-- Delve: only on clients that have delves (Midnight and other Standard clients); Forever and the
-- Classic clients don't, so the situation doesn't exist there. Like the other instances it's a
-- lockout by default: your own settings, priority above Idle, Long idle and Flight path.
local _, ns = ...
local L = ns.L

local last -- last state seen, for the debug line

ns.Engine:RegisterSituation({
	key = "delve",
	name = L["Delve"],
	events = { "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA" },
	IsAvailable = function()
		return ns.Compat:HasDelves()
	end,
	Evaluate = function()
		local inDelve, difficultyID = ns.Compat:IsInDelve()
		local now = tostring(inDelve) .. "/" .. tostring(difficultyID)
		if difficultyID and now ~= last then
			ns.addon:Debug("Scenario difficulty %s: %s", tostring(difficultyID), inDelve and "a delve" or "not a delve")
		end
		last = now
		return inDelve
	end,
})
