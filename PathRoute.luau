local cloneref = cloneref or function(x) return x end

local Players = cloneref(game:GetService("Players"))
local PathfindingService = cloneref(game:GetService("PathfindingService"))

local PathRoute = {}

local AGENT = { AgentRadius = 2, AgentHeight = 5, AgentCanJump = true }
local BODY = Vector3.new(0, 2.5, 0) -- torso height above the floor
local RADIUS = 1.5                  -- half character width, avoids clipping wall corners
local STEP = 2                      -- floor sample spacing along a straight line
local MAX_STEP_Y = 2                -- max floor height change per sample (ramps ok, ledges not)

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude

local nodes: { Vector3 } = {}
local edges: { { [number]: number } } = {}
local rootHeight = 3 -- root above floor, measured on each Go

local function getCharacter()
	local player = Players.LocalPlayer
	local character = player.Character or player.CharacterAdded:Wait()
	params.FilterDescendantsInstances = { character }
	return character:WaitForChild("HumanoidRootPart"), character:FindFirstChildOfClass("Humanoid")
end

local function toVector(p: Vector3 | CFrame): Vector3
	return if typeof(p) == "CFrame" then p.Position else p
end

local function toGround(pos: Vector3): Vector3
	local hit = workspace:Raycast(pos + Vector3.new(0, 3, 0), Vector3.new(0, -50, 0), params)
	return if hit then hit.Position else pos
end

-- True if the body hits nothing between a and b and there is floor the whole way.
local function canWalkStraight(a: Vector3, b: Vector3): boolean
	local dir = b - a
	local dist = dir.Magnitude
	if dist < 0.5 then return true end

	if workspace:Spherecast(a + BODY, RADIUS, dir, params) then
		return false
	end

	for d = STEP, dist, STEP do
		local p = a:Lerp(b, d / dist)
		local hit = workspace:Raycast(p + BODY, Vector3.new(0, -(BODY.Y + 4), 0), params)
		if not hit or math.abs(hit.Position.Y - p.Y) > MAX_STEP_Y then
			return false
		end
	end
	return true
end

-- Mover gets the position the HumanoidRootPart should reach, yields until there, returns success.
local mover = function(pos: Vector3): boolean
	local _, humanoid = getCharacter()
	humanoid:MoveTo(pos)
	return humanoid.MoveToFinished:Wait()
end

local function move(floorPos: Vector3): boolean
	return mover(floorPos + Vector3.new(0, rootHeight, 0))
end

-- Roblox pathfinding from the character to a floor point.
local function pathfindTo(goal: Vector3): boolean
	local root = getCharacter()
	for _ = 1, 3 do
		local path = PathfindingService:CreatePath(AGENT)
		local ok = pcall(path.ComputeAsync, path, root.Position, goal)
		if ok and path.Status == Enum.PathStatus.Success then
			local done = true
			for _, wp in path:GetWaypoints() do
				if not move(wp.Position) then done = false break end
			end
			if done then return true end
		end
	end
	warn("PathRoute: could not reach", goal)
	return false
end

-- Dijkstra over the point network. Returns node indices from -> to, or nil if unlinked.
local function shortestRoute(from: number, to: number): { number }?
	local dist, prev, done = {}, {}, {}
	for i = 1, #nodes do dist[i] = math.huge end
	dist[from] = 0

	while true do
		local u, best = nil, math.huge
		for i = 1, #nodes do
			if not done[i] and dist[i] < best then u, best = i, dist[i] end
		end
		if not u then return nil end
		if u == to then break end
		done[u] = true
		for v, w in edges[u] do
			if best + w < dist[v] then
				dist[v] = best + w
				prev[v] = u
			end
		end
	end

	local route = {}
	local n = to
	while n do
		table.insert(route, 1, n)
		n = prev[n]
	end
	return route
end

-- Which point to enter the network from `pos` (also used to leave it near the goal).
local function pickEntryNode(pos: Vector3): number
	-- TODO(human): prefer the nearest node that canWalkStraight(pos, node) can reach,
	-- fall back to the plain nearest node if none is reachable.
	local best, bestDist = 1, math.huge
	for i, node in nodes do
		local d = (node - pos).Magnitude
		if d < bestDist then best, bestDist = i, d end
	end
	return best
end

-- points: list of CFrame/Vector3. Links every pair with a clear straight line.
function PathRoute:SetPath(points: { Vector3 | CFrame })
	getCharacter() -- so raycasts ignore our own character
	nodes, edges = {}, {}
	for i, p in points do
		nodes[i] = toGround(toVector(p))
		edges[i] = {}
	end
	for i = 1, #nodes do
		for j = i + 1, #nodes do
			if canWalkStraight(nodes[i], nodes[j]) then
				local d = (nodes[i] - nodes[j]).Magnitude
				edges[i][j] = d
				edges[j][i] = d
			end
		end
	end
end

-- fn(rootPos: Vector3) -> boolean. Must yield until the root reaches rootPos.
function PathRoute:SetMover(fn: (Vector3) -> boolean)
	mover = fn
end

-- Pathfind onto the network, follow it (with shortcuts), then pathfind to the target.
function PathRoute:Go(target: Vector3 | CFrame): boolean
	local root = getCharacter()
	local here = toGround(root.Position)
	rootHeight = root.Position.Y - here.Y
	local goal = toGround(toVector(target))

	if canWalkStraight(here, goal) then
		return move(goal) or pathfindTo(goal)
	end
	if #nodes == 0 then
		return pathfindTo(goal)
	end

	local entry, exit = pickEntryNode(here), pickEntryNode(goal)
	local route = shortestRoute(entry, exit)
	if not route then
		warn("PathRoute: points are not linked, using pathfinding only")
		return pathfindTo(goal)
	end

	if not pathfindTo(nodes[entry]) then return false end

	local stops = {}
	for _, i in route do table.insert(stops, nodes[i]) end

	local i = 1 -- standing on stops[1] (entry)
	while i < #stops do
		-- Look from the farthest stop backwards; first one with a clear line is the shortcut.
		local from = toGround(root.Position)
		local j = i + 1
		for k = #stops, i + 2, -1 do
			if canWalkStraight(from, stops[k]) then j = k break end
		end
		if not move(stops[j]) and not pathfindTo(stops[j]) then return false end
		i = j
	end

	return pathfindTo(goal)
end

return PathRoute
