local FH = shared.Facility
local Library = FH and FH.Library

if not Library then
	local BASE = "https://raw.githubusercontent.com/FacilityHUB/UI-Facility/refs/heads/main/"
	local source = game:HttpGet(BASE .. "main.luau")
	local chunk, err = loadstring(source)
	assert(chunk, "main.luau compile error: " .. tostring(err))
	Library = chunk()
	assert(type(Library) == "table", "main.luau returned nothing")
	Library.BaseUrl = BASE
end

local SESSION = (shared.FacilitySession or 0) + 1
shared.FacilitySession = SESSION

local function alive()
	return shared.FacilitySession == SESSION
end

if shared.FacilityCleanup then
	pcall(shared.FacilityCleanup)
	shared.FacilityCleanup = nil
end

local HUB_BASE = FH and FH.HubBase or "https://raw.githubusercontent.com/FacilityHUB/Facility-Sexility/refs/heads/main/"
local moduleErrors = {}

local function fetchModule(path, label)
	local fetched, source = pcall(function()
		return game:HttpGet(HUB_BASE .. path .. "?v=" .. tostring(tick()):gsub("%.", ""))
	end)
	if not fetched or type(source) ~= "string" then
		table.insert(moduleErrors, label .. ": download failed - " .. tostring(source))
		return nil
	end
	local chunk, compileError = loadstring(source)
	if not chunk then
		table.insert(moduleErrors, label .. ": compile failed - " .. tostring(compileError))
		return nil
	end
	local ok, result = pcall(chunk)
	if not ok or type(result) ~= "table" then
		table.insert(moduleErrors, label .. ": load failed - " .. tostring(result))
		return nil
	end
	return result
end

local Movement = fetchModule("CModules/FMovement.luau", "movement")
if Movement then pcall(function() Movement:Load() end) end
if FH then FH.Movement = Movement end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")

local LocalPlayer = Players.LocalPlayer

local H = {}
local U = {}
local S = { connections = {}, threads = {}, instances = {} }
local F = {
	tree = "Generic",
	amount = 1,
	autoFarm = false,
	autoSell = false,
	cutting = false,
	manualCut = false,
	stopFarm = false,
	sellRunning = false,
	dupeCooldown = false,
	timeLock = "Off",
	noFog = false,
	clickTeleport = false,
	antiAfk = true,
	antiKick = true,
	location = "Wood Shop",
	walkOn = false,
	walkValue = 50,
	jumpOn = false,
	jumpValue = 100,
}

local SELL_POSITION = Vector3.new(314.54, -0.5, 86.823)

local LOCATIONS = {
	{ "Wood Shop", CFrame.new(264, 3, 57) },
	{ "Land Office", CFrame.new(111, 11, -987) },
	{ "Furniture Store", CFrame.new(114, 3, -611) },
	{ "Volcano", CFrame.new(-1585, 625, 1140) },
	{ "Swamp", CFrame.new(-1209, 138, -801) },
	{ "Cave", CFrame.new(3581, -177, 430) },
	{ "Palm Island", CFrame.new(2549, 5, -42) },
	{ "Spawn", CFrame.new(0, 5, 0) },
}

local KNOWN_TREES = {
	"Generic", "GoldSwampy", "CaveCrawler", "Cherry", "Frost", "Volcano", "Oak", "Walnut", "Birch",
	"SnowGlow", "Pine", "GreenSwampy", "Koa", "Palm", "Spooky", "SpookyNeon", "LoneCave",
}

function H.track(connection)
	table.insert(S.connections, connection)
	return connection
end

function H.spawn(fn, ...)
	local thread = task.spawn(fn, ...)
	table.insert(S.threads, thread)
	return thread
end

function H.gcall(fn, ...)
	local packed = table.pack(...)
	local box = nil
	task.spawn(function()
		box = table.pack(pcall(fn, table.unpack(packed, 1, packed.n)))
	end)
	if not box then
		local deadline = os.clock() + 10
		while not box and os.clock() < deadline do task.wait() end
	end
	if not box then return false, "timed out" end
	return table.unpack(box, 1, box.n)
end

function H.notify(text, duration)
	pcall(function() Library:Notify("Facility", text, duration or 3) end)
end

function H.find(parent, ...)
	local node = parent
	for _, name in ipairs({ ... }) do
		if not node then return nil end
		node = node:FindFirstChild(name)
	end
	return node
end

function H.remote(...)
	return H.find(ReplicatedStorage, ...)
end

function H.fire(remote, ...)
	if remote then pcall(remote.FireServer, remote, ...) end
end

