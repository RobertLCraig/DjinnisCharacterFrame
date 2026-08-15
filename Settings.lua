-- Djinni's Character Frame — Settings
-- Blizzard Interface Options integration.
local addonName, ns = ...
local DCF = ns.addon

---------------------------------------------------------------------------
-- Refresh helper — forces all character-frame modules to re-draw
-- so that toggling a setting is visible immediately.
---------------------------------------------------------------------------

local function RefreshCharacter()
    local slotMod = ns.modules.SlotOverlay
    if slotMod and slotMod.UpdateCharacter then
        slotMod:UpdateCharacter()
    end
    local specMod = ns.modules.SpecDisplay
    if specMod and specMod.SetVisible then
        specMod:SetVisible(DCF:IsEnabled() and ns.db.showSpecDisplay)
    end
    local statsMod = ns.modules.StatsPanel
    if statsMod and statsMod.Update then
        statsMod:Update()
    end
end

---------------------------------------------------------------------------
-- Widget helpers (minimal, self-contained)
---------------------------------------------------------------------------

local function AddCheckbox(parent, y, label, getter, setter, refreshList)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, y)
    local text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    text:SetText(label)
    cb:SetChecked(getter())
    cb:SetScript("OnClick", function(self)
        setter(self:GetChecked())
        RefreshCharacter()
    end)
    if refreshList then
        table.insert(refreshList, function() cb:SetChecked(getter()) end)
    end
    return y - 26
end

local function AddSectionHeader(parent, y, text)
    local hdr = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    hdr:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, y - 6)
    hdr:SetText(text)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetPoint("LEFT", hdr, "RIGHT", 8, 0)
    line:SetPoint("RIGHT", parent, "RIGHT", -18, 0)
    line:SetHeight(1)
    line:SetColorTexture(0.5, 0.5, 0.5, 0.3)
    return y - 30
end

local function CreateScrollPanel()
    local panel = CreateFrame("Frame")
    panel:Hide()
    local scroll = CreateFrame("ScrollFrame", nil, panel, "ScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -5)
    scroll:SetPoint("BOTTOMRIGHT", -24, 5)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetWidth(560)
    scroll:SetScrollChild(content)
    content:SetHeight(600)
    panel.content = content
    panel:SetScript("OnSizeChanged", function(self, w)
        content:SetWidth(math.max(w - 30, 400))
    end)
    return panel
end

---------------------------------------------------------------------------
-- Settings registration
---------------------------------------------------------------------------

function DCF:SetupOptions()
    local panel  = CreateScrollPanel()
    local c      = panel.content
    local r      = {}   -- refresh callbacks
    local y      = -10

    y = AddSectionHeader(c, y, "Item Level")
    y = AddCheckbox(c, y, "Show item level on each slot",
        function() return ns.db.showIlvl end,
        function(v) ns.db.showIlvl = v end, r)

    y = AddSectionHeader(c, y, "Enchants")
    y = AddCheckbox(c, y, "Show enchant name on enchanted slots",
        function() return ns.db.showEnchants end,
        function(v) ns.db.showEnchants = v end, r)
    y = AddCheckbox(c, y, "Show missing-enchant warning (!)",
        function() return ns.db.showMissingEnchant end,
        function(v) ns.db.showMissingEnchant = v end, r)

    y = AddSectionHeader(c, y, "Gems")
    y = AddCheckbox(c, y, "Show gem count on socketed slots (e.g. 2/3)",
        function() return ns.db.showGems end,
        function(v) ns.db.showGems = v end, r)
    y = AddCheckbox(c, y, "Highlight missing gems in orange",
        function() return ns.db.showMissingGem end,
        function(v) ns.db.showMissingGem = v end, r)

    -- Gem Socket modifier key
    do
        local lbl = c:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        lbl:SetPoint("TOPLEFT", c, "TOPLEFT", 18, y - 4)
        lbl:SetText("Gem socket shortcut:")

        local MODIFIERS = { "alt", "ctrl", "shift" }
        local LABELS    = { alt = "Alt + Right-click", ctrl = "Ctrl + Right-click", shift = "Shift + Right-click" }

        local modBtn = CreateFrame("Button", nil, c)
        modBtn:SetSize(160, 20)
        modBtn:SetPoint("LEFT", lbl, "RIGHT", 8, 0)

        local modBg = modBtn:CreateTexture(nil, "BACKGROUND")
        modBg:SetAllPoints()
        modBg:SetColorTexture(0.15, 0.15, 0.15, 0.8)

        local modText = modBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        modText:SetAllPoints()
        modText:SetJustifyH("CENTER")
        local function UpdateModText()
            modText:SetText(LABELS[ns.db.gemSocketModifier or "alt"] or "Alt + Right-click")
        end
        UpdateModText()

        modBtn:SetScript("OnClick", function()
            local cur = ns.db.gemSocketModifier or "alt"
            for i, m in ipairs(MODIFIERS) do
                if m == cur then
                    ns.db.gemSocketModifier = MODIFIERS[(i % #MODIFIERS) + 1]
                    UpdateModText()
                    return
                end
            end
            ns.db.gemSocketModifier = "alt"
            UpdateModText()
        end)

        modBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
            GameTooltip:SetText("Gem Socket Shortcut")
            GameTooltip:AddLine("Click to cycle: Alt / Ctrl / Shift", 0.8, 0.8, 0.8)
            GameTooltip:AddLine("Use this modifier + Right-click on a slot to open the gem socket panel.", 0.6, 0.6, 0.6, true)
            GameTooltip:Show()
        end)
        modBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

        local hl = modBtn:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.08)

        if r then
            table.insert(r, UpdateModText)
        end

        y = y - 28
    end

    y = AddSectionHeader(c, y, "Spec Display")
    y = AddCheckbox(c, y, "Show specialisation badge on Character frame",
        function() return ns.db.showSpecDisplay end,
        function(v) ns.db.showSpecDisplay = v end, r)

    y = AddSectionHeader(c, y, "Stats Panel")
    y = AddCheckbox(c, y, "Show enhanced stats panel on Character frame",
        function() return ns.db.showStatsPanel end,
        function(v)
            ns.db.showStatsPanel = v
            local statsMod = ns.modules.StatsPanel
            if statsMod and statsMod.SetShown then
                statsMod:SetShown(v)
            end
        end, r)

    y = AddSectionHeader(c, y, "Talent Comparison")
    y = AddCheckbox(c, y, "Compare talents when inspecting same spec",
        function() return ns.db.showTalentCompare end,
        function(v) ns.db.showTalentCompare = v end, r)

    -- Version label (bottom-right of content area)
    local getMetadata = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
    local version = getMetadata and getMetadata(addonName, "Version") or "?"
    local verLabel = c:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    verLabel:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -14, 10)
    verLabel:SetTextColor(0.5, 0.5, 0.5)
    verLabel:SetText("v" .. version)

    panel:SetScript("OnShow", function()
        for _, cb in ipairs(r) do cb() end
    end)

    local cat = Settings.RegisterCanvasLayoutCategory(panel, "Djinni's Character Frame")
    Settings.RegisterAddOnCategory(cat)
    self.settingsCategoryID = cat:GetID()
end

function DCF:OpenSettings()
    if self.settingsCategoryID then
        Settings.OpenToCategory(self.settingsCategoryID)
    end
end
