-- Djinni's Character Frame — Data
-- Item link parsing, enchant resolution, gem helpers, gear stat computation,
-- rating-to-percentage estimation, item quality helpers, tier set detection.
local addonName, ns = ...

local Data = {}
ns.Data = Data

---------------------------------------------------------------------------
-- Class IDs  (source: Blizzard_ClassTalentUtil.lua)
---------------------------------------------------------------------------

-- Map numeric classID → class token (matches UnitClassBase return values).
Data.CLASS_ID = {
    [1]  = "WARRIOR",
    [2]  = "PALADIN",
    [3]  = "HUNTER",
    [4]  = "ROGUE",
    [5]  = "PRIEST",
    [6]  = "DEATHKNIGHT",
    [7]  = "SHAMAN",
    [8]  = "MAGE",
    [9]  = "WARLOCK",
    [10] = "MONK",
    [11] = "DRUID",
    [12] = "DEMONHUNTER",
    [13] = "EVOKER",
}

-- Reverse lookup: token → classID.
Data.CLASS_TOKEN = {}
for id, token in pairs(Data.CLASS_ID) do
    Data.CLASS_TOKEN[token] = id
end

---------------------------------------------------------------------------
-- Slot definitions
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

Data.ILVL_SLOTS = { 1,2,3,5,6,7,8,9,10,11,12,13,14,15,16,17 }

Data.ENCHANTABLE = {}
for id, info in pairs(Data.SLOTS) do
    Data.ENCHANTABLE[id] = info.enchantable
end

Data.SLOT_NAMES = {
    [1]  = "Head",       [2]  = "Neck",       [3]  = "Shoulder",
    [5]  = "Chest",      [6]  = "Waist",      [7]  = "Legs",
    [8]  = "Feet",       [9]  = "Wrist",      [10] = "Hands",
    [11] = "Ring 1",     [12] = "Ring 2",     [13] = "Trinket 1",
    [14] = "Trinket 2",  [15] = "Back",       [16] = "Main Hand",
    [17] = "Off Hand",
}

Data.SLOT_ENCHANT_CATEGORY = {
    [5]  = "Chest",  [7]  = "Legs",   [8]  = "Feet",
    [9]  = "Wrist",  [11] = "Finger", [12] = "Finger",
    [15] = "Back",   [16] = "Weapon", [17] = "Weapon",
}

---------------------------------------------------------------------------
-- Item quality colours  (mirrors ITEM_QUALITY_COLORS)
---------------------------------------------------------------------------

Data.QUALITY_COLORS = {
    [0] = { 0.62, 0.62, 0.62 },  -- Poor
    [1] = { 1.00, 1.00, 1.00 },  -- Common
    [2] = { 0.12, 1.00, 0.00 },  -- Uncommon
    [3] = { 0.00, 0.44, 0.87 },  -- Rare
    [4] = { 0.64, 0.21, 0.93 },  -- Epic
    [5] = { 1.00, 0.50, 0.00 },  -- Legendary
    [6] = { 0.90, 0.80, 0.50 },  -- Artifact
    [7] = { 0.00, 0.80, 1.00 },  -- Heirloom
}

--- Returns r, g, b for an item link's quality.
function Data.GetItemQualityColor(link)
    if not link then return 1, 1, 1 end
    local _, _, quality = C_Item.GetItemInfo(link)
    if quality then
        local qc = Data.QUALITY_COLORS[quality]
        if qc then return qc[1], qc[2], qc[3] end
    end
    return 1, 1, 1
end

---------------------------------------------------------------------------
-- Stat key definitions
---------------------------------------------------------------------------

Data.PRIMARY_STAT_KEYS = {
    { key = "ITEM_MOD_STRENGTH_SHORT",  label = "Strength"   },
    { key = "ITEM_MOD_AGILITY_SHORT",   label = "Agility"    },
    { key = "ITEM_MOD_INTELLECT_SHORT", label = "Intellect"  },
    { key = "ITEM_MOD_STAMINA_SHORT",   label = "Stamina"    },
}

