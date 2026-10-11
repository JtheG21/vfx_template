--!strict
--[[
	ObjectPool
	Reuses instances instead of cloning and destroying them every time.

	    local pool = ObjectPool.new(template, 5, 20)
	    local effect = pool:Get()
	    ...
	    pool:Return(effect)
]]

local ObjectPool = {}
ObjectPool.__index = ObjectPool

type PoolData = {
	Template: Instance,
	Available: { Instance },
	InPool: { [Instance]: boolean }, -- "set" of objects currently in the pool
	MaxCapacity: number,
}

-- PATTERN: typed class. `typeof(setmetatable(...))` builds a type that has BOTH the
-- data fields (PoolData) AND the methods (Get, Return), so `pool:Get()` autocompletes.
export type ObjectPool = typeof(setmetatable({} :: PoolData, ObjectPool))

local HIDDEN_CFRAME = CFrame.new(0, -5000, 0)

-- Puts an object back into a clean "unused" state
local function reset(object: Instance)
	if object:IsA("Model") and object:GetScale() ~= 1 then
		object:ScaleTo(1) -- undo any charge-based scaling
	end
	if object:IsA("PVInstance") then
		object:PivotTo(HIDDEN_CFRAME)
	end
	for _, descendant in object:GetDescendants() do
		if descendant:IsA("ParticleEmitter") then
			descendant.Enabled = false
		end
	end
	object.Parent = nil
end

function ObjectPool.new(template: Instance, initialSize: number, maxCapacity: number): ObjectPool
	local self = setmetatable({} :: PoolData, ObjectPool)
	self.Template = template
	self.Available = {}
	self.InPool = {}
	self.MaxCapacity = maxCapacity

	-- Pre-warm: do the cloning now, while nothing is happening, instead of mid-fight
	for _ = 1, initialSize do
		local clone = template:Clone()
		reset(clone)
		table.insert(self.Available, clone)
		self.InPool[clone] = true
	end

	return self
end

-- SYNTAX: `function ObjectPool.Get(self: ObjectPool)` is the same as `function ObjectPool:Get()`,
-- but writing `self` out lets us give it a type. Callers still use pool:Get().
function ObjectPool.Get(self: ObjectPool): Instance
	-- table.remove with no index removes and returns the LAST item (fastest; nothing shifts)
	local object = table.remove(self.Available)
	if object then
		self.InPool[object] = nil
		return object
	end
	-- Pool is empty: make a new one. It joins the pool when it's returned.
	return self.Template:Clone()
end

function ObjectPool.Return(self: ObjectPool, object: Instance)
	-- Guard against returning the same object twice. Without this, one object
	-- ends up in the list twice and two effects would end up using it at once.
	if self.InPool[object] then
		return
	end
	if #self.Available >= self.MaxCapacity then
		object:Destroy()
		return
	end
	reset(object)
	self.InPool[object] = true
	table.insert(self.Available, object)
end

return ObjectPool
