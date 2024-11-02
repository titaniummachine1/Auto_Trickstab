
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
local toggleCooldown = 0.7

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

local function PositionYaw(source, dest)
    local delta = Normalize(source - dest)
    return math.deg(math.atan(delta.y, delta.x))
end

-- Check if a value is NaN
local function IsNaN(value)
    return value ~= value
end

local MAX_SPEED = 320  -- Maximum speed

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

local BackstabPos = emptyVec
local globalCounter = 0

-- Function to check if the weapon can attack right now
function IsReadyToAttack(cmd, weapon)
    local TickCount = globals.TickCount()
    local NextAttackTick = Conversion.Time_to_Ticks(weapon:GetPropFloat("m_flNextPrimaryAttack") or 0)

    -- Check if the weapon's next attack time is less than or equal to the current tick
    if NextAttackTick <= TickCount and warp.CanDoubleTap(weapon) then
        LastAttackTick = TickCount  -- Update the last attack tick
        CanAttackNow = true         -- Set flag for readiness
        return true                 -- Ready to attack this tick
    else
        CanAttackNow = false
    end
    return false
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

local function UpdateTarget()
    local allPlayers = entities.FindByClass("CTFPlayer")
    local bestTargetDetails = nil
    local maxAttackDistance = 225  -- Attack range plus warp distance
    local bestDistance = maxAttackDistance + 1  -- Initialize to a large number
    local ignoreinvisible = (gui.GetValue("ignore cloaked"))

    for _, player in pairs(allPlayers) do
        if player:IsAlive()
            and not player:IsDormant()
            and player:GetTeamNumber() ~= pLocal:GetTeamNumber()
            and (ignoreinvisible == 1 and not player:InCond(4)) then

            local playerPos = player:GetAbsOrigin()
            local distance = (pLocalPos - playerPos):Length()
            local viewAngles = player:GetPropVector("tfnonlocaldata", "m_angEyeAngles[0]")  -- Fetching eye angles directly
            local viewYaw = viewAngles and EulerAngles(viewAngles:Unpack()).yaw or 0

            -- Check if the player is within the attack range
            if distance < maxAttackDistance and distance < bestDistance then
                bestDistance = distance
                local viewoffset = player:GetPropVector("localdata", "m_vecViewOffset[0]")
                bestTargetDetails = {
                    entity = player,
                    Pos = playerPos,
                    NextPos = playerPos + player:EstimateAbsVelocity() * globals.TickInterval(),
                    viewpos = playerPos + viewoffset,
                    viewYaw = viewYaw,  -- Include yaw for backstab calculations
                    Back = -EulerAngles(viewAngles:Unpack()):Forward(),  -- Ensure Back is accurate
                }
            end
        end
    end

    return bestTargetDetails
end

local function CheckYawDelta(angle1, angle2)
    local difference = NormalizeYaw(angle1 - angle2)
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

