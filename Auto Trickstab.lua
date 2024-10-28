
---@diagnostic disable: param-type-mismatch

---@alias AimTarget { entity : Entity, angles : EulerAngles, factor : number }

---@type boolean, lnxLib
local libLoaded, lnxLib = pcall(require, "lnxLib");
if (not(libLoaded)) then client.ChatPrintf("\x07FF0000LnxLib failed to load!");engine.PlaySound("common/bugreporter_failed.wav") return end

assert(libLoaded, "lnxLib not found, please install it!");
assert(lnxLib.GetVersion() >= 1.00, "lnxLib version is too old, please update it!");

-- Unload the module if it's already loaded
if package.loaded["ImMenu"] then
    package.loaded["ImMenu"] = nil
end

local menuLoaded, ImMenu = pcall(require, "ImMenu")
if (not(menuLoaded)) then client.ChatPrintf("\x07FF0000ImMenu failed to load!");engine.PlaySound("common/bugreporter_failed.wav") return end

assert(menuLoaded, "ImMenu not found, please install it!")
assert(ImMenu.GetVersion() >= 0.66, "ImMenu version is too old, please update it!")

local Math, Conversion = lnxLib.Utils.Math, lnxLib.Utils.Conversion
local WPlayer, WWeapon = lnxLib.TF2.WPlayer, lnxLib.TF2.WWeapon
local Helpers = lnxLib.TF2.Helpers
local Prediction = lnxLib.TF2.Prediction

local Menu = { -- this is the config that will be loaded every time u load the script

    Version = 2.9, -- dont touch this, this is just for managing the config version

    currentTab = 1,
    tabs = { -- dont touch this, this is just for managing the tabs in the menu
        Main = true,
        Advanced = false,
        Visuals = false,
    },

    Main = {
        Active = true,  --disable lua
        AutoWalk = true,
        AutoWarp = true,
        AutoBlink = false,
        MoveAsistance = true,
    },

    Advanced = {
        WarpTolerance = 77,
        AutoRecharge = true,
        ManualDirection = false,
    },

    Visuals = {
        Active = true,
        VisualizePoints = true,
        VisualizeStabPoint = true,
        VisualizeUsellesSimulations = true,
        Attack_Circle = false,
        BackLine = false,
    },
}

local pLocal = entities.GetLocalPlayer() or nil
local emptyVec = Vector3(0,0,0)

local pLocalPos = emptyVec
local pLocalViewPos = emptyVec
local pLocalViewOffset = Vector3(0, 0, 75)
local vHitbox = { Min = Vector3(-23.99, -23.99, 0), Max = Vector3(23.99, 23.99, 82) }

local TargetPlayer = {}
local endwarps = {}

-- Constants
local BACKSTAB_RANGE = 66  -- Hammer units
--local world = entities.FindByClass("CWorld")[0]

local lastToggleTime = 0
local Lbox_Menu_Open = true
local toggleCooldown = 0.2  -- 200 milliseconds

local function CheckMenu()
    if input.IsButtonDown(72) then  -- Replace 72 with the actual key code for the button you want to use
        local currentTime = globals.RealTime()
        if currentTime - lastToggleTime >= toggleCooldown then
            Lbox_Menu_Open = not Lbox_Menu_Open  -- Toggle the state
            lastToggleTime = currentTime  -- Reset the last toggle time
        end
    end
end

local Lua__fullPath = GetScriptName()
local Lua__fileName = Lua__fullPath:match("\\([^\\]-)$"):gsub("%.lua$", "")

local function CreateCFG(folder_name, table)
    local success, fullPath = filesystem.CreateDirectory(folder_name)
    local filepath = tostring(fullPath .. "/config.cfg")
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
        printc( 255, 183, 0, 255, "["..os.date("%H:%M:%S").."] Saved Config to ".. tostring(fullPath))
    end
end

local function LoadCFG(folder_name)
    local success, fullPath = filesystem.CreateDirectory(folder_name)
    local filepath = tostring(fullPath .. "/config.cfg")
    local file = io.open(filepath, "r")

    if file then
        local content = file:read("*a")
        file:close()
        local chunk, err = load("return " .. content)
        if chunk then
            printc( 0, 255, 140, 255, "["..os.date("%H:%M:%S").."] Loaded Config from ".. tostring(fullPath))
            return chunk()
        else
            CreateCFG(string.format([[Lua %s]], Lua__fileName), Menu) --saving the config
            print("Error loading configuration:", err)
        end
    end
end

local status, loadedMenu = pcall(function() 
    return assert(LoadCFG(string.format([[Lua %s]], Lua__fileName))) 
end) -- Auto-load config

