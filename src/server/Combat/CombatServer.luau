--!strict
--[[
	CombatServer
	Entry point on the server. It:
	  1. receives requests from clients
	  2. validates them (alive? right style? off cooldown? sane positions?)
	  3. tracks charging
	  4. hands the attack to its Delivery module, then tells every client to play it

	It never does hit detection itself. That is each Delivery's job.

	Request protocol (client -> server, via Remotes.AttackRequest):
	  "SetStyle", styleName
	  "Begin",    attackId, side?                 start charging
	  "Release",  attackId, origin, aim, side?    fire a charged attack
	  "Fire",     attackId, origin, aim, side?    fire an instant attack
	`side` is "Left"/"Right" for AlternateHands attacks, nil otherwise.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Combat = ReplicatedStorage.Combat
local Types = require(Combat.Types)
local Settings = require(Combat.Settings)
local Attacks = require(Combat.Attacks)
local Styles = require(Combat.Styles)
local Remotes = require(Combat.Remotes)
local CharacterUtil = require(Combat.Shared.CharacterUtil)
local Anchors = require(Combat.Shared.Anchors)
local Validator = require(script.Parent.Validator)

-- Check every attack, style and template once, and print one report.
-- task.spawn so a slow check can never delay combat from starting.
task.spawn(Validator.run)

------------------------------------------------------------------ SETUP

-- Auto-register every module in the Deliveries folder, keyed by its name.
-- Adding a new delivery type = drop in a ModuleScript. No edits needed here.
local Deliveries: { [string]: Types.ServerDelivery } = {}
for _, module in script.Parent.Deliveries:GetChildren() do
	if module:IsA("ModuleScript") then
		-- require() of an instance found at runtime has an unknown type, so cast it
		Deliveries[module.Name] = (require :: any)(module)
	end
end

-- Pre-compute which attacks each style is allowed to use, as a set:
-- styleAttacks.Fire.Fireball == true. Lookups are then instant.
local styleAttacks: { [string]: { [string]: boolean } } = {}
for styleName, style in Styles do
	local allowed = {}
	for _, attackId in style.Binds do
		allowed[attackId] = true
	end
	styleAttacks[styleName] = allowed
end

------------------------------------------------------------ PLAYER STATE

type ChargeState = {
	AttackId: string,
	StartTime: number,
	Side: Types.Side?,
}

type PlayerState = {
	ReadyAt: { [string]: number }, -- attackId -> os.clock() time when it's usable again
	Charging: ChargeState?,
	-- Rate limiting: how many requests arrived in the current 1-second window
	WindowStart: number,
	RequestCount: number,
}

local playerStates: { [Player]: PlayerState } = {}

local function onPlayerAdded(player: Player)
	local state: PlayerState = { ReadyAt = {}, Charging = nil, WindowStart = 0, RequestCount = 0 }
	playerStates[player] = state
	player:SetAttribute(Settings.StyleAttribute, Settings.DefaultStyle)

	-- Respawning cancels any charge that was in progress, and tells clients to clear its VFX
	player.CharacterAdded:Connect(function()
		local charging = state.Charging
		if charging then
			state.Charging = nil
			Remotes.AttackReplicate:FireAllClients("ChargeEnd", player, charging.AttackId)
		end
	end)
end

Players.PlayerAdded:Connect(onPlayerAdded)
-- Players who joined before this script ran (happens in Studio) would be missed otherwise
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end

Players.PlayerRemoving:Connect(function(player)
	playerStates[player] = nil -- clean up, or the table keeps growing forever (memory leak)
end)

------------------------------------------------------------- VALIDATION

-- Returns the attack config if this player may use it right now, otherwise nil.
local function getUsableAttack(player: Player, state: PlayerState, attackId: string): Types.AttackConfig?
	local attack = Attacks[attackId]
	if not attack then
		return nil
	end

	-- Attributes can hold any type, so check it really is a string before using it as a key
	local styleName = player:GetAttribute(Settings.StyleAttribute)
	if typeof(styleName) ~= "string" then
		return nil
	end
	local allowed = styleAttacks[styleName]
	if not (allowed and allowed[attackId]) then
		return nil -- not bound in the player's current style (a client asking for it is exploiting)
	end

	-- `or 0` = "never used yet, so it's ready". The NoCooldown attribute can only be set by
	-- the server (attributes a client sets never replicate), so a client can't grant it to itself.
	local ignoresCooldown = player:GetAttribute(Settings.NoCooldownAttribute) == true
	if not ignoresCooldown and os.clock() < (state.ReadyAt[attackId] or 0) then
		return nil
	end

	if not CharacterUtil.getAliveHumanoid(player.Character) then
		return nil
	end

	return attack
end

------------------------------------------------------------- EXECUTION

local function executeAttack(
	player: Player,
	state: PlayerState,
	attackId: string,
	attack: Types.AttackConfig,
	origin: Vector3,
	aim: Vector3,
	charge: number,
	side: Types.Side?
)
	local character = player.Character
	if not character then
		return
	end
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not (rootPart and rootPart:IsA("BasePart")) then
		return
	end

	-- Written as `not (x <= max)` on purpose. An exploiter can send NaN, and EVERY
	-- comparison with NaN is false. `x > max` would let NaN through; `not (x <= max)` blocks it.
	if not ((origin - rootPart.Position).Magnitude <= Settings.MaxOriginDistance) then
		return
	end

	local offset = aim - origin
	local length = offset.Magnitude
	if not (length >= 0.1 and length <= Settings.MaxAimDistance) then
		return -- too close (.Unit would be NaN), too far, NaN or infinity
	end
	local direction = offset.Unit
	local distance = math.min(length, attack.Range)

	local delivery = Deliveries[attack.Delivery]
	if not delivery then
		warn(`[Combat] No server delivery module named "{attack.Delivery}"`)
		return
	end

	state.ReadyAt[attackId] = os.clock() + attack.Cooldown

	-- Linear interpolation (lerp): a + (b - a) * t
	-- charge 0 -> 1x damage, charge 1 -> DamageMultiplier x damage, smooth in between
	local multiplier = 1
	if attack.Charge then
		multiplier = 1 + (attack.Charge.DamageMultiplier - 1) * charge
	end

	local context: Types.AttackContext = {
		Player = player,
		Character = character,
		AttackId = attackId,
		Attack = attack,
		Origin = origin,
		Target = origin + direction * distance,
		Direction = direction,
		Distance = distance,
		Charge = charge,
		Damage = attack.Damage * multiplier,
	}

	local endPosition = delivery(context)

	local fireData: Types.FireData = { Origin = origin, Target = endPosition, Charge = charge, Side = side }
	Remotes.AttackReplicate:FireAllClients("Fire", player, attackId, fireData)
end

-------------------------------------------------------- REQUEST HANDLERS

local function onSetStyle(player: Player, state: PlayerState, styleName: string)
	if state.Charging or not Styles[styleName] then
		return
	end
	-- Attributes replicate to every client automatically. That's how other
	-- players' clients know which aura to show on this player.
	player:SetAttribute(Settings.StyleAttribute, styleName)
end

-- Only AlternateHands attacks use a side; for everything else it's dropped
local function sideFor(attack: Types.AttackConfig, side: Types.Side?): Types.Side?
	return if attack.Anchor == "AlternateHands" then side else nil
end

local function onBegin(player: Player, state: PlayerState, attackId: string, side: Types.Side?)
	if state.Charging then
		return -- already charging something
	end
	local attack = getUsableAttack(player, state, attackId)
	if not attack or attack.Input ~= "Charge" then
		return
	end
	-- The SERVER's clock times the charge. A client can't fake a full charge.
	local chargeSide: Types.Side? = sideFor(attack, side)
	state.Charging = { AttackId = attackId, StartTime = os.clock(), Side = chargeSide }
	local chargeData: Types.ChargeData = { Side = chargeSide }
	Remotes.AttackReplicate:FireAllClients("ChargeStart", player, attackId, chargeData)
end

local function onRelease(player: Player, state: PlayerState, attackId: string, origin: Vector3, aim: Vector3)
	local charging = state.Charging
	if not charging or charging.AttackId ~= attackId then
		return
	end
	state.Charging = nil
	Remotes.AttackReplicate:FireAllClients("ChargeEnd", player, attackId)

	local attack = getUsableAttack(player, state, attackId)
	if not (attack and attack.Charge) then
		return
	end

	-- math.clamp(x, min, max) keeps x between min and max
	local charge = math.clamp((os.clock() - charging.StartTime) / attack.Charge.Time, 0, 1)
	if charge < attack.Charge.MinCharge then
		return -- released too early: fizzle
	end

	-- The hand is the one chosen when charging began, not whatever the release claims
	executeAttack(player, state, attackId, attack, origin, aim, charge, charging.Side)
end

local function onFire(
	player: Player,
	state: PlayerState,
	attackId: string,
	origin: Vector3,
	aim: Vector3,
	side: Types.Side?
)
	local attack = getUsableAttack(player, state, attackId)
	if not attack or attack.Input ~= "Instant" then
		return
	end
	executeAttack(player, state, attackId, attack, origin, aim, 1, sideFor(attack, side))
end

-- Fixed 1-second window: once a player sends more than MaxRequestsPerSecond requests
-- in one window, the rest are dropped until the next window. Legit play never gets
-- close (even mashing keys), but a script spamming the remote can't flood the server.
local function allowRequest(state: PlayerState): boolean
	local now = os.clock()
	if now - state.WindowStart >= 1 then
		state.WindowStart = now
		state.RequestCount = 0
	end
	state.RequestCount += 1
	return state.RequestCount <= Settings.MaxRequestsPerSecond
end

-- NEVER trust remote arguments. A client can send anything: wrong types, nil, huge numbers.
-- Typing them as `unknown` forces a `typeof` check before they can be used.
Remotes.AttackRequest.OnServerEvent:Connect(
	function(player: Player, action: unknown, name: unknown, arg3: unknown, arg4: unknown, arg5: unknown)
		local state = playerStates[player]
		if not state or not allowRequest(state) then
			return
		end
		if typeof(action) ~= "string" or typeof(name) ~= "string" then
			return
		end

		if action == "SetStyle" then
			onSetStyle(player, state, name)
		elseif action == "Begin" then
			-- `:: Types.Side` is safe here: Anchors.isSide just proved it's "Left" or "Right"
			onBegin(player, state, name, if Anchors.isSide(arg3) then arg3 :: Types.Side else nil)
		elseif typeof(arg3) == "Vector3" and typeof(arg4) == "Vector3" then
			if action == "Release" then
				onRelease(player, state, name, arg3, arg4)
			elseif action == "Fire" then
				onFire(player, state, name, arg3, arg4, if Anchors.isSide(arg5) then arg5 :: Types.Side else nil)
			end
		end
	end
)
