# DjinnisCharacterFrame

A standalone World of Warcraft (Retail / The War Within) addon that enhances both the
**Character Frame** (self) and the **Inspect Frame** (other players), bringing inspect
up to near-parity with the character frame in terms of detail.

---

## Goals

1. Show **per-slot item level** on every equipment slot button.
2. Show **enchants** on enchantable slots — and clearly flag **missing** enchants.
3. Show **gems** in sockets — and clearly flag **empty sockets**.
4. Show the inspected player's active **specialisation** with role icon.
5. Show a **secondary stats summary** (Crit, Haste, Mastery, Versatility, Speed) for self;
   best-effort derivation for inspect.
6. Keep the Blizzard frames intact — no frame replacement, only augmentation via hooks
   and overlaid FontStrings/Textures.
7. Work without ElvUI (standalone), but not break under ElvUI either.

---

## Feature Breakdown

### 1. Item Level Display (per slot)

| Context   | API                                              | Notes                          |
|-----------|--------------------------------------------------|--------------------------------|
| Self      | `GetInventoryItemLink("player", slot)`           | Then `C_Item.GetDetailedItemLevelInfo` |
| Inspect   | `GetInventoryItemLink(inspectUnit, slot)`        | Same path, different unit      |
| Average   | `GetAverageItemLevel()` (self)                   | Already shown by Blizzard; keep it |

- A small `FontString` overlay sits on the bottom-right of each slot button.
- Color: grey for normal, green for upgrade, red for significantly below average (toggle).
- Updates on `PLAYER_EQUIPMENT_CHANGED` (self) and `INSPECT_READY` (inspect).

### 2. Enchant Display

Enchantable slots (retail): Head, Neck, Shoulder, Back, Chest, Wrist, Hands, Legs, Feet,
Finger1, Finger2, MainHand, OffHand.

- **Parse enchant ID** from item link string (field index 2 after itemID in the `:`-split).
- A non-zero enchant ID → show a short enchant name badge on the slot.
- A zero enchant ID on an enchantable slot → show a red "!" or "No Enchant" badge.
- Enchant name resolution:
  - v1: local mapping of common enchant IDs to short names (fast, no API calls).
  - v2: tooltip scanning via `C_TooltipInfo.GetHyperlink` for dynamic resolution.

### 3. Gem Display

- Use `C_Item.GetItemGem(itemLink, index)` for indexes 1–4 per slot.
- Slots with sockets but empty gems → show amber/red dot overlay on the slot icon.
- Slots with no sockets → no overlay.
- Optional gem count badge (e.g. "2/3") as a secondary overlay.

### 4. Spec Display

| Context  | API                                                      |
|----------|----------------------------------------------------------|
| Self     | `GetSpecialization()` + `GetSpecializationInfo(index)`   |
| Inspect  | `GetInspectSpecialization(unit)` + `GetSpecializationInfoByID(id)` |

- Displayed below or alongside the character name/level text in both frames.
- Shows spec icon + spec name + role (e.g. "Holy — Healer").
- For inspect: shown only after `INSPECT_READY` fires and `C_Traits.HasValidInspectData()`
  returns true.

### 5. Secondary Stats Panel

Stats to display:

| Stat         | API                                                           |
|--------------|---------------------------------------------------------------|
| Critical Hit | `GetCombatRatingBonus(CR_CRIT_MELEE)`                         |
| Haste        | `GetCombatRatingBonus(CR_HASTE_MELEE)`                        |
| Mastery      | `GetCombatRatingBonus(CR_MASTERY)`                            |
| Versatility  | `GetCombatRatingBonus(CR_VERSATILITY_DAMAGE_DONE)`            |
| Speed        | `GetCombatRatingBonus(CR_SPEED)`                              |
| Leech        | `GetCombatRatingBonus(CR_LIFESTEAL)`                          |
| Avoidance    | `GetCombatRatingBonus(CR_AVOIDANCE)`                          |

- For **self**: all values readable directly.
- For **inspect**: secondary stats are not exposed by the API.
  - v1: Show "—" / hide panel.
  - v2: Derive from item tooltip data via `C_TooltipInfo.GetInventoryItem` (complex but feasible).

### 6. Inspect Request Management

- Wrap `NotifyInspect` with a queue enforcing ~1 s cooldown between requests (server throttle).
- Listen for `INSPECT_READY` with GUID verification.
- Implement a 3 s timeout fallback that retries once on failure.
- Call `ClearInspectPlayer()` when inspect frame closes.

---

## Architecture

