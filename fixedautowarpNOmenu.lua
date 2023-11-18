
---@alias AimTarget { entity : Entity, angles : EulerAngles, factor : number }

package.path = package.path .. ";C:\\Users\\Terminatort8000\\AppData\\Local\\?.lua"

--[[
---@type boolean, lnxLib
local libLoaded, lnxLib = pcall(require, "lnxLib");
assert(libLoaded, "lnxLib not found, please install it!");
assert(lnxLib.GetVersion() <= 0.995, "lnxLib version is too old, please update it!");


local menuLoaded, ImMenu = pcall(require, "ImMenu")
assert(menuLoaded, "ImMenu not found, please install it!")
assert(ImMenu.GetVersion() >= 0.66, "ImMenu version is too old, please update it!")

local Math, Conversion = lnxLib.Utils.Math, lnxLib.Utils.Conversion
local WPlayer, WWeapon = lnxLib.TF2.WPlayer, lnxLib.TF2.WWeapon
local Helpers = lnxLib.TF2.Helpers
local Prediction = lnxLib.TF2.Prediction
local Fonts = lnxLib.UI.FontslnxLib]]

local Menu = { -- this is the config that will be loaded every time u load the script

    Version = 1.5, -- dont touch this, this is just for managing the config version

    tabs = { -- dont touch this, this is just for managing the tabs in the menu
        Main = true,
        Advanced = false,
        Visuals = false,
    },

    Main = {
        Active = true,  --disable lua
        TrickstabMode = {"Assistance", "Assistance + Blink", "Auto Blink", "Auto Warp",  "Auto Warp + Auto Blink", "Debug"},
        TrickstabModeSelected = 6,
        AutoBackstab = true,
        AutoWalk = true,
        AutoRecharge = true,
    },

    Advanced = {
        ColisionCheck = true,
        AdvancedPred = true,
        Simulations = 5,
    },

    Visuals = {
        Active = true,
        VisualizePoints = true,
        VisualizeStabPoint = true,
        VisualizeUsellesSimulations = true,
    },
}

local lastToggleTime = 0
local Lbox_Menu_Open = true
local function toggleMenu()
    local currentTime = globals.RealTime()
    if currentTime - lastToggleTime >= 0.1 then
        if Lbox_Menu_Open == false then
            Lbox_Menu_Open = true
        elseif Lbox_Menu_Open == true then
            Lbox_Menu_Open = false
        end
        lastToggleTime = currentTime
    end
end

local function CreateCFG(folder_name, table)
    local success, fullPath = filesystem.CreateDirectory(folder_name)
    local filepath = tostring(fullPath .. "/config.txt")
    local file = io.open(filepath, "w")
    
    if file then
        local function serializeTable(tbl, level)
            level = level or 0
            local result = string.rep("    ", level) .. "{\n"
            for key, value in pairs(tbl) do
                result = result .. string.rep("    ", level + 1)
                if type(key) == "string" then
                    result = result .. '["' .. key .. '"] = '
                else
                    result = result .. "[" .. key .. "] = "
                end
                if type(value) == "table" then
                    result = result .. serializeTable(value, level + 1) .. ",\n"
                elseif type(value) == "string" then
                    result = result .. '"' .. value .. '",\n'
                else
                    result = result .. tostring(value) .. ",\n"
                end
            end
            result = result .. string.rep("    ", level) .. "}"
            return result
        end
        
        local serializedConfig = serializeTable(table)
        file:write(serializedConfig)
        file:close()
        printc( 255, 183, 0, 255, "["..os.date("%H:%M:%S").."] Saved to ".. tostring(fullPath))
    end
end

local function LoadCFG(folder_name)
    local success, fullPath = filesystem.CreateDirectory(folder_name)
    local filepath = tostring(fullPath .. "/config.txt")
    local file = io.open(filepath, "r")

    if file then
        local content = file:read("*a")
        file:close()
        local chunk, err = load("return " .. content)
        if chunk then
            printc( 0, 255, 140, 255, "["..os.date("%H:%M:%S").."] Loaded from ".. tostring(fullPath))
            return chunk()
        else
            print("Error loading configuration:", err)
        end
    end
end

local status, loadedMenu = pcall(function() return assert(LoadCFG([[LBOX Auto trickstab lua]])) end) --auto laod config

if status then --ensure config is not causing errors
    if loadedMenu.Version == Menu.Version then
        Menu = loadedMenu
    else
        CreateCFG([[LBOX Auto trickstab lua]], Menu) --saving the config
    end
end


local M_RADPI = 180 / math.pi

