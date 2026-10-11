--!strict
local Settings = {

	DefaultStyle = "Fire",
	StyleAttribute = "CombatStyle",

	MaxOriginDistance = 15, --anti exploit
	MaxAimDistance = 1000, --anti exploit

	DefaultHitVFX = "Common/Blood",
	MarkLifetime = 8,
	MarkFadeTime = 1.5,

	ShakeRadius = 60,

	MaxRequestsPerSecond = 20, --anti exploit: attack requests above this rate are dropped
	AreaLineOfSight = true, -- explosions and melee can't hit through walls

	NoCooldownAttribute = "NoCooldown", -- Player attribute: true = no cooldowns (dev tools, buffs)
	DebugDrawAttribute = "CombatDebugDraw", -- workspace attribute: true = draw hitboxes
}

-- read only so values can only be changed in here

return table.freeze(Settings)
