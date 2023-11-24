
---@alias AimTarget { entity : Entity, angles : EulerAngles, factor : number }

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

    Version = 2.2, -- dont touch this, this is just for managing the config version

    tabs = { -- dont touch this, this is just for managing the tabs in the menu
        Main = true,
        Advanced = false,
        Visuals = false,
    },

    Main = {
        Active = true,  --disable lua
        TrickstabMode = { "Auto Warp + Auto Blink", "Auto Warp", "Auto Blink", "Assistance", "Assistance + Blink", "Debug"},
        TrickstabModeSelected = 1,
        AutoWalk = true,
        AutoAlign = true,
    },

    Advanced = {
        ColisionCheck = true,
        AdvancedPred = true,
        Simulations = 3,
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

local pLocal = entities.GetLocalPlayer()
local cachedLoadoutSlot2
local pLocalPos
local pLocalViewPos
local tickCount = 0
local vHitbox = { Vector3(-24, -24, 0), Vector3(24, 24, 82) }
local TargetPlayer = {}
local allWarps = {}
local endwarps = {}
-- Constants
local BACKSTAB_RANGE = 66  -- Hammer units
local BACKSTAB_ANGLE = 160  -- Degrees in radians for dot product calculation
local cachedoffset = 25
local BestYawDifference = 180
local BestPosition
local AlignPos = nil

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

    local pitch = math.atan(delta.z / math.sqrt(delta.x * delta.x + delta.y * delta.y)) * M_RADPI
    local yaw = 0

    if delta.x == 0 and delta.y == 0 then
        yaw = 0
    elseif delta.x >= 0 then
        yaw = math.atan(delta.y / delta.x) * M_RADPI + 180
    else
        yaw = math.atan(delta.y / delta.x) * M_RADPI
    end

    if isNaN(pitch) then pitch = 0 end
    if isNaN(yaw) then yaw = 0 end

    return EulerAngles(pitch, yaw, 0)
end


-- Normalizes a vector to a unit vector
local function NormalizeVector(vec)
    if vec == nil then return Vector3(0, 0, 0) end
    local length = math.sqrt(vec.x^2 + vec.y^2 + vec.z^2)
    if length == 0 then return Vector3(0, 0, 0) end
    return Vector3(vec.x / length, vec.y / length, vec.z / length)
end

local function GetHitboxForwardDirection(player, idx)
    local hitboxes = player:SetupBones()

    -- Process only the specified hitbox
    local boneMatrix = hitboxes[idx]
    if boneMatrix then
        -- Extract rotation and translation components
        local rotation = {boneMatrix[1], boneMatrix[2], boneMatrix[3]}
        
        -- Assuming boneMatrix[1][1], boneMatrix[2][1], boneMatrix[3][1] represent the forward vector
        local forward = {x = rotation[1][1], y = rotation[2][1], z = rotation[3][1]}

        -- Check if the player's class is Engineer (class index 8)
        if player:GetPropInt("m_iClass") == 9 then
            -- Invert the forward vector for Engineers
            forward.x = -forward.x
            forward.y = -forward.y
        end

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
    pLocal = entities.GetLocalPlayer()
    if not pLocal
    or pLocal:GetPropInt("m_iClass") ~= 8
    or not pLocal:IsAlive()
    or pLocal:InCond(4) or pLocal:InCond(9)
    or pLocal:GetPropInt("m_bFeignDeathReady") == 1
    then return false end

    --cachedLoadoutSlot2 = pLocal and pLocal:GetEntityForLoadoutSlot(2) or nil
    pLocalViewPos = pLocal and (pLocal:GetAbsOrigin() + pLocal:GetPropVector("localdata", "m_vecViewOffset[0]")) or nil
    pLocalPos = pLocal:GetAbsOrigin()
    --AlignPos = nil
    return pLocal
end

local function UpdateTarget()
    local allPlayers = entities.FindByClass("CTFPlayer")
    local bestTargetDetails = nil
    local maxDistance = 220  -- Attack range plus warp distance
    local bestDistance = maxDistance + 1  -- Initialize with a value larger than max distance
    local found = false
    for _, player in pairs(allPlayers) do
        if player:IsAlive() and not player:IsDormant() and not (player:GetTeamNumber() == pLocal:GetTeamNumber()) then
            local playerAbsOrigin = player:GetAbsOrigin()
            local delta = pLocalPos - playerAbsOrigin
            local manhattanDistance = math.abs(delta.x) + math.abs(delta.y) + math.abs(delta.z)

            if manhattanDistance <= maxDistance then
                local hitboxidx = 4  -- Assuming hitboxID 4
                local hitbox = player:GetHitboxes()[hitboxidx]
                if hitbox then
                    TargetPlayer = {
                        idx = player:GetIndex(),
                        entity = player,
                        Pos = playerAbsOrigin,
                        viewOffset = player:GetPropVector("localdata", "m_vecViewOffset[0]"),
                        hitboxPos = (hitbox[1] + hitbox[2]) * 0.5,
                        hitboxForward = GetHitboxForwardDirection(player, 1)
                    }

                    if manhattanDistance < bestDistance then
                        bestTargetDetails = TargetPlayer
                        bestDistance = manhattanDistance
                    end
                    found = true
                end
            end
        end
    end
    if found then
        return TargetPlayer
    else
        return nil
    end
end


-- Initialize cache
UpdateLocalPlayerCache()

-- Constants
local MAX_SPEED = 320  -- Maximum speed
local SIMULATION_TICKS = 25  -- Number of ticks for simulation
local positions = {}

local FORWARD_COLLISION_ANGLE = 55
local GROUND_COLLISION_ANGLE_LOW = 45
local GROUND_COLLISION_ANGLE_HIGH = 55

local function BasicTraceHull(startPoint, endPoint, hitbox, traceMask)
    local direction = (endPoint - startPoint):Normalize()
    
    -- Determine hitbox size and calculate offset
    local hitboxSize = hitbox.max - hitbox.min
    local hitboxOffset = hitboxSize * 0.5 * direction

    -- Adjust the start position based on hitbox size
    local adjustedStart = startPoint + hitboxOffset

    -- Determine the closest hitbox corner in the direction
    local closestHitboxCorner = Vector3(
        direction.x > 0 and hitbox.max.x or hitbox.min.x,
        direction.y > 0 and hitbox.max.y or hitbox.min.y,
        hitbox.min.z -- Bottom corner
    )

    local closestCornerPoint = startPoint + closestHitboxCorner
    local sidewaysTrace = engine.TraceLine(adjustedStart, closestCornerPoint, traceMask)

    if sidewaysTrace.Hit then
        -- If there's a collision, do a trace from start to collision point
        local collisionTrace = engine.TraceLine(startPoint, sidewaysTrace.HitPos, traceMask)
        return collisionTrace
    else
        -- If no collision, return the original sideways trace result
        return sidewaysTrace
    end
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


local function CheckYawDelta(angle1, angle2)
    local difference = angle1 - angle2

    local normalizedDifference = NormalizeYaw(difference)

    -- Assuming you want to check if within a 120-degree arc to the right and a 40-degree arc to the left of the back
    local withinRightArc = normalizedDifference > -60 and normalizedDifference <= 0
    local withinLeftArc = normalizedDifference < 90 and normalizedDifference >= 0

    return withinRightArc or withinLeftArc
end

-- Assuming TargetPlayer is a global or accessible object with Pos and hitbox details
-- Also assuming Vector3 is a properly defined class with necessary methods

local function checkInRange(spherePos, sphereRadius)
    -- Validate inputs
    if not (spherePos and sphereRadius) then
        error("Invalid input to checkInRange function")
    end

    -- Ensure sphereRadius is positive
    if sphereRadius < 0 then
        error("Sphere radius must be positive")
    end

    -- Retrieve target player's position and hitbox
    local targetPos = TargetPlayer.Pos
    local hitbox_min = (targetPos + vHitbox[1]) -- Replace with actual way to get 
    local hitbox_max = (targetPos + vHitbox[2]) -- Replace with actual way to get hitbox max

    -- Calculate the closest point on the hitbox to the sphere
    local closestPoint = Vector3(
        math.max(spherePos.x, hitbox_min.x, math.min(spherePos.x, hitbox_max.x)),
        math.max(spherePos.y, hitbox_min.y, math.min(spherePos.y, hitbox_max.y)),
        math.max(spherePos.z, hitbox_min.z, math.min(spherePos.z, hitbox_max.z))
    )

    -- Calculate the vector from the closest point to the sphere center
    local distanceVector = (spherePos - closestPoint)
    local distance = math.abs(distanceVector:Length()) -- Assuming a Length method in Vector3

    -- Check if the sphere is in range (including intersecting)
    local inRange = distance <= sphereRadius

        -- Compare the distance along the vector to the sum of the radius
        if sphereRadius >= distance then
            -- InRange detected (including intersecting)
            return true, closestPoint

        else
            -- No InRange
            return false, nil
        end
end


local function CheckBackstab(testPoint)
    -- Check if testPoint is valid
    if not testPoint then
        print("Invalid testPoint")
        return nil
    end

    local viewPos = testPoint + Vector3(0, 0, 75) -- Adjust for viewpoint

    if TargetPlayer and TargetPlayer.Pos and TargetPlayer.hitboxForward then
        local InRange, closestPoint = checkInRange(viewPos, 66) -- Assuming checkInRange is defined correctly
        if InRange and TargetPlayer.hitboxForward then
            local enemyYaw = CalculateYawAngle(TargetPlayer.hitboxPos, TargetPlayer.hitboxForward)
            enemyYaw = NormalizeYaw(enemyYaw) -- Normalize

            local spyYaw = PositionYaw(TargetPlayer.Pos, viewPos)
            local Delta = math.abs(NormalizeYaw(spyYaw - enemyYaw))

            local canBackstab = CheckYawDelta(spyYaw, enemyYaw) -- Assuming CheckYawDelta is defined correctly
            return canBackstab, Delta
        end
    else
        print("TargetPlayer is nil")
    end

    return false, nil
end

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
    stepSize = pLocal and pLocal:GetPropFloat("localdata", "m_flStepSize") or 0,
    flags = pLocal and pLocal:GetPropInt("m_fFlags") or 0
}

