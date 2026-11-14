-- Slash commands: /jpm
local _, ns = ...
local L = ns.L

local JPM = ns.addon

local HELP = {
	L["|cffffd200/jpm|r - open the options window"],
	L["|cffffd200/jpm status|r - show the current state"],
	L["|cffffd200/jpm on|r / |cffffd200off|r - enable or disable automatic switching"],
	L["|cffffd200/jpm restore|r - restore your graphics settings now"],
	L["|cffffd200/jpm list|r - list situations, their settings and whether they're active"],
	L["|cffffd200/jpm enable <situation>|r / |cffffd200disable <situation>|r - turn a situation on or off"],
	L["|cffffd200/jpm idle <seconds>|r - seconds without input before you count as idle"],
	L["|cffffd200/jpm force <situation>|r - pretend a situation is active (|cffffd200/jpm force off|r to stop)"],
	L["|cffffd200/jpm probe|r - report which graphics CVars this client has and whether we can set them"],
	L["|cffffd200/jpm probe combat|r - run the probe automatically when your next combat starts"],
	L["|cffffd200/jpm watch|r - print every setting the game changes (e.g. change one in the graphics menu to see its CVar name)"],
	L["|cffffd200/jpm debug|r - toggle debug messages"],
}

-- Short status for the options window and the minimap menu tooltip.
function JPM:GetStatusLines()
	local db = self.db.profile
	local active, pendingFor = ns.Applier:GetActive()
	local current, def = ns.Engine:GetCurrent()
	local lines = {}
	if not db.enabled then
		lines[1] = "|cffff0000" .. L["Automatic switching is off."] .. "|r"
	else
		lines[1] = L["Situation: %s"]:format("|cffffd200" .. ((current and def and def.name) or L["none"]) .. "|r")
	end
	lines[2] = L["Graphics: %s"]:format("|cffffd200" .. ((active and active ~= "recovered") and active or L["your settings"]) .. "|r")
		.. (pendingFor and (" " .. L["(pending until combat ends)"]) or "")
	return lines
end

function JPM:SetEnabled(on)
	self.db.profile.enabled = on and true or false
	if on then
		ns.Engine:Enable()
	else
		ns.Engine:Disable()
		ns.Applier:RestoreAll(L["disabled"])
	end
	if ns.Options then ns.Options:Update() end
end

