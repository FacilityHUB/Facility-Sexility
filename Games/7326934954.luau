--!nocheck
--!nolint UnknownGlobal

local FH      = shared.Facility
local Library = FH.Library
local Entity  = FH.Entity
local Esp     = FH.Esp

local SESSION = (shared.FacilitySession or 0) + 1
shared.FacilitySession = SESSION

local function alive()
	return shared.FacilitySession == SESSION
end

if shared.FacilityCleanup then
	pcall(shared.FacilityCleanup)
	shared.FacilityCleanup = nil
end

local HUB_BASE = FH.HubBase or "https://raw.githubusercontent.com/FacilityHUB/Facility-Sexility/refs/heads/main/"

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

FH.Movement = Movement

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local Lighting = game:GetService("Lighting")
local Terrain = workspace:FindFirstChildOfClass("Terrain")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local H = {}
local U = {}
local S = {
	connections = {}, drawings = {}, instances = {}, threads = {}, originals = {},
	firing = false, perf = {},
}

local F = {
	teamMode = "Team",

	autoEat = false, eatBelow = 150, hungerMax = 200, eatRange = 30,
	autoFuel = false, fuelEvery = 5, fuelOnlyItems = true,
	chopAura = false, chopRange = 100,
	bringGroup = "All", bringNames = {}, bringRadius = 10, bringDrag = true,
	bringSpot = "Around Me", bringSpread = 2, bringHeight = 3, treeEsp = true,

	playerEsp = false, itemEsp = false, itemEspRange = 300,
	itemEspGroups = { Fuel = true, Food = true, Other = false },
	itemColors = { Fuel = Color3.fromRGB(255, 170, 60), Food = Color3.fromRGB(120, 230, 120), Other = Color3.fromRGB(200, 200, 255) },
	fullbright = false, noFog = false,

	lowGraphics = false, noTextures = false, noEffects = false, noShadows = false, whiteScreen = false,
}

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

function H.track(connection)
	table.insert(S.connections, connection)
	return connection
end

function H.loop(interval, fn)
	local thread = task.spawn(function()
		while alive() do
			pcall(fn)
			task.wait(interval)
		end
	end)
	table.insert(S.threads, thread)
	return thread
end

function H.notify(title, text, duration)
	pcall(function() Library:Notify(title, tostring(text), duration or 3) end)
end

function H.root(character)
	character = character or LocalPlayer.Character
	if not character then return nil end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root then return root end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return humanoid and humanoid.RootPart or nil
end

function H.humanoid(character)
	character = character or LocalPlayer.Character
	return character and character:FindFirstChildOfClass("Humanoid") or nil
end

function H.aliveChar(character)
	local humanoid = H.humanoid(character)
	return humanoid ~= nil and humanoid.Health > 0
end

function H.enemy(player)
	if player == LocalPlayer then return false end
	if F.teamMode == "Off" then return true end
	if F.teamMode == "TeamColor" then
		if LocalPlayer.Neutral or player.Neutral then return true end
		return player.TeamColor ~= LocalPlayer.TeamColor
	end
	if LocalPlayer.Team == nil or player.Team == nil then return true end
	return player.Team ~= LocalPlayer.Team
end

function H.setTeamMode(mode)
	F.teamMode = mode
	pcall(function() Entity.Settings.TeamCheck = mode end)
	pcall(function() Esp.sharedSettings.teamCheck = mode end)
end

function H.guiParent()
	local ok, parent = pcall(function() return gethui and gethui() end)
	if ok and parent then return parent end
	return game:GetService("CoreGui")
end

function H.overlay()
	if S.gui and S.gui.Parent then return S.gui end

	local gui = Instance.new("ScreenGui")
	gui.Name = tostring(math.random(100000, 999999))
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = H.guiParent()

	S.gui = gui
	return gui
end

function H.drawing(kind, props)
	local ok, object = pcall(function() return Drawing.new(kind) end)
	if not ok or not object then return nil end
	for key, value in pairs(props or {}) do
		pcall(function() object[key] = value end)
	end
	table.insert(S.drawings, object)
	return object
end

function H.setProp(node, key, value)
	if not node then return end
	S.originals[node] = S.originals[node] or {}

	local ok, current = pcall(function() return node[key] end)
	if not ok then return end
	if S.originals[node][key] == nil then S.originals[node][key] = current end
	if current ~= value then pcall(function() node[key] = value end) end
end

function H.restoreProp(node, key)
	local saved = S.originals[node]
	if saved and saved[key] ~= nil then
		pcall(function() node[key] = saved[key] end)
		saved[key] = nil
	end
end

function H.restoreAll()
	for node, values in pairs(S.originals) do
		for key, value in pairs(values) do
			pcall(function() node[key] = value end)
		end
	end
	table.clear(S.originals)
end

function H.mouseDown()
	if type(mouse1press) == "function" then
		pcall(mouse1press)
		return
	end
	pcall(function() VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 0) end)
end

function H.mouseUp()
	if type(mouse1release) == "function" then
		pcall(mouse1release)
		return
	end
	pcall(function() VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 0) end)
end

function H.click()
	if type(mouse1click) == "function" then
		pcall(mouse1click)
		return
	end
	H.mouseDown()
	task.wait(0.02)
	H.mouseUp()
end

function H.fixCollision(character)
	character = character or LocalPlayer.Character
	if not character then return end
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
			pcall(function() part.CanCollide = true end)
		end
	end
end

H.track(UserInputService.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then S.firing = true end
end))

H.track(UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then S.firing = false end
end))

function H.remote(name)
	local events = ReplicatedStorage:FindFirstChild("RemoteEvents")
	local found = events and events:FindFirstChild(name)
	if found then return found end
	return ReplicatedStorage:FindFirstChild(name, true)
