-- Djinni's Character Frame — SlotOverlay
-- Creates and updates per-slot ilvl / enchant / gem overlays on both the
-- Character frame and the Inspect frame.
local addonName, ns = ...

local mod = {}
ns:RegisterModule("SlotOverlay", mod)

local Data   = ns.Data
local Inspect = ns.Inspect

---------------------------------------------------------------------------
-- Overlay widget creation
-- Each slot button gets three lazy-created overlays:
--   .DCF_ilvl     FontString  bottom-right  item level number
--   .DCF_enchant  FontString  top-left      enchant short name (green)
--   .DCF_missing  Texture     top-right     red dot when enchant absent
--   .DCF_gems     FontString  bottom-left   "filled/total" gem count
---------------------------------------------------------------------------

local function EnsureOverlays(button)
    if button.DCF_ilvl then return end

    local ilvl = button:CreateFontString(nil, "OVERLAY")
    ilvl:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    ilvl:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
    ilvl:SetJustifyH("RIGHT")
    button.DCF_ilvl = ilvl

    local ench = button:CreateFontString(nil, "OVERLAY")
    ench:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
    ench:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
    ench:SetJustifyH("LEFT")
    ench:SetTextColor(0.4, 0.85, 1, 1)
    button.DCF_enchant = ench

    local miss = button:CreateTexture(nil, "OVERLAY")
    miss:SetSize(7, 7)
    miss:SetPoint("TOPRIGHT", button, "TOPRIGHT", -2, -2)
    miss:SetColorTexture(1, 0.15, 0.15, 0.9)
    miss:Hide()
    button.DCF_missing = miss

    local gems = button:CreateFontString(nil, "OVERLAY")
    gems:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
    gems:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 2, 2)
    gems:SetJustifyH("LEFT")
    button.DCF_gems = gems
end

---------------------------------------------------------------------------
-- Single-slot update
---------------------------------------------------------------------------

local function UpdateSlot(button, unit)
    if not button or not button.GetID then return end
    EnsureOverlays(button)

    local db     = ns.db
    local slotID = button:GetID()
    local link   = GetInventoryItemLink(unit, slotID)

    -- Item level
    if db.showIlvl then
        local ilvl = Data.GetItemLevel(link)
        if ilvl > 0 then
            button.DCF_ilvl:SetText(ilvl)
            button.DCF_ilvl:Show()
        else
            button.DCF_ilvl:Hide()
        end
    else
        button.DCF_ilvl:Hide()
    end

    -- Enchants
    local isEnchantable = Data.ENCHANTABLE[slotID]
    if isEnchantable and link then
        local enchID = Data.GetEnchantID(link)
        if enchID > 0 then
            -- Has an enchant — try to get a readable name
            if db.showEnchants then
                local name = Data.GetEnchantName(unit, slotID)
                if name then
                    -- Truncate to first word or ~10 chars so it fits the slot
                    local short = name:match("^(%S+)") or name
                    if #short > 10 then short = short:sub(1, 10) end
                    button.DCF_enchant:SetText(short)
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
            -- No enchant on an enchantable slot
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
                if filled < total then
                    button.DCF_gems:SetText(filled .. "/" .. total)
                    if db.showMissingGem then
                        button.DCF_gems:SetTextColor(1, 0.35, 0.1, 1)
                    else
                        button.DCF_gems:SetTextColor(0.9, 0.75, 0.2, 1)
                    end
                else
                    button.DCF_gems:SetText(filled .. "/" .. total)
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
    for slotID, info in pairs(Data.SLOTS) do
        local btn = _G[info.char]
        if btn then UpdateSlot(btn, "player") end
    end
end

function mod:UpdateInspect(unit)
    unit = unit or (InspectFrame and InspectFrame.unit)
    if not unit then return end
    for slotID, info in pairs(Data.SLOTS) do
        local btn = _G[info.inspect]
        if btn then UpdateSlot(btn, unit) end
    end
end

function mod:ClearInspect()
    for _, info in pairs(Data.SLOTS) do
        local btn = _G[info.inspect]
        if btn then
            if btn.DCF_ilvl    then btn.DCF_ilvl:Hide() end
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
    -- Character frame hooks (Blizzard_UIPanels_Game)
    ns:OnBlizzardAddonLoaded("Blizzard_UIPanels_Game", function()
        hooksecurefunc("PaperDollItemSlotButton_Update", function(btn)
            if not ns.db.showIlvl and not ns.db.showEnchants
               and not ns.db.showGems and not ns.db.showMissingEnchant
               and not ns.db.showMissingGem then return end
            UpdateSlot(btn, "player")
        end)
    end)

    -- Inspect frame hooks (Blizzard_InspectUI)
    ns:OnBlizzardAddonLoaded("Blizzard_InspectUI", function()
        hooksecurefunc("InspectPaperDollItemSlotButton_Update", function(btn)
            if not InspectFrame or not InspectFrame.unit then return end
            UpdateSlot(btn, InspectFrame.unit)
        end)

        -- Also update when inspect frame is shown (data may already be cached)
        hooksecurefunc("InspectPaperDollFrame_OnShow", function()
            if InspectFrame and InspectFrame.unit then
                mod:UpdateInspect(InspectFrame.unit)
            end
        end)

        -- Clear overlays when inspect frame is closed
        hooksecurefunc("InspectFrame_Hide", function()
            mod:ClearInspect()
        end)
    end)

    -- Update character slots when equipment changes
    local equipFrame = CreateFrame("Frame")
    equipFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    equipFrame:SetScript("OnEvent", function()
        mod:UpdateCharacter()
    end)

    -- Update on inspect ready (fired by Inspect.lua's callbacks)
    ns.Inspect:OnInspectReady(function(unit)
        mod:UpdateInspect(unit)
    end)
end
