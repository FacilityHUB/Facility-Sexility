--!nocheck
--!nolint UnknownGlobal

local F       = shared.Facility
local Library = F.Library
local Entity  = F.Entity
local Esp     = F.Esp

local MOVEMENT_URL = "https://raw.githubusercontent.com/FacilityHUB/Facility-Sexility/refs/heads/main/CModules/FMovement.luau"

local function fetchModule(url, label)
	local ok, result = pcall(function()
		return loadstring(game:HttpGet(url .. "?v=" .. tostring(tick()):gsub("%.", "")))()
	end)

	if not ok or type(result) ~= "table" then
		warn("Facility: could not load " .. label .. " from " .. url)
		return nil
	end

	return result
end

local Movement = fetchModule(MOVEMENT_URL, "movement")

if Movement then Movement:Load() end

F.Movement = Movement

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local TeleportService = game:GetService("TeleportService")
local UserInputService = game:GetService("UserInputService")
local VirtualUser = game:GetService("VirtualUser")

local LocalPlayer = Players.LocalPlayer

local Remotes = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Game")
local ActiveEggs = ReplicatedStorage:WaitForChild("ServerData"):WaitForChild("ActiveEggs")

local function requireData(name)
	local ok, result = pcall(function()
		return require(ReplicatedStorage.GameData[name])
	end)
	return ok and result or nil
end

local Data = {
	Eggs       = requireData("Eggs"),
	Pets       = requireData("Pets"),
	Foods      = requireData("Foods"),
	Shop       = requireData("Shop"),
	Rebirths   = requireData("Rebirths"),
	EggBaskets = requireData("EggBaskets"),
	Mutations  = requireData("Mutations"),
}

local RARITY_ORDER = { "Common", "Rare", "Epic", "Legendary", "Mythic", "Divine", "Ethereal" }

local RARITY_RANK = {}
for index, name in ipairs(RARITY_ORDER) do
	RARITY_RANK[name] = index
end

local RARITY_CHOICES = { "Any" }
for _, name in ipairs(RARITY_ORDER) do
	table.insert(RARITY_CHOICES, name)
end

local RARITY_COLORS = {
	Common    = Color3.fromRGB(214, 218, 228),
	Rare      = Color3.fromRGB(96, 170, 255),
	Epic      = Color3.fromRGB(190, 110, 255),
	Legendary = Color3.fromRGB(255, 196, 66),
	Mythic    = Color3.fromRGB(255, 82, 90),
	Divine    = Color3.fromRGB(255, 240, 150),
	Ethereal  = Color3.fromRGB(125, 225, 255),
}

local cleanupTasks = {}

local function onCleanup(fn)
	table.insert(cleanupTasks, fn)
end

local Game = {
	FlySpeed = 600,
	CruiseHeight = 250,
	Status = "Idle",
	Movement = { Owner = nil },
	RarityOrder = RARITY_ORDER,
	RarityRank = RARITY_RANK,
	RarityChoices = RARITY_CHOICES,
	RarityColors = RARITY_COLORS,
}

local random = Random.new()
local plotCache = nil

function Game.Character()
	return LocalPlayer.Character
end

function Game.Humanoid()
	local character = LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")

	if humanoid and humanoid.Health > 0 then return humanoid end

	return nil
end

function Game.Root()
	local character = LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")

	if root and root:IsDescendantOf(workspace) then return root end

	return nil
end

function Game.Plot()
	if plotCache and plotCache.Parent then
		local data = plotCache:FindFirstChild("Data")
		local owner = data and data:FindFirstChild("Owner")
		if owner and owner.Value == LocalPlayer then return plotCache end
	end

	plotCache = nil

	local plots = workspace:FindFirstChild("Plots")
	if not plots then return nil end

	for _, child in ipairs(plots:GetChildren()) do
		local data = child:FindFirstChild("Data")
		local owner = data and data:FindFirstChild("Owner")

		if owner and owner.Value == LocalPlayer then
			plotCache = child
			return child
		end
	end

	return nil
end

function Game.PlotBase()
	local plot = Game.Plot()
	local baseplate = plot and plot:FindFirstChild("Baseplate")

	if baseplate and baseplate:IsA("BasePart") then return baseplate end

	return nil
end

function Game.PlotTop()
	local base = Game.PlotBase()
	if not base then return nil end

	return base.Position + Vector3.new(0, base.Size.Y / 2, 0)
end

function Game.RandomPlotPoint(margin, taken, spacing)
	local base = Game.PlotBase()
	if not base then return nil end

	local halfX = math.max(1, base.Size.X / 2 - margin)
	local halfZ = math.max(1, base.Size.Z / 2 - margin)
	local top = base.Position.Y + base.Size.Y / 2

	local fallback = nil

	for _ = 1, 24 do
		local offset = Vector3.new(random:NextNumber(-halfX, halfX), 0, random:NextNumber(-halfZ, halfZ))
		local world = base.CFrame:PointToWorldSpace(offset)
		local point = Vector3.new(world.X, top, world.Z)

		local free = true

		if taken then
			for _, used in ipairs(taken) do
				if Vector3.new(used.X - point.X, 0, used.Z - point.Z).Magnitude < spacing then
					free = false
					break
				end
			end
		end

		if free then return point end

		fallback = fallback or point
	end

	return fallback
end

function Game.Cash()
	local saved = LocalPlayer:FindFirstChild("SavedData")
	local cash = saved and saved:FindFirstChild("Cash")
	return cash and tonumber(cash.Value) or 0
end

function Game.Saved(name)
	local saved = LocalPlayer:FindFirstChild("SavedData")
	local value = saved and saved:FindFirstChild(name)
	return value and value.Value or nil
end

function Game.Fire(name, ...)
	local remote = Remotes:FindFirstChild(name)
	if not remote or not remote:IsA("RemoteEvent") then return false end

	local args = table.pack(...)

	return pcall(function()
		remote:FireServer(table.unpack(args, 1, args.n))
	end)
end

function Game.EggData(name)
	local eggs = Data.Eggs
	local entry = type(eggs) == "table" and eggs[tostring(name)] or nil
	return type(entry) == "table" and entry or nil
end

function Game.EggRank(name)
	local entry = Game.EggData(name)
	return entry and RARITY_RANK[tostring(entry.Rarity)] or 0
end

function Game.EggRarity(name)
	local entry = Game.EggData(name)
	return entry and tostring(entry.Rarity) or "Common"
end

function Game.EggLuck(name)
	local entry = Game.EggData(name)
	return entry and tonumber(entry.Luck) or 0
end

function Game.PetData(name)
	local pets = Data.Pets
	local entry = type(pets) == "table" and pets[tostring(name)] or nil
	return type(entry) == "table" and entry or nil
end

function Game.MutationBonus(name)
	local mutations = Data.Mutations
	local entry = type(mutations) == "table" and name and mutations[tostring(name)] or nil
	return 1 + (type(entry) == "table" and tonumber(entry.StatMultiplier) or 0) / 100
end

function Game.PetScore(name, weight, mutation)
	local entry = Game.PetData(name)
	return (entry and tonumber(entry.Income) or 1)
		* math.max(tonumber(weight) or 1, 0.1)
		* Game.MutationBonus(mutation)
end

function Game.PetNameOf(instance)
	local attribute = instance:GetAttribute("PetName")

	if type(attribute) == "string" and attribute ~= "" then return attribute end

	return (string.gsub(instance.Name, "%s*%[.*$", ""))
end

function Game.Tools(tag)
	local found = {}

	local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")

	if backpack then
		for _, child in ipairs(backpack:GetChildren()) do
			if child:IsA("Tool") and CollectionService:HasTag(child, tag) then
				table.insert(found, child)
			end
		end
	end

	local character = LocalPlayer.Character

	if character then
		for _, child in ipairs(character:GetChildren()) do
			if child:IsA("Tool") and CollectionService:HasTag(child, tag) then
				table.insert(found, child)
			end
		end
	end

	return found
end

function Game.Equip(tool)
	local humanoid = Game.Humanoid()
	local character = LocalPlayer.Character

	if not humanoid or not tool or not character then return false end
	if tool.Parent == character then return true end

	pcall(function() humanoid:EquipTool(tool) end)

	local deadline = os.clock() + 1

	while tool.Parent ~= character and os.clock() < deadline do
		RunService.Heartbeat:Wait()
	end

	return tool.Parent == character
end

function Game.Unequip()
	local humanoid = Game.Humanoid()

	if humanoid then
		pcall(function() humanoid:UnequipTools() end)
	end
end

function Game.BasketCount()
	local basket = LocalPlayer:FindFirstChild("Basket")
	return basket and #basket:GetChildren() or 0
end

function Game.BasketCapacity()
	local equipped = Game.Saved("EquippedEggBasket")
	local baskets = Data.EggBaskets
	local entry = type(baskets) == "table" and equipped and baskets[tostring(equipped)] or nil
	local capacity = type(entry) == "table" and tonumber(entry.Capacity) or 1

	if capacity == math.huge or capacity > 50 then return 50 end

	return math.max(1, capacity)
end

function Game.BasketDeadline()
	local basket = LocalPlayer:FindFirstChild("Basket")
	if not basket then return nil end

	local earliest = nil

	for _, child in ipairs(basket:GetChildren()) do
		local breakAt = tonumber(child:GetAttribute("BreakAt"))
		if breakAt and (earliest == nil or breakAt < earliest) then
			earliest = breakAt
		end
	end

	return earliest
end

function Game.Claim(owner)
	local movement = Game.Movement

	if movement.Owner == nil or movement.Owner == owner then
		movement.Owner = owner
		return true
	end

	return false
end

function Game.Release(owner)
	if Game.Movement.Owner == owner then
		Game.Movement.Owner = nil
	end
end

local collideCache = {}

local function setNoclip(state)
	local character = LocalPlayer.Character
	if not character then return end

	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") then
			if state then
				if collideCache[descendant] == nil then
					collideCache[descendant] = descendant.CanCollide
				end
				descendant.CanCollide = false
			elseif collideCache[descendant] ~= nil then
				descendant.CanCollide = collideCache[descendant]
			end
		end
	end

	if not state then table.clear(collideCache) end
end

Game.SetNoclip = setNoclip

local function pathTo(from, to)
	if Vector3.new(to.X - from.X, 0, to.Z - from.Z).Magnitude < 80
		and math.abs(to.Y - from.Y) < 30 then
		return { to }
	end

	local height = math.max(from.Y, to.Y) + Game.CruiseHeight

	return {
		Vector3.new(from.X, height, from.Z),
		Vector3.new(to.X, height, to.Z),
		to,
	}
end

function Game.TravelTime(from, to)
	local total = 0

	for _, point in ipairs(pathTo(from, to)) do
		total = total + (point - from).Magnitude
		from = point
	end

	return total / math.max(Game.FlySpeed, 20)
end

