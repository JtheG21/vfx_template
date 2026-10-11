--!strict
--[[
	Projectile (client)
	Flies the VFX model along the same Trajectory the server uses (straight or arced),
	facing the way it's moving. It stops at the first thing it touches, so the
	visual lands where the server's hit lands. Damage is the server's job; this is looks only.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Combat = ReplicatedStorage:WaitForChild("Combat")
local Types = require(Combat.Types)
local Raycasting = require(Combat.Shared.Raycasting)
local Trajectory = require(Combat.Shared.Trajectory)
local AssetPool = require(script.Parent.Parent.AssetPool)
local VFXUtil = require(script.Parent.Parent.VFXUtil)

local DEFAULT_SPEED = 100

local play: Types.ClientDelivery = function(caster, attack, data)
	local vfxPath = attack.VFX.Main
	if not vfxPath then
		return
	end

	local path = Trajectory.new(data.Origin, data.Target, attack.ArcHeight)
	if path.Length < 0.1 then
		return
	end
	local duration = path.Length / (attack.Speed or DEFAULT_SPEED)

	local projectile = AssetPool.get(vfxPath)
	if not projectile then
		return
	end
	if not projectile:IsA("PVInstance") then
		AssetPool.release(vfxPath, projectile) -- not something we can move; give it back
		return
	end

	-- Bigger projectile for a bigger charge.
	-- PATTERN `a and b or c`: if Charge exists AND has VisualScale, use it, otherwise 1.
	-- (Careful: it falls back to c whenever b is nil OR false.)
	if projectile:IsA("Model") then
		local fullScale = attack.Charge and attack.Charge.VisualScale or 1
		projectile:ScaleTo(1 + (fullScale - 1) * data.Charge) -- lerp from 1 to fullScale
	end

	-- Face along the start of the curve (a tiny step ahead of the origin)
	projectile:PivotTo(CFrame.lookAt(path.Origin, Trajectory.getPoint(path, 0.01)))
	projectile.Parent = VFXUtil.Container
	-- Trails stream, one-shot emitters pop at launch, looped sounds (a whoosh) travel with it
	VFXUtil.sustain(projectile)

	local ignore: { Instance } = { VFXUtil.Container }
	if caster.Character then
		table.insert(ignore, caster.Character)
	end

	local elapsed = 0
	local lastPosition = path.Origin
	local connection: RBXScriptConnection

	local function finish(position: Vector3)
		connection:Disconnect()
		VFXUtil.shakeAt(attack.Shake, position)
		-- Let the trail particles finish before the model goes back in the pool
		local fadeTime = VFXUtil.stop(projectile)
		task.delay(fadeTime, function()
			AssetPool.release(vfxPath, projectile)
		end)
	end

	connection = RunService.Heartbeat:Connect(function(deltaTime)
		elapsed += deltaTime
		local t = math.min(elapsed / duration, 1)
		local position = Trajectory.getPoint(path, t)
		local segment = position - lastPosition

		local result: RaycastResult? = nil
		if segment.Magnitude > 0.001 then
			result = Raycasting.cast(lastPosition, segment.Unit, segment.Magnitude, ignore)
			if result then
				position = result.Position -- snap the visual onto the impact point
			end
			-- Face the direction of travel. On an arc this tilts the meteor
			-- nose-up on the way up and nose-down on the way in.
			projectile:PivotTo(CFrame.lookAt(position, position + segment))
		end
		lastPosition = position

		if result or t >= 1 then
			finish(position)
		end
	end)
end

return play
