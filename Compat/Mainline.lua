-- Mainline-family implementation: Forever (16001) and Midnight/Standard (12.x).
local _, ns = ...

local C_CVar = C_CVar
local UnitOnTaxi, InCombatLockdown = UnitOnTaxi, InCombatLockdown
local UnitAffectingCombat, UnitIsAFK, IsResting, UnitIsDeadOrGhost =
	UnitAffectingCombat, UnitIsAFK, IsResting, UnitIsDeadOrGhost

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

function impl.IsInCombat()
	return (UnitAffectingCombat("player") or InCombatLockdown()) and true or false
end

function impl.IsAFK()
	return UnitIsAFK("player") and true or false
end

function impl.IsResting()
	return IsResting() and true or false
end

function impl.IsDeadOrGhost()
	return UnitIsDeadOrGhost("player") and true or false
end

function impl.InCinematic()
	if InCinematic and InCinematic() then return true end
	if IsInCinematicScene and IsInCinematicScene() then return true end
	local movie = _G.MovieFrame
	return (movie and movie:IsShown()) and true or false
end

function impl.GetActivitySnapshot()
	local moving = (IsPlayerMoving and IsPlayerMoving()) or (GetUnitSpeed("player") or 0) > 0
	local casting = UnitCastingInfo("player") ~= nil or UnitChannelInfo("player") ~= nil
	local x, y = GetCursorPosition()
	local facing = GetPlayerFacing and GetPlayerFacing() -- nil in instances
	return moving and true or false, casting, x, y, facing
end

-- Service windows (auction house, mail, bank, vendor...) via the interaction manager events.
local SERVICE_TYPES = { "Auctioneer", "MailInfo", "Banker", "AccountBanker", "GuildBanker", "Merchant" }
local serviceTypes, openWindows = {}, {}

function impl.IsServiceWindowOpen()
	return next(openWindows) ~= nil
end

function impl.Init(notify)
	local types = Enum and Enum.PlayerInteractionType
	if types then
		for _, name in ipairs(SERVICE_TYPES) do
			if types[name] then serviceTypes[types[name]] = name end
		end
	end
	local frame = CreateFrame("Frame")
	frame:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
	frame:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE")
	frame:RegisterEvent("PLAYER_ENTERING_WORLD")
	frame:SetScript("OnEvent", function(_, event, interactionType)
		if event == "PLAYER_ENTERING_WORLD" then
			wipe(openWindows)
		elseif serviceTypes[interactionType] then
			openWindows[interactionType] = (event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW") or nil
			notify("service window " .. serviceTypes[interactionType])
		end
	end)
end

ns.Compat:Register(impl)
