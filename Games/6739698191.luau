--!nocheck
--!nolint UnknownGlobal

local FH      = shared.Facility
local Library = FH.Library

local SESSION = (shared.FacilitySession or 0) + 1
shared.FacilitySession = SESSION

local function alive()
	return shared.FacilitySession == SESSION
end

if shared.FacilityCleanup then
	pcall(shared.FacilityCleanup)
	shared.FacilityCleanup = nil
end

local MOVEMENT_URL = (FH.HubBase or "https://raw.githubusercontent.com/FacilityHUB/Facility-Sexility/refs/heads/main/") .. "CModules/FMovement.luau"

local Movement = nil

pcall(function()
	local source = game:HttpGet(MOVEMENT_URL .. "?v=" .. tostring(tick()):gsub("%.", ""))
	local chunk = loadstring(source)
	if chunk then Movement = chunk() end
end)

if type(Movement) == "table" then
	pcall(function() Movement:Load() end)
	FH.Movement = Movement
else
	Movement = nil
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local H = {}
local U = {}
local S = {
	connections = {}, drawings = {}, instances = {}, threads = {},
	originals = {}, hookInstalled = false, hooks = {},
}

local F = {
	autoVault = false, autoSlide = false, autoRunPC = false, autoRunMobile = false,
	speed = false, speedValue = 1,
	skipEndscreen = false,
	qr = false, pl = false, fs = false, ar = false, perkCooldown = 10,
	stretch = false, stretchAmount = 0.67,
	thirdPerson = false, infiniteZoom = false, camFov = false, camFovValue = 90,
	dbd = false, dbdDistance = 13, dbdHeight = 4.2, dbdRunSmooth = 0.1, dbdLookSmooth = 0.28,
	dbdSens = 0.55, dbdPitchMin = -0.55, dbdPitchMax = 0.45, dbdFov = 70,
	streamer = false, invis = false, moonwalk = false, moonwalkButton = false,
	crosshair = false, crossStyle = "Plus", crossSize = 8, crossThickness = 2,
	crossX = 0, crossY = 0, crossColor = Color3.fromRGB(255, 255, 255),

	skillCheck = false, skillMode = "Legit",
	genBoost = false, genMode = "Manual Repair",
	tof = false, tofPredict = false, tofBlock = false, tofLock = false, tofWall = false,
	tofLaser = true, tofTarget = "Killer", tofBlockKnocked = true,
	flashSilent = false, flashOffset = 1.5,
	antiHook = false, antiHookOffset = 250, antiHookHz = 44,
	tpGate = false, autoCrouch = false, unlimitedVault = false, antiSlowVault = false,
	flowstate = false, noFall = false, bypassGate = false, selfHeal = false, godMode = false,
	survAim = false, survAimFov = true, survAimRadius = 150, survAimDist = 300,
	survAimSmooth = 0.5, survAimPredict = 0.01, survAimPart = "Root", survAimHold = false,
	parryV1 = false, parryV1Safety = false, parryV1Aggressive = false, parryV1Circle = true,
	parryV1Radius = 15, parryV1Face = 0.7,
	parryV2 = false, parryV2Safety = false, parryV2Mode = "Legit", parryV2Trigger = "Remote",
	parryV2Face = 0.6, parryV2Circle = true, parryV2Range = 12,
	autoPallet = false, autoPalletSafety = true, autoPalletDistance = 10,

	killerAim = false, killerAimDist = 12, killerAimSmooth = 0.5,
	veil = false, veilPredict = false, veilShowFov = true, veilLead = 1.4,
	spearSpeed = 165, spearGravity = 103, auraSpeed = 165, auraGravity = 96.5,
	veilFov = 150, veilMaxDist = 500,
	antiBlind = false, antiParry = false, infiniteLunge = false, autoStalk = false,
	noSlowdown = false, hiddenNoCd = false, infiniteCorrupt = false,
	flaskSilent = false, flaskLaser = false, antiLoop = false,

	esp = false, espMax = 1000, espPlayer = false, espKiller = false, espName = true,
	espDistance = true, espStatus = false, espItem = false, espKillerWarn = false,
	espOutline = false, espHookCount = false,
	espGen = false, espGenName = true, espPallet = false, espWindow = false,
	espHook = false, espGate = false, espScp = false,
	fullBright = false, timeOfDay = 14, noFog = false, noShadow = false, lowGfx = false,
	nextKiller = false, mapName = false, killerPerks = false, stunIndicator = false, spectators = false,
}

local C = {
	player = Color3.fromRGB(60, 255, 60),
	killer = Color3.fromRGB(255, 60, 60),
	generator = Color3.fromRGB(255, 255, 0),
	generatorDone = Color3.fromRGB(0, 255, 0),
	pallet = Color3.fromRGB(60, 255, 255),
	hook = Color3.fromRGB(255, 105, 180),
	gate = Color3.fromRGB(255, 255, 255),
	window = Color3.fromRGB(60, 255, 255),
	scp = Color3.fromRGB(255, 0, 255),
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
			task.wait(type(interval) == "function" and interval() or interval)
		end
	end)
	table.insert(S.threads, thread)
	return thread
end

function H.notify(title, text, duration)
	pcall(function() Library:Notify(title, tostring(text), duration or 3) end)
end

function H.role()
	local team = LocalPlayer.Team
	if not team then return "Unknown" end
	if team.Name == "Killer" then return "Killer" end
	if team.Name == "Survivors" then return "Survivor" end
	return "Spectator"
end

function H.isKiller(player)
	return player.Team ~= nil and player.Team.Name == "Killer"
end

function H.isSurvivor(player)
	return player.Team ~= nil and player.Team.Name == "Survivors"
end

function H.char()
	return LocalPlayer.Character
end

function H.root(character)
	character = character or LocalPlayer.Character
	return character and character:FindFirstChild("HumanoidRootPart") or nil
end

function H.humanoid(character)
	character = character or LocalPlayer.Character
	return character and character:FindFirstChildOfClass("Humanoid") or nil
end

function H.downed(character)
	return character ~= nil and (character:GetAttribute("Knocked") == true or character:GetAttribute("IsHooked") == true)
end

function H.distance(position)
	local root = H.root()
	if not root then return math.huge end
	return (root.Position - position).Magnitude
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

function H.interact(character)
	character = character or LocalPlayer.Character
	return character and character:FindFirstChild("CheckInterractable") or nil
end

function H.busy(character, keys)
	local node = H.interact(character)
	if not node then return false end
	for _, key in ipairs(keys) do
		if node:GetAttribute(key) == true then return true end
	end
	return false
end

H.BUSY_BASIC = { "isVaulting", "isRepairing", "isUnhooking", "isHealing", "isSliding" }

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
	gui.DisplayOrder = 50
	gui.Parent = H.guiParent()

	S.gui = gui
	return gui
end

function H.make(class, props, parent)
	local object = Instance.new(class)
	for key, value in pairs(props or {}) do
		pcall(function() object[key] = value end)
	end
	object.Parent = parent or H.overlay()
	table.insert(S.instances, object)
	return object
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

function H.mobileGui(survivor)
	if survivor then
		return PlayerGui:FindFirstChild("Survivor-mob") or PlayerGui:FindFirstChild("SurvivorMob")
	end

	for _, child in ipairs(PlayerGui:GetChildren()) do
		if string.sub(child.Name, -4) == "-mob" and child.Name ~= "Survivor-mob" then return child end
	end

	return nil
end

function H.control(survivor, names)
	local gui = H.mobileGui(survivor)
	local controls = gui and gui:FindFirstChild("Controls")
	if not controls then return nil end

	for _, name in ipairs(names) do
		local item = controls:FindFirstChild(name)
		if item then return item end
	end

	return nil
end

function H.visibleChain(object)
	local node = object
	while node and node:IsA("GuiObject") do
		if not node.Visible then return false end
		node = node.Parent
	end
	return true
end

function H.tap(button, hold)
	if not button then return false end

	if type(firesignal) == "function" then
		local ok = pcall(function()
			firesignal(button.MouseButton1Down)
			task.wait(hold or 0.01)
			firesignal(button.MouseButton1Up)
			pcall(function() firesignal(button.MouseButton1Click) end)
		end)
		if ok then return true end
	end

	local inset = GuiService:GetGuiInset()
	local x = button.AbsolutePosition.X + button.AbsoluteSize.X / 2 + inset.X
	local y = button.AbsolutePosition.Y + button.AbsoluteSize.Y / 2 + inset.Y
	local id = 8822 + math.random(1, 9999)

	pcall(function()
		VirtualInputManager:SendTouchEvent(id, 0, x, y)
		task.wait(hold or 0.01)
		VirtualInputManager:SendTouchEvent(id, 2, x, y)
	end)

	return true
end

function H.key(code, hold)
	pcall(function()
		VirtualInputManager:SendKeyEvent(true, code, false, game)
		task.wait(hold or 0.01)
		VirtualInputManager:SendKeyEvent(false, code, false, game)
	end)
end

function H.touchOnly()
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
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

function H.flat(vector)
	local flat = Vector3.new(vector.X, 0, vector.Z)
	if flat.Magnitude < 0.001 then return Vector3.zero end
	return flat.Unit
end

function H.onCharacter(fn, delay)
	H.track(LocalPlayer.CharacterAdded:Connect(function(character)
		task.wait(delay or 1)
		if alive() then pcall(fn, character) end
	end))
end

function H.animId(track)
	local animation = track and track.Animation
	return animation and tostring(animation.AnimationId):match("%d+") or nil
end

H.KILLER_ANIMS = {
	["122812055447896"] = "Veil lunge", ["133963973694098"] = "Mayers Basic",
	["117042998468241"] = "Mayers lunge", ["135002183282873"] = "cure lunge",
	["121216847022485"] = "cure Basic", ["132817836308238"] = "Jeff Basic",
	["129784271201071"] = "Jeff lunge", ["82666958311998"] = "Jeff Frenzy",
	["78432063483146"] = "Abyssal Basic", ["118907603246885"] = "Abyssal lunge",
	["139369275981139"] = "Jason Basic", ["110355011987939"] = "Jason lunge",
	["111920872708571"] = "Masked Basic", ["105374834496520"] = "Masked lunge",
	["138720291317243"] = "Masked Tony", ["106871536134254"] = "Masked Alex",
	["130593238885843"] = "Masked Cobra", ["115244153053858"] = "Masked Cobra lunge",
	["74968262036854"] = "Hidden Basic", ["113255068724446"] = "Hidden lunge",
	["98163597193511"] = "Hidden S1", ["80411309607666"] = "Abyssal S1",
}

H.V2_ANIMS = {}
for id in pairs(H.KILLER_ANIMS) do
	if id ~= "98163597193511" and id ~= "80411309607666" then H.V2_ANIMS[id] = true end
end
H.V2_ANIMS["109402730355822"] = true
H.V2_ANIMS["78935059863801"] = true
H.V2_ANIMS["117070354890871"] = true

local MAP = {
	Generators = {}, Hooks = {}, Gates = {}, Pallets = {}, Windows = {}, SCPs = {},
	scannedAt = 0,
}

function H.firstPart(model)
	if model:IsA("BasePart") then return model end
	return model:FindFirstChildWhichIsA("BasePart", true)
end

function H.scanMap(force)
	if not force and os.clock() - MAP.scannedAt < 2 then return end
	MAP.scannedAt = os.clock()

	local found = { Generators = {}, Hooks = {}, Gates = {}, Pallets = {}, Windows = {}, SCPs = {} }
	local seenPallets = {}
	local root = workspace:FindFirstChild("Map") or workspace

	for index, item in ipairs(root:GetDescendants()) do
		if index % 300 == 0 then task.wait() end

		if item:IsA("Model") then
			local name = string.lower(item.Name)

			if name == "generator" then
				local part = item:FindFirstChild("GeneratorBody") or item:FindFirstChildWhichIsA("BasePart")
				if part then table.insert(found.Generators, { model = item, part = part }) end
			elseif name == "hook" and item:FindFirstChild("HookPoint") then
				table.insert(found.Hooks, item)
			elseif name == "gate" and item:FindFirstChild("ExitLever") then
				table.insert(found.Gates, item)
			elseif name == "window" then
				table.insert(found.Windows, item)
			end
		elseif item:IsA("BasePart") and item.Name == "PrimaryPartPallet" then
			local pallet = item.Parent
			if pallet and not seenPallets[pallet] then
				seenPallets[pallet] = true
				table.insert(found.Pallets, pallet)
			end
		end
	end

	for index, item in ipairs(workspace:GetDescendants()) do
		if index % 300 == 0 then task.wait() end
		if item:IsA("Model") and string.lower(item.Name):match("^scp") then
			table.insert(found.SCPs, item)
		end
	end

	for key, list in pairs(found) do MAP[key] = list end
end

task.spawn(function()
	task.wait(2)
	pcall(H.scanMap, true)
end)

H.track(workspace.ChildAdded:Connect(function(child)
	if child.Name == "Map" then
		task.wait(1)
		pcall(H.scanMap, true)
	end
end))

H.loop(40, function() H.scanMap(true) end)

function H.namecallHook()
	if S.hookInstalled then return true end

	local hook = hookmetamethod
	if type(hook) ~= "function" or type(getnamecallmethod) ~= "function" or type(newcclosure) ~= "function" then
		return false
	end

	local caller = type(checkcaller) == "function" and checkcaller or function() return false end

	local ok = pcall(function()
		local old
		old = hook(game, "__namecall", newcclosure(function(self, ...)
			local method = getnamecallmethod()

			if alive() and (method == "FireServer" or method == "InvokeServer") and not caller() and typeof(self) == "Instance" then
				local replaced, result = H.intercept(self, method, old, ...)
				if replaced then return result end
			end

			return old(self, ...)
		end))
		S.oldNamecall = old
	end)

	S.hookInstalled = ok
	return ok
end

function H.intercept(self, method, old, ...)
	local name = self.Name

	if F.noFall and name == "Fall" and self.Parent and self.Parent.Name == "Mechanics" then
		local args = table.pack(...)
		args[1] = 0
		return true, old(self, table.unpack(args, 1, args.n))
	end

	if F.antiBlind and name == "GotBlinded" and H.role() == "Killer" then
		return true, nil
	end

	if F.tofBlock and name == "Fire" and self.Parent and self.Parent.Name == "Twist of Fate" then
		return true, nil
	end

	if F.flaskSilent and name == "ThrowFlask" then
		local args = table.pack(...)
		local target = H.nearestPlayer(function(player) return not H.isKiller(player) end)
		local root = target and H.root(target.Character)

		if root and typeof(args[2]) == "Vector3" then
			args[1] = (root.Position - args[2]).Unit
			return true, old(self, table.unpack(args, 1, args.n))
		end
	end

	if F.invis and method == "FireServer" and string.lower(name) == "updatecharacterlook" then
		local args = table.pack(...)
		for index = 1, args.n do
			if typeof(args[index]) == "CFrame" then args[index] = args[index] * CFrame.new(0, 5000, 0) end
		end
		return true, old(self, table.unpack(args, 1, args.n))
	end

	if F.veil and name == "Spearthrow" and self:IsA("RemoteEvent") then
		local args = table.pack(...)
		local direction, speed, origin = H.solveSpear(args[1], args[3])
		if direction then
			return true, old(self, direction, speed, origin)
		end
	end

	return false
end

function H.nearestPlayer(filter, maxDistance)
	local root = H.root()
	if not root then return nil end

	local best, bestDistance = nil, maxDistance or math.huge

	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer and player.Character and filter(player) then
			local other = H.root(player.Character)
			if other then
				local distance = (other.Position - root.Position).Magnitude
				if distance < bestDistance then best, bestDistance = player, distance end
			end
		end
	end

	return best, bestDistance
end

S.lastAction = 0

H.loop(0.1, function()
	if not (F.autoVault or F.autoSlide) then return end
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then return end
	if os.clock() - S.lastAction < 0.5 then return end

	local prompts = PlayerGui:FindFirstChild("pcprompts")
	local frame = prompts and prompts:FindFirstChild("Frame")
	if not frame then return end

	local vault = frame:FindFirstChild("VaultPromptGui")
	local slide = frame:FindFirstChild("PalletSlidePromptGui")

	if (F.autoVault and vault and vault.Visible) or (F.autoSlide and slide and slide.Visible) then
		S.lastAction = os.clock()
		H.key(Enum.KeyCode.Space, 0.01)
	end
end)

H.loop(0.15, function()
	if not (F.autoVault or F.autoSlide) then return end
	if not UserInputService.TouchEnabled then return end
	if os.clock() - S.lastAction < 0.5 then return end

	local action = H.control(true, { "action" })
	if not action then return end

	for _, child in ipairs(action:GetChildren()) do
		if (child:IsA("ImageLabel") or child:IsA("ImageButton")) and child.Visible then
			local name = string.lower(child.Name)
			local isPallet = name:find("pallet") or name:find("slide")
			local isVault = name:find("vault") and not name:find("pallet")

			if (isVault and F.autoVault) or (isPallet and F.autoSlide) then
				S.lastAction = os.clock()
				H.tap(action, 0.01)
				return
			end
		end
	end
end)

H.loop(0.1, function()
	if F.autoRunPC then
		pcall(function() VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.LeftShift, false, game) end)
	end
end)

function H.sprintButton()
	local sprint = H.control(true, { "sprint" })
	if not sprint then return nil end
	if sprint:IsA("GuiButton") then return sprint end

	local icon = sprint:FindFirstChild("icon")
	if icon and icon:IsA("GuiButton") then return icon end

	return sprint
end

