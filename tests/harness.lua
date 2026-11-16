-- Minimal WoW API mock that loads the addon (per the TOC its client would read) and checks its behaviour.
-- Usage: scripts/fetch-libs.sh && luajit tests/harness.lua . [flavor]   (flavors: tests/flavors)
--
-- The client flavor (default forever) sets what the mock reports (build, interface, project ID) and
-- which TOC is loaded. Every check runs for every flavor unless it's about one game's rules: those sit
-- inside `if FLAVOR == "..." then` blocks. CI runs each flavor listed in tests/flavors.
local ROOT = arg[1] or "."
local FLAVOR = arg[2] or "forever"
local CLIENTS = {
	forever  = { version = "1.60.1", build = "70938", interface = 16001,  project = 18, toc = "Mainline" }, -- WOW_PROJECT_CAMELOT
	midnight = { version = "12.1.5", build = "70783", interface = 120105, project = 1,  toc = "Mainline" }, -- WOW_PROJECT_MAINLINE
}
local CLIENT = CLIENTS[FLAVOR]
if not CLIENT then
	local names = {}
	for name in pairs(CLIENTS) do names[#names + 1] = name end
	table.sort(names)
	io.write("Unknown flavor '", FLAVOR, "' (use one of: ", table.concat(names, ", "), ")\n"); os.exit(2)
end
io.write("Client flavor: ", FLAVOR, " (interface ", CLIENT.interface, ")\n")
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
GetBuildInfo = function() return CLIENT.version, CLIENT.build, "Nov 2026", CLIENT.interface end
GetTime = function() return now end
time, date = os.time, os.date
WOW_PROJECT_ID = CLIENT.project
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
-- castInfo/channelInfo: the values UnitCastingInfo/UnitChannelInfo return (6th = isTradeSkill).
local castInfo, channelInfo
UnitCastingInfo = function() if combat then return SECRET end if castInfo then return unpack(castInfo) end end
UnitChannelInfo = function() if channelInfo then return unpack(channelInfo) end end
local mainHand -- item ID in the main hand
local ITEMS = { [12225] = { 2, 20 }, [1234] = { 2, 7 } } -- Blump Family Fishing Pole, a sword
GetInventoryItemID = function(_, slot) if slot == 16 then return mainHand end end
C_Item = { GetItemInfoInstant = function(id) local i = ITEMS[id]
	if i then return id, "Weapon", "?", "INVTYPE_WEAPON", 0, i[1], i[2] end end }
GetCursorPosition = function() return cx, cy end
local focusBox, mouseFocus -- edit box with keyboard focus; frame under the mouse
GetCurrentKeyBoardFocus = function() return focusBox end
GetMouseFoci = function() return { mouseFocus } end
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
	UnitNameNPC = "1", UnitNameOwn = "0", UnitNameFriendlyPlayerName = "1", nameplateShowEnemies = "1",
	-- Minion names on, pet names turned off by hand (the client sets all three with the minion one).
	UnitNameFriendlyMinionName = "1", UnitNameFriendlyPetName = "0", UnitNameFriendlyGuardianName = "1",
	UnitNameFriendlyTotemName = "1",
	Brightness = "50", useMaxFPS = "0", maxFPS = "144", useMaxFPSBk = "1", maxFPSBk = "30", renderScale = "1",
	graphicsShadowQuality = "4", graphicsSSAO = "3", graphicsParticleDensity = "4",
	graphicsLiquidDetail = "2", graphicsSpellDensity = "5", graphicsQuality = "7",
	graphicsGroundClutter = "9", graphicsViewDistance = "9",
	graphicsLightMode = "3", giQuality = "4", RenderFormat = "2", graphicsPBRLiquidDetail = "2", pbrLiquidDetail = "2",
	-- Lower-level settings: user's /console tweaks, different from what the presets would set.
	groundEffectDensity = "256", groundEffectDist = "300", farclip = "5000", gxWindow = "1",
	lastSeenThing = "a", chatStyleThing = "x", -- unrelated Default-category CVars
}
-- Friendly player nameplates: both clients have nameplateShowFriendlyPlayers and no nameplateShowFriends
-- (seen in game on Forever 1.60.1 and Midnight 12.1.5).
local FRIEND_PLATES = "nameplateShowFriendlyPlayers"
cvars[FRIEND_PLATES] = "1"
local secure = { renderScale = true, nameplateShowEnemies = true }
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
	graphicsLightMode = function(level) SetCVarRaw("giQuality", level + 1); SetCVarRaw("RenderFormat", math.min(level + 1, 2)) end,
	graphicsPBRLiquidDetail = function(level) SetCVarRaw("pbrLiquidDetail", level) end,
	-- Seen on Midnight 12.1.5: restoring the minion names setting also set these.
	UnitNameFriendlyMinionName = function(v)
		SetCVarRaw("UnitNameFriendlyPetName", v); SetCVarRaw("UnitNameFriendlyGuardianName", v); SetCVarRaw("UnitNameFriendlyTotemName", v)
	end,
}
local writes = {} -- CVar -> number of times it was set
local CLAMP = {}  -- CVar -> function(number) returning the value the client keeps
local LATE = {}   -- CVar -> true: CVAR_UPDATE fires a moment after the write, not during it
function SetCVarRaw(n, v)
	writes[n] = (writes[n] or 0) + 1
	cvars[n] = tostring(v); fire("CVAR_UPDATE", n, tostring(v))
