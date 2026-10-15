
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

local AIMBOT_URL = "https://raw.githubusercontent.com/FacilityHUB/Facility-Sexility/refs/heads/main/CModules/FAimbot.luau"
local MOVEMENT_URL = "https://raw.githubusercontent.com/FacilityHUB/Facility-Sexility/refs/heads/main/CModules/FMovement.luau"

local moduleErrors = {}

local function fetchModule(url, label)
	local fetched, source = pcall(function()
		return game:HttpGet(url .. "?v=" .. tostring(tick()):gsub("%.", ""))
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

local Aimbot = fetchModule(AIMBOT_URL, "aimbot")
local Movement = fetchModule(MOVEMENT_URL, "movement")

if Movement then pcall(function() Movement:Load() end) end

FH.Aimbot = Aimbot
FH.Movement = Movement

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Lighting = game:GetService("Lighting")

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

local H = {}
local U = {}

local F = {
	bots = true, roomCheck = true,
	aimAlways = false, mobileButton = false,
	silent = false, silentPart = "Head", silentFov = 250, silentShowFov = true,
	silentWall = true, silentTeam = true, silentBots = true, silentHitChance = 100,
	silentRespect = true, silentMaxDistance = 3000,
	rapid = false,
	trigger = false, triggerMode = "Crosshair", triggerFov = 12, triggerKey = nil,
	triggerRequireAim = false, triggerHitChance = 100, triggerReaction = 0.05,
	triggerCooldown = 0.3, triggerHold = 0.06, triggerWall = true, triggerTeam = true,
	triggerParts = { "Head", "UpperTorso" }, triggerMaxDistance = 3000,
	chams = false, chamsAllies = false, chamsMax = 24,
	chamsVisible = Color3.fromRGB(255, 70, 70), chamsHidden = Color3.fromRGB(255, 200, 60),
	chamsAlly = Color3.fromRGB(80, 200, 120), chamsThrough = true,
	panel = false,
	fov = false, fovValue = 85, keepScope = true,
	bright = false, noFog = false,
}

local S = {
	api = nil, apiTried = false,
	controller = nil, controllerTried = false,
	attackGroup = nil, groupTried = false,
	proxies = {}, owner = {}, chams = {}, originals = {},
	hooks = {}, silentInstalled = false, rapidInstalled = false,
	silentChoice = nil, silentDepth = 0, lastSilent = nil, lastSilentAt = 0,
	mobileHeld = false, selfRender = nil,
	connections = {}, drawings = {}, gui = nil,
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

H.track(workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	Camera = workspace.CurrentCamera
end))

function H.api()
	if S.api or S.apiTried then return S.api end
	S.apiTried = true

	local ok, value = H.gcall(function()
		local remote = ReplicatedStorage:FindFirstChild("Remote")
		local module = remote and remote:FindFirstChild("EntityService")
		return module and require(module) or nil
	end)

	if ok and type(value) == "table" then S.api = value end
	return S.api
end

function H.controller()
	if S.controller or S.controllerTried then return S.controller end
	S.controllerTried = true

	local ok, value = H.gcall(function()
		local client = ReplicatedStorage:FindFirstChild("Client")
		local module = client and client:FindFirstChild("EntityController")
		return module and require(module) or nil
	end)

	if ok and type(value) == "table" then S.controller = value end
	return S.controller
end

function H.call(name, ...)
	local api = H.api()
	if not api then return nil end

	local found, fn = pcall(function() return api[name] end)
	if not found or type(fn) ~= "function" then return nil end

	local ok, value = H.gcall(fn, ...)
	if ok then return value end
	return nil
end

function H.attackGroup()
	if S.groupTried then return S.attackGroup end
	S.groupTried = true

	local value = H.call("GetCollision", LocalPlayer, "Attack")
	if type(value) == "string" then S.attackGroup = value end

	return S.attackGroup
end

function H.isModel(value)
	return typeof(value) == "Instance" and value:IsA("Model")
end

function H.modelOf(unit)
	if H.isModel(unit) then return unit end

	local api = H.api()

	if api and type(api.GetEntity) == "function" then
		local ok, model = H.gcall(function()
			local entity = api.GetEntity(unit)
			return entity and entity:GetModel()
		end)

		if ok and H.isModel(model) then return model end
	end

	local character = unit.Character
	if H.isModel(character) then return character end

	return nil
end

function H.renderOf(unit, fallback)
	local api, controller = H.api(), H.controller()
	if not (api and controller) then return fallback end

	local ok, model = H.gcall(function()
		local entity = api.FetchEntity(unit)
		local handle = entity and controller.GetController(entity)
		return handle and handle:GetCurrentModel()
	end)

	if ok and H.isModel(model) and model:IsDescendantOf(workspace) then return model end
	return fallback
end

function H.room(unit)
	local ok, value = pcall(function()
		return unit:GetAttribute("GameRoom") or unit:GetAttribute("World")
	end)
	return ok and value or nil
end

function H.sameRoom(unit)
	local mine, theirs = H.room(LocalPlayer), H.room(unit)
	return not (mine and theirs and mine ~= theirs)
end

function H.finite(value)
	return type(value) == "number" and value == value and math.abs(value) < 1e7
end

function H.healthOf(unit, model)
	local health = unit:GetAttribute("Health")
	local maximum = unit:GetAttribute("MaxHealth")

	local native = H.call("GetHealth", unit)
	if H.finite(native) then health = native end

	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	if type(health) ~= "number" then health = humanoid and humanoid.Health or 100 end
	if type(maximum) ~= "number" then maximum = humanoid and humanoid.MaxHealth or 100 end

	return math.max(0, health), math.max(1, maximum)
end

function H.isAlive(unit, health)
	if health <= 0 then return false end

	local native = H.call("IsAlive", unit)
	if native == false then return false end
	if native == nil and unit:GetAttribute("State") == "Dead" then return false end

	return true
end

function H.friendly(unit)
	local native = H.call("IsFriendly", unit)
	if type(native) == "boolean" then return native end

	local mine, theirs = LocalPlayer:GetAttribute("Team"), unit:GetAttribute("Team")
	if mine ~= nil and theirs ~= nil then return mine == theirs end

	if not (typeof(unit) == "Instance" and unit:IsA("Player")) then return false end

	return LocalPlayer.Team ~= nil and unit.Team ~= nil and LocalPlayer.Team == unit.Team
end

function H.hitbox(model, name)
	if not model then return nil end

	local collider = model:FindFirstChild("Collider")
	local wanted = (name == "UpperTorso" or name == "Torso") and "Body" or name
	local part = collider and collider:FindFirstChild(wanted, true)

	if not (part and part:IsA("BasePart")) then part = model:FindFirstChild(name) end
	if not (part and part:IsA("BasePart")) then part = model:FindFirstChild(name, true) end
	if not (part and part:IsA("BasePart")) then part = collider and collider:FindFirstChild("Head", true) end
	if not (part and part:IsA("BasePart")) then part = model:FindFirstChild("HumanoidRootPart") end
	if not (part and part:IsA("BasePart")) then part = model.PrimaryPart end

	if part and part:IsA("BasePart") then return part end
	return nil
end

function H.botName(model)
	return tostring(model:GetAttribute("DisplayName") or model.Name)
end

function H.proxy(model)
	local proxy = S.proxies[model]
	if proxy then return proxy end

	proxy = {
		Name = model.Name,
		DisplayName = H.botName(model) .. " [BOT]",
		UserId = 0,
		IsBot = true,
		Model = model,
	}

	S.proxies[model] = proxy
	return proxy
end

function H.unitOf(key)
	if type(key) == "table" then return key.Model end
	return key
end

function H.botModels()
	local list, seen = {}, {}

	local function add(model)
		if H.isModel(model) and not seen[model]
			and model:GetAttribute("_entity") == "HumanoidEntity"
			and model:IsDescendantOf(workspace)
			and not Players:GetPlayerFromCharacter(model) then
			seen[model] = true
			table.insert(list, model)
		end
	end

	local api = H.api()

	if api and type(api.Entity) == "table" and type(api.Entity.GetAll) == "function" then
		local ok, found = H.gcall(function()
			local out = {}
			local registry = api.Entity.GetAll()
			for _, entity in pairs(type(registry) == "table" and (registry._items or registry) or {}) do
				if type(entity) == "table" then
					local instance = entity.Instance
					if typeof(instance) == "Instance" then table.insert(out, instance) end
				end
			end
			return out
		end)

		if ok and type(found) == "table" then
			for _, model in ipairs(found) do add(model) end
		end
	end

	local worlds = workspace:FindFirstChild("World")

	if worlds then
		for _, world in ipairs(worlds:GetChildren()) do
			local entities = world:FindFirstChild("Entities")
			if entities then
				for _, model in ipairs(entities:GetChildren()) do add(model) end
			end
		end
	end

	return list
end

function Entity:IsTargetable(key)
	if key == LocalPlayer then return false end
	if self.Settings.TeamCheck == "Off" then return true end

	local unit = H.unitOf(key)
	if not unit then return false end

	return not H.friendly(unit)
end

function Entity:_build() end

function Entity:Refresh(player, isLocal)
	if isLocal then return end
	pcall(H.syncUnit, player, player)
end

function H.drop(key)
	local ent = Entity.Entities[key]
	if ent then
		S.owner[ent.Character] = nil
		if ent.Render then S.owner[ent.Render] = nil end
	end
	Entity:Remove(key)
end

function H.syncUnit(key, unit)
	if not unit or (typeof(unit) == "Instance" and unit.Parent == nil) then
		H.drop(key)
		return
	end

	local model = H.modelOf(unit)

	if not model or not model:IsDescendantOf(workspace) then
		H.drop(key)
		return
	end

	if F.roomCheck and not H.sameRoom(unit) then
		H.drop(key)
		return
	end

	local health, maximum = H.healthOf(unit, model)

	if not H.isAlive(unit, health) then
		H.drop(key)
		return
	end

	local head = H.hitbox(model, "Head")
	local root = model:FindFirstChild("HumanoidRootPart") or H.hitbox(model, "UpperTorso") or head

	if not (head and root) then
		H.drop(key)
		return
	end

	local ent = Entity.Entities[key]

	if ent and ent.Character ~= model then
		H.drop(key)
		ent = nil
	end

	if not ent then
		ent = {
			Player      = key,
			Character   = model,
			Humanoid    = model:FindFirstChildOfClass("Humanoid"),
			Head        = head,
			RootPart    = root,
			Team        = unit:GetAttribute("Team"),
			Targetable  = Entity:IsTargetable(key),
			Health      = health,
			MaxHealth   = maximum,
			Alive       = true,
			Connections = {},
			IsBot       = type(key) == "table",
			Unit        = unit,
			Render      = H.renderOf(unit, model),
			RenderAt    = os.clock(),
			TeamAt      = os.clock(),
		}

		S.owner[model] = ent
		if ent.Render then S.owner[ent.Render] = ent end

		Entity.Entities[key] = ent
		Entity.Added:Fire(ent)
		return
	end

	local changed = ent.Health ~= health or ent.MaxHealth ~= maximum

	ent.Health, ent.MaxHealth = health, maximum
	ent.Head, ent.RootPart = head, root

	local now = os.clock()

	if now - (ent.RenderAt or 0) > 2 then
		ent.RenderAt = now
		local render = H.renderOf(unit, model)
		if render ~= ent.Render then
			if ent.Render then S.owner[ent.Render] = nil end
			ent.Render = render
			if render then S.owner[render] = ent end
		end
	end

	if now - (ent.TeamAt or 0) > 1 then
		ent.TeamAt = now
		local targetable = Entity:IsTargetable(key)
		if targetable ~= ent.Targetable then
			ent.Targetable = targetable
			changed = true
		end
	end

	if changed then Entity.Updated:Fire(ent) end
end

function H.syncSelf()
	local model = H.modelOf(LocalPlayer)

	if model and model:IsDescendantOf(workspace) then
		Entity.Self.Alive = true
		Entity.Self.Character = model
		Entity.Self.Humanoid = model:FindFirstChildOfClass("Humanoid")
		Entity.Self.Head = H.hitbox(model, "Head")
		Entity.Self.RootPart = model:FindFirstChild("HumanoidRootPart") or Entity.Self.Head
		S.selfRender = H.renderOf(LocalPlayer, model)
	else
		Entity.Self.Alive = false
	end
end

function H.sync()
	H.syncSelf()

	local seen = {}

	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer then
			seen[player] = true
			pcall(H.syncUnit, player, player)
		end
	end

	if F.bots then
		for _, model in ipairs(H.botModels()) do
			local key = H.proxy(model)
			seen[key] = true
			pcall(H.syncUnit, key, model)
		end
	end

	for key in pairs(Entity.Entities) do
		if not seen[key] then H.drop(key) end
	end

	for model, proxy in pairs(S.proxies) do
		if not seen[proxy] and (model.Parent == nil or not F.bots) then
			S.proxies[model] = nil
		end
	end
end

task.spawn(function()
	while alive() do
		pcall(H.sync)
		task.wait(0.25)
	end
end)

H.track(Players.PlayerRemoving:Connect(function(player)
	Entity.Ids[player] = nil
	H.drop(player)
end))

function H.ownerOf(instance)
	local node = instance

	while node and node ~= workspace do
		local ent = S.owner[node]
		if ent then return ent end
		node = node.Parent
	end

	return nil
end

H.rayParams = RaycastParams.new()
H.rayParams.FilterType = Enum.RaycastFilterType.Exclude
H.rayParams.RespectCanCollide = false
H.rayParams.IgnoreWater = true

function H.ignoreList()
	local list = {}
	if Entity.Self.Character then table.insert(list, Entity.Self.Character) end
	if S.selfRender then table.insert(list, S.selfRender) end
	if LocalPlayer.Character then table.insert(list, LocalPlayer.Character) end
	return list
end

function H.canSee(ent, point)
	local camera = workspace.CurrentCamera
	if not camera then return false end

	local params = H.rayParams
	params.FilterDescendantsInstances = H.ignoreList()

	local group = S.attackGroup
	if group then pcall(function() params.CollisionGroup = group end) end

	local origin = camera.CFrame.Position
	local hit = workspace:Raycast(origin, point - origin, params)

	if not hit then return true end
	if hit.Instance:IsDescendantOf(ent.Character) then return true end
	if ent.Render and hit.Instance:IsDescendantOf(ent.Render) then return true end

	return H.ownerOf(hit.Instance) == ent
end

function H.screenOrigin()
	local camera = workspace.CurrentCamera
	if not camera then return Vector2.zero end

	local locked = UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter
	local touchOnly = UserInputService.TouchEnabled and not UserInputService.MouseEnabled

	if locked or touchOnly then return camera.ViewportSize / 2 end

	return UserInputService:GetMouseLocation() - GuiService:GetGuiInset()
end

function H.typing()
	local ok, box = pcall(function() return UserInputService:GetFocusedTextBox() end)
	return ok and box ~= nil
end

function H.silentPick()
	local camera = workspace.CurrentCamera
	if not camera then return nil end

	local center = camera.ViewportSize / 2
	local best, bestScore = nil, math.huge
	local radius = tonumber(F.silentFov) or 0

	for _, ent in ipairs(Entity:GetAll(F.silentTeam)) do
		if ent.Alive and (F.silentBots or not ent.IsBot) then
			local part = H.hitbox(ent.Character, F.silentPart)

			if part then
				local position = part.Position
				local point, onScreen = camera:WorldToViewportPoint(position)
				local range = (position - camera.CFrame.Position).Magnitude

				if onScreen and point.Z > 0 and range <= F.silentMaxDistance then
					local delta = (Vector2.new(point.X, point.Y) - center).Magnitude

					if radius <= 0 or delta <= radius then
						if not F.silentWall or H.canSee(ent, position) then
							if delta < bestScore then
								best, bestScore = { ent = ent, part = part, position = position }, delta
							end
						end
					end
				end
			end
		end
	end

	if best and F.silentHitChance < 100 and math.random(1, 100) > F.silentHitChance then
		return nil
	end

	return best
end

function H.hookTools()
	local env = getgenv and getgenv() or {}
	local hook = env.hookfunction or (type(hookfunction) == "function" and hookfunction)
	local unhook = env.restorefunction or (type(restorefunction) == "function" and restorefunction)
	local ups = env.getupvalues or (debug and debug.getupvalues)
	return hook, unhook, ups
end

function H.unhookAll()
	local _, unhook = H.hookTools()

	if type(unhook) == "function" then
		for _, fn in ipairs(S.hooks) do pcall(unhook, fn) end
		table.clear(S.hooks)
		S.silentInstalled = false
		S.rapidInstalled = false
	end
end

function H.installSilent()
	if S.silentInstalled then return true end

	local hook, _, ups = H.hookTools()
	if type(hook) ~= "function" or type(ups) ~= "function" then
		return false, "this executor has no hookfunction or getupvalues"
	end

	local ok, err = H.gcall(function()
		local client = ReplicatedStorage:WaitForChild("Client", 5)
		local cameraApi = require(client.CameraController)
		local shootable = require(client.CombatController.ClientComponent.ClientShootableComponent)

		local originState = nil
		for _, value in pairs(ups(cameraApi.GetCombatOriginFn())) do
			if type(value) == "table" and type(value.Get) == "function" and value.TempParams then
				originState = value
			end
		end

		local targeting = nil
		for _, value in pairs(ups(cameraApi.GetTargetingFn())) do
			if type(value) == "function" then
				targeting = value
				break
			end
		end

		assert(originState and targeting and type(shootable.LocalShoot) == "function", "shot pipeline not found")

		local originalOrigin
		originalOrigin = hook(originState.Get, function(...)
			local cframe, at, params = originalOrigin(...)
			local choice = S.silentChoice

			if alive() and F.silent and S.silentDepth > 0 and choice and typeof(cframe) == "CFrame" then
				return CFrame.lookAt(cframe.Position, choice.position), at, params
			end

			return cframe, at, params
		end)
		table.insert(S.hooks, originState.Get)

		local originalTargeting
		originalTargeting = hook(targeting, function(...)
			local choice = S.silentChoice

			if alive() and F.silent and S.silentDepth > 0 and choice then
				return choice.position, choice.part
			end

			return originalTargeting(...)
		end)
		table.insert(S.hooks, targeting)

		local originalShoot
		originalShoot = hook(shootable.LocalShoot, function(self, ...)
			local choice = nil

			if alive() and F.silent and not H.typing() then
				choice = H.silentPick()
			end

			if choice and F.rapid and F.silentRespect
				and type(self._LastShootTime) == "number"
				and type(self.GetTimeNow) == "function"
				and self.Holder and type(self.Holder.GetCurrentAttackRate) == "function" then
				local fine, remaining = pcall(function()
					local rate = self.Holder:GetCurrentAttackRate("Shoot")
					if type(rate) ~= "number" or rate <= 0 then return 0 end
					return 1 / rate - (self:GetTimeNow() - self._LastShootTime)
				end)

				if fine and remaining > 0.01 then return nil end
			end

			local args = table.pack(...)

			if choice and (args[1] == nil or type(args[1]) == "table") then
				local api = S.api
				local built, packet = pcall(function()
					local entity = api and api.GetEntity(choice.ent.Unit)
					if not entity or not entity.Instance then return nil end

					local pivot = entity:GetPivot(true)
					if typeof(pivot) ~= "CFrame" then return nil end

					local value = table.clone(args[1] or {})
					value.Target = entity.Instance
					value.TargetPos = pivot:PointToObjectSpace(choice.position)
					value.TargetHeadshot = choice.part.Name == "Head"
					return value
				end)

				if built and packet then
					args[1] = packet
					args.n = math.max(args.n, 1)
				end

				S.lastSilent = choice.ent
				S.lastSilentAt = os.clock()
			end

			local previous = S.silentChoice
			S.silentChoice = choice
			S.silentDepth = S.silentDepth + 1

			local result = table.pack(pcall(originalShoot, self, table.unpack(args, 1, args.n)))

			S.silentDepth = S.silentDepth - 1
			S.silentChoice = previous

			if not result[1] then error(result[2], 0) end
			return table.unpack(result, 2, result.n)
		end)
		table.insert(S.hooks, shootable.LocalShoot)
	end)

	if not ok then return false, tostring(err) end

	S.silentInstalled = true
	return true
end

function H.installRapid()
	if S.rapidInstalled then return true end

	local hook = H.hookTools()
	if type(hook) ~= "function" then return false, "this executor has no hookfunction" end

	local ok, err = H.gcall(function()
		local component = require(ReplicatedStorage.Common.CombatService.CommonComponent.CommonShootableComponent)
		assert(type(component.UpdateNextShootTime) == "function", "cooldown function not found")

		local original
		original = hook(component.UpdateNextShootTime, function(self, ...)
			local results = table.pack(original(self, ...))

			if alive() and F.rapid then
				pcall(function()
					local entity = self:GetHolderEntity()
					if entity and entity.Instance == LocalPlayer
						and self.Holder._ActionTimeCause == component.Action.Shoot then
						local now = self:GetTimeNow()
						self._NextShootTime = now
						self.Holder:SetActionTime(now, component.Action.Shoot, true)
					end
				end)
			end

			return table.unpack(results, 1, results.n)
		end)

		table.insert(S.hooks, component.UpdateNextShootTime)
	end)

	if not ok then return false, tostring(err) end

	S.rapidInstalled = true
	return true
end

function H.setProp(node, key, value)
	if not node then return end

	S.originals[node] = S.originals[node] or {}

	local ok, current = pcall(function() return node[key] end)
	if not ok then return end

	if S.originals[node][key] == nil then S.originals[node][key] = current end

	local same = current == value
		or (type(current) == "number" and type(value) == "number" and math.abs(current - value) < 0.0001)

	if not same then pcall(function() node[key] = value end) end
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

function H.updateView()
	local camera = workspace.CurrentCamera

	if camera then
		if F.fov then
			local saved = S.originals[camera] and S.originals[camera].FieldOfView
			local scoped = F.keepScope and camera.FieldOfView < 40 and camera.FieldOfView ~= F.fovValue
			if not scoped then H.setProp(camera, "FieldOfView", F.fovValue) end
			if scoped and saved then S.originals[camera].FieldOfView = saved end
		else
			H.restoreProp(camera, "FieldOfView")
		end
	end

	if F.bright then
		H.setProp(Lighting, "Brightness", 3)
		H.setProp(Lighting, "ClockTime", 14)
		H.setProp(Lighting, "GlobalShadows", false)
	else
		H.restoreProp(Lighting, "Brightness")
		H.restoreProp(Lighting, "ClockTime")
		H.restoreProp(Lighting, "GlobalShadows")
	end

	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")

	if F.noFog then
		H.setProp(Lighting, "FogStart", 99999)
		H.setProp(Lighting, "FogEnd", 100000)
		if atmosphere then
			H.setProp(atmosphere, "Density", 0)
			H.setProp(atmosphere, "Haze", 0)
		end
	else
		H.restoreProp(Lighting, "FogStart")
		H.restoreProp(Lighting, "FogEnd")
		if atmosphere then
			H.restoreProp(atmosphere, "Density")
			H.restoreProp(atmosphere, "Haze")
		end
	end
end

task.spawn(function()
	while alive() do
		pcall(H.updateView)
		task.wait(0.2)
	end
end)

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
	gui.DisplayOrder = 40
	gui.Parent = H.guiParent()

	S.gui = gui
	return gui
end

function H.clearChams()
	for key, highlight in pairs(S.chams) do
		pcall(function() highlight:Destroy() end)
		S.chams[key] = nil
	end
end

function H.updateChams()
	if not F.chams then
		H.clearChams()
		return
	end

	local used, count = {}, 0

	for key, ent in pairs(Entity.Entities) do
		if ent.Alive and count < F.chamsMax and (ent.Targetable or F.chamsAllies) then
			local adornee = ent.Render or ent.Character

			if adornee and adornee.Parent then
				count = count + 1
				used[key] = true

				local highlight = S.chams[key]
				if not highlight or not highlight.Parent then
					highlight = Instance.new("Highlight")
					highlight.FillTransparency = 0.75
					highlight.OutlineTransparency = 0.1
					highlight.Parent = H.overlay()
					S.chams[key] = highlight
				end

				local color

				if not ent.Targetable then
					color = F.chamsAlly
				elseif ent.Head and H.canSee(ent, ent.Head.Position) then
					color = F.chamsVisible
				else
					color = F.chamsHidden
				end

				highlight.Adornee = adornee
				highlight.FillColor = color
				highlight.OutlineColor = color
				highlight.DepthMode = F.chamsThrough and Enum.HighlightDepthMode.AlwaysOnTop
					or Enum.HighlightDepthMode.Occluded
			end
		end
	end

	for key, highlight in pairs(S.chams) do
		if not used[key] then
			pcall(function() highlight:Destroy() end)
			S.chams[key] = nil
		end
	end
end

task.spawn(function()
	while alive() do
		pcall(H.updateChams)
		task.wait(0.15)
	end
end)

function H.drawing(kind, props)
	local ok, object = pcall(function() return Drawing.new(kind) end)
	if not ok or not object then return nil end

	for key, value in pairs(props) do
		pcall(function() object[key] = value end)
	end

	table.insert(S.drawings, object)
	return object
end

U.silentCircle = H.drawing("Circle", {
	Visible = false, Thickness = 1, NumSides = 64, Filled = false,
	Color = Color3.fromRGB(120, 180, 255), Transparency = 0.6,
})

U.panelText = H.drawing("Text", {
	Visible = false, Size = 15, Center = true, Outline = true,
	Color = Color3.new(1, 1, 1),
})

function H.panelTarget()
	if Aimbot and Aimbot.Target then
		local ent = Entity:Get(Aimbot.Target)
		if ent and ent.Alive then return ent end
	end

	if S.lastSilent and os.clock() - S.lastSilentAt < 1.5 and S.lastSilent.Alive then
		return S.lastSilent
	end

	return nil
end

H.track(RunService.RenderStepped:Connect(function()
	if not alive() then return end

	local camera = workspace.CurrentCamera
	if not camera then return end

	if Aimbot then
		local locked = UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter
		local touchOnly = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
		Aimbot.Settings.Mode = (locked or touchOnly) and "Camera" or "Mouse"
	end

	if U.silentCircle then
		local show = F.silent and F.silentShowFov and F.silentFov > 0
		U.silentCircle.Visible = show
		if show then
			U.silentCircle.Position = camera.ViewportSize / 2
			U.silentCircle.Radius = F.silentFov
		end
	end

	if U.panelText then
		local ent = F.panel and H.panelTarget() or nil

		if ent then
			local distance = ent.RootPart and math.floor((ent.RootPart.Position - camera.CFrame.Position).Magnitude) or 0
			local visible = ent.Head and H.canSee(ent, ent.Head.Position)

			U.panelText.Text = string.format("%s   %d / %d hp   %d studs   %s",
				tostring(ent.Player.DisplayName or ent.Player.Name),
				math.floor(ent.Health or 0), math.floor(ent.MaxHealth or 100),
				distance, visible and "VISIBLE" or "behind cover")
			U.panelText.Color = visible and Color3.fromRGB(120, 255, 140) or Color3.fromRGB(255, 200, 90)
			U.panelText.Position = Vector2.new(camera.ViewportSize.X / 2, 64)
			U.panelText.Visible = true
		else
			U.panelText.Visible = false
		end
	end
end))

function H.mobileButton(show)
	if not show then
		if S.mobile then pcall(function() S.mobile:Destroy() end) end
		S.mobile = nil
		S.mobileHeld = false
		return
	end

	if S.mobile and S.mobile.Parent then return end

	local button = Instance.new("TextButton")
	button.Size = UDim2.fromOffset(74, 74)
	button.Position = UDim2.new(1, -170, 1, -230)
	button.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
	button.BackgroundTransparency = 0.25
	button.Text = "AIM"
	button.TextColor3 = Color3.new(1, 1, 1)
	button.Font = Enum.Font.GothamBold
	button.TextSize = 16
	button.AutoButtonColor = false
	button.Active = true
	button.Draggable = true
	button.Parent = H.overlay()

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = button

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 70, 70)
	stroke.Thickness = 2
	stroke.Parent = button

	button.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			S.mobileHeld = true
			stroke.Color = Color3.fromRGB(120, 255, 140)
		end
	end)

	button.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			S.mobileHeld = false
			stroke.Color = Color3.fromRGB(255, 70, 70)
		end
	end)

	S.mobile = button
