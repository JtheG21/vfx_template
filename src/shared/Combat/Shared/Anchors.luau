--!strict
--[[
	Anchors
	Turns an attack's Anchor setting into real body parts. Used for where an attack
	STARTS (its origin) and where its kits ATTACH (Charge, ChargeFull, Cast, Melee, Aura).

	  RightHand / LeftHand   one hand
	  BothHands              both hands (origin = halfway between them)
	  AlternateHands         one hand, switching every use: right, left, right...
	  Torso                  the chest
	  Feet                   both feet (origin = between them), good for stomps
	  Root                   the HumanoidRootPart, the center of the character

	Works on R15 and R6 rigs.
]]

local Types = require(script.Parent.Parent.Types)

local Anchors = {}

local DEFAULT_ANCHOR: Types.Anchor = "RightHand"
Anchors.Default = DEFAULT_ANCHOR

-- Each limb is listed as { R15 name, R6 name }
type Limb = { string }

local RIGHT_HAND: Limb = { "RightHand", "Right Arm" }
local LEFT_HAND: Limb = { "LeftHand", "Left Arm" }

local LIMBS: { [Types.Anchor]: { Limb } } = {
	RightHand = { RIGHT_HAND },
	LeftHand = { LEFT_HAND },
	BothHands = { LEFT_HAND, RIGHT_HAND },
	AlternateHands = { RIGHT_HAND }, -- the side picks the real hand, see getLimbs
	Torso = { { "UpperTorso", "Torso" } },
	Feet = { { "LeftFoot", "Left Leg" }, { "RightFoot", "Right Leg" } },
	Root = { { "HumanoidRootPart", "HumanoidRootPart" } },
}

local function getLimbs(anchor: Types.Anchor?, side: Types.Side?): { Limb }
	if anchor == "AlternateHands" then
		return { if side == "Left" then LEFT_HAND else RIGHT_HAND }
	end
	return LIMBS[anchor or DEFAULT_ANCHOR] or LIMBS[DEFAULT_ANCHOR]
end

local function findLimb(character: Model, limb: Limb): BasePart?
	for _, name in limb do
		local part = character:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			return part
		end
	end
	return nil
end

-- The parts an anchor refers to, right now. Missing limbs are skipped.
function Anchors.getParts(character: Model, anchor: Types.Anchor?, side: Types.Side?): { BasePart }
	local parts = {}
	for _, limb in getLimbs(anchor, side) do
		local part = findLimb(character, limb)
		if part then
			table.insert(parts, part)
		end
	end
	return parts
end

-- Same, but WAITS for limbs to load (characters stream in part by part).
-- Use right after CharacterAdded. Limbs that don't appear within `timeout` are skipped.
function Anchors.waitForParts(character: Model, anchor: Types.Anchor?, side: Types.Side?, timeout: number): { BasePart }
	local humanoid = character:WaitForChild("Humanoid", timeout)
	if not (humanoid and humanoid:IsA("Humanoid")) then
		return {}
	end
	-- The rig type tells us which of the two names to wait for
	local nameIndex = if humanoid.RigType == Enum.HumanoidRigType.R15 then 1 else 2

	local parts = {}
	for _, limb in getLimbs(anchor, side) do
		local part = character:WaitForChild(limb[nameIndex], timeout)
		if part and part:IsA("BasePart") then
			table.insert(parts, part)
		end
	end
	return parts
end

-- Where an attack anchored here starts: the average position of its parts.
function Anchors.getOrigin(character: Model, anchor: Types.Anchor?, side: Types.Side?): Vector3
	local parts = Anchors.getParts(character, anchor, side)
	if #parts == 0 then
		return character:GetPivot().Position
	end
	local sum = Vector3.zero
	for _, part in parts do
		sum += part.Position
	end
	return sum / #parts
end

-- The side to use NEXT time. Only AlternateHands has sides; everything else returns nil.
function Anchors.nextSide(anchor: Types.Anchor?, previous: Types.Side?): Types.Side?
	if anchor ~= "AlternateHands" then
		return nil
	end
	return if previous == "Right" then "Left" else "Right"
end

-- Runtime checks for values that arrive untyped (remote arguments, config typos).
function Anchors.isAnchor(value: unknown): boolean
	return typeof(value) == "string" and LIMBS[value :: any] ~= nil
end

function Anchors.isSide(value: unknown): boolean
	return value == "Left" or value == "Right"
end

return Anchors
