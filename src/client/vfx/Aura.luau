--!strict
--[[
	Aura
	Shows each player's style aura (e.g. flaming hands) for as long as the style is equipped.
	Where it sits comes from the style's AuraAnchor (default "BothHands").

	The server stores the style in a Player attribute. Attributes replicate,
	so every client sees every player's style and draws the aura locally.
	No VFX is ever created on the server.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Combat = ReplicatedStorage:WaitForChild("Combat")
local Types = require(Combat.Types)
local Settings = require(Combat.Settings)
local Styles = require(Combat.Styles)
local Anchors = require(Combat.Shared.Anchors)
local VFXUtil = require(script.Parent.VFXUtil)

local LIMB_TIMEOUT = 10
local DEFAULT_AURA_ANCHOR: Types.Anchor = "BothHands"

type Tracked = {
	Attachments: { Attachment },
	Version: number,
}

local Aura = {}

local function clear(entry: Tracked)
	VFXUtil.detachKit(entry.Attachments) -- fades the old aura out instead of popping it off
	entry.Attachments = {}
end

local function apply(player: Player, entry: Tracked)
	-- PATTERN: "version token". waitForParts below can YIELD (pause). If the style
	-- changes while we wait, a newer apply() starts. Each call bumps the version,
	-- and an older call that sees a newer version quits instead of adding duplicates.
	entry.Version += 1
	local version = entry.Version
	clear(entry)

	local character = player.Character
	local styleName = player:GetAttribute(Settings.StyleAttribute)
	if not character or typeof(styleName) ~= "string" then
		return
	end
	local style = Styles[styleName]
	if not (style and style.AuraVFX) then
		return
	end

	local parts = Anchors.waitForParts(character, style.AuraAnchor or DEFAULT_AURA_ANCHOR, nil, LIMB_TIMEOUT)
	if entry.Version ~= version or player.Character ~= character then
		return -- a newer apply() took over, or the character respawned, while we were waiting
	end
	entry.Attachments = VFXUtil.attachKit(style.AuraVFX, parts)
end

-- Starts tracking a player. Returns a CLEANUP FUNCTION.
-- PATTERN: the caller stores the function and calls it when the player leaves,
-- so it never needs to know which connections or instances were created.
function Aura.track(player: Player): () -> ()
	local entry: Tracked = { Attachments = {}, Version = 0 }

	local function refresh()
		-- task.spawn runs apply in its own thread, so its waiting never blocks the caller
		task.spawn(apply, player, entry)
	end

	local connections = {
		player:GetAttributeChangedSignal(Settings.StyleAttribute):Connect(refresh),
		player.CharacterAdded:Connect(refresh),
	}
	refresh()

	return function()
		for _, connection in connections do
			connection:Disconnect()
		end
		entry.Version += 1 -- cancels any apply() still waiting
		clear(entry)
	end
end

return Aura