local function SimulateDash(simulatedVelocity, ticks)
    -- Normalize the simulated velocity and set it to the player's current speed
    simulatedVelocity = Normalize(simulatedVelocity) * pLocal:EstimateAbsVelocity():Length()
    local tick_interval = globals.TickInterval()

    -- Set gravity and step size from cached values
    local gravity = simulationCache.gravity * tick_interval
    local stepSize = simulationCache.stepSize
    local vUp = Vector3(0, 0, 1)
    local vStep = Vector3(0, 0, stepSize or 18)

    -- Helper to determine if an entity should be hit
    local shouldHitEntity = function(entity) return shouldHitEntityFun(entity, pLocal) end

    -- Initialize simulation state
    local lastP = pLocalPos
    local lastV = simulatedVelocity
    local flags = simulationCache.flags
    local lastG = (flags & 1 == 1)  -- Check if initially on the ground

    -- Track the closest backstab opportunity
    local closestBackstabPos = nil
    local minWarpTicks = ticks + 1  -- Initialize to a high value outside of tick range

    for i = 1, ticks do
        -- Calculate the new position based on the velocity
        local pos = lastP + lastV * tick_interval
        local vel = lastV
        local onGround = lastG

        -- Collision and movement logic
        if Menu.Advanced.ColisionCheck then
            local wallTrace = engine.TraceHull(lastP + vStep, pos + vStep, vHitbox.Min, vHitbox.Max, MASK_PLAYERSOLID, shouldHitEntity)
            if wallTrace.fraction < 1 then
                if wallTrace.entity then
                    if wallTrace.entity:GetClass() == "CTFPlayer" then
                        break
                    else
                        pos.x, pos.y = handleForwardCollision(vel, wallTrace)
                    end
                else
                    pos.x, pos.y = handleForwardCollision(vel, wallTrace)
                end
            end

            local downStep = onGround and vStep or Vector3(0, 0, 0)
            local groundTrace = engine.TraceHull(pos + vStep, pos - downStep, vHitbox.Min, vHitbox.Max, MASK_PLAYERSOLID, shouldHitEntity)
            if groundTrace.fraction < 1 then
                pos, onGround = handleGroundCollision(vel, groundTrace, vUp)
            else
                onGround = false
            end
        end

        -- Simulate jumping if space is pressed
        if onGround and input.IsButtonDown(KEY_SPACE) then
            vel.z = (gui.GetValue("Duck Jump") == 1) and 277 or 271
            onGround = false
        end

        -- Apply gravity if not on the ground
        if not onGround then
            vel.z = vel.z - gravity
        end

        -- Check for backstab possibility at the current position
        local isBackstab = CheckBackstab(pos)

        -- Store each tick position and backstab status for visualization
        positions[i] = pos  -- Store every tick position for later visualization
        endwarps[i] = {pos, isBackstab}

        -- Update closest backstab position if available at this tick
        if isBackstab and i < minWarpTicks then
            minWarpTicks = i
            closestBackstabPos = pos
        end

        -- Update simulation state
        lastP, lastV, lastG = pos, vel, onGround
    end

    -- Return closest backstab position, minimum warp ticks, and final simulated position
    return lastP, closestBackstabPos, minWarpTicks
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

local BACKSTAB_MAX_YAW_DIFF = 180  -- Maximum allowable yaw difference for backstab

local function CalculateTrickstab(cmd)
    if not TargetPlayer or not TargetPlayer.Pos then
        return emptyVec, nil, nil
    end

    local my_pos = pLocalPos
    local enemy_pos = TargetPlayer.Pos
    local hitbox_size = 49
    local vertical_range = 82

    local all_positions = get_best_corners_or_origin(my_pos, enemy_pos, hitbox_size, vertical_range) or {}

    -- Calculate yaw differences to determine best direction (left or right)
    local left_yaw_diff, right_yaw_diff, center_yaw_diff = math.huge, math.huge, math.huge
    for _, pos in ipairs(all_positions) do
        local test_yaw = PositionYaw(enemy_pos, enemy_pos + pos)
        local enemy_yaw = TargetPlayer.viewYaw
        local yaw_diff = math.abs(NormalizeYaw(test_yaw - enemy_yaw))

        if pos.y > 0 then
            left_yaw_diff = math.min(left_yaw_diff, yaw_diff)
        elseif pos.y < 0 then
            right_yaw_diff = math.min(right_yaw_diff, yaw_diff)
        elseif pos == center then
            center_yaw_diff = yaw_diff
        end
    end

    -- Determine which side to prioritize based on yaw difference
    local best_side = (left_yaw_diff < right_yaw_diff) and "left" or "right"
    local best_positions = {}

    -- Check if we’re behind the enemy (within 180-degree range) and filter positions accordingly
    if math.min(left_yaw_diff, right_yaw_diff, center_yaw_diff) < 90 then
        -- If behind enemy, include the optimal side and center
        for _, pos in ipairs(all_positions) do
            if ((best_side == "left" and pos.y > 0) or (best_side == "right" and pos.y < 0) or pos == center) then
                table.insert(best_positions, pos)
            end
        end
    else
        -- If not behind enemy, include only the optimal side
        for _, pos in ipairs(all_positions) do
            if (best_side == "left" and pos.y > 0) or (best_side == "right" and pos.y < 0) then
                table.insert(best_positions, pos)
            end
        end
    end

    -- Track the optimal backstab position based on scoring
    local optimalBackstabPos = nil
    local bestScore = -1
    local minWarpTicks = math.huge
    positions = {}
    endwarps = {}

    for _, test_pos in ipairs(best_positions) do
        local final_pos, backstab_pos, warpTicks = SimulateDash(enemy_pos + test_pos - my_pos, warp.GetChargedTicks() or 24)

        -- Store each tick for visualization
        if final_pos then table.insert(positions, final_pos) end
        if backstab_pos then
            table.insert(endwarps, {backstab_pos, true})
        else
            table.insert(endwarps, {final_pos, false})
        end

        if backstab_pos then
            local spyYaw = PositionYaw(enemy_pos, backstab_pos)
            local enemyYaw = TargetPlayer.viewYaw
            local isWithinBackstabYaw = CheckYawDelta(spyYaw, enemyYaw)

            if isWithinBackstabYaw then
                local yawDiff = math.abs(NormalizeYaw(spyYaw - enemyYaw))
                local yawComponent = math.max(0, 1 - yawDiff / BACKSTAB_MAX_YAW_DIFF)

                local distance = (backstab_pos - enemy_pos):Length()
                local distanceComponent = math.max(0, math.min(1, (120 - distance) / (120 - 48)))

                local score = 0.5 * yawComponent + 0.5 * distanceComponent

                if score > bestScore or (score == bestScore and warpTicks < minWarpTicks) then
                    bestScore = score
                    optimalBackstabPos = backstab_pos
                    minWarpTicks = warpTicks
                end
            end
        end
    end

    return optimalBackstabPos or emptyVec, bestScore, minWarpTicks
