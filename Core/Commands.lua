-- Slash commands: /jpm
local _, ns = ...

local JPM = ns.addon

local HELP = {
	"|cffffd200/jpm status|r - show the current state",
	"|cffffd200/jpm on|r / |cffffd200off|r - enable or disable automatic switching",
	"|cffffd200/jpm restore|r - restore your graphics settings now",
	"|cffffd200/jpm force <situation>|r - pretend a situation is active (|cffffd200/jpm force off|r to stop)",
	"|cffffd200/jpm probe|r - report which graphics CVars this client has and whether we can set them",
	"|cffffd200/jpm debug|r - toggle debug messages",
}

function JPM:PrintStatus()
	local db = self.db.profile
	local active, pendingFor = ns.Applier:GetActive()
	local current = ns.Engine:GetCurrent()
	self:Msg("v%s, %s, compat %s, interface %s", self.version,
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

function JPM:HandleSlash(input)
	local cmd, arg = self:GetArgs(input or "", 2)
	cmd = cmd and cmd:lower() or "status"
	local db = self.db.profile

	if cmd == "status" then
		self:PrintStatus()
	elseif cmd == "on" then
		db.enabled = true
		ns.Engine:Enable()
		self:Msg("Enabled.")
	elseif cmd == "off" then
		db.enabled = false
		ns.Engine:Disable()
		ns.Applier:RestoreAll("disabled")
		self:Msg("Disabled.")
	elseif cmd == "restore" then
		ns.Engine:Force(nil)
		ns.Applier:RestoreAll("manual restore")
	elseif cmd == "force" then
		if not arg or arg == "off" then
			ns.Engine:Force(nil)
			self:Msg("No longer forcing a situation.")
		elseif ns.Engine:GetSituation(arg) then
			ns.Engine:Force(arg)
		else
			self:Msg("Unknown situation '%s'.", arg)
		end
	elseif cmd == "probe" then
		self:Probe()
	elseif cmd == "debug" then
		db.debug = not db.debug
		self:Msg("Debug %s.", db.debug and "on" or "off")
	else
		for _, line in ipairs(HELP) do self:Msg(line) end
	end
end
