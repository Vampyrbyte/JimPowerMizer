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

local Applier = {}
ns.Applier = Applier
LibStub("AceEvent-3.0"):Embed(Applier) -- own registrations, separate from other modules

local Registry = ns.CVarRegistry
local Equal = Registry.Equal

local pending        -- queued { [name] = value } while in combat
local detailTimer    -- scheduled second pass of restoreDetails
local restoreDetailsSoon -- defined below
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

-- Apply a full set of changes { [name] = value or false } (false = restore baseline).
local function applyChanges(changes, label)
	local st = state()
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
	-- Everything is back to the user's values: put the lower-level settings back too.
	if not next(st.baseline) and not pending then restoreDetailsSoon() end
end

-- ---------------------------------------------------------------------------------------------
-- Lower-level ("detail") CVars, e.g. groundEffectDensity under graphicsGroundClutter. The client
-- overwrites these when a preset changes, so /console tweaks would be lost on restore. They're
-- snapshotted (state.detail) before the first change and written back once everything is restored.

-- Never written back: display/device settings, the presets themselves (writing one would cascade
-- again), and anything the CVarRegistry manages directly.
local DETAIL_EXCLUDE_PREFIXES = { "gx", "msaa", "graphics", "raidgraphics", "raidsettings" }

local function isDetailCandidate(name)
	local lower = name:lower()
	for _, prefix in ipairs(DETAIL_EXCLUDE_PREFIXES) do
		if lower:sub(1, #prefix) == prefix then return false end
	end
	if Registry:Get(name) then return false end
	local info = ns.Compat:GetCVarInfo(name)
	return info ~= nil and not info.isReadOnly and not info.isLocked
end

local function snapshotDetails()
	if not ns.addon.db.profile.protectDetails then return end
	local st = state()
	wipe(st.detail)
	local n = 0
	for _, name in ipairs((ns.Compat:GetDetailCVarNames())) do
		if isDetailCandidate(name) then
			local v = ns.Compat:GetCVar(name)
			if v ~= nil then
				st.detail[name] = v
				n = n + 1
			end
		end
	end
	ns.addon:Debug("Saved %d detail settings", n)
end

-- Write back any detail CVar that differs from the snapshot. Returns the number written.
local function restoreDetails(label)
	local st = state()
	local n = 0
	for name, value in pairs(st.detail) do
		local current = ns.Compat:GetCVar(name)
		if current ~= nil and not Equal(current, value) and canWriteNow(name) then
			if ns.Compat:SetCVar(name, value) then
				n = n + 1
				ns.addon:Debug("%s: restored %s = %s (was %s)", label, name, value, current)
			end
		end
	end
	return n
end

-- Called once all presets are back to the user's values: restore details now, and again shortly
-- after in case the client applies the preset's values a frame later. Then drop the snapshot,
-- unless a profile was applied again meanwhile.
function restoreDetailsSoon()
	if not next(state().detail) then return end
	restoreDetails("restore")
	if detailTimer then ns.addon:CancelTimer(detailTimer) end
	detailTimer = ns.addon:ScheduleTimer(function()
		detailTimer = nil
		local st = state()
		if next(st.baseline) then return end -- a profile is active again; keep the snapshot
		restoreDetails("restore (2nd pass)")
		wipe(st.detail)
	end, 0.5)
end

-- The profile's values plus derived ones. If the profile caps foreground FPS, the background cap
-- must not be higher, or alt-tabbing out while idle would *raise* the frame rate.
local function effectiveProfile(profile)
	if not profile then return nil end
	local p = {}
	for k, v in pairs(profile) do p[k] = v end
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
		ns.addon:Msg("Unknown graphics profile '%s'", profileName)
		profileName, profile = nil, nil
	end
	if not force and st.active == profileName and not pending and (profileName or not next(st.baseline)) then return end
	profile = effectiveProfile(profile)

	-- First change from the user's own settings: snapshot the lower-level settings.
	if profile and not next(st.baseline) then
		if detailTimer then ns.addon:CancelTimer(detailTimer); detailTimer = nil end
		if next(st.detail) then
			restoreDetails("restore (before new snapshot)")
		end
		snapshotDetails()
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
	applyChanges(changes, profileName or "restore")

	if ns.addon.db.profile.notify then
		if profileName then
			ns.addon:Msg("Graphics profile |cffffd200%s|r (%s)", profileName, reason or "?")
		else
			ns.addon:Msg("Restored your graphics settings (%s)", reason or "?")
		end
	end
end

-- Re-apply the active profile after it was edited.
function Applier:ReapplyIfActive(profileName)
	if profileName and state().active == profileName and ns.addon.db.profile.graphicsProfiles[profileName] then
		self:Apply(profileName, "profile edited", true)
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
				Applier:RestoreAll("left over from last session")
			end
		end, ns.STARTUP_GRACE)
	else
		st.active = nil
		wipe(st.owned)
		-- Interrupted between the restore and the detail restore's second pass.
		if next(st.detail) then restoreDetailsSoon() end
	end
end
