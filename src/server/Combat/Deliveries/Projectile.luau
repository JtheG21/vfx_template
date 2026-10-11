--!strict
--[[
	Projectile (server)
	Moves an invisible point along the attack's Trajectory (straight or arced),
	raycasting the short segment it covered each frame. Clients follow the exact
	same path for the visual; the server only does the math.

	On landing:
	  BlastRadius set -> explode, damaging everyone in the radius
	  otherwise       -> damage whatever it hit directly (or mark the wall)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Combat = ReplicatedStorage.Combat
local Types = require(Combat.Types)
local CharacterUtil = require(Combat.Shared.CharacterUtil)
local Raycasting = require(Combat.Shared.Raycasting)
local Trajectory = require(Combat.Shared.Trajectory)
local HitService = require(script.Parent.Parent.HitService)
local DebugDraw = require(script.Parent.Parent.DebugDraw)

local DEFAULT_SPEED = 100

local function land(context: Types.AttackContext, position: Vector3, result: RaycastResult?)
	local blastRadius = context.Attack.BlastRadius
	if blastRadius then
		HitService.explode(context, position, blastRadius, result)
		return
	end
	if not result then
		return -- flew its full range and hit nothing
	end
	local _, humanoid = CharacterUtil.getCharacterFromPart(result.Instance)
	if humanoid then
		HitService.hitCharacter(context, humanoid, result.Instance, result.Position, result.Normal)
	else
		HitService.hitSurface(context, result.Instance, result.Position, result.Normal)
	end
end

local execute: Types.ServerDelivery = function(context)
	local speed = context.Attack.Speed or DEFAULT_SPEED
	local path = Trajectory.new(context.Origin, context.Target, context.Attack.ArcHeight)
	local duration = path.Length / speed -- time = distance / speed
	local ignore: { Instance } = { context.Character }

	local elapsed = 0
	local lastPosition = path.Origin
	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function(deltaTime)
		elapsed += deltaTime
		-- t = how far along the path we are, 0 to 1. Time-based, so the speed holds at any FPS.
		local t = math.min(elapsed / duration, 1)
		local position = Trajectory.getPoint(path, t)

		-- Swept check: raycast the segment covered THIS frame, so nothing slips
		-- through between frames even when the projectile is fast.
		local segment = position - lastPosition
		DebugDraw.line(lastPosition, position, DebugDraw.Colors.Path)
		if segment.Magnitude > 0 then
			local result = Raycasting.cast(lastPosition, segment.Unit, segment.Magnitude, ignore)
			if result then
				connection:Disconnect()
				land(context, result.Position, result)
				return
			end
		end
		lastPosition = position

		if t >= 1 then
			connection:Disconnect()
			land(context, position, nil) -- reached the end in mid-air
		end
	end)

	-- Clients rebuild the identical path from Origin + this Target + the config's ArcHeight
	return context.Target
end

return execute
