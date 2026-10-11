--!strict
--[[
	CombatVFX
	Listens to the server and plays every visual and sound: charge-ups, cast flashes,
	attacks, impacts, and the auras of every player. Contains no game logic.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- WaitForChild on the client: things in ReplicatedStorage may still be loading when this runs.
-- A folder replicates together with everything inside it, so its children can be
-- indexed directly once the folder itself exists.
local Combat = ReplicatedStorage:WaitForChild("Combat")
local Types = require(Combat.Types)
local Attacks = require(Combat.Attacks)
local Remotes = require(Combat.Remotes)
local Anchors = require(Combat.Shared.Anchors)
local AttackAnimations = require(script.Parent:WaitForChild("AttackAnimations"))

local VFX = script.Parent:WaitForChild("VFX")
local VFXUtil = require(VFX.VFXUtil)
local Charge = require(VFX.Charge)
local Impact = require(VFX.Impact)
local Aura = require(VFX.Aura)

-- Auto-register every module in VFX/Deliveries by name (same trick as the server)
local DeliveryVFX: { [string]: Types.ClientDelivery } = {}
for _, module in VFX.Deliveries:GetChildren() do
	if module:IsA("ModuleScript") then
		DeliveryVFX[module.Name] = (require :: any)(module)
	end
end

----------------------------------------------------------- ATTACK EVENTS

local function onFire(caster: Player, attack: Types.AttackConfig, data: Types.FireData)
	-- Cast: a burst at the anchor the moment the attack leaves (muzzle flash, whoosh)
	local character = caster.Character
	if attack.VFX.Cast and character then
		VFXUtil.burstKit(attack.VFX.Cast, Anchors.getParts(character, attack.Anchor, data.Side))
	end

	local play = DeliveryVFX[attack.Delivery]
	if not play then
		return
	end
	-- Melee and AOE effects wait for the animation's Hit frame (other deliveries don't
	-- wait at all). In a new thread, so the wait never holds up anything else.
	task.spawn(function()
		if character then
			AttackAnimations.waitForHit(character, attack, data.Side)
		end
		play(caster, attack, data)
	end)
end

Remotes.AttackReplicate.OnClientEvent:Connect(function(phase: string, caster: Player?, attackId: string, data: any)
	local attack = Attacks[attackId]
	if not attack then
		return
	end

	-- Impacts don't need the caster. They can arrive after the caster has left the game
	-- (a projectile still in flight), and should still play.
	if phase == "Impact" then
		Impact.play(attack, data)
		return
	end

	if not caster then
		return
	end
	if phase == "ChargeStart" then
		Charge.start(caster, attack, data or {})
	elseif phase == "ChargeEnd" then
		Charge.stop(caster)
	elseif phase == "Fire" then
		onFire(caster, attack, data)
	end
end)

------------------------------------------------------------------- AURAS

local cleanups: { [Player]: () -> () } = {}

local function onPlayerAdded(player: Player)
	cleanups[player] = Aura.track(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end

Players.PlayerRemoving:Connect(function(player)
	local cleanup = cleanups[player]
	if cleanup then
		cleanup()
		cleanups[player] = nil
	end
	Charge.stop(player)
end)