function JPM:PrintStatus()
	local db = self.db.profile
	local active, pendingFor = ns.Applier:GetActive()
	local current = ns.Engine:GetCurrent()
	self:Msg("%s, %s, compat %s, interface %s",
		self.version == "dev" and "development build" or ("version " .. self.version),
		db.enabled and "|cff00ff00enabled|r" or "|cffff0000disabled|r",
		ns.Compat.name, tostring(ns.client.interface))
	self:Msg("Situation: %s; graphics profile: %s%s",
		current or "none", active or "your settings",
		pendingFor and " (changes pending until combat ends)" or "")
	local active_ = ns.Engine:GetActiveSituations()
	if #active_ > 0 then self:Msg("Active situations: %s", table.concat(active_, ", ")) end
	local n, parts = 0, {}
	for name, value in pairs(ns.Applier:GetBaseline()) do
		n = n + 1
		parts[#parts + 1] = ("%s=%s"):format(name, value)
	end
	if n > 0 then
		table.sort(parts)
		self:Msg("Saved original values (%d): %s", n, table.concat(parts, ", "))
	end
end

-- Report CVar availability, and test a harmless write/restore on maxFPSBk.
function JPM:Probe()
	local c = ns.client
	self:Msg("Build %s (%s), interface %s, WOW_PROJECT_ID %s, WOW_PROJECT_CAMELOT %s, in combat: %s",
		tostring(c.version), tostring(c.build), tostring(c.interface), tostring(c.projectID),
		tostring(rawget(_G, "WOW_PROJECT_CAMELOT")), tostring(ns.Compat:InCombat()))
	for _, def in ipairs(ns.CVarRegistry:All()) do
		local info = ns.Compat:GetCVarInfo(def.name)
		if info then
			local flags = {}
			if info.isSecure then flags[#flags + 1] = "secure" end
			if info.isReadOnly then flags[#flags + 1] = "read-only" end
			if info.isLocked then flags[#flags + 1] = "locked" end
			if def.restart then flags[#flags + 1] = "not auto-changed" end
			self:Msg("  %s = %s (default %s)%s", def.name, tostring(info.value), tostring(info.default),
				#flags > 0 and (" [" .. table.concat(flags, ", ") .. "]") or "")
		else
			self:Msg("  %s: |cffff0000not on this client|r", def.name)
		end
	end

	local delayedNames, syncNames, fromConsole = ns.Compat:GetCascadeCandidates()
	self:Msg("Lower-level settings watched: %d graphics (%d from the console's Graphics list), %d more checked only during preset changes",
		#delayedNames, fromConsole, #syncNames)
	if ns.Compat.impl.DescribeConsoleList then
		self:Msg("  Console list: %s", ns.Compat.impl.DescribeConsoleList())
	end
	for _, name in ipairs({ "groundEffectDensity", "groundEffectDist", "farclip" }) do
		local info = ns.Compat:GetCVarInfo(name)
		if info then self:Msg("  %s = %s (default %s)", name, tostring(info.value), tostring(info.default)) end
	end

	-- Write test: change maxFPSBk by one and put it back.
	local name = "maxFPSBk"
	local before = ns.Compat:GetCVar(name)
	if before then
		local test = tostring((tonumber(before) or 30) == 30 and 31 or 30)
		local ok = ns.Compat:SetCVar(name, test)
		local after = ns.Compat:GetCVar(name)
		ns.Compat:SetCVar(name, before)
		local restored = ns.Compat:GetCVar(name)
		self:Msg("Write test on %s: set %s -> %s (call %s), read back %s, restored to %s",
			name, before, test, ok and "ok" or "FAILED", tostring(after), tostring(restored))
		if ns.CVarRegistry.Equal(after, test) and ns.CVarRegistry.Equal(restored, before) then
			self:Msg("|cff00ff00Write test passed.|r")
		else
			self:Msg("|cffff0000Write test failed.|r Please report this output.")
		end
	end
end

function JPM:ListSituations()
	local order, defs = ns.Engine:GetSituations()
	local active = {}
	for _, key in ipairs(ns.Engine:GetActiveSituations()) do active[key] = true end
	local current = ns.Engine:GetCurrent()
	local sorted = {}
	for _, key in ipairs(order) do sorted[#sorted + 1] = key end
	local sit = self.db.profile.situations
	table.sort(sorted, function(a, b) return (sit[a].priority or 0) > (sit[b].priority or 0) end)
	self:Msg(L["Situations (highest priority first):"])
	for _, key in ipairs(sorted) do
		local cfg = sit[key]
		local extra = ""
		if key == "idle" then
			extra = (", after %ds, idle for %ds"):format(cfg.timeout or 0, math.floor(ns.IdleSeconds and ns.IdleSeconds() or 0))
		end
		self:Msg("  %s|cffffd200%s|r (%s): %s, %s, priority %d, delay %ss%s%s",
			key == current and "> " or "", key, defs[key].name,
			cfg.enabled and "|cff00ff00on|r" or "|cff808080off|r",
			cfg.profile and ("profile " .. cfg.profile) or "your settings",
			cfg.priority or 0, tostring(cfg.enterDelay or 0), extra,
			active[key] and " |cffffff00[active]|r" or "")
	end
end

function JPM:HandleSlash(input)
	local cmd, arg = self:GetArgs(input or "", 2)
	cmd = cmd and cmd:lower() or "options"
	local db = self.db.profile

	if cmd == "options" or cmd == "config" then
		ns.Options:Toggle()
	elseif cmd == "status" then
		self:PrintStatus()
	elseif cmd == "on" then
		self:SetEnabled(true)
		self:Msg(L["Enabled."])
	elseif cmd == "off" then
		self:SetEnabled(false)
		self:Msg(L["Disabled."])
	elseif cmd == "list" then
		self:ListSituations()
	elseif cmd == "enable" or cmd == "disable" then
		local cfg = arg and db.situations[arg]
		if not cfg then
			self:Msg(L["Unknown situation '%s'. See /jpm list."], tostring(arg))
		else
			cfg.enabled = (cmd == "enable")
			self:Msg(cfg.enabled and L["Situation %s enabled."] or L["Situation %s disabled."], arg)
			ns.Engine:Refresh("settings")
		end
	elseif cmd == "idle" then
		local seconds = tonumber(arg)
		if not seconds or seconds < 10 then
			self:Msg(L["Usage: /jpm idle <seconds> (at least 10). Currently %d."], db.situations.idle.timeout)
		else
			db.situations.idle.timeout = math.floor(seconds)
			self:Msg(L["Idle after %d seconds without input."], db.situations.idle.timeout)
			ns.Engine:Refresh("settings")
		end
	elseif cmd == "restore" then
		ns.Engine:Force(nil)
		ns.Applier:RestoreAll(L["manual restore"])
	elseif cmd == "force" then
		if not arg or arg == "off" then
			ns.Engine:Force(nil)
			self:Msg(L["No longer forcing a situation."])
		elseif ns.Engine:GetSituation(arg) then
			ns.Engine:Force(arg)
		else
			self:Msg(L["Unknown situation '%s'. See /jpm list."], arg)
		end
	elseif cmd == "probe" then
		if arg == "combat" then
			self:RegisterEvent("PLAYER_REGEN_DISABLED", function()
				self:UnregisterEvent("PLAYER_REGEN_DISABLED")
				-- Combat lockdown starts just after this event, so wait a moment.
				self:ScheduleTimer("Probe", 1)
			end)
			self:Msg("Probe armed: it will run when you next enter combat (e.g. attack a target dummy).")
		else
			self:Probe()
		end
	elseif cmd == "watch" then
		self.watching = not self.watching
		if self.watching then
			self:RegisterEvent("CVAR_UPDATE", function(_, name, value)
				self:Msg("CVar %s = %s", tostring(name), tostring(value or ns.Compat:GetCVar(tostring(name))))
			end)
		else
			self:UnregisterEvent("CVAR_UPDATE")
		end
		self:Msg(self.watching and L["Watching setting changes. /jpm watch again to stop."] or L["Stopped watching setting changes."])
	elseif cmd == "debug" then
		db.debug = not db.debug
		self:Msg("Debug %s.", db.debug and "on" or "off")
	else
		for _, line in ipairs(HELP) do self:Msg(line) end
	end
end
