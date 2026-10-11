--!strict
--[[
	HitService
	The ONLY place damage is applied and impacts are announced to clients.

	Deliveries decide WHAT got hit. HitService decides what HAPPENS because of it.
	Later features like blocking, armor, combo counters or damage numbers go in here once,
	and every attack gets them automatically.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Combat = ReplicatedStorage.Combat
local Types = require(Combat.Types)
local Settings = require(Combat.Settings)
local Remotes = require(Combat.Remotes)
local CharacterUtil = require(Combat.Shared.CharacterUtil)
local Raycasting = require(Combat.Shared.Raycasting)
local DebugDraw = require(script.Parent.DebugDraw)

-- Line-of-sight rays stop this far short of the target's center. Otherwise a target
-- standing with their back against a wall could count as "behind" it.
local SIGHT_MARGIN = 1
-- Explosion sight lines start this far out from the surface the blast is on (along the
-- surface's normal), so the floor or wall the explosion sits on doesn't block its own rays.
local BLAST_EYE_OFFSET = 1

local HitService = {}

-- True if nothing solid (walls, floors) sits between `from` and `part`.
-- Characters never block: castWorld passes straight through them.
-- Used by area attacks (explosions, melee boxes) so they can't hit through walls.
function HitService.canReach(from: Vector3, part: BasePart, ignore: { Instance }): boolean
	if not Settings.AreaLineOfSight then
		return true
	end
	local offset = part.Position - from
	local distance = offset.Magnitude - SIGHT_MARGIN
	if distance <= 0 then
		return true -- the target is basically touching the source
	end
	return Raycasting.castWorld(from, offset.Unit, distance, ignore) == nil
end

local function replicateImpact(context: Types.AttackContext, data: Types.ImpactData)
	-- task.defer runs this right AFTER the current code finishes.
	-- Instant attacks (Beam, AOE) detect hits BEFORE CombatServer sends the "Fire"
	-- packet. Deferring guarantees clients always get Fire first, then Impact.
	task.defer(function()
		Remotes.AttackReplicate:FireAllClients("Impact", context.Player, context.AttackId, data)
	end)
end

local function damageCharacter(
	context: Types.AttackContext,
	humanoid: Humanoid,
	part: BasePart,
	position: Vector3,
	normal: Vector3,
	splash: boolean
)
	if humanoid.Health <= 0 then
		return -- already dead: no damage, no blood
	end
	humanoid:TakeDamage(context.Damage)
	replicateImpact(context, {
		Position = position,
		Normal = normal,
		Part = part,
		IsCharacter = true,
		Splash = splash,
	})
end

-- A character got hit directly: damage, impact burst and blood.
function HitService.hitCharacter(
	context: Types.AttackContext,
	humanoid: Humanoid,
	part: BasePart,
	position: Vector3,
	normal: Vector3
)
	damageCharacter(context, humanoid, part, position, normal, false)
end

-- A wall/floor got hit: no damage, just impact VFX and a mark.
function HitService.hitSurface(context: Types.AttackContext, part: BasePart, position: Vector3, normal: Vector3)
	replicateImpact(context, {
		Position = position,
		Normal = normal,
		Part = part,
		IsCharacter = false,
		Splash = false,
	})
end

-- An explosion: ONE central blast (impact burst + scorch mark if it landed on something),
-- then damage to every character in the radius. Those only get blood, so 5 enemies
-- caught in one blast don't trigger 5 extra explosions.
-- `surface` is what the explosion landed on (nil if it went off in mid-air).
function HitService.explode(context: Types.AttackContext, center: Vector3, radius: number, surface: RaycastResult?)
	DebugDraw.sphere(center, radius)
	replicateImpact(context, {
		Position = center,
		Normal = if surface then surface.Normal else Vector3.yAxis,
		Part = if surface then surface.Instance else nil,
		IsCharacter = false,
		Splash = false,
	})

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = { context.Character }

	local eye = center + (if surface then surface.Normal else Vector3.yAxis) * BLAST_EYE_OFFSET
	local damaged: { [Humanoid]: boolean } = {}
	for _, part in workspace:GetPartBoundsInRadius(center, radius, overlapParams) do
		local _, humanoid = CharacterUtil.getCharacterFromPart(part)
		-- One limb in view is enough: a character peeking round a corner still gets hit,
		-- because their other limbs get checked too until one has a clear line.
		if humanoid and not damaged[humanoid] and HitService.canReach(eye, part, { context.Character }) then
			damaged[humanoid] = true

			-- The blood sprays AWAY from the blast center.
			-- Guard the .Unit: a part sitting exactly on the center would give NaN.
			local offset = part.Position - center
			local normal = if offset.Magnitude > 0.01 then offset.Unit else Vector3.yAxis
			damageCharacter(context, humanoid, part, part.Position, normal, true)
		end
	end
end

return HitService
