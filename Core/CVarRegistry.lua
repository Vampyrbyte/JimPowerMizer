-- Known graphics CVars. Profiles refer to these keys; the Applier only touches CVars listed here
-- that exist on the running client. Names must be confirmed per flavor with `/jpm probe`.
local _, ns = ...
local L = ns.L

local Registry = {}
ns.CVarRegistry = Registry

-- Names: the game's own (localized) strings, the same globals Blizzard's Graphics menu uses
-- (Interface/AddOns/Blizzard_SettingsDefinitions_Shared/Graphics.lua and GraphicsOverrides.lua, read
-- for every client on 2026-11-17), with English fallbacks.
local function G(globalName, fallback)
	local v = rawget(_G, globalName)
	return type(v) == "string" and v ~= "" and v or fallback
end

-- A level list: { value, global name, English fallback } per menu entry, in menu order.
local DISABLED = { "VIDEO_OPTIONS_DISABLED", L["Disabled"] }
local NONE = { "VIDEO_OPTIONS_NONE", L["None"] }
local LOW, FAIR, MEDIUM = { "VIDEO_OPTIONS_LOW", L["Low"] }, { "VIDEO_OPTIONS_FAIR", L["Fair"] }, { "VIDEO_OPTIONS_MEDIUM", L["Medium"] }
local HIGH, ULTRA = { "VIDEO_OPTIONS_HIGH", L["High"] }, { "VIDEO_OPTIONS_ULTRA", L["Ultra"] }
local ULTRA_HIGH = { "VIDEO_OPTIONS_ULTRA_HIGH", L["Ultra High"] }
local function levels(...)
	local list = {}
	for i = 1, select("#", ...) do
		local entry = (select(i, ...))
		list[i] = { i - 1, entry[1], entry[2] } -- values 0, 1, 2, ...
	end
	return list
end
local function menu() return ns.Compat:GraphicsMenu() end