-- Function to check if all expected functions exist in the loaded config
local function checkAllFunctionsExist(expectedMenu, loadedMenu)
    for key, value in pairs(expectedMenu) do
        if type(value) == 'function' then
            -- Check if the function exists in the loaded menu and has the correct type
            if not loadedMenu[key] or type(loadedMenu[key]) ~= 'function' then
                return false
            end
        end
    end
    for key, value in pairs(expectedMenu) do
        if not loadedMenu[key] or type(loadedMenu[key]) ~= type(value) then
            return false
        end
    end
    return true
end

-- Execute this block only if loading the config was successful
if status then
    if checkAllFunctionsExist(Menu, loadedMenu) and not input.IsButtonDown(KEY_LSHIFT) then
        Menu = loadedMenu
    else
        print("Config is outdated or invalid. Creating a new config.")
        CreateCFG(string.format([[Lua %s]], Lua__fileName), Menu) -- Save the config
    end
else
    print("Failed to load config. Creating a new config.")
    CreateCFG(string.format([[Lua %s]], Lua__fileName), Menu) -- Save the config
end

-- Function to calculate Manhattan Distance
local function ManhattanDistance(pos1, pos2)
    return math.abs(pos1.x - pos2.x) + math.abs(pos1.y - pos2.y) + math.abs(pos1.z - pos2.z)
end

local M_RADPI = 180 / math.pi

local function isNaN(x) return x ~= x end

-- Normalizes a vector to a unit vector
-- ultimate Normalize a vector
local function Normalize(vec)
    return  vec / vec:Length()
end

-- Normalize a yaw angle to the range [-180, 180]
local function NormalizeYaw(yaw)
    yaw = yaw % 360
    if yaw > 180 then
        yaw = yaw - 360
    elseif yaw < -180 then
        yaw = yaw + 360
    end
    return yaw
end


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

local positions = {}
-- Function to update the cache for the local player and loadout slot
local function UpdateLocalPlayerCache()
    pLocal = entities.GetLocalPlayer()
    if not pLocal
    or pLocal:GetPropInt("m_iClass") ~= TF2_Spy
    or not pLocal:IsAlive()
    or pLocal:InCond(TFCond_Cloaked) or pLocal:InCond(TFCond_CloakFlicker)
    or pLocal:GetPropInt("m_bFeignDeathReady") == 1
    then return false end

    --cachedLoadoutSlot2 = pLocal and pLocal:GetEntityForLoadoutSlot(2) or nil
    pLocalViewOffset = pLocal:GetPropVector("localdata", "m_vecViewOffset[0]")
    pLocalPos = pLocal:GetAbsOrigin()
    pLocalViewPos = pLocal and (pLocal:GetAbsOrigin() + pLocalViewOffset) or pLocalPos or emptyVec

    endwarps = {}
    positions = {}
    TargetPlayer = {}

    return pLocal
end

--[[Calculate the backward vector based on the player's eye angles
local function CalculateforwardVector(player)
    local forwardAngle = player:GetPropVector("tfnonlocaldata", "m_angEyeAngles[0]")
    -- Convert angles from degrees to radians
    local pitchRad = math.rad(forwardAngle.x)
    local yawRad = math.rad(forwardAngle.y)

    -- Calculate the directional vector components
    local x = math.cos(pitchRad) * math.cos(yawRad)
    local y = math.cos(pitchRad) * math.sin(yawRad)

    return Vector3(x, y, 0)
end]]

local function UpdateTarget()
    local allPlayers = entities.FindByClass("CTFPlayer")
    local bestTargetDetails = nil
    local maxAttackDistance = 225  -- Attack range plus warp distance
    --local maxBacktrackDistance = 670 -- Max backtrack distance
    local bestDistance = maxAttackDistance + 1  -- Initialize to a large number
    local ignoreinvisible = (gui.GetValue("ignore cloaked"))

    for _, player in pairs(allPlayers) do
        if player:IsAlive()
            and not player:IsDormant()
            and player:GetTeamNumber() ~= pLocal:GetTeamNumber()
            and (ignoreinvisible == 1 and not player:InCond(4)) then

            local playerPos = player:GetAbsOrigin()
            local distance = (pLocalPos - playerPos):Length()
            local viewDirection = EulerAngles(player:GetPropVector("tfnonlocaldata", "m_angEyeAngles[0]"):Unpack())

            -- Check if the player is within the attack range
            if distance < maxAttackDistance and distance < bestDistance then
                bestDistance = distance
                local viewoffset = player:GetPropVector("localdata", "m_vecViewOffset[0]")
                bestTargetDetails = {
                    entity = player,
                    Pos = playerPos,
                    NextPos = playerPos + player:EstimateAbsVelocity() * globals.TickInterval(),
                    viewpos = playerPos + viewoffset,
                    Back = -viewDirection:Forward(),
                }
            end
        end
    end

    return bestTargetDetails