function H.moving()
	local humanoid = H.humanoid()
	if humanoid and humanoid.MoveDirection.Magnitude > 0.12 then return true end

	local root = H.root()
	if root then
		local velocity = root.AssemblyLinearVelocity
		return Vector3.new(velocity.X, 0, velocity.Z).Magnitude > 1.5
	end

	return false
end

function H.sprinting()
	local character = H.char()
	return character ~= nil and (character:GetAttribute("Sprinting") == true or character:GetAttribute("IsRunning") == true)
end

function H.crouching()
	local character = H.char()
	return character ~= nil and (character:GetAttribute("Crouching") == true or character:GetAttribute("Crouchingserver") == true)
end

H.loop(0.12, function()
	if not F.autoRunMobile then return end

	local moving, sprinting = H.moving(), H.sprinting()

	if H.crouching() then
		if sprinting then H.tap(H.sprintButton(), 0.04) end
	elseif moving ~= sprinting then
		H.tap(H.sprintButton(), 0.04)
	end
end)

H.loop(1, function()
	if not F.skipEndscreen then return end

	local map = workspace:FindFirstChild("Map")
	local endscreen = map and map:FindFirstChild("endscreen", true)

	if endscreen then
		for _, item in ipairs(endscreen:GetDescendants()) do
			if item:IsA("LocalScript") then pcall(function() item.Disabled = true end) end
		end
		pcall(function() endscreen:Destroy() end)
	end

	local results = PlayerGui:FindFirstChild("Results")
	local frame = results and results:FindFirstChild("Frame")
	local close = frame and frame:FindFirstChild("Close")

	if close and frame.Visible and close.Visible then H.tap(close, 0.01) end
end)

S.perks = { qrAt = 0, plAt = 0, fsAt = 0, arAt = 0, boosting = false, fsCooldown = false, conns = {} }

function H.perkBoost(character, seconds, stamp)
	if S.perks.boosting then return end
	if H.role() ~= "Survivor" then return end
	if os.clock() - (S.perks[stamp] or 0) < F.perkCooldown then return end

	S.perks.boosting = true
	S.perks[stamp] = os.clock()

	task.spawn(function()
		local started = os.clock()
		while os.clock() - started < seconds and character and character.Parent do
			pcall(function() character:SetAttribute("speedboost", 1.4) end)
			task.wait()
		end
		pcall(function() character:SetAttribute("speedboost", 1) end)
		S.perks.boosting = false
	end)
end

function H.playingAnim(character, id)
	local humanoid = H.humanoid(character)
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then return false end

	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		if H.animId(track) == id then return true end
	end

	return false
end

function H.bindPerks(character)
	for _, connection in ipairs(S.perks.conns) do pcall(function() connection:Disconnect() end) end
	table.clear(S.perks.conns)

	if not character then return end

	table.insert(S.perks.conns, character:GetAttributeChangedSignal("isvaulting"):Connect(function()
		if not F.qr or character:GetAttribute("isvaulting") ~= true then return end
		task.wait(0.1)
		if not H.playingAnim(character, "126081405469607") and character:GetAttribute("isvaulting") == true then
			H.perkBoost(character, 3, "qrAt")
		end
	end))

	table.insert(S.perks.conns, character:GetAttributeChangedSignal("speedboost"):Connect(function()
		if F.pl and character:GetAttribute("speedboost") == 0.625 then
			H.perkBoost(character, 3, "plAt")
		end
	end))

	table.insert(S.perks.conns, character:GetAttributeChangedSignal("Flowstate"):Connect(function()
		if not F.fs or H.role() ~= "Survivor" then return end
		local value = character:GetAttribute("Flowstate")

		if value == true and (S.perks.fsCooldown or os.clock() - S.perks.fsAt < F.perkCooldown) then
			character:SetAttribute("Flowstate", false)
		elseif value == false and not S.perks.fsCooldown and os.clock() - S.perks.fsAt >= F.perkCooldown then
			character:SetAttribute("Flowstate", true)
		end
	end))

	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 5)

	if humanoid then
		local last = humanoid.Health

		table.insert(S.perks.conns, humanoid.HealthChanged:Connect(function(health)
			if F.ar and health < last and health <= 50 and health > 0 then
				H.perkBoost(character, 5, "arAt")
			end
			last = health
		end))

		local animator = humanoid:FindFirstChildOfClass("Animator") or humanoid:WaitForChild("Animator", 3)

		if animator then
			table.insert(S.perks.conns, animator.AnimationPlayed:Connect(function(track)
				if not F.fs or H.animId(track) ~= "136962284480779" then return end

				track.Stopped:Once(function()
					S.perks.fsAt = os.clock()
					S.perks.fsCooldown = true
					pcall(function() character:SetAttribute("Flowstate", false) end)

					task.delay(F.perkCooldown, function()
						S.perks.fsCooldown = false
						if F.fs and character.Parent then pcall(function() character:SetAttribute("Flowstate", true) end) end
					end)
				end)
			end))
		end
	end

	if F.fs then
		task.wait(0.5)
		pcall(function() character:SetAttribute("Flowstate", true) end)
	end
end

task.spawn(function()
	if LocalPlayer.Character then pcall(H.bindPerks, LocalPlayer.Character) end
end)
H.onCharacter(H.bindPerks, 0.5)

function H.cameraTick(dt)
	local camera = workspace.CurrentCamera
	if not camera then return end

	if F.speed then
		local humanoid, root = H.humanoid(), H.root()
		if humanoid and root and humanoid.MoveDirection.Magnitude > 0 then
			local extra = (F.speedValue - 0.1) * 10
			if extra > 0 then root.CFrame = root.CFrame + humanoid.MoveDirection * extra * dt end
		end
	end

	if F.moonwalk then
		local humanoid, root = H.humanoid(), H.root()
		if humanoid and root then
			if humanoid.AutoRotate then humanoid.AutoRotate = false end

			local look = H.flat(camera.CFrame.LookVector)
			local right = H.flat(camera.CFrame.RightVector)
			local wave = math.sin(tick() * 35)
			local facing = CFrame.Angles(0, math.rad(30 * wave), 0) * look

			root.CFrame = CFrame.lookAt(root.Position, root.Position + facing)
			humanoid:Move(-look * 1.2 + right * (wave * 1.05), false)
		end
	end

	if F.stretch then
		camera.CFrame = camera.CFrame * CFrame.new(0, 0, 0, 1, 0, 0, 0, F.stretchAmount, 0, 0, 0, 1)
	end

	if F.camFov and not F.dbd then
		camera.FieldOfView = F.camFovValue
	end
end

H.track(RunService.RenderStepped:Connect(function(dt)
	if alive() then pcall(H.cameraTick, dt) end
end))

function H.setMoonwalk(state)
	F.moonwalk = state
	if not state then
		local humanoid = H.humanoid()
		if humanoid then humanoid.AutoRotate = true end
	end
	if S.moonButton then
		S.moonButton.Text = state and "MOON [ON]" or "MOON [OFF]"
		S.moonButton.TextColor3 = state and Color3.fromRGB(180, 255, 180) or Color3.fromRGB(200, 200, 200)
	end
end

function H.floatingButton(text, position, onClick)
	local button = H.make("TextButton", {
		Size = UDim2.fromOffset(110, 36),
		Position = position,
		BackgroundColor3 = Color3.fromRGB(30, 30, 35),
		BackgroundTransparency = 0.15,
		Text = text,
		TextColor3 = Color3.fromRGB(220, 220, 228),
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		AutoButtonColor = true,
		Active = true,
		Draggable = true,
	})

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = button

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(90, 90, 95)
	stroke.Parent = button

	button.MouseButton1Click:Connect(onClick)
	return button
end

function H.moonwalkButton(show)
	if not show then
		if S.moonButton then pcall(function() S.moonButton:Destroy() end) end
		S.moonButton = nil
		return
	end

	if S.moonButton and S.moonButton.Parent then return end
	S.moonButton = H.floatingButton(F.moonwalk and "MOON [ON]" or "MOON [OFF]", UDim2.new(0.85, 0, 0.45, 0), function()
		H.setMoonwalk(not F.moonwalk)
	end)
end

function H.thirdPersonApply()
	if not F.thirdPerson then return end

	if H.role() ~= "Killer" then
		F.thirdPerson = false
		H.thirdPersonReset()
		return
	end

	pcall(function()
		LocalPlayer.CameraMode = Enum.CameraMode.Classic
		LocalPlayer.CameraMinZoomDistance = 7
		LocalPlayer.CameraMaxZoomDistance = 128
	end)

	local character = H.char()
	if character then
		for _, item in ipairs(character:GetDescendants()) do
			if item:IsA("BasePart") or item:IsA("Decal") then
				pcall(function() item.LocalTransparencyModifier = 0 end)
			end
		end
	end
end

function H.thirdPersonReset()
	pcall(function()
		LocalPlayer.CameraMode = Enum.CameraMode.Classic
		if F.infiniteZoom then
			LocalPlayer.CameraMinZoomDistance = 0
			LocalPlayer.CameraMaxZoomDistance = math.huge
		else
			LocalPlayer.CameraMinZoomDistance = 0.5
			LocalPlayer.CameraMaxZoomDistance = 128
		end
	end)
end

H.track(RunService.RenderStepped:Connect(function()
	if alive() and F.thirdPerson then pcall(H.thirdPersonApply) end
end))

function H.setZoom(state)
	F.infiniteZoom = state
	pcall(function()
		if state then
			LocalPlayer.CameraMaxZoomDistance = math.huge
			LocalPlayer.CameraMinZoomDistance = 0
		else
			LocalPlayer.CameraMaxZoomDistance = 12
			LocalPlayer.CameraMinZoomDistance = 0.5
		end
	end)
end

S.dbd = { yaw = 0, pitch = 0.12, lookInput = nil, lastPos = nil, conns = {}, oldFov = nil }

function H.dbdStop()
	for _, connection in ipairs(S.dbd.conns) do pcall(function() connection:Disconnect() end) end
	table.clear(S.dbd.conns)

	local camera = workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Custom
		if S.dbd.oldFov then camera.FieldOfView = S.dbd.oldFov end
	end

	S.dbd.lookInput, S.dbd.lastPos, S.dbd.oldFov = nil, nil, nil
	pcall(function() UserInputService.MouseBehavior = Enum.MouseBehavior.Default end)
end

function H.dbdStart()
	H.dbdStop()
	if not F.dbd then return end

	local camera = workspace.CurrentCamera
	local root = H.root()

	if root then
		local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
		if look.Magnitude > 0.05 then S.dbd.yaw = math.atan2(-look.X, -look.Z) end
	end

	S.dbd.oldFov = camera.FieldOfView
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = F.dbdFov

	local humanoid = H.humanoid()
	if humanoid then humanoid.AutoRotate = true end

	local function turn(dx, dy, scale)
		S.dbd.yaw = S.dbd.yaw - dx * scale * F.dbdSens
		S.dbd.pitch = math.clamp(S.dbd.pitch - dy * scale * F.dbdSens, F.dbdPitchMin, F.dbdPitchMax)
	end

	table.insert(S.dbd.conns, UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch and input == S.dbd.lookInput then
			if S.dbd.lastPos then
				turn(input.Position.X - S.dbd.lastPos.X, input.Position.Y - S.dbd.lastPos.Y, 0.011)
			end
			S.dbd.lastPos = input.Position
		elseif input.UserInputType == Enum.UserInputType.MouseMovement
			and UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
			turn(input.Delta.X, input.Delta.Y, 0.006)
		end
	end))

	table.insert(S.dbd.conns, UserInputService.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch and input.Position.X > camera.ViewportSize.X * 0.22 then
			S.dbd.lookInput = input
			S.dbd.lastPos = input.Position
		end
	end))

	table.insert(S.dbd.conns, UserInputService.InputEnded:Connect(function(input)
		if input == S.dbd.lookInput then
			S.dbd.lookInput, S.dbd.lastPos = nil, nil
		end
	end))

	table.insert(S.dbd.conns, RunService.RenderStepped:Connect(function(dt)
		if not F.dbd then return end

		local current = H.root()
		if not current then return end

		local direction = Vector3.new(
			math.sin(S.dbd.yaw) * math.cos(S.dbd.pitch),
			math.sin(S.dbd.pitch),
			math.cos(S.dbd.yaw) * math.cos(S.dbd.pitch))

		local focus = current.Position + Vector3.new(0, 1.6, 0)
		local eye = focus - direction * F.dbdDistance + Vector3.new(0, F.dbdHeight - 1.6, 0)
		local smooth = S.dbd.lookInput and F.dbdLookSmooth or F.dbdRunSmooth
		local alpha = 1 - math.pow(1 - smooth, dt * 60)

		camera.CFrame = camera.CFrame:Lerp(CFrame.lookAt(eye, focus), alpha)
	end))
end

H.onCharacter(function() if F.dbd then H.dbdStart() end end, 0.6)

S.streamer = { conns = {} }

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

function H.streamerProcess(item)
	if item:IsA("TextLabel") or item:IsA("TextButton") or item:IsA("TextBox") then
		local function fix()
			if not F.streamer then return end
			local text = item.Text
			if item:GetAttribute("FacilityOriginalText") == nil then item:SetAttribute("FacilityOriginalText", text) end

			local changed = false
			for _, player in ipairs(Players:GetPlayers()) do
				if text:find(player.Name, 1, true) or text:find(player.DisplayName, 1, true) then
					text = H.plainReplace(H.plainReplace(text, player.Name, "Facility"), player.DisplayName, "Facility")
					changed = true
				end
			end

			if changed and item.Text ~= text then item.Text = text end
		end

		fix()
		table.insert(S.streamer.conns, item:GetPropertyChangedSignal("Text"):Connect(fix))
	elseif item:IsA("ImageLabel") or item:IsA("ImageButton") then
		local function fix()
			if not F.streamer then return end
			local image = item.Image

			for _, player in ipairs(Players:GetPlayers()) do
				if image:find(tostring(player.UserId), 1, true) then
					if item:GetAttribute("FacilityOriginalImage") == nil then item:SetAttribute("FacilityOriginalImage", image) end
					if item.Image ~= "rbxassetid://0" then item.Image = "rbxassetid://0" end
					return
				end
			end
		end

		fix()
		table.insert(S.streamer.conns, item:GetPropertyChangedSignal("Image"):Connect(fix))
	end
end

function H.setStreamer(state)
	F.streamer = state

	for _, connection in ipairs(S.streamer.conns) do pcall(function() connection:Disconnect() end) end
	table.clear(S.streamer.conns)

	if state then
		for _, item in ipairs(PlayerGui:GetDescendants()) do pcall(H.streamerProcess, item) end
		table.insert(S.streamer.conns, PlayerGui.DescendantAdded:Connect(function(item)
			task.defer(function() pcall(H.streamerProcess, item) end)
		end))
		return
	end

	for _, item in ipairs(PlayerGui:GetDescendants()) do
		local text = item:GetAttribute("FacilityOriginalText")
		if text ~= nil then
			pcall(function() item.Text = text end)
			item:SetAttribute("FacilityOriginalText", nil)
		end

		local image = item:GetAttribute("FacilityOriginalImage")
		if image ~= nil then
			pcall(function() item.Image = image end)
			item:SetAttribute("FacilityOriginalImage", nil)
		end
	end
end

S.crosshair = { gui = nil, built = nil }

function H.crosshairBuild()
	if S.crosshair.gui then pcall(function() S.crosshair.gui:Destroy() end) end
	S.crosshair.gui = nil

	if not F.crosshair then return end

	local gui = Instance.new("ScreenGui")
	gui.Name = tostring(math.random(100000, 999999))
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 999
	gui.Parent = H.guiParent()
	S.crosshair.gui = gui

	local center = UDim2.new(0.5, F.crossX, 0.5, F.crossY)

	local function bar(size)
		local frame = Instance.new("Frame")
		frame.BackgroundColor3 = F.crossColor
		frame.BorderSizePixel = 0
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Size = size
		frame.Position = center
		frame.Parent = gui
		return frame
	end

	if F.crossStyle == "Plus" then
		bar(UDim2.fromOffset(F.crossSize * 2, F.crossThickness))
		bar(UDim2.fromOffset(F.crossThickness, F.crossSize * 2))
	elseif F.crossStyle == "Dot" then
		local dot = bar(UDim2.fromOffset(F.crossSize, F.crossSize))
		Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)
	else
		local ring = bar(UDim2.fromOffset(F.crossSize * 2, F.crossSize * 2))
		ring.BackgroundTransparency = 1
		Instance.new("UICorner", ring).CornerRadius = UDim.new(1, 0)
		local stroke = Instance.new("UIStroke")
		stroke.Color = F.crossColor
		stroke.Thickness = F.crossThickness
		stroke.Parent = ring
	end
end

function H.setInvis(state)
	F.invis = state
	if state and not H.namecallHook() then
		F.invis = false
		H.notify("Invisibility", "This executor has no hookmetamethod.", 5)
		return false
	end
	return true
end

S.skill = { busy = false, normalRandom = false }

function H.skillPress()
	local button = H.control(true, { "action", "check" })

	if button and button.Visible then
		H.tap(button, 0.005)
		return
	end

	H.key(Enum.KeyCode.Space, 0.005)
end

function H.inWindow(value, from, to)
	value, from, to = value % 360, from % 360, to % 360
	if from <= to then return value >= from and value <= to end
	return value >= from or value <= to
end

