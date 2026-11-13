-- Mainline-family implementation: Forever (16001) and Midnight/Standard (12.x).
local _, ns = ...

local C_CVar = C_CVar
local UnitOnTaxi, InCombatLockdown = UnitOnTaxi, InCombatLockdown

local impl = { name = "Mainline" }

function impl.IsSupported()
	-- Feature check rather than WOW_PROJECT_ID: Forever reported different project IDs across builds.
	return C_CVar ~= nil and C_CVar.GetCVarInfo ~= nil and C_CVar.SetCVar ~= nil
end

function impl.GetCVar(name)
	return C_CVar.GetCVar(name)
end

function impl.SetCVar(name, value)
	local ok, result = pcall(C_CVar.SetCVar, name, tostring(value))
	-- C_CVar.SetCVar returns a success boolean on Mainline; treat nil as success for older builds.
	return ok and result ~= false
end

function impl.GetCVarInfo(name)
	local value, default, _, _, isLocked, isSecure, isReadOnly = C_CVar.GetCVarInfo(name)
	if value == nil then return nil end
	return {
		value = value,
		default = default,
		isLocked = isLocked and true or false,
		isSecure = isSecure and true or false,
		isReadOnly = isReadOnly and true or false,
	}
end

function impl.IsOnTaxi()
	return UnitOnTaxi("player") and true or false
end

function impl.InCombat()
	return InCombatLockdown() and true or false
end

ns.Compat:Register(impl)
