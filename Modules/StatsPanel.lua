-- Djinni's Character Frame — StatsPanel
-- Comprehensive stats panel replacing Blizzard's CharacterStatsPane.
-- Visual style matched to ChonkyCharacterSheet: SquareMask gradients,
-- CCS section colours, scrollable with collapsible headers.
local addonName, ns = ...

local mod = {}
ns:RegisterModule("StatsPanel", mod)

local Data = ns.Data

---------------------------------------------------------------------------
-- Layout constants (CCS reference: Width=222, Height=23, yOffset=3.5)
---------------------------------------------------------------------------

local ROW_H       = 14
local HDR_H       = 20
local ILVL_H      = 24
local PAD_Y       = 3.5
local MASK_TEX    = "Interface\\Masks\\SquareMask.BLP"

---------------------------------------------------------------------------
-- Section colours (CCS exact defaults)
---------------------------------------------------------------------------

local SECTION_COLORS = {
    ATTRIBUTES = { r = 0.64, g = 0.47, b = 0.10, a = 0.4 },
    SECONDARY  = { r = 0.16, g = 0.34, b = 0.08, a = 0.4 },
    ATTACK     = { r = 0.41, g = 0.00, b = 0.00, a = 0.4 },
    DEFENSE    = { r = 0.00, g = 0.13, b = 0.38, a = 0.4 },
    GENERAL    = { r = 0.45, g = 0.45, b = 0.45, a = 0.4 },
}

---------------------------------------------------------------------------
-- Panel + widget state
---------------------------------------------------------------------------

local panel          = nil
local scrollFrame    = nil
local scrollChild    = nil
local sections       = {}
local allRows        = {}
local updateThrottle = nil
local ilvlRow        = nil

---------------------------------------------------------------------------
-- Row creation helpers — CCS style
---------------------------------------------------------------------------

local function CreateHeaderRow(parent, sectionKey, title, color)
    local f = CreateFrame("Button", "DCFStatHdr_" .. sectionKey, parent)
    f:SetHeight(HDR_H)

    -- CCS headers: gradient from dark/transparent(left) to colored(right)
    local bg = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    bg:SetAllPoints()
    bg:SetTexture(MASK_TEX)
    bg:SetGradient("HORIZONTAL",
        CreateColor(0, 0, 0, color.a * 0.5),
        CreateColor(color.r, color.g, color.b, color.a))

    -- Centered title text (CCS style)
    local txt = f:CreateFontString(nil, "OVERLAY")
    txt:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    txt:SetPoint("CENTER", f, "CENTER", 0, 0)
    txt:SetTextColor(1, 1, 1, 1)
    txt:SetText(title)
    f.title = txt

    -- Collapse state
    f.isCollapsed = false
    f.sectionKey = sectionKey

    f:SetScript("OnClick", function()
        f.isCollapsed = not f.isCollapsed
        mod:LayoutRows()
    end)

    -- Subtle highlight on hover
    local hl = f:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.06)

    return f
end

local function CreateStatRow(parent, key, color)
    local f = CreateFrame("Frame", "DCFStatRow_" .. key, parent)
    f:SetHeight(ROW_H)
    f:EnableMouse(true)

    -- CCS stat rows: gradient from colored(left) to dark/transparent(right)
    local bg = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    bg:SetAllPoints()
    bg:SetTexture(MASK_TEX)
    bg:SetGradient("HORIZONTAL",
        CreateColor(color.r, color.g, color.b, color.a),
        CreateColor(0, 0, 0, color.a * 0.5))
    f.bg = bg

    -- Left text (stat name)
    local lbl = f:CreateFontString(nil, "OVERLAY")
    lbl:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    lbl:SetPoint("LEFT", f, "LEFT", 2, 0)
    lbl:SetJustifyH("LEFT")
    lbl:SetTextColor(1, 1, 1, 1)
    f.label = lbl

    -- Right text (stat value)
    local val = f:CreateFontString(nil, "OVERLAY")
    val:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    val:SetPoint("RIGHT", f, "RIGHT", -2, 0)
    val:SetJustifyH("RIGHT")
    val:SetTextColor(1, 1, 1, 1)
    f.value = val

    -- Hover highlight
    local hl = f:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.06)

    -- Tooltip support
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

    f.rowKey = key
    return f
