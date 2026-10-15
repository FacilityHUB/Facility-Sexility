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
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local H = {}
local U = {}
local S = {
	connections = {}, drawings = {}, instances = {}, threads = {}, originals = {},
	chams = {}, hitbox = {}, pickups = {}, pickupConns = {}, xray = {}, lag = {}, streamer = {},
	targetPoint = nil, firing = false, syntheticUntil = 0, nextFire = 0,
}

local F = {
	teamMode = "Team",

	silent = false, silentMethod = "Module", silentFov = 180, silentShowFov = false, silentPart = "Head",
	silentRange = 1200, silentLead = 0, silentTeam = true, silentVisible = false, silentFiring = true,
	silentHitChance = 100,
	rageFire = false, rageDelay = 0.15,

	trigger = false, triggerTeam = true, triggerDelay = 0,

	hitbox = false, hitboxMode = "All", hitboxSize = 21, hitboxTrans = 6, hitboxTeam = true, hitboxNoCol = false,

	hitSound = false, killSound = false, hitSoundName = "NL Hitmarker", killSoundName = "NL Kill", soundVolume = 0.6,

	autofarm = false,

	bhop = false, bhopBoost = 30, debris = false, debrisItem = "Both",
	antiAim = false, aaMode = "Spin", aaSpeed = 10, aaJitter = 80,
	thirdPerson = false, tpDistance = 5, tpHeight = 2,

	chams = false, chamsVisible = Color3.fromRGB(255, 70, 70), chamsHidden = Color3.fromRGB(255, 200, 60),
	chamsAllies = false, chamsAlly = Color3.fromRGB(80, 200, 120), chamsThrough = true,

	gradient = false, gradientStart = Color3.fromRGB(255, 45, 90), gradientEnd = Color3.fromRGB(75, 100, 255),
	gradientSpeed = 1,

	armCharms = false, armMaterial = "Plastic", armColor = Color3.fromRGB(50, 50, 50),
	gunCharms = false, gunMaterial = "Plastic", gunColor = Color3.fromRGB(50, 50, 50),
	rainbow = false, rainbowFast = false,
	xray = false,

	infAmmo2 = false, fastReload = false, fastFire = false, alwaysAuto = false, noSpread = false, noRecoil = false,

	camFov = 70, fullbright = false, dayTime = false, antiLag = false, streamer = false,
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

function H.wkspc(name)
	local folder = ReplicatedStorage:FindFirstChild("wkspc")
	return folder and folder:FindFirstChild(name) or nil
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

function H.arms()
	local camera = workspace.CurrentCamera
	return camera and camera:FindFirstChild("Arms") or nil
end

H.track(UserInputService.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then S.firing = true end
end))

H.track(UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then S.firing = false end
end))

S.rayParams = RaycastParams.new()
S.rayParams.FilterType = Enum.RaycastFilterType.Exclude

function H.clearLine(origin, part, character)
	S.rayParams.FilterDescendantsInstances = { LocalPlayer.Character, workspace.CurrentCamera }
	local hit = workspace:Raycast(origin, part.Position - origin, S.rayParams)
	return hit == nil or hit.Instance:IsDescendantOf(character)
end

function H.silentPick(origin)
	local camera = workspace.CurrentCamera
	if not camera then return nil end

	local center = camera.ViewportSize / 2
	local bestPoint, bestDistance = nil, nil

	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if player ~= LocalPlayer and character and (not F.silentTeam or H.enemy(player)) then
			local humanoid = H.humanoid(character)
			local part = character:FindFirstChild(F.silentPart) or character:FindFirstChild("Head") or H.root(character)

			if humanoid and humanoid.Health > 0 and part and (part.Position - origin).Magnitude <= F.silentRange then
				local screen, onScreen = camera:WorldToViewportPoint(part.Position)
				local distance = (Vector2.new(screen.X, screen.Y) - center).Magnitude

				if onScreen and screen.Z > 0 and distance <= F.silentFov and (not bestDistance or distance < bestDistance) then
					if not F.silentVisible or H.clearLine(origin, part, character) then
						bestDistance = distance
						bestPoint = part.Position + part.AssemblyLinearVelocity * (F.silentLead / 1000)
					end
				end
			end
		end
	end

	return bestPoint
end

H.track(RunService.RenderStepped:Connect(function()
	if not (F.silent or F.rageFire) then
		S.targetPoint = nil
		return
	end

	local camera = workspace.CurrentCamera
	local root = H.root()
	S.cameraPos = camera and camera.CFrame.Position
	S.rootPos = root and root.Position

	if not S.cameraPos then
		S.targetPoint = nil
		return
	end

	S.busy = true
	local ok, point = pcall(H.silentPick, S.cameraPos)
	S.busy = false
	S.targetPoint = ok and point or nil
end))

function H.shouldRedirect()
	if not F.silent or not S.targetPoint then return false end
	if F.silentFiring and not S.firing and os.clock() > S.syntheticUntil then return false end
	if F.silentHitChance < 100 and math.random(1, 100) > F.silentHitChance then return false end
	return true
end

function H.redirect(origin, direction)
	if typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" or direction.Magnitude < 40 then return nil end

	local nearCamera = S.cameraPos and (origin - S.cameraPos).Magnitude <= 75
	local nearRoot = S.rootPos and (origin - S.rootPos).Magnitude <= 75
	if not (nearCamera or nearRoot) then return nil end
	if not H.shouldRedirect() then return nil end

	local aim = S.targetPoint - origin
	if aim.Magnitude < 1 then return nil end
	return aim.Unit * math.min(15000, math.max(direction.Magnitude, aim.Magnitude + 2))
end

function H.installModuleSilent()
	if S.castOriginal then return true end

	local ok, module = pcall(function()
		return require(ReplicatedStorage:WaitForChild("Modules", 5):WaitForChild("GeneralFunctions", 5))
	end)

	if not ok or type(module) ~= "table" or type(module.cast) ~= "function" then
		ok, module = H.gcall(function()
			return require(ReplicatedStorage:WaitForChild("Modules", 5):WaitForChild("GeneralFunctions", 5))
		end)
	end

	if not ok or type(module) ~= "table" or type(module.cast) ~= "function" then return false end

	local original = module.cast
	S.castModule = module
	S.castOriginal = original

	module.cast = function(ray, ...)
		if alive() and F.silent and F.silentMethod == "Module" and typeof(ray) == "Ray" then
			local direction = H.redirect(ray.Origin, ray.Direction)
			if direction then ray = Ray.new(ray.Origin, direction) end
		end
		return original(ray, ...)
	end

	return true
end

function H.installRaycastSilent()
	if S.namecallHooked then return true end

	if type(hookmetamethod) ~= "function" or type(getnamecallmethod) ~= "function" or type(checkcaller) ~= "function" then
		return false
	end

	local old
	local function intercept(self, ...)
		if alive() and F.silent and F.silentMethod == "Raycast" and self == workspace and not S.busy and not checkcaller() then
			local method = getnamecallmethod()

			if method == "Raycast" then
				local args = table.pack(...)
				S.busy = true
				local ok, direction = pcall(H.redirect, args[1], args[2])
				S.busy = false
				if ok and direction then
					args[2] = direction
					return old(self, table.unpack(args, 1, args.n))
				end
			elseif method == "FindPartOnRay" or method == "FindPartOnRayWithIgnoreList" or method == "FindPartOnRayWithWhitelist" then
				local args = table.pack(...)
				local ray = args[1]
				if typeof(ray) == "Ray" then
					S.busy = true
					local ok, direction = pcall(H.redirect, ray.Origin, ray.Direction)
					S.busy = false
					if ok and direction then
						args[1] = Ray.new(ray.Origin, direction)
						return old(self, table.unpack(args, 1, args.n))
					end
				end
			end
		end

		return old(self, ...)
	end

	local ok, original = pcall(hookmetamethod, game, "__namecall",
		type(newcclosure) == "function" and newcclosure(intercept) or intercept)

	if not ok or type(original) ~= "function" then return false end

	old = original
	S.namecallHooked = true
	return true
end

function H.setSilent(state)
	F.silent = state
	if not state then return true end

	local installed
	if F.silentMethod == "Module" then
		installed = H.installModuleSilent()
		if not installed then H.notify("Silent Aim", "GeneralFunctions.cast not found, try the Raycast method.", 6) end
	else
		installed = H.installRaycastSilent()
		if not installed then H.notify("Silent Aim", "This executor cannot hook raycasts.", 6) end
	end

	if not installed then F.silent = false end
	return installed
end

function H.uninstallSilent()
	if S.castModule and S.castOriginal then
		pcall(function() S.castModule.cast = S.castOriginal end)
	end
	S.castModule, S.castOriginal = nil, nil
end

U.silentCircle = H.drawing("Circle", {
	Visible = false, Color = Color3.fromRGB(220, 25, 25), Filled = false, Thickness = 1.5, NumSides = 64, Transparency = 1,
})

H.track(RunService.RenderStepped:Connect(function()
	if not U.silentCircle then return end
	local camera = workspace.CurrentCamera
	local show = F.silent and F.silentShowFov and camera ~= nil
	U.silentCircle.Visible = show
	if show then
		U.silentCircle.Position = camera.ViewportSize / 2
		U.silentCircle.Radius = F.silentFov
	end
end))