local function isNaN(x) return x ~= x end

-- Calculates the angle between two vectors
---@param source Vector3
---@param dest Vector3
---@return EulerAngles angles
local function PositionAngles(source, dest)
    local delta = source - dest

    local pitch = math.atan(delta.z / delta:Length2D()) * M_RADPI
    local yaw = math.atan(delta.y / delta.x) * M_RADPI

    if delta.x >= 0 then
        yaw = yaw + 180
    end

    if isNaN(pitch) then pitch = 0 end
    if isNaN(yaw) then yaw = 0 end

    return EulerAngles(pitch, yaw, 0)
end

-- Normalizes a vector to a unit vector
local function NormalizeVector(vec)
    local length = math.sqrt(vec.x^2 + vec.y^2 + vec.z^2)
    return Vector3(vec.x / length, vec.y / length, vec.z / length)
end

local cachedLocalPlayer
local cachedPlayers = {}
local cachedLoadoutSlot2
local pLocalViewPos
local tickCount = 0
local pLocal = entities.GetLocalPlayer()
local vHitbox = { Vector3(-22, -22, 0), Vector3(22, 22, 82) }

local function GetHitboxForwardDirection(player)
    local hitboxes = player:SetupBones()

    -- Process only the first hitbox (assuming it has index 0)
    local boneMatrix = hitboxes[1]
    if boneMatrix then
        -- Extract rotation and translation components
        local rotation = {boneMatrix[1], boneMatrix[2], boneMatrix[3]}
        local translation = {x = boneMatrix[1][4], y = boneMatrix[2][4], z = boneMatrix[3][4]}
    
        -- Assuming boneMatrix[1][1], boneMatrix[2][1], boneMatrix[3][1] represent the forward vector
        local forward = {x = rotation[1][1], y = rotation[2][1], z = rotation[3][1]}

        -- Rotate the forward vector by 90 degrees around the Z-axis
        local rotatedForward = {
            x = -forward.y,  -- x' = -y
            y = forward.x,   -- y' = x
            z = forward.z    -- z' = z (no change in z-axis)
        }

        return rotatedForward
    end
    return nil
end


-- Function to update the cache for the local player and loadout slot
local function UpdateLocalPlayerCache()
    cachedLocalPlayer = entities.GetLocalPlayer()
    cachedLoadoutSlot2 = cachedLocalPlayer and cachedLocalPlayer:GetEntityForLoadoutSlot(2) or nil
    pLocalViewPos = cachedLocalPlayer and (cachedLocalPlayer:GetAbsOrigin() + cachedLocalPlayer:GetPropVector("localdata", "m_vecViewOffset[0]")) or nil
end

local function UpdatePlayersCache()
    local allPlayers = entities.FindByClass("CTFPlayer")
    for i, player in pairs(allPlayers) do
        if player:GetIndex() ~= cachedLocalPlayer:GetIndex() then
            local hitbox = player:GetHitboxes()[4] -- Assuming hitboxID 4

            cachedPlayers[player:GetIndex()] = {
                entity = player,
                isAlive = player:IsAlive(),
                isDormant = player:IsDormant(),
                teamNumber = player:GetTeamNumber(),
                absOrigin = player:GetAbsOrigin(),
                viewOffset = player:GetPropVector("localdata", "m_vecViewOffset[0]"),
                hitboxPos = hitbox and (hitbox[1] + hitbox[2]) * 0.5 or nil,
                hitboxForward = GetHitboxForwardDirection(player) -- Calculated forward direction
            }
        end
    end
end

-- Initialize cache
UpdateLocalPlayerCache()
UpdatePlayersCache()

-- Constants
local MAX_SPEED = 320  -- Maximum speed
local SIMULATION_TICKS = 24  -- Number of ticks for simulation
local positions = {}

local FORWARD_COLLISION_ANGLE = 55
local GROUND_COLLISION_ANGLE_LOW = 45
local GROUND_COLLISION_ANGLE_HIGH = 55

-- Helper function for forward collision
local function handleForwardCollision(vel, wallTrace, vUp)
    local normal = wallTrace.plane
    local angle = math.deg(math.acos(normal:Dot(vUp)))
    if angle > FORWARD_COLLISION_ANGLE then
        local dot = vel:Dot(normal)
        vel = vel - normal * dot
    end
    return wallTrace.endpos.x, wallTrace.endpos.y
end