end

---------------------------------------------------------------------------
-- Section + row definitions
---------------------------------------------------------------------------

local STAT_SECTIONS = {
    {
        key = "ATTRIBUTES", title = "Attributes",
        rows = {
            { key = "primary",  label = "Primary" },
            { key = "stamina",  label = "Stamina" },
            { key = "health",   label = "Health" },
            { key = "power",    label = "Power" },
            { key = "armor",    label = "Armor" },
            { key = "gcd",      label = "GCD" },
        },
    },
    {
        key = "SECONDARY", title = "Secondary",
        rows = {
            { key = "crit",     label = "Crit" },
            { key = "haste",    label = "Haste" },
            { key = "mastery",  label = "Mastery" },
            { key = "vers",     label = "Versatility" },
        },
    },
    {
        key = "ATTACK", title = "Attack",
        rows = {
            { key = "atkpower", label = "Attack Power" },
            { key = "atkspeed", label = "Attack Speed" },
            { key = "sppower",  label = "Spell Power" },
        },
    },
    {
        key = "DEFENSE", title = "Defense",
        rows = {
            { key = "dodge",    label = "Dodge" },
            { key = "parry",    label = "Parry" },
            { key = "block",    label = "Block" },
        },
    },
    {
        key = "GENERAL", title = "General",
        rows = {
            { key = "leech",    label = "Leech" },
            { key = "avoid",    label = "Avoidance" },
            { key = "speed",    label = "Speed" },
            { key = "movespd",  label = "Move Speed" },
        },
    },
}

---------------------------------------------------------------------------
-- Build the panel
---------------------------------------------------------------------------

local PANEL_W = 200  -- default; adjusted dynamically

local function BuildPanel(parent)
    local f = CreateFrame("Frame", "DCFStatsPanel", parent)
    f:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, 0)
    f:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -18, 5)

    -- Scroll frame (CCS uses UIPanelScrollFrameTemplate)
    local sf = CreateFrame("ScrollFrame", "DCFStatsSF", f, "UIPanelScrollFrameTemplate")
    sf:SetAllPoints()

    -- Scroll child — must use explicit SetWidth (scroll children ignore anchor-based width)
    local sc = CreateFrame("Frame", "DCFStatsSC", sf)
    sc:SetWidth(PANEL_W)
    sc:SetHeight(1)
    sf:SetScrollChild(sc)

    scrollFrame = sf
    scrollChild = sc

    -- Dynamically match scroll child width to available space
    f:SetScript("OnSizeChanged", function(self, w)
        if w and w > 30 then
            local childW = w - 28  -- account for scrollbar
            sc:SetWidth(childW)
            PANEL_W = childW
        end
    end)

    -- Item Level row (CCS style: prominent, centered, dark gradient)
    local ilvl = CreateFrame("Button", "DCFStatIlvl", sc)
    ilvl:SetHeight(ILVL_H)
    local ilvlBg = ilvl:CreateTexture(nil, "BACKGROUND", nil, 1)
    ilvlBg:SetAllPoints()
    ilvlBg:SetTexture(MASK_TEX)
    ilvlBg:SetGradient("VERTICAL",
        CreateColor(0, 0, 0, 0.2),
        CreateColor(0.1, 0.1, 0.1, 0.4))
    local ilvlText = ilvl:CreateFontString(nil, "OVERLAY")
    ilvlText:SetFont("Fonts\\FRIZQT__.TTF", 16, "OUTLINE")
    ilvlText:SetPoint("CENTER", ilvl, "CENTER", 0, 0)
    ilvlText:SetTextColor(1, 1, 1, 1)
    ilvl.text = ilvlText
    ilvl.tooltipTitle = nil
    ilvl.tooltipBody = nil
    ilvl:SetScript("OnEnter", function(self)
        if self.tooltipTitle then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.tooltipTitle, 1, 0.82, 0)
            if self.tooltipBody then
                GameTooltip:AddLine(self.tooltipBody, 1, 1, 1, true)
            end
            GameTooltip:Show()
        end
    end)
    ilvl:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ilvlRow = ilvl

    -- Build section headers and stat rows
    allRows = {}
    sections = {}

    for _, secDef in ipairs(STAT_SECTIONS) do
        local color = SECTION_COLORS[secDef.key] or SECTION_COLORS.GENERAL
        local hdr = CreateHeaderRow(sc, secDef.key, secDef.title, color)

        sections[secDef.key] = { header = hdr, rows = {}, collapsed = false }
        table.insert(allRows, { type = "header", frame = hdr, section = secDef.key })

        for _, rowDef in ipairs(secDef.rows) do
            local row = CreateStatRow(sc, rowDef.key, color)
            row.label:SetText(rowDef.label)
            row.sectionKey = secDef.key
            sections[secDef.key].rows[rowDef.key] = row
            table.insert(allRows, { type = "row", frame = row, section = secDef.key, key = rowDef.key })
        end
    end

    f:Hide()
    panel = f
    return f