end

local function PositionYaw(source, dest)
    local delta = Normalize(source - dest)
    return math.deg(math.atan(delta.y, delta.x))
end

local function CheckYawDelta(angle1, angle2)
    local difference = NormalizeYaw(angle1 - angle2)
    --print(difference)
    return (difference > 0 and difference < 89) or (difference < 0 and difference > -89)
end

local SwingHullSize = 38
local SwingHalfhullSize = SwingHullSize / 2
local SwingHull = {Min = Vector3(-SwingHalfhullSize,-SwingHalfhullSize,-SwingHalfhullSize), Max = Vector3(SwingHalfhullSize,SwingHalfhullSize,SwingHalfhullSize)}

-- Function to check if target is in range
local function IsInRange(targetPos, spherePos, sphereRadius)
    local hitbox_min_trigger = targetPos + vHitbox.Min
    local hitbox_max_trigger = targetPos + vHitbox.Max

    -- Calculate the closest point on the hitbox to the sphere
    local closestPoint = Vector3(
        math.max(hitbox_min_trigger.x, math.min(spherePos.x, hitbox_max_trigger.x)),
        math.max(hitbox_min_trigger.y, math.min(spherePos.y, hitbox_max_trigger.y)),
        math.max(hitbox_min_trigger.z, math.min(spherePos.z, hitbox_max_trigger.z))
    )

    -- Calculate the squared distance from the closest point to the sphere center
    local distanceSquared = (spherePos - closestPoint):LengthSqr()

    -- Check if the target is within the sphere radius squared
    if sphereRadius * sphereRadius > distanceSquared then
        -- Calculate the direction from spherePos to closestPoint
        local direction = Normalize(closestPoint - spherePos)
        local SwingtraceEnd = spherePos + direction * sphereRadius

        if Menu.Advanced.AdvancedPred then
            local trace = engine.TraceLine(spherePos, SwingtraceEnd, MASK_SHOT_HULL)
            if trace.entity == TargetPlayer.entity then
                return true, closestPoint
            else
                trace = engine.TraceHull(spherePos, SwingtraceEnd, SwingHull.Min, SwingHull.Max, MASK_SHOT_HULL)
                if trace.entity == TargetPlayer.entity then
                    return true, closestPoint
                else
                    return false, nil
                end
            end
        end

        return true, closestPoint
    else
        -- Target is not in range
        return false, nil
    end
end

local function CheckBackstab(testPoint)
    local viewPos = testPoint + pLocalViewOffset -- Adjust for viewpoint
    local enemyYaw = NormalizeYaw(PositionYaw(TargetPlayer.viewpos, TargetPlayer.viewpos + TargetPlayer.Back)) --back direction
    local spyYaw = NormalizeYaw(PositionYaw(TargetPlayer.viewpos, viewPos)) --spy direction

    -- Check if the yaw delta is within the correct backstab angle range
    if CheckYawDelta(spyYaw, enemyYaw) and IsInRange(TargetPlayer.Pos, viewPos, BACKSTAB_RANGE) then
        return true
    end

    return false
end

local function adjustDirection(direction, normal, maxAngle)
    direction = Normalize(direction)
    local angle = math.deg(math.acos(normal:Dot(UP_VECTOR)))
    if angle > maxAngle then
        return direction
    end
    local dot = direction:Dot(normal)
    direction.z = direction.z - normal.z * dot
    return direction
end

-- Constants
local SIMULATION_TICKS = 23  -- Number of ticks for simulation

local FORWARD_COLLISION_ANGLE = 55
local GROUND_COLLISION_ANGLE_LOW = 45
local GROUND_COLLISION_ANGLE_HIGH = 55


-- Function to handle forward collision
local function handleForwardCollision(vel, wallTrace)
    local normal = wallTrace.plane
    local angle = math.deg(math.acos(normal:Dot(Vector3(0, 0, 1))))

    -- Adjust velocity if angle is greater than forward collision angle
    if angle > FORWARD_COLLISION_ANGLE then
        -- The wall is steep, adjust velocity to prevent moving into the wall
        local dot = vel:Dot(normal)
        vel = vel - normal * dot
    end

    return wallTrace.endpos.x, wallTrace.endpos.y
end

-- Function to handle ground collision
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