-- Function to update cache (call this when game environment changes)
local function UpdateSimulationCache()
    simulationCache.tickInterval = globals.TickInterval()
    simulationCache.gravity = client.GetConVar("sv_gravity")
    simulationCache.stepSize = pLocal and pLocal:GetPropFloat("localdata", "m_flStepSize") or 0
    simulationCache.flags = pLocal and pLocal:GetPropInt("m_fFlags") or 0
end

-- Simulates movement in a specified direction vector for a player over a given number of ticks
local function SimulateDash(simulatedVelocity, ticks)
    local tick_interval = simulationCache.tickInterval
    local gravity = simulationCache.gravity
    local stepSize = simulationCache.stepSize
    local vUp = Vector3(0, 0, 1)
    local vStep = Vector3(0, 0, stepSize / 2)

    local localPositions = {}  -- Use a local variable to store positions for this simulation
    local lastP = pLocalPos
    local lastV = simulatedVelocity
    local flags = simulationCache.flags
    local lastG = (flags & 1 == 1)
    local Endpos = Vector3(0, 0, 0)

    for i = 1, ticks do
        
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
        table.insert(positions, lastP)  -- Store position for this tick in the local variable
        Endpos = lastP
    end

    table.insert(endwarps, {lastP, CheckBackstab(lastP)})  -- Store position for this tick in the local variable
    return Endpos
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