function Game.FlyTo(target, abort, tolerance)
	local root = Game.Root()
	if not root or typeof(target) ~= "Vector3" then return false end

	local reach = tolerance or 3
	if (root.Position - target).Magnitude <= reach then return true end

	local path = pathTo(root.Position, target)
	local deadline = os.clock() + Game.TravelTime(root.Position, target) + 6

	setNoclip(true)

	local connection = RunService.Stepped:Connect(function()
		local character = LocalPlayer.Character
		if not character then return end

		for _, descendant in ipairs(character:GetDescendants()) do
			if descendant:IsA("BasePart") and descendant.CanCollide then
				descendant.CanCollide = false
			end
		end
	end)

	local index = 1
	local arrived = false

	while os.clock() < deadline do
		if abort and abort() then break end

		local dt = RunService.Heartbeat:Wait()
		local current = Game.Root()
		if not current then break end

		local last = index == #path
		local offset = path[index] - current.Position
		local distance = offset.Magnitude

		if distance <= (last and reach or 2) then
			if last then
				arrived = true
				break
			end

			index = index + 1
		else
			local step = math.min(distance, math.max(Game.FlySpeed, 20) * dt)
			local flat = Vector3.new(offset.X, 0, offset.Z)
			local rotation = flat.Magnitude > 0.1
				and CFrame.lookAt(Vector3.zero, flat.Unit)
				or current.CFrame.Rotation

			pcall(function()
				current.CFrame = CFrame.new(current.Position + offset.Unit * step) * rotation
				current.AssemblyLinearVelocity = Vector3.zero
				current.AssemblyAngularVelocity = Vector3.zero
			end)
		end
	end

	connection:Disconnect()
	setNoclip(false)

	local final = Game.Root()

	if final then
		pcall(function() final.AssemblyLinearVelocity = Vector3.zero end)

		if (final.Position - target).Magnitude <= reach + 1 then return true end
	end

	return arrived
end

function Game.FirePrompt(prompt)
	if not prompt or not prompt:IsA("ProximityPrompt") then return false end

	if typeof(fireproximityprompt) == "function" then
		return pcall(fireproximityprompt, prompt)
	end

	return pcall(function()
		prompt:InputHoldBegin()
		task.wait(prompt.HoldDuration + 0.1)
		prompt:InputHoldEnd()
	end)
end

onCleanup(function() setNoclip(false) end)

local Farm = {
	Collect = false,
	Plant = false,
	Hatch = false,
	Place = false,
	Swap = false,
	Feed = false,
	Busy = false,
	Manual = {},
	Carried = {},
	Target = nil,
	TargetManual = false,
	Dropped = nil,
	PickupPos = nil,
	LastPickupAt = 0,
	Relaying = false,
}

local Collect = {
	MinRank = 0,
	Targets = {},
	Priority = "Highest Rarity",
	Cooldowns = {},
}

local MUTATION_MULTIPLIER = {
	Shocked = 2,
	Volted = 3,
	Rage = 4,
	Void = 10,
	Magma = 10,
	Eternal = 100,
}

local MUTATION_WEIGHT = {
	Eternal = 100000,
	Magma = 75000,
	Void = 50000,
	Rage = 20000,
	Volted = 10000,
	Shocked = 5000,
}

local STORM_TO_MUTATION = {
	Thunder = "Shocked",
	Volt = "Volted",
	Raging = "Rage",
	Dreadful = "Void",
	Eternal = "Eternal",
}

local MUTATION_TIERS = {
	"Any Mutation",
	"Volted and above",
	"Rage and above",
	"Void and above",
	"Eternal only",
}

local MUTATION_TIER_VALUE = {
	["Any Mutation"] = 2,
	["Volted and above"] = 3,
	["Rage and above"] = 4,
	["Void and above"] = 10,
	["Eternal only"] = 100,
}

local Mutations = {
	Prioritize = true,
	WaitForStorm = false,
	MinTier = "Any Mutation",
	Notify = true,
}

local function activeStorm()
	local serverData = ReplicatedStorage:FindFirstChild("ServerData")
	if not serverData then return nil end

	local raw = serverData:GetAttribute("ActiveWeathers")
	if not raw or raw == "" or raw == "[]" then return nil end

	local ok, decoded = pcall(function()
		return HttpService:JSONDecode(raw)
	end)

	if not ok or type(decoded) ~= "table" then return nil end

	local now = workspace:GetServerTimeNow()

	for _, entry in ipairs(decoded) do
		if entry.Type == "Storm" and entry.Variant
			and (not entry.EndsAt or entry.EndsAt > now) then
			return entry
		end
	end

	return nil
end

local function mutationPasses(mutation)
	if not mutation or mutation == "" then return false end

	local value = MUTATION_MULTIPLIER[mutation] or 1
	local required = MUTATION_TIER_VALUE[Mutations.MinTier] or 2

	return value >= required
end

local function mutationOf(entry)
	local mutation = entry:GetAttribute("Mutation")
	if mutation and mutation ~= "" then return mutation end

	if entry:FindFirstChild("MutationHitbox") then
		local storm = activeStorm()

		if storm and storm.Variant and STORM_TO_MUTATION[storm.Variant] then
			return STORM_TO_MUTATION[storm.Variant]
		end

		return "Shocked"
	end

	return nil
end

local Weight = {
	PreferHeaviest = false,
	Minimum = 0,
}

local PRIORITIES = { "Highest Luck", "Highest Rarity", "Nearest", "Farthest" }

local SAFETY_MARGIN = 3
local RELAY_DISTANCE = 250

local eggChoices = {}

do
	local ranked = {}

	if type(Data.Eggs) == "table" then
		for name, egg in pairs(Data.Eggs) do
			if type(egg) == "table" then
				table.insert(ranked, {
					Name = name,
					Rank = RARITY_RANK[tostring(egg.Rarity)] or 0,
					Luck = tonumber(egg.Luck) or 0,
				})
			end
		end
	end

	table.sort(ranked, function(a, b)
		if a.Rank ~= b.Rank then return a.Rank > b.Rank end
		return a.Luck > b.Luck
	end)

	for _, entry in ipairs(ranked) do
		table.insert(eggChoices, entry.Name)
	end
end

local function alreadyCollected(eggName)
	local attribute = LocalPlayer:GetAttribute("CollectedEggs")
	return type(attribute) == "string"
		and attribute ~= ""
		and string.find(attribute, tostring(eggName) .. ",", 1, true) ~= nil
end

local function candidates(origin)
	local list = {}
	local top = Game.PlotTop()
	local now = os.clock()
	local filtered = next(Collect.Targets) ~= nil

	for _, child in ipairs(ActiveEggs:GetChildren()) do
		local eggName = child:GetAttribute("Egg")
		local position = child:GetAttribute("Position")
		local private = child:GetAttribute("PrivateTo")
		local cooldown = Collect.Cooldowns[child.Name]

		local usable = type(eggName) == "string"
			and typeof(position) == "Vector3"
			and (private == nil or private == LocalPlayer.UserId)
			and not (cooldown and cooldown > now)

		if usable and not alreadyCollected(eggName) then
			local rank = Game.EggRank(eggName)

			if rank >= Collect.MinRank and (not filtered or Collect.Targets[eggName]) then
				local travel = top and Game.TravelTime(position, top) or 0

				local weight = tonumber(child:GetAttribute("Weight")) or 1
				local mutation = mutationOf(child)
				local mutated = mutation ~= nil and mutationPasses(mutation)

				local keep = travel < 20 - SAFETY_MARGIN - 2
					and weight >= Weight.Minimum

				if keep and Mutations.WaitForStorm and not mutated then
					keep = activeStorm() == nil
				end

				if keep then
					table.insert(list, {
						Config = child,
						Name = eggName,
						Position = position,
						Rank = rank,
						Weight = weight,
						Mutation = mutated and mutation or nil,
						MutationWeight = mutated and (MUTATION_WEIGHT[mutation] or 1000) or 0,
						Luck = Game.EggLuck(eggName) * weight,
						Distance = (position - origin).Magnitude,
					})
				end
			end
		end
	end

	local mode = Collect.Priority

	table.sort(list, function(a, b)
		if Mutations.Prioritize and a.MutationWeight ~= b.MutationWeight then
			return a.MutationWeight > b.MutationWeight
		end

		if Weight.PreferHeaviest and a.Weight ~= b.Weight then
			return a.Weight > b.Weight
		end

		if mode == "Nearest" then return a.Distance < b.Distance end
		if mode == "Farthest" then return a.Distance > b.Distance end

		if mode == "Highest Rarity" then
			if a.Rank ~= b.Rank then return a.Rank > b.Rank end
			if a.Luck ~= b.Luck then return a.Luck > b.Luck end
			return a.Distance < b.Distance
		end

		if a.Luck ~= b.Luck then return a.Luck > b.Luck end
		return a.Distance < b.Distance
	end)

	return list
end

local function manualTarget()
	while #Farm.Manual > 0 do
		local child = ActiveEggs:FindFirstChild(Farm.Manual[1])
		local eggName = child and child:GetAttribute("Egg")
		local position = child and child:GetAttribute("Position")
		local private = child and child:GetAttribute("PrivateTo")

		if type(eggName) == "string"
			and typeof(position) == "Vector3"
			and (private == nil or private == LocalPlayer.UserId) then
			return { Config = child, Name = eggName, Position = position, Manual = true }
		end

		table.remove(Farm.Manual, 1)
	end

	return nil
end

local function forgetManual(name)
	local index = table.find(Farm.Manual, name)
	if index then table.remove(Farm.Manual, index) end
end

local function relayNearBase(base, top, abort)
	local root = Game.Root()
	local basket = LocalPlayer:FindFirstChild("Basket")
	if not root or not basket then return end

	local local_ = base.CFrame:PointToObjectSpace(root.Position)
	local flat = Vector3.new(local_.X, 0, local_.Z)

	if flat.Magnitude < 1 then flat = Vector3.new(0, 0, 1) end

	local halfX = base.Size.X / 2
	local halfZ = base.Size.Z / 2
	local unit = flat.Unit
	local scaled = unit / math.max(math.abs(unit.X) / (halfX + 20), math.abs(unit.Z) / (halfZ + 20))
	local world = base.CFrame:PointToWorldSpace(Vector3.new(scaled.X, 0, scaled.Z))
	local drop = Vector3.new(world.X, top.Y + 4, world.Z)

	Game.FlyTo(drop, abort, 4)

	local here = Game.Root()
	if not here or (here.Position - drop).Magnitude > 10 then return end

	Game.Status = "Re-picking eggs near base"

	local hold = os.clock() + 0.3

	while os.clock() < hold do
		local current = Game.Root()

		if current then
			pcall(function()
				current.CFrame = CFrame.new(drop) * current.CFrame.Rotation
				current.AssemblyLinearVelocity = Vector3.zero
			end)
		end

		RunService.Heartbeat:Wait()
	end

	local known = {}

	for _, child in ipairs(ActiveEggs:GetChildren()) do
		known[child] = true
	end

	local dropped = {}

	for _, child in ipairs(basket:GetChildren()) do
		local attribute = child:GetAttribute("Egg")
		if type(attribute) == "string" then table.insert(dropped, attribute) end
	end

	Farm.Relaying = true

	for _, name in ipairs(dropped) do
		Game.Fire("BasketDrop", name)
	end

	local appeared = {}
	local deadline = os.clock() + 3

	while #appeared < #dropped and os.clock() < deadline do
		for _, child in ipairs(ActiveEggs:GetChildren()) do
			if not known[child]
				and child:GetAttribute("OriginPosition") ~= nil
				and typeof(child:GetAttribute("Position")) == "Vector3" then
				known[child] = true
				table.insert(appeared, child)
			end
		end

		RunService.Heartbeat:Wait()
	end

	for _, child in ipairs(appeared) do
		local position = child:GetAttribute("Position")

		for _ = 1, 3 do
			if child.Parent == nil then break end

			if typeof(position) == "Vector3" then
				Game.FlyTo(position + Vector3.new(0, 3, 0), nil, 5)
			end

			local before = Game.BasketCount()
			Farm.LastPickupAt = os.clock()
			Game.Fire("EggPickup", child.Name)

			local wait = os.clock() + 1.5

			while Game.BasketCount() == before and os.clock() < wait do
				RunService.Heartbeat:Wait()
			end

			if Game.BasketCount() > before then break end
		end

		if child.Parent ~= nil and not table.find(Farm.Manual, child.Name) then
			table.insert(Farm.Manual, 1, child.Name)
		end
	end

	Farm.Relaying = false
end

