--!strict
--[[
	Styles
	A style is an element/fighting style (Fire, Lightning, ...). It decides:
	  - which aura VFX the player wears (AuraVFX, placed at AuraAnchor, default BothHands)
	  - which attack each key fires

	TO ADD A NEW STYLE: copy a block, give it a new SelectKey, and bind attack ids from Attacks.
	The server only accepts attacks that are bound in the player's CURRENT style.
]]

local Types = require(script.Parent.Types)

local Styles: { [string]: Types.StyleConfig } = {
	Fire = {
		DisplayName = "Fire",
		SelectKey = Enum.KeyCode.Z,
		AuraVFX = "Fire/Hands",
		Binds = {

			[Enum.UserInputType.MouseButton1] = "FirePunch",
			[Enum.KeyCode.E] = "Fireball",
			[Enum.KeyCode.R] = "Meteor",
		},
	},

	Lightning = {
		DisplayName = "Lightning",
		SelectKey = Enum.KeyCode.X,
		AuraVFX = "Lightning/Hands",
		Binds = {
			[Enum.UserInputType.MouseButton1] = "ShockPalm",
			[Enum.KeyCode.E] = "LightningBolt",
			[Enum.KeyCode.R] = "ThunderStrike",
		},
	},
}

return table.freeze(Styles)
