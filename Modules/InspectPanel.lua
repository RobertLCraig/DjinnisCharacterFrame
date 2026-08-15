-- Djinni's Character Frame — InspectPanel
-- Companion stats panel anchored to the right of InspectFrame.
-- Matches the character frame StatsPanel visual style: gradient headers,
-- collapsible sections, stat rows with tooltips.
--
-- Sections:
--   Item Level       — avg ilvl (class-coloured) + per-slot breakdown tooltip
--   Specialisation   — spec icon + name + role badge
--   Gear Audit       — interactive enchant/gem status with AH shopping lists
--   Tier Sets        — class set detection with bonus status
--   Attributes       — primary stat + stamina + health
--   Secondary        — crit/haste/mastery/vers (rating + estimated %)
--   Defense          — dodge/parry (estimated)
--   General          — leech/avoidance/speed (from gear)
--   Talent Compare   — node-by-node diff when same class+spec
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

local ILVL_SLOTS  = Data.ILVL_SLOTS
local ENCHANTABLE = Data.ENCHANTABLE

---------------------------------------------------------------------------
-- Section colours (match StatsPanel)
---------------------------------------------------------------------------

local SEC_COLORS = {
    ILVL       = { r = 0.40, g = 0.78, b = 1.00 },
    SPEC       = { r = 0.80, g = 0.60, b = 1.00 },
    AUDIT      = { r = 1.00, g = 0.82, b = 0.00 },
    TIER       = { r = 0.40, g = 0.78, b = 1.00 },
    ATTRIBUTES = { r = 0.90, g = 0.70, b = 0.20 },
    SECONDARY  = { r = 0.40, g = 0.80, b = 0.40 },
    DEFENSE    = { r = 0.29, g = 0.46, b = 0.90 },
    GENERAL    = { r = 0.70, g = 0.70, b = 0.70 },
    TALENTS    = { r = 0.80, g = 0.40, b = 1.00 },
}

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

local PANEL_W = 210
local PAD_X   = 8
local PAD_Y   = 6
local ROW_H   = 17
local HDR_H   = 18
local ROW_SPC = 1

---------------------------------------------------------------------------
-- Per-slot detail (populated during Refresh)
---------------------------------------------------------------------------

local enchDetail  = {}
local gemDetail   = {}
local slotDetail  = {}
local currentUnit = nil

---------------------------------------------------------------------------
-- Auctionator shopping list helpers
---------------------------------------------------------------------------

local function CreateEnchantShoppingList()
    if not Auctionator or not Auctionator.API or not Auctionator.API.v1 then
        ns.addon:Print("Auctionator is not loaded."); return
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
        ns.addon:Print("No missing enchants with known AH categories."); return
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
        ns.addon:Print("Auctionator is not loaded."); return
    end
    local hasMissing = false
    for _, info in ipairs(gemDetail) do
        if info.filled < info.total then hasMissing = true; break end
    end
    if not hasMissing then
        ns.addon:Print("No missing gems."); return
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

    local totalActive, matching, diffs = 0, 0, {}
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
    return { total = totalActive, matching = matching, diffs = diffs }
end

---------------------------------------------------------------------------
-- Data computation
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

local function BuildSlotDetail(unit)
    local ed, gd = {}, {}
    for _, sid in ipairs(ILVL_SLOTS) do
        if ENCHANTABLE[sid] then
            local link = GetInventoryItemLink(unit, sid)
            if link then
                local hasEnch = Data.GetEnchantID(link) > 0
                local enchName = hasEnch and Data.GetEnchantName(unit, sid) or nil
                table.insert(ed, {
                    slotID      = sid,
                    slotName    = Data.SLOT_NAMES[sid] or "?",
                    hasEnchant  = hasEnch,
                    enchantName = enchName,
                })
            end
        end
    end
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
-- Build helpers (matching StatsPanel visual style)
---------------------------------------------------------------------------

