--!strict
--[[
	Raycasting
	Raycasts shared by the server deliveries and the client visuals.

	WHY THIS EXISTS: aim points come from the mouse, which always sits EXACTLY on a
	surface. A ray that ends exactly on a surface can miss it by a hair (floating-point
	rounding), and then a shot at the floor reports no impact. So every ray here
	reaches SURFACE_EPSILON studs past its target.
]]

local CharacterUtil = require(script.Parent.CharacterUtil)

local SURFACE_EPSILON = 0.5
local MAX_CHARACTER_PASSES = 5

local Raycasting = {}

local function makeParams(ignore: { Instance }): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	return params
end

-- First thing along the ray: a character OR the world.
function Raycasting.cast(origin: Vector3, direction: Vector3, distance: number, ignore: { Instance }): RaycastResult?
	return workspace:Raycast(origin, direction * (distance + SURFACE_EPSILON), makeParams(ignore))
end

-- First piece of WORLD along the ray (walls, floor, terrain), passing through characters.
-- Used for "where does this stop" questions: projectile end points, AOE ground snapping.
function Raycasting.castWorld(
	origin: Vector3,
	direction: Vector3,
	distance: number,
	ignore: { Instance }
): RaycastResult?
	local params = makeParams(ignore)
	for _ = 1, MAX_CHARACTER_PASSES do
		local result = workspace:Raycast(origin, direction * (distance + SURFACE_EPSILON), params)
		if not result then
			return nil
		end
		local hitCharacter = CharacterUtil.getCharacterFromPart(result.Instance)
		if not hitCharacter then
			return result
		end
		-- A character is in the way: ignore it and cast again to see what's behind
		params:AddToFilter(hitCharacter)
	end
	return nil
end

return Raycasting
