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
		graphicsProfiles = Database.BUILTIN_PROFILES,
		situations = {
			-- priority: higher wins when several situations are active at once.
			-- enterDelay: seconds the situation must stay active before switching.
			taxi = { enabled = true, profile = "Max saver", priority = 80, enterDelay = 2 },
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