H.track(RunService.RenderStepped:Connect(function()
	if not F.rageFire or os.clock() < S.nextFire then return end
	if not H.aliveChar() or not S.targetPoint then return end

	S.nextFire = os.clock() + F.rageDelay
	S.syntheticUntil = os.clock() + 0.12
	task.spawn(H.click)
end))

S.trigger = { holding = false, tap = 0, seen = 0 }

function H.triggerTarget()
	local camera = workspace.CurrentCamera
	if not camera then return nil end

	local ignore = { LocalPlayer.Character, camera }
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer and player.Character and not H.aliveChar(player.Character) then
			table.insert(ignore, player.Character)
		end
	end
	S.rayParams.FilterDescendantsInstances = ignore

	local hit = workspace:Raycast(camera.CFrame.Position, camera.CFrame.LookVector * 1000, S.rayParams)
	if not hit then return nil end

	local model = hit.Instance:FindFirstAncestorOfClass("Model")
	while model and not model:FindFirstChildOfClass("Humanoid") do
		model = model:FindFirstAncestorOfClass("Model")
	end
	if not model or not H.aliveChar(model) then return nil end

	local player = Players:GetPlayerFromCharacter(model)
	if not player or player == LocalPlayer then return nil end
	if F.triggerTeam and not H.enemy(player) then return nil end
	return player
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

function H.hitboxParts()
	if F.hitboxMode == "Head Only" then return { "Head" } end
	if F.hitboxMode == "Head + Torso" then return { "Head", "UpperTorso", "Torso" } end
	return { "UpperTorso", "Head", "HumanoidRootPart" }
end

function H.findPart(character, name)
	local exact = character:FindFirstChild(name)
	if exact and exact:IsA("BasePart") then return exact end
	for _, part in ipairs(character:GetChildren()) do
		if part:IsA("BasePart") and string.find(string.lower(part.Name), string.lower(name), 1, true) then return part end
	end
	return nil
end

function H.hitboxExtend(player)
	local character = player.Character
	if not character then return end

	S.hitbox[player] = S.hitbox[player] or {}
	local saved = S.hitbox[player]
	local alpha = F.hitboxTrans / 10

	for _, name in ipairs(H.hitboxParts()) do
		local part = H.findPart(character, name)
		if part then
			if saved[part] == nil then
				saved[part] = { CanCollide = part.CanCollide, Massless = part.Massless, Transparency = part.Transparency, Size = part.Size }
			end

			part.CanCollide = not F.hitboxNoCol
			part.Transparency = alpha
			part.Size = Vector3.new(F.hitboxSize, F.hitboxSize, F.hitboxSize)

			for _, decal in ipairs(part:GetChildren()) do
				if decal:IsA("Decal") or decal:IsA("Texture") then decal.Transparency = alpha end
			end
		end
	end
end

function H.hitboxRestore(player)
	local saved = S.hitbox[player]
	if not saved then return end

	for part, props in pairs(saved) do
		if part.Parent then
			pcall(function()
				part.CanCollide = props.CanCollide
				part.Massless = props.Massless
				part.Transparency = props.Transparency
				part.Size = props.Size
				for _, decal in ipairs(part:GetChildren()) do
					if decal:IsA("Decal") or decal:IsA("Texture") then decal.Transparency = props.Transparency end
				end
			end)
		end
	end

	S.hitbox[player] = nil
end

function H.hitboxRestoreAll()
	for player in pairs(S.hitbox) do H.hitboxRestore(player) end
end

function H.hitboxRefresh()
	if not F.hitbox then return end
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer and player.Character and H.root(player.Character) then
			if not F.hitboxTeam or H.enemy(player) then
				H.hitboxExtend(player)
			else
				H.hitboxRestore(player)
			end
		end
	end
end

H.track(RunService.Stepped:Connect(function()
	if F.hitbox then pcall(H.hitboxRefresh) end
end))

H.loop(0.5, function()
	for player in pairs(S.hitbox) do
		if not player.Parent or not player.Character or not player.Character:IsDescendantOf(game) then
			S.hitbox[player] = nil
		end
	end
end)

function H.setHitbox(state)
	F.hitbox = state
	if not state then H.hitboxRestoreAll() end
end

H.SOUNDS = {
	["NL Hitmarker"] = "rbxassetid://160248522",
	["NL Headshot"] = "rbxassetid://6383936267",
	["NL Kill"] = "rbxassetid://3120609515",
	["NL Click"] = "rbxassetid://7286442500",
	["NL Bell"] = "rbxassetid://8214292746",
}
H.SOUND_NAMES = { "NL Bell", "NL Click", "NL Headshot", "NL Hitmarker", "NL Kill" }

function H.playSound(name)
	local sound = Instance.new("Sound")
	sound.SoundId = H.SOUNDS[name] or H.SOUNDS["NL Hitmarker"]
	sound.Volume = F.soundVolume
	sound.Parent = workspace
	sound:Play()
	sound.Ended:Once(function() sound:Destroy() end)
	task.delay(5, function() if sound.Parent then sound:Destroy() end end)
end

function H.aimedAt(player)
	local character = player.Character
	local head = character and (character:FindFirstChild("Head") or H.root(character))
	local camera = workspace.CurrentCamera
	if not (head and camera) then return false end

	local direction = head.Position - camera.CFrame.Position
	if direction.Magnitude < 2 then return true end
	if camera.CFrame.LookVector:Dot(direction.Unit) < 0.985 then return false end

	S.rayParams.FilterDescendantsInstances = { LocalPlayer.Character, camera }
	local hit = workspace:Raycast(camera.CFrame.Position, direction, S.rayParams)
	return hit ~= nil and hit.Instance:IsDescendantOf(character)
end

function H.ourHit(player)
	if S.targetPoint and F.silent then return true end
	local mine, theirs = H.root(), player.Character and H.root(player.Character)
	if mine and theirs and (mine.Position - theirs.Position).Magnitude < 9 then return true end
	return H.aimedAt(player)
end

function H.bindSounds(player, humanoid)
	local last = humanoid.Health
	H.track(humanoid.HealthChanged:Connect(function(health)
		if last and last > 0 and (F.hitSound or F.killSound) then
			if health <= 0 then
				if F.killSound and H.ourHit(player) then H.playSound(F.killSoundName) end
			elseif health < last - 0.5 and F.hitSound and H.ourHit(player) then
				H.playSound(F.hitSoundName)
			end
		end
		last = health
	end))
end

function H.watchSounds(player)
	if player == LocalPlayer then return end

	local function bind(character)
		local humanoid = character and (character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 5))
		if humanoid then H.bindSounds(player, humanoid) end
	end

	H.track(player.CharacterAdded:Connect(function(character) task.wait(0.5) bind(character) end))
	if player.Character then task.spawn(bind, player.Character) end
end

for _, player in ipairs(Players:GetPlayers()) do H.watchSounds(player) end
H.track(Players.PlayerAdded:Connect(H.watchSounds))

S.farm = { holding = false, conn = nil }

function H.farmTarget()
	local root = H.root()
	if not root then return nil end

	local best, bestDistance = nil, math.huge
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer and H.enemy(player) and player.Character then
			local other = player.Character:FindFirstChild("HumanoidRootPart")
			if other and H.aliveChar(player.Character) then
				local distance = (root.Position - other.Position).Magnitude
				if distance < bestDistance then best, bestDistance = player, distance end
			end
		end
	end

	return best
end

function H.setAutofarm(state)
	F.autofarm = state

	if S.farm.conn then S.farm.conn:Disconnect() S.farm.conn = nil end

	local curse, scale = H.wkspc("CurrentCurse"), H.wkspc("TimeScale")

	if not state then
		if curse then pcall(function() curse.Value = "" end) end
		if scale then pcall(function() scale.Value = 1 end) end
		if S.farm.holding then H.mouseUp() S.farm.holding = false end
		return
	end

	if curse then pcall(function() curse.Value = "Infinite Ammo" end) end
	if scale then pcall(function() scale.Value = 12 end) end

	S.farm.conn = H.track(RunService.Stepped:Connect(function()
		if not F.autofarm then return end
		local root = H.root()
		if not root then return end

		local target = H.farmTarget()
		local camera = workspace.CurrentCamera

		if target then
			local other = target.Character.HumanoidRootPart
			root.CFrame = CFrame.new(other.Position - other.CFrame.LookVector * 2 + Vector3.new(0, 2, 0))
			local head = target.Character:FindFirstChild("Head")
			if head and camera then camera.CFrame = CFrame.new(camera.CFrame.Position, head.Position) end
			if not S.farm.holding then H.mouseDown() S.farm.holding = true end
		elseif S.farm.holding then
			H.mouseUp()
			S.farm.holding = false
		end
	end))
end

H.track(RunService.RenderStepped:Connect(function()
	if not (F.bhop and UserInputService:IsKeyDown(Enum.KeyCode.Space)) then return end

	local root, humanoid = H.root(), H.humanoid()
	if not (root and humanoid) then return end

	local state = humanoid:GetState()
	if state == Enum.HumanoidStateType.Landed or state == Enum.HumanoidStateType.Running then
		local camera = workspace.CurrentCamera
		if camera then
			local look = camera.CFrame.LookVector
			local flat = Vector3.new(look.X, 0, look.Z)
			if flat.Magnitude > 0.01 then
				root.AssemblyLinearVelocity = root.AssemblyLinearVelocity + flat.Unit * F.bhopBoost
			end
		end
		humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	end
end))