-- Helper function for ground collision
local function handleGroundCollision(vel, groundTrace, vUp)
    local normal = groundTrace.plane
    local angle = math.deg(math.acos(normal:Dot(vUp)))
    local onGround = false
    if angle < GROUND_COLLISION_ANGLE_LOW then
        onGround = true
    elseif angle < GROUND_COLLISION_ANGLE_HIGH then
        vel.x, vel.y, vel.z = 0, 0, 0
    else
        local dot = vel:Dot(normal)
        vel = vel - normal * dot
        onGround = true
    end
    if onGround then vel.z = 0 end
    return groundTrace.endpos, onGround
end

-- Simulates movement in a specified direction vector for a player over a given number of ticks
local function SimulateWalk(player, simulatedVelocity)
    local tick_interval = globals.TickInterval()
    local gravity = client.GetConVar("sv_gravity")
    local stepSize = player:GetPropFloat("localdata", "m_flStepSize")
    local vUp = Vector3(0, 0, 1)
    local vStep = Vector3(0, 0, stepSize / 2)

    positions = {}  -- Store positions for each tick
    local lastP = player:GetAbsOrigin()
    local lastV = simulatedVelocity
    local flags = player:GetPropInt("m_fFlags")
    local lastG = (flags & 1 == 1)

    for i = 1, SIMULATION_TICKS do
        
        local pos = lastP + lastV * tick_interval
        local vel = lastV
        local onGround = lastG

        if Menu.Advanced.ColisionCheck then
            if Menu.Advanced.AdvancedPred then
                -- Forward collision
                local wallTrace = engine.TraceHull(lastP + vStep, pos + vStep, vHitbox[1], vHitbox[2], MASK_PLAYERSOLID)
                if wallTrace.fraction < 1 then
                    pos.x, pos.y = handleForwardCollision(vel, wallTrace, vUp)
                end
            else
                -- Forward collision
                local wallTrace = engine.TraceHull(lastP + vStep, pos + vStep, vHitbox[1], vHitbox[2], MASK_PLAYERSOLID)
                if wallTrace.fraction < 1 then
                    positions[24] = lastP
                    break  -- Exit the loop as collision has occurred
                end
            end

            -- Ground collision
            local downStep = onGround and vStep or Vector3()
            local groundTrace = engine.TraceHull(pos + vStep, pos - downStep, vHitbox[1], vHitbox[2], MASK_PLAYERSOLID)
            if groundTrace.fraction < 1 then
                pos, onGround = handleGroundCollision(vel, groundTrace, vUp)
            else
                onGround = false
            end
        end

        -- Apply gravity if not on ground
        if not onGround then
            vel.z = vel.z - gravity * tick_interval
        end

        lastP, lastV, lastG = pos, vel, onGround
        positions[i] = lastP  -- Store position for this tick
    end

    return positions
end

-- Normalize a yaw angle to the range [-180, 180]
local function NormalizeYaw(yaw)
    while yaw > 180 do yaw = yaw - 360 end
    while yaw < -180 do yaw = yaw + 360 end
    return yaw
end

-- Calculate the yaw angle between two positions
local function CalculateYawAngle(fromPos, toPos)
    local delta = toPos - fromPos
    local angle = math.deg(math.atan(delta.y / delta.x))

    if delta.x < 0 then
        angle = angle + 180
    elseif delta.y < 0 then
        angle = angle + 360
    end

    return angle
end


-- Check if the angle difference is within 90 degrees FOV
local function IsWithin90DegreesFOV(angle1, angle2)
    local difference = NormalizeYaw(angle1 - angle2)
    return math.abs(difference) <= 90
end


-- Constants
local BACKSTAB_RANGE = 104  -- Hammer units
local BACKSTAB_ANGLE = 180  -- Degrees in radians for dot product calculation

local BestYawDifference = 0
local BestPosition

