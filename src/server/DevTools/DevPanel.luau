--!strict
--[[
	DevPanel
	Only runs for players with dev access: DevServer copies it into their PlayerGui.

	  Spawn Dummy / Spawn Moving Dummy   training targets (auto-heal, respawn)
	  Clear Dummies
	  No Cooldowns                       attack as fast as you like
	  Show Hitboxes                      see melee boxes, blast radii, projectile paths, beam rays
	  Heal Me

	Open and close with F2 or the DEV button. Dummies get a health bar and
	floating damage numbers, drawn only on your screen.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Settings = require(ReplicatedStorage:WaitForChild("Combat"):WaitForChild("Settings"))

-- At runtime this script's parent is the ScreenGui DevServer made for us
local gui = (script.Parent :: any) :: ScreenGui
local remote = gui:WaitForChild("DevRequest") :: RemoteEvent
local player = Players.LocalPlayer

local TOGGLE_KEY = Enum.KeyCode.F2
local DAMAGE_RISE = 2.5 -- studs a damage number floats up
local DAMAGE_TIME = 0.9 -- seconds it takes to float up and fade

local THEME = {
	Panel = Color3.fromRGB(24, 24, 28),
	Button = Color3.fromRGB(46, 46, 54),
	ButtonOn = Color3.fromRGB(40, 125, 70),
	Text = Color3.fromRGB(235, 235, 240),
	Accent = Color3.fromRGB(255, 170, 0),
	BarBack = Color3.fromRGB(40, 40, 40),
	BarFill = Color3.fromRGB(80, 220, 110),
}

------------------------------------------------------------------- UI HELPERS

local function round(instance: GuiObject, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = instance
end

-- Named buttons are easy to find in the Explorer while debugging the panel itself
local function makeButton(parent: Instance, name: string, text: string, order: number): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.LayoutOrder = order
	button.Size = UDim2.new(1, 0, 0, 30)
	button.BackgroundColor3 = THEME.Button
	button.TextColor3 = THEME.Text
	button.Font = Enum.Font.GothamMedium
	button.TextSize = 14
	button.Text = text
	button.AutoButtonColor = true
	round(button, 6)
	button.Parent = parent
	return button
end

------------------------------------------------------------------------ PANEL

local openButton = Instance.new("TextButton")
openButton.Name = "Open"
openButton.Size = UDim2.fromOffset(52, 28)
openButton.Position = UDim2.fromOffset(12, 12)
openButton.BackgroundColor3 = THEME.Panel
openButton.TextColor3 = THEME.Accent
openButton.Font = Enum.Font.GothamBold
openButton.TextSize = 14
openButton.Text = "DEV"
round(openButton, 6)
openButton.Parent = gui

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.Size = UDim2.fromOffset(210, 0)
panel.AutomaticSize = Enum.AutomaticSize.Y -- grows to fit the buttons
panel.Position = UDim2.fromOffset(12, 48)
panel.BackgroundColor3 = THEME.Panel
panel.BackgroundTransparency = 0.05
panel.Visible = false
round(panel, 8)
panel.Parent = gui

local padding = Instance.new("UIPadding")
padding.PaddingTop = UDim.new(0, 10)
padding.PaddingBottom = UDim.new(0, 10)
padding.PaddingLeft = UDim.new(0, 10)
padding.PaddingRight = UDim.new(0, 10)
padding.Parent = panel

local layout = Instance.new("UIListLayout")
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, 6)
layout.Parent = panel

local title = Instance.new("TextLabel")
title.LayoutOrder = 0
title.Size = UDim2.new(1, 0, 0, 20)
title.BackgroundTransparency = 1
title.TextColor3 = THEME.Accent
title.Font = Enum.Font.GothamBold
title.TextSize = 15
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "Dev Tools  (F2)"
title.Parent = panel

local function togglePanel()
	panel.Visible = not panel.Visible
end
openButton.Activated:Connect(togglePanel)
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if not gameProcessed and input.KeyCode == TOGGLE_KEY then
		togglePanel()
	end
end)

-- Plain action buttons
makeButton(panel, "SpawnDummy", "Spawn Dummy", 1).Activated:Connect(function()
	remote:FireServer("SpawnDummy", "Still")
end)
makeButton(panel, "SpawnMovingDummy", "Spawn Moving Dummy", 2).Activated:Connect(function()
	remote:FireServer("SpawnDummy", "Moving")
end)
makeButton(panel, "ClearDummies", "Clear Dummies", 3).Activated:Connect(function()
	remote:FireServer("ClearDummies")
end)
makeButton(panel, "HealMe", "Heal Me", 6).Activated:Connect(function()
	remote:FireServer("HealSelf")
end)

-- On/off buttons. The SERVER owns the state (an attribute); the button only asks to
-- flip it, and redraws whenever the attribute actually changes. The label can
-- never disagree with what the game is really doing.
local function makeToggle(
	name: string,
	label: string,
	order: number,
	owner: Instance,
	attribute: string,
	action: string
)
	local button = makeButton(panel, name, label, order)
	local function isOn(): boolean
		return owner:GetAttribute(attribute) == true
	end
	local function redraw()
		button.Text = `{label}: {if isOn() then "ON" else "OFF"}`
		button.BackgroundColor3 = if isOn() then THEME.ButtonOn else THEME.Button
	end
	button.Activated:Connect(function()
		remote:FireServer(action, not isOn())
	end)
	owner:GetAttributeChangedSignal(attribute):Connect(redraw)
	redraw()
end

makeToggle("NoCooldowns", "No Cooldowns", 4, player, Settings.NoCooldownAttribute, "SetNoCooldown")
makeToggle("ShowHitboxes", "Show Hitboxes", 5, workspace, Settings.DebugDrawAttribute, "SetHitboxes")

------------------------------------------------------------- DUMMY OVERLAYS

local function formatDamage(amount: number): string
	-- Whole numbers show as "8", fractions as "52.5"
	return if amount % 1 == 0 then tostring(amount) else string.format("%.1f", amount)
end

local function showDamage(head: BasePart, amount: number)
	local billboard = Instance.new("BillboardGui")
	billboard.Adornee = head
	billboard.AlwaysOnTop = true
	billboard.Size = UDim2.fromOffset(100, 36)
	-- A little random sideways offset so rapid hits don't stack on top of each other
	local start = Vector3.new((math.random() - 0.5) * 3, 3, 0)
	billboard.StudsOffset = start

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = THEME.Accent
	label.TextStrokeTransparency = 0.3
	label.Text = formatDamage(amount)
	label.Parent = billboard
	billboard.Parent = gui -- UI lives in PlayerGui and is pinned to the head with Adornee

	TweenService:Create(billboard, TweenInfo.new(DAMAGE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		StudsOffset = start + Vector3.yAxis * DAMAGE_RISE,
	}):Play()
	TweenService:Create(label, TweenInfo.new(DAMAGE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()
	task.delay(DAMAGE_TIME, function()
		billboard:Destroy()
	end)
end

local function addOverlay(model: Model)
	local humanoid = model:WaitForChild("Humanoid", 10)
	local head = model:WaitForChild("Head", 10)
	if not (humanoid and humanoid:IsA("Humanoid") and head and head:IsA("BasePart")) then
		return
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Adornee = head
	billboard.AlwaysOnTop = true
	billboard.Size = UDim2.fromOffset(130, 36)
	billboard.StudsOffset = Vector3.new(0, 2.2, 0)

	local name = Instance.new("TextLabel")
	name.Size = UDim2.new(1, 0, 0, 16)
	name.BackgroundTransparency = 1
	name.Font = Enum.Font.GothamBold
	name.TextSize = 13
	name.TextColor3 = THEME.Text
	name.TextStrokeTransparency = 0.5
	name.Text = model.Name
	name.Parent = billboard

	local bar = Instance.new("Frame")
	bar.Position = UDim2.fromOffset(0, 18)
	bar.Size = UDim2.new(1, 0, 0, 14)
	bar.BackgroundColor3 = THEME.BarBack
	round(bar, 4)
	bar.Parent = billboard

	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = THEME.BarFill
	round(fill, 4)
	fill.Parent = bar

	local amount = Instance.new("TextLabel")
	amount.Size = UDim2.fromScale(1, 1)
	amount.BackgroundTransparency = 1
	amount.Font = Enum.Font.GothamBold
	amount.TextSize = 11
	amount.TextColor3 = THEME.Text
	amount.ZIndex = 2
	amount.Parent = bar

	local function redraw()
		local fraction = math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)
		fill.Size = UDim2.fromScale(fraction, 1)
		amount.Text = `{math.ceil(humanoid.Health)} / {humanoid.MaxHealth}`
	end
	redraw()
	billboard.Parent = gui

	local lastHealth = humanoid.Health
	local connection = humanoid.HealthChanged:Connect(function(health)
		local lost = lastHealth - health
		lastHealth = health
		redraw()
		if lost > 0.01 then -- only damage gets a number, not healing
			showDamage(head, lost)
		end
	end)

	-- Clean up when the dummy is removed (killed and respawned, or cleared)
	model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(workspace) then
			connection:Disconnect()
			billboard:Destroy()
		end
	end)
end

local function watchDummies(folder: Instance)
	for _, child in folder:GetChildren() do
		if child:IsA("Model") then
			task.spawn(addOverlay, child)
		end
	end
	folder.ChildAdded:Connect(function(child)
		if child:IsA("Model") then
			task.spawn(addOverlay, child)
		end
	end)
end

local folderName = gui:GetAttribute("DummyFolder")
if typeof(folderName) == "string" then
	task.spawn(function()
		watchDummies(workspace:WaitForChild(folderName))
	end)
end