local function MakeGradientHeader(parent, key, title, color, y)
    local f = CreateFrame("Button", nil, parent)
    f:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
    f:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
    f:SetHeight(HDR_H)

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(color.r, color.g, color.b, 0.20)

    local grad = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    grad:SetAllPoints()
    grad:SetGradient("HORIZONTAL",
        CreateColor(color.r, color.g, color.b, 0.30),
        CreateColor(color.r, color.g, color.b, 0.03))

    local chev = f:CreateFontString(nil, "OVERLAY")
    chev:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
    chev:SetPoint("LEFT", f, "LEFT", 4, 0)
    chev:SetTextColor(color.r, color.g, color.b, 0.7)
    f.chevron = chev

    local txt = f:CreateFontString(nil, "OVERLAY")
    txt:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    txt:SetPoint("LEFT", chev, "RIGHT", 3, 0)
    txt:SetTextColor(color.r, color.g, color.b, 1)
    txt:SetText(title)

    local hl = f:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.04)

    f.isCollapsed = false
    f.sectionKey = key

    local function UpdateChev()
        chev:SetText(f.isCollapsed and "+" or "-")
    end
    UpdateChev()

    f:SetScript("OnClick", function()
        f.isCollapsed = not f.isCollapsed
        UpdateChev()
        if widgets.layoutFunc then widgets.layoutFunc() end
    end)

    return f, y - HDR_H - ROW_SPC
end

local function MakeStatRow(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(ROW_H)

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.05, 0.05, 0.4)

    local lbl = f:CreateFontString(nil, "OVERLAY")
    lbl:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    lbl:SetPoint("LEFT", f, "LEFT", PAD_X, 0)
    lbl:SetJustifyH("LEFT")
    lbl:SetTextColor(C_LABEL[1], C_LABEL[2], C_LABEL[3])
    f.label = lbl

    local val = f:CreateFontString(nil, "OVERLAY")
    val:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    val:SetPoint("RIGHT", f, "RIGHT", -PAD_X, 0)
    val:SetJustifyH("RIGHT")
    val:SetTextColor(C_VALUE[1], C_VALUE[2], C_VALUE[3])
    f.value = val

    local hl = f:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.04)

    f:EnableMouse(true)
    f.tooltipTitle = nil
    f.tooltipBody  = nil

    f:SetScript("OnEnter", function(self)
        if self.tooltipTitle then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.tooltipTitle, 1, 0.82, 0)
            if self.tooltipBody then
                GameTooltip:AddLine(self.tooltipBody, 1, 1, 1, true)
            end
            GameTooltip:Show()
        end
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)

    f.isHidden = false
    return f
end

