-- Debug configuration
local Debug = {
    enabled = false,      -- Set to true to enable debugging, false to disable
    level = 3,           -- Debug levels: 0 = OFF, 1 = ERROR, 2 = WARNING, 3 = INFO, 4 = DEBUG
    prefix = "[BalloonCtrl]", -- Prefix for all debug messages from this file
    lastPrintedMessageSignature = nil,

    Log = function(self, level, message) -- Add self
        if not self.enabled or level > self.level then -- Use self
            return
        end
        
        local currentSignature = level .. "::" .. tostring(message)
        if currentSignature == self.lastPrintedMessageSignature then
            return -- Suppress identical consecutive message
        end

        local levelStr = ({"[OFF]", "[ERROR]", "[WARNING]", "[INFO]", "[DEBUG]"})[level + 1]
        print(self.prefix .. " " .. levelStr .. " " .. tostring(message)) -- Use self
        self.lastPrintedMessageSignature = currentSignature
    end,

    ResetSuppression = function(self)
        self.lastPrintedMessageSignature = nil
        local originalEnabled = self.enabled
        local originalLevel = self.level
        self.enabled = true
        self.level = 4
        self:Log(4, "Debug message suppression reset.")
        self.enabled = originalEnabled
        self.level = originalLevel
    end
}

local balloon
local lockZ = false
local useCameraRelativeControls = true -- Set to false to revert to original NSEW controls

local balloonPrompts = UipromptGroup:new("Balloon")

local nsPrompt = Uiprompt:new({`INPUT_VEH_MOVE_UP_ONLY`, `INPUT_VEH_MOVE_DOWN_ONLY`}, "Forward/Back", balloonPrompts)
local wePrompt = Uiprompt:new({`INPUT_VEH_MOVE_LEFT_ONLY`, `INPUT_VEH_MOVE_RIGHT_ONLY`}, "Left/Right", balloonPrompts)
local boostPrompt = Uiprompt:new(`INPUT_CONTEXT_B`, "Boost", balloonPrompts) 
local brakePrompt = Uiprompt:new(`INPUT_CONTEXT_X`, "Brake", balloonPrompts)
local lockZPrompt = Uiprompt:new(`INPUT_CONTEXT_A`, "Lock Altitude", balloonPrompts)
local throttlePrompt = Uiprompt:new(`INPUT_VEH_FLY_THROTTLE_UP`, "Ascend", balloonPrompts)
local controlModePrompt = Uiprompt:new(`INPUT_FRONTEND_Y`, "Toggle Control Mode", balloonPrompts)

-- Function to calculate direction vectors based on camera heading
local function GetCameraRelativeVectors()
    local camRot = GetGameplayCamRot(2)
    local camHeading = math.rad(camRot.z) -- Convert heading to radians
    
    -- Create unit vectors for forward and right directions based on camera
    local forwardVector = vector3(
        -math.sin(camHeading), -- X
        math.cos(camHeading),  -- Y
        0.0                    -- Z
    )
    
    local rightVector = vector3(
        math.cos(camHeading),  -- X
        math.sin(camHeading),  -- Y
        0.0                    -- Z
    )
    
    return forwardVector, rightVector
end

-- Function to toggle control mode
local function ToggleControlMode()
    useCameraRelativeControls = not useCameraRelativeControls
    Debug:Log(3, "Control mode switched to: " .. (useCameraRelativeControls and "Camera Relative" or "World NSEW"))
    
    -- Update prompt text to reflect current control mode
    if useCameraRelativeControls then
        nsPrompt:setText("Forward/Back")
        wePrompt:setText("Left/Right")
    else
        nsPrompt:setText("North/South")
        wePrompt:setText("West/East")
    end
    
    -- Display notification to player
    local modeText = useCameraRelativeControls and "Camera Relative" or "World NSEW"
    Citizen.InvokeNative(0x202709F4C58A0424, CreateVarString(10, "LITERAL_STRING", "Control Mode: " .. modeText), true, false)
