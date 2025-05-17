-- Debug configuration
local Debug = {
    enabled = false,      -- Set to true to enable debugging, false to disable
    level = 3,           -- Debug levels: 0 = OFF, 1 = ERROR, 2 = WARNING, 3 = INFO, 4 = DEBUG
    prefix = "[BalloonAnim]", -- Prefix for all debug messages from this file
    lastPrintedMessageSignature = nil, -- Stores signature of the last message actually printed

    Log = function(self, level, message) -- Add self as first parameter
        if not self.enabled or level > self.level then -- Use self.enabled and self.level
            return
        end
        
        local currentSignature = level .. "::" .. tostring(message)
        if currentSignature == self.lastPrintedMessageSignature then
            return -- Suppress identical consecutive message
        end

        local levelStr = ({"[OFF]", "[ERROR]", "[WARNING]", "[INFO]", "[DEBUG]"})[level + 1]
        print(self.prefix .. " " .. levelStr .. " " .. tostring(message)) -- Use self.prefix
        self.lastPrintedMessageSignature = currentSignature
    end,

    ResetSuppression = function(self)
        self.lastPrintedMessageSignature = nil
        -- Temporarily enable and set level high to ensure this message prints, then restore
        local originalEnabled = self.enabled
        local originalLevel = self.level
        self.enabled = true
        self.level = 4 
        self:Log(4, "Debug message suppression reset.")
        self.enabled = originalEnabled
        self.level = originalLevel
    end
}

local activePilot = true
local currentAnim
local rope = nil
local isDrivingBalloon = false

-- Animation definitions
local animations = {
    captain = {
        idle = {
            dict = "script_story@gng2@ig@ig_2_balloon_control",
            name = "idle_burner_line_arthur",
            flags = 17
        },
        pulling = {
            dict = "script_story@gng2@ig@ig_2_balloon_control",
            name = "base_burner_pull_arthur",
            flags = 17
        }
    },
    passenger = {
        idle = {
            dict = "script_amb@prop_human_seat_chair@female@proper@base",
            name = "base",
            flags = 1
        }
    }
}

local function isPlayingAnim(ped, anim)
    if not anim or not anim.dict or not anim.name then
        Debug:Log(1, "isPlayingAnim: Invalid animation data provided.")
        return false
    end
	return IsEntityPlayingAnim(ped, anim.dict, anim.name, anim.flags)
end

local function playAnim(ped, anim)
    if not anim or not anim.dict or not anim.name then
        Debug:Log(1, "playAnim: Invalid animation data provided.")
        return
    end
	if not DoesAnimDictExist(anim.dict) then
        Debug:Log(1, "playAnim: Animation dictionary '" .. anim.dict .. "' does not exist.")
		return
	end

    Debug:Log(4, "playAnim: Requesting anim dict: " .. anim.dict)
	RequestAnimDict(anim.dict)

    local timeout = GetGameTimer() + 5000 -- 5 seconds timeout
	while not HasAnimDictLoaded(anim.dict) do
		Citizen.Wait(0)
        if GetGameTimer() > timeout then
            Debug:Log(1, "playAnim: Timeout loading anim dict: " .. anim.dict)
            RemoveAnimDict(anim.dict) -- Clean up
            return
        end
	end
    Debug:Log(4, "playAnim: Anim dict '" .. anim.dict .. "' loaded. Playing anim: " .. anim.name)
	TaskPlayAnim(ped, anim.dict, anim.name, 1.0, 1.0, -1, anim.flags, 0.0, false, 0, false, "", false)
    -- It's generally better to remove the anim dict when it's no longer needed, 
    -- but TaskPlayAnim might still need it. If issues arise, consider removing it after a delay or when anim stops.
	-- RemoveAnimDict(anim.dict) 
end

local function stopAnim(ped, anim)
    if not anim or not anim.dict or not anim.name then
        Debug:Log(1, "stopAnim: Invalid animation data provided.")
        return
    end
    Debug:Log(4, "stopAnim: Stopping animation '" .. anim.name .. "' from dict '" .. anim.dict .. "'.")
	StopAnimTask(ped, anim.dict, anim.name, 1.0)
    RemoveAnimDict(anim.dict) -- Clean up anim dict after stopping
end

AddEventHandler("onResourceStop", function(resourceName)
	if GetCurrentResourceName() == resourceName then
        Debug:Log(3, "Resource " .. resourceName .. " stopping (animations).")
		if currentAnim then
            Debug:Log(3, "Stopping current animation due to resource stop.")
			stopAnim(PlayerPedId(), currentAnim)
            currentAnim = nil
		end
        
        -- Make sure rope is cleaned up
        if rope then
            DeleteRope(rope)
            rope = nil
        end
	end
end)

