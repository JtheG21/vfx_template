--!strict
--[[
	Attacks
	The catalog of every attack in the game. DATA ONLY, no logic.

	TO ADD A NEW ATTACK:
	  1. Copy an entry below and change the values.
	  2. Bind its id to a key in Styles.
	  3. Put its VFX in ReplicatedStorage.VFXTemplates at the paths you list.
	     (Any missing VFX is skipped with a warning, so it still works without art.)

	Input:    "Instant" = fires on press | "Charge" = charges while held, fires on release
	Delivery: "Projectile" | "Beam" | "AOE" | "Melee"
	Anchor:   where it comes from and where its kits attach (default "RightHand"):
	          "RightHand" | "LeftHand" | "BothHands" | "AlternateHands" | "Torso" | "Feet" | "Root"

	VFX slots (all optional):
	  Charge      kit on the anchor while charging
	  ChargeFull  kit that pops on the anchor when the charge hits 100%
	  Cast        kit that pops on the anchor the moment the attack fires
	  Main        the attack itself (Projectile: flying model, Beam: beam styles,
	              AOE: placed effect, Melee: kit on the anchor)
	  Impact      burst where it connects       Hit   burst on characters it hits
	  Mark        decal left on surfaces
	Sounds go INSIDE templates: any Sound in a template plays with that effect.

	Animations (all optional, each "rbxassetid://123..."):
	  Charge      loops while charging        Fire   plays once when the attack goes off
	  ChargeLeft / ChargeRight / FireLeft / FireRight   per-hand versions for "AlternateHands"
	  In Moon Animator, add a marker named "Hit" on the frame the attack connects:
	  Melee and AOE effects wait for it. Set HitDelay to the same time so the damage
	  lands on that frame too (in Studio, the Output tells you if they differ).

	The server checks this whole file at startup and prints any problems to the Output.
]]

local Types = require(script.Parent.Types)

-- Annotating the table means EVERY entry is checked against AttackConfig.
-- A missing Damage field or a typo like Delivery = "Projectle" gets a red underline.
local Attacks: { [string]: Types.AttackConfig } = {
	----------------------------------------------------------------- FIRE
	FirePunch = {
		DisplayName = "Fire Punch",
		Input = "Instant",
		Delivery = "Melee",
		Anchor = "AlternateHands", -- left, right, left... a combo
		Damage = 8,
		Cooldown = 0.35,
		Range = 6,
		HitboxSize = Vector3.new(5, 5, 6),
		HitDelay = 0.08,
		VFX = { Main = "Fire/Punch", Impact = "Fire/PunchImpact" },
		Shake = { Intensity = 0.3, Frequency = 30, Duration = 0.15 },
	},

	Fireball = {
		DisplayName = "Fireball",
		Input = "Charge",
		Delivery = "Projectile",
		Damage = 20,
		Cooldown = 1,
		Range = 150,
		Speed = 120,
		Charge = { Time = 1.2, MinCharge = 0.15, DamageMultiplier = 2.5, VisualScale = 2, MaxHold = 3 },
		VFX = {
			Charge = "Fire/Charge",
			ChargeFull = "Fire/Punch",
			Cast = "Fire/Punch",
			Main = "Fire/Fireball",
			Impact = "Fire/Impact",
			Mark = "Fire/Scorch",
		},
		Shake = { Intensity = 1.2, Frequency = 45, Duration = 0.5 },
	},

	Meteor = {
		DisplayName = "Meteor",
		Input = "Charge",
		Delivery = "Projectile",
		Anchor = "BothHands", -- charged and thrown with both hands
		Damage = 25,
		Cooldown = 4,
		Range = 90,
		Speed = 70,
		ArcHeight = 20, -- lobs up 20 studs, then crashes down onto the target
		BlastRadius = 14, -- explodes on landing
		Charge = { Time = 1.5, MinCharge = 0.3, DamageMultiplier = 1.8, VisualScale = 1.6 },
		VFX = {
			Charge = "Fire/Charge",
			ChargeFull = "Fire/Punch",
			Cast = "Fire/Punch",
			Main = "Fire/Meteor",
			Impact = "Fire/Impact",
			Mark = "Fire/Scorch",
		},
		Shake = { Intensity = 3, Frequency = 30, Duration = 0.7 },
	},

	------------------------------------------------------------ LIGHTNING
	ShockPalm = {
		DisplayName = "Shock Palm",
		Input = "Instant",
		Delivery = "Melee",
		Anchor = "AlternateHands",
		Damage = 10,
		Cooldown = 0.5,
		Range = 7,
		HitboxSize = Vector3.new(5, 5, 7),
		HitDelay = 0.05,
		VFX = { Main = "Lightning/Palm", Impact = "Lightning/Impact" },
		Shake = { Intensity = 0.4, Frequency = 50, Duration = 0.15 },
	},

	LightningBolt = {
		DisplayName = "Lightning Bolt",
		Input = "Charge",
		Delivery = "Beam",
		Damage = 30,
		Cooldown = 2.5,
		Range = 200,
		Charge = { Time = 0.8, MinCharge = 0.2, DamageMultiplier = 2 },
		VFX = {
			Charge = "Lightning/Charge",
			ChargeFull = "Lightning/Zap",
			Cast = "Lightning/Zap",
			Main = "Lightning/Beam",
			Impact = "Lightning/Impact",
			Mark = "Lightning/Scorch",
		},
		Shake = { Intensity = 2.5, Frequency = 60, Duration = 0.4 },
	},

	ThunderStrike = {
		DisplayName = "Thunder Strike",
		Input = "Charge",
		Delivery = "AOE",
		Anchor = "BothHands",
		SkyStrike = true,
		Damage = 35,
		Cooldown = 5,
		Range = 80,
		Radius = 12,
		Charge = { Time = 1, MinCharge = 0.4, DamageMultiplier = 1.5 },
		VFX = {
			Charge = "Lightning/Charge",
			ChargeFull = "Lightning/Zap",
			Main = "Lightning/Bolt",
			Impact = "Lightning/Impact",
			Mark = "Lightning/Scorch",
		},
		Shake = { Intensity = 3.5, Frequency = 55, Duration = 0.5 },
	},
}

return table.freeze(Attacks)
