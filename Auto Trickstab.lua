---@diagnostic disable: param-type-mismatch

---@alias AimTarget { entity : Entity, angles : EulerAngles, factor : number }

---@type boolean, lnxLib
local libLoaded, lnxLib = pcall(require, "lnxLib")
if not libLoaded then
	client.ChatPrintf("\x07FF0000LnxLib failed to load!")
	engine.PlaySound("common/bugreporter_failed.wav")
	return
end

assert(libLoaded, "lnxLib not found, please install it!")
assert(lnxLib.GetVersion() >= 1.00, "lnxLib version is too old, please update it!")

-- Unload the module if it's already loaded
if package.loaded["TimMenu"] then
	package.loaded["TimMenu"] = nil
end

local menuLoaded, TimMenu = pcall(require, "TimMenu")
if not menuLoaded then
	client.ChatPrintf("\x07FF0000TimMenu failed to load!")
	engine.PlaySound("common/bugreporter_failed.wav")
	return
end

assert(menuLoaded, "TimMenu not found, please install it!")

local Math, Conversion = lnxLib.Utils.Math, lnxLib.Utils.Conversion
local WPlayer, WWeapon = lnxLib.TF2.WPlayer, lnxLib.TF2.WWeapon
local Helpers = lnxLib.TF2.Helpers
local Prediction = lnxLib.TF2.Prediction

local Menu = { -- this is the config that will be loaded every time u load the script

	Version = 3.0, -- dont touch this, this is just for managing the config version

	currentTab = 1,
	tabs = { -- dont touch this, this is just for managing the tabs in the menu
		Main = true,
		Advanced = false,
		Visuals = false,
	},

	Main = {
		Active = true, --disable lua
		AutoWalk = true,
		AutoWarp = true,
		AutoBlink = false,
		MoveAsistance = true,
		Keybind = KEY_NONE, -- Keybind for trickstab activation
		ActivationMode = 0, -- 0=Always, 1=On Hold, 2=On Release, 3=Toggle, 4=On Click
	},

	Advanced = {
		BackstabRange = 66, -- Backstab range in hammer units
		MinBackstabPoints = 4, -- Minimum number of backstab points in simulation before allowing warp (slider: 1-30)
		MaxBackstabTime = 14, -- Maximum time (in ticks) to attempt backstab
		UseAngleSnap = true, -- Use angle snapping for movement (disable for smooth rotation - needs lbox fix)
	},

	Visuals = {
		Active = true,
		VisualizePoints = true,
		VisualizeStabPoint = true,
		VisualizeUsellesSimulations = true,
		Attack_Circle = true,
		BackLine = false,
	},
}

local pLocal = entities.GetLocalPlayer() or nil
local emptyVec = Vector3(0, 0, 0)

local pLocalPos = emptyVec
local pLocalViewPos = emptyVec
local pLocalViewOffset = Vector3(0, 0, 75)
local vHitbox = { Min = Vector3(-23.99, -23.99, 0), Max = Vector3(23.99, 23.99, 82) }

local TargetPlayer = {}
local endwarps = {}
local debugCornerData = {} -- Debug info for corner visualization

-- Constants
local BACKSTAB_RANGE = 66 -- Hammer units

-- Cache ConVars for performance (accessed frequently)
local SV_GRAVITY = client.GetConVar("sv_gravity")
local CL_INTERP = client.GetConVar("cl_interp")

-- Class max speeds (units per second) - from Swing Prediction
local CLASS_MAX_SPEEDS = {
	[1] = 400, -- Scout
	[2] = 240, -- Sniper
	[3] = 240, -- Soldier
	[4] = 280, -- Demoman
	[5] = 230, -- Medic
	[6] = 300, -- Heavy
	[7] = 240, -- Pyro
	[8] = 320, -- Spy
	[9] = 320, -- Engineer
}

-- Keybind state tracking
local previousKeyState = false
local toggleActive = false
local clickProcessed = false

-- Function to check if keybind should activate trickstab logic
local function ShouldActivateTrickstab()
	-- Mode 0: Always - always active, no keybind needed
	if Menu.Main.ActivationMode == 0 then
		return true
	end

	-- For other modes, check keybind
	if Menu.Main.Keybind == KEY_NONE then
		return true -- Fallback if no keybind set
	end

	local currentKeyState = input.IsButtonDown(Menu.Main.Keybind)
	local shouldActivate = false

	-- Mode 1: On Hold - only active while holding the key
	if Menu.Main.ActivationMode == 1 then
		shouldActivate = currentKeyState

	-- Mode 2: On Release - active when NOT holding the key (reversed from On Hold)
	elseif Menu.Main.ActivationMode == 2 then
		shouldActivate = not currentKeyState

	-- Mode 3: Toggle - toggle on/off with key press
	elseif Menu.Main.ActivationMode == 3 then
		if currentKeyState and not previousKeyState then
			toggleActive = not toggleActive
		end
		shouldActivate = toggleActive

	-- Mode 4: On Click - activate once per key press
	elseif Menu.Main.ActivationMode == 4 then
		if currentKeyState and not previousKeyState then
			clickProcessed = false
		end
		if not currentKeyState and previousKeyState then
			clickProcessed = true -- Reset for next click
		end
		shouldActivate = currentKeyState and not clickProcessed
	end

	previousKeyState = currentKeyState
	return shouldActivate
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
		printc(255, 183, 0, 255, "[" .. os.date("%H:%M:%S") .. "] Saved Config to " .. tostring(fullPath))
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
			printc(0, 255, 140, 255, "[" .. os.date("%H:%M:%S") .. "] Loaded Config from " .. tostring(fullPath))
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
		if type(value) == "function" then
			-- Check if the function exists in the loaded menu and has the correct type
			if not loadedMenu[key] or type(loadedMenu[key]) ~= "function" then
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
	return vec / vec:Length()
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

-- TF2 Physics Constants for velocity simulation
local TF2_GROUND_FRICTION = 4.0
local TF2_STOPSPEED = 100
local TF2_ACCEL = 10 -- Ground acceleration

local MAX_SPEED = 320 -- Maximum speed

-- Apply ground friction to velocity
local function ApplyFriction(velocity, onGround)
	if not onGround then
		return velocity
	end

	local speed = velocity:Length()
	if speed < 0.1 then
		return Vector3(0, 0, 0)
	end

	local drop = 0
	local control = math.max(speed, TF2_STOPSPEED)
	drop = control * TF2_GROUND_FRICTION * globals.TickInterval()

	local newSpeed = math.max(0, speed - drop)
	if newSpeed ~= speed then
		newSpeed = newSpeed / speed
		return velocity * newSpeed
	end

	return velocity
end

-- Calculate optimal movement direction towards target
local function CalculateOptimalMoveDir(currentVel, currentPos, targetPos)
	local toTarget = targetPos - currentPos
	local distance = toTarget:Length()

	if distance < 1 then
		return Vector3(0, 0, 0)
	end

	local targetDir = Normalize(toTarget)

	-- If we have velocity, blend with current direction for smooth pathing
	local currentSpeed = currentVel:Length()
	if currentSpeed > 10 then
		local currentDir = Normalize(currentVel)
		-- Blend 30% current direction, 70% target direction
		local blendedDir = Normalize(currentDir * 0.3 + targetDir * 0.7)
		return blendedDir
	end

	return targetDir
end

-- Simulate optimal path with velocity and acceleration
local function SimulateVelocityPath(startPos, startVel, targetPos, numTicks, playerClass)
	local pos = startPos
	local vel = startVel
	local maxSpeed = CLASS_MAX_SPEEDS[playerClass] or 320

	for tick = 1, numTicks do
		-- Calculate optimal direction
		local optimalDir = CalculateOptimalMoveDir(vel, pos, targetPos)

		-- Apply acceleration towards target
		local accelVector = optimalDir * (TF2_ACCEL * 10 * globals.TickInterval())
		vel = vel + accelVector

		-- Cap to max speed (horizontal only)
		local horizSpeed = math.sqrt(vel.x * vel.x + vel.y * vel.y)
		if horizSpeed > maxSpeed then
			local scale = maxSpeed / horizSpeed
			vel = Vector3(vel.x * scale, vel.y * scale, vel.z)
		end

		-- Apply friction
		vel = ApplyFriction(vel, true) -- Assume on ground during warp

		-- Update position
		pos = pos + vel * globals.TickInterval()
	end

	return pos, vel