local function CanBackstabFromPosition(cmd, viewPos, real, targetPlayerGlobal)
    if real then
        for _, targetPlayer in pairs(cachedPlayers) do
            if targetPlayer.isAlive and not targetPlayer.isDormant and targetPlayer.teamNumber ~= cachedLocalPlayer:GetTeamNumber() then
                local distance = vector.Distance(viewPos, targetPlayer.hitboxPos)
                if distance < BACKSTAB_RANGE then
                    local ang = PositionAngles(viewPos, targetPlayer.hitboxPos)
                    cmd:SetViewAngles(ang.pitch, ang.yaw, 0) --engine.SetViewAngles(ang) --
                    if cachedLoadoutSlot2:GetPropInt("m_bReadyToBackstab") == 257 then
                        return true
                    end
                end
            end
        end
    else
        local targetPlayer = cachedPlayers[targetPlayerGlobal:GetIndex()]
        if targetPlayer and targetPlayer.isAlive and not targetPlayer.isDormant and targetPlayer.teamNumber ~= cachedLocalPlayer:GetTeamNumber() then
            local distance = vector.Distance(viewPos, targetPlayer.hitboxPos)
            if distance < BACKSTAB_RANGE then
                -- Invert the yaw angle by adding 180 degrees
                local enemyYaw = -(cachedPlayers[targetPlayerGlobal:GetIndex()].viewOffset.y)
                enemyYaw = NormalizeYaw(enemyYaw + 180)  -- Normalize after adding 180 degrees
        
                local spyYaw = CalculateYawAngle(viewPos, targetPlayer.hitboxPos)
        
                local yawDifference = math.abs(NormalizeYaw(spyYaw - enemyYaw))
        
                if IsWithin90DegreesFOV(spyYaw, enemyYaw) and yawDifference > BestYawDifference then
                    BestYawDifference = yawDifference
                    BestPosition = viewPos
                end
                return IsWithin90DegreesFOV(spyYaw, enemyYaw)
            end
        end        
    end
    return false
end




local function GetBestTarget(me)
    local players = entities.FindByClass("CTFPlayer")
    local bestTarget = nil
    local maxDistance = 117  -- 24 ticks into future at speed of 320 units

    for _, player in pairs(players) do
        if player ~= nil and player:IsAlive() and not player:IsDormant()
        and player ~= me and player:GetTeamNumber() ~= me:GetTeamNumber() then
            local distance = vector.Distance(me:GetAbsOrigin(), player:GetAbsOrigin())

            if distance <= maxDistance then
                if bestTarget == nil or distance < vector.Distance(me:GetAbsOrigin(), bestTarget:GetAbsOrigin()) then
                    bestTarget = player
                end
            end
        end
    end

    return bestTarget
end

local function CalculateTrickstab(player, target, leftOffset, rightOffset)
    local endPositions = {}
    local playerPos = player:GetAbsOrigin()
    local targetPos = target:GetAbsOrigin()
    local centralAngle = math.deg(math.atan(targetPos.y - playerPos.y, targetPos.x - playerPos.x))

    local totalSimulations = Menu.Advanced.Simulations
    local evenDistribution = totalSimulations % 2 == 0

    -- Special angles for left and right offsets
    endPositions[centralAngle + leftOffset] = SimulateWalk(player, Vector3(math.cos(math.rad(centralAngle + leftOffset)), math.sin(math.rad(centralAngle + leftOffset)), 0) * MAX_SPEED)
    endPositions[centralAngle + rightOffset] = SimulateWalk(player, Vector3(math.cos(math.rad(centralAngle + rightOffset)), math.sin(math.rad(centralAngle + rightOffset)), 0) * MAX_SPEED)

    -- Include forward direction and adjust simulations
    local simulationsToDistribute = totalSimulations - 3
    local angleIncrement = (rightOffset - leftOffset) / (simulationsToDistribute + 1)
    local currentAngle = centralAngle + leftOffset

    for i = 1, simulationsToDistribute do
        currentAngle = currentAngle + angleIncrement
        local radianAngle = math.rad(currentAngle)
        local directionVector = NormalizeVector(Vector3(math.cos(radianAngle), math.sin(radianAngle), 0))
        local simulatedVelocity = directionVector * MAX_SPEED
        endPositions[currentAngle] = SimulateWalk(player, simulatedVelocity)
    end

    if not evenDistribution then
        endPositions[centralAngle] = SimulateWalk(player, Vector3(math.cos(math.rad(centralAngle)), math.sin(math.rad(centralAngle)), 0) * MAX_SPEED)
    end

    return endPositions
end

-- Computes the move vector between two points
---@param userCmd UserCmd
---@param a Vector3
---@param b Vector3
---@return Vector3
local function ComputeMove(userCmd, a, b)
    local diff = (b - a)
    if diff:Length() == 0 then return Vector3(0, 0, 0) end

    local x = diff.x
    local y = diff.y
    local vSilent = Vector3(x, y, 0)

    local ang = vSilent:Angles()
    local cPitch, cYaw, cRoll = engine.GetViewAngles():Unpack()
    local yaw = math.rad(ang.y - cYaw)
    local pitch = math.rad(ang.x - cPitch)
    local move = Vector3(math.cos(yaw) * 320, -math.sin(yaw) * 320, -math.cos(pitch) * 320)

    return move
end

-- Global variable to store the move direction
local movedir