function Farm.Deliver(abort)
	if Game.BasketCount() <= 0 then return true end

	local top = Game.PlotTop()
	local base = Game.PlotBase()
	if not top or not base then return false end

	Game.Status = "Bringing eggs home"

	local root = Game.Root()
	local from = Farm.PickupPos or (root and root.Position)

	if from and (from - top).Magnitude > RELAY_DISTANCE then
		relayNearBase(base, top, abort)
		Game.Status = "Bringing eggs home"
	end

	Game.FlyTo(top + Vector3.new(0, 4, 0), abort, 4)

	local deadline = os.clock() + 3

	while Game.BasketCount() > 0 and os.clock() < deadline do
		RunService.Heartbeat:Wait()
	end

	if Game.BasketCount() == 0 then
		table.clear(Farm.Carried)
		Farm.PickupPos = nil
	end

	return Game.BasketCount() == 0
end

function Farm.AutoPlan(origin)
	if not Farm.Collect then return {} end
	return candidates(origin)
end

function Farm.CollectStep(abort)
	if not Game.Root() then return false end

	local capacity = Game.BasketCapacity()
	local collected = false

	while Game.BasketCount() < capacity do
		if abort() then break end

		local deadline = Game.BasketDeadline()
		local top = Game.PlotTop()

		if deadline and top then
			local root = Game.Root()
			local travel = root and Game.TravelTime(root.Position, top) or 0

			if deadline - workspace:GetServerTimeNow() - travel < SAFETY_MARGIN + 4 then
				break
			end
		end

		local root = Game.Root()
		if not root then break end

		local target = manualTarget()

		if not target and Farm.Collect then
			for _, entry in ipairs(candidates(root.Position)) do
				if not table.find(Farm.Manual, entry.Config.Name) then
					target = entry
					break
				end
			end
		end

		if not target then
			if not collected then Game.Status = "No egg matches the filters" end
			break
		end

		local key = target.Config.Name
		Farm.Target = key
		Farm.TargetManual = target.Manual == true
		Farm.Dropped = nil
		Game.Status = string.format("Collecting %s", target.Name)

		local reached = Game.FlyTo(target.Position + Vector3.new(0, 3, 0), function()
			return abort() or target.Config.Parent == nil or Farm.Dropped == key
		end, 6)

		if Farm.Dropped == key then
			Farm.Target = nil
			Farm.Dropped = nil
		elseif target.Config.Parent == nil and not reached then
			forgetManual(key)
			Farm.Target = nil
		elseif not reached then
			Collect.Cooldowns[key] = os.clock() + 20
			forgetManual(key)
			Farm.Target = nil
			break
		else
			local before = Game.BasketCount()
			Farm.LastPickupAt = os.clock()

			if before == 0 then Farm.PickupPos = target.Position end

			Game.Fire("EggPickup", key)

			local soft = os.clock() + 1.2
			local hard = soft + 1.5

			while Game.BasketCount() == before do
				if os.clock() >= soft and (target.Config.Parent ~= nil or os.clock() >= hard) then
					break
				end
				RunService.Heartbeat:Wait()
			end

			forgetManual(key)
			Farm.Target = nil

			if Game.BasketCount() > before then
				Farm.Carried[key] = target.Config
				collected = true
			else
				Collect.Cooldowns[key] = os.clock() + 20
			end
		end
	end

	return collected
end

local Plant = {
	MinRank = 0,
	BlockedUntil = 0,
	BlockedCount = 0,
}

local function plotEggs()
	local plot = Game.Plot()
	local eggs = plot and plot:FindFirstChild("Eggs")
	return eggs and eggs:GetChildren() or {}
end

local function occupiedPoints()
	local points = {}

	for _, egg in ipairs(plotEggs()) do
		local ok, pivot = pcall(function() return egg:GetPivot().Position end)
		if ok then table.insert(points, pivot) end
	end

	local plot = Game.Plot()
	local pets = plot and plot:FindFirstChild("Pets")

	if pets then
		for _, child in ipairs(pets:GetChildren()) do
			local ok, pivot = pcall(function() return child:GetPivot().Position end)
			if ok then table.insert(points, pivot) end
		end
	end

	return points
end

function Farm.PlantStep(abort)
	if os.clock() < Plant.BlockedUntil and #plotEggs() >= Plant.BlockedCount then
		return false
	end

	local held = {}

	for _, tool in ipairs(Game.Tools("Egg")) do
		if Plant.MinRank <= Game.EggRank(tool.Name) then
			table.insert(held, tool)
		end
	end

	if #held == 0 then return false end

	table.sort(held, function(a, b)
		return Game.EggLuck(a.Name) > Game.EggLuck(b.Name)
	end)

	local planted = 0

	for _, tool in ipairs(held) do
		if abort() then break end
		if tool.Parent then
			local point = Game.RandomPlotPoint(8, occupiedPoints(), 5)
			if not point then break end

			Game.Status = string.format("Planting %s", tool.Name)

			if not Game.Equip(tool) then break end

			local before = #plotEggs()
			Game.Fire("EggPlaced", { PlantPosition = point })

			local deadline = os.clock() + 1.2

			while os.clock() < deadline and #plotEggs() == before do
				RunService.Heartbeat:Wait()
			end

			if #plotEggs() > before then
				planted = planted + 1
			else
				Plant.BlockedUntil = os.clock() + 15
				Plant.BlockedCount = #plotEggs()
				break
			end
		end
	end

	Game.Unequip()

	return planted > 0
end

local function readyEggs()
	local ready = {}

	for _, egg in ipairs(plotEggs()) do
		local timer = egg:FindFirstChild("Timer", true)
		local prompt = egg:FindFirstChild("Hatch", true)

		if prompt and prompt:IsA("ProximityPrompt") and prompt.Enabled
			and timer and timer:IsA("TextLabel") and timer.Text == "Ready" then
			table.insert(ready, { Egg = egg, Prompt = prompt })
		end
	end

	return ready
end

function Farm.HatchWanted()
	return Farm.Hatch and #readyEggs() > 0
end

function Farm.HatchStep(abort)
	local hatched = 0

	for _, entry in ipairs(readyEggs()) do
		if abort() then break end

		if entry.Egg.Parent then
			local ok, pivot = pcall(function() return entry.Egg:GetPivot().Position end)

			if ok then
				Game.Status = "Hatching eggs"
				Game.FlyTo(pivot + Vector3.new(0, 3, 3), abort, 5)
				Game.FirePrompt(entry.Prompt)

				local deadline = os.clock() + 2

				while os.clock() < deadline and entry.Egg.Parent do
					RunService.Heartbeat:Wait()
				end

				if not entry.Egg.Parent then hatched = hatched + 1 end
			end
		end
	end

	if hatched > 0 then
		task.wait(0.5)
		Game.Unequip()
	end

	return hatched > 0
end

local foodChoices = {}

do
	local ranked = {}

	if type(Data.Foods) == "table" then
		for name, food in pairs(Data.Foods) do
			if type(food) == "table" then
				table.insert(ranked, { Name = name, Cost = tonumber(food.Cost) or 0 })
			end
		end
	end

	table.sort(ranked, function(a, b) return a.Cost < b.Cost end)

	for _, entry in ipairs(ranked) do
		table.insert(foodChoices, entry.Name)
	end
end

local Pets = {
	Foods = {},
	FeedCooldowns = {},
	SkipMaxAge = true,
	MaxAge = 100,
	AllowPremium = true,
	PremiumFoods = { Dragonfruit = true, Apple = true },
}

local function plotPets()
	local plot = Game.Plot()
	local pets = plot and plot:FindFirstChild("Pets")
	return pets and pets:GetChildren() or {}
end

local function maxPets()
	return math.max(1,
		tonumber(LocalPlayer:GetAttribute("MaxPets"))
		or tonumber(Game.Saved("MaxPets"))
		or 5)
end

local function placedScore(instance)
	return Game.PetScore(
		instance:GetAttribute("PetName") or instance.Name,
		instance:GetAttribute("Weight"),
		instance:GetAttribute("Mutation"))
end

local function toolScore(tool)
	return Game.PetScore(
		Game.PetNameOf(tool),
		tool:GetAttribute("Weight"),
		tool:GetAttribute("Mutation"))
end

local function bestHeldPet()
	local best, bestValue = nil, -1

	for _, tool in ipairs(Game.Tools("Pet")) do
		local value = toolScore(tool)
		if value > bestValue then
			best, bestValue = tool, value
		end
	end

	return best, bestValue
end

local function weakestPlacedPet()
	local worst, worstValue = nil, math.huge

	for _, instance in ipairs(plotPets()) do
		local value = placedScore(instance)
		if value < worstValue then
			worst, worstValue = instance, value
		end
	end

	return worst, worstValue
end

function Farm.PlaceWanted()
	if not Farm.Place then return false end

	local best, bestValue = bestHeldPet()
	if not best then return false end

	if #plotPets() < maxPets() then return true end

	if Farm.Swap then
		local _, worstValue = weakestPlacedPet()
		return bestValue > worstValue * 1.05
	end

	return false
end

local function placePet(tool, abort)
	local key = tool:GetAttribute("PetKey")
	if not key then return false end

	local top = Game.PlotTop()
	if top then Game.FlyTo(top + Vector3.new(0, 4, 0), abort, 20) end

	if not Game.Equip(tool) then return false end

	local point = Game.RandomPlotPoint(10, nil, 0)
	local before = #plotPets()

	Game.Fire("PlacePet", key, point + Vector3.new(0, 2, 0))
	task.wait(0.35)
	Game.Unequip()

	local deadline = os.clock() + 1.5

	while os.clock() < deadline and #plotPets() == before do
		RunService.Heartbeat:Wait()
	end

	return #plotPets() > before
end

function Farm.PlaceStep(abort)
	local placed = 0

	for _ = 1, maxPets() do
		if abort() or not Farm.PlaceWanted() then break end

		local best = bestHeldPet()
		if not best then break end

		if #plotPets() < maxPets() then
			Game.Status = string.format("Placing %s", Game.PetNameOf(best))
			if not placePet(best, abort) then break end
			placed = placed + 1
		else
			local worst = weakestPlacedPet()
			local key = worst and worst:GetAttribute("PetKey")
			if not key then break end

			Game.Status = "Swapping in a stronger pet"

			local top = Game.PlotTop()
			if top then Game.FlyTo(top + Vector3.new(0, 4, 0), abort, 20) end

			Game.Fire("PickupPet", key)

			local deadline = os.clock() + 1.5

			while os.clock() < deadline and worst.Parent do
				RunService.Heartbeat:Wait()
			end

			if worst.Parent then break end

			Game.Status = string.format("Placing %s", Game.PetNameOf(best))
			if not placePet(best, abort) then break end
			placed = placed + 1
		end
	end

	return placed > 0
end

local function cheapestFood()
	local best, bestCost = nil, math.huge
	local filtered = next(Pets.Foods) ~= nil

	for _, tool in ipairs(Game.Tools("Food")) do
		local amount = tool:FindFirstChild("Amount", true)
		local count = amount and tonumber(amount.Value) or 1

		local premiumBlocked = not Pets.AllowPremium and Pets.PremiumFoods[tool.Name] == true

		if count > 0 and not premiumBlocked and (not filtered or Pets.Foods[tool.Name]) then
			local entry = type(Data.Foods) == "table" and Data.Foods[tool.Name] or nil
			local cost = type(entry) == "table" and tonumber(entry.Cost) or 0

			if cost < bestCost then
				best, bestCost = tool, cost
			end
		end
	end

	return best
end

function Farm.FeedWanted()
	if not Farm.Feed or not cheapestFood() then return false end

	local now = os.clock()

	for _, instance in ipairs(plotPets()) do
		local key = instance:GetAttribute("PetKey")
		local age = tonumber(instance:GetAttribute("Age")) or 0
		local tooOld = Pets.SkipMaxAge and age >= Pets.MaxAge

		if key and not tooOld and (Pets.FeedCooldowns[key] or 0) <= now then return true end
	end

	return false