-- kind: "bool" | "number" | "enum". An enum with `levels` (a list, or a function returning one for
-- menus that differ between clients) gets a dropdown, otherwise a slider. offset: added to the value
-- for display (the game shows the 0-9 detail sliders as 1-10).
-- restart = true: needs RestartGx()/client restart; never changed automatically.
local CVARS = {
	{ name = "useMaxFPS",               kind = "bool",   label = L["Limit foreground FPS"] },
	{ name = "maxFPS",                  kind = "number", label = L["Max foreground FPS"], min = 8, max = 300, bigStep = 5 },
	{ name = "useMaxFPSBk",             kind = "bool",   label = L["Limit background FPS"] },
	{ name = "maxFPSBk",                kind = "number", label = L["Max background FPS"], min = 8, max = 300, bigStep = 5 },
	{ name = "Brightness",              kind = "number", label = G("OPTIONS_BRIGHTNESS", L["Brightness"]), min = 0, max = 100, bigStep = 5 },
	{ name = "renderScale",             kind = "number", label = L["Render scale"], min = 0.33, max = 2.0, step = 0.01, bigStep = 0.05, percent = true },

	-- The Graphics menu's quality settings, in its order. Each client shows the ones it has.
	{ name = "graphicsShadowQuality",   kind = "enum", label = G("SHADOW_QUALITY", L["Shadow quality"]),
		levels = levels(LOW, FAIR, MEDIUM, HIGH, ULTRA, ULTRA_HIGH) },
	{ name = "graphicsLiquidDetail",    kind = "enum", label = G("LIQUID_DETAIL", L["Liquid detail"]),
		levels = levels(LOW, FAIR, MEDIUM, HIGH) },
	-- Light mode also sets giQuality and RenderFormat, PBR liquid sets pbrLiquidDetail (kept safe
	-- as lower-level settings). Forever only.
	{ name = "graphicsPBRLiquidDetail", kind = "enum", label = G("PBR_LIQUID_DETAIL", L["PBR liquid detail"]),
		levels = levels(LOW, HIGH, ULTRA) },
	-- Where secondary lighting isn't supported (all but Forever), 0 turns particles off, combat cues too.
	{ name = "graphicsParticleDensity", kind = "enum", label = G("PARTICLE_DENSITY", L["Particle density"]),
		levels = function()
			if ns.Compat:HasSecondaryLighting() then return levels(LOW, FAIR, MEDIUM, HIGH, ULTRA) end
			return levels(DISABLED, LOW, FAIR, MEDIUM, HIGH, ULTRA)
		end },
	{ name = "graphicsSSAO",            kind = "enum", label = G("SSAO_LABEL", L["SSAO"]),
		levels = levels(DISABLED, LOW, MEDIUM, HIGH, ULTRA) },
	{ name = "graphicsDepthEffects",    kind = "enum", label = G("DEPTH_EFFECTS", L["Depth effects"]),
		levels = levels(DISABLED, LOW, MEDIUM, HIGH) },
	{ name = "graphicsComputeEffects",  kind = "enum", label = G("COMPUTE_EFFECTS", L["Compute effects"]),
		levels = function()
			if menu() == "forever" then return levels(LOW, FAIR, MEDIUM, HIGH, ULTRA) end
			return levels(DISABLED, LOW, MEDIUM, HIGH, ULTRA)
		end },
	{ name = "graphicsOutlineMode",     kind = "enum", label = G("OUTLINE_MODE", L["Outline mode"]),
		levels = { { 0, DISABLED[1], DISABLED[2] }, { 1, MEDIUM[1], MEDIUM[2] }, { 2, HIGH[1], HIGH[2] } } },
	-- Switching it reloads textures (a short hitch), so the built-in profiles leave it alone.
	{ name = "graphicsTextureResolution", kind = "enum", label = G("TEXTURE_DETAIL", L["Texture resolution"]),
		levels = function()
			if menu() == "classic" then return levels(LOW, HIGH) end
			return levels(LOW, FAIR, HIGH)
		end },
	{ name = "graphicsSpellDensity",    kind = "enum", label = G("SPELL_DENSITY", L["Spell density"]),
		levels = levels({ "VIDEO_OPTIONS_SFX_DENSITY_MIN", L["Minimal"] }, { "VIDEO_OPTIONS_SFX_DENSITY_REDUCED", L["Reduced"] },
			{ "VIDEO_OPTIONS_SFX_DENSITY_FULL", L["Full"] }) },
	{ name = "graphicsProjectedTextures", kind = "bool", label = G("PROJECTED_TEXTURES", L["Projected textures"]) },
	{ name = "graphicsLightMode",       kind = "enum", label = G("LIGHTING_MODE", L["Secondary lighting"]),
		levels = levels(FAIR, MEDIUM, HIGH, ULTRA) },
	{ name = "graphicsViewDistance",    kind = "enum", label = G("FARCLIP", L["View distance"]), min = 0, max = 9, offset = 1 },
	{ name = "graphicsEnvironmentDetail", kind = "enum", label = G("ENVIRONMENT_DETAIL", L["Environment detail"]), min = 0, max = 9, offset = 1 },
	{ name = "graphicsGroundClutter",   kind = "enum", label = G("GROUND_CLUTTER", L["Ground clutter"]), min = 0, max = 9, offset = 1 },
	{ name = "graphicsSunshafts",       kind = "enum", label = G("SUNSHAFTS", L["Sun shafts"]), -- Classic only
		levels = levels(DISABLED, LOW, HIGH) },

	-- The menu's advanced settings that change how hard the GPU works. Values a graphics card doesn't
	-- support (CMAA, ray-traced shadows, variable rate shading) are refused by the client.
	{ name = "ffxAntiAliasingMode",     kind = "enum", label = G("FXAA_CMAA_LABEL", L["Anti-aliasing"]),
		levels = levels(NONE, { "ANTIALIASING_FXAA_LOW", L["FXAA Low"] }, { "ANTIALIASING_FXAA_HIGH", L["FXAA High"] },
			{ "ANTIALIASING_CMAA", L["CMAA"] }, { "ANTIALIASING_CMAA2", L["CMAA 2"] }) },
	{ name = "textureFilteringMode",    kind = "enum", label = G("ANISOTROPIC", L["Texture filtering"]),
		levels = levels({ "VIDEO_OPTIONS_BILINEAR", L["Bilinear"] }, { "VIDEO_OPTIONS_TRILINEAR", L["Trilinear"] },
			{ "VIDEO_OPTIONS_2XANISOTROPIC", L["2x Anisotropic"] }, { "VIDEO_OPTIONS_4XANISOTROPIC", L["4x Anisotropic"] },
			{ "VIDEO_OPTIONS_8XANISOTROPIC", L["8x Anisotropic"] }, { "VIDEO_OPTIONS_16XANISOTROPIC", L["16x Anisotropic"] }) },
	{ name = "shadowrt",                kind = "enum", label = G("RT_SHADOW_QUALITY", L["Ray traced shadows"]),
		levels = levels(DISABLED, FAIR, MEDIUM, HIGH) },
	{ name = "ResampleQuality",         kind = "enum", label = G("RESAMPLE_QUALITY", L["Resample quality"]),
		levels = levels({ "RESAMPLE_QUALITY_POINT", L["Point"] }, { "RESAMPLE_QUALITY_BILINEAR", L["Bilinear"] },
			{ "RESAMPLE_QUALITY_BICUBIC", L["Bicubic"] }, { "RESAMPLE_QUALITY_FSR", L["FidelityFX Super Resolution 1.0"] }) },
	{ name = "vrsValar",                kind = "enum", label = G("VRS_MODE", L["Variable rate shading"]),
		levels = levels(DISABLED, { "VIDEO_OPTIONS_STANDARD", L["Standard"] }, { "VIDEO_OPTIONS_AGGRESSIVE", L["Aggressive"] }) },
	{ name = "vsync",                   kind = "bool", label = G("VERTICAL_SYNC", L["Vertical sync"]) },

	-- Listed so the probe reports it, but never changed automatically: switching the preset
	-- overwrites the user's individual settings.
	{ name = "graphicsQuality",         kind = "enum",   label = L["Overall preset"], min = 1, max = 10, restart = true },
	{ name = "MSAAQuality",             kind = "enum",   label = L["MSAA"],           restart = true },
}