end

-- ===== TWO-PASS WARP SIMULATION SYSTEM =====

-- Simplified physics simulation for warp (no collision, no gravity if on ground)
local function SimulateWarpNoCollision(startPos, startVel, moveDir, warpTicks, playerClass)
	local pos = startPos
	local vel = startVel
	local maxSpeed = CLASS_MAX_SPEEDS[playerClass] or 320

	for tick = 1, warpTicks do
		-- Apply acceleration in movement direction
		local accelVector = moveDir * (TF2_ACCEL * 10 * globals.TickInterval())
		vel = vel + accelVector

		-- Cap to max speed (horizontal only)
		local horizSpeed = math.sqrt(vel.x * vel.x + vel.y * vel.y)
		if horizSpeed > maxSpeed then
			local scale = maxSpeed / horizSpeed
			vel = Vector3(vel.x * scale, vel.y * scale, vel.z)
		end

		-- Apply friction (assuming on ground during warp)
		vel = ApplyFriction(vel, true)

		-- Update position (no collision check, no gravity if on ground)
		pos = pos + vel * globals.TickInterval()
	end

	return pos, vel
end

-- Calculate optimal movement direction to reach target
local function CalculateOptimalMoveDirection(currentPos, currentVel, targetPos, warpTicks, playerClass)
	-- Direct vector to target
	local toTarget = targetPos - currentPos
	local targetDir = Normalize(Vector3(toTarget.x, toTarget.y, 0)) -- Horizontal only

	-- If we have significant velocity, blend it with target direction
	local currentSpeed = currentVel:Length()
	if currentSpeed > 50 then
		local currentDir = Normalize(Vector3(currentVel.x, currentVel.y, 0))
		-- Less blending - prioritize target direction (80% target, 20% current)
		local blendedDir = Normalize(currentDir * 0.2 + targetDir * 0.8)
		return blendedDir
	end

	return targetDir
end

-- Constants for movement
local MAX_CMD_SPEED = 450
local TWO_PI = 2 * math.pi
local DEG_TO_RAD = math.pi / 180

-- Walk in a specific direction relative to view angles
-- Two methods: angle snapping (works now) or smooth rotation (needs lbox fix)
-- forceNoSnap: force disable angle snap (for MoveAsistance without stab points)
local function WalkInDirection(cmd, direction, forceNoSnap)
	local dx, dy = direction.x, direction.y

	-- Default to angle snap if not set (unless forced off)
	local useAngleSnap = Menu.Advanced.UseAngleSnap
	if useAngleSnap == nil then
		useAngleSnap = true
	end

	-- Disable snap if forced (e.g., MoveAsistance without stab points)
	if forceNoSnap then
		useAngleSnap = false
	end

	if useAngleSnap then
		-- METHOD 1: Angle snap - Account for player's current input and rotate view
		-- So that their input direction results in the optimal walk direction

		-- Get player's current input (may be forward, backward, diagonal, etc)
		local forwardMove = cmd:GetForwardMove()
		local sideMove = cmd:GetSideMove()

		-- Calculate desired world direction (radians)
		local targetYaw = math.atan(dy, dx)

		-- If player has input, calculate angle relative to view forward
		-- Otherwise assume walking forward
		local inputAngle = 0
		if math.abs(forwardMove) > 0.1 or math.abs(sideMove) > 0.1 then
			-- TF2: sideMove is NEGATIVE for right, POSITIVE for left
			-- atan2(y, x) gives angle from x-axis (forward)
			-- Negate sideMove to get correct angle direction
			inputAngle = math.atan(-sideMove, forwardMove)
		end

		-- Calculate what view angle makes the input go in target direction
		-- Current movement direction = viewYaw + inputAngle
		-- We want: viewYaw + inputAngle = targetYaw
		-- So: viewYaw = targetYaw - inputAngle
		local desiredViewYaw = targetYaw - inputAngle

		-- Convert to degrees and normalize to -180 to 180
		desiredViewYaw = desiredViewYaw * (180 / math.pi)
		desiredViewYaw = desiredViewYaw % 360
		if desiredViewYaw > 180 then
			desiredViewYaw = desiredViewYaw - 360
		elseif desiredViewYaw < -180 then
			desiredViewYaw = desiredViewYaw + 360
		end

		-- Get current view angles
		local viewAngles = engine.GetViewAngles()

		-- Set absolute yaw that makes player input go in optimal direction
		local newAngles = EulerAngles(viewAngles.x, desiredViewYaw, 0)
		engine.SetViewAngles(newAngles)

		-- Keep player's input unchanged (they might be walking backward/diagonal)
		-- The view rotation will make their input go in the right direction!
	else
		-- METHOD 2: Smooth rotation without angle snap (NEEDS LBOX FIX)
		-- Calculate target yaw from direction vector
		local targetYaw = (math.atan(dy, dx) + TWO_PI) % TWO_PI

		-- Get current view yaw
		local _, currentYaw = cmd:GetViewAngles()
		currentYaw = currentYaw * DEG_TO_RAD

		-- Calculate difference
		local yawDiff = (targetYaw - currentYaw + math.pi) % TWO_PI - math.pi

		-- Calculate forward and side move
		local forward = math.cos(yawDiff) * MAX_CMD_SPEED
		local side = math.sin(-yawDiff) * MAX_CMD_SPEED

		cmd:SetForwardMove(forward)
		cmd:SetSideMove(side)
	end
end

-- Ground-physics helpers
local DEFAULT_GROUND_FRICTION = 4
local DEFAULT_SV_ACCELERATE = 10

local function GetGroundFriction()
	local ok, val = pcall(client.GetConVar, "sv_friction")
	if ok and val and val > 0 then
		return val
	end
	return DEFAULT_GROUND_FRICTION
end

local function GetGroundMaxDeltaV(player, tick)
	tick = (tick and tick > 0) and tick or globals.TickInterval()
	local svA = client.GetConVar("sv_accelerate") or 0
	if svA <= 0 then
		svA = DEFAULT_SV_ACCELERATE
	end

	local cap = player and player:GetPropFloat("m_flMaxspeed") or MAX_CMD_SPEED
	if not cap or cap <= 0 then
		cap = MAX_CMD_SPEED
	end

	return svA * cap * tick
end

-- Computes the move vector between two points (from A_standstillDummy.lua)
---@param userCmd UserCmd
---@param a Vector3
---@param b Vector3

local BackstabPos = emptyVec
local globalCounter = 0

-- Function to check if the weapon can attack right now
function IsReadyToAttack(cmd, weapon)
	local TickCount = globals.TickCount()
	local NextAttackTick = Conversion.Time_to_Ticks(weapon:GetPropFloat("m_flNextPrimaryAttack") or 0)

	-- Check if the weapon's next attack time is less than or equal to the current tick
	if NextAttackTick <= TickCount and warp.CanDoubleTap(weapon) then
		LastAttackTick = TickCount -- Update the last attack tick
		CanAttackNow = true -- Set flag for readiness
		return true -- Ready to attack this tick
	else
		CanAttackNow = false
	end
	return false
end