local ignoreEntities = {"CTFAmmoPack", "CTFDroppedWeapon"}
local function shouldHitEntityFun(entity, player)
    for _, ignoreEntity in ipairs(ignoreEntities) do --ignore custom
        if entity:GetClass() == ignoreEntity then
            return false
        end
    end

    if entity:GetName() == player:GetName() then return false end --ignore self
    if entity:GetTeamNumber() == player:GetTeamNumber() then return false end --ignore teammates
    return true
end

local MAX_SPEED = 320  -- Maximum speed

-- Simulates movement in a specified direction vector for a player over a given number of ticks
local function SimulateDash(simulatedVelocity, ticks)
    simulatedVelocity = Normalize(simulatedVelocity) * pLocal:EstimateAbsVelocity():Length()
    -- Calculate the tick interval based on the server's settings
    local tick_interval = globals.TickInterval()

    local gravity = simulationCache.gravity * tick_interval
    local stepSize = simulationCache.stepSize
    local vUp = Vector3(0, 0, 1)
    local vStep = Vector3(0, 0, stepSize or 18)

    local shouldHitEntity = function(entity) return shouldHitEntityFun(entity, pLocal) end
    local localPositions = {}
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
                local wallTrace = engine.TraceHull(lastP + vStep, pos + vStep, vHitbox.Min, vHitbox.Max, MASK_PLAYERSOLID, shouldHitEntity)
                if wallTrace.fraction < 1 then
                    if wallTrace.entity then
                        if wallTrace.entity:GetClass() == "CTFPlayer" then
                            -- Detected collision with a player, stop simulation
                            positions[ticks] = lastP
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
            else
                -- Forward collision
                local wallTrace = engine.TraceHull(lastP + vStep, pos + vStep, vHitbox.Min, vHitbox.Max, MASK_PLAYERSOLID, shouldHitEntity)
                if wallTrace.fraction < 1 then
                    pos.x, pos.y = handleForwardCollision(vel, wallTrace)
                end
            end

            -- Ground collision
            local downStep = onGround and vStep or Vector3(0, 0, 0)
            local groundTrace = engine.TraceHull(pos + vStep, pos - downStep, vHitbox.Min, vHitbox.Max, MASK_PLAYERSOLID, shouldHitEntity)
            if groundTrace.fraction < 1 then
                pos, onGround = handleGroundCollision(vel, groundTrace, vUp)
            else
                onGround = false
            end
        end

        -- Simulate jumping
        if onGround and input.IsButtonDown(KEY_SPACE) then
            if gui.GetValue("Duck Jump") == 1 then
                vel.z = 277
            else
                vel.z = 271
            end
            onGround = false
        end

        -- Apply gravity if not on ground
        if not onGround then
            vel.z = vel.z - gravity
        end

        lastP, lastV, lastG = pos, vel, onGround
        table.insert(positions, lastP)  -- Store position for this tick in the local variable
        Endpos = lastP
    end

    table.insert(endwarps, {lastP, CheckBackstab(lastP)})  -- Store position for this tick in the local variable
    return Endpos
end

local corners = {
    Vector3(-49.0, 49.0, 0.0),  -- top left corner
    Vector3(49.0, 49.0, 0.0),   -- top right corner
    Vector3(-49.0, -49.0, 0.0), -- bottom left corner
    Vector3(49.0, -49.0, 0.0)   -- bottom right corner
}

local center = Vector3(0, 0, 0)

local direction_to_corners = {
    [-1] = {
        [-1] = {center, corners[1], corners[4]},  -- Top-left
        [0] = {center, corners[2], corners[4]},   -- Left
        [1] = {center, corners[2], corners[3]}    -- Top-left to bottom-right (corrected)
    },
    [0] = {
        [-1] = {center, corners[1], corners[2]},  -- Up (corrected)
        [0] = {center},                           -- Center
        [1] = {center, corners[4], corners[3]}    -- Down (corrected)
    },
    [1] = {
        [-1] = {center, corners[3], corners[2]},  -- Top-right to bottom-left (corrected)
        [0] = {center, corners[3], corners[1]},   -- Right
        [1] = {center, corners[4], corners[1]}    -- Bottom-right
    }
}

local function determine_direction(my_pos, enemy_pos, hitbox_size, vertical_range)
    local dx = enemy_pos.x - my_pos.x
    local dy = enemy_pos.y - my_pos.y
    local dz = enemy_pos.z - my_pos.z
    local buffor = 1 --fixing the bug wehre hugging the target makes algoritm think were inside him XD

    local out_of_vertical_range = (math.abs(dz) > vertical_range) and 1 or 0

    local direction_x = ((dx > hitbox_size - buffor) and 1 or 0) - ((dx < -hitbox_size + buffor) and 1 or 0)
    local direction_y = ((dy > hitbox_size - buffor) and 1 or 0) - ((dy < -hitbox_size + buffor) and 1 or 0)

    return {(direction_x * (1 - out_of_vertical_range)), (direction_y * (1 - out_of_vertical_range))}