-- Walks to the destination and sets the global move direction
---@param userCmd UserCmd
---@param localPlayer Entity
---@param destination Vector3
local function WalkTo(userCmd, Pos, destination)
    local localPos = Pos
    local result = ComputeMove(userCmd, localPos, destination)

    userCmd:SetButtons(userCmd.buttons & (~8))
    userCmd:SetButtons(userCmd.buttons & (~16))
    userCmd:SetButtons(userCmd.buttons & (~128))
    userCmd:SetButtons(userCmd.buttons & (~256))

    userCmd:SetForwardMove(result.x)
    userCmd:SetSideMove(result.y)

    -- Set the global move direction
    movedir = Vector3(result.x, result.y, 0)
end

local function calculateRadiusOfSquare(sideLength)
    return math.sqrt(2 * (sideLength ^ 2))
end

-- Function to check if there's a collision between two spheres
local function checkSphereCollision(center1, radius1, center2, radius2)
    local distance = vector.Distance(center1, center2)
    return distance < (radius1 + radius2)
end

-- Additional helper function to check collision between sphere and AABB
local function checkSphereAABBCollision(sphereCenter, sphereRadius, aabbMin, aabbMax)
    local closestPoint = Vector3(
        math.max(aabbMin.x, math.min(sphereCenter.x, aabbMax.x)),
        math.max(aabbMin.y, math.min(sphereCenter.y, aabbMax.y)),
        math.max(aabbMin.z, math.min(sphereCenter.z, aabbMax.z))
    )

    local distanceVec = sphereCenter - closestPoint
    local distanceSq = distanceVec.x^2 + distanceVec.y^2 + distanceVec.z^2
    return distanceSq < (sphereRadius * sphereRadius)
end

-- Function to calculate the right offset with additional collision simulation
local function calculateRightOffset(pLocalPos, targetPos, enemyAABB)
    local radius = calculateRadiusOfSquare(24)  -- Radius as the diagonal of a 24x24 square
    local angleIncrement = 5
    local maxIterations = 180 / angleIncrement

    local initialDirection = NormalizeVector(targetPos - pLocalPos)

    for i = 1, maxIterations do
        local radianAngle = math.rad(i * angleIncrement)
        local rotatedDirection = Vector3(
            initialDirection.x * math.cos(radianAngle) - initialDirection.y * math.sin(radianAngle),
            initialDirection.x * math.sin(radianAngle) + initialDirection.y * math.cos(radianAngle),
            0
        )
        local offsetVector = rotatedDirection * radius * 2
        local testPos = pLocalPos + offsetVector

        if not checkSphereCollision(testPos, radius, targetPos, radius) then
            -- Additional collision check with the enemy's AABB
            if not checkSphereAABBCollision(testPos, radius, enemyAABB[1], enemyAABB[2]) then
                return i * angleIncrement
            end
        end
    end

    return nil -- No unobstructed path found
end



local allWarps = {}
local endwarps = {}
local TargetGlobalPlayer
local global_CMD

local function Assistance(cmd, pLocal)
    global_CMD = cmd

    pLocal = entities.GetLocalPlayer()
    -- Store all potential positions in allWarps
    local target = GetBestTarget(cachedLocalPlayer)
    if not target then return end
    TargetGlobalPlayer = target

    local RightOffst = calculateRightOffset(pLocal:GetAbsOrigin(), target:GetAbsOrigin())
    local LeftOffset = -RightOffst --calculateLeftOffset(pLocalPos, targetPos, vHitbox, Right)

    local currentWarps = CalculateTrickstab(pLocal, target, RightOffst , LeftOffset)
    table.insert(allWarps, currentWarps)

        -- Store the 24th tick positions in endwarps
        for angle, positions1 in pairs(currentWarps) do
            local twentyFourthTickPosition = positions1[24]
            if twentyFourthTickPosition then
                endwarps[angle] = { twentyFourthTickPosition, false }
            end
        end


        -- check if any of warp positions can stab anyone
        local lastDistance
        for angle, point in pairs(endwarps) do
            if CanBackstabFromPosition(cmd, point[1] + Vector3(0, 0, 75), false, target) then
                endwarps[angle] = {point[1], true}

                if Menu.Main.AutoWalk and warp.CanWarp() then
                    WalkTo(cmd, cachedLocalPlayer:GetAbsOrigin(), point[1])
                end
            end
        end
end

