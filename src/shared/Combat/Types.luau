--!strict
--types for the entire combat system

export type InputMode = "Instant" | "Charge"
export type Delivery = "Projectile" | "Beam" | "AOE" | "Melee"

-- Where on the character an attack starts, and where its kits (Charge, Cast, Melee, Aura) attach
export type Anchor = "RightHand" | "LeftHand" | "BothHands" | "AlternateHands" | "Torso" | "Feet" | "Root"
export type Side = "Left" | "Right" -- which hand, for AlternateHands

export type ShakeProfile = {
	Intensity: number,
	Frequency: number,
	Duration: number,
}

export type ChargeSettings = {
	Time: number, --sec to reach full charge
	MinCharge: number, -- 0 to 1
	DamageMultiplier: number,
	VisualScale: number?,
	MaxHold: number?, -- auto release after (n) seconds
}

export type AttackVFX = {

	Charge: string?,
	ChargeFull: string?, -- burst at the anchor when the charge reaches 100%
	Cast: string?, -- burst at the anchor the moment the attack fires
	Main: string?,
	Impact: string?,
	Mark: string?,
	Hit: string?,
}

export type AttackAnimations = {

	Charge: string?, -- loops while charging
	ChargeLeft: string?, -- AlternateHands: per-hand versions (a missing hand falls back to Charge)
	ChargeRight: string?,
	Fire: string?, -- plays once when the attack goes off. Put a "Hit" marker on the hit frame
	FireLeft: string?, -- AlternateHands: per-hand versions (a missing hand falls back to Fire)
	FireRight: string?,
}

export type AttackConfig = {

	DisplayName: string,
	Input: InputMode,
	Delivery: Delivery,
	Anchor: Anchor?, -- where it comes from (default "RightHand")
	Damage: number,
	Cooldown: number,
	Range: number,
	Charge: ChargeSettings?,
	Speed: number?,
	ArcHeight: number?, -- Projectile: studs the path peaks above a straight line (nil/0 = straight)
	BlastRadius: number?, -- Projectile: explode on landing, damaging everyone in this radius
	Radius: number?,
	HitboxSize: Vector3?,
	HitDelay: number?,
	SkyStrike: boolean?,
	Animations: AttackAnimations?,
	VFX: AttackVFX,
	Shake: ShakeProfile?,
}

export type StyleConfig = {

	DisplayName: string,
	SelectKey: Enum.KeyCode,
	AuraVFX: string?, -- kit that stays on the character while this style is equipped
	AuraAnchor: Anchor?, -- where the aura sits (default "BothHands")
	Binds: { [EnumItem]: string },
}

export type FireData = {

	Origin: Vector3,
	Target: Vector3,
	Charge: number, -- 0 to 1. 1 = instant
	Side: Side?, -- which hand fired it (AlternateHands only)
}

export type ChargeData = {

	Side: Side?, -- which hand is charging (AlternateHands only)
}

export type ImpactData = {

	Position: Vector3,
	Normal: Vector3,
	Part: BasePart?,
	IsCharacter: boolean,
	Splash: boolean, -- caught in an explosion: blood only
}

export type AttackContext = {

	Player: Player,
	Character: Model,
	AttackId: string,
	Attack: AttackConfig,
	Origin: Vector3,
	Target: Vector3,
	Direction: Vector3,
	Distance: number,
	Charge: number,
	Damage: number,
}

export type ServerDelivery = (contex: AttackContext) -> Vector3
export type ClientDelivery = (caster: Player, attack: AttackConfig, data: FireData) -> ()

return {}
