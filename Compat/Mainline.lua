-- Mainline-family implementation: Forever (16001) and Midnight/Standard (12.x).
local _, ns = ...

local C_CVar = C_CVar
local UnitOnTaxi, InCombatLockdown = UnitOnTaxi, InCombatLockdown
local UnitAffectingCombat, UnitIsAFK, IsResting, UnitIsDeadOrGhost =
	UnitAffectingCombat, UnitIsAFK, IsResting, UnitIsDeadOrGhost

local impl = { name = "Mainline" }

-- Midnight-era clients (including Forever) return "secret values" for some unit data, mostly in
-- combat. Secrets can't be compared or tested, so anything we read goes through clean():
-- a secret becomes nil ("unknown").
local issecretvalue = issecretvalue
local function clean(v)
	if issecretvalue and issecretvalue(v) then return nil end
	return v
end
-- Boolean API result -> true/false, or `unknown` (default false) if the value is secret.
local function flag(v, unknown)
	if issecretvalue and issecretvalue(v) then return unknown or false end
	return v and true or false
end

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
	return flag(UnitOnTaxi("player"))
end

function impl.InCombat()
	return InCombatLockdown() and true or false
end

function impl.IsInCombat()
	if InCombatLockdown() then return true end
	return flag(UnitAffectingCombat("player"), true) -- secret almost certainly means in combat
end

function impl.IsAFK()
	return flag(UnitIsAFK("player"))
end

function impl.IsResting()
	return flag(IsResting())
end

function impl.IsDeadOrGhost()
	return flag(UnitIsDeadOrGhost("player"))
end

function impl.InCinematic()
	if InCinematic and InCinematic() then return true end
	if IsInCinematicScene and IsInCinematicScene() then return true end
	local movie = _G.MovieFrame
	return (movie and movie:IsShown()) and true or false
end

-- Each value may be nil when unknown (secret, or unavailable such as facing in instances).
function impl.GetActivitySnapshot()
	local moving
	if IsPlayerMoving then moving = clean(IsPlayerMoving()) end
	if moving == nil then
		local speed = clean(GetUnitSpeed("player"))
		if speed ~= nil then moving = speed > 0 end
	end
	-- A secret cast name counts as "not casting" (unknown); combat is handled by the Idle situation.
	local casting = clean(UnitCastingInfo("player")) ~= nil or clean(UnitChannelInfo("player")) ~= nil
	local x, y = GetCursorPosition()
	x, y = clean(x), clean(y)
	local facing = GetPlayerFacing and clean(GetPlayerFacing())
	return moving and true or false, casting and true or false, x, y, facing
end

-- Lower-level graphics CVars. Setting a graphics preset CVar (graphicsGroundClutter, ...) makes the
-- client overwrite the CVars it controls (groundEffectDensity, ...) with its own values, wiping
-- tweaks made with /console. We snapshot these and put them back after restoring the presets.
-- Source: every CVar in the client's Graphics console category, plus known ones as a fallback.
local KNOWN_DETAIL_CVARS = {
	"groundEffectDensity", "groundEffectDist", "groundEffectAnimation", "farclip", "horizonStart",
	"terrainLodDist", "wmoLodDist", "entityLodDist", "doodadLodDist", "lodObjectCullSize",
	"lodObjectMinSize", "particleDensity", "particleMTDensity", "weatherDensity", "shadowMode",
	"shadowTextureSize", "shadowSoft", "shadowBlendCascades", "waterDetail", "rippleDetail",
	"reflectionMode", "sunShafts", "ssao", "ssaoBlur", "spellClutter", "projectedTextures",
	"textureFilteringMode", "componentTextureLevel", "worldBaseMip",
}
local detailNames, detailFromConsole

local function getAllConsoleCommands()
	local fn = (C_Console and C_Console.GetAllCommands) or ConsoleGetAllCommands
	if not fn then return nil, "no GetAllCommands API" end
	local ok, commands = pcall(fn)
	if not ok then return nil, "GetAllCommands errored: " .. tostring(commands) end
	if type(commands) ~= "table" then return nil, "GetAllCommands returned " .. type(commands) end
	return commands
end