H.loop(0.1, function()
	if not F.debris then return end
	local root = H.root()
	local folder = workspace:FindFirstChild("debris")
	if not (root and folder) then return end

	for _, item in ipairs(folder:GetChildren()) do
		if (F.debrisItem == "Both" or item.Name == F.debrisItem) and item:IsA("BasePart") then
			item.CFrame = root.CFrame
		end
	end
end)

S.aa = { block = nil, rotate = nil, conn = nil, sign = 1 }

function H.aaBlock(character)
	character = character or LocalPlayer.Character
	if S.aa.block then S.aa.block:Disconnect() S.aa.block = nil end
	if S.aa.rotate then S.aa.rotate:Disconnect() S.aa.rotate = nil end
	if not character then return end

	local humanoid = H.humanoid(character)
	if humanoid then humanoid.AutoRotate = false end

	S.aa.block = H.track(character.ChildAdded:Connect(function(child)
		if child:IsA("BodyGyro") or child:IsA("AlignOrientation") or child:IsA("BodyAngularVelocity") then
			pcall(function() child:Destroy() end)
		end
	end))

	if humanoid then
		S.aa.rotate = H.track(humanoid:GetPropertyChangedSignal("AutoRotate"):Connect(function()
			if F.antiAim then humanoid.AutoRotate = false end
		end))
	end
end

function H.aaUnblock()
	if S.aa.block then S.aa.block:Disconnect() S.aa.block = nil end
	if S.aa.rotate then S.aa.rotate:Disconnect() S.aa.rotate = nil end
	local humanoid = H.humanoid()
	if humanoid then humanoid.AutoRotate = true end
end

function H.setAntiAim(state)
	F.antiAim = state
	if S.aa.conn then S.aa.conn:Disconnect() S.aa.conn = nil end

	if not state then
		H.aaUnblock()
		local root = H.root()
		if root then root.AssemblyAngularVelocity = Vector3.zero end
		H.fixCollision()
		return
	end

	H.aaBlock()

	S.aa.conn = H.track(RunService.Heartbeat:Connect(function()
		local character = LocalPlayer.Character
		local root, humanoid = H.root(character), H.humanoid(character)
		if not (root and humanoid) then return end

		for _, part in ipairs(character:GetDescendants()) do
			if part:IsA("BasePart") and part.CanCollide then part.CanCollide = false end
		end

		local state = humanoid:GetState()
		if state == Enum.HumanoidStateType.Freefall or state == Enum.HumanoidStateType.Jumping then
			root.AssemblyAngularVelocity = Vector3.zero
		elseif F.aaMode == "Spin" then
			root.AssemblyAngularVelocity = Vector3.new(0, F.aaSpeed, 0)
		else
			root.AssemblyAngularVelocity = Vector3.zero
			local camera = workspace.CurrentCamera
			if not camera then return end

			local look = Vector3.new(camera.CFrame.LookVector.X, 0, camera.CFrame.LookVector.Z)
			if look.Magnitude < 0.01 then return end

			S.aa.sign = -S.aa.sign
			local offset = F.aaMode == "Jitter" and S.aa.sign * F.aaJitter or 0
			root.CFrame = CFrame.lookAt(root.Position, root.Position - look) * CFrame.Angles(0, math.rad(offset), 0)
		end
	end))
end

H.track(LocalPlayer.CharacterAdded:Connect(function(character)
	task.wait(0.5)
	if not alive() then return end
	H.fixCollision(character)
	if F.antiAim then H.aaBlock(character) end
end))

S.tpBound = false

function H.setThirdPerson(state)
	F.thirdPerson = state

	if not state then
		if S.tpBound then pcall(function() RunService:UnbindFromRenderStep("FacilityThirdPerson") end) end
		S.tpBound = false
		return
	end

	if S.tpBound then return end
	S.tpBound = true

	RunService:BindToRenderStep("FacilityThirdPerson", Enum.RenderPriority.Camera.Value + 1, function()
		if not (alive() and F.thirdPerson) then return end
		local camera = workspace.CurrentCamera
		if not camera then return end

		camera.CFrame = camera.CFrame * CFrame.new(0, F.tpHeight, F.tpDistance)

		local arms = H.arms()
		if arms then pcall(function() arms:PivotTo(CFrame.new(0, -9999, 0)) end) end

		local character = LocalPlayer.Character
		if character then
			for _, part in ipairs(character:GetDescendants()) do
				if (part:IsA("BasePart") or part:IsA("Decal")) and part.LocalTransparencyModifier ~= 0 then
					part.LocalTransparencyModifier = 0
				end
			end
		end
	end)
end

function H.clearChams()
	for key, highlight in pairs(S.chams) do
		pcall(function() highlight:Destroy() end)
		S.chams[key] = nil
	end
end

function H.canSee(character, point)
	local camera = workspace.CurrentCamera
	if not camera then return false end
	S.rayParams.FilterDescendantsInstances = { LocalPlayer.Character, camera }
	local origin = camera.CFrame.Position
	local hit = workspace:Raycast(origin, point - origin, S.rayParams)
	return hit == nil or hit.Instance:IsDescendantOf(character)
end

function H.updateChams()
	if not F.chams then
		H.clearChams()
		return
	end

	local used = {}

	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local enemy = H.enemy(player)

		if player ~= LocalPlayer and character and H.aliveChar(character) and (enemy or F.chamsAllies) then
			used[player] = true

			local highlight = S.chams[player]
			if not highlight or not highlight.Parent then
				highlight = Instance.new("Highlight")
				highlight.FillTransparency = 0.75
				highlight.OutlineTransparency = 0.1
				highlight.Parent = H.overlay()
				S.chams[player] = highlight
			end

			local head = character:FindFirstChild("Head")
			local color
			if not enemy then
				color = F.chamsAlly
			elseif head and H.canSee(character, head.Position) then
				color = F.chamsVisible
			else
				color = F.chamsHidden
			end

			highlight.Adornee = character
			highlight.FillColor = color
			highlight.OutlineColor = color
			highlight.DepthMode = F.chamsThrough and Enum.HighlightDepthMode.AlwaysOnTop or Enum.HighlightDepthMode.Occluded
		end
	end

	for player, highlight in pairs(S.chams) do
		if not used[player] then
			pcall(function() highlight:Destroy() end)
			S.chams[player] = nil
		end
	end
end

H.loop(0.15, H.updateChams)

H.GRADIENT_KEYS = { "boxColor", "box3dColor", "tracerColor", "skeletonColor", "offScreenArrowColor" }

H.track(RunService.RenderStepped:Connect(function()
	if not F.gradient then return end
	local phase = F.gradientSpeed == 0 and 0 or (math.sin(os.clock() * F.gradientSpeed) + 1) / 2
	local color = F.gradientStart:Lerp(F.gradientEnd, phase)
	local team = Esp.teamSettings.enemy
	for _, key in ipairs(H.GRADIENT_KEYS) do
		local current = team[key]
		team[key] = { color, type(current) == "table" and current[2] or 1 }
	end
end))

function H.zigzag(x)
	return math.acos(math.cos(x * math.pi)) / math.pi
end

S.rainbow = { slow = 1, hue = 0 }

H.track(RunService.RenderStepped:Connect(function()
	if not (F.armCharms or F.gunCharms or F.rainbow or F.rainbowFast) then return end
	local arms = H.arms()
	if not arms then return end

	local rainbowColor
	if F.rainbowFast then
		S.rainbow.hue = (S.rainbow.hue + 0.1) % 1
		rainbowColor = Color3.fromHSV(S.rainbow.hue, 1, 1)
	elseif F.rainbow then
		S.rainbow.slow = S.rainbow.slow + 0.0001
		rainbowColor = Color3.fromHSV(H.zigzag(S.rainbow.slow), 1, 1)
	end

	for _, item in ipairs(arms:GetDescendants()) do
		if F.armCharms and (item.Name == "Right Arm" or item.Name == "Left Arm") and item:IsA("BasePart") then
			item.Material = Enum.Material[F.armMaterial]
			item.Color = F.armColor
		elseif F.armCharms and item:IsA("SpecialMesh") then
			if item.TextureId == "" then item.TextureId = "rbxassetid://0" end
			item.VertexColor = Vector3.new(F.armColor.R, F.armColor.G, F.armColor.B)
		elseif F.armCharms and (item.Name == "L" or item.Name == "R") then
			pcall(function() item:Destroy() end)
		elseif item:IsA("MeshPart") then
			if F.gunCharms then
				item.Material = Enum.Material[F.gunMaterial]
				item.Color = F.gunColor
			end
			if rainbowColor then item.Color = rainbowColor end
		end
	end
end))

function H.pickupLabel(parent, text)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = tostring(math.random(100000, 999999))
	billboard.AlwaysOnTop = true
	billboard.Size = UDim2.fromOffset(70, 24)
	billboard.StudsOffset = Vector3.new(0, 2, 0)
	billboard.Adornee = parent
	billboard.Parent = H.guiParent()

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 1, 0)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 12
	label.TextStrokeTransparency = 0.4
	label.TextColor3 = text == "HP Jug" and Color3.fromRGB(90, 255, 120) or Color3.fromRGB(255, 200, 60)
	label.Text = text
	label.Parent = billboard

	return billboard
