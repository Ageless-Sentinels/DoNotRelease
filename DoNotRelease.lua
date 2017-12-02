local addonName = ...
local addon = LibStub("AceAddon-3.0"):NewAddon(addonName, "AceComm-3.0", "AceHook-3.0", "AceConsole-3.0")

local DNR_CHECK_DELAY = 5 -- Amount of seconds to wait for replies. 

local isDNRActive = false
local raidList = {}

local function ResetDNR()
    isDNRActive = false
    addon:Print("DNR Reset:", isDNRActive)
end

local function ToggleDNR(prefix, text)
    addon:Print(prefix, text)
    if text and text == "reset" then 
        ResetDNR()
    elseif text and text == "request" then
        addon:BroadcastDNR(isDNRActive)
    else
        isDNRActive = true
    end
    addon:Print("DNR Status:", isDNRActive)
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
    addon:Print(prefix, text, dist, from)
    if text == "check" then
        if not from then addon:Printf("Error: Target is not valid") end -- This line should never be hit
        addon:Printf("Received Check Request From %s, Sending back whisper with version %s", from, version)
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
        end
    end
    if numWrongVer == 0 then
        addon:Print("Everyone is good to go.")
    end
end

function addon:OnInitialize()
	self:RegisterChatCommand("dnr", "ChatCommand")
end

function addon:ChatCommand(input)
    if IsInRaid() then
        if UnitIsGroupLeader("player") or UnitIsRaidOfficer("player") then
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
    
    if IsInRaid() then
        local raidLead = GetRaidRosterInfo(1)
        self:SendCommMessage("DNR_Toggle", "request", "WHISPER", raidLead)
    end
end

function addon:DialogOnUpdateHook(dialog)
    local isInstance, instanceType = IsInInstance()
    if IsInRaid() and instanceType == "raid" and isDNRActive then
        dialog.button1:Disable()
        dialog.text:SetText("DO NOT RELEASE! DO NOT RELEASE!")
    end
end