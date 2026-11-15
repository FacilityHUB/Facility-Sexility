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


local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer

local H = {}
local U = {}
local S = { connections = {}, drawings = {}, threads = {}, triggerHeld = false, lastTap = 0, botProxies = {}, killTargets = {}, botToggles = {} }
local F = {
	teamMode = "Team",
	bots = false,
	silent = false,
	silentCone = 360,
	silentRange = 600,
	silentBots = true,
	silentTeam = true,
	killAll = false,
	killDelay = 0.04,
	killPart = "Head",
	killPanic = 40,
	trigger = false,
	triggerMode = "Crosshair",
	triggerFov = 0,
	triggerTeam = true,
	triggerDelay = 0,
}

local HIT_PARTS = { "HeadHitbox", "Head", "BodyHitbox", "UpperTorso", "Torso", "HumanoidRootPart" }
local MAX_RANGE = 600

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

function H.setTeamMode(mode)
	F.teamMode = mode
	pcall(function() Entity.Settings.TeamCheck = mode end)
	pcall(function() Esp.sharedSettings.teamCheck = mode end)
	pcall(function() Entity:RefreshTargets() end)
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

S.game = {}
do
	local modules = ReplicatedStorage:FindFirstChild("Modules")
	local shared = modules and modules:FindFirstChild("Shared")
	local deagleModule = shared and shared:FindFirstChild("DeagleShared")
	local modeModule = shared and shared:FindFirstChild("GamemodeShared")
	local network = modules and modules:FindFirstChild("Packages")
	network = network and network:FindFirstChild("Network")
	S.game.remote = network and network:FindFirstChild("NetworkRemote")
	if deagleModule then
		local ok, result = H.gcall(require, deagleModule)
		if ok and type(result) == "table" then S.game.deagle = result end
	end
	if modeModule then
		local ok, result = H.gcall(require, modeModule)
		if ok and type(result) == "table" then S.game.modes = result end
	end
	local loader = LocalPlayer:FindFirstChild("PlayerScripts")
	loader = loader and loader:FindFirstChild("ModuleLoader")
	local controller = loader and loader:FindFirstChild("DeagleController")
	if controller then
		local ok, result = H.gcall(require, controller)
		if ok and type(result) == "table" then S.game.controller = result end
	end
end

if S.game.deagle and type(S.game.deagle.Raycast) == "function" then
	if shared.FacilityDeagleRaycast and S.game.deagle.Raycast ~= shared.FacilityDeagleRaycast then
		S.game.deagle.Raycast = shared.FacilityDeagleRaycast
	end
	shared.FacilityDeagleRaycast = shared.FacilityDeagleRaycast or S.game.deagle.Raycast
end
local rawRaycast = shared.FacilityDeagleRaycast

function H.teammates(character)
	local modes = S.game.modes
	local mine = LocalPlayer.Character
	if not modes or type(modes.AreTeammates) ~= "function" or not mine then return false end
	local ok, result = pcall(modes.AreTeammates, mine, character)
	return ok and result == true
end

function H.attackable(character, teamCheck)
	if not character or not character.Parent or character == LocalPlayer.Character then return false end
	if character:GetAttribute("Alive") == false or character:GetAttribute("SpawnProtection") == true
		or character:GetAttribute("Ragdolled") == true or character:GetAttribute("IsDead") == true
		or character:FindFirstChild("Dead") then
		return false
	end
	if teamCheck and H.teammates(character) then return false end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0 and humanoid:GetState() ~= Enum.HumanoidStateType.Dead
end

function H.opponents(includeBots, teamCheck)
	local list, seen = {}, {}
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if player ~= LocalPlayer and character and player:GetAttribute("InRound") ~= false
			and H.attackable(character, teamCheck) then
			seen[character] = true
			table.insert(list, character)
		end
	end
	if includeBots then
		for _, child in ipairs(workspace:GetChildren()) do
			if not seen[child] and child:IsA("Model")
				and (child:GetAttribute("IsBot") == true or child:GetAttribute("TutorialTarget") == true or H.isBot(child))
				and H.attackable(child, teamCheck) then
				seen[child] = true
				table.insert(list, child)
			end
		end
	end
	return list
end

