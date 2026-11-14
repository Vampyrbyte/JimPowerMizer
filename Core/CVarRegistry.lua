-- Known graphics CVars. Profiles refer to these keys; the Applier only touches CVars listed here
-- that exist on the running client. Names must be confirmed per flavor with `/jpm probe`.
local _, ns = ...
local L = ns.L

local Registry = {}
ns.CVarRegistry = Registry

-- Level names. The game's own (localized) strings where they exist, English otherwise. Shown as
-- "3 - High" so the number, which is what's stored, stays visible if a name doesn't match.
local function G(globalName, fallback)
	local v = rawget(_G, globalName)
	return type(v) == "string" and v or fallback
end
local OFF, LOW, FAIR, GOOD = G("VIDEO_OPTIONS_DISABLED", L["Disabled"]), G("VIDEO_OPTIONS_LOW", L["Low"]),
	G("VIDEO_OPTIONS_FAIR", L["Fair"]), G("VIDEO_OPTIONS_GOOD", L["Good"])
local HIGH, ULTRA, ULTRA_HIGH = G("VIDEO_OPTIONS_HIGH", L["High"]), G("VIDEO_OPTIONS_ULTRA", L["Ultra"]),
	G("VIDEO_OPTIONS_ULTRA_HIGH", L["Ultra High"])
local LEVELS = {
	shadow   = { [0] = LOW, FAIR, GOOD, HIGH, ULTRA, ULTRA_HIGH },
	offToUltra = { [0] = OFF, LOW, GOOD, HIGH, ULTRA },
	particle = { [0] = LOW, FAIR, GOOD, HIGH, ULTRA, ULTRA_HIGH },
	liquid   = { [0] = LOW, FAIR, GOOD, HIGH },
	depth    = { [0] = OFF, LOW, GOOD, HIGH },
	spell    = { [0] = L["Essential"], L["Some"], L["Half"], L["Most"], L["Dynamic"], L["Everything"] },
}

-- kind: "bool" | "number" | "enum"; enum with `levels` gets a dropdown, otherwise a slider.
-- restart = true: needs RestartGx()/client restart; never changed automatically.
local CVARS = {
	{ name = "useMaxFPS",               kind = "bool",   label = L["Limit foreground FPS"] },
	{ name = "maxFPS",                  kind = "number", label = L["Max foreground FPS"], min = 8, max = 300, bigStep = 5 },
	{ name = "useMaxFPSBk",             kind = "bool",   label = L["Limit background FPS"] },
	{ name = "maxFPSBk",                kind = "number", label = L["Max background FPS"], min = 8, max = 300, bigStep = 5 },
	{ name = "Brightness",              kind = "number", label = L["Brightness"], min = 0, max = 100, bigStep = 5 },
	{ name = "renderScale",             kind = "number", label = L["Render scale"], min = 0.33, max = 2.0, step = 0.01, bigStep = 0.05, percent = true },
	{ name = "graphicsShadowQuality",   kind = "enum",   label = L["Shadow quality"],      min = 0, max = 5, levels = LEVELS.shadow },
	{ name = "graphicsSSAO",            kind = "enum",   label = L["SSAO"],                min = 0, max = 4, levels = LEVELS.offToUltra },
	{ name = "graphicsParticleDensity", kind = "enum",   label = L["Particle density"],    min = 0, max = 5, levels = LEVELS.particle },
	{ name = "graphicsLiquidDetail",    kind = "enum",   label = L["Liquid detail"],       min = 0, max = 3, levels = LEVELS.liquid },
	-- Forever menu options; ranges seen with /jpm watch. Light mode also sets giQuality and
	-- RenderFormat, PBR liquid sets pbrLiquidDetail (kept safe as lower-level settings).
	{ name = "graphicsPBRLiquidDetail", kind = "enum",   label = L["PBR liquid detail"],   min = 0, max = 2 },
	{ name = "graphicsLightMode",       kind = "enum",   label = L["Secondary lighting"],  min = 0, max = 3 },
	{ name = "graphicsViewDistance",    kind = "enum",   label = L["View distance"],       min = 0, max = 9 },
	{ name = "graphicsEnvironmentDetail", kind = "enum", label = L["Environment detail"],  min = 0, max = 9 },
	{ name = "graphicsGroundClutter",   kind = "enum",   label = L["Ground clutter"],      min = 0, max = 9 },
	{ name = "graphicsSpellDensity",    kind = "enum",   label = L["Spell density"],       min = 0, max = 5, levels = LEVELS.spell },
	{ name = "graphicsComputeEffects",  kind = "enum",   label = L["Compute effects"],     min = 0, max = 4, levels = LEVELS.offToUltra },
	{ name = "graphicsDepthEffects",    kind = "enum",   label = L["Depth effects"],       min = 0, max = 3, levels = LEVELS.depth },
	-- Listed so the probe reports it, but never changed automatically: switching the preset
	-- overwrites the user's individual settings.
	{ name = "graphicsQuality",         kind = "enum",   label = L["Overall preset"], min = 1, max = 10, restart = true },
	{ name = "MSAAQuality",             kind = "enum",   label = L["MSAA"],           restart = true },
}

local byName = {}
for i, def in ipairs(CVARS) do
	def.order = i
	byName[def.name:lower()] = def
end

-- { [level] = "3 - High" } for a dropdown, or nil if the CVar has no level names.
function Registry:LevelValues(name)
	local def = self:Get(name)
	if not def or not def.levels then return nil end
	local values = {}
	for level = def.min or 0, def.max or 0 do
		local label = def.levels[level]
		values[level] = label and ("%d - %s"):format(level, label) or tostring(level)
	end
	return values
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