end

function H.itemsFolder()
	return workspace:FindFirstChild("Items")
end

function H.mainFire()
	local map = workspace:FindFirstChild("Map")
	local camp = map and map:FindFirstChild("Campground")
	return camp and camp:FindFirstChild("MainFire")
end

function H.query(root, selector, attribute)
	if not root then return {} end
	local ok, found = pcall(function() return root:QueryDescendants(selector) end)
	if ok and type(found) == "table" and #found > 0 then return found end
	local list = {}
	for index, item in ipairs(root:GetDescendants()) do
		if index % 2000 == 0 then task.wait() end
		if item:GetAttribute(attribute) ~= nil then table.insert(list, item) end
	end
	return list
end

function H.position(item)
	if not item then return nil end
	if item:IsA("Attachment") then return item.WorldPosition end
	if item:IsA("BasePart") then return item.Position end
	if item:IsA("Model") then
		local ok, pivot = pcall(item.GetPivot, item)
		if ok then return pivot.Position end
	end
	return nil
end

function H.moveItem(item, cframe)
	if item:IsA("Model") then
		pcall(item.PivotTo, item, cframe)
	elseif item:IsA("BasePart") then
		pcall(function() item.CFrame = cframe end)
	end
end

function H.drag(item, cframe)
	local start, stop = H.remote("RequestStartDraggingItem"), H.remote("StopDraggingItem")
	if start then pcall(function() start:FireServer(item) end) end
	H.moveItem(item, cframe)
	if stop then pcall(function() stop:FireServer(item) end) end
end

function H.foods()
	local list = {}
	local folder = H.itemsFolder()
	for _, item in ipairs(folder and folder:GetChildren() or {}) do
		if item:GetAttribute("RestoreHunger") then table.insert(list, item) end
	end
	return list
end

function H.closestFood()
	local hunger = LocalPlayer:GetAttribute("Hunger")
	local best, bestDistance = nil, F.eatRange
	for _, food in ipairs(H.foods()) do
		local handle = food:FindFirstChild("Handle") or food:FindFirstChildWhichIsA("BasePart")
		local refill = food:GetAttribute("RestoreHunger")
		local fits = not (hunger and refill) or hunger + refill <= F.hungerMax
		if handle and fits then
			local distance = LocalPlayer:DistanceFromCharacter(handle.Position)
			if distance and distance < bestDistance then best, bestDistance = food, distance end
		end
	end
	return best
end

H.loop(0.15, function()
	if not F.autoEat or not H.aliveChar() then return end
	local hunger = LocalPlayer:GetAttribute("Hunger")
	if hunger and hunger >= F.eatBelow then return end
	local remote = H.remote("RequestConsumeItem")
	local food = remote and H.closestFood()
	if food then task.spawn(function() pcall(function() remote:InvokeServer(food) end) end) end
end)

function H.fuels()
	return H.query(H.itemsFolder(), "[$BurnFuel]", "BurnFuel")
end

function H.feedFire()
	local fire = H.mainFire()
	if not fire then return 0 end
	local target = CFrame.new(fire:GetPivot().Position + Vector3.new(0, 2, 0))
	local count = 0
	for _, fuel in ipairs(H.fuels()) do
		if not alive() then break end
		if F.fuelOnlyItems and fuel.Parent ~= H.itemsFolder() then
			fuel = nil
		end
		if fuel then
			H.drag(fuel, target)
			count = count + 1
			if count % 10 == 0 then task.wait() end
		end
	end
	return count
end

S.fuelAt = 0
H.loop(0.5, function()
	if not F.autoFuel or os.clock() - S.fuelAt < F.fuelEvery then return end
	S.fuelAt = os.clock()
	H.feedFire()
end)

function H.toolOf(pattern)
	local character = LocalPlayer.Character
	for _, model in ipairs(character and character:GetChildren() or {}) do
		local name = model:IsA("Model") and model:GetAttribute("ToolName")
		if type(name) == "string" and string.find(name, pattern, 1, true) then
			local original = model:FindFirstChild("OriginalItem")
			return original and original.Value or nil
		end
	end
	return nil
end

function H.hasInventory(pattern)
	local inventory = LocalPlayer:FindFirstChild("Inventory")
	for _, tool in ipairs(inventory and inventory:GetChildren() or {}) do
		local name = tool:GetAttribute("ToolName")
		if type(name) == "string" and string.find(name, pattern, 1, true) then return true end
	end
	return false
end

function H.enemyHandler()
	if S.enemyHandler ~= nil then return S.enemyHandler or nil end
	local ok, module = H.gcall(function()
		local scripts = LocalPlayer:WaitForChild("PlayerScripts", 5)
		local client = scripts and scripts:WaitForChild("Client", 5)
		local handler = client and client:WaitForChild("EnemyHandler", 5)
		return handler and require(handler)
	end)
	S.enemyHandler = (ok and type(module) == "table") and module or false
	return S.enemyHandler or nil
end

S.trees = { list = {}, at = 0 }

function H.trees()
	if os.clock() - S.trees.at < 3 then return S.trees.list end
	S.trees.at = os.clock()
	S.trees.list = H.query(workspace, "[$Resource]", "Resource")
	return S.trees.list
end

function H.closestTree()
	local chainsaw = nil
	local best, bestDistance = nil, F.chopRange
	for _, tree in ipairs(H.trees()) do
		local trunk = tree.Parent and tree:FindFirstChild("Trunk")
		if trunk then
			local big = string.find(tree.Name, "Big", 1, true) ~= nil
			if big and chainsaw == nil then chainsaw = H.hasInventory("Chainsaw") end
			if not big or chainsaw then
				local distance = LocalPlayer:DistanceFromCharacter(trunk.Position)
				if distance and distance < bestDistance then best, bestDistance = tree, distance end
			end
		end
	end
	return best
