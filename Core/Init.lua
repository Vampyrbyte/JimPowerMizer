-- JimPowerMizer: core addon object and namespace.
local ADDON_NAME, ns = ...

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
	ns.Applier:RestoreAll("addon disabled")
end

-- Blizzard addon compartment (minimap addon menu). Referenced from the TOC.
function JimPowerMizer_OnAddonCompartmentClick()
	JPM:PrintStatus()
end