-- Function to calculate the right offset with additional collision simulation
local function calculateRightOffset(enemyAABB, initialOffset)
    local radius = 25  -- Assume this function correctly calculates the radius
    local angleIncrement = 5
    local maxIterations = 360 / angleIncrement
    local initialDirection = NormalizeVector(TargetPlayer.Pos - pLocalPos) -- Corrected variable name
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

        -- Check for sphere collision
        if not checkSphereCollision(testPos, radius, TargetPlayer.Pos, radius) then
            local clearPathFound = false
            for step = 0, radius, stepSize do
                local incrementalPos = pLocalPos + rotatedDirection * (radius - step)
                local incrementalAABBMin = incrementalPos - Vector3(radius, radius, radius)
                local incrementalAABBMax = incrementalPos + Vector3(radius, radius, radius)

                if not checkAABBAABBCollision(incrementalAABBMin, incrementalAABBMax, enemyAABB[1], enemyAABB[2]) then
                    clearPathFound = true
                    break
                end
            end

            if clearPathFound then
                -- cachedoffset = currentAngle  -- Uncomment if cachedoffset is used elsewhere
                return currentAngle
            end
        end
    end

    return nil -- No unobstructed path found
end

local cleartiemr = 50
local function CalculateTrickstab()
    -- Ensure pLocal and TargetPlayer are valid and have position data
    if not pLocal or not pLocal:GetAbsOrigin() then
        print("Local player position is undefined")
        return
    end

    if not TargetPlayer or not TargetPlayer.Pos then
        print("Target player or target player position is undefined")
        return
    end

    local playerPos = pLocal:GetAbsOrigin()  -- Get local player position
    local targetPos = TargetPlayer.Pos
    local rightOffset = calculateRightOffset(vHitbox, 25)  -- Calculate right offset
    local leftOffset = -rightOffset
    local centralAngle = math.deg(math.atan(targetPos.y - playerPos.y, targetPos.x - playerPos.x))
    local backstabPosition = nil

    local Disguised = pLocal:InCond(TFCond_Disguised)
    MAX_SPEED = Disguised and pLocal:EstimateAbsVelocity():Length() or 320

    local totalSimulations = math.max(3, math.min(Menu.Advanced.Simulations or 24, 20))
    local angleIncrement = (rightOffset - leftOffset) / (totalSimulations - 1)

    -- Function to validate a test point
    local function isValidTestPoint(point)
        return point and point.x and point.y and point.z
    end

    -- Function to create a direction vector from an angle
    local function createDirectionVector(angle)
        local radianAngle = math.rad(angle)
        return Vector3(math.cos(radianAngle), math.sin(radianAngle), 0) * MAX_SPEED
    end

    -- Function to check and simulate backstab for a given angle
    local function simulateAndCheckBackstab(angle)
        local directionVector = createDirectionVector(angle)
        local testPoint = SimulateDash(directionVector, SIMULATION_TICKS)
        return isValidTestPoint(testPoint) and CheckBackstab(testPoint)
    end

    -- Start with forward vector simulation
    if simulateAndCheckBackstab(centralAngle) then
        return SimulateDash(createDirectionVector(centralAngle), SIMULATION_TICKS)
    end

    -- Determine initial yaw difference for further simulations
    local enemyYaw = CalculateYawAngle(TargetPlayer.hitboxPos, TargetPlayer.hitboxForward)
    local spyYaw = PositionYaw(playerPos, targetPos)
    local initialYawDiff = NormalizeYaw(spyYaw - enemyYaw)
    local prioritizeRight = initialYawDiff <= 0

    -- Check the most likely direction first
    local likelyAngleOffset = prioritizeRight and rightOffset or leftOffset
    if simulateAndCheckBackstab(centralAngle + likelyAngleOffset) then
        return SimulateDash(createDirectionVector(centralAngle + likelyAngleOffset), SIMULATION_TICKS)
    end

    -- Loop through remaining simulations only if necessary
    for i = 1, totalSimulations - 2 do
        local currentAngle = centralAngle + leftOffset + angleIncrement * i
        if simulateAndCheckBackstab(currentAngle) then
            backstabPosition = SimulateDash(createDirectionVector(currentAngle), SIMULATION_TICKS)
            endwarps[i] = {backstabPosition, true}
            break
        end
    end

    cleartiemr = cleartiemr - 1
    if cleartiemr < 1 then
        collectgarbage()
        cleartiemr = 50
    end


    return backstabPosition
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
    local move = Vector3(math.cos(yaw) * 320, -math.sin(yaw) * 320, 0)

    return move
