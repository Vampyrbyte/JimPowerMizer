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
end

-- Switch to graphics profile `profileName` (nil = restore the user's settings).
function Applier:Apply(profileName, reason)
	local st = state()
	local profile = profileName and ns.addon.db.profile.graphicsProfiles[profileName]
	if profileName and not profile then
		ns.addon:Msg("Unknown graphics profile '%s'", profileName)
		profileName, profile = nil, nil
	end
	if st.active == profileName and not pending and (profileName or not next(st.baseline)) then return end

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
end

function Applier:Enable()
	self:RegisterEvent("CVAR_UPDATE", "OnCVarUpdate")
	self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnCombatEnd")
	self:RegisterEvent("PLAYER_LOGOUT", "OnLogout")

	-- Crash recovery: a baseline left over from last session means our values may still be live.
	local st = state()
	if next(st.baseline) then
		st.active = "recovered"
		self:RestoreAll("left over from last session")
	else
		st.active = nil
		wipe(st.owned)
	end
end
