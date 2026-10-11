local RaycastHitbox = {}
RaycastHitbox.__index = RaycastHitbox

type Hitbox = {
	Active: boolean,
	IgnoreList: { Instance },
	AttachmentPoints: { Attachment },
	LastPosition: { [Attachment]: Vector3 },
	OnHitConnection: BindableEvent,
	HitTargets: { [Instance]: boolean },
}

export type Type = typeof(setmetatable({} :: Hitbox, RaycastHitbox))

function RaycastHitbox.New(attachmentPoints: { Attachment }, ignoreLists: { Instance }): Type
	local self = setmetatable({} :: Hitbox, RaycastHitbox)

	self.Active = false
	self.IgnoreList = ignoreLists
	self.AttachmentPoints = attachmentPoints
	self.LastPosition = {}
	self.HitTargets = {}
	self.OnHitConnection = Instance.new("BindableEvent")

	return self
end

function RaycastHitbox:Start()
	self.Active = true
	table.clear(self.HitTargets)

	for _, attachment in ipairs(self.AttachmentPoints) do
		self.LastPosition[attachment] = attachment.WorldPosition
	end
end

function RaycastHitbox:Stop()
	self.Active = false
end

--this method must be called every physics frame while the hitbox is active
function RaycastHitbox:Update()
	if not self.Active then
		return
	end

	local raycastParams = RaycastParams.new()
	raycastParams.FilterDescendantsInstances = self.IgnoreList
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude

	for _, attachment in ipairs(self.AttachmentPoints) do
		local currentPos = attachment.WorldPosition
		local lastPos = self.LastPosition[attachment] or currentPos

		local direction = currentPos - lastPos
		local distance = direction.Magnitude

		if distance > 0.01 then
			local raycastResult = workspace:Raycast(lastPos, direction, raycastParams)

			if raycastResult and raycastResult.Instance then
				local model = raycastResult.Instance:FindFirstAncestorOfClass("Model")
				local humanoid = model and model:FindFirstChildOfClass("Humanoid")

				if humanoid and model and not self.HitTargets[model] then
					self.HitTargets[model] = true
					self.OnHitConnection:Fire(model, humanoid, raycastResult.Position)
				elseif not humanoid and not self.HitTargets[raycastResult.Instance] then
					-- Non-humanoid hit (ground, wall, etc.) — fire with nil humanoid so caller can stop projectile
					self.HitTargets[raycastResult.Instance] = true
					self.OnHitConnection:Fire(raycastResult.Instance, nil, raycastResult.Position)
				end
			end
		end
		self.LastPosition[attachment] = currentPos
	end
end

function RaycastHitbox:Destroy()
	self:Stop()
	self.OnHitConnection:Destroy()
end

-- Lowercase alias for consistent API conventions
RaycastHitbox.new = RaycastHitbox.New

return RaycastHitbox
