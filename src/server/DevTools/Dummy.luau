--!strict
--[[
	Dummy
	Training dummies for testing attacks.
	  - lots of health, and they heal back to full a few seconds after the last hit
	  - respawn in the same spot when killed
	  - "Moving" dummies walk left and right, for testing aim and projectiles
	  - new dummies find a free spot, so they never spawn inside each other (or inside a
	    moving dummy's walking path) and shove each other around
	They're ordinary Humanoid characters, so every attack treats them like a real player.
]]

local Players = game:GetService("Players")

export type Mode = "Still" | "Moving"

local MAX_HEALTH = 1000
local HEAL_DELAY = 3 -- seconds after the last hit before healing to full
local RESPAWN_DELAY = 2
local WALK_DISTANCE = 8 -- moving dummies walk this far to each side of their spawn
local WALK_SPEED = 10
local DUMMY_COLOR = Color3.fromRGB(163, 162, 165)
local MIN_SPACING = 5 -- dummies closer than this push each other around
local MAX_SPOT_ATTEMPTS = 12 -- how many sideways steps to try when looking for a free spot
local FOOTPRINT_SAMPLES = 8 -- points checked along a moving dummy's walking line

local Dummy = {}

-- Clients look for dummies in this folder (the dev panel draws their health bars)
Dummy.FolderName = "Dummies"

local folder = Instance.new("Folder")
folder.Name = Dummy.FolderName
folder.Parent = workspace

-- One plain grey body for every dummy
local description = Instance.new("HumanoidDescription")
description.HeadColor = DUMMY_COLOR
description.TorsoColor = DUMMY_COLOR
description.LeftArmColor = DUMMY_COLOR
description.RightArmColor = DUMMY_COLOR
description.LeftLegColor = DUMMY_COLOR
description.RightLegColor = DUMMY_COLOR

------------------------------------------------------------------ SPACING

-- The ground a dummy covers: a single point for still dummies, the whole
-- walking line for moving ones. Returned as the two ends of a line.
local function getFootprint(cframe: CFrame, mode: Mode): (Vector3, Vector3)
	if mode == "Moving" then
		return (cframe * CFrame.new(-WALK_DISTANCE, 0, 0)).Position, (cframe * CFrame.new(WALK_DISTANCE, 0, 0)).Position
	end
	return cframe.Position, cframe.Position
end

-- Shortest distance from a point to a line segment, ignoring height
local function flatDistanceToSegment(point: Vector3, from: Vector3, to: Vector3): number
	local p = Vector3.new(point.X, 0, point.Z)
	local a = Vector3.new(from.X, 0, from.Z)
	local segment = Vector3.new(to.X, 0, to.Z) - a
	local lengthSquared = segment:Dot(segment)
	-- t = how far along the segment the closest point is (0 = start, 1 = end).
	-- Dot products project the point onto the line; clamping keeps it on the segment.
	local t = if lengthSquared > 0 then math.clamp((p - a):Dot(segment) / lengthSquared, 0, 1) else 0
	return (p - (a + segment * t)).Magnitude
end

local function isClear(from: Vector3, to: Vector3): boolean
	for _, model in folder:GetChildren() do
		local otherFrom, otherTo = model:GetAttribute("FootprintFrom"), model:GetAttribute("FootprintTo")
		if typeof(otherFrom) == "Vector3" and typeof(otherTo) == "Vector3" then
			for i = 0, FOOTPRINT_SAMPLES do
				local point = from:Lerp(to, i / FOOTPRINT_SAMPLES)
				if flatDistanceToSegment(point, otherFrom, otherTo) < MIN_SPACING then
					return false
				end
			end
		end
	end
	return true
end

-- The closest spot to `cframe` where a dummy of this mode won't touch any other dummy.
-- Tries the spot itself, then steps out sideways: right 1, left 1, right 2, left 2...
function Dummy.findFreeSpot(cframe: CFrame, mode: Mode): CFrame
	for attempt = 0, MAX_SPOT_ATTEMPTS do
		local steps = math.ceil(attempt / 2) * (if attempt % 2 == 1 then 1 else -1)
		local candidate = cframe * CFrame.new(steps * MIN_SPACING, 0, 0)
		if isClear(getFootprint(candidate, mode)) then
			return candidate
		end
	end
	return cframe -- everything nearby is crowded: use the requested spot anyway
end

----------------------------------------------------------------- BEHAVIOUR

local function startHealing(model: Model, humanoid: Humanoid)
	local lastHit = 0
	local lastHealth = humanoid.Health
	humanoid.HealthChanged:Connect(function(health)
		if health < lastHealth then
			lastHit = os.clock()
		end
		lastHealth = health
	end)

	task.spawn(function()
		while model.Parent and humanoid.Health > 0 do
			if humanoid.Health < humanoid.MaxHealth and os.clock() - lastHit >= HEAL_DELAY then
				humanoid.Health = humanoid.MaxHealth
			end
			task.wait(0.25)
		end
	end)
end

local function startWalking(model: Model, humanoid: Humanoid, home: CFrame)
	humanoid.WalkSpeed = WALK_SPEED
	-- `home * CFrame.new(x, 0, 0)` = x studs to the dummy's own right
	local points =
		{ (home * CFrame.new(WALK_DISTANCE, 0, 0)).Position, (home * CFrame.new(-WALK_DISTANCE, 0, 0)).Position }
	task.spawn(function()
		local index = 1
		while model.Parent and humanoid.Health > 0 do
			humanoid:MoveTo(points[index])
			humanoid.MoveToFinished:Wait() -- Roblox gives up on its own after 8 seconds
			-- `index % 2 + 1` flips between 1 and 2
			index = index % 2 + 1
		end
	end)
end

function Dummy.spawn(cframe: CFrame, mode: Mode): Model?
	-- CreateHumanoidModelFromDescription builds a full R15 character (it can yield briefly)
	local ok, result = pcall(function()
		return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	end)
	if not ok then
		warn(`[DevTools] Couldn't create a dummy: {result}`)
		return nil
	end
	local model = result :: Model
	model.Name = if mode == "Moving" then "Moving Dummy" else "Training Dummy"
	local footprintFrom, footprintTo = getFootprint(cframe, mode)
	model:SetAttribute("FootprintFrom", footprintFrom)
	model:SetAttribute("FootprintTo", footprintTo)

	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.MaxHealth = MAX_HEALTH
	humanoid.Health = MAX_HEALTH
	-- The dev panel draws its own health bar and damage numbers
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None

	model:PivotTo(cframe)
	model.Parent = folder
	-- The server simulates the dummy, so it never stutters for whoever is looking at it
	local root = model.PrimaryPart
	if root then
		root:SetNetworkOwner(nil)
	end

	startHealing(model, humanoid)
	if mode == "Moving" then
		startWalking(model, humanoid, cframe)
	end

	humanoid.Died:Connect(function()
		task.delay(RESPAWN_DELAY, function()
			-- Parent is nil if "Clear Dummies" removed it in the meantime: don't bring it back
			if model.Parent then
				model:Destroy()
				Dummy.spawn(cframe, mode)
			end
		end)
	end)

	return model
end

function Dummy.clear()
	folder:ClearAllChildren()
end

return Dummy