H.track(RunService.Heartbeat:Connect(function()
	if not (alive() and F.skillCheck) or S.skill.busy then return end

	local gui = PlayerGui:FindFirstChild("SkillCheckPromptGui")
	local check = gui and gui:FindFirstChild("Check")
	if not check then return end

	if not check.Visible then
		S.skill.normalRandom = false
		return
	end

	local line, goal = check:FindFirstChild("Line"), check:FindFirstChild("Goal")
	if not (line and goal) then return end

	local mode = F.skillMode
	local instant = mode == "Instant" or (mode == "Random" and not S.skill.normalRandom)

	local function press()
		S.skill.busy = true
		task.spawn(function()
			H.skillPress()
			task.wait(0.05)
			S.skill.busy = false
		end)
	end

	if instant then
		line.Rotation = goal.Rotation + 109
		press()
		return
	end

	local normal = mode == "Normal" or (mode == "Random" and S.skill.normalRandom)
	local from = goal.Rotation + (normal and 116 or 102)
	local to = goal.Rotation + (normal and 140 or 116)

	if H.inWindow(line.Rotation, from, to) then press() end
end))

task.spawn(function()
	local remote = H.remote("KillerPerks.kingscourge.KingScourgeStart")
	if not remote then
		local remotes = ReplicatedStorage:WaitForChild("Remotes", 15)
		local perks = remotes and remotes:WaitForChild("KillerPerks", 10)
		local king = perks and perks:WaitForChild("kingscourge", 10)
		remote = king and king:WaitForChild("KingScourgeStart", 10)
	end
	if remote and remote:IsA("RemoteEvent") then
		H.track(remote.OnClientEvent:Connect(function()
			if F.skillMode == "Random" then S.skill.normalRandom = true end
		end))
	end
end)

S.gen = { processed = {}, autoPoint = nil, autoOn = false, track = nil, cache = nil, cacheAt = 0 }

function H.generators()
	if S.gen.cache and os.clock() - S.gen.cacheAt < 5 then return S.gen.cache end

	local list = {}
	local map = workspace:FindFirstChild("Map")

	if map then
		for _, item in ipairs(map:GetDescendants()) do
			if item:IsA("Model") and item.Name == "Generator"
				and (item:GetAttribute("RepairProgress") ~= nil or item:GetAttribute("kickcount") ~= nil or item:GetAttribute("ProgressRepair") ~= nil) then
				local points = {}
				for _, child in ipairs(item:GetChildren()) do
					if child:IsA("BasePart") and child.Name:find("GeneratorPoint") then table.insert(points, child) end
				end
				table.insert(list, { model = item, points = points })
			end
		end
	end

	S.gen.cache, S.gen.cacheAt = list, os.clock()
	return list
end

function H.nearestGenPoint(range)
	local root = H.root()
	if not root then return nil end

	local best, bestDistance, bestGen = nil, range, nil

	for _, gen in ipairs(H.generators()) do
		for _, point in ipairs(gen.points) do
			local distance = (point.Position - root.Position).Magnitude
			if distance < bestDistance then best, bestDistance, bestGen = point, distance, gen end
		end
	end

	return best, bestGen
end

function H.repair(point, state)
	H.fire("Generator.RepairEvent", point, state)
end

function H.stopAutoRepair()
	S.gen.autoOn = false
	if S.gen.track then pcall(function() S.gen.track:Stop() end) end
	S.gen.track = nil
	if S.gen.autoPoint then H.repair(S.gen.autoPoint, false) end
	S.gen.autoPoint = nil
end

function H.autoRepairLoop(gen)
	S.gen.autoOn = true

	task.spawn(function()
		while alive() and S.gen.autoOn and F.genBoost do
			local root = H.root()
			local near = nil

			if root then
				for _, point in ipairs(gen.points) do
					if (point.Position - root.Position).Magnitude <= 5 then near = point break end
				end
			end

			if not near then break end

			S.gen.autoPoint = near

			local humanoid = H.humanoid()
			local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")

			if animator and not (S.gen.track and S.gen.track.IsPlaying) then
				pcall(function()
					local animation = Instance.new("Animation")
					animation.AnimationId = "rbxassetid://92960319113695"
					S.gen.track = animator:LoadAnimation(animation)
					S.gen.track.Priority = Enum.AnimationPriority.Action
					S.gen.track:Play()
				end)
			end

			H.repair(near, true)
			task.wait(0.5)
		end

		H.stopAutoRepair()
		S.gen.processed[gen.model] = nil
	end)
end

function H.multiRepair(clicked, gen)
	if not (clicked and gen) or S.gen.processed[gen.model] then return end
	S.gen.processed[gen.model] = true

	local root = H.root()
	if not root then return end

	local saved = root.CFrame

	for _, point in ipairs(gen.points) do
		if point ~= clicked and alive() then
			root.Anchored = true
			root.CFrame = point.CFrame
			task.wait(0.15)
			H.repair(point, true)

			local deadline = os.clock() + 0.8
			while os.clock() < deadline and point:GetAttribute("IsRepairing") ~= true do task.wait() end

			if point:GetAttribute("IsRepairing") ~= true then
				H.repair(point, false)
				task.wait(0.1)
				root.CFrame = point.CFrame
				task.wait(0.15)
				H.repair(point, true)
				local retry = os.clock() + 0.5
				while os.clock() < retry and point:GetAttribute("IsRepairing") ~= true do task.wait() end
			end

			root.Anchored = false
			task.wait(0.05)
		end
	end

	root.Anchored = false
	root.CFrame = saved
	task.wait(0.1)

	if F.genMode == "Auto Repair" then
		H.autoRepairLoop(gen)
	else
		H.repair(clicked, false)
	end
end

H.track(UserInputService.InputBegan:Connect(function(input, processed)
	if processed or not (alive() and F.genBoost) then return end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end

	local prompts = PlayerGui:FindFirstChild("pcprompts")
	local frame = prompts and prompts:FindFirstChild("Frame")
	local repair = frame and frame:FindFirstChild("GeneratorRepair")
	if not (repair and repair.Visible) then return end

	local point, gen = H.nearestGenPoint(8)
	if point then task.spawn(H.multiRepair, point, gen) end
end))

function H.genButton(show)
	if not show then
		if S.genButton then pcall(function() S.genButton:Destroy() end) end
		S.genButton = nil
		return
	end

	if S.genButton and S.genButton.Parent then return end

	S.genButton = H.floatingButton("GEN", UDim2.new(0.86, 0, 0.55, 0), function()
		local point, gen = H.nearestGenPoint(8)
		if point then
			task.spawn(H.multiRepair, point, gen)
		else
			H.notify("Gen Boost", "No generator point within 8 studs.", 3)
		end
	end)
end

H.loop(2, function()
	local root = H.root()
	for model in pairs(S.gen.processed) do
		local keep = false
		if model.Parent and root then
			for _, child in ipairs(model:GetChildren()) do
				if child:IsA("BasePart") and child.Name:find("GeneratorPoint") and (child.Position - root.Position).Magnitude <= 10 then
					keep = true
					break
				end
			end
		end
		if not keep and not S.gen.autoOn then S.gen.processed[model] = nil end
	end
end)

S.tof = { aiming = false, velocity = {}, laser = nil, gui = nil }

function H.tofGun()
	local character = H.char()
	local tool = character and character:FindFirstChild("Twist of Fate", true)
	if not tool then return nil end

	local arm = character:FindFirstChild("Right Arm")
	return (arm and (arm:FindFirstChild("gun") or arm:FindFirstChild("EmperorGun"))) or tool
end

function H.tofMuzzle(gun)
	local character, root = H.char(), H.root()
	if not root then return nil end

	if character:GetAttribute("IsCarried") == true then return root.Position + root.CFrame.LookVector * 2 end

	if gun then
		if gun:IsA("BasePart") then return gun.Position end
		local part = gun:FindFirstChildWhichIsA("BasePart", true)
		if part then return part.Position end
	end

	return root.Position + Vector3.new(0, 1.5, 0)
end

function H.sampleVelocity(model, part)
	local now = os.clock()
	local record = S.tof.velocity[model]

	if record then
		local dt = now - record.time
		if dt > 0.001 and dt < 0.1 then
			local velocity = (part.Position - record.position) / dt
			record.velocity = record.velocity and record.velocity:Lerp(velocity, 0.4) or velocity
		end
		record.position, record.time = part.Position, now
		return record.velocity or part.AssemblyLinearVelocity
	end

	S.tof.velocity[model] = { position = part.Position, time = now }
	return part.AssemblyLinearVelocity
end

function H.scpTargets()
	local list = {}
	local map = workspace:FindFirstChild("Map")
	if not map then return list end

	for _, item in ipairs(map:GetDescendants()) do
		if item:IsA("Model") and item:FindFirstChild("HumanoidRootPart") and next(item:GetAttributes()) ~= nil then
			table.insert(list, item.HumanoidRootPart)
		end
	end

	return list
end

function H.tofTarget(muzzle)
	local camera = workspace.CurrentCamera
	local root = H.root()
	if not (camera and root) then return nil end

	local best, bestScore = nil, nil
	local mode = F.tofTarget

	local function consider(part, score)
		if bestScore == nil or score > bestScore then best, bestScore = part, score end
	end

	if mode == "Killer" then
		for _, player in ipairs(Players:GetPlayers()) do
			if player ~= LocalPlayer and H.isKiller(player) and player.Character then
				local torso = player.Character:FindFirstChild("Torso") or H.root(player.Character)
				if torso then consider(torso, -(torso.Position - root.Position).Magnitude) end
			end
		end
	elseif mode == "Survivors" then
		for _, player in ipairs(Players:GetPlayers()) do
			if player ~= LocalPlayer and H.isSurvivor(player) and player.Character then
				local torso = player.Character:FindFirstChild("Torso") or H.root(player.Character)
				if torso then
					local dot = camera.CFrame.LookVector:Dot((torso.Position - camera.CFrame.Position).Unit)
					if dot > 0.5 then consider(torso, dot) end
				end
			end
		end
	else
		for _, part in ipairs(H.scpTargets()) do
			local dot = camera.CFrame.LookVector:Dot((part.Position - camera.CFrame.Position).Unit)
			if dot > 0.5 then consider(part, dot) end
		end
	end

	if best and F.tofWall and muzzle then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		local ignore = { H.char(), best.Parent }
		if S.tof.laser then table.insert(ignore, S.tof.laser) end
		params.FilterDescendantsInstances = ignore

		if workspace:Raycast(muzzle, best.Position - muzzle, params) then return nil end
	end

	return best
end

function H.tofAimPoint(target, muzzle)
	local position = target.Position
	if not F.tofPredict then return position end

	local offset = position - muzzle
	if offset.Magnitude < 8 then return position end

	local velocity = H.sampleVelocity(target.Parent, target)
	local speed = 500
	local a = velocity:Dot(velocity) - speed * speed
	local b = 2 * offset:Dot(velocity)
	local c = offset:Dot(offset)
	local disc = b * b - 4 * a * c
	if disc < 0 or math.abs(a) < 1e-6 then return position end

	local root1 = (-b - math.sqrt(disc)) / (2 * a)
	local root2 = (-b + math.sqrt(disc)) / (2 * a)
	local t = math.huge
	if root1 > 0 then t = math.min(t, root1) end
	if root2 > 0 then t = math.min(t, root2) end
	if t == math.huge then return position end

	return position + velocity * 0.85 * t
end

function H.tofShoot()
	if not (F.tof and S.tof.aiming) then return end

	local character = H.char()
	if F.tofBlockKnocked and H.downed(character) then return end

	local gun = H.tofGun()
	local remote = H.remote("Items.Twist of Fate.Fire")
	if not (gun and remote) then return end

	local muzzle = H.tofMuzzle(gun)
	local target = muzzle and H.tofTarget(muzzle)
	if not target then return end

	local aim = H.tofAimPoint(target, muzzle)
	pcall(function() remote:FireServer(gun, (aim - muzzle).Unit) end)
end

function H.tofLaser(from, to)
	if not (F.tofLaser and from and to) then
		if S.tof.laser then S.tof.laser.Transparency = 1 end
		return
	end

	if not (S.tof.laser and S.tof.laser.Parent) then
		local part = Instance.new("Part")
		part.Name = tostring(math.random(100000, 999999))
		part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch, part.CastShadow = true, false, false, false, false
		part.Material = Enum.Material.Neon
		part.Color = Color3.fromRGB(255, 50, 50)
		part.Parent = workspace
		S.tof.laser = part
		table.insert(S.instances, part)
	end

	local length = (to - from).Magnitude
	S.tof.laser.Size = Vector3.new(0.05, 0.05, length)
	S.tof.laser.CFrame = CFrame.new((from + to) / 2, to)
	S.tof.laser.Transparency = 0
end

H.track(UserInputService.InputBegan:Connect(function(input, processed)
	if not alive() then return end

	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		S.tof.aiming = true
		S.flashAiming = true
	elseif input.UserInputType == Enum.UserInputType.MouseButton1 and not processed then
		if F.tof then task.spawn(H.tofShoot) end
	elseif input.UserInputType == Enum.UserInputType.Keyboard and not processed and F.tof then
		local modes = { [Enum.KeyCode.K] = "Killer", [Enum.KeyCode.J] = "Survivors", [Enum.KeyCode.L] = "Zombie" }
		local mode = modes[input.KeyCode]
		if mode then
			F.tofTarget = mode
			H.notify("Twist Of Fate", "Target: " .. mode, 2)
		end
	end
end))

H.track(UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		S.tof.aiming = false
		S.flashAiming = false
	end
end))

H.loop(1, function()
	if not (F.tof or F.flashSilent) then return end

	local button = H.control(true, { "Gui-mob", "GuiMob" })
	if not button or button:GetAttribute("FacilityHooked") then return end
	button:SetAttribute("FacilityHooked", true)

	H.track(button.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			S.tof.aiming = true
			S.flashAiming = true
		end
	end))

	H.track(button.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			if F.tof then task.spawn(H.tofShoot) end
			S.tof.aiming = false
			S.flashAiming = false
		end
	end))
end)

H.track(RunService.Heartbeat:Connect(function()
	if not alive() then return end

	if not (F.tof and S.tof.aiming) then
		H.tofLaser(nil)
		return
	end

	local gun = H.tofGun()
	local muzzle = H.tofMuzzle(gun)
	local target = muzzle and H.tofTarget(muzzle)

	if not target then
		H.tofLaser(nil)
		return
	end

	local aim = H.tofAimPoint(target, muzzle)
	local root, character = H.root(), H.char()

	if root and character and character:GetAttribute("IsCarried") ~= true then
		root.CFrame = CFrame.lookAt(root.Position, Vector3.new(aim.X, root.Position.Y, aim.Z))
	end

	if F.tofLock then
		local camera = workspace.CurrentCamera
		camera.CFrame = camera.CFrame:Lerp(CFrame.lookAt(camera.CFrame.Position, aim), 0.15)
	end

	H.tofLaser(muzzle, aim)
end))

H.track(RunService.RenderStepped:Connect(function()
	if not (alive() and F.flashSilent and S.flashAiming) then return end

	local killer = H.nearestPlayer(function(player)
		return H.isKiller(player) and not H.downed(player.Character)
			and (H.humanoid(player.Character) and H.humanoid(player.Character).Health > 0)
	end)
	local target = killer and H.root(killer.Character)
	if not target then return end

	local camera = workspace.CurrentCamera
	local aim = target.Position + Vector3.new(0, F.flashOffset, 0)
	camera.CFrame = camera.CFrame:Lerp(CFrame.lookAt(camera.CFrame.Position, aim), 0.5)

	local root = H.root()
	if root then
		root.CFrame = root.CFrame:Lerp(CFrame.lookAt(root.Position, Vector3.new(aim.X, root.Position.Y, aim.Z)), 0.5)
	end
end))

S.antiHook = { accumulator = 0 }

H.track(RunService.Heartbeat:Connect(function(dt)
	if not (alive() and F.antiHook) then return end

	local character = H.char()
	if not (character and character:GetAttribute("IsCarried") == true) then
		S.antiHook.accumulator = 0
		return
	end

	local remote = H.remote("Game.UpdateCharacterLook")
	if not remote then return end

	local interval = 1 / math.max(1, F.antiHookHz)
	S.antiHook.accumulator = S.antiHook.accumulator + dt

	local sent = 0
	local offset = CFrame.new(0, -F.antiHookOffset, 0)

	while S.antiHook.accumulator >= interval and sent < 3 do
		S.antiHook.accumulator = S.antiHook.accumulator - interval
		sent = sent + 1
		pcall(function() remote:FireServer(CFrame.new(0, 1, 0), offset, offset, offset, offset) end)
	end
end))

S.gate = { original = nil }

function H.setTpGate(state)
	F.tpGate = state

	local ok, err = H.gcall(function()
		local items = ReplicatedStorage.Modules.Items
		local client = require(items:FindFirstChild("GateClient"))

		if type(getgc) == "function" then
			for _, value in ipairs(getgc(true)) do
				if type(value) == "table" and rawget(value, "gateDuration") ~= nil and rawget(value, "gateRemote") ~= nil then
					rawset(value, "gateDuration", state and 0 or 1.5)
				end
			end
		end

		if state and not S.gate.original then
			S.gate.original = { new = client.new, CanUse = client.CanUse }

			client.new = function(...)
				local object = S.gate.original.new(...)
				if F.tpGate and type(object) == "table" then object.gateDuration = 0 end
				return object
			end

			client.CanUse = function(self, ...)
				if not F.tpGate then return S.gate.original.CanUse(self, ...) end
				if self.isSilenced or self.isBuffering then return false end
				return os.clock() - (self.lastUse or 0) >= (self.currentCooldown or 0)
			end
		elseif not state and S.gate.original then
			client.new = S.gate.original.new
			client.CanUse = S.gate.original.CanUse
			S.gate.original = nil
		end
	end)

	if not ok then H.notify("Instant TP Gate", "Unavailable: " .. tostring(err), 5) end
end

H.onCharacter(function() if F.tpGate then H.setTpGate(true) end end, 0.5)