end

function Farm.FeedStep(abort)
	local placed = plotPets()

	table.sort(placed, function(a, b)
		return placedScore(a) > placedScore(b)
	end)

	local fed = 0

	for _, instance in ipairs(placed) do
		if abort() then break end

		local food = cheapestFood()
		if not food then break end

		local key = instance:GetAttribute("PetKey")
		local age = tonumber(instance:GetAttribute("Age")) or 0
		local tooOld = Pets.SkipMaxAge and age >= Pets.MaxAge

		if key and not tooOld and (Pets.FeedCooldowns[key] or 0) <= os.clock() then
			local ok, pivot = pcall(function() return instance:GetPivot().Position end)

			if ok then
				Game.Status = string.format("Feeding %s",
					tostring(instance:GetAttribute("PetName") or instance.Name))

				Game.FlyTo(pivot + Vector3.new(0, 4, 4), abort, 8)

				if Game.Equip(food) then
					local age = instance:GetAttribute("Age")
					Game.Fire("FeedPet", key, food.Name)

					local deadline = os.clock() + 1.2

					while os.clock() < deadline and instance:GetAttribute("Age") == age do
						RunService.Heartbeat:Wait()
					end

					Pets.FeedCooldowns[key] = os.clock() + 2
					fed = fed + 1
				end
			end
		end
	end

	Game.Unequip()

	return fed > 0
end

local VOLCANO_TOP = Vector3.new(-5102.8, 41408, -3489.1)
local VOLCANO_PLATFORM = CFrame.new(-4917.03369, 41285.5312, -3704.17505)
local FUSION_SPOT = Vector3.new(387.9, 40328.8, 751.3)

local Magma = {
	Enabled = false,
	Dipping = false,
	Duration = 9.5,
}

local function volcanoPlatform()
	local part = workspace:FindFirstChild("FacilityVolcanoPlatform")
	local target = CFrame.new(VOLCANO_PLATFORM.Position - Vector3.new(0, 3.2, 0))

	if not part then
		part = Instance.new("Part")
		part.Name = "FacilityVolcanoPlatform"
		part.Size = Vector3.new(14, 1, 14)
		part.Anchored = true
		part.CanCollide = true
		part.Material = Enum.Material.SmoothPlastic
		part.Transparency = 0.5
		part.CFrame = target
		part.Parent = workspace
	else
		part.CFrame = target
	end

	return part
end

onCleanup(function()
	local part = workspace:FindFirstChild("FacilityVolcanoPlatform")
	if part then pcall(function() part:Destroy() end) end
end)

local function volcanoRemote()
	local packages = ReplicatedStorage:FindFirstChild("packages")
	local net = packages and packages:FindFirstChild("Net")
	return net and net:FindFirstChild("RE/VolcanoDip")
end

local function dippableEgg()
	local basket = LocalPlayer:FindFirstChild("Basket")
	if not basket then return nil end

	for _, child in ipairs(basket:GetChildren()) do
		if child:GetAttribute("VolcanoDipped") ~= true
			and child:GetAttribute("Delivering") ~= true then
			local mutation = child:GetAttribute("Mutation")

			if mutation ~= "Eternal" and mutation ~= "Magma" then
				return child
			end
		end
	end

	return nil
end

local function magmaDip(abort)
	if not Magma.Enabled or Magma.Dipping then return false end

	local egg = dippableEgg()
	if not egg then return false end

	local root = Game.Root()
	if not root then return false end

	Magma.Dipping = true

	volcanoPlatform()

	Game.Status = "Warping to the volcano"

	local function anchorAtTop()
		pcall(function()
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
			root.CFrame = CFrame.new(VOLCANO_TOP)
		end)
	end

	anchorAtTop()
	task.wait(0.2)

	if (root.Position - VOLCANO_TOP).Magnitude > 25 then
		anchorAtTop()
		task.wait(0.1)
	end

	Game.Status = "Triggering the lava dip"

	local remote = volcanoRemote()
	local deadline = os.clock() + 3.5

	while os.clock() < deadline do
		if not egg.Parent or abort() then break end

		local until_ = egg:GetAttribute("VolcanoUntil")

		if (type(until_) == "number" and until_ > workspace:GetServerTimeNow())
			or egg:GetAttribute("VolcanoDipped") == true then
			break
		end

		if remote then
			pcall(function() remote:FireServer() end)
		end

		pcall(function()
			local gui = LocalPlayer:FindFirstChild("PlayerGui")
			local main = gui and gui:FindFirstChild("Main")
			local holder = main and main:FindFirstChild("ActionsHolder")
			local button = holder and holder:FindFirstChild("DropEggVolcanoButton")

			if button and firesignal then firesignal(button.Activated) end
		end)

		task.wait(0.3)
	end

	local started = os.clock()

	while os.clock() - started < Magma.Duration do
		if not egg.Parent or abort() then break end

		local current = Game.Root()

		if current and (current.Position - VOLCANO_TOP).Magnitude > 30 then
			pcall(function()
				current.AssemblyLinearVelocity = Vector3.zero
				current.AssemblyAngularVelocity = Vector3.zero
				current.CFrame = CFrame.new(VOLCANO_TOP)
			end)
		end

		local until_ = egg:GetAttribute("VolcanoUntil")

		if type(until_) == "number" and workspace:GetServerTimeNow() >= until_ then
			break
		end

		Game.Status = string.format("Dipping in lava  %ds",
			math.max(0, math.ceil(Magma.Duration - (os.clock() - started))))

		task.wait(0.2)
	end

	pcall(function() egg:SetAttribute("VolcanoDipped", true) end)

	if egg.Parent and egg:GetAttribute("Mutation") == "Magma" then
		Game.Status = "Magma mutation landed"

		Library:Notify({
			Title = "Magma",
			Text = string.format("%s mutated to Magma, 10x.", egg.Name),
			Style = "success",
			Duration = 5,
		})
	else
		Game.Status = "Dip done, no Magma"
	end

	Magma.Dipping = false

	return true
end

local farmRunning = true
local farmWake = false

function Farm.Wake()
	farmWake = true
end

function Farm.CollectActive()
	return Farm.Collect or #Farm.Manual > 0
end

local function carryingEggs()
	if Game.BasketCount() <= 0 then return false end
	if next(Farm.Carried) ~= nil then return true end
	return os.clock() - Farm.LastPickupAt < 30
end

local function anyWork()
	return Farm.CollectActive()
		or carryingEggs()
		or Farm.Plant
		or Farm.Hatch
		or Farm.Place
		or Farm.Feed
end

local function shouldStop()
	return not farmRunning or not anyWork()
end

local function stopWhenOff(key)
	return function()
		return shouldStop() or not Farm[key]
	end
end

task.spawn(function()
	while farmRunning do
		local progressed = false

		if anyWork() and Game.Root() and Game.Plot() then
			Farm.Busy = true

			local ok = pcall(function()
				if Game.BasketCount() > 0 then
					if Magma.Enabled and not shouldStop() then
						if magmaDip(shouldStop) then progressed = true end
					end

					Farm.Deliver(shouldStop)
					progressed = true
				end

				if Farm.Plant and not shouldStop() then
					if Farm.PlantStep(stopWhenOff("Plant")) then progressed = true end
				end

				if Farm.HatchWanted() and not shouldStop() then
					if Farm.HatchStep(stopWhenOff("Hatch")) then progressed = true end
				end

				if Farm.PlaceWanted() and not shouldStop() then
					if Farm.PlaceStep(stopWhenOff("Place")) then progressed = true end
				end

				if Farm.FeedWanted() and not shouldStop() then
					if Farm.FeedStep(stopWhenOff("Feed")) then progressed = true end
				end

				if Farm.CollectActive() and not shouldStop() then
					if Farm.CollectStep(function()
						return shouldStop() or not Farm.CollectActive()
					end) then
						progressed = true
					end
				end
			end)

			if not ok then Game.Unequip() end

			Farm.Busy = false

			if not progressed and not Farm.Collect then
				Game.Status = "Waiting for work"
			end
		elseif not anyWork() then
			Game.Status = "Idle"
		end

		local deadline = os.clock() + (progressed and 0.15 or 1)

		while farmRunning and os.clock() < deadline and not farmWake do
			RunService.Heartbeat:Wait()
		end

		farmWake = false
	end
end)

onCleanup(function() farmRunning = false end)

local Shop = {
	Enabled = { Food = false, Gears = false },
	Wanted = { Food = {}, Gears = {} },
	Stock = { Food = nil, Gears = nil },
	Retry = {},
	KeepCash = 0,
}

local function shopChoices(category)
	local entries = {}
	local shop = Data.Shop
	local section = type(shop) == "table" and shop[category] or nil

	if type(section) == "table" then
		for name, item in pairs(section) do
			if type(item) == "table" then
				table.insert(entries, { Name = name, Price = tonumber(item.Price) or 0 })
			end
		end
	end

	table.sort(entries, function(a, b) return a.Price < b.Price end)

	local names = {}
	for _, entry in ipairs(entries) do
		table.insert(names, entry.Name)
	end

	return names
end

local function shopPrice(category, name)
	local shop = Data.Shop
	local section = type(shop) == "table" and shop[category] or nil
	local item = type(section) == "table" and section[name] or nil
	return type(item) == "table" and tonumber(item.Price) or math.huge
end

local function readStock(payload)
	if type(payload) ~= "table" then return end

	for category, section in pairs(payload) do
		if (category == "Food" or category == "Gears") and type(section) == "table" then
			local counts = {}

			for name, item in pairs(section) do
				if type(item) == "table" then
					counts[name] = tonumber(item.Amount) or (item.InStock and 1 or 0)
				end
			end

			Shop.Stock[category] = counts
		end
	end
end

local stockConnections = {}

for _, remoteName in ipairs({ "Restock", "ShopStock" }) do
	local remote = Remotes:FindFirstChild(remoteName)

	if remote and remote:IsA("RemoteEvent") then
		table.insert(stockConnections, remote.OnClientEvent:Connect(readStock))
	end
end

Game.Fire("ShopStock")

local function ownedCount(name)
	local total = 0
	local character = LocalPlayer.Character

	for _, container in ipairs({ LocalPlayer:FindFirstChildOfClass("Backpack"), character }) do
		if container then
			for _, child in ipairs(container:GetChildren()) do
				if child:IsA("Tool") and string.gsub(child.Name, "%s*%[.*$", "") == name then
					local amount = child:FindFirstChild("Amount", true)
					total = total + (amount and tonumber(amount.Value) or 1)
				end
			end
		end
	end

	return total
end

local function buyCategory(category)
	if not Shop.Enabled[category] then return end

	local opened = false

	for _, name in ipairs(shopChoices(category)) do
		if Shop.Wanted[category][name] then
			local price = shopPrice(category, name)
			local stock = Shop.Stock[category]
			local left = stock and stock[name]

			local allowed = left == nil
				and (Shop.Retry[category .. name] or 0) <= os.clock()
				or (left ~= nil and left > 0)

			local bought = 0

			while allowed and bought < 20 and Game.Cash() - price >= Shop.KeepCash do
				if not opened then
					Game.Fire("SetOpenShop", category)
					task.wait(0.15)
					opened = true
				end

				local before = ownedCount(name)
				Game.Fire("BuyWithCash", category, name)
				bought = bought + 1

				local deadline = os.clock() + 0.8

				while os.clock() < deadline and ownedCount(name) <= before do
					RunService.Heartbeat:Wait()
				end

				if ownedCount(name) > before then
					if stock and stock[name] then
						stock[name] = math.max(0, stock[name] - 1)
						allowed = stock[name] > 0
					end
				else
					if stock then stock[name] = 0 end
					Shop.Retry[category .. name] = os.clock() + 30
					allowed = false
				end
			end
		end
	end