end

local killed = false

local function damageLogger(event)
    if (event:GetName() == 'player_death') then
        pLocal = entities:GetLocalPlayer()

        local attacker = entities.GetByUserID(event:GetInt("attacker"))
        if attacker and attacker:IsValid() and pLocal:GetIndex() == attacker:GetIndex() then --getBool(event, "crit")
            killed = true  -- Flag a kill to trigger recharge
        end
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

-- Function to handle controlled warp without triggering attacks
local function PerformControlledWarp(cmd, targetPos, warpTicks)
    -- Set the necessary number of ticks for the warp
    client.RemoveConVarProtection("sv_maxusrcmdprocessticks")
    client.SetConVar("sv_maxusrcmdprocessticks", warpTicks, true)

    -- Move to target position
    WalkTo(cmd, pLocalPos, targetPos, true)  -- Align movement towards the target

    -- Execute the warp
    warp.TriggerWarp()

    -- Reset sv_maxusrcmdprocessticks after warp
    client.SetConVar("sv_maxusrcmdprocessticks", 24, true)
end


-- Modified AutoWarp to use minWarpTicks from CalculateTrickstab
local function AutoWarp(cmd)
    local sideMove = cmd:GetSideMove()
    local forwardMove = cmd:GetForwardMove()

    -- Calculate the optimal backstab position based on the current command
    BackstabPos, bestScore, minWarpTicks = CalculateTrickstab(cmd)

    -- Ensure we have a valid position for backstab
    if BackstabPos ~= emptyVec and minWarpTicks then
        -- Determine movement and warp directions
        local MoveDirection = PositionYaw(pLocalPos, pLocal:EstimateAbsVelocity())
        local WarpDir = PositionYaw(pLocalPos, BackstabPos)
        local canstab = CheckBackstab(BackstabPos)

        -- Movement Assistance: Move towards target if backstab isn't immediately possible
        if Menu.Main.MoveAsistance and not canstab then
            if forwardMove > 0 or sideMove ~= 0 then
                FakelagOn()  -- Enable fake lag for smoother movement
                WalkTo(cmd, pLocalPos, BackstabPos, false)  -- Walk to position without triggering warp
                return  -- Skip warp logic when using movement assistance
            end
            FakelagOff()
        end

        -- Auto Warp Handling: Conditions for triggering a warp
        if Menu.Main.AutoWarp and canstab and not warp.IsWarping() and warp.CanWarp() and warp.GetChargedTicks() >= 23 then
            -- Calculate the number of ticks needed for the warp (use minimum required)
            local warpTicks = math.min(warp.GetChargedTicks(), minWarpTicks)

            -- Perform the controlled warp to the optimal backstab position
            PerformControlledWarp(cmd, BackstabPos, warpTicks)
        elseif canstab then
            FakelagOn()  -- Enable fake lag if warp is unavailable or backstab not viable yet
        end
    else
        FakelagOff()  -- Disable fake lag if no action needed (no valid backstab position)
    end
end