function H.characterFromHit(part)
	local deagle = S.game.deagle
	if deagle and type(deagle.GetCharacterFromHit) == "function" then
		local ok, result = pcall(deagle.GetCharacterFromHit, part)
		if ok then return result end
	end
	return part and part:FindFirstAncestorWhichIsA("Model")
end

function H.silentPick(origin, aim)
	local mine = LocalPlayer.Character
	if not mine or not mine:FindFirstChild("Deagle") or not rawRaycast then return nil end
	local humanoid = mine:FindFirstChildOfClass("Humanoid")
	local aimVector = aim - origin
	if not humanoid or humanoid.Health <= 0 or aimVector.Magnitude <= 0 then return nil end

	local direction = aimVector.Unit
	local minimumDot = math.cos(math.rad(math.clamp(F.silentCone, 0, 360) * 0.5))
	local range = math.clamp(F.silentRange, 0, MAX_RANGE)
	local candidates = {}
	for _, character in ipairs(H.opponents(F.silentBots, F.silentTeam)) do
		for _, name in ipairs(HIT_PARTS) do
			local part = character:FindFirstChild(name)
			if part and part:IsA("BasePart") then
				local offset = part.Position - origin
				local distance = offset.Magnitude
				if distance > 0 and distance <= range then
					local alignment = direction:Dot(offset.Unit)
					if alignment >= minimumDot then
						table.insert(candidates, { character = character, alignment = alignment, distance = distance })
					end
				end
				break
			end
		end
	end
	table.sort(candidates, function(a, b)
		if a.alignment == b.alignment then return a.distance < b.distance end
		return a.alignment > b.alignment
	end)
	for _, candidate in ipairs(candidates) do
		for _, name in ipairs(HIT_PARTS) do
			local part = candidate.character:FindFirstChild(name)
			if part and part:IsA("BasePart") then
				local offset = part.Position - origin
				if offset.Magnitude > 0 and offset.Magnitude <= range and direction:Dot(offset.Unit) >= minimumDot then
					local hit = rawRaycast(mine, origin, part.Position)
					if hit and H.characterFromHit(hit.Instance) == candidate.character then
						return part.Position, hit.Instance, hit.Position
					end
				end
			end
		end
	end
	return nil
end

function H.redirect(arguments)
	if not alive() or not F.silent then return nil end
	if arguments.n ~= 6 or arguments[1] ~= "Shoot" or typeof(arguments[2]) ~= "Vector3" or typeof(arguments[3]) ~= "Vector3" then
		return nil
	end
	local ok, position, part, hitPosition = pcall(H.silentPick, arguments[2], arguments[3])
	if ok and position then
		arguments[3], arguments[4], arguments[5] = position, part, hitPosition
		return arguments
	end
	return nil
end

if not shared.FacilityDeagleHook then
	shared.FacilityDeagleHook = { redirect = nil, remote = nil }
	local state = shared.FacilityDeagleHook
	if hookmetamethod and newcclosure and getnamecallmethod and setnamecallmethod then
		local original
		original = hookmetamethod(game, "__namecall", newcclosure(function(receiver, ...)
			local redirect = state.redirect
			if redirect and receiver == state.remote then
				local method = getnamecallmethod()
				if method == "FireServer" then
					local changed = redirect(table.pack(...))
					setnamecallmethod(method)
					if changed then return original(receiver, table.unpack(changed, 1, changed.n)) end
				end
			end
			return original(receiver, ...)
		end))
		state.installed = true
	end
end
shared.FacilityDeagleHook.remote = S.game.remote
shared.FacilityDeagleHook.redirect = H.redirect
if not shared.FacilityDeagleHook.installed then
	table.insert(moduleErrors, "silent aim: your executor cannot hook remotes")
elseif not S.game.remote or not S.game.deagle then
	table.insert(moduleErrors, "silent aim: game modules not found, rejoin fully then execute again")
end

