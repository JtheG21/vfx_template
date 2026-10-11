--!strict
--[[
	ObjectPool
	Reuses instances instead of cloning and destroying them every time.

	    local pool = ObjectPool.new(template, 5, 20, resetFunction)
	    local effect = pool:Get()
	    ...
	    pool:Return(effect)

	The pool itself only knows how to hide and store objects. What "clean" means
	for a particular kind of object (e.g. a VFX: particles off, sounds stopped) is
	passed in as `onReset`. That keeps this module reusable for anything.
]]

local ObjectPool = {}
ObjectPool.__index = ObjectPool

type PoolData = {
	Template: Instance,
	Available: { Instance },
	InPool: { [Instance]: boolean }, -- "set" of objects currently in the pool
	MaxCapacity: number,
	OnReset: ((Instance) -> ())?,
}

-- PATTERN: typed class. `typeof(setmetatable(...))` builds a type that has BOTH the
-- data fields (PoolData) AND the methods (Get, Return), so `pool:Get()` autocompletes.
export type ObjectPool = typeof(setmetatable({} :: PoolData, ObjectPool))

local HIDDEN_CFRAME = CFrame.new(0, -5000, 0)

-- Puts an object into a clean, hidden, unused state
local function resetObject(pool: ObjectPool, object: Instance)
	if pool.OnReset then
		pool.OnReset(object)
	end
	if object:IsA("PVInstance") then
		object:PivotTo(HIDDEN_CFRAME)
	end
	object.Parent = nil
end

-- SYNTAX: `((Instance) -> ())?` = "an optional function that takes an Instance and returns nothing"
function ObjectPool.new(
	template: Instance,
	initialSize: number,
	maxCapacity: number,
	onReset: ((Instance) -> ())?
): ObjectPool
	local self = setmetatable({} :: PoolData, ObjectPool)
	self.Template = template
	self.Available = {}
	self.InPool = {}
	self.MaxCapacity = maxCapacity
	self.OnReset = onReset

	-- Pre-warm: do the cloning now, while nothing is happening, instead of mid-fight
	for _ = 1, initialSize do
		local clone = template:Clone()
		resetObject(self, clone)
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
	-- Pool is empty: make a new one, cleaned exactly like pooled ones so it behaves the same.
	-- It joins the pool when it's returned.
	local clone = self.Template:Clone()
	resetObject(self, clone)
	return clone
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
	resetObject(self, object)
	self.InPool[object] = true
	table.insert(self.Available, object)
end

return ObjectPool
