local balloonOccupancy = {} -- { [balloonNetId] = { captain = playerServerIdOrNil, passenger1 = playerServerIdOrNil, ... } }

local Debug = {
    enabled = false,
    level = 3, -- INFO
    prefix = "[BalloonServer]",
    Log = function(self, level, message)
        if not self.enabled or level > self.level then return end
        local levelStr = ({"[OFF]", "[ERROR]", "[WARNING]", "[INFO]", "[DEBUG]"})[level + 1]
        print(self.prefix .. " " .. levelStr .. " " .. tostring(message))
    end
}

local function getSeatKeys()
    return {"captain", "passenger1", "passenger2", "passenger3", "passenger4"}
end

local function initializeBalloonSeats(balloonNetId)
    if not balloonOccupancy[balloonNetId] then
        balloonOccupancy[balloonNetId] = {}
        for _, seatKey in ipairs(getSeatKeys()) do
            balloonOccupancy[balloonNetId][seatKey] = nil
        end
        Debug:Log(4, "Initialized seats for balloonNetId: " .. balloonNetId)
    end
end

RegisterNetEvent("balloon:requestEnterSeat", function(balloonNetId, seatType, requestingPlayerServerId)
    local src = source -- This is the server ID of the player who sent the event
    if requestingPlayerServerId ~= src then
        Debug:Log(1, "Player SID mismatch! Event from " .. src .. " but for " .. requestingPlayerServerId .. ". Denying.")
        TriggerClientEvent("balloon:seatDenied", src, "Security check failed.")
        return
    end

    initializeBalloonSeats(balloonNetId)
    Debug:Log(3, "Player " .. src .. " requests seat " .. seatType .. " on balloon " .. balloonNetId)

    if not balloonOccupancy[balloonNetId][seatType] then
        -- Check if player is already in another seat on this balloon
        for _, key in ipairs(getSeatKeys()) do
            if balloonOccupancy[balloonNetId][key] == src then
                Debug:Log(2, "Player " .. src .. " already in seat " .. key .. " on balloon " .. balloonNetId .. ". Vacating old seat.")
                balloonOccupancy[balloonNetId][key] = nil
                TriggerClientEvent("balloon:seatUpdate", -1, balloonNetId, key, src, false) -- Broadcast old seat now vacant
            end
        end

        balloonOccupancy[balloonNetId][seatType] = src
        Debug:Log(3, "Seat " .. seatType .. " on balloon " .. balloonNetId .. " assigned to player " .. src)
        TriggerClientEvent("balloon:seatConfirmed", src, balloonNetId, seatType, src)
        TriggerClientEvent("balloon:seatUpdate", -1, balloonNetId, seatType, src, true) -- Broadcast to all clients
    else
        Debug:Log(2, "Seat " .. seatType .. " on balloon " .. balloonNetId .. " already occupied by " .. balloonOccupancy[balloonNetId][seatType] .. ". Request denied for " .. src)
        TriggerClientEvent("balloon:seatDenied", src, "Seat is already occupied.")
    end
end)

RegisterNetEvent("balloon:vacateSeat", function(balloonNetId, seatType)
    local src = source
    if not balloonNetId then
        Debug:Log(2, "Player " .. src .. " tried to vacate a seat without providing a valid balloon NetID")
        return
    end

    initializeBalloonSeats(balloonNetId) -- Ensure it exists
    Debug:Log(3, "Player " .. src .. " vacating seat " .. seatType .. " on balloon " .. balloonNetId)

    if balloonOccupancy[balloonNetId][seatType] == src then
        balloonOccupancy[balloonNetId][seatType] = nil
        Debug:Log(3, "Seat " .. seatType .. " on balloon " .. balloonNetId .. " vacated by " .. src)
        TriggerClientEvent("balloon:seatUpdate", -1, balloonNetId, seatType, src, false) -- Broadcast to all clients
    elseif balloonOccupancy[balloonNetId][seatType] then
        Debug:Log(2, "Player " .. src .. " tried to vacate seat " .. seatType .. " but it was occupied by " .. balloonOccupancy[balloonNetId][seatType])
    else
        Debug:Log(2, "Player " .. src .. " tried to vacate seat " .. seatType .. " but it was already empty.")
    end
end)

RegisterNetEvent("balloon:captainEntered", function(balloonNetId, captainPlayerServerId)
    local src = source -- player who triggered this, should match captainPlayerServerId
    if captainPlayerServerId ~= src then
        Debug:Log(1, "Captain SID mismatch! Event from " .. src .. " but for " .. captainPlayerServerId .. ". Ignoring.")
        return
    end

    initializeBalloonSeats(balloonNetId)
    Debug:Log(3, "Player " .. src .. " entered as captain on balloon " .. balloonNetId)

    -- If captain was previously a passenger on this balloon, vacate that seat
    for i=1,4 do
        local pSeat = "passenger"..i
        if balloonOccupancy[balloonNetId][pSeat] == src then
            balloonOccupancy[balloonNetId][pSeat] = nil
            TriggerClientEvent("balloon:seatUpdate", -1, balloonNetId, pSeat, src, false)
            Debug:Log(3, "Captain " .. src .. " was passenger in " .. pSeat .. ", vacated.")
            break
        end
    end
    
    balloonOccupancy[balloonNetId].captain = src
    TriggerClientEvent("balloon:seatUpdate", -1, balloonNetId, "captain", src, true)
end)