S.vaultTagConn = nil

function H.setUnlimitedVault(state)
	F.unlimitedVault = state

	if S.vaultTagConn then
		pcall(function() S.vaultTagConn:Disconnect() end)
		S.vaultTagConn = nil
	end

	if not state then return end

	for _, item in ipairs(CollectionService:GetTagged("Blocked")) do
		pcall(function() CollectionService:RemoveTag(item, "Blocked") end)
	end

	S.vaultTagConn = CollectionService:GetInstanceAddedSignal("Blocked"):Connect(function(item)
		if F.unlimitedVault then pcall(function() CollectionService:RemoveTag(item, "Blocked") end) end
	end)
	table.insert(S.connections, S.vaultTagConn)
end

H.onCharacter(function() if F.unlimitedVault then H.setUnlimitedVault(true) end end, 1)

S.vaultPatched = false

function H.patchVault()
	if S.vaultPatched then return true end

	local ok, err = H.gcall(function()
		local module = ReplicatedStorage:WaitForChild("Modules", 5):WaitForChild("Survivors", 5):WaitForChild("SurvivorAnimationsController", 5)
		local controller = require(module)

		local facing = controller._isFacingStraightEnough
		local onVault = controller._onVaultAnimation
		assert(type(facing) == "function" and type(onVault) == "function", "vault controller not found")

		controller._isFacingStraightEnough = function(self, ...)
			if F.antiSlowVault then
				self.characterspeed = 20
				return true, 0
			end
			return facing(self, ...)
		end

		controller._onVaultAnimation = function(self, a, b, ...)
			if F.antiSlowVault then return onVault(self, a, true, ...) end
			return onVault(self, a, b, ...)
		end
	end)

	S.vaultPatched = ok
	if not ok then H.notify("Anti Slow Vault", "Unavailable: " .. tostring(err), 5) end
	return ok
end

S.flowConn = nil

function H.setFlowstateNoCd(state)
	F.flowstate = state
	if S.flowConn then pcall(function() S.flowConn:Disconnect() end) end
	S.flowConn = nil

	local character = H.char()
	if not character then return end

	if state then
		character:SetAttribute("Flowstate", true)
		S.flowConn = character:GetAttributeChangedSignal("Flowstate"):Connect(function()
			if F.flowstate and character:GetAttribute("Flowstate") == false then
				task.wait(0.05)
				pcall(function() character:SetAttribute("Flowstate", true) end)
			end
		end)
		table.insert(S.connections, S.flowConn)
	else
		character:SetAttribute("Flowstate", false)
	end
end

H.onCharacter(function() if F.flowstate then H.setFlowstateNoCd(true) end end, 1)

function H.setBypassGate(state)
	F.bypassGate = state
	local map = workspace:FindFirstChild("Map")
	if not map then return end

	for _, gate in ipairs(map:GetDescendants()) do
		if gate.Name == "Gate" then
			for _, name in ipairs({ "LeftGate", "RightGate" }) do
				local part = gate:FindFirstChild(name)
				if part and part:IsA("BasePart") then
					H.setProp(part, "Transparency", state and 1 or 0)
					H.setProp(part, "CanCollide", not state)
					if not state then H.restoreProp(part, "Transparency") H.restoreProp(part, "CanCollide") end
				end
			end

			for _, name in ipairs({ "LeftGate-end", "LeftGate-end2", "RightGate-end", "RightGate-end2" }) do
				local part = gate:FindFirstChild(name)
				if part and part:IsA("BasePart") then
					if state then H.setProp(part, "Transparency", 0) else H.restoreProp(part, "Transparency") end
				end
			end

			local box = gate:FindFirstChild("Box")
			if box and box:IsA("BasePart") then
				if state then H.setProp(box, "CanCollide", false) else H.restoreProp(box, "CanCollide") end
			end
		end
	end
end

H.track(workspace.ChildAdded:Connect(function(child)
	if child.Name == "Map" and F.bypassGate then
		task.wait(1)
		pcall(H.setBypassGate, true)
	end
end))

H.loop(3, function()
	if not F.selfHeal or H.role() ~= "Survivor" then return end

	local humanoid, root = H.humanoid(), H.root()
	if not (humanoid and root) or humanoid.Health >= humanoid.MaxHealth then return end
	if H.busy(nil, H.BUSY_BASIC) then return end

	H.fire("Healing.HealEvent", root, true)
end)

S.healAnimConn = nil

function H.bindHealHide(character)
	if S.healAnimConn then pcall(function() S.healAnimConn:Disconnect() end) end
	S.healAnimConn = nil

	local humanoid = character and (character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 5))
	local animator = humanoid and (humanoid:FindFirstChildOfClass("Animator") or humanoid:WaitForChild("Animator", 5))
	if not animator then return end

	S.healAnimConn = animator.AnimationPlayed:Connect(function(track)
		if F.selfHeal and H.animId(track) == "95836365038528" then pcall(function() track:Stop() end) end
	end)
	table.insert(S.connections, S.healAnimConn)
end

task.spawn(function() if LocalPlayer.Character then pcall(H.bindHealHide, LocalPlayer.Character) end end)
H.onCharacter(H.bindHealHide, 2)

H.track(RunService.Heartbeat:Connect(function()
	if not (alive() and F.godMode) then return end
	local humanoid = H.humanoid()
	if humanoid and humanoid.Health < humanoid.MaxHealth then humanoid.Health = humanoid.MaxHealth end
end))

function H.applyKorless()
	local character = H.char()
	if not character then return end

	local head = character:FindFirstChild("Head")
	local leg = character:FindFirstChild("Right Leg") or character:WaitForChild("Right Leg", 5)
	if not (head and leg) then return end

	head.Transparency = 1
	local face = head:FindFirstChild("face")
	if face then face:Destroy() end
	leg.Transparency = 1

	if character:FindFirstChild("KorlessHead") then return end

	local mesh = Instance.new("MeshPart")
	mesh.Name = "KorlessHead"
	mesh.Size = Vector3.new(0.85, 0.85, 0.85)
	mesh.CanCollide = false
	mesh.Massless = true
	pcall(function()
		mesh.MeshId = "rbxassetid://902942096"
		mesh.TextureID = "rbxassetid://902843398"
	end)
	mesh.CFrame = leg.CFrame * CFrame.new(0, 0.7, 0)
	mesh.Parent = character

	local weld = Instance.new("WeldConstraint")
	weld.Part0, weld.Part1 = leg, mesh
	weld.Parent = mesh
end

H.onCharacter(function() if S.korless then H.applyKorless() end end, 1)

function H.instantEscape()
	local root = H.root()
	if not root then return end

	for _, item in ipairs(workspace:GetDescendants()) do
		if item:IsA("BasePart") and string.lower(item.Name) == "fininshline" then
			root.CFrame = item.CFrame + Vector3.new(0, 5, 0)
			return
		end
	end

	H.notify("Instant Escape", "No finish line on this map yet.", 3)
end

function H.crouchDodge()
	local crouch = H.control(true, { "crouch" })
	local icon = crouch and crouch:FindFirstChild("icon")

	if crouch and icon and icon.Visible and UserInputService.TouchEnabled then
		H.tap(crouch, 0.01)
		task.wait(1.4)
		H.tap(crouch, 0.01)
		return
	end

	pcall(function()
		VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.LeftControl, false, game)
		task.wait(1.4)
		VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.LeftControl, false, game)
	end)
end

S.aimHighlight = H.make("Highlight", {
	FillColor = Color3.fromRGB(255, 0, 0), OutlineColor = Color3.fromRGB(255, 255, 0),
	FillTransparency = 0.4, OutlineTransparency = 0.2, Enabled = false,
})

U.survCircle = H.drawing("Circle", { Visible = false, Thickness = 1.5, NumSides = 64, Filled = false, Color = Color3.new(1, 1, 1), Transparency = 0.5 })

function H.survAimPart(character)
	if F.survAimPart == "Head" then return character:FindFirstChild("Head") end
	if F.survAimPart == "Torso" then return character:FindFirstChild("Torso") or character:FindFirstChild("UpperTorso") end
	return H.root(character)
end

H.track(UserInputService.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton2 then S.survHolding = true end
end))

H.track(UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton2 then S.survHolding = false end
end))

H.track(RunService.RenderStepped:Connect(function()
	if not alive() then return end
	local camera = workspace.CurrentCamera

	local active = F.survAim and H.role() == "Survivor"

	if U.survCircle then
		U.survCircle.Visible = active and F.survAimFov
		if U.survCircle.Visible then
			U.survCircle.Position = camera.ViewportSize / 2
			U.survCircle.Radius = F.survAimRadius
		end
	end

	if not active or (F.survAimHold and not S.survHolding) then
		if S.aimHighlight.Adornee and not F.killerAim then S.aimHighlight.Enabled = false end
		return
	end

	local center = camera.ViewportSize / 2
	local best, bestDistance = nil, F.survAimRadius

	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer and H.isKiller(player) and player.Character then
			local part = H.survAimPart(player.Character)
			if part and H.distance(part.Position) <= F.survAimDist then
				local point, onScreen = camera:WorldToViewportPoint(part.Position)
				if onScreen then
					local distance = (Vector2.new(point.X, point.Y) - center).Magnitude
					if distance < bestDistance then best, bestDistance = part, distance end
				end
			end
		end
	end

	if not best then
		S.aimHighlight.Enabled = false
		return
	end

	S.aimHighlight.Adornee = best.Parent
	S.aimHighlight.Enabled = true

	local aim = best.Position
	local range = H.distance(aim)
	if range < 100 then aim = aim + camera.CFrame.RightVector * ((100 - range) * F.survAimPredict) end

	camera.CFrame = camera.CFrame:Lerp(CFrame.new(camera.CFrame.Position, aim), F.survAimSmooth)

	local root = H.root()
	if root then
		root.CFrame = root.CFrame:Lerp(CFrame.new(root.Position, Vector3.new(aim.X, root.Position.Y, aim.Z)), F.survAimSmooth)
	end
end))

S.parry = { cooldown = false, resolving = false, token = 0, sensors = {}, button = nil }

function H.parryRemote()
	return H.remote("Items.Parrying Dagger.parry")
end

function H.parryCooldown(seconds)
	S.parry.cooldown = true
	S.parry.resolving = false
	S.parry.token = S.parry.token + 1
	local token = S.parry.token

	task.delay(seconds, function()
		if S.parry.token == token then S.parry.cooldown = false end
	end)
end

task.spawn(function()
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 15)
	local items = remotes and remotes:WaitForChild("Items", 10)
	local dagger = items and items:WaitForChild("Parrying Dagger", 10)
	local result = dagger and dagger:WaitForChild("parryResult", 10)

	if result and result:IsA("RemoteEvent") then
		H.track(result.OnClientEvent:Connect(function(success, cooldown)
			local seconds = tonumber(cooldown)
			if not seconds or seconds <= 0 then seconds = success == true and 90 or 60 end
			H.parryCooldown(seconds)
			local root = H.root()
			if root then pcall(function() CollectionService:RemoveTag(root, "doing action") end) end
		end))
	end
end)

function H.facing(killerRoot, myRoot, threshold)
	local look = H.flat(killerRoot.CFrame.LookVector)
	local offset = myRoot.Position - killerRoot.Position
	local flat = Vector3.new(offset.X, 0, offset.Z)
	if flat.Magnitude < 0.15 then return true end
	return look:Dot(flat.Unit) >= threshold
end

function H.safeToParry(keys)
	return not H.busy(nil, keys)
end

function H.parryV1Fire()
	local remote = H.parryRemote()
	if remote then
		for _ = 1, 8 do pcall(function() remote:FireServer() end) end
	end

	task.spawn(function()
		local button = H.control(true, { "Gui-mob", "GuiMob" })
		if button and button.Visible then
			H.tap(button, 0.01)
		elseif type(mouse2click) == "function" then
			pcall(mouse2click)
		else
			pcall(function()
				VirtualInputManager:SendMouseButtonEvent(0, 0, 1, true, game, 0)
				task.wait(0.01)
				VirtualInputManager:SendMouseButtonEvent(0, 0, 1, false, game, 0)
			end)
		end
	end)
end

function H.parryV1(killerRoot, id)
	if not F.parryV1 or S.parry.cooldown then return end
	if H.downed(H.char()) then return end
	if F.parryV1Safety and not H.safeToParry(H.BUSY_BASIC) then return end

	local root = H.root()
	if not root then return end

	local threshold = F.parryV1Face < 0.2 and 0.35 or F.parryV1Face
	local radius = F.parryV1Radius

	local function ready()
		local distance = (killerRoot.Position - root.Position).Magnitude
		if F.parryV1Aggressive then
			return distance <= 12 and H.facing(killerRoot, root, threshold)
		end
		return distance <= radius + 2 and H.facing(killerRoot, root, threshold)
	end

	local limit = F.parryV1Aggressive and radius + 5 or radius + 6
	if (killerRoot.Position - root.Position).Magnitude > limit then return end

	if ready() then
		H.parryV1Fire()
		return
	end

	local deadline = os.clock() + (F.parryV1Aggressive and 0.85 or 0.28)
	while os.clock() < deadline do
		RunService.Heartbeat:Wait()
		if ready() then
			H.parryV1Fire()
			return
		end
	end
end

H.V2_BUSY = { "isVaulting", "isSliding", "isDroppingPallet", "isRepairing", "isHealing", "isUnhooking", "isExiting" }

function H.v2Busy()
	local character = H.char()
	if not character then return true end
	if LocalPlayer:GetAttribute("IsDead") == true then return true end
	if character:GetAttribute("IsCarried") == true or character:GetAttribute("IsHooked") == true then return true end
	if H.downed(character) then return true end
	local root = H.root()
	if root and CollectionService:HasTag(root, "doing action") then return true end
	return H.busy(character, H.V2_BUSY)
end

function H.v2CanParry()
	local character = H.char()
	if not (F.parryV2 and character and character:FindFirstChild("Parrying Dagger")) then return false end
	if S.parry.cooldown or S.parry.resolving then return false end
	if F.parryV2Safety and H.v2Busy() then return false end

	local humanoid = H.humanoid()
	return humanoid ~= nil and humanoid.Health >= humanoid.MaxHealth * 0.5
end

H.PARRY_SKINS = {
	{ { "shield", "bloodshield" }, "75939529748815" },
	{ { "robot", "feedbacker" }, "126894569253341" },
	{ { "katana", "enten" }, "127096285501517" },
	{ { "fish", "fih" }, "123307242865945" },
	{ { "watcher", "stopwatch" }, "81793464499285" },
}

function H.parrySkinAnim()
	local character = H.char()
	local skin = ""

	for _, holder in ipairs({ character, character and character:FindFirstChild("Parrying Dagger"), LocalPlayer }) do
		if holder then
			for key, value in pairs(holder:GetAttributes()) do
				local lower = string.lower(key)
				if type(value) == "string" and (lower:find("skin") or lower:find("parry")) then
					skin = string.lower(value)
					break
				end
			end
		end
		if skin ~= "" then break end
	end

	for _, entry in ipairs(H.PARRY_SKINS) do
		for _, word in ipairs(entry[1]) do
			if skin:find(word, 1, true) then return entry[2] end
		end
	end

	return "109133187196613"
end

function H.v2DoParry()
	if not H.v2CanParry() then return end
	S.parry.resolving = true

	local resolveToken = S.parry.token

	if F.parryV2Trigger == "Button" then
		local button = H.control(true, { "Gui-mob", "GuiMob" })
		if button and H.visibleChain(button) and button.AbsoluteSize.X >= 4 then
			H.tap(button, 0.06)
		else
			pcall(function()
				local mouse = UserInputService:GetMouseLocation()
				VirtualInputManager:SendMouseButtonEvent(mouse.X, mouse.Y, 0, true, game, 0)
				task.wait(0.06)
				VirtualInputManager:SendMouseButtonEvent(mouse.X, mouse.Y, 0, false, game, 0)
			end)
		end
	else
		local remote = H.parryRemote()
		if remote then pcall(function() remote:FireServer() end) end

		local root, humanoid = H.root(), H.humanoid()
		local camera = workspace.CurrentCamera

		if root and humanoid then
			local look = H.flat(camera.CFrame.LookVector)
			if look.Magnitude > 0 then
				local target = CFrame.lookAt(root.Position, root.Position + look)
				humanoid.AutoRotate = false
				pcall(function() TweenService:Create(root, TweenInfo.new(0.2), { CFrame = target }):Play() end)

				task.spawn(function()
					local stop = os.clock() + 0.8
					while os.clock() < stop do
						RunService.Heartbeat:Wait()
						if root.Parent then root.CFrame = CFrame.lookAt(root.Position, root.Position + look) end
					end
					humanoid.AutoRotate = true
				end)
			end

			local animator = humanoid:FindFirstChildOfClass("Animator")
			if animator then
				pcall(function()
					local animation = Instance.new("Animation")
					animation.AnimationId = "rbxassetid://" .. H.parrySkinAnim()
					local track = animator:LoadAnimation(animation)
					track.Priority = Enum.AnimationPriority.Action4
					track:Play()
				end)
			end

			pcall(function() CollectionService:AddTag(root, "doing action") end)
		end
	end

	task.delay(2, function()
		if S.parry.resolving and S.parry.token == resolveToken then
			H.parryCooldown(F.parryV2Trigger == "Button" and 1.2 or 60)
			local root = H.root()
			if root then pcall(function() CollectionService:RemoveTag(root, "doing action") end) end
		end
	end)
end

function H.lineOfSight(fromRoot, toRoot)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { fromRoot.Parent, toRoot.Parent }
	return workspace:Raycast(fromRoot.Position, toRoot.Position - fromRoot.Position, params) == nil
