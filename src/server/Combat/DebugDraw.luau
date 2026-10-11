--!strict
--[[
	DebugDraw
	Draws what an attack actually checks, so you can SEE it in the world:
	  box     melee hitboxes           (orange)
	  sphere  explosion radii          (red)
	  line    projectile paths, beams  (yellow / blue)

	Off by default. Switched on by the workspace attribute named in
	Settings.DebugDrawAttribute (the dev panel's "Show Hitboxes" button sets it).
	When it's off every call returns immediately, so leaving the calls in
	production code costs nothing.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Settings = require(ReplicatedStorage.Combat.Settings)

local LIFETIME = 0.75 -- seconds each shape stays visible
local LINE_THICKNESS = 0.15
local TRANSPARENCY = 0.65

local DebugDraw = {}

DebugDraw.Colors = table.freeze({
	Melee = Color3.fromRGB(255, 170, 0),
	Area = Color3.fromRGB(255, 60, 60),
	Path = Color3.fromRGB(255, 230, 80),
	Ray = Color3.fromRGB(80, 200, 255),
})

local folder: Folder? = nil

local function isEnabled(): boolean
	return workspace:GetAttribute(Settings.DebugDrawAttribute) == true
end

-- Created the first time something is drawn, so games that never use it get no folder
local function getFolder(): Folder
	if folder and folder.Parent then
		return folder
	end
	local newFolder = Instance.new("Folder")
	newFolder.Name = "CombatDebug"
	newFolder.Parent = workspace
	folder = newFolder
	return newFolder
end

local function draw(shape: Enum.PartType, cframe: CFrame, size: Vector3, color: Color3)
	local part = Instance.new("Part")
	part.Shape = shape
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = Enum.Material.Neon
	part.Transparency = TRANSPARENCY
	-- A debug shape must never affect the game: no physics, no raycasts, no touches
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = getFolder()
	task.delay(LIFETIME, function()
		part:Destroy()
	end)
end

function DebugDraw.box(cframe: CFrame, size: Vector3, color: Color3?)
	if isEnabled() then
		draw(Enum.PartType.Block, cframe, size, color or DebugDraw.Colors.Melee)
	end
end

function DebugDraw.sphere(center: Vector3, radius: number, color: Color3?)
	if isEnabled() then
		-- A Ball part's diameter is its size
		draw(Enum.PartType.Ball, CFrame.new(center), Vector3.one * radius * 2, color or DebugDraw.Colors.Area)
	end
end

function DebugDraw.line(from: Vector3, to: Vector3, color: Color3?)
	if not isEnabled() then
		return
	end
	local offset = to - from
	local length = offset.Magnitude
	if length < 0.01 then
		return
	end
	-- A thin block, centered halfway between the points and facing along the line
	draw(
		Enum.PartType.Block,
		CFrame.lookAt(from + offset / 2, to),
		Vector3.new(LINE_THICKNESS, LINE_THICKNESS, length),
		color or DebugDraw.Colors.Ray
	)
end

return DebugDraw
