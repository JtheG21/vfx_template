--!strict
--[[
	DevServer
	Developer test tools: training dummies, no-cooldown mode, hitbox drawing, self heal.

	WHO GETS THEM: everyone while testing in Studio. In a live game, only the UserIds
	in ALLOWED_USER_IDS. Players without access never receive the panel's code or its
	remote at all, so there is nothing for them to find or exploit. The server still
	re-checks access on every request.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Settings = require(ReplicatedStorage.Combat.Settings)
local Dummy = require(script.Parent.Dummy)

-- Add your UserId (the number in your Roblox profile URL) to use dev tools in a live game
local ALLOWED_USER_IDS: { [number]: boolean } = {
	-- [12345678] = true,
}

local DUMMY_DISTANCE = 10 -- studs in front of you that a dummy appears

-- The panel's LocalScript sits next to this script. LocalScripts don't run in
-- ServerScriptService, so it does nothing until it's copied into a player's PlayerGui.
local panelScript = script.Parent:WaitForChild("DevPanel")

local function hasAccess(player: Player): boolean
	return RunService:IsStudio() or ALLOWED_USER_IDS[player.UserId] == true
end

local function onRequest(player: Player, action: unknown, value: unknown)
	if not hasAccess(player) or typeof(action) ~= "string" then
		return
	end
	local character = player.Character

	if action == "SpawnDummy" then
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not (root and root:IsA("BasePart")) then
			return
		end
		-- In front of you, turned to face you (same height, so it stands upright)
		local position = root.Position + root.CFrame.LookVector * DUMMY_DISTANCE
		local facing = Vector3.new(root.Position.X, position.Y, root.Position.Z)
		local mode: Dummy.Mode = if value == "Moving" then "Moving" else "Still"
		Dummy.spawn(Dummy.findFreeSpot(CFrame.lookAt(position, facing), mode), mode)
	elseif action == "ClearDummies" then
		Dummy.clear()
	elseif action == "SetNoCooldown" and typeof(value) == "boolean" then
		player:SetAttribute(Settings.NoCooldownAttribute, value)
	elseif action == "SetHitboxes" and typeof(value) == "boolean" then
		workspace:SetAttribute(Settings.DebugDrawAttribute, value)
	elseif action == "HealSelf" then
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			humanoid.Health = humanoid.MaxHealth
		end
	end
end

local function givePanel(player: Player)
	if not hasAccess(player) then
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "DevTools"
	gui.ResetOnSpawn = false -- keep the panel (and its state) when you respawn
	gui.DisplayOrder = 100 -- draw above the game's own UI
	gui:SetAttribute("DummyFolder", Dummy.FolderName)

	-- The remote lives INSIDE this player's PlayerGui, so only they can ever see it
	local remote = Instance.new("RemoteEvent")
	remote.Name = "DevRequest"
	remote.Parent = gui
	remote.OnServerEvent:Connect(function(sender, action, value)
		if sender == player then
			onRequest(sender, action, value)
		end
	end)

	panelScript:Clone().Parent = gui
	gui.Parent = player:WaitForChild("PlayerGui")
end

Players.PlayerAdded:Connect(givePanel)
for _, player in Players:GetPlayers() do
	task.spawn(givePanel, player)
end