end

local shopRunning = true

task.spawn(function()
	while shopRunning do
		pcall(buyCategory, "Food")
		pcall(buyCategory, "Gears")
		task.wait(3)
	end
end)

onCleanup(function()
	shopRunning = false
	for _, connection in ipairs(stockConnections) do
		pcall(function() connection:Disconnect() end)
	end
end)

local Progress = {
	Rebirth = false,
	ClaimIndex = false,
}

local function rebirthCost()
	local rebirths = Data.Rebirths
	if type(rebirths) ~= "table" then return nil end

	local owned = tonumber(Game.Saved("Rebirths")) or 0
	local cap = tonumber(rebirths.Cap)

	if cap and owned >= cap then return nil end

	if type(rebirths.GetCost) == "function" then
		local ok, cost = pcall(rebirths.GetCost, owned)
		if ok and tonumber(cost) then return tonumber(cost) end
	end

	return nil
end

local progressRunning = true

task.spawn(function()
	local nextRebirth = 0
	local nextClaim = 0

	while progressRunning do
		local now = os.clock()

		if Progress.Rebirth and now >= nextRebirth then
			local cost = rebirthCost()

			if cost and Game.Cash() >= cost then
				Game.Fire("Rebirth")
				nextRebirth = now + 15
			else
				nextRebirth = now + 3
			end
		end

		if Progress.ClaimIndex and now >= nextClaim then
			Game.Fire("ClaimIndexReward")
			nextClaim = now + 60
		end

		task.wait(1)
	end
end)

onCleanup(function() progressRunning = false end)

local ProximityPromptService = game:GetService("ProximityPromptService")

local promptHolds = {}
local promptConnections = {}

local function patchPrompt(prompt)
	if not prompt:IsA("ProximityPrompt") then return end

	if promptHolds[prompt] == nil then
		promptHolds[prompt] = prompt.HoldDuration
	end

	if prompt.HoldDuration ~= 0 then
		prompt.HoldDuration = 0
	end
end

local function restorePrompts()
	for _, connection in ipairs(promptConnections) do
		pcall(function() connection:Disconnect() end)
	end

	table.clear(promptConnections)

	for prompt, hold in pairs(promptHolds) do
		if prompt.Parent then
			pcall(function() prompt.HoldDuration = hold end)
		end
	end

	table.clear(promptHolds)
end

local function instantPickup(state)
	restorePrompts()

	if not state then return end

	for _, descendant in ipairs(workspace:GetDescendants()) do
		if descendant:IsA("ProximityPrompt") then
			patchPrompt(descendant)
		end
	end

	table.insert(promptConnections, workspace.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("ProximityPrompt") then
			task.defer(patchPrompt, descendant)
		end
	end))

	table.insert(promptConnections, ProximityPromptService.PromptShown:Connect(patchPrompt))
end

onCleanup(restorePrompts)

local Hop = {
	Mode = "Least Players",
	Running = false,
	Token = 0,
	Cache = nil,
	CacheMode = nil,
	CacheAt = 0,
	Blocked = {},
	Pending = nil,
	Denied = false,
}

local CACHE_LIFETIME = 25

local function blockServer(id)
	Hop.Pending = nil
	if id then Hop.Blocked[id] = true end
end

pcall(function()
	TeleportService.TeleportInitFailed:Connect(function(_, result, message)
		if not Hop.Pending then return end

		blockServer(Hop.Pending)
		Hop.Denied = true

		if not Hop.Running then
			Library:Notify({ Title = "Server Hop", Text = tostring(message ~= "" and message or result), Style = "error", Duration = 6 })
		end
	end)
end)