local function Debug(cmd, pLocal)
     -- Store all potential positions in allWarps
     local target = GetBestTarget(cachedLocalPlayer)
     if not target then return end
     TargetGlobalPlayer = target
 
     local RightOffst = calculateRightOffset(pLocal:GetAbsOrigin(), target:GetAbsOrigin(), vHitbox)
     local LeftOffset = -RightOffst --calculateLeftOffset(pLocalPos, targetPos, vHitbox, Right)
 
     local currentWarps = CalculateTrickstab(pLocal, target, RightOffst , LeftOffset)
     table.insert(allWarps, currentWarps)
 
     -- Store the 24th tick positions in endwarps
     for angle, positions1 in pairs(currentWarps) do
         local twentyFourthTickPosition = positions1[24]
         if twentyFourthTickPosition then
             endwarps[angle] = { twentyFourthTickPosition, false }
         end
     end
 
 
         -- check if any of warp positions can stab anyone
         local lastDistance
         for angle, point in pairs(endwarps) do
             if CanBackstabFromPosition(cmd, point[1] + Vector3(0, 0, 75), false, target) then
                endwarps[angle] = {point[1], true}
 
                if Menu.Main.AutoWalk then
                    WalkTo(cmd, cachedLocalPlayer:GetAbsOrigin(), point[1])
                    warp.TriggerWarp()
                end
             end
         end
 
     if CanBackstabFromPosition(cmd, pLocalViewPos, true, target) then
         cmd:SetButtons(cmd.buttons | 1)  -- Perform backstab
     end
end

local function OnCreateMove(cmd)
    UpdateLocalPlayerCache()  -- Update local player data every tick
    UpdatePlayersCache()  -- Update player data every tick
    BestYawDifference = 0
    allWarps = {}
    endwarps = {}

    pLocal = entities.GetLocalPlayer()
    if not pLocal
    or pLocal:InCond(4) or pLocal:InCond(9)
    or pLocal:GetPropInt("m_bFeignDeathReady") == 1
    or not pLocal:GetPropInt("m_iClass") == 8 then return end

    -- Get the local player's active weapon
    local pWeapon = pLocal:GetPropEntity("m_hActiveWeapon")
    if not pWeapon or pWeapon:IsMeleeWeapon() == false then return end -- Return if the local player doesn't have an active weaponend

    if Menu.Main.AutoBackstab and CanBackstabFromPosition(cmd, pLocalViewPos, true, target) then
        cmd:SetButtons(cmd.buttons | 1)  -- Perform backstab
    end

    if Menu.Main.TrickstabModeSelected == 1 then
        Assistance(cmd, pLocal)
    elseif Menu.Main.TrickstabModeSelected == 2 then

    elseif Menu.Main.TrickstabModeSelected == 3 then
        
    elseif Menu.Main.TrickstabModeSelected == 4 then

    elseif Menu.Main.TrickstabModeSelected == 5 then

    elseif Menu.Main.TrickstabModeSelected == 6 then
        Debug(cmd, pLocal)
    end

end

