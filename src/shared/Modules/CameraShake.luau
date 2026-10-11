--!strict
--[[
	CameraShake (client only)
	    CameraShake.start(intensity, frequency, duration, decay?)
	Several shakes can run at once; their offsets add together.
]]

local RunService = game:GetService("RunService")

local CameraShake = {}

type Shake = {
	Intensity: number,
	Frequency: number,
	Duration: number,
	Decay: number,
	Elapsed: number,
}

local DEFAULT_DECAY = 4

local activeShakes: { Shake } = {}
local isBound = false

local function update(deltaTime: number)
	local totalOffset = Vector3.zero

	-- Loop BACKWARDS so table.remove doesn't skip the next element
	for i = #activeShakes, 1, -1 do
		local shake = activeShakes[i]
		shake.Elapsed += deltaTime

		if shake.Elapsed >= shake.Duration then
			table.remove(activeShakes, i)
		else
			-- Exponential decay: strong at the start, fading smoothly to nothing
			local strength = shake.Intensity * math.exp(-shake.Decay * shake.Elapsed)
			local t = shake.Elapsed * shake.Frequency
			-- Different speeds per axis so the motion doesn't look like a straight line
			totalOffset += Vector3.new(math.sin(t), math.cos(t * 1.5), math.sin(t * 0.8) * 0.5) * strength
		end
	end

	if totalOffset.Magnitude > 0.001 then
		-- Read CurrentCamera every frame. It can be replaced (e.g. on respawn), so a saved reference could go stale.
		local camera = workspace.CurrentCamera
		camera.CFrame *= CFrame.new(totalOffset)
	end
end

-- `decay: number?` = optional parameter. Callers can leave it off.
function CameraShake.start(intensity: number, frequency: number, duration: number, decay: number?)
	-- Lazy bind: only start the render loop the first time a shake is used,
	-- instead of the moment the module is required.
	if not isBound then
		isBound = true
		RunService:BindToRenderStep("CombatCameraShake", Enum.RenderPriority.Camera.Value + 1, update)
	end

	table.insert(activeShakes, {
		Intensity = intensity,
		Frequency = frequency,
		Duration = duration,
		Decay = decay or DEFAULT_DECAY,
		Elapsed = 0,
	})
end

return CameraShake