-- For /jpm probe: why the console list did or didn't work.
function impl.DescribeConsoleList()
	local commands, err = getAllConsoleCommands()
	if not commands then return err end
	local cvarType = Enum and Enum.ConsoleCommandType and Enum.ConsoleCommandType.Cvar
	local graphics = Enum and Enum.ConsoleCategory and Enum.ConsoleCategory.Graphics
	local first = commands[1]
	local fields = {}
	if type(first) == "table" then
		for k, v in pairs(first) do fields[#fields + 1] = ("%s=%s"):format(tostring(k), tostring(v)) end
		table.sort(fields)
	end
	local sample
	for _, c in ipairs(commands) do
		if type(c) == "table" and c.command == "groundEffectDensity" then
			sample = ("groundEffectDensity: type=%s category=%s"):format(tostring(c.commandType), tostring(c.category))
		end
	end
	return ("%d commands; Enum Cvar=%s Graphics=%s; first entry {%s}; %s"):format(#commands,
		tostring(cvarType), tostring(graphics), table.concat(fields, ", "), sample or "groundEffectDensity not listed")
end

function impl.GetDetailCVarNames()
	if detailNames then return detailNames, detailFromConsole end
	local names, seen = {}, {}
	local function add(name)
		if type(name) == "string" and not seen[name:lower()] then
			seen[name:lower()] = true
			names[#names + 1] = name
		end
	end
	detailFromConsole = 0
	local cvarType = Enum and Enum.ConsoleCommandType and Enum.ConsoleCommandType.Cvar
	local graphics = Enum and Enum.ConsoleCategory and Enum.ConsoleCategory.Graphics
	local commands = getAllConsoleCommands()
	if commands and cvarType and graphics then
		for _, c in ipairs(commands) do
			if type(c) == "table" and c.commandType == cvarType and c.category == graphics then
				add(c.command)
				detailFromConsole = detailFromConsole + 1
			end
		end
	end
	for _, name in ipairs(KNOWN_DETAIL_CVARS) do add(name) end
	detailNames = names
	return names, detailFromConsole
end

-- Service windows (auction house, mail, bank, vendor...).
-- Tracked from two sources, because not every window reports through the interaction manager on
-- every client (e.g. the bank on Forever): the PLAYER_INTERACTION_MANAGER_FRAME_SHOW/HIDE events
-- and the older per-window events. Both map to the same window name, so a close from either
-- source closes it.
local SERVICE_TYPES = {
	-- Forever's bank reports as CharacterBanker (67), verified in Ratchet.
	Auctioneer = "auction", MailInfo = "mail", Banker = "bank", CharacterBanker = "bank", AccountBanker = "bank",
	GuildBanker = "guildbank", Merchant = "merchant",
}
local LEGACY_EVENTS = {
	BANKFRAME_OPENED = { "bank", true },          BANKFRAME_CLOSED = { "bank", false },
	MAIL_SHOW = { "mail", true },                 MAIL_CLOSED = { "mail", false },
	AUCTION_HOUSE_SHOW = { "auction", true },     AUCTION_HOUSE_CLOSED = { "auction", false },
	MERCHANT_SHOW = { "merchant", true },         MERCHANT_CLOSED = { "merchant", false },
	GUILDBANKFRAME_OPENED = { "guildbank", true }, GUILDBANKFRAME_CLOSED = { "guildbank", false },
}
local serviceTypes, typeNames, openWindows = {}, {}, {}

function impl.IsServiceWindowOpen()
	return next(openWindows) ~= nil
end

function impl.Init(notify)
	local types = Enum and Enum.PlayerInteractionType
	if types then
		for name, id in pairs(types) do typeNames[id] = name end
		for name, window in pairs(SERVICE_TYPES) do
			if types[name] then serviceTypes[types[name]] = window end
		end
	end
	local frame = CreateFrame("Frame")
	frame:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
	frame:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE")
	frame:RegisterEvent("PLAYER_ENTERING_WORLD")
	for event in pairs(LEGACY_EVENTS) do
		pcall(frame.RegisterEvent, frame, event) -- an event may not exist on every client
	end
	frame:SetScript("OnEvent", function(_, event, arg1)
		if event == "PLAYER_ENTERING_WORLD" then
			wipe(openWindows)
			return
		end
		local key, open
		if event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" or event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
			open = event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW"
			ns.addon:Debug("Interaction window %s: %s (%s)%s", open and "shown" or "hidden",
				tostring(typeNames[arg1] or "?"), tostring(arg1), serviceTypes[arg1] and "" or ", not tracked")
			if not serviceTypes[arg1] then return end
			key = serviceTypes[arg1]
		else
			local info = LEGACY_EVENTS[event]
			if not info then return end
			key, open = info[1], info[2]
			ns.addon:Debug("Window event %s", event)
		end
		local was = openWindows[key] or false
		openWindows[key] = open or nil
		if was ~= open then notify("service window " .. key) end
	end)
end

ns.Compat:Register(impl)
