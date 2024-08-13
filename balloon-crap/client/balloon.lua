RegisterCommand('balloon', function(source, args, rawCommand)
    -- Get the player's ped (player's character model)
    local playerPed = PlayerPedId()

    -- Get the player's current coordinates
    local playerCoords = GetEntityCoords(playerPed)

    -- Define the model names for the hot air balloon and the object to attach
    local balloonModel = 'hotairballoon01'  -- Adjust this to the correct model name if necessary
    local objectModel = 'p_ambfloorscrub01x'

    -- Request the models to be loaded
    RequestModel(balloonModel)
    RequestModel(objectModel)

    -- Wait until both models are loaded
    while not HasModelLoaded(balloonModel) or not HasModelLoaded(objectModel) do
        Citizen.Wait(1)
    end

    -- Create the hot air balloon at the player's current coordinates
    local balloon = CreateVehicle(GetHashKey(balloonModel), playerCoords.x, playerCoords.y, playerCoords.z, GetEntityHeading(playerPed), true, false)

    -- Create the object and attach it to the hot air balloon
    local object = CreateObject(GetHashKey(objectModel), playerCoords.x, playerCoords.y, playerCoords.z, true, true, false)
    AttachEntityToEntity(object, balloon, 0, 0.0, 0.0, 0.09, 0.0, 0.0, 0.0, true, true, true, false, false, true, true, true)

        -- Make the attached object invisible
         SetEntityVisible(object, false)

    -- Set the models as no longer needed to free up memory
    SetModelAsNoLongerNeeded(balloonModel)
    SetModelAsNoLongerNeeded(objectModel)
end, false)