function H.invoke(remote, ...)
	if not remote then return nil end
	local ok, result = pcall(remote.InvokeServer, remote, ...)
	if ok then return result end
	return nil
end

function H.root()
	local character = LocalPlayer.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

function H.humanoid()
	local character = LocalPlayer.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

function H.teleport(cframe)
	local root = H.root()
	if not root then return false end
	root.CFrame = cframe
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	return true
end

function H.stopped(isAuto)
	if not alive() then return true end
	if isAuto then return F.stopFarm end
	return not F.manualCut
end

function H.isOwned(model)
	local owner = model:FindFirstChild("Owner")
	if not owner then return false end
	if owner:IsA("ObjectValue") then return owner.Value == LocalPlayer end
	if owner:IsA("StringValue") then return owner.Value == LocalPlayer.Name end
	local ownerString = owner:FindFirstChild("OwnerString")
	return ownerString ~= nil and ownerString.Value == LocalPlayer.Name
end

function H.dragRemotes()
	return H.remote("Interaction", "ClientIsDragging"), H.remote("Interaction", "ClientRequestOwnership")
end

function H.properties()
	local folder = workspace:FindFirstChild("Properties")
	return folder and folder:GetChildren() or {}
end

function H.myProperty()
	for _, plot in ipairs(H.properties()) do
		local owner = plot:FindFirstChild("Owner")
		if owner and owner.Value == LocalPlayer then return plot end
	end
end