end

if Aimbot then
	local originalKeyDown = Aimbot._keyDown

	function Aimbot:_keyDown()
		if F.aimAlways or S.mobileHeld then return true end
		return originalKeyDown(self)
	end

	function Aimbot:_partOf(record)
		local name = self._currentPart or self.Settings.Parts[1] or "Head"
		return H.hitbox(record.Character, name) or record.Head or record.RootPart
	end

	function Aimbot:_visiblePoint(record, part, wallCheck, multipoint)
		if wallCheck == nil then wallCheck = self.Settings.WallCheck end
		if multipoint == nil then multipoint = self.Settings.Multipoint end

		local points = { part.Position }

		if multipoint then
			local half = part.Size * 0.375
			for _, offset in ipairs({ Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 1, 0), Vector3.new(0, -1, 0) }) do
				table.insert(points, part.CFrame:PointToWorldSpace(offset * half))
			end
		end

		if not wallCheck then
			return points[math.random(1, #points)]
		end

		local clear = {}
		for _, point in ipairs(points) do
			if H.canSee(record, point) then table.insert(clear, point) end
		end

		if #clear == 0 then return nil end
		return clear[math.random(1, #clear)]
	end

	function Aimbot:_visible(record, part)
		if not self.Settings.WallCheck then return true end
		return H.canSee(record, part.Position)
	end

	function Aimbot:_aim(position)
		local camera = workspace.CurrentCamera
		if not camera then return end

		local smooth = math.clamp(tonumber(self.Settings.Smoothness) or 0.25, 0.01, 1)
		local eased = smooth
		if type(self._eased) == "function" then
			local ok, value = pcall(self._eased, self, smooth)
			if ok and type(value) == "number" then eased = value end
		end

		if type(mousemoverel) == "function" then
			local point, onScreen = camera:WorldToViewportPoint(position)
			if not onScreen or point.Z <= 0 then return end

			local delta = Vector2.new(point.X, point.Y) - H.screenOrigin()
			local sensitivity = math.clamp(tonumber(self.Settings.Sensitivity) or 0.35, 0.02, 1)

			mousemoverel(delta.X * eased * sensitivity * 2, delta.Y * eased * sensitivity * 2)
			return
		end

		local cframe = camera.CFrame
		camera.CFrame = cframe:Lerp(CFrame.lookAt(cframe.Position, position), eased)
	end
end

function H.keyHeld(key)
	if typeof(key) ~= "EnumItem" then return true end
	if H.typing() then return false end

	local ok, down = pcall(function()
		if key.EnumType == Enum.UserInputType then
			return UserInputService:IsMouseButtonPressed(key)
		end
		return UserInputService:IsKeyDown(key)
	end)

	return ok and down == true
end

function H.triggerPart(ent)
	for _, name in ipairs(F.triggerParts) do
		local part = H.hitbox(ent.Character, name)
		if part then return part end
	end
	return ent.Head or ent.RootPart
end

function H.triggerTarget()
	local camera = workspace.CurrentCamera
	if not camera then return nil end

	local center = camera.ViewportSize / 2

	if F.triggerMode == "Crosshair" then
		local params = H.rayParams
		params.FilterDescendantsInstances = H.ignoreList()

		local ray = camera:ViewportPointToRay(center.X, center.Y)
		local hit = workspace:Raycast(ray.Origin, ray.Direction * F.triggerMaxDistance, params)
		if not hit then return nil end

		return H.ownerOf(hit.Instance)
	end

	if F.triggerMode == "Target" then
		if not (Aimbot and Aimbot.Target) then return nil end
		return Entity:Get(Aimbot.Target)
	end

	local radius = F.triggerFov > 0 and F.triggerFov or 12
	local best, bestDistance = nil, radius

	for _, ent in pairs(Entity.Entities) do
		if ent.Alive then
			local part = H.triggerPart(ent)
			if part then
				local point, onScreen = camera:WorldToViewportPoint(part.Position)
				if onScreen and point.Z > 0 then
					local distance = (Vector2.new(point.X, point.Y) - center).Magnitude
					if distance <= bestDistance then best, bestDistance = ent, distance end
				end
			end
		end
	end

	return best
end

function H.triggerValid(ent)
	if not ent or not ent.Alive then return false end
	if F.triggerTeam and not ent.Targetable then return false end

	local part = H.triggerPart(ent)
	if not part then return false end

	local camera = workspace.CurrentCamera
	if (camera.CFrame.Position - part.Position).Magnitude > F.triggerMaxDistance then return false end

	if F.triggerWall and not H.canSee(ent, part.Position) then return false end

	return true
end

function H.click()
	if S.clicking then return end
	S.clicking = true

	task.spawn(function()
		pcall(function()
			if type(mouse1press) == "function" and type(mouse1release) == "function" then
				mouse1press()
				task.wait(F.triggerHold)
				mouse1release()
			else
				local input = game:GetService("VirtualInputManager")
				input:SendMouseButtonEvent(0, 0, 0, true, game, 0)
				task.wait(F.triggerHold)
				input:SendMouseButtonEvent(0, 0, 0, false, game, 0)
			end
		end)
		S.clicking = false
	end)
end

H.track(RunService.Heartbeat:Connect(function()
	if not (alive() and F.trigger) then
		S.triggerSince = nil
		return
	end

	if F.triggerRequireAim and not (Aimbot and Aimbot.Active) then
		S.triggerSince = nil
		return
	end

	if F.triggerKey and not H.keyHeld(F.triggerKey) then
		S.triggerSince = nil
		return
	end

	local ent = H.triggerTarget()

	if not H.triggerValid(ent) then
		S.triggerSince = nil
		return
	end

	local now = os.clock()

	if S.triggerSince == nil or S.triggerEnt ~= ent then
		S.triggerSince = now
		S.triggerEnt = ent
		S.triggerRolled = F.triggerHitChance >= 100 or math.random(1, 100) <= F.triggerHitChance
	end

	if now - S.triggerSince < F.triggerReaction then return end
	if not S.triggerRolled then return end
	if now - (S.triggerLast or 0) < F.triggerCooldown then return end

	S.triggerLast = now
	H.click()
end))

shared.FacilityCleanup = function()
	pcall(H.unhookAll)
	pcall(H.restoreAll)
	pcall(H.clearChams)
	pcall(H.mobileButton, false)

	for _, connection in ipairs(S.connections) do
		pcall(function() connection:Disconnect() end)
	end

	for _, object in ipairs(S.drawings) do
		pcall(function() object:Remove() end)
	end

	if S.gui then pcall(function() S.gui:Destroy() end) end

	pcall(function() Esp:Unload() end)
	if Aimbot then pcall(function() Aimbot:Unload() end) end
	if Movement then pcall(function() Movement:Unload() end) end
	pcall(function() Library:Destroy() end)
end

for _, message in ipairs(moduleErrors) do
	warn("[Facility] " .. message)
end

Entity.Settings.TeamCheck = "Team"
Esp.sharedSettings.teamCheck = "Team"
Esp.teamSettings.enemy.enabled = true
Esp.teamSettings.friendly.enabled = false
Esp.teamSettings.friendly.boxColor = { Color3.fromRGB(80, 200, 120), 1 }
Esp.teamSettings.friendly.nameColor = { Color3.fromRGB(80, 200, 120), 1 }

Esp.getBoxParts = function(model)
	local parts = {}
	local collider = model:FindFirstChild("Collider")

	if collider then
		for _, child in ipairs(collider:GetDescendants()) do
			if child:IsA("BasePart") then table.insert(parts, child) end
		end
	end

	if #parts == 0 then
		for _, child in ipairs(model:GetChildren()) do
			if child:IsA("BasePart") then table.insert(parts, child) end
		end
	end

	return parts
end

Esp.getWeapon = function()
	return nil
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

U.Combat   = Window:Tab("Combat", "crosshair")
U.Silent   = Window:Tab("Silent Aim", "target")
U.Visuals  = Window:Tab("Visuals", "eye")
U.PlayerT  = Window:Tab("Player", "user-round")
Window:TabDivider()
U.Settings = Window:Tab("Settings", "cog")

if #moduleErrors > 0 then
	U.failBox = U.Combat:Section("Modules", "full")

	for _, message in ipairs(moduleErrors) do
		U.failBox:Label(message, { Style = "dim" })
	end

	task.spawn(function()
		task.wait(1)
		for _, message in ipairs(moduleErrors) do
			Library:Error("Facility", message, 20)
		end
	end)
end

if Aimbot then

Aimbot.Settings.TeamCheck = true
Aimbot.Settings.WallCheck = true

U.aimBox = U.Combat:Section("Aimbot", 1)

U.aimBox:Toggle({
	Text = "Enable",
	Flag = "sa_aim_enable",
	Default = false,
	Callback = function(state)
		if state then
			local ok, err = pcall(function() Aimbot:Load(Entity) end)
			if not ok then
				Library:Error("Aimbot", tostring(err), 10)
				return
			end
			if type(mousemoverel) ~= "function" then
				Library:Warn("Aimbot", "No mousemoverel here, the camera is moved directly instead.", 6)
			end
		end
		Aimbot.Enabled = state
	end,
})

U.aimBox:Keybind({
	Text = "Aim Key",
	Flag = "sa_aim_key",
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
	Flag = "sa_aim_toggle_mode",
	Default = false,
	Callback = function(state) Aimbot.Settings.ToggleMode = state end,
})

U.aimBox:Toggle({
	Text = "Always On",
	Flag = "sa_aim_always",
	Default = false,
	Hint = "aims without holding the key",
	Callback = function(state) F.aimAlways = state end,
})

U.aimBox:Toggle({
	Text = "Mobile Aim Button",
	Flag = "sa_aim_mobile",
	Default = false,
	Hint = "a round button you hold with your thumb to aim",
	Callback = function(state)
		F.mobileButton = state
		H.mobileButton(state)
	end,
})

U.aimBox:Dropdown({
	Text = "Priority",
	Flag = "sa_aim_priority",
	Options = { "Cursor", "Closest", "LowestHealth" },
	Default = "Cursor",
	Callback = function(value) Aimbot.Settings.Priority = value end,
})

U.aimBox:Dropdown({
	Text = "Target Part",
	Flag = "sa_aim_parts",
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
	Flag = "sa_aim_random_part",
	Default = false,
	Callback = function(state) Aimbot.Settings.RandomPart = state end,
})
	:Gear(function(panel)
		panel:Slider({
			Text = "Interval",
			Flag = "sa_aim_random_interval",
			Min = 0.1, Max = 3, Default = 1,
			Decimals = 1,
			Suffix = " s",
			Callback = function(value) Aimbot.Settings.RandomInterval = value end,
		})
	end)

U.aimBox:Slider({
	Text = "Smoothness",
	Flag = "sa_aim_smoothness",
	Min = 0.05, Max = 1, Default = 0.3,
	Decimals = 2,
	Callback = function(value) Aimbot.Settings.Smoothness = value end,
})

U.aimBox:Slider({
	Text = "Sensitivity",
	Flag = "sa_aim_sensitivity",
	Min = 0.02, Max = 1, Default = 0.5,
	Decimals = 2,
	Callback = function(value) Aimbot.Settings.Sensitivity = value end,
})

U.aimBox:Dropdown({
	Text = "Easing Style",
	Flag = "sa_aim_easing_style",
	Options = { "Linear", "Sine", "Quad", "Cubic", "Quart", "Quint", "Exponential", "Back" },
	Default = "Quad",
	Callback = function(value) Aimbot.Settings.EasingStyle = value end,
})

U.aimBox:Dropdown({
	Text = "Easing Direction",
	Flag = "sa_aim_easing_direction",
	Options = { "In", "Out", "InOut" },
	Default = "Out",
	Callback = function(value) Aimbot.Settings.EasingDirection = value end,
})

U.aimBox:Slider({
	Text = "Switch Delay",
	Flag = "sa_aim_switch_delay",
	Min = 0, Max = 2, Default = 0,
	Decimals = 2,
	Suffix = " s",
	Callback = function(value) Aimbot.Settings.SwitchDelay = value end,
})

U.aimBox:Slider({
	Text = "Max Distance",
	Flag = "sa_aim_max_distance",
	Min = 100, Max = 5000, Default = 3000,
	Suffix = " studs",
	Callback = function(value) Aimbot.Settings.MaxDistance = value end,
})

U.fovBox = U.Combat:Section("Fov", 2)

U.fovBox:Toggle({
	Text = "Fov",
	Flag = "sa_aim_fov_enabled",
	Default = true,
	Callback = function(state)
		Aimbot.Settings.FovCheck = state
		Aimbot.Settings.FovVisible = state
	end,
})
	:ColorPicker({
		Flag = "sa_aim_fov_color",
		Default = Color3.fromRGB(255, 255, 255),
		Callback = function(color) Aimbot.Settings.FovColor = color end,
	})
	:ColorPicker({
		Flag = "sa_aim_fov_lock_color",
		Default = Color3.fromRGB(255, 70, 70),
		Callback = function(color) Aimbot.Settings.FovLockColor = color end,
	})

U.fovBox:Slider({
	Text = "Radius",
	Flag = "sa_aim_fov",
	Min = 20, Max = 600, Default = 220,
	Callback = function(value)
		Aimbot.Settings.Fov = value
		pcall(function() Aimbot:SetFov(value) end)
	end,
})

U.fovBox:Slider({
	Text = "Thickness",
	Flag = "sa_aim_fov_thickness",
	Min = 1, Max = 5, Default = 1,
	Callback = function(value) Aimbot.Settings.FovThickness = value end,
})

U.fovBox:Slider({
	Text = "Transparency",
	Flag = "sa_aim_fov_transparency",
	Min = 0, Max = 1, Default = 0.4,
	Decimals = 2,
	Callback = function(value) Aimbot.Settings.FovTransparency = value end,
})

U.fovBox:Toggle({
	Text = "Filled",
	Flag = "sa_aim_fov_filled",
	Default = false,
	Callback = function(state) Aimbot.Settings.FovFilled = state end,
})

U.behaviourBox = U.Combat:Section("Behaviour", 2)

U.behaviourBox:Toggle({
	Text = "Team Check",
	Flag = "sa_aim_team_check",
	Default = true,
	Callback = function(state) Aimbot.Settings.TeamCheck = state end,
})

U.behaviourBox:Toggle({
	Text = "Wall Check",
	Flag = "sa_aim_wall_check",
	Default = true,
	Callback = function(state) Aimbot.Settings.WallCheck = state end,
})

U.behaviourBox:Toggle({
	Text = "Multipoint",
	Flag = "sa_aim_multipoint",
	Default = false,
	Callback = function(state) Aimbot.Settings.Multipoint = state end,
})

U.behaviourBox:Slider({
	Text = "Deadzone",
	Flag = "sa_aim_deadzone",
	Min = 0, Max = 200, Default = 0,
	Callback = function(value) Aimbot.Settings.Deadzone = value end,
})

U.behaviourBox:Toggle({
	Text = "Sticky Target",
	Flag = "sa_aim_sticky",
	Default = true,
	Callback = function(state) Aimbot.Settings.Sticky = state end,
})
	:Gear(function(panel)
		panel:Slider({
			Text = "Hold Fov",
			Flag = "sa_aim_sticky_fov",
			Min = 1, Max = 3, Default = 1.6,
			Decimals = 1,
			Callback = function(value) Aimbot.Settings.StickyFov = value end,
		})
	end)

U.behaviourBox:Toggle({
	Text = "Prediction",
	Flag = "sa_aim_prediction",
	Default = false,
	Hint = "only useful if the sniper bullet has travel time",
	Callback = function(state) Aimbot.Settings.Prediction = state end,
})
	:Gear(function(panel)
		panel:Slider({
			Text = "Time",
			Flag = "sa_aim_prediction_time",
			Min = 0, Max = 0.5, Default = 0.1,
			Decimals = 2,
			Suffix = " s",
			Callback = function(value) Aimbot.Settings.PredictionTime = value end,
		})
		panel:Toggle({
			Text = "Add Ping",
			Flag = "sa_aim_prediction_ping",
			Default = false,
			Callback = function(state) Aimbot.Settings.PingPrediction = state end,
		})
	end)

U.behaviourBox:Toggle({
	Text = "Target Line",
	Flag = "sa_aim_target_line",
	Default = false,
	Callback = function(state) Aimbot.Settings.TargetLine = state end,
})
	:ColorPicker({
		Flag = "sa_aim_target_line_color",
		Default = Color3.fromRGB(255, 70, 70),
		Callback = function(color) Aimbot.Settings.TargetLineColor = color end,
	})

U.behaviourBox:Toggle({
	Text = "Target Info",
	Flag = "sa_aim_target_info",
	Default = false,
	Callback = function(state) Aimbot.Settings.TargetInfo = state end,
})

U.triggerBox = U.Combat:Section("Trigger Bot", 1)

function H.triggerKeyEnum(name)
	local mouse = {
		MB1 = Enum.UserInputType.MouseButton1,
		MB2 = Enum.UserInputType.MouseButton2,
		MB3 = Enum.UserInputType.MouseButton3,
	}

	if mouse[name] then return mouse[name] end

	local ok, code = pcall(function() return Enum.KeyCode[name] end)
	if ok and code then return code end

	return Enum.KeyCode.C
end

function H.applyTriggerKey()
	if not Library.Flags["sa_trigger_use_key"] then
		F.triggerKey = nil
		return
	end

	F.triggerKey = H.triggerKeyEnum(Library.Flags["sa_trigger_key"] or "C")
end

U.triggerBox:Toggle({
	Text = "Enable",
	Flag = "sa_trigger_enable",
	Default = false,
	Hint = "fires on its own when an enemy sits under your crosshair",
	Callback = function(state) F.trigger = state end,
})
	:Gear(function(panel)
		panel:Toggle({
			Text = "Require Aim",
			Flag = "sa_trigger_require_aim",
			Default = false,
			Callback = function(state) F.triggerRequireAim = state end,
		})
		panel:Slider({
			Text = "Hit Chance",
			Flag = "sa_trigger_hit_chance",
			Min = 0, Max = 100, Default = 100,
			Suffix = "%",
			Callback = function(value) F.triggerHitChance = tonumber(value) or 100 end,
		})
	end)

U.triggerBox:Dropdown({
	Text = "Mode",
	Flag = "sa_trigger_mode",
	Options = { "Crosshair", "Target", "Fov" },
	Default = "Crosshair",
	Callback = function(value) F.triggerMode = tostring(value) end,
})

U.triggerBox:Slider({
	Text = "Fov",
	Flag = "sa_trigger_fov",
	Min = 0, Max = 400, Default = 0,
	Callback = function(value) F.triggerFov = tonumber(value) or 0 end,
})

U.triggerBox:Toggle({
	Text = "Use Key",
	Flag = "sa_trigger_use_key",
	Default = false,
	Callback = function() H.applyTriggerKey() end,
})

U.triggerBox:Keybind({
	Text = "Trigger Key",
	Flag = "sa_trigger_key",
	Default = "C",
	Mode = "toggle",
	OnChanged = function() H.applyTriggerKey() end,
})

U.triggerBox:Slider({
	Text = "Reaction",
	Flag = "sa_trigger_reaction",
	Min = 0, Max = 0.5, Default = 0.05,
	Decimals = 2,
	Suffix = " s",
	Callback = function(value) F.triggerReaction = tonumber(value) or 0 end,
})

U.triggerBox:Slider({
	Text = "Cooldown",
	Flag = "sa_trigger_cooldown",
	Min = 0.05, Max = 2, Default = 0.3,
	Decimals = 2,
	Suffix = " s",
	Callback = function(value) F.triggerCooldown = tonumber(value) or 0.3 end,
})

U.triggerBox:Toggle({
	Text = "Wall Check",
	Flag = "sa_trigger_wall_check",
	Default = true,
	Callback = function(state) F.triggerWall = state end,
})

U.triggerBox:Toggle({
	Text = "Team Check",
	Flag = "sa_trigger_team_check",
	Default = true,
	Callback = function(state) F.triggerTeam = state end,
})

U.triggerBox:Dropdown({
	Text = "Target Part",
	Flag = "sa_trigger_parts",
	Options = { "Head", "UpperTorso", "HumanoidRootPart" },
	Default = { "Head", "UpperTorso" },
	Multi = true,
	Empty = "Head",
	Callback = function(selected)
		if #selected == 0 then selected = { "Head" } end
		F.triggerParts = selected
	end,
})

end

U.targetBox = U.Combat:Section("Targets", Aimbot and 2 or 1)

U.targetBox:Toggle({
	Text = "Include Bots",
	Flag = "sa_bots",
	Default = true,
	Callback = function(state)
		F.bots = state
		if not state then
			for key in pairs(Entity.Entities) do
				if type(key) == "table" then H.drop(key) end
			end
		end
	end,
})

U.targetBox:Toggle({
	Text = "Same Room Only",
	Flag = "sa_room_check",
	Default = true,
	Hint = "ignores players sitting in another match or the lobby",
	Callback = function(state) F.roomCheck = state end,
})

U.targetBox:Toggle({
	Text = "Target Panel",
	Flag = "sa_panel",
	Default = false,
	Hint = "name, health, distance and cover of your current target at the top of the screen",
	Callback = function(state) F.panel = state end,
})

U.targetBox:Button({
	Text = "Debug Targets",
	Callback = function()
		local players, bots, enemies = 0, 0, 0

		for _, ent in pairs(Entity.Entities) do
			if ent.IsBot then bots = bots + 1 else players = players + 1 end
			if ent.Targetable then enemies = enemies + 1 end

			print(string.format("[Facility] %s bot=%s hp=%s/%s targetable=%s model=%s render=%s",
				tostring(ent.Player.DisplayName or ent.Player.Name), tostring(ent.IsBot),
				tostring(ent.Health), tostring(ent.MaxHealth), tostring(ent.Targetable),
				ent.Character and ent.Character:GetFullName() or "nil",
				ent.Render and ent.Render:GetFullName() or "nil"))
		end

		print("[Facility] entity api " .. tostring(H.api() ~= nil)
			.. " | controller " .. tostring(H.controller() ~= nil)
			.. " | attack group " .. tostring(H.attackGroup())
			.. " | my room " .. tostring(H.room(LocalPlayer)))

		Library:Notify("Facility", string.format("%d players, %d bots, %d enemies. Details in the console.",
			players, bots, enemies), 8)
	end,
})

U.silentBox = U.Silent:Section("Silent Aim", 1)

U.silentBox:Toggle({
	Text = "Enable",
	Flag = "sa_silent",
	Default = false,
	Hint = "every shot you fire lands on the best target, the camera never moves",
	Callback = function(state)
		if state then
			H.attackGroup()
			local ok, err = H.installSilent()
			if not ok then
				F.silent = false
				Library:Error("Silent Aim", "Unavailable: " .. tostring(err), 8)
				return
			end
		end
		F.silent = state
	end,
})

U.silentBox:Dropdown({
	Text = "Aim Part",
	Flag = "sa_silent_part",
	Options = { "Head", "UpperTorso", "HumanoidRootPart" },
	Default = "Head",
	Callback = function(value) F.silentPart = tostring(value) end,
})

U.silentBox:Slider({
	Text = "Fov",
	Flag = "sa_silent_fov",
	Min = 0, Max = 800, Default = 250,
	ZeroText = "0 - whole screen",
	Callback = function(value) F.silentFov = tonumber(value) or 0 end,
})

U.silentBox:Toggle({
	Text = "Show Fov",
	Flag = "sa_silent_show_fov",
	Default = true,
	Callback = function(state) F.silentShowFov = state end,
})
	:ColorPicker({
		Flag = "sa_silent_fov_color",
		Default = Color3.fromRGB(120, 180, 255),
		Callback = function(color)
			if U.silentCircle then U.silentCircle.Color = color end
		end,
	})

U.silentBox:Slider({
	Text = "Hit Chance",
	Flag = "sa_silent_hit_chance",
	Min = 0, Max = 100, Default = 100,
	Suffix = "%",
	Callback = function(value) F.silentHitChance = tonumber(value) or 100 end,
})

U.silentBox:Slider({
	Text = "Max Distance",
	Flag = "sa_silent_max_distance",
	Min = 100, Max = 5000, Default = 3000,
	Suffix = " studs",
	Callback = function(value) F.silentMaxDistance = tonumber(value) or 3000 end,
})

U.silentCheck = U.Silent:Section("Checks", 2)

U.silentCheck:Toggle({
	Text = "Wall Check",
	Flag = "sa_silent_wall",
	Default = true,
	Hint = "only redirects onto targets the shot can actually reach",
	Callback = function(state) F.silentWall = state end,
})

U.silentCheck:Toggle({
	Text = "Team Check",
	Flag = "sa_silent_team",
	Default = true,
	Callback = function(state) F.silentTeam = state end,
})

U.silentCheck:Toggle({
	Text = "Target Bots",
	Flag = "sa_silent_bots",
	Default = true,
	Callback = function(state) F.silentBots = state end,
})

U.rapidBox = U.Silent:Section("Fire Rate", 2)

U.rapidBox:Toggle({
	Text = "No Shot Delay",
	Flag = "sa_rapid",
	Default = false,
	Hint = "removes the client cooldown, the server still enforces the real fire rate",
	Callback = function(state)
		if state then
			local ok, err = H.installRapid()
			if not ok then
				F.rapid = false
				Library:Error("Fire Rate", "Unavailable: " .. tostring(err), 8)
				return
			end
		end
		F.rapid = state
	end,
})

U.rapidBox:Toggle({
	Text = "Respect Server Rate",
	Flag = "sa_silent_respect",
	Default = true,
	Hint = "drops silent shots fired before the weapon is ready, so the server never sees an impossible rate",
	Callback = function(state) F.silentRespect = state end,
})

U.rapidBox:Label("The server keeps the real fire rate, extra shots are simply ignored. Keep Respect Server Rate on so no impossible shot ever reaches it.", { Style = "dim" })

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
	Flag = "sa_esp_enable",
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
	:Keybind({ Default = "RightAlt", Flag = "sa_esp_enable_key" })

U.espBox:Toggle({
	Text = "Box",
	Flag = "sa_esp_box",
	Default = true,
	Callback = function(state) H.espSet("box", state) end,
})
	:ColorPicker({
		Flag = "sa_esp_box_color",
		Default = Color3.fromRGB(74, 146, 255),
		Callback = function(color, alpha)
			H.espPair("boxColor", color, alpha)
			H.espPair("box3dColor", color, alpha)
		end,
	})
	:Gear(function(panel)
		panel:Dropdown({
			Text = "Style",
			Flag = "sa_esp_box_style",
			Options = { "2D", "3D" },
			Default = "2D",
			Callback = function(value)
				H.espSet("box", value == "2D")
				H.espSet("box3d", value == "3D")
			end,
		})
	end)

U.espBox:Toggle({
	Text = "Health Bar",
	Flag = "sa_esp_health_bar",
	Default = true,
	Callback = function(state) H.espSet("healthBar", state) end,
})
	:ColorPicker({
		Flag = "sa_esp_health_healthy",
		Default = Color3.fromRGB(82, 197, 148),
		Callback = function(color) H.espSet("healthyColor", color) end,
	})
	:ColorPicker({
		Flag = "sa_esp_health_dying",
		Default = Color3.fromRGB(240, 90, 102),
		Callback = function(color) H.espSet("dyingColor", color) end,
	})

U.espBox:Toggle({
	Text = "Tracers",
	Flag = "sa_esp_tracer",
	Default = false,
	Callback = function(state) H.espSet("tracer", state) end,
})
	:ColorPicker({
		Flag = "sa_esp_tracer_color",
		Default = Color3.new(1, 1, 1),
		Callback = function(color, alpha) H.espPair("tracerColor", color, alpha) end,
	})

U.espBox:Toggle({
	Text = "Off Screen Arrow",
	Flag = "sa_esp_arrow",
	Default = false,
	Callback = function(state) H.espSet("offScreenArrow", state) end,
})
	:ColorPicker({
		Flag = "sa_esp_arrow_color",
		Default = Color3.new(1, 1, 1),
		Callback = function(color, alpha) H.espPair("offScreenArrowColor", color, alpha) end,
	})

U.displayBox = U.Visuals:Section("Display", 2)

U.displayBox:Toggle({
	Text = "Name",
	Flag = "sa_esp_name",
	Default = true,
	Callback = function(state) H.espSet("name", state) end,
})
	:ColorPicker({
		Flag = "sa_esp_name_color",
		Default = Color3.fromRGB(236, 241, 250),
		Callback = function(color, alpha) H.espPair("nameColor", color, alpha) end,
	})

U.displayBox:Toggle({
	Text = "Distance",
	Flag = "sa_esp_distance",
	Default = true,
	Callback = function(state) H.espSet("distance", state) end,
})
	:ColorPicker({
		Flag = "sa_esp_distance_color",
		Default = Color3.fromRGB(170, 184, 205),
		Callback = function(color, alpha) H.espPair("distanceColor", color, alpha) end,
	})

U.displayBox:Toggle({
	Text = "Health",
	Flag = "sa_esp_health_text",
	Default = false,
	Callback = function(state) H.espSet("healthText", state) end,
})

U.displayBox:Slider({
	Text = "Text Size",
	Flag = "sa_esp_text_size",
	Min = 8, Max = 24, Default = 13,
	Callback = function(value) Esp.sharedSettings.textSize = value end,
})

U.displayBox:Slider({
	Text = "Max Distance",
	Flag = "sa_esp_max_distance",
	Min = 100, Max = 5000, Default = 1500,
	Suffix = " studs",
	Callback = function(value) H.espSet("maxDistance", value) end,
})

U.displayBox:Toggle({
	Text = "Show Allies",
	Flag = "sa_esp_allies",
	Default = false,
	Callback = function(state) Esp.teamSettings.friendly.enabled = state end,
})

U.chamsBox = U.Visuals:Section("Chams", 1)

U.chamsBox:Toggle({
	Text = "Enable",
	Flag = "sa_chams",
	Default = false,
	Hint = "outlines the real visible model, colour switches when the target is behind cover",
	Callback = function(state) F.chams = state end,
})

U.chamsBox:Toggle({
	Text = "Visible",
	Flag = "sa_chams_visible_toggle",
	Default = true,
	Callback = function() end,
})
	:ColorPicker({
		Flag = "sa_chams_visible",
		Default = Color3.fromRGB(255, 70, 70),
		Callback = function(color) F.chamsVisible = color end,
	})

U.chamsBox:Toggle({
	Text = "Behind Cover",
	Flag = "sa_chams_hidden_toggle",
	Default = true,
	Callback = function() end,
})
	:ColorPicker({
		Flag = "sa_chams_hidden",
		Default = Color3.fromRGB(255, 200, 60),
		Callback = function(color) F.chamsHidden = color end,
	})

U.chamsBox:Toggle({
	Text = "Allies",
	Flag = "sa_chams_allies",
	Default = false,
	Callback = function(state) F.chamsAllies = state end,
})
	:ColorPicker({
		Flag = "sa_chams_ally_color",
		Default = Color3.fromRGB(80, 200, 120),
		Callback = function(color) F.chamsAlly = color end,
	})

U.chamsBox:Toggle({
	Text = "Through Walls",
	Flag = "sa_chams_through",
	Default = true,
	Callback = function(state) F.chamsThrough = state end,
})

U.chamsBox:Slider({
	Text = "Max Highlights",
	Flag = "sa_chams_max",
	Min = 1, Max = 30, Default = 24,
	Callback = function(value) F.chamsMax = tonumber(value) or 24 end,
})

if Movement then

Movement.Settings.WalkSpeedMode = "Velocity"
Movement.Settings.JumpMode = "Humanoid"

U.moveBox = U.PlayerT:Section("Movement", 1)

U.moveBox:Toggle({
	Text = "Walk Speed",
	Flag = "sa_walkspeed",
	Default = false,
	Callback = function(state)
		Movement:WalkSpeed(state and Movement.Settings.WalkSpeed or 16)
	end,
})

U.moveBox:Slider({
	Text = "Speed",
	Flag = "sa_walkspeed_value",
	Min = 8, Max = 100, Default = 24,
	Callback = function(value)
		Movement.Settings.WalkSpeed = value
		if Library.Flags["sa_walkspeed"] then Movement:WalkSpeed(value) end
	end,
})

U.moveBox:Toggle({
	Text = "Jump Power",
	Flag = "sa_jump",
	Default = false,
	Callback = function(state)
		Movement:JumpPower(state and Movement.Settings.JumpPower or 50)
	end,
})

U.moveBox:Slider({
	Text = "Power",
	Flag = "sa_jump_value",
	Min = 20, Max = 150, Default = 60,
	Callback = function(value)
		Movement.Settings.JumpPower = value
		if Library.Flags["sa_jump"] then Movement:JumpPower(value) end
	end,
})

U.moveBox:Toggle({
	Text = "Infinite Jump",
	Flag = "sa_infjump",
	Default = false,
	Callback = function(state) Movement:InfiniteJump(state) end,
})

U.moveBox:Toggle({
	Text = "Noclip",
	Flag = "sa_noclip",
	Default = false,
	Callback = function(state) Movement:Noclip(state) end,
})
	:Keybind({ Default = "N", Flag = "sa_noclip_key" })

U.moveBox:Toggle({
	Text = "Fly",
	Flag = "sa_fly",
	Default = false,
	Callback = function(state) Movement:Fly(state) end,
})
	:Keybind({ Default = "F", Flag = "sa_fly_key" })

U.moveBox:Slider({
	Text = "Fly Speed",
	Flag = "sa_fly_speed",
	Min = 1, Max = 20, Default = 2,
	Decimals = 1,
	Callback = function(value) Movement.Settings.FlySpeed = value end,
})

end

U.viewBox = U.PlayerT:Section("View", 2)

U.viewBox:Toggle({
	Text = "Field Of View",
	Flag = "sa_fov",
	Default = false,
	Callback = function(state) F.fov = state end,
})

U.viewBox:Slider({
	Text = "Value",
	Flag = "sa_fov_value",
	Min = 50, Max = 120, Default = 85,
	Callback = function(value) F.fovValue = tonumber(value) or 85 end,
})

U.viewBox:Toggle({
	Text = "Keep Scope Zoom",
	Flag = "sa_keep_scope",
	Default = true,
	Hint = "leaves the camera alone while you are scoped in",
	Callback = function(state) F.keepScope = state end,
})

U.viewBox:Toggle({
	Text = "Fullbright",
	Flag = "sa_bright",
	Default = false,
	Callback = function(state) F.bright = state end,
})

U.viewBox:Toggle({
	Text = "No Fog",
	Flag = "sa_nofog",
	Default = false,
	Callback = function(state) F.noFog = state end,
})

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
SaveManager:SetFolder("Facility/122446657157717")

InterfaceManager:BuildInterfaceSection(U.Settings, 1)
SaveManager:BuildConfigSection(U.Settings, 2)
ThemeManager:Mount(Window)

Window:SetTab(U.Combat)

Library:Notify("Facility", "Sniper Arena loaded.", 4)

SaveManager:LoadAutoloadConfig()
ThemeManager:Load()
