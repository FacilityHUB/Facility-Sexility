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

local Aimbot = fetchModule("CModules/FAimbot.luau", "aimbot")
local Movement = fetchModule("CModules/FMovement.luau", "movement")

if Movement then pcall(function() Movement:Load() end) end

FH.Aimbot = Aimbot
FH.Movement = Movement

local function service(name)
	local found = game:GetService(name)
	if type(cloneref) == "function" then
		local ok, wrapped = pcall(cloneref, found)
		if ok and wrapped then return wrapped end
	end
	return found
end

local Players = service("Players")
local ReplicatedStorage = service("ReplicatedStorage")
local RunService = service("RunService")
local UserInputService = service("UserInputService")
local VirtualInputManager = service("VirtualInputManager")
local VirtualUser = service("VirtualUser")
local Lighting = service("Lighting")
local HttpService = service("HttpService")
local TeleportService = service("TeleportService")

local LocalPlayer = Players.LocalPlayer

local H = {}
local U = {}
local S = {
	connections = {}, drawings = {}, instances = {}, threads = {}, originals = {},
	lib = {}, binders = {}, infoBackup = setmetatable({}, { __mode = "k" }), soundHooks = {}, rings = {},
	trigger = { holding = false, tap = 0, seen = 0 }, rage = { target = nil, part = nil, holding = false },
	silent = { model = nil, part = nil }, flagged = {}, firing = false,
}

local F = {
	teamCheck = true,

	silent = false, silentFov = 160, silentShowFov = false, silentFovColor = Color3.fromRGB(120, 170, 255),
	silentPart = "Head", silentHit = 100, silentHead = 100, silentVisible = true, silentFiring = false,

	trigger = false, triggerTeam = true, triggerDelay = 0, triggerMode = "Crosshair", triggerFov = 0,

	rage = false, rageVisible = true, rageRange = 1500, rageFire = true,

	noSpread = false, recoil = false, recoilPct = 0, fireRate = false, fireRatePct = 50, autoFire = false,
	aimSpeed = false, aimSpeedPct = 200, melee = false, meleePct = 50, dash = false, dashPct = 50,

	soundEsp = false, soundEnemiesOnly = true, soundColor = Color3.fromRGB(255, 200, 80), soundLife = 1.5,
	camFov = false, camFovValue = 90,
	fullbright = false, noFog = false, clockTime = false, clockValue = 14,

	cosmetics = false,
	autoRespawn = false, antiAfk = false, modNotify = true, modLeave = false,
}

H.MOD_GROUP = 3461453
H.MOD_RANK = 100
H.SAVE_FOLDER = "Facility/6035872082"
H.COSMETIC_FILE = H.SAVE_FOLDER .. "/cosmetics.json"
H.SLOTS = { "Skin", "Wrap", "Charm", "Finisher" }

function H.clone(fn)
	if type(clonefunction) == "function" and type(fn) == "function" then
		local ok, copy = pcall(clonefunction, fn)
		if ok and copy then return copy end
	end
	return fn
end

H.fireServer = H.clone(Instance.new("RemoteEvent").FireServer)
H.fireUnreliable = H.clone(Instance.new("UnreliableRemoteEvent").FireServer)

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

function H.roll(percent)
	return percent >= 100 or math.random() * 100 < percent
end

function H.decode(raw)
	if type(raw) ~= "string" then return nil end
	local ok, value = pcall(HttpService.JSONDecode, HttpService, raw)
	return ok and value or nil
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

function H.guiParent()
	local ok, parent = pcall(function() return gethui and gethui() end)
	if ok and parent then return parent end
	return service("CoreGui")
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

function H.require(module)
	if typeof(module) ~= "Instance" or not module:IsA("ModuleScript") then return nil end
	local ok, result = pcall(require, module)
	if ok then return result end

	local done, okAgain, again = false, false, nil
	task.spawn(function()
		pcall(setthreadidentity, 2)
		okAgain, again = pcall(require, module)
		done = true
	end)
	local deadline = os.clock() + 5
	while not done and os.clock() < deadline do task.wait() end
	return okAgain and again or nil
end

function H.path(root, ...)
	local node = root
	for _, name in ipairs({ ... }) do
		if not node then return nil end
		node = node:FindFirstChild(name) or node:WaitForChild(name, 5)
	end
	return node
end