end

-- Global variable to store the move direction
local movedir

-- Function to normalize angle to [-180, 180]
local function NormalizeAngle(angle)
    return (angle + 180) % 360 - 180
end

-- Walks to the destination and sets the global move direction
---@param userCmd UserCmd
---@param localPlayer Entity
---@param destination Vector3
local function WalkTo(cmd, Pos, destination)
        if warp.CanWarp() and pLocal:EstimateAbsVelocity():Length() > 319 then
                -- Adjust yaw angle based on movement keys
                local yawAdjustment = 0
                if input.IsButtonDown(KEY_W) then
                    yawAdjustment = 0  -- Forward
                    if input.IsButtonDown(KEY_A) then
                        yawAdjustment = -40  -- Forward and left
                    elseif input.IsButtonDown(KEY_D) then
                        yawAdjustment = 40  -- Forward and right
                    end
                elseif input.IsButtonDown(KEY_S) then
                    yawAdjustment = 190  -- Backward
                    if input.IsButtonDown(KEY_A) then
                        yawAdjustment = -130  -- Backward and left
                    elseif input.IsButtonDown(KEY_D) then
                        yawAdjustment = 130 -- Backward and right
                    end
                elseif input.IsButtonDown(KEY_A) then
                    yawAdjustment = -100  -- Left
                elseif input.IsButtonDown(KEY_D) then
                    yawAdjustment = 100  -- Right
                end

            -- Calculate the base yaw angle based on the destination
            local baseYaw = PositionAngles(pLocalPos, destination).yaw

            local adjustedYaw = NormalizeAngle(baseYaw + yawAdjustment)
            local angle1 = EulerAngles(engine.GetViewAngles().pitch, adjustedYaw, 0)

            engine.SetViewAngles(angle1)
        end

    local currentVelocity = pLocal:EstimateAbsVelocity()  -- Get the current velocity

    -- Invert the current velocity
    local invertedVelocity = Vector3(-currentVelocity.x, -currentVelocity.y, -currentVelocity.z)

    -- Compute the move to the destination
    local moveToDestination = ComputeMove(cmd, Pos, destination)

    local combinedMove = moveToDestination

    if invertedVelocity and invertedVelocity:Length() >= 319 then
        invertedVelocity = NormalizeVector(invertedVelocity)
        -- Combine inverted velocity with moveToDestination
        combinedMove = invertedVelocity + moveToDestination
    end

    combinedMove = NormalizeVector(combinedMove) * 320


    -- Set forward and side move
    cmd:SetForwardMove(combinedMove.x)
    cmd:SetSideMove(combinedMove.y)
    -- Set the global move direction
    movedir = combinedMove
