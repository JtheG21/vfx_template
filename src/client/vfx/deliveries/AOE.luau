--!strict
--[[
	AOE (client)
	Two looks, chosen by the attack config:
	  SkyStrike = true -> the template (a standing strike) is placed upright on the target
	  otherwise        -> a blast at the target; a part named "Wave" expands to the radius
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Combat = ReplicatedStorage:WaitForChild("Combat")
local Types = require(Combat.Types)
local AssetPool = require(script.Parent.Parent.AssetPool)
local VFXUtil = require(script.Parent.Parent.VFXUtil)

local DEFAULT_RADIUS = 15
local STRIKE_DURATION = 0.2
local WAVE_TIME = 0.4
local WAVE_HEIGHT = 2

-- Sky-strike templates are built STANDING on the ground: the pivot is the strike
-- point, and the bolt (e.g. a tall flipbook) is laid out above it. So: place it
-- upright on the target and fire everything once.
local function playSkyStrike(path: string, effect: PVInstance, center: Vector3)
	effect:PivotTo(CFrame.new(center))
	effect.Parent = VFXUtil.Container
	local lifetime = VFXUtil.burst(effect)

	task.delay(math.max(lifetime, STRIKE_DURATION), function()
		AssetPool.release(path, effect)
	end)
end

local function playBlast(path: string, effect: PVInstance, center: Vector3, radius: number)
	effect:PivotTo(CFrame.new(center))
	effect.Parent = VFXUtil.Container

	local wave = effect:FindFirstChild("Wave", true)
	if wave and wave:IsA("BasePart") then
		wave.Size = Vector3.zero
		wave.Transparency = 0
		-- Grow to the real damage radius, so what players SEE matches what HURTS
		TweenService:Create(wave, TweenInfo.new(WAVE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.new(radius * 2, WAVE_HEIGHT, radius * 2),
			Transparency = 1,
		}):Play()
	end

	local lifetime = VFXUtil.burst(effect)
	task.delay(math.max(lifetime, WAVE_TIME), function()
		AssetPool.release(path, effect)
	end)
end

local play: Types.ClientDelivery = function(_caster, attack, data)
	local path = attack.VFX.Main
	local center = data.Target
	VFXUtil.shakeAt(attack.Shake, center)
	if not path then
		return
	end

	local effect = AssetPool.get(path)
	if not effect then
		return
	end
	if not effect:IsA("PVInstance") then
		AssetPool.release(path, effect)
		return
	end

	if attack.SkyStrike then
		playSkyStrike(path, effect, center)
	else
		playBlast(path, effect, center, attack.Radius or DEFAULT_RADIUS)
	end
end

return play