RegisterNetEvent("balloon:captainExited", function(balloonNetId, captainPlayerServerId)
    local src = source
     if captainPlayerServerId ~= src then
        Debug:Log(1, "Captain SID mismatch! Event from " .. src .. " but for " .. captainPlayerServerId .. ". Ignoring.")
        return
    end

    initializeBalloonSeats(balloonNetId)
    Debug:Log(3, "Player " .. src .. " exited as captain from balloon " .. balloonNetId)

    if balloonOccupancy[balloonNetId].captain == src then
        balloonOccupancy[balloonNetId].captain = nil
        TriggerClientEvent("balloon:seatUpdate", -1, balloonNetId, "captain", src, false)
    else
        Debug:Log(2, "Player " .. src .. " tried to exit captain seat but was not registered as captain or seat already empty.")
    end
end)

AddEventHandler("playerDropped", function(reason)
    local src = source
    Debug:Log(3, "Player " .. src .. " dropped. Reason: " .. reason .. ". Checking balloon occupancy.")
    for balloonNetId, seats in pairs(balloonOccupancy) do
        for seatKey, occupantId in pairs(seats) do
            if occupantId == src then
                Debug:Log(3, "Player " .. src .. " was in seat " .. seatKey .. " on balloon " .. balloonNetId .. ". Vacating.")
                balloonOccupancy[balloonNetId][seatKey] = nil
                TriggerClientEvent("balloon:seatUpdate", -1, balloonNetId, seatKey, src, false)
            end
        end
    end
end)

-- Cleanup for balloons that might no longer exist (e.g. despawned)
-- This is a basic cleanup. More robust solutions might involve tracking balloon entities server-side.
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(300000) -- Every 5 minutes
        local currentBalloons = {}
        -- In a more complex setup, you'd get a list of active balloon network IDs.
        -- For now, we assume if a balloon hasn't had activity, it might be gone.
        -- This part is highly dependent on how your framework handles entity states server-side.
        -- A simple approach: if a balloon has no occupants, remove it from tracking after a while.
        -- However, without knowing if NetworkDoesEntityExist works server-side reliably for all scenarios,
        -- this part is tricky. For now, we'll rely on playerDropped and explicit vacate/exit events.
        
        local emptyBalloons = {}
        for balloonNetId, seats in pairs(balloonOccupancy) do
            local isEmpty = true
            for _, occupantId in pairs(seats) do
                if occupantId then
                    isEmpty = false
                    break
                end
            end
            if isEmpty then
                table.insert(emptyBalloons, balloonNetId)
            end
        end

        if #emptyBalloons > 0 then
            Debug:Log(4, "Found " .. #emptyBalloons .. " empty balloons in tracking. Removing them.")
            for _, balloonNetId in ipairs(emptyBalloons) do
                balloonOccupancy[balloonNetId] = nil
            end
        end
    end
end)

Debug:Log(3, "Balloon Server Script Initialized.")

-- Command to inspect server-side occupancy (for debugging)
RegisterCommand("balloon_server_status", function(adminSource, args, rawCommand)
    -- Basic permission check (e.g., for admin/developer)
    -- Replace with your actual permission system if you have one
    if IsPlayerAceAllowed(adminSource, "command.balloon_server_status") or GetPlayerName(adminSource):lower() == "youradminname" then -- Adjust permission
        Debug:Log(3, "--- Balloon Server Status ---")
        if next(balloonOccupancy) == nil then
            Debug:Log(3, "No balloons currently tracked.")
            print(Debug.prefix .. " [INFO] No balloons currently tracked.")
        else
            for balloonNetId, seats in pairs(balloonOccupancy) do
                Debug:Log(3, "Balloon NetID: " .. balloonNetId)
                print(Debug.prefix .. " [INFO] Balloon NetID: " .. balloonNetId)
                for seat, occupant in pairs(seats) do
                    if occupant then
                        Debug:Log(3, "  Seat: " .. seat .. " - Occupant SID: " .. occupant .. " (Player: " .. GetPlayerName(occupant) .. ")")
                        print(Debug.prefix .. " [INFO]   Seat: " .. seat .. " - Occupant SID: " .. occupant .. " (Player: " .. GetPlayerName(occupant) .. ")")
                    else
                        Debug:Log(3, "  Seat: " .. seat .. " - Empty")
                        print(Debug.prefix .. " [INFO]   Seat: " .. seat .. " - Empty")
                    end
                end
            end
        end
    else
        Debug:Log(1, "Player " .. adminSource .. " (" .. GetPlayerName(adminSource) .. ") attempted to use /balloon_server_status without permission.")
        TriggerClientEvent('chat:addMessage', adminSource, {
            color = {255, 0, 0},
            multiline = true,
            args = {"System", "You do not have permission to use this command."}
        })
    end
end, false) -- false means only server console or authorized players can run it
