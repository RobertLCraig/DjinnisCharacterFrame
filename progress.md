Spec Summary
What it does
Augments the existing Blizzard Character and Inspect frames — no replacement, just hooks + overlaid widgets.

Features (v1)
Feature	Self	Inspect
Per-slot item level	✅	✅
Enchant name / missing warning	✅	✅
Gem display / empty socket warning	✅	✅
Spec + role badge	✅	✅
Secondary stats (Crit/Haste/Mastery/Vers/Speed)	✅	❌ (API limitation — show "—")
Architecture

Core.lua          — addon object, module system, SavedVariables
Data.lua          — link parsing, enchant ID map, gem helpers
Inspect.lua       — NotifyInspect queue + INSPECT_READY handler
Modules/
  SlotOverlay.lua — ilvl / enchant / gem overlays on both frames
  SpecDisplay.lua — spec icon + name + role badge
  StatsPanel.lua  — secondary stats (self only v1)
Settings.lua      — Blizzard Interface Options integration
Key technical notes
Enchant: parsed from item link string field 3 (:enchantID:) — no dedicated read API exists
Gems: C_Item.GetItemGem(link, 1..4) — iterate until nil to find socket count
Inspect throttle: server silently drops rapid requests; wrapping NotifyInspect in a 1 s cooldown queue with a 3 s retry timeout is essential
Stats on inspect: not available from the API — this is a hard server-side limitation
Next step
Start with DjinnisCharacterFrame.toc + Core.lua skeleton, then SlotOverlay.lua as the first visible module. Ready to begin whenever you are.


Files created
File	Purpose
DjinnisCharacterFrame.toc	Addon metadata, load order
Core.lua	Addon object, module system, OnBlizzardAddonLoaded callback bus, ADDON_LOADED init
Data.lua	Slot definitions, enchant ID parsing, enchant name via C_TooltipInfo, gem counts via C_Item.GetItemGem
Inspect.lua	NotifyInspect queue with 1.2 s throttle, 4 s timeout, 1 retry, GUID-verified INSPECT_READY
Modules/SlotOverlay.lua	ilvl / enchant name / missing-enchant dot / gem count overlays on both frames
Modules/SpecDisplay.lua	Spec icon + name + role badge on character frame; role icon beside InspectLevelText
Modules/StatsPanel.lua	Compact Crit/Haste/Mastery/Vers/Speed/Leech/Avoid panel below CharacterStatsPane
Settings.lua	Blizzard Interface Options panel with checkboxes for each feature
Key design decisions
No frame replacement — everything is hooks + overlaid widgets, ElvUI-safe
Blizzard addon load-order handled — OnBlizzardAddonLoaded callbacks fire when Blizzard_UIPanels_Game and Blizzard_InspectUI load on demand; hooksecurefunc is called only then
Overlays are lazy — EnsureOverlays(button) creates FontStrings the first time the hook fires for each button, so nothing breaks if a slot button doesn't exist yet
Inspect queue — wraps NotifyInspect to survive server throttle
Next step
Copy/symlink the folder to your AddOns directory and test in-game. The most likely things to tweak on first run are the overlay positions (TOPLEFT, BOTTOMRIGHT offsets in SlotOverlay) — those depend on actual slot button size (usually ~37×37 px in retail).


---

New: Modules/InspectPanel.lua

A companion panel anchored to InspectFrame's right edge, matching the character frame's right-pane layout:

Section	Content	Source
Item Level	X.XX in blue	C_PaperDollInfo.GetInspectItemLevel → fallback computed average
Specialisation	Spec icon + name + role (Tank/Healer/DPS in role colour)	GetInspectSpecialization + GetSpecializationInfoByID
Gear Audit	Enchants: X / Y · Gems: X / Y (green=all good, orange=partial, red=none)	Item link parsing
Stats	"Primary and secondary stats not available…" in dim grey	API limitation
The panel:

