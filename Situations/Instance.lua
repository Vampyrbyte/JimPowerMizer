-- Dungeons, raids and battlegrounds (arenas count as battlegrounds). By default they're a lockout:
-- your own settings, with a priority above Idle, Long idle and Flight path, so nothing switches
-- inside an instance and no settings change can cause a hitch at a bad moment. Each can be given a
-- graphics profile of its own instead. Scenarios and delves aren't included.
local _, ns = ...
local L = ns.L

local KINDS = {
	{ key = "dungeon", name = L["Dungeon"], types = { party = true } },
	{ key = "raid", name = L["Raid"], types = { raid = true } },
	{ key = "battleground", name = L["Battleground / arena"], types = { pvp = true, arena = true } },
}
local EVENTS = { "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA" }
local lastType = false -- last instance type seen, for the debug line (false = not looked yet)

for i, kind in ipairs(KINDS) do
	ns.Engine:RegisterSituation({
		key = kind.key,
		name = kind.name,
		events = EVENTS,
		Evaluate = function()
			local instanceType = ns.Compat:GetInstanceType()
			if i == 1 and instanceType ~= lastType then
				lastType = instanceType
				ns.addon:Debug("Instance type: %s", tostring(instanceType or "none"))
			end
			return kind.types[instanceType or ""] == true
		end,
	})
end
