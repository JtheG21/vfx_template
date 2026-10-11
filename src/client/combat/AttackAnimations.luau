--!strict
--[[
	AttackAnimations
	Everything about attack animations, on the client:
	  - plays YOUR character's Charge and Fire animations (CombatInput calls this)
	  - lets effects wait for an animation's "Hit" marker, so a punch's flame shows
	    on the exact frame the fist connects (CombatVFX calls this)

	Slots in an attack's Animations table (all optional):
	  Charge                    loops while a Charge attack is held
	  Fire                      plays once when the attack goes off
	  ChargeLeft / ChargeRight  per-hand versions for Anchor = "AlternateHands".
	  FireLeft / FireRight      A missing hand falls back to the plain Charge / Fire.

	Every attack animation:
	  - gets a priority above walking and idling (set here, so Moon's setting can't break it)
	  - blends in and out over FADE_TIME instead of snapping
	  - is downloaded and loaded when your character spawns, so its first use isn't late

	HIT MARKERS: in Moon Animator, add a marker named "Hit" on the frame the attack
	connects. Melee and AOE effects wait for it. Damage still lands after HitDelay on
	the server (the server can't trust a client's timing), so keep the two equal.
	In Studio, the Output warns you when they disagree and says what HitDelay should be.
]]

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Combat = ReplicatedStorage:WaitForChild("Combat")
local Types = require(Combat.Types)
local Attacks = require(Combat.Attacks)
local CharacterUtil = require(Combat.Shared.CharacterUtil)

export type Slot = "Charge" | "Fire"

local FADE_TIME = 0.1 -- seconds to blend into and out of an attack animation
local HIT_MARKER = "Hit" -- the marker name to put on the hit frame in Moon Animator
local TRACK_WAIT = 0.25 -- how long another player's animation may arrive after their attack
local HIT_GRACE = 0.15 -- extra time to wait for a marker we've seen before (frame timing varies)
local HIT_TOLERANCE = 0.1 -- Studio warns when the marker and HitDelay are further apart than this

-- Higher priorities override lower ones, and both of these override walking and idling.
-- Fire is above Charge, so a release blends cleanly over the charge pose.
local PRIORITY: { [Slot]: Enum.AnimationPriority } = {
	Charge = Enum.AnimationPriority.Action,
	Fire = Enum.AnimationPriority.Action2,
}

