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
    showIlvl          = true,
    showEnchants      = true,
    showMissingEnchant = true,
    showGems          = true,
    showMissingGem    = true,
    showSpecDisplay   = true,
    showStatsPanel    = true,
    showTalentCompare = true,
    ilvlFontSize      = 11,
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
-- Blizzard addon load callbacks
-- Modules register interest in a Blizzard addon; Core fires them when it loads.
---------------------------------------------------------------------------

ns.blizzardCallbacks = {}

function ns:OnBlizzardAddonLoaded(blizzAddon, fn)
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
initFrame:SetScript("OnEvent", function(_, _, loaded)
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
        SlashCmdList["DCF"] = function()
            ns.addon:OpenSettings()
        end

        -- Init modules that don't depend on Blizzard addon load order
        for _, mod in pairs(ns.modules) do
            if mod.Init then mod:Init() end
        end

    elseif ns.blizzardCallbacks[loaded] then
        for _, fn in ipairs(ns.blizzardCallbacks[loaded]) do
            fn()
        end
        ns.blizzardCallbacks[loaded] = nil
    end
end)
