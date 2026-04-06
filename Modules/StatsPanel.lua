-- Djinni's Character Frame — StatsPanel
-- Compact secondary stats panel attached to the Character frame.
-- Shows Crit / Haste / Mastery / Versatility / Speed / Leech / Avoidance
-- for the player (self only — these values aren't available for inspected targets).
local addonName, ns = ...

local mod = {}
ns:RegisterModule("StatsPanel", mod)

---------------------------------------------------------------------------
-- Stat definitions
-- CR_* constants are global in the WoW API.
---------------------------------------------------------------------------

local STATS = {
    { label = "Crit",   rating = CR_CRIT_MELEE                 },
    { label = "Haste",  rating = CR_HASTE_MELEE                },
    { label = "Mastery",rating = CR_MASTERY                    },
    { label = "Vers",   rating = CR_VERSATILITY_DAMAGE_DONE    },
    { label = "Speed",  rating = CR_SPEED                      },
    { label = "Leech",  rating = CR_LIFESTEAL                  },
    { label = "Avoid",  rating = CR_AVOIDANCE                  },
}

---------------------------------------------------------------------------
-- Panel frame
---------------------------------------------------------------------------

local panel = nil

-- Two-column layout: label on left, value on right per stat.
-- Stats are displayed in two rows of four (or similar).
local COL_W     = 90    -- width per label+value pair
local ROW_H     = 16
local PAD_X     = 8
local PAD_Y     = 6
local COLS      = 4

local statRows  = {}    -- { label, value } FontString pairs

local function CreatePanel(parent)
    local ncols = COLS
    local nrows = math.ceil(#STATS / ncols)
    local w = ncols * COL_W + PAD_X * 2
    local h = nrows * ROW_H + PAD_Y * 2 + 14   -- 14 for title

    local f = CreateFrame("Frame", "DCFStatsPanel", parent, "BackdropTemplate")
    f:SetSize(w, h)
    -- Anchor below the stats pane divider at the bottom of CharacterFrameInsetRight
    f:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", 0, -2)
    f:SetBackdrop({
        bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\ChatFrame\\ChatFrameBackground",
        tile = true, edgeSize = 1, tileSize = 8,
    })
    f:SetBackdropColor(0, 0, 0, 0.55)
    f:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.8)

    local title = f:CreateFontString(nil, "OVERLAY")
    title:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    title:SetPoint("TOPLEFT", PAD_X, -4)
    title:SetTextColor(0.8, 0.8, 0.8, 0.7)
    title:SetText("Secondary Stats")

    for i, stat in ipairs(STATS) do
        local col = (i - 1) % ncols
        local row = math.floor((i - 1) / ncols)
        local x   = PAD_X + col * COL_W
        local y   = -(14 + PAD_Y + row * ROW_H)

        local lbl = f:CreateFontString(nil, "OVERLAY")
        lbl:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
        lbl:SetPoint("TOPLEFT", f, "TOPLEFT", x, y)
        lbl:SetTextColor(0.65, 0.65, 0.65, 0.9)
        lbl:SetText(stat.label .. ":")

        local val = f:CreateFontString(nil, "OVERLAY")
        val:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
        val:SetPoint("LEFT", lbl, "RIGHT", 3, 0)
        val:SetTextColor(1, 1, 1, 0.9)
        val:SetText("0%")

        statRows[i] = { label = lbl, value = val, rating = stat.rating }
    end

    f:Hide()
    return f
end

---------------------------------------------------------------------------
-- Update
---------------------------------------------------------------------------

local updateThrottle = nil

local function DoUpdate()
    updateThrottle = nil
    if not panel then return end
    if not ns.db.showStatsPanel then panel:Hide(); return end

    for _, row in ipairs(statRows) do
        local pct = GetCombatRatingBonus(row.rating) or 0
        row.value:SetText(string.format("%.2f%%", pct))
    end
    panel:Show()
end

function mod:Update()
    if updateThrottle then return end
    updateThrottle = C_Timer.After(0.25, DoUpdate)
end

---------------------------------------------------------------------------
-- Init
---------------------------------------------------------------------------

function mod:Init()
    ns:OnBlizzardAddonLoaded("Blizzard_UIPanels_Game", function()
        -- Attach below CharacterStatsPane (the right-hand stat scroll pane)
        local anchor = _G.CharacterStatsPane or _G.CharacterFrameInsetRight
        if anchor then
            panel = CreatePanel(anchor)
            mod:Update()
        end

        hooksecurefunc("PaperDollFrame_UpdateStats", function()
            mod:Update()
        end)
    end)

    local statFrame = CreateFrame("Frame")
    statFrame:RegisterEvent("UNIT_STATS")
    statFrame:RegisterEvent("CHARACTER_POINTS_CHANGED")
    statFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    statFrame:SetScript("OnEvent", function(_, event, unit)
        if event == "UNIT_STATS" and unit ~= "player" then return end
        mod:Update()
    end)
end
