--!strict
--[[
	VFXUtil
	How every effect is played. Three modes cover everything:

	  burst(root)    fire once: every emitter emits, sounds play, lights flash and fade.
	                 Returns how long until it has fully played out.
	  sustain(root)  keep running: emitters authored ON stream, emitters authored OFF
	                 pop once, sounds play (looped ones keep looping), lights on.
	  stop(root)     end a sustained effect: streaming stops, looped sounds stop, lights fade.
	                 Returns how long until what's left has faded out.

	On top of those:
	  playBurst(path, cframe)    a pooled burst placed in the world (impacts, blood)
	  attachKit / detachKit      a sustained kit on body parts (auras, charge-ups)
	  burstKit(path, parts)      a one-shot kit on body parts (cast flashes, punches)

	TEMPLATE TIPS
	  - ParticleEmitter attribute EmitCount (number): particles per burst (default 20).
	  - Sound attribute PitchVariance (number): random pitch change (default 0.05 = +/-5%).
	  - Sound attribute MaxDuration (number): fade the sound out after this many seconds,
	    for sounds that run longer than the effect should.
	  - Looped sounds fade in when they start and fade out when they stop, so loops never
	    pop on or cut off.
	  - Put Sounds inside a Part or Attachment so they come FROM the effect's position.
	  - In kits, only Attachments and effects sitting directly on parts are copied to the
	    character; the parts themselves are not.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Combat = ReplicatedStorage:WaitForChild("Combat")
local Types = require(Combat.Types)
local Settings = require(Combat.Settings)
local CameraShake = require(Combat.Shared.CameraShake)
local AssetPool = require(script.Parent.AssetPool)
local TemplatePrep = require(script.Parent.TemplatePrep)

local ATTRIBUTES = TemplatePrep.Attributes
local DEFAULT_EMIT_COUNT = 20
local DEFAULT_PITCH_VARIANCE = 0.05
local UNLOADED_SOUND_LENGTH = 2 -- seconds to assume for a sound that hasn't loaded yet
local MIN_FADE_TIME = 0.1
local SOUND_FADE_IN = 0.15 -- looped sounds ease in instead of popping on
local SOUND_FADE_OUT = 0.3 -- sounds ease out instead of cutting off

local VFXUtil = {}

-- Every effect on screen lives in this folder. Raycasts can exclude it in one go.
-- A module only runs ONCE per client, however many scripts require it,
-- so every script shares this same folder.
local container = Instance.new("Folder")
container.Name = "ActiveVFX"
container.Parent = workspace
VFXUtil.Container = container

--------------------------------------------------------------- BUILDING BLOCKS

-- Calls `callback` for `root` itself and everything inside it
local function forEach(root: Instance, callback: (Instance) -> ())
	callback(root)
	for _, descendant in root:GetDescendants() do
		callback(descendant)
	end
end

local function emitOnce(emitter: ParticleEmitter)
	emitter:Emit(TemplatePrep.getNumber(emitter, ATTRIBUTES.EmitCount, DEFAULT_EMIT_COUNT))
end

-- Every time a sound plays it gets a new number. Delayed fades check the number first,
-- so a fade meant for an OLD play never touches a pooled sound that's playing again.
local playIds: { [Sound]: number } = setmetatable({}, { __mode = "k" }) :: any

local function fadeOutSound(sound: Sound)
	local playId = playIds[sound]
	local tween = TweenService:Create(sound, TweenInfo.new(SOUND_FADE_OUT), { Volume = 0 })
	tween.Completed:Connect(function(state)
		if state == Enum.PlaybackState.Completed and playIds[sound] == playId then
			sound:Stop()
		end
	end)
	tween:Play()
end

local function playSound(sound: Sound)
	local baseSpeed = TemplatePrep.getNumber(sound, ATTRIBUTES.BaseSpeed, sound.PlaybackSpeed)
	local baseVolume = TemplatePrep.getNumber(sound, ATTRIBUTES.BaseVolume, sound.Volume)
	local variance = TemplatePrep.getNumber(sound, ATTRIBUTES.PitchVariance, DEFAULT_PITCH_VARIANCE)
	-- math.random() * 2 - 1 is a random number from -1 to 1, so the pitch lands
	-- anywhere within +/- variance. Repeated hits never sound copy-pasted.
	sound.PlaybackSpeed = baseSpeed * (1 + (math.random() * 2 - 1) * variance)

	local playId = (playIds[sound] or 0) + 1
	playIds[sound] = playId

	if sound.Looped then
		sound.Volume = 0
		sound:Play()
		TweenService:Create(sound, TweenInfo.new(SOUND_FADE_IN), { Volume = baseVolume }):Play()
	else
		sound.Volume = baseVolume
		sound:Play()
	end

	local maxDuration = TemplatePrep.getNumber(sound, ATTRIBUTES.MaxDuration, 0)
	if maxDuration > 0 then
		task.delay(maxDuration, function()
			if playIds[sound] == playId and sound.IsPlaying then
				fadeOutSound(sound)
			end
		end)
	end
end

local function getSoundLength(sound: Sound): number
	if sound.Looped then
		return 0 -- looped sounds are stopped by code, they don't set the lifetime
	end
	local length = if sound.TimeLength > 0 then sound.TimeLength else UNLOADED_SOUND_LENGTH
	local duration = length / math.max(sound.PlaybackSpeed, 0.01)
	local maxDuration = TemplatePrep.getNumber(sound, ATTRIBUTES.MaxDuration, 0)
	if maxDuration > 0 then
		duration = math.min(duration, maxDuration + SOUND_FADE_OUT)
	end
	return duration
end

-- Lights always start from their authored brightness (a pooled light may have been faded)
local function resetLight(light: Light)
	light.Brightness = TemplatePrep.getNumber(light, ATTRIBUTES.BaseBrightness, light.Brightness)
end

local function fadeLight(light: Light, duration: number)
	TweenService:Create(light, TweenInfo.new(math.max(duration, MIN_FADE_TIME)), { Brightness = 0 }):Play()
end

-- How long until everything inside `root` has played out: the slowest particle
-- or the longest one-shot sound.
function VFXUtil.getLifetime(root: Instance): number
	local longest = 0
	forEach(root, function(instance)
		if instance:IsA("ParticleEmitter") then
			-- Lifetime is a NumberRange (Min to Max). We want the slowest particle.
			longest = math.max(longest, instance.Lifetime.Max)
		elseif instance:IsA("Sound") then
			longest = math.max(longest, getSoundLength(instance))
		end
	end)
	return longest
end

-------------------------------------------------------------------- PLAY MODES

-- Root must already be in the workspace: particles and sounds outside it do nothing.
function VFXUtil.burst(root: Instance): number
	local lifetime = VFXUtil.getLifetime(root)
	forEach(root, function(instance)
		if instance:IsA("ParticleEmitter") then
			emitOnce(instance)
		elseif instance:IsA("Sound") then
			playSound(instance)
		elseif instance:IsA("Light") then
			resetLight(instance)
			fadeLight(instance, lifetime) -- a flash that dims as the effect plays out
		end
	end)
	return lifetime
end

function VFXUtil.sustain(root: Instance)
	forEach(root, function(instance)
		if instance:IsA("ParticleEmitter") then
			-- Authored ON = a stream (a trail, a flame). Authored OFF = a pop at the start.
			if instance:GetAttribute(ATTRIBUTES.BaseEnabled) == false then
				emitOnce(instance)
			else
				instance.Enabled = true
			end
		elseif instance:IsA("Sound") then
			playSound(instance)
		elseif instance:IsA("Light") then
			resetLight(instance)
		end
	end)
end

function VFXUtil.stop(root: Instance): number
	local fadeTime = 0
	forEach(root, function(instance)
		if instance:IsA("ParticleEmitter") then
			instance.Enabled = false
			fadeTime = math.max(fadeTime, instance.Lifetime.Max)
		end
	end)
	local fadingSound = false
	forEach(root, function(instance)
		if instance:IsA("Sound") and instance.Looped and instance.IsPlaying then
			fadeOutSound(instance)
			fadingSound = true
		elseif instance:IsA("Light") then
			fadeLight(instance, fadeTime)
		end
	end)
	-- Never 0: lights need a moment to fade even when there are no particles,
	-- and a fading loop needs its fade-out time before the effect is removed
	return math.max(fadeTime, MIN_FADE_TIME, if fadingSound then SOUND_FADE_OUT else 0)
end

-------------------------------------------------------------- PLACED EFFECTS

-- Pulls an effect from its pool, places it, bursts it, then returns it to the pool afterwards.
function VFXUtil.playBurst(path: string?, cframe: CFrame)
	if not path then
		return
	end
	local effect = AssetPool.get(path)
	if not effect then
		return
	end
	if effect:IsA("PVInstance") then
		effect:PivotTo(cframe)
	end
	effect.Parent = container -- must be in workspace BEFORE bursting, or nothing shows

	local lifetime = VFXUtil.burst(effect)
	task.delay(lifetime, function()
		AssetPool.release(path, effect)
	end)
end

------------------------------------------------------------------------ KITS

-- Effects that can live inside an Attachment
local function isAttachableEffect(instance: Instance): boolean
	return instance:IsA("ParticleEmitter") or instance:IsA("Light") or instance:IsA("Sound")
end

-- A kit's "prototype" is the list of Attachments to copy onto the character,
-- built once per template and cached (weak keys, like TemplatePrep).
--   - Attachments in the template are used as they are (keeping their offset).
--   - Effects sitting directly on a part (common in VFX packs) are gathered into a
--     new Attachment, so templates work either way.
local prototypes: { [Instance]: { Attachment } } = setmetatable({}, { __mode = "k" }) :: any

local function getPrototype(template: Instance): { Attachment }
	local cached = prototypes[template]
	if cached then
		return cached
	end

	local prototype = {}
	-- The template itself counts too: it may be a single Part with effects right on it
	local candidates = template:GetDescendants()
	table.insert(candidates, 1, template)
	for _, descendant in candidates do
		if descendant:IsA("Attachment") then
			table.insert(prototype, descendant)
		elseif descendant:IsA("BasePart") then
			local holder: Attachment? = nil
			for _, child in descendant:GetChildren() do
				if isAttachableEffect(child) then
					-- Create the holder only once we know there's something to put in it
					if not holder then
						holder = Instance.new("Attachment")
					end
					child:Clone().Parent = holder
				end
			end
			if holder then
				holder.Name = descendant.Name
				table.insert(prototype, holder)
			end
		end
	end

	prototypes[template] = prototype
	return prototype
end

local function copyKit(path: string, parts: { BasePart }): { Attachment }
	local attachments = {}
	local template = if #parts > 0 then AssetPool.findTemplate(path) else nil
	if not template then
		return attachments
	end
	for index, part in parts do
		for _, piece in getPrototype(template) do
			local copy = piece:Clone()
			-- A kit on several parts (BothHands, Feet) shows its particles on each one, but
			-- plays its sounds only once. The same sound from both hands would play doubled.
			if index > 1 then
				for _, descendant in copy:GetDescendants() do
					if descendant:IsA("Sound") then
						descendant:Destroy()
					end
				end
			end
			copy.Parent = part
			table.insert(attachments, copy)
		end
	end
	return attachments
end

-- A kit that stays on until detachKit (auras, charge-ups)
function VFXUtil.attachKit(path: string, parts: { BasePart }): { Attachment }
	local attachments = copyKit(path, parts)
	for _, attachment in attachments do
		VFXUtil.sustain(attachment)
	end
	return attachments
end

-- Fades a kit out, then removes it. Removing instantly would make particles
-- already in the air vanish mid-flight.
function VFXUtil.detachKit(attachments: { Attachment })
	local fadeTime = 0
	for _, attachment in attachments do
		-- Parent is nil once destroyed, e.g. the character died and took the kit with it
		if attachment.Parent then
			fadeTime = math.max(fadeTime, VFXUtil.stop(attachment))
		end
	end
	task.delay(fadeTime, function()
		for _, attachment in attachments do
			attachment:Destroy() -- safe even if the character (and the attachment) is already gone
		end
	end)
end

-- A kit that fires once and cleans itself up (cast flashes, punches, full-charge pops)
function VFXUtil.burstKit(path: string?, parts: { BasePart })
	if not path then
		return
	end
	local attachments = copyKit(path, parts)
	local lifetime = 0
	for _, attachment in attachments do
		lifetime = math.max(lifetime, VFXUtil.burst(attachment))
	end
	task.delay(lifetime, function()
		for _, attachment in attachments do
			attachment:Destroy()
		end
	end)
end

--------------------------------------------------------------------- HELPERS

-- The part named "Core", or else the first BasePart. Beams stretch this part.
function VFXUtil.getMainPart(root: Instance): BasePart?
	if root:IsA("BasePart") then
		return root
	end
	local core = root:FindFirstChild("Core", true) -- `true` = search ALL descendants, not just children
	if core and core:IsA("BasePart") then
		return core
	end
	return root:FindFirstChildWhichIsA("BasePart", true)
end

-- Builds a CFrame whose TOP face (UpVector) points along `normal`.
-- A flat decal part placed with this lies flat on any wall, floor or ceiling.
function VFXUtil.surfaceCFrame(position: Vector3, normal: Vector3): CFrame
	-- Need any vector that is NOT parallel to the normal to build the other axes from
	local reference = if math.abs(normal.Y) < 0.99 then Vector3.yAxis else Vector3.xAxis
	-- Cross product = a vector at 90 degrees to both inputs
	local right = reference:Cross(normal).Unit
	-- fromMatrix(position, rightVector, upVector). The 3rd axis is worked out automatically.
	return CFrame.fromMatrix(position, right, normal)
end

-- Shakes the LOCAL player's camera, weaker the further they are from `position`.
function VFXUtil.shakeAt(shake: Types.ShakeProfile?, position: Vector3)
	if not shake then
		return
	end
	local character = Players.LocalPlayer.Character
	if not character then
		return
	end
	local distance = (position - character:GetPivot().Position).Magnitude
	if distance >= Settings.ShakeRadius then
		return
	end
	local falloff = 1 - distance / Settings.ShakeRadius -- 1 right on top of it, 0 at the edge
	CameraShake.start(shake.Intensity * falloff, shake.Frequency, shake.Duration)
end

return VFXUtil
