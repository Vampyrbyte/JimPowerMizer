-- Options UI (AceConfig): a standalone window (/jpm, minimap addon menu) and a page in the game's
-- Settings > AddOns. The table is rebuilt whenever profiles or situations change.
local ADDON_NAME, ns = ...

local L = ns.L

local Options = {}
ns.Options = Options

local APP = ADDON_NAME
local USER = "__user" -- select value meaning "your own settings" (stored as false)

local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")

local Registry = ns.CVarRegistry

local SITUATION_HELP = {
	combat = L["In combat. Use your own settings so fights look and play as normal."],
	cinematic = L["In-game cutscenes and movies."],
	idle = L["You're AFK, or haven't moved your character, cast, targeted, looted or talked to an NPC for the idle timeout. Being carried by a ship or zeppelin doesn't count as moving."],
	taxi = L["On a flight path."],
	dead = L["Dead or a ghost."],
	serviceWindow = L["An auction house, mailbox, bank, guild bank or vendor window is open."],
	resting = L["In an inn or a city."],
}

local function db()
	return ns.addon.db.profile
end

local cache

-- Something changed that affects the table's shape (profile added, renamed...).
function Options:Refresh()
	cache = nil
	AceConfigRegistry:NotifyChange(APP)
end

local function refreshEngine()
	if ns.Engine:IsEnabled() then ns.Engine:Refresh("settings") end
end

-- --------------------------------------------------------------------------------------------
-- Graphics profile helpers

local function profileValues()
	local v = { [USER] = L["Your settings"] }
	for name in pairs(db().graphicsProfiles) do v[name] = name end
	return v
end

