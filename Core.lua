-- Djinni's Character Frame — Core
-- Addon object, module system, font objects, SavedVariables init.
local addonName, ns = ...

---------------------------------------------------------------------------
-- Addon object
---------------------------------------------------------------------------

local DCF = {}
DCF.__index = DCF
ns.addon = DCF

---------------------------------------------------------------------------
-- Module system
---------------------------------------------------------------------------

ns.modules  = {}
ns.defaults = {}

function ns:RegisterModule(key, mod, defaults)
    self.modules[key] = mod
    if defaults then
        self.defaults[key] = defaults
    end
end

---------------------------------------------------------------------------
-- Defaults merge (deep, non-destructive)
---------------------------------------------------------------------------

local function MergeDefaults(target, defaults)
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(target[k]) ~= "table" then target[k] = {} end
            MergeDefaults(target[k], v)
        elseif target[k] == nil then
            target[k] = v
        end
    end
end

---------------------------------------------------------------------------
-- Global defaults
---------------------------------------------------------------------------

ns.defaults = {
    enabled           = true,
    showIlvl          = true,
    showEnchants      = true,
    showMissingEnchant = true,
    showGems          = true,
    showMissingGem    = true,
    showSpecDisplay   = true,
    showStatsPanel    = true,
    showTalentCompare = true,
    ilvlFontSize      = 11,
    gemSocketModifier = "alt",   -- "alt", "ctrl", or "shift"
}

---------------------------------------------------------------------------
-- Print helper
---------------------------------------------------------------------------

function DCF:Print(msg)
    print("|cff33ff99DCF:|r " .. tostring(msg))
end

---------------------------------------------------------------------------
-- Font objects
---------------------------------------------------------------------------

local function InitFonts()
    local sm = CreateFont("DCFFontSmall")
    sm:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
    local nm = CreateFont("DCFFontNormal")
    nm:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    local hd = CreateFont("DCFFontHeader")
    hd:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
end

---------------------------------------------------------------------------
-- Master enable/disable toggle
-- Hides or shows all DCF overlays and panels instantly.
---------------------------------------------------------------------------

function DCF:SetEnabled(state)
    ns.db.enabled = state

    -- Slot overlays — UpdateCharacter respects IsEnabled() and hides all if off
    local slotMod = ns.modules.SlotOverlay
    if slotMod and slotMod.UpdateCharacter then
        slotMod:UpdateCharacter()
    end

    -- Spec badge
    local specMod = ns.modules.SpecDisplay
    if specMod and specMod.SetVisible then
        specMod:SetVisible(state and ns.db.showSpecDisplay)
    end

    -- Stats panel: show our panel OR restore Blizzard's
    local statsMod = ns.modules.StatsPanel
    if statsMod and statsMod.SetShown then
        statsMod:SetShown(state and ns.db.showStatsPanel)
    end

    -- Toggle button appearance
    if ns.toggleBtn then
        if state then
            ns.toggleBtn.label:SetTextColor(0.4, 1.0, 0.4)
            ns.toggleBtn.bg:SetColorTexture(0.08, 0.12, 0.08, 0.85)
        else
            ns.toggleBtn.label:SetTextColor(0.6, 0.3, 0.3)
            ns.toggleBtn.bg:SetColorTexture(0.12, 0.06, 0.06, 0.85)
        end
    end
end

function DCF:IsEnabled()
    return ns.db.enabled ~= false
end

---------------------------------------------------------------------------
-- Toggle button on the character frame
---------------------------------------------------------------------------

local function CreateToggleButton(parent)
    local btn = CreateFrame("Button", "DCFToggleButton", parent)
    btn:SetSize(36, 18)
    btn:SetPoint("BOTTOMRIGHT", parent, "TOPRIGHT", -4, 2)
    btn:SetFrameLevel(parent:GetFrameLevel() + 10)

    -- Dark background
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    btn.bg = bg

    -- Subtle border
    local border = btn:CreateTexture(nil, "BORDER")
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetColorTexture(0.3, 0.3, 0.3, 0.5)

    local label = btn:CreateFontString(nil, "OVERLAY")
    label:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
    label:SetAllPoints()
    label:SetJustifyH("CENTER")
    label:SetText("DCF")
    btn.label = label

    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.1)

    btn:SetScript("OnClick", function()
        DCF:SetEnabled(not DCF:IsEnabled())
    end)

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        GameTooltip:SetText("Djinni's Character Frame")
        if DCF:IsEnabled() then
            GameTooltip:AddLine("Click to disable overlays", 0.8, 0.8, 0.8)
        else
            GameTooltip:AddLine("Click to enable overlays", 0.8, 0.8, 0.8)
        end
        GameTooltip:AddLine("/dcf — open settings", 0.5, 0.5, 0.5)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    ns.toggleBtn = btn

    -- Set initial appearance
    if DCF:IsEnabled() then
        label:SetTextColor(0.4, 1.0, 0.4)
        bg:SetColorTexture(0.08, 0.12, 0.08, 0.85)
    else
        label:SetTextColor(0.6, 0.3, 0.3)
        bg:SetColorTexture(0.12, 0.06, 0.06, 0.85)
    end

    return btn