end

---------------------------------------------------------------------------
-- Layout: position all visible rows
---------------------------------------------------------------------------

function mod:LayoutRows()
    if not scrollChild then return end
    local w = PANEL_W
    if w < 20 then w = 200 end
    local y = -PAD_Y

    -- Item level row at top
    if ilvlRow then
        ilvlRow:ClearAllPoints()
        ilvlRow:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, y)
        ilvlRow:SetSize(w, ILVL_H)
        ilvlRow:Show()
        y = y - ILVL_H - PAD_Y
    end

    for _, entry in ipairs(allRows) do
        if entry.type == "header" then
            local sec = sections[entry.section]
            entry.frame:ClearAllPoints()
            entry.frame:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, y)
            entry.frame:SetSize(w, HDR_H)
            entry.frame:Show()
            sec.collapsed = entry.frame.isCollapsed
            y = y - HDR_H - PAD_Y
        elseif entry.type == "row" then
            local sec = sections[entry.section]
            if sec.collapsed or entry.frame.isHidden then
                entry.frame:Hide()
            else
                entry.frame:ClearAllPoints()
                entry.frame:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, y)
                entry.frame:SetSize(w, ROW_H)
                entry.frame:Show()
                y = y - ROW_H - PAD_Y
            end
        end
    end

    scrollChild:SetHeight(math.abs(y) + PAD_Y)

    -- Hide scrollbar if not needed
    if scrollFrame and scrollFrame.GetVerticalScrollRange then
        local bar = _G["DCFStatsSFScrollBar"]
        if bar then
            if scrollFrame:GetVerticalScrollRange() > 0 then
                bar:Show()
            else
                bar:Hide()
            end
        end
    end
end

---------------------------------------------------------------------------
-- Formatting helpers
---------------------------------------------------------------------------

local function Fmt(n)
    if BreakUpLargeNumbers then
        local ok, result = pcall(BreakUpLargeNumbers, n)
        if ok and result then return result end
    end
    return tostring(n or 0)
end

local function PctFmt(n)
    return string.format("%.2f%%", n or 0)
end

local function RatingPctFmt(rating, pct)
    if rating and rating > 0 then
        return string.format("%s | %s", Fmt(rating), PctFmt(pct))
    end
    return PctFmt(pct)
end

local function BuildDRTooltip(drInfo)
    if not drInfo or drInfo.rawRating <= 0 then return nil end
    local lines = {}
    table.insert(lines, string.format(
        "Rating: %s  |  Raw: %s",
        Fmt(drInfo.rawRating), PctFmt(drInfo.rawPercent)))
    table.insert(lines, string.format(
        "|cff68ccefEffective: %s  (+%s)|r",
        Fmt(drInfo.effectiveRating), PctFmt(drInfo.effectivePercent)))
    if drInfo.percentLost > 0.01 then
        table.insert(lines, string.format(
            "|cffff5555Lost: %s  (+%s)|r",
            Fmt(drInfo.ratingLost), PctFmt(drInfo.percentLost)))
    end
    table.insert(lines, string.format(
        "|cff9d9d9dBracket: %s – %s|r",
        PctFmt(drInfo.bracketStart), PctFmt(drInfo.bracketEnd)))
    return table.concat(lines, "\n")
