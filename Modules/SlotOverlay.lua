-- Djinni's Character Frame — SlotOverlay
-- Creates and updates per-slot ilvl / enchant / gem overlays on both the
-- Character frame and the Inspect frame.
--
-- Overlays are pre-initialised when each Blizzard addon loads (not lazily
-- inside hook callbacks) so that no frames are created during combat.
local addonName, ns = ...

local mod = {}
ns:RegisterModule("SlotOverlay", mod)

local Data = ns.Data

---------------------------------------------------------------------------
-- Overlay widget creation
-- Each slot button gets four overlays:
--   .DCF_ilvl     FontString  bottom-right  item level number
--   .DCF_enchant  FontString  top-left      enchant short name (blue)
--   .DCF_missing  Texture     top-right     red dot when enchant absent
--   .DCF_gems     FontString  bottom-left   "filled/total" gem count
---------------------------------------------------------------------------

local function EnsureOverlays(button)
    if button.DCF_ilvl then return end
    if InCombatLockdown() then return end

    local ilvl = button:CreateFontString(nil, "OVERLAY")
    ilvl:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    ilvl:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
    ilvl:SetJustifyH("RIGHT")
    button.DCF_ilvl = ilvl

    -- Tier badge (e.g. "T1", "T2") — top-left corner
    local tier = button:CreateFontString(nil, "OVERLAY")
    tier:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
    tier:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
    tier:SetJustifyH("LEFT")
    tier:SetTextColor(0.4, 0.78, 1.0, 1)
    tier:Hide()
    button.DCF_tier = tier

    -- Enchant name — anchored after tier or at top-left if no tier
    local ench = button:CreateFontString(nil, "OVERLAY")
    ench:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
    ench:SetPoint("TOPLEFT", tier, "TOPRIGHT", 2, 0)
    ench:SetJustifyH("LEFT")
    ench:SetTextColor(0.4, 1.0, 0.4, 1)
    button.DCF_enchant = ench

    -- Missing enchant: bold "!" text
    local miss = button:CreateFontString(nil, "OVERLAY")
    miss:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    miss:SetPoint("TOPRIGHT", button, "TOPRIGHT", -1, -1)
    miss:SetJustifyH("RIGHT")
    miss:SetTextColor(1, 0.2, 0.2, 1)
    miss:SetText("!")
    miss:Hide()
    button.DCF_missing = miss

    local gems = button:CreateFontString(nil, "OVERLAY")
    gems:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
    gems:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 2, 2)
    gems:SetJustifyH("LEFT")
    button.DCF_gems = gems
end

---------------------------------------------------------------------------
-- Pre-initialise all slot buttons for a given frame type
-- Call these once when the respective Blizzard addon loads, so overlays
-- exist before any combat can occur.
---------------------------------------------------------------------------

