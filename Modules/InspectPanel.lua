-- Djinni's Character Frame — InspectPanel
-- Companion stats panel anchored to the right of InspectFrame.
--
-- Sections:
--   Item Level       — C_PaperDollInfo.GetInspectItemLevel or computed
--   Specialisation   — GetInspectSpecialization + GetSpecializationInfoByID
--   Gear Audit       — interactive enchant/gem breakdown with AH shopping lists
--   Attributes       — primary stats summed from gear (C_Item.GetItemStats)
--   Enhancements     — secondary stat ratings summed from gear
--   Talent Compare   — node-by-node diff when same class+spec (C_Traits)
local addonName, ns = ...

local mod = {}
ns:RegisterModule("InspectPanel", mod)

local Data = ns.Data

---------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------

local MAX_DIFF_ROWS = 6
local DIFF_ROW_H    = 15

---------------------------------------------------------------------------
-- Slot lists
---------------------------------------------------------------------------

local ILVL_SLOTS  = { 1,2,3,5,6,7,8,9,10,11,12,13,14,15,16,17 }
local ENCHANTABLE = Data.ENCHANTABLE

---------------------------------------------------------------------------
-- Colours
---------------------------------------------------------------------------

local C_HEADER = { 1.00, 0.82, 0.00 }
local C_LABEL  = { 0.68, 0.68, 0.68 }
local C_VALUE  = { 1.00, 1.00, 1.00 }
local C_GOOD   = { 0.40, 1.00, 0.40 }
local C_WARN   = { 1.00, 0.65, 0.10 }
local C_BAD    = { 1.00, 0.25, 0.25 }
local C_NA     = { 0.45, 0.45, 0.45 }

local CLR_YOU  = "66c8ff"
local CLR_THEM = "ffa533"

---------------------------------------------------------------------------
-- Layout
---------------------------------------------------------------------------

local PANEL_W = 200
local PAD_X   = 10
local PAD_Y   = 8
local ROW_H   = 17
local HDR_H   = 20
local SEP_GAP = 4

---------------------------------------------------------------------------
-- Per-slot detail (populated during Refresh, read by tooltip handlers)
---------------------------------------------------------------------------

local enchDetail = {}   -- { {slotID, slotName, hasEnchant, enchantName}, ... }
local gemDetail  = {}   -- { {slotID, slotName, total, filled}, ... }
local currentUnit = nil

---------------------------------------------------------------------------
-- Auctionator shopping list helpers
---------------------------------------------------------------------------

