-- Minimal WoW API mock that loads the addon (per the Forever TOC) and checks its behaviour.
-- Usage: scripts/fetch-libs.sh && luajit tests/harness.lua .
local ROOT = arg[1] or "."
local now = 0
local timers = {}
local frames = {}
local printed = {}
SavedDB = SavedDB -- carried between "sessions"

function print(...) local t = {} for i = 1, select("#", ...) do t[#t+1] = tostring((select(i, ...))) end
	local line = table.concat(t, " "):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	printed[#printed+1] = line; io.write("    > ", line, "\n") end

-- Lua/WoW globals
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
strmatch, strsub, strfind, strlower, strupper, format = string.match, string.sub, string.find, string.lower, string.upper, string.format
tinsert, tremove = table.insert, table.remove
geterrorhandler = function() return function(e) io.write("  LUA ERROR: ", tostring(e), "\n"); FAILED = true end end
securecallfunction = function(f, ...) return f(...) end
securecall = securecallfunction
hooksecurefunc = function() end
issecurevariable = function() return false end
IsLoggedIn = function() return false end
GetLocale = function() return "enUS" end
GetRealmName = function() return "Realm" end
GetNormalizedRealmName = GetRealmName
UnitName = function() return "Tester" end
UnitNameUnmodified = UnitName
strlenutf8 = function(s) return #s end
UnitClass = function() return "Warrior", "WARRIOR" end
UnitRace = function() return "Human", "Human" end
UnitFactionGroup = function() return "Alliance" end
GetCurrentRegion = function() return 3 end
GetCurrentRegionName = function() return "EU" end
GetBuildInfo = function() return "1.60.1", "70338", "Nov 2026", 16001 end
GetTime = function() return now end
WOW_PROJECT_ID = 18
SlashCmdList, hash_SlashCmdList = {}, {}
C_AddOns = { GetAddOnMetadata = function() return "@project-version@" end }

local combat, taxi = false, false
local afk, resting, dead, cine, moving = false, false, false, false, false
local cx, cy = 500, 400
InCombatLockdown = function() return combat end
UnitOnTaxi = function() return taxi end
UnitAffectingCombat = function() return combat end
UnitIsAFK = function() return afk end
IsResting = function() return resting end
UnitIsDeadOrGhost = function() return dead end
IsPlayerMoving = function() return moving end
-- Secret values: in combat, these return a userdata that errors when compared.
local SECRET = setmetatable({}, { __lt = function() error("attempt to compare a secret number value") end,
	__le = function() error("attempt to compare a secret number value") end })
issecretvalue = function(v) return v == SECRET end
GetUnitSpeed = function() if combat then return SECRET end return moving and 7 or 0 end
UnitCastingInfo = function() if combat then return SECRET end return nil end
UnitChannelInfo = function() return nil end
GetCursorPosition = function() return cx, cy end
GetPlayerFacing = function() return 1.5 end
InCinematic = function() return cine end
Enum = { PlayerInteractionType = { Merchant = 5, Banker = 8, MailInfo = 17, Auctioneer = 21, CharacterBanker = 67 } }

-- CVars
local cvars = {
	useMaxFPS = "0", maxFPS = "144", useMaxFPSBk = "1", maxFPSBk = "30", renderScale = "1",
	graphicsShadowQuality = "4", graphicsSSAO = "3", graphicsParticleDensity = "4",
	graphicsLiquidDetail = "2", graphicsSpellDensity = "5", graphicsQuality = "7",
}
local secure = { renderScale = true }
local function fire(event, ...)
	for _, f in ipairs(frames) do
		if f.events[event] and f.script then f.script(f, event, ...) end
	end
end
C_CVar = {
	GetCVar = function(n) return cvars[n] end,
	SetCVar = function(n, v)
		if cvars[n] == nil then return false end
		if secure[n] and combat then error("blocked: secure cvar in combat") end
		cvars[n] = tostring(v); fire("CVAR_UPDATE", n, tostring(v)); return true
	end,
	GetCVarInfo = function(n)
		if cvars[n] == nil then return nil end
		return cvars[n], "0", false, false, false, secure[n] or false, false
	end,
}

-- Frames / timers
function CreateFrame()
	local f = { events = {} }
	function f:RegisterEvent(e) self.events[e] = true end
	function f:UnregisterEvent(e) self.events[e] = nil end
	function f:UnregisterAllEvents() self.events = {} end
	function f:IsEventRegistered(e) return self.events[e] end
	function f:SetScript(_, fn) self.script = fn end
	function f:GetScript() return self.script end
	function f:Show() end function f:Hide() end
	frames[#frames+1] = f
	return f
end
C_Timer = {
	After = function(d, fn) timers[#timers+1] = { at = now + d, fn = fn } end,
	NewTimer = function(d, fn) local t = { at = now + d, fn = fn }
		function t:Cancel() self.cancelled = true end timers[#timers+1] = t return t end,
	NewTicker = function(d, fn, n) local t = { at = now + d, fn = fn, every = d, n = n }
		function t:Cancel() self.cancelled = true end timers[#timers+1] = t return t end,
}
local function advance(sec)
	local target = now + sec
	while true do
		table.sort(timers, function(a, b) return a.at < b.at end)
		local t = timers[1]
		if not t or t.at > target then break end
		table.remove(timers, 1)
		now = t.at
		if not t.cancelled then
			t.fn(t)
			if t.every and not t.cancelled then t.at = now + t.every; timers[#timers+1] = t end
		end
	end
	now = target
end

-- Loader
local function loadFile(path, ...)
	local chunk = assert(loadfile(ROOT .. "/" .. path:gsub("\\", "/")))
	return chunk(...)
end
local function loadXml(path)
	local dir = path:match("^(.*)[/\\]") or ""
	local f = assert(io.open(ROOT .. "/" .. path:gsub("\\", "/")))
	local text = f:read("*a"); f:close()
	for tag, file in text:gmatch('<(%a+) file="([^"]+)"') do
		local full = (dir ~= "" and dir .. "\\" or "") .. file
		if tag == "Script" then loadFile(full) elseif tag == "Include" then loadXml(full) end
	end
end

local function session(label)
	io.write("\n== ", label, "\n")
	frames, timers, printed = {}, {}, {}
	LibStub, JimPowerMizer, JimPowerMizerDB = nil, nil, SavedDB
	local ns = {}
	local f = assert(io.open(ROOT .. "/JimPowerMizer_Forever.toc"))
	for line in f:lines() do
		if line ~= "" and not line:match("^#") then
			if line:match("%.xml$") then loadXml(line) else loadFile(line, "JimPowerMizer", ns) end
		end
	end
	f:close()
	fire("ADDON_LOADED", "JimPowerMizer")
	IsLoggedIn = function() return true end
	fire("PLAYER_LOGIN")
	fire("PLAYER_ENTERING_WORLD", true, false)
	ns.addon.db.profile.debug = true
	advance(0.1)
	return ns
end

local function noErrors(label)
	for _, line in ipairs(printed) do
		if line:find("errored") then
			io.write("  FAIL ", label, ": ", line, "\n"); FAILED = true; return
		end
	end
	io.write("  PASS ", label, ": no situation errors\n")
end
local function check(cond, msg) io.write(cond and "  PASS " or "  FAIL ", msg, "\n"); if not cond then FAILED = true end end
local function slash(s) SlashCmdList["ACECONSOLE_JPM"](s) end

-- Session 1 --------------------------------------------------------------
IsLoggedIn = function() return false end
local ns = session("session 1: normal flight")
check(cvars.maxFPS == "144", "baseline untouched at login")
advance(ns.STARTUP_GRACE)
taxi = true; fire("PLAYER_CONTROL_LOST"); advance(1)
check(cvars.maxFPS == "144", "no switch before enterDelay")
advance(2.5)
check(cvars.maxFPS == "20" and cvars.useMaxFPS == "1" and cvars.renderScale == "0.5", "Max saver applied on taxi")
check(cvars.useMaxFPSBk == "1" and cvars.maxFPSBk == "20", "background FPS capped to foreground cap")
check(cvars.graphicsQuality == "7", "graphicsQuality never touched")
taxi = false; fire("PLAYER_CONTROL_GAINED"); advance(0.1)
check(cvars.maxFPS == "144" and cvars.useMaxFPS == "0" and cvars.renderScale == "1" and cvars.graphicsShadowQuality == "4", "all restored after landing")
check(cvars.maxFPSBk == "30", "background FPS cap restored")
check(next(JimPowerMizerDB.global.state.baseline) == nil, "baseline cleared")

-- User changes a managed CVar mid-flight
taxi = true; advance(4)
check(cvars.maxFPS == "20", "applied again (poll fallback, no event)")
C_CVar.SetCVar("graphicsShadowQuality", "2") -- user edits in Blizzard settings
taxi = false; advance(2.1)
check(cvars.graphicsShadowQuality == "2", "user's mid-flight change kept")
check(cvars.maxFPS == "144", "others restored")

-- Combat: secure CVar deferred
taxi = true; advance(4)
combat = true; taxi = false; fire("PLAYER_REGEN_DISABLED"); advance(2.1)
check(cvars.maxFPS == "144", "non-secure restored in combat")
check(cvars.renderScale == "0.5", "secure renderScale deferred in combat")
combat = false; fire("PLAYER_REGEN_ENABLED"); advance(0.1)
check(cvars.renderScale == "1", "renderScale restored after combat")

-- Force + status + probe
slash("force taxi"); advance(0.1)
check(cvars.maxFPS == "20", "/jpm force taxi applies")
slash("status")
slash("force off"); advance(0.1)
check(cvars.maxFPS == "144", "/jpm force off restores")
slash("probe")
check(cvars.maxFPSBk == "30", "probe left maxFPSBk unchanged")
slash("off"); taxi = true; advance(5)
check(cvars.maxFPS == "144", "/jpm off: no switching")
slash("on"); advance(2.5)
check(cvars.maxFPS == "20", "/jpm on: switching again")

noErrors("session 1")

-- Crash while on taxi: no PLAYER_LOGOUT. Pretend the game kept the reduced values.
SavedDB = JimPowerMizerDB
taxi = false
ns = session("session 2: after crash")
check(cvars.maxFPS == "20", "leftover values kept during startup grace")
advance(ns.STARTUP_GRACE)
check(cvars.maxFPS == "144" and cvars.renderScale == "1", "crash recovery restored settings at login")
check(next(JimPowerMizerDB.global.state.baseline) == nil, "baseline cleared after recovery")

-- Logout while on taxi: values restored for Config.wtf, baseline kept
taxi = true; advance(4)
fire("PLAYER_LOGOUT")
check(cvars.maxFPS == "144", "logout writes user values back")
local function dump(t, ind) ind = ind or "" for k, v in pairs(t) do if type(v) == "table" then io.write(ind, tostring(k), ":\n") dump(v, ind .. "  ") else io.write(ind, tostring(k), "=", tostring(v), "\n") end end end

check(next(JimPowerMizerDB.global.state.baseline) ~= nil, "baseline kept through logout")
SavedDB = JimPowerMizerDB
ns = session("session 3: log in again, still on taxi")
check(cvars.maxFPS == "20", "reapplied immediately on login while on taxi")
advance(ns.STARTUP_GRACE + 1)
check(cvars.maxFPS == "20", "grace-period recovery didn't undo the taxi profile")
taxi = false; advance(2.1)
check(cvars.maxFPS == "144" and cvars.renderScale == "1" and cvars.graphicsShadowQuality == "2" and cvars.maxFPSBk == "30", "final restore matches user settings")

-- Background cap not raised: user's background cap already lower than the profile's foreground cap
cvars.maxFPSBk = "10"; taxi = true; advance(2.5)
check(cvars.maxFPSBk == "10", "lower user background cap left alone")
taxi = false; advance(2.1)

noErrors("session 3")

-- Session 4: M2 situations ------------------------------------------------------
JimPowerMizerDB = nil; SavedDB = nil
ns = session("session 4: idle, combat, cinematic, service windows, resting, dead")
local function poke() cx = cx + 10 end -- user moves the mouse
advance(ns.STARTUP_GRACE)
slash("idle 30"); poke(); advance(1.1)
advance(28)
check(cvars.maxFPS == "144", "not idle before timeout")
advance(3)
check(cvars.maxFPS == "20", "idle after 30 s without input -> Max saver")
poke(); advance(1.1)
check(cvars.maxFPS == "144", "mouse movement ends idle within 1 s")
moving = true; advance(20); moving = false; advance(15)
check(cvars.maxFPS == "144", "movement counts as input")
afk = true; fire("PLAYER_FLAGS_CHANGED", "player"); advance(6)
check(cvars.maxFPS == "20", "AFK flag -> idle after 5 s")
combat = true; fire("PLAYER_REGEN_DISABLED"); advance(0.1)
check(cvars.maxFPS == "144" and cvars.renderScale == "0.5", "combat restores at once (secure renderScale deferred)")
combat = false; afk = false; poke(); fire("PLAYER_REGEN_ENABLED"); advance(1.1)
check(cvars.maxFPS == "144" and cvars.renderScale == "1", "after combat, active again -> your settings")
slash("idle 600")

taxi = true; fire("PLAYER_CONTROL_LOST"); advance(2.5)
check(cvars.maxFPS == "20", "taxi -> Max saver")
cine = true; fire("CINEMATIC_START"); advance(0.1)
check(cvars.maxFPS == "144", "cinematic on a flight -> your settings")
cine = false; fire("CINEMATIC_STOP"); advance(0.1)
check(cvars.maxFPS == "20", "cinematic over -> back to Max saver")
taxi = false; fire("PLAYER_CONTROL_GAINED"); advance(0.1)
check(cvars.maxFPS == "144", "landed")

fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 21); advance(2)
check(cvars.maxFPS == "144", "service window ignored while disabled (default)")
fire("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 21)
slash("enable serviceWindow")
fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 21); advance(0.5)
check(cvars.maxFPS == "144", "service window: waits for enter delay")
advance(1)
check(cvars.maxFPS == "30" and cvars.renderScale == "1", "auction house open -> Light saver")
fire("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 21); advance(0.1)
check(cvars.maxFPS == "144", "auction house closed -> your settings")
fire("BANKFRAME_OPENED"); advance(1.1)
check(cvars.maxFPS == "30", "bank via legacy BANKFRAME_OPENED -> Light saver")
fire("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 8); advance(0.1)
check(cvars.maxFPS == "144", "bank opened by legacy event, closed by interaction event")
fire("MAIL_SHOW"); fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 17); advance(1.1)
check(cvars.maxFPS == "30", "mail open (both sources)")
fire("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 17); advance(0.1)
check(cvars.maxFPS == "144", "mail closed by one source only -> not stuck open")
fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 67); advance(1.1)
check(cvars.maxFPS == "30", "Forever bank (CharacterBanker 67) -> Light saver")
fire("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 67); advance(0.1)
check(cvars.maxFPS == "144", "Forever bank closed")

slash("enable resting")
resting = true; fire("PLAYER_UPDATE_RESTING"); advance(5.5)
check(cvars.maxFPS == "30", "resting -> Light saver")
taxi = true; fire("PLAYER_CONTROL_LOST"); advance(2.5)
check(cvars.maxFPS == "20", "taxi outranks resting")
taxi = false; advance(2.1)
check(cvars.maxFPS == "30", "back to resting after taxi")
resting = false; fire("PLAYER_UPDATE_RESTING"); advance(0.1)

slash("enable dead")
dead = true; fire("PLAYER_DEAD"); advance(3.5)
check(cvars.maxFPS == "30", "dead -> Light saver")
dead = false; fire("PLAYER_ALIVE"); advance(0.1)
check(cvars.maxFPS == "144" and next(JimPowerMizerDB.global.state.baseline) == nil, "alive -> your settings, baseline clear")
slash("list")
noErrors("session 4")

io.write(FAILED and "\nSOME CHECKS FAILED\n" or "\nALL CHECKS PASSED\n")
os.exit(FAILED and 1 or 0)
