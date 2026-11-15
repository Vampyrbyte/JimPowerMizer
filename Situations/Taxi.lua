-- Flight path (taxi) situation: on a flight path, and after landing until you do something, so an
-- unattended flight keeps saving power until you're back.
-- "Something" is moving your character, casting or entering combat (at once), or any other input
-- by the Idle situation's rules (targeting, looting, talking to an NPC, ...; see Idle.lua) once
-- the landing has settled.
-- Events catch the start quickly; the poll is a fallback because UnitOnTaxi isn't always true yet
-- when PLAYER_CONTROL_LOST fires.
local _, ns = ...
local L = ns.L

local MOVE_POLL_DELAY = 1 -- after landing, ignore a polled "moving" this long (landing settle)
-- Idle's input clock only counts this long after the last moment we saw you on the flight: the
-- landing itself changes polled values (e.g. facing, with Idle's mouse option on).
local INPUT_SETTLE = 2
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
		-- Idle (registered first, so already up to date in this pass) saw input since the landing.
		if landed and ns.LastInputTime and ns.LastInputTime() >= landedAt + INPUT_SETTLE then
			ns.addon:Debug("Flight path: input after landing")
			landed = false
		end
		return landed
	end,
})