function H.freeProperty()
	local free = {}
	for _, plot in ipairs(H.properties()) do
		local owner = plot:FindFirstChild("Owner")
		if owner and owner.Value == nil and plot:FindFirstChild("OriginSquare") then table.insert(free, plot) end
	end
	if #free == 0 then return nil end
	return free[math.random(1, #free)]
end

function H.claimLand()
	if H.myProperty() then
		H.notify("You already own a plot.")
		return
	end
	local plot = H.freeProperty()
	if not plot then
		H.notify("No free plot found.")
		return
	end
	local setPurchasing = H.remote("PropertyPurchasing", "SetPropertyPurchasingValue")
	local purchased = H.remote("PropertyPurchasing", "ClientPurchasedProperty")
	if not purchased then
		H.notify("Land remote not found.")
		return
	end
	H.invoke(setPurchasing, true)
	H.fire(purchased, plot, plot.OriginSquare.Position)
	H.invoke(setPurchasing, false)
	H.teleport(plot.OriginSquare.CFrame + Vector3.new(0, 4, 0))
	H.notify("Plot claimed.")
end

function H.expandLand()
	local plot = H.myProperty()
	if not plot then
		H.notify("You need to own a plot first.")
		return
	end
	local origin = plot:FindFirstChild("OriginSquare")
	local expanded = H.remote("PropertyPurchasing", "ClientExpandedProperty")
	if not origin or not expanded then
		H.notify("Land expansion not available.")
		return
	end
	local base = origin.Position
	local offsets = {
		{ 40, 0 }, { -40, 0 }, { 0, 40 }, { 0, -40 },
		{ 40, 40 }, { 40, -40 }, { -40, 40 }, { -40, -40 },
		{ 80, 0 }, { -80, 0 }, { 0, 80 }, { 0, -80 },
		{ 80, 80 }, { 80, -80 }, { -80, 80 }, { -80, -80 },
		{ 40, 80 }, { -40, 80 }, { 80, 40 }, { 80, -40 },
		{ -80, 40 }, { -80, -40 }, { 40, -80 }, { -40, -80 },
	}
	for _, offset in ipairs(offsets) do
		if not alive() then return end
		H.fire(expanded, plot, CFrame.new(base.X + offset[1], base.Y, base.Z + offset[2]))
		task.wait(0.05)
	end
	H.notify("Plot expanded to max size.")
end

function H.ownedWood(includeSections)
	local list = {}
	local logs = workspace:FindFirstChild("LogModels")
	if logs then
		for _, model in ipairs(logs:GetChildren()) do
			if model:IsA("Model") and H.isOwned(model) then table.insert(list, model) end
		end
	end
	local placed = workspace:FindFirstChild("PlayerModels")
	if placed then
		for _, model in ipairs(placed:GetChildren()) do
			if model:IsA("Model") and H.isOwned(model) then
				if model:FindFirstChild("WoodSection") or (includeSections and model:FindFirstChild("TreeClass")) then
					table.insert(list, model)
				end
			end
		end
	end
	return list
end

function H.sections(model)
	local list = {}
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") and part.Name == "WoodSection" then table.insert(list, part) end
	end
	return list
end

function H.highestSection(model)
	local best
	for _, part in ipairs(H.sections(model)) do
		if not best or part.Position.Y > best.Position.Y then best = part end
	end
	return best
end

function H.sellAll(isAuto)
	local root = H.root()
	if not root then return 0 end
	local dragging, ownership = H.dragRemotes()
	local home = root.CFrame
	local total, empty, attempts = 0, 0, 0

	while empty < 3 and attempts < 30 and not (isAuto and H.stopped(true)) and alive() do
		attempts += 1
		local targets = H.ownedWood(true)
		if #targets == 0 then
			empty += 1
			task.wait(1)
		else
			empty = 0
			for _, model in ipairs(targets) do
				if isAuto and H.stopped(true) then break end
				total += 1
				for _, section in ipairs(H.sections(model)) do
					if isAuto and H.stopped(true) then break end
					if section.Parent then
						local current = H.root()
						if current and (current.Position - section.Position).Magnitude > 10 then
							current.CFrame = CFrame.new(section.Position + Vector3.new(0, 3, 0))
							task.wait(0.05)
						end
						for _, joint in ipairs(model:GetDescendants()) do
							if (joint:IsA("Weld") or joint:IsA("WeldConstraint") or joint:IsA("ManualWeld"))
								and (joint.Part0 == section or joint.Part1 == section) then
								pcall(function() joint:Destroy() end)
							end
						end
						for _ = 1, 3 do
							H.fire(dragging, model)
							H.fire(ownership, section)
							task.wait(0.01)
						end
						local spin = CFrame.Angles(math.rad(math.random(0, 360)), math.rad(math.random(0, 360)), math.rad(math.random(0, 360)))
						section.CFrame = CFrame.new(SELL_POSITION) * spin
						section.AssemblyLinearVelocity = Vector3.zero
					end
				end
			end
			task.wait(0.5)
		end
	end

	if H.root() then H.teleport(home) end
	return total
end

function H.splitWood()
	local root = H.root()
	if not root then return end
	local dragging = H.dragRemotes()
	local home = root.CFrame
	local count = 0
	for _, model in ipairs(H.ownedWood(false)) do
		if not alive() then break end
		local top = H.highestSection(model)
		if top then
			count += 1
			local current = H.root()
			if current then current.CFrame = CFrame.new(top.Position.X, current.Position.Y, top.Position.Z) end
			task.wait(0.05)
			for _, joint in ipairs(model:GetDescendants()) do
				if joint:IsA("JointInstance") or joint:IsA("WeldConstraint") then
					pcall(function() joint:Destroy() end)
				end
			end
			for _ = 1, 3 do
				H.fire(dragging, model)
				task.wait(0.01)
			end
			for _, part in ipairs(H.sections(model)) do
				part.Anchored = false
				part.CFrame = home * CFrame.new(math.random(-8, 8), 2, math.random(-8, 8))
				part.AssemblyLinearVelocity = Vector3.zero
			end
		end
	end
	H.teleport(home)
	H.notify("Split " .. count .. " wood models.")
end

function H.bringLogs()
	local root = H.root()
	if not root then return end
	local dragging, ownership = H.dragRemotes()
	local home = root.CFrame
	local count = 0
	local logs = workspace:FindFirstChild("LogModels")
	for _, model in ipairs(logs and logs:GetChildren() or {}) do
		if not alive() then break end
		if model:IsA("Model") and H.isOwned(model) then
			local top = H.highestSection(model)
			if top then
				if not model.PrimaryPart then model.PrimaryPart = top end
				local current = H.root()
				if current then current.CFrame = CFrame.new(top.Position.X, home.Position.Y, top.Position.Z) end
				task.wait(0.05)
				for _ = 1, 5 do
					H.fire(ownership, model)
					H.fire(dragging, model)
					if model.PrimaryPart then model:PivotTo(home * CFrame.new(0, 0, -5)) end
					task.wait(0.02)
				end
				count += 1
			end
		end
	end
	H.teleport(home)
	H.notify("Brought " .. count .. " logs.")
end

function H.tools()
	local humanoid = H.humanoid()
	if humanoid then humanoid:UnequipTools() end
	local backpack = LocalPlayer:FindFirstChild("Backpack")
	local list = {}
	for _, tool in ipairs(backpack and backpack:GetChildren() or {}) do
		if tool:IsA("Tool") and tool.Name ~= "BlueprintTool" and tool:FindFirstChild("ToolName") then
			table.insert(list, tool)
		end
	end
	return list
end

function H.axeStats(tool)
	local name = typeof(tool) == "string" and tool or tool.ToolName.Value
	local classes = ReplicatedStorage:FindFirstChild("AxeClasses")
	local module = classes and classes:FindFirstChild("AxeClass_" .. name)
	if not module then return nil end
	local ok, stats = H.gcall(function() return require(module).new() end)
	if ok and type(stats) == "table" then return stats end
	return nil
end

function H.damageFor(stats, treeClass)
	local damage = stats.Damage or 0
	local special = stats.SpecialTrees and stats.SpecialTrees[treeClass]
	if special and special.Damage then damage = special.Damage end
	return damage
end

function H.bestAxe(treeClass)
	local tools = H.tools()
	if #tools == 0 then return nil, "No axe in your backpack." end
	if treeClass == "LoneCave" then
		for _, tool in ipairs(tools) do
			if tool.ToolName.Value == "EndTimesAxe" then return tool end
		end
		return nil, "This tree needs the End Times axe."
	end
	local best, bestDamage = nil, -1
	for _, tool in ipairs(tools) do
		local stats = H.axeStats(tool)
		local damage = stats and H.damageFor(stats, treeClass) or 0
		if damage > bestDamage then best, bestDamage = tool, damage end
	end
	return best
end

S.treeRegions = {}
S.treeClasses = {}

function H.scanTrees()
	table.clear(S.treeRegions)
	local classes = {}
	for _, region in ipairs(workspace:GetChildren()) do
		if region.Name == "TreeRegion" then
			local found = {}
			for _, tree in ipairs(region:GetChildren()) do
				local class = tree:FindFirstChild("TreeClass")
				if class then
					found[class.Value] = true
					classes[class.Value] = true
				end
			end
			S.treeRegions[region] = found
		end
	end
	for _, name in ipairs(KNOWN_TREES) do classes[name] = true end
	local list = {}
	for name in pairs(classes) do table.insert(list, name) end
	table.sort(list, function(a, b)
		if a == "Generic" then return true end
		if b == "Generic" then return false end
		return a < b
	end)
	S.treeClasses = list
	return list
end

function H.biggestTree(treeClass)
	local best
	for region, classes in pairs(S.treeRegions) do
		if classes[treeClass] and region.Parent then
			for _, tree in ipairs(region:GetChildren()) do
				local class = tree:FindFirstChild("TreeClass")
				local owner = tree:FindFirstChild("Owner")
				if tree:IsA("Model") and class and owner and class.Value == treeClass
					and (owner.Value == nil or owner.Value == LocalPlayer) then
					local mass, trunk = 0, nil
					for _, part in ipairs(tree:GetChildren()) do
						if part:IsA("BasePart") then
							local id = part:FindFirstChild("ID")
							if id and id.Value == 1 then trunk = part end
							mass += part:GetMass()
						end
					end
					if trunk and trunk.Size.X >= 1 and trunk.Size.Y >= 2 and trunk.Size.Z >= 1
						and (not best or mass > best.mass) then
						best = { tree = tree, trunk = trunk, mass = mass }
					end
				end
			end
		end
	end
	return best
end

function H.cutTree(treeClass, isAuto)
	F.cutting = true
	local function finish(ok, message)
		F.cutting = false
		return ok, message
	end

	local axe, axeError = H.bestAxe(treeClass)
	if not axe then return finish(false, axeError) end
	local info = H.biggestTree(treeClass)
	if not info then return finish(false, "No " .. treeClass .. " tree available.") end
	local root = H.root()
	if not root then return finish(false, "No character.") end
	local logs = workspace:FindFirstChild("LogModels")
	local cutRemote = H.remote("Interaction", "RemoteProxy")
	if not logs or not cutRemote then return finish(false, "Game remotes not found.") end

	local dragging, ownership = H.dragRemotes()
	local home = root.CFrame
	local stats = H.axeStats(axe)
	local damage = stats and H.damageFor(stats, treeClass) or 1

	local hold = Instance.new("BodyPosition")
	hold.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
	hold.Position = info.trunk.Position
	hold.Parent = root
	table.insert(S.instances, hold)

	H.teleport(info.trunk.CFrame)
	task.wait(0.1)

	local down = false
	local listener = logs.ChildAdded:Connect(function(child)
		local owner = child:WaitForChild("Owner", 3)
		local class = child:FindFirstChild("TreeClass")
		if not owner or owner.Value ~= LocalPlayer or not class or class.Value ~= treeClass then return end
		down = true
		local section = child:FindFirstChild("WoodSection")
		if not child.PrimaryPart and section then child.PrimaryPart = section end
		for _ = 1, 30 do
			if H.stopped(isAuto) then break end
			H.fire(ownership, child)
			H.fire(dragging, child)
			if child.PrimaryPart then child:PivotTo(home) end
			task.wait(0.02)
		end
	end)

	local started = os.clock()
	while not down and os.clock() - started < 60 and not H.stopped(isAuto) do
		local cutEvent = info.tree.Parent and info.tree:FindFirstChild("CutEvent")
		if cutEvent then
			H.fire(cutRemote, cutEvent, {
				tool = axe, faceVector = Vector3.new(1, 0, 0), height = 0.32,
				sectionId = 1, hitPoints = damage, cooldown = -14, cuttingClass = "Axe",
			})
		end
		task.wait(0.1)
	end

	task.wait(0.5)
	listener:Disconnect()
	pcall(function() hold:Destroy() end)
	H.teleport(home)

	if not down then
		if H.stopped(isAuto) then return finish(false, "Stopped") end
		return finish(false, "Timed out, this tree may not be cuttable.")
	end
	return finish(true)
end

function H.setFarmToggle(state)
	task.defer(function()
		if U.autoFarm and U.autoFarm.Set then pcall(function() U.autoFarm:Set(state) end) end
	end)
end

function H.farmLoop()
	local fails = 0
	while F.autoFarm and not F.stopFarm and alive() do
		if not H.root() then
			H.notify("Waiting for respawn...", 2)
			pcall(function() LocalPlayer.CharacterAdded:Wait() end)
			task.wait(2)
		end
		if F.stopFarm or not alive() then break end

		local cut = 0
		for index = 1, F.amount do
			if not F.autoFarm or F.stopFarm or not alive() then break end
			local ok, message = H.cutTree(F.tree, true)
			if ok then
				cut += 1
				H.notify("Cut " .. index .. "/" .. F.amount, 1)
			else
				if message ~= "Stopped" then
					fails += 1
					H.notify("Cut failed: " .. tostring(message), 2)
					if fails >= 5 then
						H.notify("Auto farm stopped after 5 failures.", 5)
						F.autoFarm = false
						H.setFarmToggle(false)
						return
					end
				end
				break
			end
			task.wait(0.5)
		end

		if cut > 0 and not F.stopFarm and alive() then
			fails = 0
			task.wait(0.5)
			local sold = H.sellAll(true)
			H.notify("Sold " .. sold .. " logs.", 2)
		end
		task.wait(0.5)
	end
	F.cutting = false
end

function H.startAutoSell()
	if F.sellRunning then return end
	F.sellRunning = true
	H.spawn(function()
		while F.autoSell and alive() do
			if not F.cutting and not F.manualCut then pcall(H.sellAll, false) end
			task.wait(2)
		end
		F.sellRunning = false
	end)
end

function H.manualCut()
	if F.manualCut then
		F.manualCut = false
		H.notify("Stopping...", 2)
		return
	end
	if F.autoFarm or F.cutting then
		H.notify("A cut or auto farm is already running.")
		return
	end
	F.manualCut = true
	H.notify("Cutting started, press again to stop.", 2)
	H.spawn(function()
		local done = 0
		for index = 1, F.amount do
			if not F.manualCut or not alive() then break end
			local ok, message = H.cutTree(F.tree, false)
			if ok then
				done += 1
				H.notify("Cut " .. index .. "/" .. F.amount, 2)
			else
				if message ~= "Stopped" then H.notify("Failed: " .. tostring(message), 3) end
				break
			end
			task.wait(0.5)
		end
		F.manualCut = false
		if done > 0 then H.notify("Finished, " .. done .. "/" .. F.amount .. " trees cut.") end
	end)
end

function H.unlockBlueprints()
	local owned = H.find(LocalPlayer, "PlayerBlueprints", "Blueprints")
	local info = ReplicatedStorage:FindFirstChild("ClientItemInfo")
	if not owned or not info then
		H.notify("Blueprint folders not found.")
		return
	end
	local count = 0
	for _, item in ipairs(info:GetChildren()) do
		if item:FindFirstChild("WoodCost") and not owned:FindFirstChild(item.Name) then
			item:Clone().Parent = owned
			count += 1
		end
	end
	H.notify("Unlocked " .. count .. " blueprints for this session.")
end

function H.axeDupe()
	if F.dupeCooldown then
		H.notify("Axe dupe is on cooldown.")
		return
	end
	local slotLabel = H.find(LocalPlayer, "PlayerGui", "LoadSaveGUI", "SlotInfo", "Main", "SlotName")
	local slot = slotLabel and tonumber(slotLabel.Text:match("%d+"))
	local request = H.remote("LoadSaveRequests", "RequestLoad")
	if not slot or not request then
		H.notify("Load a save slot first.")
		return
	end
	F.dupeCooldown = true
	H.notify("Duping on slot " .. slot .. "...")

	local humanoid = H.humanoid()
	if humanoid then humanoid:UnequipTools() end
	local root = H.root()
	if root then root.CFrame = CFrame.new(0, -390, 0) end
	task.wait(0.33)

	if not LocalPlayer.Character or not LocalPlayer.Character.Parent then
		LocalPlayer.CharacterAdded:Wait()
	end
	local backpack = LocalPlayer:WaitForChild("Backpack", 10)
	local deadline = os.clock() + 10
	while backpack and not backpack:FindFirstChildWhichIsA("Tool") and os.clock() < deadline do
		task.wait(0.1)
	end

	pcall(function() request:InvokeServer(slot, LocalPlayer) end)

	H.spawn(function()
		local remaining = 60
		while remaining > 0 and alive() do
			if U.dupeLabel then pcall(function() U.dupeLabel:Set("Cooldown: " .. remaining .. "s") end) end
			task.wait(1)
			remaining -= 1
		end
		F.dupeCooldown = false
		if U.dupeLabel then pcall(function() U.dupeLabel:Set("Ready") end) end
		if alive() then H.notify("Axe dupe ready.") end
	end)
end

function H.applyTime()
	if F.timeLock == "Day" then
		Lighting.ClockTime = 12
		local sun = Lighting:FindFirstChild("SunPos")
		if sun then sun.Value = 1 end
	elseif F.timeLock == "Night" then
		Lighting.ClockTime = 0
		local sun = Lighting:FindFirstChild("SunPos")
		if sun then sun.Value = -1 end
	end
end

S.originalFogEnd = Lighting.FogEnd
S.originalShadows = Lighting.GlobalShadows

H.track(Lighting:GetPropertyChangedSignal("ClockTime"):Connect(function()
	if alive() and F.timeLock ~= "Off" then
		local goal = F.timeLock == "Day" and 12 or 0
		if Lighting.ClockTime ~= goal then H.applyTime() end
	end
end))

H.track(Lighting:GetPropertyChangedSignal("FogEnd"):Connect(function()
	if alive() and F.noFog and Lighting.FogEnd < 100000 then Lighting.FogEnd = 100000 end
end))

H.track(UserInputService.InputBegan:Connect(function(input, processed)
	if processed or not alive() or not F.clickTeleport then return end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
	if not UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then return end
	local root = H.root()
	if root then
		local hit = LocalPlayer:GetMouse().Hit
		H.teleport(CFrame.new(hit.Position + Vector3.new(0, root.Size.Y + 1.5, 0)))
	end
end))

pcall(function()
	local virtualUser = game:GetService("VirtualUser")
	H.track(LocalPlayer.Idled:Connect(function()
		if not alive() or not F.antiAfk then return end
		virtualUser:CaptureController()
		virtualUser:ClickButton2(Vector2.new())
	end))
end)

if not shared.FacilityGuardState then
	shared.FacilityGuardState = { enabled = false }
	local guard = shared.FacilityGuardState
	if hookmetamethod and getnamecallmethod and newcclosure then
		local original
		original = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
			if guard.enabled then
				local method = getnamecallmethod()
				if method == "Kick" and self == LocalPlayer then return nil end
				if method == "FireServer" or method == "InvokeServer" then
					local name = tostring(self)
					if name == "Ban" or name == "AddLog" then return true end
				end
			end
			return original(self, ...)
		end))
	end
