--!strict
--[[
	Melee (client)
	Bursts the attack's Main kit from its Anchor (e.g. the punching hand).
	With Anchor = "AlternateHands", data.Side says which hand threw this punch.
	Template: a kit (particles and sounds, in Attachments or directly on a part).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Combat = ReplicatedStorage:WaitForChild("Combat")
local Types = require(Combat.Types)
local Anchors = require(Combat.Shared.Anchors)
local VFXUtil = require(script.Parent.Parent.VFXUtil)

local play: Types.ClientDelivery = function(caster, attack, data)
	VFXUtil.shakeAt(attack.Shake, data.Origin)

	local character = caster.Character
	if not character then
		return
	end
	VFXUtil.burstKit(attack.VFX.Main, Anchors.getParts(character, attack.Anchor, data.Side))
end