end

H.loop(0.1, function()
	if not F.chopAura or not H.aliveChar() then return end
	local remote = H.remote("ToolDamageObject")
	local axe = H.toolOf("Axe") or H.toolOf("Chainsaw")
	local root = H.root()
	local handler = H.enemyHandler()
	if not (remote and axe and root and handler and type(handler.GetHitRegId) == "function") then return end

	local tree = H.closestTree()
	if not tree then return end
	local ok, id = H.gcall(handler.GetHitRegId)
	if not ok then return end
	task.spawn(function()
		pcall(function() remote:InvokeServer(tree, axe, id, root.CFrame, true) end)
	end)
end)

H.ITEM_GROUPS = { "All", "Fuel", "Food", "Other" }

function H.itemGroup(item)
	if item:GetAttribute("BurnFuel") ~= nil then return "Fuel" end
	if item:GetAttribute("RestoreHunger") ~= nil then return "Food" end
	return "Other"
end

function H.itemNames()
	local seen, names = {}, {}
	local folder = H.itemsFolder()
	for _, item in ipairs(folder and folder:GetChildren() or {}) do
		if not seen[item.Name] then
			seen[item.Name] = true
			table.insert(names, item.Name)
		end
	end
	table.sort(names)
	return names
end

H.BRING_SPOTS = { "Around Me", "Campfire", "Scrapper" }

function H.campground()
	local map = workspace:FindFirstChild("Map")
	return map and map:FindFirstChild("Campground")
end

function H.bringSpot()
	if F.bringSpot == "Campfire" then
		local fire = H.mainFire()
		return H.position(fire and (fire:FindFirstChild("Center") or fire))
	end
	if F.bringSpot == "Scrapper" then
		local camp = H.campground()
		return H.position(camp and camp:FindFirstChild("Scrapper"))
	end
	local root = H.root()
	return root and root.Position or nil
end

function H.bringItems()
	local center = H.bringSpot()
	local folder = H.itemsFolder()
	if not center then
		H.notify("Items", F.bringSpot .. " not found on this map.", 4)
		return 0
	end
	if not folder then return 0 end

	local picked = {}
	local named = next(F.bringNames) ~= nil
	for _, item in ipairs(folder:GetChildren()) do
		local groupOk = F.bringGroup == "All" or H.itemGroup(item) == F.bringGroup
		local nameOk = not named or F.bringNames[item.Name]
		if groupOk and nameOk then table.insert(picked, item) end
	end

	local aroundMe = F.bringSpot == "Around Me"
	local radius = aroundMe and F.bringRadius or F.bringSpread
	local lift = aroundMe and 0 or F.bringHeight
	local count = #picked

	for index, item in ipairs(picked) do
		if not alive() then break end
		local angle = ((index - 1) / math.max(count, 1)) * math.pi * 2
		local spot = center + Vector3.new(math.cos(angle) * radius, lift, math.sin(angle) * radius)
		if F.bringDrag then H.drag(item, CFrame.new(spot)) else H.moveItem(item, CFrame.new(spot)) end
		if index % 10 == 0 then task.wait() end
	end
	return count
end

S.treeEsp = {}

function H.treeHealth(tree)
	local health = tree:GetAttribute("Health")
	local value = tree:FindFirstChild("Health")
	if health == nil and value and value:IsA("ValueBase") then health = value.Value end
	if type(health) ~= "number" then return nil, nil end
	local maximum = tree:GetAttribute("MaxHealth")
	local maxValue = tree:FindFirstChild("MaxHealth")
	if maximum == nil and maxValue and maxValue:IsA("ValueBase") then maximum = maxValue.Value end
	if type(maximum) ~= "number" then
		S.treeMax = S.treeMax or setmetatable({}, { __mode = "k" })
		S.treeMax[tree] = math.max(S.treeMax[tree] or 0, health)
		maximum = S.treeMax[tree]
	end
	return health, maximum
end

function H.treeColor(ratio)
	if ratio > 0.5 then return Color3.new((1 - ratio) * 2, 1, 0) end
	return Color3.new(1, ratio * 2, 0)
end

function H.treeEspSync()
	local seen = {}
	if F.treeEsp and F.chopAura then
		local root = H.root()
		for _, tree in ipairs(H.trees()) do
			local trunk = tree.Parent and tree:FindFirstChild("Trunk")
			if root and trunk and (trunk.Position - root.Position).Magnitude <= F.chopRange + 20 then
				seen[trunk] = true
				if not S.treeEsp[trunk] then
					local options = {
						enabled = true,
						maxDistance = F.chopRange + 40,
						textColor = { Color3.new(1, 1, 1), 1 },
					}
					options.getText = function()
						local health, maximum = H.treeHealth(tree)
						if not health then return tree.Name end
						local ratio = maximum and maximum > 0 and math.clamp(health / maximum, 0, 1) or 1
						options.textColor[1] = H.treeColor(ratio)
						return string.format("%s  %d / %d", tree.Name, math.floor(health + 0.5), math.floor((maximum or health) + 0.5))
					end
					S.treeEsp[trunk] = true
					pcall(function() Esp:AddInstance(trunk, options) end)
				end
			end
		end
	end
	for trunk in pairs(S.treeEsp) do
		if not seen[trunk] then
			pcall(function() Esp:RemoveInstance(trunk) end)
			S.treeEsp[trunk] = nil
		end
	end
end

function H.treeEspClear()
	for trunk in pairs(S.treeEsp) do pcall(function() Esp:RemoveInstance(trunk) end) end
	table.clear(S.treeEsp)
end

H.loop(1, H.treeEspSync)

