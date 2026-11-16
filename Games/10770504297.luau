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

local LocalPlayer = Players.LocalPlayer

local H = {}
local U = {}
local S = { connections = {}, drawings = {}, threads = {}, triggerHeld = false, lastTap = 0, lastAuto = 0, botProxies = {}, botToggles = {}, target = nil }
local F = {
	bots = false,
	silent = false,
	silentMelee = true,
	silentPart = "Head",
	silentPriority = "Distance",
	silentRange = 300,
	silentFov = 0,
	autoShoot = false,
	autoInterval = 0.22,
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

function H.require(parent, ...)
	local node = parent
	for _, name in ipairs({ ... }) do
		node = node and node:FindFirstChild(name)
	end
	if not node or not node:IsA("ModuleScript") then return nil end
	local ok, result = H.gcall(require, node)
	if ok and type(result) == "table" then return result end
	return nil
end

S.game = {}
do
	local scripts = LocalPlayer:WaitForChild("PlayerScripts", 10)
	local client = scripts and scripts:WaitForChild("Client", 10)
	S.game.weapons = client and H.require(client, "Weapons", "WeaponController")
	S.game.assist = client and H.require(client, "Weapons", "AimAssist")
	S.game.flow = client and H.require(client, "Flow")
	S.game.holes = H.require(ReplicatedStorage, "Shared", "WindowHoles")
	S.game.config = H.require(ReplicatedStorage, "Shared", "Config")
	S.game.teams = H.require(ReplicatedStorage, "Shared", "Teams")
	local revolver = S.game.config and S.game.config.Revolver or {}
	S.game.range = math.min(revolver.Range or 300, 500)
	F.silentRange = S.game.range
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





function H.botContainers()
	local list = { workspace }
	local combatants = workspace:FindFirstChild("Combatants")
	if combatants then table.insert(list, combatants) end
	return list
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
		IsBot = true, Targetable = not H.allies(model), Health = humanoid.Health, MaxHealth = humanoid.MaxHealth,
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
	for _, container in ipairs(H.botContainers()) do
		for _, child in ipairs(container:GetChildren()) do
			if not S.botProxies[child] and child:IsA("Model") then H.addBot(child) end
		end
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



function H.allies(model)
	local teams = S.game.teams
	local mine = LocalPlayer.Character
	if not teams or type(teams.allies) ~= "function" or not mine or not model then return false end
	local ok, result = pcall(teams.allies, model, mine)
	return ok and result == true
end

S.originalTargetable = Entity and Entity.IsTargetable
if Entity then
	Entity.IsTargetable = function(self, player)
		if player == LocalPlayer then return false end
		local character = typeof(player) == "Instance" and player.Character or (type(player) == "table" and player.Character)
		if not character then return true end
		return not H.allies(character)
	end
	pcall(function() Entity:RefreshTargets() end)
end

H.spawn(function()
	while alive() do
		task.wait(1)
		if Entity then pcall(function() Entity:RefreshTargets() end) end
	end
end)

S.rayParams = RaycastParams.new()
S.rayParams.FilterType = Enum.RaycastFilterType.Exclude
S.rayParams.RespectCanCollide = false

function H.blocked(model, position)
	local camera = workspace.CurrentCamera
	if not camera then return true end
	local filter = { camera }
	if LocalPlayer.Character then table.insert(filter, LocalPlayer.Character) end
	for _, name in ipairs({ "Ragdolls", "Effects" }) do
		local folder = workspace:FindFirstChild(name)
		if folder then table.insert(filter, folder) end
	end
	S.rayParams.FilterDescendantsInstances = filter
	local origin = camera.CFrame.Position
	local direction = position - origin
	local hit
	local holes = S.game.holes
	if holes and type(holes.raycast) == "function" then
		local ok, result = pcall(holes.raycast, origin, direction, S.rayParams)
		hit = ok and result or nil
	else
		hit = workspace:Raycast(origin, direction, S.rayParams)
	end
	if not hit then return false end
	return not hit.Instance:IsDescendantOf(model)
end

function H.living(model)
	if not model or model:GetAttribute("Alive") == false then return false end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

function H.deployed()
	local flow = S.game.flow
	if flow and type(flow.isDeployed) == "function" then
		local ok, result = pcall(flow.isDeployed)
		return ok and result == true
	end
	return true
end

function H.aimPart(model)
	if F.silentPart == "Torso" then
		return model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso") or model:FindFirstChild("Head")
	end
	return model:FindFirstChild("Head") or model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso")
end

function H.combatants()
	local list, seen = {}, {}
	local folder = workspace:FindFirstChild("Combatants")
	local mine = LocalPlayer.Character
	local function add(model)
		if model and model:IsA("Model") and model ~= mine and not seen[model] then
			seen[model] = true
			table.insert(list, model)
		end
	end
	if folder then
		for _, model in ipairs(folder:GetChildren()) do add(model) end
	end
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer then add(player.Character) end
	end
	return list
end

function H.enemy(model, teamCheck)
	if not H.living(model) or model:GetAttribute("Protected") == true then return false end
	if teamCheck and H.allies(model) then return false end
	return true
end

function H.pickTarget()
	local character = LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not H.living(character) or not H.deployed() then return nil end
	local camera = workspace.CurrentCamera
	local center = camera and camera.ViewportSize / 2
	local best, bestScore
	for _, model in ipairs(H.combatants()) do
		if H.enemy(model, true) then
			local part = H.aimPart(model)
			if part then
				local distance = (model:GetPivot().Position - root.Position).Magnitude
				if distance <= F.silentRange and not H.blocked(model, part.Position) then
					local score = distance
					local inside = true
					if camera and (F.silentPriority == "Crosshair" or F.silentFov > 0) then
						local point, onScreen = camera:WorldToViewportPoint(part.Position)
						local screen = onScreen and (Vector2.new(point.X, point.Y) - center).Magnitude or math.huge
						if F.silentFov > 0 and screen > F.silentFov then inside = false end
						if F.silentPriority == "Crosshair" then score = screen end
					end
					if inside and (not bestScore or score < bestScore) then
						best, bestScore = { model = model, part = part }, score
					end
				end
			end
		end
	end
	return best
end

function H.lockedDirection(origin)
	local target = S.target
	if not alive() or not F.silent or not target or not target.part.Parent then return nil end
	local position = target.part.Position
	if H.blocked(target.model, position) then return nil end
	return (position - origin).Unit
end

local saved = shared.FacilityBendTools
if saved and saved.assist then
	if saved.shot then rawset(saved.assist, "bendShot", saved.shot) end
	if saved.melee then rawset(saved.assist, "bendMelee", saved.melee) end
end
shared.FacilityBendTools = nil

local O = {}
if S.game.assist then
	O.shot = rawget(S.game.assist, "bendShot") or S.game.assist.bendShot
	O.melee = rawget(S.game.assist, "bendMelee") or S.game.assist.bendMelee
	shared.FacilityBendTools = { assist = S.game.assist, shot = O.shot, melee = O.melee }
end

function H.bendShot(origin, direction, ...)
	local locked = H.lockedDirection(origin)
	if locked then return locked end
	return O.shot(origin, direction, ...)
end

function H.bendMelee(origin, direction, reach, ...)
	if F.silentMelee then
		local locked = H.lockedDirection(origin)
		if locked then return locked end
	end
	return O.melee(origin, direction, reach, ...)
end

if S.game.assist and type(O.shot) == "function" then rawset(S.game.assist, "bendShot", H.bendShot) end
if S.game.assist and type(O.melee) == "function" then rawset(S.game.assist, "bendMelee", H.bendMelee) end

if not S.game.assist or type(O.shot) ~= "function" then
	table.insert(moduleErrors, "silent aim: the game's aim assist module was not found")
end
if not S.game.teams then
	table.insert(moduleErrors, "teams: the game's team module was not found, everyone counts as an enemy")
end

function H.shootOnce()
	local weapons = S.game.weapons
	if weapons and type(weapons.touchShoot) == "function" then
		pcall(weapons.touchShoot, true)
		task.delay(0.02, function() pcall(weapons.touchShoot, false) end)
		return
	end
	if mouse1click then pcall(mouse1click) end
end

function H.hold(down)
	local weapons = S.game.weapons
	if weapons and type(weapons.touchShoot) == "function" then
		pcall(weapons.touchShoot, down)
	elseif down and mouse1press then
		pcall(mouse1press)
	elseif not down and mouse1release then
		pcall(mouse1release)
	end
end

H.spawn(function()
	while alive() do
		if F.silent or F.autoShoot then
			local ok, target = pcall(H.pickTarget)
			S.target = ok and target or nil
			if S.target and F.autoShoot then
				local now = os.clock()
				if now - S.lastAuto >= F.autoInterval then
					S.lastAuto = now
					H.shootOnce()
				end
			end
			task.wait(0.02)
		else
			S.target = nil
			task.wait(0.1)
		end
	end
end)

function H.triggerRelease()
	if S.triggerHeld then
		S.triggerHeld = false
		H.hold(false)
	end
end

function H.triggerTarget()
	local camera = H.camera()
	if not camera then return nil end
	if F.triggerMode == "Target" then
		local target = Aimbot and Aimbot.Target
		local record = target and Entity and Entity:Get(target)
		local model = record and record.Character
		return model and H.enemy(model, F.triggerTeam) and model or nil
	end
	local center = H.center()
	if F.triggerMode == "Crosshair" then
		local ray = camera:ViewportPointToRay(center.X, center.Y)
		local filter = { camera, LocalPlayer.Character }
		for _, name in ipairs({ "Ragdolls", "Effects" }) do
			local folder = workspace:FindFirstChild(name)
			if folder then table.insert(filter, folder) end
		end
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = filter
		local hit = workspace:Raycast(ray.Origin, ray.Direction * 2000, params)
		if not hit then return nil end
		for _, model in ipairs(H.combatants()) do
			if hit.Instance:IsDescendantOf(model) then
				return H.enemy(model, F.triggerTeam) and model or nil
			end
		end
		return nil
	end
	local radius = F.triggerFov > 0 and F.triggerFov or 12
	for _, model in ipairs(H.combatants()) do
		if H.enemy(model, F.triggerTeam) then
			local head = model:FindFirstChild("Head")
			if head then
				local point, onScreen = camera:WorldToViewportPoint(head.Position)
				if onScreen and (Vector2.new(point.X, point.Y) - center).Magnitude <= radius and not H.blocked(model, head.Position) then
					return model
				end
			end
		end
	end
end

H.track(RunService.Heartbeat:Connect(function()
	if not alive() then return end
	local character = LocalPlayer.Character
	if not F.trigger or not H.living(character) or not H.deployed() or UserInputService:GetFocusedTextBox() then
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
			H.hold(true)
		end
		return
	end
	local now = os.clock()
	if now - S.lastTap >= F.triggerDelay then
		S.lastTap = now
		H.shootOnce()
	end
end))

shared.FacilityCleanup = function()
	F.silent, F.autoShoot, F.trigger = false, false, false
	S.target = nil
	H.triggerRelease()
	H.clearBots()
	F.bots = false
	if S.game.assist then
		if rawget(S.game.assist, "bendShot") == H.bendShot then rawset(S.game.assist, "bendShot", O.shot) end
		if rawget(S.game.assist, "bendMelee") == H.bendMelee then rawset(S.game.assist, "bendMelee", O.melee) end
	end
	shared.FacilityBendTools = nil
	if Entity and S.originalTargetable then
		Entity.IsTargetable = S.originalTargetable
		pcall(function() Entity:RefreshTargets() end)
	end
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
		Flag = "rva_aim_enable",
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
		Flag = "rva_aim_key",
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
	H.T(U.aimBox, "Toggle Mode", "rva_aim_toggle_mode", false, function(state) Aimbot.Settings.ToggleMode = state end)
	H.D(U.aimBox, "Priority", "rva_aim_priority", { "Cursor", "Closest", "LowestHealth" }, "Cursor", function(value) Aimbot.Settings.Priority = value end)
	U.aimBox:Dropdown({
		Text = "Target Part",
		Flag = "rva_aim_parts",
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
		Flag = "rva_aim_random_part",
		Default = false,
		Callback = function(state) Aimbot.Settings.RandomPart = state end,
	}):Gear(function(panel)
		H.S(panel, "Interval", "rva_aim_random_interval", 0.1, 3, 1, 1, function(value) Aimbot.Settings.RandomInterval = value end, " s")
	end)
	H.S(U.aimBox, "Smoothness", "rva_aim_smoothness", 0.05, 1, 0.3, 2, function(value) Aimbot.Settings.Smoothness = value end)
	H.S(U.aimBox, "Sensitivity", "rva_aim_sensitivity", 0.02, 1, 0.5, 2, function(value) Aimbot.Settings.Sensitivity = value end)
	H.D(U.aimBox, "Easing Style", "rva_aim_easing_style", { "Linear", "Sine", "Quad", "Cubic", "Quart", "Quint", "Exponential", "Back" }, "Quad", function(value) Aimbot.Settings.EasingStyle = value end)
	H.D(U.aimBox, "Easing Direction", "rva_aim_easing_direction", { "In", "Out", "InOut" }, "Out", function(value) Aimbot.Settings.EasingDirection = value end)
	H.S(U.aimBox, "Switch Delay", "rva_aim_switch_delay", 0, 2, 0, 2, function(value) Aimbot.Settings.SwitchDelay = value end, " s")
	H.S(U.aimBox, "Max Distance", "rva_aim_max_distance", 100, 5000, 3000, 0, function(value) Aimbot.Settings.MaxDistance = value end, " studs")

	U.fovBox = U.AimSub:Section("Fov", 2)
	U.fovBox:Toggle({
		Text = "Fov",
		Flag = "rva_aim_fov_enabled",
		Default = true,
		Callback = function(state)
			Aimbot.Settings.FovCheck = state
			Aimbot.Settings.FovVisible = state
		end,
	})
		:ColorPicker({ Flag = "rva_aim_fov_color", Default = Color3.fromRGB(255, 255, 255), Callback = function(color) Aimbot.Settings.FovColor = color end })
		:ColorPicker({ Flag = "rva_aim_fov_lock_color", Default = Color3.fromRGB(255, 70, 70), Callback = function(color) Aimbot.Settings.FovLockColor = color end })
	U.fovBox:Slider({
		Text = "Radius",
		Flag = "rva_aim_fov",
		Min = 20, Max = 600, Default = 180,
		Callback = function(value)
			Aimbot.Settings.Fov = value
			pcall(function() Aimbot:SetFov(value) end)
		end,
	})
	H.S(U.fovBox, "Thickness", "rva_aim_fov_thickness", 1, 5, 1, 0, function(value) Aimbot.Settings.FovThickness = value end)
	H.S(U.fovBox, "Transparency", "rva_aim_fov_transparency", 0, 1, 0.4, 2, function(value) Aimbot.Settings.FovTransparency = value end)
	H.T(U.fovBox, "Filled", "rva_aim_fov_filled", false, function(state) Aimbot.Settings.FovFilled = state end)

	U.behaviourBox = U.AimSub:Section("Behaviour", 2)
	H.T(U.behaviourBox, "Team Check", "rva_aim_team_check", true, function(state) Aimbot.Settings.TeamCheck = state end)
	H.T(U.behaviourBox, "Wall Check", "rva_aim_wall_check", true, function(state) Aimbot.Settings.WallCheck = state end)
	H.T(U.behaviourBox, "Multipoint", "rva_aim_multipoint", false, function(state) Aimbot.Settings.Multipoint = state end)
	H.S(U.behaviourBox, "Deadzone", "rva_aim_deadzone", 0, 200, 0, 0, function(value) Aimbot.Settings.Deadzone = value end)
	U.behaviourBox:Toggle({
		Text = "Sticky Target",
		Flag = "rva_aim_sticky",
		Default = true,
		Callback = function(state) Aimbot.Settings.Sticky = state end,
	}):Gear(function(panel)
		H.S(panel, "Hold Fov", "rva_aim_sticky_fov", 1, 3, 1.6, 1, function(value) Aimbot.Settings.StickyFov = value end)
	end)
	U.behaviourBox:Toggle({
		Text = "Prediction",
		Flag = "rva_aim_prediction",
		Default = false,
		Callback = function(state) Aimbot.Settings.Prediction = state end,
	}):Gear(function(panel)
		H.S(panel, "Time", "rva_aim_prediction_time", 0, 0.5, 0.1, 2, function(value) Aimbot.Settings.PredictionTime = value end, " s")
		H.T(panel, "Add Ping", "rva_aim_prediction_ping", false, function(state) Aimbot.Settings.PingPrediction = state end)
	end)
	U.behaviourBox:Toggle({
		Text = "Target Line",
		Flag = "rva_aim_target_line",
		Default = false,
		Callback = function(state) Aimbot.Settings.TargetLine = state end,
	}):ColorPicker({ Flag = "rva_aim_target_line_color", Default = Color3.fromRGB(255, 70, 70), Callback = function(color) Aimbot.Settings.TargetLineColor = color end })
	H.T(U.behaviourBox, "Target Info", "rva_aim_target_info", false, function(state) Aimbot.Settings.TargetInfo = state end)
end





U.teamBox = U.AimSub:Section("Targets", 1)
H.botToggle(U.teamBox, "rva_aim_bots")
U.teamBox:Label("Teams come from the game, bots also show in the esp and can be locked by the aimbot.", { Style = "dim" })

U.silentBox = U.RageSub:Section("Silent Aim", 1)
U.silentBox:Toggle({
	Text = "Silent Aim",
	Flag = "rva_silent",
	Default = false,
	Hint = "bends every shot onto the chosen visible enemy",
	Callback = function(state) F.silent = state end,
}):Keybind({ Default = "X", Flag = "rva_silent_key" })
H.T(U.silentBox, "Melee Too", "rva_silent_melee", true, function(state) F.silentMelee = state end)
H.D(U.silentBox, "Aim Part", "rva_silent_part", { "Head", "Torso" }, "Head", function(value) F.silentPart = value end)
H.D(U.silentBox, "Priority", "rva_silent_priority", { "Distance", "Crosshair" }, "Distance", function(value) F.silentPriority = value end)
H.S(U.silentBox, "Max Distance", "rva_silent_range", 25, S.game.range, S.game.range, 0, function(value) F.silentRange = value end, " studs")
H.S(U.silentBox, "Fov", "rva_silent_fov", 0, 600, 0, 0, function(value) F.silentFov = value end)
U.silentBox:Label("Fov 0 means no limit, any visible enemy in range can be hit.", { Style = "dim" })

U.autoBox = U.RageSub:Section("Auto Shoot", 2)
U.autoBox:Toggle({
	Text = "Auto Shoot",
	Flag = "rva_auto_shoot",
	Default = false,
	Hint = "fires on its own whenever a target is available, works on mobile",
	Callback = function(state) F.autoShoot = state end,
}):Keybind({ Default = "None", Flag = "rva_auto_shoot_key" })
H.S(U.autoBox, "Interval", "rva_auto_interval", 0.1, 1, 0.22, 2, function(value) F.autoInterval = value end, " s")
U.autoBox:Label("Uses the same target as silent aim, turn both on for full rage.", { Style = "dim" })

U.triggerBox = U.RageSub:Section("Trigger Bot", 2)
U.triggerBox:Toggle({
	Text = "Enable",
	Flag = "rva_trigger",
	Default = false,
	Hint = "fires while an enemy is under your crosshair",
	Callback = function(state)
		F.trigger = state
		if not state then H.triggerRelease() end
	end,
}):Keybind({ Default = "T", Flag = "rva_trigger_key" })
H.D(U.triggerBox, "Mode", "rva_trigger_mode", { "Crosshair", "Target", "Fov" }, "Crosshair", function(value) F.triggerMode = value end)
H.S(U.triggerBox, "Fov", "rva_trigger_fov", 0, 400, 0, 0, function(value) F.triggerFov = value end)
H.T(U.triggerBox, "Team Check", "rva_trigger_team", true, function(state) F.triggerTeam = state end)
H.S(U.triggerBox, "Shot Delay", "rva_trigger_delay", 0, 2, 0, 2, function(value)
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
	Flag = "rva_esp_enable",
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
}):Keybind({ Default = "None", Flag = "rva_esp_enable_key" })
U.espBox:Toggle({
	Text = "Box",
	Flag = "rva_esp_box",
	Default = true,
	Callback = function(state) H.espSet("box", state) end,
})
	:ColorPicker({
		Flag = "rva_esp_box_color",
		Default = Color3.fromRGB(255, 60, 60),
		Callback = function(color, alpha)
			H.espPair("boxColor", color, alpha)
			H.espPair("box3dColor", color, alpha)
		end,
	})
	:Gear(function(panel)
		H.D(panel, "Style", "rva_esp_box_style", { "2D", "3D" }, "2D", function(value)
			H.espSet("box", value == "2D")
			H.espSet("box3d", value == "3D")
		end)
	end)