-- Deliveries whose damage waits HitDelay on the server (see the server's Melee and AOE).
-- Only their effects wait for the Hit marker: a projectile or beam leaves the moment
-- you attack on the server, so its effects must too.
local SYNCED_DELIVERIES: { [string]: boolean } = { Melee = true, AOE = true }

local player = Players.LocalPlayer

local AttackAnimations = {}

-- The animation for a slot, for the hand being used (side is only set for AlternateHands)
function AttackAnimations.getId(animations: Types.AttackAnimations?, slot: Slot, side: Types.Side?): string?
	if not animations then
		return nil
	end
	if slot == "Charge" then
		local forHand = if side == "Left" then animations.ChargeLeft elseif side == "Right" then animations.ChargeRight else nil
		return forHand or animations.Charge
	end
	local forHand = if side == "Left" then animations.FireLeft elseif side == "Right" then animations.FireRight else nil
	return forHand or animations.Fire
end

----------------------------------------------------------------- CATALOG

-- One Animation object per id, shared by every character. They only hold the id.
local animationObjects: { [string]: Animation } = {}

local function getAnimationObject(id: string): Animation
	local existing = animationObjects[id]
	if existing then
		return existing
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = id
	animationObjects[id] = animation
	return animation
end

-- Every animation id any attack uses, without repeats
local function collectIds(): { string }
	local ids: { string } = {}
	local seen: { [string]: boolean } = {}
	for _, attack in Attacks do
		-- (any) lets us loop over the slots without naming each one
		for _, id in (attack.Animations or {}) :: any do
			if typeof(id) == "string" and not seen[id] then
				seen[id] = true
				table.insert(ids, id)
			end
		end
	end
	return ids
end

-------------------------------------------------------------- HIT MARKERS

-- Where each animation's Hit marker is (seconds into it), once we've seen it play
local hitTimes: { [string]: number } = {}
-- Tracks already listening for their marker. Weak keys: destroyed tracks are forgotten.
local watched: { [AnimationTrack]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local warned: { [string]: boolean } = {}

-- Studio only. When the marker and HitDelay disagree, the effect and the damage land at
-- different moments: say so once per attack and animation, with the number to use.
local function checkHitDelay(id: string, hitTime: number)
	if not RunService:IsStudio() then
		return
	end
	for attackId, attack in Attacks do
		-- Which of this attack's Fire slots uses the animation (nil = none of them)
		local animations = attack.Animations
		local slot = if not animations then nil
			elseif animations.FireLeft == id then "FireLeft"
			elseif animations.FireRight == id then "FireRight"
			elseif animations.Fire == id then "Fire"
			else nil
		local hitDelay = attack.HitDelay or 0
		local key = `{attackId}|{id}`
		if slot and SYNCED_DELIVERIES[attack.Delivery] and not warned[key] and math.abs(hitTime - hitDelay) > HIT_TOLERANCE then
			warned[key] = true
			local suggested = string.format("%.2f", hitTime)
			warn(
				`[Combat] {attackId}: the "{HIT_MARKER}" marker in Animations.{slot} is at about {suggested}s, but HitDelay is {hitDelay}.`
					.. ` Set HitDelay = {suggested} so the damage lands on the hit frame.`
			)
		end
	end
end

local function watchHitMarker(track: AnimationTrack, id: string)
	if watched[track] then
		return
	end
	watched[track] = true
	track:GetMarkerReachedSignal(HIT_MARKER):Connect(function()
		hitTimes[id] = track.TimePosition
		checkHitDelay(id, track.TimePosition)
	end)
end

-------------------------------------------------------------- YOUR TRACKS

-- Tracks belong to one Animator, and a new character brings a new Animator.
-- The cache notices the change and starts over by itself.
local loadedFor: Animator? = nil
local tracks: { [string]: AnimationTrack } = {}
local playing: { [Slot]: AnimationTrack } = {} -- what's playing in each slot right now

local function getTrack(animator: Animator, id: string): AnimationTrack
	if animator ~= loadedFor then
		loadedFor = animator
		table.clear(tracks)
		table.clear(playing)
	end
	local existing = tracks[id]
	if existing then
		return existing
	end
	local track = animator:LoadAnimation(getAnimationObject(id))
	tracks[id] = track
	watchHitMarker(track, id)
	return track
end

local function getLocalAnimator(): Animator?
	local humanoid = CharacterUtil.getAliveHumanoid(player.Character)
	return if humanoid then humanoid:FindFirstChildOfClass("Animator") else nil
end

-- Plays a slot's animation on YOUR character. Animations on your own character
-- replicate to everyone automatically, so other players see it too.
function AttackAnimations.play(attack: Types.AttackConfig, slot: Slot, side: Types.Side?)
	local id = AttackAnimations.getId(attack.Animations, slot, side)
	local animator = getLocalAnimator()
	if not id or not animator then
		return
	end
	local track = getTrack(animator, id)
	track.Priority = PRIORITY[slot]
	track.Looped = slot == "Charge"

	-- One animation per slot: the last punch blends out while this one blends in
	local previous = playing[slot]
	if previous and previous ~= track then
		previous:Stop(FADE_TIME)
	end
	playing[slot] = track
	track:Play(FADE_TIME) -- already playing? Play restarts it from the first frame
end

function AttackAnimations.stop(slot: Slot)
	local track = playing[slot]
	if track then
		playing[slot] = nil
		track:Stop(FADE_TIME)
	end
end

------------------------------------------------------------------ PRELOAD

-- Load every attack animation onto a new character up front, and make sure they're
-- downloaded (PreloadAsync waits until they are). Otherwise each one's first use can
-- start a few frames late, after the attack already happened.
local function onCharacterAdded(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	local animator = if humanoid then humanoid:WaitForChild("Animator", 10) else nil
	if not (animator and animator:IsA("Animator")) then
		return
	end
	-- Annotated as Instances: PreloadAsync takes any kind of Instance
	local animations: { Instance } = {}
	for _, id in collectIds() do
		getTrack(animator, id)
		table.insert(animations, getAnimationObject(id))
	end
	ContentProvider:PreloadAsync(animations)
end

player.CharacterAdded:Connect(onCharacterAdded)
if player.Character then
	task.spawn(onCharacterAdded, player.Character)
end

------------------------------------------------------------- WAIT FOR HIT

-- The same asset can be written different ways: "rbxassetid://123" or
-- "http://www.roblox.com/asset/?id=123". Compare the number at the end.
local function sameAnimation(a: string, b: string): boolean
	if a == b then
		return true
	end
	local numberA = string.match(a, "[/=](%d+)$")
	return numberA ~= nil and numberA == string.match(b, "[/=](%d+)$")
end

local function findPlayingTrack(animator: Animator, id: string): AnimationTrack?
	for _, track in animator:GetPlayingAnimationTracks() do
		local animation = track.Animation
		if animation and sameAnimation(animation.AnimationId, id) then
			return track
		end
	end
	return nil
end

-- PATTERN: "whichever happens first". `connect` hooks up some events and calls
-- `done(value)` when one fires. After `timeout` seconds we stop waiting and get nil.
-- Only the first call to `done` counts, and every connection is cleaned up.
local function waitForFirst(timeout: number, connect: (done: (any) -> ()) -> { RBXScriptConnection }): any
	local thread = coroutine.running()
	local finished = false
	local connections: { RBXScriptConnection } = {}
	local function done(value: any)
		if finished then
			return
		end
		finished = true
		for _, connection in connections do
			connection:Disconnect()
		end
		task.spawn(thread, value) -- wake the waiting thread up, handing it the value
	end
	connections = connect(done)
	task.delay(timeout, done, nil)
	return coroutine.yield() -- pause here until `done` wakes us
end

-- Another player's animation reaches us separately from their attack, and can be a
-- moment behind it. Look for it, and wait briefly if it isn't here yet.
local function findTrack(animator: Animator, id: string): AnimationTrack?
	local playingTrack = findPlayingTrack(animator, id)
	if playingTrack then
		return playingTrack
	end
	return waitForFirst(TRACK_WAIT, function(done)
		return {
			animator.AnimationPlayed:Connect(function(track)
				local animation = track.Animation
				if animation and sameAnimation(animation.AnimationId, id) then
					done(track)
				end
			end),
		}
	end)
end

local function waitForMarker(track: AnimationTrack, timeout: number)
	waitForFirst(timeout, function(done)
		return {
			track:GetMarkerReachedSignal(HIT_MARKER):Connect(done),
			track.Stopped:Connect(done),
		}
	end)
end

-- Yields until `character`'s attack animation reaches its Hit marker. Returns at once
-- when there's nothing to wait for: not a Melee or AOE attack, no animation, the
-- animation never showed up, or the hit frame already passed (a slow connection).
function AttackAnimations.waitForHit(character: Model, attack: Types.AttackConfig, side: Types.Side?)
	if not SYNCED_DELIVERIES[attack.Delivery] then
		return
	end
	local id = AttackAnimations.getId(attack.Animations, "Fire", side)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = if humanoid then humanoid:FindFirstChildOfClass("Animator") else nil
	if not id or not animator then
		return
	end
	local track = findTrack(animator, id)
	if not track then
		return
	end
	watchHitMarker(track, id)

	-- Expect the hit where we've seen this marker before, or at HitDelay until we have.
	-- Until then HitDelay is also the deadline, so an animation with no marker never
	-- holds effects back past the moment the damage lands.
	local learned = hitTimes[id]
	local remaining = (learned or attack.HitDelay or 0) - track.TimePosition
	if remaining > 0 then
		waitForMarker(track, remaining + (if learned then HIT_GRACE else 0))
	end
end

return AttackAnimations