function H.lightingStep()
	if F.fullbright then
		H.setProp(Lighting, "Brightness", 2)
		H.setProp(Lighting, "ClockTime", 14)
		H.setProp(Lighting, "GlobalShadows", false)
		H.setProp(Lighting, "Ambient", Color3.fromRGB(178, 178, 178))
		H.setProp(Lighting, "OutdoorAmbient", Color3.fromRGB(178, 178, 178))
	else
		for _, key in ipairs({ "Brightness", "ClockTime", "Ambient", "OutdoorAmbient" }) do H.restoreProp(Lighting, key) end
		if not F.noShadows then H.restoreProp(Lighting, "GlobalShadows") end
	end
	if F.noFog then
		H.setProp(Lighting, "FogEnd", 1e6)
		local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
		if atmosphere then H.setProp(atmosphere, "Density", 0) end
	elseif not F.lowGraphics then
		H.restoreProp(Lighting, "FogEnd")
		local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
		if atmosphere then H.restoreProp(atmosphere, "Density") end
	end
end

H.loop(0.5, function()
	if F.fullbright or F.noFog then H.lightingStep() end
end)

S.itemEsp = {}

function H.itemEspSync()
	local folder = H.itemsFolder()
	local seen = {}
	if F.itemEsp and folder then
		for _, item in ipairs(folder:GetChildren()) do
			local group = H.itemGroup(item)
			local wanted = F.itemEspGroups[group]
			local part = item:IsA("BasePart") and item or (item:IsA("Model") and (item.PrimaryPart or item:FindFirstChildWhichIsA("BasePart")))
			if wanted and part then
				seen[part] = true
				if not S.itemEsp[part] then
					S.itemEsp[part] = true
					pcall(function()
						Esp:AddInstance(part, {
							enabled = true,
							maxDistance = F.itemEspRange,
							textColor = { F.itemColors[group], 1 },
							getText = function()
								local root = H.root()
								local distance = root and math.floor((part.Position - root.Position).Magnitude) or 0
								return item.Name .. " [" .. distance .. "]"
							end,
						})
					end)
				end
			end
		end
	end
	for part in pairs(S.itemEsp) do
		if not seen[part] then
			pcall(function() Esp:RemoveInstance(part) end)
			S.itemEsp[part] = nil
		end
	end
end

function H.itemEspClear()
	for part in pairs(S.itemEsp) do pcall(function() Esp:RemoveInstance(part) end) end
	table.clear(S.itemEsp)
end

H.loop(1, H.itemEspSync)

H.EFFECT_CLASSES = { "ParticleEmitter", "Trail", "Beam", "Smoke", "Fire", "Sparkles" }

function H.restoreKey(key, filter)
	for node, values in pairs(S.originals) do
		if values[key] ~= nil and (not filter or filter(node)) then
			pcall(function() node[key] = values[key] end)
			values[key] = nil
		end
	end
end

function H.isEffect(item)
	for _, class in ipairs(H.EFFECT_CLASSES) do
		if item:IsA(class) then return true end
	end
	return false
end

function H.perfItem(item)
	if F.noEffects and H.isEffect(item) then H.setProp(item, "Enabled", false) end
	if F.noTextures then
		if item:IsA("Decal") or item:IsA("Texture") then
			H.setProp(item, "Transparency", 1)
		elseif item:IsA("BasePart") and not item:IsA("Terrain") then
			H.setProp(item, "Material", Enum.Material.SmoothPlastic)
			H.setProp(item, "Reflectance", 0)
		elseif item:IsA("SurfaceAppearance") then
			H.setProp(item, "Parent", nil)
		end
	end
	if F.noShadows and item:IsA("BasePart") then H.setProp(item, "CastShadow", false) end
end

function H.perfWanted()
	return F.noEffects or F.noTextures or F.noShadows
end

function H.perfScan()
	S.perf.scan = (S.perf.scan or 0) + 1
	local token = S.perf.scan
	task.spawn(function()
		for index, item in ipairs(workspace:GetDescendants()) do
			if not alive() or token ~= S.perf.scan or not H.perfWanted() then return end
			if index % 400 == 0 then task.wait() end
			pcall(H.perfItem, item)
		end
	end)

	if H.perfWanted() and not S.perf.added then
		S.perf.added = H.track(workspace.DescendantAdded:Connect(function(item)
			if alive() and H.perfWanted() then
				task.defer(function() pcall(H.perfItem, item) end)
			end
		end))
	end
end

function H.setEffects(state)
	F.noEffects = state
	if state then
		for _, effect in ipairs(Lighting:GetChildren()) do
			if effect:IsA("PostEffect") then H.setProp(effect, "Enabled", false) end
		end
		H.perfScan()
	else
		H.restoreKey("Enabled", function(node) return typeof(node) == "Instance" end)
	end
end

function H.setTextures(state)
	F.noTextures = state
	if state then
		H.perfScan()
	else
		H.restoreKey("Transparency")
		H.restoreKey("Material")
		H.restoreKey("Reflectance")
		H.restoreKey("Parent")
	end
end

function H.setShadows(state)
	F.noShadows = state
	if state then
		H.setProp(Lighting, "GlobalShadows", false)
		H.perfScan()
	else
		H.restoreKey("CastShadow")
		H.restoreProp(Lighting, "GlobalShadows")
	end
end