```
DjinnisCharacterFrame/
├── DjinnisCharacterFrame.toc       -- Addon metadata
├── Core.lua                        -- Addon object, module system, SavedVariables init
├── Data.lua                        -- Item link parsing, enchant ID map, gem helpers
├── Inspect.lua                     -- NotifyInspect queue, INSPECT_READY handler
├── Modules/
│   ├── SlotOverlay.lua             -- Per-slot ilvl / enchant / gem overlays (both frames)
│   ├── SpecDisplay.lua             -- Spec + role badge (both frames)
│   └── StatsPanel.lua             -- Secondary stats panel (self only for v1)
├── Settings.lua                    -- Blizzard Settings (Interface Options) integration
└── Libs/
    └── LibStub/LibStub.lua
```

### Module lifecycle (mirrors DjinnisDataTexts / DjinnisClassProfiles pattern)

```lua
local addonName, ns = ...
local mod = {}
ns:RegisterModule("SlotOverlay", mod)

function mod:Init()   ... end          -- called from Core on ADDON_LOADED
function mod:Update(unit) ... end      -- unit = "player" or inspect unit token
```

---

## Slot ID Reference

```
INVSLOT_HEAD      = 1   enchantable
INVSLOT_NECK      = 2   enchantable
INVSLOT_SHOULDER  = 3   enchantable
INVSLOT_CHEST     = 5   enchantable
INVSLOT_WAIST     = 6
INVSLOT_LEGS      = 7   enchantable
INVSLOT_FEET      = 8   enchantable
INVSLOT_WRIST     = 9   enchantable
INVSLOT_HAND      = 10  enchantable
INVSLOT_FINGER1   = 11  enchantable
INVSLOT_FINGER2   = 12  enchantable
INVSLOT_BACK      = 15  enchantable
INVSLOT_MAINHAND  = 16  enchantable
INVSLOT_OFFHAND   = 17  enchantable
```

Shirt (4) and Tabard (19) are excluded from augmentation.

---

## Events

| Event                           | Handler                                       |
|---------------------------------|-----------------------------------------------|
| `PLAYER_EQUIPMENT_CHANGED`      | SlotOverlay.Update("player")                  |
| `INSPECT_READY`                 | Inspect.OnReady → SlotOverlay + SpecDisplay   |
| `PLAYER_SPECIALIZATION_CHANGED` | SpecDisplay.Update("player")                  |
| `UNIT_STATS`                    | StatsPanel.Update (throttled)                 |
| `CHARACTER_POINTS_CHANGED`      | StatsPanel.Update                             |

---

## Key API Calls Cheat-Sheet

```lua
-- Item level
local link = GetInventoryItemLink(unit, slotID)
local ilvl = link and select(1, C_Item.GetDetailedItemLevelInfo(link)) or 0

-- Enchant ID from link  ("item:12345:ENCHANT:gem1:gem2:gem3:gem4:...")
local enchantID = tonumber(select(3, strsplit(":", link or "")) or 0)

-- Gems
local gemName, gemLink = C_Item.GetItemGem(link, 1)  -- index 1-4

-- Spec (self)
local specIndex = GetSpecialization()
local id, name, _, icon, _, role = GetSpecializationInfo(specIndex)

-- Spec (inspect)
local specID = GetInspectSpecialization(unit)
local _, name, _, icon, _, role = GetSpecializationInfoByID(specID)

-- Secondary stats (self only)
local crit  = GetCombatRatingBonus(CR_CRIT_MELEE)
local haste = GetCombatRatingBonus(CR_HASTE_MELEE)
local mast  = GetCombatRatingBonus(CR_MASTERY)
local vers  = GetCombatRatingBonus(CR_VERSATILITY_DAMAGE_DONE)
local speed = GetCombatRatingBonus(CR_SPEED)
```

---

## Known Limitations / Out of Scope (v1)

- **Inspect stats**: secondary stat values are not available from the API for other players.
  Panel shows "—" for inspect targets.
- **Enchant names**: v1 uses a local ID→name map for common enchants. Dynamic resolution is v2.
- **Gem socket count**: derived by iterating C_Item.GetItemGem indexes 1–4 until nil is returned;
  no dedicated socket-count API exists.
- **Retail only**: The War Within / Midnight forward. No Classic support.
- **Inspect throttle**: a single retry is attempted; persistent failures show stale/empty data
  with a "Inspect failed" notice.

---

## Install Path

```
C:\Games\World of Warcraft\_retail_\Interface\AddOns\DjinnisCharacterFrame\
```

No build step — pure Lua.