end

local warpdelay = 0
local function AutoWarp_AutoBlink(cmd)
    local BackstabPos = CalculateTrickstab()

    -- Main logic
    local lastDistance
    if BackstabPos then
            if Menu.Main.AutoWalk then
                -- Walk to the backstab position if AutoWalk is enabled
                WalkTo(cmd, pLocalPos, BackstabPos)
            end

            if Menu.Advanced.AutoWarp and warp.CanWarp() then
                -- Trigger warp after changing direction 10 times
                gui.SetValue("fake lag", 0)
                warp.TriggerWarp()
            elseif not warp.CanWarp() then
                gui.SetValue("fake lag", 1)
            else
                gui.SetValue("fake lag", 0)
            end
        --[[else
            endwarps[angle] = {point[1], false}
            if Menu.Main.AutoAlign then
                WalkTo(cmd, pLocal:GetAbsOrigin(), AutoAlign)
            end
            -- Optional: Logic for handling when you can't backstab from a position]]
        elseif warp.GetChargedTicks() > 22 then
            gui.SetValue("fake lag", 1)
        end
end

local RechargeDelay = 0
local function OnCreateMove(cmd)
    if UpdateLocalPlayerCache() == false then return end  -- Update local player data every tick
    endwarps = {}
    positions = {}

    -- Get the local player's active weapon
    local pWeapon = pLocal:GetPropEntity("m_hActiveWeapon")
    if not pWeapon or not pWeapon:IsMeleeWeapon() then return end -- Return if the local player doesn't have an active weaponend

    --UpdateBacktrackData() --update position and angle data for backtrack --todo

    TargetPlayer = nil
    local target = UpdateTarget()

    if not TargetPlayer then
        gui.SetValue("fake lag", 0)
        if Menu.Advanced.AutoRecharge and not warp.IsWarping() and warp.GetChargedTicks() < 23 then
            warp.TriggerCharge()
        end
        --TargetPlayer = {}
    else
        UpdateSimulationCache()
        if Menu.Main.TrickstabModeSelected == 1 then
            AutoWarp_AutoBlink(cmd)
        elseif Menu.Main.TrickstabModeSelected == 2 then

        elseif Menu.Main.TrickstabModeSelected == 3 then
            
        elseif Menu.Main.TrickstabModeSelected == 4 then

        elseif Menu.Main.TrickstabModeSelected == 5 then
    
        elseif Menu.Main.TrickstabModeSelected == 6 then

        end
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

        -- Visualize Simulated Positions

        if Menu.Visuals.VisualizePoints and positions then
            for _, point in ipairs(positions) do
                local screenPos = client.WorldToScreen(Vector3(point.x, point.y, point.z))
                if screenPos then
                    draw.Color(255, 0, 0, 255)  -- Green color for simulated positions
                    draw.FilledRect(screenPos[1] - 2, screenPos[2] - 2, screenPos[1] + 2, screenPos[2] + 2)
                end
            end
        end

        if Menu.Visuals.VisualizePoints and positions then
            -- Drawing all simulated positions in green
            for _, point in ipairs(positions) do
                local screenPos = client.WorldToScreen(Vector3(point.x, point.y, point.z))
                if screenPos then
                    draw.Color(0, 255, 0, 255)
                    draw.FilledRect(screenPos[1] - 2, screenPos[2] - 2, screenPos[1] + 2, screenPos[2] + 2)
                end
            end
        end

        -- Visualize Backstab Position
        if Menu.Visuals.VisualizeStabPoint and BackstabPos then
            local screenPos = client.WorldToScreen(Vector3(BackstabPos.x, BackstabPos.y, BackstabPos.z))
            if screenPos then
                draw.Color(255, 0, 0, 255)  -- Red color for backstab position
                draw.FilledRect(screenPos[1] - 5, screenPos[2] - 5, screenPos[1] + 5, screenPos[2] + 5)
            end
        end

        -- Draw the circle with collision detection
        if Menu.Visuals.Attack_Circle and pLocal then
            local segments = 32
            local radius = 220
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
                if point[2] == false then
                    draw.Color(255, 0, 0, 255)
                    
                    local screenPos = client.WorldToScreen(Vector3(point[1].x, point[1].y, point[1].z))
                    if screenPos then
                        draw.FilledRect(screenPos[1] - 5, screenPos[2] - 5, screenPos[1] + 5, screenPos[2] + 3)
                    end
                else
                    draw.Color(255, 255, 255, 255)
                    local screenPos = client.WorldToScreen(Vector3(point[1].x, point[1].y, point[1].z))
                    if screenPos then
                        draw.FilledRect(screenPos[1] - 5, screenPos[2] - 5, screenPos[1] + 5, screenPos[2] + 5)
                    end
                end
            end
        end

        if Menu.Visuals.ForwardLine then
            if TargetPlayer and TargetPlayer.Pos then
                local forward = TargetPlayer.hitboxForward
                local hitboxPos = TargetPlayer.hitboxPos

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
            ImMenu.Text("Please Use Lbox Auto Bacsktab")
            ImMenu.EndFrame()
    
            ImMenu.BeginFrame(1)
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