end

ns.CreateToggleButton = CreateToggleButton

---------------------------------------------------------------------------
-- EQOL (EnhanceQoL) conflict detection
-- EnhanceQoL modifies CharacterStatsPane with its own stat formatting.
-- When both are active, they fight over the same panel.
---------------------------------------------------------------------------

local function CheckEQOLConflict()
    local isLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
    if isLoaded and isLoaded("EnhanceQoL") then
        C_Timer.After(4, function()
            if ns.db.showStatsPanel then
                print("|cff33ff99DCF:|r |cffffcc00EnhanceQoL detected.|r Its Character Stats Formatting may conflict with the DCF stats panel.")
                print("|cff33ff99DCF:|r To avoid overlap, disable |cff68ccefEnhanceQoL > Character Stats Formatting|r in its settings, or disable the DCF stats panel in |cff68ccef/dcf|r settings.")
            end
        end)
    end
end

ns.CheckEQOLConflict = CheckEQOLConflict

---------------------------------------------------------------------------
-- Changelog / "loaded" confirmation window
-- Shows once per version on login. Dismiss with close button or Escape.
-- Re-show any time with /dcf changelog
---------------------------------------------------------------------------

local DCF_VERSION = C_AddOns and C_AddOns.GetAddOnMetadata
    and C_AddOns.GetAddOnMetadata(addonName, "Version") or "?"

local CHANGELOG = {
    {
        version = "0.1.0",
        lines = {
            "Per-slot item level on Character + Inspect frames",
            "Enchant names, missing-enchant warning (!), gem counts",
            "Spec + role badge on Character frame",
            "Secondary stats panel (Crit/Haste/Mastery/Vers/etc.)",
            "Inspect companion panel with ilvl, spec, gear audit",
            "Inspect stats inferred from gear (rating + est. %)",
            "Interactive enchant/gem audit with AH shopping lists",
            "Talent comparison (same class + spec)",
            "Tier set detection with bonus status",
            "Per-slot ilvl breakdown tooltip (quality-coloured)",
            "Enable/disable toggle button on Character frame",
            "Blizzard Settings panel with per-feature toggles",
            "/dcf slash command",
        },
    },
}

local changelogFrame = nil

local function CreateChangelogFrame()
    local f = CreateFrame("Frame", "DCFChangelogFrame", UIParent, "BackdropTemplate")
    f:SetSize(360, 340)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetBackdrop({
        bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 14,
        insets   = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    f:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)

    -- Close on Escape
    tinsert(UISpecialFrames, "DCFChangelogFrame")

    -- Title
    local title = f:CreateFontString(nil, "OVERLAY")
    title:SetFont("Fonts\\FRIZQT__.TTF", 14, "")
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetTextColor(1, 0.82, 0)
    title:SetText("Djinni's Character Frame")

    -- Version
    local ver = f:CreateFontString(nil, "OVERLAY")
    ver:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    ver:SetPoint("TOPRIGHT", -14, -14)
    ver:SetTextColor(0.6, 0.6, 0.6)
    ver:SetText("v" .. DCF_VERSION)

    -- Close button
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() f:Hide() end)

    -- Scrollable content
    local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -36)
    scroll:SetPoint("BOTTOMRIGHT", -30, 12)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetWidth(310)
    scroll:SetScrollChild(content)

    -- Build changelog text
    local y = 0
    for _, entry in ipairs(CHANGELOG) do
        local hdr = content:CreateFontString(nil, "OVERLAY")
        hdr:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
        hdr:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
        hdr:SetTextColor(0.4, 0.78, 1.0)
        hdr:SetText("v" .. entry.version)
        y = y - 18

        for _, line in ipairs(entry.lines) do
            local li = content:CreateFontString(nil, "OVERLAY")
            li:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
            li:SetPoint("TOPLEFT", content, "TOPLEFT", 8, y)
            li:SetPoint("RIGHT", content, "RIGHT", -4, 0)
            li:SetJustifyH("LEFT")
            li:SetWordWrap(true)
            li:SetTextColor(0.85, 0.85, 0.85)
            li:SetText("- " .. line)
            -- Estimate height for word-wrapped text
            local lineH = li:GetStringHeight() or 13
            y = y - math.max(lineH + 2, 14)
        end
        y = y - 8
    end

    content:SetHeight(math.abs(y) + 10)

    f:Hide()
    return f
