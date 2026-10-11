--!strict
--[[
	AOE (server)
	Snaps the aim point to the ground, then explodes there: one central blast
	plus damage to every character in the radius.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Combat = ReplicatedStorage.Combat
local Types = require(Combat.Types)
local Raycasting = require(Combat.Shared.Raycasting)
local HitService = require(script.Parent.Parent.HitService)

local DEFAULT_RADIUS = 15
local GROUND_SNAP_HEIGHT = 5 -- start the ground ray this far above the aim point
local GROUND_SNAP_DEPTH = 50 -- and search this far down

local execute: Types.ServerDelivery = function(context)
	local radius = context.Attack.Radius or DEFAULT_RADIUS

	-- Snap to the ground. castWorld passes THROUGH characters, so aiming at
	-- someone's head still lands the blast on the floor under them.
	local groundHit = Raycasting.castWorld(
		context.Target + Vector3.yAxis * GROUND_SNAP_HEIGHT,
		-Vector3.yAxis, -- straight down (Vector3s can be negated like numbers)
		GROUND_SNAP_HEIGHT + GROUND_SNAP_DEPTH,
		{ context.Character }
	)
	local center = if groundHit then groundHit.Position else context.Target

	-- Optional delay between the visual starting and the damage landing
	task.delay(context.Attack.HitDelay or 0, function()
		HitService.explode(context, center, radius, groundHit)
	end)

	return center
end

return execute
