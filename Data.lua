-- Djinni's Character Frame — Data
-- Item link parsing, enchant resolution, gem helpers, gear stat computation.
local addonName, ns = ...

local Data = {}
ns.Data = Data

---------------------------------------------------------------------------
-- Slot definitions
-- Maps inventory slot ID → { frameName (character), frameName (inspect),
--   enchantable (bool) }
---------------------------------------------------------------------------

Data.SLOTS = {
    [1]  = { char = "CharacterHeadSlot",           inspect = "InspectHeadSlot",          enchantable = true  },
    [2]  = { char = "CharacterNeckSlot",            inspect = "InspectNeckSlot",          enchantable = true  },
    [3]  = { char = "CharacterShoulderSlot",        inspect = "InspectShoulderSlot",      enchantable = true  },
    [5]  = { char = "CharacterChestSlot",           inspect = "InspectChestSlot",         enchantable = true  },
    [6]  = { char = "CharacterWaistSlot",           inspect = "InspectWaistSlot",         enchantable = false },
    [7]  = { char = "CharacterLegsSlot",            inspect = "InspectLegsSlot",          enchantable = true  },
    [8]  = { char = "CharacterFeetSlot",            inspect = "InspectFeetSlot",          enchantable = true  },
    [9]  = { char = "CharacterWristSlot",           inspect = "InspectWristSlot",         enchantable = true  },
    [10] = { char = "CharacterHandsSlot",           inspect = "InspectHandsSlot",         enchantable = true  },
    [11] = { char = "CharacterFinger0Slot",         inspect = "InspectFinger0Slot",       enchantable = true  },
    [12] = { char = "CharacterFinger1Slot",         inspect = "InspectFinger1Slot",       enchantable = true  },
    [13] = { char = "CharacterTrinket0Slot",        inspect = "InspectTrinket0Slot",      enchantable = false },
    [14] = { char = "CharacterTrinket1Slot",        inspect = "InspectTrinket1Slot",      enchantable = false },
    [15] = { char = "CharacterBackSlot",            inspect = "InspectBackSlot",          enchantable = true  },
    [16] = { char = "CharacterMainHandSlot",        inspect = "InspectMainHandSlot",      enchantable = true  },
    [17] = { char = "CharacterSecondaryHandSlot",   inspect = "InspectSecondaryHandSlot", enchantable = true  },
}

-- Ordered list of slot IDs used for ilvl average and stat summation
Data.ILVL_SLOTS = { 1,2,3,5,6,7,8,9,10,11,12,13,14,15,16,17 }

-- Quick lookup: slotID → enchantable
Data.ENCHANTABLE = {}
for id, info in pairs(Data.SLOTS) do
    Data.ENCHANTABLE[id] = info.enchantable
end

-- Slot display names
Data.SLOT_NAMES = {
    [1]  = "Head",
    [2]  = "Neck",
    [3]  = "Shoulder",
    [5]  = "Chest",
    [6]  = "Waist",
    [7]  = "Legs",
    [8]  = "Feet",
    [9]  = "Wrist",
    [10] = "Hands",
    [11] = "Ring 1",
    [12] = "Ring 2",
    [13] = "Trinket 1",
    [14] = "Trinket 2",
    [15] = "Back",
    [16] = "Main Hand",
    [17] = "Off Hand",
}

-- Map slot IDs to Auctionator "Item Enhancements" subcategory names
Data.SLOT_ENCHANT_CATEGORY = {
    [5]  = "Chest",
    [7]  = "Legs",
    [8]  = "Feet",
    [9]  = "Wrist",
    [11] = "Finger",
    [12] = "Finger",
    [15] = "Back",
    [16] = "Weapon",
    [17] = "Weapon",
}

---------------------------------------------------------------------------
-- Stat key definitions for C_Item.GetItemStats
-- Keys are the global string NAMES returned in the stat table.
-- order: display order in the panel.
---------------------------------------------------------------------------

-- Primary attributes
Data.PRIMARY_STAT_KEYS = {
    { key = "ITEM_MOD_STRENGTH_SHORT",  label = "Strength"   },
    { key = "ITEM_MOD_AGILITY_SHORT",   label = "Agility"    },
    { key = "ITEM_MOD_INTELLECT_SHORT", label = "Intellect"  },
    { key = "ITEM_MOD_STAMINA_SHORT",   label = "Stamina"    },
}

-- Secondary (combat rating) stats
Data.SECONDARY_STAT_KEYS = {
    { key = "ITEM_MOD_CRIT_RATING_SHORT",    label = "Critical Strike", cr = CR_CRIT_MELEE              },
    { key = "ITEM_MOD_HASTE_RATING_SHORT",   label = "Haste",           cr = CR_HASTE_MELEE             },
    { key = "ITEM_MOD_MASTERY_RATING_SHORT", label = "Mastery",         cr = CR_MASTERY                 },
    { key = "ITEM_MOD_VERSATILITY",          label = "Versatility",     cr = CR_VERSATILITY_DAMAGE_DONE },
    { key = "ITEM_MOD_CR_SPEED",             label = "Speed",           cr = CR_SPEED                   },
    { key = "ITEM_MOD_CR_LIFESTEAL",         label = "Leech",           cr = CR_LIFESTEAL               },
    { key = "ITEM_MOD_CR_AVOIDANCE",         label = "Avoidance",       cr = CR_AVOIDANCE               },
    { key = "ITEM_MOD_DODGE_RATING_SHORT",   label = "Dodge",           cr = CR_DODGE                   },
    { key = "ITEM_MOD_PARRY_RATING_SHORT",   label = "Parry",           cr = CR_PARRY                   },
}