end
C_CVar = {
	GetCVar = function(n) return cvars[n] end,
	SetCVar = function(n, v)
		if cvars[n] == nil then return false end
		if secure[n] and combat then error("blocked: secure cvar in combat") end
		if CLAMP[n] then v = CLAMP[n](tonumber(v)) end
		if LATE[n] then
			cvars[n] = tostring(v)
			C_Timer.After(0.01, function() fire("CVAR_UPDATE", n, cvars[n]) end)
		else
			SetCVarRaw(n, v)
		end
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
	function f:RegisterUnitEvent(e) self.events[e] = true end
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
	local f = assert(io.open(ROOT .. "/JimPowerMizer_" .. CLIENT.toc .. ".toc"))
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
-- Land from a flight path and walk off (the taxi situation lasts until you move).
local function land()
	taxi = false; fire("PLAYER_CONTROL_GAINED"); fire("PLAYER_STARTED_MOVING"); fire("PLAYER_STOPPED_MOVING")
end

-- Session 1 --------------------------------------------------------------
IsLoggedIn = function() return false end
local ns = session("session 1: normal flight")
check(ns.client.interface == CLIENT.interface and ns.client.projectID == CLIENT.project, "addon sees the " .. FLAVOR .. " client")
check(ns.Compat.name == "Mainline", "Mainline compat layer chosen")
check(cvars.maxFPS == "144", "baseline untouched at login")
advance(ns.STARTUP_GRACE)
taxi = true; fire("PLAYER_CONTROL_LOST"); advance(1)
check(cvars.maxFPS == "144", "no switch before enterDelay")
advance(2.5)
check(cvars.maxFPS == "20" and cvars.useMaxFPS == "1" and cvars.renderScale == "0.5", "Max saver applied on taxi")
check(cvars.useMaxFPSBk == "1" and cvars.maxFPSBk == "20", "background FPS capped to foreground cap")
check(cvars.graphicsQuality == "7", "graphicsQuality never touched")
land(); advance(0.1)
check(cvars.maxFPS == "144" and cvars.useMaxFPS == "0" and cvars.renderScale == "1" and cvars.graphicsShadowQuality == "4", "all restored after landing")
check(cvars.maxFPSBk == "30", "background FPS cap restored")
check(next(JimPowerMizerDB.global.state.baseline) == nil, "baseline cleared")

-- User changes a managed CVar mid-flight
taxi = true; advance(4)
check(cvars.maxFPS == "20", "applied again (poll fallback, no event)")
C_CVar.SetCVar("graphicsShadowQuality", "2") -- user edits in Blizzard settings
land(); advance(2.1)
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
land(); advance(2.1)
check(cvars.maxFPS == "144" and cvars.renderScale == "1" and cvars.graphicsShadowQuality == "2" and cvars.maxFPSBk == "30", "final restore matches user settings")

-- Background cap not raised: user's background cap already lower than the profile's foreground cap
cvars.maxFPSBk = "10"; taxi = true; advance(2.5)
check(cvars.maxFPSBk == "10", "lower user background cap left alone")
land(); advance(2.1)

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
land(); advance(0.1)
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
if FLAVOR == "forever" then -- verified in game on Forever only
	fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 67); advance(1.1)
	check(cvars.maxFPS == "30", "Forever bank (CharacterBanker 67) -> Light saver")
	fire("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 67); advance(0.1)
	check(cvars.maxFPS == "144", "Forever bank closed")
end

slash("enable resting")
resting = true; fire("PLAYER_UPDATE_RESTING"); advance(5.5)
check(cvars.maxFPS == "30", "resting -> Light saver")
taxi = true; fire("PLAYER_CONTROL_LOST"); advance(2.5)
check(cvars.maxFPS == "20", "taxi outranks resting")
land(); advance(2.1)
check(cvars.maxFPS == "30", "back to resting after taxi")
resting = false; fire("PLAYER_UPDATE_RESTING"); advance(0.1)

slash("enable dead")
dead = true; fire("PLAYER_DEAD"); advance(3.5)
check(cvars.maxFPS == "30", "dead -> Light saver")
dead = false; fire("PLAYER_ALIVE"); advance(0.1)
check(cvars.maxFPS == "144" and next(JimPowerMizerDB.global.state.baseline) == nil, "alive -> your settings, baseline clear")
-- Fishing: on Forever you hold the pole in your main hand (Midnight's rule comes with M5)
if FLAVOR == "forever" then
	mainHand = 1234; fire("PLAYER_EQUIPMENT_CHANGED", 16); advance(1.5)
	check(cvars.maxFPS == "144", "a sword in the main hand isn't fishing")
	mainHand = 12225; fire("PLAYER_EQUIPMENT_CHANGED", 16); advance(0.5)
	check(cvars.maxFPS == "144", "fishing: waits for enter delay")
	advance(0.6)
	check(cvars.maxFPS == "30", "fishing pole equipped -> Light saver")
	channelInfo = { "Fishing", "Fishing", 136245, 1, 2, false, false, 7731 }
	fire("UNIT_SPELLCAST_CHANNEL_START", "player"); advance(0.1)
	check(ns.Engine:GetCurrent() == "fishing", "a Fishing cast isn't crafting")
	channelInfo = nil; fire("UNIT_SPELLCAST_CHANNEL_STOP", "player")
	mainHand = 1234; fire("PLAYER_EQUIPMENT_CHANGED", 16); advance(0.1)
	check(cvars.maxFPS == "144", "weapon back on -> your settings")
end
-- Crafting

fire("TRADE_SKILL_SHOW"); advance(3)
check(cvars.maxFPS == "144", "profession window alone isn't crafting")
local SMELT = { "Smelt Copper", "Smelt Copper", 136235, 1, 2, true, "Cast-1", true, 2657 }
castInfo = SMELT; fire("UNIT_SPELLCAST_START", "player"); advance(0.1)
check(cvars.maxFPS == "30", "profession cast -> Light saver")
castInfo = nil; fire("UNIT_SPELLCAST_STOP", "player"); advance(3)
check(cvars.maxFPS == "30", "still crafting during the grace period")
castInfo = SMELT; fire("UNIT_SPELLCAST_START", "player"); advance(0.1)
castInfo = nil; fire("UNIT_SPELLCAST_STOP", "player"); advance(9.5)
check(cvars.maxFPS == "30", "next craft restarts the grace period")
advance(1)
check(cvars.maxFPS == "144", "grace period over -> your settings")
castInfo = SMELT; fire("UNIT_SPELLCAST_START", "player"); advance(0.1)
castInfo = nil; fire("UNIT_SPELLCAST_STOP", "player"); advance(2)
moving = true; fire("PLAYER_STARTED_MOVING"); advance(0.1)
check(cvars.maxFPS == "144", "moving ends the grace period early")
moving = false; fire("PLAYER_STOPPED_MOVING")
castInfo = SMELT; fire("UNIT_SPELLCAST_START", "player"); advance(0.1)
castInfo = nil; fire("UNIT_SPELLCAST_STOP", "player"); advance(2)
fire("TRADE_SKILL_CLOSE"); advance(0.1)
check(cvars.maxFPS == "144", "closing the profession window ends the grace period early")
castInfo = SMELT; fire("UNIT_SPELLCAST_START", "player"); advance(0.1)
check(cvars.maxFPS == "30", "craft with the window closed (macro)")
castInfo = nil; fire("UNIT_SPELLCAST_STOP", "player"); advance(5)
check(cvars.maxFPS == "30", "macro craft keeps its grace period")
advance(5.5)
castInfo = SMELT; fire("UNIT_SPELLCAST_START", "player"); advance(0.1)
moving = true; fire("PLAYER_STARTED_MOVING"); castInfo = nil; fire("UNIT_SPELLCAST_INTERRUPTED", "player"); advance(0.1)
check(cvars.maxFPS == "144", "craft interrupted by moving: no grace period")
moving = false; fire("PLAYER_STOPPED_MOVING")
slash("crafting 0")
castInfo = SMELT; fire("UNIT_SPELLCAST_START", "player"); advance(0.1)
castInfo = nil; fire("UNIT_SPELLCAST_STOP", "player"); advance(1.1)
check(cvars.maxFPS == "144" and ns.addon.db.profile.situations.crafting.grace == 0, "/jpm crafting 0: no grace period")
slash("crafting 10")
castInfo = SMELT; fire("UNIT_SPELLCAST_START", "player"); advance(0.1)
combat = true; fire("PLAYER_REGEN_DISABLED"); advance(0.1)
check(cvars.maxFPS == "144", "combat outranks crafting (secret cast info)")
castInfo = nil; combat = false; fire("PLAYER_REGEN_ENABLED"); advance(11)
check(cvars.maxFPS == "144", "back to your settings after combat and grace")

slash("disable cutscenes")
check(ns.addon.db.profile.situations.cinematic.enabled == false, "/jpm disable cutscenes works on the cinematic situation")
slash("enable cutscenes")
check(ns.Engine:GetSituation("cinematic").name == "Cutscenes", "cinematic situation shown as Cutscenes")
slash("list")

-- Flight path: stays active after landing until you move
taxi = true; fire("PLAYER_CONTROL_LOST"); advance(2.5)
check(cvars.maxFPS == "20", "flight -> Max saver")
taxi = false; fire("PLAYER_CONTROL_GAINED"); advance(30)
check(cvars.maxFPS == "20", "landed, untouched: still saving")
fire("PLAYER_STARTED_MOVING"); advance(0.1)
check(cvars.maxFPS == "144", "moving after landing ends it")
fire("PLAYER_STOPPED_MOVING")
taxi = true; fire("PLAYER_CONTROL_LOST"); advance(2.5)
fire("PLAYER_TARGET_CHANGED"); advance(5) -- input during the flight isn't input after landing
taxi = false; fire("PLAYER_CONTROL_GAINED"); advance(30)
check(cvars.maxFPS == "20", "targeting during the flight doesn't end it after landing")
fire("PLAYER_TARGET_CHANGED"); advance(0.1)
check(cvars.maxFPS == "144", "changing target after landing ends it (any input by Idle's rules)")
-- With Idle's mouse option on, the turn of the landing itself isn't input; moving the mouse later is
ns.addon.db.profile.situations.idle.mouseActivity = true
taxi = true; fire("PLAYER_CONTROL_LOST"); advance(2.5)
facing = facing + 1; advance(3); facing = facing + 1
taxi = false; fire("PLAYER_CONTROL_GAINED"); advance(30)
check(cvars.maxFPS == "20", "mouse option on: the landing's own turn doesn't end it")
cx = cx + 50; advance(1.1)
check(cvars.maxFPS == "144", "mouse option on: moving the mouse after landing ends it")
ns.addon.db.profile.situations.idle.mouseActivity = false
taxi = true; fire("PLAYER_CONTROL_LOST"); advance(2.5)
taxi = false; fire("PLAYER_CONTROL_GAINED"); advance(2.1)
moving = true; advance(2.1)
check(cvars.maxFPS == "144", "missed STARTED_MOVING: the poll ends it")
moving = false
taxi = true; fire("PLAYER_CONTROL_LOST"); advance(2.5)
taxi = false; fire("PLAYER_CONTROL_GAINED"); advance(1)
castInfo = { "Summon Mount" }; fire("UNIT_SPELLCAST_SENT", "player"); advance(0.1)
check(cvars.maxFPS == "144", "casting after landing ends it")
castInfo = nil; advance(1.1)

-- Idle: a loading screen (ship crossing zones) isn't input
slash("idle 30"); poke(); advance(1.1)
afk = true; fire("PLAYER_FLAGS_CHANGED", "player"); advance(6)
check(cvars.maxFPS == "20", "AFK on a ship -> idle")
fire("LOADING_SCREEN_ENABLED")
afk = false; fire("PLAYER_FLAGS_CHANGED", "player") -- the game drops the flag while zoning
fire("PLAYER_TARGET_CHANGED"); fire("LOADING_SCREEN_DISABLED"); fire("PLAYER_ENTERING_WORLD", false, false)
moving = true; fire("PLAYER_STARTED_MOVING"); cx = cx + 50; facing = facing + 1; advance(4)
check(cvars.maxFPS == "20", "loading screen and zoning events don't end idle")
moving = false; fire("PLAYER_STOPPED_MOVING"); advance(10)
check(cvars.maxFPS == "20", "AFK from before the loading screen still counts")
poke(); advance(0.1)
check(cvars.maxFPS == "144", "real input after the loading screen ends idle")
advance(10)
check(cvars.maxFPS == "144", "carried AFK cleared by input: back to the timeout")

-- Long idle: its own timeout and profile, outranks idle
ns.addon.db.profile.situations.longIdle.profile = "Light saver"
slash("longidle 120"); poke(); advance(31)
check(ns.Engine:GetCurrent() == "idle" and cvars.maxFPS == "20", "short idle first (Max saver)")
advance(90)
check(ns.Engine:GetCurrent() == "longIdle" and cvars.maxFPS == "30", "long idle after its timeout (its own profile)")
poke(); advance(0.1)
check(cvars.maxFPS == "144", "input ends both")
afk = true; fire("PLAYER_FLAGS_CHANGED", "player"); advance(6)
check(ns.Engine:GetCurrent() == "idle", "AFK flag starts short idle, not long idle")
afk = false; poke(); advance(0.1)
slash("disable longidle")
check(ns.addon.db.profile.situations.longIdle.enabled == false, "/jpm disable longidle (any case)")
advance(130)
check(ns.Engine:GetCurrent() == "idle", "long idle disabled: short idle stays")
slash("enable longIdle"); slash("list"); poke(); advance(1) -- let the restore's 2nd pass run
ns.addon.db.profile.situations.longIdle.profile = "Max saver"
-- Flight path outranks idle (no input on a flight), long idle outranks flight path
slash("idle 30"); ns.addon.db.profile.situations.taxi.profile = "Light saver"; poke()
taxi = true; fire("PLAYER_CONTROL_LOST"); advance(40)
check(ns.Engine:GetCurrent() == "taxi" and cvars.maxFPS == "30", "a long flight keeps the flight profile over idle")
slash("longidle 60"); advance(30)
check(ns.Engine:GetCurrent() == "longIdle" and cvars.maxFPS == "20", "long idle outranks the flight")
land(); advance(1)
check(cvars.maxFPS == "144", "landing and walking off ends all")
ns.addon.db.profile.situations.taxi.profile = "Max saver"
slash("longidle 900")
slash("idle 600")
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
check(cvars.graphicsLightMode == "0" and cvars.giQuality == "1" and cvars.graphicsPBRLiquidDetail == "0" and cvars.pbrLiquidDetail == "0", "saver: secondary lighting and PBR liquid lowered")
cvars.chatStyleThing = "y" -- changed by something else mid-flight
land()
C_Timer.After(0.2, function() SetCVarRaw("lastSeenThing", "b") end) -- unrelated change just after landing
advance(0.01)
check(cvars.graphicsGroundClutter == "9" and cvars.groundEffectDensity == "256" and cvars.groundEffectDist == "300", "restore: custom density/dist put back at once")
advance(0.6)
check(cvars.farclip == "5000", "restore: delayed cascade on farclip undone by 2nd pass")
check(cvars.graphicsLightMode == "3" and cvars.giQuality == "4" and cvars.RenderFormat == "2" and cvars.pbrLiquidDetail == "2", "restore: lighting and PBR liquid settings back")
check(cvars.gxWindow == "1", "display settings untouched")
check(cvars.chatStyleThing == "y" and cvars.lastSeenThing == "b", "unrelated Default-category changes not reverted")
check(next(JimPowerMizerDB.global.state.detail) == nil, "detail snapshot cleared after restore")
-- User changes a console setting while nothing is active: next snapshot picks it up
cvars.groundEffectDensity = "200"
taxi = true; fire("PLAYER_CONTROL_LOST"); advance(2.5)
land(); advance(0.6)
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
land(); advance(0.6)
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
check(node("situations", "crafting", "grace") ~= nil and get("situations", "crafting", "grace") == 10, "crafting has a grace setting, 10 s by default")
check(node("situations", "fishing") ~= nil and node("situations", "fishing", "grace") == nil, "fishing listed, no grace setting")
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
land(); advance(2.1)
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
ns.Options:GetTable().args.graphics.args["p_Max saver"].args.Brightness.args.change.set({}, true)
ns.Options:GetTable().args.graphics.args["p_Max saver"].args.Brightness.args.value.set({}, 20)
ns.Options:GetTable().args.graphics.args["p_Max saver"].args.screen.args.hideNames.set({}, true)
check(ms.hideUI == true and ms.Brightness == 20 and ms.hideNames == true, "hide UI, names and brightness stored in the profile")
check(ns.Options:GetTable().args.graphics.args["p_Max saver"].args.UnitNameNPC == nil, "name settings not listed in the profile editor")
taxi = true; fire("PLAYER_CONTROL_LOST"); advance(2.5)
check(cvars.maxFPS == "20" and not UIParent:IsShown(), "taxi: UI hidden")
local skipped = false
for _, line in ipairs(printed) do if line:find("Skipping hideUI") or line:find("Skipping dim") then skipped = true end end
check(not skipped and cvars.hideUI == nil, "screen keys not treated as CVars")
check(cvars.Brightness == "20", "taxi: brightness lowered")
check(cvars.UnitNameNPC == "0" and cvars.UnitNameFriendlyPlayerName == "0" and cvars.nameplateShowEnemies == "0", "taxi: names and nameplates hidden")
check(cvars[FRIEND_PLATES] == "0", "taxi: friendly player nameplates hidden (" .. FRIEND_PLATES .. ")")
cine = true; fire("CINEMATIC_START"); advance(0.1)
check(not UIParent:IsShown() and cvars.Brightness == "50", "cinematic: your brightness, UI left to the cinematic")
cine = false; fire("CINEMATIC_STOP"); advance(1.2)
check(not UIParent:IsShown() and cvars.Brightness == "20", "after the cinematic: still hidden and dimmed on the flight")
UIParent:Show() -- user presses Alt+Z
advance(4)
check(UIParent:IsShown(), "UI shown by the user stays shown for the rest of the switch")
land(); advance(0.1)
check(UIParent:IsShown() and cvars.Brightness == "50" and cvars.maxFPS == "144", "landed: UI shown, brightness restored")
check(cvars.UnitNameNPC == "1" and cvars.UnitNameOwn == "0" and cvars.nameplateShowEnemies == "1", "landed: your name settings back")
check(cvars[FRIEND_PLATES] == "1", "landed: friendly player nameplates back")
check(cvars.UnitNameFriendlyMinionName == "1" and cvars.UnitNameFriendlyPetName == "0" and cvars.UnitNameFriendlyGuardianName == "1"
	and cvars.UnitNameFriendlyTotemName == "1", "landed: minion, pet, guardian and totem names back, whatever the write order")
local mistaken = false
for _, line in ipairs(printed) do if line:find("User changed UnitName") then mistaken = true end end
check(not mistaken and next(ns.addon.db.global.state.baseline) == nil, "linked name settings not mistaken for your changes")
taxi = true; fire("PLAYER_CONTROL_LOST"); advance(2.5)
check(not UIParent:IsShown(), "next flight hides the UI again")
fire("PLAYER_REGEN_DISABLED"); combat = true; advance(0.1)
check(UIParent:IsShown() and cvars.Brightness == "50", "combat: UI shown before lockdown, brightness restored")
check(cvars.UnitNameNPC == "1" and cvars.nameplateShowEnemies == "1", "combat: names and nameplates back before lockdown")
combat = false; fire("PLAYER_REGEN_ENABLED"); advance(1)
check(not UIParent:IsShown(), "after combat, still flying: UI hidden again")
-- Combat situation disabled: can't show in lockdown, shown once combat ends
ns.addon.db.profile.situations.combat.enabled = false
combat = true; fire("PLAYER_REGEN_DISABLED"); land(); advance(2.5)
check(not UIParent:IsShown() and cvars.maxFPS == "144", "landed in combat lockdown: UI waits")
combat = false; fire("PLAYER_REGEN_ENABLED"); advance(1)
check(UIParent:IsShown(), "UI shown once combat ends")
ns.addon.db.profile.situations.combat.enabled = true
-- Capture keeps the screen options
ns.Options:GetTable().args.graphics.args["p_Max saver"].args.capture.func()
ms = ns.addon.db.profile.graphicsProfiles["Max saver"]
check(ms.hideUI == true and ms.hideNames == true and ms.maxFPS == 144 and ms.UnitNameNPC == nil, "Capture current keeps screen options, no name CVars")
ms.dim = 0.6; SavedDB = JimPowerMizerDB
ns = session("session 7b: leftover dim from a development build")
check(ns.addon.db.profile.graphicsProfiles["Max saver"].dim == nil, "old dim setting removed")
noErrors("session 7")

-- Session 8: built-in profile updates for existing settings --------------------------------
SavedDB = { profileKeys = { ["Tester - Realm"] = "Default" }, profiles = { Default = { profilesSeeded = true,
	graphicsProfiles = { ["Max saver"] = { graphicsParticleDensity = 1, maxFPS = 20 }, ["Mine"] = { graphicsParticleDensity = 1 } } } } }
ns = session("session 8: built-in updates")
local gp = ns.addon.db.profile.graphicsProfiles
check(gp["Max saver"].graphicsParticleDensity == 0 and gp["Max saver"].maxFPS == 20, "old Max saver particle density lowered to Low")
check(gp["Mine"].graphicsParticleDensity == 1, "user's own profiles untouched")
check(gp["Max saver"].graphicsLightMode == 0 and gp["Max saver"].graphicsPBRLiquidDetail == 0, "secondary lighting and PBR liquid added to old Max saver")
check(gp["Mine"].graphicsLightMode == nil, "not added to the user's own profiles")
check(gp["Cinematic"] and gp["Cinematic"].hideUI and gp["Cinematic"].hideNames and gp["Cinematic"].maxFPS == 30, "Cinematic profile added to existing settings")
check(gp["Cinematic"].graphicsShadowQuality == nil and gp["Cinematic"].renderScale == nil, "Cinematic leaves graphics settings alone")
check(ns.addon.db.profile.builtinVersion == #ns.Database.BUILTIN_UPDATES, "update recorded")
gp["Max saver"].graphicsParticleDensity = 2; SavedDB = JimPowerMizerDB
ns = session("session 8b: reload")
ns.addon.db.profile.graphicsProfiles["Cinematic"] = nil; SavedDB = JimPowerMizerDB
ns = session("session 8b2: reload after deleting Cinematic")
check(ns.addon.db.profile.graphicsProfiles["Max saver"].graphicsParticleDensity == 2, "user's later edit not overwritten again")
check(ns.addon.db.profile.graphicsProfiles["Cinematic"] == nil, "deleted Cinematic stays deleted")
JimPowerMizerDB = nil; SavedDB = nil
ns = session("session 8c: fresh install")
check(ns.addon.db.profile.graphicsProfiles["Max saver"].graphicsParticleDensity == 0, "fresh install: particle density Low")
check(ns.addon.db.profile.graphicsProfiles["Cinematic"] ~= nil, "fresh install: Cinematic profile")
advance(ns.STARTUP_GRACE); poke()
ns.addon.db.profile.situations.taxi.profile = "Cinematic"
local before = { shadow = cvars.graphicsShadowQuality, scale = cvars.renderScale, view = cvars.graphicsViewDistance }
taxi = true; fire("PLAYER_CONTROL_LOST"); advance(2.5)
check(not UIParent:IsShown() and cvars.UnitNameNPC == "0" and cvars.maxFPS == "30" and cvars.useMaxFPS == "1", "Cinematic: UI and names hidden, FPS capped")
check(cvars.graphicsShadowQuality == before.shadow and cvars.renderScale == before.scale and cvars.graphicsViewDistance == before.view, "Cinematic: graphics left at your settings")
land(); advance(0.6)
check(UIParent:IsShown() and cvars.UnitNameNPC == "1" and cvars.maxFPS == "144", "Cinematic ends: everything back")
slash("watch"); C_CVar.SetCVar("graphicsSSAO", "1")
local seen = false
for _, line in ipairs(printed) do if line:find("CVar graphicsSSAO = 1", 1, true) then seen = true end end
check(seen, "/jpm watch prints setting changes")
slash("watch")
noErrors("session 8")

-- Session 9: fixes from the code review ---------------------------------------------------
JimPowerMizerDB = nil; SavedDB = nil
taxi, afk, resting, dead, combat, cine, moving = false, false, false, false, false, false, false
castInfo, channelInfo, mainHand = nil, nil, nil
cvars.maxFPSBk = "30"
ns = session("session 9: review fixes")
advance(ns.STARTUP_GRACE); poke()
slash("idle 30"); poke()
-- Start running inside the settle window after a loading screen and keep running
fire("LOADING_SCREEN_ENABLED"); fire("LOADING_SCREEN_DISABLED"); fire("PLAYER_ENTERING_WORLD", false, false)
advance(1); moving = true; fire("PLAYER_STARTED_MOVING"); advance(45)
check(cvars.maxFPS == "144", "running since just after a loading screen: not idle while still running")
moving = false; fire("PLAYER_STOPPED_MOVING"); advance(31)
check(cvars.maxFPS == "20", "idle 30 s after stopping")
poke(); advance(1)
-- Carried AFK flag isn't cleared by someone else's flag change
afk = true; fire("PLAYER_FLAGS_CHANGED", "player"); advance(6)
fire("LOADING_SCREEN_ENABLED"); afk = false
fire("LOADING_SCREEN_DISABLED"); fire("PLAYER_ENTERING_WORLD", false, false); advance(6)
fire("PLAYER_FLAGS_CHANGED", "nameplate3"); advance(1.1)
check(cvars.maxFPS == "20", "another player's flag change doesn't clear the carried AFK flag")
poke(); advance(1)
-- /jpm off during combat, /jpm on after it
combat = true; fire("PLAYER_REGEN_DISABLED"); advance(0.1)
slash("off"); combat = false; fire("PLAYER_REGEN_ENABLED"); slash("on"); advance(31)
check(cvars.maxFPS == "20", "turned off in combat and on after it: idle still works")
poke(); advance(1)
slash("idle 600")
-- /jpm probe while a profile owns maxFPSBk
taxi = true; fire("PLAYER_CONTROL_LOST"); advance(2.5)
check(cvars.maxFPSBk == "20", "flight caps the background FPS")
slash("probe")
land(); advance(1)
check(cvars.maxFPSBk == "30", "probe during a profile doesn't lose your maxFPSBk")
-- /jpm force while switched off isn't remembered
slash("off"); slash("force taxi"); slash("on"); advance(3)
check(cvars.maxFPS == "144" and ns.Engine:GetCurrent() == nil, "/jpm force while off isn't applied on /jpm on")
-- A switch at the end of combat isn't undone by changes queued during it
ns.addon.db.profile.situations.combat.enabled = false
taxi = true; fire("PLAYER_CONTROL_LOST"); advance(2.5)
combat = true; fire("PLAYER_REGEN_DISABLED"); land(); advance(1)
check(cvars.maxFPS == "144" and cvars.renderScale == "0.5", "landed in combat: secure renderScale queued")
combat = false; slash("force taxi") -- a switch that lands before the Applier's own combat-end handler
fire("PLAYER_REGEN_ENABLED"); advance(1)
check(cvars.maxFPS == "20" and cvars.renderScale == "0.5", "queued restore doesn't overwrite the newer profile")
slash("force off"); advance(1)
check(cvars.maxFPS == "144" and cvars.renderScale == "1" and next(JimPowerMizerDB.global.state.baseline) == nil, "and everything is restored afterwards")
ns.addon.db.profile.situations.combat.enabled = true
-- Settings profiles carry their own on/off switch
ns.addon.db:SetProfile("Other"); slash("off")
ns.addon.db:SetProfile("Default")
check(ns.Engine:IsEnabled(), "switching to a settings profile that's on turns switching on")
ns.addon.db:SetProfile("Other")
check(not ns.Engine:IsEnabled(), "switching to a settings profile that's off turns switching off")
ns.addon.db:SetProfile("Default")
-- The client clamps a value we set: not mistaken for a change made by the user
CLAMP.maxFPS = function(v) return math.max(v, 24) end
taxi = true; fire("PLAYER_CONTROL_LOST"); advance(2.5)
check(cvars.maxFPS == "24", "client clamps the profile's maxFPS")
land(); advance(1)
check(cvars.maxFPS == "144", "a clamped value is still restored afterwards")
-- The same when the game reports the change a moment after the write rather than during it
LATE.maxFPS = true
taxi = true; fire("PLAYER_CONTROL_LOST"); advance(2.5)
check(cvars.maxFPS == "24" and JimPowerMizerDB.global.state.baseline.maxFPS == "144", "clamped value reported late: your original is still saved")
land(); advance(1)
check(cvars.maxFPS == "144", "a clamped value reported late is still restored afterwards")
check(next(JimPowerMizerDB.global.state.baseline) == nil and next(JimPowerMizerDB.global.state.owned) == nil, "nothing left over after the late reports")
LATE.maxFPS = nil
CLAMP.maxFPS = nil
-- A value the profile wants that's already set isn't written again
local ssao = cvars.graphicsSSAO; cvars.graphicsSSAO = "0"; writes.graphicsSSAO = 0
taxi = true; fire("PLAYER_CONTROL_LOST"); advance(2.5)
land(); advance(1)
check(writes.graphicsSSAO == 0 and cvars.graphicsSSAO == "0", "a setting already at the profile's value isn't rewritten")
cvars.graphicsSSAO = ssao
-- Secure lower-level setting reset by a delayed cascade after combat lockdown began
secure.farclip = true; cvars.farclip = "5000" -- (an earlier session left it at a preset value)
taxi = true; fire("PLAYER_CONTROL_LOST"); advance(2.5)
check(cvars.farclip == "1000", "flight lowers farclip")
fire("PLAYER_REGEN_DISABLED"); combat = true; land(); advance(1)
check(cvars.farclip == "4500" and cvars.maxFPS == "144", "in combat: the 2nd pass can't write the secure farclip")
combat = false; fire("PLAYER_REGEN_ENABLED"); advance(1)
check(cvars.farclip == "5000", "farclip put back once combat ends")
check(next(JimPowerMizerDB.global.state.detail) == nil, "detail snapshot cleared after that")
secure.farclip = nil
-- "Keep custom console settings" turned off mid-flight: what was saved is still put back
cvars.groundEffectDensity = "200"
taxi = true; fire("PLAYER_CONTROL_LOST"); advance(2.5)
check(cvars.groundEffectDensity == "0", "flight lowers ground density")
ns.addon.db.profile.protectDetails = false
land(); advance(1)
check(cvars.groundEffectDensity == "200" and cvars.farclip == "5000", "option turned off mid-flight: saved console values still restored")
ns.addon.db.profile.protectDetails = true
-- A loading screen that never reports its end
slash("idle 30"); poke()
fire("LOADING_SCREEN_ENABLED"); advance(310)
check(cvars.maxFPS == "20", "idle during an endless loading screen")
poke(); advance(0.1)
check(cvars.maxFPS == "144", "after 5 minutes without an end-of-loading event, input counts again")
-- Typing, clicking on the interface and opening a window are input
poke(); advance(20)
local chatText = ""
focusBox = { GetText = function() return chatText end }; advance(15)
check(cvars.maxFPS == "144", "opening the chat box is input")
chatText = "hel"; advance(20); chatText = "hello"; advance(20)
check(cvars.maxFPS == "144", "typing keeps you active")
advance(31)
check(cvars.maxFPS == "20", "a chat box left open and untouched doesn't block idle")
focusBox = nil; advance(2)
check(cvars.maxFPS == "20", "losing the keyboard focus (e.g. interface hidden) isn't input")
mouseFocus = WorldFrame; fire("GLOBAL_MOUSE_DOWN", "RightButton"); advance(0.1)
check(cvars.maxFPS == "20", "a click on the world (panning the camera) isn't input")
mouseFocus = UIParent; fire("GLOBAL_MOUSE_DOWN", "LeftButton"); advance(0.1)
check(cvars.maxFPS == "144", "a click on the interface is input")
mouseFocus = nil; advance(31)
check(cvars.maxFPS == "20", "idle again")
fire("MAIL_SHOW"); advance(0.1)
check(cvars.maxFPS == "144", "opening the mailbox is input")
fire("MAIL_CLOSED"); advance(31)
check(cvars.maxFPS == "20", "closing it isn't")
poke(); advance(1)
slash("idle 600")
noErrors("session 9")

-- Session 10: energy savings ---------------------------------------------------------------
JimPowerMizerDB = nil; SavedDB = nil
taxi, afk, resting, dead, combat, moving, focusBox, mouseFocus = false, false, false, false, false, false, nil, nil
ns = session("session 10: energy savings")
advance(ns.STARTUP_GRACE)
slash("disable idle"); slash("disable longIdle")
local sv = function() return ns.addon.db.global.savings end
-- Printed lines since `mark` that contain `text` (plain).
local mark = 0
local function setMark() mark = #printed end
local function said(text)
	for i = mark + 1, #printed do if printed[i]:find(text, 1, true) then return printed[i] end end
end
local function fly(seconds)
	taxi = true; fire("PLAYER_CONTROL_LOST"); advance(2.5)
	advance(seconds - 0.5) -- applied after the 2 s delay
	setMark(); land(); advance(2.1)
end
setMark(); slash("stats")
check(said("No graphics profile has been used yet."), "stats before any profile was used")

fly(600)
check(math.abs(sv().stats["Max saver"].seconds - 600) < 1, "10 min of Max saver recorded")
local msg = said("Restored your graphics settings")
check(msg and not msg:find("saved"), "no watts entered: the switch message is unchanged")
setMark(); slash("stats")
check(said("Max saver: 10 min") and not said("Wh") and not said("CO2") and not said("~"), "stats show only the time without watts")
check(said("Enter your PC's power use"), "stats say where to enter the watts")
check(said("This session: 10 min"), "session total")

-- Watts entered later count for the time already recorded
set("300", "savings", "power", "normal")
set("150", "savings", "power", "w_Max saver")
check(sv().normal == 300 and sv().watts["Max saver"] == 150, "watts stored as numbers")
setMark(); slash("stats")
local line = said("Max saver:")
check(line and line:find("10 min, ~25 Wh saved", 1, true) and not line:find("(", 1, true), "energy for earlier time, no cost or CO2 when not entered")
check(not said("Enter your PC's power use"), "no hint once watts are entered")
check(call(node("savings", "power", "normal").validate, {}, "abc") ~= true, "a non-number is rejected")
check(call(node("savings", "power", "normal").validate, {}, "") == true, "an empty box is allowed")
set("0,25", "savings", "extras", "price"); set(" £ ", "savings", "extras", "currency")
check(sv().price == 0.25 and sv().currency == "£", "price with a decimal comma, currency trimmed")
setMark(); slash("stats")
line = said("Max saver:")
check(line and line:find("(~£0.01)", 1, true) and not line:find("CO2"), "cost shown, CO2 left out")
set("200", "savings", "extras", "co2")
setMark(); slash("stats")
check(said("Max saver: 10 min, ~25 Wh saved (~£0.01, ~5 g CO2)"), "cost and CO2 shown")
set("", "savings", "extras", "price")
check(sv().price == nil, "emptying the box clears the price")
set("0.25", "savings", "extras", "price")
ok, err = pcall(reg.ValidateOptionsTable, reg, tbl(), "JimPowerMizer")
check(ok, "options table with the Savings tab passes AceConfig validation" .. (ok and "" or (": " .. tostring(err))))
check(type(call(node("savings", "stats").name)) == "string", "Savings tab stats render")

-- Chat line when a profile ends: only with the switch messages on and watts entered
fly(1200)
check(said("Restored your graphics settings") and said("Max saver: 20 min, ~50 Wh saved (~£0.01, ~10 g CO2)"), "switch message says what the profile saved")
set(false, "general", "notify")
fly(60)
check(not said("saved") and not said("Restored"), "nothing in chat with switch messages off")
set(true, "general", "notify")
set("Light saver", "situations", "taxi", "profile")
fly(60)
msg = said("Restored your graphics settings")
check(msg and not msg:find("saved"), "a profile without watts: switch message unchanged")
set("Max saver", "situations", "taxi", "profile")
-- Switching straight from one profile to another reports the one that ended
set("100", "savings", "power", "w_Light saver")
taxi = true; fire("PLAYER_CONTROL_LOST"); advance(2.5); advance(120)
setMark(); set("Light saver", "situations", "taxi", "profile")
check(said("Graphics profile Light saver") and said("Max saver: 2 min"), "profile to profile: the ended one is reported")
advance(180); setMark(); land(); advance(2.1)
check(said("Light saver: 3 min, ~10 Wh saved"), "then the second one when it ends")
set("Max saver", "situations", "taxi", "profile")
-- Re-applying the same profile (edited) doesn't end its period
taxi = true; fire("PLAYER_CONTROL_LOST"); advance(2.5); advance(60)
setMark(); set(18, "graphics", "p_Max saver", "maxFPS", "value")
check(not said("saved"), "editing the active profile doesn't end its period")
local before = sv().stats["Max saver"].seconds
advance(60); setMark(); land(); advance(2.1)
check(math.abs(sv().stats["Max saver"].seconds - before - 120) < 1, "the whole period is counted once")

-- Logout while applied: counted and saved; the next session starts its own session total
local maxBefore = sv().stats["Max saver"].seconds
taxi = true; fire("PLAYER_CONTROL_LOST"); advance(2.5); advance(300)
fire("PLAYER_LOGOUT")
check(math.abs(sv().stats["Max saver"].seconds - maxBefore - 300) < 1, "logout counts the running period")
SavedDB = JimPowerMizerDB; taxi = false
ns = session("session 10b: reload")
advance(ns.STARTUP_GRACE)
check(math.abs(ns.addon.db.global.savings.stats["Max saver"].seconds - maxBefore - 300) < 1, "stats kept through the reload")
check(next(ns.addon.db.global.state.baseline) == nil, "left-over settings restored")
setMark(); slash("stats")
check(said("This session: 0 s"), "the recovered settings after reload aren't counted")

-- Rename: stats and watts go with the profile; the old name starts again from zero
local maxSeconds = sv().stats["Max saver"].seconds
set("Flying saver", "graphics", "p_Max saver", "rename")
check(sv().stats["Flying saver"] and sv().stats["Flying saver"].seconds == maxSeconds and sv().watts["Flying saver"] == 150, "rename moves stats and watts")
check(sv().stats["Max saver"] == nil and sv().watts["Max saver"] == nil, "nothing left under the old name")
set("Max saver", "graphics", "new")
check(sv().stats["Max saver"] == nil and sv().watts["Max saver"] == nil, "a new profile with the old name starts from zero")
-- Delete: counted in the totals as "Deleted profiles", never adopted by a new profile of that name
run("graphics", "p_Flying saver", "delete")
check(sv().stats["Flying saver"] == nil and sv().watts["Flying saver"] == nil, "delete removes the profile's entry and watts")
check(math.abs(sv().deleted.seconds - maxSeconds) < 1 and math.abs(sv().deleted.wh - maxSeconds * 150 / 3600) < 0.01, "its time and energy move to the deleted total")
set("Flying saver", "graphics", "new")
check(sv().stats["Flying saver"] == nil and sv().watts["Flying saver"] == nil, "a new profile with a deleted one's name starts from zero")
setMark(); slash("stats")
check(said("Deleted profiles:") and said("Total:"), "deleted profiles shown in the stats")
-- Deleting the profile that's applied right now
set("Light saver", "situations", "taxi", "profile")
local lightBefore = sv().stats["Light saver"].seconds
local deletedBefore = sv().deleted.seconds
taxi = true; fire("PLAYER_CONTROL_LOST"); advance(2.5); advance(100)
run("graphics", "p_Light saver", "delete")
check(math.abs(sv().deleted.seconds - deletedBefore - lightBefore - 100) < 1, "deleting the applied profile counts its running period")
check(cvars.maxFPS == "144", "and your settings are back")
land(); advance(2.1)
-- Reset needs confirming
setMark(); slash("stats reset")
check(said("To go ahead") and sv().deleted.seconds > 0, "reset asks to confirm first")
slash("stats reset yes")
check(next(sv().stats) == nil and sv().deleted.seconds == 0 and sv().since == nil, "reset clears the stats")
check(sv().normal == 300 and sv().price == 0.25, "reset keeps the figures entered")
noErrors("session 10")

io.write(FAILED and "\nSOME CHECKS FAILED" or "\nALL CHECKS PASSED", " (", FLAVOR, ")\n")
os.exit(FAILED and 1 or 0)