local function MakeClickableRow(parent)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetHeight(ROW_H)
    btn:RegisterForClicks("LeftButtonUp")

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.05, 0.05, 0.4)

    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.06)

    local lbl = btn:CreateFontString(nil, "OVERLAY")
    lbl:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    lbl:SetPoint("LEFT", btn, "LEFT", PAD_X, 0)
    lbl:SetJustifyH("LEFT")
    lbl:SetTextColor(C_LABEL[1], C_LABEL[2], C_LABEL[3])
    btn.label = lbl

    local val = btn:CreateFontString(nil, "OVERLAY")
    val:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    val:SetPoint("RIGHT", btn, "RIGHT", -PAD_X, 0)
    val:SetJustifyH("RIGHT")
    val:SetTextColor(C_VALUE[1], C_VALUE[2], C_VALUE[3])
    btn.value = val

    return btn
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
        tile = true, edgeSize = 1, tileSize = 8,
    })
    f:SetBackdropColor(0.04, 0.04, 0.04, 0.9)
    f:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.8)

    -- Scrollable content
    local sf = CreateFrame("ScrollFrame", nil, f, "ScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -2)
    sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 2)

    local sc = CreateFrame("Frame", nil, sf)
    sc:SetWidth(PANEL_W - 16)
    sf:SetScrollChild(sc)
    widgets.scrollChild = sc

    -- ── Item Level ──────────────────────────────────────────────────────
    local ilvlHdr
    ilvlHdr, _ = MakeGradientHeader(sc, "ILVL", "Item Level", SEC_COLORS.ILVL, 0)
    widgets.ilvlHeader = ilvlHdr

    -- Big ilvl display
    local ilvlRow = CreateFrame("Button", nil, sc)
    ilvlRow:SetHeight(24)
    ilvlRow:RegisterForClicks("LeftButtonUp")
    local ilvlVal = ilvlRow:CreateFontString(nil, "OVERLAY")
    ilvlVal:SetFont("Fonts\\FRIZQT__.TTF", 16, "OUTLINE")
    ilvlVal:SetPoint("LEFT", ilvlRow, "LEFT", PAD_X, 0)
    ilvlVal:SetTextColor(0.40, 0.78, 1.00)
    widgets.ilvl = ilvlVal
    widgets.ilvlRow = ilvlRow

    local slotsFS = ilvlRow:CreateFontString(nil, "OVERLAY")
    slotsFS:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
    slotsFS:SetPoint("RIGHT", ilvlRow, "RIGHT", -PAD_X, 0)
    slotsFS:SetJustifyH("RIGHT")
    slotsFS:SetTextColor(C_LABEL[1], C_LABEL[2], C_LABEL[3])
    widgets.slotsCount = slotsFS

    ilvlRow:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Per-Slot Item Level", 1, 0.82, 0)
        for _, info in ipairs(slotDetail) do
            local qc = Data.QUALITY_COLORS[info.quality] or Data.QUALITY_COLORS[1]
            GameTooltip:AddDoubleLine(info.slotName, tostring(info.ilvl),
                qc[1], qc[2], qc[3], qc[1], qc[2], qc[3])
        end
        if #slotDetail == 0 then
            GameTooltip:AddLine("No items detected", C_NA[1], C_NA[2], C_NA[3])
        end
        GameTooltip:Show()
    end)
    ilvlRow:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- ── Specialisation ──────────────────────────────────────────────────
    local specHdr
    specHdr, _ = MakeGradientHeader(sc, "SPEC", "Specialisation", SEC_COLORS.SPEC, 0)
    widgets.specHeader = specHdr

    local specRow = CreateFrame("Frame", nil, sc)
    specRow:SetHeight(ROW_H + 14)

    local specIcon = specRow:CreateTexture(nil, "ARTWORK")
    specIcon:SetSize(16, 16)
    specIcon:SetPoint("TOPLEFT", specRow, "TOPLEFT", PAD_X, -2)
    specIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    specIcon:Hide()
    widgets.specIcon = specIcon

    local specName = specRow:CreateFontString(nil, "OVERLAY")
    specName:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    specName:SetPoint("TOPLEFT", specIcon, "TOPRIGHT", 4, 0)
    specName:SetTextColor(1, 1, 1)
    widgets.specName = specName

    local specRole = specRow:CreateFontString(nil, "OVERLAY")
    specRole:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
    specRole:SetPoint("TOPLEFT", specName, "BOTTOMLEFT", 0, -2)
    specRole:SetTextColor(C_LABEL[1], C_LABEL[2], C_LABEL[3])
    widgets.specRole = specRole
    widgets.specRow = specRow

    -- ── Gear Audit ──────────────────────────────────────────────────────
    local auditHdr
    auditHdr, _ = MakeGradientHeader(sc, "AUDIT", "Gear Audit", SEC_COLORS.AUDIT, 0)
    widgets.auditHeader = auditHdr

    local enchBtn = MakeClickableRow(sc)
    enchBtn.label:SetText("Enchants:")
    widgets.enchBtn = enchBtn

    enchBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Enchant Status", 1, 0.82, 0)
        for _, info in ipairs(enchDetail) do
            if info.hasEnchant then
                GameTooltip:AddDoubleLine(info.slotName, info.enchantName or "Enchanted",
                    C_GOOD[1], C_GOOD[2], C_GOOD[3], C_GOOD[1], C_GOOD[2], C_GOOD[3])
            else
                GameTooltip:AddDoubleLine(info.slotName, "Missing",
                    C_BAD[1], C_BAD[2], C_BAD[3], C_BAD[1], C_BAD[2], C_BAD[3])
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

    local gemBtn = MakeClickableRow(sc)
    gemBtn.label:SetText("Gems:")
    widgets.gemBtn = gemBtn

    gemBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Gem Status", 1, 0.82, 0)
        for _, info in ipairs(gemDetail) do
            local missing = info.total - info.filled
            if missing == 0 then
                GameTooltip:AddDoubleLine(info.slotName, info.filled .. "/" .. info.total,
                    C_GOOD[1], C_GOOD[2], C_GOOD[3], C_GOOD[1], C_GOOD[2], C_GOOD[3])
            else
                GameTooltip:AddDoubleLine(info.slotName,
                    info.filled .. "/" .. info.total .. "  (" .. missing .. " empty)",
                    C_BAD[1], C_BAD[2], C_BAD[3], C_BAD[1], C_BAD[2], C_BAD[3])
            end
        end
        if #gemDetail == 0 then
            GameTooltip:AddLine("No socketed gear", C_NA[1], C_NA[2], C_NA[3])
        end
        if Auctionator and Auctionator.API then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Click to create AH shopping list", 0.5, 0.5, 0.5)
        end
        GameTooltip:Show()
    end)
    gemBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    gemBtn:SetScript("OnClick", function() CreateGemShoppingList() end)

    -- ── Tier Sets ───────────────────────────────────────────────────────
    local tierHdr
    tierHdr, _ = MakeGradientHeader(sc, "TIER", "Tier Sets", SEC_COLORS.TIER, 0)
    widgets.tierHeader = tierHdr

    widgets.tierRows = {}
    for i = 1, 2 do
        local nameRow = MakeStatRow(sc)
        local bonusRow = CreateFrame("Frame", nil, sc)
        bonusRow:SetHeight(ROW_H)
        local bonusLbl = bonusRow:CreateFontString(nil, "OVERLAY")
        bonusLbl:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
        bonusLbl:SetPoint("TOPLEFT", bonusRow, "TOPLEFT", PAD_X + 4, 0)
        bonusLbl:SetPoint("TOPRIGHT", bonusRow, "TOPRIGHT", -PAD_X, 0)
        bonusLbl:SetJustifyH("LEFT")
        bonusLbl:SetWordWrap(true)
        bonusLbl:SetTextColor(C_LABEL[1], C_LABEL[2], C_LABEL[3])
        bonusRow.label = bonusLbl

        widgets.tierRows[i] = { name = nameRow, bonus = bonusRow }
    end

    -- ── Attributes ──────────────────────────────────────────────────────
    local attrHdr
    attrHdr, _ = MakeGradientHeader(sc, "ATTRIBUTES", "Attributes", SEC_COLORS.ATTRIBUTES, 0)
    widgets.attrHeader = attrHdr

    widgets.primaryRows = {}
    for _, def in ipairs(Data.PRIMARY_STAT_KEYS) do
        local row = MakeStatRow(sc)
        row.label:SetText(def.label)
        row.statKey = def.key
        widgets.primaryRows[def.key] = row
    end

    -- ── Secondary ───────────────────────────────────────────────────────
    local secHdr
    secHdr, _ = MakeGradientHeader(sc, "SECONDARY", "Secondary", SEC_COLORS.SECONDARY, 0)
    widgets.secHeader = secHdr

    widgets.secondaryRows = {}
    for _, def in ipairs(Data.SECONDARY_STAT_KEYS) do
        local row = MakeStatRow(sc)
        row.label:SetText(def.shortLabel)
        row.statKey = def.key
        row.cr = def.cr
        widgets.secondaryRows[def.key] = row
    end

    -- ── Talent Comparison ───────────────────────────────────────────────
    local talentHdr
    talentHdr, _ = MakeGradientHeader(sc, "TALENTS", "Talent Comparison", SEC_COLORS.TALENTS, 0)
    widgets.talentHeader = talentHdr

    local talentSummary = sc:CreateFontString(nil, "OVERLAY")
    talentSummary:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    talentSummary:SetJustifyH("LEFT")
    talentSummary:SetTextColor(C_LABEL[1], C_LABEL[2], C_LABEL[3])
    widgets.talentSummary = talentSummary

    widgets.diffRows = {}
    for i = 1, MAX_DIFF_ROWS do
        local fs = sc:CreateFontString(nil, "OVERLAY")
        fs:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        fs:Hide()
        widgets.diffRows[i] = fs
    end

    local overflow = sc:CreateFontString(nil, "OVERLAY")
    overflow:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
    overflow:SetTextColor(C_NA[1], C_NA[2], C_NA[3])
    overflow:Hide()
    widgets.talentOverflow = overflow

    -- ── Layout function ─────────────────────────────────────────────────
    -- Dynamically positions all elements, respecting collapsed sections
    -- and hidden rows.
    widgets.layoutFunc = function()
        local y = -PAD_Y
        local w = sc:GetWidth()

        local function PlaceHeader(hdr)
            hdr:ClearAllPoints()
            hdr:SetPoint("TOPLEFT", sc, "TOPLEFT", 0, y)
            hdr:SetPoint("RIGHT", sc, "RIGHT", 0, 0)
            hdr:Show()
            y = y - HDR_H - ROW_SPC
        end

        local function PlaceRow(row)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", sc, "TOPLEFT", 0, y)
            row:SetPoint("RIGHT", sc, "RIGHT", 0, 0)
            row:Show()
            y = y - ROW_H - ROW_SPC
        end

        local function PlaceFS(fs, h)
            fs:ClearAllPoints()
            fs:SetPoint("TOPLEFT", sc, "TOPLEFT", PAD_X, y)
            fs:SetPoint("RIGHT", sc, "RIGHT", -PAD_X, 0)
            fs:Show()
            y = y - (h or DIFF_ROW_H) - ROW_SPC
        end

        -- Item Level
        PlaceHeader(widgets.ilvlHeader)
        if not widgets.ilvlHeader.isCollapsed then
            widgets.ilvlRow:ClearAllPoints()
            widgets.ilvlRow:SetPoint("TOPLEFT", sc, "TOPLEFT", 0, y)
            widgets.ilvlRow:SetPoint("RIGHT", sc, "RIGHT", 0, 0)
            widgets.ilvlRow:Show()
            y = y - 24 - ROW_SPC
        else
            widgets.ilvlRow:Hide()
        end

        -- Spec
        PlaceHeader(widgets.specHeader)
        if not widgets.specHeader.isCollapsed then
            widgets.specRow:ClearAllPoints()
            widgets.specRow:SetPoint("TOPLEFT", sc, "TOPLEFT", 0, y)
            widgets.specRow:SetPoint("RIGHT", sc, "RIGHT", 0, 0)
            widgets.specRow:Show()
            y = y - (ROW_H + 14) - ROW_SPC
        else
            widgets.specRow:Hide()
        end

        -- Gear Audit
        PlaceHeader(widgets.auditHeader)
        if not widgets.auditHeader.isCollapsed then
            PlaceRow(widgets.enchBtn)
            PlaceRow(widgets.gemBtn)
        else
            widgets.enchBtn:Hide()
            widgets.gemBtn:Hide()
        end

        -- Tier Sets
        if widgets.tierVisible then
            PlaceHeader(widgets.tierHeader)
            if not widgets.tierHeader.isCollapsed then
                for i = 1, widgets.tierCount or 0 do
                    local tr = widgets.tierRows[i]
                    PlaceRow(tr.name)
                    PlaceRow(tr.bonus)
                end
            end
        else
            widgets.tierHeader:Hide()
        end
        -- Hide unused tier rows always
        for i = (widgets.tierCount or 0) + 1, 2 do
            widgets.tierRows[i].name:Hide()
            widgets.tierRows[i].bonus:Hide()
        end

        -- Attributes
        PlaceHeader(widgets.attrHeader)
        if not widgets.attrHeader.isCollapsed then
            for _, def in ipairs(Data.PRIMARY_STAT_KEYS) do
                local row = widgets.primaryRows[def.key]
                if not row.isHidden then
                    PlaceRow(row)
                else
                    row:Hide()
                end
            end
        else
            for _, def in ipairs(Data.PRIMARY_STAT_KEYS) do
                widgets.primaryRows[def.key]:Hide()
            end
        end

        -- Secondary
        PlaceHeader(widgets.secHeader)
        if not widgets.secHeader.isCollapsed then
            for _, def in ipairs(Data.SECONDARY_STAT_KEYS) do
                local row = widgets.secondaryRows[def.key]
                if not row.isHidden then
                    PlaceRow(row)
                else
                    row:Hide()
                end
            end
        else
            for _, def in ipairs(Data.SECONDARY_STAT_KEYS) do
                widgets.secondaryRows[def.key]:Hide()
            end
        end

        -- Talent Comparison
        if widgets.talentVisible then
            PlaceHeader(widgets.talentHeader)
            if not widgets.talentHeader.isCollapsed then
                PlaceFS(widgets.talentSummary, ROW_H)
                for i = 1, MAX_DIFF_ROWS do
                    local fs = widgets.diffRows[i]
                    if fs:IsShown() then
                        PlaceFS(fs)
                    end
                end
                if widgets.talentOverflow:IsShown() then
                    PlaceFS(widgets.talentOverflow)
                end
            else
                widgets.talentSummary:Hide()
                for i = 1, MAX_DIFF_ROWS do widgets.diffRows[i]:Hide() end
                widgets.talentOverflow:Hide()
            end
        else
            widgets.talentHeader:Hide()
            widgets.talentSummary:Hide()
            for i = 1, MAX_DIFF_ROWS do widgets.diffRows[i]:Hide() end
            widgets.talentOverflow:Hide()
        end

        sc:SetHeight(math.abs(y) + PAD_Y)
    end

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