local consolas = draw.CreateFont("Consolas", 17, 500)
local current_fps = 0
local function doDraw()
    draw.SetFont(consolas)
    draw.Color(255, 255, 255, 255)
    pLocal = entities.GetLocalPlayer()

    -- update fps every 100 frames
    if globals.FrameCount() % 100 == 0 then
      current_fps = math.floor(1 / globals.FrameTime())
    end
  
    draw.Text(5, 5, "[lmaobox | fps: " .. current_fps .. "]")

    -- Drawing all simulated positions in green
    for _, warps in ipairs(allWarps) do
        for angle, positions in pairs(warps) do
            for _, point in ipairs(positions) do
                local screenPos = client.WorldToScreen(Vector3(point.x, point.y, point.z))
                if screenPos then
                    draw.Color(0, 255, 0, 255)
                    draw.FilledRect(screenPos[1] - 2, screenPos[2] - 2, screenPos[1] + 2, screenPos[2] + 2)
                end
            end
        end
    end



    -- Drawing the 24th tick positions in red
    for angle, point in pairs(endwarps) do
        if point[2] == true then
            draw.Color(255, 255, 255, 255)
            local screenPos = client.WorldToScreen(Vector3(point[1].x, point[1].y, point[1].z))
            if screenPos then
                draw.FilledRect(screenPos[1] - 5, screenPos[2] - 5, screenPos[1] + 5, screenPos[2] + 5)
            end
        else
            draw.Color(255, 0, 0, 255)
            local screenPos = client.WorldToScreen(Vector3(point[1].x, point[1].y, point[1].z))
            if screenPos then
                draw.FilledRect(screenPos[1] - 5, screenPos[2] - 5, screenPos[1] + 5, screenPos[2] + 5)
            end
        end
    end


    local tartpoint = BestPosition
    if startPoint and movedir then
        local endPoint = startPoint + movedir
        local screenStart = client.WorldToScreen(startPoint)
        local screenEnd = client.WorldToScreen(endPoint)

        if screenStart and screenEnd then
            draw.Color(255, 0, 0, 255)  -- Red color for line
            draw.Line(screenStart[1], screenStart[2], screenEnd[1], screenEnd[2])
        end
    end
    

        --[[if TargetGlobalPlayer and cachedPlayers and TargetGlobalPlayer and TargetGlobalPlayer:IsValid() then
            local center = cachedPlayers[TargetGlobalPlayer:GetIndex()].hitboxPos
            local direction = cachedPlayers[TargetGlobalPlayer:GetIndex()].hitboxForward
            local range = 50 -- Adjust the range of the line as needed

            -- Set the color for the hitbox direction line
            draw.Color(0, 255, 0, 255) -- Blue color

            local screenPos = client.WorldToScreen(center)
            if screenPos ~= nil then
                local endPoint = center + direction * range
                local screenPos1 = client.WorldToScreen(endPoint)
                if screenPos1 ~= nil then
                    draw.Line(screenPos[1], screenPos[2], screenPos1[1], screenPos1[2])
                end
            end

            draw.Color(255, 0, 0, 255)
            local screenPos = client.WorldToScreen(center)
            if screenPos then
                draw.FilledRect(screenPos[1] - 5, screenPos[2] - 5, screenPos[1] + 5, screenPos[2] + 5)
            end

            --[[local screenCenter = client.WorldToScreen(pLocal:GetAbsOrigin())
            if screenCenter and movedir then
                local endPoint = pLocal:GetAbsOrigin() + movedir * 1
                local screenEndPoint = client.WorldToScreen(endPoint)
                if screenEndPoint then
                    draw.Color(81, 255, 54, 255)  -- Green color
                    draw.Line(screenCenter[1], screenCenter[2], screenEndPoint[1], screenEndPoint[2])
                end
            end
        end]]

        local player1 = entities.GetLocalPlayer()
        local hitboxes = player1:SetupBones(0x7FF00, globals.CurTime())
        
        -- Process only the first hitbox (assuming it has index 0)
        local boneMatrix = hitboxes[1]
        if boneMatrix then
            -- Extract rotation and translation components
            local rotation = {boneMatrix[1], boneMatrix[2], boneMatrix[3]}
            local translation = {x = boneMatrix[1][4], y = boneMatrix[2][4], z = boneMatrix[3][4]}
        
            -- Assuming boneMatrix[1][1], boneMatrix[2][1], boneMatrix[3][1] represent the forward vector
            local forward = {x = rotation[1][1], y = rotation[2][1], z = rotation[3][1]}
        
            -- Normalize the forward vector
            local length = math.sqrt(forward.x^2 + forward.y^2 + forward.z^2)
            forward.x = forward.x / length
            forward.y = forward.y / length
            forward.z = forward.z / length
        
            -- Adjust yaw by 90 degrees
            local adjustedYaw = math.atan(forward.y, forward.x) + math.rad(90)
            local adjustedForward = {x = math.cos(adjustedYaw), y = math.sin(adjustedYaw), z = 0}
        
            -- Calculate end point of the bone line (representing direction)
            local lineLength = 50  -- Change length as needed
            local endPoint = {
                x = translation.x + adjustedForward.x * lineLength,
                y = translation.y + adjustedForward.y * lineLength,
                z = translation.z + adjustedForward.z * lineLength
            }
        
            -- Convert 3D points to screen space
            local screenStart = client.WorldToScreen(Vector3(translation.x, translation.y, translation.z))
            local screenEnd = client.WorldToScreen(Vector3(endPoint.x, endPoint.y, endPoint.z))
        
            -- Draw line
            if screenStart and screenEnd then
                draw.Color(255, 255, 255, 255)  -- White color, change as needed
                draw.Line(screenStart[1], screenStart[2], screenEnd[1], screenEnd[2])
            end
        end



-----------------------------------------------------------------------------------------------------
                --Menu

    if input.IsButtonPressed( 72 )then
        toggleMenu()
    end

    if Lbox_Menu_Open == true and ImMenu and ImMenu.Begin("Auto Trickstab", true) then
        ImMenu.BeginFrame(1) -- tabs
            if ImMenu.Button("Main") then
                Menu.tabs.Main = true
                Menu.tabs.Advanced = false
                Menu.tabs.Visuals = false
            end
    
            if ImMenu.Button("Advanced") then
                Menu.tabs.Main = false
                Menu.tabs.Advanced = true
                Menu.tabs.Visuals = false
            end

            if ImMenu.Button("Visuals") then
                Menu.tabs.Main = false
                Menu.tabs.Advanced = false
                Menu.tabs.Visuals = true
            end

        ImMenu.EndFrame()
    
        if Menu.tabs.Main then
            ImMenu.BeginFrame(1)
            Menu.Main.Active = ImMenu.Checkbox("Active", Menu.Main.Active)
            ImMenu.EndFrame()

            ImMenu.BeginFrame(1)
                ImMenu.Text("                  Trickstab Modes")
            ImMenu.EndFrame()
    
            ImMenu.BeginFrame(1)
                if Menu.Main.TrickstabModeSelected ~= 1 and Menu.Main.TrickstabModeSelected ~= 6 then
                    ImMenu.Text("                not implemented yet ")
                end
            ImMenu.EndFrame()
            
            ImMenu.BeginFrame(1)
                Menu.Main.TrickstabModeSelected = ImMenu.Option(Menu.Main.TrickstabModeSelected, Menu.Main.TrickstabMode)
            ImMenu.EndFrame()
    
            ImMenu.BeginFrame(1)
            Menu.Main.AutoBackstab = ImMenu.Checkbox("Auto Backstab", Menu.Main.AutoBackstab)
            Menu.Main.AutoWalk = ImMenu.Checkbox("Auto Walk", Menu.Main.AutoWalk)
            ImMenu.EndFrame()
        end

        if Menu.tabs.Advanced then
            ImMenu.BeginFrame(1)
            Menu.Advanced.Simulations = ImMenu.Slider("Simulations", Menu.Advanced.Simulations, 3, 20)
            ImMenu.EndFrame()

            ImMenu.BeginFrame(1)
            Menu.Advanced.ColisionCheck = ImMenu.Checkbox("Colision Check", Menu.Advanced.ColisionCheck)
            Menu.Advanced.AdvancedPred = ImMenu.Checkbox("Advanced Pred", Menu.Advanced.AdvancedPred)
            ImMenu.EndFrame()
        end
        
        if Menu.tabs.Visuals then
            ImMenu.BeginFrame(1)
            Menu.Visuals.Active = ImMenu.Checkbox("Active", Menu.Visuals.Active)
            ImMenu.EndFrame()
    
            ImMenu.BeginFrame(1)
            Menu.Visuals.VisualizePoints = ImMenu.Checkbox("Simulations", Menu.Visuals.VisualizePoints)
            Menu.Visuals.VisualizeStabPoint = ImMenu.Checkbox("Stab Points", Menu.Visuals.VisualizeStabPoint)
            Menu.Visuals.VisualizeUsellesSimulations = ImMenu.Checkbox("Failed Checks", Menu.Visuals.VisualizeUsellesSimulations)
            ImMenu.EndFrame()
        end
        ImMenu.End()
    end
end

--[[ Remove the menu when unloaded ]]--
local function OnUnload()                                -- Called when the script is unloaded
    UnloadLib() --unloading lualib
    CreateCFG([[LBOX Auto trickstab lua]], Menu) --saving the config
    client.Command('play "ui/buttonclickrelease"', true) -- Play the "buttonclickrelease" sound
end

--[[ Unregister previous callbacks ]]--
callbacks.Unregister("CreateMove", "AtSM_CreateMove")            -- Unregister the "CreateMove" callback
callbacks.Unregister("Unload", "AtSM_Unload")                    -- Unregister the "Unload" callback
callbacks.Unregister("Draw", "AtSM_Draw")                        -- Unregister the "Draw" callback

--[[ Register callbacks ]]--
callbacks.Register("CreateMove", "AtSM_CreateMove", OnCreateMove)             -- Register the "CreateMove" callback
callbacks.Register("Unload", "AtSM_Unload", OnUnload)                         -- Register the "Unload" callback
callbacks.Register("Draw", "AtSM_Draw", doDraw)                               -- Register the "Draw" callback

--[[ Play sound when loaded ]]--
client.Command('play "ui/buttonclick"', true) -- Play the "buttonclick" sound when the script is loaded


--[[local function CreateSignalFolder()
    local folderPath = "C:\\gry\\steamapps\\steamapps\\common\\Team Fortress 2\\signals\\signal"

    local success, fullPath = filesystem.CreateDirectory(folderPath)
    if success then
        print("Signal folder created at: " .. tostring(fullPath))
    else
        print("Error: Unable to create signal folder.")
    end
end

-- Call the function to create the signal folder
CreateSignalFolder()]]
