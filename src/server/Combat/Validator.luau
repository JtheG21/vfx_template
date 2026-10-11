--!strict
--[[
	Validator
	Checks every attack, style, key binding and VFX template ONCE when the server
	starts, and prints a single report to the Output. Problems show up the moment
	you press Play, not 10 minutes later when you happen to use the broken attack.

	  ERROR    something is wrong and will misbehave: bad numbers, an unknown attack,
	           a template that can't be used the way the attack uses it
	  WARNING  works, but probably isn't what you meant: missing VFX, a typo'd field
	           name, an attack no key can reach

	If you add a new field to a config type in Types, add it to the matching
	*_FIELDS list below too, or the validator will flag it as a typo.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Combat = ReplicatedStorage.Combat
local Types = require(Combat.Types)
local Settings = require(Combat.Settings)
local Attacks = require(Combat.Attacks)
local Styles = require(Combat.Styles)
local Anchors = require(Combat.Shared.Anchors)

-- How a template is USED decides what it must contain
type Usage = "Kit" | "Burst" | "Mover" | "Placed" | "BeamStyle" | "Mark"

type Report = {
	Errors: { string },
	Warnings: { string },
	Checked: { [string]: boolean }, -- "path|usage" already checked, so shared templates report once
}

-- PATTERN: a "set" built from a list, for fast "is this allowed?" lookups
local function set(list: { string }): { [string]: boolean }
	local result = {}
	for _, item in list do
		result[item] = true
	end
	return result
end

local ATTACK_FIELDS = set({
	"DisplayName",
	"Input",
	"Delivery",
	"Anchor",
	"Damage",
	"Cooldown",
	"Range",
	"Charge",
	"Speed",
	"ArcHeight",
	"BlastRadius",
	"Radius",
	"HitboxSize",
	"HitDelay",
	"SkyStrike",
	"Animations",
	"VFX",
	"Shake",
})
local CHARGE_FIELDS = set({ "Time", "MinCharge", "DamageMultiplier", "VisualScale", "MaxHold" })
local VFX_FIELDS = set({ "Charge", "ChargeFull", "Cast", "Main", "Impact", "Mark", "Hit" })
local ANIMATION_FIELDS = set({ "Charge", "ChargeLeft", "ChargeRight", "Fire", "FireLeft", "FireRight" })
local SHAKE_FIELDS = set({ "Intensity", "Frequency", "Duration" })
local STYLE_FIELDS = set({ "DisplayName", "SelectKey", "AuraVFX", "AuraAnchor", "Binds" })

-- What the attack's Main template is used as, per delivery
local MAIN_USAGE: { [string]: Usage } = {
	Projectile = "Mover",
	Beam = "BeamStyle",
	AOE = "Placed",
	Melee = "Kit",
}

-- Fields that only mean something for some deliveries
local DELIVERY_ONLY: { [string]: { [string]: boolean } } = {
	Speed = set({ "Projectile" }),
	ArcHeight = set({ "Projectile" }),
	BlastRadius = set({ "Projectile" }),
	Radius = set({ "AOE" }),
	SkyStrike = set({ "AOE" }),
	HitboxSize = set({ "Melee" }),
	HitDelay = set({ "Melee", "AOE" }),
}

local Validator = {}

---------------------------------------------------------------- HELPERS

local function addError(report: Report, message: string)
	table.insert(report.Errors, message)
end

local function addWarning(report: Report, message: string)
	table.insert(report.Warnings, message)
end

local function expect(report: Report, condition: boolean, message: string)
	if not condition then
		addError(report, message)
	end
end

-- Flags keys that aren't in `allowed`. A misspelled field is otherwise silently ignored.
local function checkFields(report: Report, where: string, tbl: any, allowed: { [string]: boolean })
	for key in tbl do
		if not allowed[key] then
			addWarning(report, `{where}.{tostring(key)} isn't a known field (typo?), so it's ignored`)
		end
	end
end

local function findTemplate(templates: Instance, path: string): Instance?
	local current: Instance? = templates
	for _, name in string.split(path, "/") do
		if not current then
			break
		end
		current = current:FindFirstChild(name)
	end
	return current
end

-- True if `root` or anything inside it passes `predicate`
local function contains(root: Instance, predicate: (Instance) -> boolean): boolean
	if predicate(root) then
		return true
	end
	for _, descendant in root:GetDescendants() do
		if predicate(descendant) then
			return true
		end
	end
	return false
end

local function isPlayable(instance: Instance): boolean
	return instance:IsA("ParticleEmitter") or instance:IsA("Light") or instance:IsA("Sound")
end

---------------------------------------------------------------- TEMPLATES

local function checkTemplate(report: Report, where: string, path: string?, usage: Usage, templates: Instance?)
	if path == nil or templates == nil then
		return
	end
	if typeof(path) ~= "string" or path == "" then
		addError(report, `{where} must be a path like "Fire/Impact"`)
		return
	end
	-- One template can be used by several attacks; report its problems only once
	local key = `{path}|{usage}`
	if report.Checked[key] then
		return
	end
	report.Checked[key] = true

	local template = findTemplate(templates, path)
	if not template then
		addWarning(report, `{where}: no template at VFXTemplates/{path}, so this effect is skipped`)
		return
	end
	local label = `{where} ("{path}")`

	if usage ~= "Kit" and not template:IsA("PVInstance") then
		addError(
			report,
			`{label} must be a Model or Part so it can be placed in the world (it's a {template.ClassName})`
		)
		return
	end

	if usage == "Kit" or usage == "Burst" then
		if not contains(template, isPlayable) then
			addWarning(report, `{label} has no particles, lights or sounds, so nothing will show`)
		end
	end
	if usage == "Kit" then
		if contains(template, function(i)
			return i:IsA("Beam") or i:IsA("Trail")
		end) then
			addWarning(
				report,
				`{label}: Beams and Trails in kits are skipped (they need two attachments that can't follow the character)`
			)
		end
	elseif usage == "Burst" then
		if contains(template, function(i)
			return i:IsA("Sound") and i.Looped
		end) then
			addWarning(report, `{label} has a looped Sound; bursts end when their particles do, which cuts it off`)
		end
	elseif usage == "Mover" or usage == "Placed" then
		if not contains(template, function(i)
			return i:IsA("BasePart")
		end) then
			addError(report, `{label} has no parts to position`)
		end
	elseif usage == "BeamStyle" then
		if not contains(template, function(i)
			return i:IsA("Beam")
		end) then
			addError(report, `{label} needs at least one Beam (its look is copied onto every bolt segment)`)
		end
		if not contains(template, function(i)
			return i:IsA("BasePart")
		end) then
			addError(report, `{label} needs a Part to hold the bolt's attachments`)
		end
	elseif usage == "Mark" then
		if not contains(template, function(i)
			return i:IsA("FaceInstance")
		end) then
			addError(report, `{label} needs a Decal or Texture (that's the mark itself)`)
		end
	end

	-- Sounds are positional only inside a Part or Attachment
	for _, descendant in template:GetDescendants() do
		if descendant:IsA("Sound") then
			local parent = descendant.Parent
			if not (parent and (parent:IsA("BasePart") or parent:IsA("Attachment"))) then
				addWarning(
					report,
					`{label}: Sound "{descendant.Name}" isn't inside a Part or Attachment, so it plays at full volume everywhere`
				)
			end
			if descendant.SoundId == "" then
				addWarning(report, `{label}: Sound "{descendant.Name}" has no SoundId`)
			end
			local maxDuration = descendant:GetAttribute("MaxDuration")
			if maxDuration ~= nil and not (typeof(maxDuration) == "number" and maxDuration > 0) then
				addWarning(report, `{label}: Sound "{descendant.Name}" MaxDuration must be a number above 0`)
			end
		end
	end
end

------------------------------------------------------------------ ATTACKS

local function checkAttack(report: Report, id: string, attack: Types.AttackConfig, templates: Instance?)
	local where = `Attacks.{id}`
	checkFields(report, where, attack, ATTACK_FIELDS)

	-- `not (x >= 0)` style on purpose: it also catches NaN
	expect(report, typeof(attack.DisplayName) == "string", `{where}.DisplayName must be a string`)
	expect(report, attack.Damage >= 0, `{where}.Damage must be 0 or more`)
	expect(report, attack.Cooldown >= 0, `{where}.Cooldown must be 0 or more`)
	expect(report, attack.Range > 0, `{where}.Range must be more than 0`)
	if attack.Anchor ~= nil then
		expect(
			report,
			Anchors.isAnchor(attack.Anchor),
			`{where}.Anchor "{tostring(attack.Anchor)}" isn't a valid anchor`
		)
	end

	-- Input and charging
	local vfx = attack.VFX
	if attack.Input == "Charge" then
		local charge = attack.Charge
		if not charge then
			addError(report, `{where}: Input is "Charge" but there's no Charge table`)
		else
			checkFields(report, `{where}.Charge`, charge, CHARGE_FIELDS)
			expect(report, charge.Time > 0, `{where}.Charge.Time must be more than 0`)
			expect(
				report,
				charge.MinCharge >= 0 and charge.MinCharge <= 1,
				`{where}.Charge.MinCharge must be between 0 and 1`
			)
			expect(report, charge.DamageMultiplier >= 0, `{where}.Charge.DamageMultiplier must be 0 or more`)
			if charge.VisualScale ~= nil then
				expect(report, charge.VisualScale > 0, `{where}.Charge.VisualScale must be more than 0`)
			end
			if charge.MaxHold ~= nil then
				expect(report, charge.MaxHold > 0, `{where}.Charge.MaxHold must be more than 0`)
			end
		end
	elseif attack.Input == "Instant" then
		if attack.Charge then
			addWarning(report, `{where} has Charge settings but Input is "Instant", so they're ignored`)
		end
		if vfx and (vfx.Charge or vfx.ChargeFull) then
			addWarning(report, `{where}: VFX.Charge / VFX.ChargeFull never play on an "Instant" attack`)
		end
	else
		addError(report, `{where}.Input must be "Instant" or "Charge"`)
	end

	-- Delivery and the fields that belong to it
	-- Annotated: without it Luau widens the value to plain `string` and loses the Usage type
	local mainUsage: Usage? = MAIN_USAGE[attack.Delivery]
	if not mainUsage then
		addError(report, `{where}.Delivery "{tostring(attack.Delivery)}" isn't one of Projectile, Beam, AOE, Melee`)
	else
		-- Only once the delivery is valid: otherwise every field would be flagged on top of the real error
		for field, deliveries in DELIVERY_ONLY do
			if (attack :: any)[field] ~= nil and not deliveries[attack.Delivery] then
				addWarning(report, `{where}.{field} doesn't apply to {attack.Delivery} attacks, so it's ignored`)
			end
		end
	end
	if attack.Speed ~= nil then
		expect(report, attack.Speed > 0, `{where}.Speed must be more than 0`)
	end
	if attack.ArcHeight ~= nil then
		expect(report, attack.ArcHeight >= 0, `{where}.ArcHeight must be 0 or more`)
	end
	if attack.BlastRadius ~= nil then
		expect(report, attack.BlastRadius > 0, `{where}.BlastRadius must be more than 0`)
	end
	if attack.Radius ~= nil then
		expect(report, attack.Radius > 0, `{where}.Radius must be more than 0`)
	end
	if attack.HitDelay ~= nil then
		expect(report, attack.HitDelay >= 0, `{where}.HitDelay must be 0 or more`)
	end
	local size = attack.HitboxSize
	if size ~= nil then
		expect(report, size.X > 0 and size.Y > 0 and size.Z > 0, `{where}.HitboxSize must be positive on every axis`)
	end

	-- Feel
	local shake = attack.Shake
	if shake then
		checkFields(report, `{where}.Shake`, shake, SHAKE_FIELDS)
		expect(
			report,
			shake.Intensity >= 0 and shake.Frequency > 0 and shake.Duration > 0,
			`{where}.Shake needs Intensity >= 0, Frequency > 0 and Duration > 0`
		)
	end
	local animations = attack.Animations
	if animations then
		checkFields(report, `{where}.Animations`, animations, ANIMATION_FIELDS)
		for name, animationId in animations :: any do
			if typeof(animationId) ~= "string" or not string.match(animationId, "^rbxassetid://%d+$") then
				addWarning(report, `{where}.Animations.{name} should look like "rbxassetid://123456789"`)
			end
		end

		-- Per-hand versions. (any) so the slot names can be built from strings.
		local slots = animations :: any
		for _, slot in { "Charge", "Fire" } do
			local left, right = slots[slot .. "Left"], slots[slot .. "Right"]
			if (left or right) and attack.Anchor ~= "AlternateHands" then
				addWarning(
					report,
					`{where}.Animations.{slot}Left/{slot}Right only play for Anchor = "AlternateHands" (use {slot})`
				)
			elseif (left == nil) ~= (right == nil) and slots[slot] == nil then
				local missing = if left == nil then "Left" else "Right"
				addWarning(
					report,
					`{where}.Animations has no {slot}{missing} and no plain {slot} to fall back on, so that hand has no animation`
				)
			end
		end
		if attack.Input == "Instant" and (slots.Charge or slots.ChargeLeft or slots.ChargeRight) then
			addWarning(report, `{where}: Charge animations never play on an "Instant" attack`)
		end
	end

	-- Templates
	if typeof(vfx) ~= "table" then
		addError(report, `{where}.VFX is missing (an attack with no visuals still needs an empty VFX table)`)
		return
	end
	checkFields(report, `{where}.VFX`, vfx, VFX_FIELDS)
	if not vfx.Main then
		addWarning(report, `{where} has no VFX.Main, so the attack itself is invisible`)
	end
	checkTemplate(report, `{where}.VFX.Charge`, vfx.Charge, "Kit", templates)
	checkTemplate(report, `{where}.VFX.ChargeFull`, vfx.ChargeFull, "Kit", templates)
	checkTemplate(report, `{where}.VFX.Cast`, vfx.Cast, "Kit", templates)
	if mainUsage then
		checkTemplate(report, `{where}.VFX.Main`, vfx.Main, mainUsage, templates)
	end
	checkTemplate(report, `{where}.VFX.Impact`, vfx.Impact, "Burst", templates)
	checkTemplate(report, `{where}.VFX.Hit`, vfx.Hit, "Burst", templates)
	checkTemplate(report, `{where}.VFX.Mark`, vfx.Mark, "Mark", templates)
end

------------------------------------------------------------------- STYLES

local function checkStyles(report: Report, templates: Instance?)
	local selectKeys: { [EnumItem]: string } = {}
	local bound: { [string]: boolean } = {}

	for name, style in Styles do
		local where = `Styles.{name}`
		checkFields(report, where, style, STYLE_FIELDS)

		local owner = selectKeys[style.SelectKey]
		if owner then
			addError(report, `{where}.SelectKey {style.SelectKey.Name} is already Styles.{owner}'s key`)
		else
			selectKeys[style.SelectKey] = name
		end
		if style.AuraAnchor ~= nil then
			expect(
				report,
				Anchors.isAnchor(style.AuraAnchor),
				`{where}.AuraAnchor "{tostring(style.AuraAnchor)}" isn't a valid anchor`
			)
		end
		checkTemplate(report, `{where}.AuraVFX`, style.AuraVFX, "Kit", templates)

		for key, attackId in style.Binds do
			if Attacks[attackId] then
				bound[attackId] = true
			else
				addError(report, `{where}.Binds[{key.Name}] = "{attackId}", but there's no attack with that id`)
			end
		end
	end

	-- A style's select key wins over attack binds, so an attack bound to one can never fire
	for name, style in Styles do
		for key, attackId in style.Binds do
			local selects = selectKeys[key]
			if selects then
				addError(
					report,
					`Styles.{name}: {key.Name} is bound to "{attackId}" but also selects Styles.{selects}, so the attack can never fire`
				)
			end
		end
	end

	expect(
		report,
		Styles[Settings.DefaultStyle] ~= nil,
		`Settings.DefaultStyle "{Settings.DefaultStyle}" isn't a style in Styles`
	)

	for id in Attacks do
		if not bound[id] then
			addWarning(report, `Attacks.{id} isn't bound to a key in any style, so players can't use it`)
		end
	end
end

--------------------------------------------------------------------- RUN

function Validator.run(): Report
	local report: Report = { Errors = {}, Warnings = {}, Checked = {} }

	local templates = ReplicatedStorage:FindFirstChild("VFXTemplates")
	if not templates then
		addError(report, "ReplicatedStorage.VFXTemplates is missing, so no effects can play")
	end

	-- Sorted, so the report lists attacks in the same order every run
	local ids = {}
	for id in Attacks do
		table.insert(ids, id)
	end
	table.sort(ids)

	for _, id in ids do
		-- pcall: one badly broken entry (e.g. Damage = "ten") can't stop the rest being checked
		local ok, problem = pcall(function()
			checkAttack(report, id, Attacks[id], templates)
		end)
		if not ok then
			addError(report, `Attacks.{id} couldn't be checked: {problem}`)
		end
	end
	local ok, problem = pcall(function()
		checkStyles(report, templates)
	end)
	if not ok then
		addError(report, `Styles couldn't be checked: {problem}`)
	end
	checkTemplate(report, "Settings.DefaultHitVFX", Settings.DefaultHitVFX, "Burst", templates)

	if #report.Errors == 0 and #report.Warnings == 0 then
		print(`[Combat] Validated {#ids} attacks: no problems found`)
		return report
	end

	local lines = { `[Combat] Validation: {#report.Errors} error(s), {#report.Warnings} warning(s)` }
	for _, message in report.Errors do
		table.insert(lines, `  ERROR    {message}`)
	end
	for _, message in report.Warnings do
		table.insert(lines, `  WARNING  {message}`)
	end
	warn(table.concat(lines, "\n"))
	return report
end

return Validator