Data.SECONDARY_STAT_KEYS = {
    { key = "ITEM_MOD_CRIT_RATING_SHORT",    label = "Critical Strike", shortLabel = "Crit",   cr = CR_CRIT_MELEE              },
    { key = "ITEM_MOD_HASTE_RATING_SHORT",   label = "Haste",          shortLabel = "Haste",  cr = CR_HASTE_MELEE             },
    { key = "ITEM_MOD_MASTERY_RATING_SHORT", label = "Mastery",        shortLabel = "Mastery", cr = CR_MASTERY                 },
    { key = "ITEM_MOD_VERSATILITY",          label = "Versatility",    shortLabel = "Vers",   cr = CR_VERSATILITY_DAMAGE_DONE },
    { key = "ITEM_MOD_CR_SPEED",             label = "Speed",          shortLabel = "Speed",  cr = CR_SPEED                   },
    { key = "ITEM_MOD_CR_LIFESTEAL",         label = "Leech",          shortLabel = "Leech",  cr = CR_LIFESTEAL               },
    { key = "ITEM_MOD_CR_AVOIDANCE",         label = "Avoidance",      shortLabel = "Avoid",  cr = CR_AVOIDANCE               },
    { key = "ITEM_MOD_DODGE_RATING_SHORT",   label = "Dodge",          shortLabel = "Dodge",  cr = CR_DODGE                   },
    { key = "ITEM_MOD_PARRY_RATING_SHORT",   label = "Parry",          shortLabel = "Parry",  cr = CR_PARRY                   },
}

---------------------------------------------------------------------------
-- Rating → percentage estimation
-- Uses the player's own combat rating ratios as a reference.
-- For same-level targets this is exact; for different levels it's close
-- enough (the rating formula scales with level but endgame chars are all
-- max level).
---------------------------------------------------------------------------

--- Returns a table { [cr_constant] = percentPerPoint } derived from the
--- player's current combat ratings.  Cached per session / re-computed on
--- demand.
Data._ratingRatios = nil

function Data.GetRatingRatios()
    if Data._ratingRatios then return Data._ratingRatios end
    Data._ratingRatios = {}
    if not GetCombatRating or not GetCombatRatingBonus then
        return Data._ratingRatios
    end
    for _, def in ipairs(Data.SECONDARY_STAT_KEYS) do
        if def.cr then
            local ok, rating = pcall(GetCombatRating, def.cr)
            local ok2, bonus = pcall(GetCombatRatingBonus, def.cr)
            if ok and ok2 and rating and bonus and rating > 0 then
                Data._ratingRatios[def.cr] = bonus / rating
            end
        end
    end
    return Data._ratingRatios
end

--- Invalidate rating ratio cache (call when player levels up or changes spec).
function Data.InvalidateRatingCache()
    Data._ratingRatios = nil
end

--- Estimate percentage for a given combat rating value.
--- Returns formatted string like "12.34%" or nil if ratio unknown.
function Data.EstimatePercent(cr, ratingValue)
    if not cr or not ratingValue or ratingValue <= 0 then return nil end
    local ratios = Data.GetRatingRatios()
    local ratio = ratios[cr]
    if not ratio or ratio <= 0 then return nil end
    return string.format("%.2f%%", ratingValue * ratio)
end

---------------------------------------------------------------------------
-- Gear stat computation
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
-- Per-slot item level breakdown for a unit
-- Returns { {slotID, slotName, ilvl, quality, link}, ... }
-- Sorted by ILVL_SLOTS order.
---------------------------------------------------------------------------

function Data.GetPerSlotIlvl(unit)
    local result = {}
    for _, slotID in ipairs(Data.ILVL_SLOTS) do
        local link = GetInventoryItemLink(unit, slotID)
        if link then
            local ilvl = Data.GetItemLevel(link)
            local _, _, quality = C_Item.GetItemInfo(link)
            table.insert(result, {
                slotID   = slotID,
                slotName = Data.SLOT_NAMES[slotID] or "?",
                ilvl     = ilvl or 0,
                quality  = quality or 1,
                link     = link,
            })
        end
    end
    return result