local function fetchServers(mode)
	local current = tostring(game.JobId or "")
	local found = {}
	local random_ = mode == "Random"
	local order = mode == "Least Players" and "Asc" or "Desc"
	local pages = random_ and 3 or 6
	local cursor = nil

	for _ = 1, pages do
		local url = string.format(
			"https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=%s&excludeFullGames=true&limit=100",
			game.PlaceId, order)

		if cursor and cursor ~= "" then
			url = url .. "&cursor=" .. HttpService:UrlEncode(cursor)
		end

		local ok, payload = pcall(function()
			return HttpService:JSONDecode(game:HttpGet(url))
		end)

		if not ok or type(payload) ~= "table" then
			return found, false
		end

		for _, entry in ipairs(payload.data or {}) do
			local id = tostring(entry.id or "")
			local playing = tonumber(entry.playing) or math.huge
			local maximum = tonumber(entry.maxPlayers) or 0

			if id ~= "" and id ~= current and playing < maximum then
				found[#found + 1] = { Id = id, Playing = playing, Room = maximum - playing }
			end
		end

		if #found > 0 and not random_ then break end

		cursor = payload.nextPageCursor
		if not cursor or cursor == "" then break end
	end

	return found, true
end

local function serverHop(mode)
	local list

	if Hop.Cache and Hop.CacheMode == mode and os.clock() - Hop.CacheAt < CACHE_LIFETIME then
		list = Hop.Cache
	else
		local fetched, ok = fetchServers(mode)
		if not ok then return "fetch" end

		list = fetched
		Hop.Cache = fetched
		Hop.CacheMode = mode
		Hop.CacheAt = os.clock()
	end

	local function usable(minimumRoom)
		local out = {}

		for _, server in ipairs(list) do
			if not Hop.Blocked[server.Id] and server.Room >= minimumRoom then
				out[#out + 1] = server
			end
		end

		return out
	end

	local pool = usable(2)

	if #pool == 0 then pool = usable(1) end

	if #pool == 0 and next(Hop.Blocked) ~= nil then
		table.clear(Hop.Blocked)
		pool = usable(1)
	end

	if #pool == 0 then
		blockServer(nil)
		Hop.Cache = nil
		return "empty"
	end

	local id

	if mode == "Random" then
		id = pool[math.random(1, #pool)].Id
	else
		table.sort(pool, function(a, b)
			if mode == "Least Players" then return a.Playing < b.Playing end
			return a.Playing > b.Playing
		end)

		id = pool[1].Id
	end

	Hop.Denied = false
	Hop.Pending = id

	if not pcall(function()
		TeleportService:TeleportToPlaceInstance(game.PlaceId, id, LocalPlayer)
	end) then
		blockServer(id)
		return "failed"
	end

	local deadline = os.clock() + CACHE_LIFETIME

	while os.clock() < deadline do
		if Hop.Denied then return "denied" end
		task.wait(0.25)
	end

	return "waiting"
end

local function startHop()
	Hop.Token = Hop.Token + 1
	local token = Hop.Token

	task.spawn(function()
		Hop.Running = true
		local attempts = 0

		while token == Hop.Token do
			attempts = attempts + 1
			local result = serverHop(Hop.Mode)

			if result == "waiting" then break end

			if result == "empty" then
				Hop.Cache = nil
				table.clear(Hop.Blocked)
			end

			if attempts % 10 == 0 then
				Library:Notify("Server Hop",
					string.format("Every server was full so far, %d tries.", attempts), 4)
			end

			task.wait(result == "fetch" and 1 or 0.1)
		end

		Hop.Running = false
	end)
end

local Lighting = game:GetService("Lighting")

local fpsCapWarned = false

local function setFpsCap(value)
	local capped = math.clamp(math.floor(tonumber(value) or 240), 30, 1000)

	if type(setfpscap) == "function" and pcall(setfpscap, capped) then
		fpsCapWarned = false
		return
	end

	if not fpsCapWarned then
		fpsCapWarned = true
		Library:Notify({ Title = "FPS Cap", Text = "This executor does not support setfpscap.", Style = "error", Duration = 6 })
	end
end

local optimizerSaved = {}
local optimizerOn = false

local function remember(container, property)
	local key = tostring(container) .. "." .. property
	if optimizerSaved[key] ~= nil then return end

	local ok, current = pcall(function() return container[property] end)
	if ok then optimizerSaved[key] = { container, property, current } end
end

local function apply(container, property, value)
	remember(container, property)
	pcall(function() container[property] = value end)
end

local function setOptimizer(state)
	if state == optimizerOn then return end
	optimizerOn = state

	if not state then
		for _, entry in pairs(optimizerSaved) do
			pcall(function() entry[1][entry[2]] = entry[3] end)
		end
		table.clear(optimizerSaved)
		return
	end

	local rendering = settings().Rendering
	local terrain = workspace.Terrain

	apply(rendering, "QualityLevel", Enum.QualityLevel.Level01)
	apply(rendering, "MeshPartDetailLevel", Enum.MeshPartDetailLevel.Level01)
	apply(rendering, "EditQualityLevel", Enum.QualityLevel.Level01)

	local ok, userSettings = pcall(function()
		return UserSettings():GetService("UserGameSettings")
	end)

	if ok and userSettings then
		apply(userSettings, "SavedQualityLevel", Enum.SavedQualitySetting.QualityLevel1)
	end

	apply(Lighting, "GlobalShadows", false)
	apply(Lighting, "ShadowSoftness", 0)
	apply(Lighting, "FogEnd", 9e9)
	apply(Lighting, "Technology", Enum.Technology.Legacy)
	apply(Lighting, "EnvironmentDiffuseScale", 0)
	apply(Lighting, "EnvironmentSpecularScale", 0)
	apply(terrain, "Decoration", false)
	apply(terrain, "WaterWaveSize", 0)
	apply(terrain, "WaterWaveSpeed", 0)
	apply(terrain, "WaterReflectance", 0)
	apply(terrain, "WaterTransparency", 1)
end

onCleanup(function() setOptimizer(false) end)

local antiAfk = { Enabled = true, Alive = true }

local function idledConnections()
	if type(getconnections) ~= "function" then return {} end

	local ok, result = pcall(getconnections, LocalPlayer.Idled)
	return ok and type(result) == "table" and result or {}
end

local function suspendIdle()
	for _, connection in ipairs(idledConnections()) do
		pcall(function() connection:Disable() end)
	end
end

local function resumeIdle()
	for _, connection in ipairs(idledConnections()) do
		pcall(function() connection:Enable() end)
	end
end

task.spawn(function()
	while antiAfk.Alive do
		if antiAfk.Enabled then
			suspendIdle()

			pcall(function()
				VirtualUser:CaptureController()
				VirtualUser:ClickButton2(Vector2.new())
			end)
		end

		task.wait(30)
	end
end)

onCleanup(function()
	antiAfk.Alive = false
	resumeIdle()
end)

local EggEsp = {
	Enabled = false,
	Loaded = false,
	MinRank = 0,
	Tracked = {},
	Connections = {},
}

Esp.teamSettings.enemy.enabled = false
Esp.teamSettings.friendly.enabled = false
Esp.teamSettings.whitelist.enabled = false

for _, rarity in ipairs(RARITY_ORDER) do
	Esp:AddTeam("egg" .. rarity, {
		enabled       = true,
		box           = true,
		boxColor      = { RARITY_COLORS[rarity], 1 },
		name          = true,
		nameColor     = { RARITY_COLORS[rarity], 1 },
		distance      = true,
		distanceColor = { RARITY_COLORS[rarity], 1 },
		healthBar     = false,
		healthText    = false,
		weapon        = false,
		skeleton      = false,
		chams         = false,
		tracer        = false,
		tracerColor   = { RARITY_COLORS[rarity], 1 },
		maxDistance   = 5000,
	})
end

local function renderedFolder()
	return workspace:FindFirstChild("RenderedEggs")
end

local function eggNameOf(model)
	local raw = model:GetAttribute("Egg")
	if type(raw) == "string" and raw ~= "" then return raw end

	return (string.gsub(model.Name, "%s*%[.*$", ""))
end

local function dataEntryFor(model)
	local ok, pivot = pcall(function() return model:GetPivot().Position end)
	if not ok then return nil end

	for _, entry in ipairs(ActiveEggs:GetChildren()) do
		local position = entry:GetAttribute("Position")

		if typeof(position) == "Vector3" and (position - pivot).Magnitude < 10 then
			return entry
		end
	end

	return nil
end

local function untrackEgg(model)
	if not EggEsp.Tracked[model] then return end

	EggEsp.Tracked[model] = nil
	pcall(function() Esp:RemoveInstance(model) end)
end

local function anchorModel(model)
	if not model:IsA("Model") then return model:IsA("BasePart") and model or nil end

	if model.PrimaryPart and model.PrimaryPart.Parent then return model.PrimaryPart end

	local part = model:FindFirstChild("EggBase")
		or model:FindFirstChild("Handle")
		or model:FindFirstChildWhichIsA("BasePart", true)

	if not part then return nil end

	pcall(function() model.PrimaryPart = part end)

	return part
end

local function trackEgg(model)
	if not EggEsp.Enabled then return end
	if EggEsp.Tracked[model] then return end
	if not model:IsA("Model") and not model:IsA("BasePart") then return end
	if not anchorModel(model) then return end

	local eggName = eggNameOf(model)
	if eggName == "" then return end

	local rank = Game.EggRank(eggName)
	if rank < EggEsp.MinRank then return end

	local entry = dataEntryFor(model)

	if entry then
		local private = entry:GetAttribute("PrivateTo")
		if private ~= nil and private ~= LocalPlayer.UserId then return end
	end

	local rarity = Game.EggRarity(eggName)
	local parts = { eggName }

	local weight = entry and tonumber(entry:GetAttribute("Weight"))
	if weight then table.insert(parts, string.format("%.1fkg", weight)) end

	local mutation = entry and mutationOf(entry)
	if mutation then table.insert(parts, mutation) end

	EggEsp.Tracked[model] = true

	Esp:AddInstance(model, {
		Team = "egg" .. rarity,
		Text = table.concat(parts, "  "),
	})
end

local function refreshEggEsp()
	for model in pairs(EggEsp.Tracked) do
		untrackEgg(model)
	end

	if not EggEsp.Enabled then return end

	local folder = renderedFolder()
	if not folder then return end

	for _, model in ipairs(folder:GetChildren()) do
		trackEgg(model)
	end
end

local function bindRenderedFolder(folder)
	table.insert(EggEsp.Connections, folder.ChildAdded:Connect(function(model)
		task.wait(0.15)
		if EggEsp.Enabled then trackEgg(model) end
	end))

	table.insert(EggEsp.Connections, folder.ChildRemoved:Connect(untrackEgg))
end

local function setEggEsp(state)
	EggEsp.Enabled = state

	if state and not EggEsp.Loaded then
		local ok, err = pcall(function() Esp:Load(Entity) end)

		if not ok then
			EggEsp.Enabled = false
			Library:Notify({ Title = "Esp", Text = tostring(err), Style = "error", Duration = 10 })
			return
		end

		EggEsp.Loaded = true
	end

	if state and not renderedFolder() then
		Library:Notify({
			Title = "Esp",
			Text = "workspace.RenderedEggs not found yet, it will bind when it appears.",
			Style = "warning",
			Duration = 6,
		})
	end

	refreshEggEsp()
end

task.spawn(function()
	local folder = renderedFolder() or workspace:WaitForChild("RenderedEggs", 60)
	if not folder then return end

	bindRenderedFolder(folder)
	refreshEggEsp()
end)

task.spawn(function()
	while true do
		task.wait(2)

		if EggEsp.Enabled then
			local folder = renderedFolder()

			if folder then
				local present = {}

				for _, model in ipairs(folder:GetChildren()) do
					present[model] = true
					if not EggEsp.Tracked[model] then trackEgg(model) end
				end

				for model in pairs(EggEsp.Tracked) do
					if not present[model] then untrackEgg(model) end
				end
			end
		end
	end
end)

onCleanup(function()
	EggEsp.Enabled = false
	refreshEggEsp()

	for _, connection in ipairs(EggEsp.Connections) do
		pcall(function() connection:Disconnect() end)
	end

	if EggEsp.Loaded then
		pcall(function() Esp:Unload() end)
	end
end)

local Plot = {
	UpgradeLuck = false,
	UnlockNests = false,
	SpawnNest = false,
}

local function plotRemote(name)
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local gameFolder = remotes and remotes:FindFirstChild("Game")
	local plot = gameFolder and gameFolder:FindFirstChild("Plot")
	return plot and plot:FindFirstChild(name)
end

local plotRunning = true

task.spawn(function()
	while plotRunning do
		task.wait(1)

		if Plot.UpgradeLuck then
			pcall(function()
				local upgrades = plotRemote("Upgrades")

				if upgrades then
					upgrades:FireServer("HatchUpgrade", "BuyMax")
					upgrades:FireServer("HatchUpgrade", "BuyOne")
				end
			end)
		end

		if Plot.UnlockNests and LocalPlayer:GetAttribute("NoNest") ~= true then
			pcall(function()
				local plot = Game.Plot()
				local nests = plot and plot:FindFirstChild("Nests")
				if not nests then return end

				for _, nest in ipairs(nests:GetChildren()) do
					if nest:GetAttribute("Unlocked") ~= true then
						local prompt = nest:FindFirstChildWhichIsA("ProximityPrompt", true)

						if prompt then Game.FirePrompt(prompt) end

						local remote = plotRemote("Nests")
						local index = tonumber(nest.Name)

						if remote and index then remote:FireServer(index) end

						task.wait(0.25)
					end
				end
			end)
		end
	end
end)

onCleanup(function() plotRunning = false end)

local nestWatched = {}

local function applySpawnNest(state)
	Plot.SpawnNest = state

	local plot = Game.Plot()
	local nests = plot and plot:FindFirstChild("Nests")
	if not nests then return end

	for _, nest in ipairs(nests:GetChildren()) do
		for _, descendant in ipairs(nest:GetDescendants()) do
			if descendant:IsA("BasePart") and descendant.Name ~= "FacilityNestAnchor" then
				descendant.LocalTransparencyModifier = state and 0 or 1

				if not nestWatched[descendant] then
					nestWatched[descendant] = true

					descendant:GetPropertyChangedSignal("LocalTransparencyModifier"):Connect(function()
						if Plot.SpawnNest and descendant.LocalTransparencyModifier ~= 0 then
							descendant.LocalTransparencyModifier = 0
						end
					end)
				end
			end
		end

		local anchor = nest:FindFirstChild("FacilityNestAnchor")

		if state then
			if not anchor then
				anchor = Instance.new("Part")
				anchor.Name = "FacilityNestAnchor"
				anchor.Size = Vector3.new(2, 2, 2)
				anchor.CFrame = nest:GetPivot() * CFrame.new(0, 1.5, 0)
				anchor.Transparency = 1
				anchor.CanCollide = false
				anchor.CanTouch = false
				anchor.CanQuery = false
				anchor.Anchored = true
				anchor.Parent = nest
			end

			if not anchor:FindFirstChildOfClass("ProximityPrompt") then
				local prompt = Instance.new("ProximityPrompt")
				prompt.Name = "NestPlacePrompt"
				prompt.ActionText = "Place Egg"
				prompt.ObjectText = "Nest " .. nest.Name
				prompt.HoldDuration = 0
				prompt.MaxActivationDistance = 25
				prompt.RequiresLineOfSight = false
				prompt.Parent = anchor
			end
		elseif anchor then
			pcall(function() anchor:Destroy() end)
		end
	end
end

onCleanup(function()
	if Plot.SpawnNest then pcall(applySpawnNest, false) end
end)

local Fuse = {
	Enabled = false,
	ProtectFavorited = true,
	AutoFavorite = false,
	Rarities = {},
}

local function gameRemote(name)
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local gameFolder = remotes and remotes:FindFirstChild("Game")
	return gameFolder and gameFolder:FindFirstChild(name)
end

local function favoritePet(key)
	local remote = gameRemote("FavoritePet")
	if remote and key then pcall(function() remote:FireServer(key) end) end
end

local function warpTo(position)
	local root = Game.Root()
	if not root then return false end

	if (root.Position - position).Magnitude > 25 then
		pcall(function()
			root.CFrame = CFrame.new(position + Vector3.new(0, 3, 0))
		end)
		task.wait(0.4)
	end

	return true
end

local function fuseStep()
	local slots = LocalPlayer:FindFirstChild("FusionSlots")
	local result = LocalPlayer:FindFirstChild("FusionResult")
	local action = gameRemote("FusionAction")
	local place = gameRemote("FusionPetPlace")

	if not slots or not action or not place then return end

	local humanoid = Game.Humanoid()
	local character = LocalPlayer.Character
	if not humanoid or not character then return end

	local status = slots:GetAttribute("FusionStatus")

	if status == "Result" then
		warpTo(FUSION_SPOT)

		if slots:GetAttribute("FusionFailed") == true then
			action:FireServer("Claim", slots:GetAttribute("FusionResultKey"))
		else
			local pet = result and result:FindFirstChild("Pet")
			local key = pet and pet:GetAttribute("PetKey")

			if key then
				action:FireServer("Claim", key)

				if Fuse.AutoFavorite then
					task.delay(0.5, function() favoritePet(key) end)
				end
			else
				local functionals = workspace:FindFirstChild("Functionals")
				local fusion = functionals and functionals:FindFirstChild("Fusion")
				local output = fusion and fusion:FindFirstChild("FusionOutput")
				local prompt = output and output:FindFirstChildWhichIsA("ProximityPrompt", true)

				if prompt then Game.FirePrompt(prompt) end
			end
		end

		task.wait(1)
		return
	end

	if status == "Waiting" then
		local endsAt = slots:GetAttribute("EndsAt") or 0

		if workspace:GetServerTimeNow() >= endsAt then
			warpTo(FUSION_SPOT)
			action:FireServer("Fuse")
			task.wait(2)
		end

		return
	end

	local empty = {}

	for index = 1, 4 do
		if not slots:FindFirstChild(tostring(index)) then
			table.insert(empty, index)
		end
	end

	if #empty == 0 or slots:GetAttribute("Ready") == true then
		warpTo(FUSION_SPOT)
		action:FireServer("Start")
		task.wait(2)
		return
	end

	local petData = Data.Pets or {}
	local usable = {}

	local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
	if not backpack then return end

	for _, tool in ipairs(backpack:GetChildren()) do
		if tool:IsA("Tool") and CollectionService:HasTag(tool, "Pet") then
			local petName = tool:GetAttribute("PetName") or tool.Name
			local entry = petData[string.match(petName, "^(.-)%s*%[") or petName] or petData[petName]
			local rarity = entry and entry.Rarity or tool:GetAttribute("Rarity")
			local favorited = tool:GetAttribute("Favorited") == true

			if rarity and Fuse.Rarities[rarity] == true then
				if not (Fuse.ProtectFavorited and favorited) then
					table.insert(usable, tool)
				end
			end
		end
	end

	if #usable < #empty then return end

	warpTo(FUSION_SPOT)

	for _, slotIndex in ipairs(empty) do
		if #usable == 0 then break end

		local tool = table.remove(usable, 1)

		if tool and tool.Parent == backpack then
			humanoid:UnequipTools()
			task.wait(0.05)
			humanoid:EquipTool(tool)

			local deadline = os.clock() + 0.8

			while tool.Parent ~= character and os.clock() < deadline do
				task.wait(0.05)
			end

			if tool.Parent == character then
				task.wait(0.1)
				place:FireServer(slotIndex)
				task.wait(0.25)
			end
		end
	end

	task.wait(0.5)

	if slots:GetAttribute("Ready") == true or #slots:GetChildren() >= 4 then
		action:FireServer("Start")
		task.wait(2)
	end
end

local fuseRunning = true

task.spawn(function()
	while fuseRunning do
		task.wait(0.5)
		if Fuse.Enabled then pcall(fuseStep) end
	end
end)

onCleanup(function() fuseRunning = false end)

local function emptyBasket()
	local basket = LocalPlayer:FindFirstChild("Basket")
	if not basket then return 0 end

	local dropped = 0

	for _, child in ipairs(basket:GetChildren()) do
		local eggName = child:GetAttribute("Egg")

		if type(eggName) == "string" then
			Game.Fire("BasketDrop", eggName)
			dropped = dropped + 1
			task.wait(0.05)
		end
	end

	return dropped
end

local TELEPORTS = {
	["My Plot"] = function()
		local top = Game.PlotTop()
		return top and top + Vector3.new(0, 4, 0) or nil
	end,
	["Volcano Top"] = function() return VOLCANO_TOP end,
	["Fuse Machine"] = function() return FUSION_SPOT + Vector3.new(0, 3, 0) end,
}

local TELEPORT_NAMES = { "My Plot", "Volcano Top", "Fuse Machine" }

local stormWatchRunning = true

task.spawn(function()
	local lastVariant = nil

	while stormWatchRunning do
		task.wait(2)

		local storm = activeStorm()
		local variant = storm and storm.Variant or nil

		if variant ~= lastVariant then
			lastVariant = variant

			if variant and Mutations.Notify then
				Library:Notify({
					Title = "Storm",
					Text = string.format("%s storm active, mutation %s.",
						tostring(variant),
						tostring(STORM_TO_MUTATION[variant] or "unknown")),
					Style = "warning",
					Duration = 6,
				})
			end
		end
	end
end)

onCleanup(function() stormWatchRunning = false end)

local Window = Library:Window({
	Title             = "Facility",
	Suffix            = ".Sexility",
	Width             = 700,
	Height            = 580,
	MinWidth          = 580,
	SectionTitleStyle = "border",
	MobileButton      = true,
})

local FarmTab   = Window:Tab("Farm", "leaf")
local PlotTab   = Window:Tab("Plot", "box")
local EventTab  = Window:Tab("Event", "zap")
local PlayerTab = Window:Tab("Player", "user")
local ServerTab = Window:Tab("Server", "globe")
local MiscTab   = Window:Tab("Misc", "wrench")
local Settings  = Window:Tab("Settings", "cog")

local statusBox = FarmTab:Section("Status", 1)

local statusLabel = statusBox:Label("Idle")
local basketLabel = statusBox:Label("Basket 0 / 0", { Style = "dim" })

task.spawn(function()
	local shown = nil
	local shownBasket = nil

	while true do
		task.wait(0.2)

		if Game.Status ~= shown then
			shown = Game.Status
			pcall(function() statusLabel:Set(shown) end)
		end

		local basket = string.format("Basket %d / %d  ·  Cash %d",
			Game.BasketCount(), Game.BasketCapacity(), Game.Cash())

		if basket ~= shownBasket then
			shownBasket = basket
			pcall(function() basketLabel:Set(basket) end)
		end
	end
end)

local collectBox = FarmTab:Section("Auto Collect Eggs", 2)

collectBox:Toggle({
	Text = "Auto Collect Eggs",
	Flag = "farm_collect",
	Default = false,
	Callback = function(state)
		Farm.Collect = state
		Farm.Wake()
	end,
})

collectBox:Dropdown({
	Text = "Min Rarity",
	Flag = "farm_collect_rarity",
	Options = RARITY_CHOICES,
	Default = RARITY_CHOICES[1],
	Callback = function(value)
		Collect.MinRank = RARITY_RANK[tostring(value)] or 0
	end,
})

collectBox:Dropdown({
	Text = "Target Eggs",
	Flag = "farm_collect_targets",
	Options = eggChoices,
	Default = {},
	Multi = true,
	Empty = "Any egg",
	Callback = function(selected)
		local set = {}
		for _, name in ipairs(selected) do set[name] = true end
		Collect.Targets = set
	end,
})

collectBox:Dropdown({
	Text = "Priority",
	Flag = "farm_collect_priority",
	Options = PRIORITIES,
	Default = PRIORITIES[2],
	Callback = function(value) Collect.Priority = tostring(value) end,
})

collectBox:Slider({
	Text = "Fly Speed",
	Flag = "farm_fly_speed",
	Min = 100, Max = 3000, Default = 600,
	Suffix = " studs/s",
	Callback = function(value)
		Game.FlySpeed = math.clamp(tonumber(value) or 600, 100, 3000)
	end,
})

collectBox:Toggle({
	Text = "Prefer Heaviest",
	Flag = "farm_prefer_heaviest",
	Default = false,
	Callback = function(state) Weight.PreferHeaviest = state end,
})

collectBox:Slider({
	Text = "Min Weight",
	Flag = "farm_min_weight",
	Min = 0, Max = 50, Default = 0,
	Decimals = 1,
	Suffix = " kg",
	Callback = function(value) Weight.Minimum = tonumber(value) or 0 end,
})

local mutationBox = FarmTab:Section("Mutation Sniper", 1)

mutationBox:Toggle({
	Text = "Prioritize Mutated Eggs",
	Flag = "mut_prioritize",
	Default = true,
	Callback = function(state) Mutations.Prioritize = state end,
})

mutationBox:Dropdown({
	Text = "Min Mutation Tier",
	Flag = "mut_tier",
	Options = MUTATION_TIERS,
	Default = MUTATION_TIERS[1],
	Callback = function(value) Mutations.MinTier = tostring(value) end,
})

mutationBox:Toggle({
	Text = "Wait For Storm",
	Flag = "mut_wait_storm",
	Default = false,
	Callback = function(state) Mutations.WaitForStorm = state end,
})

mutationBox:Toggle({
	Text = "Storm Alerts",
	Flag = "mut_notify",
	Default = true,
	Callback = function(state) Mutations.Notify = state end,
})

local radarLabel = mutationBox:Label("No high tier egg in sight", { Style = "dim" })

task.spawn(function()
	local shown = nil

	while true do
		task.wait(1)

		local best = nil
		local bestWeight = 0

		for _, child in ipairs(ActiveEggs:GetChildren()) do
			local eggName = child:GetAttribute("Egg")
			local mutation = mutationOf(child)

			if type(eggName) == "string" and mutation then
				local weight = MUTATION_WEIGHT[mutation] or 0

				if weight > bestWeight then
					bestWeight = weight
					best = string.format("%s  ·  %s", eggName, mutation)
				end
			end
		end

		local text = best or "No high tier egg in sight"

		if text ~= shown then
			shown = text
			pcall(function() radarLabel:Set(text) end)
		end
	end
end)

local plantBox = PlotTab:Section("Plant & Hatch", 1)

plantBox:Toggle({
	Text = "Auto Plant Eggs",
	Flag = "farm_plant",
	Default = false,
	Callback = function(state)
		Farm.Plant = state
		Plant.BlockedUntil = 0
		Farm.Wake()
	end,
})

plantBox:Dropdown({
	Text = "Plant Min Rarity",
	Flag = "farm_plant_rarity",
	Options = RARITY_CHOICES,
	Default = RARITY_CHOICES[1],
	Callback = function(value)
		Plant.MinRank = RARITY_RANK[tostring(value)] or 0
	end,
})

plantBox:Toggle({
	Text = "Auto Hatch Eggs",
	Flag = "farm_hatch",
	Default = false,
	Callback = function(state)
		Farm.Hatch = state
		Farm.Wake()
	end,
})

local petBox = PlotTab:Section("Pets", 2)

petBox:Toggle({
	Text = "Auto Place Best Pets",
	Flag = "farm_place",
	Default = false,
	Callback = function(state)
		Farm.Place = state
		Farm.Wake()
	end,
})
	:Gear(function(panel)
		panel:Toggle({
			Text = "Swap Weaker Pets",
			Flag = "farm_swap",
			Default = false,
			Callback = function(state)
				Farm.Swap = state
				Farm.Wake()
			end,
		})
	end)

petBox:Toggle({
	Text = "Auto Feed Pets",
	Flag = "farm_feed",
	Default = false,
	Callback = function(state)
		Farm.Feed = state
		table.clear(Pets.FeedCooldowns)
		Farm.Wake()
	end,
})

petBox:Dropdown({
	Text = "Foods To Use",
	Flag = "farm_feed_foods",
	Options = foodChoices,
	Default = {},
	Multi = true,
	Empty = "Cheapest",
	Callback = function(selected)
		local set = {}
		for _, name in ipairs(selected) do set[name] = true end
		Pets.Foods = set
	end,
})

petBox:Toggle({
	Text = "Skip Max Age Pets",
	Flag = "farm_feed_skip_age",
	Default = true,
	Callback = function(state) Pets.SkipMaxAge = state end,
})

petBox:Toggle({
	Text = "Allow Premium Food",
	Flag = "farm_feed_premium",
	Default = true,
	Callback = function(state) Pets.AllowPremium = state end,
})

local nestBox = PlotTab:Section("Nests & Upgrades", 1)

nestBox:Toggle({
	Text = "Auto Upgrade Hatch Luck",
	Flag = "plot_upgrade_luck",
	Default = false,
	Callback = function(state) Plot.UpgradeLuck = state end,
})

nestBox:Toggle({
	Text = "Auto Unlock Nests",
	Flag = "plot_unlock_nests",
	Default = false,
	Callback = function(state) Plot.UnlockNests = state end,
})

nestBox:Toggle({
	Text = "Spawn Nest Glitch",
	Flag = "plot_spawn_nest",
	Default = false,
	Callback = function(state) pcall(applySpawnNest, state) end,
})

local magmaBox = EventTab:Section("Magma Dip", 1)

magmaBox:Toggle({
	Text = "Auto Magma Lava Dip",
	Flag = "event_magma",
	Default = false,
	Callback = function(state) Magma.Enabled = state end,
})

magmaBox:Slider({
	Text = "Dip Duration",
	Flag = "event_magma_duration",
	Min = 3, Max = 20, Default = 9.5,
	Decimals = 1,
	Suffix = " s",
	Callback = function(value) Magma.Duration = tonumber(value) or 9.5 end,
})

magmaBox:Button({
	Text = "Teleport To Volcano",
	Callback = function()
		volcanoPlatform()
		warpTo(VOLCANO_TOP)
	end,
})

local fuseBox = EventTab:Section("Fuse Machine", 2)

fuseBox:Toggle({
	Text = "Auto Fuse",
	Flag = "event_fuse",
	Default = false,
	Callback = function(state) Fuse.Enabled = state end,
})

fuseBox:Dropdown({
	Text = "Rarities To Fuse",
	Flag = "event_fuse_rarities",
	Options = RARITY_ORDER,
	Default = {},
	Multi = true,
	Empty = "Nothing",
	Callback = function(selected)
		local set = {}
		for _, name in ipairs(selected) do set[name] = true end
		Fuse.Rarities = set
	end,
})

fuseBox:Toggle({
	Text = "Protect Favorited Pets",
	Flag = "event_fuse_protect",
	Default = true,
	Callback = function(state) Fuse.ProtectFavorited = state end,
})

fuseBox:Toggle({
	Text = "Auto Favorite Results",
	Flag = "event_fuse_favorite",
	Default = false,
	Callback = function(state) Fuse.AutoFavorite = state end,
})

fuseBox:Button({
	Text = "Teleport To Fuse Machine",
	Callback = function() warpTo(FUSION_SPOT) end,
})

local shopBox = FarmTab:Section("Shop", 2)

shopBox:Toggle({
	Text = "Auto Buy Food",
	Flag = "shop_food",
	Default = false,
	Callback = function(state) Shop.Enabled.Food = state end,
})

shopBox:Dropdown({
	Text = "Food To Buy",
	Flag = "shop_food_items",
	Options = shopChoices("Food"),
	Default = {},
	Multi = true,
	Empty = "Nothing",
	Callback = function(selected)
		local set = {}
		for _, name in ipairs(selected) do set[name] = true end
		Shop.Wanted.Food = set
	end,
})

shopBox:Toggle({
	Text = "Auto Buy Gears",
	Flag = "shop_gears",
	Default = false,
	Callback = function(state) Shop.Enabled.Gears = state end,
})

shopBox:Dropdown({
	Text = "Gears To Buy",
	Flag = "shop_gear_items",
	Options = shopChoices("Gears"),
	Default = {},
	Multi = true,
	Empty = "Nothing",
	Callback = function(selected)
		local set = {}
		for _, name in ipairs(selected) do set[name] = true end
		Shop.Wanted.Gears = set
	end,
})

shopBox:Slider({
	Text = "Keep Cash",
	Flag = "shop_keep_cash",
	Min = 0, Max = 1000000, Default = 0,
	Callback = function(value) Shop.KeepCash = math.max(0, tonumber(value) or 0) end,
})

local progressBox = FarmTab:Section("Progress", 2)

progressBox:Toggle({
	Text = "Auto Rebirth",
	Flag = "progress_rebirth",
	Default = false,
	Callback = function(state) Progress.Rebirth = state end,
})

progressBox:Toggle({
	Text = "Auto Claim Index Reward",
	Flag = "progress_index",
	Default = false,
	Callback = function(state) Progress.ClaimIndex = state end,
})

if Movement then

Movement.Settings.WalkSpeedMode = "Velocity"
Movement.Settings.JumpMode = "Humanoid"

local moveBox = PlayerTab:Section("Movement", 1)

moveBox:Toggle({
	Text = "Speed Boost",
	Flag = "move_walkspeed",
	Default = false,
	Callback = function(state)
		Movement:WalkSpeed(state and Movement.Settings.WalkSpeed or 16)
	end,
})

moveBox:Slider({
	Text = "Speed",
	Flag = "move_walkspeed_value",
	Min = 16, Max = 300, Default = 16,
	Callback = function(value)
		Movement.Settings.WalkSpeed = value
		if Library.Flags["move_walkspeed"] then Movement:WalkSpeed(value) end
	end,
})

moveBox:Toggle({
	Text = "Infinite Jump",
	Flag = "move_infinite_jump",
	Default = false,
	Callback = function(state) Movement:InfiniteJump(state) end,
})

moveBox:Toggle({
	Text = "Noclip",
	Flag = "move_noclip",
	Default = false,
	Callback = function(state) Movement:Noclip(state) end,
})
	:Keybind({ Default = "N", Flag = "move_noclip_key" })

moveBox:Toggle({
	Text = "Fly",
	Flag = "move_fly",
	Default = false,
	Callback = function(state) Movement:Fly(state) end,
})
	:Keybind({ Default = "F", Flag = "move_fly_key" })

moveBox:Slider({
	Text = "Fly Speed",
	Flag = "move_fly_speed",
	Min = 1, Max = 20, Default = 2,
	Decimals = 1,
	Callback = function(value) Movement.Settings.FlySpeed = value end,
})

end

local travelBox = PlayerTab:Section("Fast Travel", 2)

local travelTarget = TELEPORT_NAMES[1]

travelBox:Dropdown({
	Text = "Destination",
	Flag = "travel_target",
	Options = TELEPORT_NAMES,
	Default = TELEPORT_NAMES[1],
	Callback = function(value) travelTarget = tostring(value) end,
})

travelBox:Button({
	Text = "Teleport",
	Callback = function()
		local resolve = TELEPORTS[travelTarget]
		local position = resolve and resolve()

		if not position then
			Library:Notify({
				Title = "Teleport",
				Text = "That destination is not available right now.",
				Style = "error",
				Duration = 5,
			})
			return
		end

		warpTo(position)
	end,
})

travelBox:Button({
	Text = "Empty Basket",
	Callback = function()
		local dropped = emptyBasket()

		Library:Notify({
			Title = "Basket",
			Text = string.format("Dropped %d egg(s).", dropped),
			Style = dropped > 0 and "success" or "normal",
			Duration = 4,
		})
	end,
})

local utilityBox = PlayerTab:Section("Utility", 1)

utilityBox:Toggle({
	Text = "Instant Pickup",
	Flag = "player_instant_pickup",
	Default = false,
	Callback = instantPickup,
})

local espBox = PlayerTab:Section("Egg Esp", 1)

espBox:Toggle({
	Text = "Enable",
	Flag = "esp_eggs",
	Default = false,
	Callback = setEggEsp,
})
	:Keybind({ Default = "RightAlt", Flag = "esp_eggs_key" })

espBox:Dropdown({
	Text = "Min Rarity",
	Flag = "esp_eggs_rarity",
	Options = RARITY_CHOICES,
	Default = RARITY_CHOICES[1],
	Callback = function(value)
		EggEsp.MinRank = RARITY_RANK[tostring(value)] or 0
		if EggEsp.Enabled then refreshEggEsp() end
	end,
})

espBox:Slider({
	Text = "Max Distance",
	Flag = "esp_eggs_distance",
	Min = 100, Max = 10000, Default = 5000,
	Suffix = " studs",
	Callback = function(value)
		for _, rarity in ipairs(RARITY_ORDER) do
			Esp.teamSettings["egg" .. rarity].maxDistance = value
		end
	end,
})

espBox:Toggle({
	Text = "Tracers",
	Flag = "esp_eggs_tracer",
	Default = false,
	Callback = function(state)
		for _, rarity in ipairs(RARITY_ORDER) do
			Esp.teamSettings["egg" .. rarity].tracer = state
		end
	end,
})

espBox:Slider({
	Text = "Text Size",
	Flag = "esp_eggs_text_size",
	Min = 8, Max = 24, Default = 13,
	Callback = function(value) Esp.sharedSettings.textSize = value end,
})

local hopBox = ServerTab:Section("Server Hop", 1)

hopBox:Dropdown({
	Text = "Mode",
	Flag = "hop_mode",
	Options = { "Least Players", "Most Players", "Random" },
	Default = "Least Players",
	Callback = function(value) Hop.Mode = tostring(value or "Least Players") end,
})

hopBox:Button({
	Text = "Hop Now",
	Callback = startHop,
})

hopBox:Button({
	Text = "Rejoin Server",
	Callback = function()
		pcall(function()
			TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
		end)
	end,
})

hopBox:Button({
	Text = "Copy Job ID",
	Callback = function()
		if type(setclipboard) == "function" then
			pcall(setclipboard, tostring(game.JobId))
			Library:Notify({ Title = "Server", Text = "Job ID copied.", Style = "success", Duration = 3 })
		else
			Library:Notify({ Title = "Server", Text = "This executor has no setclipboard.", Style = "error", Duration = 5 })
		end
	end,
})

local browserBox = ServerTab:Section("Browser", 2)

local browserApi = nil

browserBox:Button({
	Text = "Open Server Browser",
	Callback = function()
		if not browserApi then
			local ok, result = pcall(function()
				return Library:ServerBrowser({
					PlaceId = game.PlaceId,
					MaxRows = 50,
					OnJoin = function(jobId, placeId)
						TeleportService:TeleportToPlaceInstance(placeId or game.PlaceId, jobId, LocalPlayer)
					end,
				})
			end)

			if not ok or type(result) ~= "table" then
				Library:Notify({
					Title = "Server",
					Text = tostring(result),
					Style = "error",
					Duration = 8,
				})
				return
			end

			browserApi = result
		end

		browserApi:Toggle()
	end,
})

local perfBox = MiscTab:Section("Performance", 1)

perfBox:Slider({
	Text = "FPS Cap",
	Flag = "misc_fps_cap",
	Min = 30, Max = 1000, Default = 240,
	Suffix = " fps",
	Callback = setFpsCap,
})

perfBox:Toggle({
	Text = "Optimizer",
	Flag = "misc_optimizer",
	Default = false,
	Callback = setOptimizer,
})

local utilBox = MiscTab:Section("Utility", 2)

utilBox:Toggle({
	Text = "Anti AFK",
	Flag = "misc_anti_afk",
	Default = true,
	Callback = function(state)
		antiAfk.Enabled = state ~= false

		if antiAfk.Enabled then
			suspendIdle()
		else
			resumeIdle()
		end
	end,
})

local hudPanel = Library:Panel({
	Title = "stats",
	Icon = "activity",
	Width = 170,
	Position = UDim2.fromOffset(18, 320),
	Visible = false,
})

hudPanel:SetVisible(false)

hudPanel.Content:Label("fps", { Style = "dim" })
local fpsLabel = hudPanel.Content:Label("-", { Style = "bright" })

hudPanel.Content:Divider()

hudPanel.Content:Label("ping", { Style = "dim" })
local pingLabel = hudPanel.Content:Label("-", { Style = "bright" })

hudPanel.Content:Divider()

hudPanel.Content:Label("status", { Style = "dim" })
local panelStatus = hudPanel.Content:Label("Idle")

local counterBox = MiscTab:Section("Counters", 1)

local counterShown = false

counterBox:Toggle({
	Text = "Show Stats Panel",
	Flag = "misc_counters",
	Default = false,
	Callback = function(state)
		counterShown = state
		hudPanel:SetVisible(state)
	end,
})
	:Keybind({ Default = "RightControl", Flag = "misc_counters_key" })

task.spawn(function()
	local frames = 0
	local since = os.clock()
	local fps = 0

	local connection = RunService.RenderStepped:Connect(function()
		frames = frames + 1
		local now = os.clock()

		if now - since >= 0.5 then
			fps = math.floor(frames / (now - since) + 0.5)
			frames = 0
			since = now
		end
	end)

	onCleanup(function() connection:Disconnect() end)

	local lastStatus = nil

	while true do
		task.wait(0.5)

		if counterShown then
			local ping = 0

			pcall(function()
				ping = math.floor(game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue())
			end)

			pcall(function() fpsLabel:Set(tostring(fps)) end)
			pcall(function() pingLabel:Set(string.format("%d ms", ping)) end)

			if Game.Status ~= lastStatus then
				lastStatus = Game.Status
				pcall(function() panelStatus:Set(Game.Status) end)
			end
		end
	end
end)

onCleanup(function()
	pcall(function() hudPanel:SetVisible(false) end)
end)

local SaveManager      = Library.SaveManager
local InterfaceManager = Library.InterfaceManager
local ThemeManager     = Library.ThemeManager

SaveManager:SetLibrary(Library)
InterfaceManager:SetLibrary(Library)
InterfaceManager:SetWindow(Window)
ThemeManager:SetLibrary(Library)

SaveManager:IgnoreThemeSettings()
InterfaceManager:SetFolder("Facility")
ThemeManager:SetFolder("Facility")
SaveManager:SetFolder("Facility/124216119978534")

InterfaceManager:BuildInterfaceSection(Settings, 1)
SaveManager:BuildConfigSection(Settings, 2)
ThemeManager:Mount(Window)

Window:SetTab(FarmTab)

Library:Notify("Facility", "Loaded.", 4)

SaveManager:LoadAutoloadConfig()
ThemeManager:Load()

local libraryDestroy = Library.Destroy

function Library:Destroy(...)
	for index = #cleanupTasks, 1, -1 do
		pcall(cleanupTasks[index])
	end

	table.clear(cleanupTasks)

	return libraryDestroy(self, ...)
end

F.Unload = function()
	pcall(function() Library:Destroy() end)
end
