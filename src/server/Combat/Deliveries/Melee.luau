--!strict
--[[
	Melee (server)
	Hand-to-hand attacks. A box hitbox in front of the player, checked once
	after a short wind-up (HitDelay). The box follows the player during the wind-up.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Combat = ReplicatedStorage.Combat
local Types = require(Combat.Types)
local CharacterUtil = require(Combat.Shared.CharacterUtil)
local HitService = require(script.Parent.Parent.HitService)
local DebugDraw = require(script.Parent.Parent.DebugDraw)

local DEFAULT_HITBOX = Vector3.new(5, 5, 6)

local execute: Types.ServerDelivery = function(context)
	local rootPart = context.Character:FindFirstChild("HumanoidRootPart")
	if not (rootPart and rootPart:IsA("BasePart")) then
		return context.Origin
	end

	local size = context.Attack.HitboxSize or DEFAULT_HITBOX

	task.delay(context.Attack.HitDelay or 0, function()
		-- The player may have died during the wind-up
		if not CharacterUtil.getAliveHumanoid(context.Character) then
			return
		end

		-- Read the CFrame AFTER the delay so the punch lands where the player is NOW.
		-- CFrame * CFrame.new(0, 0, -z) = "z studs in front of", in the player's own facing direction.
		local boxCFrame = rootPart.CFrame * CFrame.new(0, 0, -size.Z / 2)
		DebugDraw.box(boxCFrame, size)

		local overlapParams = OverlapParams.new()
		overlapParams.FilterType = Enum.RaycastFilterType.Exclude
		overlapParams.FilterDescendantsInstances = { context.Character }

		local hit: { [Humanoid]: boolean } = {}
		for _, part in workspace:GetPartBoundsInBox(boxCFrame, size, overlapParams) do
			local _, humanoid = CharacterUtil.getCharacterFromPart(part)
			-- canReach: no punching through walls
			if
				humanoid
				and not hit[humanoid]
				and HitService.canReach(rootPart.Position, part, { context.Character })
			then
				hit[humanoid] = true
				HitService.hitCharacter(context, humanoid, part, part.Position, rootPart.CFrame.LookVector)
			end
		end
	end)

	return rootPart.Position + rootPart.CFrame.LookVector * size.Z
end

return execute
