-- Idle: the player's AFK flag, or no input for `timeout` seconds.
--
-- Input = moving your character, casting, changing target, looting, talking to an NPC, combat.
-- Movement comes from PLAYER_STARTED/STOPPED_MOVING, which only fire for your own movement, not
-- when a ship or zeppelin carries you (polled speed and facing do change on a transport).
-- Mouse and camera movement (cursor, facing, mouselook, turning) only count if the idle option
-- `mouseActivity` is on.
local _, ns = ...
local L = ns.L

local AFK_GRACE = 5 -- with the AFK flag set, wait this long after the last input
local lastActivity = 0
local lastX, lastY, lastFacing
local inCombat = false
local movingByInput = false -- between PLAYER_STARTED_MOVING and PLAYER_STOPPED_MOVING

-- Event -> activity name (for the debug line).
local ACTIVITY_EVENTS = {
	PLAYER_TARGET_CHANGED = "target", UNIT_SPELLCAST_SENT = "casting", LOOT_OPENED = "looting",
	GOSSIP_SHOW = "NPC", QUEST_DETAIL = "quest",
	-- Combat counts as activity (and combat outranks idle anyway).
	PLAYER_REGEN_DISABLED = "combat", PLAYER_REGEN_ENABLED = "combat",
}
local CAMERA_EVENTS = { PLAYER_STARTED_TURNING = "turning", PLAYER_STARTED_LOOKING = "camera" }

local function settings()
	return ns.addon.db.profile.situations.idle
end

local function events()
	local list = { "PLAYER_FLAGS_CHANGED", "PLAYER_STARTED_MOVING", "PLAYER_STOPPED_MOVING", "PLAYER_ENTERING_WORLD" }
	for e in pairs(ACTIVITY_EVENTS) do list[#list + 1] = e end
	for e in pairs(CAMERA_EVENTS) do list[#list + 1] = e end
	return list
end

-- Record input. Logs (debug) what ended an idle period, or input after a long quiet spell.
local function activity(what, now)
	now = now or GetTime()
	if now - lastActivity >= 10 then
		ns.addon:Debug("Idle: input (%s) after %ds", what, math.floor(now - lastActivity))
	end
	lastActivity = now
end

ns.Engine:RegisterSituation({
	key = "idle",
	name = L["Idle"],
	events = events(),
	poll = 1,
	OnEnable = function()
		lastActivity = GetTime()
		lastX, lastY, lastFacing = nil, nil, nil
		movingByInput = false
	end,
	OnEvent = function(event)
		if event == "PLAYER_STARTED_MOVING" then
			movingByInput = true
			activity("moving")
		elseif event == "PLAYER_STOPPED_MOVING" or event == "PLAYER_ENTERING_WORLD" then
			movingByInput = false
		elseif ACTIVITY_EVENTS[event] then
			activity(ACTIVITY_EVENTS[event])
		elseif CAMERA_EVENTS[event] and settings().mouseActivity then
			activity(CAMERA_EVENTS[event])
		end
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
		-- A missed STOPPED_MOVING mustn't block idle forever: "not moving" from the poll is reliable.
		if movingByInput and not moving then movingByInput = false end
		if movingByInput then
			lastActivity = now -- still running: no log line every second
		elseif casting then
			activity("casting", now)
		elseif settings().mouseActivity then
			local cursorMoved = x ~= nil and lastX ~= nil and (math.abs(x - lastX) > 1 or math.abs(y - lastY) > 1)
			local turned = facing ~= nil and lastFacing ~= nil and math.abs(facing - lastFacing) > 0.01
			if cursorMoved then activity("mouse", now) elseif turned then activity("turning", now) end
		end
		lastX, lastY, lastFacing = x, y, facing

		local inactive = now - lastActivity
		if ns.Compat:IsAFK() and inactive >= AFK_GRACE then return true end
		return inactive >= (settings().timeout or 180)
	end,
})

-- For /jpm status.
function ns.IdleSeconds()
	return GetTime() - lastActivity
end
