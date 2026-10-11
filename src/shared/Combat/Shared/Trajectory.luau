--!strict
--[[
	Trajectory
	The flight path of a projectile, shared by the server (hit detection) and every
	client (visuals). Both sides run this SAME math from the SAME inputs, so they
	agree on where the projectile is without sending its position over the network.

	A path is a quadratic Bezier curve: it starts at Origin, ends at Target, and is
	"pulled" toward a Control point in between.
	    ArcHeight = 0  -> the control point sits on the straight line -> a straight shot
	    ArcHeight > 0  -> the control point is lifted                 -> a lob / arc

	    local path = Trajectory.new(origin, target, 20)
	    local position = Trajectory.getPoint(path, 0.5) -- halfway along the curve
]]

local Trajectory = {}

export type Path = {
	Origin: Vector3,
	Control: Vector3,
	Target: Vector3,
	Length: number, -- approximate length of the curve in studs
}

-- More samples = more accurate length, but slower. 16 is plenty for gameplay.
local LENGTH_SAMPLES = 16

-- Quadratic Bezier formula:
--   B(t) = (1 - t)^2 * P0  +  2(1 - t)t * P1  +  t^2 * P2
-- t = 0 gives P0 (start), t = 1 gives P2 (end), values in between slide along the curve.
function Trajectory.getPoint(path: Path, t: number): Vector3
	local u = 1 - t
	return path.Origin * (u * u) + path.Control * (2 * u * t) + path.Target * (t * t)
end

function Trajectory.new(origin: Vector3, target: Vector3, arcHeight: number?): Path
	-- A quadratic curve only climbs HALFWAY to its control point, so to peak
	-- `arcHeight` studs above the midpoint the control point goes twice as high.
	local control = origin:Lerp(target, 0.5) + Vector3.yAxis * ((arcHeight or 0) * 2)

	local path: Path = { Origin = origin, Control = control, Target = target, Length = 0 }

	-- A Bezier curve has no simple length formula, so measure it: chop it into
	-- short straight pieces and add up their lengths.
	local length = 0
	local previous = origin
	for i = 1, LENGTH_SAMPLES do
		local point = Trajectory.getPoint(path, i / LENGTH_SAMPLES)
		length += (point - previous).Magnitude
		previous = point
	end
	path.Length = length

	return path
end

return Trajectory
