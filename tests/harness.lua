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
local facing = 1.5
GetPlayerFacing = function() return facing end
InCinematic = function() return cine end
-- Like Forever: the global ConsoleGetAllCommands (no C_Console), and groundEffectDensity filed
-- under Default (5) rather than Graphics (1), alongside unrelated CVars.
ConsoleGetAllCommands = function()
	return {
		{ command = "groundEffectDensity", commandType = 0, category = 5 },
		{ command = "groundEffectDist", commandType = 0, category = 5 },
		{ command = "lastSeenThing", commandType = 0, category = 5 },
		{ command = "chatStyleThing", commandType = 0, category = 5 },
		{ command = "gxWindow", commandType = 0, category = 1 },
		{ command = "graphicsGroundClutter", commandType = 0, category = 1 },
		{ command = "someSoundThing", commandType = 0, category = 7 },
	}
end
Enum = { ConsoleCommandType = { Cvar = 0 }, ConsoleCategory = { Graphics = 1, Default = 5, Sound = 7 }, PlayerInteractionType = { Merchant = 5, Banker = 8, MailInfo = 17, Auctioneer = 21, CharacterBanker = 67 } }

-- CVars
local cvars = {
	useMaxFPS = "0", maxFPS = "144", useMaxFPSBk = "1", maxFPSBk = "30", renderScale = "1",
	graphicsShadowQuality = "4", graphicsSSAO = "3", graphicsParticleDensity = "4",
	graphicsLiquidDetail = "2", graphicsSpellDensity = "5", graphicsQuality = "7",
	graphicsGroundClutter = "9", graphicsViewDistance = "9",
	-- Lower-level settings: user's /console tweaks, different from what the presets would set.
	groundEffectDensity = "256", groundEffectDist = "300", farclip = "5000", gxWindow = "1",
	lastSeenThing = "a", chatStyleThing = "x", -- unrelated Default-category CVars
}
local secure = { renderScale = true }
local function fire(event, ...)
	for _, f in ipairs(frames) do
		if f.events[event] and f.script then f.script(f, event, ...) end
	end
end
local SetCVarRaw
-- Presets overwrite the settings under them, like the real client: Ground Clutter at once,
-- View Distance a moment later (to test the delayed second pass).
local CASCADE = {
	graphicsGroundClutter = function(level) SetCVarRaw("groundEffectDensity", level * 16); SetCVarRaw("groundEffectDist", level * 20) end,
	graphicsViewDistance = function(level) C_Timer.After(0.1, function() SetCVarRaw("farclip", level * 500) end) end,
}
function SetCVarRaw(n, v)
	cvars[n] = tostring(v); fire("CVAR_UPDATE", n, tostring(v))
