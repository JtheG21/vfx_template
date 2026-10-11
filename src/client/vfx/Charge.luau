--!strict
--[[
	Charge
	While a player holds a charge attack:
	  - the attack's Charge kit sits on its Anchor (both hands, right hand, feet...)
	  - its sounds rise in pitch as it charges, so you can HEAR how charged it is
	  - when the charge reaches 100%, the ChargeFull kit pops once, so the player
	    (and everyone watching) can SEE it's fully charged
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Combat = ReplicatedStorage:WaitForChild("Combat")
local Types = require(Combat.Types)
local Anchors = require(Combat.Shared.Anchors)
local VFXUtil = require(script.Parent.VFXUtil)

-- Charge sounds end this much higher-pitched than they start (1.25 = 25% higher)
local CHARGE_PITCH_RISE = 1.25

type ActiveCharge = {
	Attachments: { Attachment },
}

local Charge = {}

local active: { [Player]: ActiveCharge } = {}

-- Sine "In" easing starts slow and speeds up, like something building power.
-- The rise peaks exactly when the charge is full, right as ChargeFull pops.
local function risePitch(attachments: { Attachment }, duration: number)
	local info = TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.In)
	for _, attachment in attachments do
		for _, descendant in attachment:GetDescendants() do
			if descendant:IsA("Sound") then
				TweenService:Create(descendant, info, { PlaybackSpeed = descendant.PlaybackSpeed * CHARGE_PITCH_RISE })
					:Play()
			end
		end
	end
end

function Charge.start(caster: Player, attack: Types.AttackConfig, data: Types.ChargeData)
	Charge.stop(caster) -- never stack two charge effects on one player

	local character = caster.Character
	if not character then
		return
	end
	local parts = Anchors.getParts(character, attack.Anchor, data.Side)

	local entry: ActiveCharge = {
		Attachments = if attack.VFX.Charge then VFXUtil.attachKit(attack.VFX.Charge, parts) else {},
	}
	active[caster] = entry

	local chargeSettings = attack.Charge
	if chargeSettings then
		risePitch(entry.Attachments, chargeSettings.Time)
	end

	local fullPath = attack.VFX.ChargeFull
	if chargeSettings and fullPath then
		task.delay(chargeSettings.Time, function()
			-- PATTERN: the entry TABLE is its own token. If this charge was released or
			-- replaced in the meantime, active[caster] is a different table (or nil).
			if active[caster] == entry then
				VFXUtil.burstKit(fullPath, parts)
			end
		end)
	end
end

function Charge.stop(caster: Player)
	local entry = active[caster]
	if entry then
		active[caster] = nil
		VFXUtil.detachKit(entry.Attachments)
	end
end

return Charge