local function Fmt(n) return Data.FormatNumber(n) end
local function PctFmt(n) return string.format("%.2f%%", n or 0) end

local function Refresh(unit)
    if not panel then return end
    if not unit then panel:Hide(); return end

    currentUnit = unit

    local avgIlvl, specName, specIcon, specRole,
          enchSlots, enchFilled, gemTotal, gemFilled,
          primary, secondary = ComputeData(unit)

    enchDetail, gemDetail = BuildSlotDetail(unit)
    slotDetail = Data.GetPerSlotIlvl(unit)

    -- Item level (class-coloured)
    if avgIlvl > 0 then
        widgets.ilvl:SetText(string.format("%.1f", avgIlvl))
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
    widgets.slotsCount:SetText(#slotDetail .. "/16")

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
        widgets.enchBtn.value:SetText(enchFilled .. "/" .. enchSlots)
        if missing == 0 then
            widgets.enchBtn.value:SetTextColor(C_GOOD[1], C_GOOD[2], C_GOOD[3])
        elseif missing == enchSlots then
            widgets.enchBtn.value:SetTextColor(C_BAD[1], C_BAD[2], C_BAD[3])
        else
            widgets.enchBtn.value:SetTextColor(C_WARN[1], C_WARN[2], C_WARN[3])
        end
    else
        widgets.enchBtn.value:SetText("—")
        widgets.enchBtn.value:SetTextColor(C_NA[1], C_NA[2], C_NA[3])
    end

    -- Gems
    if gemTotal > 0 then
        local missing = gemTotal - gemFilled
        widgets.gemBtn.value:SetText(gemFilled .. "/" .. gemTotal)
        if missing == 0 then
            widgets.gemBtn.value:SetTextColor(C_GOOD[1], C_GOOD[2], C_GOOD[3])
        elseif missing == gemTotal then
            widgets.gemBtn.value:SetTextColor(C_BAD[1], C_BAD[2], C_BAD[3])
        else
            widgets.gemBtn.value:SetTextColor(C_WARN[1], C_WARN[2], C_WARN[3])
        end
    else
        widgets.gemBtn.value:SetText("—")
        widgets.gemBtn.value:SetTextColor(C_NA[1], C_NA[2], C_NA[3])
    end

    -- Tier sets
    local tierSets = Data.GetTierSetInfo(unit)
    if tierSets and #tierSets > 0 then
        widgets.tierVisible = true
        widgets.tierCount = math.min(#tierSets, 2)
        for i = 1, widgets.tierCount do
            local tr = widgets.tierRows[i]
            local ts = tierSets[i]
            tr.name.label:SetText(ts.name)
            tr.name.value:SetText(ts.count .. "/" .. ts.total)
            if ts.count >= ts.total then
                tr.name.value:SetTextColor(C_GOOD[1], C_GOOD[2], C_GOOD[3])
            elseif ts.count >= 2 then
                tr.name.value:SetTextColor(C_WARN[1], C_WARN[2], C_WARN[3])
            else
                tr.name.value:SetTextColor(C_LABEL[1], C_LABEL[2], C_LABEL[3])
            end
            -- Bonus text
            local bonusParts = {}
            for _, b in ipairs(ts.bonuses) do
                if b.active then
                    table.insert(bonusParts, "|cff66ff66(" .. b.threshold .. ")|r " .. b.text)
                else
                    table.insert(bonusParts, "|cff666666(" .. b.threshold .. ")|r " .. b.text)
                end
            end
            if #bonusParts > 0 then
                tr.bonus.label:SetText(table.concat(bonusParts, "\n"))
            else
                tr.bonus.label:SetText("")
            end
        end
    else
        widgets.tierVisible = false
        widgets.tierCount = 0
    end

    -- Primary stats
    for _, def in ipairs(Data.PRIMARY_STAT_KEYS) do
        local row = widgets.primaryRows[def.key]
        local v = primary[def.key]
        if v and v > 0 then
            row.value:SetText(Fmt(v))
            row.isHidden = false
        else
            row.isHidden = true
        end
    end

    -- Secondary stats (rating + estimated %)
    for _, def in ipairs(Data.SECONDARY_STAT_KEYS) do
        local row = widgets.secondaryRows[def.key]
        local v = secondary[def.key]
        if v and v > 0 then
            local pctStr = Data.EstimatePercent(row.cr, v)
            if pctStr then
                row.value:SetText("(" .. pctStr .. ") " .. Fmt(v))
            else
                row.value:SetText(Fmt(v))
            end
            row.tooltipTitle = def.label
            row.tooltipBody  = string.format("Rating: %s%s",
                Fmt(v), pctStr and ("\nEstimated: " .. pctStr) or "")
            row.isHidden = false
        else
            row.isHidden = true
        end
    end

    -- Talent comparison
    if not ns.db.showTalentCompare then
        widgets.talentVisible = false
    else
        local result, reason = ComputeTalentDiff(unit)
        if not result then
            if reason == "class" or reason == "spec" then
                widgets.talentVisible = false
            else
                widgets.talentVisible = true
                widgets.talentSummary:SetText(reason == "api"
                    and "Talent API unavailable" or "Not available")
                widgets.talentSummary:SetTextColor(C_NA[1], C_NA[2], C_NA[3])
                for i = 1, MAX_DIFF_ROWS do widgets.diffRows[i]:Hide() end
                widgets.talentOverflow:Hide()
            end
        else
            widgets.talentVisible = true
            local pct = result.total > 0
                and math.floor(result.matching / result.total * 100) or 0
            widgets.talentSummary:SetText(
                string.format("%d/%d match (%d%%)", result.matching, result.total, pct))
            if pct == 100 then
                widgets.talentSummary:SetTextColor(C_GOOD[1], C_GOOD[2], C_GOOD[3])
            elseif pct >= 80 then
                widgets.talentSummary:SetTextColor(C_WARN[1], C_WARN[2], C_WARN[3])
            else
                widgets.talentSummary:SetTextColor(C_BAD[1], C_BAD[2], C_BAD[3])
            end

            local maxShow = math.min(#result.diffs, MAX_DIFF_ROWS)
            for i = 1, MAX_DIFF_ROWS do
                if i <= maxShow then
                    local d = result.diffs[i]
                    local pName = d.yourRank > 0  and (d.yours  or "?") or "not taken"
                    local iName = d.theirRank > 0 and (d.theirs or "?") or "not taken"
                    widgets.diffRows[i]:SetText(
                        string.format("|cff%s%s|r  >  |cff%s%s|r",
                            CLR_YOU, pName, CLR_THEM, iName))
                    widgets.diffRows[i]:Show()
                else
                    widgets.diffRows[i]:Hide()
                end
            end

            if #result.diffs > MAX_DIFF_ROWS then
                widgets.talentOverflow:SetText(
                    "... and " .. (#result.diffs - MAX_DIFF_ROWS) .. " more")
                widgets.talentOverflow:Show()
            else
                widgets.talentOverflow:Hide()
            end
        end
    end

    -- Layout everything
    widgets.layoutFunc()
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