-- Play appropriate animation based on role
Citizen.CreateThread(function()
    Debug:Log(3, "Starting animation control thread.")
    while true do
        local canWait = true
        local playerPed = PlayerPedId()
        local playerRole = exports['poggy-balloon']:GetPlayerBalloonRole()

        if playerRole then
            canWait = false
            Debug:Log(4, "Player role for animation: " .. playerRole)
            if playerRole == "captain" then
                -- Restore original captain animations with rope pull based on controls
                local veh = GetVehiclePedIsIn(playerPed)
                if veh ~= 0 and GetEntityModel(veh) == GetHashKey('hotairballoon01') then
                    -- Check if player is pressing ascend control (restore original behavior)
                    local ropePull
                    if IsControlPressed(0, 0x7232BAB3) then -- INPUT_VEH_FLY_THROTTLE_UP
                        ropePull = "base_burner_pull_arthur"
                        Debug:Log(4, "Captain is pulling rope")
                    else
                        ropePull = "idle_burner_line_arthur"
                    end
                    
                    local newAnim = {
                        dict = "script_story@gng2@ig@ig_2_balloon_control",
                        name = ropePull,
                        flags = 17
                    }
                    
                    if not currentAnim or currentAnim.name ~= newAnim.name then
                        if currentAnim then stopAnim(playerPed, currentAnim) end
                        currentAnim = newAnim
                        Debug:Log(4, "Captain: Playing animation " .. currentAnim.name)
                        playAnim(playerPed, currentAnim)
                    elseif not isPlayingAnim(playerPed, currentAnim) then
                        Debug:Log(4, "Captain: Re-playing animation " .. currentAnim.name .. " as it was not playing.")
                        playAnim(playerPed, currentAnim)
                    end
                elseif currentAnim then
                    Debug:Log(4, "Captain not in balloon, stopping animation.")
                    stopAnim(playerPed, currentAnim)
                    currentAnim = nil
                end
                activePilot = true
            else -- Passenger
                activePilot = false -- Ensure passengers don't trigger captain-specific logic if any remains
                local newAnim = animations.passenger.idle
                if not currentAnim or currentAnim.name ~= newAnim.name then
                    if currentAnim then stopAnim(playerPed, currentAnim) end
                    currentAnim = newAnim
                    Debug:Log(4, "Passenger: Playing animation " .. currentAnim.name)
                    playAnim(playerPed, currentAnim)
                elseif not isPlayingAnim(playerPed, currentAnim) then
                     Debug:Log(4, "Passenger: Re-playing animation " .. currentAnim.name .. " as it was not playing.")
                    playAnim(playerPed, currentAnim)
                end
            end
        elseif currentAnim then
            Debug:Log(4, "No player role, stopping current animation: " .. currentAnim.name)
            stopAnim(playerPed, currentAnim)
            currentAnim = nil
        end

        Citizen.Wait(canWait and 1000 or 50) 
    end
end)

-- Rope for captain only - restore original behavior
Citizen.CreateThread(function()
    Debug:Log(3, "Starting rope management thread.")
    while true do
        Citizen.Wait(1000)  -- Check every second

        local playerPed = PlayerPedId()
        local playerRole = exports['poggy-balloon']:GetPlayerBalloonRole()
        local vehicle = GetVehiclePedIsIn(playerPed, false)
        
        if playerRole == "captain" and vehicle ~= 0 and GetEntityModel(vehicle) == GetHashKey('hotairballoon01') then
            if not isDrivingBalloon then
                -- The player started driving the balloon, so create the rope
                local playerCoords = GetEntityCoords(playerPed)
                local ropeLength = 0.7  -- Adjust this value for desired rope length

                -- Create the rope
                Debug:Log(3, "Creating rope for captain")
                rope = AddRope(playerCoords.x, playerCoords.y, playerCoords.z, 0.0, 0.0, 0.0, 
                               ropeLength, 7, ropeLength, ropeLength, ropeLength, false, false, false, 
                               1.0, false, 0)

                -- Attach rope ends to the player and the balloon
                if rope and rope ~= 0 then
                    AttachEntitiesToRope(rope, playerPed, vehicle, 
                                        0.0, 0.05, 0.05, -0.2, 0.0, 0.0, 
                                        ropeLength, 0, 0, 
                                        "PH_L_HAND", "engine", 0, 
                                        -1, -1, 0, 0, 1, 1)
                    Debug:Log(3, "Rope attached between captain and balloon")
                else
                    Debug:Log(2, "Failed to create rope")
                end

                isDrivingBalloon = true
            end
        else
            if isDrivingBalloon then
                -- The player stopped driving the balloon, so delete the rope
                Debug:Log(3, "Player is not captain or not in balloon, deleting rope")
                if rope and rope ~= 0 then
                    DeleteRope(rope)
                    rope = nil
                end
                isDrivingBalloon = false
            end
        end
    end
end)

RegisterCommand("balloon_debug_anim", function(source, args, rawCommand)
    local cmd = args[1]
    if cmd == "level" then
        local newLevel = tonumber(args[2])
        if newLevel and newLevel >= 0 and newLevel <= 4 then
            Debug.level = newLevel
            Debug:ResetSuppression()
            Debug:Log(3, "Animation Debug level set to: " .. newLevel)
        else
            Debug:Log(2, "Usage: /balloon_debug_anim level [0-4]")
        end
    elseif cmd == "toggle" then
        Debug.enabled = not Debug.enabled
        Debug:ResetSuppression()
        -- Log outside of the normal flow if disabling, so it's always visible
        if Debug.enabled then
            Debug:Log(3, "Animation Debugging ENABLED")
        else
            print(Debug.prefix .. " [INFO] Animation Debugging DISABLED")
            Debug.lastPrintedMessageSignature = nil -- Ensure next log prints if re-enabled
        end
    else
        Debug:Log(2, "Usage: /balloon_debug_anim [level|toggle]")
    end
end, false)

Debug:Log(3, "Balloon animations script initialized. Debug Level: " .. Debug.level .. ", Enabled: " .. tostring(Debug.enabled))