function H.setLowGraphics(state)
	F.lowGraphics = state
	local rendering = nil
	pcall(function() rendering = settings().Rendering end)
	if state then
		if rendering then H.setProp(rendering, "QualityLevel", Enum.QualityLevel.Level01) end
		H.setProp(Lighting, "EnvironmentDiffuseScale", 0)
		H.setProp(Lighting, "EnvironmentSpecularScale", 0)
		H.setProp(Lighting, "FogEnd", 1e6)
		if Terrain then
			H.setProp(Terrain, "Decoration", false)
			H.setProp(Terrain, "WaterWaveSize", 0)
			H.setProp(Terrain, "WaterWaveSpeed", 0)
			H.setProp(Terrain, "WaterReflectance", 0)
		end
		local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
		if atmosphere then H.setProp(atmosphere, "Density", 0) end
	else
		if rendering then H.restoreProp(rendering, "QualityLevel") end
		H.restoreProp(Lighting, "EnvironmentDiffuseScale")
		H.restoreProp(Lighting, "EnvironmentSpecularScale")
		H.restoreProp(Lighting, "FogEnd")
		if Terrain then
			H.restoreProp(Terrain, "Decoration")
			H.restoreProp(Terrain, "WaterWaveSize")
			H.restoreProp(Terrain, "WaterWaveSpeed")
			H.restoreProp(Terrain, "WaterReflectance")
		end
		local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
		if atmosphere then H.restoreProp(atmosphere, "Density") end
	end
end

function H.setWhiteScreen(state)
	F.whiteScreen = state
	pcall(function() RunService:Set3dRenderingEnabled(not state) end)
end

function H.setFpsCap(value)
	if type(setfpscap) ~= "function" then
		H.notify("Fps Cap", "Your executor has no setfpscap.", 4)
		return
	end
	pcall(setfpscap, value)
end

S.fps = { frames = 0, at = os.clock(), value = 0 }

H.track(RunService.RenderStepped:Connect(function()
	S.fps.frames = S.fps.frames + 1
	local now = os.clock()
	if now - S.fps.at >= 1 then
		S.fps.value = math.floor(S.fps.frames / (now - S.fps.at) + 0.5)
		S.fps.frames, S.fps.at = 0, now
	end
end))

function H.memoryText()
	local ok, total = pcall(function() return game:GetService("Stats"):GetTotalMemoryUsageMb() end)
	return ok and string.format("%.0f MB", total) or "-"
end

function H.pingText()
	local ok, ping = pcall(LocalPlayer.GetNetworkPing, LocalPlayer)
	return ok and string.format("%.0f ms", ping * 1000) or "-"
end

shared.FacilityCleanup = function()
	F.autoEat, F.autoFuel, F.chopAura, F.fullbright, F.noFog = false, false, false, false, false
	pcall(H.itemEspClear)
	pcall(H.treeEspClear)
	if F.whiteScreen then pcall(H.setWhiteScreen, false) end
	pcall(H.restoreAll)

	for _, connection in ipairs(S.connections) do pcall(function() connection:Disconnect() end) end
	for _, thread in ipairs(S.threads) do pcall(task.cancel, thread) end
	for _, object in ipairs(S.drawings) do pcall(function() object:Remove() end) end
	for _, object in ipairs(S.instances) do pcall(function() object:Destroy() end) end
	if S.gui then pcall(function() S.gui:Destroy() end) end

	pcall(function() Esp:Unload() end)
	if Movement then pcall(function() Movement:Unload() end) end
	pcall(function() Library:Destroy() end)
end

for _, message in ipairs(moduleErrors) do
	warn("[Facility] " .. message)
end

H.setTeamMode("Team")
Esp.teamSettings.enemy.enabled = true
Esp.teamSettings.friendly.enabled = false

function H.T(section, text, flag, default, callback, hint)
	return section:Toggle({
		Text = text, Flag = flag, Default = default, Hint = hint,
		Callback = function(state) pcall(callback, state) end,
	})
end

function H.S(section, text, flag, min, max, default, decimals, callback, suffix)
	return section:Slider({
		Text = text, Flag = flag, Min = min, Max = max, Default = default, Decimals = decimals, Suffix = suffix,
		Callback = function(value) pcall(callback, tonumber(value) or default) end,
	})
end

function H.D(section, text, flag, options, default, callback)
	return section:Dropdown({
		Text = text, Flag = flag, Options = options, Default = default,
		Callback = function(value)
			if type(value) == "table" then value = value[1] end
			pcall(callback, value)
		end,
	})
end

function H.B(section, text, callback)
	return section:Button({ Text = text, Callback = function() task.spawn(function() pcall(callback) end) end })
end

local Window = Library:Window({
	Title             = "Facility",
	Suffix            = ".Sexility",
	Width             = 720,
	Height            = 600,
	MinWidth          = 580,
	SectionTitleStyle = "border",
	MobileButton      = true,
	TabStyle          = "side",
})

U.Farm     = Window:Tab("Farm", "axe")
U.ItemsT   = Window:Tab("Items", "package")
U.Visuals  = Window:Tab("Visuals", "eye")
U.PlayerT  = Window:Tab("Player", "user-round")
U.Perf     = Window:Tab("Performance", "gauge")
Window:TabDivider()
U.Settings = Window:Tab("Settings", "cog")

if #moduleErrors > 0 then
	U.failBox = U.Farm:Section("Modules", "full")
	for _, message in ipairs(moduleErrors) do
		U.failBox:Label(message, { Style = "dim" })
	end
end

function H.espEnsure()
	local want = F.playerEsp or F.itemEsp or (F.chopAura and F.treeEsp)
	local loaded = Esp._loaded == true
	if want and not loaded then
		local ok, err = pcall(function() Esp:Load(Entity) end)
		if not ok then Library:Error("Esp", tostring(err), 10) end
	elseif not want and loaded then
		pcall(function() Esp:Unload() end)
	end
	Esp.teamSettings.enemy.enabled = F.playerEsp
	Esp.teamSettings.friendly.enabled = F.playerEsp and (Library.Flags["nf_esp_allies"] == true)
end

