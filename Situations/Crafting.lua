-- Crafting: casting a profession spell, then a short grace period so a follow-up craft doesn't
-- switch graphics back and forth. Having the profession window open doesn't count on its own.
-- The grace period ends early when you move your character, or close the profession window
-- (if it was open during the craft; crafts from a macro with the window closed keep their grace).
local _, ns = ...
local L = ns.L

local casting = false
local graceUntil = 0
local windowDuringCraft = false -- profession window open while crafting
local movedDuringCraft = false

local function settings()
	return ns.addon.db.profile.situations.crafting
end

ns.Engine:RegisterSituation({
	key = "crafting",
	name = L["Crafting"],
	events = { "PLAYER_STARTED_MOVING", "PLAYER_ENTERING_WORLD" },
	poll = 1, -- ends the grace period on time; also a fallback for a missed cast event
	OnEnable = function()
		casting, graceUntil, windowDuringCraft, movedDuringCraft = false, 0, false, false
	end,
	OnEvent = function(event)
		if event == "PLAYER_STARTED_MOVING" then
			graceUntil = 0
			if casting then movedDuringCraft = true end
		end
	end,
	Evaluate = function()
		local now = GetTime()
		local windowOpen = ns.Compat:IsProfessionWindowOpen()
		if ns.Compat:IsCraftingCast() then
			if not casting then
				casting, windowDuringCraft, movedDuringCraft = true, false, false
			end
			if windowOpen then windowDuringCraft = true end
			graceUntil = 0
			return true
		end
		if casting then
			-- The craft just ended (finished, or interrupted by moving).
			casting = false
			local moving = ns.Compat:GetActivitySnapshot()
			if not (moving or movedDuringCraft) then
				graceUntil = now + (settings().grace or 10)
			end
		end
		if windowDuringCraft and not windowOpen then graceUntil = 0 end
		return now < graceUntil
	end,
})

-- For /jpm list: seconds of grace left, or nil.
function ns.CraftingGraceLeft()
	local left = graceUntil - GetTime()
	return left > 0 and left or nil
end