Appears/disappears with InspectFrame via InspectFrame_OnShow/OnHide hooks
Refreshes on INSPECT_READY (our queue callback) and on InspectPaperDollFrame_UpdateButtons (Blizzard's own update path, catches cached reopens)
The redundant role icon that was on InspectLevelText in SpecDisplay has been removed since InspectPanel now owns spec display for the inspect frame


---

All done. Here's a summary of what changed:

SlotOverlay.lua — taint fix:

Added PreInitCharSlots() / PreInitInspectSlots() called immediately when each Blizzard addon loads, so all overlay FontStrings/Textures are created before any combat can occur
Added InCombatLockdown() guard inside EnsureOverlays as a last-resort safety net
Switched all hooksecurefunc calls to ns.SafeHook (pcall wrapper, deduped error logging)
Replaced hooksecurefunc("InspectFrame_OnHide", ...) with InspectFrame:HookScript("OnHide", ...) to catch all hide paths
All event/callback bodies wrapped in pcall
InspectPanel.lua — stats + auto-close:

Auto-close: replaced hooksecurefunc("InspectFrame_OnHide", ...) with InspectFrame:HookScript("OnHide", ...) — this fires for every hide path including out-of-range server-side closes, not just explicit function calls
Attributes section: pre-created rows for all 4 primary stats (Strength/Agility/Intellect/Stamina), hidden when value is 0
Enhancements section: pre-created rows for all 9 secondary stat ratings (Crit/Haste/Mastery/Versatility/Speed/Leech/Avoidance/Dodge/Parry), hidden when value is 0
Both sections fed by Data.ComputeGearStats(unit) which parses C_Item.GetItemStats across all equipped slots
Refresh wrapped in SafeRefresh (pcall, logs once per session)
Init body wrapped in pcall


---

Visual update (InspectPanel.lua)
Thinner border — switched from thick tooltip border (UI-Tooltip-Border, edgeSize=12) to thin 1px border (ChatFrameBackground, edgeSize=1), matching StatsPanel's style
Subtle background — slightly more transparent (0.85 vs 0.92 opacity), darker tint
Dynamic layout — talent section repositions itself based on how many stat rows are visible, eliminating gaps from hidden stats (Speed/Leech/Avoidance/Dodge/Parry when 0)
Talent Comparison (new section in InspectPanel)
Detects same class + same spec between you and the inspected player
Uses C_Traits API to compare talent node selections node-by-node via Constants.TraitConsts.INSPECT_TRAIT_CONFIG_ID
Shows summary: "23 / 25 match (92%)" with green/yellow/red coloring
Shows differences: each diff as "|cblueYour Talent|r → |corangeTheir Talent|r" with inline WoW color codes
Up to 6 diff rows shown, with "… and N more" overflow
Gracefully handles: different class ("Different class"), different spec ("Different spec"), missing API ("API unavailable"), missing inspect config
All API calls wrapped in pcall
Toggle added to Settings: "Compare talents when inspecting same spec"
Supporting changes
Core.lua — added showTalentCompare = true default
Settings.lua — added Talent Comparison section with toggle checkbox

---

Enchant/gem visibility (SlotOverlay.lua)
Enchant text: color changed from blue to green (signals "all good"), font bumped 8→9pt
Missing enchant: replaced tiny 7x7 red dot with a bold red "!" at 14pt — far more visible
Gem text: font bumped 8→9pt for consistency
Interactive Gear Audit (InspectPanel.lua)
Enchants and Gems rows are now clickable Button frames with hover highlight
Hover shows a GameTooltip with per-slot breakdown (slot name + "Enchanted"/"Missing" or gem counts, color-coded green/red)
Click creates an Auctionator shopping list for missing enchants/gems, using the same category-filtered search format as DjinnisDataTexts (Item Enhancements/Chest, Item Enhancements/Weapon, Gems, etc.)
Falls back gracefully if Auctionator isn't loaded (prints message)
Talent comparison hiding (InspectPanel.lua)
Different class or different spec: talent section is now hidden entirely (no "Different class" noise)
Same class+spec but API unavailable: still shows the section with an error message (helps debugging)
Only shows when there's an actual comparison to display
Data tables (Data.lua)
Added Data.SLOT_NAMES — display names for all 16 gear slots
Added Data.SLOT_ENCHANT_CATEGORY — maps slot IDs to Auctionator subcategory names (Chest, Legs, Feet, Wrist, Finger, Back, Weapon)

---

The ilvl number in the InspectPanel now uses RAID_CLASS_COLORS[class] — so a Shaman's ilvl will show in blue, a Druid's in orange, a Warrior's in tan, etc. Falls back to the previous blue if the class color can't be resolved.

---

Deployed. Here's everything that changed:

Per-slot ilvl now quality-coloured (SlotOverlay.lua)
Item level numbers on each slot button are now colored by item quality — epic purple, rare blue, legendary orange, etc.
Rating + percentage on both frames
Character frame (StatsPanel.lua):

Now shows 490 | 20.65% format (rating + percentage) instead of just percentage
Invalidates the rating ratio cache on update so the inspect panel always has fresh conversion data
Inspect panel (InspectPanel.lua):

Secondary stats now show 666 | 8.42% — raw rating from gear + estimated percentage derived from the player's own rating-to-% ratios (same formula, same max level = accurate estimate)
Uses short labels (Crit/Haste/Mastery/Vers) to fit rating+% in the panel width
Per-slot ilvl breakdown tooltip (InspectPanel.lua)
Item Level row is now hoverable — shows a GameTooltip listing every slot with its ilvl, quality-coloured (epic purple, rare blue, etc.)
Shows "X / 16 slots" count next to the average
Tier set detection (Data.lua + InspectPanel.lua)
New Data.GetTierSetInfo(unit) — scans equipped item tooltips for set membership patterns ("SetName (X/Y)")
Detects set bonus thresholds ((2) Set:, (4) Set:) and whether each is active
InspectPanel shows Tier Sets section between Gear Audit and Attributes — set name, piece count (colour-coded), and bonus text (green if active, grey if not)
Section hides entirely when no set pieces are worn
Rating estimation engine (Data.lua)
Data.GetRatingRatios() — samples the player's own GetCombatRating / GetCombatRatingBonus to derive % per rating point for each stat
Data.EstimatePercent(cr, rating) — applies that ratio to any rating value
Data.InvalidateRatingCache() — called when player stats change
Works because endgame characters are all max level, so the rating→% conversion is identical
Item quality colours (Data.lua)
Data.QUALITY_COLORS table and Data.GetItemQualityColor(link) helper — used by both SlotOverlay and InspectPanel tooltip
Panel slightly wider
200px → 210px to accommodate the rating | percent format

---

Done. A "DCF" toggle button is now placed in the top-right corner of the character frame:

Green "DCF" = enabled — all overlays, spec badge, and stats panel visible
Click → disables everything instantly — ilvl numbers, enchant text, missing indicators, gem counts, spec badge, and stats panel all hide, leaving the clean Blizzard UI
Click again → re-enables and refreshes all overlays
Hover → tooltip explains the action
State is saved in DjinnisCharacterFrameDB.enabled so it persists across sessions
All modules (SlotOverlay, SpecDisplay, StatsPanel) check ns.addon:IsEnabled() before rendering, so hooks that fire while disabled are no-ops

---

Done. A changelog window now appears:

On first load per version — pops up 2 seconds after login/reload, confirming the addon loaded and showing what's new
Dismissible — close button or Escape key
Re-openable — /dcf changelog (or /dcf cl or /dcf log)
Draggable — can reposition it
Scrollable — future versions get prepended to the CHANGELOG table in Core.lua
Won't show again for the same version (tracks lastSeenVersion in SavedVariables)

---

All changes are deployed. Here's a summary of what was fixed:

StatsPanel.lua — Fixed primary stat detection: was checking UnitStat(unit, 3) (Stamina) instead of UnitStat(unit, 4) (Intellect). Now correctly checks indices 1 (Str), 2 (Agi), 4 (Int). Also cleaned up redundant stamina variable.

SlotOverlay.lua — Three updates to UpdateSlot():

Tier badge: Calls new Data.GetSlotTierInfo(unit, slotID) to detect set pieces. Shows "T2", "T4" etc. on the top-left of set items. Enchant text re-anchors after the tier badge when present.
Kill-switch: DCF_tier now properly hidden when addon is disabled.
Full enchant names: Removed the truncation to first word. Now shows up to 18 characters of the full enchant name (e.g. "Enchant of the Twi..").
ClearInspect: Now also hides DCF_tier on inspect slots.
SpecDisplay.lua — Fixed forward-reference bug where mod:SetVisible() called UpdateCharBadge() before it was defined as a local function. Moved the function definition above SetVisible.

Data.lua — Added Data.GetSlotTierInfo(unit, slotID) — per-slot tooltip scan that returns setName, count, total for tier set pieces.

---

ChonkyCharacterSheet - Key Features
Stat Panel Layout:

Scrollable vertical panel replacing Blizzard's CharacterStatsPane
7 collapsible sections with color-coded gradient headers (click to collapse, chevron indicator)
Each row: [Icon] Stat Name .............. (15.45%) 1,234
Click any stat row to highlight which equipped items contribute that stat
Rich tooltips with diminishing returns breakdown (effective vs lost rating, DR bracket progress)
Stat Categories:

Section	Stats	Color
Attributes	Primary, Stamina, Health, Power/Mana, GCD	Gold
Secondary	Crit, Haste, Mastery, Vers (priority-sortable)	Green
Attack	Attack Power, Attack Speed, Spell Power	Red
Defense	Armor, Dodge, Parry, Block, Stagger	Blue
General	Durability, Leech, Avoidance, Speed, Move Speed	Gray
Crests	Currency tracking (M+ crests, catalyst)	Purple
PvP	Honor level, Honor, Conquest	Magenta
Notable features we don't have:

GCD calculation (haste-adjusted, class-aware)
Power type display (Mana/Energy/Rage/etc.)
Diminishing returns with bracket progress
Stat priority ordering per spec
Stat-to-item highlighting
Versatility split (dmg done / dmg taken)
Narcissus Radar Chart
A 96x96px diamond-shaped chart with 4 vertices (Crit top-left, Haste bottom-left, Mastery top-right, Vers bottom-right). Each vertex extends proportionally to that stat's rating relative to total. Uses mask textures + rotation math for filled polygon rendering, with animated transitions.

Proposed DCF Implementation
Combining both into our existing character window:

Radar chart at the top of StatsPanel — diamond visualization of secondary stat balance using WoW's Line widget API (no external textures needed)
Collapsible sections with color-coded headers (Attributes/Secondary/Attack/Defense/Tertiary)
Richer stat rows — (pct%) rating format for secondaries, Versatility split
New stats — GCD, Power type, Attack/Spell Power, Block
DR tooltips — show effective rating, lost rating, bracket progress on hover
Scrollable panel if content exceeds available height
This is a significant rewrite of StatsPanel. Want me to proceed with all of it, or prioritize specific features?


---

StatsPanel (Character Frame)
Replaces Blizzard's CharacterStatsPane — hides the default stat categories and takes over the space
5 collapsible sections with CCS-style gradient headers (click to collapse):
Attributes (gold) — Primary stat, Stamina, Health, Power type, Armor, GCD
Secondary (green) — Crit, Haste, Mastery, Versatility (with (done%/taken%) rating format)
Attack (red) — Attack Power, Attack Speed (MH/OH), Spell Power
Defense (blue) — Dodge, Parry, Block (hidden if 0)
General (gray) — Leech, Avoidance, Speed, Movement Speed
DR tooltips on secondary stats showing effective rating, lost rating, bracket progress
Scrollable content within the existing pane
"Stats" toggle button on the character frame (bottom-right) to show/hide the enhanced view
InspectPanel
Same visual style — gradient headers, dark stat rows, collapsible sections
Matching sections: Item Level, Spec, Gear Audit (with AH shopping lists), Tier Sets, Attributes, Secondary (with estimated %), Talent Comparison
All existing functionality preserved (tooltips, AH integration, talent diff)
Data.lua
Added Data.DR_BRACKETS, Data.ApplySecondaryDR(), Data.GetStatDRInfo(), Data.GetVersDRInfo() for diminishing returns calculations
/reload in-game to test. The "Stats" button bottom-right on the character frame toggles the enhanced view on/off.

---


GemSocket Module
Trigger: Modifier + Right-click on any equipment slot (default: Alt + Right-click)

What it does:

A compact dropdown appears anchored next to the clicked slot
Shows each socket on the item — filled sockets show the gem name + icon in green, empty sockets show "Empty" in red
Below empty sockets, lists all gems found in your bags sorted by quality (epic first)
Each gem row shows: icon, quality-colored name, count in bags
Hover a gem row for its full tooltip
Click a gem to socket it directly — uses the WoW API (PickupContainerItem → SocketInventoryItem → ClickSocketButton → AcceptSockets), suppresses the Blizzard socket UI during the operation
After socketing, the popup refreshes to show the updated state
Close with Escape or the X button
Configurable modifier key:

Settings panel → Gems section → "Gem socket shortcut" button
Click to cycle between Alt, Ctrl, and Shift
Default is Alt + Right-click to avoid conflicting with Blizzard's Alt+hover equipment comparison
/reload in-game to test. The socketing flow will need live testing since the API calls are timing-sensitive.

---
should now see:

Any error messages in red in chat — these will tell us exactly what's failing if something still breaks
"DCF" button — small green text above the top-right corner of the character frame
"Stats" button — bottom-right corner inside the character frame
The key fixes:

All module init and Blizzard callbacks now wrapped in pcall so one error can't break everything
PaperDollFrame_UpdateStats hook guarded against the function not existing
Added CharacterFrame:OnShow hook to re-hide Blizzard stats each time the frame opens

---
The root cause: Blizzard_UIPanels_Game likely loads before our addon, so our OnBlizzardAddonLoaded callback never fires. The inspect frame works because Blizzard_InspectUI is demand-loaded (after our addon registers).

The fix is to check if the Blizzard addon is already loaded when we register
The fix: when a module calls ns:OnBlizzardAddonLoaded("Blizzard_UIPanels_Game", fn), we now check C_AddOns.IsAddOnLoaded first — if it already loaded before our addon, we fire the callback immediately instead of waiting for an ADDON_LOADED event that already passed. This is why the inspect panel worked (demand-loaded after us) but the character frame didn't (loaded before us).


---

