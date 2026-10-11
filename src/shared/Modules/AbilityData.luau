--!strict
export type VFXType = "Projectile" | "InstantBeam" | "PointAOE" | "MeleeSweep"

export type AbilityConfig = {
	Name: string,
	TemplateName: string,
	VFXType: VFXType,
	Speed: number?,
	MaxDistance: number?,
	Damage: number,
	Cooldown: number,
	TrajectoryType: "Linear" | "Bezier"?,
	CurveOffset: Vector3?,
	Radius: number?,
	AnimationId: string?, -- Used for programmatic Bezier curves (e.g., arching shots)
	ShakeProfile: {
		Intensity: number,
		Frequency: number,
		Duration: number,
	},
}

local AbilityData = {
	["Fireball"] = {
		Name = "Fireball",
		TemplateName = "Fireball",
		VFXType = "Projectile",
		Speed = 100,
		MaxDistance = 100,
		Damage = 25,
		Cooldown = 0.5,
		TrajectoryType = "Linear",
		ShakeProfile = { Intensity = 1.0, Frequency = 40, Duration = 0.4 },
	},

	["MeteorShot"] = {
		Name = "Meteor Shot",
		TemplateName = "Meteor",
		VFXType = "Projectile", -- Moves over time
		Speed = 150,
		MaxDistance = 120,
		Damage = 25,
		Cooldown = 0.5,
		TrajectoryType = "Linear",
		ShakeProfile = { Intensity = 1.2, Frequency = 45, Duration = 0.6 },
	},
	["LightningBolt"] = {
		Name = "Lightning Bolt",
		TemplateName = "Lightning",
		VFXType = "InstantBeam", -- Instant line raycast
		MaxDistance = 200,
		Damage = 50,
		Cooldown = 3.0,
		ShakeProfile = { Intensity = 3.0, Frequency = 60, Duration = 0.4 },
	},

	["LightningStrike"] = {
		Name = "Sky Lightning",
		TemplateName = "Lightning",
		VFXType = "PointAOE", -- Logic is an explosion radius on the ground where clicked
		Radius = 15,
		Damage = 35,
		Cooldown = 1.5,
		ShakeProfile = { Intensity = 3.5, Frequency = 55, Duration = 0.5 },
	},

	["SwordSlash"] = {
		Name = "Katana Slash",
		TemplateName = "Fireball",
		VFXType = "MeleeSweep", -- Driven by character animation frames
		AnimationId = "rbxassetid://123456789", -- Your custom swinging animation asset
		Damage = 20,
		Cooldown = 0.8,
		ShakeProfile = { Intensity = 0.5, Frequency = 20, Duration = 0.2 },
	},

	["GroundSlam"] = {
		Name = "Earthquake Slam",
		TemplateName = "Meteor",
		VFXType = "PointAOE", -- Instant circle radius check
		Radius = 25,
		Damage = 35,
		Cooldown = 2.5,
		ShakeProfile = { Intensity = 4.5, Frequency = 25, Duration = 0.8 },
	},
}

return AbilityData
