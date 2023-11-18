
---@alias AimTarget { entity : Entity, angles : EulerAngles, factor : number }

package.path = package.path .. ";C:\\Users\\Terminatort8000\\AppData\\Local\\?.lua"

---@type boolean, lnxLib
local libLoaded, lnxLib = pcall(require, "lnxLib");
assert(libLoaded, "lnxLib not found, please install it!");
assert(lnxLib.GetVersion() >= 0.996, "lnxLib version is too old, please update it!");


local menuLoaded, ImMenu = pcall(require, "ImMenu")
assert(menuLoaded, "ImMenu not found, please install it!")
assert(ImMenu.GetVersion() >= 0.66, "ImMenu version is too old, please update it!")

local Math, Conversion = lnxLib.Utils.Math, lnxLib.Utils.Conversion
local WPlayer, WWeapon = lnxLib.TF2.WPlayer, lnxLib.TF2.WWeapon
local Helpers = lnxLib.TF2.Helpers
local Prediction = lnxLib.TF2.Prediction
local Fonts = lnxLib.UI.FontslnxLib

local Menu = { -- this is the config that will be loaded every time u load the script

    Version = 1.8, -- dont touch this, this is just for managing the config version

    tabs = { -- dont touch this, this is just for managing the tabs in the menu
        Main = true,
        Advanced = false,
        Visuals = false,
    },

    Main = {
        Active = true,  --disable lua
        TrickstabMode = { "Auto Warp + Auto Blink", "Auto Warp", "Auto Blink", "Assistance", "Assistance + Blink", "Debug"},
        TrickstabModeSelected = 1,
        AutoBackstab = true,
        AutoWalk = true,
        AutoAlign = true,
    },

    Advanced = {
        ColisionCheck = true,
        AdvancedPred = true,
        Simulations = 5,
        AutoWarp = true,
        AutoRecharge = true,
    },

    Visuals = {
        Active = true,
        VisualizePoints = true,
        VisualizeStabPoint = true,
        VisualizeUsellesSimulations = true,
        Attack_Circle = true,
        ForwardLine = false,
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

-- Function to calculate Manhattan Distance
local function ManhattanDistance(pos1, pos2)
    return math.abs(pos1.x - pos2.x) + math.abs(pos1.y - pos2.y) + math.abs(pos1.z - pos2.z)
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
    if vec == nil then return Vector3(0, 0, 0) end
    local length = math.sqrt(vec.x^2 + vec.y^2 + vec.z^2)
    return Vector3(vec.x / length, vec.y / length, vec.z / length)
end

local cachedLocalPlayer
local cachedPlayers = {}
local cachedLoadoutSlot2
local plocalAbsOrigin
local pLocalViewPos
local tickCount = 0
local pLocal = entities.GetLocalPlayer()
local vHitbox = { Vector3(-24, -24, 0), Vector3(24, 24, 82) }

local function GetHitboxForwardDirection(player, idx)
    local hitboxes = player:SetupBones()

    -- Process only the first hitbox (assuming it has index 0)
    local boneMatrix = hitboxes[idx]
    if boneMatrix then
        -- Extract rotation and translation components
        local rotation = {boneMatrix[1], boneMatrix[2], boneMatrix[3]}
        
        -- Assuming boneMatrix[1][1], boneMatrix[2][1], boneMatrix[3][1] represent the forward vector
        local forward = {x = rotation[1][1], y = rotation[2][1], z = rotation[3][1]}

        -- Rotate the forward vector by 90 degrees around the Z-axis
        local rotatedForward = {
            x = -forward.y,  -- x' = -y
            y = forward.x,   -- y' = x
            z = forward.z    -- z' = z (no change in z-axis)
        }

        -- Normalize the rotated vector
        local length = math.sqrt(rotatedForward.x^2 + rotatedForward.y^2 + rotatedForward.z^2)
        if length == 0 then return Vector3(0, 0, 0) end
        return Vector3(rotatedForward.x / length, rotatedForward.y / length, rotatedForward.z / length)
    end
    return nil
end


-- Function to update the cache for the local player and loadout slot
local function UpdateLocalPlayerCache()
    cachedLocalPlayer = entities.GetLocalPlayer()
    cachedLoadoutSlot2 = cachedLocalPlayer and cachedLocalPlayer:GetEntityForLoadoutSlot(2) or nil
    pLocalViewPos = cachedLocalPlayer and (cachedLocalPlayer:GetAbsOrigin() + cachedLocalPlayer:GetPropVector("localdata", "m_vecViewOffset[0]")) or nil
    plocalAbsOrigin = cachedLocalPlayer:GetAbsOrigin()
    AlignPos = nil
end

local function UpdatePlayersCache()
    local allPlayers = entities.FindByClass("CTFPlayer")
    for i, player in pairs(allPlayers) do
        if player:GetIndex() ~= cachedLocalPlayer:GetIndex() then
            local hitboxidx = 4
            local hitbox = player:GetHitboxes()[hitboxidx] -- Assuming hitboxID 4

            cachedPlayers[player:GetIndex()] = {
                idx = player:GetIndex(),
                entity = player,
                isAlive = player:IsAlive(),
                isDormant = player:IsDormant(),
                teamNumber = player:GetTeamNumber(),
                absOrigin = player:GetAbsOrigin(),
                viewOffset = player:GetPropVector("localdata", "m_vecViewOffset[0]"),
                hitboxPos = hitbox and (hitbox[1] + hitbox[2]) * 0.5 or nil,
                hitboxForward = GetHitboxForwardDirection(player, hitboxidx) -- Calculated forward direction
            }
        end
    end
end

-- Initialize cache
UpdateLocalPlayerCache()
UpdatePlayersCache()

-- Constants
local MAX_SPEED = 320  -- Maximum speed
local SIMULATION_TICKS = 23  -- Number of ticks for simulation
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

-- Cache structure
local simulationCache = {
    tickInterval = globals.TickInterval(),
    gravity = client.GetConVar("sv_gravity"),
    stepSize = 0,  -- This will be set based on the player object,
    flags = 0,
}

-- Function to update cache (call this when game environment changes)
local function UpdateSimulationCache(player)
    simulationCache.tickInterval = globals.TickInterval()
    simulationCache.gravity = client.GetConVar("sv_gravity")
    simulationCache.stepSize = player and player:GetPropFloat("localdata", "m_flStepSize") or 0
    simulationCache.flags = player and player:GetPropInt("m_fFlags") or 0
end

-- Simulates movement in a specified direction vector for a player over a given number of ticks
local function SimulateWalk(player, simulatedVelocity)
    local tick_interval = simulationCache.tickInterval
    local gravity = simulationCache.gravity
    local stepSize = simulationCache.stepSize
    local vUp = Vector3(0, 0, 1)
    local vStep = Vector3(0, 0, stepSize / 2)

    positions = {}  -- Store positions for each tick
    local lastP = plocalAbsOrigin
    local lastV = simulatedVelocity
    local flags = simulationCache.flags
    local lastG = (flags & 1 == 1)

    for i = 1, SIMULATION_TICKS do
        
        local pos = lastP + lastV * tick_interval
        local vel = lastV
        local onGround = lastG

        if Menu.Advanced.ColisionCheck then
            if Menu.Advanced.AdvancedPred then
                -- Forward collision
                local wallTrace = engine.TraceHull(lastP + vStep, pos + vStep, vHitbox[1], vHitbox[2], MASK_PLAYERSOLID_BRUSHONLY)
                if wallTrace.fraction < 1 then
                    pos.x, pos.y = handleForwardCollision(vel, wallTrace, vUp)
                end
            else
               -- Forward collision
                local wallTrace = engine.TraceHull(lastP + vStep, pos + vStep, vHitbox[1], vHitbox[2], MASK_PLAYERSOLID_BRUSHONLY)
                if wallTrace.fraction < 1 then
                    if wallTrace.entity and wallTrace.entity:IsValid() then
                        if wallTrace.entity:GetClass() == "CTFPlayer" then
                            -- Detected collision with a player, stop simulation
                            positions[23] = lastP
                            break
                        else
                            -- Handle collision with non-player entities
                            pos.x, pos.y = handleForwardCollision(vel, wallTrace, vUp)
                        end
                    else
                        -- Handle collision when no valid entity is involved
                        pos.x, pos.y = handleForwardCollision(vel, wallTrace, vUp)
                    end
                end
            end

            -- Ground collision
            local downStep = onGround and vStep or Vector3()
            local groundTrace = engine.TraceHull(pos + vStep, pos - downStep, vHitbox[1], vHitbox[2], MASK_PLAYERSOLID_BRUSHONLY)
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

-- Function to calculate yaw angle between two points
local function CalculateYawAngle(point1, direction)
    -- Determine a point along the forward direction
    local forwardPoint = point1 + direction * 104  -- 'someDistance' is an arbitrary distance

    -- Calculate the difference in the x and y coordinates
    local dx = forwardPoint.x - point1.x
    local dy = forwardPoint.y - point1.y

    -- Calculate the yaw angle
    local yaw
    if dx ~= 0 then
        yaw = math.atan(dy / dx)
    else
        -- Handle the case where dx is 0 to avoid division by zero
        if dy > 0 then
            yaw = math.pi / 2  -- 90 degrees
        else
            yaw = -math.pi / 2  -- -90 degrees
        end
    end

    -- Adjust yaw to correct quadrant
    if dx < 0 then
        yaw = yaw + math.pi  -- Adjust for second and third quadrants
    end

    return math.deg(yaw)  -- Convert radians to degrees
end

local function PositionYaw(source, dest)
    local delta = dest - source  -- delta vector from source to dest

    local yaw
    if delta.x ~= 0 then
        yaw = math.atan(delta.y / delta.x)
    else
        -- Handle the case where dx is 0 to avoid division by zero
        if delta.y > 0 then
            yaw = math.pi / 2  -- 90 degrees
        else
            yaw = -math.pi / 2  -- -90 degrees
        end
    end

    -- Adjust yaw to correct quadrant
    if delta.x < 0 then
        yaw = yaw + math.pi  -- Adjust for second and third quadrants
    end

    return math.deg(yaw)  -- Convert radians to degrees
end


local function IsWithin90DegreesFOV(angle1, angle2)
    local difference = angle1 - angle2

    local normalizedDifference = NormalizeYaw(difference)

    local absoluteDifference = math.abs(normalizedDifference)

    return absoluteDifference <= 90
end

-- Constants
local BACKSTAB_RANGE = 97  -- Hammer units
local BACKSTAB_ANGLE = 175  -- Degrees in radians for dot product calculation

local BestYawDifference = 180
local BestPosition
local AlignPos = nil

-- Updated function with Manhattan Distance
local function CanBackstabFromPosition(cmd, viewPos, real, targetPlayerGlobal)
    if real then
        for _, targetPlayer in pairs(cachedPlayers) do
            if targetPlayer.isAlive and not targetPlayer.isDormant and targetPlayer.teamNumber ~= cachedLocalPlayer:GetTeamNumber() then
                local distance = ManhattanDistance(viewPos, targetPlayer.hitboxPos)
                if distance < BACKSTAB_RANGE then
                    local ang = PositionAngles(viewPos, targetPlayer.hitboxPos)
                    cmd:SetViewAngles(ang.pitch, ang.yaw, 0)
                    if cachedLoadoutSlot2:GetPropInt("m_bReadyToBackstab") == 257 then
                        return true
                    end
                end
            end
        end
    else
         local targetPlayer = cachedPlayers[targetPlayerGlobal:GetIndex()]
        if targetPlayer and targetPlayer.isAlive and not targetPlayer.isDormant and targetPlayer.teamNumber ~= cachedLocalPlayer:GetTeamNumber() then
            local distance = ManhattanDistance(viewPos, targetPlayer.hitboxPos)
            if distance < BACKSTAB_RANGE then
                -- Invert the yaw angle by adding 180 degrees
                local enemyYaw = CalculateYawAngle(targetPlayer.hitboxPos, targetPlayer.hitboxForward)
                enemyYaw = NormalizeYaw(enemyYaw)  -- Normalize

                local spyYaw = PositionYaw(targetPlayer.hitboxPos, viewPos)

                local yawDifference = math.abs(NormalizeYaw(spyYaw - enemyYaw))

                if IsWithin90DegreesFOV(spyYaw, enemyYaw) and yawDifference > BestYawDifference then
                    BestYawDifference = yawDifference
                    BestPosition = viewPos
                end
                return IsWithin90DegreesFOV(spyYaw, enemyYaw)
            end
        end
        if BestPosition == nil then
            AlignPos = viewPos
        end
    end
    return false
end




local function GetBestTarget(me)
    local players = entities.FindByClass("CTFPlayer")
    local bestTarget = nil
    local maxDistance = 220  -- Adjust as needed, considering Manhattan distance

    for _, player in pairs(players) do
        if player ~= nil and player:IsAlive() and not player:IsDormant()
        and player ~= me and player:GetTeamNumber() ~= me:GetTeamNumber() then
            local delta = me:GetAbsOrigin() - player:GetAbsOrigin()
            local manhattanDistance = math.abs(delta.x) + math.abs(delta.y) + math.abs(delta.z)

            if manhattanDistance <= maxDistance then
                if bestTarget == nil or manhattanDistance < (math.abs(bestTarget:GetAbsOrigin().x - me:GetAbsOrigin().x)
                    + math.abs(bestTarget:GetAbsOrigin().y - me:GetAbsOrigin().y)
                    + math.abs(bestTarget:GetAbsOrigin().z - me:GetAbsOrigin().z)) then
                    bestTarget = player
                end
            end
        end
    end

    return bestTarget
end
local function CalculateTrickstab(player, target, leftOffset, rightOffset, forwardVector)
    local endPositions = {}
    local playerPos = player:GetAbsOrigin()
    local targetPos = target:GetAbsOrigin()
    local centralAngle = math.deg(math.atan(targetPos.y - playerPos.y, targetPos.x - playerPos.x))

    local totalSimulations = Menu.Advanced.Simulations
    local evenDistribution = totalSimulations % 2 == 0

    -- Simulate special angles for left and right offsets
    endPositions[centralAngle + leftOffset] = SimulateWalk(player, Vector3(math.cos(math.rad(centralAngle + leftOffset)), math.sin(math.rad(centralAngle + leftOffset)), 0) * MAX_SPEED)
    endPositions[centralAngle + rightOffset] = SimulateWalk(player, Vector3(math.cos(math.rad(centralAngle + rightOffset)), math.sin(math.rad(centralAngle + rightOffset)), 0) * MAX_SPEED)

    -- Simulate forward direction using provided forward vector
    local normalizedForwardVector = NormalizeVector(forwardVector)
    endPositions["forward"] = SimulateWalk(player, normalizedForwardVector * MAX_SPEED)

    -- Adjust simulations for remaining angles
    local simulationsToDistribute = totalSimulations - 4
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
local function ComputeMove(cmd, a, b)
    local diff = (b - a)
    if diff:Length() == 0 then return Vector3(0, 0, 0) end

    local x = diff.x
    local y = diff.y
    local vSilent = Vector3(x, y, 0)

    local ang = vSilent:Angles()
    local cPitch, cYaw, cRoll = engine.GetViewAngles():Unpack()
    local yaw = math.rad(ang.y - cYaw)
    local pitch = math.rad(ang.x - cPitch)
    local move = Vector3(math.cos(yaw) * 302, -math.sin(yaw) * 320, -math.cos(pitch) * 320)

    return move
end

-- Global variable to store the move direction
local movedir

-- Walks to the destination and sets the global move direction
---@param userCmd UserCmd
---@param localPlayer Entity
---@param destination Vector3
local function WalkTo(cmd, Pos, destination)
    local localPos = Pos
    local result = ComputeMove(cmd, localPos, destination)

    cmd:SetButtons(cmd.buttons & (~IN_FORWARD))
    cmd:SetButtons(cmd.buttons & (~IN_BACK))
    cmd:SetButtons(cmd.buttons & (~IN_LEFT))
    cmd:SetButtons(cmd.buttons & (~IN_RIGHT))

    cmd:SetForwardMove(result.x)
    cmd:SetSideMove(result.y)
    --userCmd:SetUpMove(result.z)

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

-- Function to check if there's a collision between two AABBs
local function checkAABBAABBCollision(aabb1Min, aabb1Max, aabb2Min, aabb2Max)
    return (aabb1Min.x <= aabb2Max.x and aabb1Max.x >= aabb2Min.x) and
           (aabb1Min.y <= aabb2Max.y and aabb1Max.y >= aabb2Min.y) and
           (aabb1Min.z <= aabb2Max.z and aabb1Max.z >= aabb2Min.z)
end

local cachedoffset = 25

-- Function to calculate the right offset with additional collision simulation
local function calculateRightOffset(pLocalPos, targetPos, enemyAABB, initialOffset)
    local radius = calculateRadiusOfSquare(25)  -- Assume this function correctly calculates the radius
    local angleIncrement = 5
    local maxIterations = 360 / angleIncrement
    local initialDirection = NormalizeVector(targetPos - pLocalPos)
    local startAngle = initialOffset or 0
    local stepSize = 5  -- Step size for incremental movement

    for i = 0, maxIterations do
        local currentAngle = (startAngle + i * angleIncrement) % 360
        local radianAngle = math.rad(currentAngle)
        local rotatedDirection = Vector3(
            initialDirection.x * math.cos(radianAngle) - initialDirection.y * math.sin(radianAngle),
            initialDirection.x * math.sin(radianAngle) + initialDirection.y * math.cos(radianAngle),
            0
        )

        local offsetVector = rotatedDirection * radius * 2
        local testPos = pLocalPos + offsetVector

        -- Check for sphere collision first
        if not checkSphereCollision(testPos, radius, targetPos, radius) then
            local clearPathFound = false
            for step = 0, radius, stepSize do
                local incrementalPos = pLocalPos + rotatedDirection * (radius - step)
                local incrementalAABBMin = incrementalPos - Vector3(radius, radius, radius)
                local incrementalAABBMax = incrementalPos + Vector3(radius, radius, radius)

                -- Perform AABB collision check
                if not checkAABBAABBCollision(incrementalAABBMin, incrementalAABBMax, enemyAABB[1], enemyAABB[2]) then
                    clearPathFound = true
                    break
                end
            end

            if clearPathFound then
                cachedoffset = currentAngle
                return currentAngle
            end
        end
    end

    return nil -- No unobstructed path found
end


local allWarps = {}
local endwarps = {}
local TargetGlobalPlayer
local global_CMD

local function Assistance(cmd, target)
    global_CMD = cmd

    pLocal = entities.GetLocalPlayer()
    -- Store all potential positions in allWarps

    local RightOffst = calculateRightOffset(pLocal:GetAbsOrigin(), target:GetAbsOrigin(), 25)
    local LeftOffset = -RightOffst --calculateLeftOffset(pLocalPos, targetPos, vHitbox, Right)

    local currentWarps = CalculateTrickstab(pLocal, target, RightOffst , LeftOffset)
    table.insert(allWarps, currentWarps)

        -- Store the 23th tick positions in endwarps
        for angle, positions1 in pairs(currentWarps) do
            local twentyFourthTickPosition = positions1[23]
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

local function AutoWarp(cmd, target)
    local RightOffst = calculateRightOffset(pLocal:GetAbsOrigin(), target:GetAbsOrigin(), { Vector3(-24, -24, 0), Vector3(24, 24, 82) }, 25)
    local LeftOffset = -RightOffst --calculateLeftOffset(pLocalPos, targetPos, vHitbox, Right)

    local currentWarps = CalculateTrickstab(pLocal, target, RightOffst , LeftOffset)
    table.insert(allWarps, currentWarps)

    -- Store the 24th tick positions in endwarps
    for angle, positions1 in pairs(currentWarps) do
        local twentyFourthTickPosition = positions1[23]
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

               if Menu.Advanced.AutoWarp and warp.CanWarp() then
                   warp.TriggerWarp()
               end
            end
        end
end

local function AutoWarp_AutoBlink(cmd, target)
    local RightOffst = calculateRightOffset(pLocal:GetAbsOrigin(), target:GetAbsOrigin(), { Vector3(-24, -24, 0), Vector3(24, 24, 82) }, 25)
    local LeftOffset = -RightOffst --calculateLeftOffset(pLocalPos, targetPos, vHitbox, Right)

    local currentWarps = CalculateTrickstab(pLocal, target, RightOffst , LeftOffset)
    table.insert(allWarps, currentWarps)

    -- Store the 24th tick positions in endwarps
    for angle, positions1 in pairs(currentWarps) do
        local twentyFourthTickPosition = positions1[23]
        if twentyFourthTickPosition then
            endwarps[angle] = { twentyFourthTickPosition, false }
        end
    end


            -- Main logic
    local lastDistance
    for angle, point in pairs(endwarps) do
        local canBackstab = CanBackstabFromPosition(cmd, point[1] + Vector3(0, 0, 75), false, target)
        local canWarp = warp.CanWarp()

        if canBackstab then
            endwarps[angle] = {point[1], true}

            if Menu.Main.AutoWalk then
                WalkTo(cmd, cachedLocalPlayer:GetAbsOrigin(), point[1])
                if not canWarp and warp.GetChargedTicks() < 1 then
                    gui.SetValue("fake lag", 1)
                end
            end

            if Menu.Advanced.AutoWarp and canTriggerWarp() then
                warp.TriggerWarp()
            end
        end
    end
end

local function Debug(cmd, target)
     local RightOffst = calculateRightOffset(pLocal:GetAbsOrigin(), target:GetAbsOrigin(), vHitbox)
     local LeftOffset = -RightOffst
 
     local currentWarps = CalculateTrickstab(pLocal, target, RightOffst , LeftOffset)
     table.insert(allWarps, currentWarps)
 
     -- Store the 24th tick positions in endwarps
     for angle, positions1 in pairs(currentWarps) do
         local twentyFourthTickPosition = positions1[23]
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

                if Menu.Advanced.AutoWarp and warp.CanWarp() then
                    warp.TriggerWarp()
                end
             end
         end
end

local function OnCreateMove(cmd)
    UpdateLocalPlayerCache()  -- Update local player data every tick
    UpdatePlayersCache()  -- Update player data every tick
    --UpdateBacktrackData() --update position and angle data for backtrack
    BestYawDifference = 0
    allWarps = {}
    endwarps = {}

    --cmd:SetButtons(cmd.buttons & (~IN_JUMP))

    pLocal = entities.GetLocalPlayer()
    if not pLocal
    or pLocal:InCond(4) or pLocal:InCond(9)
    or pLocal:GetPropInt("m_bFeignDeathReady") == 1
    or not pLocal:GetPropInt("m_iClass") == 8
    or not pLocal:IsAlive() then return end

    local target = GetBestTarget(cachedLocalPlayer)
    if target == nil then
            gui.SetValue("fake lag", 0)

            if Menu.Advanced.AutoRecharge and not warp.IsWarping() and warp.GetChargedTicks() < 24 then -- if cannot dt/warp
                warp.TriggerCharge()
            end
        return
    end
    TargetGlobalPlayer = target

    -- Get the local player's active weapon
    local pWeapon = pLocal:GetPropEntity("m_hActiveWeapon")
    if not pWeapon or pWeapon:IsMeleeWeapon() == false then return end -- Return if the local player doesn't have an active weaponend

    UpdateSimulationCache(pLocal)

    if Menu.Main.AutoBackstab and CanBackstabFromPosition(cmd, pLocalViewPos, true, target) then
        cmd:SetButtons(cmd.buttons | IN_ATTACK)   -- Perform backstab
        gui.SetValue("fake lag", 0)
        if Menu.Advanced.AutoRecharge and not warp.IsWarping() and warp.GetChargedTicks() < 24 then -- if cannot dt/warp
            warp.TriggerCharge()
        end
    end

    if Menu.Main.TrickstabModeSelected == 1 then
        AutoWarp(cmd, target)
    elseif Menu.Main.TrickstabModeSelected == 2 then
        AutoWarp_AutoBlink(cmd, target)
    elseif Menu.Main.TrickstabModeSelected == 3 then
        
    elseif Menu.Main.TrickstabModeSelected == 4 then
        Assistance(cmd, target)
    elseif Menu.Main.TrickstabModeSelected == 5 then

    elseif Menu.Main.TrickstabModeSelected == 6 then
        Debug(cmd, target)
    end

end

    -- Function to check for wall collision and adjust circle points
    local function CheckCollisionAndAdjustPoint(center, point, radius)
        -- Perform a trace line from the center to the point
        local traceResult = engine.TraceLine(center, point, MASK_SOLID)

        -- If the trace hits something before reaching the full radius, adjust the point
        if traceResult.fraction < 1 then
            local distanceToWall = radius * traceResult.fraction
            local direction = NormalizeVector(point - center)
            return center + direction * distanceToWall
        end

        return point
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
  
    draw.Text(5, 5, "[Auto trickstab | fps: " .. current_fps .. "]")

    if Menu.Visuals.Active then

        if Menu.Visuals.VisualizePoints then
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
        end

        -- Draw the circle with collision detection
        if Menu.Visuals.Attack_Circle and pLocal then
            local segments = 32
            local radius = 104
            local center = pLocal:GetAbsOrigin()
            local angleStep = (2 * math.pi) / segments

            for i = 1, segments do
                local startX = center.x + radius * math.cos(angleStep * (i - 1))
                local startY = center.y + radius * math.sin(angleStep * (i - 1))
                local endX = center.x + radius * math.cos(angleStep * i)
                local endY = center.y + radius * math.sin(angleStep * i)

                local startPoint = Vector3(startX, startY, center.z)
                local endPoint = Vector3(endX, endY, center.z)

                -- Check collision for both start and end points
                startPoint = CheckCollisionAndAdjustPoint(center, startPoint, radius)
                endPoint = CheckCollisionAndAdjustPoint(center, endPoint, radius)

                -- Convert start and end points to screen space
                local screenStart = client.WorldToScreen(startPoint)
                local screenEnd = client.WorldToScreen(endPoint)

                -- Draw each line segment
                if screenStart and screenEnd then
                    draw.Line(screenStart[1], screenStart[2], screenEnd[1], screenEnd[2])
                end
            end
        end



        if Menu.Visuals.VisualizeStabPoint then
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
        end

        if Menu.Visuals.ForwardLine then
            if TargetGlobalPlayer then
                local forward = cachedPlayers[TargetGlobalPlayer:GetIndex()].hitboxForward
                local hitboxPos = cachedPlayers[TargetGlobalPlayer:GetIndex()].hitboxPos

                -- Calculate end point of the line in the forward direction
                local lineLength = 50  -- Length of the line, you can adjust this as needed
                local endPoint = Vector3(
                    hitboxPos.x + forward.x * lineLength,
                    hitboxPos.y + forward.y * lineLength,
                    hitboxPos.z + forward.z * lineLength
                )
        
                -- Convert 3D points to screen space
                local screenStart = client.WorldToScreen(hitboxPos)
                local screenEnd = client.WorldToScreen(endPoint)
        
                -- Draw line
                if screenStart and screenEnd then
                    draw.Color(0, 255, 255, 255)  -- White color, change as needed
                    draw.Line(screenStart[1], screenStart[2], screenEnd[1], screenEnd[2])
                end
            end
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
                Menu.Main.TrickstabModeSelected = ImMenu.Option(Menu.Main.TrickstabModeSelected, Menu.Main.TrickstabMode)
            ImMenu.EndFrame()
    
            ImMenu.BeginFrame(1)
            Menu.Main.AutoBackstab = ImMenu.Checkbox("Auto Backstab", Menu.Main.AutoBackstab)
            Menu.Main.AutoWalk = ImMenu.Checkbox("Auto Walk", Menu.Main.AutoWalk)
            Menu.Main.AutoAlign = ImMenu.Checkbox("Auto Align", Menu.Main.AutoAlign)
            ImMenu.EndFrame()
        end

        if Menu.tabs.Advanced then
            ImMenu.BeginFrame(1)
            Menu.Advanced.Simulations = ImMenu.Slider("Simulations", Menu.Advanced.Simulations, 3, 20)
            ImMenu.EndFrame()

            ImMenu.BeginFrame(1)
            Menu.Advanced.AutoWarp = ImMenu.Checkbox("Auto Warp", Menu.Advanced.AutoWarp)
            Menu.Advanced.AutoRecharge = ImMenu.Checkbox("Auto Recharge", Menu.Advanced.AutoRecharge)
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
            ImMenu.EndFrame()

            ImMenu.BeginFrame(1)
            Menu.Visuals.Attack_Circle = ImMenu.Checkbox("Attack Circle", Menu.Visuals.Attack_Circle)
            Menu.Visuals.ForwardLine = ImMenu.Checkbox("Forward Line", Menu.Visuals.ForwardLine)
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