end

---------------------------------------------------------------------------
-- Stat update
---------------------------------------------------------------------------

local function SetRow(key, label, value, ttTitle, ttBody, hidden)
    for _, sec in pairs(sections) do
        local row = sec.rows[key]
        if row then
            if label then row.label:SetText(label) end
            if value then row.value:SetText(value) end
            row.tooltipTitle = ttTitle
            row.tooltipBody  = ttBody
            row.isHidden = hidden or false
            return row
        end
    end
end

local function DoUpdate()
    updateThrottle = nil
    if not panel then return end
    if not ns.addon:IsEnabled() then panel:Hide(); return end
    if not ns.db.showStatsPanel then panel:Hide(); return end

    local unit = "player"

    -- ── Item Level (CCS-style prominent display) ────────────────────────
    if ilvlRow then
        local avgItemLevel, avgItemLevelEquipped = GetAverageItemLevel()
        local eqText = string.format("%.1f", avgItemLevelEquipped or 0)
        local bagText = string.format("%.1f", avgItemLevel or 0)
        -- Color by average equipped rarity (approximate via quality color)
        local colorHex = "a335ee" -- default epic purple
        ilvlRow.text:SetText(string.format("|cFF%s%s / %s|r", colorHex, eqText, bagText))
        ilvlRow.tooltipTitle = "Item Level"
        ilvlRow.tooltipBody = string.format(
            "Equipped: %s\nOverall: %s",
            eqText, bagText)
    end

    -- ── Attributes ──────────────────────────────────────────────────────

    local primaryLabel, primaryVal = "Primary", 0
    local primaryIndices = { {1, "Strength"}, {2, "Agility"}, {4, "Intellect"} }
    for _, info in ipairs(primaryIndices) do
        local _, val = UnitStat(unit, info[1])
        if val and val > primaryVal then
            primaryVal = val
            primaryLabel = info[2]
        end
    end
    SetRow("primary", primaryLabel, Fmt(primaryVal),
        primaryLabel, string.format("Your primary stat: %s", Fmt(primaryVal)))

    local _, stamVal = UnitStat(unit, 3)
    SetRow("stamina", "Stamina", Fmt(stamVal or 0),
        "Stamina", string.format("Increases health pool.\nStamina: %s", Fmt(stamVal or 0)))

    local health = UnitHealthMax(unit) or 0
    SetRow("health", "Health", Fmt(health),
        "Health", string.format("Maximum health: %s", Fmt(health)))

    local powerType = UnitPowerType(unit)
    local power = UnitPowerMax(unit) or 0
    local powerNames = { [0] = "Mana", [1] = "Rage", [2] = "Focus",
        [3] = "Energy", [4] = "Combo Points", [5] = "Runes",
        [6] = "Runic Power", [8] = "Lunar Power", [11] = "Maelstrom",
        [12] = "Chi", [13] = "Insanity", [17] = "Fury", [18] = "Pain" }
    local powerName = powerNames[powerType] or "Power"
    local hidePower = (power == 0)
    SetRow("power", powerName, Fmt(power),
        powerName, string.format("Maximum %s: %s", powerName, Fmt(power)), hidePower)

    local _, armor = UnitArmor(unit)
    SetRow("armor", "Armor", Fmt(armor or 0),
        "Armor", string.format("Armor: %s\nReduces physical damage taken.", Fmt(armor or 0)))

    local hasteVal = GetHaste and GetHaste() or 0
    local gcd = math.max(0.75, 1.5 * 100 / (100 + hasteVal))
    local _, class = UnitClass(unit)
    if class == "ROGUE" or class == "MONK" then
        gcd = 1.0
    elseif class == "DRUID" then
        if GetShapeshiftFormID and GetShapeshiftFormID() == 1 then gcd = 1.0 end
    end
    SetRow("gcd", "GCD", string.format("%.2fs", gcd),
        "Global Cooldown", string.format("%.2f seconds\nReduced by Haste.", gcd))

    -- ── Secondary ───────────────────────────────────────────────────────

    local critRating = GetCombatRating(CR_CRIT_SPELL) or 0
    local critPct    = GetSpellCritChance and GetSpellCritChance() or 0
    local critDR     = Data.GetStatDRInfo(CR_CRIT_SPELL)
    SetRow("crit", "Crit", RatingPctFmt(critRating, critPct),
        "Critical Strike", BuildDRTooltip(critDR))

    local hasteRating = GetCombatRating(CR_HASTE_SPELL) or 0
    local hastePct    = UnitSpellHaste and UnitSpellHaste(unit) or 0
    local hasteDR     = Data.GetStatDRInfo(CR_HASTE_SPELL)
    SetRow("haste", "Haste", RatingPctFmt(hasteRating, hastePct),
        "Haste", BuildDRTooltip(hasteDR))

    local masteryRating = GetCombatRating(CR_MASTERY) or 0
    local masteryPct    = GetMasteryEffect and GetMasteryEffect() or 0
    local masteryDR     = Data.GetStatDRInfo(CR_MASTERY)
    SetRow("mastery", "Mastery", RatingPctFmt(masteryRating, masteryPct),
        "Mastery", BuildDRTooltip(masteryDR))

    local versRating = GetCombatRating(CR_VERSATILITY_DAMAGE_DONE) or 0
    local versDone   = (GetCombatRatingBonus(CR_VERSATILITY_DAMAGE_DONE) or 0)
                     + ((GetVersatilityBonus and GetVersatilityBonus(CR_VERSATILITY_DAMAGE_DONE)) or 0)
    local versTaken  = (GetCombatRatingBonus(CR_VERSATILITY_DAMAGE_TAKEN) or 0)
                     + ((GetVersatilityBonus and GetVersatilityBonus(CR_VERSATILITY_DAMAGE_TAKEN)) or 0)
    local versDisplay = string.format("%s | %s / %s",
        Fmt(versRating), PctFmt(versDone), PctFmt(versTaken))
    local versDR = Data.GetStatDRInfo(CR_VERSATILITY_DAMAGE_DONE)
    local versTooltip = string.format(
        "Damage/Healing: +%s\nDamage Reduction: +%s\nRating: %s",
        PctFmt(versDone), PctFmt(versTaken), Fmt(versRating))
    if versDR and versDR.rawRating > 0 then
        versTooltip = versTooltip .. "\n\n" .. (BuildDRTooltip(versDR) or "")
    end
    SetRow("vers", "Versatility", versDisplay,
        "Versatility", versTooltip)

    -- ── Attack ──────────────────────────────────────────────────────────

    local apBase, apPos, apNeg = UnitAttackPower(unit)
    local ap = (apBase or 0) + (apPos or 0) + (apNeg or 0)
    SetRow("atkpower", "Attack Power", Fmt(ap),
        "Attack Power", string.format("Attack Power: %s", Fmt(ap)))

    local mainSpeed, offSpeed = UnitAttackSpeed(unit)
    local spdText = mainSpeed and string.format("%.2f", mainSpeed) or "—"
    if offSpeed and offSpeed > 0 then
        spdText = spdText .. " / " .. string.format("%.2f", offSpeed)
    end
    SetRow("atkspeed", "Attack Speed", spdText,
        "Attack Speed", mainSpeed and string.format("Main Hand: %.2fs%s",
            mainSpeed, offSpeed and string.format("\nOff Hand: %.2fs", offSpeed) or "") or nil)

    local sp = GetSpellBonusDamage and GetSpellBonusDamage(2) or 0
    SetRow("sppower", "Spell Power", Fmt(sp),
        "Spell Power", string.format("Spell Power: %s", Fmt(sp)))

    -- ── Defense ─────────────────────────────────────────────────────────

    local dodge = GetDodgeChance and GetDodgeChance() or 0
    SetRow("dodge", "Dodge", PctFmt(dodge),
        "Dodge", string.format("Dodge Chance: %s", PctFmt(dodge)))

    local parry = GetParryChance and GetParryChance() or 0
    SetRow("parry", "Parry", PctFmt(parry),
        "Parry", string.format("Parry Chance: %s", PctFmt(parry)))

    local block = GetBlockChance and GetBlockChance() or 0
    local hideBlock = (block == 0)
    SetRow("block", "Block", PctFmt(block),
        "Block", string.format("Block Chance: %s", PctFmt(block)), hideBlock)

    -- ── General ─────────────────────────────────────────────────────────

    local leech = GetCombatRatingBonus(CR_LIFESTEAL) or 0
    local leechRating = GetCombatRating(CR_LIFESTEAL) or 0
    SetRow("leech", "Leech",
        leechRating > 0 and RatingPctFmt(leechRating, leech) or PctFmt(leech),
        "Leech", string.format("Leech: %s\nHeals you for this %% of damage dealt.", PctFmt(leech)))

    local avoid = GetCombatRatingBonus(CR_AVOIDANCE) or 0
    local avoidRating = GetCombatRating(CR_AVOIDANCE) or 0
    SetRow("avoid", "Avoidance",
        avoidRating > 0 and RatingPctFmt(avoidRating, avoid) or PctFmt(avoid),
        "Avoidance", string.format("Avoidance: %s\nReduces AoE damage taken.", PctFmt(avoid)))

    local speedRating = GetCombatRating(CR_SPEED) or 0
    local speedPct = GetCombatRatingBonus(CR_SPEED) or 0
    SetRow("speed", "Speed",
        speedRating > 0 and RatingPctFmt(speedRating, speedPct) or PctFmt(speedPct),
        "Speed", string.format("Speed: %s\nIncreases movement speed.", PctFmt(speedPct)))

    local moveSpd = GetUnitSpeed and GetUnitSpeed(unit) or 0
    local movePct = (moveSpd / 7) * 100
    SetRow("movespd", "Move Speed", string.format("%d%%", movePct),
        "Movement Speed", string.format("Current: %d%%\n%.1f yards/sec", movePct, moveSpd))

    -- Invalidate rating ratio cache for inspect panel
    if Data.InvalidateRatingCache then Data.InvalidateRatingCache() end

    mod:LayoutRows()
    panel:Show()
