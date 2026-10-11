--!strict
--[[
	Beam (server)
	One instant raycast. The first thing it touches gets hit: a character or a wall.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Combat = ReplicatedStorage.Combat
local Types = require(Combat.Types)
local CharacterUtil = require(Combat.Shared.CharacterUtil)
local HitService = require(script.Parent.Parent.HitService)
local DebugDraw = require(script.Parent.Parent.DebugDraw)
local Raycasting = require(Combat.Shared.Raycasting)

local execute: Types.ServerDelivery = function(context)
	local result = Raycasting.cast(context.Origin, context.Direction, context.Distance, { context.Character })
	DebugDraw.line(context.Origin, if result then result.Position else context.Target)
	if not result then
		return context.Target -- hit nothing: the beam reaches full range
	end

	local _, humanoid = CharacterUtil.getCharacterFromPart(result.Instance)
	if humanoid then
		HitService.hitCharacter(context, humanoid, result.Instance, result.Position, result.Normal)
	else
		HitService.hitSurface(context, result.Instance, result.Position, result.Normal)
	end

	return result.Position -- the beam visual stops exactly where it hit
end

return execute
