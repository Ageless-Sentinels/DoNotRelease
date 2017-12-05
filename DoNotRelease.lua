local addonName = ...
local addon = LibStub("AceAddon-3.0"):NewAddon(addonName, "AceComm-3.0", "AceHook-3.0", "AceConsole-3.0")

--testing webhook

-- Constants
local ONLY_SHOW_STATUS_WHEN_ACTIVE = false
local DNR_CHECK_DELAY = 5 -- Amount of seconds to wait for replies. 
local DNR_STATUS_WIDTH = 150
local DNR_STATUS_HEIGHT = 24
local DNR_STATUS_FONTSIZE = 13
local DNR_DEBUG = true

-- Local variables
local isDNRActive = false
local raidList = {}

-- Cached globals
local GetNumGroupMembers = GetNumGroupMembers
local GetRaidRosterInfo = GetRaidRosterInfo
local UnitIsGroupLeader = UnitIsGroupLeader
local UnitIsRaidOfficer = UnitIsRaidOfficer
local GetAddOnMetadata = GetAddOnMetadata
local IsInInstance = IsInInstance
local CreateFrame = CreateFrame
local IsInRaid = IsInRaid
local strsub = strsub
local pairs = pairs

-- Returns true while in a raid group, inside a raid instance.
local function IsAddonActive()
    local isInstance, instanceType = IsInInstance()
    if IsInRaid() and instanceType == "raid" then
        return true
    elseif DNR_DEBUG then
        return true
    end
    return false
end

-- Update the status frame whenever we toggle DNR
local function UpdateDNRStatus()
    if DNRStatusFrame then 
        DNRStatusFrame:SetFormattedText("DNR Status: %s", isDNRActive and "true" or "false")
        -- Special setting that will make the frame show up when active
        if ONLY_SHOW_STATUS_WHEN_ACTIVE then
            if isDNRActive then 
                DNRStatusFrame:Show()
            else
                DNRStatusFrame:Hide()
            end
        end
    else
        -- The setting would also make /dnr status do nothing appear to do nothing most of the time
        -- so just make the frame when it turns active if it doesnt exists.
        if ONLY_SHOW_STATUS_WHEN_ACTIVE and isDNRActive then
            addon:ToggleStatusFrame()
        end 
    end
end

local function ResetDNR()
    isDNRActive = false
    UpdateDNRStatus()
end

local function ToggleDNR(prefix, text)
    if text and text == "reset" then 
        ResetDNR()
    elseif text and text == "request" then
        addon:BroadcastDNR(isDNRActive)
    else
        isDNRActive = true
    end
    UpdateDNRStatus()
end

-- Function will send a DNR value to everyone in the raid.
-- state (bool) - the value to be sent.
function addon:BroadcastDNR(state)
    if state then
        self:SendCommMessage("DNR_Toggle", "active", "RAID")
    else
        self:SendCommMessage("DNR_Toggle", "reset", "RAID")
    end
end

-- This handles the communication over DNR_Check
function addon:DNRComms(prefix, text, dist, from)
    local version = GetAddOnMetadata(addonName, "Version")
    --addon:Print(prefix, text, dist, from)
    if text == "check" then
        if not from then addon:Printf("Error: Target is not valid") end -- This line should never be hit
        --addon:Printf("Received Check Request From %s, Sending back whisper with version %s", from, version)
        self:SendCommMessage("DNR_Check", version, "WHISPER", from)
    else
        -- Strsub is used to get rid of the "1." from verison number. We're only interested in comparing version minors. 
        local minVer = strsub(text, 3)
        if strsub(version, 3) > minVer then
            raidList[from] = minVer
        else
            raidList[from] = true
        end
    end
end

-- This function is called shortly after calling for a DNR Check to display the results.
function addon:CheckRaidList()
    local numWrongVer = 0
    for name, result in pairs(raidList) do
        -- If you never receive a whisper back, result will remain unchanged
        if result == false then
            addon:Print(name, "does not have DoNotRelease installed")
            numWrongVer = numWrongVer + 1
        --If someone has an outdated version, result will have changed to their version.
        elseif result ~= true then
            addon:Print(name, "is using old version:", result)
            numWrongVer = numWrongVer + 1
        end
    end
    if numWrongVer == 0 then
        addon:Print("Everyone is good to go.")
    end
end