end

function H.setPickupEsp(state, name, text)
	if S.pickupConns[name] then S.pickupConns[name]:Disconnect() S.pickupConns[name] = nil end

	for parent, billboard in pairs(S.pickups) do
		if parent.Name == name or not parent.Parent then
			pcall(function() billboard:Destroy() end)
			S.pickups[parent] = nil
		end
	end

	if not state then return end

	local function add(item)
		if item:IsA("TouchTransmitter") and item.Parent and item.Parent.Name == name and not S.pickups[item.Parent] then
			local parent = item.Parent
			S.pickups[parent] = H.pickupLabel(parent, text)
			parent.AncestryChanged:Once(function()
				if not parent:IsDescendantOf(workspace) and S.pickups[parent] then
					pcall(function() S.pickups[parent]:Destroy() end)
					S.pickups[parent] = nil
				end
			end)
		end
	end

	for _, item in ipairs(workspace:GetDescendants()) do add(item) end
	S.pickupConns[name] = H.track(workspace.DescendantAdded:Connect(add))
end

function H.setXray(state)
	F.xray = state

	if state then
		for _, part in ipairs(workspace:GetDescendants()) do
			local mine = LocalPlayer.Character
			if part:IsA("BasePart") and not (mine and part:IsDescendantOf(mine)) then
				local owner = part:FindFirstAncestorOfClass("Model")
				if not (owner and Players:GetPlayerFromCharacter(owner)) then
					if S.xray[part] == nil then S.xray[part] = part.Transparency end
					part.Transparency = 0.5
				end
			end
		end
		return
	end

	for part, value in pairs(S.xray) do
		pcall(function() part.Transparency = value end)
	end
	table.clear(S.xray)
end

H.GUN_FIELDS = {
	fastFire = { FireRate = true, BFireRate = true, FireDelay = true },
	alwaysAuto = { Auto = true, AutoFire = true, Automatic = true, AutoShoot = true, AutoGun = true },
	noSpread = { MaxSpread = true, Spread = true, SpreadControl = true },
	noRecoil = { RecoilControl = true, Recoil = true, CamShake = true },
	fastReload = { ReloadTime = true, EReloadTime = true },
}

H.GUN_VALUES = { fastFire = 0.02, alwaysAuto = true, noSpread = 0, noRecoil = 0, fastReload = 0.01 }

S.gun = { targets = {}, conn = nil, scan = nil }

function H.gunRescan()
	local targets = {}
	for key in pairs(H.GUN_FIELDS) do targets[key] = {} end

	local weapons = ReplicatedStorage:FindFirstChild("Weapons")
	if weapons then
		for _, item in ipairs(weapons:GetDescendants()) do
			for key, names in pairs(H.GUN_FIELDS) do
				if names[item.Name] and item:IsA("ValueBase") then table.insert(targets[key], item) end
			end
		end
	end

	S.gun.targets = targets
end

function H.gunActive()
	return F.fastFire or F.alwaysAuto or F.noSpread or F.noRecoil or F.fastReload
end

function H.gunRefresh()
	if not H.gunActive() then
		if S.gun.conn then S.gun.conn:Disconnect() S.gun.conn = nil end
		if S.gun.scan then S.gun.scan:Disconnect() S.gun.scan = nil end
		H.gunRestore()
		return
	end

	H.gunRestore()
	if S.gun.conn then return end
	H.gunRescan()

	local weapons = ReplicatedStorage:FindFirstChild("Weapons")
	if weapons and not S.gun.scan then
		S.gun.scan = H.track(weapons.ChildAdded:Connect(H.gunRescan))
	end

	S.gun.conn = H.track(RunService.Stepped:Connect(function()
		for key, list in pairs(S.gun.targets) do
			if F[key] then
				for _, item in ipairs(list) do
					H.setProp(item, "Value", H.GUN_VALUES[key])
				end
			end
		end
	end))
end

function H.gunRestore()
	for key, list in pairs(S.gun.targets) do
		if not F[key] then
			for _, item in ipairs(list) do H.restoreProp(item, "Value") end
		end
	end
end

function H.setInfAmmo1(state)
	local curse = H.wkspc("CurrentCurse")
	if curse then pcall(function() curse.Value = state and "Infinite Ammo" or "" end) end
end

H.track(RunService.Stepped:Connect(function()
	if not F.infAmmo2 then return end
	pcall(function()
		local variables = PlayerGui.GUI.Client.Variables
		variables.ammocount.Value = 99
		variables.ammocount2.Value = 99
	end)
end))

function H.effect(class, name)
	local effect = Lighting:FindFirstChild(name)
	if effect then return effect end
	effect = Instance.new(class)
	effect.Name = name
	effect.Parent = Lighting
	table.insert(S.instances, effect)
	return effect
end

S.shader = { brightness = Lighting.Brightness, fogEnd = Lighting.FogEnd, fogStart = Lighting.FogStart, shadows = Lighting.GlobalShadows, ready = false }
task.delay(0.5, function() S.shader.ready = true end)

H.EFFECT_NAMES = { "FacilityCC", "FacilityBloom", "FacilitySunRays", "FacilityDoF" }

function H.resetShaders()
	pcall(function()
		Lighting.Brightness = S.shader.brightness
		Lighting.FogEnd = S.shader.fogEnd
		Lighting.FogStart = S.shader.fogStart
		Lighting.GlobalShadows = S.shader.shadows
	end)
	for _, name in ipairs(H.EFFECT_NAMES) do
		local effect = Lighting:FindFirstChild(name)
		if effect then effect:Destroy() end
	end
end

function H.cc(key, value)
	if not S.shader.ready then return end
	H.effect("ColorCorrectionEffect", "FacilityCC")[key] = value
end

function H.tint(channel, value)
	if not S.shader.ready then return end
	local effect = H.effect("ColorCorrectionEffect", "FacilityCC")
	local color = effect.TintColor
	local r, g, b = color.R * 255, color.G * 255, color.B * 255
	if channel == "R" then r = value elseif channel == "G" then g = value else b = value end
	effect.TintColor = Color3.fromRGB(r, g, b)
end

function H.bloom(key, value)
	if not S.shader.ready then return end
	H.effect("BloomEffect", "FacilityBloom")[key] = value
end

H.track(workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	local camera = workspace.CurrentCamera
	if camera and F.camFov ~= 70 then camera.FieldOfView = F.camFov end
end))

H.loop(0.5, function()
	if F.fullbright then
		H.setProp(Lighting, "Brightness", 2)
		H.setProp(Lighting, "ClockTime", 14)
		H.setProp(Lighting, "FogEnd", 1e6)
		H.setProp(Lighting, "GlobalShadows", false)
		H.setProp(Lighting, "OutdoorAmbient", Color3.fromRGB(128, 128, 128))
	end
	if F.dayTime and not F.fullbright then H.setProp(Lighting, "ClockTime", 14) end
end)

function H.setFullbright(state)
	F.fullbright = state
	if not state then
		for _, key in ipairs({ "Brightness", "FogEnd", "GlobalShadows", "OutdoorAmbient" }) do H.restoreProp(Lighting, key) end
		if not F.dayTime then H.restoreProp(Lighting, "ClockTime") end
	end
end

function H.setDayTime(state)
	F.dayTime = state
	if not state and not F.fullbright then H.restoreProp(Lighting, "ClockTime") end
end

function H.fpsBoost()
	pcall(function()
		Lighting.GlobalShadows = false
		Lighting.FogEnd = 1e6
	end)
	for _, effect in ipairs(Lighting:GetChildren()) do
		if effect:IsA("BloomEffect") or effect:IsA("SunRaysEffect") or effect:IsA("DepthOfFieldEffect") or effect:IsA("BlurEffect") then
			effect.Enabled = false
		end
	end
end

function H.lagItem(item)
	if item:IsA("Decal") or item:IsA("Texture") then
		if S.lag[item] == nil then S.lag[item] = item.Texture end
		item.Texture = ""
	elseif item:IsA("ParticleEmitter") or item:IsA("Beam") or item:IsA("Trail") then
		if S.lag[item] == nil then S.lag[item] = item.Enabled end
		item.Enabled = false
	end
end

function H.setAntiLag(state)
	F.antiLag = state
	if S.lagConn then S.lagConn:Disconnect() S.lagConn = nil end

	if state then
		for _, item in ipairs(workspace:GetDescendants()) do pcall(H.lagItem, item) end
		S.lagConn = H.track(workspace.DescendantAdded:Connect(function(item) pcall(H.lagItem, item) end))
		return
	end

	for item, value in pairs(S.lag) do
		pcall(function()
			if item:IsA("Decal") or item:IsA("Texture") then item.Texture = value else item.Enabled = value end
		end)
	end
	table.clear(S.lag)
end

S.afk = nil

function H.setAntiAfk(state)
	if S.afk then S.afk:Disconnect() S.afk = nil end
	if not state then return end
	S.afk = H.track(LocalPlayer.Idled:Connect(function()
		pcall(function()
			local virtualUser = game:GetService("VirtualUser")
			virtualUser:CaptureController()
			virtualUser:ClickButton2(Vector2.new())
		end)
	end))
end

