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
		ColisionCheck = true, -- Enable collision checking with map geometry (stairs, walls, etc.)
		AdvancedPred = true, -- Enable advanced trace validation for range checks
		ManualDirection = false, -- Manual movement direction control
		AutoRecharge = true, -- Auto recharge warp after kill/hurt
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

-- Ensure warp works without user binding dash key
-- KEY_SCROLLLOCKTOGGLE (106) = impossible to accidentally press
if gui.GetValue("dash move key") == 0 then
	gui.SetValue("dash move key", 106)
end

-- Configure triggerbot for auto backstab: key=NONE, backstab=Rage, FOV=99
gui.SetValue("trigger key", 0)
gui.SetValue("auto backstab", 2)
gui.SetValue("auto backstab fov", 99)

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

-- Returns pitch and yaw angles from source looking at dest
local function PositionAngles(source, dest)
	local delta = dest - source
	local dist = math.sqrt(delta.x * delta.x + delta.y * delta.y)
	local pitch = math.deg(math.atan(-delta.z, dist))
	local yaw = math.deg(math.atan(delta.y, delta.x))
	return { pitch = pitch, yaw = yaw }
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
		-- Calculate the direction from spherePos to closestPoint (safe normalize)
		local dirVec = closestPoint - spherePos
		local dirLen = dirVec:Length()
		local direction = (dirLen > 0) and (dirVec / dirLen) or Vector3(1, 0, 0) -- Default forward if overlapping
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

-- Helper: check if entity is a teammate (blocks melee)
local function IsTeammate(ent)
	if not ent or not ent:IsValid() or not pLocal then
		return false
	end
	if ent:GetClass() ~= "CTFPlayer" then
		return false
	end
	if ent == pLocal then
		return true
	end -- Self is passthrough
	return ent:GetTeamNumber() == pLocal:GetTeamNumber()
end

-- Proper melee can-hit check (same logic as A_Swing_Prediction)
-- 1. AABB closest point to enemy hitbox
-- 2. Distance check - can we even reach?
-- 3. TraceLine to closest point at swing range
-- 4. If miss → TraceHull with melee hull size
local function CanAttackFromPos(testPoint)
	if not TargetPlayer or not TargetPlayer.Pos or not TargetPlayer.entity then
		return false
	end

	local viewPos = testPoint + pLocalViewOffset
	local targetPos = TargetPlayer.Pos

	-- AABB closest point calculation (same as A_Swing_Prediction)
	local hitbox_min = targetPos + vHitbox.Min
	local hitbox_max = targetPos + vHitbox.Max

	local closestPoint = Vector3(
		math.max(hitbox_min.x, math.min(viewPos.x, hitbox_max.x)),
		math.max(hitbox_min.y, math.min(viewPos.y, hitbox_max.y)),
		math.max(hitbox_min.z, math.min(viewPos.z, hitbox_max.z))
	)

	-- Distance from viewPos to closest point on hitbox
	local distanceToHitbox = (viewPos - closestPoint):Length()

	-- Can we even reach? (backstab range check)
	if distanceToHitbox > BACKSTAB_RANGE then
		return false
	end

	-- Calculate swing direction and end point
	local dirToClosest = closestPoint - viewPos
	local dirLen = dirToClosest:Length()
	local direction = (dirLen > 0) and (dirToClosest / dirLen) or Vector3(1, 0, 0)
	local swingEnd = viewPos + direction * BACKSTAB_RANGE

	-- TraceLine first - if it hits anything, that's the final result
	local trace = engine.TraceLine(viewPos, swingEnd, MASK_SHOT_HULL)
	if trace.fraction < 1 then
		-- Hit something - check what it is
		if trace.entity == TargetPlayer.entity then
			return true -- Hit target
		else
			return false -- Hit wall, teammate, or other obstacle
		end
	end

	-- TraceLine hit nothing → try TraceHull (melee has hull)
	trace = engine.TraceHull(viewPos, swingEnd, SwingHull.Min, SwingHull.Max, MASK_SHOT_HULL)
	if trace.fraction < 1 then
		-- Hit something with hull - check what it is
		if trace.entity == TargetPlayer.entity then
			return true -- Hit target
		else
			return false -- Hit wall, teammate, or other obstacle
		end
	end

	return true -- Both traces hit nothing - clear path
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

