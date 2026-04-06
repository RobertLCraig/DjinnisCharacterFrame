-- Djinni's Character Frame — Inspect
-- Wraps NotifyInspect with a queue + retry to handle server throttling.
local addonName, ns = ...

local Inspect = {}
ns.Inspect = Inspect

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------

local THROTTLE_DELAY = 1.2   -- seconds between requests
local TIMEOUT        = 4.0   -- seconds before we consider the request failed
local MAX_RETRIES    = 1

local queue         = {}     -- pending unit tokens
local currentUnit   = nil
local currentGUID   = nil
local retryCount    = 0
local lastRequestAt = 0
local timeoutTimer  = nil

---------------------------------------------------------------------------
-- Internal helpers
---------------------------------------------------------------------------

local function CancelTimeout()
    if timeoutTimer then
        timeoutTimer:Cancel()
        timeoutTimer = nil
    end
end

local function OnTimeout()
    timeoutTimer = nil
    if retryCount < MAX_RETRIES then
        retryCount = retryCount + 1
        lastRequestAt = 0   -- force immediate retry
        -- Re-queue the unit at the front
        table.insert(queue, 1, currentUnit)
        currentUnit = nil
        Inspect:ProcessQueue()
    else
        -- Give up; fire failure callbacks
        Inspect:OnFailed(currentUnit)
        currentUnit = nil
        currentGUID = nil
        retryCount  = 0
        Inspect:ProcessQueue()
    end
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

-- Request an inspect for unit. Silently deduplicates.
function Inspect:Request(unit)
    if not unit then return end
    if currentUnit == unit then return end
    for _, u in ipairs(queue) do
        if u == unit then return end
    end
    table.insert(queue, unit)
    self:ProcessQueue()
end

function Inspect:ProcessQueue()
    if currentUnit then return end   -- already waiting for a response
    if #queue == 0 then return end

    local now = GetTime()
    local remaining = THROTTLE_DELAY - (now - lastRequestAt)
    if remaining > 0 then
        C_Timer.After(remaining, function() Inspect:ProcessQueue() end)
        return
    end

    currentUnit   = table.remove(queue, 1)
    currentGUID   = UnitGUID(currentUnit)
    retryCount    = 0
    lastRequestAt = now

    if CanInspect(currentUnit) then
        NotifyInspect(currentUnit)
        CancelTimeout()
        timeoutTimer = C_Timer.NewTimer(TIMEOUT, OnTimeout)
    else
        -- Can't inspect right now; skip silently
        Inspect:OnFailed(currentUnit)
        currentUnit = nil
        currentGUID = nil
        self:ProcessQueue()
    end
end

-- Called by the event listener when INSPECT_READY fires.
function Inspect:OnReady(guid)
    if not currentUnit then return end
    if guid ~= currentGUID then return end   -- not our request

    CancelTimeout()
    local unit = currentUnit
    currentUnit = nil
    currentGUID = nil
    retryCount  = 0

    -- Notify registered callbacks
    for _, fn in ipairs(Inspect.readyCallbacks) do
        pcall(fn, unit)
    end

    self:ProcessQueue()
end

-- Called when an inspect definitively fails (timeout after max retries).
function Inspect:OnFailed(unit)
    for _, fn in ipairs(Inspect.failCallbacks) do
        pcall(fn, unit)
    end
end

-- Registers a function to be called when inspect data is ready.
Inspect.readyCallbacks = {}
function Inspect:OnInspectReady(fn)
    table.insert(self.readyCallbacks, fn)
end

-- Registers a function to be called when an inspect fails.
Inspect.failCallbacks = {}
function Inspect:OnInspectFailed(fn)
    table.insert(self.failCallbacks, fn)
end

---------------------------------------------------------------------------
-- Event wiring (set up after our addon loads, works for any Blizzard version)
---------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("INSPECT_READY")
eventFrame:SetScript("OnEvent", function(_, event, guid)
    if event == "INSPECT_READY" then
        Inspect:OnReady(guid)
    end
end)