-- Names above characters and nameplates. Not shown in the profile editor: a profile's "Hide names"
-- option sets every one the client has to 0 (see Applier effectiveProfile). Names differ between
-- clients, so missing ones are simply skipped. ("Hostle" is Blizzard's spelling.)
Registry.NAME_CVARS = {
	"UnitNameOwn", "UnitNameNPC", "UnitNameHostleNPC", "UnitNameInteractiveNPC",
	"UnitNameFriendlySpecialNPCName", "UnitNameNonCombatCreatureName",
	"UnitNameFriendlyPlayerName", "UnitNameFriendlyMinionName", "UnitNameFriendlyPetName",
	"UnitNameFriendlyGuardianName", "UnitNameFriendlyTotemName",
	"UnitNameEnemyPlayerName", "UnitNameEnemyMinionName", "UnitNameEnemyPetName",
	"UnitNameEnemyGuardianName", "UnitNameEnemyTotemName",
	"UnitNamePlayerGuild", "UnitNamePlayerPVPTitle", "UnitNameGuildTitle",
	"nameplateShowAll", "nameplateShowEnemies", "nameplateShowFriends", "nameplateShowFriendlyNPCs",
	"nameplateShowFriendlyPlayers", -- seen on Forever 1.60.1 and Midnight 12.1.5; neither has nameplateShowFriends
}
for _, name in ipairs(Registry.NAME_CVARS) do
	CVARS[#CVARS + 1] = { name = name, kind = "bool", label = name, hidden = true }
end

local byName = {}
for i, def in ipairs(CVARS) do
	def.order = i
	byName[def.name:lower()] = def
end

-- The menu's entries for a CVar on this client, { { value, name }, ... } in menu order, or nil if
-- it has no level names (a slider).
function Registry:Levels(name)
	local def = self:Get(name)
	local list = def and def.levels
	if type(list) == "function" then list = list() end
	if not list then return nil end
	local out = {}
	for i, entry in ipairs(list) do out[i] = { entry[1], G(entry[2], entry[3]) } end
	return out
end

-- { [value] = name } for a dropdown, or nil for a slider.
function Registry:LevelValues(name)
	local list = self:Levels(name)
	if not list then return nil end
	local values = {}
	for _, entry in ipairs(list) do values[entry[1]] = entry[2] end
	return values
end

-- Values in menu order, for the dropdown's sorting.
function Registry:LevelSorting(name)
	local list = self:Levels(name)
	if not list then return nil end
	local sorting = {}
	for i, entry in ipairs(list) do sorting[i] = entry[1] end
	return sorting
end

function Registry:Get(name)
	return byName[name:lower()]
end

function Registry:All()
	return CVARS
end

-- Is this CVar safe for us to change automatically on this client?
function Registry:IsUsable(name)
	local def = self:Get(name)
	if not def or def.restart then return false end
	local info = ns.Compat:GetCVarInfo(def.name)
	return info ~= nil and not info.isReadOnly and not info.isLocked
end

-- Compare two CVar values, treating "20" and "20.000" as equal.
function Registry.Equal(a, b)
	if a == b then return true end
	if a == nil or b == nil then return false end
	local na, nb = tonumber(a), tonumber(b)
	if na and nb then return math.abs(na - nb) < 1e-4 end
	return tostring(a) == tostring(b)
end