-- Combined check: can backstab AND can attack (LOS clear)
local function CanBackstabFromPos(testPoint)
	return CheckBackstab(testPoint) and CanAttackFromPos(testPoint)
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

-- Cache structure (TF2 defaults: gravity=800, stepSize=18)
local simulationCache = {
	tickInterval = globals.TickInterval(),
	gravity = SV_GRAVITY or 800, -- Use cached ConVar with fallback
	stepSize = pLocal and pLocal:GetPropFloat("localdata", "m_flStepSize") or 18,
	flags = pLocal and pLocal:GetPropInt("m_fFlags") or 0,
}

-- Function to update cache (call this when game environment changes)
local function UpdateSimulationCache()
	simulationCache.tickInterval = globals.TickInterval()
	simulationCache.gravity = SV_GRAVITY or 800 -- Use cached ConVar with fallback
	local step = pLocal and pLocal:GetPropFloat("localdata", "m_flStepSize")
	simulationCache.stepSize = (step and step > 0) and step or 18 -- TF2 default step size
	simulationCache.flags = pLocal and pLocal:GetPropInt("m_fFlags") or 0
end

local function shouldHitEntityFun(entity, player)
	if not entity then
		return false
	end

	-- Most common: player collision (check first for speed)
	if entity:IsPlayer() then
		-- Ignore self
		if entity:GetIndex() == player:GetIndex() then
			return false
		end
		-- Ignore teammates
		if entity:GetTeamNumber() == player:GetTeamNumber() then
			return false
		end
		-- Hit enemy players
		return true
	end

	-- World geometry (stairs, ramps, brushes)
	local pos = entity:GetAbsOrigin()
	if pos then
		local contents = engine.GetPointContents(pos + Vector3(0, 0, 1))
		if contents ~= 0 then
			return true
		end
	end

	-- Ignore dropped items
	local entClass = entity:GetClass()
	if entClass == "CTFAmmoPack" or entClass == "CTFDroppedWeapon" then
		return false
	end

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
	local gravity = (simulationCache.gravity or 800) * tick_interval
	local stepSize = simulationCache.stepSize
	-- Ensure stepSize is at least 18 (TF2 default) - handles both nil and 0
	if not stepSize or stepSize <= 0 then
		stepSize = 18
	end
	local vUp = Vector3(0, 0, 1)
	local vStep = Vector3(0, 0, stepSize)

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

		-- EARLY TERMINATION: Stop if horizontal speed drops below 5 units/tick (wall sliding too slow)
		local horizSpeed = math.sqrt(vel.x * vel.x + vel.y * vel.y)
		if horizSpeed < 37 then
			break -- No point simulating further, we're stuck
		end

		-- Check for backstab possibility at the current position (with LOS check)
		local isBackstab = CanBackstabFromPos(pos)

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
		[-1] = { center, corners[4], corners[1] }, -- Top-left
		[0] = { center, corners[4], corners[2] }, -- Left
		[1] = { center, corners[3], corners[2] }, -- Top-left to bottom-right (corrected)
	},
	[0] = {
		[-1] = { center, corners[2], corners[1] }, -- BACK: top corners (y=49)
		[0] = { center }, -- Center
		[1] = { center, corners[3], corners[4] }, -- FRONT: bottom corners (y=-49) - FIXED
	},
	[1] = {
		[-1] = { center, corners[2], corners[3] }, -- Top-right to bottom-left (corrected)
		[0] = { center, corners[1], corners[3] }, -- Right
		[1] = { center, corners[1], corners[4] }, -- Bottom-right
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

-- Scale a corner unit vector to actual distance (preserves AABB shape)
-- Don't normalize! AABB corners are at (±dist, ±dist), diagonal stays diagonal
local function scale_corner_to_distance(corner, dist)
	return Vector3(
		corner.x ~= 0 and (corner.x > 0 and dist or -dist) or 0,
		corner.y ~= 0 and (corner.y > 0 and dist or -dist) or 0,
		0
	)
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

	-- STEP 1: Get direction from START position to target
	-- Then extend target 450 units further so we don't stop at corner
	local baseTarget = enemyPos + offsetFromEnemy
	local dirFromStart = baseTarget - startPos
	local dirFromStartNorm = Normalize(dirFromStart)

	-- Extended target: 450 units past the corner in same direction
	local extendedTarget = baseTarget + dirFromStartNorm * 450

	-- STEP 2: Simulate coasting WITHOUT input
	local pos = Vector3(startPos.x, startPos.y, startPos.z)
	local vel = Vector3(startVel.x, startVel.y, startVel.z)

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

	-- STEP 3: Direction from coasted position to EXTENDED target
	-- This ensures we keep full speed toward/past the corner
	local directionToTarget = extendedTarget - pos

	-- Always return normalized direction (full-length wishdir)
	return Normalize(directionToTarget)
end

local function CalculateTrickstab(cmd)
	if not TargetPlayer or not TargetPlayer.Pos then
		return emptyVec, nil, nil
	end

	local my_pos = pLocalPos
	local enemy_pos = TargetPlayer.Pos

	-- Lag compensation: Predict enemy position ahead by half our ping
	-- This accounts for the time it takes for our warp to reach the server
	local netChan = clientstate.GetNetChannel()
	if netChan and TargetPlayer.entity then
		local latOut = netChan:GetLatency(0) -- FLOW_OUTGOING
		local latIn = netChan:GetLatency(1) -- FLOW_INCOMING
		local totalLatency = latOut + latIn
		local halfPing = totalLatency / 2 -- Time for server to receive our position

		-- Convert to ticks for simulation consistency
		local tick_interval = globals.TickInterval()
		local predictionTicks = math.floor(halfPing / tick_interval)
		local predictionTime = predictionTicks * tick_interval

		-- Predict where enemy will be when server processes our warp
		local enemyVelocity = TargetPlayer.entity:EstimateAbsVelocity()
		if enemyVelocity then
			enemy_pos = enemy_pos + enemyVelocity * predictionTime
		end
	end

	-- Get actual collision hulls from game (used in simulation)
	local myMins, myMaxs = pLocal:GetMins(), pLocal:GetMaxs()
	local myRadius = myMaxs.x -- Player's actual collision radius
	local enemyMins = TargetPlayer.mins or Vector3(-24, -24, 0)
	local enemyMaxs = TargetPlayer.maxs or Vector3(24, 24, 82)
	local enemyRadius = TargetPlayer.hitboxRadius or 24

	-- Combined hitbox size (exact collision boundary, NO buffer)
	local combinedHitbox = myRadius + enemyRadius

	-- Corner positions: combined hitbox + 1 unit buffer (for target point selection)
	local cornerDistance = combinedHitbox
	local dynamicCorners = {
		Vector3(-cornerDistance, cornerDistance, 0.0), -- top left
		Vector3(cornerDistance, cornerDistance, 0.0), -- top right
		Vector3(-cornerDistance, -cornerDistance, 0.0), -- bottom left
		Vector3(cornerDistance, -cornerDistance, 0.0), -- bottom right
	}

	-- Direction detection uses EXACT combined hitbox (NO buffer)
	-- Buffer would cause "center" detection when actually on a side
	local hitbox_size = combinedHitbox
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

	-- Simulate ALL 3 paths with 2-pass approach (LEFT, RIGHT, CENTER)
	local simulationTargets = {}

	-- Find other side position (opposite of optimal)
	local otherSidePos = nil
	local otherSide = (best_side == "left") and "right" or "left"
	for i, pos in ipairs(all_positions) do
		if pos ~= center then
			if (otherSide == "left" and pos.y < 0) or (otherSide == "right" and pos.y > 0) then
				otherSidePos = pos
				break
			end
		end
	end

	-- Check our yaw delta from enemy's back (for CENTER eligibility)
	local enemyBackYaw = NormalizeYaw(PositionYaw(enemy_pos, enemy_pos + TargetPlayer.Back))
	local ourYawToEnemy = NormalizeYaw(PositionYaw(enemy_pos, my_pos))
	local ourYawDeltaFromBack = math.abs(NormalizeYaw(ourYawToEnemy - enemyBackYaw))
	local withinBackAngle = ourYawDeltaFromBack <= 90

	-- Track if optimal side hit a wall (to decide if we need other_side)
	local optimalHitWall = false

	-- Path 1: Optimal side (always simulate - best yaw to back)
	if optimalSidePos then
		table.insert(simulationTargets, { name = "optimal_side", offset = optimalSidePos })
	else
		print("ERROR: No optimal side position found!")
	end

	-- Helper to simulate a single path and check wall hit
	local function SimulatePath(simTarget)
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
		local targetDirection = optimalWishdir * 100
		local final_pos, minTicks, simPath, simEndwarps = SimulateDash(targetDirection, warpTicks)

		-- Check if simulation was cut short (hit wall / early termination)
		local expectedTicks = warpTicks
		local actualTicks = simPath and #simPath or 0
		local hitWall = actualTicks < expectedTicks

		return simPath, simEndwarps, optimalWishdir, hitWall
	end

	-- Helper to score endwarps and update best backstab position
	local function ScoreEndwarps(simEndwarps, targetDirection)
		if not simEndwarps then
			return
		end
		for tick, warpData in ipairs(simEndwarps) do
			local backstab_pos = warpData[1]
			local isBackstab = warpData[2]
			local tickNum = warpData[3] or tick

			if isBackstab and backstab_pos then
				totalBackstabPoints = totalBackstabPoints + 1

				local spyYaw = PositionYaw(enemy_pos, backstab_pos)
				local enemyYaw = TargetPlayer.viewYaw
				local isWithinBackstabYaw = CheckYawDelta(spyYaw, enemyYaw)

				if isWithinBackstabYaw then
					local yawDiff = math.abs(NormalizeYaw(spyYaw - enemyYaw))
					local yawComponent = math.max(0, 1 - yawDiff / 90)
					local distance = (backstab_pos - enemy_pos):Length()
					local distanceComponent = math.max(0, 1 - distance / 120)
					local score = 0.7 * yawComponent + 0.3 * distanceComponent

					if score > bestScore or (score == bestScore and tickNum < minWarpTicks) then
						bestScore = score
						optimalBackstabPos = backstab_pos
						minWarpTicks = tickNum
						bestDirection = targetDirection
					end
				end
			end
		end
	end

	-- First simulate optimal side to check if it hits a wall
	local optimalPath, optimalEndwarps, optimalWishdir, optimalHitWall
	if optimalSidePos then
		optimalPath, optimalEndwarps, optimalWishdir, optimalHitWall = SimulatePath(simulationTargets[1])
		table.insert(allPaths, optimalPath)
		table.insert(allEndwarps, optimalEndwarps)
		-- Score the optimal path
		ScoreEndwarps(optimalEndwarps, optimalWishdir * 100)
	end

	-- Path 2: Other side - show if optimal hit a wall OR within 90° of back
	-- This helps assistance pick the path with more open space
	if otherSidePos and (optimalHitWall or withinBackAngle) then
		table.insert(simulationTargets, { name = "other_side", offset = otherSidePos })
	end

	-- Path 3: Center/back - ONLY if within 90° of back
	if withinBackAngle then
		table.insert(simulationTargets, { name = "center", offset = center })
	end

	-- Simulate remaining paths (skip first which we already did)
	for i = 2, #simulationTargets do
		local simTarget = simulationTargets[i]
		local simPath, simEndwarps, wishdir, hitWall = SimulatePath(simTarget)

		-- Store this simulation path for visualization
		table.insert(allPaths, simPath)
		table.insert(allEndwarps, simEndwarps)

		-- Score this path
		ScoreEndwarps(simEndwarps, wishdir * 100)
	end

	-- Set global visualization data to show ALL paths (not just best one)
	positions = allPaths
	endwarps = allEndwarps

	-- Only set fallback direction if we found at least some backstab points
	-- If no backstab points at all, leave bestDirection nil so MoveAssistance uses simple approach
	if not bestDirection and optimalSidePos and totalBackstabPoints > 0 then
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

	-- Track warp time for auto recharge cooldown
	LastWarpTime = globals.RealTime()

	-- Reset
	client.SetConVar("sv_maxusrcmdprocessticks", 24, true)
end

-- Auto recharge state
local LastWarpTime = 0

-- On kill recharge - instant recharge on successful kill
local function OnKillRecharge(event)
	if not Menu.Advanced.AutoRecharge then
		return
	end
	if event:GetName() ~= "player_death" then
		return
	end

	local localPlayer = entities.GetLocalPlayer()
	if not localPlayer then
		return
	end

	local attackerIdx = event:GetInt("attacker")
	local victimIdx = event:GetInt("userid")

	-- Check if we are the attacker
	local attackerEntity = entities.GetByUserID(attackerIdx)
	if attackerEntity and attackerEntity:GetIndex() == localPlayer:GetIndex() then
		-- We got a kill - instant recharge
		warp.TriggerCharge()
		LastWarpTime = 0
	end
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

	-- PRIORITY 0: Movement Assistance - Helps reach enemy's back (footwork only)
	-- Works standalone, but AutoWalk takes priority when stab points found
	-- Picks LEFT or RIGHT side with smallest yaw delta to enemy's back
	-- User can override: sidemove -450 = force RIGHT, +450 = force LEFT
	local backstabPointCount = totalBackstabPoints or 0
	local hasStabPoints = backstabPointCount > 0

	-- AutoWalk has priority when enabled AND stab points found
	local autoWalkTakesPriority = Menu.Main.AutoWalk and hasStabPoints

	if Menu.Main.MoveAsistance and TargetPlayer and TargetPlayer.Pos and TargetPlayer.Back then
		local canCurrentlyBackstab = CanBackstabFromPos(pLocalPos)

		-- MoveAssistance active when not backstabbing AND AutoWalk not taking priority
		if not canCurrentlyBackstab and not autoWalkTakesPriority then
			local my_pos = pLocalPos
			local enemy_pos = TargetPlayer.Pos

			-- VISIBILITY CHECK: Don't assist if wall between us and enemy
			local losTrace = engine.TraceLine(pLocalViewPos, TargetPlayer.viewpos, MASK_SHOT)
			if losTrace.fraction < 0.99 and losTrace.entity ~= TargetPlayer.entity then
				-- Wall blocking LOS - don't waste time assisting
				goto skip_assistance
			end
			local enemyBackYaw = NormalizeYaw(PositionYaw(enemy_pos, enemy_pos + TargetPlayer.Back))

			-- Get hitbox sizes
			local myMins, myMaxs = pLocal:GetMins(), pLocal:GetMaxs()
			local myRadius = myMaxs.x
			local enemyRadius = TargetPlayer.hitboxRadius or 24
			local combinedHitbox = myRadius + enemyRadius

			-- Get velocity and speed for 2-pass wishdir calculation
			local vel = pLocal:EstimateAbsVelocity()
			local maxSpeed = CLASS_MAX_SPEEDS[playerClass] or 320

			-- Use the proper helper function for direction detection (DRY)
			local cornerOptions = get_best_corners_or_origin(my_pos, enemy_pos, combinedHitbox, 82)

			-- Target points use combinedHitbox + 1 unit buffer (for collision safety)
			local cornerDist = combinedHitbox + 1

			-- Get left/right corners and scale to distance (use helper for DRY)
			local leftCorner = cornerOptions[2] or Vector3(-1, 0, 0)
			local rightCorner = cornerOptions[3] or Vector3(1, 0, 0)
			local leftOffset = scale_corner_to_distance(leftCorner, cornerDist)
			local rightOffset = scale_corner_to_distance(rightCorner, cornerDist)

			-- DEPTH 2 scoring: simulate reaching first point, then find next optimal
			-- This prevents getting stuck at left/right - continues circling to back

			-- Helper: simulate walking in wishdir for N ticks, return end position
			-- Also tracks wall collisions - returns ticksBeforeWall (more = better, open space)
			local function SimulateWalk(startPos, startVel, wishdir, ticks)
				local pos = Vector3(startPos.x, startPos.y, startPos.z)
				local simVel = Vector3(startVel.x, startVel.y, startVel.z)
				local tick_interval = globals.TickInterval()
				local ticksBeforeWall = ticks -- Assume no wall hit

				-- Use actual current speed if higher than class max (speed buffs)
				local actualSpeed = math.sqrt(startVel.x * startVel.x + startVel.y * startVel.y)
				local effectiveMaxSpeed = math.max(maxSpeed, actualSpeed)

				-- Get player hull for traces
				local mins = myMins or Vector3(-24, -24, 0)
				local maxs = myMaxs or Vector3(24, 24, 82)

				for i = 1, ticks do
					-- Accelerate toward wishdir
					local currentSpeed = simVel:Dot(wishdir)
					local addSpeed = effectiveMaxSpeed - currentSpeed
					if addSpeed > 0 then
						local accelSpeed = math.min(TF2_ACCEL * effectiveMaxSpeed * tick_interval, addSpeed)
						simVel = simVel + wishdir * accelSpeed
					end
					-- Cap speed (only to effective max, preserves buffs)
					local horizSpeed = math.sqrt(simVel.x * simVel.x + simVel.y * simVel.y)
					if horizSpeed > effectiveMaxSpeed then
						local scale = effectiveMaxSpeed / horizSpeed
						simVel = Vector3(simVel.x * scale, simVel.y * scale, simVel.z)
					end
					-- Friction
					simVel = ApplyFriction(simVel, true)

					-- Calculate next position
					local nextPos = pos + simVel * tick_interval

					-- Wall collision check (forward trace)
					local wallTrace = engine.TraceHull(pos, nextPos, mins, maxs, MASK_PLAYERSOLID_BRUSHONLY)
					if wallTrace.fraction < 1.0 then
						-- Hit a wall - record when and handle sliding
						if ticksBeforeWall == ticks then
							ticksBeforeWall = i -- First wall hit
						end
						-- Slide along wall (remove velocity into wall)
						local normal = wallTrace.plane
						if normal then
							local dot = simVel:Dot(normal)
							if dot < 0 then
								simVel = simVel - normal * dot
							end
						end
						pos = wallTrace.endpos

						-- EARLY TERMINATION: Stop if sliding speed drops below 5 units/tick
						local slideSpeed = math.sqrt(simVel.x * simVel.x + simVel.y * simVel.y)
						if slideSpeed < 37 then
							ticksBeforeWall = i -- Record where we got stuck
							break -- No point simulating further
						end
					else
						pos = nextPos
					end
				end
				return pos, simVel, ticksBeforeWall
			end

			-- CalculateOptimalWishdir handles the +450 extension internally
			-- Pass raw offsets - extension is done FROM our position TO target

			local backDir = Normalize(TargetPlayer.Back)
			local backOffset = backDir * (combinedHitbox + 1)

			-- Calculate LEFT path with wall collision tracking
			local leftWishdir =
				CalculateOptimalWishdir(my_pos, vel, leftOffset, enemy_pos, 24, maxSpeed, combinedHitbox, 82)
			local leftPos1, leftVel1, leftWall1 = SimulateWalk(my_pos, vel, leftWishdir, 12)
			local leftWishdir2 =
				CalculateOptimalWishdir(leftPos1, leftVel1, backOffset, enemy_pos, 12, maxSpeed, combinedHitbox, 82)
			local leftPos2, _, leftWall2 = SimulateWalk(leftPos1, leftVel1, leftWishdir2, 12)
			local leftYaw = NormalizeYaw(PositionYaw(enemy_pos, leftPos2))
			local leftYawDiff = math.abs(NormalizeYaw(leftYaw - enemyBackYaw))
			local leftOpenSpace = leftWall1 + leftWall2 -- Total ticks before wall (higher = more open)

			-- Calculate RIGHT path with wall collision tracking
			local rightWishdir =
				CalculateOptimalWishdir(my_pos, vel, rightOffset, enemy_pos, 24, maxSpeed, combinedHitbox, 82)
			local rightPos1, rightVel1, rightWall1 = SimulateWalk(my_pos, vel, rightWishdir, 12)
			local rightWishdir2 =
				CalculateOptimalWishdir(rightPos1, rightVel1, backOffset, enemy_pos, 12, maxSpeed, combinedHitbox, 82)
			local rightPos2, _, rightWall2 = SimulateWalk(rightPos1, rightVel1, rightWishdir2, 12)
			local rightYaw = NormalizeYaw(PositionYaw(enemy_pos, rightPos2))
			local rightYawDiff = math.abs(NormalizeYaw(rightYaw - enemyBackYaw))
			local rightOpenSpace = rightWall1 + rightWall2

			-- Score function
			local function ScorePath(yawDiff, openSpace)
				-- Lower score = better. Penalize wall hits heavily
				return yawDiff + (24 - openSpace) * 10
			end

			local leftScore = ScorePath(leftYawDiff, leftOpenSpace)
			local rightScore = ScorePath(rightYawDiff, rightOpenSpace)

			-- OPTIMIZATION: Only simulate CENTER if:
			-- 1. LEFT or RIGHT hit a wall, AND
			-- 2. We're within 90° of enemy's back (no point warping to back if we're in front)
			local centerWishdir, centerScore
			local eitherHitWall = leftOpenSpace < 24 or rightOpenSpace < 24

			-- Check our yaw delta from enemy's back
			local ourYawToEnemy = NormalizeYaw(PositionYaw(enemy_pos, my_pos))
			local ourYawDeltaFromBack = math.abs(NormalizeYaw(ourYawToEnemy - enemyBackYaw))
			local withinBackAngle = ourYawDeltaFromBack <= 90

			if eitherHitWall and withinBackAngle then
				local centerOffset = backDir * (combinedHitbox + 1)
				centerWishdir =
					CalculateOptimalWishdir(my_pos, vel, centerOffset, enemy_pos, 24, maxSpeed, combinedHitbox, 82)
				local centerPos1, centerVel1, centerWall1 = SimulateWalk(my_pos, vel, centerWishdir, 12)
				local centerWishdir2 = CalculateOptimalWishdir(
					centerPos1,
					centerVel1,
					backOffset,
					enemy_pos,
					12,
					maxSpeed,
					combinedHitbox,
					82
				)
				local centerPos2, _, centerWall2 = SimulateWalk(centerPos1, centerVel1, centerWishdir2, 12)
				local centerYaw = NormalizeYaw(PositionYaw(enemy_pos, centerPos2))
				local centerYawDiff = math.abs(NormalizeYaw(centerYaw - enemyBackYaw))
				local centerOpenSpace = centerWall1 + centerWall2
				centerScore = ScorePath(centerYawDiff, centerOpenSpace)
			else
				-- No wall hit - center not needed, give it worst score
				centerScore = math.huge
			end

			-- Pick direction to CIRCLE toward
			local wishdir
			local userSideMove = cmd:GetSideMove()

			-- Manual override: TF2 sidemove: positive = right (D key), negative = left (A key)
			if Menu.Advanced.ManualDirection then
				if userSideMove >= 400 then
					wishdir = rightWishdir
				elseif userSideMove <= -400 then
					wishdir = leftWishdir
				else
					-- Auto pick best score
					if leftScore <= rightScore and leftScore <= centerScore then
						wishdir = leftWishdir
					elseif rightScore <= centerScore then
						wishdir = rightWishdir
					else
						wishdir = centerWishdir
					end
				end
			else
				-- Auto mode: pick best score (open space + yaw)
				if leftScore <= rightScore and leftScore <= centerScore then
					wishdir = leftWishdir
				elseif rightScore <= centerScore then
					wishdir = rightWishdir
				else
					wishdir = centerWishdir
				end
			end

			-- MoveAssistance continuously circles enemy (footwork only, no camera snap)
			FakelagOn()
			WalkInDirection(cmd, wishdir, true) -- forceNoSnap = true
		end
	end
	::skip_assistance::

	-- Ensure we have a valid warp target position for AutoWalk and AutoWarp
	if BackstabPos ~= emptyVec and minWarpTicks then
		-- Check if we can CURRENTLY backstab (from our current position)
		local canCurrentlyBackstab = CanBackstabFromPos(pLocalPos)

		-- Check if WARP would result in backstab (at BackstabPos) - includes LOS check
		local warpWouldBackstab = CanBackstabFromPos(BackstabPos)

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

			-- FIRST: Snap view angles to backstab position (so warp will work correctly)
			if Menu.Advanced.UseAngleSnap and BackstabPos and BackstabPos ~= emptyVec then
				local lookAngles = PositionAngles(pLocalPos, BackstabPos)
				if lookAngles then
					cmd:SetViewAngles(lookAngles.pitch, lookAngles.yaw, 0)
					engine.SetViewAngles(EulerAngles(lookAngles.pitch, lookAngles.yaw, 0))
				end
			end

			-- THEN: Walk toward the optimal direction (footwork)
			WalkInDirection(cmd, dir, not Menu.Advanced.UseAngleSnap) -- forceNoSnap if angle snap disabled
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

	-- Angle snap mode requires user input to work (abuses player's own input for direction)
	if Menu.Advanced.UseAngleSnap then
		local fwd = cmd:GetForwardMove()
		local side = cmd:GetSideMove()
		if fwd == 0 and side == 0 then
			return -- No user input, can't angle snap
		end
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

	-- Auto recharge logic: Recharge when kill/hurt confirmed or ping-based cooldown after warp
	if Menu.Advanced.AutoRecharge and not warp.IsWarping() and warp.GetChargedTicks() < 24 and not warp.CanWarp() then
		local shouldRecharge = false

		-- Check 1: Got kill/hurt confirmation (immediate recharge)
		if warpConfirmed then
			shouldRecharge = true
		end

		-- Check 2: Ping-based cooldown after warp (latency + buffer in ticks)
		if warpExecutedTick > 0 then
			local currentTick = globals.TickCount()
			local ticksSinceWarp = currentTick - warpExecutedTick
			-- Use latency-based cooldown: Latency in ticks + 5 tick buffer
			local pingCooldown = math.max(7, (Latency or 0) + 5)
			if ticksSinceWarp >= pingCooldown then
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
	if not TargetPlayer or not TargetPlayer.entity then
		-- No valid target - update cache for next tick
		UpdateSimulationCache()
	else
		-- Valid target - run trickstab logic
		UpdateSimulationCache() -- Keep cache fresh
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

				-- Path colors: Path 1 = Green (optimal), Path 2 = Orange (other side), Path 3 = Cyan (center)
				local baseR, baseG, baseB
				if pathIdx == 1 then
					baseR, baseG, baseB = 0, 255, 0 -- Green for optimal side
				elseif pathIdx == 2 then
					baseR, baseG, baseB = 255, 150, 0 -- Orange for other side
				else
					baseR, baseG, baseB = 0, 200, 255 -- Cyan for center
				end

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
callbacks.Unregister("FireGameEvent", "AtSM_KillRecharge")

--[[ Register callbacks ]]
--
callbacks.Register("CreateMove", "AtSM_CreateMove", OnCreateMove) -- Register the "CreateMove" callback
callbacks.Register("Unload", "AtSM_Unload", OnUnload) -- Register the "Unload" callback
callbacks.Register("Draw", "AtSM_Draw", doDraw) -- Register the "Draw" callback
callbacks.Register("FireGameEvent", "adaamageLogger", damageLogger)
callbacks.Register("FireGameEvent", "AtSM_KillRecharge", OnKillRecharge) -- Auto recharge on kill

--[[ Play sound when loaded ]]
--
engine.PlaySound("hl1/fvox/activated.wav")
