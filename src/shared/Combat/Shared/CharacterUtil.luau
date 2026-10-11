--!strict
--[[
	CharacterUtil
	Small character helpers used by both the server and clients.
	(Body-part lookups like hands and feet live in Anchors.)
]]

local CharacterUtil = {}

-- Finds which character a part belongs to. Climbs through nested models,
-- e.g. an accessory or held item inside the character.
function CharacterUtil.getCharacterFromPart(part: Instance): (Model?, Humanoid?)
	local model = part:FindFirstAncestorOfClass("Model")
	while model do
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if humanoid then
			return model, humanoid
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil, nil
end

-- Returns the Humanoid only if the character exists AND is alive.
-- Saves writing the same 3 checks in every script.
function CharacterUtil.getAliveHumanoid(character: Model?): Humanoid?
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		return humanoid
	end
	return nil
end

return CharacterUtil
