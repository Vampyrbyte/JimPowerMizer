std = "lua51"
max_line_length = false
exclude_files = { "Libs/", ".release/" }
ignore = {
	"212/self", -- unused self
	"212/_.*",  -- unused args starting with _
}
globals = { "JimPowerMizer", "JimPowerMizer_OnAddonCompartmentClick", "JimPowerMizer_OnAddonCompartmentEnter",
	"JimPowerMizer_OnAddonCompartmentLeave", "JimPowerMizerDB" }
read_globals = {
	"LibStub", "C_AddOns", "C_CVar", "GetBuildInfo", "GetTime", "UnitOnTaxi", "InCombatLockdown",
	"WOW_PROJECT_ID", "wipe", "UnitAffectingCombat", "UnitIsAFK", "IsResting", "UnitIsDeadOrGhost",
	"InCinematic", "IsInCinematicScene", "IsPlayerMoving", "GetUnitSpeed", "UnitCastingInfo",
	"UnitChannelInfo", "GetCursorPosition", "GetPlayerFacing", "Enum", "CreateFrame", "GameTooltip", "strtrim",
}
