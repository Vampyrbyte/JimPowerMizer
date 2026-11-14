-- Screen effects a graphics profile can add on top of its CVars:
--  * hideUI: hide the user interface (like Alt+Z) while the profile is active.
-- (Dimming is the game's Brightness CVar, handled by the Applier like any other setting.)
--
-- Nothing is saved: a /reload or crash simply brings the UI back.
--
-- Hiding/showing UIParent is blocked in combat, and cinematics hide and restore the UI themselves,
-- so changes wait until combat or the cinematic is over. Combat normally switches to your own
-- settings on PLAYER_REGEN_DISABLED, just before the lockdown starts, so the UI comes back in time.
-- If you show the UI yourself (Alt+Z), it stays shown until the next profile switch.
local _, ns = ...

local Screen = {}
ns.Screen = Screen
LibStub("AceEvent-3.0"):Embed(Screen)

-- Profile keys handled here rather than as CVars. `dim` was an overlay in development builds;
-- it's ignored, and removed from saved profiles by Database:EnsureProfiles.
Screen.KEYS = { hideUI = true, dim = true }

local wantHidden = false -- the active profile wants the UI hidden
local hiddenByUs = false -- UIParent is hidden because we hid it
local userShown = false  -- the user showed the UI again during this profile

local function canToggleUI()
	return not ns.Compat:InCombat() and not ns.Compat:InCinematic()
end

function Screen:SyncUI()
	local ui = _G.UIParent
	if not ui then return end
	if wantHidden then
		if not hiddenByUs and not userShown and ui:IsShown() and canToggleUI() then
			hiddenByUs = true
			ui:Hide()
			ns.addon:Debug("Hid the user interface")
		end
	elseif hiddenByUs then
		if ui:IsShown() then
			hiddenByUs = false
		elseif canToggleUI() then
			hiddenByUs = false
			ui:Show()
			ns.addon:Debug("Showed the user interface")
		end
	end
end

-- Apply the screen effects of `profile` (a graphics profile table, or nil for none).
function Screen:Apply(profile)
	local hide = (profile and profile.hideUI) and true or false
	if hide ~= wantHidden then
		wantHidden = hide
		userShown = false
	end
	self:SyncUI()
end

function Screen:IsUIHidden()
	return hiddenByUs
end

function Screen:Enable()
	local ui = _G.UIParent
	if ui and ui.HookScript then
		ui:HookScript("OnShow", function()
			-- Shown by someone else (Alt+Z, Escape, a cinematic ending) while we had it hidden.
			if hiddenByUs then
				hiddenByUs = false
				userShown = wantHidden
				ns.addon:Debug("User interface shown again; leaving it shown until the next switch")
			end
		end)
	end
	local function later() C_Timer.After(0.5, function() Screen:SyncUI() end) end
	self:RegisterEvent("PLAYER_REGEN_ENABLED", later)
	self:RegisterEvent("CINEMATIC_STOP", later)
	self:RegisterEvent("STOP_MOVIE", later)
end