end
shared.FacilityGuardState.enabled = F.antiKick

H.scanTrees()

shared.FacilityCleanup = function()
	F.autoFarm, F.autoSell, F.manualCut, F.stopFarm = false, false, false, true
	F.timeLock, F.noFog, F.clickTeleport = "Off", false, false
	if shared.FacilityGuardState then shared.FacilityGuardState.enabled = false end
	for _, connection in ipairs(S.connections) do pcall(function() connection:Disconnect() end) end
	table.clear(S.connections)
	for _, thread in ipairs(S.threads) do
		if thread ~= coroutine.running() then pcall(task.cancel, thread) end
	end
	table.clear(S.threads)
	for _, instance in ipairs(S.instances) do pcall(function() instance:Destroy() end) end
	table.clear(S.instances)
	pcall(function()
		Lighting.FogEnd = S.originalFogEnd
		Lighting.GlobalShadows = S.originalShadows
	end)
	if Movement then pcall(function() Movement:Unload() end) end
	pcall(function() Library:Destroy() end)
end

local Window = Library:Window({
	Title = "Facility",
	Suffix = ".Sexility",
	Width = 720,
	Height = 600,
	MinWidth = 580,
	SectionTitleStyle = "border",
	MobileButton = true,
	TabStyle = "side",
})