function H.loadGame()
	local scripts = LocalPlayer:WaitForChild("PlayerScripts", 10)
	local controllers = H.path(scripts, "Controllers")
	local clientModules = H.path(scripts, "Modules")
	local sharedModules = H.path(ReplicatedStorage, "Modules")
	local classes = H.path(clientModules, "ClientReplicatedClasses")

	local wanted = {
		{ "Fighter", controllers, { "FighterController" } },
		{ "Camera", controllers, { "CameraController" } },
		{ "PlayerData", controllers, { "PlayerDataController" } },
		{ "ClientItem", classes, { "ClientFighter", "ClientItem" } },
		{ "Enum", sharedModules, { "EnumLibrary" } },
		{ "Cosmetics", sharedModules, { "CosmeticLibrary" } },
		{ "Items", sharedModules, { "ItemLibrary" } },
		{ "DataUtility", sharedModules, { "PlayerDataUtility" } },
	}

	for _, entry in ipairs(wanted) do
		local module = H.require(H.path(entry[2], table.unpack(entry[3])))
		if module ~= nil then
			S.lib[entry[1]] = module
		else
			table.insert(moduleErrors, "game module " .. entry[3][#entry[3]] .. " unavailable")
		end
	end

	local remotes = H.path(ReplicatedStorage, "Remotes")
	S.remotes = {
		root = remotes,
		replication = H.path(remotes, "Replication"),
		fighter = H.path(remotes, "Replication", "Fighter"),
		useItem = H.path(remotes, "Replication", "Fighter", "UseItem"),
		respawn = H.path(remotes, "Duels", "RespawnNow"),
	}
end

H.loadGame()

function H.encode(name)
	local enum = S.lib.Enum
	local map = type(enum) == "table" and rawget(enum, "_to_enum")
	return type(map) == "table" and rawget(map, name) or nil
end

function H.decodeEnum(value)
	local enum = S.lib.Enum
	local map = type(enum) == "table" and rawget(enum, "_from_enum")
	return type(map) == "table" and rawget(map, value) or nil
end

function H.encodeCFrame(cframe)
	local rx, ry, rz = cframe:ToOrientation()
	return { ["\0"] = cframe.X, ["\1"] = cframe.Y, ["\2"] = cframe.Z, ["\3"] = rx, ["\4"] = ry, ["\5"] = rz }
end

function H.decodeCFrame(data)
	if type(data) ~= "table" then return nil end
	local values = { data["\0"], data["\1"], data["\2"], data["\3"], data["\4"], data["\5"] }
	for index = 1, 6 do
		if type(values[index]) ~= "number" then return nil end
	end
	return CFrame.new(values[1], values[2], values[3]) * CFrame.fromOrientation(values[4], values[5], values[6])
end

function H.localFighter()
	local controller = S.lib.Fighter
	local map = type(controller) == "table" and rawget(controller, "_player_to_fighter")
	return type(map) == "table" and map[LocalPlayer] or nil
end

function H.fighterItems()
	local fighter = H.localFighter()
	local items = fighter and rawget(fighter, "Items")
	return type(items) == "table" and items or {}
end

function H.itemByObjectId(objectId)
	for _, item in pairs(H.fighterItems()) do
		local data = type(item) == "table" and rawget(item, "Data")
		if type(data) == "table" and rawget(data, "ObjectID") == objectId then return item end
	end
	return nil
end

function H.itemType(item)
	local info = type(item) == "table" and rawget(item, "Info")
	return type(info) == "table" and rawget(info, "Type") or nil
end

function H.equippedGun()
	local fighter = H.localFighter()
	local item = fighter and rawget(fighter, "EquippedItem")
	return item and H.itemType(item) == "Gun" and item or nil
end

function H.enemy(player)
	if player == LocalPlayer then return false end
	if not F.teamCheck then return true end
	local myEnv, theirEnv = LocalPlayer:GetAttribute("EnvironmentID"), player:GetAttribute("EnvironmentID")
	if myEnv == nil or theirEnv ~= myEnv then return false end
	local myTeam = LocalPlayer:GetAttribute("TeamID")
	return myTeam == nil or player:GetAttribute("TeamID") ~= myTeam
end

S.entityOriginal = rawget(Entity, "IsTargetable")
Entity.IsTargetable = function(self, player)
	if not alive() then
		if type(S.entityOriginal) == "function" then return S.entityOriginal(self, player) end
		return true
	end
	return H.enemy(player)
end

H.loop(0.5, function()
	pcall(function() Entity:RefreshTargets() end)
end)

function H.targets(teamCheck)
	local list = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if player ~= LocalPlayer and character and character:FindFirstChild("Head") and H.aliveChar(character) then
			if not teamCheck or H.enemy(player) then table.insert(list, { model = character, player = player }) end
		end
	end
	return list
end

S.rayParams = RaycastParams.new()
S.rayParams.FilterType = Enum.RaycastFilterType.Exclude

function H.visible(model, part)
	local camera = workspace.CurrentCamera
	if not camera then return false end
	S.rayParams.FilterDescendantsInstances = { LocalPlayer.Character, camera, model }
	local origin = camera.CFrame.Position
	return workspace:Raycast(origin, part.Position - origin, S.rayParams) == nil
end

H.PART_SETS = {
	Head = { "Head" },
	Torso = { "UpperTorso", "Torso", "HumanoidRootPart" },
	Random = { "Head", "UpperTorso", "Torso", "HumanoidRootPart" },
}

function H.pickPart(model, mode)
	if mode == "Random" then
		local set = H.PART_SETS.Random
		local part = model:FindFirstChild(set[math.random(1, #set)])
		if part and part:IsA("BasePart") then return part end
	end
	for _, name in ipairs(H.PART_SETS[mode] or H.PART_SETS.Head) do
		local part = model:FindFirstChild(name)
		if part and part:IsA("BasePart") then return part end
	end
	return model:FindFirstChild("HumanoidRootPart")
end

function H.same(a, b)
	if type(compareinstances) == "function" then
		local ok, result = pcall(compareinstances, a, b)
		if ok then return result end
	end
	return a == b
end

function H.childOf(instance)
	return function(_, key)
		local ok, value = pcall(function() return instance[key] end)
		return ok and value or nil
	end
end

function H.onUseItem(objectId, kind, args, ...)
	if alive() then pcall(H.dispatchShot, objectId, kind, args) end
	return H.fireServer(S.remotes.useItem, objectId, kind, args, ...)
end

function H.installInputHook()
	if S.inputHook then return true end
	local class = S.lib.ClientItem
	local input = type(class) == "table" and rawget(class, "Input")
	if type(input) ~= "function" then return false, "ClientItem.Input not found" end
	if not (S.remotes.useItem and S.remotes.fighter and S.remotes.replication and S.remotes.root) then return false, "UseItem remote not found" end

	local reader = (debug and debug.getupvalues) or getupvalues
	if type(reader) ~= "function" then return false, "debug.getupvalues unavailable" end
	local ok, values = pcall(reader, input)
	if not ok or type(values) ~= "table" then return false, "upvalue read failed" end

	local realStorage = game:GetService("ReplicatedStorage")
	for _, holder in pairs(values) do
		if type(holder) == "table" then
			for key, entry in pairs(holder) do
				if typeof(entry) == "Instance" and H.same(entry, realStorage) then
					local fakeUse = {
						FireServer = function(_, objectId, kind, args, ...)
							return H.onUseItem(objectId, kind, args, ...)
						end,
					}
					local fakeFighter = setmetatable({ UseItem = fakeUse }, { __index = H.childOf(S.remotes.fighter) })
					local fakeReplication = setmetatable({ Fighter = fakeFighter }, { __index = H.childOf(S.remotes.replication) })
					local fakeRemotes = setmetatable({ Replication = fakeReplication }, { __index = H.childOf(S.remotes.root) })
					local fakeStorage = setmetatable({ Remotes = fakeRemotes }, { __index = H.childOf(entry) })

					holder[key] = fakeStorage
					S.inputHook = { holder = holder, key = key, original = entry }
					return true
				end
			end
		end
	end

	return false, "ReplicatedStorage upvalue not found"
end

function H.removeInputHook()
	local hook = S.inputHook
	if hook then pcall(function() hook.holder[hook.key] = hook.original end) end
	S.inputHook = nil
end

function H.needInputHook(label)
	local ok, err = H.installInputHook()
	if not ok then H.notify(label, "Shot hook unavailable: " .. tostring(err), 6) end
	return ok
end

function H.localHit(origin, part, point)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { part }
	local hit = workspace:Raycast(origin, (point - origin) * 1.02, params)
	if not hit then return nil end
	local offset = part.CFrame:PointToObjectSpace(hit.Position)
	if offset == Vector3.zero then return nil end
	return offset
end

function H.shotTarget()
	if F.rage and S.rage.part and S.rage.part.Parent then return S.rage.part end
	if not F.silent or not S.silent.part or not S.silent.part.Parent then return nil end
	if F.silentFiring and not S.firing then return nil end
	if not H.roll(F.silentHit) then return nil end
	if F.silentPart == "Head" and F.silentHead < 100 and not H.roll(F.silentHead) then
		local body = H.pickPart(S.silent.model, "Torso")
		if body then return body end
	end
	return S.silent.part
end

function H.dispatchShot(objectId, kind, args)
	if H.decodeEnum(kind) ~= "StartShooting" or type(args) ~= "table" then return end
	local item = H.itemByObjectId(objectId)
	if not item or H.itemType(item) ~= "Gun" then return end

	if F.noSpread then args["\2"] = true end

	local part = H.shotTarget()
	local shot = args["\1"]
	if not part or type(shot) ~= "table" then return end

	local origin = H.decodeCFrame(shot["\0"])
	local view = H.decodeCFrame(shot["\1"])
	if not (origin and view) then return end

	local point = part.Position
	local offset = H.localHit(origin.Position, part, point)
	if not offset then return end

	shot["\0"] = H.encodeCFrame(CFrame.lookAt(origin.Position, point))
	shot["\1"] = H.encodeCFrame(CFrame.lookAt(view.Position, point))
	shot["\2"] = part
	shot["\3"] = H.encodeCFrame(CFrame.new(offset))
end

function H.silentPick()
	local camera = workspace.CurrentCamera
	if not camera then return nil end
	local mouse = UserInputService:GetMouseLocation()
	local best, bestPart, bestDistance = nil, nil, F.silentFov

	for _, target in ipairs(H.targets(true)) do
		local part = H.pickPart(target.model, F.silentPart == "Random" and "Head" or F.silentPart)
		if part then
			local screen, onScreen = camera:WorldToViewportPoint(part.Position)
			if onScreen and screen.Z > 0 then
				local distance = (Vector2.new(screen.X, screen.Y) - mouse).Magnitude
				if distance < bestDistance and (not F.silentVisible or H.visible(target.model, part)) then
					best, bestPart, bestDistance = target.model, part, distance
				end
			end
		end
	end

	if best and F.silentPart == "Random" then bestPart = H.pickPart(best, "Random") or bestPart end
	return best, bestPart
end

function H.ragePick()
	local camera = workspace.CurrentCamera
	if not camera then return nil end
	local origin = camera.CFrame.Position
	local best, bestPart, bestDistance = nil, nil, F.rageRange

	for _, target in ipairs(H.targets(true)) do
		local part = H.pickPart(target.model, "Head")
		if part then
			local distance = (part.Position - origin).Magnitude
			if distance < bestDistance and (not F.rageVisible or H.visible(target.model, part)) then
				best, bestPart, bestDistance = target.model, part, distance
			end
		end
	end

	return best, bestPart
end

function H.rageRelease()
	if S.rage.holding then
		H.mouseUp()
		S.rage.holding = false
	end
end

H.track(RunService.RenderStepped:Connect(function()
	if not alive() then return end

	if F.silent and H.aliveChar() then
		local ok, model, part = pcall(H.silentPick)
		S.silent.model, S.silent.part = ok and model or nil, ok and part or nil
	else
		S.silent.model, S.silent.part = nil, nil
	end

	if F.rage and H.aliveChar() and H.equippedGun() then
		local ok, model, part = pcall(H.ragePick)
		S.rage.target, S.rage.part = ok and model or nil, ok and part or nil
		if S.rage.target and F.rageFire then
			if not S.rage.holding then
				H.mouseDown()
				S.rage.holding = true
			end
		else
			H.rageRelease()
		end
	else
		S.rage.target, S.rage.part = nil, nil
		H.rageRelease()
	end
end))

U.silentCircle = H.drawing("Circle", {
	Visible = false, Color = F.silentFovColor, Filled = false, Thickness = 1.5, NumSides = 64, Transparency = 1,
})

H.track(RunService.RenderStepped:Connect(function()
	if not U.silentCircle then return end
	local show = F.silent and F.silentShowFov
	U.silentCircle.Visible = show
	if show then
		U.silentCircle.Position = UserInputService:GetMouseLocation()
		U.silentCircle.Radius = F.silentFov
		U.silentCircle.Color = F.silentFovColor
	end
end))

function H.triggerValid(model, player)
	if not model or not H.aliveChar(model) or not player or player == LocalPlayer then return nil end
	if F.triggerTeam and not H.enemy(player) then return nil end
	return model
end

function H.triggerTarget()
	local camera = workspace.CurrentCamera
	if not camera then return nil end

	if F.triggerMode == "Target" then
		local target = Aimbot and Aimbot.Target
		local player = nil
		if typeof(target) == "Instance" and target:IsA("Player") then player = target end
		if type(target) == "table" and typeof(target.Player) == "Instance" then player = target.Player end
		return player and H.triggerValid(player.Character, player) or nil
	end

	if F.triggerMode == "Fov" then
		local center = camera.ViewportSize / 2
		local best, bestDistance = nil, F.triggerFov > 0 and F.triggerFov or 12
		for _, target in ipairs(H.targets(F.triggerTeam)) do
			local part = target.model:FindFirstChild("Head") or H.root(target.model)
			if part then
				local point, onScreen = camera:WorldToViewportPoint(part.Position)
				if onScreen and point.Z > 0 then
					local distance = (Vector2.new(point.X, point.Y) - center).Magnitude
					if distance <= bestDistance and H.visible(target.model, part) then
						best, bestDistance = target.model, distance
					end
				end
			end
		end
		return best
	end

	S.rayParams.FilterDescendantsInstances = { LocalPlayer.Character, camera }
	local hit = workspace:Raycast(camera.CFrame.Position, camera.CFrame.LookVector * 2000, S.rayParams)
	if not hit then return nil end
	local model = hit.Instance:FindFirstAncestorOfClass("Model")
	while model and not model:FindFirstChildOfClass("Humanoid") do
		model = model:FindFirstAncestorOfClass("Model")
	end
	if not model then return nil end
	return H.triggerValid(model, Players:GetPlayerFromCharacter(model))
end

function H.triggerRelease()
	if S.trigger.holding then
		H.mouseUp()
		S.trigger.holding = false
	end
end

H.track(RunService.RenderStepped:Connect(function(dt)
	if not alive() then return end
	if not (F.trigger and H.aliveChar()) or S.rage.holding then
		H.triggerRelease()
		S.trigger.tap, S.trigger.seen = 0, 0
		return
	end

	local now = os.clock()
	local onTarget = H.triggerTarget() ~= nil
	if onTarget then S.trigger.seen = now end

	if F.triggerDelay <= 0 then
		local recent = now - S.trigger.seen <= 0.12
		if recent and not S.trigger.holding then
			H.mouseDown()
			S.trigger.holding = true
		elseif not recent then
			H.triggerRelease()
		end
		return
	end

	H.triggerRelease()

	if onTarget then
		S.trigger.tap = S.trigger.tap - dt
		if S.trigger.tap <= 0 then
			task.spawn(H.click)
			S.trigger.tap = F.triggerDelay
		end
	else
		S.trigger.tap = 0
	end
end))

H.INFO_KEYS = { "ShootRecoil", "ShootCooldown", "AimSpeed", "AttackCooldown", "DashCooldown", "InputSpammingEnabled" }

H.INFO_MODS = {
	{ key = "ShootRecoil", on = function() return F.recoil end, scale = function() return 1 - F.recoilPct / 100 end },
	{ key = "ShootCooldown", on = function() return F.fireRate end, scale = function() return F.fireRatePct / 100 end },
	{ key = "AimSpeed", on = function() return F.aimSpeed end, scale = function() return F.aimSpeedPct / 100 end },
	{ key = "AttackCooldown", on = function() return F.melee end, scale = function() return F.meleePct / 100 end },
	{ key = "DashCooldown", on = function() return F.dash end, scale = function() return F.dashPct / 100 end },
}

function H.infoWritable(info)
	return type(info) == "table" and not (table.isfrozen and table.isfrozen(info))
end

function H.applyItem(item)
	local info = type(item) == "table" and rawget(item, "Info")
	if not H.infoWritable(info) then return end

	local backup = S.infoBackup[item]
	if not backup then
		backup = { info = info }
		for _, key in ipairs(H.INFO_KEYS) do backup[key] = rawget(info, key) end
		S.infoBackup[item] = backup
	end

	for _, mod in ipairs(H.INFO_MODS) do
		local base = backup[mod.key]
		if type(base) == "number" then
			rawset(info, mod.key, mod.on() and base * mod.scale() or base)
		end
	end

	local spam = backup.InputSpammingEnabled
	if type(spam) == "table" then
		if F.autoFire then
			local copy = table.clone(spam)
			copy.StartShooting = 0
			copy.StartReloading = 0
			rawset(info, "InputSpammingEnabled", copy)
		else
			rawset(info, "InputSpammingEnabled", spam)
		end
	end
end

function H.restoreItems()
	for _, backup in pairs(S.infoBackup) do
		local info = backup.info
		if H.infoWritable(info) then
			for _, key in ipairs(H.INFO_KEYS) do
				if backup[key] ~= nil then rawset(info, key, backup[key]) end
			end
		end
	end
	table.clear(S.infoBackup)
end

function H.modsWanted()
	return F.recoil or F.fireRate or F.aimSpeed or F.melee or F.dash or F.autoFire
end

H.loop(0.3, function()
	if not H.modsWanted() and not next(S.infoBackup) then return end
	for _, item in pairs(H.fighterItems()) do pcall(H.applyItem, item) end
end)

function H.overlayFolder()
	if S.adornFolder and S.adornFolder.Parent then return S.adornFolder end
	local folder = Instance.new("Folder")
	folder.Name = tostring(math.random(100000, 999999))
	folder.Parent = H.guiParent()
	S.adornFolder = folder
	return folder
end

function H.soundSource(sound)
	local parent = sound.Parent
	if not parent then return nil end
	if parent:IsA("BasePart") then return parent.Position end
	if parent:IsA("Attachment") then return parent.WorldPosition end
	local model = parent:FindFirstAncestorOfClass("Model")
	local root = model and H.root(model)
	return root and root.Position or nil
end

function H.soundOwner(sound)
	local model = sound:FindFirstAncestorOfClass("Model")
	while model do
		local player = Players:GetPlayerFromCharacter(model)
		if player then return player end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil
end

function H.ring(position, loudness)
	if #S.rings >= 40 then
		local oldest = table.remove(S.rings, 1)
		pcall(function() oldest.adorn:Destroy() end)
	end
	local adorn = Instance.new("CylinderHandleAdornment")
	adorn.Adornee = workspace.Terrain
	adorn.AlwaysOnTop = true
	adorn.ZIndex = 5
	adorn.Height = 0.05
	adorn.InnerRadius = 0
	adorn.Radius = 0.5
	adorn.Color3 = F.soundColor
	adorn.Transparency = 0.2
	adorn.CFrame = CFrame.new(position) * CFrame.Angles(math.rad(90), 0, 0)
	adorn.Parent = H.overlayFolder()
	table.insert(S.rings, { adorn = adorn, born = os.clock(), size = 2 + math.clamp(loudness, 0, 1) * 6 })
end

function H.onSoundPlayed(sound)
	if not (alive() and F.soundEsp) then return end
	local owner = H.soundOwner(sound)
	if not owner or owner == LocalPlayer then return end
	if F.soundEnemiesOnly and not H.enemy(owner) then return end
	local position = H.soundSource(sound)
	if not position then return end
	local loudness = math.clamp((sound.Volume or 0.5) * (sound.PlaybackLoudness > 0 and 1 or 0.6), 0, 1)
	H.ring(position, loudness)
end

function H.trackSound(sound)
	if S.soundHooks[sound] then return end
	S.soundHooks[sound] = {
		sound.Played:Connect(function() pcall(H.onSoundPlayed, sound) end),
		sound.Destroying:Connect(function()
			local hooks = S.soundHooks[sound]
			S.soundHooks[sound] = nil
			if hooks then for _, connection in ipairs(hooks) do pcall(function() connection:Disconnect() end) end end
		end),
	}
end

function H.stopSoundTracking()
	if S.soundAdded then
		pcall(function() S.soundAdded:Disconnect() end)
		S.soundAdded = nil
	end
	for _, hooks in pairs(S.soundHooks) do
		for _, connection in ipairs(hooks) do pcall(function() connection:Disconnect() end) end
	end
	table.clear(S.soundHooks)
	for _, ring in ipairs(S.rings) do pcall(function() ring.adorn:Destroy() end) end
	table.clear(S.rings)
end

function H.setSoundEsp(state)
	F.soundEsp = state
	if not state then
		H.stopSoundTracking()
		return
	end
	if S.soundAdded then return end
	S.soundAdded = workspace.DescendantAdded:Connect(function(item)
		if item:IsA("Sound") then H.trackSound(item) end
	end)
	task.spawn(function()
		for index, item in ipairs(workspace:GetDescendants()) do
			if index % 500 == 0 then task.wait() end
			if not F.soundEsp then return end
			if item:IsA("Sound") then H.trackSound(item) end
		end
	end)
end

H.track(RunService.RenderStepped:Connect(function()
	local now = os.clock()
	for index = #S.rings, 1, -1 do
		local ring = S.rings[index]
		local age = (now - ring.born) / math.max(F.soundLife, 0.2)
		if age >= 1 or not ring.adorn.Parent then
			pcall(function() ring.adorn:Destroy() end)
			table.remove(S.rings, index)
		else
			ring.adorn.Radius = 0.5 + ring.size * (1 - (1 - age) ^ 3)
			ring.adorn.Transparency = 0.2 + age * 0.8
			ring.adorn.Color3 = F.soundColor
		end
	end
end))

S.fov = { base = 0, saved = nil }
S.renderName = "FacilityRivalsFov" .. SESSION

RunService:BindToRenderStep(S.renderName, Enum.RenderPriority.Camera.Value + 5, function()
	if not alive() then return end
	local camera = workspace.CurrentCamera
	if not camera then return end
	if not F.camFov then
		if S.fov.saved then
			camera.FieldOfView = S.fov.saved
			S.fov.saved = nil
		end
		S.fov.base = 0
		return
	end
	local current = camera.FieldOfView
	if current ~= F.camFovValue then
		if current > S.fov.base then S.fov.base = current end
		if current < S.fov.base * 0.92 then return end
	end
	S.fov.saved = S.fov.saved or current
	camera.FieldOfView = F.camFovValue
end)

function H.lightingStep()
	if F.fullbright then
		H.setProp(Lighting, "Brightness", 2)
		H.setProp(Lighting, "GlobalShadows", false)
		H.setProp(Lighting, "Ambient", Color3.fromRGB(178, 178, 178))
		H.setProp(Lighting, "OutdoorAmbient", Color3.fromRGB(178, 178, 178))
	else
		H.restoreProp(Lighting, "Brightness")
		H.restoreProp(Lighting, "GlobalShadows")
		H.restoreProp(Lighting, "Ambient")
		H.restoreProp(Lighting, "OutdoorAmbient")
	end

	if F.noFog then
		H.setProp(Lighting, "FogEnd", 1e6)
		local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
		if atmosphere then H.setProp(atmosphere, "Density", 0) end
	else
		H.restoreProp(Lighting, "FogEnd")
		local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
		if atmosphere then H.restoreProp(atmosphere, "Density") end
	end

	if F.clockTime then
		H.setProp(Lighting, "ClockTime", F.clockValue)
	else
		H.restoreProp(Lighting, "ClockTime")
	end
end

H.loop(0.5, H.lightingStep)

S.cosmetics = { map = {}, key = "GetWeaponData\0fcl", patch = nil }

function H.cosmeticSave()
	if type(writefile) ~= "function" then return end
	pcall(function()
		if type(isfolder) == "function" and type(makefolder) == "function" then
			if not isfolder("Facility") then makefolder("Facility") end
			if not isfolder(H.SAVE_FOLDER) then makefolder(H.SAVE_FOLDER) end
		end
		writefile(H.COSMETIC_FILE, HttpService:JSONEncode(S.cosmetics.map))
	end)
end

function H.cosmeticLoad()
	if type(readfile) ~= "function" or type(isfile) ~= "function" then return end
	local ok, raw = pcall(function()
		if isfile(H.COSMETIC_FILE) then return readfile(H.COSMETIC_FILE) end
		return nil
	end)
	local map = ok and H.decode(raw)
	if type(map) == "table" then S.cosmetics.map = map end
end

H.cosmeticLoad()

function H.weaponNames()
	local library = S.lib.Items
	local items = type(library) == "table" and rawget(library, "Items")
	local names = {}
	if type(items) == "table" then
		for name in pairs(items) do
			if name ~= "MISSING_WEAPON" then table.insert(names, name) end
		end
	end
	table.sort(names)
	return names
end

function H.cosmeticNames(slot, weapon)
	local library = S.lib.Cosmetics
	local cosmetics = type(library) == "table" and rawget(library, "Cosmetics")
	local names = {}
	if type(cosmetics) == "table" then
		for name, entry in pairs(cosmetics) do
			if type(entry) == "table" and rawget(entry, "Type") == slot then
				if slot ~= "Skin" or rawget(entry, "ItemName") == weapon then table.insert(names, name) end
			end
		end
	end
	table.sort(names)
	table.insert(names, 1, "None")
	return names
end

function H.weaponDataFunction()
	local controller = S.lib.PlayerData
	if type(controller) ~= "table" then return nil end
	local meta = getmetatable(controller)
	local index = type(meta) == "table" and rawget(meta, "__index")
	local found = type(index) == "table" and rawget(index, "GetWeaponData") or nil
	return found or rawget(controller, "GetWeaponData")
end

function H.installCosmetics()
	if S.cosmetics.patch then return true end
	local utility = S.lib.DataUtility
	local original = type(utility) == "table" and rawget(utility, "GetWeaponData")
	local caller = H.weaponDataFunction()
	if type(original) ~= "function" or type(caller) ~= "function" then return false, "weapon data functions not found" end
	if type(debug.getconstants) ~= "function" or type(debug.setconstant) ~= "function" then return false, "debug.setconstant unavailable" end

	local index = nil
	for slot, constant in pairs(debug.getconstants(caller)) do
		if constant == "GetWeaponData" then
			index = slot
			break
		end
	end
	if not index then return false, "GetWeaponData constant not found" end

	rawset(utility, S.cosmetics.key, function(first, context, weapon, ...)
		local data = original(first, context, weapon, ...)
		if not (alive() and F.cosmetics) or type(weapon) ~= "string" then return data end

		local player = type(context) == "table" and (rawget(context, "Player") or rawget(context, "_player_object")) or nil
		if typeof(player) == "Instance" and player:IsA("Player") and player ~= LocalPlayer then return data end

		local chosen = S.cosmetics.map[weapon]
		if type(chosen) ~= "table" or next(chosen) == nil then return data end

		local copy = type(data) == "table" and table.clone(data) or {}
		for _, slot in ipairs(H.SLOTS) do
			if chosen[slot] then copy[slot] = { Name = chosen[slot] } end
		end
		return copy
	end)

	debug.setconstant(caller, index, S.cosmetics.key)
	S.cosmetics.patch = { caller = caller, index = index, utility = utility }
	return true
end

function H.removeCosmetics()
	local patch = S.cosmetics.patch
	if not patch then return end
	pcall(debug.setconstant, patch.caller, patch.index, "GetWeaponData")
	pcall(rawset, patch.utility, S.cosmetics.key, nil)
	S.cosmetics.patch = nil
end

function H.setCosmetic(weapon, slot, name)
	if not weapon or weapon == "" then return end
	local map = S.cosmetics.map
	map[weapon] = map[weapon] or {}
	if name == nil or name == "None" then
		map[weapon][slot] = nil
	else
		map[weapon][slot] = name
	end
	if next(map[weapon]) == nil then map[weapon] = nil end
	H.cosmeticSave()
end

function H.cosmeticCount()
	local count = 0
	for _ in pairs(S.cosmetics.map) do count = count + 1 end
	return count
end

S.respawnAt = 0

H.loop(0.25, function()
	if not F.autoRespawn or not S.remotes.respawn then return end
	local character = LocalPlayer.Character
	local dead = character ~= nil and not H.aliveChar(character)
	if not dead or os.clock() - S.respawnAt < 2 then return end
	S.respawnAt = os.clock()
	for _ = 1, 5 do
		if not alive() then return end
		pcall(H.fireServer, S.remotes.respawn)
		task.wait(0.1)
	end
end)

H.track(LocalPlayer.Idled:Connect(function()
	if not F.antiAfk then return end
	pcall(function()
		VirtualUser:CaptureController()
		VirtualUser:ClickButton2(Vector2.new())
	end)
end))

function H.checkModerator(player)
	if player == LocalPlayer or S.flagged[player] ~= nil then return end
	S.flagged[player] = false
	task.spawn(function()
		local ok, rank = pcall(player.GetRankInGroup, player, H.MOD_GROUP)
		if not (alive() and ok and type(rank) == "number" and rank >= H.MOD_RANK) then return end
		S.flagged[player] = true
		if F.modNotify then
			pcall(function() Library:Warn("Moderator", player.DisplayName .. " (@" .. player.Name .. ") is a game moderator.", 15) end)
		end
		if F.modLeave then
			pcall(function() LocalPlayer:Kick("Facility: a moderator joined (" .. player.Name .. ")") end)
		end
	end)
end

for _, player in ipairs(Players:GetPlayers()) do H.checkModerator(player) end
H.track(Players.PlayerAdded:Connect(H.checkModerator))
H.track(Players.PlayerRemoving:Connect(function(player) S.flagged[player] = nil end))

function H.moderatorsText()
	local names = {}
	for player, flagged in pairs(S.flagged) do
		if flagged and player.Parent then table.insert(names, player.DisplayName) end
	end
	return #names > 0 and table.concat(names, ", ") or "none in this server"
end

function H.rejoin()
	pcall(function() TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer) end)
end

function H.serverHop()
	pcall(function() TeleportService:Teleport(game.PlaceId, LocalPlayer) end)
end

shared.FacilityCleanup = function()
	F.silent, F.trigger, F.rage, F.soundEsp, F.cosmetics = false, false, false, false, false
	F.recoil, F.fireRate, F.aimSpeed, F.melee, F.dash, F.autoFire, F.noSpread = false, false, false, false, false, false, false
	F.camFov, F.fullbright, F.noFog, F.clockTime = false, false, false, false

	pcall(H.triggerRelease)
	pcall(H.rageRelease)
	pcall(H.removeInputHook)
	pcall(H.removeCosmetics)
	pcall(H.restoreItems)
	pcall(H.stopSoundTracking)
	pcall(H.restoreAll)
	pcall(function() RunService:UnbindFromRenderStep(S.renderName) end)
	if S.fov.saved and workspace.CurrentCamera then pcall(function() workspace.CurrentCamera.FieldOfView = S.fov.saved end) end
	Entity.IsTargetable = S.entityOriginal
	pcall(function() Entity:RefreshTargets() end)

	for _, connection in ipairs(S.connections) do pcall(function() connection:Disconnect() end) end
	for _, thread in ipairs(S.threads) do pcall(task.cancel, thread) end
	for _, object in ipairs(S.drawings) do pcall(function() object:Remove() end) end
	for _, object in ipairs(S.instances) do pcall(function() object:Destroy() end) end
	if S.adornFolder then pcall(function() S.adornFolder:Destroy() end) end

	pcall(function() Esp:Unload() end)
	if Aimbot then pcall(function() Aimbot:Unload() end) end
	if Movement then pcall(function() Movement:Unload() end) end
	pcall(function() Library:Destroy() end)
end

for _, message in ipairs(moduleErrors) do
	warn("[Facility] " .. message)
end

pcall(function() Entity.Settings.TeamCheck = "Team" end)
pcall(function() Esp.sharedSettings.teamCheck = "Team" end)
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

U.Combat    = Window:Tab("Combat", "crosshair")
U.Silent    = Window:Tab("Silent Aim", "target")
U.Guns      = Window:Tab("Weapons", "sword")
U.Visuals   = Window:Tab("Visuals", "eye")
U.World     = Window:Tab("World", "globe")
U.PlayerT   = Window:Tab("Player", "user-round")
U.Cosmetics = Window:Tab("Cosmetics", "palette")
U.Misc      = Window:Tab("Misc", "package")
Window:TabDivider()
U.Settings  = Window:Tab("Settings", "cog")

if #moduleErrors > 0 then
	U.failBox = U.Combat:Section("Modules", "full")
	for _, message in ipairs(moduleErrors) do
		U.failBox:Label(message, { Style = "dim" })
	end
end

U.teamBox = U.Combat:Section("Targets", 2)
H.T(U.teamBox, "Team Check", "rv_team_check", true, function(state)
	F.teamCheck = state
	pcall(function() Entity:RefreshTargets() end)
end, "uses the duel teams, players in other matches are ignored")

if Aimbot then

Aimbot.Settings.TeamCheck = true
Aimbot.Settings.WallCheck = true

U.aimBox = U.Combat:Section("Aimbot", 1)

U.aimBox:Toggle({
	Text = "Enable",
	Flag = "rv_aim_enable",
	Default = false,
	Callback = function(state)
		if state then
			local ok, err = pcall(function() Aimbot:Load(Entity) end)
			if not ok then
				Library:Error("Aimbot", tostring(err), 10)
				return
			end
		end
		Aimbot.Enabled = state
	end,
})

U.aimBox:Keybind({
	Text = "Aim Key",
	Flag = "rv_aim_key",
	Default = "MB2",
	Mode = "toggle",
	OnChanged = function(key)
		local map = {
			MB1 = Enum.UserInputType.MouseButton1,
			MB2 = Enum.UserInputType.MouseButton2,
			MB3 = Enum.UserInputType.MouseButton3,
		}
		local chosen = map[key] or Enum.KeyCode[key] or Enum.UserInputType.MouseButton2
		Aimbot.Settings.Key = chosen
		pcall(function() Aimbot:SetKey(chosen) end)
	end,
})

U.aimBox:Toggle({
	Text = "Toggle Mode",
	Flag = "rv_aim_toggle_mode",
	Default = false,
	Callback = function(state) Aimbot.Settings.ToggleMode = state end,
})

U.aimBox:Dropdown({
	Text = "Priority",
	Flag = "rv_aim_priority",
	Options = { "Cursor", "Closest", "LowestHealth" },
	Default = "Cursor",
	Callback = function(value) Aimbot.Settings.Priority = value end,
})

U.aimBox:Dropdown({
	Text = "Target Part",
	Flag = "rv_aim_parts",
	Options = { "Head", "UpperTorso", "HumanoidRootPart" },
	Default = { "Head" },
	Multi = true,
	Empty = "Head",
	Callback = function(selected)
		if #selected == 0 then selected = { "Head" } end
		Aimbot.Settings.Parts = selected
	end,
})

U.aimBox:Toggle({
	Text = "Random Part",
	Flag = "rv_aim_random_part",
	Default = false,
	Callback = function(state) Aimbot.Settings.RandomPart = state end,
})
	:Gear(function(panel)
		panel:Slider({
			Text = "Interval",
			Flag = "rv_aim_random_interval",
			Min = 0.1, Max = 3, Default = 1,
			Decimals = 1,
			Suffix = " s",
			Callback = function(value) Aimbot.Settings.RandomInterval = value end,
		})
	end)

H.S(U.aimBox, "Smoothness", "rv_aim_smoothness", 0.05, 1, 0.3, 2, function(value) Aimbot.Settings.Smoothness = value end)
H.S(U.aimBox, "Sensitivity", "rv_aim_sensitivity", 0.02, 1, 0.5, 2, function(value) Aimbot.Settings.Sensitivity = value end)
H.D(U.aimBox, "Easing Style", "rv_aim_easing_style", { "Linear", "Sine", "Quad", "Cubic", "Quart", "Quint", "Exponential", "Back" }, "Quad", function(value) Aimbot.Settings.EasingStyle = value end)
H.D(U.aimBox, "Easing Direction", "rv_aim_easing_direction", { "In", "Out", "InOut" }, "Out", function(value) Aimbot.Settings.EasingDirection = value end)
H.S(U.aimBox, "Switch Delay", "rv_aim_switch_delay", 0, 2, 0, 2, function(value) Aimbot.Settings.SwitchDelay = value end, " s")
H.S(U.aimBox, "Max Distance", "rv_aim_max_distance", 100, 5000, 3000, 0, function(value) Aimbot.Settings.MaxDistance = value end, " studs")

U.fovBox = U.Combat:Section("Fov", 2)

U.fovBox:Toggle({
	Text = "Fov",
	Flag = "rv_aim_fov_enabled",
	Default = true,
	Callback = function(state)
		Aimbot.Settings.FovCheck = state
		Aimbot.Settings.FovVisible = state
	end,
})
	:ColorPicker({
		Flag = "rv_aim_fov_color",
		Default = Color3.fromRGB(255, 255, 255),
		Callback = function(color) Aimbot.Settings.FovColor = color end,
	})
	:ColorPicker({
		Flag = "rv_aim_fov_lock_color",
		Default = Color3.fromRGB(255, 70, 70),
		Callback = function(color) Aimbot.Settings.FovLockColor = color end,
	})

U.fovBox:Slider({
	Text = "Radius",
	Flag = "rv_aim_fov",
	Min = 20, Max = 600, Default = 180,
	Callback = function(value)
		Aimbot.Settings.Fov = value
		pcall(function() Aimbot:SetFov(value) end)
	end,
})

H.S(U.fovBox, "Thickness", "rv_aim_fov_thickness", 1, 5, 1, 0, function(value) Aimbot.Settings.FovThickness = value end)
H.S(U.fovBox, "Transparency", "rv_aim_fov_transparency", 0, 1, 0.4, 2, function(value) Aimbot.Settings.FovTransparency = value end)
H.T(U.fovBox, "Filled", "rv_aim_fov_filled", false, function(state) Aimbot.Settings.FovFilled = state end)

U.behaviourBox = U.Combat:Section("Behaviour", 2)

H.T(U.behaviourBox, "Team Check", "rv_aim_team_check", true, function(state) Aimbot.Settings.TeamCheck = state end)
H.T(U.behaviourBox, "Wall Check", "rv_aim_wall_check", true, function(state) Aimbot.Settings.WallCheck = state end)
H.T(U.behaviourBox, "Multipoint", "rv_aim_multipoint", false, function(state) Aimbot.Settings.Multipoint = state end)
H.S(U.behaviourBox, "Deadzone", "rv_aim_deadzone", 0, 200, 0, 0, function(value) Aimbot.Settings.Deadzone = value end)

U.behaviourBox:Toggle({
	Text = "Sticky Target",
	Flag = "rv_aim_sticky",
	Default = true,
	Callback = function(state) Aimbot.Settings.Sticky = state end,
})
	:Gear(function(panel)
		H.S(panel, "Hold Fov", "rv_aim_sticky_fov", 1, 3, 1.6, 1, function(value) Aimbot.Settings.StickyFov = value end)
	end)

U.behaviourBox:Toggle({
	Text = "Prediction",
	Flag = "rv_aim_prediction",
	Default = false,
	Callback = function(state) Aimbot.Settings.Prediction = state end,
})
	:Gear(function(panel)
		H.S(panel, "Time", "rv_aim_prediction_time", 0, 0.5, 0.1, 2, function(value) Aimbot.Settings.PredictionTime = value end, " s")
		H.T(panel, "Add Ping", "rv_aim_prediction_ping", false, function(state) Aimbot.Settings.PingPrediction = state end)
	end)

U.behaviourBox:Toggle({
	Text = "Target Line",
	Flag = "rv_aim_target_line",
	Default = false,
	Callback = function(state) Aimbot.Settings.TargetLine = state end,
})
	:ColorPicker({
		Flag = "rv_aim_target_line_color",
		Default = Color3.fromRGB(255, 70, 70),
		Callback = function(color) Aimbot.Settings.TargetLineColor = color end,
	})

H.T(U.behaviourBox, "Target Info", "rv_aim_target_info", false, function(state) Aimbot.Settings.TargetInfo = state end)

end

U.triggerBox = U.Combat:Section("Trigger Bot", 1)

U.triggerBox:Toggle({
	Text = "Enable",
	Flag = "rv_trigger",
	Default = false,
	Hint = "fires while an enemy sits under your crosshair",
	Callback = function(state)
		F.trigger = state
		if not state then H.triggerRelease() end
	end,
})
	:Keybind({ Default = "None", Flag = "rv_trigger_key" })

H.D(U.triggerBox, "Mode", "rv_trigger_mode", { "Crosshair", "Target", "Fov" }, "Crosshair", function(value) F.triggerMode = value end)
H.S(U.triggerBox, "Fov", "rv_trigger_fov", 0, 400, 0, 0, function(value) F.triggerFov = value end)
H.T(U.triggerBox, "Team Check", "rv_trigger_team", true, function(state) F.triggerTeam = state end)
H.S(U.triggerBox, "Shot Delay", "rv_trigger_delay", 0, 2, 0, 2, function(value)
	F.triggerDelay = value
	H.triggerRelease()
end, " s")
U.triggerBox:Label("0 holds and sprays, higher values tap.", { Style = "dim" })

U.silentBox = U.Silent:Section("Silent Aim", 1)

U.silentBox:Toggle({
	Text = "Enable",
	Flag = "rv_silent",
	Default = false,
	Hint = "your shots land on the target inside the circle",
	Callback = function(state)
		F.silent = state
		if state and not H.needInputHook("Silent Aim") then F.silent = false end
	end,
})
	:Keybind({ Default = "None", Flag = "rv_silent_key" })
	:ColorPicker({ Flag = "rv_silent_fov_color", Default = F.silentFovColor, Callback = function(color) F.silentFovColor = color end })

H.S(U.silentBox, "Fov", "rv_silent_fov", 20, 800, 160, 0, function(value) F.silentFov = value end, " px")
H.T(U.silentBox, "Show Fov", "rv_silent_show_fov", false, function(state) F.silentShowFov = state end)
H.D(U.silentBox, "Aim Part", "rv_silent_part", { "Head", "Torso", "Random" }, "Head", function(value) F.silentPart = value end)
H.S(U.silentBox, "Hit Chance", "rv_silent_hit", 1, 100, 100, 0, function(value) F.silentHit = value end, "%")
H.S(U.silentBox, "Head Chance", "rv_silent_head", 0, 100, 100, 0, function(value) F.silentHead = value end, "%")

U.silentChecks = U.Silent:Section("Silent Checks", 2)
H.T(U.silentChecks, "Visible Only", "rv_silent_visible", true, function(state) F.silentVisible = state end)
H.T(U.silentChecks, "Only While Firing", "rv_silent_firing", false, function(state) F.silentFiring = state end)
U.silentChecks:Label("Shots are rewritten before they leave your game, the camera never moves.", { Style = "dim" })

U.rageBox = U.Silent:Section("Ragebot", 1)

U.rageBox:Toggle({
	Text = "Enable",
	Flag = "rv_rage",
	Default = false,
	Hint = "targets the closest enemy and fires on its own",
	Callback = function(state)
		F.rage = state
		if state and not H.needInputHook("Ragebot") then F.rage = false end
		if not F.rage then H.rageRelease() end
	end,
})
	:Keybind({ Default = "None", Flag = "rv_rage_key" })

H.T(U.rageBox, "Auto Fire", "rv_rage_fire", true, function(state)
	F.rageFire = state
	if not state then H.rageRelease() end
end)
H.T(U.rageBox, "Visible Only", "rv_rage_visible", true, function(state) F.rageVisible = state end, "off also shoots through walls")
H.S(U.rageBox, "Max Distance", "rv_rage_range", 50, 3000, 1500, 0, function(value) F.rageRange = value end, " studs")

U.gunBox = U.Guns:Section("Aim & Fire", 1)
H.T(U.gunBox, "Remove Spread", "rv_no_spread", false, function(state)
	F.noSpread = state
	if state and not H.needInputHook("Remove Spread") then F.noSpread = false end
end)
H.T(U.gunBox, "Automatic Fire", "rv_auto_fire", false, function(state) F.autoFire = state end, "hold to keep shooting with any gun")

U.gunBox:Toggle({
	Text = "Reduce Recoil",
	Flag = "rv_recoil",
	Default = false,
	Callback = function(state) F.recoil = state end,
})
	:Gear(function(panel)
		H.S(panel, "Reduction", "rv_recoil_pct", 0, 100, 100, 0, function(value) F.recoilPct = value end, "%")
	end)

U.gunBox:Toggle({
	Text = "Aim Speed",
	Flag = "rv_aim_speed",
	Default = false,
	Callback = function(state) F.aimSpeed = state end,
})
	:Gear(function(panel)
		H.S(panel, "Speed", "rv_aim_speed_pct", 50, 500, 200, 0, function(value) F.aimSpeedPct = value end, "%")
	end)

U.coolBox = U.Guns:Section("Cooldowns", 2)

U.coolBox:Toggle({
	Text = "Fire Rate",
	Flag = "rv_fire_rate",
	Default = false,
	Callback = function(state) F.fireRate = state end,
})
	:Gear(function(panel)
		H.S(panel, "Cooldown", "rv_fire_rate_pct", 10, 100, 50, 0, function(value) F.fireRatePct = value end, "%")
	end)

U.coolBox:Toggle({
	Text = "Melee Cooldown",
	Flag = "rv_melee",
	Default = false,
	Callback = function(state) F.melee = state end,
})
	:Gear(function(panel)
		H.S(panel, "Cooldown", "rv_melee_pct", 0, 100, 50, 0, function(value) F.meleePct = value end, "%")
	end)

U.coolBox:Toggle({
	Text = "Dash Cooldown",
	Flag = "rv_dash",
	Default = false,
	Callback = function(state) F.dash = state end,
})
	:Gear(function(panel)
		H.S(panel, "Cooldown", "rv_dash_pct", 0, 100, 50, 0, function(value) F.dashPct = value end, "%")
	end)

U.coolBox:Label("Percent of the normal value, lower is faster. Applies to every weapon you hold.", { Style = "dim" })

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

U.espBox = U.Visuals:Section("Esp", 1)

U.espBox:Toggle({
	Text = "Enable",
	Flag = "rv_esp_enable",
	Default = false,
	Callback = function(state)
		local ok, err
		if state then
			ok, err = pcall(function() Esp:Load(Entity) end)
		else
			ok, err = pcall(function() Esp:Unload() end)
		end
		if not ok then Library:Error("Esp", tostring(err), 10) end
	end,
})
	:Keybind({ Default = "None", Flag = "rv_esp_enable_key" })

U.espBox:Toggle({
	Text = "Box",
	Flag = "rv_esp_box",
	Default = true,
	Callback = function(state) H.espSet("box", state) end,
})
	:ColorPicker({
		Flag = "rv_esp_box_color",
		Default = Color3.fromRGB(255, 255, 255),
		Callback = function(color, alpha)
			H.espPair("boxColor", color, alpha)
			H.espPair("box3dColor", color, alpha)
		end,
	})
	:Gear(function(panel)
		H.D(panel, "Style", "rv_esp_box_style", { "2D", "3D" }, "2D", function(value)
			H.espSet("box", value == "2D")
			H.espSet("box3d", value == "3D")
		end)
	end)

U.espBox:Toggle({
	Text = "Health Bar",
	Flag = "rv_esp_health_bar",
	Default = true,
	Callback = function(state) H.espSet("healthBar", state) end,
})
	:ColorPicker({ Flag = "rv_esp_health_healthy", Default = Color3.fromRGB(82, 197, 148), Callback = function(color) H.espSet("healthyColor", color) end })
	:ColorPicker({ Flag = "rv_esp_health_dying", Default = Color3.fromRGB(240, 90, 102), Callback = function(color) H.espSet("dyingColor", color) end })

U.espBox:Toggle({
	Text = "Skeleton",
	Flag = "rv_esp_skeleton",
	Default = false,
	Callback = function(state) H.espSet("skeleton", state) end,
})
	:ColorPicker({ Flag = "rv_esp_skeleton_color", Default = Color3.new(1, 1, 1), Callback = function(color, alpha) H.espPair("skeletonColor", color, alpha) end })

U.espBox:Toggle({
	Text = "Tracers",
	Flag = "rv_esp_tracer",
	Default = false,
	Callback = function(state) H.espSet("tracer", state) end,
})
	:ColorPicker({ Flag = "rv_esp_tracer_color", Default = Color3.new(1, 1, 1), Callback = function(color, alpha) H.espPair("tracerColor", color, alpha) end })
	:Gear(function(panel)
		H.D(panel, "Origin", "rv_esp_tracer_origin", { "Bottom", "Middle", "Top", "Mouse" }, "Bottom", function(value) H.espSet("tracerOrigin", value) end)
	end)

U.espBox:Toggle({
	Text = "Highlight",
	Flag = "rv_esp_chams",
	Default = false,
	Callback = function(state) H.espSet("chams", state) end,
})
	:ColorPicker({ Flag = "rv_esp_chams_color", Default = Color3.fromRGB(255, 60, 60), Callback = function(color, alpha) H.espPair("chamsFillColor", color, alpha) end })

U.espBox:Toggle({
	Text = "Off Screen Arrow",
	Flag = "rv_esp_arrow",
	Default = false,
	Callback = function(state) H.espSet("offScreenArrow", state) end,
})
	:ColorPicker({ Flag = "rv_esp_arrow_color", Default = Color3.new(1, 1, 1), Callback = function(color, alpha) H.espPair("offScreenArrowColor", color, alpha) end })

U.displayBox = U.Visuals:Section("Display", 2)

U.displayBox:Toggle({
	Text = "Name",
	Flag = "rv_esp_name",
	Default = true,
	Callback = function(state) H.espSet("name", state) end,
})
	:ColorPicker({ Flag = "rv_esp_name_color", Default = Color3.fromRGB(236, 241, 250), Callback = function(color, alpha) H.espPair("nameColor", color, alpha) end })

U.displayBox:Toggle({
	Text = "Distance",
	Flag = "rv_esp_distance",
	Default = true,
	Callback = function(state) H.espSet("distance", state) end,
})
	:ColorPicker({ Flag = "rv_esp_distance_color", Default = Color3.fromRGB(170, 184, 205), Callback = function(color, alpha) H.espPair("distanceColor", color, alpha) end })

U.displayBox:Toggle({
	Text = "Weapon",
	Flag = "rv_esp_weapon",
	Default = false,
	Callback = function(state) H.espSet("weapon", state) end,
})
	:ColorPicker({ Flag = "rv_esp_weapon_color", Default = Color3.fromRGB(255, 255, 255), Callback = function(color, alpha) H.espPair("weaponColor", color, alpha) end })

H.T(U.displayBox, "Health", "rv_esp_health_text", false, function(state) H.espSet("healthText", state) end)
H.T(U.displayBox, "Team Color", "rv_esp_team_color", false, function(state) Esp.sharedSettings.useTeamColor = state end)
H.S(U.displayBox, "Text Size", "rv_esp_text_size", 8, 24, 13, 0, function(value) Esp.sharedSettings.textSize = value end)
H.S(U.displayBox, "Max Distance", "rv_esp_max_distance", 100, 5000, 1500, 0, function(value) H.espSet("maxDistance", value) end, " studs")

U.displayBox:Toggle({
	Text = "Show Teammates",
	Flag = "rv_esp_allies",
	Default = false,
	Callback = function(state) Esp.teamSettings.friendly.enabled = state end,
})
	:ColorPicker({
		Flag = "rv_esp_ally_color",
		Default = Color3.fromRGB(60, 255, 120),
		Callback = function(color)
			Esp.teamSettings.friendly.boxColor = { color, 1 }
			Esp.teamSettings.friendly.nameColor = { color, 1 }
		end,
	})


U.moveBox = U.PlayerT:Section("Movement", 1)

if Movement then

Movement.Settings.JumpMode = "Humanoid"

U.moveBox:Toggle({
	Text = "Fly",
	Flag = "rv_fly",
	Default = false,
	Callback = function(state) Movement:Fly(state) end,
})
	:Keybind({ Default = "None", Flag = "rv_fly_key" })
	:Gear(function(panel)
		H.S(panel, "Speed", "rv_fly_speed", 1, 20, 2, 1, function(value) Movement.Settings.FlySpeed = value end)
	end)

U.moveBox:Toggle({
	Text = "Jump Power",
	Flag = "rv_jump",
	Default = false,
	Callback = function(state) Movement:JumpPower(state and Movement.Settings.JumpPower or 50) end,
})
	:Gear(function(panel)
		H.S(panel, "Power", "rv_jump_value", 30, 300, 80, 0, function(value)
			Movement.Settings.JumpPower = value
			if Library.Flags["rv_jump"] then Movement:JumpPower(value) end
		end)
	end)

H.T(U.moveBox, "Infinite Jump", "rv_inf_jump", false, function(state) Movement:InfiniteJump(state) end)

U.moveBox:Toggle({
	Text = "Noclip",
	Flag = "rv_noclip",
	Default = false,
	Callback = function(state)
		Movement:Noclip(state)
		if not state then H.fixCollision() end
	end,
})
	:Keybind({ Default = "None", Flag = "rv_noclip_key" })

U.speedBox = U.PlayerT:Section("Speed", 2)

U.speedBox:Toggle({
	Text = "Walk Speed",
	Flag = "rv_walk",
	Default = false,
	Hint = "pushes your character forward on top of the normal speed",
	Callback = function(state)
		Movement:WalkSpeed(state and (Library.Flags["rv_walk_value"] or 30) or 16, "CFrame")
	end,
})
	:Keybind({ Default = "None", Flag = "rv_walk_key" })

H.S(U.speedBox, "Speed", "rv_walk_value", 16, 80, 30, 0, function(value)
	if Library.Flags["rv_walk"] then Movement:WalkSpeed(value, "CFrame") end
end)

end

U.soundBox = U.Visuals:Section("Sound Esp", 1)

U.soundBox:Toggle({
	Text = "Enable",
	Flag = "rv_sound_esp",
	Default = false,
	Hint = "draws a ring where enemies walk, shoot or reload, even through walls",
	Callback = function(state) H.setSoundEsp(state) end,
})
	:ColorPicker({ Flag = "rv_sound_color", Default = F.soundColor, Callback = function(color) F.soundColor = color end })

H.T(U.soundBox, "Enemies Only", "rv_sound_enemies", true, function(state) F.soundEnemiesOnly = state end)
H.S(U.soundBox, "Ring Time", "rv_sound_life", 0.5, 4, 1.5, 1, function(value) F.soundLife = value end, " s")

U.camBox = U.Visuals:Section("Camera", 2)
H.T(U.camBox, "Custom Fov", "rv_cam_fov", false, function(state) F.camFov = state end, "zoomed scopes are left alone")
H.S(U.camBox, "Field Of View", "rv_cam_fov_value", 60, 120, 90, 0, function(value) F.camFovValue = value end)

U.lightBox = U.World:Section("Lighting", 1)
H.T(U.lightBox, "Fullbright", "rv_fullbright", false, function(state)
	F.fullbright = state
	H.lightingStep()
end)
H.T(U.lightBox, "No Fog", "rv_no_fog", false, function(state)
	F.noFog = state
	H.lightingStep()
end)

U.lightBox:Toggle({
	Text = "Time Of Day",
	Flag = "rv_clock",
	Default = false,
	Callback = function(state)
		F.clockTime = state
		H.lightingStep()
	end,
})
	:Gear(function(panel)
		H.S(panel, "Hour", "rv_clock_value", 0, 24, 14, 1, function(value)
			F.clockValue = value
			H.lightingStep()
		end)
	end)

U.lookBox = U.Cosmetics:Section("Weapon Look", 1)

H.T(U.lookBox, "Enable", "rv_cosmetics", false, function(state)
	F.cosmetics = state
	if state then
		local ok, err = H.installCosmetics()
		if not ok then
			H.notify("Cosmetics", "Unavailable: " .. tostring(err), 6)
			F.cosmetics = false
		end
	end
end, "client side, only you see it")

S.lookSel = { weapon = nil }
U.lookPickers = {}

function H.refreshLookPickers()
	local weapon = S.lookSel.weapon
	local chosen = weapon and S.cosmetics.map[weapon] or {}
	for _, slot in ipairs(H.SLOTS) do
		local picker = U.lookPickers[slot]
		if picker then
			pcall(function() picker:SetOptions(H.cosmeticNames(slot, weapon)) end)
			pcall(function() picker:Set(chosen[slot] or "None") end)
		end
	end
end

U.lookWeapon = H.D(U.lookBox, "Weapon", "rv_look_weapon", { "-" }, "-", function(value)
	if value == "-" or value == S.lookSel.weapon then return end
	S.lookSel.weapon = value
	H.refreshLookPickers()
end)

for _, slot in ipairs(H.SLOTS) do
	U.lookPickers[slot] = H.D(U.lookBox, slot, "rv_look_" .. string.lower(slot), { "None" }, "None", function(value)
		local weapon = S.lookSel.weapon
		if not weapon then return end
		local current = S.cosmetics.map[weapon] and S.cosmetics.map[weapon][slot] or "None"
		if value == current then return end
		H.setCosmetic(weapon, slot, value)
		pcall(function() U.lookCount:Set(H.cosmeticCount() .. " weapons customised") end)
	end)
end

U.lookCount = U.lookBox:Label(H.cosmeticCount() .. " weapons customised", { Style = "dim" })

U.lookTools = U.Cosmetics:Section("Tools", 2)

H.B(U.lookTools, "Reload Lists", function()
	local weapons = H.weaponNames()
	S.lookSel.weapon = weapons[1]
	pcall(function() U.lookWeapon:SetOptions(#weapons > 0 and weapons or { "-" }) end)
	pcall(function() U.lookWeapon:Set(S.lookSel.weapon or "-") end)
	H.refreshLookPickers()
	H.notify("Cosmetics", #weapons .. " weapons found.", 3)
end)

H.B(U.lookTools, "Random Look On Everything", function()
	for _, weapon in ipairs(H.weaponNames()) do
		for _, slot in ipairs(H.SLOTS) do
			local names = H.cosmeticNames(slot, weapon)
			if #names > 1 then H.setCosmetic(weapon, slot, names[math.random(2, #names)]) end
		end
	end
	H.refreshLookPickers()
	pcall(function() U.lookCount:Set(H.cosmeticCount() .. " weapons customised") end)
end)

H.B(U.lookTools, "Reset Selected Weapon", function()
	local weapon = S.lookSel.weapon
	if weapon then
		S.cosmetics.map[weapon] = nil
		H.cosmeticSave()
	end
	H.refreshLookPickers()
	pcall(function() U.lookCount:Set(H.cosmeticCount() .. " weapons customised") end)
end)

H.B(U.lookTools, "Reset Everything", function()
	table.clear(S.cosmetics.map)
	H.cosmeticSave()
	H.refreshLookPickers()
	pcall(function() U.lookCount:Set(H.cosmeticCount() .. " weapons customised") end)
end)

U.lookTools:Label("Changes show on the next equip or respawn. Choices are saved for the next run.", { Style = "dim" })

task.spawn(function()
	task.wait(0.5)
	if not alive() then return end
	local weapons = H.weaponNames()
	S.lookSel.weapon = weapons[1]
	pcall(function() U.lookWeapon:SetOptions(#weapons > 0 and weapons or { "-" }) end)
	pcall(function() U.lookWeapon:Set(S.lookSel.weapon or "-") end)
	H.refreshLookPickers()
end)

U.autoBox = U.Misc:Section("Automation", 1)
H.T(U.autoBox, "Auto Respawn", "rv_auto_respawn", false, function(state) F.autoRespawn = state end, "skips the death screen")
H.T(U.autoBox, "Anti AFK", "rv_anti_afk", false, function(state) F.antiAfk = state end)
H.B(U.autoBox, "Rejoin Server", H.rejoin)
H.B(U.autoBox, "Server Hop", H.serverHop)

U.modBox = U.Misc:Section("Moderator Detection", 2)
H.T(U.modBox, "Notify", "rv_mod_notify", true, function(state) F.modNotify = state end, "warns when a game moderator is in your server")
H.T(U.modBox, "Leave Automatically", "rv_mod_leave", false, function(state)
	F.modLeave = state
	if state then
		for player, flagged in pairs(S.flagged) do
			if flagged and player.Parent then
				pcall(function() LocalPlayer:Kick("Facility: a moderator is in this server (" .. player.Name .. ")") end)
				return
			end
		end
	end
end)
U.modStatus = U.modBox:Paragraph({ Title = "Moderators", Content = H.moderatorsText() })

U.statusBox = U.Misc:Section("Status", 1)
U.statusText = U.statusBox:Paragraph({ Title = "Session", Content = "loading..." })

function H.statusText()
	local fighter = H.localFighter()
	return table.concat({
		"Shot hook: " .. (S.inputHook and "ready" or "not installed"),
		"Cosmetics hook: " .. (S.cosmetics.patch and "ready" or "not installed"),
		"Fighter: " .. (fighter and "loaded" or "in lobby"),
		"Team: " .. tostring(LocalPlayer:GetAttribute("TeamID") or "-"),
	}, "\n")
end

H.loop(1, function()
	pcall(function() U.statusText:Set({ Title = "Session", Content = H.statusText() }) end)
	pcall(function() U.modStatus:Set({ Title = "Moderators", Content = H.moderatorsText() }) end)
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
SaveManager:SetFolder(H.SAVE_FOLDER)

InterfaceManager:BuildInterfaceSection(U.Settings, 1)
SaveManager:BuildConfigSection(U.Settings, 2)
ThemeManager:Mount(Window)

Window:SetTab(U.Combat)

if #moduleErrors > 0 then
	task.delay(1, function()
		for _, message in ipairs(moduleErrors) do Library:Error("Facility", message, 20) end
	end)
end

Library:Notify("Facility", "Rivals loaded.", 4)

SaveManager:LoadAutoloadConfig()
ThemeManager:Load()
