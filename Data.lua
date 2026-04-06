-- Djinni's Character Frame — Data
-- Item link parsing, enchant resolution, gem helpers.
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

-- Quick lookup: slotID → enchantable
Data.ENCHANTABLE = {}
for id, info in pairs(Data.SLOTS) do
    Data.ENCHANTABLE[id] = info.enchantable
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
    -- strip colour codes first so field indices are stable
    local stripped = link:match("|Hitem:(.+)|h") or link
    local fields = { strsplit(":", stripped) }
    -- fields[1]=itemID, fields[2]=enchantID, fields[3..6]=gemIDs
    return tonumber(fields[2]) or 0
end

-- Returns enchant name for a unit's equipped slot by scanning the tooltip.
-- Falls back to a plain "Enchanted" string if the name can't be extracted.
-- Returns nil if no enchant is present.
function Data.GetEnchantName(unit, slotID)
    if not C_TooltipInfo or not C_TooltipInfo.GetInventoryItem then return nil end
    local data = C_TooltipInfo.GetInventoryItem(unit, slotID)
    if not data or not data.lines then return nil end
    for _, line in ipairs(data.lines) do
        local text = line.leftText
        if text then
            -- Retail enchant lines look like: "Enchanted: Haste & Versatility"
            local name = text:match("^Enchanted: (.+)$")
            if name then return name end
            -- Some enchants appear as "Permanently enchanted with ..."
            name = text:match("^Permanently enchanted with (.+)$")
            if name then return name end
        end
    end
    return nil
end

---------------------------------------------------------------------------
-- Gem helpers
-- C_Item.GetItemGem(itemInfo, index) → gemName (string), gemLink (string|nil)
--   nil gemName  = no socket at that index
--   ""  gemName  = socket exists but is empty
--   str gemName  = socket has a gem
---------------------------------------------------------------------------

-- Returns total socket count and filled socket count for an item link.
function Data.GetGemCounts(link)
    if not link then return 0, 0 end
    if not C_Item or not C_Item.GetItemGem then return 0, 0 end
    local total, filled = 0, 0
    for i = 1, 4 do
        local gemName, gemLink = C_Item.GetItemGem(link, i)
        if gemName == nil then break end   -- no more sockets
        total = total + 1
        if gemLink then filled = filled + 1 end
    end
    return total, filled
end

---------------------------------------------------------------------------
-- Item level helper
---------------------------------------------------------------------------

function Data.GetItemLevel(link)
    if not link then return 0 end
    if not C_Item or not C_Item.GetDetailedItemLevelInfo then return 0 end
    local ilvl = C_Item.GetDetailedItemLevelInfo(link)
    return ilvl or 0
end
