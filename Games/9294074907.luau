local FH = shared.Facility
local Library = FH and FH.Library
assert(Library, "Start Facility with the loader")
local Entity = FH.Entity
local Esp = FH.Esp

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
FH.Aimbot = Aimbot
local Movement = fetchModule("CModules/FMovement.luau", "movement")
if Movement then pcall(function() Movement:Load() end) end
FH.Movement = Movement



local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")

local LocalPlayer = Players.LocalPlayer

local H = {}
local U = {}
local S = { connections = {}, drawings = {}, threads = {}, triggerHeld = false, lastTap = 0, botProxies = {}, botToggles = {}, fireRates = {} }
local F = {
	teamMode = "Team",
	bots = false,
	silent = false,
	silentTeam = true,
	infiniteAmmo = false,
	noRecoil = false,
	rapidFire = false,
	fireRate = 1000,
	trigger = false,
	triggerMode = "Crosshair",
	triggerFov = 0,
	triggerTeam = true,
	triggerDelay = 0,
	walkOn = false,
	walkValue = 30,
	jumpOn = false,
	jumpValue = 75,
}

local EDGE_OFFSETS = {
	Vector3.new(0.36, 0, 0),
	Vector3.new(-0.36, 0, 0),
	Vector3.new(0, 0.36, 0),
	Vector3.new(0, -0.36, 0),
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

function H.notifyError(title, message)
	pcall(function() Library:Notify({ Title = title, Text = tostring(message), Duration = 10, Style = "Error" }) end)
end

function H.camera()
	return workspace.CurrentCamera
end

function H.center()
	local camera = H.camera()
	return camera and camera.ViewportSize / 2 or Vector2.zero
end

function H.findPart(character, name)
	local part = character:FindFirstChild(name)
	if part and part:IsA("BasePart") then return part end
	for _, item in ipairs(character:GetDescendants()) do
		if item.Name == name and item:IsA("BasePart") then return item end
	end
end

function H.visible(origin, position, ignore)
	local camera = H.camera()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { LocalPlayer.Character, camera, ignore }
	params.IgnoreWater = true
	local direction = position - origin
	local distance = direction.Magnitude
	if distance <= 0 then return false end
	local hit = workspace:Raycast(origin, direction, params)
	return hit == nil or hit.Distance >= distance - 0.5
end




function H.botRoot(model)
	return model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
		or model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso")
end

function H.isBot(model)
	if not model:IsA("Model") or model == LocalPlayer.Character then return false end
	if Players:GetPlayerFromCharacter(model) then return false end
	if model.Name:lower():find("viewmodel", 1, true) then return false end
	return model:FindFirstChildWhichIsA("Humanoid") ~= nil and H.botRoot(model) ~= nil
end

function H.removeBot(model)
	local proxy = S.botProxies[model]
	if not proxy then return end
	S.botProxies[model] = nil
	pcall(function() Entity:Remove(proxy) end)
end

function H.addBot(model)
	if not alive() or not F.bots or not Entity or S.botProxies[model] or not H.isBot(model) then return end
	local humanoid = model:FindFirstChildWhichIsA("Humanoid")
	local root = H.botRoot(model)
	local head = model:FindFirstChild("Head") or root
	local proxy = { Name = model.Name, DisplayName = model.Name, UserId = 0, IsBot = true, Character = model }
	S.botProxies[model] = proxy
	local record = {
		Player = proxy, Character = model, Humanoid = humanoid, Head = head, RootPart = root,
		IsBot = true, Targetable = true, Health = humanoid.Health, MaxHealth = humanoid.MaxHealth,
		Alive = true, Connections = {},
	}
	local function watch(signal, fn) table.insert(record.Connections, signal:Connect(fn)) end
	watch(humanoid:GetPropertyChangedSignal("Health"), function()
		record.Health = humanoid.Health
		Entity.Updated:Fire(record)
	end)
	watch(humanoid:GetPropertyChangedSignal("MaxHealth"), function()
		record.MaxHealth = humanoid.MaxHealth
		Entity.Updated:Fire(record)
	end)
	watch(model.AncestryChanged, function()
		if not model:IsDescendantOf(workspace) then H.removeBot(model) end
	end)
	watch(model.ChildRemoved, function(child)
		if child == root or child == humanoid then H.removeBot(model) end
	end)
	Entity.Entities[proxy] = record
	Entity.Added:Fire(record)
end

function H.sweepBots()
	for model in pairs(S.botProxies) do
		if not model:IsDescendantOf(workspace) or Players:GetPlayerFromCharacter(model) then H.removeBot(model) end
	end
	if not F.bots then return end
	for _, child in ipairs(workspace:GetChildren()) do
		if not S.botProxies[child] and child:IsA("Model") then H.addBot(child) end
	end
end

function H.clearBots()
	for model in pairs(S.botProxies) do H.removeBot(model) end
end

function H.setBots(state)
	F.bots = state
	if state then H.sweepBots() else H.clearBots() end
	for _, toggle in ipairs(S.botToggles) do
		if toggle.Set then pcall(toggle.Set, toggle, state, true) end
	end
end

H.track(workspace.ChildAdded:Connect(function(child)
	if not alive() or not F.bots or not child:IsA("Model") then return end
	H.addBot(child)
	if not S.botProxies[child] then
		task.delay(1, function() if alive() and child.Parent then H.addBot(child) end end)
	end
end))
H.track(workspace.ChildRemoved:Connect(H.removeBot))
H.spawn(function()
	while alive() do
		task.wait(2)
		if F.bots and alive() then H.sweepBots() end
	end
end)


function H.setTeamMode(mode)
	F.teamMode = mode
	pcall(function() Entity.Settings.TeamCheck = mode end)
	pcall(function() Esp.sharedSettings.teamCheck = mode end)
	pcall(function() Entity:RefreshTargets() end)
end

function H.require(module)
	if not module then return nil end
	local ok, result = H.gcall(require, module)
	if ok and type(result) == "table" then return result end
	return nil
end

S.game = {}
do
	local scripts = LocalPlayer:FindFirstChild("PlayerScripts")
	local start = scripts and scripts:WaitForChild("Start", 8)
	local modules = start and start:WaitForChild("Game", 8)
	local weaponModule = modules and modules:WaitForChild("WeaponClient", 8)
	S.game.weapon = H.require(weaponModule)
	S.game.viewmodel = H.require(modules and modules:FindFirstChild("ViewmodelClient"))
	local common = ReplicatedStorage:FindFirstChild("Common")
	local managers = common and common:FindFirstChild("Managers")
	S.game.manager = H.require(managers and managers:FindFirstChild("WeaponManager"))
	local constants = S.game.manager and S.game.manager.Constants
	S.game.maxDistance = constants and constants.DEFAULT_MAX_DISTANCE or 1000
end

local upvalues = debug and debug.getupvalues

function H.findSpring(shoot)
	if type(shoot) ~= "function" or type(upvalues) ~= "function" then return nil end
	local found
	for _, value in pairs(upvalues(shoot)) do
		if type(value) == "table" and rawget(value, "Mass") == 5 and rawget(value, "Force") == 100
			and rawget(value, "Damping") == 15 and rawget(value, "Speed") == 3
			and type(rawget(value, "shove")) == "function" then
			if found then return nil end
			found = value
		end
	end
	return found
end

function H.findPacket(fire)
	if type(fire) ~= "function" or type(upvalues) ~= "function" then return nil end
	local sender
	for _, value in pairs(upvalues(fire)) do
		if type(value) == "function" then
			if sender then return nil end
			sender = value
		end
	end
	if not sender then return nil end
	local packet
	for _, value in pairs(upvalues(sender)) do
		if type(value) == "table" and type(rawget(value, "send")) == "function"
			and type(rawget(value, "reader")) == "function" and type(rawget(value, "listen")) == "function" then
			if packet then return nil end
			packet = value
		end
	end
	return packet
end

local saved = shared.FacilityShotTools
if saved then
	if saved.packet and saved.send then saved.packet.send = saved.send end
	if saved.weapon then
		if saved.getBullets then saved.weapon.getBullets = saved.getBullets end
		if saved.decreaseBullets then saved.weapon.decreaseBullets = saved.decreaseBullets end
	end
	if saved.viewmodel and saved.shoot then saved.viewmodel.shoot = saved.shoot end
	if saved.spring and saved.shove then saved.spring.shove = saved.shove end
	shared.FacilityShotTools = nil
end

if S.game.weapon then
	local deadline = os.clock() + 8
	repeat
		S.game.packet = H.findPacket(S.game.weapon.fire)
		if not S.game.packet then task.wait(0.15) end
	until S.game.packet or os.clock() >= deadline
end
S.game.spring = S.game.viewmodel and H.findSpring(S.game.viewmodel.shoot)

local O = {
	send = S.game.packet and S.game.packet.send,
	getBullets = S.game.weapon and S.game.weapon.getBullets,
	decreaseBullets = S.game.weapon and S.game.weapon.decreaseBullets,
	shoot = S.game.viewmodel and S.game.viewmodel.shoot,
	shove = S.game.spring and S.game.spring.shove,
}
shared.FacilityShotTools = {
	packet = S.game.packet, weapon = S.game.weapon, viewmodel = S.game.viewmodel, spring = S.game.spring,
	send = O.send, getBullets = O.getBullets, decreaseBullets = O.decreaseBullets, shoot = O.shoot, shove = O.shove,
}

if type(upvalues) ~= "function" then
	table.insert(moduleErrors, "game hooks: your executor has no debug.getupvalues")
elseif not S.game.weapon then
	table.insert(moduleErrors, "game hooks: weapon module not found, rejoin fully then execute again")
elseif not S.game.packet then
	table.insert(moduleErrors, "silent aim: the game's shot sender was not found")
end
if S.game.viewmodel and not S.game.spring then
	table.insert(moduleErrors, "no recoil: weapon spring not found")
end

S.rayParams = RaycastParams.new()
S.rayParams.FilterType = Enum.RaycastFilterType.Exclude

function H.enemyCharacter(character, teamCheck)
	if not character or not character:IsA("Model") or character == LocalPlayer.Character
		or not character:IsDescendantOf(workspace) then
		return false
	end
	local owner = Players:GetPlayerFromCharacter(character)
	if owner then
		if teamCheck and LocalPlayer.Team ~= nil and owner.Team == LocalPlayer.Team
			and not LocalPlayer.Neutral and not owner.Neutral then
			return false
		end
		if character:GetAttribute("deployed") == false then return false end
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0 and not character:FindFirstChild("ForceField")
end

function H.opponents(teamCheck)
	local list, seen = {}, {}
	local function add(character)
		if character and not seen[character] and H.enemyCharacter(character, teamCheck) then
			seen[character] = true
			table.insert(list, character)
		end
	end
	for _, character in ipairs(CollectionService:GetTagged("Character")) do add(character) end
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer then add(player.Character) end
	end
	if F.bots then
		for model in pairs(S.botProxies) do add(model) end
	end
	return list
end

function H.pickHit(origin, direction)
	local exclusions = { LocalPlayer.Character }
	local effects = workspace:FindFirstChild("Effects")
	if effects then table.insert(exclusions, effects) end
	S.rayParams.FilterDescendantsInstances = exclusions
	local range = S.game.maxDistance

	local candidates = {}
	for _, character in ipairs(H.opponents(F.silentTeam)) do
		local head = character:FindFirstChild("Hitbox_Head") or character:FindFirstChild("Head")
		local torso = character:FindFirstChild("Torso") or character:FindFirstChild("UpperTorso")
		local root = character:FindFirstChild("HumanoidRootPart")
		local aim = head or torso or root
		if aim and aim:IsA("BasePart") then
			local towards = aim.Position - origin
			local distance = towards.Magnitude
			if distance > 0 and distance <= range then
				local parts, used = {}, {}
				local function include(part)
					if part and part:IsA("BasePart") and not used[part] then
						used[part] = true
						table.insert(parts, part)
					end
				end
				include(head)
				include(torso)
				include(root)
				include(character:FindFirstChild("LowerTorso"))
				include(character:FindFirstChild("Left Arm") or character:FindFirstChild("LeftUpperArm"))
				include(character:FindFirstChild("Right Arm") or character:FindFirstChild("RightUpperArm"))
				local exposed = {}
				if head and head:IsA("BasePart") then table.insert(exposed, head) end
				if torso and torso:IsA("BasePart") and torso ~= head then table.insert(exposed, torso) end
				table.insert(candidates, {
					character = character, parts = parts, exposed = exposed,
					distance = distance, alignment = towards.Unit:Dot(direction),
				})
			end
		end
	end
	if #candidates == 0 then return nil end
	table.sort(candidates, function(a, b)
		if a.alignment == b.alignment then return a.distance < b.distance end
		return a.alignment > b.alignment
	end)

	local function check(candidate, point)
		local towards = point - origin
		local distance = towards.Magnitude
		if distance <= 0 or distance > range then return nil end
		local hit = workspace:Raycast(origin, towards, S.rayParams)
		if not hit or not hit.Instance:IsDescendantOf(candidate.character) then return nil end
		local part = hit.Instance
		local parent = part.Parent
		if parent and (parent:IsA("Hat") or (parent:IsA("Accessory")
			and (parent.AccessoryType == Enum.AccessoryType.Hat or parent.AccessoryType == Enum.AccessoryType.Face))) then
			part = candidate.character:FindFirstChild("Hitbox_Head") or candidate.character:FindFirstChild("Head") or part
		end
		return candidate.character, part, hit.Position, towards.Unit
	end

	for _, candidate in ipairs(candidates) do
		for _, part in ipairs(candidate.parts) do
			local character, part2, position, towards = check(candidate, part.Position)
			if character then return character, part2, position, towards end
		end
		for _, part in ipairs(candidate.exposed) do
			for _, offset in ipairs(EDGE_OFFSETS) do
				local point = part.CFrame:PointToWorldSpace(Vector3.new(part.Size.X * offset.X, part.Size.Y * offset.Y, 0))
				local character, part2, position, towards = check(candidate, point)
				if character then return character, part2, position, towards end
			end
		end
	end
	return nil
end

function H.send(shot)
	if alive() and F.silent and type(shot) == "table" and shot.weaponType ~= "Knife"
		and typeof(shot.origin) == "Vector3" and typeof(shot.direction) == "Vector3" then
		local ok, character, part, position, direction = pcall(H.pickHit, shot.origin, shot.direction)
		if ok and character then
			shot.hitResult = character
			shot.hitPart = part
			shot.position = position
			shot.direction = direction
		end
	end
	return O.send(shot)
end

function H.slot()
	local character = LocalPlayer.Character
	return character and character:GetAttribute("currentWeapon")
end

function H.getBullets(...)
	if alive() and F.infiniteAmmo then
		local slot = H.slot()
		if slot == nil or slot == "Primary" or slot == "Secondary" then
			return S.game.weapon.getMaxBulletsForCurrentWeapon()
		end
	end
	return O.getBullets(...)
end

function H.decreaseBullets(...)
	if alive() and F.infiniteAmmo and H.slot() ~= "Knife" then return end
	return O.decreaseBullets(...)
end

function H.shoot(isKnife, ...)
	if alive() and F.noRecoil then return O.shoot(true, ...) end
	return O.shoot(isKnife, ...)
end

function H.shove(...)
	if alive() and F.noRecoil then return end
	return O.shove(...)
end

if S.game.packet and O.send then S.game.packet.send = H.send end
if S.game.weapon and O.getBullets and O.decreaseBullets then
	S.game.weapon.getBullets = H.getBullets
	S.game.weapon.decreaseBullets = H.decreaseBullets
end
if S.game.spring and O.shove and O.shoot then
	S.game.spring.shove = H.shove
	S.game.viewmodel.shoot = H.shoot
end

function H.applyFireRate()
	local manager = S.game.manager
	if not manager or type(manager.getWeapons) ~= "function" then return end
	local ok, weapons = pcall(manager.getWeapons)
	if not ok or type(weapons) ~= "table" then return end
	for _, data in pairs(weapons) do
		if type(data) == "table" then
			if F.rapidFire then
				if S.fireRates[data] == nil then S.fireRates[data] = { value = rawget(data, "firerate") } end
				data.firerate = F.fireRate
			elseif S.fireRates[data] then
				data.firerate = S.fireRates[data].value
				S.fireRates[data] = nil
			end
		end
	end
end

function H.press(down)
	if down and mouse1press then pcall(mouse1press)
	elseif not down and mouse1release then pcall(mouse1release) end
end

function H.triggerRelease()
	if S.triggerHeld then
		S.triggerHeld = false
		H.press(false)
	end
end

function H.triggerTarget()
	local camera = H.camera()
	if not camera then return nil end
	if F.triggerMode == "Target" then
		local target = Aimbot and Aimbot.Target
		local record = target and Entity and Entity:Get(target)
		local character = record and record.Character
		return H.enemyCharacter(character, F.triggerTeam) and character or nil
	end
	local center = H.center()
	if F.triggerMode == "Crosshair" then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { LocalPlayer.Character, camera, workspace:FindFirstChild("Effects") }
		local ray = camera:ViewportPointToRay(center.X, center.Y)
		local hit = workspace:Raycast(ray.Origin, ray.Direction * 5000, params)
		if not hit then return nil end
		for _, character in ipairs(H.opponents(F.triggerTeam)) do
			if hit.Instance:IsDescendantOf(character) then return character end
		end
		return nil
	end
	local radius = F.triggerFov > 0 and F.triggerFov or 12
	for _, character in ipairs(H.opponents(F.triggerTeam)) do
		local head = character:FindFirstChild("Hitbox_Head") or character:FindFirstChild("Head")
		if head then
			local point, onScreen = camera:WorldToViewportPoint(head.Position)
			if onScreen and (Vector2.new(point.X, point.Y) - center).Magnitude <= radius
				and H.visible(camera.CFrame.Position, head.Position, character) then
				return character
			end
		end
	end
end

H.track(RunService.Heartbeat:Connect(function()
	if not alive() then return end
	local character = LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not F.trigger or not humanoid or humanoid.Health <= 0 or UserInputService:GetFocusedTextBox() then
		H.triggerRelease()
		return
	end
	if not H.triggerTarget() then
		H.triggerRelease()
		return
	end
	if F.triggerDelay <= 0 then
		if not S.triggerHeld then
			S.triggerHeld = true
			H.press(true)
		end
		return
	end
	local now = os.clock()
	if now - S.lastTap >= F.triggerDelay then
		S.lastTap = now
		H.press(true)
		task.delay(0.03, function() H.press(false) end)
	end
end))

shared.FacilityCleanup = function()
	F.silent, F.infiniteAmmo, F.noRecoil, F.trigger = false, false, false, false
	F.rapidFire = false
	pcall(H.applyFireRate)
	H.triggerRelease()
	H.clearBots()
	F.bots = false
	if S.game.packet and S.game.packet.send == H.send then S.game.packet.send = O.send end
	if S.game.weapon then
		if S.game.weapon.getBullets == H.getBullets then S.game.weapon.getBullets = O.getBullets end
		if S.game.weapon.decreaseBullets == H.decreaseBullets then S.game.weapon.decreaseBullets = O.decreaseBullets end
	end
	if S.game.viewmodel and S.game.viewmodel.shoot == H.shoot then S.game.viewmodel.shoot = O.shoot end
	if S.game.spring and S.game.spring.shove == H.shove then S.game.spring.shove = O.shove end
	shared.FacilityShotTools = nil
	for _, connection in ipairs(S.connections) do pcall(function() connection:Disconnect() end) end
	table.clear(S.connections)
	for _, thread in ipairs(S.threads) do
		if thread ~= coroutine.running() then pcall(task.cancel, thread) end
	end
	table.clear(S.threads)
	if Aimbot then pcall(function() Aimbot:Unload() end) end
	if Movement then pcall(function() Movement:Unload() end) end
	pcall(function() Esp:Unload() end)
	pcall(function() Library:Destroy() end)
end

local Window = Library:Window({
	Title = "Facility",
	Suffix = ".app",
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

U.Combat = Window:Tab("Combat", "crosshair")
U.Visuals = Window:Tab("Visuals", "eye")
U.Player = Window:Tab("Player", "user")
Window:TabDivider()
U.Settings = Window:Tab("Settings", "settings")

U.AimSub = H.sub(U.Combat, "Aimbot", "crosshair")
U.RageSub = H.sub(U.Combat, "Rage", "zap")

if #moduleErrors > 0 then
	U.failBox = U.AimSub:Section("Modules", "full")
	for _, message in ipairs(moduleErrors) do U.failBox:Label(message, { Style = "dim" }) end
end

function H.botToggle(section, flag)
	local toggle = section:Toggle({
		Text = "Include Bots / NPCs",
		Flag = flag,
		Default = false,
		Callback = function(state)
			if F.bots ~= state then H.setBots(state) end
		end,
	})
	table.insert(S.botToggles, toggle)
	return toggle
end


if Aimbot then
	Aimbot.Settings.TeamCheck = true
	Aimbot.Settings.WallCheck = true

	U.aimBox = U.AimSub:Section("Aimbot", 1)
	U.aimBox:Toggle({
		Text = "Enable",
		Flag = "otp_aim_enable",
		Default = false,
		Callback = function(state)
			if state then
				local ok, err = pcall(function() Aimbot:Load(Entity) end)
				if not ok then
					H.notifyError("Aimbot", err)
					return
				end
			end
			Aimbot.Enabled = state
		end,
	})
	U.aimBox:Keybind({
		Text = "Aim Key",
		Flag = "otp_aim_key",
		Default = "MB2",
		Mode = "toggle",
		OnChanged = function(key)
			local map = {
				MB1 = Enum.UserInputType.MouseButton1,
				MB2 = Enum.UserInputType.MouseButton2,
				MB3 = Enum.UserInputType.MouseButton3,
			}
			local ok, chosen = pcall(function() return map[key] or Enum.KeyCode[key] end)
			chosen = ok and chosen or Enum.UserInputType.MouseButton2
			Aimbot.Settings.Key = chosen
			pcall(function() Aimbot:SetKey(chosen) end)
		end,
	})
	H.T(U.aimBox, "Toggle Mode", "otp_aim_toggle_mode", false, function(state) Aimbot.Settings.ToggleMode = state end)
	H.D(U.aimBox, "Priority", "otp_aim_priority", { "Cursor", "Closest", "LowestHealth" }, "Cursor", function(value) Aimbot.Settings.Priority = value end)
	U.aimBox:Dropdown({
		Text = "Target Part",
		Flag = "otp_aim_parts",
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
		Flag = "otp_aim_random_part",
		Default = false,
		Callback = function(state) Aimbot.Settings.RandomPart = state end,
	}):Gear(function(panel)
		H.S(panel, "Interval", "otp_aim_random_interval", 0.1, 3, 1, 1, function(value) Aimbot.Settings.RandomInterval = value end, " s")
	end)
	H.S(U.aimBox, "Smoothness", "otp_aim_smoothness", 0.05, 1, 0.3, 2, function(value) Aimbot.Settings.Smoothness = value end)
	H.S(U.aimBox, "Sensitivity", "otp_aim_sensitivity", 0.02, 1, 0.5, 2, function(value) Aimbot.Settings.Sensitivity = value end)
	H.D(U.aimBox, "Easing Style", "otp_aim_easing_style", { "Linear", "Sine", "Quad", "Cubic", "Quart", "Quint", "Exponential", "Back" }, "Quad", function(value) Aimbot.Settings.EasingStyle = value end)
	H.D(U.aimBox, "Easing Direction", "otp_aim_easing_direction", { "In", "Out", "InOut" }, "Out", function(value) Aimbot.Settings.EasingDirection = value end)
	H.S(U.aimBox, "Switch Delay", "otp_aim_switch_delay", 0, 2, 0, 2, function(value) Aimbot.Settings.SwitchDelay = value end, " s")
	H.S(U.aimBox, "Max Distance", "otp_aim_max_distance", 100, 5000, 3000, 0, function(value) Aimbot.Settings.MaxDistance = value end, " studs")

	U.fovBox = U.AimSub:Section("Fov", 2)
	U.fovBox:Toggle({
		Text = "Fov",
		Flag = "otp_aim_fov_enabled",
		Default = true,
		Callback = function(state)
			Aimbot.Settings.FovCheck = state
			Aimbot.Settings.FovVisible = state
		end,
	})
		:ColorPicker({ Flag = "otp_aim_fov_color", Default = Color3.fromRGB(255, 255, 255), Callback = function(color) Aimbot.Settings.FovColor = color end })
		:ColorPicker({ Flag = "otp_aim_fov_lock_color", Default = Color3.fromRGB(255, 70, 70), Callback = function(color) Aimbot.Settings.FovLockColor = color end })
	U.fovBox:Slider({
		Text = "Radius",
		Flag = "otp_aim_fov",
		Min = 20, Max = 600, Default = 180,
		Callback = function(value)
			Aimbot.Settings.Fov = value
			pcall(function() Aimbot:SetFov(value) end)
		end,
	})
	H.S(U.fovBox, "Thickness", "otp_aim_fov_thickness", 1, 5, 1, 0, function(value) Aimbot.Settings.FovThickness = value end)
	H.S(U.fovBox, "Transparency", "otp_aim_fov_transparency", 0, 1, 0.4, 2, function(value) Aimbot.Settings.FovTransparency = value end)
	H.T(U.fovBox, "Filled", "otp_aim_fov_filled", false, function(state) Aimbot.Settings.FovFilled = state end)

	U.behaviourBox = U.AimSub:Section("Behaviour", 2)
	H.T(U.behaviourBox, "Team Check", "otp_aim_team_check", true, function(state) Aimbot.Settings.TeamCheck = state end)
	H.T(U.behaviourBox, "Wall Check", "otp_aim_wall_check", true, function(state) Aimbot.Settings.WallCheck = state end)
	H.T(U.behaviourBox, "Multipoint", "otp_aim_multipoint", false, function(state) Aimbot.Settings.Multipoint = state end)
	H.S(U.behaviourBox, "Deadzone", "otp_aim_deadzone", 0, 200, 0, 0, function(value) Aimbot.Settings.Deadzone = value end)
	U.behaviourBox:Toggle({
		Text = "Sticky Target",
		Flag = "otp_aim_sticky",
		Default = true,
		Callback = function(state) Aimbot.Settings.Sticky = state end,
	}):Gear(function(panel)
		H.S(panel, "Hold Fov", "otp_aim_sticky_fov", 1, 3, 1.6, 1, function(value) Aimbot.Settings.StickyFov = value end)
	end)
	U.behaviourBox:Toggle({
		Text = "Prediction",
		Flag = "otp_aim_prediction",
		Default = false,
		Callback = function(state) Aimbot.Settings.Prediction = state end,
	}):Gear(function(panel)
		H.S(panel, "Time", "otp_aim_prediction_time", 0, 0.5, 0.1, 2, function(value) Aimbot.Settings.PredictionTime = value end, " s")
		H.T(panel, "Add Ping", "otp_aim_prediction_ping", false, function(state) Aimbot.Settings.PingPrediction = state end)
	end)
	U.behaviourBox:Toggle({
		Text = "Target Line",
		Flag = "otp_aim_target_line",
		Default = false,
		Callback = function(state) Aimbot.Settings.TargetLine = state end,
	}):ColorPicker({ Flag = "otp_aim_target_line_color", Default = Color3.fromRGB(255, 70, 70), Callback = function(color) Aimbot.Settings.TargetLineColor = color end })
	H.T(U.behaviourBox, "Target Info", "otp_aim_target_info", false, function(state) Aimbot.Settings.TargetInfo = state end)
end




U.teamBox = U.AimSub:Section("Targets", 1)
H.D(U.teamBox, "Team Check", "otp_team_mode", { "Team", "TeamColor", "Off" }, "Team", function(value) H.setTeamMode(value) end)
H.botToggle(U.teamBox, "otp_aim_bots")
U.teamBox:Label("Use Off in free for all if nobody gets targeted.", { Style = "dim" })

U.silentBox = U.RageSub:Section("Silent Aim", 1)
U.silentBox:Toggle({
	Text = "Silent Aim",
	Flag = "otp_silent",
	Default = false,
	Hint = "sends every shot to the most aligned enemy you can see, any angle",
	Callback = function(state) F.silent = state end,
}):Keybind({ Default = "X", Flag = "otp_silent_key" })
H.T(U.silentBox, "Team Check", "otp_silent_team", true, function(state) F.silentTeam = state end)
U.silentBox:Label("Also aims at edges of the head and body when the centre is covered.", { Style = "dim" })

U.gunBox = U.RageSub:Section("Gun Mods", 1)
H.T(U.gunBox, "Infinite Ammo", "otp_inf_ammo", false, function(state) F.infiniteAmmo = state end)
H.T(U.gunBox, "No Recoil", "otp_no_recoil", false, function(state) F.noRecoil = state end)
U.gunBox:Toggle({
	Text = "Rapid Fire",
	Flag = "otp_rapid",
	Default = false,
	Callback = function(state)
		F.rapidFire = state
		H.applyFireRate()
	end,
}):Keybind({ Default = "None", Flag = "otp_rapid_key" })
H.S(U.gunBox, "Fire Rate", "otp_fire_rate", 100, 2000, 1000, 0, function(value)
	F.fireRate = value
	if F.rapidFire then H.applyFireRate() end
end, " rpm")

U.triggerBox = U.RageSub:Section("Trigger Bot", 2)
U.triggerBox:Toggle({
	Text = "Enable",
	Flag = "otp_trigger",
	Default = false,
	Hint = "fires while an enemy is under your crosshair",
	Callback = function(state)
		F.trigger = state
		if not state then H.triggerRelease() end
	end,
}):Keybind({ Default = "T", Flag = "otp_trigger_key" })
H.D(U.triggerBox, "Mode", "otp_trigger_mode", { "Crosshair", "Target", "Fov" }, "Crosshair", function(value) F.triggerMode = value end)
H.S(U.triggerBox, "Fov", "otp_trigger_fov", 0, 400, 0, 0, function(value) F.triggerFov = value end)
H.T(U.triggerBox, "Team Check", "otp_trigger_team", true, function(state) F.triggerTeam = state end)
H.S(U.triggerBox, "Shot Delay", "otp_trigger_delay", 0, 2, 0, 2, function(value)
	F.triggerDelay = value
	H.triggerRelease()
end, " s")
U.triggerBox:Label("0 holds and sprays, higher values tap. Fov 0 is 12 px.", { Style = "dim" })



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
	Flag = "otp_esp_enable",
	Default = false,
	Callback = function(state)
		local ok, err
		if state then
			ok, err = pcall(function() Esp:Load(Entity) end)
		else
			ok, err = pcall(function() Esp:Unload() end)
		end
		if not ok then H.notifyError("Esp", err) end
	end,
}):Keybind({ Default = "None", Flag = "otp_esp_enable_key" })
U.espBox:Toggle({
	Text = "Box",
	Flag = "otp_esp_box",
	Default = true,
	Callback = function(state) H.espSet("box", state) end,
})
	:ColorPicker({
		Flag = "otp_esp_box_color",
		Default = Color3.fromRGB(255, 60, 60),
		Callback = function(color, alpha)
			H.espPair("boxColor", color, alpha)
			H.espPair("box3dColor", color, alpha)
		end,
	})
	:Gear(function(panel)
		H.D(panel, "Style", "otp_esp_box_style", { "2D", "3D" }, "2D", function(value)
			H.espSet("box", value == "2D")
			H.espSet("box3d", value == "3D")
		end)
	end)
U.espBox:Toggle({
	Text = "Health Bar",
	Flag = "otp_esp_health_bar",
	Default = true,
	Callback = function(state) H.espSet("healthBar", state) end,
})
	:ColorPicker({ Flag = "otp_esp_health_healthy", Default = Color3.fromRGB(82, 197, 148), Callback = function(color) H.espSet("healthyColor", color) end })
	:ColorPicker({ Flag = "otp_esp_health_dying", Default = Color3.fromRGB(240, 90, 102), Callback = function(color) H.espSet("dyingColor", color) end })
U.espBox:Toggle({
	Text = "Skeleton",
	Flag = "otp_esp_skeleton",
	Default = false,
	Callback = function(state) H.espSet("skeleton", state) end,
}):ColorPicker({ Flag = "otp_esp_skeleton_color", Default = Color3.new(1, 1, 1), Callback = function(color, alpha) H.espPair("skeletonColor", color, alpha) end })
U.espBox:Toggle({
	Text = "Tracers",
	Flag = "otp_esp_tracer",
	Default = false,
	Callback = function(state) H.espSet("tracer", state) end,
})
	:ColorPicker({ Flag = "otp_esp_tracer_color", Default = Color3.new(1, 1, 1), Callback = function(color, alpha) H.espPair("tracerColor", color, alpha) end })
	:Gear(function(panel)
		H.D(panel, "Origin", "otp_esp_tracer_origin", { "Bottom", "Middle", "Top", "Mouse" }, "Bottom", function(value) H.espSet("tracerOrigin", value) end)
	end)
U.espBox:Toggle({
	Text = "Highlight",
	Flag = "otp_esp_chams",
	Default = false,
	Callback = function(state) H.espSet("chams", state) end,
}):ColorPicker({ Flag = "otp_esp_chams_color", Default = Color3.fromRGB(255, 60, 60), Callback = function(color, alpha) H.espPair("chamsFillColor", color, alpha) end })
U.espBox:Toggle({
	Text = "Off Screen Arrow",
	Flag = "otp_esp_arrow",
	Default = false,
	Callback = function(state) H.espSet("offScreenArrow", state) end,
}):ColorPicker({ Flag = "otp_esp_arrow_color", Default = Color3.new(1, 1, 1), Callback = function(color, alpha) H.espPair("offScreenArrowColor", color, alpha) end })

U.displayBox = U.Visuals:Section("Display", 2)
U.displayBox:Toggle({
	Text = "Name",
	Flag = "otp_esp_name",
	Default = true,
	Callback = function(state) H.espSet("name", state) end,
}):ColorPicker({ Flag = "otp_esp_name_color", Default = Color3.fromRGB(236, 241, 250), Callback = function(color, alpha) H.espPair("nameColor", color, alpha) end })
U.displayBox:Toggle({
	Text = "Distance",
	Flag = "otp_esp_distance",
	Default = true,
	Callback = function(state) H.espSet("distance", state) end,
}):ColorPicker({ Flag = "otp_esp_distance_color", Default = Color3.fromRGB(170, 184, 205), Callback = function(color, alpha) H.espPair("distanceColor", color, alpha) end })
U.displayBox:Toggle({
	Text = "Weapon",
	Flag = "otp_esp_weapon",
	Default = true,
	Callback = function(state) H.espSet("weapon", state) end,
}):ColorPicker({ Flag = "otp_esp_weapon_color", Default = Color3.fromRGB(255, 220, 100), Callback = function(color, alpha) H.espPair("weaponColor", color, alpha) end })
H.T(U.displayBox, "Health", "otp_esp_health_text", false, function(state) H.espSet("healthText", state) end)
H.T(U.displayBox, "Team Color", "otp_esp_team_color", false, function(state) Esp.sharedSettings.useTeamColor = state end)
H.T(U.displayBox, "Rainbow", "otp_esp_rainbow", false, function(state) Esp.sharedSettings.rainbow = state end)
H.S(U.displayBox, "Text Size", "otp_esp_text_size", 8, 24, 13, 0, function(value) Esp.sharedSettings.textSize = value end)
H.S(U.displayBox, "Max Distance", "otp_esp_max_distance", 100, 5000, 1500, 0, function(value) H.espSet("maxDistance", value) end, " studs")
U.displayBox:Toggle({
	Text = "Show Teammates",
	Flag = "otp_esp_allies",
	Default = false,
	Callback = function(state) Esp.teamSettings.friendly.enabled = state end,
}):ColorPicker({
	Flag = "otp_esp_ally_color",
	Default = Color3.fromRGB(0, 200, 255),
	Callback = function(color)
		Esp.teamSettings.friendly.boxColor = { color, 1 }
		Esp.teamSettings.friendly.nameColor = { color, 1 }
	end,
})




U.espBotsBox = U.Visuals:Section("Bots", 2)
H.botToggle(U.espBotsBox, "otp_esp_bots")

U.moveBox = U.Player:Section("Movement", 1)
if Movement then
	U.moveBox:Toggle({ Text = "Walk Speed", Flag = "otp_walk_on", Default = false, Callback = function(state)
		F.walkOn = state
		Movement:WalkSpeed(state and F.walkValue or 16, "Humanoid")
	end }):Keybind({ Default = "None", Flag = "otp_walk_key" })
	H.S(U.moveBox, "Speed", "otp_walk_value", 16, 120, F.walkValue, 0, function(value)
		F.walkValue = value
		if F.walkOn then Movement:WalkSpeed(value, "Humanoid") end
	end)
	U.moveBox:Toggle({ Text = "Jump Power", Flag = "otp_jump_on", Default = false, Callback = function(state)
		F.jumpOn = state
		Movement:JumpPower(state and F.jumpValue or 50, "Humanoid")
	end })
	H.S(U.moveBox, "Power", "otp_jump_value", 50, 200, F.jumpValue, 0, function(value)
		F.jumpValue = value
		if F.jumpOn then Movement:JumpPower(value, "Humanoid") end
	end)
	U.moveBox:Toggle({ Text = "Fly", Flag = "otp_fly", Default = false, Callback = function(state)
		Movement:Fly(state)
	end }):Keybind({ Default = "None", Flag = "otp_fly_key" })
	H.S(U.moveBox, "Fly Speed", "otp_fly_speed", 1, 20, 2, 1, function(value) Movement:SetFlySpeed(value) end)
	H.T(U.moveBox, "Noclip", "otp_noclip", false, function(state) Movement:Noclip(state) end)
	H.T(U.moveBox, "Infinite Jump", "otp_inf_jump", false, function(state) Movement:InfiniteJump(state) end)
	H.T(U.moveBox, "Spider", "otp_spider", false, function(state) Movement:Spider(state) end)
else
	U.moveBox:Label("Movement module failed to load.", { Style = "dim" })
end

local SaveManager = Library.SaveManager
local InterfaceManager = Library.InterfaceManager
local ThemeManager = Library.ThemeManager

SaveManager:SetLibrary(Library)
InterfaceManager:SetLibrary(Library)
InterfaceManager:SetWindow(Window)
ThemeManager:SetLibrary(Library)

SaveManager:IgnoreThemeSettings()
InterfaceManager:SetFolder("Facility")
ThemeManager:SetFolder("Facility")
SaveManager:SetFolder("Facility/9294074907")

InterfaceManager:BuildInterfaceSection(U.Settings, 1)
SaveManager:BuildConfigSection(U.Settings, 2)
ThemeManager:Mount(Window)

Window:SetTab(U.Combat)

Library:Notify("Facility", "One Tap loaded.", 4)

SaveManager:LoadAutoloadConfig()
ThemeManager:Load()