function H.predicted(part)
	local character = part.Parent
	local root = character and (character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Torso") or character:FindFirstChild("UpperTorso"))
	if root and root:IsA("BasePart") then
		local ok, ping = pcall(LocalPlayer.GetNetworkPing, LocalPlayer)
		return part.Position + root.AssemblyLinearVelocity * ((ok and ping or 0.03) * 1.85)
	end
	return part.Position
end

function H.fakeRaycast(...)
	if alive() and F.killAll then
		for part in pairs(S.killTargets) do
			if part.Parent and H.attackable(part.Parent, false) then
				return { Instance = part, Position = H.predicted(part), Normal = Vector3.yAxis, Material = Enum.Material.Plastic }
			end
		end
	end
	return rawRaycast(...)
end

if S.game.deagle and rawRaycast then S.game.deagle.Raycast = H.fakeRaycast end

function H.shootAt(position)
	local controller = S.game.controller
	if type(controller.Shoot) == "function" then
		pcall(controller.Shoot, position)
	elseif type(controller.Fire) == "function" then
		pcall(controller.Fire, position)
	end
end

function H.killSweep()
	local controller = S.game.controller
	local mine = LocalPlayer.Character
	local root = mine and (mine:FindFirstChild("HumanoidRootPart") or mine:FindFirstChild("Torso"))
	local humanoid = mine and mine:FindFirstChildOfClass("Humanoid")
	if not controller or not root or not humanoid or humanoid.Health <= 0 then return end

	controller.ShootCooldownUntil = 0
	controller.CanShoot = true
	controller.CurrentSpread = 0
	if type(controller.WeaponStats) == "table" then controller.WeaponStats.Spread = 0 end

	table.clear(S.killTargets)
	local pool = H.opponents(true, true)
	table.sort(pool, function(a, b)
		local ra, rb = H.botRoot(a), H.botRoot(b)
		if ra and rb then return (root.Position - ra.Position).Magnitude < (root.Position - rb.Position).Magnitude end
		return false
	end)

	local panic = humanoid.Health / math.max(humanoid.MaxHealth, 1) * 100 <= F.killPanic
	local function partOf(character)
		return character:FindFirstChild(F.killPart) or character:FindFirstChild("Head")
	end
	if panic then
		local chosen
		for _, character in ipairs(pool) do
			local part = partOf(character)
			if part and H.visible(root.Position, part.Position, character) then
				chosen = part
				break
			end
		end
		if not chosen then
			for _, character in ipairs(pool) do
				chosen = partOf(character)
				if chosen then break end
			end
		end
		if chosen then
			S.killTargets[chosen] = true
			H.shootAt(H.predicted(chosen))
		end
		return
	end
	for _, character in ipairs(pool) do
		local part = partOf(character)
		if part then
			S.killTargets[part] = true
			H.shootAt(H.predicted(part))
		end
	end
end

H.spawn(function()
	while alive() do
		task.wait(math.max(F.killDelay, 0.01))
		if F.killAll then pcall(H.killSweep) else table.clear(S.killTargets) end
	end
end)

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

function H.triggerValid(character)
	if not character then return false end
	if not H.attackable(character, F.triggerTeam) then return false end
	local owner = Players:GetPlayerFromCharacter(character)
	if owner then return owner ~= LocalPlayer end
	return F.bots or character:GetAttribute("IsBot") == true or character:GetAttribute("TutorialTarget") == true
end

function H.triggerTarget()
	local camera = H.camera()
	if not camera then return nil end
	if F.triggerMode == "Target" then
		local target = Aimbot and Aimbot.Target
		local record = target and Entity and Entity:Get(target)
		local character = record and record.Character
		return H.triggerValid(character) and character or nil
	end
	local center = H.center()
	if F.triggerMode == "Crosshair" then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { LocalPlayer.Character, camera }
		local ray = camera:ViewportPointToRay(center.X, center.Y)
		local hit = workspace:Raycast(ray.Origin, ray.Direction * 5000, params)
		local character = hit and H.characterFromHit(hit.Instance)
		return H.triggerValid(character) and character or nil
	end
	local radius = F.triggerFov > 0 and F.triggerFov or 12
	for _, character in ipairs(H.opponents(F.bots, F.triggerTeam)) do
		local head = character:FindFirstChild("Head") or character:FindFirstChild("HeadHitbox")
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
	F.silent, F.killAll, F.trigger = false, false, false
	H.triggerRelease()
	H.clearBots()
	F.bots = false
	if shared.FacilityDeagleHook then shared.FacilityDeagleHook.redirect = nil end
	if S.game.deagle and rawRaycast and S.game.deagle.Raycast == H.fakeRaycast then S.game.deagle.Raycast = rawRaycast end
	for _, connection in ipairs(S.connections) do pcall(function() connection:Disconnect() end) end
	table.clear(S.connections)
	for _, thread in ipairs(S.threads) do
		if thread ~= coroutine.running() then pcall(task.cancel, thread) end
	end
	table.clear(S.threads)
	if Aimbot then pcall(function() Aimbot:Unload() end) end
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
		Flag = "dgl_aim_enable",
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
		Flag = "dgl_aim_key",
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
	H.T(U.aimBox, "Toggle Mode", "dgl_aim_toggle_mode", false, function(state) Aimbot.Settings.ToggleMode = state end)
	H.D(U.aimBox, "Priority", "dgl_aim_priority", { "Cursor", "Closest", "LowestHealth" }, "Cursor", function(value) Aimbot.Settings.Priority = value end)
	U.aimBox:Dropdown({
		Text = "Target Part",
		Flag = "dgl_aim_parts",
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
		Flag = "dgl_aim_random_part",
		Default = false,
		Callback = function(state) Aimbot.Settings.RandomPart = state end,
	}):Gear(function(panel)
		H.S(panel, "Interval", "dgl_aim_random_interval", 0.1, 3, 1, 1, function(value) Aimbot.Settings.RandomInterval = value end, " s")
	end)
	H.S(U.aimBox, "Smoothness", "dgl_aim_smoothness", 0.05, 1, 0.3, 2, function(value) Aimbot.Settings.Smoothness = value end)
	H.S(U.aimBox, "Sensitivity", "dgl_aim_sensitivity", 0.02, 1, 0.5, 2, function(value) Aimbot.Settings.Sensitivity = value end)
	H.D(U.aimBox, "Easing Style", "dgl_aim_easing_style", { "Linear", "Sine", "Quad", "Cubic", "Quart", "Quint", "Exponential", "Back" }, "Quad", function(value) Aimbot.Settings.EasingStyle = value end)
	H.D(U.aimBox, "Easing Direction", "dgl_aim_easing_direction", { "In", "Out", "InOut" }, "Out", function(value) Aimbot.Settings.EasingDirection = value end)
	H.S(U.aimBox, "Switch Delay", "dgl_aim_switch_delay", 0, 2, 0, 2, function(value) Aimbot.Settings.SwitchDelay = value end, " s")
	H.S(U.aimBox, "Max Distance", "dgl_aim_max_distance", 100, 5000, 3000, 0, function(value) Aimbot.Settings.MaxDistance = value end, " studs")

	U.fovBox = U.AimSub:Section("Fov", 2)
	U.fovBox:Toggle({
		Text = "Fov",
		Flag = "dgl_aim_fov_enabled",
		Default = true,
		Callback = function(state)
			Aimbot.Settings.FovCheck = state
			Aimbot.Settings.FovVisible = state
		end,
	})
		:ColorPicker({ Flag = "dgl_aim_fov_color", Default = Color3.fromRGB(255, 255, 255), Callback = function(color) Aimbot.Settings.FovColor = color end })
		:ColorPicker({ Flag = "dgl_aim_fov_lock_color", Default = Color3.fromRGB(255, 70, 70), Callback = function(color) Aimbot.Settings.FovLockColor = color end })
	U.fovBox:Slider({
		Text = "Radius",
		Flag = "dgl_aim_fov",
		Min = 20, Max = 600, Default = 180,
		Callback = function(value)
			Aimbot.Settings.Fov = value
			pcall(function() Aimbot:SetFov(value) end)
		end,
	})
	H.S(U.fovBox, "Thickness", "dgl_aim_fov_thickness", 1, 5, 1, 0, function(value) Aimbot.Settings.FovThickness = value end)
	H.S(U.fovBox, "Transparency", "dgl_aim_fov_transparency", 0, 1, 0.4, 2, function(value) Aimbot.Settings.FovTransparency = value end)
	H.T(U.fovBox, "Filled", "dgl_aim_fov_filled", false, function(state) Aimbot.Settings.FovFilled = state end)

	U.behaviourBox = U.AimSub:Section("Behaviour", 2)
	H.T(U.behaviourBox, "Team Check", "dgl_aim_team_check", true, function(state) Aimbot.Settings.TeamCheck = state end)
	H.T(U.behaviourBox, "Wall Check", "dgl_aim_wall_check", true, function(state) Aimbot.Settings.WallCheck = state end)
	H.T(U.behaviourBox, "Multipoint", "dgl_aim_multipoint", false, function(state) Aimbot.Settings.Multipoint = state end)
	H.S(U.behaviourBox, "Deadzone", "dgl_aim_deadzone", 0, 200, 0, 0, function(value) Aimbot.Settings.Deadzone = value end)
	U.behaviourBox:Toggle({
		Text = "Sticky Target",
		Flag = "dgl_aim_sticky",
		Default = true,
		Callback = function(state) Aimbot.Settings.Sticky = state end,
	}):Gear(function(panel)
		H.S(panel, "Hold Fov", "dgl_aim_sticky_fov", 1, 3, 1.6, 1, function(value) Aimbot.Settings.StickyFov = value end)
	end)
	U.behaviourBox:Toggle({
		Text = "Prediction",
		Flag = "dgl_aim_prediction",
		Default = false,
		Callback = function(state) Aimbot.Settings.Prediction = state end,
	}):Gear(function(panel)
		H.S(panel, "Time", "dgl_aim_prediction_time", 0, 0.5, 0.1, 2, function(value) Aimbot.Settings.PredictionTime = value end, " s")
		H.T(panel, "Add Ping", "dgl_aim_prediction_ping", false, function(state) Aimbot.Settings.PingPrediction = state end)
	end)
	U.behaviourBox:Toggle({
		Text = "Target Line",
		Flag = "dgl_aim_target_line",
		Default = false,
		Callback = function(state) Aimbot.Settings.TargetLine = state end,
	}):ColorPicker({ Flag = "dgl_aim_target_line_color", Default = Color3.fromRGB(255, 70, 70), Callback = function(color) Aimbot.Settings.TargetLineColor = color end })
	H.T(U.behaviourBox, "Target Info", "dgl_aim_target_info", false, function(state) Aimbot.Settings.TargetInfo = state end)
end



U.teamBox = U.AimSub:Section("Targets", 1)
H.D(U.teamBox, "Team Check", "dgl_team_mode", { "Team", "TeamColor", "Off" }, "Team", function(value) H.setTeamMode(value) end)
H.botToggle(U.teamBox, "dgl_aim_bots")
U.teamBox:Label("Bots also show in the esp and can be locked by the aimbot.", { Style = "dim" })

U.silentBox = U.RageSub:Section("Silent Aim", 1)
U.silentBox:Toggle({
	Text = "Silent Aim",
	Flag = "dgl_silent",
	Default = false,
	Hint = "moves your shot onto a visible enemy inside the cone",
	Callback = function(state) F.silent = state end,
}):Keybind({ Default = "X", Flag = "dgl_silent_key" })
H.S(U.silentBox, "Aim Cone", "dgl_silent_cone", 0, 360, 360, 0, function(value) F.silentCone = value end, "°")
H.S(U.silentBox, "Max Distance", "dgl_silent_range", 50, MAX_RANGE, MAX_RANGE, 0, function(value) F.silentRange = value end, " studs")
H.T(U.silentBox, "Target Bots", "dgl_silent_bots", true, function(state) F.silentBots = state end)
H.T(U.silentBox, "Team Check", "dgl_silent_team", true, function(state) F.silentTeam = state end)
U.silentBox:Label("360 hits anyone you can see, lower values keep it near your crosshair.", { Style = "dim" })

U.killBox = U.RageSub:Section("Kill All", 2)
U.killBox:Toggle({
	Text = "Kill All",
	Flag = "dgl_kill_all",
	Default = false,
	Hint = "shoots every enemy and bot on its own, very obvious",
	Callback = function(state)
		F.killAll = state
		if state and not S.game.controller then
			pcall(function() Library:Notify({ Title = "Kill All", Text = "The game's gun controller was not found.", Duration = 6, Style = "Warning" }) end)
		end
	end,
}):Keybind({ Default = "None", Flag = "dgl_kill_all_key" })
H.S(U.killBox, "Shot Interval", "dgl_kill_delay", 0.02, 0.5, 0.04, 2, function(value) F.killDelay = value end, " s")
H.D(U.killBox, "Aim Part", "dgl_kill_part", { "Head", "HeadHitbox", "UpperTorso", "Torso", "HumanoidRootPart" }, "Head", function(value) F.killPart = value end)
H.S(U.killBox, "Low Health Mode", "dgl_kill_panic", 0, 100, 40, 0, function(value) F.killPanic = value end, "%")
U.killBox:Label("Below this health, only the closest visible enemy is shot.", { Style = "dim" })

U.triggerBox = U.RageSub:Section("Trigger Bot", 2)
U.triggerBox:Toggle({
	Text = "Enable",
	Flag = "dgl_trigger",
	Default = false,
	Hint = "fires while an enemy is under your crosshair",
	Callback = function(state)
		F.trigger = state
		if not state then H.triggerRelease() end
	end,
}):Keybind({ Default = "T", Flag = "dgl_trigger_key" })
H.D(U.triggerBox, "Mode", "dgl_trigger_mode", { "Crosshair", "Target", "Fov" }, "Crosshair", function(value) F.triggerMode = value end)
H.S(U.triggerBox, "Fov", "dgl_trigger_fov", 0, 400, 0, 0, function(value) F.triggerFov = value end)
H.T(U.triggerBox, "Team Check", "dgl_trigger_team", true, function(state) F.triggerTeam = state end)
H.S(U.triggerBox, "Shot Delay", "dgl_trigger_delay", 0, 2, 0, 2, function(value)
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
	Flag = "dgl_esp_enable",
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
}):Keybind({ Default = "None", Flag = "dgl_esp_enable_key" })
U.espBox:Toggle({
	Text = "Box",
	Flag = "dgl_esp_box",
	Default = true,
	Callback = function(state) H.espSet("box", state) end,
})
	:ColorPicker({
		Flag = "dgl_esp_box_color",
		Default = Color3.fromRGB(255, 60, 60),
		Callback = function(color, alpha)
			H.espPair("boxColor", color, alpha)
			H.espPair("box3dColor", color, alpha)
		end,
	})
	:Gear(function(panel)
		H.D(panel, "Style", "dgl_esp_box_style", { "2D", "3D" }, "2D", function(value)
			H.espSet("box", value == "2D")
			H.espSet("box3d", value == "3D")
		end)
	end)