local function profileSorting()
	local names = {}
	for name in pairs(db().graphicsProfiles) do names[#names + 1] = name end
	table.sort(names)
	table.insert(names, 1, USER)
	return names
end

-- A profile holding the user's own value for every setting we can change.
local function captureUserSettings()
	local values = {}
	for _, def in ipairs(Registry:All()) do
		if not def.hidden and Registry:IsUsable(def.name) then
			local v = ns.Applier:GetUserValue(def.name)
			values[def.name] = tonumber(v) or v
		end
	end
	return values
end

local function validateNewName(name, except)
	name = name and strtrim(name) or ""
	if name == "" then return L["Enter a name."] end
	if name == USER then return L["That name is reserved."] end
	if name ~= except and db().graphicsProfiles[name] then return L["A profile with that name already exists."] end
	return true
end

local function uniqueName(base)
	local name, n = base, 2
	while db().graphicsProfiles[name] do
		name = ("%s %d"):format(base, n)
		n = n + 1
	end
	return name
end

local function profileEdited(name)
	ns.Applier:ReapplyIfActive(name)
end

local function renameProfile(old, new)
	local p = db()
	p.graphicsProfiles[new] = p.graphicsProfiles[old]
	p.graphicsProfiles[old] = nil
	for _, cfg in pairs(p.situations) do
		if cfg.profile == old then cfg.profile = new end
	end
	Options:Refresh()
	refreshEngine()
	AceConfigDialog:SelectGroup(APP, "graphics", "p_" .. new)
end

local function deleteProfile(name)
	local p = db()
	p.graphicsProfiles[name] = nil
	for _, cfg in pairs(p.situations) do
		if cfg.profile == name then cfg.profile = false end
	end
	Options:Refresh()
	refreshEngine()
end

-- One inline group per CVar: "Change" tick box + value control.
local function cvarArgs(profileName)
	local function profile() return db().graphicsProfiles[profileName] or {} end
	local args = {}
	for i, def in ipairs(Registry:All()) do
		if not def.restart and not def.hidden and ns.Compat:GetCVarInfo(def.name) then
			local name = def.name
			local function unset() return profile()[name] == nil end
			local value
			local levels = Registry:LevelValues(name)
			if levels then
				value = {
					type = "select", name = L["Value"], order = 2, width = 1.5, disabled = unset,
					values = levels,
					get = function() return tonumber(profile()[name]) end,
					set = function(_, v) profile()[name] = v; profileEdited(profileName) end,
				}
			elseif def.kind == "bool" then
				value = {
					type = "toggle", name = L["On"], order = 2, disabled = unset,
					get = function() return tonumber(profile()[name]) == 1 end,
					set = function(_, v) profile()[name] = v and 1 or 0; profileEdited(profileName) end,
				}
			else
				value = {
					type = "range", name = L["Value"], order = 2, width = 1.5, disabled = unset,
					min = def.min or 0, max = def.max or 10, step = def.step or 1, bigStep = def.bigStep,
					isPercent = def.percent,
					get = function() return tonumber(profile()[name]) or def.min or 0 end,
					set = function(_, v) profile()[name] = v; profileEdited(profileName) end,
				}
			end
			args[name] = {
				type = "group", inline = true, order = 10 + i, name = def.label,
				args = {
					change = {
						type = "toggle", name = L["Change"], order = 1, width = 0.7,
						desc = L["Untick to leave this setting as it is when this profile is active."],
						get = function() return not unset() end,
						set = function(_, v)
							if v then
								local current = ns.Applier:GetUserValue(name)
								profile()[name] = tonumber(current) or current
							else
								profile()[name] = nil
							end
							profileEdited(profileName)
						end,
					},
					value = value,
				},
			}
		end
	end
	return args
end

-- Screen effects (not CVars): hide the UI.
local function screenArgs(profileName)
	local function profile() return db().graphicsProfiles[profileName] or {} end
	return {
		type = "group", inline = true, order = 6, name = L["Screen"],
		args = {
			hideUI = {
				type = "toggle", name = L["Hide the user interface"], order = 1, width = "full",
				desc = L["Hide the user interface (like Alt+Z) while this profile is active. It comes back when the profile ends, e.g. when combat starts. If you show it yourself with Alt+Z, it stays shown until the next switch."],
				get = function() return profile().hideUI and true or false end,
				set = function(_, v) profile().hideUI = v or nil; profileEdited(profileName) end,
			},
			hideNames = {
				type = "toggle", name = L["Hide names and nameplates"], order = 2, width = "full",
				desc = L["Turn off the names above players and NPCs, and nameplates, while this profile is active. Your own name settings come back when it ends."],
				get = function() return profile().hideNames and true or false end,
				set = function(_, v) profile().hideNames = v or nil; profileEdited(profileName) end,
			},
		},
	}
end

local function profileGroup(name, order)
	local args = cvarArgs(name)
	args.rename = {
		type = "input", name = L["Rename"], order = 1, width = 1.2,
		get = function() return name end,
		validate = function(_, v) return validateNewName(v, name) end,
		set = function(_, v)
			v = strtrim(v)
			if v ~= name then renameProfile(name, v) end
		end,
	}
	args.copy = {
		type = "execute", name = L["Copy"], order = 2, width = 0.6,
		func = function()
			local new = uniqueName(L["%s copy"]:format(name))
			db().graphicsProfiles[new] = ns.Database.Copy(db().graphicsProfiles[name])
			Options:Refresh()
			AceConfigDialog:SelectGroup(APP, "graphics", "p_" .. new)
		end,
	}
	args.capture = {
		type = "execute", name = L["Capture current"], order = 3, width = 0.9,
		desc = L["Set every setting in this profile to your current graphics settings (your own values, not ones this addon has lowered)."],
		confirm = true, confirmText = L["Replace all settings in '%s' with your current graphics settings?"]:format(name),
		func = function()
			local values = captureUserSettings()
			for key in pairs(ns.Screen.KEYS) do values[key] = db().graphicsProfiles[name][key] end
			db().graphicsProfiles[name] = values
			profileEdited(name)
			Options:Refresh()
		end,
	}
	args.delete = {
		type = "execute", name = L["Delete"], order = 4, width = 0.6,
		confirm = true, confirmText = L["Delete graphics profile '%s'? Situations using it will use your settings instead."]:format(name),
		func = function() deleteProfile(name) end,
	}
	args.usedBy = {
		type = "description", order = 5, fontSize = "medium",
		name = function()
			local users = {}
			local order_, defs = ns.Engine:GetSituations()
			for _, key in ipairs(order_) do
				if db().situations[key] and db().situations[key].profile == name then users[#users + 1] = defs[key].name end
			end
			return "\n" .. L["Used by: %s"]:format(#users > 0 and table.concat(users, ", ") or L["nothing"])
				.. "\n" .. L["Tick |cffffd200Change|r for each setting this profile should change; unticked settings are left alone."] .. "\n"
		end,
	}
	args.screen = screenArgs(name)
	return { type = "group", name = name, order = order, args = args }
end

-- --------------------------------------------------------------------------------------------
-- Situations

local function situationGroup(key, def, order)
	local function cfg() return db().situations[key] end
	local args = {
		help = { type = "description", order = 0, fontSize = "medium", name = (SITUATION_HELP[key] or def.name) .. "\n" },
		enabled = {
			type = "toggle", name = L["Enabled"], order = 1, width = "full",
			get = function() return cfg().enabled end,
			set = function(_, v) cfg().enabled = v; refreshEngine() end,
		},
		profile = {
			type = "select", name = L["Graphics profile"], order = 2, width = 1.5,
			desc = L["\"Your settings\" restores your own graphics settings while this situation is active."],
			values = profileValues, sorting = profileSorting,
			get = function() return cfg().profile or USER end,
			set = function(_, v) cfg().profile = (v ~= USER) and v or false; refreshEngine() end,
		},
		priority = {
			type = "range", name = L["Priority"], order = 3, min = 0, max = 200, step = 1, bigStep = 5,
			desc = L["When several situations are active at once, the one with the highest priority decides."],
			get = function() return cfg().priority or 0 end,
			set = function(_, v) cfg().priority = v; refreshEngine() end,
		},
		enterDelay = {
			type = "range", name = L["Delay (seconds)"], order = 4, min = 0, max = 60, step = 1,
			desc = L["How long the situation must last before switching, to avoid switching for brief moments."],
			get = function() return cfg().enterDelay or 0 end,
			set = function(_, v) cfg().enterDelay = v; refreshEngine() end,
		},
	}
	if key == "idle" then
		args.timeout = {
			type = "range", name = L["Idle after (seconds)"], order = 5, min = 10, max = 1800, step = 1, bigStep = 10,
			desc = L["Seconds without input before you count as idle. With the AFK flag set, idle starts after 5 seconds."],
			get = function() return cfg().timeout or 180 end,
			set = function(_, v) cfg().timeout = v; refreshEngine() end,
		}
		args.mouseActivity = {
			type = "toggle", name = L["Mouse and camera movement count as activity"], order = 6, width = "full",
			desc = L["Moving the mouse, panning the camera or turning ends idle. Off: only moving your character, casting, targeting, looting, talking to NPCs and combat do."],
			get = function() return cfg().mouseActivity end,
			set = function(_, v) cfg().mouseActivity = v end,
		}
	end
	return {
		type = "group", order = order, args = args,
		name = function()
			local c = cfg()
			return c.enabled and def.name or ("|cff808080" .. def.name .. "|r")
		end,
	}
end

-- --------------------------------------------------------------------------------------------

local function build()
	local p = db()
	local tbl = {
		type = "group", name = "JimPowerMizer", childGroups = "tab",
		args = {
			general = {
				type = "group", name = L["General"], order = 1,
				args = {
					status = {
						type = "description", order = 0, fontSize = "medium",
						name = function() return table.concat(ns.addon:GetStatusLines(), "\n") .. "\n" end,
					},
					enabled = {
						type = "toggle", name = L["Enable automatic switching"], order = 1, width = "full",
						get = function() return db().enabled end,
						set = function(_, v) ns.addon:SetEnabled(v) end,
					},
					notify = {
						type = "toggle", name = L["Chat message when switching"], order = 2, width = "full",
						get = function() return db().notify end,
						set = function(_, v) db().notify = v end,
					},
					capBackground = {
						type = "toggle", name = L["Cap background FPS too"], order = 3, width = "full",
						desc = L["When a profile caps the foreground FPS, also cap the background FPS no higher, so alt-tabbing out doesn't raise the frame rate."],
						get = function() return db().capBackground end,
						set = function(_, v) db().capBackground = v; ns.Applier:ReapplyIfActive(ns.Applier:GetActive()) end,
					},
					protectDetails = {
						type = "toggle", name = L["Keep custom console settings"], order = 3.5, width = "full",
						desc = L["Changing a graphics preset (e.g. Ground Clutter) makes the game reset the settings under it (e.g. groundEffectDensity), losing changes made with /console. With this on, those settings are saved before switching and put back afterwards."],
						get = function() return db().protectDetails end,
						set = function(_, v) db().protectDetails = v end,
					},
					debug = {
						type = "toggle", name = L["Debug messages"], order = 4, width = "full",
						get = function() return db().debug end,
						set = function(_, v) db().debug = v end,
					},
					restore = {
						type = "execute", name = L["Restore my settings now"], order = 5, width = 1.3,
						desc = L["Put your own graphics settings back now. Switching resumes at the next situation change."],
						func = function() ns.addon:HandleSlash("restore") end,
					},
				},
			},
			situations = {
				type = "group", name = L["Situations"], order = 2, childGroups = "tree",
				args = {},
			},
			graphics = {
				type = "group", name = L["Graphics profiles"], order = 3, childGroups = "tree",
				args = {
					intro = {
						type = "description", order = 0, fontSize = "medium",
						name = L["A graphics profile is a set of graphics settings used while a situation is active. Your own settings are saved first and put back afterwards.\n"],
					},
					new = {
						type = "input", name = L["New profile"], order = 1, width = 1.5,
						desc = L["Creates a profile from your current graphics settings, ready to turn down."],
						get = function() return "" end,
						validate = function(_, v) return validateNewName(v) end,
						set = function(_, v)
							v = strtrim(v)
							db().graphicsProfiles[v] = captureUserSettings()
							Options:Refresh()
							AceConfigDialog:SelectGroup(APP, "graphics", "p_" .. v)
						end,
					},
				},
			},
			settingsProfiles = LibStub("AceDBOptions-3.0"):GetOptionsTable(ns.addon.db),
		},
	}
	tbl.args.settingsProfiles.name = L["Settings profiles"]
	tbl.args.settingsProfiles.order = 4

	local order_, defs = ns.Engine:GetSituations()
	local sorted = {}
	for _, key in ipairs(order_) do sorted[#sorted + 1] = key end
	table.sort(sorted, function(a, b)
		return (p.situations[a].priority or 0) > (p.situations[b].priority or 0)
	end)
	for i, key in ipairs(sorted) do
		tbl.args.situations.args[key] = situationGroup(key, defs[key], i)
	end

	local names = {}
	for name in pairs(p.graphicsProfiles) do names[#names + 1] = name end
	table.sort(names)
	for i, name in ipairs(names) do
		tbl.args.graphics.args["p_" .. name] = profileGroup(name, 10 + i)
	end
	return tbl
end

function Options:GetTable()
	if not cache then cache = build() end
	return cache
end

function Options:Toggle()
	if AceConfigDialog.OpenFrames[APP] then
		AceConfigDialog:Close(APP)
	else
		AceConfigDialog:Open(APP)
	end
end

-- Status changed (situation switch): redraw if open, without rebuilding.
function Options:Update()
	if AceConfigDialog.OpenFrames[APP] then AceConfigRegistry:NotifyChange(APP) end
end

function Options:Init()
	AceConfigRegistry:RegisterOptionsTable(APP, function() return Options:GetTable() end)
	AceConfigDialog:SetDefaultSize(APP, 780, 600)
	AceConfigDialog:AddToBlizOptions(APP, "JimPowerMizer")
end
