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
		graphicsParticleDensity = 1,
		graphicsLiquidDetail = 0,
		graphicsSpellDensity = 0,
		graphicsViewDistance = 2,
		graphicsEnvironmentDetail = 2,
		graphicsGroundClutter = 0,
		graphicsComputeEffects = 0,
	},
	["Light saver"] = {
		useMaxFPS = 1,
		maxFPS = 30,
		graphicsShadowQuality = 1,
		graphicsSSAO = 0,
	},
}

local defaults = {
	profile = {
		enabled = true,
		debug = false,
		notify = true,               -- chat message when the profile switches
		capBackground = true,        -- when a profile caps foreground FPS, cap background FPS no higher
		graphicsProfiles = Database.BUILTIN_PROFILES,
		situations = {
			-- profile: graphics profile name, or false for "your own settings".
			-- priority: higher wins when several situations are active at once.
			-- enterDelay: seconds the situation must stay active before switching.
			combat        = { enabled = true,  profile = false,         priority = 100, enterDelay = 0 },
			cinematic     = { enabled = true,  profile = false,         priority = 95,  enterDelay = 0 },
			idle          = { enabled = true,  profile = "Max saver",   priority = 90,  enterDelay = 0,
			                  timeout = 180 }, -- seconds without input before counting as idle
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
		state = { baseline = {}, owned = {}, active = nil },
	},
}

function Database:Init(addon)
	addon.db = LibStub("AceDB-3.0"):New("JimPowerMizerDB", defaults, true)
end
