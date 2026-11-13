-- JimPowerMizer: core addon object and namespace.
local ADDON_NAME, ns = ...
local L = ns.L

local JPM = LibStub("AceAddon-3.0"):NewAddon(ADDON_NAME, "AceEvent-3.0", "AceTimer-3.0", "AceConsole-3.0")
ns.addon = JPM
_G.JimPowerMizer = JPM

JPM.version = (C_AddOns and C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version")) or "dev"
if JPM.version:find("@project", 1, true) then JPM.version = "dev" end

-- Client info. Use flavor feature checks rather than WOW_PROJECT_ID alone (see docs/PLAN.md).
do
	local version, build, _, interface = GetBuildInfo()
	ns.client = {
		version = version,
		build = build,
		interface = interface,
		projectID = WOW_PROJECT_ID,
	}
end

-- Seconds after login/reload during which situations that are already active apply at once
-- (no enter delay), and leftover settings from the last session wait before being restored.
ns.STARTUP_GRACE = 5

local CHAT_PREFIX = "|cff33ff99JimPowerMizer|r:"

function JPM:Msg(fmt, ...)
	print(CHAT_PREFIX, (select("#", ...) > 0) and fmt:format(...) or fmt)
end

function JPM:Debug(fmt, ...)
	if self.db and self.db.profile.debug then
		print("|cff999999JPM debug:|r", (select("#", ...) > 0) and fmt:format(...) or fmt)
	end
end

function JPM:OnInitialize()
	ns.Database:Init(self)
	ns.Compat:Init()
	ns.Options:Init()
	self:RegisterChatCommand("jpm", "HandleSlash")
	self:RegisterChatCommand("jimpowermizer", "HandleSlash")
end

function JPM:OnEnable()
	ns.Applier:Enable()
	if self.db.profile.enabled then ns.Engine:Enable() end
	self:Debug("Enabled. Client %s (%s), interface %s, project %s, compat %s",
		ns.client.version, ns.client.build, tostring(ns.client.interface),
		tostring(ns.client.projectID), ns.Compat.name)
end

function JPM:OnDisable()
	ns.Engine:Disable()
	ns.Applier:RestoreAll(L["disabled"])
end

-- Blizzard addon compartment (minimap addon menu). Referenced from the TOC.
-- Left-click: options window. Right-click: turn automatic switching on/off.
function JimPowerMizer_OnAddonCompartmentClick(_, mouseButton)
	if mouseButton == "RightButton" then
		JPM:SetEnabled(not JPM.db.profile.enabled)
		JPM:Msg(JPM.db.profile.enabled and L["Enabled."] or L["Disabled."])
	else
		ns.Options:Toggle()
	end
end

function JimPowerMizer_OnAddonCompartmentEnter(_, menuButton)
	local tip = GameTooltip
	tip:SetOwner(menuButton, "ANCHOR_LEFT")
	tip:SetText("JimPowerMizer")
	for _, line in ipairs(JPM:GetStatusLines()) do tip:AddLine(line, 1, 1, 1) end
	tip:AddLine(" ")
	tip:AddLine(L["Left-click: options"], 0.6, 0.6, 0.6)
	tip:AddLine(L["Right-click: turn automatic switching on/off"], 0.6, 0.6, 0.6)
	tip:Show()
end

function JimPowerMizer_OnAddonCompartmentLeave()
	GameTooltip:Hide()
end
