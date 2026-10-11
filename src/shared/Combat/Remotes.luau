--!strict
--[[
	Remotes
	Owns every RemoteEvent in the combat system. The SERVER creates them at runtime
	and clients wait for them, so there is nothing to set up by hand in the Explorer.

	AttackRequest   client -> server   ("SetStyle" | "Begin" | "Release" | "Fire", ...)
	AttackReplicate server -> clients  ("ChargeStart" | "ChargeEnd" | "Fire" | "Impact", ...)

	Splitting requests from replication means each remote has one job and one
	direction, so OnServerEvent and OnClientEvent never mean two different things.
]]

local RunService = game:GetService("RunService")

local REMOTE_NAMES = { "AttackRequest", "AttackReplicate" }

local folder: Instance
if RunService:IsServer() then
	folder = Instance.new("Folder")
	folder.Name = "RemoteEvents"
	for _, remoteName in REMOTE_NAMES do
		local remote = Instance.new("RemoteEvent")
		remote.Name = remoteName
		remote.Parent = folder
	end
	-- Parent LAST: clients only see the folder once every remote is already inside it
	folder.Parent = script.Parent
else
	folder = script.Parent:WaitForChild("RemoteEvents")
end

return {
	AttackRequest = folder:WaitForChild("AttackRequest") :: RemoteEvent,
	AttackReplicate = folder:WaitForChild("AttackReplicate") :: RemoteEvent,
}
