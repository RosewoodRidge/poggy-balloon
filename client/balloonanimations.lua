local activePilot = true
local currentAnim
local rope = nil
local isDrivingBalloon = false


local function isPlayingAnim(ped, anim)
	return IsEntityPlayingAnim(ped, anim.dict, anim.name, anim.flags)
end

local function playAnim(ped, anim)
	if not DoesAnimDictExist(anim.dict) then
		return
	end

	RequestAnimDict(anim.dict)

	while not HasAnimDictLoaded(anim.dict) do
		Citizen.Wait(0)
	end

	TaskPlayAnim(ped, anim.dict, anim.name, 1.0, 1.0, -1, 29, 0.0, false, 0, false, "", false)

	RemoveAnimDict(anim.dict)
end

local function stopAnim(ped, anim)
	StopAnimTask(ped, anim.dict, anim.name, 1.0)
end

AddEventHandler("onResourceStop", function(resourceName)
	if GetCurrentResourceName() == resourceName then
		if currentAnim then
			stopAnim(PlayerPedId(), currentAnim)
		end
	end
end)

-- play animation if in the balloon
Citizen.CreateThread(function()

	while true do
		local canWait = true

		if activePilot then
			local playerPed = PlayerPedId()
            local veh = GetVehiclePedIsIn(playerPed)
            local model = GetEntityModel(veh)
            if model == 1588640480 then

				local ropePull


				if IsControlPressed(0, 0x7232BAB3) then
					ropePull = "base_burner_pull_arthur"
				else
					ropePull = "idle_burner_line_arthur"
				end

				currentAnim = {
					dict = ("script_story@gng2@ig@ig_2_balloon_control"),
					name = ropePull,
					flags = 17
				}

				if currentAnim and not isPlayingAnim(playerPed, currentAnim) then
					playAnim(playerPed, currentAnim)
				end

				canWait = false
			elseif currentAnim then
				stopAnim(playerPed, currentAnim)
				currentAnim = nil
			end
		end

		Citizen.Wait(canWait and 1000 or 100)
	end
end)

-- Rope 
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(1000)  -- Check every second

        local playerPed = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(playerPed, false)

        if vehicle ~= 0 and GetEntityModel(vehicle) == GetHashKey('hotairballoon01') then
            if not isDrivingBalloon then
                -- The player started driving the balloon again, so recreate the rope
                local playerCoords = GetEntityCoords(playerPed)

                local ropeLength = 0.7  -- Adjust this value for desired rope length

                -- Create the rope
                rope = AddRope(playerCoords.x, playerCoords.y, playerCoords.z, 0.0, 0.0, 0.0, ropeLength, 7, ropeLength, ropeLength, ropeLength, false, false, false, 1.0, false, 0)

                -- Attach rope ends to the player and the balloon
                AttachEntitiesToRope(rope, playerPed, vehicle, 0.0, 0.05, 0.05, -0.2, 0.0, 0.0, ropeLength, 0, 0, "PH_L_HAND", "engine", 0, -1, -1, 0, 0, 1, 1)

                isDrivingBalloon = true
            end
        else
            if isDrivingBalloon then
                -- The player stopped driving the balloon, so delete the rope
                if rope then
                    DeleteRope(rope)
                    rope = nil
                end
                isDrivingBalloon = false
            end
        end
    end
end)