end

---------------------------------------------------------------------------
-- Tier / class set detection
-- Scans equipped items for set membership via C_Item.GetItemSetInfo or
-- tooltip parsing.
---------------------------------------------------------------------------

function Data.GetTierSetInfo(unit)
    if not C_Item then return nil end

    -- Track set items by setID
    local sets = {}  -- { [setID] = { name, count, total, bonuses } }

    for _, slotID in ipairs(Data.ILVL_SLOTS) do
        local link = GetInventoryItemLink(unit, slotID)
        if link then
            -- Try C_Item.GetItemSetInfo if available
            local itemID = link:match("|Hitem:(%d+):")
            if itemID then
                itemID = tonumber(itemID)
                local setName, setID
                -- GetItemInfo returns setName at index 16 (not always reliable)
                -- Better: scan tooltip for "Set:" lines
                if C_TooltipInfo and C_TooltipInfo.GetInventoryItem then
                    local ok, data = pcall(C_TooltipInfo.GetInventoryItem, unit, slotID)
                    if ok and data and data.lines then
                        for _, line in ipairs(data.lines) do
                            local text = line.leftText
                            if text then
                                -- Match "SetName (X/Y)" pattern
                                local name, cur, tot = text:match("^(.+) %((%d+)/(%d+)%)$")
                                if name and cur and tot then
                                    setName = name
                                    -- Use the name as key since setID isn't reliably available
                                    if not sets[name] then
                                        sets[name] = {
                                            name    = name,
                                            count   = tonumber(cur) or 0,
                                            total   = tonumber(tot) or 0,
                                            bonuses = {},
                                        }
                                    else
                                        -- Update count (tooltip shows current total)
                                        sets[name].count = tonumber(cur) or sets[name].count
                                    end
                                end
                                -- Match set bonus lines: "(2) Set: ..." or "(4) Set: ..."
                                local threshold, bonusText = text:match("^%((%d+)%) Set: (.+)$")
                                if threshold and bonusText and setName and sets[setName] then
                                    table.insert(sets[setName].bonuses, {
                                        threshold = tonumber(threshold),
                                        text      = bonusText,
                                        active    = sets[setName].count >= tonumber(threshold),
                                    })
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- Convert to array
    local result = {}
    for _, info in pairs(sets) do
        table.insert(result, info)
    end
    if #result == 0 then return nil end
    return result
end

--- Check if a single slot's item belongs to a tier set.
--- Returns setName, count, total  or nil if not a set piece.
function Data.GetSlotTierInfo(unit, slotID)
    if not C_TooltipInfo or not C_TooltipInfo.GetInventoryItem then return nil end
    local ok, data = pcall(C_TooltipInfo.GetInventoryItem, unit, slotID)
    if not ok or not data or not data.lines then return nil end
    for _, line in ipairs(data.lines) do
        local text = line.leftText
        if text then
            local name, cur, tot = text:match("^(.+) %((%d+)/(%d+)%)$")
            if name and cur and tot then
                return name, tonumber(cur), tonumber(tot)
            end
        end
    end
    return nil
end

---------------------------------------------------------------------------
-- Item link parsing
---------------------------------------------------------------------------

function Data.GetEnchantID(link)
    if not link then return 0 end
    local stripped = link:match("|Hitem:(.+)|h") or link
    local fields = { strsplit(":", stripped) }
    return tonumber(fields[2]) or 0
end

function Data.GetEnchantName(unit, slotID)
    if not C_TooltipInfo or not C_TooltipInfo.GetInventoryItem then return nil end
    local ok, data = pcall(C_TooltipInfo.GetInventoryItem, unit, slotID)
    if not ok or not data or not data.lines then return nil end
    for _, line in ipairs(data.lines) do
        local text = line.leftText
        if text then
            local name = text:match("^Enchanted: (.+)$")
                      or text:match("^Permanently enchanted with (.+)$")
            if name then
                -- Strip "Enchant <SlotType> - " prefix (e.g. "Enchant Helm - Hex…" → "Hex…")
                name = name:gsub("^Enchant%s+%S+%s+%-%s+", "")
                return name
            end
        end
    end
    return nil