U.espBox:Toggle({
	Text = "Health Bar",
	Flag = "rva_esp_health_bar",
	Default = true,
	Callback = function(state) H.espSet("healthBar", state) end,
})
	:ColorPicker({ Flag = "rva_esp_health_healthy", Default = Color3.fromRGB(82, 197, 148), Callback = function(color) H.espSet("healthyColor", color) end })
	:ColorPicker({ Flag = "rva_esp_health_dying", Default = Color3.fromRGB(240, 90, 102), Callback = function(color) H.espSet("dyingColor", color) end })
U.espBox:Toggle({
	Text = "Skeleton",
	Flag = "rva_esp_skeleton",
	Default = false,
	Callback = function(state) H.espSet("skeleton", state) end,
}):ColorPicker({ Flag = "rva_esp_skeleton_color", Default = Color3.new(1, 1, 1), Callback = function(color, alpha) H.espPair("skeletonColor", color, alpha) end })
U.espBox:Toggle({
	Text = "Tracers",
	Flag = "rva_esp_tracer",
	Default = false,
	Callback = function(state) H.espSet("tracer", state) end,
})
	:ColorPicker({ Flag = "rva_esp_tracer_color", Default = Color3.new(1, 1, 1), Callback = function(color, alpha) H.espPair("tracerColor", color, alpha) end })
	:Gear(function(panel)
		H.D(panel, "Origin", "rva_esp_tracer_origin", { "Bottom", "Middle", "Top", "Mouse" }, "Bottom", function(value) H.espSet("tracerOrigin", value) end)
	end)