local Latency = 0
local lerp = 0
-- Main function to control the create move process and use AutoWarp and SimulateAttack effectively
local function OnCreateMove(cmd)
    if not Menu.Main.Active then return end
    CheckMenu()

    -- Reset tables for storing positions and backstab states
    positions = {}  -- Stores all tick positions for visualization
    endwarps = {}   -- Stores warp data for each tick, including backstab status

    local latOut = clientstate.GetLatencyOut()
    local latIn = clientstate.GetLatencyIn()
    lerp = (client.GetConVar("cl_interp") + latOut + latIn) or 0
    Latency = Conversion.Time_to_Ticks(latOut + latIn + lerp)

    if Menu.Advanced.AutoRecharge and not warp.IsWarping() and warp.GetChargedTicks() < 24 and not warp.CanWarp() then
        globalCounter = globalCounter + globals.TickInterval()
        if globalCounter >= (24 + Latency) * globals.TickInterval() or killed then
            warp.TriggerCharge()
            globalCounter = 0
            killed = false
        end
    end

    if UpdateLocalPlayerCache() == false or not pLocal then return end

    local pWeapon = pLocal:GetPropEntity("m_hActiveWeapon")
    if not pWeapon then return end
    if pLocal:InCond(4) then return end
    if not IsReadyToAttack(cmd, pWeapon) then return end

    TargetPlayer = UpdateTarget()
    if TargetPlayer == {} then
        UpdateSimulationCache()
    else
        AutoWarp(cmd)
    end
end


local consolas = draw.CreateFont("Consolas", 17, 500)
local current_fps = 0
local function doDraw()
    draw.SetFont(consolas)
    draw.Color(255, 255, 255, 255)
    pLocal = entities.GetLocalPlayer()

    -- Update FPS every 100 frames
    if globals.FrameCount() % 100 == 0 then
      current_fps = math.floor(1 / globals.FrameTime())
    end

    if Menu.Visuals.Active and TargetPlayer and TargetPlayer.Pos then
        -- Visualize Simulated Positions for each tick
        if Menu.Visuals.VisualizePoints and positions then
            for tick, point in ipairs(positions) do
                local screenPos = client.WorldToScreen(Vector3(point.x, point.y, point.z))
                if screenPos then
                    draw.Color(0, 255, 0, 255)  -- Green color for simulated positions
                    draw.FilledRect(screenPos[1] - 1, screenPos[2] - 1, screenPos[1] + 1, screenPos[2] + 1)
                end
            end
        end

        -- Visualize backstab potential points with different colors
        if Menu.Visuals.VisualizeStabPoint and endwarps then
            for tick, warpData in ipairs(endwarps) do
                local pos, isBackstab = warpData[1], warpData[2]
                local screenPos = client.WorldToScreen(Vector3(pos.x, pos.y, pos.z))

                if screenPos then
                    if isBackstab then
                        draw.Color(255, 0, 0, 255)  -- Red color for backstab points
                        draw.FilledRect(screenPos[1] - 5, screenPos[2] - 5, screenPos[1] + 5, screenPos[2] + 5)
                    else
                        draw.Color(255, 255, 255, 255)  -- White color for non-backstab points
                        draw.FilledRect(screenPos[1] - 2, screenPos[2] - 2, screenPos[1] + 2, screenPos[2] + 2)
                    end
                    
                end
            end
        end
    

        -- Visualize Attack Circle around the player
        if Menu.Visuals.Attack_Circle and pLocal then
            local centerPOS = pLocal:GetAbsOrigin() -- Center of the circle at the player's feet
            local viewPos = pLocalViewPos -- View position to shoot traces from
            local radius = 220 -- Radius of the circle
            local segments = 32 -- Number of segments to draw the circle
            local angleStep = (2 * math.pi) / segments

            -- Set the drawing color based on TargetPlayer's presence
            local circleColor = TargetPlayer and {0, 255, 0, 255} or {255, 255, 255, 255} -- Green if TargetPlayer exists, otherwise white
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

        -- Visualize Forward Line for backstab direction
        if Menu.Visuals.BackLine and TargetPlayer then
            local Back = TargetPlayer.Back
            local hitboxPos = TargetPlayer.viewpos

            -- Calculate end point of the line in the backward direction
            local lineLength = 50  -- Length of the line, adjust as needed
            local endPoint = hitboxPos + (Back * lineLength)  -- Move in the backward direction

            -- Convert 3D points to screen space
            local screenStart = client.WorldToScreen(hitboxPos)
            local screenEnd = client.WorldToScreen(endPoint)

            -- Draw the backstab line
            if screenStart and screenEnd then
                draw.Color(0, 255, 255, 255)  -- Cyan color for the backstab line
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