local positions = {}
-- Function to update the cache for the local player and loadout slot
local function UpdateLocalPlayerCache()
	pLocal = entities.GetLocalPlayer()
	if
		not pLocal
		or pLocal:GetPropInt("m_iClass") ~= TF2_Spy
		or not pLocal:IsAlive()
		or pLocal:InCond(TFCond_Cloaked)
		or pLocal:InCond(TFCond_CloakFlicker)
		or pLocal:GetPropInt("m_bFeignDeathReady") == 1
	then
		return false
	end

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
	local maxAttackDistance = 225 -- Attack range plus warp distance
	local bestDistance = maxAttackDistance + 1 -- Initialize to a large number
	local ignoreinvisible = (gui.GetValue("ignore cloaked"))

	for _, player in pairs(allPlayers) do
		if
			player:IsAlive()
			and not player:IsDormant()
			and player:GetTeamNumber() ~= pLocal:GetTeamNumber()
			and (ignoreinvisible == 1 and not player:InCond(4))
		then
			local playerPos = player:GetAbsOrigin()
			local distance = (pLocalPos - playerPos):Length()
			local viewAngles = player:GetPropVector("tfnonlocaldata", "m_angEyeAngles[0]") -- Fetching eye angles directly

			-- Nil check for viewAngles
			if not viewAngles then
				goto continue -- Skip this player if viewAngles is nil
			end

			local viewYaw = EulerAngles(viewAngles:Unpack()).yaw or 0

			-- Check if the player is within the attack range
			if distance < maxAttackDistance and distance < bestDistance then
				bestDistance = distance
				local viewoffset = player:GetPropVector("localdata", "m_vecViewOffset[0]")
				-- Nil check for viewoffset
				if not viewoffset then
					goto continue
				end

				-- Get hitbox directly from entity - handles ducking, etc. automatically
				local mins, maxs = player:GetMins(), player:GetMaxs()
				local hitboxRadius = maxs.x -- Horizontal radius (x and y are same)
				local hitboxHeight = maxs.z -- Vertical height

				bestTargetDetails = {
					entity = player,
					Pos = playerPos,
					NextPos = playerPos + player:EstimateAbsVelocity() * globals.TickInterval(),
					viewpos = playerPos + viewoffset,
					viewYaw = viewYaw, -- Include yaw for backstab calculations
					Back = -EulerAngles(viewAngles:Unpack()):Forward(), -- Ensure Back is accurate
					hitboxRadius = hitboxRadius, -- Real-time hitbox radius from game
					hitboxHeight = hitboxHeight, -- Real-time hitbox height from game
					mins = mins, -- Store full mins for reference
					maxs = maxs, -- Store full maxs for reference
				}
			end

			::continue::
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
local SwingHull = {
	Min = Vector3(-SwingHalfhullSize, -SwingHalfhullSize, -SwingHalfhullSize),
	Max = Vector3(SwingHalfhullSize, SwingHalfhullSize, SwingHalfhullSize),
}

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
	-- Safety check: ensure TargetPlayer exists
	if not TargetPlayer or not TargetPlayer.viewpos or not TargetPlayer.Back or not TargetPlayer.Pos then
		return false
	end

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
local SIMULATION_TICKS = 23 -- Number of ticks for simulation

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

	if onGround then
		vel.z = 0
	end
	return groundTrace.endpos, onGround
end

-- Cache structure
local simulationCache = {
	tickInterval = globals.TickInterval(),
	gravity = SV_GRAVITY, -- Use cached ConVar
	stepSize = pLocal and pLocal:GetPropFloat("localdata", "m_flStepSize") or 0,
	flags = pLocal and pLocal:GetPropInt("m_fFlags") or 0,
}

-- Function to update cache (call this when game environment changes)
local function UpdateSimulationCache()
	simulationCache.tickInterval = globals.TickInterval()
	simulationCache.gravity = SV_GRAVITY -- Use cached ConVar
	simulationCache.stepSize = pLocal and pLocal:GetPropFloat("localdata", "m_flStepSize") or 0
	simulationCache.flags = pLocal and pLocal:GetPropInt("m_fFlags") or 0
end

local ignoreEntities = { "CTFAmmoPack", "CTFDroppedWeapon" }
local function shouldHitEntityFun(entity, player)
	for _, ignoreEntity in ipairs(ignoreEntities) do --ignore custom
		if entity:GetClass() == ignoreEntity then
			return false
		end
	end

	if entity:GetName() == player:GetName() then
		return false
	end --ignore self
	if entity:GetTeamNumber() == player:GetTeamNumber() then
		return false
	end --ignore teammates
	return true
end

-- Simulate warp in a specific direction
-- Assumes we're inputting optimal movement in that direction from tick 0
-- NOT using current velocity - assumes we START accelerating optimally
local function SimulateDash(targetDirection, ticks)
	local tick_interval = globals.TickInterval()
	local playerClass = pLocal:GetPropInt("m_iClass")
	local maxSpeed = CLASS_MAX_SPEEDS[playerClass] or 320

	-- Normalize the direction we want to warp toward
	local wishdir = Normalize(targetDirection)

	-- Start with current velocity, will accelerate toward maxSpeed in wishdir
	local currentVel = pLocal:EstimateAbsVelocity()
	local vel = Vector3(currentVel.x, currentVel.y, currentVel.z)

	-- Set gravity and step size from cached values
	local gravity = simulationCache.gravity * tick_interval
	local stepSize = simulationCache.stepSize
	local vUp = Vector3(0, 0, 1)
	local vStep = Vector3(0, 0, stepSize or 18)

	-- Helper to determine if an entity should be hit
	local shouldHitEntity = function(entity)
		return shouldHitEntityFun(entity, pLocal)
	end

	-- Initialize simulation state
	local lastP = pLocalPos
	local lastV = vel
	local flags = simulationCache.flags
	local lastG = (flags & 1 == 1) -- Check if initially on the ground

	-- Track the closest backstab opportunity
	local closestBackstabPos = nil
	local minWarpTicks = ticks + 1 -- Initialize to a high value outside of tick range

	-- LOCAL arrays for THIS simulation only (not global!)
	local simPositions = {}
	local simEndwarps = {}

	for i = 1, ticks do
		-- Apply friction first (ground movement)
		local vel = ApplyFriction(lastV, lastG)

		-- Accelerate toward maxSpeed in wishdir (assume optimal input)
		if lastG then
			local currentspeed = vel:Dot(wishdir)
			local addspeed = maxSpeed - currentspeed
			if addspeed > 0 then
				local accelspeed = math.min(TF2_ACCEL * maxSpeed * tick_interval, addspeed)
				vel = vel + wishdir * accelspeed
			end

			-- Cap to max speed (horizontal)
			local horizSpeed = math.sqrt(vel.x * vel.x + vel.y * vel.y)
			if horizSpeed > maxSpeed then
				local scale = maxSpeed / horizSpeed
				vel = Vector3(vel.x * scale, vel.y * scale, vel.z)
			end
		end

		-- Calculate the new position based on the velocity
		local pos = lastP + vel * tick_interval
		local onGround = lastG

		-- Collision and movement logic
		if Menu.Advanced.ColisionCheck then
			local wallTrace = engine.TraceHull(
				lastP + vStep,
				pos + vStep,
				vHitbox.Min,
				vHitbox.Max,
				MASK_PLAYERSOLID,
				shouldHitEntity
			)
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
			local groundTrace = engine.TraceHull(
				pos + vStep,
				pos - downStep,
				vHitbox.Min,
				vHitbox.Max,
				MASK_PLAYERSOLID,
				shouldHitEntity
			)
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

		-- Store each tick position and backstab status in LOCAL arrays
		simPositions[i] = pos
		simEndwarps[i] = { pos, isBackstab, i } -- Include tick number for scoring

		-- Track EARLIEST backstab tick (for fallback)
		if isBackstab and i < minWarpTicks then
			minWarpTicks = i
			closestBackstabPos = pos
		end

		-- Update simulation state
		lastP, lastV, lastG = pos, vel, onGround
	end

	-- Return: final pos, min ticks (for info), LOCAL path arrays (includes ALL backstabs)
	-- Don't return single backstab pos - let caller score all of them
	return lastP, minWarpTicks, simPositions, simEndwarps
end