function H.sub(tab, name, icon)
	if tab.SubTab then return tab:SubTab(name, icon) end
	return tab
end

U.Player = Window:Tab("Player", "user")
U.Farm = Window:Tab("Farm", "axe")
U.Land = Window:Tab("Land", "map")
U.World = Window:Tab("World", "sun")
U.Teleport = Window:Tab("Teleport", "navigation")
Window:TabDivider()
U.Settings = Window:Tab("Settings", "settings")

local move = U.Player:Section("Movement", 1)
if Movement then
	move:Toggle({ Text = "Walk Speed", Flag = "lt_walk_on", Default = false, Callback = function(v)
		F.walkOn = v
		Movement:WalkSpeed(v and F.walkValue or 16, "Humanoid")
	end })
	move:Slider({ Text = "Speed", Flag = "lt_walk_value", Min = 16, Max = 200, Default = F.walkValue, Callback = function(v)
		F.walkValue = v
		if F.walkOn then Movement:WalkSpeed(v, "Humanoid") end
	end })
	move:Toggle({ Text = "Jump Power", Flag = "lt_jump_on", Default = false, Callback = function(v)
		F.jumpOn = v
		Movement:JumpPower(v and F.jumpValue or 50, "Humanoid")
	end })
	move:Slider({ Text = "Power", Flag = "lt_jump_value", Min = 50, Max = 300, Default = F.jumpValue, Callback = function(v)
		F.jumpValue = v
		if F.jumpOn then Movement:JumpPower(v, "Humanoid") end
	end })
	move:Toggle({ Text = "Fly", Flag = "lt_fly", Default = false, Callback = function(v)
		Movement:Fly(v)
	end }):Keybind({ Default = "F", Flag = "lt_fly_key" })
	move:Slider({ Text = "Fly Speed", Flag = "lt_fly_speed", Min = 1, Max = 20, Default = 2, Decimals = 1, Callback = function(v)
		Movement:SetFlySpeed(v)
	end })
	move:Toggle({ Text = "Noclip", Flag = "lt_noclip", Default = false, Callback = function(v)
		Movement:Noclip(v)
	end })
	move:Toggle({ Text = "Infinite Jump", Flag = "lt_infjump", Default = false, Callback = function(v)
		Movement:InfiniteJump(v)
	end })
