-- Fishing. Which rule applies is the client's (ns.Compat:FishesByChannel()):
--  * Forever: a fishing pole in the main hand. You hold the pole to fish, and every catch needs a
--    new cast, so it isn't idle time (each cast also counts as input for the Idle situation).
--  * Midnight: the pole sits in a profession slot, so it's channeling Fishing, then a short grace
--    period so looting and casting again doesn't switch graphics back and forth. Moving your
--    character ends the grace period early.
local _, ns = ...
local L = ns.L

local channeling = false
local graceUntil = 0

local function settings()
	return ns.addon.db.profile.situations.fishing
end

ns.Engine:RegisterSituation({
	key = "fishing",
	name = L["Fishing"],
	events = { "PLAYER_EQUIPMENT_CHANGED", "PLAYER_STARTED_MOVING", "PLAYER_ENTERING_WORLD" },
	poll = 1, -- ends the grace period on time; also a fallback for a missed cast event
	OnEnable = function()
		channeling, graceUntil = false, 0
	end,
	OnEvent = function(event)
		if event == "PLAYER_STARTED_MOVING" then graceUntil = 0 end
	end,
	Evaluate = function()
		if not ns.Compat:FishesByChannel() then
			return ns.Compat:IsFishingPoleEquipped()
		end
		local now = GetTime()
		if ns.Compat:IsFishingChannel() then
			channeling, graceUntil = true, 0
			return true
		end
		if channeling then
			-- The cast just ended (a catch, the bobber timed out, or interrupted by moving).
			channeling = false
			local moving = ns.Compat:GetActivitySnapshot()
			if not moving then graceUntil = now + (settings().grace or 10) end
		end
		return now < graceUntil
	end,
})

-- For /jpm list: seconds of grace left, or nil.
function ns.FishingGraceLeft()
	local left = graceUntil - GetTime()
	return left > 0 and left or nil
end