end

function H.parryV2(killerRoot)
	if not H.v2CanParry() then return end

	local root = H.root()
	if not root then return end

	local function facingOk()
		local offset = root.Position - killerRoot.Position
		local flat = Vector3.new(offset.X, 0, offset.Z)
		if flat.Magnitude < 0.01 then return true end
		return H.flat(killerRoot.CFrame.LookVector):Dot(flat.Unit) >= math.clamp(F.parryV2Face, -1, 1)
	end

	local distance = (killerRoot.Position - root.Position).Magnitude

	if F.parryV2Mode == "Aggressive" then
		if distance > F.parryV2Range + 3 then return end
		local deadline = os.clock() + 1.5
		while os.clock() < deadline do
			if (killerRoot.Position - root.Position).Magnitude <= F.parryV2Range and facingOk() then
				H.v2DoParry()
				return
			end
			RunService.Heartbeat:Wait()
		end
		return
	end

	if distance > F.parryV2Range or not facingOk() or not H.lineOfSight(killerRoot, root) then return end

	if F.parryV2Mode == "Strict" then
		local camera = workspace.CurrentCamera
		local look = H.flat(camera.CFrame.LookVector)
		local toKiller = H.flat(killerRoot.Position - root.Position)
		if look:Dot(toKiller) < 0.5 then return end
	end

	H.v2DoParry()
end

function H.attachSensor(player)
	if player == LocalPlayer then return end

	local function bind(character)
		local old = S.parry.sensors[player]
		if old then pcall(function() old:Disconnect() end) end
		S.parry.sensors[player] = nil

		if not (character and H.isKiller(player)) then return end

		local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 5)
		local animator = humanoid and (humanoid:FindFirstChildOfClass("Animator") or humanoid:WaitForChild("Animator", 5))
		if not animator then return end

		S.parry.sensors[player] = animator.AnimationPlayed:Connect(function(track)
			if not alive() then return end
			local id = H.animId(track)
			local killerRoot = H.root(character)
			if not (id and killerRoot) then return end

			if id == "80411309607666" and F.autoCrouch and not H.downed(H.char()) then
				if H.distance(killerRoot.Position) <= 40 then task.spawn(H.crouchDodge) end
			end

			if F.parryV1 and H.KILLER_ANIMS[id] and id ~= "80411309607666" then task.spawn(H.parryV1, killerRoot, id) end
			if F.parryV2 and H.V2_ANIMS[id] then task.spawn(H.parryV2, killerRoot) end
		end)
		table.insert(S.connections, S.parry.sensors[player])
	end

	if player.Character then task.spawn(bind, player.Character) end
	H.track(player.CharacterAdded:Connect(function(character) task.wait(0.5) bind(character) end))
	H.track(player:GetPropertyChangedSignal("Team"):Connect(function() task.wait(0.5) bind(player.Character) end))
end

for _, player in ipairs(Players:GetPlayers()) do H.attachSensor(player) end
H.track(Players.PlayerAdded:Connect(H.attachSensor))

S.parryCircle = H.make("CylinderHandleAdornment", {
	Height = 0.05, Transparency = 1, Color3 = Color3.new(1, 1, 1), AlwaysOnTop = false, ZIndex = 1,
})

H.track(RunService.Heartbeat:Connect(function()
	if not alive() then return end

	local root = H.root()
	local circle = S.parryCircle
	local show = root and ((F.parryV1 and F.parryV1Circle) or (F.parryV2 and F.parryV2Circle))

	if not show then
		circle.Transparency = 1
		return
	end

	local radius = F.parryV2 and F.parryV2Range or F.parryV1Radius
	circle.Adornee = workspace.Terrain
	circle.Radius = radius
	circle.InnerRadius = math.max(0, radius - 0.15)
	circle.Transparency = 0.3
	circle.Color3 = S.parry.cooldown and Color3.fromRGB(255, 128, 0)
		or (F.parryV1Aggressive and Color3.fromRGB(255, 60, 60) or Color3.new(1, 1, 1))

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { H.char() }
	local hit = workspace:Raycast(root.Position, Vector3.new(0, -15, 0), params)
	local ground = hit and hit.Position or (root.Position - Vector3.new(0, 3, 0))

	circle.CFrame = CFrame.new(ground + Vector3.new(0, 0.05, 0)) * CFrame.Angles(math.pi / 2, 0, 0)
end))

S.pallet = { used = {}, last = 0 }

function H.palletRef(pallet)
	return pallet:FindFirstChild("PrimaryPartPallet") or pallet:FindFirstChild("PalletPoint")
		or pallet:FindFirstChild("PalletPointSlide") or pallet:FindFirstChildWhichIsA("BasePart")
end

function H.palletFirePart(pallet)
	return pallet:FindFirstChild("PalletPointSlide") or pallet:FindFirstChild("PalletPoint")
		or pallet:FindFirstChildWhichIsA("BasePart")
end

H.loop(0.3, function()
	if not F.autoPallet or H.role() ~= "Survivor" then return end
	if os.clock() - S.pallet.last < 2.5 then return end

	local character, root, humanoid = H.char(), H.root(), H.humanoid()
	if not (character and root and humanoid) or humanoid.Health <= 0 then return end

	if F.autoPalletSafety then
		if character:GetAttribute("Knocked") or character:GetAttribute("IsCarried") or character:GetAttribute("IsHooked") then return end
		if H.busy(character, { "isVaulting", "isRepairing", "isUnhooking", "isHealing", "isSliding", "isCarrying" }) then return end
	end

	local killer = H.nearestPlayer(function(player) return H.isKiller(player) end, F.autoPalletDistance)
	if not killer then return end

	local best, bestDistance = nil, F.autoPalletDistance

	for _, pallet in ipairs(MAP.Pallets) do
		if pallet.Parent and not S.pallet.used[pallet] then
			local ref = H.palletRef(pallet)
			if ref then
				local distance = (ref.Position - root.Position).Magnitude
				if distance < bestDistance then best, bestDistance = pallet, distance end
			end
		end
	end

	if best then
		local part = H.palletFirePart(best)
		if part then
			H.fire("Pallet.PalletDropEvent", part)
			S.pallet.used[best] = true
			S.pallet.last = os.clock()
		end
	end
end)

H.onCharacter(function()
	table.clear(S.pallet.used)
	S.pallet.last = 0
end, 0.1)

function H.dropAllPallets()
	local map = workspace:FindFirstChild("Map")
	local remote = H.remote("Pallet.PalletDropEvent")

	if not map then H.notify("Pallets", "No map loaded.", 3) return end
	if not remote then H.notify("Pallets", "Pallet remote not found.", 3) return end

	local count = 0
	for _, item in ipairs(map:GetDescendants()) do
		if item:IsA("BasePart") and item.Name == "PalletPoint" then
			pcall(function() remote:FireServer(item) end)
			count = count + 1
		end
	end

	H.notify("Pallets", count .. " pallets dropped.", 3)
end

S.veil = { target = nil }

U.veilCircle = H.drawing("Circle", { Visible = false, Thickness = 1.5, NumSides = 64, Filled = false, Color = Color3.fromRGB(255, 60, 60), Transparency = 0.6 })

S.veilHighlight = H.make("Highlight", {
	Name = tostring(math.random(100000, 999999)), FillColor = Color3.fromRGB(255, 60, 60), FillTransparency = 0.6,
	OutlineColor = Color3.fromRGB(255, 255, 255), OutlineTransparency = 0, Enabled = false,
})

function H.screenCenter()
	local camera = workspace.CurrentCamera
	return camera.ViewportSize / 2
end

function H.veilTarget()
	local camera = workspace.CurrentCamera
	local center = H.screenCenter()
	local origin = H.root()
	if not origin then return nil end

	local best, bestScore = nil, F.veilFov

	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer and not H.isKiller(player) and player.Character then
			local humanoid = H.humanoid(player.Character)
			local part = H.root(player.Character)
			if humanoid and humanoid.Health > 0 and part and (part.Position - origin.Position).Magnitude <= F.veilMaxDist then
				local point, onScreen = camera:WorldToViewportPoint(part.Position)
				if onScreen then
					local score = (Vector2.new(point.X, point.Y) - center).Magnitude
					if score < bestScore then best, bestScore = part, score end
				end
			end
		end
	end

	return best
end

function H.ballistic(origin, goal, speed, gravity)
	local delta = goal - origin
	local flat = Vector3.new(delta.X, 0, delta.Z)
	local x = flat.Magnitude
	if x < 0.01 then return delta.Unit, 0 end

	local y = delta.Y
	local s2 = speed * speed
	local inner = s2 * s2 - gravity * (gravity * x * x + 2 * y * s2)
	if inner < 0 then inner = 0 end

	local theta = math.atan((s2 - math.sqrt(inner)) / (gravity * x))
	local time = x / (speed * math.cos(theta))
	local direction = flat.Unit * math.cos(theta) + Vector3.new(0, math.sin(theta), 0)

	return direction.Unit, time
end

function H.targetVelocity(part)
	local humanoid = part.Parent and part.Parent:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.MoveDirection.Magnitude > 0.05 then
		return humanoid.MoveDirection * humanoid.WalkSpeed
	end
	return part.AssemblyLinearVelocity
end

function H.solveSpear(dirArg, originArg)
	local character = H.char()
	if not character then return nil end

	local special = character:GetAttribute("special")
	local speed = special and F.auraSpeed or F.spearSpeed
	local gravity = special and F.auraGravity or F.spearGravity

	local root = H.root(character)
	local head = character:FindFirstChild("Head")

	local origin = typeof(originArg) == "Vector3" and originArg or nil
	if not origin then
		if F.veilPredict and root then
			origin = root.Position
		else
			origin = (head and head.Position) or (root and root.Position)
		end
	end
	if not origin then return nil end

	local target = H.veilTarget()
	if not target then return nil end

	local goal = target.Position
	local direction, time = H.ballistic(origin, goal, speed, gravity)

	if F.veilPredict then
		local velocity = H.targetVelocity(target)
		local horizontal = Vector3.new(velocity.X, 0, velocity.Z)
		if horizontal.Magnitude > 0.5 then
			local distance = (goal - origin).Magnitude
			local lead = horizontal * (time * F.veilLead)
			local limit = math.clamp(distance * 0.6, 3, 45)
			if lead.Magnitude > limit then lead = lead.Unit * limit end
			direction = H.ballistic(origin, goal + lead, speed, gravity)
		end
	end

	return direction, speed, origin
end

H.track(RunService.RenderStepped:Connect(function()
	local show = F.veil and H.role() == "Killer"

	if U.veilCircle then
		U.veilCircle.Visible = show and F.veilShowFov
		if show then
			U.veilCircle.Position = H.screenCenter()
			U.veilCircle.Radius = F.veilFov
		end
	end

	local target = show and H.veilTarget() or nil
	S.veil.target = target

	if S.veilHighlight then
		if target then
			S.veilHighlight.Adornee = target.Parent
			S.veilHighlight.Enabled = true
		else
			S.veilHighlight.Enabled = false
		end
	end
end))

S.killerAim = { holding = false, target = nil }

S.killerHighlight = H.make("Highlight", {
	Name = tostring(math.random(100000, 999999)), FillColor = Color3.fromRGB(255, 0, 0), FillTransparency = 0.5,
	OutlineColor = Color3.fromRGB(255, 255, 255), OutlineTransparency = 0, Enabled = false,
})

function H.killerAimTarget()
	local player = H.nearestPlayer(function(other)
		local humanoid = H.humanoid(other.Character)
		return not H.isKiller(other) and humanoid ~= nil and humanoid.Health > 0 and not H.downed(other.Character)
	end, F.killerAimDist)
	return player and H.root(player.Character) or nil
end

function H.killerAimBegin()
	if not F.killerAim or H.role() ~= "Killer" then return end
	S.killerAim.holding = true
	S.killerAim.target = H.killerAimTarget()
end

function H.killerAimEnd()
	S.killerAim.holding = false
	S.killerAim.target = nil
end

H.track(UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then H.killerAimBegin() end
end))

H.track(UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then H.killerAimEnd() end
end))

S.killerAttackBound = nil

H.loop(1, function()
	if not UserInputService.TouchEnabled then return end
	local attack = H.control(false, { "attack" })
	if not attack or S.killerAttackBound == attack then return end
	S.killerAttackBound = attack

	H.track(attack.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then H.killerAimBegin() end
	end))
	H.track(attack.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then H.killerAimEnd() end
	end))
end)

H.track(RunService.RenderStepped:Connect(function()
	local target = S.killerAim.target
	local active = F.killerAim and S.killerAim.holding and target and target.Parent ~= nil

	if S.killerHighlight then
		S.killerHighlight.Enabled = active and true or false
		if active then S.killerHighlight.Adornee = target.Parent end
	end

	if not active then return end

	local root = H.root()
	local camera = workspace.CurrentCamera
	if not root then return end

	local alpha = math.clamp(1 - F.killerAimSmooth, 0.05, 1)
	local look = CFrame.lookAt(camera.CFrame.Position, target.Position)
	camera.CFrame = camera.CFrame:Lerp(look, alpha)

	local flatTarget = Vector3.new(target.Position.X, root.Position.Y, target.Position.Z)
	if (flatTarget - root.Position).Magnitude > 0.1 then
		root.CFrame = root.CFrame:Lerp(CFrame.lookAt(root.Position, flatTarget), alpha)
	end
end))

H.loop(0.3, function()
	if not F.antiParry or H.role() ~= "Killer" then return end

	local near = H.nearestPlayer(function(player) return not H.isKiller(player) end, 15)
	if not near then return end

	local humanoid = H.humanoid()
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then return end

	local animation = Instance.new("Animation")
	animation.AnimationId = "rbxassetid://117042998468241"
	local track = animator:LoadAnimation(animation)
	track:Play(0, 0, 1)
	task.wait(0.05)
	track:Stop(0)
	track:Destroy()
	animation:Destroy()
end)

S.lungeConn = nil

function H.applyLunge(character)
	if S.lungeConn then pcall(function() S.lungeConn:Disconnect() end) S.lungeConn = nil end
	character = character or H.char()
	if not character then return end

	if F.infiniteLunge then
		character:SetAttribute("lungeboost", 999)
		S.lungeConn = character:GetAttributeChangedSignal("lungeboost"):Connect(function()
			if F.infiniteLunge and character:GetAttribute("lungeboost") ~= 999 then
				character:SetAttribute("lungeboost", 999)
			end
		end)
		H.track(S.lungeConn)
	else
		character:SetAttribute("lungeboost", 1)
	end
end

H.onCharacter(function(character) if F.infiniteLunge then H.applyLunge(character) end end, 1)

H.loop(0.35, function()
	if not F.autoStalk or H.role() ~= "Killer" then return end
	local remote = H.remote("Killers.Stalker.StartStalking")
	if not remote then return end

	local target = H.nearestPlayer(function(player)
		local humanoid = H.humanoid(player.Character)
		return not H.isKiller(player) and humanoid ~= nil and humanoid.Health > 30
	end, 150)

	if target then pcall(function() remote:FireServer(target) end) end
end)

H.track(RunService.Heartbeat:Connect(function()
	if not F.noSlowdown or H.role() ~= "Killer" then return end
	local humanoid = H.humanoid()
	if humanoid and humanoid.WalkSpeed < 16 then humanoid.WalkSpeed = 16 end
end))

S.hidden = { running = false }

function H.hiddenFind()
	local found = {}
	if type(getgc) ~= "function" or type(debug.getinfo) ~= "function" then return found end

	for _, item in ipairs(getgc(true)) do
		if type(item) == "function" and (type(islclosure) ~= "function" or islclosure(item)) then
			local ok, info = pcall(debug.getinfo, item)
			if ok and info and (info.name == "tryActivate" or info.name == "playM2Animation") then
				table.insert(found, item)
			end
		end
	end

	return found
end

function H.setHiddenNoCd(state)
	F.hiddenNoCd = state
	if not state or S.hidden.running then return end

	if type(debug.setupvalue) ~= "function" or type(debug.getupvalues) ~= "function" then
		H.notify("Hidden", "This executor has no debug.setupvalue.", 5)
		return
	end

	S.hidden.running = true

	task.spawn(function()
		local _, closures = H.gcall(H.hiddenFind)
		closures = type(closures) == "table" and closures or {}
		local refreshAt = os.clock() + 8

		while alive() and F.hiddenNoCd do
			if #closures == 0 or os.clock() > refreshAt then
				local _, fresh = H.gcall(H.hiddenFind)
				closures = type(fresh) == "table" and fresh or {}
				refreshAt = os.clock() + 8
			end

			H.gcall(function()
				for _, closure in ipairs(closures) do
					local ok, values = pcall(debug.getupvalues, closure)
					if ok and type(values) == "table" then
						for index, value in pairs(values) do
							if value == true then pcall(debug.setupvalue, closure, index, false) end
						end
					end
				end
			end)

			task.wait(0.1)
		end

		S.hidden.running = false
	end)
end

H.onCharacter(function() if F.hiddenNoCd and not S.hidden.running then H.setHiddenNoCd(true) end end, 2)

S.corrupt = { holding = false }

function H.isAbyss()
	local value = LocalPlayer:FindFirstChild("SelectedKiller")
	local name = (value and value.Value) or LocalPlayer:GetAttribute("SelectedKiller")
	return name ~= nil and string.find(string.lower(tostring(name)), "abyss", 1, true) ~= nil
end

H.track(UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.Q then S.corrupt.holding = true end
end))

H.track(UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.Q then S.corrupt.holding = false end
end))