end

local function get_best_corners_or_origin(my_pos, enemy_pos, hitbox_size, vertical_range)
    local direction = determine_direction(my_pos, enemy_pos, hitbox_size, vertical_range)
    local bestcorners = direction_to_corners[direction[1]] and direction_to_corners[direction[1]][direction[2]]

    if not bestcorners then
        print("Invalid direction detected:", direction[1], direction[2])
        return {center}  -- Fallback to center if direction is invalid
    end

    return bestcorners
end


local function CalculateTrickstab(cmd)
    -- Ensure pLocal and TargetPlayer are valid and have position data
    if not TargetPlayer or not TargetPlayer.Pos then
        --print("player position is undefined")
        return emptyVec
    end

    if not TargetPlayer or not TargetPlayer.Pos then
        return emptyVec
    end

    local my_pos = pLocalPos
    local enemy_pos = TargetPlayer.Pos
    local hitbox_size = 49 -- Adjust based on actual hitbox size
    local vertical_range = 82 -- Adjust based on actual vertical range

    local sideMove = cmd:GetSideMove()
    local forwardMove = cmd:GetForwardMove()
    local intrickstab = forwardMove > 0 and sideMove ~= 0

    -- Get the best positions (corners or origin) based on the direction to the enemy
    local best_positions = get_best_corners_or_origin(my_pos, enemy_pos, hitbox_size, vertical_range)

    -- Calculate yaw angles
    local my_yaw = PositionYaw(enemy_pos, my_pos)
    local enemyYaw = NormalizeYaw(PositionYaw(enemy_pos + Vector3(0, 0, 75), enemy_pos + TargetPlayer.Back))
    local spyYaw = NormalizeYaw(PositionYaw(enemy_pos, my_pos + Vector3(0, 0, 75)))

    if CheckYawDelta(spyYaw, enemyYaw) then
        -- We are within backstab yaw range, check the first index
        local center_pos = enemy_pos + best_positions[1]
        local simulated_position = SimulateDash(center_pos - my_pos, warp.GetChargedTicks() or 24)
        if CheckBackstab(simulated_position) then
            return simulated_position
        end
    else
        if Menu.Advanced.ManualDirection then
            -- Manual direction logic using A and D keys
            local best_pos = emptyVec

            if sideMove < 0 then
                best_pos = best_positions[3]  -- Move left relative to the enemy
            elseif sideMove > 0 then
                best_pos = best_positions[2]  -- Move right relative to the enemy
            else
                -- Fallback to automatic direction based on view deviation
                local view_deviation = NormalizeYaw(enemyYaw - my_yaw)
                best_pos = (view_deviation > 0) and best_positions[2] or best_positions[3]
            end

            local simulated_position = SimulateDash((enemy_pos + best_pos - my_pos), warp.GetChargedTicks() or 24)
            if CheckBackstab(simulated_position) or Menu.Main.MoveAsistance and intrickstab then
                -- Move towards the position without warping if Move Assistance is enabled
                return simulated_position
            end
        else
            -- Automatic direction logic
            local view_deviation = NormalizeYaw(enemyYaw - my_yaw)
            local best_pos = (view_deviation > 0) and best_positions[2] or best_positions[3]

            local simulated_position = SimulateDash((enemy_pos + best_pos - my_pos), warp.GetChargedTicks() or 24)
            if CheckBackstab(simulated_position) or Menu.Main.MoveAsistance and intrickstab then
                -- Move towards the position without warping if Move Assistance is enabled
                return simulated_position
            end
        end
    end

    -- If no valid backstab position is found and Move Assistance is not enabled, return emptyVec
    return emptyVec
end

-- Check if a value is NaN
local function IsNaN(value)
    return value ~= value
end

-- Computes the move vector between two points
---@param cmd UserCmd
---@param a Vector3
---@param b Vector3
---@return Vector3
local function ComputeMove(cmd, a, b)
    local diff = (b - a)
    if diff:Length() == 0 then return Vector3(0, 0, 0) end

    local vSilent = Vector3(diff.x, diff.y, 0)

    -- Calculate angles and adjust based on current view angles
    local ang = vSilent:Angles()
    local cPitch, cYaw, cRoll = engine.GetViewAngles():Unpack()
    local yaw = math.rad(ang.y - cYaw)

    -- Calculate movement vector based on adjusted yaw
    local moveX = math.cos(yaw) * MAX_SPEED
    local moveY = -math.sin(yaw) * MAX_SPEED

    -- Check for NaN values and correct them
    if IsNaN(moveX) or IsNaN(moveY) then
        print("Warning: NaN detected, falling back to forward direction")
        return Vector3(MAX_SPEED, 0, 0)  -- Move forward as fallback
    end

    return Vector3(moveX, moveY, 0)