end

---------------------------------------------------------------------------
-- Gem helpers
---------------------------------------------------------------------------

function Data.GetGemCounts(link)
    if not link then return 0, 0 end

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
-- Number formatting
---------------------------------------------------------------------------

function Data.FormatNumber(n)
    if not n or n == 0 then return "0" end
    n = math.floor(n + 0.5)
    local s = tostring(n)
    local result = s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    return result
end

---------------------------------------------------------------------------
-- Diminishing Returns (from Blizzard / Wowhead)
-- https://www.wowhead.com/guide/diminishing-returns-on-secondary-stats
---------------------------------------------------------------------------

Data.DR_BRACKETS = {
    { 30, 1.00 },   -- 0% penalty
    { 39, 0.90 },   -- 10% penalty
    { 47, 0.80 },   -- 20% penalty
    { 54, 0.70 },   -- 30% penalty
    { 66, 0.60 },   -- 40% penalty
    { 126, 0.50 },  -- 50% penalty
}

--- Apply diminishing returns to a raw percent value.
--- Returns effectivePercent, percentLost
function Data.ApplySecondaryDR(rawPercent)
    local remaining = rawPercent
    local effective = 0
    local lastCap = 0
    for _, bracket in ipairs(Data.DR_BRACKETS) do
        if remaining <= 0 then break end
        local cap, mult = bracket[1], bracket[2]
        local slice = math.min(remaining, cap - lastCap)
        effective = effective + slice * mult
        remaining = remaining - slice
        lastCap = cap
    end
    return effective, rawPercent - effective
end

--- Full DR info for a combat rating constant.
--- Returns table with rawRating, rawPercent, effectivePercent, percentLost,
--- effectiveRating, ratingLost, bracketStart, bracketEnd.
function Data.GetStatDRInfo(ratingID)
    local rawRating = GetCombatRating(ratingID) or 0
    if rawRating <= 0 then
        return { rawRating = 0, rawPercent = 0, effectivePercent = 0,
                 percentLost = 0, effectiveRating = 0, ratingLost = 0 }
    end

    local rawPercent = GetCombatRatingBonus(ratingID) or 0
    local effectivePercent, percentLost = Data.ApplySecondaryDR(rawPercent)

    local percentPerRating = rawPercent / rawRating
    local ratingLost = (percentPerRating > 0) and (percentLost / percentPerRating) or 0
    local effectiveRating = rawRating - ratingLost

    -- Find current DR bracket
    local bracketStart, bracketEnd = 0, Data.DR_BRACKETS[1][1]
    local lastCap = 0
    for _, bracket in ipairs(Data.DR_BRACKETS) do
        if rawPercent <= bracket[1] then
            bracketStart = lastCap
            bracketEnd = bracket[1]
            break
        end
        lastCap = bracket[1]
    end

    return {
        rawRating        = rawRating,
        rawPercent       = rawPercent,
        effectivePercent = effectivePercent,
        percentLost      = percentLost,
        effectiveRating  = effectiveRating,
        ratingLost       = ratingLost,
        bracketStart     = bracketStart,
        bracketEnd       = bracketEnd,
    }
end

---------------------------------------------------------------------------
-- Gem helpers (bag scanning)
---------------------------------------------------------------------------

