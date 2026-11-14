-- Applies graphics profiles while keeping the user's own settings safe.
--
-- Rules:
--  * Before changing a CVar for the first time, store the user's value in `state.baseline`
--    (SavedVariables), so it can be restored even after a crash.
--  * If the user changes a CVar we manage (e.g. in Blizzard's settings), their value wins: it is
--    removed from baseline/owned and we stop touching it until the next profile switch.
--  * On login, any leftover baseline (from a crash or disconnect) is restored first.
--  * Secure CVars can't be set in combat; those changes are queued until combat ends.
local _, ns = ...
local L = ns.L

local Applier = {}
ns.Applier = Applier
LibStub("AceEvent-3.0"):Embed(Applier) -- own registrations, separate from other modules

local Registry = ns.CVarRegistry
local Equal = Registry.Equal

local pending        -- queued { [name] = value } while in combat
local pendingProfile -- profile name for the pending change (for status display)

local function state()
	return ns.addon.db.global.state
end

-- Set one CVar, remembering the value we wrote. Returns true on success.
local function write(name, value)
	local st = state()
	value = tostring(value)
	st.owned[name] = value
	local ok = ns.Compat:SetCVar(name, value)
	if not ok then
		st.owned[name] = nil
		ns.addon:Debug("SetCVar(%s, %s) failed", name, value)
	end
	return ok
end

local function canWriteNow(name)
	if not ns.Compat:InCombat() then return true end
	local info = ns.Compat:GetCVarInfo(name)
	return info and not info.isSecure
end

-- ---------------------------------------------------------------------------------------------
-- Lower-level ("detail") CVars. Setting a preset (graphicsGroundClutter, ...) makes the client
-- overwrite the CVars under it (groundEffectDensity, ...), so restoring the preset would lose
-- /console tweaks. We detect which CVars each batch of preset writes actually changed, remember
-- their original values in state.detail (SavedVariables), and write them back once everything is
-- restored.
--
-- Candidates come from the Compat layer in two groups:
--  * delayed: Graphics console category + a known list. Checked right after our writes and again
--    0.5 s later (the client may apply a preset a frame later).
--  * sync: e.g. the Default console category, which mixes in many non-graphics CVars. Only counted
--    if they change *during* our writes, which nothing else can cause.

-- Never written back: display/device settings, the presets themselves (writing one would cascade
-- again), and anything the CVarRegistry manages directly.
local DETAIL_EXCLUDE_PREFIXES = { "gx", "msaa", "graphics", "raidgraphics", "raidsettings" }
local DELAYED_CHECK = 0.5

local candidates   -- { all = {...}, delayed = {...} }, built once per session
local initial      -- all candidate values before the first change (this session; the delayed
                   -- ones are also saved in state.initial, to survive a crash)
local batchSeq = 0 -- latest write batch; only its delayed check finishes a restore

local function isDetailCandidate(name)
	local lower = name:lower()
	for _, prefix in ipairs(DETAIL_EXCLUDE_PREFIXES) do
		if lower:sub(1, #prefix) == prefix then return false end
	end
	if Registry:Get(name) then return false end
	local info = ns.Compat:GetCVarInfo(name)
	return info ~= nil and not info.isReadOnly and not info.isLocked
end

local function getCandidates()
	if candidates then return candidates end
	local delayedNames, syncNames = ns.Compat:GetCascadeCandidates()
	candidates = { all = {}, delayed = {} }
	local seen = {}
	local function add(name, delayed)
		local key = name:lower()
		if seen[key] or not isDetailCandidate(name) then return end
		seen[key] = true
		candidates.all[#candidates.all + 1] = name
		if delayed then candidates.delayed[#candidates.delayed + 1] = name end
	end
	for _, name in ipairs(delayedNames) do add(name, true) end
	for _, name in ipairs(syncNames) do add(name, false) end
	return candidates
end

local function snapshot(list)
	local values = {}
	for _, name in ipairs(list) do values[name] = ns.Compat:GetCVar(name) end
	return values
end

-- Remember the original value of every CVar in `list` that changed since `before`. The original
-- is the value from before the saver period; if that isn't known (e.g. after a crash), the CVar
-- is left alone rather than "restored" to a lowered value.
local function record(before, list, label)
	local st = state()
	for _, name in ipairs(list) do
		local was = before[name]
		if was ~= nil and st.detail[name] == nil then
			local now = ns.Compat:GetCVar(name)
			if now ~= nil and not Equal(was, now) then
				local original = (initial and initial[name]) or st.initial[name]
				if original ~= nil then
					st.detail[name] = original
					ns.addon:Debug("%s also changed %s: %s -> %s", label, name, tostring(was), tostring(now))
				else
					ns.addon:Debug("%s also changed %s (original unknown, left alone)", label, name)
				end
			end
		end
	end
end

local function clearDetails()
	local st = state()
	wipe(st.detail)
	wipe(st.initial)
end

-- Write back every remembered detail CVar that differs from its original value.
local function restoreDetails(label)
	local n = 0
	for name, value in pairs(state().detail) do
		local current = ns.Compat:GetCVar(name)
		if current ~= nil and not Equal(current, value) and canWriteNow(name) then
			if ns.Compat:SetCVar(name, value) then
				n = n + 1
				ns.addon:Debug("%s: put back %s = %s (was %s)", label, name, value, current)
			end
		end
	end
	return n
end

local function fullyRestored()
	return not next(state().baseline) and not pending
end

-- Apply a full set of changes { [name] = value or false } (false = restore baseline).
-- `fresh` = the user's own settings are live right now (first change of a saver period).
local function applyChanges(changes, label, fresh)
	local st = state()
	local protect = ns.addon.db.profile.protectDetails
	local before
	if protect then
		before = snapshot(getCandidates().all)
		if fresh then
			initial = before
			wipe(st.initial)
			for _, name in ipairs(candidates.delayed) do st.initial[name] = before[name] end
		end
	end

	local deferred
	for name, value in pairs(changes) do
		if canWriteNow(name) then
			if value == false then
				local base = st.baseline[name]
				if base ~= nil then
					if write(name, base) then
						st.baseline[name] = nil
						st.owned[name] = nil
					end
				end
			else
				if write(name, value) then
					ns.addon:Debug("%s: %s = %s", label, name, tostring(value))
				end
			end
		else
			deferred = deferred or {}
			deferred[name] = value
		end
	end
	if deferred then
		pending = pending or {}
		for k, v in pairs(deferred) do pending[k] = v end
		pendingProfile = label
		ns.addon:Debug("Deferred %s changes until combat ends", label)
	end

	if not protect then
		if fullyRestored() then clearDetails() end
		return
	end
	record(before, candidates.all, label)
	if fullyRestored() then restoreDetails("restore") end

	batchSeq = batchSeq + 1
	local seq = batchSeq
	ns.addon:ScheduleTimer(function()
		record(before, candidates.delayed, label .. " (delayed)")
		if seq == batchSeq and fullyRestored() then
			restoreDetails("restore (2nd pass)")
			clearDetails()
		end
	end, DELAYED_CHECK)
end

-- The profile's values plus derived ones. If the profile caps foreground FPS, the background cap
-- must not be higher, or alt-tabbing out while idle would *raise* the frame rate.
local function effectiveProfile(profile)
	if not profile then return nil end
	local p = {}
	for k, v in pairs(profile) do
		if not ns.Screen.KEYS[k] then p[k] = v end -- screen effects aren't CVars
	end
	-- "Hide names": every name/nameplate CVar this client has goes to 0.
	if profile.hideNames then
		for _, name in ipairs(Registry.NAME_CVARS) do
			if p[name] == nil and Registry:IsUsable(name) then p[name] = 0 end
		end
	end
	local fg = tonumber(p.maxFPS)
	if ns.addon.db.profile.capBackground and tonumber(p.useMaxFPS) == 1 and fg
		and p.maxFPSBk == nil and p.useMaxFPSBk == nil then
		local st = state()
		-- Compare against the user's own background setting, not one we've already lowered.
		local useBk = tonumber(st.baseline.useMaxFPSBk or ns.Compat:GetCVar("useMaxFPSBk")) == 1
		local bk = tonumber(st.baseline.maxFPSBk or ns.Compat:GetCVar("maxFPSBk"))
		if not useBk or not bk or bk > fg then
			p.useMaxFPSBk = 1
			p.maxFPSBk = fg
		end
	end
	return p
end

-- Switch to graphics profile `profileName` (nil = restore the user's settings).
function Applier:Apply(profileName, reason, force)
	local st = state()
	local profile = profileName and ns.addon.db.profile.graphicsProfiles[profileName]
	if profileName and not profile then
		ns.addon:Msg(L["Unknown graphics profile '%s'"], profileName)
		profileName, profile = nil, nil
	end
	if not force and st.active == profileName and not pending and (profileName or not next(st.baseline)) then return end
	profile = effectiveProfile(profile)

	-- First change away from the user's own settings. Details left from a restore less than 0.5 s
	-- ago are put back first, so the new period starts from the user's values.
	local fresh = profile ~= nil and not next(st.baseline)
	if fresh and next(st.detail) then
		restoreDetails("restore (before new period)")
		clearDetails()
	end

	local changes = {}
	-- 1. CVars changed by the old profile that the new one doesn't set go back to the baseline.
	for name in pairs(st.baseline) do
		if not (profile and profile[name] ~= nil) then
			changes[name] = false
		end
	end
	-- 2. CVars in the new profile: capture the baseline first, then set them.
	if profile then
		for name, value in pairs(profile) do
			if Registry:IsUsable(name) then
				if st.baseline[name] == nil then
					local current = ns.Compat:GetCVar(name)
					if current ~= nil then st.baseline[name] = current end
				end
				if st.baseline[name] ~= nil then changes[name] = value end
			else
				ns.addon:Debug("Skipping %s (unavailable or unsafe on this client)", name)
			end
		end
	end

	st.active = profileName
	applyChanges(changes, profileName or "restore", fresh)
	ns.Screen:Apply(profileName and ns.addon.db.profile.graphicsProfiles[profileName])

	if ns.addon.db.profile.notify then
		if profileName then
			ns.addon:Msg(L["Graphics profile %s (%s)"], "|cffffd200" .. profileName .. "|r", reason or "?")
		else
			ns.addon:Msg(L["Restored your graphics settings (%s)"], reason or "?")
		end
	end
end

-- Re-apply the active profile after it was edited.
function Applier:ReapplyIfActive(profileName)
	if profileName and state().active == profileName and ns.addon.db.profile.graphicsProfiles[profileName] then
		self:Apply(profileName, L["profile edited"], true)
	end
end

-- The user's own value for a CVar: the saved original if we've changed it, else the live value.
function Applier:GetUserValue(name)
	local base = state().baseline[name]
	if base ~= nil then return base end
	return ns.Compat:GetCVar(name)
end

function Applier:RestoreAll(reason)
	self:Apply(nil, reason)
end

function Applier:GetActive()
	return state().active, pending and pendingProfile
end

function Applier:GetBaseline()
	return state().baseline
end

-- CVAR_UPDATE: notice user-made changes to CVars we manage.
function Applier:OnCVarUpdate(_, name, value)
	if type(name) ~= "string" then return end
	local st = state()
	-- CVar names in events can differ in case from ours.
	for ownedName, ownedValue in pairs(st.owned) do
		if ownedName:lower() == name:lower() then
			local current = value or ns.Compat:GetCVar(ownedName)
			if not Equal(current, ownedValue) then
				ns.addon:Debug("User changed %s to %s; keeping it", ownedName, tostring(current))
				st.owned[ownedName] = nil
				st.baseline[ownedName] = nil
				if pending then pending[ownedName] = nil end
			end
			return
		end
	end
end

function Applier:OnCombatEnd()
	if not pending then return end
	local changes = pending
	pending, pendingProfile = nil, nil
	applyChanges(changes, state().active or "restore")
end

function Applier:OnLogout()
	-- Put the user's values back so they're what gets written to Config.wtf. The baseline is
	-- deliberately kept: if these writes don't stick (or the game crashes instead of logging out),
	-- it's restored again on the next login.
	local st = state()
	for name, value in pairs(st.baseline) do
		st.owned[name] = value -- mark as our write, so OnCVarUpdate doesn't drop the baseline
		ns.Compat:SetCVar(name, value)
	end
	for name, value in pairs(st.detail) do
		ns.Compat:SetCVar(name, value)
	end
end

function Applier:GetDetailCount()
	local n = 0
	for _ in pairs(state().detail) do n = n + 1 end
	return n
end

function Applier:Enable()
	ns.Screen:Enable()
	self:RegisterEvent("CVAR_UPDATE", "OnCVarUpdate")
	self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnCombatEnd")
	self:RegisterEvent("PLAYER_LOGOUT", "OnLogout")

	-- A baseline left over from last session (logout mid-situation, or a crash) means our values
	-- may still be live. Wait for the startup grace period: if a situation is still active (e.g.
	-- /reload on a flight path) the Engine switches straight to its profile, keeping this baseline;
	-- otherwise restore the user's settings.
	local st = state()
	if next(st.baseline) then
		st.active = "recovered"
		ns.addon:ScheduleTimer(function()
			if state().active == "recovered" then
				Applier:RestoreAll(L["left over from last session"])
			end
		end, ns.STARTUP_GRACE)
	else
		st.active = nil
		wipe(st.owned)
		-- Interrupted between the restore and the detail restore's second pass.
		if next(st.detail) then
			restoreDetails("left over from last session")
			clearDetails()
		end
	end
end