end
C_CVar = {
	GetCVar = function(n) return cvars[n] end,
	SetCVar = function(n, v)
		if cvars[n] == nil then return false end
		if secure[n] and combat then error("blocked: secure cvar in combat") end
		SetCVarRaw(n, v)
		if CASCADE[n] then CASCADE[n](tonumber(v)) end
		return true
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
	f.shown, f.alpha, f.hooks = true, 1, {}
	function f:Show() local was = self.shown; self.shown = true
		if not was then for _, h in ipairs(self.hooks.OnShow or {}) do h(self) end end end
	function f:Hide() self.shown = false end
	function f:IsShown() return self.shown end
	function f:HookScript(s, fn) self.hooks[s] = self.hooks[s] or {}; table.insert(self.hooks[s], fn) end
	function f:SetAlpha(a) self.alpha = a end function f:GetAlpha() return self.alpha end
	function f:SetFrameStrata() end function f:SetAllPoints() end function f:EnableMouse() end
	function f:CreateTexture() return { SetAllPoints = function() end, SetColorTexture = function() end } end
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
	local text = f:read("*a"):gsub("<!%-%-.-%-%->", ""); f:close()
	for tag, file in text:gmatch('<(%a+) file="([^"]+)"') do
		local full = (dir ~= "" and dir .. "\\" or "") .. file
		-- The GUI libraries need a real UI; the dialog is replaced by a stub below.
		if full:find("AceGUI") or full:find("AceConfigDialog") then
			if full:find("AceConfigDialog") and not LibStub("AceConfigDialog-3.0", true) then
				local dlg = LibStub:NewLibrary("AceConfigDialog-3.0", 1)
				dlg.OpenFrames = {}
				function dlg:AddToBlizOptions() end
				function dlg:SetDefaultSize() end
				function dlg:SelectGroup(_, ...) self.selected = { ... } end
				function dlg:Open(app) self.OpenFrames[app] = true end
				function dlg:Close(app) self.OpenFrames[app] = nil end
			end
		elseif tag == "Script" then loadFile(full) elseif tag == "Include" then loadXml(full) end
	end
end

local function session(label)
	io.write("\n== ", label, "\n")
	frames, timers, printed = {}, {}, {}
	LibStub, JimPowerMizer, JimPowerMizerDB = nil, nil, SavedDB
	UIParent, WorldFrame = CreateFrame(), CreateFrame()
	UIParent.Hide = function(self) if combat then error("blocked: UIParent:Hide() in combat") end self.shown = false end
	UIParent.Show = function(self) if combat then error("blocked: UIParent:Show() in combat") end
		local was = self.shown; self.shown = true
		if not was then for _, h in ipairs(self.hooks.OnShow or {}) do h(self) end end end
	local ns = {}
	local f = assert(io.open(ROOT .. "/JimPowerMizer_Mainline.toc"))
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
local function poke() fire("PLAYER_TARGET_CHANGED") end -- user does something
advance(ns.STARTUP_GRACE)
slash("idle 30"); poke(); advance(1.1)
advance(28)
check(cvars.maxFPS == "144", "not idle before timeout")
advance(3)
check(cvars.maxFPS == "20", "idle after 30 s without input -> Max saver")
cx = cx + 50; facing = facing + 1; fire("PLAYER_STARTED_LOOKING"); advance(1.1)
check(cvars.maxFPS == "20", "mouse/camera movement doesn't end idle (default)")
moving = true; facing = facing + 1; advance(5) -- carried by a ship: poll says moving, facing changes
check(cvars.maxFPS == "20", "being carried by a ship/zeppelin doesn't end idle")
moving = false
poke(); advance(0.1)
check(cvars.maxFPS == "144", "changing target ends idle at once")
moving = true; fire("PLAYER_STARTED_MOVING"); advance(40)
check(cvars.maxFPS == "144", "running continuously for longer than the timeout keeps you active")
moving = false; fire("PLAYER_STOPPED_MOVING"); advance(31)
check(cvars.maxFPS == "20", "idle again 30 s after stopping")
moving = true; fire("PLAYER_STARTED_MOVING"); advance(0.1)
check(cvars.maxFPS == "144", "moving your character ends idle at once")
moving = false; advance(1.1) -- STOPPED_MOVING missed: the poll clears it
advance(31)
check(cvars.maxFPS == "20", "missed STOPPED_MOVING doesn't block idle")
ns.addon.db.profile.situations.idle.mouseActivity = true
cx = cx + 50; advance(1.1)
check(cvars.maxFPS == "144", "with the mouse option on, mouse movement ends idle")
ns.addon.db.profile.situations.idle.mouseActivity = false
poke(); advance(1.1)
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

-- Session 6: lower-level (/console) settings ------------------------------------------
JimPowerMizerDB = nil; SavedDB = nil
taxi, afk, resting, dead, combat = false, false, false, false, false
ns = session("session 6: /console tweaks under presets")
advance(ns.STARTUP_GRACE); poke()
check(cvars.groundEffectDensity == "256" and cvars.farclip == "5000", "start with custom console values")
taxi = true; fire("PLAYER_CONTROL_LOST"); advance(2.5)
check(cvars.graphicsGroundClutter == "0" and cvars.groundEffectDensity == "0", "saver: clutter 0 cascades density down")
check(cvars.farclip == "1000", "saver: view distance cascades farclip down (delayed)")
cvars.chatStyleThing = "y" -- changed by something else mid-flight
taxi = false; fire("PLAYER_CONTROL_GAINED")
C_Timer.After(0.2, function() SetCVarRaw("lastSeenThing", "b") end) -- unrelated change just after landing
advance(0.01)
check(cvars.graphicsGroundClutter == "9" and cvars.groundEffectDensity == "256" and cvars.groundEffectDist == "300", "restore: custom density/dist put back at once")
advance(0.6)
check(cvars.farclip == "5000", "restore: delayed cascade on farclip undone by 2nd pass")
check(cvars.gxWindow == "1", "display settings untouched")
check(cvars.chatStyleThing == "y" and cvars.lastSeenThing == "b", "unrelated Default-category changes not reverted")
check(next(JimPowerMizerDB.global.state.detail) == nil, "detail snapshot cleared after restore")
-- User changes a console setting while nothing is active: next snapshot picks it up
cvars.groundEffectDensity = "200"
taxi = true; fire("PLAYER_CONTROL_LOST"); advance(2.5)
taxi = false; fire("PLAYER_CONTROL_GAINED"); advance(0.6)
check(cvars.groundEffectDensity == "200", "new console value captured at next switch")
-- Crash mid-flight: details recovered on next login
taxi = true; fire("PLAYER_CONTROL_LOST"); advance(2.5)
check(cvars.groundEffectDensity == "0", "saver active before crash")
SavedDB = JimPowerMizerDB; taxi = false
ns = session("session 6b: after crash")
advance(ns.STARTUP_GRACE + 0.6)
check(cvars.groundEffectDensity == "200" and cvars.farclip == "5000" and cvars.graphicsGroundClutter == "9", "crash recovery restores console values too")
-- Option off: old behaviour
ns.addon.db.profile.protectDetails = false
taxi = true; fire("PLAYER_CONTROL_LOST"); advance(2.5)
taxi = false; fire("PLAYER_CONTROL_GAINED"); advance(0.6)
check(cvars.groundEffectDensity == "144", "option off: preset values left as the game sets them")
noErrors("session 6")

-- Session 5: options UI (table logic only) ---------------------------------------
JimPowerMizerDB = nil; SavedDB = nil
taxi, afk, resting, dead, combat = false, false, false, false, false
ns = session("session 5: options")
advance(ns.STARTUP_GRACE); poke()
local reg = LibStub("AceConfigRegistry-3.0")
local function tbl() return ns.Options:GetTable() end
local function node(...)
	local n = tbl()
	for i = 1, select("#", ...) do n = n.args[select(i, ...)]; if not n then return nil end end
	return n
end
local function call(fn, ...) if type(fn) == "function" then return fn(...) end return fn end
local function set(value, ...) local n = node(...); call(n.set, {}, value) end
local function get(...) local n = node(...); return call(n.get, {}) end
local function run(...) local n = node(...); call(n.func, {}) end
local ok, err = pcall(reg.ValidateOptionsTable, reg, tbl(), "JimPowerMizer")
check(ok, "options table passes AceConfig validation" .. (ok and "" or (": " .. tostring(err))))
check(node("graphics", "p_Max saver") and node("graphics", "p_Light saver"), "built-in profiles listed")
check(node("situations", "idle", "args") == nil and node("situations", "idle", "timeout") ~= nil, "idle has a timeout setting")
check(node("situations", "taxi", "timeout") == nil, "only idle has a timeout")
check(node("situations", "idle", "mouseActivity") ~= nil and get("situations", "idle", "mouseActivity") == false, "idle mouse option shown, off by default")

-- Edit the active profile -> applied live
taxi = true; fire("PLAYER_CONTROL_LOST"); advance(2.5)
check(cvars.maxFPS == "20", "taxi -> Max saver")
set(15, "graphics", "p_Max saver", "maxFPS", "value")
check(cvars.maxFPS == "15", "editing active profile applies at once")
set(false, "graphics", "p_Max saver", "renderScale", "change")
check(cvars.renderScale == "1", "unticking a setting restores it at once")
-- Switch the active situation's profile
set("Light saver", "situations", "taxi", "profile")
check(cvars.maxFPS == "30" and cvars.graphicsViewDistance == nil or cvars.maxFPS == "30", "changing taxi's profile applies at once")
set("__user", "situations", "taxi", "profile")
check(cvars.maxFPS == "144" and JimPowerMizerDB.profiles.Default.situations.taxi.profile == false, "'Your settings' stored as false and restores")
set("Max saver", "situations", "taxi", "profile")
check(cvars.maxFPS == "15", "back to Max saver")
-- Disable active situation
set(false, "situations", "taxi", "enabled")
check(cvars.maxFPS == "144", "disabling the active situation restores")
set(true, "situations", "taxi", "enabled")
check(cvars.maxFPS == "15", "re-enabling applies again")

-- Capture uses the user's values, not the lowered live ones
set("My profile", "graphics", "new")
check(node("graphics", "p_My profile") ~= nil, "new profile created")
check(ns.addon.db.profile.graphicsProfiles["My profile"].maxFPS == 144, "new profile captured YOUR maxFPS (144), not the live 15")
check(call(node("graphics", "new").validate, {}, "My profile") ~= true, "duplicate name rejected")
-- Rename updates references
set("My profile", "situations", "taxi", "profile")
set("Flying", "graphics", "p_My profile", "rename")
check(ns.addon.db.profile.situations.taxi.profile == "Flying" and node("graphics", "p_Flying") and not node("graphics", "p_My profile"), "rename updates situations")
-- Delete -> situations fall back to your settings
run("graphics", "p_Flying", "delete")
check(ns.addon.db.profile.situations.taxi.profile == false and not node("graphics", "p_Flying"), "delete falls back to your settings")
check(cvars.maxFPS == "144", "taxi now uses your settings")
set("Max saver", "situations", "taxi", "profile")
-- Copy
run("graphics", "p_Max saver", "copy")
check(node("graphics", "p_Max saver copy") ~= nil, "copy created")
-- General toggles
set(false, "general", "enabled")
check(cvars.maxFPS == "144" and not ns.Engine:IsEnabled(), "General: disable restores")
set(true, "general", "enabled")
check(cvars.maxFPS == "15", "General: enable applies again")
check(type(call(node("general", "status").name)) == "string", "status text renders")
JimPowerMizer_OnAddonCompartmentClick("JimPowerMizer", "LeftButton")
check(LibStub("AceConfigDialog-3.0").OpenFrames.JimPowerMizer, "compartment left-click opens options")
taxi = false; advance(2.1)
-- Deleted built-ins stay deleted after reload
run("graphics", "p_Light saver", "delete")
SavedDB = JimPowerMizerDB
ns = session("session 5b: reload after deleting Light saver")
check(ns.addon.db.profile.graphicsProfiles["Light saver"] == nil, "deleted built-in profile stays deleted")
check(ns.addon.db.profile.graphicsProfiles["Max saver"].maxFPS == 15, "edited built-in profile keeps edits")
noErrors("session 5")

-- Session 7: screen effects (hide UI, dim) -------------------------------------------
JimPowerMizerDB = nil; SavedDB = nil
taxi, afk, resting, dead, combat, cine = false, false, false, false, false, false
ns = session("session 7: hide UI and dim")
advance(ns.STARTUP_GRACE); poke()
check(ns.Options:GetTable().args.graphics.args["p_Max saver"].args.screen ~= nil, "profile page has screen options")
local ms = ns.addon.db.profile.graphicsProfiles["Max saver"]
ns.Options:GetTable().args.graphics.args["p_Max saver"].args.screen.args.hideUI.set({}, true)
ns.Options:GetTable().args.graphics.args["p_Max saver"].args.screen.args.dim.set({}, 0.6)
check(ms.hideUI == true and ms.dim == 0.6, "screen options stored in the profile")
taxi = true; fire("PLAYER_CONTROL_LOST"); advance(2.5)
check(cvars.maxFPS == "20" and not UIParent:IsShown(), "taxi: UI hidden")
local skipped = false
for _, line in ipairs(printed) do if line:find("Skipping hideUI") or line:find("Skipping dim") then skipped = true end end
check(not skipped and cvars.hideUI == nil, "screen keys not treated as CVars")
advance(1.1)
check(math.abs(ns.Screen:GetDim() - 0.6) < 1e-6, "screen dimmed to 60% after fading in")
cine = true; fire("CINEMATIC_START"); advance(0.1)
check(not UIParent:IsShown() and ns.Screen:GetDim() == 0, "cinematic: undimmed, UI left to the cinematic")
cine = false; fire("CINEMATIC_STOP"); advance(1.2)
check(not UIParent:IsShown() and ns.Screen:GetDim() > 0.59, "after the cinematic: still hidden and dimmed on the flight")
UIParent:Show() -- user presses Alt+Z
advance(4)
check(UIParent:IsShown(), "UI shown by the user stays shown for the rest of the switch")
taxi = false; fire("PLAYER_CONTROL_GAINED"); advance(0.1)
check(UIParent:IsShown() and ns.Screen:GetDim() == 0 and cvars.maxFPS == "144", "landed: UI shown, undimmed")
taxi = true; fire("PLAYER_CONTROL_LOST"); advance(2.5)
check(not UIParent:IsShown(), "next flight hides the UI again")
fire("PLAYER_REGEN_DISABLED"); combat = true; advance(0.1)
check(UIParent:IsShown() and ns.Screen:GetDim() == 0, "combat: UI shown before lockdown, undimmed")
combat = false; fire("PLAYER_REGEN_ENABLED"); advance(1)
check(not UIParent:IsShown(), "after combat, still flying: UI hidden again")
-- Combat situation disabled: can't show in lockdown, shown once combat ends
ns.addon.db.profile.situations.combat.enabled = false
combat = true; fire("PLAYER_REGEN_DISABLED"); taxi = false; fire("PLAYER_CONTROL_GAINED"); advance(2.5)
check(not UIParent:IsShown() and cvars.maxFPS == "144", "landed in combat lockdown: UI waits")
combat = false; fire("PLAYER_REGEN_ENABLED"); advance(1)
check(UIParent:IsShown(), "UI shown once combat ends")
ns.addon.db.profile.situations.combat.enabled = true
-- Capture keeps the screen options
ns.Options:GetTable().args.graphics.args["p_Max saver"].args.capture.func()
ms = ns.addon.db.profile.graphicsProfiles["Max saver"]
check(ms.hideUI == true and ms.dim == 0.6 and ms.maxFPS == 144, "Capture current keeps hide/dim settings")
ns.Options:GetTable().args.graphics.args["p_Max saver"].args.screen.args.dim.set({}, 0)
check(ms.dim == nil, "dim 0% removes the setting")
noErrors("session 7")

-- Session 8: built-in profile updates for existing settings --------------------------------
SavedDB = { profileKeys = { ["Tester - Realm"] = "Default" }, profiles = { Default = { profilesSeeded = true,
	graphicsProfiles = { ["Max saver"] = { graphicsParticleDensity = 1, maxFPS = 20 }, ["Mine"] = { graphicsParticleDensity = 1 } } } } }
ns = session("session 8: built-in updates")
local gp = ns.addon.db.profile.graphicsProfiles
check(gp["Max saver"].graphicsParticleDensity == 0 and gp["Max saver"].maxFPS == 20, "old Max saver particle density lowered to Low")
check(gp["Mine"].graphicsParticleDensity == 1, "user's own profiles untouched")
check(ns.addon.db.profile.builtinVersion == #ns.Database.BUILTIN_UPDATES, "update recorded")
gp["Max saver"].graphicsParticleDensity = 2; SavedDB = JimPowerMizerDB
ns = session("session 8b: reload")
check(ns.addon.db.profile.graphicsProfiles["Max saver"].graphicsParticleDensity == 2, "user's later edit not overwritten again")
JimPowerMizerDB = nil; SavedDB = nil
ns = session("session 8c: fresh install")
check(ns.addon.db.profile.graphicsProfiles["Max saver"].graphicsParticleDensity == 0, "fresh install: particle density Low")
slash("watch"); C_CVar.SetCVar("graphicsSSAO", "1")
local seen = false
for _, line in ipairs(printed) do if line:find("CVar graphicsSSAO = 1", 1, true) then seen = true end end
check(seen, "/jpm watch prints setting changes")
slash("watch")
noErrors("session 8")

io.write(FAILED and "\nSOME CHECKS FAILED\n" or "\nALL CHECKS PASSED\n")
os.exit(FAILED and 1 or 0)