end

--- detect if player is in a balloon as captain
Citizen.CreateThread(function()
    Debug:Log(3, "Starting captain detection thread for controls.")
	while true do
		local playerPed = PlayerPedId()
		local playerRole = exports[GetCurrentResourceName()]:GetPlayerBalloonRole()
		local isCaptain = playerRole == "captain"
		local vehiclePedIsIn = nil
		
		if isCaptain then
            Debug:Log(4, "Player role is captain, checking vehicle.")
			vehiclePedIsIn = GetVehiclePedIsIn(playerPed, false)
			if vehiclePedIsIn ~= 0 and GetEntityModel(vehiclePedIsIn) == `hotairballoon01` then
                Debug:Log(4, "Player is captain and in balloon ID: " .. vehiclePedIsIn)
			else
                Debug:Log(4, "Player is captain but not in a balloon vehicle.")
				vehiclePedIsIn = nil -- Ensure it's nil if not in the correct vehicle
            end
		end

		if not balloon and vehiclePedIsIn and isCaptain then
			balloon = vehiclePedIsIn
			LockMinimapAngle(1)
            Debug:Log(3, "Balloon controls activated for vehicle: " .. balloon)
		elseif balloon and (not vehiclePedIsIn or not isCaptain) then
            Debug:Log(3, "Deactivating balloon controls. Current balloon: " .. tostring(balloon) .. ", New Vehicle: " .. tostring(vehiclePedIsIn) .. ", IsCaptain: " .. tostring(isCaptain))
			balloon = nil
			UnlockMinimapAngle()
		end

		Citizen.Wait(500)
	end
end)

