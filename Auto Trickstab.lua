-- Full script with Left Shift (key 42) hold-to-activate gating applied
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
-- Key codes
local KEY_LSHIFT = 42 -- left Shift key code per task requirement
local Menu = { -- config
    Version = 2.9,
    currentTab = 1,
    tabs = { Main = true, Advanced = false, Visuals = false },
    Main = { Active = true, AutoWalk = true, AutoWarp = true, AutoBlink = false, MoveAsistance = true },
    Advanced = { WarpTolerance = 77, AutoRecharge = true, ManualDirection = false },
    Visuals = { Active = true, VisualizePoints = true, VisualizeStabPoint = true, VisualizeUsellesSimulations = true, Attack_Circle = false, BackLine = false },
}
local pLocal = entities.GetLocalPlayer() or nil
local emptyVec = Vector3(0,0,0)
local pLocalPos = emptyVec
local pLocalViewPos = emptyVec
local pLocalViewOffset = Vector3(0, 0, 75)
local vHitbox = { Min = Vector3(-23.99, -23.99, 0), Max = Vector3(23.99, 23.99, 82) }
local TargetPlayer = {}
local endwarps = {}
local BACKSTAB_RANGE = 66
local lastToggleTime = 0
local Lbox_Menu_Open = true
local toggleCooldown = 0.7
local function CheckMenu()
    if input.IsButtonDown(72) then -- H key keeps menu toggle
        local currentTime = globals.RealTime()
        if currentTime - lastToggleTime >= toggleCooldown then
            Lbox_Menu_Open = not Lbox_Menu_Open
            lastToggleTime = currentTime
        end
    end
end
-- Hold-to-activate helper
local function IsShiftHeld()
    return input.IsButtonDown(KEY_LSHIFT) == true
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
                if type(key) == "string" then result = result .. '["' .. key .. '"] = ' else result = result .. "[" .. key .. "] = " end
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
            CreateCFG(string.format([[Lua %s]], Lua__fileName), Menu)
            print("Error loading configuration:", err)
        end
    end
end
local status, loadedMenu = pcall(function() return assert(LoadCFG(string.format([[Lua %s]], Lua__fileName))) end)
local function checkAllFunctionsExist(expectedMenu, loadedMenu)
    for key, value in pairs(expectedMenu) do
        if type(value) == 'function' then
            if not loadedMenu[key] or type(loadedMenu[key]) ~= 'function' then return false end
        end
    end
    for key, value in pairs(expectedMenu) do
        if not loadedMenu[key] or type(loadedMenu[key]) ~= type(value) then return false end
    end
    return true
end
if status then
    if checkAllFunctionsExist(Menu, loadedMenu) and not input.IsButtonDown(KEY_LSHIFT) then
        Menu = loadedMenu
    else
        print("Config is outdated or invalid. Creating a new config.")
        CreateCFG(string.format([[Lua %s]], Lua__fileName), Menu)
    end
else
    print("Failed to load config. Creating a new config.")
    CreateCFG(string.format([[Lua %s]], Lua__fileName), Menu)
end
local function Normalize(vec) return  vec / vec:Length() end
local function NormalizeYaw(yaw)
    yaw = yaw % 360
    if yaw > 180 then yaw = yaw - 360 elseif yaw < -180 then yaw = yaw + 360 end
    return yaw
end
local function PositionYaw(source, dest)
    local delta = Normalize(source - dest)
    return math.deg(math.atan(delta.y, delta.x))
end
local function IsNaN(value) return value ~= value end
local MAX_SPEED = 320
local function ComputeMove(cmd, a, b)
    local diff = (b - a)
    if diff:Length() == 0 then return Vector3(0, 0, 0) end
    local vSilent = Vector3(diff.x, diff.y, 0)
    local ang = vSilent:Angles()
    local cPitch, cYaw, cRoll = engine.GetViewAngles():Unpack()
    local yaw = math.rad(ang.y - cYaw)
    local moveX = math.cos(yaw) * MAX_SPEED
    local moveY = -math.sin(yaw) * MAX_SPEED
    if IsNaN(moveX) or IsNaN(moveY) then return Vector3(MAX_SPEED, 0, 0) end
    return Vector3(moveX, moveY, 0)
end
local function WalkTo(cmd, Pos, destination, AdjustView)
    if AdjustView and pLocal and warp.CanWarp() and not warp.IsWarping() then
        local forwardMove = cmd:GetForwardMove()
        local sideMove = cmd:GetSideMove()
        local moveDirectionAngle = 0
        if forwardMove ~= 0 or sideMove ~= 0 then moveDirectionAngle = math.deg(math.atan(sideMove, forwardMove)) end
        local baseYaw = PositionYaw(destination, Pos)
        local adjustedYaw = NormalizeYaw(baseYaw + moveDirectionAngle)
        if not IsNaN(adjustedYaw) then
            local currentAngles = engine.GetViewAngles()
            local newViewAngles = EulerAngles(currentAngles.pitch, adjustedYaw, 0)
            engine.SetViewAngles(newViewAngles)
        end
    end
    local moveToDestination = ComputeMove(cmd, Pos, destination)
    moveToDestination = Normalize(moveToDestination) * 450
    if IsNaN(moveToDestination.x) or IsNaN(moveToDestination.y) then
        cmd:SetForwardMove(450)
        cmd:SetSideMove(0)
    else
        cmd:SetForwardMove(moveToDestination.x)
        cmd:SetSideMove(moveToDestination.y)
    end