local function CreateEnchantShoppingList()
    if not Auctionator or not Auctionator.API or not Auctionator.API.v1 then
        ns.addon:Print("Auctionator is not loaded.")
        return
    end
    local parentCat = AUCTION_CATEGORY_ITEM_ENHANCEMENT or "Item Enhancements"
    local expID     = LE_EXPANSION_LEVEL_CURRENT or 11
    local terms     = {}
    for _, info in ipairs(enchDetail) do
        if not info.hasEnchant then
            local cat = Data.SLOT_ENCHANT_CATEGORY[info.slotID]
            if cat then
                table.insert(terms, string.format(
                    ";%s/%s;0;0;0;0;0;0;0;0;;#;%d;", parentCat, cat, expID))
            end
        end
    end
    if #terms == 0 then
        ns.addon:Print("No missing enchants with known AH categories.")
        return
    end
    local ok, err = pcall(Auctionator.API.v1.CreateShoppingList,
        "DjinnisCharacterFrame", "DCF - Missing Enchants", terms)
    if ok then
        ns.addon:Print("Shopping list created with " .. #terms .. " enchant searches.")
    else
        ns.addon:Print("Failed: " .. tostring(err))
    end
end

local function CreateGemShoppingList()
    if not Auctionator or not Auctionator.API or not Auctionator.API.v1 then
        ns.addon:Print("Auctionator is not loaded.")
        return
    end
    local hasMissing = false
    for _, info in ipairs(gemDetail) do
        if info.filled < info.total then hasMissing = true; break end
    end
    if not hasMissing then
        ns.addon:Print("No missing gems.")
        return
    end
    local gemCat = AUCTION_CATEGORY_GEMS or "Gems"
    local expID  = LE_EXPANSION_LEVEL_CURRENT or 11
    local search = string.format(";%s;0;0;0;0;0;0;0;0;;#;%d;", gemCat, expID)
    local ok, err = pcall(Auctionator.API.v1.CreateShoppingList,
        "DjinnisCharacterFrame", "DCF - Gems", { search })
    if ok then
        ns.addon:Print("Gem shopping list created.")
    else
        ns.addon:Print("Failed: " .. tostring(err))
    end
end

---------------------------------------------------------------------------
-- Talent comparison helpers
---------------------------------------------------------------------------

local function GetTalentSpellName(configID, entryID)
    if not entryID or entryID == 0 then return nil end
    if not C_Traits or not C_Traits.GetEntryInfo then return nil end

    local ok, entryInfo = pcall(C_Traits.GetEntryInfo, configID, entryID)
    if not ok or not entryInfo or not entryInfo.definitionID then return nil end

    local ok2, defInfo = pcall(C_Traits.GetDefinitionInfo, entryInfo.definitionID)
    if not ok2 or not defInfo or not defInfo.spellID then return nil end

    if C_Spell and C_Spell.GetSpellName then
        local ok3, name = pcall(C_Spell.GetSpellName, defInfo.spellID)
        if ok3 and name then return name end
    end
    if GetSpellInfo then
        local ok4, name = pcall(GetSpellInfo, defInfo.spellID)
        if ok4 and name then return name end
    end
    return nil
end

--- Returns { total, matching, diffs } or nil, reason.
--- reason == "class" or "spec" means "hide section entirely".
local function ComputeTalentDiff(unit)
    local _, playerClass = UnitClass("player")
    local _, targetClass = UnitClass(unit)
    if not playerClass or not targetClass or playerClass ~= targetClass then
        return nil, "class"
    end

    local playerSpecIndex = C_SpecializationInfo.GetSpecialization()
    if not playerSpecIndex then return nil, "spec" end
    local playerSpecID = select(1, C_SpecializationInfo.GetSpecializationInfo(playerSpecIndex))
    local targetSpecID = C_SpecializationInfo.GetInspectSpecialization(unit)
    if not playerSpecID or not targetSpecID or playerSpecID ~= targetSpecID then
        return nil, "spec"
    end

    if not C_ClassTalents or not C_ClassTalents.GetActiveConfigID then
        return nil, "api"
    end
    local playerConfigID = C_ClassTalents.GetActiveConfigID()
    if not playerConfigID then return nil, "api" end

    if not C_Traits or not C_Traits.GetConfigInfo then return nil, "api" end

    local ok, configInfo = pcall(C_Traits.GetConfigInfo, playerConfigID)
    if not ok or not configInfo or not configInfo.treeIDs
       or #configInfo.treeIDs == 0 then
        return nil, "api"
    end
    local treeID = configInfo.treeIDs[1]

    local ok2, nodeIDs = pcall(C_Traits.GetTreeNodes, treeID)
    if not ok2 or not nodeIDs then return nil, "api" end

    local inspectConfigID
    local ok3, cid = pcall(function()
        return Constants.TraitConsts.INSPECT_TRAIT_CONFIG_ID
    end)
    if ok3 and cid then inspectConfigID = cid end
    if not inspectConfigID then return nil, "api" end

    local totalActive = 0
    local matching    = 0
    local diffs       = {}

    for _, nodeID in ipairs(nodeIDs) do
        local ok4, pNode = pcall(C_Traits.GetNodeInfo, playerConfigID, nodeID)
        local ok5, iNode = pcall(C_Traits.GetNodeInfo, inspectConfigID, nodeID)

        if ok4 and ok5 and pNode and iNode then
            local pRank = pNode.activeRank or 0
            local iRank = iNode.activeRank or 0

            if pRank > 0 or iRank > 0 then
                totalActive = totalActive + 1
                local pEntry = pNode.activeEntry and pNode.activeEntry.entryID or 0
                local iEntry = iNode.activeEntry and iNode.activeEntry.entryID or 0

                if pRank == iRank and pEntry == iEntry then
                    matching = matching + 1
                else
                    table.insert(diffs, {
                        yours     = GetTalentSpellName(playerConfigID, pEntry),
                        theirs    = GetTalentSpellName(inspectConfigID, iEntry),
                        yourRank  = pRank,
                        theirRank = iRank,
                    })
                end
            end
        end
    end

    return {
        total    = totalActive,
        matching = matching,
        diffs    = diffs,
    }
end

---------------------------------------------------------------------------
-- Data computation (ilvl, spec, enchants, gems, gear stats)
---------------------------------------------------------------------------

local function ComputeData(unit)
    local avgIlvl = 0
    if C_PaperDollInfo and C_PaperDollInfo.GetInspectItemLevel then
        avgIlvl = C_PaperDollInfo.GetInspectItemLevel(unit) or 0
    end
    if avgIlvl == 0 then
        local total, count = 0, 0
        for _, sid in ipairs(ILVL_SLOTS) do
            local link = GetInventoryItemLink(unit, sid)
            if link then
                local ilvl = Data.GetItemLevel(link)
                if ilvl > 0 then total = total + ilvl; count = count + 1 end
            end
        end
        if count > 0 then avgIlvl = total / count end
    end

    local specID = C_SpecializationInfo.GetInspectSpecialization(unit)
    local specName, specIcon, specRole
    if specID and specID ~= 0 then
        local sex = UnitSex(unit)
        local _, sn, _, si, _, sr = GetSpecializationInfoByID(specID, sex)
        specName = sn; specIcon = si; specRole = sr
    end

    local enchSlots, enchFilled = 0, 0
    for sid, isEnchantable in pairs(ENCHANTABLE) do
        if isEnchantable then
            local link = GetInventoryItemLink(unit, sid)
            if link then
                enchSlots = enchSlots + 1
                if Data.GetEnchantID(link) > 0 then enchFilled = enchFilled + 1 end
            end
        end
    end

    local gemTotal, gemFilled = 0, 0
    for _, sid in ipairs(ILVL_SLOTS) do
        local link = GetInventoryItemLink(unit, sid)
        if link then
            local t, f = Data.GetGemCounts(link)
            gemTotal  = gemTotal  + t
            gemFilled = gemFilled + f
        end
    end

    local primary, secondary = Data.ComputeGearStats(unit)

    return avgIlvl, specName, specIcon, specRole,
           enchSlots, enchFilled, gemTotal, gemFilled,
           primary, secondary
end

--- Build per-slot enchant/gem detail tables for tooltip display.
local function BuildSlotDetail(unit)
    local ed, gd = {}, {}

    -- Enchant detail: one entry per enchantable slot that has gear
    for _, sid in ipairs(ILVL_SLOTS) do
        if ENCHANTABLE[sid] then
            local link = GetInventoryItemLink(unit, sid)
            if link then
                local hasEnch = Data.GetEnchantID(link) > 0
                local enchName = hasEnch and Data.GetEnchantName(unit, sid) or nil
                table.insert(ed, {
                    slotID    = sid,
                    slotName  = Data.SLOT_NAMES[sid] or "?",
                    hasEnchant = hasEnch,
                    enchantName = enchName,
                })
            end
        end
    end

    -- Gem detail: one entry per slot that has sockets
    for _, sid in ipairs(ILVL_SLOTS) do
        local link = GetInventoryItemLink(unit, sid)
        if link then
            local total, filled = Data.GetGemCounts(link)
            if total > 0 then
                table.insert(gd, {
                    slotID   = sid,
                    slotName = Data.SLOT_NAMES[sid] or "?",
                    total    = total,
                    filled   = filled,
                })
            end
        end
    end

    return ed, gd
end

---------------------------------------------------------------------------
-- Panel state
---------------------------------------------------------------------------

local panel   = nil
local widgets = {}

---------------------------------------------------------------------------
-- Build helpers
---------------------------------------------------------------------------

local function MakeSep(parent, y)
    local sep = parent:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetPoint("TOPLEFT",  parent, "TOPLEFT",  PAD_X,  y)
    sep:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -PAD_X, y)
    sep:SetColorTexture(0.35, 0.35, 0.35, 0.6)
    return y - (1 + SEP_GAP)