local function PreInitCharSlots()
    for slotID, info in pairs(Data.SLOTS) do
        local btn = _G[info.char]
        if btn then
            EnsureOverlays(btn)
            -- Modifier+Right-click opens gem socket popup (player's own gear)
            btn:HookScript("OnClick", function(self, mouseBtn)
                if mouseBtn == "RightButton" then
                    local mod = ns.db.gemSocketModifier or "alt"
                    local held = false
                    if mod == "alt"   then held = IsAltKeyDown()
                    elseif mod == "ctrl"  then held = IsControlKeyDown()
                    elseif mod == "shift" then held = IsShiftKeyDown()
                    end
                    if held then
                        local gemMod = ns.modules.GemSocket
                        if gemMod and gemMod.ShowForSlot then
                            gemMod:ShowForSlot(self, self:GetID())
                        end
                    end
                end
            end)
        end
    end
end

local function PreInitInspectSlots()
    for _, info in pairs(Data.SLOTS) do
        local btn = _G[info.inspect]
        if btn then EnsureOverlays(btn) end
    end
end

---------------------------------------------------------------------------
-- Single-slot update
---------------------------------------------------------------------------

local function UpdateSlot(button, unit)
    if not button or not button.GetID then return end
    -- If overlays somehow don't exist yet (safety net) and we're out of combat,
    -- create them now; otherwise skip silently.
    if not button.DCF_ilvl then
        if InCombatLockdown() then return end
        EnsureOverlays(button)
        if not button.DCF_ilvl then return end
    end

    local db     = ns.db
    local slotID = button:GetID()
    local link   = GetInventoryItemLink(unit, slotID)

    -- Master kill-switch: hide everything if addon is disabled
    if not ns.addon:IsEnabled() then
        button.DCF_ilvl:Hide()
        button.DCF_tier:Hide()
        button.DCF_enchant:Hide()
        button.DCF_missing:Hide()
        button.DCF_gems:Hide()
        return
    end

    -- Item level (coloured by item quality)
    if db.showIlvl then
        local ilvl = Data.GetItemLevel(link)
        if ilvl > 0 then
            button.DCF_ilvl:SetText(ilvl)
            local r, g, b = Data.GetItemQualityColor(link)
            button.DCF_ilvl:SetTextColor(r, g, b)
            button.DCF_ilvl:Show()
        else
            button.DCF_ilvl:Hide()
        end
    else
        button.DCF_ilvl:Hide()
    end

    -- Tier badge
    if link then
        local setName, setCur, setTot = Data.GetSlotTierInfo(unit, slotID)
        if setName then
            button.DCF_tier:SetText("T" .. (setCur or "?"))
            button.DCF_tier:Show()
            -- Re-anchor enchant after visible tier badge
            button.DCF_enchant:SetPoint("TOPLEFT", button.DCF_tier, "TOPRIGHT", 2, 0)
        else
            button.DCF_tier:Hide()
            -- Anchor enchant directly at top-left when no tier
            button.DCF_enchant:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
        end
    else
        button.DCF_tier:Hide()
        button.DCF_enchant:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
    end

    -- Enchants
    local isEnchantable = Data.ENCHANTABLE[slotID]
    if isEnchantable and link then
        local enchID = Data.GetEnchantID(link)
        if enchID > 0 then
            if db.showEnchants then
                local name = Data.GetEnchantName(unit, slotID)
                if name then
                    button.DCF_enchant:SetText(name)
                    button.DCF_enchant:Show()
                else
                    button.DCF_enchant:SetText("Enc")
                    button.DCF_enchant:Show()
                end
            else
                button.DCF_enchant:Hide()
            end
            button.DCF_missing:Hide()
        else
            button.DCF_enchant:Hide()
            if db.showMissingEnchant then
                button.DCF_missing:Show()
            else
                button.DCF_missing:Hide()
            end
        end
    else
        button.DCF_enchant:Hide()
        button.DCF_missing:Hide()
    end

    -- Gems
    if db.showGems or db.showMissingGem then
        local total, filled = Data.GetGemCounts(link)
        if total > 0 then
            if db.showGems then
                button.DCF_gems:SetText(filled .. "/" .. total)
                if filled < total then
                    button.DCF_gems:SetTextColor(db.showMissingGem and 1 or 0.9,
                                                 db.showMissingGem and 0.35 or 0.75,
                                                 db.showMissingGem and 0.1 or 0.2, 1)
                else
                    button.DCF_gems:SetTextColor(0.4, 1, 0.4, 0.8)
                end
                button.DCF_gems:Show()
            else
                button.DCF_gems:Hide()
            end
        else
            button.DCF_gems:Hide()
        end
    else
        button.DCF_gems:Hide()
    end
end

---------------------------------------------------------------------------
-- Bulk updates
---------------------------------------------------------------------------

function mod:UpdateCharacter()
    for _, info in pairs(Data.SLOTS) do
        local btn = _G[info.char]
        if btn then UpdateSlot(btn, "player") end
    end
end

function mod:UpdateInspect(unit)
    unit = unit or (InspectFrame and InspectFrame.unit)
    if not unit then return end
    for _, info in pairs(Data.SLOTS) do
        local btn = _G[info.inspect]
        if btn then UpdateSlot(btn, unit) end
    end
end

function mod:ClearInspect()
    for _, info in pairs(Data.SLOTS) do
        local btn = _G[info.inspect]
        if btn then
            if btn.DCF_ilvl    then btn.DCF_ilvl:Hide() end
            if btn.DCF_tier    then btn.DCF_tier:Hide() end
            if btn.DCF_enchant then btn.DCF_enchant:Hide() end
            if btn.DCF_missing then btn.DCF_missing:Hide() end
            if btn.DCF_gems    then btn.DCF_gems:Hide() end
        end
    end
end

---------------------------------------------------------------------------
-- Init: hook Blizzard update functions when their addons load
---------------------------------------------------------------------------

function mod:Init()
    -- Character frame (Blizzard_UIPanels_Game)
    ns:OnBlizzardAddonLoaded("Blizzard_UIPanels_Game", function()
        PreInitCharSlots()

        -- Create toggle button on character frame
        local charFrame = _G.CharacterFrame
        if charFrame then
            if ns.CreateToggleButton then
                ns.CreateToggleButton(charFrame)
            end
        end

        -- Check for EQOL conflicts
        if ns.CheckEQOLConflict then
            ns.CheckEQOLConflict()
        end

        ns.SafeHook("PaperDollItemSlotButton_Update", function(btn)
            if not ns.addon:IsEnabled() then return end
            if not ns.db.showIlvl and not ns.db.showEnchants
               and not ns.db.showGems and not ns.db.showMissingEnchant
               and not ns.db.showMissingGem then return end
            UpdateSlot(btn, "player")
        end)
    end)

    -- Inspect frame (Blizzard_InspectUI)
    ns:OnBlizzardAddonLoaded("Blizzard_InspectUI", function()
        PreInitInspectSlots()

        ns.SafeHook("InspectPaperDollItemSlotButton_Update", function(btn)
            if not InspectFrame or not InspectFrame.unit then return end
            UpdateSlot(btn, InspectFrame.unit)
        end)

        ns.SafeHook("InspectPaperDollFrame_OnShow", function()
            if InspectFrame and InspectFrame.unit then
                mod:UpdateInspect(InspectFrame.unit)
            end
        end)

        -- HookScript catches ALL hide paths (out-of-range, target change, ESC, etc.)
        InspectFrame:HookScript("OnHide", function()
            local ok, err = pcall(mod.ClearInspect, mod)
            if not ok then
                print("|cffff4444DCF SlotOverlay OnHide error:|r " .. tostring(err))
            end
        end)
    end)

    -- Equipment change → refresh character slots
    local equipFrame = CreateFrame("Frame")
    equipFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    equipFrame:SetScript("OnEvent", function()
        if not ns.addon:IsEnabled() then return end
        local ok, err = pcall(mod.UpdateCharacter, mod)
        if not ok then
            print("|cffff4444DCF SlotOverlay PLAYER_EQUIPMENT_CHANGED error:|r " .. tostring(err))
        end
    end)

    -- Inspect ready → refresh inspect slots
    ns.Inspect:OnInspectReady(function(unit)
        local ok, err = pcall(mod.UpdateInspect, mod, unit)
        if not ok then
            print("|cffff4444DCF SlotOverlay InspectReady error:|r " .. tostring(err))
        end
    end)
end