end

function mod:Update()
    if updateThrottle then return end
    updateThrottle = C_Timer.After(0.15, DoUpdate)
end

---------------------------------------------------------------------------
-- Public: show/hide
---------------------------------------------------------------------------

function mod:SetShown(state)
    if panel then
        if state and ns.addon:IsEnabled() and ns.db.showStatsPanel then
            if mod.HideBlizzardStats then mod.HideBlizzardStats() end
            mod:Update()
        else
            panel:Hide()
            if mod.RestoreBlizzardStats then mod.RestoreBlizzardStats() end
        end
    end
end

---------------------------------------------------------------------------
-- Init
---------------------------------------------------------------------------

function mod:Init()
    ns:OnBlizzardAddonLoaded("Blizzard_UIPanels_Game", function()
        local pane = _G.CharacterStatsPane
        if not pane then
            print("|cffff4444DCF StatsPanel: CharacterStatsPane not found|r")
            return
        end

        -- Store Blizzard hide/restore as module methods so Core can call them
        function mod.HideBlizzardStats()
            if pane.ItemLevelCategory then
                pane.ItemLevelCategory:ClearAllPoints()
                pane.ItemLevelCategory:SetPoint("TOP", pane, "TOP", 0, -7000)
            end
            if pane.ClassBackground then
                pane.ClassBackground:SetAlpha(0)
            end
            for _, child in pairs({ pane:GetChildren() }) do
                if child ~= panel and child.Hide then
                    child:Hide()
                end
            end
            pane:UnregisterAllEvents()
        end

        function mod.RestoreBlizzardStats()
            if pane.ItemLevelCategory then
                pane.ItemLevelCategory:ClearAllPoints()
                pane.ItemLevelCategory:SetPoint("TOP", pane, "TOP", -3, 2)
            end
            if pane.ClassBackground then
                pane.ClassBackground:SetAlpha(1)
            end
            for _, child in pairs({ pane:GetChildren() }) do
                if child ~= panel and child.Show then
                    child:Show()
                end
            end
            pcall(function()
                pane:RegisterUnitEvent("UNIT_STATS", "player")
                pane:RegisterUnitEvent("UNIT_RESISTANCES", "player")
                pane:RegisterUnitEvent("UNIT_ATTACK_POWER", "player")
                pane:RegisterUnitEvent("UNIT_RANGED_ATTACK_POWER", "player")
                pane:RegisterUnitEvent("UNIT_DAMAGE", "player")
                pane:RegisterUnitEvent("UNIT_ATTACK_SPEED", "player")
                pane:RegisterUnitEvent("UNIT_MAXHEALTH", "player")
                pane:RegisterUnitEvent("UNIT_AURA", "player")
                pane:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
                pane:RegisterEvent("PLAYER_LEVEL_UP")
                pane:RegisterEvent("PLAYER_ENTERING_WORLD")
                pane:RegisterEvent("COMBAT_RATING_UPDATE")
                pane:RegisterEvent("MASTERY_UPDATE")
                pane:RegisterEvent("SPEED_UPDATE")
                pane:RegisterEvent("LIFESTEAL_UPDATE")
                pane:RegisterEvent("AVOIDANCE_UPDATE")
                pane:RegisterEvent("PLAYER_TALENT_UPDATE")
                pane:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
                pane:RegisterEvent("PLAYER_DAMAGE_DONE_MODS")
                pane:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
            end)
            -- Force Blizzard to update its stats display
            if type(PaperDollFrame_UpdateStats) == "function" then
                pcall(PaperDollFrame_UpdateStats)
            end
        end

        panel = BuildPanel(pane)

        if ns.db.showStatsPanel and ns.addon:IsEnabled() then
            mod.HideBlizzardStats()
            mod:Update()
        end

        -- Hook Blizzard's update path
        if type(PaperDollFrame_UpdateStats) == "function" then
            hooksecurefunc("PaperDollFrame_UpdateStats", function()
                if ns.db.showStatsPanel and ns.addon:IsEnabled() then
                    mod.HideBlizzardStats()
                    mod:Update()
                end
            end)
        end

        -- Re-hide Blizzard stats each time character frame opens
        local charFrame = _G.CharacterFrame
        if charFrame then
            charFrame:HookScript("OnShow", function()
                if ns.db.showStatsPanel and ns.addon:IsEnabled() then
                    C_Timer.After(0.05, function()
                        mod.HideBlizzardStats()
                        mod:Update()
                    end)
                end
            end)
        end
    end)

    -- Events that trigger stat refresh
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("UNIT_STATS")
    eventFrame:RegisterEvent("CHARACTER_POINTS_CHANGED")
    eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    eventFrame:RegisterEvent("UNIT_MAXHEALTH")
    eventFrame:RegisterEvent("UNIT_AURA")
    eventFrame:RegisterEvent("COMBAT_RATING_UPDATE")
    eventFrame:RegisterEvent("MASTERY_UPDATE")
    eventFrame:RegisterEvent("SPEED_UPDATE")
    eventFrame:RegisterEvent("LIFESTEAL_UPDATE")
    eventFrame:RegisterEvent("AVOIDANCE_UPDATE")
    eventFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
    eventFrame:RegisterEvent("PLAYER_DAMAGE_DONE_MODS")
    eventFrame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
    eventFrame:RegisterEvent("UNIT_POWER_UPDATE")
    eventFrame:SetScript("OnEvent", function(_, event, unit)
        if unit and unit ~= "player" then return end
        mod:Update()
    end)
end