---------------------------------------------------------------------------
-- Gear stat computation
-- Sums C_Item.GetItemStats across all equipped slots for the given unit.
-- Returns { primary = { key→value }, secondary = { key→value } }
-- Values are raw stat ratings from item data (excludes base stats and buffs).
---------------------------------------------------------------------------

function Data.ComputeGearStats(unit)
    local primary   = {}
    local secondary = {}
    if not C_Item or not C_Item.GetItemStats then return primary, secondary end

    for _, slotID in ipairs(Data.ILVL_SLOTS) do
        local link = GetInventoryItemLink(unit, slotID)
        if link then
            local ok, stats = pcall(C_Item.GetItemStats, link)
            if ok and stats then
                for _, def in ipairs(Data.PRIMARY_STAT_KEYS) do
                    local v = stats[def.key]
                    if v and v > 0 then
                        primary[def.key] = (primary[def.key] or 0) + v
                    end
                end
                for _, def in ipairs(Data.SECONDARY_STAT_KEYS) do
                    local v = stats[def.key]
                    if v and v > 0 then
                        secondary[def.key] = (secondary[def.key] or 0) + v
                    end
                end
            end
        end
    end
    return primary, secondary
end

---------------------------------------------------------------------------
-- Item link parsing
-- Link format: |Hitem:ITEMID:ENCHANTID:GEM1:GEM2:GEM3:GEM4:SUFFIXID:...|h[Name]|h
-- After strsplit(":", rawLink):
--   [1] = "|cXXXXXXXX|Hitem"  or "item" portion (we skip)
--   [2] = ITEMID
--   [3] = ENCHANTID
--   [4] = GEM1, [5] = GEM2, [6] = GEM3, [7] = GEM4
---------------------------------------------------------------------------

-- Returns the enchant ID (number) embedded in an item link, or 0.
function Data.GetEnchantID(link)
    if not link then return 0 end
    local stripped = link:match("|Hitem:(.+)|h") or link
    local fields = { strsplit(":", stripped) }
    -- fields[1]=itemID, fields[2]=enchantID, fields[3..6]=gemIDs
    return tonumber(fields[2]) or 0
end

-- Returns enchant name for a unit's equipped slot by scanning the tooltip.
-- Returns nil if no enchant is present or the name can't be extracted.
function Data.GetEnchantName(unit, slotID)
    if not C_TooltipInfo or not C_TooltipInfo.GetInventoryItem then return nil end
    local ok, data = pcall(C_TooltipInfo.GetInventoryItem, unit, slotID)
    if not ok or not data or not data.lines then return nil end
    for _, line in ipairs(data.lines) do
        local text = line.leftText
        if text then
            local name = text:match("^Enchanted: (.+)$")
            if name then return name end
            name = text:match("^Permanently enchanted with (.+)$")
            if name then return name end
        end
    end
    return nil
end

---------------------------------------------------------------------------
-- Gem helpers
-- Uses C_Item.GetItemStats for total socket count (EMPTY_SOCKET_* keys),
-- C_Item.GetItemGem for filled count (returns nil for empty sockets).
---------------------------------------------------------------------------

function Data.GetGemCounts(link)
    if not link then return 0, 0 end

    -- Total sockets: sum all EMPTY_SOCKET_* entries from item stats
    local total = 0
    if C_Item and C_Item.GetItemStats then
        local ok, stats = pcall(C_Item.GetItemStats, link)
        if ok and stats then
            for k, v in pairs(stats) do
                if k:find("EMPTY_SOCKET", 1, true) then
                    total = total + (v or 0)
                end
            end
        end
    end

    if total == 0 then return 0, 0 end

    -- Filled sockets: iterate up to total using GetItemGem
    local filled = 0
    if C_Item and C_Item.GetItemGem then
        for i = 1, total do
            local ok2, gemName = pcall(C_Item.GetItemGem, link, i)
            if ok2 and gemName and gemName ~= "" then
                filled = filled + 1
            end
        end
    end

    return total, filled
end

---------------------------------------------------------------------------
-- Item level helper
---------------------------------------------------------------------------

function Data.GetItemLevel(link)
    if not link then return 0 end
    if not C_Item or not C_Item.GetDetailedItemLevelInfo then return 0 end
    local ok, ilvl = pcall(C_Item.GetDetailedItemLevelInfo, link)
    return (ok and ilvl) or 0
end

---------------------------------------------------------------------------
-- Number formatting helper (comma-separated thousands)
---------------------------------------------------------------------------

function Data.FormatNumber(n)
    if not n or n == 0 then return "0" end
    n = math.floor(n + 0.5)
    local s = tostring(n)
    local result = s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    return result
end
