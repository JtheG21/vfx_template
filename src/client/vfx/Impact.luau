--!strict
--[[
	Impact
	Plays when the server reports a hit:
	  - the attack's Impact burst (skipped for Splash hits, see below)
	  - hit a character: the Hit VFX (blood)
	  - hit a surface: a Mark (scorch decal) that fades out after a while

	A Mark template is a part with a Decal (or Texture) on ANY face; the mark is turned so
	that face lies against the surface. Anything else inside it runs while the mark is
	down: a smoke emitter makes it smolder, a looped sound makes it crackle.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Combat = ReplicatedStorage:WaitForChild("Combat")
local Types = require(Combat.Types)
local Settings = require(Combat.Settings)
local AssetPool = require(script.Parent.AssetPool)
local TemplatePrep = require(script.Parent.TemplatePrep)
local VFXUtil = require(script.Parent.VFXUtil)

-- Lift marks slightly off the surface. Two faces in the same spot flicker ("z-fighting").
local MARK_LIFT = 0.05
local FULL_TURN = math.pi * 2 -- radians in a full circle (360 degrees)

local Impact = {}

-- Which face of the mark carries the decal (Top if there's none to go by)
local function getDecalFace(mark: Instance): Enum.NormalId
	local decal = mark:FindFirstChildWhichIsA("Decal", true) -- also finds Textures
	return if decal then decal.Face else Enum.NormalId.Top
end

local function placeMark(path: string, position: Vector3, normal: Vector3)
	local mark = AssetPool.get(path)
	if not mark then
		return
	end

	if mark:IsA("PVInstance") then
		-- Random spin around the normal so repeated marks don't all look identical
		local spin = CFrame.Angles(0, math.random() * FULL_TURN, 0)
		-- surfaceCFrame points the mark's TOP at the surface normal. If the decal is on
		-- another face, first rotate that face to where Top is, so the decal faces out.
		local faceNormal = Vector3.FromNormalId(getDecalFace(mark))
		local faceToTop = CFrame.fromRotationBetweenVectors(faceNormal, Vector3.yAxis)
		mark:PivotTo(VFXUtil.surfaceCFrame(position + normal * MARK_LIFT, normal) * spin * faceToTop)
	end
	-- Start fully visible as authored (a pooled mark was faded out last time)
	for _, descendant in mark:GetDescendants() do
		if descendant:IsA("Decal") then
			descendant.Transparency = TemplatePrep.getNumber(descendant, TemplatePrep.Attributes.BaseTransparency, 0)
		end
	end
	mark.Parent = VFXUtil.Container
	VFXUtil.sustain(mark)

	task.delay(Settings.MarkLifetime, function()
		VFXUtil.stop(mark)
		-- IsA("Decal") also matches Textures (Texture inherits from Decal).
		-- The pool restores their authored transparency when the mark is reused.
		local fadeInfo = TweenInfo.new(Settings.MarkFadeTime)
		for _, descendant in mark:GetDescendants() do
			if descendant:IsA("Decal") then
				TweenService:Create(descendant, fadeInfo, { Transparency = 1 }):Play()
			end
		end
		task.delay(Settings.MarkFadeTime, function()
			AssetPool.release(path, mark)
		end)
	end)
end

function Impact.play(attack: Types.AttackConfig, data: Types.ImpactData)
	local cframe = VFXUtil.surfaceCFrame(data.Position, data.Normal)
	-- Splash = caught in an explosion. The explosion's own burst already played at
	-- its center, so these hits only get blood.
	if not data.Splash then
		VFXUtil.playBurst(attack.VFX.Impact, cframe)
	end

	if data.IsCharacter then
		VFXUtil.playBurst(attack.VFX.Hit or Settings.DefaultHitVFX, cframe)
	elseif attack.VFX.Mark and data.Part and data.Part.Anchored then
		-- Only mark anchored parts. A mark on a moving part would be left floating in the air.
		placeMark(attack.VFX.Mark, data.Position, data.Normal)
	end
end

return Impact