--- Scan bags for gem items. Returns array of { itemID, name, link, icon,
--- quality, bagID, slotIndex, count }.
function Data.ScanBagsForGems()
    local gems = {}
    local seen = {}  -- dedup by itemID
    if not C_Container or not C_Container.GetContainerNumSlots then return gems end

    for bag = 0, 4 do
        local numSlots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, numSlots do
            local link = C_Container.GetContainerItemLink(bag, slot)
            if link then
                local _, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(link)
                -- classID 3 = Gem
                if classID == 3 then
                    local itemID = C_Container.GetContainerItemID(bag, slot)
                    if itemID and not seen[itemID] then
                        local name, _, quality, _, _, _, _, _, _, icon = C_Item.GetItemInfo(link)
                        local info = C_Container.GetContainerItemInfo(bag, slot)
                        local count = info and info.stackCount or 1
                        seen[itemID] = true
                        table.insert(gems, {
                            itemID    = itemID,
                            name      = name or "?",
                            link      = link,
                            icon      = icon,
                            quality   = quality or 1,
                            bagID     = bag,
                            slotIndex = slot,
                            count     = count,
                        })
                    end
                end
            end
        end
    end

    -- Sort by quality desc, then name
    table.sort(gems, function(a, b)
        if a.quality ~= b.quality then return a.quality > b.quality end
        return a.name < b.name
    end)

    return gems
end

--- Get socket info for an equipped item.
--- Returns { total = N, sockets = { {index, gemName, gemIcon, gemLink}, ... } }
function Data.GetSocketInfo(unit, slotID)
    local link = GetInventoryItemLink(unit, slotID)
    if not link then return nil end

    local total, filled = Data.GetGemCounts(link)
    if total == 0 then return nil end

    local sockets = {}
    for i = 1, total do
        local gemName, gemLink
        if C_Item and C_Item.GetItemGem then
            local ok, gn, gl = pcall(C_Item.GetItemGem, link, i)
            if ok then
                gemName = gn
                gemLink = gl
            end
        end
        local gemIcon = nil
        if gemLink then
            local _, _, _, _, _, ic = C_Item.GetItemInfoInstant(gemLink)
            gemIcon = ic
        elseif gemName and gemName ~= "" then
            local _, _, _, _, _, _, _, _, _, ic = C_Item.GetItemInfo(gemName)
            gemIcon = ic
        end
        table.insert(sockets, {
            index   = i,
            name    = (gemName and gemName ~= "") and gemName or nil,
            icon    = gemIcon,
            link    = gemLink,
            isEmpty = not gemName or gemName == "",
        })
    end

    return { total = total, filled = filled, sockets = sockets }
end

--- Find the bag position of a gem by itemID.
--- Returns bagID, slotIndex or nil.
function Data.FindGemInBags(itemID)
    if not C_Container or not C_Container.GetContainerNumSlots then return nil end
    for bag = 0, 4 do
        local numSlots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, numSlots do
            local id = C_Container.GetContainerItemID(bag, slot)
            if id == itemID then
                return bag, slot
            end
        end
    end
    return nil
end

--- Versatility DR info — returns dmg done % and dmg taken % separately.
function Data.GetVersDRInfo()
    local rawRating = GetCombatRating(CR_VERSATILITY_DAMAGE_DONE) or 0
    if rawRating <= 0 then
        return { rawRating = 0, dmgDone = 0, dmgTaken = 0,
                 effectiveDone = 0, effectiveTaken = 0 }
    end
    local ratingDone  = GetCombatRatingBonus(CR_VERSATILITY_DAMAGE_DONE) or 0
    local ratingTaken = GetCombatRatingBonus(CR_VERSATILITY_DAMAGE_TAKEN) or 0
    local bonusDone   = (GetVersatilityBonus and GetVersatilityBonus(CR_VERSATILITY_DAMAGE_DONE)) or 0
    local bonusTaken  = (GetVersatilityBonus and GetVersatilityBonus(CR_VERSATILITY_DAMAGE_TAKEN)) or 0
    local totalDone  = ratingDone + bonusDone
    local totalTaken = ratingTaken + bonusTaken
    local effDone  = Data.ApplySecondaryDR(totalDone)
    local effTaken = Data.ApplySecondaryDR(totalTaken)
    return {
        rawRating      = rawRating,
        dmgDone        = totalDone,
        dmgTaken       = totalTaken,
        effectiveDone  = effDone,
        effectiveTaken = effTaken,
    }
end
