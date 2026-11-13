-- Idle: the player's AFK flag, or no input for `timeout` seconds.
-- "Input" = moving, casting, the cursor moving, turning, or one of the activity events below.
-- Ends as soon as any input is seen (within the 1 s poll).
local _, ns = ...

local AFK_GRACE = 5 -- with the AFK flag set, wait this long after the last input
local lastActivity = 0
local lastX, lastY, lastFacing

local ACTIVITY_EVENTS = {
	PLAYER_STARTED_MOVING = true, PLAYER_STARTED_TURNING = true, PLAYER_STARTED_LOOKING = true,
	PLAYER_TARGET_CHANGED = true, UNIT_SPELLCAST_SENT = true, LOOT_OPENED = true,
	GOSSIP_SHOW = true, QUEST_DETAIL = true,
	-- Combat counts as activity (and combat outranks idle anyway).
	PLAYER_REGEN_DISABLED = true, PLAYER_REGEN_ENABLED = true,
}
local inCombat = false

local function events()
	local list = {}
	for e in pairs(ACTIVITY_EVENTS) do list[#list + 1] = e end
	list[#list + 1] = "PLAYER_FLAGS_CHANGED"
	return list
end

local function settings()
	return ns.addon.db.profile.situations.idle
end

ns.Engine:RegisterSituation({
	key = "idle",
	name = "Idle",
	events = events(),
	poll = 1,
	OnEnable = function()
		lastActivity = GetTime()
		lastX, lastY, lastFacing = nil, nil, nil
	end,
	OnEvent = function(event)
		if ACTIVITY_EVENTS[event] then lastActivity = GetTime() end
		if event == "PLAYER_REGEN_DISABLED" then inCombat = true
		elseif event == "PLAYER_REGEN_ENABLED" then inCombat = false end
	end,
	Evaluate = function()
		local now = GetTime()
		if inCombat then
			lastActivity = now
			return false
		end
		local moving, casting, x, y, facing = ns.Compat:GetActivitySnapshot()
		local cursorMoved = x ~= nil and lastX ~= nil and (math.abs(x - lastX) > 1 or math.abs(y - lastY) > 1)
		local turned = facing ~= nil and lastFacing ~= nil and math.abs(facing - lastFacing) > 0.01
		lastX, lastY, lastFacing = x, y, facing
		if moving or casting or cursorMoved or turned then lastActivity = now end

		local inactive = now - lastActivity
		if ns.Compat:IsAFK() and inactive >= AFK_GRACE then return true end
		return inactive >= (settings().timeout or 180)
	end,
})

-- For /jpm status.
function ns.IdleSeconds()
	return GetTime() - lastActivity
end