end

-- Walks to the destination and sets the global move direction
---@param cmd UserCmd
---@param Pos Vector3
---@param destination Vector3
---@param AdjustView boolean
local function WalkTo(cmd, Pos, destination, AdjustView)
    -- Adjust the view only if necessary
    if AdjustView and pLocal and warp.CanWarp() and not warp.IsWarping() then
        local forwardMove = cmd:GetForwardMove()
        local sideMove = cmd:GetSideMove()

        -- Determine the movement direction angle
        local moveDirectionAngle = 0
        if forwardMove ~= 0 or sideMove ~= 0 then
            moveDirectionAngle = math.deg(math.atan(sideMove, forwardMove))
        end

        -- Calculate the base yaw angle towards the destination and adjust by movement direction
        local baseYaw = PositionYaw(destination, Pos)
        local adjustedYaw = NormalizeYaw(baseYaw + moveDirectionAngle)

        -- Validate the adjusted yaw, fallback to base yaw if NaN is detected
        if IsNaN(adjustedYaw) then
            print("Warning: adjustedYaw is NaN, skipping view angle adjustment")
        else
            -- Set view angles only if valid
            local currentAngles = engine.GetViewAngles()
            local newViewAngles = EulerAngles(currentAngles.pitch, adjustedYaw, 0)
            engine.SetViewAngles(newViewAngles)
        end
    end

    -- Compute the move towards the destination
    local moveToDestination = ComputeMove(cmd, Pos, destination)

    -- Normalize and apply the move command, with fallback for NaN detection
    moveToDestination = Normalize(moveToDestination) * 450

    if IsNaN(moveToDestination.x) or IsNaN(moveToDestination.y) then
        print("Warning: moveToDestination contains NaN values, falling back to forward move")
        cmd:SetForwardMove(450)  -- Fallback to moving forward
        cmd:SetSideMove(0)
    else
        cmd:SetForwardMove(moveToDestination.x)
        cmd:SetSideMove(moveToDestination.y)
    end
end

local function getBool(event, name)
	local bool = event:GetInt(name)
	return bool == 1
end

local killed = false
local function damageLogger(event)
    if (event:GetName() == 'player_hurt' ) then
        --local victim = entities.GetByUserID(event:GetInt("userid"))
        local attacker = entities.GetByUserID(event:GetInt("attacker"))

        if (attacker == nil or pLocal == nil or pLocal:GetIndex() ~= attacker:GetIndex()) or not getBool(event, "crit") then
            return
        end
        killed = true --raprot kill now safely can recharge
    end
end

local function FakelagOn()
    if Menu.Main.AutoBlink then
        gui.SetValue("fake lag", 1)
    end
end

local function FakelagOff()
    if Menu.Main.AutoBlink then
        gui.SetValue("fake lag", 0)
    end
end

-- Compare two yaw angles to see if they are in the same direction
local function CompareYawDirections(yaw1, yaw2, tolerance)
    yaw1 = NormalizeYaw(yaw1)
    yaw2 = NormalizeYaw(yaw2)

    -- Ensure yaw values are not NaN
    if not (yaw1 == yaw1) or not (yaw2 == yaw2) then
        print("Error: NaN value detected in yaw calculations")
        return false
    end

    local difference = math.abs(yaw1 - yaw2)

    -- Ensure difference is not NaN
    if not (difference == difference) then
        print("Error: NaN value detected in yaw difference")
        return false
    end

    return difference <= tolerance or difference >= (360 - tolerance)
end

local Latency = 0
local lerp = 0
local globalCounter = 0
local BackstabPos = emptyVec

