-- Energy savings: how long each graphics profile has been applied, and what that saved according to
-- the power figures the user entered (the game can't measure power). Account-wide, by profile name.
--
-- Only time is recorded. Energy is worked out when shown, from the watts entered now:
-- seconds / 3600 * (watts at your own settings - watts with the profile) Wh. So figures entered later
-- count for the time already recorded. A deleted profile's energy is fixed when it's deleted, as its
-- watts go with it.
local _, ns = ...
local L = ns.L

local Savings = {}
ns.Savings = Savings

local current, startedAt  -- the profile being timed, and GetTime() when it was applied
local session = {}        -- [name] = seconds this session (finished periods)
local sessionDeleted = { seconds = 0, wh = 0 }

local function data()
	return ns.addon.db.global.savings
end

-- ---------------------------------------------------------------------------------------------
-- Recording

-- Add the running period to the totals and stop the clock. Returns the profile and its seconds.
local function finish()
	if not current then return end
	local name, seconds = current, math.max(0, GetTime() - startedAt)
	current, startedAt = nil, nil
	local d = data()
	d.since = d.since or time()
	local s = d.stats[name]
	if not s then
		s = { seconds = 0 }
		d.stats[name] = s
	end
	s.seconds = s.seconds + seconds
	session[name] = (session[name] or 0) + seconds
	return name, seconds
end

-- The applied graphics profile changed (nil: your own settings). Returns the profile that ended and
-- how long it was applied, if one did.
function Savings:Switch(profileName)
	if profileName == "recovered" then profileName = nil end -- left over from a crash, not timed
	if profileName == current then return end
	local ended, seconds = finish()
	if profileName then current, startedAt = profileName, GetTime() end
	return ended, seconds
end

-- Logout: count the running period (the saved totals are written now).
function Savings:Stop()
	finish()
end

-- Move a profile's stats into the deleted total, with its energy worked out now, and drop its watts.
local function retire(name)
	local d = data()
	local s = d.stats[name]
	if s then
		local wh = Savings:Energy(name, s.seconds) or 0
		d.deleted.seconds = d.deleted.seconds + s.seconds
		d.deleted.wh = d.deleted.wh + wh
		d.stats[name] = nil
	end
	if session[name] then
		sessionDeleted.seconds = sessionDeleted.seconds + session[name]
		sessionDeleted.wh = sessionDeleted.wh + (Savings:Energy(name, session[name]) or 0)
		session[name] = nil
	end
	d.watts[name] = nil
end

-- A graphics profile was deleted. Its time still counts in the totals, but not under its name.
function Savings:ProfileDeleted(name)
	if current == name then finish() end
	retire(name)
end

-- A graphics profile was created (new, copy). It starts from zero, even if an old profile had the
-- same name (e.g. one deleted in another settings profile).
function Savings:ProfileCreated(name)
	if current == name then return end
	retire(name)
end

-- A graphics profile was renamed: its stats and watts go with it.
function Savings:ProfileRenamed(old, new)
	if old == new then return end
	self:ProfileCreated(new)
	local d = data()
	d.stats[new], d.stats[old] = d.stats[old], nil
	d.watts[new], d.watts[old] = d.watts[old], nil
	session[new], session[old] = session[old], nil
	if current == old then current = new end
end

function Savings:Reset()
	local d = data()
	wipe(d.stats)
	d.deleted.seconds, d.deleted.wh = 0, 0
	d.since = nil
	wipe(session)
	sessionDeleted.seconds, sessionDeleted.wh = 0, 0
	if current then startedAt = GetTime() end
end

-- ---------------------------------------------------------------------------------------------
-- Figures

-- Wh saved by `seconds` of profile `name`, or nil if the watts for it aren't entered.
function Savings:Energy(name, seconds)
	local d = data()
	local normal, profile = tonumber(d.normal), tonumber(d.watts[name])
	if not normal or not profile then return nil end
	return math.max(0, normal - profile) * seconds / 3600
end

-- Seconds recorded for a profile, including the running period. session: this session only.
local function secondsFor(name, sessionOnly)
	local seconds = sessionOnly and (session[name] or 0) or ((data().stats[name] or {}).seconds or 0)
	if current == name then seconds = seconds + math.max(0, GetTime() - startedAt) end
	return seconds
end

local function formatTime(seconds)
	seconds = math.floor(seconds + 0.5)
	if seconds < 60 then return L["%d s"]:format(seconds) end
	local minutes = math.floor(seconds / 60)
	if minutes < 60 then return L["%d min"]:format(minutes) end
	return L["%d h %d min"]:format(math.floor(minutes / 60), minutes % 60)
end

local function formatEnergy(wh)
	if wh < 10 then return ("%.1f Wh"):format(wh) end
	if wh < 1000 then return ("%d Wh"):format(math.floor(wh + 0.5)) end
	return ("%.2f kWh"):format(wh / 1000)
end

-- "~£0.05, ~120 g CO2", leaving out what isn't entered. nil if neither is.
local function extras(wh)
	local d = data()
	local parts = {}
	local price, co2 = tonumber(d.price), tonumber(d.co2)
	if price then parts[#parts + 1] = ("~%s%.2f"):format(d.currency or "", price * wh / 1000) end
	if co2 then
		local g = co2 * wh / 1000
		parts[#parts + 1] = g < 1000 and ("~%d g CO2"):format(math.floor(g + 0.5)) or ("~%.2f kg CO2"):format(g / 1000)
	end
	return #parts > 0 and table.concat(parts, ", ") or nil
end

-- "22 min, ~45 Wh saved (~£0.01, ~12 g CO2)"; just the time if wh is nil or there was no time.
local function describe(seconds, wh)
	local text = formatTime(seconds)
	if wh and seconds >= 1 then
		text = text .. ", " .. L["~%s saved"]:format(formatEnergy(wh))
		local more = extras(wh)
		if more then text = text .. " (" .. more .. ")" end
	end
	return text
end

-- For the chat message when a profile ends: "Max saver: 22 min, ~45 Wh saved (...)", or nil if its
-- energy can't be worked out (no watts entered), so the message stays as it was.
function Savings:EndedText(name, seconds)
	local wh = name and self:Energy(name, seconds)
	if not wh then return nil end
	return ("|cffffd200%s|r: %s"):format(name, describe(seconds, wh))
end

-- Whether any energy can be worked out at all.
function Savings:HasWatts()
	local d = data()
	if not tonumber(d.normal) then return false end
	for _, value in pairs(d.watts) do
		if tonumber(value) then return true end
	end
	return false
end

-- Lines for /jpm stats and the options: lifetime per profile, deleted profiles, totals.
function Savings:GetLines()
	local d = data()
	local lines = {}
	local names = {}
	for name in pairs(d.stats) do names[#names + 1] = name end
	if current and not d.stats[current] then names[#names + 1] = current end
	table.sort(names)

	local totalSeconds, totalWh, sessionSeconds, sessionWh = 0, nil, 0, nil
	local function addWh(sum, wh) if wh then return (sum or 0) + wh end return sum end
	for _, name in ipairs(names) do
		local seconds = secondsFor(name)
		local wh = self:Energy(name, seconds)
		lines[#lines + 1] = ("  |cffffd200%s|r: %s"):format(name, describe(seconds, wh))
		totalSeconds, totalWh = totalSeconds + seconds, addWh(totalWh, wh)
		local s = secondsFor(name, true)
		sessionSeconds, sessionWh = sessionSeconds + s, addWh(sessionWh, self:Energy(name, s))
	end
	if d.deleted.seconds > 0 then
		local wh = d.deleted.wh > 0 and d.deleted.wh or nil
		lines[#lines + 1] = "  " .. L["Deleted profiles"] .. ": " .. describe(d.deleted.seconds, wh)
		totalSeconds, totalWh = totalSeconds + d.deleted.seconds, addWh(totalWh, wh)
	end
	if sessionDeleted.seconds > 0 then
		sessionSeconds = sessionSeconds + sessionDeleted.seconds
		if sessionDeleted.wh > 0 then sessionWh = addWh(sessionWh, sessionDeleted.wh) end
	end

	if #lines == 0 then
		return { L["No graphics profile has been used yet."] }
	end
	table.insert(lines, 1, d.since and L["Since %s:"]:format(date("%d %b %Y", d.since)) or L["So far:"])
	lines[#lines + 1] = L["Total: %s"]:format(describe(totalSeconds, totalWh))
	lines[#lines + 1] = L["This session: %s"]:format(describe(sessionSeconds, sessionWh))
	if not self:HasWatts() then
		lines[#lines + 1] = L["Enter your PC's power use in the options (Savings tab) to see the energy saved."]
	end
	return lines
end

-- ---------------------------------------------------------------------------------------------
-- Settings

-- A number typed by the user ("0,25" works too), or nil for an empty box. false if it isn't one.
function Savings.ParseNumber(text)
	text = strtrim(tostring(text or "")):gsub(",", ".")
	if text == "" then return nil end
	local n = tonumber(text)
	if not n or n < 0 then return false end
	return n
end
