-- Djinni's Character Frame — SpecDisplay
-- Adds a spec icon + name + role badge to the Character frame (self view).
-- The Inspect frame already shows spec name via InspectLevelText; we add
-- a role icon to complement it.
local addonName, ns = ...

local mod = {}
ns:RegisterModule("SpecDisplay", mod)

---------------------------------------------------------------------------
-- Spec badge frame (character frame)
-- Positioned just below the character model, above the stat pane divider.
---------------------------------------------------------------------------

local charBadge = nil

local ROLE_COLORS = {
    TANK    = { 0.2, 0.6, 1.0 },
    HEALER  = { 0.2, 0.9, 0.4 },
    DAMAGER = { 1.0, 0.4, 0.3 },
}

local ROLE_LABELS = {
    TANK    = "Tank",
    HEALER  = "Healer",
    DAMAGER = "DPS",
}

local function CreateBadge(parent, xOff, yOff)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(150, 20)
    f:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", xOff, yOff)

    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(16, 16)
    f.icon:SetPoint("LEFT", 0, 0)
    f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    f.label = f:CreateFontString(nil, "OVERLAY")
    f.label:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    f.label:SetPoint("LEFT", f.icon, "RIGHT", 4, 0)
    f.label:SetJustifyH("LEFT")
    f.label:SetTextColor(1, 1, 1, 0.9)

    f.role = f:CreateFontString(nil, "OVERLAY")
    f.role:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    f.role:SetPoint("LEFT", f.label, "RIGHT", 6, 0)
    f.role:SetJustifyH("LEFT")

    f:Hide()
    return f
end

local function UpdateBadge(badge, specID, sex)
    if not badge then return end
    if not ns.db.showSpecDisplay then badge:Hide(); return end
    if not specID or specID == 0 then badge:Hide(); return end

    local _, specName, _, iconID, _, role = GetSpecializationInfoByID(specID, sex)
    if not specName or specName == "" then badge:Hide(); return end

    badge.icon:SetTexture(iconID)
    badge.label:SetText(specName)

    local roleLabel = ROLE_LABELS[role] or role or ""
    local rc = ROLE_COLORS[role] or { 0.8, 0.8, 0.8 }
    badge.role:SetText(roleLabel)
    badge.role:SetTextColor(rc[1], rc[2], rc[3], 0.9)

    badge:Show()
end

---------------------------------------------------------------------------
-- Character frame badge
---------------------------------------------------------------------------

local function UpdateCharBadge()
    if not charBadge then return end
    if not ns.db.showSpecDisplay then charBadge:Hide(); return end

    local specIndex = GetSpecialization()
    if not specIndex then charBadge:Hide(); return end

    local specID = select(1, GetSpecializationInfo(specIndex))
    local sex    = UnitSex("player")
    UpdateBadge(charBadge, specID, sex)
end

---------------------------------------------------------------------------
-- Inspect frame role icon
-- We hook into InspectPaperDollFrame_SetLevel which already sets the level
-- text. We add a small role icon beside InspectLevelText.
---------------------------------------------------------------------------

local inspectRoleIcon = nil

local function UpdateInspectRole()
    if not inspectRoleIcon then return end
    if not ns.db.showSpecDisplay then inspectRoleIcon:Hide(); return end
    if not InspectFrame or not InspectFrame.unit then inspectRoleIcon:Hide(); return end

    local unit  = InspectFrame.unit
    local specID = GetInspectSpecialization(unit)
    if not specID or specID == 0 then inspectRoleIcon:Hide(); return end

    local sex = UnitSex(unit)
    local _, _, _, iconID, _, role = GetSpecializationInfoByID(specID, sex)
    if not iconID then inspectRoleIcon:Hide(); return end

    inspectRoleIcon:SetTexture(iconID)
    local rc = ROLE_COLORS[role] or { 0.8, 0.8, 0.8 }
    inspectRoleIcon:SetVertexColor(rc[1], rc[2], rc[3], 1)
    inspectRoleIcon:Show()
end

---------------------------------------------------------------------------
-- Init
---------------------------------------------------------------------------

function mod:Init()
    ns:OnBlizzardAddonLoaded("Blizzard_UIPanels_Game", function()
        -- Attach badge below the 3D model on the character frame left panel.
        -- CharacterModelScene sits in the upper-left of CharacterFrame.
        local parent = _G.CharacterModelScene or _G.CharacterFrame
        if parent then
            charBadge = CreateBadge(parent, 6, 4)
            UpdateCharBadge()
        end

        hooksecurefunc("PaperDollFrame_UpdateSidebarTabs", function()
            UpdateCharBadge()
        end)

        local specFrame = CreateFrame("Frame")
        specFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
        specFrame:SetScript("OnEvent", function()
            UpdateCharBadge()
        end)
    end)

    ns:OnBlizzardAddonLoaded("Blizzard_InspectUI", function()
        -- Small spec icon to the right of InspectLevelText
        local anchor = _G.InspectLevelText
        if anchor then
            inspectRoleIcon = InspectFrame:CreateTexture(nil, "OVERLAY")
            inspectRoleIcon:SetSize(16, 16)
            inspectRoleIcon:SetPoint("LEFT", anchor, "RIGHT", 6, 0)
            inspectRoleIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            inspectRoleIcon:Hide()
        end

        hooksecurefunc("InspectPaperDollFrame_SetLevel", function()
            UpdateInspectRole()
        end)
    end)

    -- Update inspect role after inspect data is ready
    ns.Inspect:OnInspectReady(function()
        UpdateInspectRole()
    end)
end
