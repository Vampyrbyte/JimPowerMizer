-- Screen effects a graphics profile can add on top of its CVars:
--  * hideUI: hide the user interface (like Alt+Z) while the profile is active.
--  * dim:    darken the screen with a black overlay, 0 (off) to 0.9 (90 % darker).
--
-- Neither is saved anywhere: a /reload or crash simply brings the UI back at full brightness.
--
-- Hiding/showing UIParent is blocked in combat, and cinematics hide and restore the UI themselves,
-- so changes wait until combat or the cinematic is over. Combat normally switches to your own
-- settings on PLAYER_REGEN_DISABLED, just before the lockdown starts, so the UI comes back in time.
-- If you show the UI yourself (Alt+Z), it stays shown until the next profile switch.
local _, ns = ...

local Screen = {}
ns.Screen = Screen
LibStub("AceEvent-3.0"):Embed(Screen)

-- Profile keys handled here rather than as CVars.
Screen.KEYS = { hideUI = true, dim = true }
Screen.MAX_DIM = 0.9

local FADE_TIME = 1.0 -- seconds to fade the dimming in (removing it is instant)
local FADE_STEP = 0.05

local wantHidden = false -- the active profile wants the UI hidden
local hiddenByUs = false -- UIParent is hidden because we hid it
local userShown = false  -- the user showed the UI again during this profile
local overlay, fadeTicker

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

local function getOverlay()
	if overlay then return overlay end
	-- Parented to WorldFrame so it stays visible while UIParent is hidden; covers the UI too.
	overlay = CreateFrame("Frame", nil, _G.WorldFrame)
	overlay:SetFrameStrata("FULLSCREEN_DIALOG")
	overlay:SetAllPoints(_G.WorldFrame)
	overlay:EnableMouse(false)
	local tex = overlay:CreateTexture(nil, "BACKGROUND")
	tex:SetAllPoints(overlay)
	tex:SetColorTexture(0, 0, 0, 1)
	overlay:SetAlpha(0)
	overlay:Hide()
	return overlay
end

local function setDim(target)
	target = math.max(0, math.min(Screen.MAX_DIM, tonumber(target) or 0))
	if fadeTicker then fadeTicker:Cancel(); fadeTicker = nil end
	if target <= 0 then
		if overlay then overlay:SetAlpha(0); overlay:Hide() end
		return
	end
	local f = getOverlay()
	local from = f:IsShown() and f:GetAlpha() or 0
	f:Show()
	if target <= from then
		f:SetAlpha(target)
		return
	end
	local steps = math.max(1, math.floor(FADE_TIME / FADE_STEP + 0.5))
	local i = 0
	fadeTicker = C_Timer.NewTicker(FADE_STEP, function()
		i = i + 1
		f:SetAlpha(from + (target - from) * i / steps)
		if i >= steps and fadeTicker then fadeTicker:Cancel(); fadeTicker = nil end
	end, steps)
end

-- Apply the screen effects of `profile` (a graphics profile table, or nil for none).
function Screen:Apply(profile)
	local hide = (profile and profile.hideUI) and true or false
	if hide ~= wantHidden then
		wantHidden = hide
		userShown = false
	end
	self:SyncUI()
	setDim(profile and profile.dim)
end

function Screen:GetDim()
	return (overlay and overlay:IsShown()) and overlay:GetAlpha() or 0
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