else
	move:Label("Movement module failed to load.")
end

local util = U.Player:Section("Utility", 2)
util:Toggle({ Text = "Click Teleport", Flag = "lt_click_tp", Default = false, Callback = function(v)
	F.clickTeleport = v
end })
util:Label("Hold Left Ctrl and click to teleport.")
util:Toggle({ Text = "Anti AFK", Flag = "lt_anti_afk", Default = true, Callback = function(v)
	F.antiAfk = v
end })
util:Toggle({ Text = "Block Kick And Logs", Flag = "lt_anti_kick", Default = true, Callback = function(v)
	F.antiKick = v
	if shared.FacilityGuardState then shared.FacilityGuardState.enabled = v end
end })

local items = U.Player:Section("Items", 2)
items:Button({ Text = "Axe Dupe", Callback = function() H.spawn(H.axeDupe) end })
U.dupeLabel = items:Label("Ready")
items:Label("Respawns you and reloads your slot, 60 s cooldown.")
items:Button({ Text = "Unlock Blueprints", Callback = H.unlockBlueprints })
items:Label("Client side, lasts until you leave.")

local treesSub = H.sub(U.Farm, "Trees", "axe")
local woodSub = H.sub(U.Farm, "Wood", "package")

local cutting = treesSub:Section("Cutting", 1)
U.treeDropdown = cutting:Dropdown({ Text = "Tree Type", Flag = "lt_tree", Options = S.treeClasses, Default = "Generic",
	Callback = function(v)
		if type(v) == "table" then v = v[1] end
		F.tree = tostring(v or "Generic")
	end })
