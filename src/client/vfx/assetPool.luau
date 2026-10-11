--!strict
--[[
	AssetPool
	Finds VFX templates by path ("Fire/Fireball" -> VFXTemplates.Fire.Fireball),
	prepares them (see TemplatePrep), and keeps one ObjectPool per path, created
	the first time that path is used.

	    local effect = AssetPool.get("Fire/Impact")
	    ...
	    AssetPool.release("Fire/Impact", effect)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Combat = ReplicatedStorage:WaitForChild("Combat")
local ObjectPool = require(Combat.Shared.ObjectPool)
local TemplatePrep = require(script.Parent.TemplatePrep)

local VFXTemplates = ReplicatedStorage:WaitForChild("VFXTemplates")

local INITIAL_POOL_SIZE = 2
local MAX_POOL_SIZE = 20

local AssetPool = {}

local pools: { [string]: ObjectPool.ObjectPool } = {}
local warned: { [string]: boolean } = {}

-- Finds and prepares a template. Warns ONCE per missing path instead of every time.
function AssetPool.findTemplate(path: string): Instance?
	local current: Instance? = VFXTemplates
	-- string.split("Fire/Fireball", "/") -> { "Fire", "Fireball" }
	for _, name in string.split(path, "/") do
		if not current then
			break
		end
		current = current:FindFirstChild(name)
	end

	if not current then
		if not warned[path] then
			warned[path] = true
			-- SYNTAX: backtick strings are "string interpolation". {expression} is replaced
			-- with its value. Same as "Missing VFX template: VFXTemplates/" .. path
			warn(`[Combat] Missing VFX template: VFXTemplates/{path}`)
		end
		return nil
	end

	TemplatePrep.prepare(current)
	return current
end

-- Lazy creation: the pool is only built the first time a path is requested,
-- so templates nobody uses are never cloned.
function AssetPool.get(path: string): Instance?
	local pool = pools[path]
	if not pool then
		local template = AssetPool.findTemplate(path)
		if not template then
			return nil
		end
		-- TemplatePrep.reset is passed as the pool's reset hook: every copy that goes
		-- back into the pool is restored to exactly how the template was built.
		pool = ObjectPool.new(template, INITIAL_POOL_SIZE, MAX_POOL_SIZE, TemplatePrep.reset)
		pools[path] = pool
	end
	return pool:Get()
end

function AssetPool.release(path: string, object: Instance)
	local pool = pools[path]
	if pool then
		pool:Return(object)
	else
		object:Destroy()
	end
end

return AssetPool