function H.plainReplace(text, needle, replacement)
	if needle == nil or needle == "" then return text end
	local out, start = {}, 1
	while true do
		local from, to = string.find(text, needle, start, true)
		if not from then break end
		table.insert(out, string.sub(text, start, from - 1))
		table.insert(out, replacement)
		start = to + 1
	end
	table.insert(out, string.sub(text, start))
	return table.concat(out)
end

function H.streamerFix(item)
	if not F.streamer then return end
	if not (item:IsA("TextLabel") or item:IsA("TextButton")) then return end

	local text = item.Text
	local changed = text
	for _, player in ipairs(Players:GetPlayers()) do
		changed = H.plainReplace(changed, player.Name, "Player")
		if player.DisplayName ~= player.Name then changed = H.plainReplace(changed, player.DisplayName, "Player") end
	end

	if changed ~= text then
		if item:GetAttribute("FacilityText") == nil then item:SetAttribute("FacilityText", text) end
		item.Text = changed
	end
end

function H.setStreamer(state)
	F.streamer = state
	for _, connection in ipairs(S.streamer) do pcall(function() connection:Disconnect() end) end
	table.clear(S.streamer)

	if state then
		local function watch(item)
			if item:IsA("TextLabel") or item:IsA("TextButton") then
				pcall(H.streamerFix, item)
				table.insert(S.streamer, item:GetPropertyChangedSignal("Text"):Connect(function() pcall(H.streamerFix, item) end))
			end
		end
		for _, item in ipairs(PlayerGui:GetDescendants()) do watch(item) end
		table.insert(S.streamer, PlayerGui.DescendantAdded:Connect(function(item) task.defer(watch, item) end))
		return
	end

	for _, item in ipairs(PlayerGui:GetDescendants()) do
		local original = item:GetAttribute("FacilityText")
		if original ~= nil then
			pcall(function() item.Text = original end)
			item:SetAttribute("FacilityText", nil)
		end
	end
end

function H.serverHop(pick)
	local request = (syn and syn.request) or http_request or request or (http and http.request)
	if type(request) ~= "function" then
		H.notify("Server Hop", "This executor has no http request.", 4)
		return
	end

	local ok, response = pcall(request, {
		Url = "https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=100",
		Method = "GET",
	})
	if not ok or not response or not response.Body then
		H.notify("Server Hop", "Server list unavailable.", 4)
		return
	end

	local decoded, data = pcall(function() return HttpService:JSONDecode(response.Body) end)
	if not decoded or type(data) ~= "table" or type(data.data) ~= "table" then return end

	local best
	for _, server in ipairs(data.data) do
		if server.id ~= game.JobId and server.playing < server.maxPlayers then
			if not best
				or (pick == "low" and server.playing < best.playing)
				or (pick == "high" and server.playing > best.playing) then
				best = server
			end
		end
	end

	if best then
		TeleportService:TeleportToPlaceInstance(game.PlaceId, best.id, LocalPlayer)
	else
		H.notify("Server Hop", "No server found.", 4)
	end
end

function H.copy(text)
	if type(setclipboard) == "function" then
		pcall(setclipboard, tostring(text))
		H.notify("Facility", "Copied to clipboard.", 3)
	else
		H.notify("Facility", "No clipboard support.", 4)
	end
end

shared.FacilityCleanup = function()
	F.silent, F.rageFire, F.trigger, F.autofarm = false, false, false, false
	pcall(H.uninstallSilent)
	pcall(H.triggerRelease)
	pcall(H.setAutofarm, false)
	pcall(H.setHitbox, false)
	pcall(H.setAntiAim, false)
	pcall(H.setThirdPerson, false)
	pcall(H.clearChams)
	pcall(H.setXray, false)
	pcall(H.setAntiLag, false)
	pcall(H.setStreamer, false)
	pcall(H.setPickupEsp, false, "DeadAmmo", "Ammo Box")
	pcall(H.setPickupEsp, false, "DeadHP", "HP Jug")
	F.fastFire, F.alwaysAuto, F.noSpread, F.noRecoil, F.fastReload = false, false, false, false, false
	pcall(H.gunRefresh)
	pcall(H.resetShaders)
	pcall(H.restoreAll)
	pcall(function()
		local camera = workspace.CurrentCamera
		if camera then camera.FieldOfView = 70 end
	end)

	for _, connection in ipairs(S.connections) do pcall(function() connection:Disconnect() end) end
	for _, connection in ipairs(S.streamer) do pcall(function() connection:Disconnect() end) end
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

U.Combat   = Window:Tab("Combat", "crosshair")
U.Rage     = Window:Tab("Rage", "skull")
U.Visuals  = Window:Tab("Visuals", "eye")
U.Weapons  = Window:Tab("Weapons", "sword")
U.PlayerT  = Window:Tab("Player", "user-round")
U.WorldT   = Window:Tab("World", "sun")
U.Misc     = Window:Tab("Misc", "wrench")
Window:TabDivider()
U.Settings = Window:Tab("Settings", "cog")

if #moduleErrors > 0 then
	U.failBox = U.Combat:Section("Modules", "full")
	for _, message in ipairs(moduleErrors) do
		U.failBox:Label(message, { Style = "dim" })
	end
end

U.teamBox = U.Combat:Section("Targets", 2)

H.D(U.teamBox, "Team Check", "ars_team_mode", { "Team", "TeamColor", "Off" }, "Team", function(value) H.setTeamMode(value) end)
U.teamBox:Label("Use Off in free for all if nobody gets targeted.", { Style = "dim" })

if Aimbot then

Aimbot.Settings.TeamCheck = true
Aimbot.Settings.WallCheck = true

U.aimBox = U.Combat:Section("Aimbot", 1)

U.aimBox:Toggle({
	Text = "Enable",
	Flag = "ars_aim_enable",
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
	Flag = "ars_aim_key",
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
	Flag = "ars_aim_toggle_mode",
	Default = false,
	Callback = function(state) Aimbot.Settings.ToggleMode = state end,
})

U.aimBox:Dropdown({
	Text = "Priority",
	Flag = "ars_aim_priority",
	Options = { "Cursor", "Closest", "LowestHealth" },
	Default = "Cursor",
	Callback = function(value) Aimbot.Settings.Priority = value end,
})

U.aimBox:Dropdown({
	Text = "Target Part",
	Flag = "ars_aim_parts",
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
	Flag = "ars_aim_random_part",
	Default = false,
	Callback = function(state) Aimbot.Settings.RandomPart = state end,
})
	:Gear(function(panel)
		panel:Slider({
			Text = "Interval",
			Flag = "ars_aim_random_interval",
			Min = 0.1, Max = 3, Default = 1,
			Decimals = 1,
			Suffix = " s",
			Callback = function(value) Aimbot.Settings.RandomInterval = value end,
		})
	end)

H.S(U.aimBox, "Smoothness", "ars_aim_smoothness", 0.05, 1, 0.3, 2, function(value) Aimbot.Settings.Smoothness = value end)
H.S(U.aimBox, "Sensitivity", "ars_aim_sensitivity", 0.02, 1, 0.5, 2, function(value) Aimbot.Settings.Sensitivity = value end)
H.D(U.aimBox, "Easing Style", "ars_aim_easing_style", { "Linear", "Sine", "Quad", "Cubic", "Quart", "Quint", "Exponential", "Back" }, "Quad", function(value) Aimbot.Settings.EasingStyle = value end)
H.D(U.aimBox, "Easing Direction", "ars_aim_easing_direction", { "In", "Out", "InOut" }, "Out", function(value) Aimbot.Settings.EasingDirection = value end)
H.S(U.aimBox, "Switch Delay", "ars_aim_switch_delay", 0, 2, 0, 2, function(value) Aimbot.Settings.SwitchDelay = value end, " s")
H.S(U.aimBox, "Max Distance", "ars_aim_max_distance", 100, 5000, 3000, 0, function(value) Aimbot.Settings.MaxDistance = value end, " studs")

U.fovBox = U.Combat:Section("Fov", 2)

U.fovBox:Toggle({
	Text = "Fov",
	Flag = "ars_aim_fov_enabled",
	Default = true,
	Callback = function(state)
		Aimbot.Settings.FovCheck = state
		Aimbot.Settings.FovVisible = state
	end,
})
	:ColorPicker({
		Flag = "ars_aim_fov_color",
		Default = Color3.fromRGB(255, 255, 255),
		Callback = function(color) Aimbot.Settings.FovColor = color end,
	})
	:ColorPicker({
		Flag = "ars_aim_fov_lock_color",
		Default = Color3.fromRGB(255, 70, 70),
		Callback = function(color) Aimbot.Settings.FovLockColor = color end,
	})

U.fovBox:Slider({
	Text = "Radius",
	Flag = "ars_aim_fov",
	Min = 20, Max = 600, Default = 180,
	Callback = function(value)
		Aimbot.Settings.Fov = value
		pcall(function() Aimbot:SetFov(value) end)
	end,
})

H.S(U.fovBox, "Thickness", "ars_aim_fov_thickness", 1, 5, 1, 0, function(value) Aimbot.Settings.FovThickness = value end)
H.S(U.fovBox, "Transparency", "ars_aim_fov_transparency", 0, 1, 0.4, 2, function(value) Aimbot.Settings.FovTransparency = value end)
H.T(U.fovBox, "Filled", "ars_aim_fov_filled", false, function(state) Aimbot.Settings.FovFilled = state end)