U.espBox:Toggle({
	Text = "Highlight",
	Flag = "rva_esp_chams",
	Default = false,
	Callback = function(state) H.espSet("chams", state) end,
}):ColorPicker({ Flag = "rva_esp_chams_color", Default = Color3.fromRGB(255, 60, 60), Callback = function(color, alpha) H.espPair("chamsFillColor", color, alpha) end })
U.espBox:Toggle({
	Text = "Off Screen Arrow",
	Flag = "rva_esp_arrow",
	Default = false,
	Callback = function(state) H.espSet("offScreenArrow", state) end,
}):ColorPicker({ Flag = "rva_esp_arrow_color", Default = Color3.new(1, 1, 1), Callback = function(color, alpha) H.espPair("offScreenArrowColor", color, alpha) end })

U.displayBox = U.Visuals:Section("Display", 2)
U.displayBox:Toggle({
	Text = "Name",
	Flag = "rva_esp_name",
	Default = true,
	Callback = function(state) H.espSet("name", state) end,
}):ColorPicker({ Flag = "rva_esp_name_color", Default = Color3.fromRGB(236, 241, 250), Callback = function(color, alpha) H.espPair("nameColor", color, alpha) end })
U.displayBox:Toggle({
	Text = "Distance",
	Flag = "rva_esp_distance",
	Default = true,
	Callback = function(state) H.espSet("distance", state) end,
}):ColorPicker({ Flag = "rva_esp_distance_color", Default = Color3.fromRGB(170, 184, 205), Callback = function(color, alpha) H.espPair("distanceColor", color, alpha) end })
U.displayBox:Toggle({
	Text = "Weapon",
	Flag = "rva_esp_weapon",
	Default = true,
	Callback = function(state) H.espSet("weapon", state) end,
}):ColorPicker({ Flag = "rva_esp_weapon_color", Default = Color3.fromRGB(255, 220, 100), Callback = function(color, alpha) H.espPair("weaponColor", color, alpha) end })
H.T(U.displayBox, "Health", "rva_esp_health_text", false, function(state) H.espSet("healthText", state) end)
H.T(U.displayBox, "Team Color", "rva_esp_team_color", false, function(state) Esp.sharedSettings.useTeamColor = state end)
H.T(U.displayBox, "Rainbow", "rva_esp_rainbow", false, function(state) Esp.sharedSettings.rainbow = state end)
H.S(U.displayBox, "Text Size", "rva_esp_text_size", 8, 24, 13, 0, function(value) Esp.sharedSettings.textSize = value end)
H.S(U.displayBox, "Max Distance", "rva_esp_max_distance", 100, 5000, 1500, 0, function(value) H.espSet("maxDistance", value) end, " studs")
U.displayBox:Toggle({
	Text = "Show Teammates",
	Flag = "rva_esp_allies",
	Default = false,
	Callback = function(state) Esp.teamSettings.friendly.enabled = state end,
}):ColorPicker({
	Flag = "rva_esp_ally_color",
	Default = Color3.fromRGB(0, 200, 255),
	Callback = function(color)
		Esp.teamSettings.friendly.boxColor = { color, 1 }
		Esp.teamSettings.friendly.nameColor = { color, 1 }
	end,
})





