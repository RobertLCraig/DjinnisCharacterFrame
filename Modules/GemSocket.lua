-- Djinni's Character Frame — GemSocket
-- Alt+click on an equipment slot opens a compact dropdown showing each
-- socket (filled/empty) and listing matching gems from bags.
-- Click a gem row to socket it directly.
local addonName, ns = ...

local mod = {}
ns:RegisterModule("GemSocket", mod)

local Data = ns.Data

---------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------

local POPUP_W       = 220
local GEM_ROW_H     = 22
local SOCKET_ROW_H  = 20
local PAD_X         = 6
local PAD_Y         = 6
local MAX_GEMS      = 8   -- max gem rows shown at once

---------------------------------------------------------------------------
-- Colours
---------------------------------------------------------------------------

local C_EMPTY  = { 0.60, 0.30, 0.30, 1 }
local C_FILLED = { 0.40, 1.00, 0.40, 1 }
local C_LABEL  = { 0.75, 0.75, 0.75, 1 }
local C_HDR    = { 1.00, 0.82, 0.00, 1 }

---------------------------------------------------------------------------
-- Popup frame (reused singleton)
---------------------------------------------------------------------------

local popup       = nil
local gemRows     = {}
local socketRows  = {}
local currentSlot = nil
local actionLocked = false

local function LockAction()
    actionLocked = true
    C_Timer.After(0.5, function() actionLocked = false end)
end

---------------------------------------------------------------------------
-- Socket a gem: pickup from bag → socket into slot → accept
---------------------------------------------------------------------------

local suppressFrame = nil

local function SuppressBlizzardSocket()
    if not suppressFrame then
        suppressFrame = CreateFrame("Frame")
    end
    -- Temporarily hide the Blizzard socket UI if it pops open
    suppressFrame:RegisterEvent("SOCKET_INFO_UPDATE")
    suppressFrame:SetScript("OnEvent", function(self, event)
        if event == "SOCKET_INFO_UPDATE" then
            if ItemSocketingFrame and ItemSocketingFrame:IsShown() then
                ItemSocketingFrame:Hide()
            end
        end
    end)
end

local function UnsuppressBlizzardSocket()
    if suppressFrame then
        suppressFrame:UnregisterAllEvents()
        suppressFrame:SetScript("OnEvent", nil)
    end
end

local function DoSocketGem(gemItemID, slotID, socketIndex)
    if actionLocked then return end
    if InCombatLockdown() then
        ns.addon:Print("Cannot socket gems during combat.")
        return
    end

    LockAction()

    local bagID, bagSlot = Data.FindGemInBags(gemItemID)
    if not bagID then
        ns.addon:Print("Gem not found in bags.")
        return
    end

    SuppressBlizzardSocket()

    ClearCursor()
    C_Container.PickupContainerItem(bagID, bagSlot)
    SocketInventoryItem(slotID)

    -- Small delay to let the socket UI initialize, then click+accept
    C_Timer.After(0.05, function()
        local ok, err = pcall(function()
            C_ItemSocketInfo.ClickSocketButton(socketIndex)
            ClearCursor()
            C_ItemSocketInfo.AcceptSockets()
        end)
        if not ok then
            ns.addon:Print("Socket error: " .. tostring(err))
        end

        C_Timer.After(0.2, function()
            UnsuppressBlizzardSocket()
            -- Close and reopen popup to refresh state
            if popup and popup:IsShown() and currentSlot then
                mod:ShowForSlot(currentSlot.button, currentSlot.slotID)
            end
        end)
    end)
end

---------------------------------------------------------------------------
-- Build the popup frame
---------------------------------------------------------------------------

local function EnsurePopup()
    if popup then return end

    popup = CreateFrame("Frame", "DCFGemSocketPopup", UIParent, "BackdropTemplate")
    popup:SetWidth(POPUP_W)
    popup:SetFrameStrata("DIALOG")
    popup:SetFrameLevel(50)
    popup:SetBackdrop({
        bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets   = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    popup:SetBackdropColor(0.06, 0.06, 0.06, 0.95)
    popup:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)
    popup:SetClampedToScreen(true)
    popup:EnableMouse(true)
    popup:Hide()

    -- Close on Escape
    tinsert(UISpecialFrames, "DCFGemSocketPopup")

    -- Close button
    local close = CreateFrame("Button", nil, popup, "UIPanelCloseButton")
    close:SetSize(20, 20)
    close:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -1, -1)
    close:SetScript("OnClick", function() popup:Hide() end)

    -- Title
    local title = popup:CreateFontString(nil, "OVERLAY")
    title:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    title:SetPoint("TOPLEFT", popup, "TOPLEFT", PAD_X + 2, -PAD_Y)
    title:SetTextColor(C_HDR[1], C_HDR[2], C_HDR[3])
    popup.titleFS = title

    -- Close when clicking elsewhere
    popup:SetScript("OnHide", function()
        currentSlot = nil
    end)