--- vehicle controls (only for captain)
Citizen.CreateThread(function()
    Debug:Log(3, "Starting vehicle control thread.")
    local bv

    while true do
        if balloon then
            local playerRole = exports[GetCurrentResourceName()]:GetPlayerBalloonRole()
            
            if playerRole == "captain" then
                Debug:Log(4, "Captain controls active for balloon: " .. balloon)
                balloonPrompts:handleEvents()
                
                -- Check for control mode toggle
                if IsControlJustPressed(0, `INPUT_FRONTEND_Y`) then
                    ToggleControlMode()
                end

                local speed
                if IsControlPressed(0, `INPUT_CONTEXT_B`) then
                    speed = 0.15
                else
                    speed = 0.05
                end

                local v1 = GetEntityVelocity(balloon)
                local v2 = v1
                
                if useCameraRelativeControls then
                    -- Camera-relative controls
                    local forwardVec, rightVec = GetCameraRelativeVectors()
                    
                    -- Forward/Back (based on camera)
                    if IsControlPressed(0, `INPUT_VEH_MOVE_UP_ONLY`) then -- Forward
                        v2 = v2 + forwardVec * speed
                        Debug:Log(4, "Control: Move Camera Forward")
                    end
                    
                    if IsControlPressed(0, `INPUT_VEH_MOVE_DOWN_ONLY`) then -- Back
                        v2 = v2 - forwardVec * speed
                        Debug:Log(4, "Control: Move Camera Back")
                    end
                    
                    -- Left/Right (based on camera)
                    if IsControlPressed(0, `INPUT_VEH_MOVE_LEFT_ONLY`) then -- Left
                        v2 = v2 - rightVec * speed
                        Debug:Log(4, "Control: Move Camera Left")
                    end
                    
                    if IsControlPressed(0, `INPUT_VEH_MOVE_RIGHT_ONLY`) then -- Right
                        v2 = v2 + rightVec * speed
                        Debug:Log(4, "Control: Move Camera Right")
                    end
                else
                    -- Original world-relative controls (NSEW)
                    if IsControlPressed(0, `INPUT_VEH_MOVE_UP_ONLY`) then -- North
                        v2 = v2 + vector3(0, speed, 0)
                        Debug:Log(4, "Control: Move North")
                    end
                    
                    if IsControlPressed(0, `INPUT_VEH_MOVE_DOWN_ONLY`) then -- South
                        v2 = v2 - vector3(0, speed, 0)
                        Debug:Log(4, "Control: Move South")
                    end
                    
                    if IsControlPressed(0, `INPUT_VEH_MOVE_LEFT_ONLY`) then -- West
                        v2 = v2 - vector3(speed, 0, 0)
                        Debug:Log(4, "Control: Move West")
                    end
                    
                    if IsControlPressed(0, `INPUT_VEH_MOVE_RIGHT_ONLY`) then -- East
                        v2 = v2 + vector3(speed, 0, 0)
                        Debug:Log(4, "Control: Move East")
                    end
                end

                if IsControlPressed(0, `INPUT_CONTEXT_X`) then
                    Debug:Log(4, "Control: Brake")
                    if bv then
                        local x = bv.x > 0 and bv.x - speed or bv.x + speed
                        local y = bv.y > 0 and bv.y - speed or bv.y + speed
                        v2 = vector3(x, y, v2.z)
                    end
                    bv = v2.xy
                else
                    if bv then
                        bv = nil
                    end
                end

                if IsControlJustPressed(0, `INPUT_CONTEXT_A`) then
                    lockZ = not lockZ
                    Debug:Log(3, "Control: Altitude Lock toggled to: " .. tostring(lockZ))

                    if lockZ then
                        lockZPrompt:setText("Unlock Altitude")
                    else
                        lockZPrompt:setText("Lock Altitude")
                    end
                end

                if lockZ and not IsControlPressed(0, `INPUT_VEH_FLY_THROTTLE_UP`) then
                    SetEntityVelocity(balloon, vector3(v2.x, v2.y, 0.0))
                    Debug:Log(4, "Altitude locked, setting Z velocity to 0. New velocity: X=" .. v2.x .. " Y=" .. v2.y .. " Z=0")
                elseif v2 ~= v1 then
                    SetEntityVelocity(balloon, v2)
                    Debug:Log(4, "Setting new velocity: X=" .. v2.x .. " Y=" .. v2.y .. " Z=" .. v2.z)
                end
            end

            Citizen.Wait(0)
        else
            Citizen.Wait(500)
        end
    end
end)

-- Initialize the prompts when resource starts
Citizen.CreateThread(function()
    Wait(1000) -- Small delay to ensure everything is loaded
    
    -- Register and setup the control mode toggle prompt
    controlModePrompt:setEnabled(true)
    
    -- Set initial prompt texts based on default control mode
    if useCameraRelativeControls then
        nsPrompt:setText("Forward/Back")
        wePrompt:setText("Left/Right")
    else
        nsPrompt:setText("North/South")
        wePrompt:setText("West/East")
    end
end)

RegisterCommand("balloon_debug_ctrl", function(source, args, rawCommand)
    local cmd = args[1]
    if cmd == "level" then
        local newLevel = tonumber(args[2])
        if newLevel and newLevel >= 0 and newLevel <= 4 then
            Debug.level = newLevel
            Debug:ResetSuppression()
            Debug:Log(3, "Controls Debug level set to: " .. newLevel)
        else
            Debug:Log(2, "Usage: /balloon_debug_ctrl level [0-4]")
        end
    elseif cmd == "toggle" then
        Debug.enabled = not Debug.enabled
        Debug:ResetSuppression()
        if Debug.enabled then
            Debug:Log(3, "Controls Debugging ENABLED")
        else
            print(Debug.prefix .. " [INFO] Controls Debugging DISABLED")
            Debug.lastPrintedMessageSignature = nil
        end
    else
        Debug:Log(2, "Usage: /balloon_debug_ctrl [level|toggle]")
    end
end, false)

Debug:Log(3, "Balloon controls script initialized. Debug Level: " .. Debug.level .. ", Enabled: " .. tostring(Debug.enabled))
