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

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local Lighting = game:GetService("Lighting")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local H = {}
local U = {}
local S = {
	connections = {}, drawings = {}, instances = {}, threads = {}, originals = {},
	chams = {}, dots = {}, gunBackup = {}, activeGun = nil, friendlyFn = nil,
	targetPoint = nil, firing = false,
}

local F = {
	teamMode = "Game", dummies = true,

	silent = false, silentMethod = "MultiRaycast", silentFov = 120, silentShowFov = false, silentPart = "Head",
	silentRange = 2000, silentLead = 0, silentWall = false, silentFiring = false, silentHitChance = 100,

	trigger = false, triggerTeam = true, triggerDelay = 0, triggerMode = "Crosshair", triggerFov = 0,

	walkSpeed = false, walkSpeedValue = 35,

	noRecoil = false, noSpread = false, rapidFire = false, autoFire = false, fastReload = false,

	meleeAura = false, meleeRange = 15, infiniteSlide = false, spinbot = false, spinbotSpeed = 90,
	autoGlass = false, instantRespawn = false,

	chams = false, chamsVisible = Color3.fromRGB(255, 255, 255), chamsHidden = Color3.fromRGB(140, 140, 140),
	chamsAllies = false, chamsAlly = Color3.fromRGB(80, 200, 120), chamsThrough = true,
	tightBox = true,
	headDots = false, headDotColor = Color3.fromRGB(255, 255, 255),
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

function H.findFriendlyFn()
	if type(filtergc) == "function" then
		local ok, found = pcall(filtergc, "function", { Name = "IsPlayerFriendly" }, true)
		if ok and type(found) == "function" then return found end
	end

	if type(getgc) ~= "function" or type(debug.getinfo) ~= "function" then return nil end

	for _, item in ipairs(getgc(false)) do
		if type(item) == "function" and (type(islclosure) ~= "function" or islclosure(item)) then
			local ok, info = pcall(debug.getinfo, item)
			if ok and info and info.name == "IsPlayerFriendly" then return item end
		end
	end

	return nil
end

function H.enemy(player)
	if player == LocalPlayer then return false end
	if F.teamMode == "Off" then return true end

	if F.teamMode == "Game" and S.friendlyFn then
		local ok, friendly = pcall(S.friendlyFn, player)
		if ok and type(friendly) == "boolean" then return not friendly end
	end

	if LocalPlayer.Team == nil or player.Team == nil then return true end
	return player.Team ~= LocalPlayer.Team
end

function H.setTeamMode(mode)
	F.teamMode = mode
	local mapped = mode == "Game" and "Team" or mode
	pcall(function() Entity.Settings.TeamCheck = mapped end)
	pcall(function() Esp.sharedSettings.teamCheck = mapped end)
end

task.spawn(function()
	local ok, found = H.gcall(H.findFriendlyFn)
	if ok and type(found) == "function" then S.friendlyFn = found end
end)

function H.module(path)
	return H.gcall(function()
		local node = ReplicatedStorage
		for part in string.gmatch(path, "[^%.]+") do
			node = node:WaitForChild(part, 5)
		end
		return require(node)
	end)
end

function H.remote(path)
	local node = ReplicatedStorage:FindFirstChild("Remotes")
	for part in string.gmatch(path, "[^%.]+") do
		if not node then return nil end
		node = node:FindFirstChild(part)
	end
	return node
end

function H.fire(path, ...)
	local remote = H.remote(path)
	if not remote then return false end
	local args = table.pack(...)
	return pcall(function() remote:FireServer(table.unpack(args, 1, args.n)) end)
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

S.rayParams = RaycastParams.new()
S.rayParams.FilterType = Enum.RaycastFilterType.Exclude

function H.isDummy(model)
	if not model:IsA("Model") then return false end
	local ok, tagged = pcall(function() return model:HasTag("Dummy") end)
	return (ok and tagged) or string.find(string.lower(model.Name), "dummy", 1, true) ~= nil
end

S.dummies = { list = {}, at = 0 }

function H.dummyList()
	if os.clock() - S.dummies.at < 2 then return S.dummies.list end
	S.dummies.at = os.clock()

	local list = {}
	for _, item in ipairs(workspace:GetDescendants()) do
		if item:IsA("Model") and item:FindFirstChild("Head") and item:FindFirstChildOfClass("Humanoid") and H.isDummy(item) then
			table.insert(list, item)
		end
	end

	S.dummies.list = list
	return list
end

function H.targets(teamCheck)
	local list = {}

	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if player ~= LocalPlayer and character and character:FindFirstChild("Head") and H.aliveChar(character) then
			local humanoid = H.humanoid(character)
			local dead = false
			pcall(function() dead = humanoid:HasTag("Dead") end)
			if not dead and (not teamCheck or H.enemy(player)) then
				table.insert(list, { model = character, player = player })
			end
		end
	end

	if F.dummies then
		for _, model in ipairs(H.dummyList()) do
			if model.Parent and H.aliveChar(model) then table.insert(list, { model = model }) end
		end
	end

	return list
end

function H.visible(model, part)
	local camera = workspace.CurrentCamera
	if not camera then return false end

	S.rayParams.FilterDescendantsInstances = { LocalPlayer.Character, camera, model }
	pcall(function() S.rayParams.CollisionGroup = "BulletsAndProjectiles" end)

	local origin = camera.CFrame.Position
	local hit = workspace:Raycast(origin, part.Position - origin, S.rayParams)
	pcall(function() S.rayParams.CollisionGroup = "Default" end)
	return hit == nil
end

function H.silentPick()
	local camera = workspace.CurrentCamera
	if not camera then return nil end

	local mouse = UserInputService:GetMouseLocation()
	local origin = camera.CFrame.Position
	local bestPoint, bestDistance = nil, F.silentFov

	for _, target in ipairs(H.targets(true)) do
		local part = target.model:FindFirstChild(F.silentPart) or target.model:FindFirstChild("Head")
		if part and (part.Position - origin).Magnitude <= F.silentRange then
			local screen, onScreen = camera:WorldToViewportPoint(part.Position)
			if onScreen and screen.Z > 0 then
				local distance = (Vector2.new(screen.X, screen.Y) - mouse).Magnitude
				if distance < bestDistance and (not F.silentWall or H.visible(target.model, part)) then
					bestDistance = distance
					bestPoint = part.Position + part.AssemblyLinearVelocity * (F.silentLead / 1000)
				end
			end
		end
	end

	return bestPoint
end

H.track(RunService.RenderStepped:Connect(function()
	if not F.silent then
		S.targetPoint = nil
		return
	end
	local ok, point = pcall(H.silentPick)
	S.targetPoint = ok and point or nil
end))

function H.shouldRedirect()
	if not F.silent or not S.targetPoint then return false end
	if F.silentFiring and not S.firing then return false end
	if F.silentHitChance < 100 and math.random(1, 100) > F.silentHitChance then return false end
	return true
end

function H.installMultiRaycast()
	if S.multiHooked then return true end
	if type(hookfunction) ~= "function" then return false end

	local ok, module = H.module("Modules.Misc.MultiRaycast")
	if not ok then return false end

	local target = module
	if type(module) == "table" then
		for _, value in pairs(module) do
			if type(value) == "function" then target = value break end
		end
	end
	if type(target) ~= "function" then return false end

	local old
	local hooked, err = pcall(function()
		old = hookfunction(target, function(origin, direction, ...)
			if alive() and F.silentMethod == "MultiRaycast" and H.shouldRedirect()
				and typeof(origin) == "Vector3" and typeof(direction) == "Vector3" then
				local aim = S.targetPoint - origin
				if aim.Magnitude > 1 then
					direction = aim.Unit * math.max(direction.Magnitude, aim.Magnitude + 2)
				end
			end
			return old(origin, direction, ...)
		end)
	end)

	if not hooked then
		H.notify("Silent Aim", tostring(err), 5)
		return false
	end

	S.multiHooked = true
	return true
end

function H.setSilent(state)
	F.silent = state
	if not state then return true end

	local installed = true
	if F.silentMethod == "MultiRaycast" then
		installed = H.installMultiRaycast()
		if not installed then H.notify("Silent Aim", "MultiRaycast hook unavailable, try the Gun Fire method.", 6) end
	else
		installed = H.installGunPatches()
	end

	if not installed then F.silent = false end
	return installed
end

U.silentCircle = H.drawing("Circle", {
	Visible = false, Color = Color3.fromRGB(255, 255, 255), Filled = false, Thickness = 1.5, NumSides = 64, Transparency = 1,
})

H.track(RunService.RenderStepped:Connect(function()
	if not U.silentCircle then return end
	local show = F.silent and F.silentShowFov
	U.silentCircle.Visible = show
	if show then
		U.silentCircle.Position = UserInputService:GetMouseLocation()
		U.silentCircle.Radius = F.silentFov
	end
end))

function H.gunApply(gun)
	if type(gun) ~= "table" or type(gun.Config) ~= "table" then return end

	local backup = S.gunBackup[gun]
	if not backup then
		backup = {
			Firerate = gun.Config.Firerate,
			ReloadTime = gun.Config.ReloadTime,
			Modes = type(gun.Config.Modes) == "table" and table.clone(gun.Config.Modes) or nil,
			FiringMode = gun.FiringMode,
		}
		S.gunBackup[gun] = backup
	end

	gun.Config.Firerate = F.rapidFire and 25 or backup.Firerate
	gun.Config.ReloadTime = F.fastReload and 0.05 or backup.ReloadTime

	if F.autoFire then
		gun.FiringMode = "Automatic"
		if type(gun.Config.Modes) == "table" and not table.find(gun.Config.Modes, "Automatic") then
			table.insert(gun.Config.Modes, "Automatic")
		end
	else
		gun.FiringMode = backup.FiringMode
		if backup.Modes then gun.Config.Modes = table.clone(backup.Modes) end
	end
end

function H.gunRestore()
	for gun, backup in pairs(S.gunBackup) do
		pcall(function()
			gun.Config.Firerate = backup.Firerate
			gun.Config.ReloadTime = backup.ReloadTime
			gun.FiringMode = backup.FiringMode
			if backup.Modes then gun.Config.Modes = table.clone(backup.Modes) end
		end)
	end
	table.clear(S.gunBackup)
end

function H.findActiveGun()
	if type(getgc) ~= "function" then return nil end
	local character = LocalPlayer.Character
	for _, item in ipairs(getgc(true)) do
		if type(item) == "table" and rawget(item, "Config") and rawget(item, "weaponTool") and rawget(item, "CurAmmo") then
			local tool = rawget(item, "weaponTool")
			if typeof(tool) == "Instance" and tool.Parent == character then return item end
		end
	end
	return nil
end

function H.installGunPatches()
	if S.gunPatched then return true end

	local okGun, Gun = H.module("Modules.Controllers.WeaponController.Gun")
	local okCam, CameraController = H.module("Modules.Controllers.CameraController")

	if not okGun or type(Gun) ~= "table" then
		H.notify("Guns", "Gun controller not found.", 5)
		return false
	end

	S.gunModule, S.camModule = Gun, okCam and CameraController or nil
	S.gunOriginal = { new = Gun.new, Equip = Gun.Equip, CalculateSpread = Gun.CalculateSpread, Fire = Gun.Fire }

	local original = S.gunOriginal

	if type(original.new) == "function" then
		Gun.new = function(...)
			local object = original.new(...)
			S.activeGun = object
			pcall(H.gunApply, object)
			return object
		end
	end

	if type(original.Equip) == "function" then
		Gun.Equip = function(self, ...)
			S.activeGun = self
			pcall(H.gunApply, self)
			return original.Equip(self, ...)
		end
	end

	if type(original.CalculateSpread) == "function" then
		Gun.CalculateSpread = function(self, ...)
			if alive() and F.noSpread then
				pcall(function() self.Crosshair:SetSpread(0) end)
				self.CurSpread = 0
				return 0
			end
			return original.CalculateSpread(self, ...)
		end
	end

	if type(original.Fire) == "function" then
		Gun.Fire = function(self, ...)
			local camera = workspace.CurrentCamera
			local redirect = alive() and F.silentMethod == "Gun Fire" and H.shouldRedirect() and camera ~= nil
			local oldCFrame = camera and camera.CFrame
			local oldSpread

			if alive() and F.noSpread then
				pcall(function()
					oldSpread = self.Crosshair.LerpedSpread
					self.Crosshair.LerpedSpread = 0
				end)
			end

			if redirect then camera.CFrame = CFrame.lookAt(camera.CFrame.Position, S.targetPoint) end

			local results = table.pack(pcall(original.Fire, self, ...))

			if redirect and oldCFrame then camera.CFrame = oldCFrame end
			if oldSpread ~= nil then pcall(function() self.Crosshair.LerpedSpread = oldSpread end) end

			if not results[1] then error(results[2], 0) end
			return table.unpack(results, 2, results.n)
		end
	end

	if S.camModule and type(S.camModule.Recoil) == "function" then
		local recoil = S.camModule.Recoil
		S.camOriginalRecoil = recoil
		S.camModule.Recoil = function(self, ...)
			if alive() and F.noRecoil then return end
			return recoil(self, ...)
		end
	end

	S.gunPatched = true
	return true
end

function H.uninstallGunPatches()
	if S.gunModule and S.gunOriginal then
		for key, value in pairs(S.gunOriginal) do
			pcall(function() S.gunModule[key] = value end)
		end
	end
	if S.camModule and S.camOriginalRecoil then
		pcall(function() S.camModule.Recoil = S.camOriginalRecoil end)
	end
	S.gunPatched = false
end

function H.gunsWanted()
	return F.noRecoil or F.noSpread or F.rapidFire or F.autoFire or F.fastReload
end

function H.refreshGuns()
	if H.gunsWanted() then H.installGunPatches() end
	local gun = S.activeGun
	if gun then pcall(H.gunApply, gun) end
end

H.loop(0.1, function()
	if not (F.rapidFire or F.autoFire or F.fastReload) then
		if next(S.gunBackup) then H.gunRestore() end
		return
	end

	local gun = S.activeGun
	if not gun or not gun.weaponTool or gun.weaponTool.Parent ~= LocalPlayer.Character then
		local ok, found = H.gcall(H.findActiveGun)
		gun = ok and found or nil
		S.activeGun = gun
	end

	if gun then pcall(H.gunApply, gun) end
end)

S.trigger = { holding = false, tap = 0, seen = 0 }

function H.triggerValid(model, player)
	if not model or not H.aliveChar(model) then return nil end
	if player then
		if player == LocalPlayer then return nil end
		if F.triggerTeam and not H.enemy(player) then return nil end
		return model
	end
	if F.dummies and H.isDummy(model) then return model end
	return nil
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
	if not (F.trigger and H.aliveChar()) then
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

H.loop(0.1, function()
	if not F.meleeAura then return end
	local root = H.root()
	local remote = H.remote("Weapons.Melee.Swing")
	if not (root and remote) then return end

	for _, target in ipairs(H.targets(true)) do
		local other = H.root(target.model)
		local humanoid = H.humanoid(target.model)
		if other and humanoid and humanoid.Health > 0 and (other.Position - root.Position).Magnitude <= F.meleeRange then
			local payload = buffer.create(1)
			buffer.writeu8(payload, 0, 1)
			pcall(function() remote:FireServer(workspace:GetServerTimeNow(), humanoid, payload) end)
		end
	end
end)

S.walk = { module = nil }

function H.walkHandler()
	if S.walk.module then return S.walk.module end
	local ok, module = H.module("Modules.Controllers.CharacterController.WalkspeedHandler")
	if ok and type(module) == "table" then S.walk.module = module end
	return S.walk.module
end

function H.applyWalk(value)
	local handler = H.walkHandler()
	if not handler then return false end
	pcall(function()
		handler.Walkspeed = value
		if handler.Humanoid then handler.Humanoid.WalkSpeed = value end
	end)
	return true
end

function H.setWalk(state)
	F.walkSpeed = state
	if not H.applyWalk(state and F.walkSpeedValue or 18) then
		H.notify("WalkSpeed", "Walkspeed handler not found.", 4)
	end
end

H.loop(0.3, function()
	if F.walkSpeed then H.applyWalk(F.walkSpeedValue) end
end)

H.loop(0.15, function()
	if not F.infiniteSlide then return end
	local humanoid, root = H.humanoid(), H.root()
	if not (humanoid and root) or humanoid.MoveDirection.Magnitude <= 0 then return end
	H.fire("Character.CharacterStateReplication.Sliding", true)
	root.AssemblyLinearVelocity = root.AssemblyLinearVelocity + humanoid.MoveDirection * 4
end)

S.spin = { angle = 0, joint = nil, c0 = nil }

function H.rootJoint(character)
	local root = H.root(character)
	local lower = character:FindFirstChild("LowerTorso")
	return (root and root:FindFirstChild("RootJoint")) or (lower and lower:FindFirstChild("Root")) or (lower and lower:FindFirstChild("RootJoint"))
end

function H.spinReset()
	if S.spin.joint and S.spin.c0 then pcall(function() S.spin.joint.C0 = S.spin.c0 end) end
	S.spin.joint, S.spin.c0 = nil, nil
end

H.track(RunService.RenderStepped:Connect(function(dt)
	local character = LocalPlayer.Character
	if not F.spinbot or not character then
		if S.spin.joint then H.spinReset() end
		return
	end

	local joint = H.rootJoint(character)
	if not joint then return end

	if S.spin.joint ~= joint then
		S.spin.joint, S.spin.c0 = joint, joint.C0
	end

	S.spin.angle = (S.spin.angle + dt * F.spinbotSpeed * 10) % 360
	joint.C0 = CFrame.new(S.spin.c0.Position) * CFrame.Angles(0, math.rad(S.spin.angle), 0) * S.spin.c0.Rotation
end))

function H.shatterGlass()
	local remote = H.remote("Other.GlassBreak")
	if not remote then
		H.notify("Glass", "GlassBreak remote not found.", 4)
		return
	end

	local count = 0
	for index, part in ipairs(workspace:GetDescendants()) do
		if index % 400 == 0 then task.wait() end
		if part:IsA("BasePart") then
			local tagged = false
			pcall(function() tagged = part:HasTag("Glass") end)
			if tagged or part.Name == "Glass" then
				count = count + 1
				pcall(function() remote:FireServer(part, part.Position, Vector3.new(0, 1, 0)) end)
			end
		end
	end
	return count
end

H.track(LocalPlayer.CharacterAdded:Connect(function()
	if not F.autoGlass then return end
	task.wait(1.2)
	if alive() and F.autoGlass then H.shatterGlass() end
end))

H.loop(0.2, function()
	if not F.instantRespawn then return end
	local humanoid = H.humanoid()
	if humanoid and humanoid.Health <= 0 then
		H.fire("Match.FFA.NextSpawn")
		H.fire("Character.Respawned")
	end
end)

function H.trampoline()
	local range = workspace:FindFirstChild("ShootingRange")
	local node = range and range:FindFirstChild("Interactable")
	node = node and node:FindFirstChild("Trampolines")
	node = node and node:FindFirstChild("Trampoline")
	node = node and node:FindFirstChild("BouncePad")
	local remote = node and node:FindFirstChild("use")

	if not remote then
		H.notify("Trampoline", "Only works in the shooting range lobby.", 4)
		return
	end

	pcall(function() remote:FireServer() end)
	local root = H.root()
	if root then root.CFrame = root.CFrame + Vector3.new(0, 5, 0) end
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

	local used = {}

	for _, target in ipairs(H.targets(false)) do
		local enemy = target.player == nil or H.enemy(target.player)
		if enemy or F.chamsAllies then
			local model = target.model
			used[model] = true

			local highlight = S.chams[model]
			if not highlight or not highlight.Parent then
				highlight = Instance.new("Highlight")
				highlight.FillTransparency = 0.7
				highlight.OutlineTransparency = 0.1
				highlight.Parent = H.overlay()
				S.chams[model] = highlight
			end

			local head = model:FindFirstChild("Head")
			local color
			if not enemy then
				color = F.chamsAlly
			elseif head and H.visible(model, head) then
				color = F.chamsVisible
			else
				color = F.chamsHidden
			end

			highlight.Adornee = model
			highlight.FillColor = color
			highlight.OutlineColor = color
			highlight.DepthMode = F.chamsThrough and Enum.HighlightDepthMode.AlwaysOnTop or Enum.HighlightDepthMode.Occluded
		end
	end

	for model, highlight in pairs(S.chams) do
		if not used[model] then
			pcall(function() highlight:Destroy() end)
			S.chams[model] = nil
		end
	end
end

H.loop(0.15, H.updateChams)

function H.clearDots()
	for model, dot in pairs(S.dots) do
		pcall(function() dot:Remove() end)
		S.dots[model] = nil
	end
end

H.track(RunService.RenderStepped:Connect(function()
	if not F.headDots then
		if next(S.dots) then H.clearDots() end
		return
	end

	local camera = workspace.CurrentCamera
	local used = {}

	for _, target in ipairs(H.targets(true)) do
		local head = target.model:FindFirstChild("Head")
		if head and camera then
			local point, onScreen = camera:WorldToViewportPoint(head.Position)
			local dot = S.dots[target.model]
			if not dot then
				local ok, created = pcall(function() return Drawing.new("Circle") end)
				if ok and created then
					created.Filled = true
					created.NumSides = 16
					created.Transparency = 1
					dot = created
					S.dots[target.model] = dot
				end
			end

			if dot then
				used[target.model] = true
				dot.Visible = onScreen and point.Z > 0
				dot.Position = Vector2.new(point.X, point.Y)
				dot.Radius = math.clamp(120 / math.max(point.Z, 1), 2, 8)
				dot.Color = F.headDotColor
			end
		end
	end

	for model, dot in pairs(S.dots) do
		if not used[model] then
			pcall(function() dot:Remove() end)
			S.dots[model] = nil
		end
	end
end))

Esp.getWeapon = function(entity)
	local character = Esp.getCharacter(entity)
	local tool = character and character:FindFirstChildOfClass("Tool")
	return tool and tool.Name or "Fists"
end

H.BODY_PARTS = {
	Head = true, UpperTorso = true, LowerTorso = true, Torso = true, HumanoidRootPart = false,
	LeftUpperArm = true, LeftLowerArm = true, LeftHand = true, RightUpperArm = true, RightLowerArm = true, RightHand = true,
	LeftUpperLeg = true, LeftLowerLeg = true, LeftFoot = true, RightUpperLeg = true, RightLowerLeg = true, RightFoot = true,
	["Left Arm"] = true, ["Right Arm"] = true, ["Left Leg"] = true, ["Right Leg"] = true,
}

Esp.getBoxParts = function(model)
	local parts = {}
	for _, child in ipairs(model:GetChildren()) do
		if child:IsA("BasePart") and H.BODY_PARTS[child.Name] then table.insert(parts, child) end
	end
	if #parts == 0 then
		local root = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChildWhichIsA("BasePart")
		if root then table.insert(parts, root) end
	end
	return parts
end

H.BOX_SIGNS = {
	Vector3.new(-1, -1, -1), Vector3.new(1, -1, -1), Vector3.new(-1, 1, -1), Vector3.new(1, 1, -1),
	Vector3.new(-1, -1, 1), Vector3.new(1, -1, 1), Vector3.new(-1, 1, 1), Vector3.new(1, 1, 1),
}

function H.tightCorners(character, old)
	local camera = workspace.CurrentCamera
	if not camera then return nil end

	local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
	local any = false

	for _, part in ipairs(character:GetChildren()) do
		if part:IsA("BasePart") and H.BODY_PARTS[part.Name] then
			local cframe, half = part.CFrame, part.Size / 2
			for _, sign in ipairs(H.BOX_SIGNS) do
				local point, onScreen = camera:WorldToViewportPoint(cframe * (half * sign))
				if onScreen then
					any = true
					if point.X < minX then minX = point.X end
					if point.X > maxX then maxX = point.X end
					if point.Y < minY then minY = point.Y end
					if point.Y > maxY then maxY = point.Y end
				end
			end
		end
	end

	if not any then return nil end

	minX, minY, maxX, maxY = math.floor(minX - 2), math.floor(minY - 2), math.floor(maxX + 2), math.floor(maxY + 2)

	return {
		corners = old and old.corners or {},
		topLeft = Vector2.new(minX, minY),
		topRight = Vector2.new(maxX, minY),
		bottomLeft = Vector2.new(minX, maxY),
		bottomRight = Vector2.new(maxX, maxY),
	}
end

function H.patchEspRender(object)
	if S.espRenderPatched then return end
	local meta = getmetatable(object)
	local class = meta and meta.__index
	if type(class) ~= "table" or type(class.Render) ~= "function" then return end

	local original = class.Render
	S.espRenderClass, S.espRenderOriginal = class, original
	S.espRenderPatched = true

	class.Render = function(self, ...)
		if alive() and F.tightBox and self._corners and self.record and self.record.Character then
			local ok, corners = pcall(H.tightCorners, self.record.Character, self._corners)
			if ok and corners then self._corners = corners end
		end
		return original(self, ...)
	end
end

function H.unpatchEspRender()
	if S.espRenderClass and S.espRenderOriginal then
		pcall(function() S.espRenderClass.Render = S.espRenderOriginal end)
	end
	S.espRenderPatched = false
end

shared.FacilityCleanup = function()
	F.silent, F.trigger = false, false
	F.noRecoil, F.noSpread, F.rapidFire, F.autoFire, F.fastReload = false, false, false, false, false
	F.spinbot, F.headDots, F.chams = false, false, false
	pcall(H.triggerRelease)
	pcall(H.gunRestore)
	pcall(H.uninstallGunPatches)
	pcall(H.spinReset)
	pcall(H.clearChams)
	pcall(H.clearDots)
	if F.walkSpeed then pcall(H.applyWalk, 18) end
	pcall(H.restoreAll)
	pcall(H.unpatchEspRender)

	for _, connection in ipairs(S.connections) do pcall(function() connection:Disconnect() end) end
	for _, thread in ipairs(S.threads) do pcall(task.cancel, thread) end
	for _, object in ipairs(S.drawings) do pcall(function() object:Remove() end) end
	for _, object in ipairs(S.instances) do pcall(function() object:Destroy() end) end
	if S.gui then pcall(function() S.gui:Destroy() end) end

	pcall(function() Esp:Unload() end)
	if Aimbot then pcall(function() Aimbot:Unload() end) end
	if Movement then pcall(function() Movement:Unload() end) end
	pcall(function() Library:Destroy() end)
end

for _, message in ipairs(moduleErrors) do
	warn("[Facility] " .. message)
end

H.setTeamMode("Game")
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

U.Combat   = Window:Tab("Combat", "crosshair")
U.Silent   = Window:Tab("Silent Aim", "target")
U.Visuals  = Window:Tab("Visuals", "eye")
U.Guns     = Window:Tab("Guns", "sword")
U.PlayerT  = Window:Tab("Player", "user-round")
U.Exploits = Window:Tab("Exploits", "zap")
Window:TabDivider()
U.Settings = Window:Tab("Settings", "cog")

if #moduleErrors > 0 then
	U.failBox = U.Combat:Section("Modules", "full")
	for _, message in ipairs(moduleErrors) do
		U.failBox:Label(message, { Style = "dim" })
	end
end

U.teamBox = U.Combat:Section("Targets", 2)

H.D(U.teamBox, "Team Check", "sd_team_mode", { "Game", "Team", "Off" }, "Game", function(value) H.setTeamMode(value) end)
H.T(U.teamBox, "Target Dummies", "sd_dummies", true, function(state) F.dummies = state end, "practice dummies count as targets")
U.teamBox:Label("Game uses the game's own friendly check.", { Style = "dim" })

if Aimbot then

Aimbot.Settings.TeamCheck = true
Aimbot.Settings.WallCheck = true

U.aimBox = U.Combat:Section("Aimbot", 1)

U.aimBox:Toggle({
	Text = "Enable",
	Flag = "sd_aim_enable",
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
	Flag = "sd_aim_key",
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
	Flag = "sd_aim_toggle_mode",
	Default = false,
	Callback = function(state) Aimbot.Settings.ToggleMode = state end,
})

U.aimBox:Dropdown({
	Text = "Priority",
	Flag = "sd_aim_priority",
	Options = { "Cursor", "Closest", "LowestHealth" },
	Default = "Cursor",
	Callback = function(value) Aimbot.Settings.Priority = value end,
})

U.aimBox:Dropdown({
	Text = "Target Part",
	Flag = "sd_aim_parts",
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
	Flag = "sd_aim_random_part",
	Default = false,
	Callback = function(state) Aimbot.Settings.RandomPart = state end,
})
	:Gear(function(panel)
		panel:Slider({
			Text = "Interval",
			Flag = "sd_aim_random_interval",
			Min = 0.1, Max = 3, Default = 1,
			Decimals = 1,
			Suffix = " s",
			Callback = function(value) Aimbot.Settings.RandomInterval = value end,
		})
	end)

H.S(U.aimBox, "Smoothness", "sd_aim_smoothness", 0.05, 1, 0.3, 2, function(value) Aimbot.Settings.Smoothness = value end)
H.S(U.aimBox, "Sensitivity", "sd_aim_sensitivity", 0.02, 1, 0.5, 2, function(value) Aimbot.Settings.Sensitivity = value end)
H.D(U.aimBox, "Easing Style", "sd_aim_easing_style", { "Linear", "Sine", "Quad", "Cubic", "Quart", "Quint", "Exponential", "Back" }, "Quad", function(value) Aimbot.Settings.EasingStyle = value end)
H.D(U.aimBox, "Easing Direction", "sd_aim_easing_direction", { "In", "Out", "InOut" }, "Out", function(value) Aimbot.Settings.EasingDirection = value end)
H.S(U.aimBox, "Switch Delay", "sd_aim_switch_delay", 0, 2, 0, 2, function(value) Aimbot.Settings.SwitchDelay = value end, " s")
H.S(U.aimBox, "Max Distance", "sd_aim_max_distance", 100, 5000, 3000, 0, function(value) Aimbot.Settings.MaxDistance = value end, " studs")

U.fovBox = U.Combat:Section("Fov", 2)

U.fovBox:Toggle({
	Text = "Fov",
	Flag = "sd_aim_fov_enabled",
	Default = true,
	Callback = function(state)
		Aimbot.Settings.FovCheck = state
		Aimbot.Settings.FovVisible = state
	end,
})
	:ColorPicker({
		Flag = "sd_aim_fov_color",
		Default = Color3.fromRGB(255, 255, 255),
		Callback = function(color) Aimbot.Settings.FovColor = color end,
	})
	:ColorPicker({
		Flag = "sd_aim_fov_lock_color",
		Default = Color3.fromRGB(255, 70, 70),
		Callback = function(color) Aimbot.Settings.FovLockColor = color end,
	})

U.fovBox:Slider({
	Text = "Radius",
	Flag = "sd_aim_fov",
	Min = 20, Max = 600, Default = 180,
	Callback = function(value)
		Aimbot.Settings.Fov = value
		pcall(function() Aimbot:SetFov(value) end)
	end,
})

H.S(U.fovBox, "Thickness", "sd_aim_fov_thickness", 1, 5, 1, 0, function(value) Aimbot.Settings.FovThickness = value end)
H.S(U.fovBox, "Transparency", "sd_aim_fov_transparency", 0, 1, 0.4, 2, function(value) Aimbot.Settings.FovTransparency = value end)
H.T(U.fovBox, "Filled", "sd_aim_fov_filled", false, function(state) Aimbot.Settings.FovFilled = state end)

U.behaviourBox = U.Combat:Section("Behaviour", 2)

H.T(U.behaviourBox, "Team Check", "sd_aim_team_check", true, function(state) Aimbot.Settings.TeamCheck = state end)
H.T(U.behaviourBox, "Wall Check", "sd_aim_wall_check", true, function(state) Aimbot.Settings.WallCheck = state end)
H.T(U.behaviourBox, "Multipoint", "sd_aim_multipoint", false, function(state) Aimbot.Settings.Multipoint = state end)
H.S(U.behaviourBox, "Deadzone", "sd_aim_deadzone", 0, 200, 0, 0, function(value) Aimbot.Settings.Deadzone = value end)

U.behaviourBox:Toggle({
	Text = "Sticky Target",
	Flag = "sd_aim_sticky",
	Default = true,
	Callback = function(state) Aimbot.Settings.Sticky = state end,
})
	:Gear(function(panel)
		H.S(panel, "Hold Fov", "sd_aim_sticky_fov", 1, 3, 1.6, 1, function(value) Aimbot.Settings.StickyFov = value end)
	end)

U.behaviourBox:Toggle({
	Text = "Prediction",
	Flag = "sd_aim_prediction",
	Default = false,
	Callback = function(state) Aimbot.Settings.Prediction = state end,
})
	:Gear(function(panel)
		H.S(panel, "Time", "sd_aim_prediction_time", 0, 0.5, 0.1, 2, function(value) Aimbot.Settings.PredictionTime = value end, " s")
		H.T(panel, "Add Ping", "sd_aim_prediction_ping", false, function(state) Aimbot.Settings.PingPrediction = state end)
	end)

U.behaviourBox:Toggle({
	Text = "Target Line",
	Flag = "sd_aim_target_line",
	Default = false,
	Callback = function(state) Aimbot.Settings.TargetLine = state end,
})
	:ColorPicker({
		Flag = "sd_aim_target_line_color",
		Default = Color3.fromRGB(255, 70, 70),
		Callback = function(color) Aimbot.Settings.TargetLineColor = color end,
	})

H.T(U.behaviourBox, "Target Info", "sd_aim_target_info", false, function(state) Aimbot.Settings.TargetInfo = state end)

end

U.triggerBox = U.Combat:Section("Trigger Bot", 1)

U.triggerBox:Toggle({
	Text = "Enable",
	Flag = "sd_trigger",
	Default = false,
	Hint = "fires while an enemy sits under your crosshair",
	Callback = function(state)
		F.trigger = state
		if not state then H.triggerRelease() end
	end,
})
	:Keybind({ Default = "None", Flag = "sd_trigger_key" })

H.D(U.triggerBox, "Mode", "sd_trigger_mode", { "Crosshair", "Target", "Fov" }, "Crosshair", function(value) F.triggerMode = value end)
H.S(U.triggerBox, "Fov", "sd_trigger_fov", 0, 400, 0, 0, function(value) F.triggerFov = value end)
H.T(U.triggerBox, "Team Check", "sd_trigger_team", true, function(state) F.triggerTeam = state end)
H.S(U.triggerBox, "Shot Delay", "sd_trigger_delay", 0, 2, 0, 2, function(value)
	F.triggerDelay = value
	H.triggerRelease()
end, " s")
U.triggerBox:Label("0 holds and sprays, higher values tap.", { Style = "dim" })

U.silentBox = U.Silent:Section("Silent Aim", 1)

U.silentBox:Toggle({
	Text = "Silent Aim",
	Flag = "sd_silent",
	Default = false,
	Hint = "bends your shots toward the target closest to your mouse",
	Callback = function(state) H.setSilent(state) end,
})
	:Keybind({ Default = "None", Flag = "sd_silent_key" })
	:ColorPicker({
		Flag = "sd_silent_fov_color",
		Default = Color3.fromRGB(255, 255, 255),
		Callback = function(color) if U.silentCircle then U.silentCircle.Color = color end end,
	})

H.D(U.silentBox, "Method", "sd_silent_method", { "MultiRaycast", "Gun Fire" }, "MultiRaycast", function(value)
	F.silentMethod = value
	if F.silent then H.setSilent(true) end
end)
H.S(U.silentBox, "Fov", "sd_silent_fov", 30, 500, 120, 0, function(value) F.silentFov = value end)
H.T(U.silentBox, "Show Fov", "sd_silent_show_fov", false, function(state) F.silentShowFov = state end)
H.D(U.silentBox, "Aim Part", "sd_silent_part", { "Head", "UpperTorso", "HumanoidRootPart" }, "Head", function(value) F.silentPart = value end)
H.S(U.silentBox, "Range", "sd_silent_range", 100, 3000, 2000, 0, function(value) F.silentRange = value end, " studs")
H.S(U.silentBox, "Prediction", "sd_silent_lead", 0, 250, 0, 0, function(value) F.silentLead = value end, " ms")
H.S(U.silentBox, "Hit Chance", "sd_silent_hit_chance", 1, 100, 100, 0, function(value) F.silentHitChance = value end, "%")

U.silentChecks = U.Silent:Section("Checks", 2)
H.T(U.silentChecks, "Wall Check", "sd_silent_wall", false, function(state) F.silentWall = state end)
H.T(U.silentChecks, "Only While Firing", "sd_silent_firing", false, function(state) F.silentFiring = state end)
U.silentChecks:Label("Team check and dummies follow the Combat > Targets settings.", { Style = "dim" })

U.PLAYER_TEAMS = { "enemy", "friendly", "whitelist" }

function H.espSet(key, value)
	for _, name in ipairs(U.PLAYER_TEAMS) do
		local team = Esp.teamSettings[name]
		if team then team[key] = value end
	end
end

H.espSet("BeforeUpdate", function(object) H.patchEspRender(object) end)

function H.espPair(key, color, alpha)
	Esp.teamSettings.enemy[key] = { color, alpha ~= nil and (1 - alpha) or 1 }
end

U.espBox = U.Visuals:Section("Esp", 1)

U.espBox:Toggle({
	Text = "Enable",
	Flag = "sd_esp_enable",
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
	:Keybind({ Default = "None", Flag = "sd_esp_enable_key" })

U.espBox:Toggle({
	Text = "Box",
	Flag = "sd_esp_box",
	Default = true,
	Callback = function(state) H.espSet("box", state) end,
})
	:ColorPicker({
		Flag = "sd_esp_box_color",
		Default = Color3.fromRGB(255, 255, 255),
		Callback = function(color, alpha)
			H.espPair("boxColor", color, alpha)
			H.espPair("box3dColor", color, alpha)
		end,
	})
	:Gear(function(panel)
		H.D(panel, "Style", "sd_esp_box_style", { "2D", "3D" }, "2D", function(value)
			H.espSet("box", value == "2D")
			H.espSet("box3d", value == "3D")
		end)
		H.D(panel, "Fit", "sd_esp_box_fit", { "Body", "Full Model" }, "Body", function(value)
			F.tightBox = value == "Body"
		end)
	end)

U.espBox:Toggle({
	Text = "Health Bar",
	Flag = "sd_esp_health_bar",
	Default = true,
	Callback = function(state) H.espSet("healthBar", state) end,
})
	:ColorPicker({ Flag = "sd_esp_health_healthy", Default = Color3.fromRGB(82, 197, 148), Callback = function(color) H.espSet("healthyColor", color) end })
	:ColorPicker({ Flag = "sd_esp_health_dying", Default = Color3.fromRGB(240, 90, 102), Callback = function(color) H.espSet("dyingColor", color) end })

U.espBox:Toggle({
	Text = "Skeleton",
	Flag = "sd_esp_skeleton",
	Default = false,
	Callback = function(state) H.espSet("skeleton", state) end,
})
	:ColorPicker({ Flag = "sd_esp_skeleton_color", Default = Color3.new(1, 1, 1), Callback = function(color, alpha) H.espPair("skeletonColor", color, alpha) end })

U.espBox:Toggle({
	Text = "Tracers",
	Flag = "sd_esp_tracer",
	Default = false,
	Callback = function(state) H.espSet("tracer", state) end,
})
	:ColorPicker({ Flag = "sd_esp_tracer_color", Default = Color3.new(1, 1, 1), Callback = function(color, alpha) H.espPair("tracerColor", color, alpha) end })
	:Gear(function(panel)
		H.D(panel, "Origin", "sd_esp_tracer_origin", { "Bottom", "Middle", "Top", "Mouse" }, "Bottom", function(value) H.espSet("tracerOrigin", value) end)
	end)

U.espBox:Toggle({
	Text = "Highlight",
	Flag = "sd_esp_chams",
	Default = false,
	Callback = function(state) H.espSet("chams", state) end,
})
	:ColorPicker({ Flag = "sd_esp_chams_color", Default = Color3.fromRGB(255, 60, 60), Callback = function(color, alpha) H.espPair("chamsFillColor", color, alpha) end })

U.espBox:Toggle({
	Text = "Off Screen Arrow",
	Flag = "sd_esp_arrow",
	Default = false,
	Callback = function(state) H.espSet("offScreenArrow", state) end,
})
	:ColorPicker({ Flag = "sd_esp_arrow_color", Default = Color3.new(1, 1, 1), Callback = function(color, alpha) H.espPair("offScreenArrowColor", color, alpha) end })

U.displayBox = U.Visuals:Section("Display", 2)

U.displayBox:Toggle({
	Text = "Name",
	Flag = "sd_esp_name",
	Default = true,
	Callback = function(state) H.espSet("name", state) end,
})
	:ColorPicker({ Flag = "sd_esp_name_color", Default = Color3.fromRGB(236, 241, 250), Callback = function(color, alpha) H.espPair("nameColor", color, alpha) end })

U.displayBox:Toggle({
	Text = "Distance",
	Flag = "sd_esp_distance",
	Default = true,
	Callback = function(state) H.espSet("distance", state) end,
})
	:ColorPicker({ Flag = "sd_esp_distance_color", Default = Color3.fromRGB(170, 184, 205), Callback = function(color, alpha) H.espPair("distanceColor", color, alpha) end })

U.displayBox:Toggle({
	Text = "Weapon",
	Flag = "sd_esp_weapon",
	Default = false,
	Callback = function(state) H.espSet("weapon", state) end,
})
	:ColorPicker({ Flag = "sd_esp_weapon_color", Default = Color3.fromRGB(255, 255, 255), Callback = function(color, alpha) H.espPair("weaponColor", color, alpha) end })

H.T(U.displayBox, "Health", "sd_esp_health_text", false, function(state) H.espSet("healthText", state) end)
H.T(U.displayBox, "Team Color", "sd_esp_team_color", false, function(state) Esp.sharedSettings.useTeamColor = state end)
H.S(U.displayBox, "Text Size", "sd_esp_text_size", 8, 24, 13, 0, function(value) Esp.sharedSettings.textSize = value end)
H.S(U.displayBox, "Max Distance", "sd_esp_max_distance", 100, 5000, 1500, 0, function(value) H.espSet("maxDistance", value) end, " studs")

U.displayBox:Toggle({
	Text = "Show Teammates",
	Flag = "sd_esp_allies",
	Default = false,
	Callback = function(state) Esp.teamSettings.friendly.enabled = state end,
})
	:ColorPicker({
		Flag = "sd_esp_ally_color",
		Default = Color3.fromRGB(60, 255, 120),
		Callback = function(color)
			Esp.teamSettings.friendly.boxColor = { color, 1 }
			Esp.teamSettings.friendly.nameColor = { color, 1 }
		end,
	})

U.chamsBox = U.Visuals:Section("Chams", 1)

H.T(U.chamsBox, "Enable", "sd_chams", false, function(state) F.chams = state end, "colour switches when the target is behind cover")

U.chamsBox:Toggle({ Text = "Visible", Flag = "sd_chams_visible_toggle", Default = true, Callback = function() end })
	:ColorPicker({ Flag = "sd_chams_visible", Default = F.chamsVisible, Callback = function(color) F.chamsVisible = color end })

U.chamsBox:Toggle({ Text = "Behind Cover", Flag = "sd_chams_hidden_toggle", Default = true, Callback = function() end })
	:ColorPicker({ Flag = "sd_chams_hidden", Default = F.chamsHidden, Callback = function(color) F.chamsHidden = color end })

U.chamsBox:Toggle({
	Text = "Teammates",
	Flag = "sd_chams_allies",
	Default = false,
	Callback = function(state) F.chamsAllies = state end,
})
	:ColorPicker({ Flag = "sd_chams_ally", Default = F.chamsAlly, Callback = function(color) F.chamsAlly = color end })

U.chamsBox:Toggle({
	Text = "Head Dots",
	Flag = "sd_head_dots",
	Default = false,
	Callback = function(state) F.headDots = state end,
})
	:ColorPicker({ Flag = "sd_head_dot_color", Default = F.headDotColor, Callback = function(color) F.headDotColor = color end })

H.T(U.chamsBox, "Through Walls", "sd_chams_through", true, function(state) F.chamsThrough = state end)

U.gunBox = U.Guns:Section("Weapon Mods", 1)
H.T(U.gunBox, "No Recoil", "sd_no_recoil", false, function(state) F.noRecoil = state H.refreshGuns() end)
H.T(U.gunBox, "No Spread", "sd_no_spread", false, function(state) F.noSpread = state H.refreshGuns() end)
H.T(U.gunBox, "Rapid Fire", "sd_rapid_fire", false, function(state) F.rapidFire = state H.refreshGuns() end)
H.T(U.gunBox, "Auto Fire (All Guns)", "sd_auto_fire", false, function(state) F.autoFire = state H.refreshGuns() end)
H.T(U.gunBox, "Fast Reload", "sd_fast_reload", false, function(state) F.fastReload = state H.refreshGuns() end)

U.moveBox = U.PlayerT:Section("Movement", 1)

if Movement then

Movement.Settings.JumpMode = "Humanoid"

U.moveBox:Toggle({
	Text = "Fly",
	Flag = "sd_fly",
	Default = false,
	Callback = function(state) Movement:Fly(state) end,
})
	:Keybind({ Default = "None", Flag = "sd_fly_key" })
	:Gear(function(panel)
		H.S(panel, "Speed", "sd_fly_speed", 1, 20, 2, 1, function(value) Movement.Settings.FlySpeed = value end)
	end)

U.moveBox:Toggle({
	Text = "Jump Power",
	Flag = "sd_jump",
	Default = false,
	Callback = function(state) Movement:JumpPower(state and Movement.Settings.JumpPower or 50) end,
})
	:Gear(function(panel)
		H.S(panel, "Power", "sd_jump_value", 30, 300, 80, 0, function(value)
			Movement.Settings.JumpPower = value
			if Library.Flags["sd_jump"] then Movement:JumpPower(value) end
		end)
	end)

H.T(U.moveBox, "Infinite Jump", "sd_inf_jump", false, function(state) Movement:InfiniteJump(state) end)

U.moveBox:Toggle({
	Text = "Noclip",
	Flag = "sd_noclip",
	Default = false,
	Callback = function(state)
		Movement:Noclip(state)
		if not state then H.fixCollision() end
	end,
})
	:Keybind({ Default = "None", Flag = "sd_noclip_key" })

end

U.walkBox = U.PlayerT:Section("Walk Speed", 2)

U.walkBox:Toggle({
	Text = "Walk Speed",
	Flag = "sd_walk",
	Default = false,
	Hint = "uses the game's own walkspeed handler",
	Callback = function(state) H.setWalk(state) end,
})
	:Keybind({ Default = "None", Flag = "sd_walk_key" })

H.S(U.walkBox, "Speed", "sd_walk_value", 18, 150, 35, 0, function(value)
	F.walkSpeedValue = value
	if F.walkSpeed then H.applyWalk(value) end
end)

U.combatEx = U.Exploits:Section("Combat", 1)

U.combatEx:Toggle({
	Text = "Melee Kill Aura",
	Flag = "sd_melee_aura",
	Default = false,
	Callback = function(state) F.meleeAura = state end,
})
	:Gear(function(panel)
		H.S(panel, "Range", "sd_melee_range", 5, 30, 15, 0, function(value) F.meleeRange = value end, " studs")
	end)

U.moveEx = U.Exploits:Section("Movement", 2)
H.T(U.moveEx, "Infinite Slide", "sd_inf_slide", false, function(state) F.infiniteSlide = state end)

U.moveEx:Toggle({
	Text = "Spinbot",
	Flag = "sd_spinbot",
	Default = false,
	Callback = function(state) F.spinbot = state end,
})
	:Keybind({ Default = "None", Flag = "sd_spinbot_key" })

H.S(U.moveEx, "Spin Speed", "sd_spin_speed", 10, 180, 90, 0, function(value) F.spinbotSpeed = value end)

U.worldEx = U.Exploits:Section("World", 1)
H.T(U.worldEx, "Auto Glass Shatter", "sd_auto_glass", false, function(state) F.autoGlass = state end, "breaks every window when you spawn")
H.T(U.worldEx, "Instant Respawn (FFA)", "sd_instant_respawn", false, function(state) F.instantRespawn = state end)
H.B(U.worldEx, "Shatter All Glass", function()
	local count = H.shatterGlass()
	if count then H.notify("Glass", tostring(count) .. " panes broken.", 3) end
end)
H.B(U.worldEx, "Trampoline Super Bounce", H.trampoline)

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
SaveManager:SetFolder("Facility/7264587281")

InterfaceManager:BuildInterfaceSection(U.Settings, 1)
SaveManager:BuildConfigSection(U.Settings, 2)
ThemeManager:Mount(Window)

Window:SetTab(U.Combat)

if #moduleErrors > 0 then
	task.delay(1, function()
		for _, message in ipairs(moduleErrors) do Library:Error("Facility", message, 20) end
	end)
end

Library:Notify("Facility", "Sniper Duels loaded.", 4)

SaveManager:LoadAutoloadConfig()
ThemeManager:Load()
