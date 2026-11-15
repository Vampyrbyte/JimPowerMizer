-- Flight path (taxi) situation: on a flight path, and after landing until you do something
-- (move your character, cast a spell, or enter combat), so an unattended flight keeps saving
-- power until you're back.
-- Events catch the start quickly; the 2 s poll is a fallback because UnitOnTaxi isn't always
-- true yet when PLAYER_CONTROL_LOST fires.
local _, ns = ...
local L = ns.L

local MOVE_POLL_DELAY = 1 -- after landing, ignore a polled "moving" this long (landing settle)
local landed = false      -- flew and landed, no input since
local landedAt = 0

ns.Engine:RegisterSituation({
	key = "taxi",
	name = L["Flight path"],
	events = { "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED", "TAXIMAP_CLOSED", "PLAYER_ENTERING_WORLD",
		"PLAYER_STARTED_MOVING", "UNIT_SPELLCAST_SENT", "PLAYER_REGEN_DISABLED" },
	poll = 2,
	OnEnable = function()
		landed = false
	end,
	OnEvent = function(event)
		if event == "PLAYER_STARTED_MOVING" or event == "UNIT_SPELLCAST_SENT" or event == "PLAYER_REGEN_DISABLED" then
			if landed then ns.addon:Debug("Flight path: input after landing (%s)", event) end
			landed = false
		end
	end,
	Evaluate = function()
		if ns.Compat:IsOnTaxi() then
			landed, landedAt = true, GetTime()
			return true
		end
		if landed and GetTime() - landedAt >= MOVE_POLL_DELAY then
			-- Fallback for a missed STARTED_MOVING: the poll says the character is moving.
			if ns.Compat:GetActivitySnapshot() then landed = false end
		end
		return landed
	end,
})