U.behaviourBox = U.Combat:Section("Behaviour", 2)

H.T(U.behaviourBox, "Team Check", "ars_aim_team_check", true, function(state) Aimbot.Settings.TeamCheck = state end)
H.T(U.behaviourBox, "Wall Check", "ars_aim_wall_check", true, function(state) Aimbot.Settings.WallCheck = state end)
H.T(U.behaviourBox, "Multipoint", "ars_aim_multipoint", false, function(state) Aimbot.Settings.Multipoint = state end)
H.S(U.behaviourBox, "Deadzone", "ars_aim_deadzone", 0, 200, 0, 0, function(value) Aimbot.Settings.Deadzone = value end)

U.behaviourBox:Toggle({
	Text = "Sticky Target",
	Flag = "ars_aim_sticky",
	Default = true,
	Callback = function(state) Aimbot.Settings.Sticky = state end,
})
	:Gear(function(panel)
		H.S(panel, "Hold Fov", "ars_aim_sticky_fov", 1, 3, 1.6, 1, function(value) Aimbot.Settings.StickyFov = value end)
	end)

U.behaviourBox:Toggle({
	Text = "Prediction",
	Flag = "ars_aim_prediction",
	Default = false,
	Callback = function(state) Aimbot.Settings.Prediction = state end,
})
	:Gear(function(panel)
		H.S(panel, "Time", "ars_aim_prediction_time", 0, 0.5, 0.1, 2, function(value) Aimbot.Settings.PredictionTime = value end, " s")
		H.T(panel, "Add Ping", "ars_aim_prediction_ping", false, function(state) Aimbot.Settings.PingPrediction = state end)
	end)

U.behaviourBox:Toggle({
	Text = "Target Line",
	Flag = "ars_aim_target_line",
	Default = false,
	Callback = function(state) Aimbot.Settings.TargetLine = state end,
})
	:ColorPicker({
		Flag = "ars_aim_target_line_color",
		Default = Color3.fromRGB(255, 70, 70),
		Callback = function(color) Aimbot.Settings.TargetLineColor = color end,
	})

H.T(U.behaviourBox, "Target Info", "ars_aim_target_info", false, function(state) Aimbot.Settings.TargetInfo = state end)

end

U.triggerBox = U.Combat:Section("Trigger Bot", 1)

U.triggerBox:Toggle({
	Text = "Enable",
	Flag = "ars_trigger",
	Default = false,
	Hint = "fires while an enemy sits under your crosshair",
	Callback = function(state)
		F.trigger = state
		if not state then H.triggerRelease() end
	end,
})
	:Keybind({ Default = "None", Flag = "ars_trigger_key" })

H.T(U.triggerBox, "Team Check", "ars_trigger_team", true, function(state) F.triggerTeam = state end)
H.S(U.triggerBox, "Shot Delay", "ars_trigger_delay", 0, 2, 0, 2, function(value)
	F.triggerDelay = value
	H.triggerRelease()
end, " s")
U.triggerBox:Label("0 holds and sprays, higher values tap.", { Style = "dim" })

U.silentBox = U.Rage:Section("Silent Aim", 1)

U.silentBox:Toggle({
	Text = "Silent Aim",
	Flag = "ars_silent",
	Default = false,
	Hint = "bends your shots toward the closest target inside the fov",
	Callback = function(state) H.setSilent(state) end,
})
	:ColorPicker({
		Flag = "ars_silent_fov_color",
		Default = Color3.fromRGB(220, 25, 25),
		Callback = function(color) if U.silentCircle then U.silentCircle.Color = color end end,
	})

H.D(U.silentBox, "Method", "ars_silent_method", { "Module", "Raycast" }, "Module", function(value)
	F.silentMethod = value
	if F.silent then H.setSilent(true) end
end)
H.S(U.silentBox, "Fov", "ars_silent_fov", 25, 600, 180, 0, function(value) F.silentFov = value end)
H.T(U.silentBox, "Show Fov", "ars_silent_show_fov", false, function(state) F.silentShowFov = state end)
H.D(U.silentBox, "Aim Part", "ars_silent_part", { "Head", "UpperTorso", "Torso", "HumanoidRootPart" }, "Head", function(value) F.silentPart = value end)
H.S(U.silentBox, "Range", "ars_silent_range", 100, 2000, 1200, 0, function(value) F.silentRange = value end, " studs")
H.S(U.silentBox, "Prediction", "ars_silent_lead", 0, 250, 0, 0, function(value) F.silentLead = value end, " ms")
H.S(U.silentBox, "Hit Chance", "ars_silent_hit_chance", 1, 100, 100, 0, function(value) F.silentHitChance = value end, "%")

U.silentChecks = U.Rage:Section("Checks", 2)
H.T(U.silentChecks, "Team Check", "ars_silent_team", true, function(state) F.silentTeam = state end)
H.T(U.silentChecks, "Visible Only", "ars_silent_visible", false, function(state) F.silentVisible = state end)
H.T(U.silentChecks, "Only While Firing", "ars_silent_firing", true, function(state) F.silentFiring = state end)

U.rageBox = U.Rage:Section("Rage", 2)

U.rageBox:Toggle({
	Text = "Auto Fire",
	Flag = "ars_rage_fire",
	Default = false,
	Hint = "shoots on its own whenever the silent aim has a target",
	Callback = function(state) F.rageFire = state end,
})
	:Gear(function(panel)
		H.S(panel, "Delay", "ars_rage_delay", 0.05, 0.5, 0.15, 2, function(value) F.rageDelay = value end, " s")
	end)

H.T(U.rageBox, "Autofarm", "ars_autofarm", false, function(state) H.setAutofarm(state) end, "teleports behind the nearest enemy and fires, high ban risk")

U.hitboxBox = U.Rage:Section("Hitbox", 1)

U.hitboxBox:Toggle({
	Text = "Hitbox Expander",
	Flag = "ars_hitbox",
	Default = false,
	Callback = function(state) H.setHitbox(state) end,
})
	:Gear(function(panel)
		H.T(panel, "No Collision", "ars_hitbox_nocol", false, function(state) F.hitboxNoCol = state end)
	end)

H.D(U.hitboxBox, "Target", "ars_hitbox_mode", { "All", "Head Only", "Head + Torso" }, "All", function(value)
	F.hitboxMode = value
	H.hitboxRestoreAll()
end)
H.S(U.hitboxBox, "Size", "ars_hitbox_size", 1, 25, 21, 0, function(value) F.hitboxSize = value end)
H.S(U.hitboxBox, "Transparency", "ars_hitbox_trans", 1, 10, 6, 0, function(value) F.hitboxTrans = value end)
H.T(U.hitboxBox, "Enemies Only", "ars_hitbox_team", true, function(state) F.hitboxTeam = state end)

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
	Flag = "ars_esp_enable",
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
	:Keybind({ Default = "None", Flag = "ars_esp_enable_key" })

U.espBox:Toggle({
	Text = "Box",
	Flag = "ars_esp_box",
	Default = true,
	Callback = function(state) H.espSet("box", state) end,
})
	:ColorPicker({
		Flag = "ars_esp_box_color",
		Default = Color3.fromRGB(255, 60, 60),
		Callback = function(color, alpha)
			H.espPair("boxColor", color, alpha)
			H.espPair("box3dColor", color, alpha)
		end,
	})
	:Gear(function(panel)
		H.D(panel, "Style", "ars_esp_box_style", { "2D", "3D" }, "2D", function(value)
			H.espSet("box", value == "2D")
			H.espSet("box3d", value == "3D")
		end)
	end)

U.espBox:Toggle({
	Text = "Health Bar",
	Flag = "ars_esp_health_bar",
	Default = true,
	Callback = function(state) H.espSet("healthBar", state) end,
})
	:ColorPicker({ Flag = "ars_esp_health_healthy", Default = Color3.fromRGB(82, 197, 148), Callback = function(color) H.espSet("healthyColor", color) end })
	:ColorPicker({ Flag = "ars_esp_health_dying", Default = Color3.fromRGB(240, 90, 102), Callback = function(color) H.espSet("dyingColor", color) end })

U.espBox:Toggle({
	Text = "Skeleton",
	Flag = "ars_esp_skeleton",
	Default = false,
	Callback = function(state) H.espSet("skeleton", state) end,
})
	:ColorPicker({ Flag = "ars_esp_skeleton_color", Default = Color3.new(1, 1, 1), Callback = function(color, alpha) H.espPair("skeletonColor", color, alpha) end })

U.espBox:Toggle({
	Text = "Tracers",
	Flag = "ars_esp_tracer",
	Default = false,
	Callback = function(state) H.espSet("tracer", state) end,
})
	:ColorPicker({ Flag = "ars_esp_tracer_color", Default = Color3.new(1, 1, 1), Callback = function(color, alpha) H.espPair("tracerColor", color, alpha) end })
	:Gear(function(panel)
		H.D(panel, "Origin", "ars_esp_tracer_origin", { "Bottom", "Middle", "Top", "Mouse" }, "Bottom", function(value) H.espSet("tracerOrigin", value) end)
	end)