U.espBox:Toggle({
	Text = "Health Bar",
	Flag = "dgl_esp_health_bar",
	Default = true,
	Callback = function(state) H.espSet("healthBar", state) end,
})
	:ColorPicker({ Flag = "dgl_esp_health_healthy", Default = Color3.fromRGB(82, 197, 148), Callback = function(color) H.espSet("healthyColor", color) end })
	:ColorPicker({ Flag = "dgl_esp_health_dying", Default = Color3.fromRGB(240, 90, 102), Callback = function(color) H.espSet("dyingColor", color) end })
U.espBox:Toggle({
	Text = "Skeleton",
	Flag = "dgl_esp_skeleton",
	Default = false,
	Callback = function(state) H.espSet("skeleton", state) end,
}):ColorPicker({ Flag = "dgl_esp_skeleton_color", Default = Color3.new(1, 1, 1), Callback = function(color, alpha) H.espPair("skeletonColor", color, alpha) end })
U.espBox:Toggle({
	Text = "Tracers",
	Flag = "dgl_esp_tracer",
	Default = false,
	Callback = function(state) H.espSet("tracer", state) end,
})
	:ColorPicker({ Flag = "dgl_esp_tracer_color", Default = Color3.new(1, 1, 1), Callback = function(color, alpha) H.espPair("tracerColor", color, alpha) end })
	:Gear(function(panel)
		H.D(panel, "Origin", "dgl_esp_tracer_origin", { "Bottom", "Middle", "Top", "Mouse" }, "Bottom", function(value) H.espSet("tracerOrigin", value) end)
	end)
