-- Compatibility layer: the ONLY place that should know about game flavors.
-- The rest of the addon calls ns.Compat:<Function>(). Each flavor file (Compat/Mainline.lua,
-- later Compat/Classic.lua) calls ns.Compat:Register(impl) with an implementation table.
local _, ns = ...

local Compat = { name = "none" }
ns.Compat = Compat

local REQUIRED = {
	"GetCVar",        -- (name) -> string|nil
	"SetCVar",        -- (name, value) -> boolean success
	"GetCVarInfo",    -- (name) -> table|nil { value, default, isSecure, isReadOnly, isLocked }
	"IsOnTaxi",       -- () -> boolean
	"InCombat",       -- () -> boolean (combat lockdown: protected actions blocked)
	"IsInCombat",     -- () -> boolean (player is in combat; true slightly before lockdown)
	"IsAFK",          -- () -> boolean
	"IsResting",      -- () -> boolean (inn / city)
	"IsDeadOrGhost",  -- () -> boolean
	"InCinematic",    -- () -> boolean (in-game cinematic or pre-rendered movie)
	"IsServiceWindowOpen", -- () -> boolean (auction house, mail, bank, vendor, ...)
	"GetActivitySnapshot", -- () -> moving, casting, cursorX, cursorY, facing (facing may be nil)
	"GetCascadeCandidates", -- () -> delayedNames, syncNames, countFromConsole (see Applier)
}

local candidates = {}

-- impl.name: string; impl.IsSupported(): boolean; plus the REQUIRED functions.
function Compat:Register(impl)
	candidates[#candidates + 1] = impl
end

function Compat:Init()
	for _, impl in ipairs(candidates) do
		if impl.IsSupported() then
			for _, fn in ipairs(REQUIRED) do
				assert(type(impl[fn]) == "function", ("Compat %s is missing %s"):format(impl.name, fn))
				self[fn] = function(_, ...) return impl[fn](...) end
			end
			self.name = impl.name
			self.impl = impl
			-- Optional: lets the implementation tell the Engine its state changed (event-driven
			-- trackers such as the service-window one).
			if impl.Init then
				impl.Init(function(reason)
					if ns.Engine and ns.Engine:IsEnabled() then ns.Engine:Evaluate(reason) end
				end)
			end
			return
		end
	end
	error("JimPowerMizer: no compatibility layer supports this client")
end
