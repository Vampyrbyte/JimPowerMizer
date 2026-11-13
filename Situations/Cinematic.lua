-- Cinematics and pre-rendered movies: the user's own settings, so they look as intended.
local _, ns = ...
local L = ns.L

ns.Engine:RegisterSituation({
	key = "cinematic",
	name = L["Cinematic"],
	events = { "CINEMATIC_START", "CINEMATIC_STOP", "PLAY_MOVIE", "STOP_MOVIE" },
	Evaluate = function()
		return ns.Compat:InCinematic()
	end,
})