local function AutoWarp(cmd)
    local sideMove = cmd:GetSideMove()
    local forwardMove = cmd:GetForwardMove()

    BackstabPos = CalculateTrickstab(cmd)

    -- Main logic
    if BackstabPos ~= emptyVec then
        local MoveDirection = PositionYaw(pLocalPos, pLocal:EstimateAbsVelocity())
        local WarpDir = PositionYaw(pLocalPos, BackstabPos)
        local canstab = CheckBackstab(BackstabPos)

        if Menu.Main.MoveAsistance and not canstab then
            -- Only walk towards the target if moving forward or sideways
            if forwardMove > 0 or sideMove ~= 0 then
                -- Enable fake lag before walking towards the target
                FakelagOn()
                WalkTo(cmd, pLocalPos, BackstabPos, false)
                return  -- Skip the warp logic if movement assistance is active
            end
            FakelagOff()
        end

        if Menu.Advanced.AutoWarp and canstab and not warp.IsWarping() and warp.CanWarp() and warp.GetChargedTicks() >= 23 then
            -- Disable fake lag to ensure warp works correctly
            FakelagOff()

            if Menu.Main.AutoWalk then
                -- Walk to the backstab position if AutoWalk is enabled
                WalkTo(cmd, pLocalPos, BackstabPos, true)
                -- Only warp if the direction is acceptable
                local acceptable = CompareYawDirections(MoveDirection, WarpDir, Menu.Advanced.WarpTolerance)
                if acceptable then
                    warp.TriggerWarp()
                end
            end
        elseif canstab then
            -- Enable fake lag when warp isn't possible or backstab isn't viable
            FakelagOn()
        end
    else
        -- If no backstab position is found, disable fake lag as there's no action needed
        FakelagOff()
    end
end

local LastAttackTick = 0
local CanAttackNow = false

-- Function to check if the weapon can attack right now
function IsReadyToAttack(cmd, weapon)
    local TickCount = globals.TickCount()
    -- Get the weapon's next available attack time in ticks
    local NextAttackTick = Conversion.Time_to_Ticks(weapon:GetPropFloat("m_flNextPrimaryAttack") or 0)

    -- Check if the weapon's next attack time is less than or equal to the current tick
    if NextAttackTick <= TickCount and warp.CanDoubleTap(weapon) then
        LastAttackTick = TickCount  -- Update the last attack tick to the current tick
        CanAttackNow = true         -- Set flag to indicate attack can happen now
        return true                 -- Ready to attack this tick
    else
        CanAttackNow = false        -- Set flag to false if not ready to attack
    end

    -- Return false if not ready to attack on this tick
    return false
end

local function OnCreateMove(cmd)
    if not Menu.Main.Active then return end
    CheckMenu() -- ensures sync between menu and lbox gui

    -- Inside your OnCreateMove or similar function where you check for input
    if UpdateLocalPlayerCache() == false or not pLocal then return end  -- Update local player data every tick

    -- Get the local player's active weapon
    local pWeapon = pLocal:GetPropEntity("m_hActiveWeapon")
    if not pWeapon or not pWeapon:IsMeleeWeapon() then return end -- Return if the local player doesn't have an active weapon
    if pLocal:InCond(4) then return end
    if not IsReadyToAttack(cmd, pWeapon) then return end

    TargetPlayer = UpdateTarget()
    if TargetPlayer == {} then
        UpdateSimulationCache()
    else
        AutoWarp(cmd)
    end

    -- Calculate latency in seconds
    local latOut = clientstate.GetLatencyOut()
    local latIn = clientstate.GetLatencyIn()
    lerp = (client.GetConVar("cl_interp") + latOut + latIn) or 0
    Latency = Conversion.Time_to_Ticks(latOut + latIn + lerp)

    if Menu.Advanced.AutoRecharge and not warp.IsWarping() and warp.GetChargedTicks() < 24 and not warp.CanWarp() then
        globalCounter = globalCounter + globals.TickInterval()
        if globalCounter >= (24 + Latency) * globals.TickInterval() or killed then
            warp.TriggerCharge()
            globalCounter = 0  -- Reset the global counter
            killed = false  -- Reset the killed flag
        end
    end
end

local consolas = draw.CreateFont("Consolas", 17, 500)
local current_fps = 0
local function doDraw()
    draw.SetFont(consolas)
    draw.Color(255, 255, 255, 255)
    pLocal = entities.GetLocalPlayer()

    --[[ update fps every 100 frames
    if globals.FrameCount() % 100 == 0 then
      current_fps = math.floor(1 / globals.FrameTime())
    end

    --draw.Text(5, 5, "[Auto trickstab | fps: " .. current_fps .. "]")]]

    if Menu.Visuals.Active and TargetPlayer and TargetPlayer.Pos then
        -- Visualize Simulated Positions
        if Menu.Visuals.VisualizePoints and positions then
            for _, point in ipairs(positions) do
                local screenPos = client.WorldToScreen(Vector3(point.x, point.y, point.z))
                if screenPos then
                    draw.Color(0, 255, 0, 255)  -- Green color for simulated positions
                    draw.FilledRect(screenPos[1] - 2, screenPos[2] - 2, screenPos[1] + 2, screenPos[2] + 2)
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

        -- Visualize Attack Circle
        if Menu.Visuals.Attack_Circle and pLocal then
            local centerPOS = pLocal:GetAbsOrigin() -- Center of the circle at the player's feet
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
                local circlePoint = centerPOS + Vector3(math.cos(angle), math.sin(angle), 0) * radius

                local trace = engine.TraceLine(viewPos, circlePoint, MASK_SHOT_HULL)
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

        -- Visualize Forward Line
        if Menu.Visuals.BackLine and TargetPlayer then
            local Back = TargetPlayer.Back
            local hitboxPos = TargetPlayer.viewpos

            -- Calculate end point of the line in the backward direction
            local lineLength = 50  -- Length of the line, you can adjust this as needed
            local endPoint = hitboxPos + (Back * lineLength)  -- Move in the backward direction

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



