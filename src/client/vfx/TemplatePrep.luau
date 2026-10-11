--!strict
--[[
	TemplatePrep
	Makes ANY VFX template safe to use, so you never set properties by hand.
	Runs once per template, the first time it's used (on this client's copy only).

	  - Physics off: every part is Anchored, with no collisions, queries, touches or shadows.
	    An effect should never block players, catch raycasts or fall.
	  - Container blocks hidden: plain blocks that only exist to hold effects. Packs often
	    leave these semi-visible so you can find them in Studio; in game they'd show up as
	    grey cubes. A part counts as a container if it's a plain block-shaped Part with no
	    mesh or SurfaceAppearance and isn't Neon. Decals still show on a hidden part, so a
	    block that just holds a scorch decal is hidden too. Give a part the attribute
	    KeepVisible = true to keep it visible anyway.
	  - Pivot pinned to the main part, so a pivot that drifted in Studio can't make the
	    effect spawn in the wrong place.
	  - The authored state is remembered (emitter on/off, light brightness, sound speed and
	    volume, decal transparency), so reused pooled copies can be put back exactly as built.

	Whether particles run is decided by the code from how the template is USED:
	  burst   -> every emitter fires once
	  sustain -> emitters you left ON stream, emitters you left OFF pop once at the start
]]

local TemplatePrep = {}

-- Every attribute name the VFX code reads, in one place
local ATTRIBUTES = table.freeze({
	EmitCount = "EmitCount", -- ParticleEmitter: particles per burst (number)
	PitchVariance = "PitchVariance", -- Sound: random pitch change, e.g. 0.1 = +/-10% (number)
	MaxDuration = "MaxDuration", -- Sound: fade out after this many seconds (number)
	KeepVisible = "KeepVisible", -- BasePart: never auto-hide this part (boolean)
	-- Written by TemplatePrep itself, to remember the authored state:
	BaseEnabled = "BaseEnabled",
	BaseBrightness = "BaseBrightness",
	BaseSpeed = "BaseSpeed",
	BaseVolume = "BaseVolume",
	BaseTransparency = "BaseTransparency",
})
TemplatePrep.Attributes = ATTRIBUTES

-- Weak keys (__mode = "k"): this table doesn't keep templates alive on its own.
-- If a template is ever destroyed, its entry can be garbage collected.
local prepared: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function isContainer(part: BasePart): boolean
	if part:GetAttribute(ATTRIBUTES.KeepVisible) == true then
		return false
	end
	-- MeshParts, unions, wedges, balls and cylinders are deliberate shapes
	if not part:IsA("Part") or part.Shape ~= Enum.PartType.Block then
		return false
	end
	-- Glowing blocks are deliberate (laser cores, flashes)
	if part.Material == Enum.Material.Neon then
		return false
	end
	for _, child in part:GetChildren() do
		if child:IsA("DataModelMesh") or child:IsA("SurfaceAppearance") then
			return false -- it has a mesh or a surface look: it's meant to be seen
		end
	end
	return true
end

-- Only writes the attribute the FIRST time, so the authored value is never overwritten
local function remember(instance: Instance, attribute: string, value: any)
	if instance:GetAttribute(attribute) == nil then
		instance:SetAttribute(attribute, value)
	end
end

local function prepareInstance(instance: Instance)
	if instance:IsA("BasePart") then
		instance.Anchored = true
		instance.CanCollide = false
		instance.CanQuery = false
		instance.CanTouch = false
		instance.CastShadow = false
		if isContainer(instance) then
			instance.Transparency = 1
		end
	elseif instance:IsA("ParticleEmitter") then
		remember(instance, ATTRIBUTES.BaseEnabled, instance.Enabled)
	elseif instance:IsA("Light") then
		remember(instance, ATTRIBUTES.BaseBrightness, instance.Brightness)
	elseif instance:IsA("Sound") then
		remember(instance, ATTRIBUTES.BaseSpeed, instance.PlaybackSpeed)
		remember(instance, ATTRIBUTES.BaseVolume, instance.Volume)
		instance.Playing = false -- copies must not start playing the moment they enter the world
		instance.PlayOnRemove = false -- or play when a pooled copy is destroyed
	elseif instance:IsA("Decal") then -- Textures count too: Texture inherits from Decal
		remember(instance, ATTRIBUTES.BaseTransparency, instance.Transparency)
	end
end

local function pinPivot(template: Instance)
	if not template:IsA("Model") or template.PrimaryPart then
		return
	end
	local core = template:FindFirstChild("Core", true)
	local main = if core and core:IsA("BasePart") then core else template:FindFirstChildWhichIsA("BasePart", true)
	if main then
		template.PrimaryPart = main
	end
end

function TemplatePrep.prepare(template: Instance)
	if prepared[template] then
		return
	end
	prepared[template] = true

	prepareInstance(template)
	for _, descendant in template:GetDescendants() do
		prepareInstance(descendant)
	end
	pinPivot(template)
end

-- Number attribute with a fallback (attributes can hold any type, so check it)
function TemplatePrep.getNumber(instance: Instance, attribute: string, fallback: number): number
	local value = instance:GetAttribute(attribute)
	return if typeof(value) == "number" then value else fallback
end

local function resetInstance(instance: Instance)
	if instance:IsA("ParticleEmitter") then
		instance.Enabled = false
		instance:Clear() -- remove particles still in the air
	elseif instance:IsA("Sound") then
		instance:Stop()
		instance.PlaybackSpeed = TemplatePrep.getNumber(instance, ATTRIBUTES.BaseSpeed, instance.PlaybackSpeed)
		instance.Volume = TemplatePrep.getNumber(instance, ATTRIBUTES.BaseVolume, instance.Volume)
	elseif instance:IsA("Light") then
		instance.Brightness = TemplatePrep.getNumber(instance, ATTRIBUTES.BaseBrightness, instance.Brightness)
	elseif instance:IsA("Decal") then
		instance.Transparency = TemplatePrep.getNumber(instance, ATTRIBUTES.BaseTransparency, instance.Transparency)
	end
end

-- Puts a used (pooled) copy back exactly as the template was built: idle, silent, unscaled.
function TemplatePrep.reset(object: Instance)
	if object:IsA("Model") and object:GetScale() ~= 1 then
		object:ScaleTo(1)
	end
	resetInstance(object)
	for _, descendant in object:GetDescendants() do
		resetInstance(descendant)
	end
end

return TemplatePrep