end

local function MakeHeader(parent, y, text)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD_X, y)
    fs:SetTextColor(C_HEADER[1], C_HEADER[2], C_HEADER[3])
    fs:SetText(text)
    return y - HDR_H
end

local function MakeRow(parent, y, labelText)
    local lbl = parent:CreateFontString(nil, "OVERLAY")
    lbl:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    lbl:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD_X + 4, y)
    lbl:SetTextColor(C_LABEL[1], C_LABEL[2], C_LABEL[3])
    lbl:SetText(labelText)

    local val = parent:CreateFontString(nil, "OVERLAY")
    val:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    val:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -PAD_X, y)
    val:SetJustifyH("RIGHT")
    val:SetTextColor(C_VALUE[1], C_VALUE[2], C_VALUE[3])

    return y - ROW_H, lbl, val
end

--- Creates a clickable row with hover highlight for interactive Gear Audit lines.
local function MakeClickableRow(parent, y, labelText)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetPoint("TOPLEFT",  parent, "TOPLEFT",  0, y)
    btn:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, y)
    btn:SetHeight(ROW_H)
    btn:SetFrameLevel(parent:GetFrameLevel() + 5)
    btn:RegisterForClicks("LeftButtonUp")

    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.06)

    local lbl = btn:CreateFontString(nil, "OVERLAY")
    lbl:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    lbl:SetPoint("TOPLEFT", btn, "TOPLEFT", PAD_X + 4, 0)
    lbl:SetTextColor(C_LABEL[1], C_LABEL[2], C_LABEL[3])
    lbl:SetText(labelText)

    local val = btn:CreateFontString(nil, "OVERLAY")
    val:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    val:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -PAD_X, 0)
    val:SetJustifyH("RIGHT")
    val:SetTextColor(C_VALUE[1], C_VALUE[2], C_VALUE[3])

    return y - ROW_H, btn, lbl, val
