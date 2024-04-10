
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

    Version = 2.9, -- dont touch this, this is just for managing the config version

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
        Accuracy = 23,
        sidestabTolerance = 1,
        AutoWarp = true,
        AutoRecharge = true,
        ManualDirection = false,
    },

    Visuals = {
        Active = true,
        VisualizePoints = true,
        VisualizeStabPoint = true,
        VisualizeUsellesSimulations = true,
        Attack_Circle = false,
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
local cachedoffset = 24
local BestYawDifference = 180
local BestPosition
local AlignPos = nil
local tickRate = (1 / globals.TickInterval())
local shouldalign = true
local world = entities.FindByClass("CWorld")[0]

local lastToggleTime = 0
local Lbox_Menu_Open = true
local toggleCooldown = 0.2  -- 200 milliseconds

local function toggleMenu()
    local currentTime = globals.RealTime()
    if currentTime - lastToggleTime >= toggleCooldown then
        Lbox_Menu_Open = not Lbox_Menu_Open  -- Toggle the state
        lastToggleTime = currentTime  -- Reset the last toggle time
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
            CreateCFG([[LBOX Auto trickstab lua]], Menu)
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
    if length == 0 then return Vector3(0, 0, 0) end
    return Vector3(vec.x / length, vec.y / length, vec.z / length)
end

--[[local function GetHitboxForwardDirection(player, idx)
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
end]]

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
    pLocalViewPos = pLocal and (pLocal:GetAbsOrigin() + pLocal:GetPropVector("localdata", "m_vecViewOffset[0]")) or pLocalPos or Vector3(0,0,0)
    pLocalPos = pLocal:GetAbsOrigin()
    --AlignPos = nil
    return pLocal
end

-- Initialize cache
UpdateLocalPlayerCache()

local function CalculateBackwardVector(player)
    local forwardAngle = player:GetPropVector("tfnonlocaldata", "m_angEyeAngles[0]")
    local pitch = math.rad(forwardAngle.x)
    local yaw = math.rad(forwardAngle.y)
    local forwardVector = Vector3(math.cos(pitch) * math.cos(yaw), math.cos(pitch) * math.sin(yaw), 0)
    return -forwardVector
end

local function CalculateBackPoint(player1)
    local hitboxes = player1:GetHitboxes()
    if hitboxes then
        local hitboxCenter = (hitboxes[4][1] + hitboxes[4][2]) * 0.5
        return hitboxCenter - CalculateBackwardVector(player1) * 30
    else
        return nil
    end
end

local PastTicks = {{}} -- Table to hold past positions for backtracking
local function UpdateTarget()
    local allPlayers = entities.FindByClass("CTFPlayer")
    local bestTargetDetails = nil
    local maxAttackDistance = 225  -- Attack range plus warp distance
    local maxBacktrackDistance = 670 -- Max backtrack distance
    local bestDistance = maxAttackDistance + 1  -- Initialize to a large number

    for _, player in ipairs(allPlayers) do
        if player:IsAlive() and not player:IsDormant() and player:GetTeamNumber() ~= pLocal:GetTeamNumber() and player ~= pLocal then
            local playerIndex = player:GetIndex()
            local playerPos = player:GetAbsOrigin()
            local distance = (pLocalPos - playerPos):Length()

            -- Check if the player is within the attack range
            if distance < bestDistance then
                bestDistance = distance
                bestTargetDetails = {
                    idx = playerIndex,
                    entity = player,
                    Pos = playerPos,
                    FPos = playerPos + player:EstimateAbsVelocity() * 0.015,
                    viewOffset = player:GetPropVector("localdata", "m_vecViewOffset[0]"),
                    hitboxPos = (player:GetHitboxes()[4][1] + player:GetHitboxes()[4][2]) * 0.5,
                    hitboxForward = CalculateBackwardVector(player),
                    backPoint = CalculateBackPoint(player)
                }
            end

            --[[ Maintain history of past positions for backtracking if within the max backtrack distance
            if distance <= maxBacktrackDistance and bestTargetDetails then
                PastTicks[playerIndex] = PastTicks[playerIndex] or {pos = {}, backPos = {}}
                local backPoint = CalculateBackPoint(player)

                table.insert(PastTicks[playerIndex].pos, playerPos)
                table.insert(PastTicks[playerIndex].backPos, backPoint)

                if #PastTicks[playerIndex].pos > 66 then
                    table.remove(PastTicks[playerIndex].pos, 1)
                    table.remove(PastTicks[playerIndex].backPos, 1)
                end
            end]]
        end
    end

    return bestTargetDetails
end

--[[local PastTicks = {{}}
local function UpdateTarget()
    local allPlayers = entities.FindByClass("CTFPlayer")
    local bestTargetDetails = nil
    local maxAttackDistance = 225  -- Attack range plus warp distance
    local maxBacktrackDistance = 670 --distance from what yo ucan kill backtracked pos at max
    local bestDistance = maxAttackDistance + 1  -- Initialize with a value larger than max distance
    local found = false
    for _, player in pairs(allPlayers) do
        if pLocal and player:IsAlive() and not player:IsDormant() and not (player:GetTeamNumber() == pLocal:GetTeamNumber()) then --if player is even qualified for
            local playerAbsOrigin = player:GetAbsOrigin()
            local delta = pLocalPos - playerAbsOrigin
            local manhattanDistance = math.abs(delta.x) + math.abs(delta.y) + math.abs(delta.z)

            if manhattanDistance <= maxAttackDistance then
                local hitboxidx = 4  -- Assuming hitboxID 4
                local hitbox = player:GetHitboxes()[hitboxidx]
                if hitbox then
                    local hitboxCenter = (hitbox[1] + hitbox[2]) * 0.5
                    --local forwardVector = GetHitboxForwardDirection(player, 1)
                    
                    local forwardAngle = player:GetPropVector("tfnonlocaldata", "m_angEyeAngles[0]")
                    -- Assuming forwardAngle is a Vector3 where:
                    -- forwardAngle.x = Pitch, forwardAngle.y = Yaw, forwardAngle.z = Roll
                    -- Convert degrees to radians for trigonometric functions
                    local pitch = math.rad(forwardAngle.x)
                    local yaw = math.rad(forwardAngle.y) + math.pi
                    local forwardVector = Vector3(
                        math.cos(pitch) * math.cos(yaw),  -- X component
                        math.cos(pitch) * math.sin(yaw),  -- Y component
                        0                  -- Z component
                    )
                    local backPoint = hitboxCenter + forwardVector * 30  -- 30 units behind the hitbox center

                    TargetPlayer = {
                        idx = player:GetIndex(),
                        entity = player,
                        Pos = playerAbsOrigin,
                        FPos = playerAbsOrigin + player:EstimateAbsVelocity() * 0.015,
                        viewOffset = player:GetPropVector("localdata", "m_vecViewOffset[0]"),
                        hitboxPos = hitboxCenter,
                        hitboxForward = forwardVector,-- forwardVector,
                        backPoint = backPoint  -- Adding the backPoint parameter
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
end]]


-- Normalize a yaw angle to the range [-180, 180]
local function NormalizeYaw(yaw)
    while yaw > 180 do yaw = yaw - 360 end
    while yaw < -180 do yaw = yaw + 360 end
    return yaw
end

-- Function to calculate yaw angle between two points using math.atan2
local function CalculateYawAngle(point1, direction)
    -- Determine a point along the forward direction
    local forwardPoint = point1 + direction * 104  -- 'someDistance' is an arbitrary distance

    -- Calculate the difference in the x and y coordinates
    local dx = forwardPoint.x - point1.x
    local dy = forwardPoint.y - point1.y

    -- Calculate the yaw angle using math.atan
    local yaw = math.atan(dy, dx)

    return math.deg(yaw)  -- Convert radians to degrees
end

local function PositionYaw(source, dest)
    local delta = source - dest

    local yaw = math.atan(delta.y / delta.x) * M_RADPI

    if delta.x >= 0 then
        yaw = yaw + 180
    end

    if isNaN(yaw) then yaw = 0 end

    return yaw
end


local function CheckYawDelta(angle1, angle2)
    local difference = angle1 - angle2

    local normalizedDifference = NormalizeYaw(difference)

    -- Assuming you want to check if within a 120-degree arc to the right and a 40-degree arc to the left of the back
    local withinRightArc = normalizedDifference > -70 and normalizedDifference <= 0
    local withinLeftArc = normalizedDifference < 80 and normalizedDifference >= 0

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
    local targetPos = TargetPlayer.FPos
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

    if TargetPlayer and TargetPlayer.FPos and TargetPlayer.hitboxForward then
        local InRange, closestPoint = checkInRange(viewPos, 66) -- Assuming checkInRange is defined correctly
        if InRange and TargetPlayer.hitboxForward then
            local enemyYaw = CalculateYawAngle(TargetPlayer.hitboxPos, TargetPlayer.hitboxForward)
            enemyYaw = NormalizeYaw(enemyYaw) -- Normalize

            local spyYaw = PositionYaw(TargetPlayer.FPos, viewPos)
            local Delta = math.abs(NormalizeYaw(spyYaw - enemyYaw))

            local canBackstab = CheckYawDelta(spyYaw, enemyYaw) -- Assuming CheckYawDelta is defined correctly
            return canBackstab, Delta
        end
    else
        print("TargetPlayer is nil")
    end

    return false, nil
end


-- Constants
local MAX_SPEED = 320  -- Maximum speed
local SIMULATION_TICKS = 23  -- Number of ticks for simulation
local positions = {}

local FORWARD_COLLISION_ANGLE = 55
local GROUND_COLLISION_ANGLE_LOW = 45
local GROUND_COLLISION_ANGLE_HIGH = 55

-- Helper function for forward collision
local function handleForwardCollision(vel, wallTrace)
    local normal = wallTrace.plane
    local angle = math.deg(math.acos(normal:Dot(Vector3(0, 0, 1))))

     -- Adjust velocity if angle is greater than forward collision angle
    if angle > FORWARD_COLLISION_ANGLE then
        -- The wall is steep, adjust velocity to prevent moving into the wall
        local dot = vel:Dot(normal)
        vel = vel - normal * dot
    end

    return wallTrace.endpos.x, wallTrace.endpos.y, alreadyWithinStep
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
local function SimulateDash(simulatedVelocity, ticks, isBacktrack)
    local BACKTRACK_ACCURACY = 1
    local accuracy = Menu.Advanced.Accuracy
    if isBacktrack == true then
        accuracy = math.max(1, math.min(BACKTRACK_ACCURACY, SIMULATION_TICKS))
    else
        accuracy = math.max(1, math.min(Menu.Advanced.Accuracy or SIMULATION_TICKS, SIMULATION_TICKS))
    end

    -- Calculate the tick interval based on the server's settings
    local tick_interval = globals.TickInterval()

    local gravity = simulationCache.gravity * tick_interval
    local stepSize = simulationCache.stepSize
    local vUp = Vector3(0, 0, 1)
    local vStep = Vector3(0, 0, stepSize / 2)

    local localPositions = {}
    local lastP = pLocalPos
    local lastV = simulatedVelocity
    local flags = simulationCache.flags
    local lastG = (flags & 1 == 1)
    local Endpos = Vector3(0, 0, 0)

    for i = 1, accuracy do
        local pos = lastP + lastV * tick_interval
        local vel = lastV
        local onGround = lastG

        if Menu.Advanced.ColisionCheck then
            if Menu.Advanced.AdvancedPred then
                -- Forward collision
                local wallTrace = engine.TraceHull(lastP + vStep, pos + vStep, vHitbox[1], vHitbox[2], MASK_PLAYERSOLID_BRUSHONLY)
                if wallTrace.fraction < 1 then
                    pos.x, pos.y = handleForwardCollision(vel, wallTrace)
                end
            else
                -- Forward collision
                local wallTrace = engine.TraceHull(lastP + vStep, pos + vStep, vHitbox[1], vHitbox[2], MASK_PLAYERSOLID_BRUSHONLY) --local wallTrace = BasicTraceHull(lastP + vStep, pos + vStep, vHitbox, MASK_PLAYERSOLID_BRUSHONLY)
                if wallTrace.fraction < 1 then
                    if wallTrace.entity and wallTrace.entity:IsValid() then
                        if wallTrace.entity:GetClass() == "CTFPlayer" then
                            -- Detected collision with a player, stop simulation
                            positions[23] = lastP
                            break
                        else
                            -- Handle collision with non-player entities
                            pos.x, pos.y = handleForwardCollision(vel, wallTrace)
                        end
                    else
                        -- Handle collision when no valid entity is involved
                        pos.x, pos.y = handleForwardCollision(vel, wallTrace)
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

-- Function to rotate a 2D vector (x, y) around the Z-axis by a given yaw angle in degrees
local function RotateVector(vector, yawDegrees)
    local radian = math.rad(yawDegrees)
    return Vector3(
        vector.x * math.cos(radian) - vector.y * math.sin(radian),
        vector.x * math.sin(radian) + vector.y * math.cos(radian),
        vector.z  -- Maintain the original Z-component
    )
end

    -- Function to create a direction vector from an angle
    local function createDirectionVector(angle)
        local radianAngle = math.rad(angle)
        return Vector3(math.cos(radianAngle), math.sin(radianAngle), 0) * 320
    end

    -- Function to create a direction vector from an angle
    local function createDirectionVector2(angle)
        local radianAngle = math.rad(angle)
        return Vector3(math.cos(radianAngle), math.sin(radianAngle), 0) * 117
    end


local function SimulateSideStab(initialAngle, centralAngle)
    local angleAdjustmentStep = (initialAngle >= 0) and 1 or -1
    local currentAngle = centralAngle + initialAngle

    -- Define the AABB min and max relative offsets
    local aabbMin = Vector3(-24, -24, 0)
    local aabbMax = Vector3(24, 24, 82)

    --ray = Ray:new({pLocalPosx, pLocalPos.y, pLocalPos.z}, {117, 0, 0})
    --box = {{TargetPlayer.Pos.x + -48,TargetPlayer.Pos.y + -48,TargetPlayer.Pos.y - 82},{TargetPlayer.Pos.x + 48,TargetPlayer.Pos.y + 48,TargetPlayer.Pos.z + 82}}

    --[[if box[1][3] < box[2][3] - 82 * 2 then
        box[1][3] = box[2][3] - 82 * 2
    end]]

    for iteration = 1, 90 do
        local directionVector = createDirectionVector2(currentAngle)
        local newPosition = pLocalPos + directionVector

        -- Perform a hull trace from the current position to the new position
        local traceResult = engine.TraceHull(pLocalPos, newPosition, aabbMin, aabbMax, MASK_SOLID_BRUSHONLY )

        if traceResult.fraction < 1 then --traceResult.entity == TargetPlayer.entity then
            if traceResult.entity == world or traceResult.entity:GetClass() == "CWorld" then
                return nil
            else
                currentAngle = currentAngle + angleAdjustmentStep
            end
        else
            local dashResult = SimulateDash(createDirectionVector(currentAngle), SIMULATION_TICKS)
            return CheckBackstab(dashResult) and dashResult or nil
        end
    end

    local lastTest = SimulateDash(createDirectionVector(centralAngle + ( initialAngle < 0 and -90 or 90 )), SIMULATION_TICKS)
    return CheckBackstab(lastTest) and lastTest or nil
end

local function CalculateTrickstab()
    -- Ensure pLocal and TargetPlayer are valid and have position data
    if not pLocal or not pLocal:GetAbsOrigin() then
        print("Local player position is undefined")
        return nil
    end

    if not TargetPlayer or not TargetPlayer.FPos then
        print("Target player or target player position is undefined")
        return nil
    end

    if not world:IsValid() then
        world = entities.FindByClass("CWorld")[0]
        return nil
    end

    local playerPos = pLocal:GetAbsOrigin()
    local targetPos = TargetPlayer.FPos
    local dx = targetPos.x - pLocalPos.x
    local dy = targetPos.y - pLocalPos.y

    
    -- Calculate central angle using math.atan with two arguments
    local centralAngle = math.deg(math.atan(dy, dx))

    local Disguised = pLocal:InCond(TFCond_Disguised)
    MAX_SPEED = Disguised and pLocal:EstimateAbsVelocity():Length() or 320

    -- Function to check and simulate backstab for a given angle
    local function simulateAndCheckBackstab(angle)
        local directionVector = createDirectionVector(angle)
        local testPoint = SimulateDash(directionVector, SIMULATION_TICKS)
        return CheckBackstab(testPoint)
    end

    -- Determine initial yaw difference for further simulations
    local enemyYaw = CalculateYawAngle(TargetPlayer.hitboxPos, TargetPlayer.hitboxForward)
    local spyYaw = PositionYaw(playerPos, targetPos)
    local initialYawDiff = NormalizeYaw(spyYaw - enemyYaw)

    if initialYawDiff > 80 then
        -- Check the back angle next
        local backAngle = PositionYaw(pLocalPos, TargetPlayer.backPoint)
        if simulateAndCheckBackstab(backAngle) then
            return SimulateDash(createDirectionVector(backAngle), SIMULATION_TICKS)
        end
    end

    -- Use SimulateSideStab for likely angle
    local likelyAngleOffset
    if initialYawDiff < 0 then
        likelyAngleOffset = 25  -- Adjust as needed
    else
        likelyAngleOffset = -25   -- Adjust as needed
    end

    -- Check if the opposite direction key is being pressed and invert the angle if it is
    if Menu.Main.AutoAlign and Menu.Advanced.ManualDirection then
        if initialYawDiff < 0 and input.IsButtonDown(KEY_D) then
            likelyAngleOffset = -likelyAngleOffset
        elseif initialYawDiff > 0 and input.IsButtonDown(KEY_A) then
            likelyAngleOffset = -likelyAngleOffset
        end
    end

    local sideStabPos = SimulateSideStab(likelyAngleOffset, centralAngle)
    if sideStabPos then
        return sideStabPos
    end

    if initialYawDiff > 80 then
        -- Try the forward angle if both side and back angles fail
        if simulateAndCheckBackstab(centralAngle) then
            return SimulateDash(createDirectionVector(centralAngle), SIMULATION_TICKS)
        end
    end

    -- Fail the function if all checks don't work
    return nil
end




-- Computes the move vector between two points
---@param cmd UserCmd
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
---@param cmd UserCmd
---@param destination Vector3
local function WalkTo(cmd, Pos, destination, AdjustView)
    -- Check if Warp is possible and player's velocity is high enough
    if AdjustView and AdjustView == true and pLocal and pLocal:EstimateAbsVelocity():Length() > 318 and warp.CanWarp() and not warp.IsWarping() then
            local forwardMove = cmd:GetForwardMove()
            local sideMove = cmd:GetSideMove()

            -- Normalize move values for diagonal movement
            if forwardMove ~= 0 and sideMove ~= 0 then
                forwardMove = forwardMove / math.sqrt(2)  -- Normalize for diagonal
                sideMove = sideMove / math.sqrt(2)        -- Normalize for diagonal
            end

            -- Determine the movement direction
            local moveDirectionAngle = 0
            if forwardMove > 0 then
                if sideMove > 0 then
                    moveDirectionAngle = 45  -- Moving forward-right
                elseif sideMove < 0 then
                    moveDirectionAngle = -45 -- Moving forward-left
                else
                    moveDirectionAngle = 0   -- Moving forward
                end
            elseif forwardMove < 0 then
                if sideMove > 0 then
                    moveDirectionAngle = 135  -- Moving backward-right
                elseif sideMove < 0 then
                    moveDirectionAngle = -135 -- Moving backward-left
                else
                    moveDirectionAngle = 180  -- Moving backward
                end
            else
                if sideMove > 0 then
                    moveDirectionAngle = 90  -- Moving right
                elseif sideMove < 0 then
                    moveDirectionAngle = -90 -- Moving left
                end
            end
            
            -- Calculate the base yaw angle towards the destination and adjust by movement direction
            local baseYaw = PositionAngles(Pos, destination).yaw
            local adjustedYaw = NormalizeAngle(baseYaw + moveDirectionAngle)
            
            -- Set view angles
            local newViewAngles = EulerAngles(engine.GetViewAngles().pitch, adjustedYaw, 0)
            engine.SetViewAngles(newViewAngles)
    end

    -- Compute the move towards the destination
    local moveToDestination = ComputeMove(cmd, Pos, destination)

    -- Normalize and apply the move command
    moveToDestination = NormalizeVector(moveToDestination) * 450
    cmd:SetForwardMove(moveToDestination.x)
    cmd:SetSideMove(moveToDestination.y)
end

local function AutoWarp_AutoBlink(cmd)
    local BackstabPos = CalculateTrickstab()

    -- Main logic
    local lastDistance
        if BackstabPos ~= nil then
            if Menu.Main.AutoWalk then
                -- Walk to the backstab position if AutoWalk is enabled
                WalkTo(cmd, pLocalPos, BackstabPos, true)
            end

            if Menu.Advanced.AutoWarp and not warp.IsWarping() and warp.CanWarp() and warp.GetChargedTicks() > 22 and pLocal:EstimateAbsVelocity():Length() > 319 then
                -- Trigger warp after changing direction and disable fakelag so warp works right
                gui.SetValue("fake lag", 0)
                warp.TriggerWarp()
            elseif Menu.Advanced.AutoWarp and not warp.CanWarp() and not warp.IsWarping() then
                gui.SetValue("fake lag", 1)
            end
        elseif Menu.Main.AutoAlign and positions[SIMULATION_TICKS] then
            gui.SetValue("fake lag", 1)
            WalkTo(cmd, pLocalPos, positions[SIMULATION_TICKS], false)
        end
end

local killed = false
local function damageLogger(event)
    if (event:GetName() == 'player_hurt' ) then
        local victim = entities.GetByUserID(event:GetInt("userid"))
        local attacker = entities.GetByUserID(event:GetInt("attacker"))

        if (attacker == nil or pLocal:GetIndex() ~= attacker:GetIndex()) then
            return
        end
        killed = true --raprot kill now safely can recharge
    end
end

local Latency = 0
local lerp = 0
local globalCounter = 0

local function OnCreateMove(cmd)
    if UpdateLocalPlayerCache() == false or not pLocal then return end  -- Update local player data every tick
    endwarps = {}
    positions = {}
    TargetPlayer = {{}}

    -- Get the local player's active weapon
    local pWeapon = pLocal:GetPropEntity("m_hActiveWeapon")
    if not pWeapon or not pWeapon:IsMeleeWeapon() then return end -- Return if the local player doesn't have an active weaponend

    TargetPlayer = UpdateTarget()
    if TargetPlayer ~= nil then
        UpdateSimulationCache()
        if Menu.Main.TrickstabModeSelected == 1 then
            AutoWarp_AutoBlink(cmd)
        elseif Menu.Main.TrickstabModeSelected == 2 then

        elseif Menu.Main.TrickstabModeSelected == 3 then
            
        elseif Menu.Main.TrickstabModeSelected == 4 then

        elseif Menu.Main.TrickstabModeSelected == 5 then
    
        elseif Menu.Main.TrickstabModeSelected == 6 then

        end
    else
        gui.SetValue("fake lag", 0)
        --TargetPlayer = {}
    end

        -- Calculate latency in seconds
        local latOut = clientstate.GetLatencyOut()
        local latIn = clientstate.GetLatencyIn()
        lerp = client.GetConVar("cl_interp") or 0
        Latency = Conversion.Time_to_Ticks(latOut + latIn + lerp)

            -- Set a dynamic delay in ticks based on the current latency
        local rechargeDelayTicks = Conversion.Time_to_Ticks(Latency)
        local TimerRecharge = Latency  -- Initialize TimerRecharge with the current latency

        if Menu.Advanced.AutoRecharge and not warp.IsWarping() and warp.GetChargedTicks() < 24 and not warp.CanWarp() then
            globalCounter = globalCounter + 1
            if globalCounter >= 132 + Latency or killed then
                warp.TriggerCharge()
                globalCounter = 0  -- Reset the global counter
                killed = false  -- Reset the killed flag
                TimerRecharge = Latency  -- Reset the TimerRecharge to the current latency
            end
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

        if Menu.Visuals.Attack_Circle and pLocal then

            local center = pLocal:GetAbsOrigin() -- Center of the circle at the player's feet
            local viewPos = pLocalViewPos -- View position to shoot traces from
            local radius = 220 -- Radius of the circle
            local segments = 32 -- Number of segments to draw the circle
            local angleStep = (2 * math.pi) / segments
        
            -- Determine the color of the circle based on TargetPlayer
            local circleColor = TargetPlayer and {0, 255, 0, 255} or {255, 255, 255, 255} -- Green if TargetPlayer exists, otherwise white
        
            -- Set the drawing color
            draw.Color(table.unpack(circleColor))
        
            local vertices = {} -- Table to store adjusted vertices
        
            -- Calculate vertices and adjust based on trace results
            for i = 1, segments do
                local angle = angleStep * i
                local circlePoint = center + Vector3(math.cos(angle), math.sin(angle), 0) * radius
        
                local trace = engine.TraceLine(viewPos, circlePoint, MASK_SHOT_HULL) --engine.TraceHull(viewPos, circlePoint, vHitbox[1], vHitbox[2], MASK_SHOT_HULL)
                local endPoint = trace.fraction < 1.0 and trace.endpos or circlePoint
        
                vertices[i] = client.WorldToScreen(endPoint)
            end
        
            -- Draw the circle using adjusted vertices
            for i = 1, segments do
                local j = (i % segments) + 1 -- Wrap around to the first vertex after the last one
                if vertices[i] and vertices[j] then
                    draw.Line(vertices[i][1], vertices[i][2], vertices[j][1], vertices[j][2])
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
            if ray then
                -- Calculate min and max points
                local minPoint = Vector3(box[1][1], box[1][2], box[1][3])
                local maxPoint = Vector3(box[2][1], box[2][2], box[2][3])

                -- Calculate vertices of the AABB
                -- Assuming minPoint and maxPoint are the minimum and maximum points of the AABB:
                local vertices = {
                    Vector3(minPoint.x, minPoint.y, minPoint.z),  -- Bottom-back-left
                    Vector3(minPoint.x, maxPoint.y, minPoint.z),  -- Bottom-front-left
                    Vector3(maxPoint.x, maxPoint.y, minPoint.z),  -- Bottom-front-right
                    Vector3(maxPoint.x, minPoint.y, minPoint.z),  -- Bottom-back-right
                    Vector3(minPoint.x, minPoint.y, maxPoint.z),  -- Top-back-left
                    Vector3(minPoint.x, maxPoint.y, maxPoint.z),  -- Top-front-left
                    Vector3(maxPoint.x, maxPoint.y, maxPoint.z),  -- Top-front-right
                    Vector3(maxPoint.x, minPoint.y, maxPoint.z)   -- Top-back-right
                }



                --[[local vertices = {
                    client.WorldToScreen(vPlayerFuture + Vector3(hitbox_Width, hitbox_Width, 0)),
                    client.WorldToScreen(vPlayerFuture + Vector3(-hitbox_Width, hitbox_Width, 0)),
                    client.WorldToScreen(vPlayerFuture + Vector3(-hitbox_Width, -hitbox_Width, 0)),
                    client.WorldToScreen(vPlayerFuture + Vector3(hitbox_Width, -hitbox_Width, 0)),
                    client.WorldToScreen(vPlayerFuture + Vector3(hitbox_Width, hitbox_Width, hitbox_Height)),
                    client.WorldToScreen(vPlayerFuture + Vector3(-hitbox_Width, hitbox_Width, hitbox_Height)),
                    client.WorldToScreen(vPlayerFuture + Vector3(-hitbox_Width, -hitbox_Width, hitbox_Height)),
                    client.WorldToScreen(vPlayerFuture + Vector3(hitbox_Width, -hitbox_Width, hitbox_Height))
                }]]

                -- Convert 3D coordinates to 2D screen coordinates
                for i, vertex in ipairs(vertices) do
                    vertices[i] = client.WorldToScreen(vertex)
                end

                -- Draw lines between vertices to visualize the box
                if vertices[1] and vertices[2] and vertices[3] and vertices[4] and vertices[5] and vertices[6] and vertices[7] and vertices[8] then
                    -- Draw front face
                    draw.Line(vertices[1][1], vertices[1][2], vertices[2][1], vertices[2][2])
                    draw.Line(vertices[2][1], vertices[2][2], vertices[3][1], vertices[3][2])
                    draw.Line(vertices[3][1], vertices[3][2], vertices[4][1], vertices[4][2])
                    draw.Line(vertices[4][1], vertices[4][2], vertices[1][1], vertices[1][2])

                    -- Draw back face
                    draw.Line(vertices[5][1], vertices[5][2], vertices[6][1], vertices[6][2])
                    draw.Line(vertices[6][1], vertices[6][2], vertices[7][1], vertices[7][2])
                    draw.Line(vertices[7][1], vertices[7][2], vertices[8][1], vertices[8][2])
                    draw.Line(vertices[8][1], vertices[8][2], vertices[5][1], vertices[5][2])

                    -- Draw connecting lines
                    draw.Line(vertices[1][1], vertices[1][2], vertices[5][1], vertices[5][2])
                    draw.Line(vertices[2][1], vertices[2][2], vertices[6][1], vertices[6][2])
                    draw.Line(vertices[3][1], vertices[3][2], vertices[7][1], vertices[7][2])
                    draw.Line(vertices[4][1], vertices[4][2], vertices[8][1], vertices[8][2])
                end
            end
        end

        if Menu.Visuals.ForwardLine then
            if TargetPlayer and TargetPlayer.FPos then
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

        if ray then
                -- Length of the ray for visualization
                local rayLength = 117

                -- Calculate the end point of the ray based on its direction and length
                local endPoint = {
                    ray.origin[1] + ray.direction[1] * rayLength,
                    ray.origin[2] + ray.direction[2] * rayLength,
                    ray.origin[3] + ray.direction[3] * rayLength
                }

                -- Convert the 3D coordinates of the origin and end point to 2D screen coordinates
                local screenStart = client.WorldToScreen(Vector3(ray.origin[1], ray.origin[2], ray.origin[3]))
                local screenEnd = client.WorldToScreen(Vector3(endPoint[1], endPoint[2], endPoint[3]))

                -- Check if both points are on the screen
                if screenStart and screenEnd then
                    -- Set the color for the ray line (red)
                    draw.Color(255, 255, 255, 255)

                    -- Draw the line on the screen
                    draw.Line(screenStart[1], screenStart[2], screenEnd[1], screenEnd[2])
                end
            end
        end
    end



-----------------------------------------------------------------------------------------------------
    --Menu

    -- Inside your OnCreateMove or similar function where you check for input
    if input.IsButtonDown(72) then  -- Replace 72 with the actual key code for the button you want to use
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
                ImMenu.Text("                  Trickstab Modes")
            ImMenu.EndFrame()
            
            ImMenu.BeginFrame(1)
                Menu.Main.TrickstabModeSelected = ImMenu.Option(Menu.Main.TrickstabModeSelected, Menu.Main.TrickstabMode)
            ImMenu.EndFrame()
    
            ImMenu.BeginFrame(1)
            ImMenu.Text("Please Use Lbox Auto Backstab")
            ImMenu.EndFrame()
    
            ImMenu.BeginFrame(1)
            Menu.Main.AutoWalk = ImMenu.Checkbox("Auto Walk", Menu.Main.AutoWalk)
            Menu.Main.AutoAlign = ImMenu.Checkbox("Auto Align", Menu.Main.AutoAlign)
            ImMenu.EndFrame()
        end

        if Menu.tabs.Advanced then

            ImMenu.BeginFrame(1)
            Menu.Advanced.Accuracy = ImMenu.Slider("Colision Accuracy", Menu.Advanced.Accuracy, 1, SIMULATION_TICKS)
            ImMenu.EndFrame()

            ImMenu.BeginFrame(1)
            Menu.Advanced.ManualDirection = ImMenu.Checkbox("Manual Direction", Menu.Advanced.ManualDirection)
            ImMenu.EndFrame()

            ImMenu.BeginFrame(1)
            Menu.Advanced.ColisionCheck = ImMenu.Checkbox("Colision Check", Menu.Advanced.ColisionCheck)
            Menu.Advanced.AdvancedPred = ImMenu.Checkbox("Advanced Pred", Menu.Advanced.AdvancedPred)
            ImMenu.EndFrame()

            ImMenu.BeginFrame(1)
            Menu.Advanced.AutoWarp = ImMenu.Checkbox("Auto Warp", Menu.Advanced.AutoWarp)
            Menu.Advanced.AutoRecharge = ImMenu.Checkbox("Auto Recharge", Menu.Advanced.AutoRecharge)
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
callbacks.Unregister("FireGameEvent", "adaamageLogger")

--[[ Register callbacks ]]--
callbacks.Register("CreateMove", "AtSM_CreateMove", OnCreateMove)             -- Register the "CreateMove" callback
callbacks.Register("Unload", "AtSM_Unload", OnUnload)                         -- Register the "Unload" callback
callbacks.Register("Draw", "AtSM_Draw", doDraw)                               -- Register the "Draw" callback
callbacks.Register("FireGameEvent", "adaamageLogger", damageLogger)

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