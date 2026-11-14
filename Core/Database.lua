-- SavedVariables (AceDB) defaults and built-in graphics profiles.
local _, ns = ...

local Database = {}
ns.Database = Database

-- Built-in graphics profiles. A CVar missing from a profile is left alone.
Database.BUILTIN_PROFILES = {
	["Max saver"] = {
		useMaxFPS = 1,
		maxFPS = 20,
		renderScale = 0.5,
		graphicsShadowQuality = 0,
		graphicsSSAO = 0,
		graphicsParticleDensity = 0,
		graphicsLiquidDetail = 0,
		graphicsPBRLiquidDetail = 0,
		graphicsLightMode = 0,
		graphicsSpellDensity = 0,
		graphicsViewDistance = 2,
		graphicsEnvironmentDetail = 2,
		graphicsGroundClutter = 0,
		graphicsComputeEffects = 0,
	},
	-- Screensaver feel: your own graphics, no UI or names, frame rate capped.
	["Cinematic"] = {
		hideUI = true,
		hideNames = true,
		useMaxFPS = 1,
		maxFPS = 30,
	},
	["Light saver"] = {
		useMaxFPS = 1,
		maxFPS = 30,
		graphicsShadowQuality = 1,
		graphicsSSAO = 0,
	},
}

-- Changes to the built-in profiles after release, applied once to existing settings.
--  change: a value is only changed if the profile still exists and still has the old built-in
--          value (`from`; nil = not set), so the user's own edits are never overwritten.
--  add:    new built-in profiles, copied from BUILTIN_PROFILES unless the name is taken.
Database.BUILTIN_UPDATES = {
	[1] = { change = { ["Max saver"] = { graphicsParticleDensity = { from = 1, to = 0 } } } },
	[2] = { change = { ["Max saver"] = { graphicsPBRLiquidDetail = { to = 0 }, graphicsLightMode = { to = 0 } } } },
	[3] = { add = { "Cinematic" } },
}

local defaults = {
	profile = {
		enabled = true,
		debug = false,
		notify = true,               -- chat message when the profile switches
		capBackground = true,        -- when a profile caps foreground FPS, cap background FPS no higher
		protectDetails = true,       -- save and put back lower-level settings (e.g. /console tweaks)
		graphicsProfiles = {},       -- seeded from BUILTIN_PROFILES once (see EnsureProfiles)
		profilesSeeded = false,
		builtinVersion = 0,          -- last BUILTIN_UPDATES entry applied
		situations = {
			-- profile: graphics profile name, or false for "your own settings".
			-- priority: higher wins when several situations are active at once.
			-- enterDelay: seconds the situation must stay active before switching.
			combat        = { enabled = true,  profile = false,         priority = 100, enterDelay = 0 },
			cinematic     = { enabled = true,  profile = false,         priority = 95,  enterDelay = 0 },
			-- idle.timeout: seconds without input before counting as idle.
			-- idle.mouseActivity: mouse/camera movement counts as input (off: only moving your
			-- character, casting, targeting, looting, NPCs and combat do).
			idle          = { enabled = true,  profile = "Max saver",   priority = 90,  enterDelay = 0, timeout = 180,
			                  mouseActivity = false },
			taxi          = { enabled = true,  profile = "Max saver",   priority = 80,  enterDelay = 2 },
			dead          = { enabled = false, profile = "Light saver", priority = 40,  enterDelay = 3 },
			serviceWindow = { enabled = false, profile = "Light saver", priority = 35,  enterDelay = 1 },
			resting       = { enabled = false, profile = "Light saver", priority = 30,  enterDelay = 5 },
		},
	},
	global = {
		-- Applier state, account-wide because graphics CVars are account-wide.
		-- baseline: the user's own values for every CVar we have changed.
		-- owned: the values we set, used to notice when the user changes one themselves.
		-- active: name of the applied graphics profile, or nil.
		-- detail: original values of lower-level CVars (e.g. groundEffectDensity) that a preset
		-- change overwrote. initial: graphics CVar values at the start of the saver period.
		state = { baseline = {}, owned = {}, detail = {}, initial = {}, active = nil },
	},
}

local function copy(t)
	local c = {}
	for k, v in pairs(t) do c[k] = type(v) == "table" and copy(v) or v end
	return c
end
Database.Copy = copy

-- Built-in graphics profiles are copied into the user's settings once, rather than living in
-- AceDB defaults, so they can be edited, renamed and deleted for good.
function Database:EnsureProfiles(addon)
	local p = addon.db.profile
	if not p.profilesSeeded then
		for name, values in pairs(self.BUILTIN_PROFILES) do
			if p.graphicsProfiles[name] == nil then p.graphicsProfiles[name] = copy(values) end
		end
		p.profilesSeeded = true
		p.builtinVersion = #self.BUILTIN_UPDATES -- freshly seeded profiles are already current
	end
	-- `dim` (a screen overlay) only existed in development builds; dimming is now Brightness.
	for _, profile in pairs(p.graphicsProfiles) do profile.dim = nil end
	for version = (p.builtinVersion or 0) + 1, #self.BUILTIN_UPDATES do
		local update = self.BUILTIN_UPDATES[version]
		for name, changes in pairs(update.change or {}) do
			local profile = p.graphicsProfiles[name]
			if profile then
				for key, change in pairs(changes) do
					if profile[key] == change.from then profile[key] = change.to end
				end
			end
		end
		for _, name in ipairs(update.add or {}) do
			if p.graphicsProfiles[name] == nil then p.graphicsProfiles[name] = copy(self.BUILTIN_PROFILES[name]) end
		end
		p.builtinVersion = version
	end
end

function Database:Init(addon)
	addon.db = LibStub("AceDB-3.0"):New("JimPowerMizerDB", defaults, true)
	self:EnsureProfiles(addon)
	local function changed()
		self:EnsureProfiles(addon)
		if ns.Engine and ns.Engine:IsEnabled() then ns.Engine:Refresh("settings profile changed") end
		if ns.Options then ns.Options:Refresh() end
	end
	addon.db.RegisterCallback(self, "OnProfileChanged", changed)
	addon.db.RegisterCallback(self, "OnProfileCopied", changed)
	addon.db.RegisterCallback(self, "OnProfileReset", changed)
end