function addon:ToggleStatusFrame()
    if not DNRStatusFrame then
        local frame = CreateFrame("Button", "DNRStatusFrame", UIParent)
        frame:SetBackdrop({
                bgFile = "Interface/Tooltips/UI-Tooltip-Background", 
                tile = 0, tileSize = 0, edgeSize = 3, 
                insets = { left = 2, right = 2, top = 2, bottom = 2 }
        })
        frame:SetBackdropColor(0,0,0,0.4)
        frame:SetBackdropBorderColor(0,0,0,0.8)
        frame:SetWidth(DNR_STATUS_WIDTH)
        frame:SetHeight(DNR_STATUS_HEIGHT)
        frame:SetFrameStrata("DIALOG")
        frame:EnableMouse(true)
        frame:SetMovable(true)
        frame:RegisterForDrag("LeftButton")
        
        frame:SetPoint(DoNotReleaseDB.point, UIParent, DoNotReleaseDB.relativePoint, DoNotReleaseDB.x, DoNotReleaseDB.y)
        frame:Show()

        UpdateDNRStatus()
        frame:GetFontString():SetFont("Fonts\\FRIZQT__.TTF", DNR_STATUS_FONTSIZE, "OUTLINE")

        frame:SetScript("OnDragStart", function(self)
            if not DoNotReleaseDB.lock then
                self:StartMoving()
            end
        end)
        frame:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            point, _, relativePoint, x, y = self:GetPoint(1)
            DoNotReleaseDB.point = point
            DoNotReleaseDB.relativePoint = relativePoint
            DoNotReleaseDB.x = x
            DoNotReleaseDB.y = y
        end)

    else
        if DNRStatusFrame:IsShown() then
            DNRStatusFrame:Hide()
        else
            DNRStatusFrame:Show()
        end
    end
end

function addon:OnInitialize()
    self:RegisterChatCommand("dnr", "ChatCommand")
    
    -- Initialize SavedVariable, if we start having customization options, we'll switch to AceDB
    -- This is just so we don't have to drag the frame where we want every time. 
    if DoNotReleaseDB == nil then
        DoNotReleaseDB = { x = 0, y = 0, point = "CENTER", relativePoint = "CENTER", lock = false }
    end
end

-- Chat Command: /dnr
-- Only works while in raid and inside a raid instance, for raid leader or assists. 
-- /dnr        - will broadcast for the raid not to release.
-- /dnr reset  - will reset the DNR flag for everyone in the raid
-- /dnr check  - will initiate a check to see who in the raid has the addon.
-- /dnr status - will show a little frame with the current DNR status. (Does not requires raid lead/assist)
-- /dnr lock   - will lock the frame in place.
function addon:ChatCommand(input)
    if IsAddonActive() then
        if input == "status" then addon:ToggleStatusFrame()
        elseif input == "lock" then DoNotReleaseDB.lock = not DoNotReleaseDB
        elseif UnitIsGroupLeader("player") or UnitIsRaidOfficer("player") then
            if input == "check" then
                addon:Print("Checking Raid")
                for i = 1, GetNumGroupMembers() do
                    local name = GetRaidRosterInfo(i)
                    raidList[name] = false
                end
                self:SendCommMessage("DNR_Check", "check", "RAID")
                C_Timer.After(DNR_CHECK_DELAY, addon.CheckRaidList)
            elseif input == "reset" then
                addon:BroadcastDNR(false)
            else
                addon:BroadcastDNR(true)
            end
        end
    end
end

function addon:OnEnable()
    self:SecureHook(StaticPopupDialogs["DEATH"], "OnUpdate", "DialogOnUpdateHook")
    self:RegisterComm("DNR_Toggle", ToggleDNR)
    self:RegisterComm("DNR_Check", "DNRComms")

    -- Make sure it doesn't stay on across attempts or when inappropriate
    self:SecureHook("RepopMe", ResetDNR)
    self:SecureHook("UseSoulstone", ResetDNR)
    self:SecureHook("AcceptResurrect", ResetDNR)
    
    --If you disconnect or reload UI during an encounter, make sure to get an status update from the raid leader.
    if IsAddonActive() and IsInRaid() then
        -- Make sure to not request a status update from yourself, fetch it from a raid assist
        if UnitIsGroupLeader("player") then
            for i = 2, GetNumGroupMembers() do
                local name, rank = GetRaidRosterInfo(i)
                if rank == 1 then
                    self:SendCommMessage("DNR_Toggle", "request", "WHISPER", name)
                    break
                end
            end
        else
            -- First index of the Raid roster is always the raid leader. 
            local name = GetRaidRosterInfo(1)
            self:SendCommMessage("DNR_Toggle", "request", "WHISPER", name)
        end
    end
end

function addon:DialogOnUpdateHook(dialog)
    if IsAddonActive() and isDNRActive then
        dialog.button1:Disable()
        dialog.text:SetText("DO NOT RELEASE! DO NOT RELEASE!")
    end
end