-- Corners must account for BOTH player and enemy hitbox radius
-- Player hitbox (24) + Enemy hitbox (24) = 48 units needed for clearance
local PLAYER_HITBOX_RADIUS = 24
local ENEMY_HITBOX_RADIUS = 24
local CORNER_DISTANCE = PLAYER_HITBOX_RADIUS + ENEMY_HITBOX_RADIUS -- 48 units total
local corners = {
	Vector3(-CORNER_DISTANCE, CORNER_DISTANCE, 0.0), -- top left corner
	Vector3(CORNER_DISTANCE, CORNER_DISTANCE, 0.0), -- top right corner
	Vector3(-CORNER_DISTANCE, -CORNER_DISTANCE, 0.0), -- bottom left corner
	Vector3(CORNER_DISTANCE, -CORNER_DISTANCE, 0.0), -- bottom right corner
}

local center = Vector3(0, 0, 0)

local direction_to_corners = {
	[-1] = {
		[-1] = { center, corners[1], corners[4] }, -- Top-left
		[0] = { center, corners[2], corners[4] }, -- Left
		[1] = { center, corners[2], corners[3] }, -- Top-left to bottom-right (corrected)
	},
	[0] = {
		[-1] = { center, corners[1], corners[2] }, -- BACK: top corners (y=49)
		[0] = { center }, -- Center
		[1] = { center, corners[3], corners[2] }, -- FRONT: bottom corners (y=-49) - FIXED
	},
	[1] = {
		[-1] = { center, corners[2], corners[3] }, -- Top-right to bottom-left (corrected)
		[0] = { center, corners[3], corners[1] }, -- Right
		[1] = { center, corners[4], corners[1] }, -- Bottom-right
	},
}

local function determine_direction(my_pos, enemy_pos, hitbox_size, vertical_range)
	local dx = enemy_pos.x - my_pos.x
	local dy = enemy_pos.y - my_pos.y
	local dz = enemy_pos.z - my_pos.z
	local buffor = 1

	local out_of_vertical_range = (math.abs(dz) > vertical_range) and 1 or 0

	local direction_x = ((dx > hitbox_size - buffor) and 1 or 0) - ((dx < -hitbox_size + buffor) and 1 or 0)
	local direction_y = ((dy > hitbox_size - buffor) and 1 or 0) - ((dy < -hitbox_size + buffor) and 1 or 0)

	local final_dir = { (direction_x * (1 - out_of_vertical_range)), (direction_y * (1 - out_of_vertical_range)) }
	return final_dir
end

local function get_best_corners_or_origin(my_pos, enemy_pos, hitbox_size, vertical_range)
	local direction = determine_direction(my_pos, enemy_pos, hitbox_size, vertical_range)
	local bestcorners = direction_to_corners[direction[1]] and direction_to_corners[direction[1]][direction[2]]

	if not bestcorners then
		return { center }
	end

	return bestcorners
end

local BACKSTAB_MAX_YAW_DIFF = 180 -- Maximum allowable yaw difference for backstab

-- PASS 1: Project where we'd end up if we coast without input
-- Returns the optimal wishdir accounting for coasting AND recalculated best position
local function CalculateOptimalWishdir(
	startPos,
	startVel,
	offsetFromEnemy,
	enemyPos,
	ticks,
	maxSpeed,
	hitbox_size,
	vertical_range
)
	local tick_interval = globals.TickInterval()
	local pos = Vector3(startPos.x, startPos.y, startPos.z)
	local vel = Vector3(startVel.x, startVel.y, startVel.z)

	-- Simulate coasting WITHOUT input (viewangle frozen, no wishdir applied)
	for i = 1, ticks do
		-- Just move with current velocity (no acceleration)
		pos = pos + vel * tick_interval

		-- Apply friction
		local speed = vel:Length()
		if speed > 0 then
			local drop = speed * TF2_GROUND_FRICTION * tick_interval
			local newspeed = math.max(speed - drop, 0)
			if speed > 0 then
				vel = vel * (newspeed / speed)
			end
		end
	end

	-- CRITICAL: Recalculate best position FROM coasted position
	-- If we coasted past target, we need a NEW best position, not the old one
	local coastedPositions = get_best_corners_or_origin(pos, enemyPos, hitbox_size, vertical_range) or {}

	-- Find the corner/position that matches our intended offset direction
	-- (keep same strategy: optimal side or center)
	local newBestOffset = offsetFromEnemy -- Default to original offset

	-- If we have multiple options, pick the one closest to our original intent
	if #coastedPositions > 1 then
		local bestMatch = nil
		local bestDot = -math.huge
		local originalDir = Normalize(offsetFromEnemy)

		for _, coastedOffset in ipairs(coastedPositions) do
			local coastedDir = Normalize(coastedOffset)
			local dot = originalDir:Dot(coastedDir)
			if dot > bestDot then
				bestDot = dot
				bestMatch = coastedOffset
			end
		end

		if bestMatch then
			newBestOffset = bestMatch
		end
	end

	-- Calculate destination from coasted position using recalculated offset
	local destination = enemyPos + newBestOffset
	local directionToTarget = destination - pos
	local optimalWishdir = Normalize(directionToTarget)

	-- This wishdir is optimal - Pass 2 (SimulateDash) will handle full physics
	return optimalWishdir
end

