-- Known graphics CVars. Profiles refer to these keys; the Applier only touches CVars listed here
-- that exist on the running client. Names must be confirmed per flavor with `/jpm probe`.
local _, ns = ...

local Registry = {}
ns.CVarRegistry = Registry

-- kind: "bool" | "number" | "enum"
-- restart = true: needs RestartGx()/client restart; never changed automatically.
local CVARS = {
	{ name = "useMaxFPS",               kind = "bool",   label = "Limit foreground FPS" },
	{ name = "maxFPS",                  kind = "number", label = "Max foreground FPS", min = 8, max = 300, bigStep = 5 },
	{ name = "useMaxFPSBk",             kind = "bool",   label = "Limit background FPS" },
	{ name = "maxFPSBk",                kind = "number", label = "Max background FPS", min = 8, max = 300, bigStep = 5 },
	{ name = "renderScale",             kind = "number", label = "Render scale", min = 0.33, max = 2.0, step = 0.01, bigStep = 0.05, percent = true },
	{ name = "graphicsShadowQuality",   kind = "enum",   label = "Shadow quality",      min = 0, max = 5 },
	{ name = "graphicsSSAO",            kind = "enum",   label = "SSAO",                min = 0, max = 4 },
	{ name = "graphicsParticleDensity", kind = "enum",   label = "Particle density",    min = 0, max = 5 },
	{ name = "graphicsLiquidDetail",    kind = "enum",   label = "Liquid detail",       min = 0, max = 3 },
	{ name = "graphicsViewDistance",    kind = "enum",   label = "View distance",       min = 0, max = 9 },
	{ name = "graphicsEnvironmentDetail", kind = "enum", label = "Environment detail",  min = 0, max = 9 },
	{ name = "graphicsGroundClutter",   kind = "enum",   label = "Ground clutter",      min = 0, max = 9 },
	{ name = "graphicsSpellDensity",    kind = "enum",   label = "Spell density",       min = 0, max = 5 },
	{ name = "graphicsComputeEffects",  kind = "enum",   label = "Compute effects",     min = 0, max = 4 },
	{ name = "graphicsDepthEffects",    kind = "enum",   label = "Depth effects",       min = 0, max = 3 },
	-- Listed so the probe reports it, but never changed automatically: switching the preset
	-- overwrites the user's individual settings.
	{ name = "graphicsQuality",         kind = "enum",   label = "Overall preset", min = 1, max = 10, restart = true },
	{ name = "MSAAQuality",             kind = "enum",   label = "MSAA",           restart = true },
}

local byName = {}
for i, def in ipairs(CVARS) do
	def.order = i
	byName[def.name:lower()] = def
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