end
local BackstabPos = emptyVec
local globalCounter = 0
function IsReadyToAttack(cmd, weapon)
    local TickCount = globals.TickCount()
    local NextAttackTick = Conversion.Time_to_Ticks(weapon:GetPropFloat("m_flNextPrimaryAttack") or 0)
    if NextAttackTick <= TickCount and warp.CanDoubleTap(weapon) then
        LastAttackTick = TickCount
        CanAttackNow = true
        return true
    else
        CanAttackNow = false
    end
    return false
end
local positions = {}
local function UpdateLocalPlayerCache()
    pLocal = entities.GetLocalPlayer()
    if not pLocal or pLocal:GetPropInt("m_iClass") ~= TF2_Spy or not pLocal:IsAlive() or pLocal:InCond(TFCond_Cloaked) or pLocal:InCond(TFCond_CloakFlicker) or pLocal:GetPropInt("m_bFeignDeathReady") == 1 then return false end
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
    local maxAttackDistance = 225
    local bestDistance = maxAttackDistance + 1
    local ignoreinvisible = (gui.GetValue("ignore cloaked"))
    for _, player in pairs(allPlayers) do
        if player:IsAlive() and not player:IsDormant() and player:GetTeamNumber() ~= pLocal:GetTeamNumber() and (ignoreinvisible == 1 and not player:InCond(4)) then
            local playerPos = player:GetAbsOrigin()
            local distance = (pLocalPos - playerPos):Length()
            local viewAngles = player:GetPropVector("tfnonlocaldata", "m_angEyeAngles[0]")
            local viewYaw = viewAngles and EulerAngles(viewAngles:Unpack()).yaw or 0
            if distance < maxAttackDistance and distance < bestDistance then
                bestDistance = distance
                local viewoffset = player:GetPropVector("localdata", "m_vecViewOffset[0]")
                bestTargetDetails = { entity = player, Pos = playerPos, NextPos = playerPos + player:EstimateAbsVelocity() * globals.TickInterval(), viewpos = playerPos + viewoffset, viewYaw = viewYaw, Back = -EulerAngles(viewAngles:Unpack()):Forward() }
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
local function IsInRange(targetPos, spherePos, sphereRadius)
    local hitbox_min_trigger = targetPos + vHitbox.Min
    local hitbox_max_trigger = targetPos + vHitbox.Max
    local closestPoint = Vector3(
        math.max(hitbox_min_trigger.x, math.min(spherePos.x, hitbox_max_trigger.x)),
        math.max(hitbox_min_trigger.y, math.min(spherePos.y, hitbox_max_trigger.y)),
        math.max(hitbox_min_trigger.z, math.min(spherePos.z, hitbox_max_trigger.z))
    )
    local distanceSquared = (spherePos - closestPoint):LengthSqr()
    if sphereRadius * sphereRadius > distanceSquared then
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
        return false, nil
    end
end
local function CheckBackstab(testPoint)
    local viewPos = testPoint + pLocalViewOffset
    local enemyYaw = NormalizeYaw(PositionYaw(TargetPlayer.viewpos, TargetPlayer.viewpos + TargetPlayer.Back))
    local spyYaw = NormalizeYaw(PositionYaw(TargetPlayer.viewpos, viewPos))
    if CheckYawDelta(spyYaw, enemyYaw) and IsInRange(TargetPlayer.Pos, viewPos, BACKSTAB_RANGE) then
        return true
    end
    return false
end
local SIMULATION_TICKS = 23
local FORWARD_COLLISION_ANGLE = 55
local GROUND_COLLISION_ANGLE_LOW = 45
local GROUND_COLLISION_ANGLE_HIGH = 55
local function handleForwardCollision(vel, wallTrace)
    local normal = wallTrace.plane
    local angle = math.deg(math.acos(normal:Dot(Vector3(0, 0, 1))))
    if angle > FORWARD_COLLISION_ANGLE then
        local dot = vel:Dot(normal)
        vel = vel - normal * dot
    end
    return wallTrace.endpos.x, wallTrace.endpos.y
end
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
local simulationCache = { tickInterval = globals.TickInterval(), gravity = client.GetConVar("sv_gravity"), stepSize = pLocal and pLocal:GetPropFloat("localdata", "m_flStepSize") or 0, flags = pLocal and pLocal:GetPropInt("m_fFlags") or 0 }
local function UpdateSimulationCache()
    simulationCache.tickInterval = globals.TickInterval()
    simulationCache.gravity = client.GetConVar("sv_gravity")
    simulationCache.stepSize = pLocal and pLocal:GetPropFloat("localdata", "m_flStepSize") or 0
    simulationCache.flags = pLocal and pLocal:GetPropInt("m_fFlags") or 0
end
local ignoreEntities = {"CTFAmmoPack", "CTFDroppedWeapon"}
local function shouldHitEntityFun(entity, player)
    for _, ignoreEntity in ipairs(ignoreEntities) do if entity:GetClass() == ignoreEntity then return false end end
    if entity:GetName() == player:GetName() then return false end
    if entity:GetTeamNumber() == player:GetTeamNumber() then return false end
    return true
end
local function SimulateDash(simulatedVelocity, ticks)
    simulatedVelocity = Normalize(simulatedVelocity) * pLocal:EstimateAbsVelocity():Length()
    local tick_interval