local function CalculateTrickstab(cmd)
	if not TargetPlayer or not TargetPlayer.Pos then
		return emptyVec, nil, nil
	end

	local my_pos = pLocalPos
	local enemy_pos = TargetPlayer.Pos

	-- Get actual collision hulls from game (used in simulation)
	local myMins, myMaxs = pLocal:GetMins(), pLocal:GetMaxs()
	local myRadius = myMaxs.x -- Player's actual collision radius
	local enemyMins = TargetPlayer.mins or Vector3(-24, -24, 0)
	local enemyMaxs = TargetPlayer.maxs or Vector3(24, 24, 82)
	local enemyRadius = TargetPlayer.hitboxRadius or 24

	-- Corner positions: player radius + enemy radius + 1 unit buffer
	-- Buffer ONLY for target point selection, NOT for simulation collision
	local cornerDistance = myRadius + enemyRadius + 1
	local dynamicCorners = {
		Vector3(-cornerDistance, cornerDistance, 0.0), -- top left
		Vector3(cornerDistance, cornerDistance, 0.0), -- top right
		Vector3(-cornerDistance, -cornerDistance, 0.0), -- bottom left
		Vector3(cornerDistance, -cornerDistance, 0.0), -- bottom right
	}

	-- Simulation uses REAL hitboxes (no buffer)
	local hitbox_size = enemyRadius -- For direction detection
	local vertical_range = TargetPlayer.hitboxHeight or 82 -- For vertical checks
	local playerClass = pLocal:GetPropInt("m_iClass")
	local maxSpeed = CLASS_MAX_SPEEDS[playerClass] or 320
	local currentVel = pLocal:EstimateAbsVelocity()
	local warpTicks = warp.GetChargedTicks() or 24

	-- Use dynamic corners for position calculation
	local all_positions = {}
	for _, corner in ipairs(dynamicCorners) do
		all_positions[#all_positions + 1] = corner
	end
	all_positions[#all_positions + 1] = center -- Add center position

	-- Calculate yaw differences to determine best direction (left or right)
	-- pos.y > 0 = positive Y axis, pos.y < 0 = negative Y axis
	local left_yaw_diff, right_yaw_diff, center_yaw_diff = math.huge, math.huge, math.huge
	for _, pos in ipairs(all_positions) do
		local test_yaw = PositionYaw(enemy_pos, enemy_pos + pos)
		local enemy_yaw = TargetPlayer.viewYaw
		local yaw_diff = math.abs(NormalizeYaw(test_yaw - enemy_yaw))

		-- Y axis: positive = right in world space, negative = left
		if pos.y > 0 then
			right_yaw_diff = math.min(right_yaw_diff, yaw_diff)
		elseif pos.y < 0 then
			left_yaw_diff = math.min(left_yaw_diff, yaw_diff)
		elseif pos == center then
			center_yaw_diff = yaw_diff
		end
	end

	-- Determine which side to prioritize based on yaw difference
	local best_side = (left_yaw_diff < right_yaw_diff) and "left" or "right"
	local best_positions = {}

	-- Find optimal side position - pick the one with SMALLEST yaw delta
	local optimalSidePos = nil
	local optimalSideIndex = 0
	local bestYawDelta = math.huge

	for i, pos in ipairs(all_positions) do
		if pos ~= center then
			-- Check if this corner is on the best side
			if (best_side == "left" and pos.y < 0) or (best_side == "right" and pos.y > 0) then
				-- Calculate yaw delta for this specific corner
				local test_yaw = PositionYaw(enemy_pos, enemy_pos + pos)
				local enemy_yaw = TargetPlayer.viewYaw
				local yaw_diff = math.abs(NormalizeYaw(test_yaw - enemy_yaw))

				-- Pick corner with smallest yaw delta (closest to enemy back)
				if yaw_diff < bestYawDelta then
					bestYawDelta = yaw_diff
					optimalSidePos = pos
					optimalSideIndex = i
				end
			end
		end
	end

	-- Classify each corner by direction for debug
	local cornerDirections = {}
	for i, pos in ipairs(all_positions) do
		if pos == center then
			cornerDirections[i] = "CENTER"
		elseif pos.y > 0 then
			cornerDirections[i] = "RIGHT"
		elseif pos.y < 0 then
			cornerDirections[i] = "LEFT"
		else
			cornerDirections[i] = "UNKNOWN"
		end
	end

	-- Calculate player's direction indices relative to enemy (-1, 0, 1)
	local dx = enemy_pos.x - my_pos.x
	local dy = enemy_pos.y - my_pos.y
	local dz = enemy_pos.z - my_pos.z
	local buffor = 5

	local out_of_vertical_range = (math.abs(dz) > vertical_range) and 1 or 0
	local direction_x = ((dx > hitbox_size - buffor) and 1 or 0) - ((dx < -hitbox_size + buffor) and 1 or 0)
	local direction_y = ((dy > hitbox_size - buffor) and 1 or 0) - ((dy < -hitbox_size + buffor) and 1 or 0)

	-- Store for debug visualization
	debugCornerData = {
		corners = dynamicCorners,
		allPositions = all_positions,
		cornerDirections = cornerDirections,
		optimalIndex = optimalSideIndex,
		bestSide = best_side,
		leftYaw = left_yaw_diff,
		rightYaw = right_yaw_diff,
		playerDirX = direction_x, -- -1, 0, or 1
		playerDirY = direction_y, -- -1, 0, or 1
		outOfVertRange = out_of_vertical_range,
	}

	-- Fallback if no optimal side found
	if not optimalSidePos then
		for _, pos in ipairs(all_positions) do
			if pos ~= center then
				optimalSidePos = pos
				break
			end
		end
	end

	-- ALWAYS add BOTH positions in specific order
	-- Position 1: Optimal side (for green line)
	if optimalSidePos then
		table.insert(best_positions, optimalSidePos)
	else
		print("ERROR: No optimal side position found!")
	end

	-- Position 2: Center/back (for cyan line)
	table.insert(best_positions, center)

	-- Track the optimal backstab position based on scoring
	local optimalBackstabPos = nil
	local bestScore = -1
	local minWarpTicks = math.huge
	local allPaths = {} -- Store ALL simulation paths for visualization
	local allEndwarps = {} -- Store ALL endwarp data
	local bestDirection = nil
	local totalBackstabPoints = 0 -- Count total backstab positions found

	-- Simulate BOTH paths with 2-pass approach
	local simulationTargets = {}

	-- Path 1: Optimal side
	if optimalSidePos then
		table.insert(simulationTargets, { name = "optimal_side", offset = optimalSidePos })
	else
		print("ERROR: No optimal side position found!")
	end

	-- Path 2: Center/back
	table.insert(simulationTargets, { name = "center", offset = center })

	for _, simTarget in ipairs(simulationTargets) do
		-- PASS 1: Calculate optimal wishdir based on coasting projection
		-- This recalculates best position from coasted endpoint to avoid backwards acceleration
		local optimalWishdir = CalculateOptimalWishdir(
			my_pos,
			currentVel,
			simTarget.offset,
			enemy_pos,
			warpTicks,
			maxSpeed,
			hitbox_size,
			vertical_range
		)

		-- Convert wishdir to direction vector for SimulateDash (it will normalize internally)
		local targetDirection = optimalWishdir * 100 -- Scale up for direction vector

		-- PASS 2: Full simulation with calculated wishdir locked for entire warp
		local final_pos, minTicks, simPath, simEndwarps = SimulateDash(targetDirection, warpTicks)

		-- Store this simulation path for visualization (store all paths)
		table.insert(allPaths, simPath)
		table.insert(allEndwarps, simEndwarps)

		-- Score EVERY backstab position in this simulation path
		if simEndwarps then
			for tick, warpData in ipairs(simEndwarps) do
				-- Safely unpack warp data
				local backstab_pos = warpData[1]
				local isBackstab = warpData[2]
				local tickNum = warpData[3] or tick -- Fallback to loop index

				if isBackstab and backstab_pos then
					totalBackstabPoints = totalBackstabPoints + 1 -- Count all backstab points

					-- Calculate angle from stab position to enemy
					local spyYaw = PositionYaw(enemy_pos, backstab_pos)
					local enemyYaw = TargetPlayer.viewYaw
					local isWithinBackstabYaw = CheckYawDelta(spyYaw, enemyYaw)

					if isWithinBackstabYaw then
						-- Angle from enemy's BACK (0 = directly behind, 90 = edge)
						local yawDiff = math.abs(NormalizeYaw(spyYaw - enemyYaw))
						local yawComponent = math.max(0, 1 - yawDiff / 90)

						-- Distance from STAB POSITION to ENEMY
						local distance = (backstab_pos - enemy_pos):Length()
						local distanceComponent = math.max(0, 1 - distance / 120)

						-- Score: 70% angle, 30% distance
						local score = 0.7 * yawComponent + 0.3 * distanceComponent

						-- Pick highest score (or same score with fewer ticks)
						if score > bestScore or (score == bestScore and tickNum < minWarpTicks) then
							bestScore = score
							optimalBackstabPos = backstab_pos
							minWarpTicks = tickNum
							bestDirection = targetDirection
							-- print(string.format("[SCORE] tick=%d, angle=%.1f°, dist=%.0f, score=%.3f", tickNum, yawDiff, distance, score))
						end
					end
				end
			end
		end
	end

	-- Set global visualization data to show ALL paths (not just best one)
	positions = allPaths
	endwarps = allEndwarps

	-- ALWAYS return direction to optimal side, even without backstab position
	-- If no bestDirection from scoring, calculate direction to optimal side
	if not bestDirection and optimalSidePos then
		bestDirection = enemy_pos + optimalSidePos - my_pos
	end

	-- Debug: Path count validation
	-- if #allPaths ~= 2 then
	-- 	print("WARNING: Expected 2 paths, got " .. #allPaths)
	-- end

	return optimalBackstabPos or emptyVec, bestScore, minWarpTicks, bestDirection, totalBackstabPoints
end

-- Recharge state tracking
local warpExecutedTick = 0
local warpConfirmed = false -- Kill or hurt confirmed
local lastAttackedTarget = nil

local function damageLogger(event)
	local eventName = event:GetName()

	if eventName == "player_death" then
		pLocal = entities:GetLocalPlayer()
		if not pLocal then
			return
		end

		local attacker = entities.GetByUserID(event:GetInt("attacker"))
		local victim = entities.GetByUserID(event:GetInt("userid"))

		-- We got a kill - allow recharge
		if attacker and attacker:IsValid() and pLocal:GetIndex() == attacker:GetIndex() then
			warpConfirmed = true
			lastAttackedTarget = nil
		end
	elseif eventName == "player_hurt" then
		pLocal = entities:GetLocalPlayer()
		if not pLocal then
			return
		end

		local attacker = entities.GetByUserID(event:GetInt("attacker"))

		-- We hurt someone - allow recharge
		if attacker and attacker:IsValid() and pLocal:GetIndex() == attacker:GetIndex() then
			warpConfirmed = true
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

-- Function to handle controlled warp using pre-calculated optimal direction
-- IMPORTANT: Warp copies our current movement inputs and repeats them for entire warp duration
-- We CANNOT control the player during warp - only set inputs BEFORE triggering warp
-- This simulates "time compression" - same physics applied rapidly
local function PerformControlledWarp(cmd, optimalDirection, warpTicks)
	-- Use the direction that was already calculated and tested in simulation
	-- DO NOT recalculate - that would invalidate the simulation results!

	-- CRITICAL: Set movement input FIRST before configuring warp
	WalkInDirection(cmd, optimalDirection)

	-- Configure warp ticks
	client.RemoveConVarProtection("sv_maxusrcmdprocessticks")
	client.SetConVar("sv_maxusrcmdprocessticks", warpTicks, true)

	-- Execute the warp - inputs from cmd are now locked and will repeat
	-- The input we just set with WalkInDirection will be used
	warp.TriggerWarp()

	-- Reset
	client.SetConVar("sv_maxusrcmdprocessticks", 24, true)
end

-- Modified AutoWarp to use minWarpTicks from CalculateTrickstab
local function AutoWarp(cmd)
	local sideMove = cmd:GetSideMove()
	local forwardMove = cmd:GetForwardMove()
	local playerClass = pLocal:GetPropInt("m_iClass")
	local currentVel = pLocal:EstimateAbsVelocity()

	-- Calculate the optimal backstab position and direction
	local bestDirection
	local totalBackstabPoints
	BackstabPos, bestScore, minWarpTicks, bestDirection, totalBackstabPoints = CalculateTrickstab(cmd)

	-- PRIORITY 0: Movement Assistance - Works ALWAYS (even without backstab position)
	-- Helps get into position by walking to optimal side
	if Menu.Main.MoveAsistance then
		local canCurrentlyBackstab = CheckBackstab(pLocalPos)
		if not canCurrentlyBackstab then
			-- Use bestDirection from simulation if available, otherwise walk toward enemy
			local dir = bestDirection or (TargetPlayer.Pos - pLocalPos)

			-- Check if we have backstab points - if not, disable angle snap (less disruptive)
			local backstabPointCount = totalBackstabPoints or 0
			local hasStabPoints = backstabPointCount > 0
			local forceNoSnap = not hasStabPoints -- Disable snap when just getting into position

			FakelagOn()
			WalkInDirection(cmd, dir, forceNoSnap)
		end
	end

	-- Ensure we have a valid warp target position for AutoWalk and AutoWarp
	if BackstabPos ~= emptyVec and minWarpTicks then
		-- Check if we can CURRENTLY backstab (from our current position)
		local canCurrentlyBackstab = CheckBackstab(pLocalPos)

		-- Check if WARP would result in backstab (at BackstabPos)
		local warpWouldBackstab = CheckBackstab(BackstabPos)

		-- Check if warp is ready
		local warpReady = warp.CanWarp() and warp.GetChargedTicks() >= 23 and not warp.IsWarping()

		-- Direction to walk - MUST use bestDirection from simulation to align!
		-- If no bestDirection yet, fall back to direct path
		local dir = bestDirection or (BackstabPos - pLocalPos)

		-- Count backstab points across ALL simulated paths (combined total)
		local backstabPointCount = totalBackstabPoints or 0
		local hasAnyBackstabPoints = backstabPointCount > 0
		local minPointsThreshold = Menu.Advanced.MinBackstabPoints or 3
		local hasEnoughBackstabPoints = backstabPointCount >= minPointsThreshold

		-- PRIORITY 1: AutoWalk - Walk to optimal side (left/right) when stab points exist
		-- Requires at least 1 backstab point to confirm simulation found valid path
		if Menu.Main.AutoWalk and not canCurrentlyBackstab and hasAnyBackstabPoints then
			FakelagOn()
			WalkInDirection(cmd, dir) -- Walk to optimal side chosen by simulation
			-- Don't return yet - check if we should also warp
		end

		-- PRIORITY 2: Auto Warp - Only warp when ENOUGH points to pick best position
		-- 1. Warp is ready
		-- 2. Warp GUARANTEES backstab
		-- 3. Not already in backstab range
		-- 4. Found ENOUGH backstab points (threshold ensures confidence in best pick)

		if
			Menu.Main.AutoWarp
			and warpWouldBackstab
			and warpReady
			and not canCurrentlyBackstab
			and hasEnoughBackstabPoints
			and bestDirection
		then
			-- Use exact ticks from simulation (already optimal)
			local warpTicks = minWarpTicks

			-- Perform the controlled warp using the EXACT direction from simulation
			-- This direction was tested and led to the best backstab position
			PerformControlledWarp(cmd, bestDirection, warpTicks)
			return
		end

		-- Default: Fake lag management
		if canCurrentlyBackstab then
			FakelagOn() -- Close enough, hold position
		else
			FakelagOff()
		end
	else
		FakelagOff() -- Disable fake lag if no action needed (no valid backstab position)
	end
end

local Latency = 0
local lerp = 0
-- Main function to control the create move process and use AutoWarp and SimulateAttack effectively
local function OnCreateMove(cmd)
	if not Menu.Main.Active then
		-- Clear visuals when script is inactive
		positions = {}
		endwarps = {}
		return
	end

	-- Check activation mode (Always, On Hold, On Release, Toggle, On Click)
	if not ShouldActivateTrickstab() then
		-- Clear visuals when key not held
		positions = {}
		endwarps = {}
		return
	end

	-- Reset tables for storing positions and backstab states
	positions = {} -- Stores all tick positions for visualization
	endwarps = {} -- Stores warp data for each tick, including backstab status

	-- Use NetChannel for latency (not deprecated)
	local netChan = clientstate.GetNetChannel()
	if netChan then
		local latOut = netChan:GetLatency(0) -- FLOW_OUTGOING = 0
		local latIn = netChan:GetLatency(1) -- FLOW_INCOMING = 1
		local latency = latOut + latIn
		lerp = (CL_INTERP + latency) or 0
		Latency = Conversion.Time_to_Ticks(latency + lerp)
	else
		Latency = 0
	end

	-- Track when warp was executed
	if warp.IsWarping() and warpExecutedTick == 0 then
		warpExecutedTick = globals.TickCount()
		warpConfirmed = false
	end

	-- Auto recharge logic: Recharge when kill/hurt confirmed or 7 ticks after warp
	if Menu.Advanced.AutoRecharge and not warp.IsWarping() and warp.GetChargedTicks() < 24 and not warp.CanWarp() then
		local shouldRecharge = false

		-- Check 1: Got kill/hurt confirmation (immediate recharge)
		if warpConfirmed then
			shouldRecharge = true
		end

		-- Check 2: 7 ticks passed since warp (fallback timer)
		if warpExecutedTick > 0 then
			local currentTick = globals.TickCount()
			local ticksSinceWarp = currentTick - warpExecutedTick
			if ticksSinceWarp >= 7 then
				shouldRecharge = true
			end
		end

		-- Trigger recharge and reset state
		if shouldRecharge then
			warp.TriggerCharge()
			warpExecutedTick = 0
			warpConfirmed = false
		end
	end

	if UpdateLocalPlayerCache() == false or not pLocal then
		return
	end

	local pWeapon = pLocal:GetPropEntity("m_hActiveWeapon")
	if not pWeapon then
		return
	end
	if pLocal:InCond(4) then
		return
	end
	if not IsReadyToAttack(cmd, pWeapon) then
		return
	end

	-- Check if keybind should activate trickstab logic
	if not ShouldActivateTrickstab() then
		return
	end

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
		-- DEBUG: Draw corner selection visualization (only if debug enabled)
		if Menu.Visuals.DebugCorners and debugCornerData and debugCornerData.allPositions then
			local enemy_pos = TargetPlayer.Pos
			for i, pos in ipairs(debugCornerData.allPositions) do
				local cornerPos = enemy_pos + pos
				local screenPos = client.WorldToScreen(cornerPos)
				if screenPos then
					local direction = debugCornerData.cornerDirections[i] or "?"

					-- Color by direction
					if i == debugCornerData.optimalIndex then
						draw.Color(0, 255, 0, 255) -- Green for optimal
					elseif direction == "LEFT" then
						draw.Color(100, 150, 255, 200) -- Blue for left
					elseif direction == "RIGHT" then
						draw.Color(255, 150, 100, 200) -- Orange for right
					elseif direction == "CENTER" then
						draw.Color(255, 255, 0, 200) -- Yellow for center
					else
						draw.Color(255, 255, 255, 150) -- White for unknown
					end

					-- Draw corner marker (larger)
					local sx, sy = math.floor(screenPos[1]), math.floor(screenPos[2])
					draw.FilledRect(sx - 5, sy - 5, sx + 5, sy + 5)

					-- Draw corner index and direction with background for visibility
					draw.SetFont(consolas)

					-- Index number in large text
					draw.Color(0, 0, 0, 200) -- Black background
					draw.FilledRect(sx + 8, sy - 15, sx + 35, sy + 5)
					draw.Color(255, 255, 255, 255) -- White text
					draw.Text(sx + 10, sy - 12, "IDX:" .. tostring(i))

					-- Direction label
					draw.Color(0, 0, 0, 200) -- Black background
					draw.FilledRect(sx + 8, sy + 5, sx + 65, sy + 20)

					-- Color text by direction for clarity
					if direction == "LEFT" then
						draw.Color(100, 150, 255, 255)
					elseif direction == "RIGHT" then
						draw.Color(255, 150, 100, 255)
					elseif direction == "CENTER" then
						draw.Color(255, 255, 0, 255)
					else
						draw.Color(255, 255, 255, 255)
					end
					draw.Text(sx + 10, sy + 8, direction)

					-- Show X,Y coordinates for debugging direction mapping
					draw.Color(0, 0, 0, 200) -- Black background
					draw.FilledRect(sx + 8, sy + 22, sx + 90, sy + 37)
					draw.Color(255, 255, 255, 255) -- White text
					draw.Text(sx + 10, sy + 25, string.format("X:%.0f Y:%.0f", pos.x, pos.y))
				end
			end

			-- Draw best side and player direction text
			draw.SetFont(consolas)
			draw.Color(255, 255, 0, 255)
			draw.Text(
				10,
				150,
				string.format(
					"Best Side: %s (L:%.1f R:%.1f)",
					debugCornerData.bestSide,
					debugCornerData.leftYaw,
					debugCornerData.rightYaw
				)
			)

			-- Draw player direction indices relative to enemy
			draw.Color(0, 255, 255, 255) -- Cyan
			draw.Text(
				10,
				165,
				string.format(
					"Player Dir: [%d, %d] (VertRange: %d)",
					debugCornerData.playerDirX or 0,
					debugCornerData.playerDirY or 0,
					debugCornerData.outOfVertRange or 0
				)
			)
		end

		-- Draw red square around final backstab position
		if BackstabPos and BackstabPos ~= emptyVec then
			local screenPos = client.WorldToScreen(BackstabPos)
			if screenPos then
				local sx, sy = math.floor(screenPos[1]), math.floor(screenPos[2])
				draw.Color(255, 0, 0, 255) -- Red
				draw.OutlinedRect(sx - 8, sy - 8, sx + 8, sy + 8)
				draw.OutlinedRect(sx - 9, sy - 9, sx + 9, sy + 9) -- Thicker outline
			end
		end

		-- Visualize ALL Warp Simulation Paths with gradient lines
		-- Each path is drawn SEPARATELY to avoid connecting them
		if Menu.Visuals.VisualizePoints and positions then
			for pathIdx, path in ipairs(positions) do
				-- Skip invalid paths
				if not path or type(path) ~= "table" or #path < 2 then
					goto continue_path
				end

				-- Path colors: Path 1 = Green, Path 2 = Cyan
				local baseR = pathIdx == 1 and 0 or 0
				local baseG = pathIdx == 1 and 255 or 200
				local baseB = pathIdx == 1 and 0 or 255

				-- Draw gradient lines ONLY within THIS path (not connecting to other paths)
				for i = 1, #path - 1 do
					local point = path[i]
					local nextPoint = path[i + 1]

					-- Validate points
					if not point or not nextPoint then
						goto continue_segment
					end

					local screenPos = client.WorldToScreen(Vector3(point.x, point.y, point.z))
					local nextScreenPos = client.WorldToScreen(Vector3(nextPoint.x, nextPoint.y, nextPoint.z))

					if screenPos and nextScreenPos then
						-- Gradient alpha: fade out toward end of path
						local alpha = math.floor(255 * (1 - i / #path))
						draw.Color(baseR, baseG, baseB, math.max(alpha, 100))
						-- Ensure integer coordinates
						draw.Line(
							math.floor(screenPos[1]),
							math.floor(screenPos[2]),
							math.floor(nextScreenPos[1]),
							math.floor(nextScreenPos[2])
						)
					end

					::continue_segment::
				end

				::continue_path::
			end
		end

		-- Visualize backstab points ONLY (red dots where we CAN backstab)
		if Menu.Visuals.VisualizeStabPoint and endwarps then
			for pathIdx, warpDataArray in ipairs(endwarps) do
				if not warpDataArray then
					goto continue_stab
				end

				for tick, warpData in ipairs(warpDataArray) do
					local pos, isBackstab = warpData[1], warpData[2]

					-- ONLY draw if this is a backstab position
					if isBackstab then
						local screenPos = client.WorldToScreen(Vector3(pos.x, pos.y, pos.z))
						if screenPos then
							-- Red square for backstab points
							local sx = math.floor(screenPos[1])
							local sy = math.floor(screenPos[2])
							draw.Color(255, 0, 0, 255)
							draw.FilledRect(sx - 4, sy - 4, sx + 4, sy + 4)
							-- White outline
							draw.Color(255, 255, 255, 255)
							draw.OutlinedRect(sx - 4, sy - 4, sx + 4, sy + 4)
						end
					end
				end

				::continue_stab::
			end
		end

		-- Draw GREEN marker at the OPTIMAL backstab position (best score)
		if Menu.Visuals.VisualizeStabPoint and BackstabPos and BackstabPos ~= emptyVec then
			local screenPos = client.WorldToScreen(Vector3(BackstabPos.x, BackstabPos.y, BackstabPos.z))
			if screenPos then
				-- Green circle for optimal stab point
				draw.Color(0, 255, 0, 255)
				for i = 0, 360, 30 do
					local rad = math.rad(i)
					local nextRad = math.rad(i + 30)
					local x1 = math.floor(screenPos[1] + math.cos(rad) * 8)
					local y1 = math.floor(screenPos[2] + math.sin(rad) * 8)
					local x2 = math.floor(screenPos[1] + math.cos(nextRad) * 8)
					local y2 = math.floor(screenPos[2] + math.sin(nextRad) * 8)
					draw.Line(x1, y1, x2, y2)
				end
				-- Center dot
				local cx = math.floor(screenPos[1])
				local cy = math.floor(screenPos[2])
				draw.FilledRect(cx - 2, cy - 2, cx + 2, cy + 2)
			end
		end

		-- Visualize Attack Circle based on activation state
		if Menu.Visuals.Attack_Circle and pLocal then
			local shouldShowCircle = false

			-- Determine if circle should be shown based on activation mode
			if Menu.Main.ActivationMode == 0 then
				-- Always mode: always show
				shouldShowCircle = true
			elseif Menu.Main.ActivationMode == 1 then
				-- On Hold: show while holding
				shouldShowCircle = Menu.Main.Keybind ~= KEY_NONE and input.IsButtonDown(Menu.Main.Keybind)
			elseif Menu.Main.ActivationMode == 2 then
				-- On Release: show when not holding
				shouldShowCircle = TargetPlayer ~= nil -- Only show when in range
			elseif Menu.Main.ActivationMode == 3 then
				-- Toggle: show when toggled on
				shouldShowCircle = toggleActive
			elseif Menu.Main.ActivationMode == 4 then
				-- On Click: show when clicked
				shouldShowCircle = Menu.Main.Keybind ~= KEY_NONE and input.IsButtonDown(Menu.Main.Keybind)
			end

			if shouldShowCircle then
				local centerPOS = pLocal:GetAbsOrigin() -- Center of the circle at the player's feet
				local viewPos = pLocalViewPos -- View position to shoot traces from
				local radius = 220 -- Radius of the circle
				local segments = 32 -- Number of segments to draw the circle
				local angleStep = (2 * math.pi) / segments

				-- Set the drawing color based on TargetPlayer's presence
				local circleColor = TargetPlayer and { 0, 255, 0, 255 } or { 255, 255, 255, 255 } -- Green if TargetPlayer exists, otherwise white
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
		end

		-- Visualize Forward Line for backstab direction
		if Menu.Visuals.BackLine and TargetPlayer then
			local Back = TargetPlayer.Back
			local hitboxPos = TargetPlayer.viewpos

			-- Calculate end point of the line in the backward direction
			local lineLength = 50 -- Length of the line, adjust as needed
			local endPoint = hitboxPos + (Back * lineLength) -- Move in the backward direction

			-- Convert 3D points to screen space
			local screenStart = client.WorldToScreen(hitboxPos)
			local screenEnd = client.WorldToScreen(endPoint)

			-- Draw the backstab line
			if screenStart and screenEnd then
				draw.Color(0, 255, 255, 255) -- Cyan color for the backstab line
				draw.Line(screenStart[1], screenStart[2], screenEnd[1], screenEnd[2])
			end
		end
	end

	-----------------------------------------------------------------------------------------------------
	--Menu
	-- Only draw when the Lmaobox menu is open
	if not gui.IsMenuOpen() then
		return
	end

	if TimMenu and TimMenu.Begin("Auto Trickstab") then
		local tabs = { "Main", "Advanced", "Visuals" }
		Menu.currentTab = TimMenu.TabControl("tabs", tabs, Menu.currentTab)
		TimMenu.NextLine()

		if Menu.currentTab == 1 then
			TimMenu.Text("Please Use Lbox Auto Backstab")
			TimMenu.NextLine()

			Menu.Main.Active = TimMenu.Checkbox("Active", Menu.Main.Active)
			TimMenu.NextLine()

			TimMenu.Separator("Movement")
			Menu.Main.AutoWalk = TimMenu.Checkbox("Auto Walk", Menu.Main.AutoWalk)
			TimMenu.NextLine()
			Menu.Main.AutoWarp = TimMenu.Checkbox("Auto Warp", Menu.Main.AutoWarp)
			TimMenu.NextLine()

			Menu.Main.AutoBlink = TimMenu.Checkbox("Auto Blink", Menu.Main.AutoBlink)
			TimMenu.NextLine()
			Menu.Main.MoveAsistance = TimMenu.Checkbox("Move Asistance", Menu.Main.MoveAsistance)
			TimMenu.NextLine()

			TimMenu.Separator("Activation Settings")
			local activationModes = { "Always", "On Hold", "On Release", "Toggle", "On Click" }
			-- TimMenu.Dropdown returns 1-based index, convert to 0-based for our logic
			local dropdownValue = TimMenu.Dropdown("Activation Mode", Menu.Main.ActivationMode + 1, activationModes)
			Menu.Main.ActivationMode = dropdownValue - 1 -- Convert back to 0-based
			TimMenu.NextLine()

			-- Only show keybind widget if not in Always mode (mode 0)
			if Menu.Main.ActivationMode ~= 0 then
				Menu.Main.Keybind = TimMenu.Keybind("Activation Key", Menu.Main.Keybind)
				TimMenu.NextLine()
			end
		end

		if Menu.currentTab == 2 then
			Menu.Advanced.ManualDirection = TimMenu.Checkbox("Manual Direction", Menu.Advanced.ManualDirection)
			TimMenu.NextLine()
			Menu.Advanced.AutoRecharge = TimMenu.Checkbox("Auto Recharge", Menu.Advanced.AutoRecharge)
			TimMenu.NextLine()

			Menu.Advanced.MinBackstabPoints =
				TimMenu.Slider("Min Stab Points", Menu.Advanced.MinBackstabPoints, 1, 30, 1)
			TimMenu.NextLine()

			-- Default to true if not set
			if Menu.Advanced.UseAngleSnap == nil then
				Menu.Advanced.UseAngleSnap = true
			end
			Menu.Advanced.UseAngleSnap = TimMenu.Checkbox("Use Angle Snap", Menu.Advanced.UseAngleSnap)
			-- Note: Angle snap fixes warp direction. Disable for smooth rotation (needs lbox to fix warp OnCreateMove callback)
			TimMenu.NextLine()

			Menu.Advanced.ColisionCheck = TimMenu.Checkbox("Colision Check", Menu.Advanced.ColisionCheck)
			TimMenu.NextLine()
			Menu.Advanced.AdvancedPred = TimMenu.Checkbox("Advanced Pred", Menu.Advanced.AdvancedPred)
			TimMenu.NextLine()
		end

		if Menu.currentTab == 3 then
			Menu.Visuals.Active = TimMenu.Checkbox("Active", Menu.Visuals.Active)
			TimMenu.NextLine()

			Menu.Visuals.VisualizePoints = TimMenu.Checkbox("Simulations", Menu.Visuals.VisualizePoints)
			TimMenu.NextLine()
			Menu.Visuals.VisualizeStabPoint = TimMenu.Checkbox("Stab Points", Menu.Visuals.VisualizeStabPoint)
			TimMenu.NextLine()

			Menu.Visuals.Attack_Circle = TimMenu.Checkbox("Attack Circle", Menu.Visuals.Attack_Circle)
			TimMenu.NextLine()
			Menu.Visuals.BackLine = TimMenu.Checkbox("Forward Line", Menu.Visuals.BackLine)
			TimMenu.NextLine()

			-- Debug option for corner visualization
			Menu.Visuals.DebugCorners = TimMenu.Checkbox("Debug Corners", Menu.Visuals.DebugCorners or false)
			TimMenu.NextLine()
		end
	end
end

--[[ Remove the menu when unloaded ]]
--
local function OnUnload() -- Called when the script is unloaded
	UnloadLib() --unloading lualib
	CreateCFG(string.format([[Lua %s]], Lua__fileName), Menu) --saving the config
	engine.PlaySound("hl1/fvox/deactivated.wav")
end

--[[ Unregister previous callbacks ]]
--
callbacks.Unregister("CreateMove", "AtSM_CreateMove") -- Unregister the "CreateMove" callback
callbacks.Unregister("Unload", "AtSM_Unload") -- Unregister the "Unload" callback
callbacks.Unregister("Draw", "AtSM_Draw") -- Unregister the "Draw" callback
callbacks.Unregister("FireGameEvent", "adaamageLogger")

--[[ Register callbacks ]]
--
callbacks.Register("CreateMove", "AtSM_CreateMove", OnCreateMove) -- Register the "CreateMove" callback
callbacks.Register("Unload", "AtSM_Unload", OnUnload) -- Register the "Unload" callback
callbacks.Register("Draw", "AtSM_Draw", doDraw) -- Register the "Draw" callback
callbacks.Register("FireGameEvent", "adaamageLogger", damageLogger)

--[[ Play sound when loaded ]]
--
engine.PlaySound("hl1/fvox/activated.wav")