U.eatBox = U.Farm:Section("Auto Eat", 1)
H.T(U.eatBox, "Enable", "nf_auto_eat", false, function(state) F.autoEat = state end, "eats the closest food when hungry")
H.S(U.eatBox, "Eat Below", "nf_eat_below", 10, 200, 150, 0, function(value) F.eatBelow = value end)
H.S(U.eatBox, "Food Range", "nf_eat_range", 5, 60, 30, 0, function(value) F.eatRange = value end, " studs")
U.eatBox:Label("Food is skipped when it would overfill you.", { Style = "dim" })

U.fuelBox = U.Farm:Section("Auto Fuel", 2)
H.T(U.fuelBox, "Enable", "nf_auto_fuel", false, function(state) F.autoFuel = state end, "drags every burnable item into the camp fire")
H.S(U.fuelBox, "Every", "nf_fuel_every", 1, 30, 5, 0, function(value) F.fuelEvery = value end, " s")
H.T(U.fuelBox, "Loose Items Only", "nf_fuel_items", true, function(state) F.fuelOnlyItems = state end, "ignores fuel still inside other objects")
H.B(U.fuelBox, "Feed Fire Now", function()
	local count = H.feedFire()
	H.notify("Fire", count .. " items thrown in.", 3)
end)

U.chopBox = U.Farm:Section("Chop Aura", 1)
H.T(U.chopBox, "Enable", "nf_chop", false, function(state)
	F.chopAura = state
	if state and not H.enemyHandler() then H.notify("Chop Aura", "Hit handler not found yet, it will retry.", 4) S.enemyHandler = nil end
	H.espEnsure()
	if not state then H.treeEspClear() end
end, "chops the closest tree while you hold an axe or chainsaw")
H.S(U.chopBox, "Range", "nf_chop_range", 10, 150, 100, 0, function(value) F.chopRange = value end, " studs")
H.T(U.chopBox, "Tree Health", "nf_tree_esp", true, function(state)
	F.treeEsp = state
	H.espEnsure()
	if not state then H.treeEspClear() end
end, "shows the health of trees in range while the aura is on")
U.chopBox:Label("Big trees need a chainsaw in your inventory.", { Style = "dim" })

U.bringBox = U.ItemsT:Section("Bring Items", 1)
H.D(U.bringBox, "Destination", "nf_bring_spot", H.BRING_SPOTS, "Around Me", function(value) F.bringSpot = value end)
H.D(U.bringBox, "Type", "nf_bring_group", H.ITEM_GROUPS, "All", function(value) F.bringGroup = value end)

U.bringNames = U.bringBox:Dropdown({
	Text = "Only These",
	Flag = "nf_bring_names",
	Options = { "-" },
	Default = {},
	Multi = true,
	Callback = function(selected)
		table.clear(F.bringNames)
		for _, name in ipairs(type(selected) == "table" and selected or {}) do
			if name ~= "-" then F.bringNames[name] = true end
		end
	end,
})