-----------------------------------------------------------------------------------------------------
    --Menu
    CheckMenu()

    if Lbox_Menu_Open == true and ImMenu and ImMenu.Begin("Auto Trickstab", true) then
        ImMenu.BeginFrame(1) -- tabs
            local tabs = {"Main", "Advanced", "Visuals"}
            Menu.currentTab = ImMenu.TabControl(tabs, Menu.currentTab)
        ImMenu.EndFrame()

        if Menu.currentTab == 1 then
            ImMenu.BeginFrame(1)
                ImMenu.Text("Please Use Lbox Auto Backstab")
            ImMenu.EndFrame()

            ImMenu.BeginFrame(1)
                Menu.Main.Active = ImMenu.Checkbox("Active", Menu.Main.Active)
            ImMenu.EndFrame()

            ImMenu.BeginFrame(1)
                Menu.Main.AutoWalk = ImMenu.Checkbox("Auto Walk", Menu.Main.AutoWalk)
                Menu.Main.AutoWarp = ImMenu.Checkbox("Auto Warp", Menu.Main.AutoWarp)
            ImMenu.EndFrame()

            ImMenu.BeginFrame(1)
                Menu.Main.AutoBlink  = ImMenu.Checkbox("Auto Blink ", Menu.Main.AutoBlink )
                --ImMenu.Text("Assistance (WIP)")
                Menu.Main.MoveAsistance = ImMenu.Checkbox("Move Asistance", Menu.Main.MoveAsistance)
            ImMenu.EndFrame()
        end

        if Menu.currentTab == 2 then
            ImMenu.BeginFrame(1)
                Menu.Advanced.ManualDirection = ImMenu.Checkbox("Manual Direction", Menu.Advanced.ManualDirection)
                Menu.Advanced.AutoRecharge = ImMenu.Checkbox("Auto Recharge", Menu.Advanced.AutoRecharge)
            ImMenu.EndFrame()

            ImMenu.BeginFrame(1)
            print(Menu.Advanced.WarpTolerance)
                Menu.Advanced.WarpTolerance = ImMenu.Slider("Warp Tolerance", Menu.Advanced.WarpTolerance, 1, 180)
            ImMenu.EndFrame()

            ImMenu.BeginFrame(1)
                Menu.Advanced.ColisionCheck = ImMenu.Checkbox("Colision Check", Menu.Advanced.ColisionCheck)
                Menu.Advanced.AdvancedPred = ImMenu.Checkbox("Advanced Pred", Menu.Advanced.AdvancedPred)
            ImMenu.EndFrame()
        end

        if Menu.currentTab == 3 then
            ImMenu.BeginFrame(1)
                Menu.Visuals.Active = ImMenu.Checkbox("Active", Menu.Visuals.Active)
            ImMenu.EndFrame()

            ImMenu.BeginFrame(1)
                Menu.Visuals.VisualizePoints = ImMenu.Checkbox("Simulations", Menu.Visuals.VisualizePoints)
                Menu.Visuals.VisualizeStabPoint = ImMenu.Checkbox("Stab Points", Menu.Visuals.VisualizeStabPoint)
            ImMenu.EndFrame()

            ImMenu.BeginFrame(1)
                Menu.Visuals.Attack_Circle = ImMenu.Checkbox("Attack Circle", Menu.Visuals.Attack_Circle)
                Menu.Visuals.BackLine = ImMenu.Checkbox("Forward Line", Menu.Visuals.BackLine)
            ImMenu.EndFrame()
        end
        ImMenu.End()
    end
end

--[[ Remove the menu when unloaded ]]--
local function OnUnload()                                -- Called when the script is unloaded
    UnloadLib() --unloading lualib
    CreateCFG(string.format([[Lua %s]], Lua__fileName), Menu) --saving the config
    engine.PlaySound("hl1/fvox/deactivated.wav")
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
engine.PlaySound("hl1/fvox/activated.wav")