-- Debug configuration
local Debug = {
    enabled = false,      -- Set to true to enable debugging, false to disable
    level = 3,           -- Debug levels: 0 = OFF, 1 = ERROR, 2 = WARNING, 3 = INFO, 4 = DEBUG
    prefix = "[BalloonMain]", -- Prefix for all debug messages from this file
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

    DUMP = function(self, tbl, indent) -- Add self
        if not self.enabled or self.level < 4 then return end -- Use self
        indent = indent or 0
        local indentStr = string.rep("  ", indent)
        for k, v in pairs(tbl) do
            local vType = type(v)
            if vType == "table" then
                self:Log(4, indentStr .. k .. " = {") -- DUMP's Log calls will be suppressed if repetitive
                self:DUMP(v, indent + 1) 
                self:Log(4, indentStr .. "}") 
            else
                self:Log(4, indentStr .. k .. " = " .. tostring(v)) 
            end
        end
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

-- To adjust passenger positions:
-- Modify the x, y, z values in the `position` vector for passenger1 and passenger2.
-- x: side-to-side (positive = right of center, negative = left)
-- y: forward/backward (positive = forward of center, negative = backward)
-- z: height (positive = up, negative = down)
local balloonSeats = {
    captain = {
        occupied = false,
        position = vector3(0.0, 0.0, 0.0), -- Not used for attachment, only for occupancy tracking
        occupant = nil -- Will store player server ID
    },
    passenger1 = {
        occupied = false,
        position = vector3(0.5, 0.5, 1.1), -- Front-right
        occupant = nil
    },
    passenger2 = {
        occupied = false,
        position = vector3(-0.5, 0.5, 1.1), -- Front-left
        occupant = nil
    },
    passenger3 = {
        occupied = false,
        position = vector3(0.5, -0.5, 1.1), -- Back-right
        occupant = nil
    },
    passenger4 = {
        occupied = false,
        position = vector3(-0.5, -0.5, 1.1), -- Back-left
        occupant = nil
    }
}

local isNearBalloon = false
local nearestBalloon = nil
local playerRole = nil -- "captain", "passenger1", "passenger2", or nil
local currentBalloonEntity = nil -- Store the balloon entity the player is currently in
local currentBalloonNetId = nil -- Store the network ID of the current balloon

-- Register network events
RegisterNetEvent("balloon:seatConfirmed")
RegisterNetEvent("balloon:seatDenied")
RegisterNetEvent("balloon:seatUpdate")

-- Balloon entry prompts
local promptGroup = GetRandomIntInRange(0, 0xffffff)
local passengerPrompt -- Captain prompt removed

-- Function to create prompts
local function SetupPrompts()
    Debug:Log(3, "Setting up balloon entry prompts")
    -- Captain prompt setup removed

    passengerPrompt = PromptRegisterBegin()
    PromptSetControlAction(passengerPrompt, 0x0522B243) -- F key
    PromptSetText(passengerPrompt, CreateVarString(10, "LITERAL_STRING", "Enter as Passenger"))
    PromptSetEnabled(passengerPrompt, true)
    PromptSetVisible(passengerPrompt, false)
    PromptSetHoldMode(passengerPrompt, true) -- Set to hold mode
    PromptSetStandardMode(passengerPrompt, true)
    PromptSetGroup(passengerPrompt, promptGroup)
    PromptRegisterEnd(passengerPrompt)
    Debug:Log(4, "Passenger prompt registered with control 0x0522B243 (F key), Hold Mode: true")
end

-- Function to find an unoccupied passenger seat
local function GetAvailablePassengerSeat()
    for i = 1, 4 do
        local seatKey = "passenger" .. i
        if balloonSeats[seatKey] and not balloonSeats[seatKey].occupied then
            Debug:Log(4, "Passenger seat " .. i .. " available")
            return seatKey
        end
    end
    Debug:Log(4, "No passenger seats available")
    return nil
end

-- Function to attach player to a specific seat position (NOW ONLY FOR PASSENGERS)
-- This function now only handles the physical attachment. Occupancy state is managed by server.
local function AttachPlayerToSeat(playerId, balloon, seatType)
    Debug:Log(3, "Attempting to place player " .. playerId .. " in passenger seat: " .. seatType .. " on balloon " .. balloon)
    local seatInfo = balloonSeats[seatType]
    if not seatInfo or seatType == "captain" then
        Debug:Log(1, "Invalid seat type or attempt to use for captain: " .. tostring(seatType) .. " for AttachPlayerToSeat")
        return false
    end

    local pos = seatInfo.position
    Debug:Log(4, "Attaching passenger to relative position: X=" .. pos.x .. ", Y=" .. pos.y .. ", Z=" .. pos.z)
    AttachEntityToEntity(playerId, balloon, 0, 
        pos.x, pos.y, pos.z, 
        0.0, 0.0, 0.0, 
        false, false, false, false, 0, true)
    
    -- Store the current balloon for exit functionality
    currentBalloonEntity = balloon
    currentBalloonNetId = NetworkGetNetworkIdFromEntity(balloon)
    Debug:Log(4, "Stored current balloon entity " .. balloon .. " with NetID " .. currentBalloonNetId)
    
    -- seatInfo.occupied and seatInfo.occupant are now set via balloon:seatUpdate
    -- playerRole is set in balloon:seatConfirmed
    Debug:Log(3, "Player " .. playerId .. " physically attached as " .. seatType)
    return true
end

-- Function to detach player from balloon
local function DetachPlayerFromBalloon()
    if playerRole and playerRole:find("passenger") then
        local playerId = PlayerPedId()
        Debug:Log(3, "Detaching passenger " .. playerId .. " from balloon. Current role: " .. playerRole)

        -- Use stored balloon entity/netId rather than relying on nearestBalloon
        local balloonNetId = nil
        if currentBalloonNetId and currentBalloonNetId ~= 0 then
            balloonNetId = currentBalloonNetId
            Debug:Log(4, "Using stored balloon NetID: " .. balloonNetId)
        elseif nearestBalloon and NetworkGetNetworkIdFromEntity(nearestBalloon) ~= 0 then
            balloonNetId = NetworkGetNetworkIdFromEntity(nearestBalloon)
            Debug:Log(4, "Using nearest balloon NetID: " .. balloonNetId)
        else
            Debug:Log(2, "Cannot notify server: No valid balloon entity for role " .. playerRole)
        end
        
        if balloonNetId then
            TriggerServerEvent("balloon:vacateSeat", balloonNetId, playerRole)
        end

        DetachEntity(playerId, true, true)
        Debug:Log(3, "Passenger " .. playerId .. " detached.")
        
        -- Local state cleanup. Server will broadcast the authoritative update.
        if balloonSeats[playerRole] then
            balloonSeats[playerRole].occupied = false -- Locally mark as unoccupied
            balloonSeats[playerRole].occupant = nil
        end
        local exitedRole = playerRole
        playerRole = nil -- Clear role after detaching
        
        -- Clear the current balloon references
        currentBalloonEntity = nil
        currentBalloonNetId = nil
        
        TriggerEvent("balloon:exited", exitedRole) 
    elseif playerRole == "captain" then
        Debug:Log(2, "DetachPlayerFromBalloon called for captain - this should be handled by game exit. Clearing role.")
        -- Captain exit is handled by game, this function should ideally not be called for captain.
        -- If it is, just clean up internal state.
        if balloonSeats.captain then
            balloonSeats.captain.occupied = false
            balloonSeats.captain.occupant = nil
        end
        local exitedRole = playerRole
        playerRole = nil
        TriggerEvent("balloon:exited", exitedRole)
    else
        Debug:Log(2, "Attempted to detach player but playerRole is nil or not passenger.")
    end
end

-- Thread to monitor if player is captain (driver) of a balloon
Citizen.CreateThread(function()
    Debug:Log(3, "Starting captain state monitoring thread.")
    local lastKnownVehicle = 0
    while true do
        Citizen.Wait(250) -- Check periodically
        local playerPed = PlayerPedId()
        local currentVehicle = GetVehiclePedIsIn(playerPed, false)

        if currentVehicle ~= 0 and GetEntityModel(currentVehicle) == GetHashKey('hotairballoon01') and GetPedInVehicleSeat(currentVehicle, -1) == playerPed then
            if playerRole ~= "captain" then
                Debug:Log(3, "Player detected as captain of balloon " .. currentVehicle)
                if playerRole and playerRole:find("passenger") then 
                    if balloonSeats[playerRole] then -- Clear previous passenger state
                        balloonSeats[playerRole].occupied = false
                        balloonSeats[playerRole].occupant = nil
                    end
                    DetachEntity(playerPed, true, true) -- Detach from passenger seat
                end
                playerRole = "captain"
                -- balloonSeats.captain.occupied and occupant will be set by server update
                nearestBalloon = currentVehicle 
                TriggerServerEvent("balloon:captainEntered", NetworkGetNetworkIdFromEntity(currentVehicle), GetPlayerServerId(PlayerId()))
                TriggerEvent("balloon:enteredAsCaptain")
            end
            lastKnownVehicle = currentVehicle
        elseif playerRole == "captain" then
            Debug:Log(3, "Player no longer detected as captain.")
            -- balloonSeats.captain.occupied and occupant will be cleared by server update
            playerRole = nil
            if lastKnownVehicle ~= 0 and NetworkGetNetworkIdFromEntity(lastKnownVehicle) ~= 0 then
                 TriggerServerEvent("balloon:captainExited", NetworkGetNetworkIdFromEntity(lastKnownVehicle), GetPlayerServerId(PlayerId()))
            end
            TriggerEvent("balloon:exited", "captain")
            lastKnownVehicle = 0
        end
    end
end)


-- Check for nearby balloons and show prompts
Citizen.CreateThread(function()
    Debug:Log(3, "Starting balloon proximity detection thread.")
    SetupPrompts()
    
    while true do
        local playerPed = PlayerPedId()
        local playerCoords = GetEntityCoords(playerPed)
        local foundBalloonThisTick = false
        
        if not playerRole then
            Debug:Log(4, "Player not in balloon, checking for nearby balloons.")
            local balloonHash = GetHashKey('hotairballoon01')
            local vehicles = GetGamePool('CVehicle')
            Debug:Log(4, "Found " .. #vehicles .. " vehicles in pool. Searching for model hash: " .. balloonHash)
            
            for _, vehicle in ipairs(vehicles) do
                if GetEntityModel(vehicle) == balloonHash then
                    local balloonCoords = GetEntityCoords(vehicle)
                    local distance = #(playerCoords - balloonCoords)
                    Debug:Log(4, "Found balloon (ID: " .. vehicle .. ") at distance: " .. distance)
                    
                    if distance < 5.0 then
                        foundBalloonThisTick = true
                        nearestBalloon = vehicle
                        Debug:Log(4, "Player is near balloon " .. vehicle .. " (distance: " .. distance .. ")")
                        
                        if distance < 2.5 then
                            Debug:Log(4, "Player within interaction distance (2.5m).")
                            -- Captain seat availability is now based on the monitoring thread
                            local captainSeatOccupiedByGame = balloonSeats.captain.occupied 
                            local passengerSeatKey = GetAvailablePassengerSeat()
                            local passengerSeatAvailable = passengerSeatKey ~= nil

                            Debug:Log(4, "Captain seat occupied (by game): " .. tostring(captainSeatOccupiedByGame))
                            Debug:Log(4, "Passenger seat available: " .. tostring(passengerSeatAvailable))

                            -- Captain prompt visibility removed
                            PromptSetVisible(passengerPrompt, passengerSeatAvailable)
                            
                            if passengerSeatAvailable then -- Only show group if passenger prompt is visible
                                local promptText = CreateVarString(10, "LITERAL_STRING", "Hot Air Balloon")
                                PromptSetActiveGroupThisFrame(promptGroup, promptText)
                                Debug:Log(4, "Displaying passenger prompt.")
                            end
                            
                            -- Captain prompt hold check removed
                            
                            if PromptHasHoldModeCompleted(passengerPrompt) then
                                Debug:Log(3, "Passenger prompt (F) hold completed.")
                                local seatToOccupy = GetAvailablePassengerSeat() 
                                if seatToOccupy and nearestBalloon then
                                    Debug:Log(3, "Requesting to enter as passenger in seat: " .. seatToOccupy)
                                    local balloonNetId = NetworkGetNetworkIdFromEntity(nearestBalloon)
                                    if balloonNetId ~= 0 then
                                        TriggerServerEvent("balloon:requestEnterSeat", balloonNetId, seatToOccupy, GetPlayerServerId(PlayerId()))
                                    else
                                        Debug:Log(2, "Could not get network ID for balloon " .. nearestBalloon)
                                        -- Optionally, show a message to the player
                                    end
                                else
                                    Debug:Log(2, "Passenger seat was not available or nearestBalloon is nil upon prompt completion.")
                                    -- Optionally, show a message to the player: "No seats available"
                                end
                            end
                        else
                            Debug:Log(4, "Player too far for interaction prompts (distance: " .. distance .. "), hiding prompts.")
                            -- PromptSetVisible(captainPrompt, false) -- Captain prompt removed
                            PromptSetVisible(passengerPrompt, false)
                        end
                        break 
                    end
                end
            end
        else
            Debug:Log(4, "Player is currently in a balloon role: " .. playerRole)
        end
        
        isNearBalloon = foundBalloonThisTick
        
        if not foundBalloonThisTick and nearestBalloon then
            Debug:Log(4, "Player no longer near any balloon, hiding prompts and clearing nearestBalloon.")
            -- PromptSetVisible(captainPrompt, false) -- Captain prompt removed
            PromptSetVisible(passengerPrompt, false)
            nearestBalloon = nil
        end
        
        Citizen.Wait(foundBalloonThisTick and 0 or 500) 
    end
end)

-- Handle exiting the balloon (NOW ONLY FOR PASSENGERS with F key)
Citizen.CreateThread(function()
    Debug:Log(3, "Starting balloon exit monitoring thread for passengers.")
    while true do
        Citizen.Wait(0) -- Check every frame
        if playerRole and playerRole:find("passenger") then
            if IsControlJustPressed(0, 0x0522B243) then -- F key for passengers
                Debug:Log(3, "Passenger exit key (F) pressed.")
                DetachPlayerFromBalloon()
            end
        -- Captain exit is handled by game's default vehicle exit (e.g., X or holding F)
        -- and detected by the captain state monitoring thread.
        end
    end
end)

-- Export functions for other resources
exports('GetPlayerBalloonRole', function()
    Debug:Log(4, "GetPlayerBalloonRole called, returning: " .. tostring(playerRole))
    return playerRole
end)

-- Events for other scripts to use
AddEventHandler("balloon:enteredAsCaptain", function()
    Debug:Log(3, "Event: balloon:enteredAsCaptain triggered.")
end)

AddEventHandler("balloon:enteredAsPassenger", function()
    Debug:Log(3, "Event: balloon:enteredAsPassenger triggered.")
end)

AddEventHandler("balloon:exited", function(exitedRole)
    Debug:Log(3, "Event: balloon:exited triggered for role: " .. tostring(exitedRole))
    -- If the player was captain and exited, playerRole would be nil here due to captain monitoring thread.
    -- If they were a passenger, DetachPlayerFromBalloon would have set playerRole to nil.
end)

-- Server event handlers
AddEventHandler("balloon:seatConfirmed", function(balloonNetId, seatType, assignedPlayerServerId)
    local playerPed = PlayerPedId()
    local localPlayerServerId = GetPlayerServerId(PlayerId())

    Debug:Log(3, "Received balloon:seatConfirmed for seat " .. seatType .. " on balloonNetId " .. balloonNetId .. " for player " .. assignedPlayerServerId)

    if assignedPlayerServerId == localPlayerServerId then
        local balloonEntity = NetworkGetEntityFromNetworkId(balloonNetId)
        if DoesEntityExist(balloonEntity) then
            if seatType == "captain" then
                -- This event is more for other clients; captain status is primarily managed by GetVehiclePedIsIn
                -- However, we can ensure playerRole is set if somehow missed.
                if GetVehiclePedIsIn(playerPed, false) == balloonEntity and GetPedInVehicleSeat(balloonEntity, -1) == playerPed then
                    playerRole = "captain"
                    Debug:Log(3, "Confirmed as captain for balloon " .. balloonEntity)
                    TriggerEvent("balloon:enteredAsCaptain")
                else
                    Debug:Log(2, "SeatConfirmed for captain, but player not in driver seat of balloon " .. balloonEntity)
                end
            elseif seatType:find("passenger") then
                AttachPlayerToSeat(playerPed, balloonEntity, seatType)
                playerRole = seatType
                nearestBalloon = balloonEntity -- Ensure nearestBalloon is set
                currentBalloonEntity = balloonEntity
                currentBalloonNetId = balloonNetId
                Debug:Log(3, "Successfully entered seat " .. seatType .. " on balloon " .. balloonEntity)
                TriggerEvent("balloon:enteredAsPassenger")
            end
        else
            Debug:Log(2, "Balloon with NetID " .. balloonNetId .. " does not exist locally for seat confirmation.")
        end
    else
        Debug:Log(4, "Seat confirmation was for another player (" .. assignedPlayerServerId .. "), local player is " .. localPlayerServerId)
    end
end)

AddEventHandler("balloon:seatDenied", function(reason)
    Debug:Log(2, "Server denied seat request: " .. reason)
    -- You can add a player notification here, e.g., using a built-in game notification function
    -- For example: Citizen.InvokeNative(0x202709F4C58A0424, CreateVarString(10, "LITERAL_STRING", "Seat is occupied or unavailable."), true, true) -- Show RDR2 style alert
end)

AddEventHandler("balloon:seatUpdate", function(balloonNetId, seatType, occupantPlayerServerId, isOccupied)
    Debug:Log(4, "Received balloon:seatUpdate: BalloonNetID=" .. balloonNetId .. ", Seat=" .. seatType .. ", OccupantSID=" .. tostring(occupantPlayerServerId) .. ", IsOccupied=" .. tostring(isOccupied))
    
    -- Find the balloon entity this update pertains to.
    -- This is tricky if it's not 'nearestBalloon', as we don't track all balloons.
    -- For now, we'll assume updates are most relevant for 'nearestBalloon' or if the player is in that balloon.
    local balloonEntity = nil
    if nearestBalloon and NetworkGetNetworkIdFromEntity(nearestBalloon) == balloonNetId then
        balloonEntity = nearestBalloon
    elseif playerRole and GetVehiclePedIsIn(PlayerPedId(), false) ~= 0 and NetworkGetNetworkIdFromEntity(GetVehiclePedIsIn(PlayerPedId(), false)) == balloonNetId then
        balloonEntity = GetVehiclePedIsIn(PlayerPedId(), false)
    end

    if balloonEntity then
        if balloonSeats[seatType] then
            balloonSeats[seatType].occupied = isOccupied
            balloonSeats[seatType].occupant = isOccupied and occupantPlayerServerId or nil
            Debug:Log(4, "Updated local seat " .. seatType .. " on balloon " .. balloonEntity .. ": Occupied=" .. tostring(isOccupied) .. ", OccupantSID=" .. tostring(occupantPlayerServerId))

            -- If this client was the occupant and is now told the seat is not occupied by them (or anyone), clear their role.
            local localPlayerServerId = GetPlayerServerId(PlayerId())
            if playerRole == seatType and occupantPlayerServerId ~= localPlayerServerId and not isOccupied then
                Debug:Log(3, "Server update indicates player " .. localPlayerServerId .. " is no longer in seat " .. seatType .. ". Clearing role.")
                if seatType:find("passenger") then DetachEntity(PlayerPedId(), true, true) end -- Ensure detachment if passenger
                playerRole = nil
                TriggerEvent("balloon:exited", seatType)
            end
        else
            Debug:Log(2, "Received seatUpdate for unknown seatType: " .. seatType)
        end
    else
        Debug:Log(4, "Received seatUpdate for a balloon (NetID: " .. balloonNetId .. ") not currently relevant to this client.")
    end
end)


-- Reset on resource stop
AddEventHandler("onResourceStop", function(resourceName)
    if GetCurrentResourceName() == resourceName then
        Debug:Log(3, "Resource " .. resourceName .. " stopping.")
        if playerRole then
            Debug:Log(3, "Player was in balloon (role: " .. playerRole .. "), detaching/leaving.")
            DetachPlayerFromBalloon()
        end
    end
end)

RegisterCommand("balloon_debug_main", function(source, args, rawCommand)
    local cmd = args[1]
    if cmd == "level" then
        local newLevel = tonumber(args[2])
        if newLevel and newLevel >= 0 and newLevel <= 4 then
            Debug.level = newLevel
            Debug:ResetSuppression()
            Debug:Log(3, "Debug level set to: " .. newLevel)
        else
            Debug:Log(2, "Usage: /balloon_debug_main level [0-4]")
        end
    elseif cmd == "toggle" then
        Debug.enabled = not Debug.enabled
        Debug:ResetSuppression()
        if Debug.enabled then
            Debug:Log(3, "Debugging ENABLED")
        else
            print(Debug.prefix .. " [INFO] Debugging DISABLED")
            Debug.lastPrintedMessageSignature = nil 
        end
    elseif cmd == "status" then
        Debug:ResetSuppression() -- Reset to ensure status always prints fully
        Debug:Log(3, "--- Balloon Main Debug Status ---")
        Debug:Log(3, "Enabled: " .. tostring(Debug.enabled) .. ", Level: " .. Debug.level)
        Debug:Log(3, "Player Role: " .. tostring(playerRole))
        Debug:Log(3, "Is Near Balloon: " .. tostring(isNearBalloon))
        Debug:Log(3, "Nearest Balloon ID: " .. tostring(nearestBalloon))
        Debug:Log(3, "Seat Status:")
        Debug:DUMP(balloonSeats)
    else
        Debug:Log(2, "Usage: /balloon_debug_main [level|toggle|status]")
    end
end, false)

Debug:Log(3, "Balloon main script initialized. Debug Level: " .. Debug.level .. ", Enabled: " .. tostring(Debug.enabled))