end

function DCF:ShowChangelog()
    if not changelogFrame then
        changelogFrame = CreateChangelogFrame()
    end
    changelogFrame:Show()
end

ns.DCF_VERSION = DCF_VERSION

---------------------------------------------------------------------------
-- Blizzard addon load callbacks
-- Modules register interest in a Blizzard addon; Core fires them when it loads.
---------------------------------------------------------------------------

ns.blizzardCallbacks = {}

function ns:OnBlizzardAddonLoaded(blizzAddon, fn)
    -- If the Blizzard addon already loaded before us, fire immediately
    local isLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
    if isLoaded and isLoaded(blizzAddon) then
        local ok, err = pcall(fn)
        if not ok then
            print("|cffff4444DCF callback error [" .. blizzAddon .. " already-loaded]:|r " .. tostring(err))
        end
        return
    end
    if not self.blizzardCallbacks[blizzAddon] then
        self.blizzardCallbacks[blizzAddon] = {}
    end
    table.insert(self.blizzardCallbacks[blizzAddon], fn)
end

---------------------------------------------------------------------------
-- Combat-safe hook wrapper
-- Wraps hooksecurefunc so errors in addon code never taint or propagate
-- into Blizzard's protected call chain.
---------------------------------------------------------------------------

function ns.SafeHook(funcName, handler)
    hooksecurefunc(funcName, function(...)
        if InCombatLockdown() then
            -- Still allow read-only updates during combat;
            -- only skip if handler explicitly guards against it.
        end
        local ok, err = pcall(handler, ...)
        if not ok then
            -- Suppress repeated noise; first error logged once.
            if not ns._hookErrors then ns._hookErrors = {} end
            if not ns._hookErrors[funcName] then
                ns._hookErrors[funcName] = true
                print("|cffff4444DCF hook error [" .. funcName .. "]:|r " .. tostring(err))
            end
        end
    end)
end

---------------------------------------------------------------------------
-- ADDON_LOADED
---------------------------------------------------------------------------

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(_, event, loaded)
    if event == "PLAYER_LOGIN" then
        ns.db.playerClass = UnitClassBase("player")
        ns.playerClass    = ns.db.playerClass
        -- Check for addon conflicts after login
        if ns.CheckEQOLConflict then ns.CheckEQOLConflict() end
        return
    end
    if loaded == addonName then
        InitFonts()

        local svName = "DjinnisCharacterFrameDB"
        if not _G[svName] then _G[svName] = {} end
        MergeDefaults(_G[svName], ns.defaults)
        ns.db = _G[svName]

        -- Settings UI
        ns.addon:SetupOptions()

        -- Slash command
        SLASH_DCF1 = "/dcf"
        SlashCmdList["DCF"] = function(msg)
            msg = (msg or ""):lower():trim()
            if msg == "changelog" or msg == "cl" or msg == "log" then
                ns.addon:ShowChangelog()
            else
                ns.addon:OpenSettings()
            end
        end

        -- Show changelog once per version
        local seenKey = "lastSeenVersion"
        if ns.db[seenKey] ~= DCF_VERSION then
            C_Timer.After(2, function()
                ns.addon:ShowChangelog()
                ns.db[seenKey] = DCF_VERSION
            end)
        end

        -- Init modules that don't depend on Blizzard addon load order
        for key, mod in pairs(ns.modules) do
            if mod.Init then
                local ok, err = pcall(mod.Init, mod)
                if not ok then
                    print("|cffff4444DCF module init error [" .. tostring(key) .. "]:|r " .. tostring(err))
                end
            end
        end

    elseif ns.blizzardCallbacks[loaded] then
        for _, fn in ipairs(ns.blizzardCallbacks[loaded]) do
            local ok, err = pcall(fn)
            if not ok then
                print("|cffff4444DCF callback error [" .. loaded .. "]:|r " .. tostring(err))
            end
        end
        ns.blizzardCallbacks[loaded] = nil
    end
end)