U.moveBox = U.Player:Section("Movement", 1)
if Movement then
	U.moveBox:Toggle({ Text = "Walk Speed", Flag = "rva_walk_on", Default = false, Callback = function(state)
		F.walkOn = state
		Movement:WalkSpeed(state and F.walkValue or 16, "Humanoid")
	end }):Keybind({ Default = "None", Flag = "rva_walk_key" })
	H.S(U.moveBox, "Speed", "rva_walk_value", 16, 120, F.walkValue, 0, function(value)
		F.walkValue = value
		if F.walkOn then Movement:WalkSpeed(value, "Humanoid") end
	end)
	U.moveBox:Toggle({ Text = "Jump Power", Flag = "rva_jump_on", Default = false, Callback = function(state)
		F.jumpOn = state
		Movement:JumpPower(state and F.jumpValue or 50, "Humanoid")
	end })
	H.S(U.moveBox, "Power", "rva_jump_value", 50, 200, F.jumpValue, 0, function(value)
		F.jumpValue = value
		if F.jumpOn then Movement:JumpPower(value, "Humanoid") end
	end)
	U.moveBox:Toggle({ Text = "Fly", Flag = "rva_fly", Default = false, Callback = function(state)
		Movement:Fly(state)
	end }):Keybind({ Default = "None", Flag = "rva_fly_key" })
	H.S(U.moveBox, "Fly Speed", "rva_fly_speed", 1, 20, 2, 1, function(value) Movement:SetFlySpeed(value) end)
	H.T(U.moveBox, "Noclip", "rva_noclip", false, function(state) Movement:Noclip(state) end)
	H.T(U.moveBox, "Infinite Jump", "rva_inf_jump", false, function(state) Movement:InfiniteJump(state) end)
	H.T(U.moveBox, "Spider", "rva_spider", false, function(state) Movement:Spider(state) end)
else
	U.moveBox:Label("Movement module failed to load.", { Style = "dim" })
end


U.espBotsBox = U.Visuals:Section("Bots", 2)
H.botToggle(U.espBotsBox, "rva_esp_bots")
U.espBotsBox:Label("Highlight uses the game's renderer and may be easier to detect than boxes.", { Style = "dim" })

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
SaveManager:SetFolder("Facility/RevolverArena")

InterfaceManager:BuildInterfaceSection(U.Settings, 1)
SaveManager:BuildConfigSection(U.Settings, 2)
ThemeManager:Mount(Window)

Window:SetTab(U.Combat)

Library:Notify("Facility", "Revolver Arena loaded.", 4)

SaveManager:LoadAutoloadConfig()
ThemeManager:Load()
