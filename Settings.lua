-- Djinni's Character Frame — Settings
-- Blizzard Interface Options integration.
local addonName, ns = ...
local DCF = ns.addon

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
    cb:SetScript("OnClick", function(self) setter(self:GetChecked()) end)
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
    y = AddCheckbox(c, y, "Show missing-enchant warning (red dot)",
        function() return ns.db.showMissingEnchant end,
        function(v) ns.db.showMissingEnchant = v end, r)

    y = AddSectionHeader(c, y, "Gems")
    y = AddCheckbox(c, y, "Show gem count on socketed slots (e.g. 2/3)",
        function() return ns.db.showGems end,
        function(v) ns.db.showGems = v end, r)
    y = AddCheckbox(c, y, "Highlight missing gems in orange",
        function() return ns.db.showMissingGem end,
        function(v) ns.db.showMissingGem = v end, r)

    y = AddSectionHeader(c, y, "Spec Display")
    y = AddCheckbox(c, y, "Show specialisation badge on Character frame",
        function() return ns.db.showSpecDisplay end,
        function(v) ns.db.showSpecDisplay = v end, r)

    y = AddSectionHeader(c, y, "Secondary Stats")
    y = AddCheckbox(c, y, "Show secondary stats panel (self only)",
        function() return ns.db.showStatsPanel end,
        function(v)
            ns.db.showStatsPanel = v
            local p = _G.DCFStatsPanel
            if p then p:SetShown(v) end
        end, r)

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
