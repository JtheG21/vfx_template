--!strict
--[[
	Beam (client)
	Procedural lightning from Origin to Target: a fractal bolt with a few forks.
	It re-generates its shape a few times (flicker), then thins out and vanishes.

	SHAPE: "midpoint displacement". Start with a straight line, push its midpoint
	sideways by a random amount, then do the same to each half with a bit less force,
	and repeat. Big bends made of smaller bends made of smaller bends: that's what
	makes it read as lightning instead of a zig-zag.

	TEMPLATE: any Model/Part containing one or more Beam objects. They are only
	STYLES (color, width, glow). Code clones each style onto every segment, so a
	wide faint "Glow" beam plus a thin bright beam layer into a glowing bolt.
	Leave the style beams Enabled = false in the template.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Combat = ReplicatedStorage:WaitForChild("Combat")
local Types = require(Combat.Types)
local AssetPool = require(script.Parent.Parent.AssetPool)
local VFXUtil = require(script.Parent.Parent.VFXUtil)

-- Shape tuning
local ROUGHNESS = 0.09 -- first bend = up to 9% of the bolt's length sideways
local DETAIL_DECAY = 0.7 -- each finer level of bends is 70% as strong as the one before
local STUDS_PER_SEGMENT = 1.5 -- aim for roughly one tiny segment every 1.5 studs
local MIN_DETAIL = 2 -- detail N = 2^N segments: 2 -> 4 segments, 6 -> 64 segments
local MAX_DETAIL = 6

-- Forks
local FORK_COUNT = 2
local FORK_DETAIL = 3
local FORK_ROUGHNESS = 0.12
local FORK_LENGTH = NumberRange.new(0.1, 0.22) -- fraction of the main bolt's length
local FORK_SPREAD = 0.9 -- how far forks angle away from the main direction
local FORK_WIDTH = 0.55 -- forks are thinner than the main bolt

-- Timing
local FLICKER_COUNT = 3 -- how many times the bolt re-generates its shape
local FLICKER_INTERVAL = 0.05
local FADE_TIME = 0.2

-- Light cast onto the surroundings
local LIGHT_COLOR = Color3.fromRGB(110, 160, 255)
local LIGHT_RANGE = 14
local LIGHT_BRIGHTNESS = 5

type Strand = {
	Attachments: { Attachment },
	Detail: number,
	Roughness: number,
}

local function getStyles(root: Instance): { Beam }
	local styles = {}
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("Beam") and not descendant.Attachment0 then
			table.insert(styles, descendant)
		end
	end
	return styles
end

-- Two directions at 90 degrees to `direction` (and to each other)
local function getSideAxes(direction: Vector3): (Vector3, Vector3)
	local reference = if math.abs(direction.Unit.Y) < 0.99 then Vector3.yAxis else Vector3.xAxis
	local right = direction:Cross(reference).Unit
	local up = right:Cross(direction).Unit
	return right, up
end

-- math.random() * 2 - 1 = a random number between -1 and 1
local function randomSigned(): number
	return math.random() * 2 - 1
end

-- Midpoint displacement. Returns 2^detail + 1 points from `origin` to `target`.
local function buildFractal(origin: Vector3, target: Vector3, detail: number, roughness: number): { Vector3 }
	local points = { origin, target }
	local strength = (target - origin).Magnitude * roughness

	for _ = 1, detail do
		-- Each pass inserts a displaced midpoint between every pair of neighbours,
		-- so the number of segments doubles every pass.
		local refined = { points[1] }
		for i = 1, #points - 1 do
			local a, b = points[i], points[i + 1]
			local right, up = getSideAxes(b - a)
			local midpoint = (a + b) / 2 + (right * randomSigned() + up * randomSigned()) * strength
			table.insert(refined, midpoint)
			table.insert(refined, b)
		end
		points = refined
		strength *= DETAIL_DECAY
	end

	return points
end

-- Creates the attachments + beam segments for one strand (the main bolt or a fork).
-- The point count is fixed by `detail`, so flickering only has to MOVE attachments.
local function createStrand(
	anchorPart: BasePart,
	styles: { Beam },
	detail: number,
	roughness: number,
	widthScale: number,
	beams: { Beam }
): Strand
	local attachments: { Attachment } = {}
	for i = 1, 2 ^ detail + 1 do
		local attachment = Instance.new("Attachment")
		attachment.Parent = anchorPart
		attachments[i] = attachment
	end

	for _, style in styles do
		for i = 1, #attachments - 1 do
			local beam = style:Clone()
			beam.Attachment0 = attachments[i]
			beam.Attachment1 = attachments[i + 1]
			beam.Width0 = style.Width0 * widthScale
			beam.Width1 = style.Width1 * widthScale
			beam.Enabled = true
			beam.Parent = anchorPart
			table.insert(beams, beam)
		end
	end

	return { Attachments = attachments, Detail = detail, Roughness = roughness }
end

local function layoutStrand(strand: Strand, origin: Vector3, target: Vector3)
	local points = buildFractal(origin, target, strand.Detail, strand.Roughness)
	for i, attachment in strand.Attachments do
		attachment.WorldPosition = points[i]
	end
end

-- New random shape for the main bolt, then grow each fork off a random point on it
local function layoutBolt(main: Strand, forks: { Strand }, origin: Vector3, target: Vector3)
	layoutStrand(main, origin, target)

	local length = (target - origin).Magnitude
	local forward = (target - origin).Unit
	local right, up = getSideAxes(forward)
	local mainCount = #main.Attachments

	for _, fork in forks do
		-- Start somewhere in the middle 60% of the bolt, never at the very ends
		local startIndex = math.random(math.ceil(mainCount * 0.2), math.floor(mainCount * 0.8))
		local start = main.Attachments[startIndex].WorldPosition
		local direction = (forward + (right * randomSigned() + up * randomSigned()) * FORK_SPREAD).Unit
		local forkLength = length * (FORK_LENGTH.Min + math.random() * (FORK_LENGTH.Max - FORK_LENGTH.Min))
		layoutStrand(fork, start, start + direction * forkLength)
	end
end

local function addLight(attachment: Attachment, lights: { PointLight })
	local light = Instance.new("PointLight")
	light.Color = LIGHT_COLOR
	light.Range = LIGHT_RANGE
	light.Brightness = LIGHT_BRIGHTNESS
	light.Parent = attachment
	table.insert(lights, light)
end

local play: Types.ClientDelivery = function(_caster, attack, data)
	local vfxPath = attack.VFX.Main
	if not vfxPath then
		return
	end

	local origin, target = data.Origin, data.Target
	local length = (target - origin).Magnitude
	if length < 0.1 then
		return
	end

	local holder = AssetPool.get(vfxPath)
	if not holder then
		return
	end
	local styles = getStyles(holder)
	local anchorPart = VFXUtil.getMainPart(holder)
	if #styles == 0 or not anchorPart then
		warn(`[Combat] Beam template "{vfxPath}" needs a BasePart containing at least one Beam`)
		AssetPool.release(vfxPath, holder)
		return
	end
	if holder:IsA("PVInstance") then
		holder:PivotTo(CFrame.new(origin))
	end
	holder.Parent = VFXUtil.Container
	-- Anything else in the template (a crackle sound, sparks) plays once at the hand
	local extrasLifetime = VFXUtil.burst(holder)

	-- Longer bolt = more detail. math.log(x, 2) answers "2 to the what equals x?",
	-- which turns "how many segments do I want" into "how many doubling passes".
	local detail = math.clamp(math.ceil(math.log(length / STUDS_PER_SEGMENT, 2)), MIN_DETAIL, MAX_DETAIL)
	local widthScale = 1 + data.Charge -- a full charge doubles the bolt's thickness

	local beams: { Beam } = {}
	local main = createStrand(anchorPart, styles, detail, ROUGHNESS, widthScale, beams)
	local forks: { Strand } = {}
	for i = 1, FORK_COUNT do
		forks[i] = createStrand(anchorPart, styles, FORK_DETAIL, FORK_ROUGHNESS, widthScale * FORK_WIDTH, beams)
	end

	-- Lights at the hand, the middle and the target. They light up the ground and walls.
	local lights: { PointLight } = {}
	local mainCount = #main.Attachments
	for _, index in { 1, math.ceil(mainCount / 2), mainCount } do
		addLight(main.Attachments[index], lights)
	end

	VFXUtil.shakeAt(attack.Shake, target)

	-- task.spawn runs the animation in its own thread, so task.wait inside it
	-- doesn't pause the script that received the network event.
	task.spawn(function()
		for _ = 1, FLICKER_COUNT do
			layoutBolt(main, forks, origin, target)
			task.wait(FLICKER_INTERVAL)
		end

		-- Thin out and dim instead of popping out of existence
		local fadeInfo = TweenInfo.new(FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		for _, beam in beams do
			TweenService:Create(beam, fadeInfo, { Width0 = 0, Width1 = 0 }):Play()
		end
		for _, light in lights do
			TweenService:Create(light, fadeInfo, { Brightness = 0 }):Play()
		end
		task.wait(FADE_TIME)
		-- If the template's own sound or particles run longer than the bolt, let them finish
		local boltTime = FLICKER_COUNT * FLICKER_INTERVAL + FADE_TIME
		if extrasLifetime > boltTime then
			task.wait(extrasLifetime - boltTime)
		end

		-- Destroying the attachments also destroys the lights inside them
		for _, beam in beams do
			beam:Destroy()
		end
		for _, strand in { main, table.unpack(forks) } do
			for _, attachment in strand.Attachments do
				attachment:Destroy()
			end
		end
		AssetPool.release(vfxPath, holder)
	end)
end

return play