end

---------------------------------------------------------------------------
-- Create socket status row (shows "Socket 1: [icon] Gem Name" or "Empty")
---------------------------------------------------------------------------

local function EnsureSocketRow(index)
    if socketRows[index] then return socketRows[index] end

    local f = CreateFrame("Frame", nil, popup)
    f:SetSize(POPUP_W - PAD_X * 2, SOCKET_ROW_H)

    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetSize(14, 14)
    icon:SetPoint("LEFT", f, "LEFT", 2, 0)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    f.icon = icon

    local lbl = f:CreateFontString(nil, "OVERLAY")
    lbl:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
    lbl:SetPoint("LEFT", icon, "RIGHT", 4, 0)
    lbl:SetJustifyH("LEFT")
    f.label = lbl

    socketRows[index] = f
    return f
end

---------------------------------------------------------------------------
-- Create gem row (clickable, shows icon + name + count)
---------------------------------------------------------------------------

local function EnsureGemRow(index)
    if gemRows[index] then return gemRows[index] end

    local btn = CreateFrame("Button", nil, popup)
    btn:SetSize(POPUP_W - PAD_X * 2, GEM_ROW_H)
    btn:RegisterForClicks("LeftButtonUp")

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.08, 0.08, 0.08, 0.6)

    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetPoint("LEFT", btn, "LEFT", 3, 0)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    btn.icon = icon

    local name = btn:CreateFontString(nil, "OVERLAY")
    name:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    name:SetPoint("LEFT", icon, "RIGHT", 4, 0)
    name:SetPoint("RIGHT", btn, "RIGHT", -30, 0)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    name:SetMaxLines(1)
    btn.nameFS = name

    local count = btn:CreateFontString(nil, "OVERLAY")
    count:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
    count:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
    count:SetJustifyH("RIGHT")
    count:SetTextColor(0.7, 0.7, 0.7)
    btn.countFS = count

    -- Tooltip on hover
    btn:SetScript("OnEnter", function(self)
        if self.gemLink then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(self.gemLink)
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    gemRows[index] = btn
    return btn
end

---------------------------------------------------------------------------
-- Show popup for a specific slot
---------------------------------------------------------------------------

function mod:ShowForSlot(button, slotID)
    EnsurePopup()

    local socketInfo = Data.GetSocketInfo("player", slotID)
    if not socketInfo or socketInfo.total == 0 then
        ns.addon:Print("No sockets on this item.")
        popup:Hide()
        return
    end

    currentSlot = { button = button, slotID = slotID }

    -- Title: slot name
    local slotName = Data.SLOT_NAMES[slotID] or ("Slot " .. slotID)
    popup.titleFS:SetText(slotName .. " — Sockets")

    -- Position: anchor to the right of the slot button
    popup:ClearAllPoints()
    popup:SetPoint("TOPLEFT", button, "TOPRIGHT", 4, 0)

    local y = -(PAD_Y + 16)  -- below title

    -- Show socket status rows
    local emptySocketIndices = {}
    for i, sock in ipairs(socketInfo.sockets) do
        local row = EnsureSocketRow(i)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", popup, "TOPLEFT", PAD_X, y)
        row:Show()

        if sock.isEmpty then
            row.icon:SetTexture("Interface\\ItemSocketingFrame\\UI-EmptySocket-Prismatic")
            row.label:SetText("|cffcc5555Socket " .. i .. ": Empty|r")
            table.insert(emptySocketIndices, i)
        else
            if sock.icon then
                row.icon:SetTexture(sock.icon)
            else
                row.icon:SetTexture("Interface\\Icons\\INV_Misc_Gem_01")
            end
            row.label:SetText("|cff66ff66Socket " .. i .. ":|r " .. (sock.name or "Gemmed"))
        end

        y = y - SOCKET_ROW_H
    end

    -- Hide extra socket rows
    for i = socketInfo.total + 1, #socketRows do
        socketRows[i]:Hide()
    end

    -- Separator
    if #emptySocketIndices > 0 then
        y = y - 4
        if not popup.sep then
            popup.sep = popup:CreateTexture(nil, "ARTWORK")
            popup.sep:SetHeight(1)
            popup.sep:SetColorTexture(0.35, 0.35, 0.35, 0.6)
        end
        popup.sep:ClearAllPoints()
        popup.sep:SetPoint("TOPLEFT", popup, "TOPLEFT", PAD_X, y)
        popup.sep:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -PAD_X, y)
        popup.sep:Show()
        y = y - 6

        -- "Available Gems" subheader
        if not popup.gemHdr then
            popup.gemHdr = popup:CreateFontString(nil, "OVERLAY")
            popup.gemHdr:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
            popup.gemHdr:SetTextColor(C_HDR[1], C_HDR[2], C_HDR[3], 0.8)
        end
        popup.gemHdr:ClearAllPoints()
        popup.gemHdr:SetPoint("TOPLEFT", popup, "TOPLEFT", PAD_X + 2, y)
        popup.gemHdr:SetText("Available Gems")
        popup.gemHdr:Show()
        y = y - 14

        -- Scan bags for gems
        local bagGems = Data.ScanBagsForGems()

        -- Determine which empty socket to target (first empty one)
        local targetSocket = emptySocketIndices[1]

        local shown = 0
        for gi, gem in ipairs(bagGems) do
            if shown >= MAX_GEMS then break end
            shown = shown + 1

            local row = EnsureGemRow(shown)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", popup, "TOPLEFT", PAD_X, y)
            row:Show()

            row.icon:SetTexture(gem.icon or "Interface\\Icons\\INV_Misc_Gem_01")
            row.gemLink = gem.link

            -- Color by quality
            local qc = Data.QUALITY_COLORS[gem.quality] or Data.QUALITY_COLORS[2]
            row.nameFS:SetText(gem.name)
            row.nameFS:SetTextColor(qc[1], qc[2], qc[3])

            row.countFS:SetText("x" .. gem.count)

            -- Click to socket into the first empty socket
            local capturedSlotID = slotID
            local capturedSocket = targetSocket
            local capturedGemID  = gem.itemID
            row:SetScript("OnClick", function()
                DoSocketGem(capturedGemID, capturedSlotID, capturedSocket)
            end)

            y = y - GEM_ROW_H
        end

        -- Hide unused gem rows
        for gi = shown + 1, #gemRows do
            gemRows[gi]:Hide()
        end

        if shown == 0 then
            -- No gems in bags message
            if not popup.noGemsFS then
                popup.noGemsFS = popup:CreateFontString(nil, "OVERLAY")
                popup.noGemsFS:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
                popup.noGemsFS:SetTextColor(0.5, 0.5, 0.5)
            end
            popup.noGemsFS:ClearAllPoints()
            popup.noGemsFS:SetPoint("TOPLEFT", popup, "TOPLEFT", PAD_X + 2, y)
            popup.noGemsFS:SetText("No gems found in bags")
            popup.noGemsFS:Show()
            y = y - 16
        else
            if popup.noGemsFS then popup.noGemsFS:Hide() end
        end
    else
        -- All sockets filled
        for gi = 1, #gemRows do gemRows[gi]:Hide() end
        if popup.sep then popup.sep:Hide() end
        if popup.gemHdr then popup.gemHdr:Hide() end
        if popup.noGemsFS then popup.noGemsFS:Hide() end
    end

    popup:SetHeight(math.abs(y) + PAD_Y)
    popup:Show()
end

---------------------------------------------------------------------------
-- Close popup
---------------------------------------------------------------------------

function mod:Hide()
    if popup then popup:Hide() end
end

---------------------------------------------------------------------------
-- Init — no special init needed; we are triggered from SlotOverlay
---------------------------------------------------------------------------

function mod:Init()
    -- Nothing to do here; the popup is created on demand.
    -- SlotOverlay hooks Alt+click on slot buttons to call mod:ShowForSlot()
end
