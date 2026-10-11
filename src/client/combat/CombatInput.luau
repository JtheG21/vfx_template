--!strict
--[[
	CombatInput
	Turns key presses into attack requests:
	  - style keys (each style's SelectKey, e.g. Z and X) switch style
	  - "Instant" attacks fire on press
	  - "Charge" attacks start charging on press and fire on release (or at MaxHold)

	Cooldowns here exist only so the client doesn't spam the server.
	The server keeps the real cooldowns and ignores anything early.
	Animations are handled by AttackAnimations.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Combat = ReplicatedStorage:WaitForChild("Combat")
local Types = require(Combat.Types)
local Settings = require(Combat.Settings)
local Attacks = require(Combat.Attacks)
local Styles = require(Combat.Styles)
local Remotes = require(Combat.Remotes)
local CharacterUtil = require(Combat.Shared.CharacterUtil)
local Anchors = require(Combat.Shared.Anchors)
local VFXUtil = require(script.Parent:WaitForChild("VFX"):WaitForChild("VFXUtil"))
local AttackAnimations = require(script.Parent:WaitForChild("AttackAnimations"))

-- Must stay well below Settings.MaxAimDistance. The camera sits behind the
-- player, so the aim point is further from the hand than from the camera.
local AIM_DISTANCE = 500

local player = Players.LocalPlayer

type ChargeState = {
	AttackId: string,
	Attack: Types.AttackConfig,
	Bind: EnumItem, -- the key/button being held, so we know which release ends it
	StartTime: number,
	Side: Types.Side?, -- the hand this charge is in (AlternateHands only)
}

local charging: ChargeState? = nil
local chargeToken = 0
local readyAt: { [string]: number } = {}
local lastSide: { [string]: Types.Side } = {} -- attackId -> hand used last time (AlternateHands)

--------------------------------------------------------------- HELPERS

local function getCurrentStyle(): Types.StyleConfig?
	local styleName = player:GetAttribute(Settings.StyleAttribute)
	if typeof(styleName) == "string" then
		return Styles[styleName]
	end
	return nil
end

-- Where the mouse points in the 3D world, ignoring yourself and on-screen effects.
-- Better than Mouse.Hit, which can only ignore ONE instance and hits your own VFX.
local function getAimPosition(character: Model): Vector3
	local camera = workspace.CurrentCamera
	local mouse = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, VFXUtil.Container }

	local result = workspace:Raycast(ray.Origin, ray.Direction * AIM_DISTANCE, params)
	return if result then result.Position else ray.Origin + ray.Direction * AIM_DISTANCE
end

-- AlternateHands attacks switch hands every use. Every other anchor returns nil (no side).
local function pickSide(attackId: string, attack: Types.AttackConfig): Types.Side?
	-- Annotated: without it Luau widens "Left"/"Right" to plain `string`
	local side: Types.Side? = Anchors.nextSide(attack.Anchor, lastSide[attackId])
	if side then
		lastSide[attackId] = side
	end
	return side
end

---------------------------------------------------------------- ACTIONS

local function sendAttack(
	action: "Fire" | "Release",
	attackId: string,
	attack: Types.AttackConfig,
	side: Types.Side?,
	startCooldown: boolean
)
	local character = player.Character
	if not character then
		return
	end
	if startCooldown then
		readyAt[attackId] = os.clock() + attack.Cooldown
		AttackAnimations.play(attack, "Fire", side)
	end
	-- The attack starts at its Anchor (a hand, both hands, the feet...)
	local origin = Anchors.getOrigin(character, attack.Anchor, side)
	Remotes.AttackRequest:FireServer(action, attackId, origin, getAimPosition(character), side)
end

local function releaseCharge()
	local current = charging
	if not current then
		return
	end
	charging = nil

	AttackAnimations.stop("Charge")

	-- Copy the server's fizzle rule, so the client doesn't start a cooldown the server won't.
	-- We still send the release either way, because the server has to end the charge too.
	local chargeSettings = current.Attack.Charge
	local held = os.clock() - current.StartTime
	local fizzled = chargeSettings ~= nil and held / chargeSettings.Time < chargeSettings.MinCharge

	sendAttack("Release", current.AttackId, current.Attack, current.Side, not fizzled)
end

local function startCharge(attackId: string, attack: Types.AttackConfig, bind: EnumItem)
	-- Version token again: tells a stale MaxHold timer that its charge is over
	chargeToken += 1
	local token = chargeToken

	local side: Types.Side? = pickSide(attackId, attack)
	charging = { AttackId = attackId, Attack = attack, Bind = bind, StartTime = os.clock(), Side = side }
	Remotes.AttackRequest:FireServer("Begin", attackId, side)

	AttackAnimations.play(attack, "Charge", side)

	local maxHold = attack.Charge and attack.Charge.MaxHold
	if maxHold then
		task.delay(maxHold, function()
			if charging and chargeToken == token then
				releaseCharge()
			end
		end)
	end
end

------------------------------------------------------------------ INPUT

player.CharacterAdded:Connect(function()
	-- Any charge died with your old character (AttackAnimations resets its own tracks)
	charging = nil
end)

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	-- gameProcessed = Roblox already used this input (typing in chat, clicking a GUI button)
	if gameProcessed then
		return
	end

	-- Style switching
	for styleName, style in Styles do
		if input.KeyCode == style.SelectKey then
			if not charging then
				Remotes.AttackRequest:FireServer("SetStyle", styleName)
			end
			return
		end
	end

	if charging or not CharacterUtil.getAliveHumanoid(player.Character) then
		return
	end

	local style = getCurrentStyle()
	if not style then
		return
	end

	-- Keyboard keys are matched by KeyCode; mouse buttons by UserInputType
	-- (a mouse click's KeyCode is always Enum.KeyCode.Unknown).
	local bind: EnumItem = if style.Binds[input.KeyCode] then input.KeyCode else input.UserInputType
	local attackId = style.Binds[bind]
	if not attackId then
		return
	end
	local attack = Attacks[attackId]
	if not attack then
		return
	end
	local ignoresCooldown = player:GetAttribute(Settings.NoCooldownAttribute) == true
	if not ignoresCooldown and os.clock() < (readyAt[attackId] or 0) then
		return
	end

	if attack.Input == "Charge" then
		startCharge(attackId, attack, bind)
	else
		sendAttack("Fire", attackId, attack, pickSide(attackId, attack), true)
	end
end)

UserInputService.InputEnded:Connect(function(input: InputObject)
	local current = charging
	if current and (input.KeyCode == current.Bind or input.UserInputType == current.Bind) then
		releaseCharge()
	end
end)