cutting:Slider({ Text = "Trees Per Cycle", Flag = "lt_amount", Min = 1, Max = 50, Default = 1, Callback = function(v)
	F.amount = v
end })
cutting:Button({ Text = "Cut Trees", Callback = H.manualCut })
cutting:Label("Press again to stop.")
cutting:Button({ Text = "Refresh Tree List", Callback = function()
	local list = H.scanTrees()
	if U.treeDropdown and U.treeDropdown.SetOptions then pcall(function() U.treeDropdown:SetOptions(list) end) end
	H.notify(#list .. " tree types found.")
end })

local farm = treesSub:Section("Auto Farm", 2)
U.autoFarm = farm:Toggle({ Text = "Auto Farm", Flag = "lt_auto_farm", Default = false, Callback = function(v)
	if v then
		if F.autoFarm then return end
		F.autoFarm, F.stopFarm, F.manualCut = true, false, false
		if F.autoSell then
			F.autoSell = false
			task.defer(function()
				if U.autoSell and U.autoSell.Set then pcall(function() U.autoSell:Set(false) end) end
			end)
		end
		H.notify("Auto farm started: " .. F.tree)
		H.spawn(H.farmLoop)
	elseif F.autoFarm then
		F.autoFarm, F.stopFarm = false, true
		H.notify("Auto farm stopped.")
	end
end })
farm:Label("Cuts the selected tree, brings it back and sells it, in a loop.")

local selling = woodSub:Section("Selling", 1)
selling:Button({ Text = "Sell All Wood", Callback = function()
	H.spawn(function()
		F.stopFarm = false
		local count = H.sellAll(false)
		H.notify(count > 0 and ("Sold " .. count .. " wood models.") or "You have no wood to sell.")
	end)
end })
U.autoSell = selling:Toggle({ Text = "Auto Sell", Flag = "lt_auto_sell", Default = false, Callback = function(v)
	if v then
		F.autoSell = true
		if F.autoFarm then
			F.autoFarm, F.stopFarm = false, true
			H.setFarmToggle(false)
		end
		H.startAutoSell()
	else
		F.autoSell = false
	end
end })

local handling = woodSub:Section("Handling", 2)
handling:Button({ Text = "Bring All Logs", Callback = function() H.spawn(H.bringLogs) end })
handling:Button({ Text = "Split All Wood", Callback = function() H.spawn(H.splitWood) end })

local plot = U.Land:Section("Plot", 1)
plot:Button({ Text = "Claim Free Plot", Callback = function() H.spawn(H.claimLand) end })
plot:Button({ Text = "Max Plot Size", Callback = function() H.spawn(H.expandLand) end })
plot:Button({ Text = "Teleport To My Plot", Callback = function()
	local mine = H.myProperty()
	local origin = mine and mine:FindFirstChild("OriginSquare")
	if origin then H.teleport(origin.CFrame + Vector3.new(0, 4, 0)) else H.notify("You do not own a plot.") end
end })

local lighting = U.World:Section("Lighting", 1)
lighting:Dropdown({ Text = "Time Lock", Flag = "lt_time", Options = { "Off", "Day", "Night" }, Default = "Off",
	Callback = function(v)
		F.timeLock = v
		H.applyTime()
	end })
lighting:Toggle({ Text = "No Fog", Flag = "lt_no_fog", Default = false, Callback = function(v)
	F.noFog = v
	Lighting.FogEnd = v and 100000 or S.originalFogEnd
end })
lighting:Toggle({ Text = "Shadows", Flag = "lt_shadows", Default = S.originalShadows, Callback = function(v)
	Lighting.GlobalShadows = v
end })

local places = U.Teleport:Section("Locations", 1)
local names = {}
for _, entry in ipairs(LOCATIONS) do table.insert(names, entry[1]) end
places:Dropdown({ Text = "Location", Flag = "lt_location", Options = names, Default = names[1], Callback = function(v)
	F.location = v
end })
places:Button({ Text = "Teleport", Callback = function()
	for _, entry in ipairs(LOCATIONS) do
		if entry[1] == F.location then
			if H.teleport(entry[2]) then H.notify("Teleported to " .. entry[1] .. ".", 2) end
			return
		end
	end
end })

local SaveManager = Library.SaveManager
local InterfaceManager = Library.InterfaceManager
local ThemeManager = Library.ThemeManager

SaveManager:SetLibrary(Library)
InterfaceManager:SetLibrary(Library)
InterfaceManager:SetWindow(Window)
ThemeManager:SetLibrary(Library)

SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({ "lt_auto_farm" })
InterfaceManager:SetFolder("Facility")
ThemeManager:SetFolder("Facility")
SaveManager:SetFolder("Facility/13822889")

InterfaceManager:BuildInterfaceSection(U.Settings, 1)
SaveManager:BuildConfigSection(U.Settings, 2)
ThemeManager:Mount(Window)

Window:SetTab(U.Farm)

if #moduleErrors > 0 then
	task.delay(1, function()
		for _, message in ipairs(moduleErrors) do
			Library:Notify({ Title = "Facility", Text = message, Duration = 20, Style = "Error" })
		end
	end)
end

Library:Notify("Facility", "Lumber Tycoon 2 loaded.", 4)

SaveManager:LoadAutoloadConfig()
ThemeManager:Load()