end

---------------------------------------------------------------------------
-- Panel construction
---------------------------------------------------------------------------

local function BuildPanel()
    local f = CreateFrame("Frame", "DCFInspectPanel", UIParent, "BackdropTemplate")
    f:SetWidth(PANEL_W)
    f:SetPoint("TOPLEFT",    InspectFrame, "TOPRIGHT",    4, 0)
    f:SetPoint("BOTTOMLEFT", InspectFrame, "BOTTOMRIGHT", 4, 0)
    f:SetBackdrop({
        bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\ChatFrame\\ChatFrameBackground",
        tile     = true,
        edgeSize = 1,
        tileSize = 8,
    })
    f:SetBackdropColor(0.05, 0.05, 0.05, 0.85)
    f:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.8)

    local y = -PAD_Y

    -- ── Item Level ──────────────────────────────────────────────────────
    y = MakeHeader(f, y, "Item Level")

    local ilvlVal = f:CreateFontString(nil, "OVERLAY")
    ilvlVal:SetFont("Fonts\\FRIZQT__.TTF", 18, "")
    ilvlVal:SetPoint("TOPLEFT", f, "TOPLEFT", PAD_X + 4, y)
    ilvlVal:SetTextColor(0.40, 0.78, 1.00)
    ilvlVal:SetText("—")
    widgets.ilvl = ilvlVal
    y = y - 26

    y = MakeSep(f, y)

    -- ── Specialisation ──────────────────────────────────────────────────
    y = MakeHeader(f, y, "Specialisation")

    local specIconTex = f:CreateTexture(nil, "ARTWORK")
    specIconTex:SetSize(16, 16)
    specIconTex:SetPoint("TOPLEFT", f, "TOPLEFT", PAD_X + 4, y - 1)
    specIconTex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    specIconTex:Hide()
    widgets.specIcon = specIconTex

    local specNameFS = f:CreateFontString(nil, "OVERLAY")
    specNameFS:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    specNameFS:SetPoint("TOPLEFT", specIconTex, "TOPRIGHT", 4, 0)
    specNameFS:SetTextColor(C_VALUE[1], C_VALUE[2], C_VALUE[3])
    specNameFS:SetText("Unknown")
    widgets.specName = specNameFS

    local specRoleFS = f:CreateFontString(nil, "OVERLAY")
    specRoleFS:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
    specRoleFS:SetPoint("TOPLEFT", specNameFS, "BOTTOMLEFT", 0, -2)
    specRoleFS:SetTextColor(C_LABEL[1], C_LABEL[2], C_LABEL[3])
    specRoleFS:SetText("")
    widgets.specRole = specRoleFS
    y = y - ROW_H - 14

    y = MakeSep(f, y)

    -- ── Gear Audit (interactive) ────────────────────────────────────────
    y = MakeHeader(f, y, "Gear Audit")

    -- Enchants row — clickable, shows per-slot tooltip on hover
    local y2, enchBtn, enchLbl, enchVal = MakeClickableRow(f, y, "Enchants:")
    widgets.enchBtn = enchBtn
    widgets.enchVal = enchVal
    y = y2

    enchBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Enchant Status", C_HEADER[1], C_HEADER[2], C_HEADER[3])
        for _, info in ipairs(enchDetail) do
            if info.hasEnchant then
                local name = info.enchantName or "Enchanted"
                GameTooltip:AddDoubleLine(
                    info.slotName, name,
                    C_GOOD[1], C_GOOD[2], C_GOOD[3],
                    C_GOOD[1], C_GOOD[2], C_GOOD[3])
            else
                GameTooltip:AddDoubleLine(
                    info.slotName, "Missing",
                    C_BAD[1], C_BAD[2], C_BAD[3],
                    C_BAD[1], C_BAD[2], C_BAD[3])
            end
        end
        if #enchDetail == 0 then
            GameTooltip:AddLine("No enchantable gear equipped", C_NA[1], C_NA[2], C_NA[3])
        end
        if Auctionator and Auctionator.API then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Click to create AH shopping list", 0.5, 0.5, 0.5)
        end
        GameTooltip:Show()
    end)
    enchBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    enchBtn:SetScript("OnClick", function() CreateEnchantShoppingList() end)

    -- Gems row — clickable
    local y3, gemBtn, gemLbl, gemVal = MakeClickableRow(f, y, "Gems:")
    widgets.gemBtn = gemBtn
    widgets.gemVal = gemVal
    y = y3

    gemBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Gem Status", C_HEADER[1], C_HEADER[2], C_HEADER[3])
        for _, info in ipairs(gemDetail) do
            local missing = info.total - info.filled
            if missing == 0 then
                GameTooltip:AddDoubleLine(
                    info.slotName, info.filled .. " / " .. info.total,
                    C_GOOD[1], C_GOOD[2], C_GOOD[3],
                    C_GOOD[1], C_GOOD[2], C_GOOD[3])
            else
                GameTooltip:AddDoubleLine(
                    info.slotName, info.filled .. " / " .. info.total .. "  (" .. missing .. " empty)",
                    C_BAD[1], C_BAD[2], C_BAD[3],
                    C_BAD[1], C_BAD[2], C_BAD[3])
            end
        end
        if #gemDetail == 0 then
            GameTooltip:AddLine("No socketed gear equipped", C_NA[1], C_NA[2], C_NA[3])
        end
        if Auctionator and Auctionator.API then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Click to create AH shopping list", 0.5, 0.5, 0.5)
        end
        GameTooltip:Show()
    end)
    gemBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    gemBtn:SetScript("OnClick", function() CreateGemShoppingList() end)

    y = MakeSep(f, y)

    -- ── Attributes ──────────────────────────────────────────────────────
    y = MakeHeader(f, y, "Attributes")

    widgets.primaryRows = {}
    for _, def in ipairs(Data.PRIMARY_STAT_KEYS) do
        local yn, lbl, val = MakeRow(f, y, def.label .. ":")
        lbl:Hide(); val:Hide()
        widgets.primaryRows[def.key] = { lbl = lbl, val = val }
        y = yn
    end

    y = MakeSep(f, y)

    -- ── Enhancements ────────────────────────────────────────────────────
    y = MakeHeader(f, y, "Enhancements")

    widgets.secondaryRows = {}
    for _, def in ipairs(Data.SECONDARY_STAT_KEYS) do
        local yn, lbl, val = MakeRow(f, y, def.label .. ":")
        lbl:Hide(); val:Hide()
        widgets.secondaryRows[def.key] = { lbl = lbl, val = val }
        y = yn
    end

    -- Save base y for talent section dynamic positioning
    widgets.talentBaseY = y

    -- ── Talent Comparison ───────────────────────────────────────────────
    local tc = CreateFrame("Frame", nil, f)
    tc:SetPoint("TOPLEFT", f, "TOPLEFT", 0, y)
    tc:SetPoint("RIGHT", f, "RIGHT", 0, 0)
    tc:SetHeight(250)
    widgets.talentFrame = tc

    local ty = 0

    local tSep = tc:CreateTexture(nil, "ARTWORK")
    tSep:SetHeight(1)
    tSep:SetPoint("TOPLEFT",  tc, "TOPLEFT",  PAD_X,  ty)
    tSep:SetPoint("TOPRIGHT", tc, "TOPRIGHT", -PAD_X, ty)
    tSep:SetColorTexture(0.35, 0.35, 0.35, 0.6)
    ty = ty - (1 + SEP_GAP)

    local tHdr = tc:CreateFontString(nil, "OVERLAY")
    tHdr:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
    tHdr:SetPoint("TOPLEFT", tc, "TOPLEFT", PAD_X, ty)
    tHdr:SetTextColor(C_HEADER[1], C_HEADER[2], C_HEADER[3])
    tHdr:SetText("Talent Comparison")
    ty = ty - HDR_H

    local tSummary = tc:CreateFontString(nil, "OVERLAY")
    tSummary:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    tSummary:SetPoint("TOPLEFT",  tc, "TOPLEFT",  PAD_X + 4, ty)
    tSummary:SetPoint("TOPRIGHT", tc, "TOPRIGHT", -PAD_X,    ty)
    tSummary:SetJustifyH("LEFT")
    tSummary:SetTextColor(C_LABEL[1], C_LABEL[2], C_LABEL[3])
    widgets.talentSummary = tSummary
    ty = ty - ROW_H

    widgets.diffRows = {}
    for i = 1, MAX_DIFF_ROWS do
        local fs = tc:CreateFontString(nil, "OVERLAY")
        fs:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
        fs:SetPoint("TOPLEFT",  tc, "TOPLEFT",  PAD_X + 4, ty)
        fs:SetPoint("TOPRIGHT", tc, "TOPRIGHT", -PAD_X,    ty)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        fs:Hide()
        widgets.diffRows[i] = fs
        ty = ty - DIFF_ROW_H
    end

    local overflow = tc:CreateFontString(nil, "OVERLAY")
    overflow:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
    overflow:SetPoint("TOPLEFT", tc, "TOPLEFT", PAD_X + 4, ty)
    overflow:SetTextColor(C_NA[1], C_NA[2], C_NA[3])
    overflow:Hide()
    widgets.talentOverflow = overflow

    tc:Hide()
    f:Hide()
    return f