H.loop(0.5, function()
	if not F.infiniteCorrupt or H.role() ~= "Killer" or not H.isAbyss() then return end

	local active = S.corrupt.holding
	if not active and UserInputService.TouchEnabled then
		local move2 = H.control(false, { "move2" })
		active = move2 ~= nil and move2.Visible and H.visibleChain(move2)
	end

	if active then H.fire("Killers.Abysswalker.corrupt") end
end)

function H.setFlaskSilent(state)
	F.flaskSilent = state
	if state and not H.namecallHook() then
		F.flaskSilent = false
		H.notify("Flask", "This executor has no hookmetamethod.", 5)
	end
end

function H.setVeil(state)
	F.veil = state
	if state and not H.namecallHook() then
		F.veil = false
		H.notify("Veil", "This executor has no hookmetamethod.", 5)
	end
end

function H.setHookFlag(key, state)
	F[key] = state
	if state and not H.namecallHook() then
		F[key] = false
		H.notify("Hook", "This executor has no hookmetamethod.", 5)
	end
end

S.flaskLaser = nil

function H.flaskAiming(character)
	for _, item in ipairs(character:GetChildren()) do
		if item:IsA("LocalScript") and item:GetAttribute("action") == true then return true end
	end
	return false
end

H.track(RunService.RenderStepped:Connect(function()
	local character = H.char()
	local show = F.flaskLaser and H.role() == "Killer" and character ~= nil and H.flaskAiming(character)
	local target, hand = nil, nil

	if show then
		hand = character:FindFirstChild("LeftHand") or character:FindFirstChild("Left Arm") or H.root(character)
		local player = H.nearestPlayer(function(other) return not H.isKiller(other) end)
		target = player and H.root(player.Character)
	end

	if not (show and hand and target) then
		if S.flaskLaser then S.flaskLaser.Transparency = 1 end
		return
	end

	if not S.flaskLaser or not S.flaskLaser.Parent then
		S.flaskLaser = H.make("Part", {
			Name = tostring(math.random(100000, 999999)), Anchored = true, CanCollide = false, CanQuery = false,
			CanTouch = false, CastShadow = false, Material = Enum.Material.Neon, Color = Color3.fromRGB(255, 50, 50),
		}, workspace)
	end

	local from, to = hand.Position, target.Position
	local length = (to - from).Magnitude
	S.flaskLaser.Size = Vector3.new(0.16, 0.16, length)
	S.flaskLaser.CFrame = CFrame.lookAt(from, to) * CFrame.new(0, 0, -length / 2)
	S.flaskLaser.Transparency = 0.2
end))

S.antiLoop = { conns = {} }

function H.setAntiLoop(state)
	F.antiLoop = state

	for _, connection in ipairs(S.antiLoop.conns) do pcall(function() connection:Disconnect() end) end
	table.clear(S.antiLoop.conns)

	local map = workspace:FindFirstChild("Map")
	if not map then return end

	if state then
		local vault = H.remote("Window.VaultEvent")
		local slide = H.remote("Pallet.PalletSlideEvent")

		for _, item in ipairs(map:GetDescendants()) do
			if item.Name == "VaultTrigger" and vault then
				pcall(function() vault:FireServer(item, true) end)
			elseif item.Name == "PalletPointSlide" and item:IsA("BasePart") and slide then
				pcall(function() slide:FireServer(item, true) end)
			end
		end

		local function watch(item)
			if item.Name ~= "PalletPoint" and item.Name ~= "PalletPointSlide" then return end
			table.insert(S.antiLoop.conns, item:GetPropertyChangedSignal("Name"):Connect(function()
				if F.antiLoop and item.Name == "PalletPointSlide" then
					task.wait(0.1)
					if slide then pcall(function() slide:FireServer(item, true) end) end
				end
			end))
		end

		for _, item in ipairs(map:GetDescendants()) do watch(item) end
		table.insert(S.antiLoop.conns, map.DescendantAdded:Connect(watch))
		return
	end

	local vaultDone = H.remote("Window.VaultCompleteEvent")
	local slideDone = H.remote("Pallet.PalletSlideCompleteEvent")

	for _, item in ipairs(map:GetDescendants()) do
		if item.Name == "VaultPointInUse" and vaultDone then
			pcall(function() vaultDone:FireServer(item.Parent, false) end)
		elseif item.Name == "PalletPointSlideInUse" and slideDone then
			pcall(function() slideDone:FireServer(item.Parent, false) end)
		end
	end
end

S.esp = { players = {}, map = {} }

function H.itemIcon(name)
	local items = ReplicatedStorage:FindFirstChild("Items")
	local item = items and items:FindFirstChild(tostring(name))
	if not item then return nil end
	local ok, texture = pcall(function() return item.Texture end)
	if ok and texture and texture ~= "" then return texture end
	local attribute = item:GetAttribute("Texture") or item:GetAttribute("Icon")
	return attribute
end

function H.killerName(player)
	local name = player:GetAttribute("SelectedKiller")
	if not name then
		local value = player:FindFirstChild("SelectedKiller")
		if value then pcall(function() name = value.Value end) end
	end
	if name and tostring(name) ~= "" then return tostring(name) end
	return player.Name
end

function H.espClear(entry)
	if not entry then return end
	for _, object in pairs(entry) do
		if typeof(object) == "Instance" then pcall(function() object:Destroy() end) end
	end
end

function H.espBuild(player, character)
	local highlight = H.make("Highlight", {
		Name = H.isKiller(player) and "KEH" or "PEH", FillTransparency = 0.6, OutlineTransparency = 0,
		DepthMode = Enum.HighlightDepthMode.AlwaysOnTop, Adornee = character,
	})

	local head = character:FindFirstChild("Head") or H.root(character)
	local billboard = H.make("BillboardGui", {
		Name = tostring(math.random(100000, 999999)), Size = UDim2.fromOffset(200, 54),
		StudsOffset = Vector3.new(0, 3, 0), AlwaysOnTop = true, Adornee = head, MaxDistance = math.huge,
	}, H.guiParent())

	local label = H.make("TextLabel", {
		Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
		TextSize = 13, TextStrokeTransparency = 0.4, TextColor3 = Color3.new(1, 1, 1), RichText = true,
		TextYAlignment = Enum.TextYAlignment.Bottom,
	}, billboard)

	local icon = H.make("ImageLabel", {
		Size = UDim2.fromOffset(22, 22), Position = UDim2.new(0.5, -11, 0, -22), BackgroundTransparency = 1, Visible = false,
	}, billboard)

	return { highlight = highlight, billboard = billboard, label = label, icon = icon, character = character }
end

function H.espStatus(player, character, humanoid)
	if character:GetAttribute("IsHooked") then return "HOOKED" end
	if character:GetAttribute("Knocked") then return "DOWN" end
	if humanoid and humanoid.Health < humanoid.MaxHealth then return "INJURED" end
	return nil
end

function H.espUpdatePlayer(player)
	local entry = S.esp.players[player]
	local character = player.Character
	local killer = H.isKiller(player)
	local wanted = F.esp and character ~= nil and H.root(character) ~= nil
		and ((killer and F.espKiller) or (not killer and F.espPlayer))
		and player.Team ~= nil and player.Team.Name ~= "Spectator"

	local distance = wanted and H.distance(H.root(character).Position) or math.huge
	if distance > F.espMax then wanted = false end

	if not wanted then
		if entry then H.espClear(entry) S.esp.players[player] = nil end
		return
	end

	if not entry or entry.character ~= character or not entry.highlight.Parent then
		H.espClear(entry)
		entry = H.espBuild(player, character)
		S.esp.players[player] = entry
	end

	local color = killer and C.killer or C.player
	entry.highlight.FillColor = color
	entry.highlight.OutlineColor = color
	entry.highlight.FillTransparency = F.espOutline and 1 or 0.6

	local humanoid = H.humanoid(character)
	local lines = {}

	local warn = ""
	if killer and F.espKillerWarn then
		if distance <= 40 then warn = " !!" elseif distance <= 80 then warn = " !" end
	end

	if F.espName then
		table.insert(lines, (killer and H.killerName(player) or player.DisplayName) .. warn)
	elseif warn ~= "" then
		table.insert(lines, warn)
	end

	if F.espDistance then table.insert(lines, string.format("[%dm]", math.floor(distance))) end

	if F.espStatus and not killer then
		local status = H.espStatus(player, character, humanoid)
		if status then table.insert(lines, status) end
	end

	if F.espHookCount and not killer then
		table.insert(lines, "Hooks: " .. tostring(player:GetAttribute("HookCount") or 0))
	end

	entry.label.Text = table.concat(lines, "\n")
	entry.label.TextColor3 = color

	local iconImage = nil
	if F.espItem and not killer then
		local item = player:GetAttribute("EquippedItem")
		if item and item ~= "" then iconImage = H.itemIcon(item) end
	end

	entry.icon.Visible = iconImage ~= nil
	if iconImage then entry.icon.Image = iconImage end
end

H.loop(0.2, function()
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer then pcall(H.espUpdatePlayer, player) end
	end
	for player, entry in pairs(S.esp.players) do
		if not player.Parent then H.espClear(entry) S.esp.players[player] = nil end
	end
end)

H.track(Players.PlayerRemoving:Connect(function(player)
	H.espClear(S.esp.players[player])
	S.esp.players[player] = nil
end))

function H.mapMark(key, model, color, label, box)
	local entry = S.esp.map[model]

	if not entry or not entry.highlight.Parent then
		H.espClear(entry)
		local part = H.firstPart(model)
		if not part then return end

		entry = { kind = key }
		if box then
			entry.highlight = H.make("BoxHandleAdornment", {
				Adornee = box, Size = box.Size, AlwaysOnTop = true, ZIndex = 5, Transparency = 0.5, Color3 = color,
			}, box)
		else
			entry.highlight = H.make("Highlight", {
				FillTransparency = 0.6, OutlineTransparency = 0, DepthMode = Enum.HighlightDepthMode.AlwaysOnTop, Adornee = model,
			}, model)
		end

		if label ~= nil then
			entry.billboard = H.make("BillboardGui", {
				Size = UDim2.fromOffset(120, 24), AlwaysOnTop = true, Adornee = part, StudsOffset = Vector3.new(0, 4, 0),
			}, H.guiParent())
			entry.label = H.make("TextLabel", {
				Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
				TextSize = 12, TextStrokeTransparency = 0.4,
			}, entry.billboard)
		end

		S.esp.map[model] = entry
	end

	if entry.highlight:IsA("Highlight") then
		entry.highlight.FillColor = color
		entry.highlight.OutlineColor = color
	else
		entry.highlight.Color3 = color
	end

	if entry.label then
		entry.label.Text = label or ""
		entry.label.TextColor3 = color
	end

	entry.seen = true
end

function H.mapEspTick()
	for _, entry in pairs(S.esp.map) do entry.seen = false end

	if F.esp then
		if F.espGen then
			for _, gen in ipairs(MAP.Generators) do
				local progress = tonumber(gen.model:GetAttribute("RepairProgress")) or 0
				local ratio = math.clamp(progress / 100, 0, 1)
				local color = C.generator:Lerp(C.generatorDone, ratio)
				local text = ratio >= 1 and "DONE" or string.format("GEN %d%%", math.floor(progress))
				H.mapMark("gen", gen.model, color, F.espGenName and text or nil)
			end
		end

		if F.espPallet then
			for _, pallet in ipairs(MAP.Pallets) do H.mapMark("pallet", pallet, C.pallet) end
		end

		if F.espHook then
			for _, hook in ipairs(MAP.Hooks) do H.mapMark("hook", hook, C.hook) end
		end

		if F.espGate then
			for _, gate in ipairs(MAP.Gates) do H.mapMark("gate", gate, C.gate) end
		end

		if F.espWindow then
			for _, window in ipairs(MAP.Windows) do
				local bottom = window:FindFirstChild("Bottom")
				if bottom and bottom:IsA("BasePart") then H.mapMark("window", window, C.window, nil, bottom) end
			end
		end

		if F.espScp then
			for _, scp in ipairs(MAP.SCPs) do
				local humanoid = scp:FindFirstChildOfClass("Humanoid")
				if humanoid and humanoid.Health > 0 and math.floor(humanoid.WalkSpeed) == 9 then
					H.mapMark("scp", scp, C.scp)
				end
			end
		end
	end

	for model, entry in pairs(S.esp.map) do
		if not entry.seen or not model.Parent then
			H.espClear(entry)
			S.esp.map[model] = nil
		end
	end
end

H.loop(0.5, function()
	if F.esp and F.espGen then
		for _, gen in ipairs(MAP.Generators) do
			local entry = S.esp.map[gen.model]
			if entry and entry.label then
				local progress = tonumber(gen.model:GetAttribute("RepairProgress")) or 0
				local ratio = math.clamp(progress / 100, 0, 1)
				local color = C.generator:Lerp(C.generatorDone, ratio)
				entry.label.Text = F.espGenName and (ratio >= 1 and "DONE" or string.format("GEN %d%%", math.floor(progress))) or ""
				entry.label.TextColor3 = color
				if entry.highlight:IsA("Highlight") then
					entry.highlight.FillColor = color
					entry.highlight.OutlineColor = color
				end
			end
		end
	end
end)

H.loop(2, H.mapEspTick)

function H.refreshMapEsp()
	for _, entry in pairs(S.esp.map) do H.espClear(entry) end
	table.clear(S.esp.map)
	task.spawn(function()
		H.scanMap(true)
		H.mapEspTick()
	end)
end

S.world = { gfx = {}, gfxConn = nil }

function H.worldTick()
	if F.fullBright then
		H.setProp(Lighting, "Brightness", 2.8)
		H.setProp(Lighting, "ClockTime", F.timeOfDay)
		H.setProp(Lighting, "FogEnd", 100000)
		H.setProp(Lighting, "Ambient", Color3.fromRGB(200, 200, 200))
		H.setProp(Lighting, "OutdoorAmbient", Color3.fromRGB(200, 200, 200))
	end

	if F.noFog then
		H.setProp(Lighting, "FogEnd", 100000)
		H.setProp(Lighting, "FogStart", 100000)
		for _, item in ipairs(Lighting:GetChildren()) do
			if item:IsA("Atmosphere") then
				H.setProp(item, "Density", 0)
				H.setProp(item, "Haze", 0)
				H.setProp(item, "Glare", 0)
			end
		end
	end

	if F.noShadow then H.setProp(Lighting, "GlobalShadows", false) end
end

H.loop(0.4, H.worldTick)

function H.restoreWorld(keys)
	for _, key in ipairs(keys) do H.restoreProp(Lighting, key) end
end

function H.lowGfxItem(item)
	if item:IsA("BasePart") then
		if S.world.gfx[item] == nil then S.world.gfx[item] = { Material = item.Material } end
		item.Material = Enum.Material.SmoothPlastic
	elseif item:IsA("ParticleEmitter") or item:IsA("Trail") or item:IsA("Smoke") or item:IsA("Fire") or item:IsA("Sparkles") then
		if S.world.gfx[item] == nil then S.world.gfx[item] = { Enabled = item.Enabled } end
		item.Enabled = false
	elseif item:IsA("Decal") or item:IsA("Texture") then
		if S.world.gfx[item] == nil then S.world.gfx[item] = { Transparency = item.Transparency } end
		item.Transparency = 1
	end
end

function H.setLowGfx(state)
	F.lowGfx = state

	if S.world.gfxConn then pcall(function() S.world.gfxConn:Disconnect() end) S.world.gfxConn = nil end

	if state then
		task.spawn(function()
			for index, item in ipairs(workspace:GetDescendants()) do
				if index % 500 == 0 then task.wait() end
				if not F.lowGfx then return end
				pcall(H.lowGfxItem, item)
			end
		end)
		S.world.gfxConn = H.track(workspace.DescendantAdded:Connect(function(item)
			if F.lowGfx then pcall(H.lowGfxItem, item) end
		end))
		return
	end

	for item, values in pairs(S.world.gfx) do
		for key, value in pairs(values) do pcall(function() item[key] = value end) end
	end
	table.clear(S.world.gfx)
end

S.info = { gui = nil, lines = {} }

function H.infoPanel()
	if S.info.gui and S.info.gui.Parent then return S.info.gui end

	local frame = H.make("Frame", {
		Name = tostring(math.random(100000, 999999)), Size = UDim2.fromOffset(240, 0), AutomaticSize = Enum.AutomaticSize.Y,
		Position = UDim2.new(0, 14, 0.35, 0), BackgroundColor3 = Color3.fromRGB(16, 16, 20), BackgroundTransparency = 0.25,
		BorderSizePixel = 0, Active = true, Draggable = true, Visible = false,
	})
	H.make("UICorner", { CornerRadius = UDim.new(0, 8) }, frame)
	H.make("UIPadding", {
		PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8), PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10),
	}, frame)
	H.make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, frame)

	S.info.gui = frame
	return frame
end

function H.infoLine(key, order, text)
	local frame = H.infoPanel()
	local label = S.info.lines[key]

	if text == nil then
		if label then label.Visible = false end
		return
	end

	if not label or not label.Parent then
		label = H.make("TextLabel", {
			Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
			Font = Enum.Font.GothamMedium, TextSize = 13, TextWrapped = true, RichText = true,
			TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(230, 230, 236), LayoutOrder = order,
		}, frame)
		S.info.lines[key] = label
	end

	label.Text = text
	label.Visible = true
end