U.espBox:Toggle({
	Text = "Highlight",
	Flag = "ars_esp_chams",
	Default = false,
	Callback = function(state) H.espSet("chams", state) end,
})
	:ColorPicker({ Flag = "ars_esp_chams_color", Default = Color3.fromRGB(255, 60, 60), Callback = function(color, alpha) H.espPair("chamsFillColor", color, alpha) end })

U.espBox:Toggle({
	Text = "Off Screen Arrow",
	Flag = "ars_esp_arrow",
	Default = false,
	Callback = function(state) H.espSet("offScreenArrow", state) end,
})
	:ColorPicker({ Flag = "ars_esp_arrow_color", Default = Color3.new(1, 1, 1), Callback = function(color, alpha) H.espPair("offScreenArrowColor", color, alpha) end })

U.displayBox = U.Visuals:Section("Display", 2)

U.displayBox:Toggle({
	Text = "Name",
	Flag = "ars_esp_name",
	Default = true,
	Callback = function(state) H.espSet("name", state) end,
})
	:ColorPicker({ Flag = "ars_esp_name_color", Default = Color3.fromRGB(236, 241, 250), Callback = function(color, alpha) H.espPair("nameColor", color, alpha) end })

U.displayBox:Toggle({
	Text = "Distance",
	Flag = "ars_esp_distance",
	Default = true,
	Callback = function(state) H.espSet("distance", state) end,
})
	:ColorPicker({ Flag = "ars_esp_distance_color", Default = Color3.fromRGB(170, 184, 205), Callback = function(color, alpha) H.espPair("distanceColor", color, alpha) end })

H.T(U.displayBox, "Health", "ars_esp_health_text", false, function(state) H.espSet("healthText", state) end)
H.T(U.displayBox, "Team Color", "ars_esp_team_color", false, function(state) Esp.sharedSettings.useTeamColor = state end)
H.S(U.displayBox, "Text Size", "ars_esp_text_size", 8, 24, 13, 0, function(value) Esp.sharedSettings.textSize = value end)
H.S(U.displayBox, "Max Distance", "ars_esp_max_distance", 100, 5000, 1500, 0, function(value) H.espSet("maxDistance", value) end, " studs")

U.displayBox:Toggle({
	Text = "Show Teammates",
	Flag = "ars_esp_allies",
	Default = false,
	Callback = function(state) Esp.teamSettings.friendly.enabled = state end,
})
	:ColorPicker({
		Flag = "ars_esp_ally_color",
		Default = Color3.fromRGB(60, 255, 120),
		Callback = function(color)
			Esp.teamSettings.friendly.boxColor = { color, 1 }
			Esp.teamSettings.friendly.nameColor = { color, 1 }
		end,
	})

U.gradientBox = U.Visuals:Section("Gradient Esp", 2)

U.gradientBox:Toggle({
	Text = "Gradient",
	Flag = "ars_gradient",
	Default = false,
	Hint = "fades the enemy esp colour between two colours",
	Callback = function(state) F.gradient = state end,
})
	:ColorPicker({ Flag = "ars_gradient_start", Default = F.gradientStart, Callback = function(color) F.gradientStart = color end })
	:ColorPicker({ Flag = "ars_gradient_end", Default = F.gradientEnd, Callback = function(color) F.gradientEnd = color end })

H.S(U.gradientBox, "Speed", "ars_gradient_speed", 0, 5, 1, 1, function(value) F.gradientSpeed = value end)

U.chamsBox = U.Visuals:Section("Chams", 1)

H.T(U.chamsBox, "Enable", "ars_chams", false, function(state) F.chams = state end, "colour switches when the target is behind cover")

U.chamsBox:Toggle({ Text = "Visible", Flag = "ars_chams_visible_toggle", Default = true, Callback = function() end })
	:ColorPicker({ Flag = "ars_chams_visible", Default = F.chamsVisible, Callback = function(color) F.chamsVisible = color end })

U.chamsBox:Toggle({ Text = "Behind Cover", Flag = "ars_chams_hidden_toggle", Default = true, Callback = function() end })
	:ColorPicker({ Flag = "ars_chams_hidden", Default = F.chamsHidden, Callback = function(color) F.chamsHidden = color end })

U.chamsBox:Toggle({
	Text = "Teammates",
	Flag = "ars_chams_allies",
	Default = false,
	Callback = function(state) F.chamsAllies = state end,
})
	:ColorPicker({ Flag = "ars_chams_ally", Default = F.chamsAlly, Callback = function(color) F.chamsAlly = color end })

H.T(U.chamsBox, "Through Walls", "ars_chams_through", true, function(state) F.chamsThrough = state end)

U.viewmodelBox = U.Visuals:Section("Viewmodel", 1)

U.viewmodelBox:Toggle({
	Text = "Arm Chams",
	Flag = "ars_arm_charms",
	Default = false,
	Callback = function(state) F.armCharms = state end,
})
	:ColorPicker({ Flag = "ars_arm_color", Default = F.armColor, Callback = function(color) F.armColor = color end })
	:Gear(function(panel)
		H.D(panel, "Material", "ars_arm_material", { "Plastic", "ForceField", "Neon", "Glass", "Wood", "Grass" }, "Plastic", function(value) F.armMaterial = value end)
	end)

U.viewmodelBox:Toggle({
	Text = "Gun Chams",
	Flag = "ars_gun_charms",
	Default = false,
	Callback = function(state) F.gunCharms = state end,
})
	:ColorPicker({ Flag = "ars_gun_color", Default = F.gunColor, Callback = function(color) F.gunColor = color end })
	:Gear(function(panel)
		H.D(panel, "Material", "ars_gun_material", { "Plastic", "ForceField", "Neon", "Glass", "Wood", "Grass" }, "Plastic", function(value) F.gunMaterial = value end)
	end)

H.T(U.viewmodelBox, "Rainbow Gun", "ars_rainbow", false, function(state) F.rainbow = state end)
H.T(U.viewmodelBox, "Rainbow Gun (Fast)", "ars_rainbow_fast", false, function(state) F.rainbowFast = state end)

U.pickupBox = U.Visuals:Section("World", 2)
H.T(U.pickupBox, "Ammo Box Esp", "ars_ammo_esp", false, function(state) H.setPickupEsp(state, "DeadAmmo", "Ammo Box") end)
H.T(U.pickupBox, "HP Jug Esp", "ars_hp_esp", false, function(state) H.setPickupEsp(state, "DeadHP", "HP Jug") end)
H.T(U.pickupBox, "Xray", "ars_xray", false, function(state) H.setXray(state) end)

U.ammoBox = U.Weapons:Section("Ammo & Fire", 1)
H.T(U.ammoBox, "Infinite Ammo v1", "ars_inf_ammo1", false, function(state) H.setInfAmmo1(state) end, "uses the infinite ammo curse")
H.T(U.ammoBox, "Infinite Ammo v2", "ars_inf_ammo2", false, function(state) F.infAmmo2 = state end, "keeps your ammo at 99")
H.T(U.ammoBox, "Fast Reload", "ars_fast_reload", false, function(state) F.fastReload = state H.gunRefresh() end)
H.T(U.ammoBox, "Fast Fire Rate", "ars_fast_fire", false, function(state) F.fastFire = state H.gunRefresh() end)
H.T(U.ammoBox, "Always Auto", "ars_always_auto", false, function(state) F.alwaysAuto = state H.gunRefresh() end)

U.accuracyBox = U.Weapons:Section("Accuracy", 2)
H.T(U.accuracyBox, "No Spread", "ars_no_spread", false, function(state) F.noSpread = state H.gunRefresh() end)
H.T(U.accuracyBox, "No Recoil", "ars_no_recoil", false, function(state) F.noRecoil = state H.gunRefresh() end)

U.soundBox = U.Weapons:Section("Hit Sounds", 2)

U.soundBox:Toggle({
	Text = "Hit Sound",
	Flag = "ars_hit_sound",
	Default = false,
	Callback = function(state) F.hitSound = state end,
})
	:Gear(function(panel)
		H.D(panel, "Sound", "ars_hit_sound_name", H.SOUND_NAMES, "NL Hitmarker", function(value) F.hitSoundName = value end)
	end)

U.soundBox:Toggle({
	Text = "Kill Sound",
	Flag = "ars_kill_sound",
	Default = false,
	Callback = function(state) F.killSound = state end,
})
	:Gear(function(panel)
		H.D(panel, "Sound", "ars_kill_sound_name", H.SOUND_NAMES, "NL Kill", function(value) F.killSoundName = value end)
	end)

H.S(U.soundBox, "Volume", "ars_sound_volume", 0, 2, 0.6, 2, function(value) F.soundVolume = value end)

U.moveBox = U.PlayerT:Section("Movement", 1)

if Movement then

Movement.Settings.WalkSpeedMode = "Velocity"
Movement.Settings.JumpMode = "Humanoid"

U.moveBox:Toggle({
	Text = "Fly",
	Flag = "ars_fly",
	Default = false,
	Callback = function(state) Movement:Fly(state) end,
})
	:Keybind({ Default = "None", Flag = "ars_fly_key" })
	:Gear(function(panel)
		H.S(panel, "Speed", "ars_fly_speed", 1, 20, 2, 1, function(value) Movement.Settings.FlySpeed = value end)
	end)