end

---------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------

local ROLE_LABELS = { TANK = "Tank", HEALER = "Healer", DAMAGER = "DPS" }
local ROLE_COLORS = {
    TANK    = { 0.20, 0.60, 1.00 },
    HEALER  = { 0.20, 0.90, 0.40 },
    DAMAGER = { 1.00, 0.40, 0.30 },
}

local function Refresh(unit)
    if not panel then return end
    if not unit then panel:Hide(); return end

    currentUnit = unit

    local avgIlvl, specName, specIcon, specRole,
          enchSlots, enchFilled, gemTotal, gemFilled,
          primary, secondary = ComputeData(unit)

    -- Build per-slot detail for interactive tooltips
    enchDetail, gemDetail = BuildSlotDetail(unit)

    -- Item level (coloured by class)
    if avgIlvl > 0 then
        widgets.ilvl:SetText(string.format("%.2f", avgIlvl))
        local _, class = UnitClass(unit)
        local cc = class and RAID_CLASS_COLORS[class]
        if cc then
            widgets.ilvl:SetTextColor(cc.r, cc.g, cc.b)
        else
            widgets.ilvl:SetTextColor(0.40, 0.78, 1.00)
        end
    else
        widgets.ilvl:SetText("—")
        widgets.ilvl:SetTextColor(C_NA[1], C_NA[2], C_NA[3])
    end

    -- Spec
    if specName then
        if specIcon then
            widgets.specIcon:SetTexture(specIcon)
            widgets.specIcon:Show()
        else
            widgets.specIcon:Hide()
        end
        widgets.specName:SetText(specName)
        local roleLabel = ROLE_LABELS[specRole] or specRole or ""
        local rc = ROLE_COLORS[specRole] or C_LABEL
        widgets.specRole:SetText(roleLabel)
        widgets.specRole:SetTextColor(rc[1], rc[2], rc[3])
    else
        widgets.specIcon:Hide()
        widgets.specName:SetText("Unknown")
        widgets.specRole:SetText("")
    end

    -- Enchants
    if enchSlots > 0 then
        local missing = enchSlots - enchFilled
        widgets.enchVal:SetText(enchFilled .. " / " .. enchSlots)
        if missing == 0 then
            widgets.enchVal:SetTextColor(C_GOOD[1], C_GOOD[2], C_GOOD[3])
        elseif missing == enchSlots then
            widgets.enchVal:SetTextColor(C_BAD[1],  C_BAD[2],  C_BAD[3])
        else
            widgets.enchVal:SetTextColor(C_WARN[1], C_WARN[2], C_WARN[3])
        end
    else
        widgets.enchVal:SetText("—")
        widgets.enchVal:SetTextColor(C_NA[1], C_NA[2], C_NA[3])
    end

    -- Gems
    if gemTotal > 0 then
        local missing = gemTotal - gemFilled
        widgets.gemVal:SetText(gemFilled .. " / " .. gemTotal)
        if missing == 0 then
            widgets.gemVal:SetTextColor(C_GOOD[1], C_GOOD[2], C_GOOD[3])
        elseif missing == gemTotal then
            widgets.gemVal:SetTextColor(C_BAD[1],  C_BAD[2],  C_BAD[3])
        else
            widgets.gemVal:SetTextColor(C_WARN[1], C_WARN[2], C_WARN[3])
        end
    else
        widgets.gemVal:SetText("—")
        widgets.gemVal:SetTextColor(C_NA[1], C_NA[2], C_NA[3])
    end

    -- Primary stats
    local hiddenPrimary = 0
    for _, def in ipairs(Data.PRIMARY_STAT_KEYS) do
        local row = widgets.primaryRows[def.key]
        if row then
            local v = primary[def.key]
            if v and v > 0 then
                row.val:SetText(Data.FormatNumber(v))
                row.lbl:Show(); row.val:Show()
            else
                row.lbl:Hide(); row.val:Hide()
                hiddenPrimary = hiddenPrimary + 1
            end
        end
    end

    -- Secondary stats
    local hiddenSecondary = 0
    for _, def in ipairs(Data.SECONDARY_STAT_KEYS) do
        local row = widgets.secondaryRows[def.key]
        if row then
            local v = secondary[def.key]
            if v and v > 0 then
                row.val:SetText(Data.FormatNumber(v))
                row.lbl:Show(); row.val:Show()
            else
                row.lbl:Hide(); row.val:Hide()
                hiddenSecondary = hiddenSecondary + 1
            end
        end
    end

    -- Reposition talent section
    local talentY = widgets.talentBaseY + (hiddenPrimary + hiddenSecondary) * ROW_H
    widgets.talentFrame:ClearAllPoints()
    widgets.talentFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, talentY)
    widgets.talentFrame:SetPoint("RIGHT",   panel, "RIGHT",   0, 0)

    -- Talent comparison
    if not ns.db.showTalentCompare then
        widgets.talentFrame:Hide()
    else
        local result, reason = ComputeTalentDiff(unit)

        if not result then
            -- Hide entirely for different class or spec
            if reason == "class" or reason == "spec" then
                widgets.talentFrame:Hide()
            else
                -- API/config issue — show the section with a message
                widgets.talentSummary:SetText(reason == "api" and "Talent API unavailable" or "Not available")
                widgets.talentSummary:SetTextColor(C_NA[1], C_NA[2], C_NA[3])
                for i = 1, MAX_DIFF_ROWS do widgets.diffRows[i]:Hide() end
                widgets.talentOverflow:Hide()
                widgets.talentFrame:Show()
            end
        else
            local pct = result.total > 0
                and math.floor(result.matching / result.total * 100) or 0
            widgets.talentSummary:SetText(
                string.format("%d / %d match (%d%%)", result.matching, result.total, pct))
            if pct == 100 then
                widgets.talentSummary:SetTextColor(C_GOOD[1], C_GOOD[2], C_GOOD[3])
            elseif pct >= 80 then
                widgets.talentSummary:SetTextColor(C_WARN[1], C_WARN[2], C_WARN[3])
            else
                widgets.talentSummary:SetTextColor(C_BAD[1],  C_BAD[2],  C_BAD[3])
            end

            local maxShow = math.min(#result.diffs, MAX_DIFF_ROWS)
            for i = 1, MAX_DIFF_ROWS do
                if i <= maxShow then
                    local d = result.diffs[i]
                    local pName = d.yourRank > 0  and (d.yours  or "?") or "not taken"
                    local iName = d.theirRank > 0 and (d.theirs or "?") or "not taken"
                    widgets.diffRows[i]:SetText(
                        string.format("|cff%s%s|r  →  |cff%s%s|r",
                            CLR_YOU, pName, CLR_THEM, iName))
                    widgets.diffRows[i]:Show()
                else
                    widgets.diffRows[i]:Hide()
                end
            end

            if #result.diffs > MAX_DIFF_ROWS then
                widgets.talentOverflow:SetText("… and " .. (#result.diffs - MAX_DIFF_ROWS) .. " more")
                widgets.talentOverflow:Show()
            else
                widgets.talentOverflow:Hide()
            end

            widgets.talentFrame:Show()
        end
    end

    panel:Show()
end

local function SafeRefresh(unit)
    local ok, err = pcall(Refresh, unit)
    if not ok then
        if not ns._ipErrors then ns._ipErrors = {} end
        if not ns._ipErrors.refresh then
            ns._ipErrors.refresh = true
            print("|cffff4444DCF InspectPanel Refresh error:|r " .. tostring(err))
        end
    end
end

---------------------------------------------------------------------------
-- Init
---------------------------------------------------------------------------

function mod:Init()
    ns:OnBlizzardAddonLoaded("Blizzard_InspectUI", function()
        local ok, err = pcall(function()
            panel = BuildPanel()

            ns.SafeHook("InspectFrame_OnShow", function()
                if InspectFrame and InspectFrame.unit then
                    panel:Show()
                end
            end)

            InspectFrame:HookScript("OnHide", function()
                if panel then panel:Hide() end
            end)

            ns.Inspect:OnInspectReady(function(unit)
                SafeRefresh(unit)
            end)

            ns.SafeHook("InspectPaperDollFrame_UpdateButtons", function()
                if InspectFrame and InspectFrame.unit then
                    SafeRefresh(InspectFrame.unit)
                end
            end)
        end)
        if not ok then
            print("|cffff4444DCF InspectPanel init error:|r " .. tostring(err))
        end
    end)
end