function H.nextKillerText()
	local list = {}
	for _, player in ipairs(Players:GetPlayers()) do table.insert(list, player) end

	table.sort(list, function(a, b)
		local allowA = a:GetAttribute("AllowKiller") == true
		local allowB = b:GetAttribute("AllowKiller") == true
		if allowA ~= allowB then return allowA end
		return (tonumber(a:GetAttribute("KillerChance")) or 0) > (tonumber(b:GetAttribute("KillerChance")) or 0)
	end)

	local rows = { "<b>Next Killer</b>" }
	for index = 1, math.min(3, #list) do
		local player = list[index]
		table.insert(rows, string.format("%d. %s  (%s)", index, player.DisplayName, tostring(player:GetAttribute("KillerChance") or 0)))
	end
	return table.concat(rows, "\n")
end

H.MAP_NAMES = {
	{ { "random shakes", "SCP-173 Room", "SCP-205 Room" }, "Site 68" },
	{ { "HooksMeat" }, "BLOODBATH! Club" },
	{ { "Bldg_Addon_RooftopUnit_A", "Rooftop" }, "Mercy Hospital Rooftop" },
	{ { "White Armored Car" }, "Mount Massive Asylum" },
	{ { "Dumbster" }, "The Bay Harbor" },
	{ { "water pump" }, "Valdelobos Village" },
	{ { "LargeBoulder01" }, "Woodview Cabin" },
}

function H.mapName()
	local map = workspace:FindFirstChild("Map")
	if not map then return "Lobby" end

	for _, entry in ipairs(H.MAP_NAMES) do
		for _, name in ipairs(entry[1]) do
			if map:FindFirstChild(name) then return entry[2] end
		end
	end

	for _, child in ipairs(map:GetChildren()) do
		if child.Name == "Gate" and child:FindFirstChild("vfx") then return "Firelink Shrine" end
	end

	return "Unknown"
end

H.BODY_PARTS = {
	Head = true, Torso = true, UpperTorso = true, LowerTorso = true, HumanoidRootPart = true,
	["Left Arm"] = true, ["Right Arm"] = true, ["Left Leg"] = true, ["Right Leg"] = true,
	LeftUpperArm = true, LeftLowerArm = true, LeftHand = true, RightUpperArm = true, RightLowerArm = true, RightHand = true,
	LeftUpperLeg = true, LeftLowerLeg = true, LeftFoot = true, RightUpperLeg = true, RightLowerLeg = true, RightFoot = true,
}

function H.killerPerksText()
	for _, player in ipairs(Players:GetPlayers()) do
		if H.isKiller(player) and player.Character then
			local perks = {}
			for _, child in ipairs(player.Character:GetChildren()) do
				if not H.BODY_PARTS[child.Name] and string.match(child.Name, "^.+%s%d+$") then
					table.insert(perks, child.Name)
				end
			end
			if #perks == 0 then return "<b>Killer Perks</b>\nnone" end
			return "<b>Killer Perks</b>\n" .. table.concat(perks, "\n")
		end
	end
	return "<b>Killer Perks</b>\nno killer"
end

function H.spectatorText()
	local count, names = 0, {}
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Team and player.Team.Name == "Spectator" then
			count = count + 1
			table.insert(names, player.DisplayName)
		end
	end
	return string.format("<b>Spectators</b> %d\n%s", count, table.concat(names, ", "))
end

H.loop(1.5, function()
	local any = F.nextKiller or F.mapName or F.killerPerks or F.spectators
	local frame = H.infoPanel()
	frame.Visible = any

	H.infoLine("next", 1, F.nextKiller and H.nextKillerText() or nil)
	H.infoLine("map", 2, F.mapName and ("<b>Map</b> " .. H.mapName()) or nil)
	H.infoLine("perks", 3, F.killerPerks and H.killerPerksText() or nil)
	H.infoLine("spec", 4, F.spectators and H.spectatorText() or nil)
end)

S.stun = { bound = {} }

function H.stunShow(character)
	local head = character:FindFirstChild("Head") or H.root(character)
	if not head then return end

	local billboard = H.make("BillboardGui", {
		Size = UDim2.fromOffset(120, 30), AlwaysOnTop = true, Adornee = head, StudsOffset = Vector3.new(0, 5, 0),
	}, H.guiParent())
	H.make("TextLabel", {
		Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Font = Enum.Font.GothamBlack, TextSize = 18,
		Text = "STUNNED", TextColor3 = Color3.fromRGB(255, 220, 60), TextStrokeTransparency = 0.3,
	}, billboard)

	task.delay(2.2, function() pcall(function() billboard:Destroy() end) end)
end

function H.stunBind(character)
	if not character or S.stun.bound[character] then return end
	S.stun.bound[character] = true

	local function check(key)
		if F.stunIndicator and character:GetAttribute(key) == true then H.stunShow(character) end
	end

	H.track(character:GetAttributeChangedSignal("IsStunned"):Connect(function() check("IsStunned") end))
	H.track(character:GetAttributeChangedSignal("Immobile"):Connect(function() check("Immobile") end))
	H.track(character.AncestryChanged:Connect(function()
		if not character.Parent then S.stun.bound[character] = nil end
	end))
end

H.loop(1, function()
	if not F.stunIndicator then return end
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer and H.isKiller(player) and player.Character then H.stunBind(player.Character) end
	end
end)

S.tp = { Generators = 0, Hooks = 0, Gates = 0, Pallets = 0, Windows = 0 }

function H.teleportTo(position)
	local root = H.root()
	if root and position then root.CFrame = CFrame.new(position + Vector3.new(0, 3, 0)) end
end

function H.cycleTeleport(kind)
	H.scanMap()
	local list = MAP[kind]
	if not list or #list == 0 then
		H.notify("Teleport", "No " .. string.lower(kind) .. " found.", 3)
		return
	end

	S.tp[kind] = S.tp[kind] % #list + 1
	local item = list[S.tp[kind]]
	local part = kind == "Generators" and item.part or H.firstPart(item)
	if part then
		H.teleportTo(part.Position)
		H.notify("Teleport", string.format("%s %d/%d", kind, S.tp[kind], #list), 2)
	end
end

function H.playerNames()
	local names = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer then table.insert(names, player.Name) end
	end
	table.sort(names)
	return names
end

function H.teleportPlayer(name)
	local player = name and Players:FindFirstChild(name)
	local root = player and H.root(player.Character)
	if not root then
		H.notify("Teleport", "Player not available.", 3)
		return
	end
	H.teleportTo(root.Position)
end

shared.FacilityCleanup = function()
	F.hiddenNoCd = false
	pcall(H.setAntiLoop, false)
	pcall(H.setLowGfx, false)
	pcall(H.setStreamer, false)
	pcall(H.dbdStop)
	pcall(H.setMoonwalk, false)
	pcall(H.setZoom, false)
	pcall(H.setBypassGate, false)
	pcall(H.restoreAll)
	pcall(function() VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.LeftShift, false, game) end)

	for _, connection in ipairs(S.connections) do pcall(function() connection:Disconnect() end) end
	for _, connection in ipairs(S.streamer.conns) do pcall(function() connection:Disconnect() end) end
	for _, connection in ipairs(S.antiLoop.conns) do pcall(function() connection:Disconnect() end) end
	for _, connection in ipairs(S.perks.conns) do pcall(function() connection:Disconnect() end) end
	for _, thread in ipairs(S.threads) do pcall(task.cancel, thread) end
	for _, object in ipairs(S.drawings) do pcall(function() object:Remove() end) end
	for _, object in ipairs(S.instances) do pcall(function() object:Destroy() end) end

	if S.crosshair.gui then pcall(function() S.crosshair.gui:Destroy() end) end
	if S.gui then pcall(function() S.gui:Destroy() end) end

	if Movement then pcall(function() Movement:Unload() end) end
	pcall(function() Library:Destroy() end)
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

U.Main     = Window:Tab("Main", "house")
U.Survivor = Window:Tab("Survivor", "user-round")
U.Killer   = Window:Tab("Killer", "swords")
U.Visual   = Window:Tab("Visual", "eye")
U.Teleport = Window:Tab("Teleport", "map-pin")
Window:TabDivider()
U.Settings = Window:Tab("Settings", "cog")

U.move = U.Main:Section("Movement", 1)

H.T(U.move, "Auto Vault", "vd_auto_vault", false, function(state) F.autoVault = state end)
H.T(U.move, "Auto Pallet Slide", "vd_auto_slide", false, function(state) F.autoSlide = state end)
H.T(U.move, "Auto Run PC", "vd_auto_run_pc", false, function(state)
	F.autoRunPC = state
	if not state then VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.LeftShift, false, game) end
end)
H.T(U.move, "Auto Run Mobile", "vd_auto_run_mobile", false, function(state) F.autoRunMobile = state end)

U.move:Toggle({
	Text = "Speed Boost",
	Flag = "vd_speed",
	Default = false,
	Callback = function(state) F.speed = state end,
})
	:Keybind({ Default = "None", Flag = "vd_speed_key" })
	:Gear(function(panel)
		H.S(panel, "Amount", "vd_speed_value", 0.1, 3, 1, 1, function(value) F.speedValue = value end)
	end)

if Movement then
	Movement.Settings.WalkSpeedMode = "Velocity"

	U.move:Toggle({
		Text = "Fly",
		Flag = "vd_fly",
		Default = false,
		Callback = function(state) pcall(function() Movement:Fly(state) end) end,
	})
		:Keybind({ Default = "None", Flag = "vd_fly_key" })
		:Gear(function(panel)
			H.S(panel, "Fly Speed", "vd_fly_speed", 10, 200, 50, 0, function(value) Movement.Settings.FlySpeed = value end)
		end)

	H.T(U.move, "Noclip", "vd_noclip", false, function(state) Movement:Noclip(state) end)
	H.T(U.move, "Infinite Jump", "vd_inf_jump", false, function(state) Movement:InfiniteJump(state) end)
end

U.server = U.Main:Section("Server Utility", 1)
H.T(U.server, "Skip Endscreen", "vd_skip_end", false, function(state) F.skipEndscreen = state end)

U.perks = U.Main:Section("Fake Perks", 1)
H.T(U.perks, "Quick Recovery", "vd_perk_qr", false, function(state) F.qr = state end)
H.T(U.perks, "Perfect Landing", "vd_perk_pl", false, function(state) F.pl = state end)
H.T(U.perks, "Flowstate", "vd_perk_fs", false, function(state)
	F.fs = state
	local character = H.char()
	if character and state then character:SetAttribute("Flowstate", true) end
end)
H.T(U.perks, "Adrenaline Rush", "vd_perk_ar", false, function(state) F.ar = state end)
H.S(U.perks, "Perk Cooldown", "vd_perk_cd", 0, 180, 10, 0, function(value) F.perkCooldown = value end, " s")

U.utility = U.Main:Section("Players Utility", 1)
H.T(U.utility, "Invisibility", "vd_invis", false, function(state)
	if not H.setInvis(state) then Library.Flags["vd_invis"] = false end
end, "offsets your character look sent to the server")
H.T(U.utility, "Moonwalk Button", "vd_moon_button", false, function(state)
	F.moonwalkButton = state
	H.moonwalkButton(state)
end)

U.utility:Toggle({
	Text = "Moonwalk",
	Flag = "vd_moonwalk",
	Default = false,
	Callback = function(state) H.setMoonwalk(state) end,
})
	:Keybind({ Default = "None", Flag = "vd_moonwalk_key" })

U.cam = U.Main:Section("Camera", 2)

U.cam:Toggle({
	Text = "Stretch Res",
	Flag = "vd_stretch",
	Default = false,
	Callback = function(state) F.stretch = state end,
})
	:Gear(function(panel)
		H.S(panel, "Amount", "vd_stretch_amount", 0.4, 1, 0.67, 2, function(value) F.stretchAmount = value end)
	end)

H.T(U.cam, "Third Person (Killer)", "vd_third_person", false, function(state)
	F.thirdPerson = state
	if not state then H.thirdPersonReset() end
end)
H.T(U.cam, "Infinite Zoom Out", "vd_inf_zoom", false, function(state) H.setZoom(state) end)

U.cam:Toggle({
	Text = "Camera FOV",
	Flag = "vd_cam_fov",
	Default = false,
	Callback = function(state)
		F.camFov = state
		if not state and not F.dbd then workspace.CurrentCamera.FieldOfView = 70 end
	end,
})
	:Gear(function(panel)
		H.S(panel, "FOV", "vd_cam_fov_value", 60, 120, 90, 0, function(value) F.camFovValue = value end)
	end)

U.dbd = U.Main:Section("DBD Camera", 2)

U.dbd:Toggle({
	Text = "DBD Camera",
	Flag = "vd_dbd",
	Default = false,
	Callback = function(state)
		F.dbd = state
		if state then H.dbdStart() else H.dbdStop() end
	end,
})
	:Gear(function(panel)
		H.S(panel, "Distance", "vd_dbd_dist", 6, 20, 13, 1, function(value) F.dbdDistance = value end)
		H.S(panel, "Height", "vd_dbd_height", 1, 8, 4.2, 1, function(value) F.dbdHeight = value end)
		H.S(panel, "Run Smooth", "vd_dbd_run", 0.03, 0.35, 0.1, 2, function(value) F.dbdRunSmooth = value end)
		H.S(panel, "Look Smooth", "vd_dbd_look", 0.08, 0.6, 0.28, 2, function(value) F.dbdLookSmooth = value end)
		H.S(panel, "Sensitivity", "vd_dbd_sens", 0.15, 1.2, 0.55, 2, function(value) F.dbdSens = value end)
		H.S(panel, "Pitch Min", "vd_dbd_pmin", -1.2, 0, -0.55, 2, function(value) F.dbdPitchMin = value end)
		H.S(panel, "Pitch Max", "vd_dbd_pmax", 0, 1.2, 0.45, 2, function(value) F.dbdPitchMax = value end)
		H.S(panel, "FOV", "vd_dbd_fov", 50, 90, 70, 0, function(value) F.dbdFov = value end)
	end)

U.streamer = U.Main:Section("Streamer Mode", 2)
H.T(U.streamer, "Streamer Mode", "vd_streamer", false, function(state) H.setStreamer(state) end, "hides names and avatars in the game UI")

U.cross = U.Main:Section("Crosshair", 2)

U.cross:Toggle({
	Text = "Crosshair",
	Flag = "vd_cross",
	Default = false,
	Callback = function(state)
		F.crosshair = state
		H.crosshairBuild()
	end,
})
	:ColorPicker({
		Flag = "vd_cross_color",
		Default = Color3.fromRGB(255, 255, 255),
		Callback = function(color)
			F.crossColor = color
			H.crosshairBuild()
		end,
	})

H.D(U.cross, "Style", "vd_cross_style", { "Plus", "Dot", "Circle" }, "Plus", function(value) F.crossStyle = value H.crosshairBuild() end)
H.S(U.cross, "Size", "vd_cross_size", 2, 30, 8, 0, function(value) F.crossSize = value H.crosshairBuild() end)
H.S(U.cross, "Thickness", "vd_cross_thick", 1, 5, 2, 0, function(value) F.crossThickness = value H.crosshairBuild() end)
H.S(U.cross, "Position X", "vd_cross_x", -100, 100, 0, 0, function(value) F.crossX = value H.crosshairBuild() end)
H.S(U.cross, "Position Y", "vd_cross_y", -100, 100, 0, 0, function(value) F.crossY = value H.crosshairBuild() end)

U.gen = U.Survivor:Section("Generator", 1)

U.gen:Toggle({
	Text = "Auto Skill Check",
	Flag = "vd_skill",
	Default = false,
	Callback = function(state) F.skillCheck = state end,
})
	:Gear(function(panel)
		H.D(panel, "Mode", "vd_skill_mode", { "Legit", "Instant", "Normal", "Random" }, "Legit", function(value) F.skillMode = value end)
	end)

U.gen:Toggle({
	Text = "Gen Boost (Multi-Repair)",
	Flag = "vd_gen_boost",
	Default = false,
	Callback = function(state)
		F.genBoost = state
		H.genButton(state and UserInputService.TouchEnabled)
		if not state then H.stopAutoRepair() end
	end,
})
	:Gear(function(panel)
		H.D(panel, "Mode", "vd_gen_mode", { "Manual Repair", "Auto Repair" }, "Manual Repair", function(value) F.genMode = value end)
	end)

U.tofBox = U.Survivor:Section("Twist of Fate", 1)

U.tofBox:Toggle({
	Text = "Silent Aim Twist of Fate",
	Flag = "vd_tof",
	Default = false,
	Hint = "RMB to aim, LMB to shoot, K / J / L switch target",
	Callback = function(state) F.tof = state end,
})
	:Gear(function(panel)
		H.D(panel, "Target", "vd_tof_target", { "Killer", "Survivors", "Zombie" }, "Killer", function(value) F.tofTarget = value end)
	end)

H.T(U.tofBox, "Predict Aim", "vd_tof_predict", false, function(state) F.tofPredict = state end)
H.T(U.tofBox, "Lock Aim", "vd_tof_lock", false, function(state) F.tofLock = state end)
H.T(U.tofBox, "Wall Check", "vd_tof_wall", false, function(state) F.tofWall = state end)
H.T(U.tofBox, "Laser Effect", "vd_tof_laser", true, function(state) F.tofLaser = state end)
H.T(U.tofBox, "Block Bullets", "vd_tof_block", false, function(state) H.setHookFlag("tofBlock", state) end, "drops incoming Twist of Fate shots")

U.tofBox:Toggle({
	Text = "Silent Aim Flashlight",
	Flag = "vd_flash",
	Default = false,
	Callback = function(state) F.flashSilent = state end,
})
	:Gear(function(panel)
		H.S(panel, "Head Offset", "vd_flash_offset", 0, 15, 1.5, 1, function(value) F.flashOffset = value end)
	end)

U.hookBox = U.Survivor:Section("Anti Hook", 1)

U.hookBox:Toggle({
	Text = "Anti Hook",
	Flag = "vd_anti_hook",
	Default = false,
	Callback = function(state) F.antiHook = state end,
})
	:Gear(function(panel)
		H.S(panel, "Offset", "vd_anti_hook_offset", 50, 1000, 250, 0, function(value) F.antiHookOffset = value end)
		H.S(panel, "Send Hz", "vd_anti_hook_hz", 1, 60, 44, 0, function(value) F.antiHookHz = value end)
	end)

U.pal = U.Survivor:Section("Auto Drop Pallet", 1)

U.pal:Toggle({
	Text = "Auto Drop Pallet",
	Flag = "vd_auto_pallet",
	Default = false,
	Callback = function(state) F.autoPallet = state end,
})
	:Gear(function(panel)
		H.S(panel, "Trigger Distance", "vd_pallet_dist", 5, 30, 10, 0, function(value) F.autoPalletDistance = value end)
		H.T(panel, "Safety", "vd_pallet_safety", true, function(state) F.autoPalletSafety = state end)
	end)

H.B(U.pal, "Drop All Pallets", H.dropAllPallets)

U.ability = U.Survivor:Section("Survivor Ability", 2)
H.T(U.ability, "Instant TP Gate", "vd_tp_gate", false, function(state) H.setTpGate(state) end)
H.T(U.ability, "Auto Crouch (Dodge S1)", "vd_auto_crouch", false, function(state) F.autoCrouch = state end)
H.T(U.ability, "Unlimited Vault", "vd_unl_vault", false, function(state) H.setUnlimitedVault(state) end)
H.T(U.ability, "Anti Slow Vault", "vd_anti_slow_vault", false, function(state)
	F.antiSlowVault = state
	if state then H.patchVault() end
end)
H.T(U.ability, "Flowstate No CD", "vd_flow_nocd", false, function(state) H.setFlowstateNoCd(state) end)
H.T(U.ability, "No Fall Damage", "vd_no_fall", false, function(state) H.setHookFlag("noFall", state) end)
H.T(U.ability, "Bypass Exit Gate", "vd_bypass_gate", false, function(state) H.setBypassGate(state) end)
H.T(U.ability, "Self Heal", "vd_self_heal", false, function(state) F.selfHeal = state end)
H.T(U.ability, "God Mode (Anti Knockdown)", "vd_god", false, function(state) F.godMode = state end)

U.ability:ButtonRow({
	{ Text = "Apply Korless", Callback = function() task.spawn(function() pcall(H.applyKorless) end) end },
	{ Text = "Instant Escape", Callback = function() task.spawn(function() pcall(H.instantEscape) end) end },
})

U.saim = U.Survivor:Section("Survivor Aimbot", 2)

U.saim:Toggle({
	Text = "Aimbot",
	Flag = "vd_surv_aim",
	Default = false,
	Callback = function(state) F.survAim = state end,
})
	:Gear(function(panel)
		H.T(panel, "Hold RMB", "vd_surv_aim_hold", false, function(state) F.survAimHold = state end)
		H.T(panel, "Show FOV Circle", "vd_surv_aim_fov", true, function(state) F.survAimFov = state end)
		H.S(panel, "FOV Radius", "vd_surv_aim_radius", 30, 500, 150, 0, function(value) F.survAimRadius = value end)
		H.S(panel, "Max Distance", "vd_surv_aim_dist", 50, 1000, 300, 0, function(value) F.survAimDist = value end)
		H.S(panel, "Smoothness", "vd_surv_aim_smooth", 0.1, 1, 0.5, 2, function(value) F.survAimSmooth = value end)
		H.S(panel, "Predict", "vd_surv_aim_predict", 0, 0.1, 0.01, 3, function(value) F.survAimPredict = value end)
		H.D(panel, "Target Part", "vd_surv_aim_part", { "Root", "Torso", "Head" }, "Root", function(value) F.survAimPart = value end)
	end)

U.p1 = U.Survivor:Section("Auto Parry V1", 2)

U.p1:Toggle({
	Text = "Auto Parry V1",
	Flag = "vd_parry1",
	Default = false,
	Callback = function(state) F.parryV1 = state end,
})
	:Gear(function(panel)
		H.T(panel, "Safety", "vd_parry1_safety", false, function(state) F.parryV1Safety = state end)
		H.T(panel, "Aggressive Mode", "vd_parry1_aggr", false, function(state) F.parryV1Aggressive = state end)
		H.T(panel, "Show Range Circle", "vd_parry1_circle", true, function(state) F.parryV1Circle = state end)
		H.S(panel, "Parry Radius", "vd_parry1_radius", 5, 25, 15, 0, function(value) F.parryV1Radius = value end)
		H.S(panel, "Face Sensitivity", "vd_parry1_face", -10, 10, 7, 0, function(value) F.parryV1Face = value / 10 end)
	end)

H.T(U.p1, "Parry Button", "vd_parry_button", false, function(state)
	if S.parryButton then pcall(function() S.parryButton:Destroy() end) S.parryButton = nil end
	if state then
		S.parryButton = H.floatingButton("PARRY", UDim2.new(0.86, 0, 0.65, 0), function() task.spawn(H.parryV1Fire) end)
	end
end)

U.p2 = U.Survivor:Section("Auto Parry V2", 2)

U.p2:Toggle({
	Text = "Auto Parry V2",
	Flag = "vd_parry2",
	Default = false,
	Callback = function(state) F.parryV2 = state end,
})
	:Gear(function(panel)
		H.T(panel, "Safety", "vd_parry2_safety", false, function(state) F.parryV2Safety = state end)
		H.D(panel, "Mode", "vd_parry2_mode", { "Legit", "Strict", "Aggressive" }, "Legit", function(value) F.parryV2Mode = value end)
		H.D(panel, "Trigger", "vd_parry2_trigger", { "Remote", "Button" }, "Remote", function(value) F.parryV2Trigger = value end)
		H.S(panel, "Killer Face", "vd_parry2_face", -1, 1, 0.6, 2, function(value) F.parryV2Face = value end)
		H.T(panel, "Show Range Circle", "vd_parry2_circle", true, function(state) F.parryV2Circle = state end)
		H.S(panel, "Parry Radius", "vd_parry2_range", 2, 20, 12, 0, function(value) F.parryV2Range = value end)
	end)

U.kaim = U.Killer:Section("Killer Aimbot", 1)

U.kaim:Toggle({
	Text = "Aimbot (Melee)",
	Flag = "vd_killer_aim",
	Default = false,
	Hint = "locks while you hold attack",
	Callback = function(state) F.killerAim = state end,
})
	:Gear(function(panel)
		H.S(panel, "Max Distance", "vd_killer_aim_dist", 5, 30, 12, 0, function(value) F.killerAimDist = value end)
		H.S(panel, "Smoothness", "vd_killer_aim_smooth", 0.1, 1, 0.5, 2, function(value) F.killerAimSmooth = value end)
	end)

U.veilBox = U.Killer:Section("Silent Veil", 1)

U.veilBox:Toggle({
	Text = "Silent Veil",
	Flag = "vd_veil",
	Default = false,
	Callback = function(state) H.setVeil(state) end,
})
	:Gear(function(panel)
		H.S(panel, "Spear Speed", "vd_spear_speed", 50, 200, 165, 1, function(value) F.spearSpeed = value end)
		H.S(panel, "Spear Gravity", "vd_spear_gravity", 10, 200, 103, 1, function(value) F.spearGravity = value end)
		H.S(panel, "Aura Speed", "vd_aura_speed", 50, 200, 165, 1, function(value) F.auraSpeed = value end)
		H.S(panel, "Aura Gravity", "vd_aura_gravity", 10, 200, 96.5, 1, function(value) F.auraGravity = value end)
	end)

H.T(U.veilBox, "Auto Predict", "vd_veil_predict", false, function(state) F.veilPredict = state end)
H.T(U.veilBox, "Show FOV", "vd_veil_fov_show", true, function(state) F.veilShowFov = state end)
H.S(U.veilBox, "Lead", "vd_veil_lead", 0.5, 5, 1.4, 1, function(value) F.veilLead = value end)
H.S(U.veilBox, "FOV", "vd_veil_fov", 50, 500, 150, 0, function(value) F.veilFov = value end)
H.S(U.veilBox, "Max Distance", "vd_veil_dist", 50, 1000, 500, 0, function(value) F.veilMaxDist = value end)

U.flask = U.Killer:Section("Flask (Cure)", 1)
H.T(U.flask, "Silent Aim Flask", "vd_flask_silent", false, function(state) H.setFlaskSilent(state) end)
H.T(U.flask, "Flask Laser", "vd_flask_laser", false, function(state) F.flaskLaser = state end)

U.kab = U.Killer:Section("Killer Ability", 2)
H.T(U.kab, "Anti Blind (Flashlight)", "vd_anti_blind", false, function(state) H.setHookFlag("antiBlind", state) end)
H.T(U.kab, "Anti Parry", "vd_anti_parry", false, function(state) F.antiParry = state end)
H.T(U.kab, "Infinite Lunge", "vd_inf_lunge", false, function(state)
	F.infiniteLunge = state
	H.applyLunge()
end)
H.T(U.kab, "Auto Stalk", "vd_auto_stalk", false, function(state) F.autoStalk = state end)
H.T(U.kab, "No Slowdown", "vd_no_slow", false, function(state) F.noSlowdown = state end)
H.T(U.kab, "Hidden Skill No CD", "vd_hidden_nocd", false, function(state) H.setHiddenNoCd(state) end)
H.T(U.kab, "Infinite Corrupt (Abyssal)", "vd_inf_corrupt", false, function(state) F.infiniteCorrupt = state end, "hold Q")

U.loop = U.Killer:Section("Anti Looping", 2)
H.T(U.loop, "Block Vaults & Pallets", "vd_anti_loop", false, function(state) H.setAntiLoop(state) end)

U.espBox = U.Visual:Section("ESP", 1)

H.T(U.espBox, "Enable ESP", "vd_esp", false, function(state) F.esp = state end)
H.S(U.espBox, "Max Distance", "vd_esp_max", 100, 5000, 1000, 0, function(value) F.espMax = value end)

U.espBox:Toggle({
	Text = "Survivors",
	Flag = "vd_esp_player",
	Default = false,
	Callback = function(state) F.espPlayer = state end,
})
	:ColorPicker({ Flag = "vd_esp_player_color", Default = C.player, Callback = function(color) C.player = color end })

U.espBox:Toggle({
	Text = "Killer",
	Flag = "vd_esp_killer",
	Default = false,
	Callback = function(state) F.espKiller = state end,
})
	:ColorPicker({ Flag = "vd_esp_killer_color", Default = C.killer, Callback = function(color) C.killer = color end })

H.T(U.espBox, "Name", "vd_esp_name", true, function(state) F.espName = state end)
H.T(U.espBox, "Distance", "vd_esp_distance", true, function(state) F.espDistance = state end)
H.T(U.espBox, "Status", "vd_esp_status", false, function(state) F.espStatus = state end)
H.T(U.espBox, "Item Icon", "vd_esp_item", false, function(state) F.espItem = state end)
H.T(U.espBox, "Hook Count", "vd_esp_hooks", false, function(state) F.espHookCount = state end)
H.T(U.espBox, "Killer Warning", "vd_esp_warn", false, function(state) F.espKillerWarn = state end)
H.T(U.espBox, "Outline Only", "vd_esp_outline", false, function(state) F.espOutline = state end)

U.world = U.Visual:Section("World", 1)

U.world:Toggle({
	Text = "Full Bright",
	Flag = "vd_fullbright",
	Default = false,
	Callback = function(state)
		F.fullBright = state
		if not state then H.restoreWorld({ "Brightness", "ClockTime", "Ambient", "OutdoorAmbient" }) if not F.noFog then H.restoreWorld({ "FogEnd" }) end end
	end,
})
	:Gear(function(panel)
		H.S(panel, "Time Of Day", "vd_time", 0, 24, 14, 1, function(value) F.timeOfDay = value end)
	end)

H.T(U.world, "No Fog", "vd_nofog", false, function(state)
	F.noFog = state
	if not state then
		H.restoreWorld({ "FogStart" })
		if not F.fullBright then H.restoreWorld({ "FogEnd" }) end
		for _, item in ipairs(Lighting:GetChildren()) do
			if item:IsA("Atmosphere") then
				H.restoreProp(item, "Density")
				H.restoreProp(item, "Haze")
				H.restoreProp(item, "Glare")
			end
		end
	end
end)
H.T(U.world, "No Shadow", "vd_noshadow", false, function(state)
	F.noShadow = state
	if not state then H.restoreWorld({ "GlobalShadows" }) end
end)
H.T(U.world, "Low GFX", "vd_lowgfx", false, function(state) H.setLowGfx(state) end)

U.mapEsp = U.Visual:Section("Map ESP", 2)

U.mapEsp:Toggle({
	Text = "Generators",
	Flag = "vd_esp_gen",
	Default = false,
	Callback = function(state) F.espGen = state H.mapEspTick() end,
})
	:ColorPicker({ Flag = "vd_esp_gen_color", Default = C.generator, Callback = function(color) C.generator = color end })
	:ColorPicker({ Flag = "vd_esp_gen_done_color", Default = C.generatorDone, Callback = function(color) C.generatorDone = color end })

H.T(U.mapEsp, "Generator Progress", "vd_esp_gen_name", true, function(state) F.espGenName = state end)

U.mapEsp:Toggle({
	Text = "Pallets",
	Flag = "vd_esp_pallet",
	Default = false,
	Callback = function(state) F.espPallet = state H.mapEspTick() end,
})
	:ColorPicker({ Flag = "vd_esp_pallet_color", Default = C.pallet, Callback = function(color) C.pallet = color end })

U.mapEsp:Toggle({
	Text = "Windows",
	Flag = "vd_esp_window",
	Default = false,
	Callback = function(state) F.espWindow = state H.mapEspTick() end,
})
	:ColorPicker({ Flag = "vd_esp_window_color", Default = C.window, Callback = function(color) C.window = color end })

U.mapEsp:Toggle({
	Text = "Hooks",
	Flag = "vd_esp_hook",
	Default = false,
	Callback = function(state) F.espHook = state H.mapEspTick() end,
})
	:ColorPicker({ Flag = "vd_esp_hook_color", Default = C.hook, Callback = function(color) C.hook = color end })

U.mapEsp:Toggle({
	Text = "Gates",
	Flag = "vd_esp_gate",
	Default = false,
	Callback = function(state) F.espGate = state H.mapEspTick() end,
})
	:ColorPicker({ Flag = "vd_esp_gate_color", Default = C.gate, Callback = function(color) C.gate = color end })

U.mapEsp:Toggle({
	Text = "SCP",
	Flag = "vd_esp_scp",
	Default = false,
	Callback = function(state) F.espScp = state H.mapEspTick() end,
})
	:ColorPicker({ Flag = "vd_esp_scp_color", Default = C.scp, Callback = function(color) C.scp = color end })

H.B(U.mapEsp, "Refresh Map", H.refreshMapEsp)

U.info = U.Visual:Section("Information", 2)
H.T(U.info, "Next Killer", "vd_info_next", false, function(state) F.nextKiller = state end)
H.T(U.info, "Map Name", "vd_info_map", false, function(state) F.mapName = state end)
H.T(U.info, "Killer Perks", "vd_info_perks", false, function(state) F.killerPerks = state end)
H.T(U.info, "Killer Stun Indicator", "vd_info_stun", false, function(state) F.stunIndicator = state end)
H.T(U.info, "Spectators", "vd_info_spec", false, function(state) F.spectators = state end)

U.tpMap = U.Teleport:Section("Teleport Map", 1)

H.B(U.tpMap, "Refresh Map Cache", function()
	H.scanMap(true)
	H.notify("Teleport", string.format("%d gens, %d hooks, %d gates, %d pallets, %d windows",
		#MAP.Generators, #MAP.Hooks, #MAP.Gates, #MAP.Pallets, #MAP.Windows), 4)
end)

U.tpMap:ButtonRow({
	{ Text = "Generator", Callback = function() task.spawn(H.cycleTeleport, "Generators") end },
	{ Text = "Hook", Callback = function() task.spawn(H.cycleTeleport, "Hooks") end },
})
U.tpMap:ButtonRow({
	{ Text = "Gate", Callback = function() task.spawn(H.cycleTeleport, "Gates") end },
	{ Text = "Pallet", Callback = function() task.spawn(H.cycleTeleport, "Pallets") end },
})
H.B(U.tpMap, "Window", function() H.cycleTeleport("Windows") end)

U.tpPlayer = U.Teleport:Section("Teleport Player", 2)
S.tpTarget = nil

U.playerList = U.tpPlayer:Dropdown({
	Text = "Player",
	Flag = "vd_tp_player",
	Options = H.playerNames(),
	Empty = "no players",
	Callback = function(value)
		if type(value) == "table" then value = value[1] end
		S.tpTarget = value
	end,
})

function H.refreshPlayerList()
	pcall(function() U.playerList:SetOptions(H.playerNames()) end)
end

H.track(Players.PlayerAdded:Connect(H.refreshPlayerList))
H.track(Players.PlayerRemoving:Connect(function() task.defer(H.refreshPlayerList) end))

U.tpPlayer:ButtonRow({
	{ Text = "Refresh", Callback = H.refreshPlayerList },
	{ Text = "Teleport", Callback = function() H.teleportPlayer(S.tpTarget) end },
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
SaveManager:SetFolder("Facility/6739698191")

InterfaceManager:BuildInterfaceSection(U.Settings, 1)
SaveManager:BuildConfigSection(U.Settings, 2)
ThemeManager:Mount(Window)

Window:SetTab(U.Main)

Library:Notify("Facility", "Violence District loaded.", 4)

SaveManager:LoadAutoloadConfig()
ThemeManager:Load()