H.S(U.bringBox, "Ring Radius", "nf_bring_radius", 4, 30, 10, 0, function(value) F.bringRadius = value end, " studs")
H.S(U.bringBox, "Pile Spread", "nf_bring_spread", 0, 8, 2, 1, function(value) F.bringSpread = value end, " studs")
H.S(U.bringBox, "Drop Height", "nf_bring_height", 0, 10, 3, 1, function(value) F.bringHeight = value end, " studs")
U.bringBox:Label("Ring Radius is used around you, Pile Spread and Drop Height on the campfire and scrapper.", { Style = "dim" })
H.T(U.bringBox, "Use Drag", "nf_bring_drag", true, function(state) F.bringDrag = state end, "tells the server you carried them, so they stay")
H.B(U.bringBox, "Bring Now", function()
	local count = H.bringItems()
	H.notify("Items", count .. " items brought to you.", 3)
end)
H.B(U.bringBox, "Refresh Item List", function()
	local names = H.itemNames()
	pcall(function() U.bringNames:SetOptions(#names > 0 and names or { "-" }) end)
	H.notify("Items", #names .. " item types found.", 3)
end)
U.bringBox:Label("Leave Only These empty to bring every item of the chosen type.", { Style = "dim" })

task.spawn(function()
	task.wait(1)
	if not alive() then return end
	local names = H.itemNames()
	pcall(function() U.bringNames:SetOptions(#names > 0 and names or { "-" }) end)
end)

U.itemEspBox = U.ItemsT:Section("Item Esp", 2)
U.itemEspBox:Toggle({
	Text = "Enable",
	Flag = "nf_item_esp",
	Default = false,
	Callback = function(state)
		F.itemEsp = state
		H.espEnsure()
		if not state then H.itemEspClear() end
	end,
})
	:Keybind({ Default = "None", Flag = "nf_item_esp_key" })

U.itemEspBox:Toggle({ Text = "Fuel", Flag = "nf_item_esp_fuel", Default = true, Callback = function(state) F.itemEspGroups.Fuel = state H.itemEspClear() end })
	:ColorPicker({ Flag = "nf_item_color_fuel", Default = F.itemColors.Fuel, Callback = function(color) F.itemColors.Fuel = color H.itemEspClear() end })
U.itemEspBox:Toggle({ Text = "Food", Flag = "nf_item_esp_food", Default = true, Callback = function(state) F.itemEspGroups.Food = state H.itemEspClear() end })
	:ColorPicker({ Flag = "nf_item_color_food", Default = F.itemColors.Food, Callback = function(color) F.itemColors.Food = color H.itemEspClear() end })
U.itemEspBox:Toggle({ Text = "Other", Flag = "nf_item_esp_other", Default = false, Callback = function(state) F.itemEspGroups.Other = state H.itemEspClear() end })
	:ColorPicker({ Flag = "nf_item_color_other", Default = F.itemColors.Other, Callback = function(color) F.itemColors.Other = color H.itemEspClear() end })
H.S(U.itemEspBox, "Max Distance", "nf_item_esp_range", 50, 2000, 300, 0, function(value)
	F.itemEspRange = value
	H.itemEspClear()
end, " studs")

U.PLAYER_TEAMS = { "enemy", "friendly", "whitelist" }

function H.espSet(key, value)
	for _, name in ipairs(U.PLAYER_TEAMS) do
		local team = Esp.teamSettings[name]
		if team then team[key] = value end
	end
end


function H.espPair(key, color, alpha)
	Esp.teamSettings.enemy[key] = { color, alpha ~= nil and (1 - alpha) or 1 }
end

U.espBox = U.Visuals:Section("Player Esp", 1)

U.espBox:Toggle({
	Text = "Enable",
	Flag = "nf_esp_enable",
	Default = false,
	Callback = function(state)
		F.playerEsp = state
		H.espEnsure()
	end,
})
	:Keybind({ Default = "None", Flag = "nf_esp_enable_key" })

U.espBox:Toggle({
	Text = "Box",
	Flag = "nf_esp_box",
	Default = true,
	Callback = function(state) H.espSet("box", state) end,
})
	:ColorPicker({
		Flag = "nf_esp_box_color",
		Default = Color3.fromRGB(255, 255, 255),
		Callback = function(color, alpha)
			H.espPair("boxColor", color, alpha)
			H.espPair("box3dColor", color, alpha)
		end,
	})
	:Gear(function(panel)
		H.D(panel, "Style", "nf_esp_box_style", { "2D", "3D" }, "2D", function(value)
			H.espSet("box", value == "2D")
			H.espSet("box3d", value == "3D")
		end)
	end)

U.espBox:Toggle({
	Text = "Health Bar",
	Flag = "nf_esp_health_bar",
	Default = true,
	Callback = function(state) H.espSet("healthBar", state) end,
})
	:ColorPicker({ Flag = "nf_esp_health_healthy", Default = Color3.fromRGB(82, 197, 148), Callback = function(color) H.espSet("healthyColor", color) end })
	:ColorPicker({ Flag = "nf_esp_health_dying", Default = Color3.fromRGB(240, 90, 102), Callback = function(color) H.espSet("dyingColor", color) end })

U.espBox:Toggle({
	Text = "Skeleton",
	Flag = "nf_esp_skeleton",
	Default = false,
	Callback = function(state) H.espSet("skeleton", state) end,
})
	:ColorPicker({ Flag = "nf_esp_skeleton_color", Default = Color3.new(1, 1, 1), Callback = function(color, alpha) H.espPair("skeletonColor", color, alpha) end })

U.espBox:Toggle({
	Text = "Tracers",
	Flag = "nf_esp_tracer",
	Default = false,
	Callback = function(state) H.espSet("tracer", state) end,
})
	:ColorPicker({ Flag = "nf_esp_tracer_color", Default = Color3.new(1, 1, 1), Callback = function(color, alpha) H.espPair("tracerColor", color, alpha) end })
	:Gear(function(panel)
		H.D(panel, "Origin", "nf_esp_tracer_origin", { "Bottom", "Middle", "Top", "Mouse" }, "Bottom", function(value) H.espSet("tracerOrigin", value) end)
	end)

U.espBox:Toggle({
	Text = "Highlight",
	Flag = "nf_esp_chams",
	Default = false,
	Callback = function(state) H.espSet("chams", state) end,
})
	:ColorPicker({ Flag = "nf_esp_chams_color", Default = Color3.fromRGB(255, 60, 60), Callback = function(color, alpha) H.espPair("chamsFillColor", color, alpha) end })

U.espBox:Toggle({
	Text = "Off Screen Arrow",
	Flag = "nf_esp_arrow",
	Default = false,
	Callback = function(state) H.espSet("offScreenArrow", state) end,
})
	:ColorPicker({ Flag = "nf_esp_arrow_color", Default = Color3.new(1, 1, 1), Callback = function(color, alpha) H.espPair("offScreenArrowColor", color, alpha) end })

U.displayBox = U.Visuals:Section("Display", 2)

U.displayBox:Toggle({
	Text = "Name",
	Flag = "nf_esp_name",
	Default = true,
	Callback = function(state) H.espSet("name", state) end,
})
	:ColorPicker({ Flag = "nf_esp_name_color", Default = Color3.fromRGB(236, 241, 250), Callback = function(color, alpha) H.espPair("nameColor", color, alpha) end })

U.displayBox:Toggle({
	Text = "Distance",
	Flag = "nf_esp_distance",
	Default = true,
	Callback = function(state) H.espSet("distance", state) end,
})
	:ColorPicker({ Flag = "nf_esp_distance_color", Default = Color3.fromRGB(170, 184, 205), Callback = function(color, alpha) H.espPair("distanceColor", color, alpha) end })

U.displayBox:Toggle({
	Text = "Weapon",
	Flag = "nf_esp_weapon",
	Default = false,
	Callback = function(state) H.espSet("weapon", state) end,
})
	:ColorPicker({ Flag = "nf_esp_weapon_color", Default = Color3.fromRGB(255, 255, 255), Callback = function(color, alpha) H.espPair("weaponColor", color, alpha) end })

H.T(U.displayBox, "Health", "nf_esp_health_text", false, function(state) H.espSet("healthText", state) end)
H.T(U.displayBox, "Team Color", "nf_esp_team_color", false, function(state) Esp.sharedSettings.useTeamColor = state end)
H.S(U.displayBox, "Text Size", "nf_esp_text_size", 8, 24, 13, 0, function(value) Esp.sharedSettings.textSize = value end)
H.S(U.displayBox, "Max Distance", "nf_esp_max_distance", 100, 5000, 1500, 0, function(value) H.espSet("maxDistance", value) end, " studs")

U.displayBox:Toggle({
	Text = "Show Teammates",
	Flag = "nf_esp_allies",
	Default = false,
	Callback = function(state) Esp.teamSettings.friendly.enabled = state and F.playerEsp end,
})
	:ColorPicker({
		Flag = "nf_esp_ally_color",
		Default = Color3.fromRGB(60, 255, 120),
		Callback = function(color)
			Esp.teamSettings.friendly.boxColor = { color, 1 }
			Esp.teamSettings.friendly.nameColor = { color, 1 }
		end,
	})


U.worldBox = U.Visuals:Section("World", 2)
H.T(U.worldBox, "Fullbright", "nf_fullbright", false, function(state)
	F.fullbright = state
	H.lightingStep()
end, "see clearly during the night")
H.T(U.worldBox, "No Fog", "nf_no_fog", false, function(state)
	F.noFog = state
	H.lightingStep()
end)

U.moveBox = U.PlayerT:Section("Movement", 1)

if Movement then

Movement.Settings.JumpMode = "Humanoid"

U.moveBox:Toggle({
	Text = "Fly",
	Flag = "nf_fly",
	Default = false,
	Callback = function(state) Movement:Fly(state) end,
})
	:Keybind({ Default = "None", Flag = "nf_fly_key" })
	:Gear(function(panel)
		H.S(panel, "Speed", "nf_fly_speed", 1, 20, 2, 1, function(value) Movement.Settings.FlySpeed = value end)
	end)

U.moveBox:Toggle({
	Text = "Jump Power",
	Flag = "nf_jump",
	Default = false,
	Callback = function(state) Movement:JumpPower(state and Movement.Settings.JumpPower or 50) end,
})
	:Gear(function(panel)
		H.S(panel, "Power", "nf_jump_value", 30, 300, 80, 0, function(value)
			Movement.Settings.JumpPower = value
			if Library.Flags["nf_jump"] then Movement:JumpPower(value) end
		end)
	end)

H.T(U.moveBox, "Infinite Jump", "nf_inf_jump", false, function(state) Movement:InfiniteJump(state) end)

U.moveBox:Toggle({
	Text = "Noclip",
	Flag = "nf_noclip",
	Default = false,
	Callback = function(state)
		Movement:Noclip(state)
		if not state then H.fixCollision() end
	end,
})
	:Keybind({ Default = "None", Flag = "nf_noclip_key" })

end

U.walkBox = U.PlayerT:Section("Walk Speed", 2)

U.walkBox:Toggle({
	Text = "Walk Speed",
	Flag = "nf_walk",
	Default = false,
	Callback = function(state)
		if Movement then Movement:WalkSpeed(state and (Library.Flags["nf_walk_value"] or 30) or 16, "Humanoid") end
	end,
})
	:Keybind({ Default = "None", Flag = "nf_walk_key" })

H.S(U.walkBox, "Speed", "nf_walk_value", 16, 120, 30, 0, function(value)
	if Movement and Library.Flags["nf_walk"] then Movement:WalkSpeed(value, "Humanoid") end
end)

U.gfxBox = U.Perf:Section("Graphics", 1)
H.T(U.gfxBox, "Low Graphics", "nf_low_gfx", false, function(state) H.setLowGraphics(state) end, "lowest quality level, no water waves, grass or fog")
H.T(U.gfxBox, "Remove Effects", "nf_no_effects", false, function(state) H.setEffects(state) end, "particles, trails, beams and post effects")
H.T(U.gfxBox, "Plain Textures", "nf_no_textures", false, function(state) H.setTextures(state) end, "flat materials, hides decals and textures")
H.T(U.gfxBox, "No Shadows", "nf_no_shadows", false, function(state) H.setShadows(state) end)
U.gfxBox:Label("Every option above is undone when you turn it off.", { Style = "dim" })

U.fpsBox = U.Perf:Section("Frame Rate", 2)
U.fpsBox:Toggle({
	Text = "Fps Cap",
	Flag = "nf_fps_cap",
	Default = false,
	Callback = function(state) H.setFpsCap(state and (Library.Flags["nf_fps_value"] or 240) or 60) end,
})
H.S(U.fpsBox, "Max Fps", "nf_fps_value", 30, 999, 240, 0, function(value)
	if Library.Flags["nf_fps_cap"] then H.setFpsCap(value) end
end)
U.fpsBox:Label("999 removes the limit. Off goes back to 60.", { Style = "dim" })

U.fpsBox:Toggle({
	Text = "White Screen",
	Flag = "nf_white_screen",
	Default = false,
	Hint = "stops 3D rendering, for farming in the background",
	Callback = function(state) H.setWhiteScreen(state) end,
})
	:Keybind({ Default = "None", Flag = "nf_white_screen_key" })

U.statBox = U.Perf:Section("Live Stats", 2)
U.statText = U.statBox:Paragraph({ Title = "Session", Content = "loading..." })
H.loop(1, function()
	pcall(function()
		U.statText:Set({ Title = "Session", Content = "Fps: " .. S.fps.value .. "\nPing: " .. H.pingText() .. "\nMemory: " .. H.memoryText() })
	end)
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
SaveManager:SetFolder("Facility/7326934954")

InterfaceManager:BuildInterfaceSection(U.Settings, 1)
SaveManager:BuildConfigSection(U.Settings, 2)
ThemeManager:Mount(Window)

Window:SetTab(U.Farm)

if #moduleErrors > 0 then
	task.delay(1, function()
		for _, message in ipairs(moduleErrors) do Library:Error("Facility", message, 20) end
	end)
end

Library:Notify("Facility", "99 Nights loaded.", 4)

SaveManager:LoadAutoloadConfig()
ThemeManager:Load()