U.moveBox:Toggle({
	Text = "Walk Speed",
	Flag = "ars_walkspeed",
	Default = false,
	Callback = function(state) Movement:WalkSpeed(state and Movement.Settings.WalkSpeed or 16) end,
})
	:Gear(function(panel)
		H.D(panel, "Method", "ars_walk_method", { "Velocity", "CFrame", "Humanoid" }, "Velocity", function(value)
			Movement.Settings.WalkSpeedMode = value
			if Library.Flags["ars_walkspeed"] then Movement:WalkSpeed(Movement.Settings.WalkSpeed, value) end
		end)
	end)

H.S(U.moveBox, "Speed", "ars_walkspeed_value", 16, 200, 30, 0, function(value)
	Movement.Settings.WalkSpeed = value
	if Library.Flags["ars_walkspeed"] then Movement:WalkSpeed(value) end
end)

U.moveBox:Toggle({
	Text = "Jump Power",
	Flag = "ars_jump",
	Default = false,
	Callback = function(state) Movement:JumpPower(state and Movement.Settings.JumpPower or 50) end,
})
	:Gear(function(panel)
		H.S(panel, "Power", "ars_jump_value", 30, 300, 80, 0, function(value)
			Movement.Settings.JumpPower = value
			if Library.Flags["ars_jump"] then Movement:JumpPower(value) end
		end)
	end)

H.T(U.moveBox, "Infinite Jump", "ars_inf_jump", false, function(state) Movement:InfiniteJump(state) end)

U.moveBox:Toggle({
	Text = "Noclip",
	Flag = "ars_noclip",
	Default = false,
	Callback = function(state)
		Movement:Noclip(state)
		if not state then H.fixCollision() end
	end,
})
	:Keybind({ Default = "None", Flag = "ars_noclip_key" })

end

U.moveBox:Toggle({
	Text = "Bhop",
	Flag = "ars_bhop",
	Default = false,
	Hint = "hold space to keep hopping",
	Callback = function(state) F.bhop = state end,
})
	:Gear(function(panel)
		H.S(panel, "Boost", "ars_bhop_boost", 10, 100, 30, 0, function(value) F.bhopBoost = value end)
	end)

U.moveBox:Toggle({
	Text = "Collect Debris",
	Flag = "ars_debris",
	Default = false,
	Hint = "pulls dropped health and ammo to you",
	Callback = function(state) F.debris = state end,
})
	:Gear(function(panel)
		H.D(panel, "Object", "ars_debris_item", { "Both", "DeadHP", "DeadAmmo" }, "Both", function(value) F.debrisItem = value end)
	end)

H.B(U.moveBox, "Reset Collision", function() H.fixCollision() end)

U.aaBox = U.PlayerT:Section("Anti-Aim", 2)

U.aaBox:Toggle({
	Text = "Anti-Aim",
	Flag = "ars_anti_aim",
	Default = false,
	Callback = function(state) H.setAntiAim(state) end,
})
	:Keybind({ Default = "None", Flag = "ars_anti_aim_key" })

H.D(U.aaBox, "Mode", "ars_aa_mode", { "Spin", "Jitter", "Backwards" }, "Spin", function(value) F.aaMode = value end)
H.S(U.aaBox, "Spin Speed", "ars_aa_speed", 10, 100, 10, 0, function(value) F.aaSpeed = value end)
H.S(U.aaBox, "Jitter Angle", "ars_aa_jitter", 0, 180, 80, 0, function(value) F.aaJitter = value end)

U.viewBox = U.PlayerT:Section("View", 2)

U.viewBox:Toggle({
	Text = "Third Person",
	Flag = "ars_third_person",
	Default = false,
	Callback = function(state) H.setThirdPerson(state) end,
})
	:Keybind({ Default = "None", Flag = "ars_third_person_key" })

H.S(U.viewBox, "Distance", "ars_tp_distance", -15, 15, 5, 0, function(value) F.tpDistance = value end)
H.S(U.viewBox, "Height", "ars_tp_height", 0, 10, 2, 0, function(value) F.tpHeight = value end)
H.S(U.viewBox, "Field Of View", "ars_cam_fov", 70, 120, 70, 0, function(value)
	F.camFov = value
	local camera = workspace.CurrentCamera
	if camera then camera.FieldOfView = value end
end)

U.colorBox = U.WorldT:Section("Color", 1)

H.S(U.colorBox, "Game Brightness", "ars_brightness", 0, 10, math.clamp(S.shader.brightness, 0, 10), 2, function(value) Lighting.Brightness = value end)
H.S(U.colorBox, "Luminance", "ars_luminance", -1, 1, 0, 2, function(value) H.cc("Brightness", value) end)
H.S(U.colorBox, "Contrast", "ars_contrast", -1, 1, 0, 2, function(value) H.cc("Contrast", value) end)
H.S(U.colorBox, "Saturation", "ars_saturation", -1, 1, 0, 2, function(value) H.cc("Saturation", value) end)
H.S(U.colorBox, "Tint R", "ars_tint_r", 0, 255, 255, 0, function(value) H.tint("R", value) end)
H.S(U.colorBox, "Tint G", "ars_tint_g", 0, 255, 255, 0, function(value) H.tint("G", value) end)
H.S(U.colorBox, "Tint B", "ars_tint_b", 0, 255, 255, 0, function(value) H.tint("B", value) end)

U.bloomBox = U.WorldT:Section("Bloom", 2)
H.S(U.bloomBox, "Intensity", "ars_bloom_intensity", 0, 1, 0, 2, function(value) H.bloom("Intensity", value) end)
H.S(U.bloomBox, "Size", "ars_bloom_size", 1, 56, 24, 0, function(value) H.bloom("Size", value) end)
H.S(U.bloomBox, "Threshold", "ars_bloom_threshold", 0, 1, 0, 2, function(value) H.bloom("Threshold", value) end)

U.effectBox = U.WorldT:Section("Effects", 2)

H.T(U.effectBox, "No Fog", "ars_no_fog", false, function(state)
	if state then
		H.setProp(Lighting, "FogEnd", 1e9)
		H.setProp(Lighting, "FogStart", 1e9)
	else
		H.restoreProp(Lighting, "FogEnd")
		H.restoreProp(Lighting, "FogStart")
	end
end)
H.T(U.effectBox, "Sun Rays", "ars_sun_rays", false, function(state)
	if S.shader.ready or state then H.effect("SunRaysEffect", "FacilitySunRays").Intensity = state and 0.25 or 0 end
end)
H.T(U.effectBox, "Depth Of Field", "ars_dof", false, function(state)
	if S.shader.ready or state then H.effect("DepthOfFieldEffect", "FacilityDoF").FarIntensity = state and 0.5 or 0 end
end)
H.T(U.effectBox, "Global Shadows", "ars_shadows", S.shader.shadows, function(state) Lighting.GlobalShadows = state end)
H.B(U.effectBox, "Reset Shaders", H.resetShaders)

U.lightBox = U.WorldT:Section("Lighting", 1)
H.T(U.lightBox, "Fullbright", "ars_fullbright", false, function(state) H.setFullbright(state) end)
H.T(U.lightBox, "Day Time", "ars_day_time", false, function(state) H.setDayTime(state) end)
H.B(U.lightBox, "FPS Boost", H.fpsBoost)
H.T(U.lightBox, "Anti-Lag (Remove Textures)", "ars_anti_lag", false, function(state) H.setAntiLag(state) end)

U.serverBox = U.Misc:Section("Character & Server", 1)

H.B(U.serverBox, "Reset Character", function()
	local humanoid = H.humanoid()
	if humanoid then humanoid.Health = 0 end
end)

H.B(U.serverBox, "Rejoin Server", function()
	if game.JobId ~= "" then
		TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
	else
		TeleportService:Teleport(game.PlaceId, LocalPlayer)
	end
end)

U.serverBox:ButtonRow({
	{ Text = "Server Hop", Callback = function() task.spawn(H.serverHop, "any") end },
	{ Text = "Low Server", Callback = function() task.spawn(H.serverHop, "low") end },
})
H.B(U.serverBox, "High Server (not full)", function() H.serverHop("high") end)

U.copyBox = U.Misc:Section("Copy", 2)
U.copyBox:ButtonRow({
	{ Text = "JobId", Callback = function() H.copy(game.JobId) end },
	{ Text = "GameId", Callback = function() H.copy(game.GameId) end },
})
H.B(U.copyBox, "User Id", function() H.copy(LocalPlayer.UserId) end)

U.utilBox = U.Misc:Section("Utility", 2)
H.T(U.utilBox, "Anti-AFK", "ars_anti_afk", false, function(state) H.setAntiAfk(state) end)
H.T(U.utilBox, "Streamer Mode", "ars_streamer", false, function(state) H.setStreamer(state) end, "hides player names in the game UI")
H.B(U.utilBox, "Unload", function() if shared.FacilityCleanup then shared.FacilityCleanup() end end)

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
SaveManager:SetFolder("Facility/111958650")

InterfaceManager:BuildInterfaceSection(U.Settings, 1)
SaveManager:BuildConfigSection(U.Settings, 2)
ThemeManager:Mount(Window)

Window:SetTab(U.Combat)

if #moduleErrors > 0 then
	task.delay(1, function()
		for _, message in ipairs(moduleErrors) do Library:Error("Facility", message, 20) end
	end)
end

Library:Notify("Facility", "Arsenal loaded.", 4)

SaveManager:LoadAutoloadConfig()
ThemeManager:Load()