U.espBox:Toggle({
	Text = "Highlight",
	Flag = "dgl_esp_chams",
	Default = false,
	Callback = function(state) H.espSet("chams", state) end,
}):ColorPicker({ Flag = "dgl_esp_chams_color", Default = Color3.fromRGB(255, 60, 60), Callback = function(color, alpha) H.espPair("chamsFillColor", color, alpha) end })
U.espBox:Toggle({
	Text = "Off Screen Arrow",
	Flag = "dgl_esp_arrow",
	Default = false,
	Callback = function(state) H.espSet("offScreenArrow", state) end,
}):ColorPicker({ Flag = "dgl_esp_arrow_color", Default = Color3.new(1, 1, 1), Callback = function(color, alpha) H.espPair("offScreenArrowColor", color, alpha) end })

U.displayBox = U.Visuals:Section("Display", 2)
U.displayBox:Toggle({
	Text = "Name",
	Flag = "dgl_esp_name",
	Default = true,
	Callback = function(state) H.espSet("name", state) end,
}):ColorPicker({ Flag = "dgl_esp_name_color", Default = Color3.fromRGB(236, 241, 250), Callback = function(color, alpha) H.espPair("nameColor", color, alpha) end })
U.displayBox:Toggle({
	Text = "Distance",
	Flag = "dgl_esp_distance",
	Default = true,
	Callback = function(state) H.espSet("distance", state) end,
}):ColorPicker({ Flag = "dgl_esp_distance_color", Default = Color3.fromRGB(170, 184, 205), Callback = function(color, alpha) H.espPair("distanceColor", color, alpha) end })
U.displayBox:Toggle({
	Text = "Weapon",
	Flag = "dgl_esp_weapon",
	Default = true,
	Callback = function(state) H.espSet("weapon", state) end,
}):ColorPicker({ Flag = "dgl_esp_weapon_color", Default = Color3.fromRGB(255, 220, 100), Callback = function(color, alpha) H.espPair("weaponColor", color, alpha) end })
H.T(U.displayBox, "Health", "dgl_esp_health_text", false, function(state) H.espSet("healthText", state) end)
H.T(U.displayBox, "Team Color", "dgl_esp_team_color", false, function(state) Esp.sharedSettings.useTeamColor = state end)
H.T(U.displayBox, "Rainbow", "dgl_esp_rainbow", false, function(state) Esp.sharedSettings.rainbow = state end)
H.S(U.displayBox, "Text Size", "dgl_esp_text_size", 8, 24, 13, 0, function(value) Esp.sharedSettings.textSize = value end)
H.S(U.displayBox, "Max Distance", "dgl_esp_max_distance", 100, 5000, 1500, 0, function(value) H.espSet("maxDistance", value) end, " studs")
U.displayBox:Toggle({
	Text = "Show Teammates",
	Flag = "dgl_esp_allies",
	Default = false,
	Callback = function(state) Esp.teamSettings.friendly.enabled = state end,
}):ColorPicker({
	Flag = "dgl_esp_ally_color",
	Default = Color3.fromRGB(0, 200, 255),
	Callback = function(color)
		Esp.teamSettings.friendly.boxColor = { color, 1 }
		Esp.teamSettings.friendly.nameColor = { color, 1 }
	end,
})



U.espBotsBox = U.Visuals:Section("Bots", 2)
H.botToggle(U.espBotsBox, "dgl_esp_bots")

local SaveManager = Library.SaveManager
local InterfaceManager = Library.InterfaceManager
local ThemeManager = Library.ThemeManager

SaveManager:SetLibrary(Library)
InterfaceManager:SetLibrary(Library)
InterfaceManager:SetWindow(Window)
ThemeManager:SetLibrary(Library)

SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({ "dgl_kill_all" })
InterfaceManager:SetFolder("Facility")
ThemeManager:SetFolder("Facility")
SaveManager:SetFolder("Facility/84556640895285")

InterfaceManager:BuildInterfaceSection(U.Settings, 1)
SaveManager:BuildConfigSection(U.Settings, 2)
ThemeManager:Mount(Window)

Window:SetTab(U.Combat)

Library:Notify("Facility", "Deagle Arena loaded.", 4)

SaveManager:LoadAutoloadConfig()
ThemeManager:Load()
