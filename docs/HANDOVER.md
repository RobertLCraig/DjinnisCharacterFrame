# HANDOVER: Djinni's Character Frame (DCF)

> A World of Warcraft Retail addon that augments the Character and Inspect frames with per-slot item
> level, enchants, gems, spec and secondary stats. It augments the Blizzard frames by hooking them
> and never replaces them. Read this, then `docs/board/`, before changing anything.

**Stage:** dormant
**Category:** addon
**Status:** v0.1.1, `Interface: 120100`. The tree is clean and there is nothing unpushed, because
there is nothing to push to: **this repository has no remote**, which is `WoWAddons#0004`. Last
commit `2026-08-15`, "feat(character): gem socketing, tier sets and a rebuilt stats panel".
**It is NOT installed in the game**, so nothing here has been run against 12.1.0 by anybody. Rob
narrowed active scope to four addons and this is not one of them.
_Last updated: 2026-08-26 (board and handover created; no addon code was touched)_

## Goal & success criteria
**No PRD exists. This section is an interim home and a real gap.** The goal and the criteria below
are lifted from `README.md`, which states them plainly, and are not a spec Rob signed off.

Goal: bring the Inspect frame up to near-parity with the Character frame in detail, for self and for
other players, without replacing either frame.

Success criteria, as `README.md` states them:
- Per-slot item level on every equipment slot button.
- Enchants shown on enchantable slots, with **missing** enchants clearly flagged.
- Gems shown in sockets, with **empty sockets** clearly flagged.
- The inspected player's active specialisation, with role icon.
- A secondary stats summary (Crit, Haste, Mastery, Versatility, Speed) for self, best-effort for
  inspect.
- The Blizzard frames stay intact: hooks and overlaid FontStrings/Textures only, no replacement.
- Works standalone without ElvUI, and does not break under ElvUI either.

**The non-goals are unknown and need Rob.**

## Canonical data shape
`DjinnisCharacterFrameDB`, one account-wide SavedVariables table declared in the `.toc`. **Its shape
lives in `Settings.lua` and `Core.lua` and nowhere else**; there is no `DATA-MODEL.md`, and that is
a gap rather than a decision.

## Architecture / stack
Lua against the Blizzard Retail API, no Ace3 and no `embeds.xml`. `## OptionalDeps: ElvUI` is a
compatibility declaration, not a dependency. Nine Lua files across the root and `Modules/`. No build
step and no test suite: **every check that matters happens in a live game client, which no agent can
run**, so a change here is never verified by anything in this repository.

## Key files / structure
- `Core.lua` - load, event wiring and the shared frame hooks.
- `Inspect.lua` - the Inspect frame half, which is the harder one: inspect data arrives
  asynchronously and can be incomplete.
- `Data.lua` - item level, enchant and gem derivation.
- `Settings.lua` - the options panel and `DjinnisCharacterFrameDB`.
- `Modules/` - the per-feature code.
- `deploy.ps1` and `release.ps1` - this addon owns its own deploy and release scripts, with their
  own exclusion lists. The workspace `bin\deploy.ps1` calls this one when it is present.
- `progress.md`, `CHANGELOG.md`, `RELEASE_NOTES.md` - **history, not a plan.** Anything still owed
  belongs on `docs/board/`.

## Decisions locked
- **Augment, never replace.** Hooks and overlays only. This is criterion 6 of `README.md` and is
  what keeps the addon alive across a patch that rebuilds a Blizzard frame.
- **Standalone first.** ElvUI is optional in both directions.

## Current state
Dormant and out of the game. The 12.1.0 sweep across the workspace updated `.toc` files and one
renamed function and **checked nothing else**, so this addon has been cleared of neither of the two
known 12.1 faults: secret values and protected events. See `C:\Dev\WoWAddons\docs\DECISIONS.md`.

## What's next (in order)
**`docs/board/` owns this.** The board is empty because nothing has been triaged into it yet, not
because nothing is owed - the 12.1 sweep above is a real unaudited gap.

## Blockers / open questions
- **No GitHub remote.** `WoWAddons#0004` is that question, and it covers this repo by name.
- **Never run on 12.1.0.** The first person to deploy it should expect Lua errors, not assume none.
- **The non-goals are unstated**, so scope creep here has nothing to push back against.

## How to pick up
1. Read this file, then `docs/board/README.md` and any card in `docs/board/`.
2. Read `C:\Dev\WoWAddons\docs\DECISIONS.md` for the two 12.1 traps before touching event
   registration or anything keyed on a unit.
3. Deploy from the workspace and never edit the game folder:
   `C:\Dev\WoWAddons\bin\deploy.ps1 -WhatIf -Only DjinnisCharacterFrame`, then the same without
   `-WhatIf`. The dry run is the plan.
4. Check any API against `C:\Dev\WoWAddons\wow-ui-source\`, never from memory. Anything defined only
   under `Blizzard_Deprecated*/` is CVar-gated and is not safe to rely on.

## Sibling docs
- `README.md` in the repository root is the goal statement until a `docs/PRD.md` exists.
- Workspace: `C:\Dev\WoWAddons\docs\HANDOVER.md` and `docs\DECISIONS.md`.
- **Gaps:** no `PRD.md`, no `DATA-MODEL.md`, no `DECISIONS.md`.

## Branch status
One branch, `master`. Clean. No remote, so "unpushed" is not a meaningful count here.

## Session log
- **2026-08-26** Board and handover created, so this stops showing on `board:map` as an
  unidentifiable nested folder. No addon code was touched.
