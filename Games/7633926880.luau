--!nocheck
--!nolint UnknownGlobal

local FH      = shared.Facility
local Library = FH.Library
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

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local VirtualUser = game:GetService("VirtualUser")
local Lighting = game:GetService("Lighting")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")

local LocalPlayer = Players.LocalPlayer

local moduleErrors = {}

local H = {}
local U = {}
local S = {
	connections = {}, threads = {}, drawings = {}, instances = {}, hooks = {}, hookOrder = {},
	lib = {}, weapons = {}, motion = setmetatable({}, { __mode = "k" }),
	press = { down = false, at = 0, tapAt = 0 }, lastShot = 0,
	trig = { model = nil, since = 0, pass = false },
	aimHeld = false, aimTarget = nil, aimPart = nil, rageTarget = nil, ragePart = nil, silentTarget = nil, viewSaved = nil,
	espOn = false, espKeys = {}, ghosts = {}, marks = {},
	skins = { map = {}, catalog = nil, rank = {}, applied = setmetatable({}, { __mode = "k" }), originals = setmetatable({}, { __mode = "k" }) },
	bought = {}, replaying = false, redeeming = false, rebuyPending = false, phase = nil,
	hop = { at = 0, crouched = false, space = false },
	fovBase = 0, fovSaved = nil, lightSaved = nil,
}

local F = {
	teamCheck = true, bots = true,

	aim = false, aimAlways = false, aimSmooth = 4, aimBone = "Head", aimPriority = "Crosshair", aimFov = 150,
	aimShowFov = false, aimFovColor = Color3.fromRGB(255, 255, 255), aimVisible = true, aimSticky = true, aimRange = 1500,

	silent = false, silentHit = 100, silentHead = 100, silentPriority = "Crosshair", silentFov = 220, silentShowFov = false,
	silentFovColor = Color3.fromRGB(120, 170, 255), silentVisible = true, silentRange = 2000, silentPredict = false,

	trigger = false, triggerMode = "Crosshair", triggerFov = 0, triggerTeam = true, triggerDelay = 0,
	triggerReaction = 0, triggerChance = 100,

	rage = false, rageVisible = true, rageRange = 2000,

	noRecoil = false, noSpread = false,

	tightBox = true, memory = 5, ghostColor = Color3.fromRGB(255, 196, 64),
	soundEsp = false, soundLife = 3, soundColor = Color3.fromRGB(255, 196, 64),

	radar = false, radarRange = 250, radarSize = 180, radarEnemy = Color3.fromRGB(255, 70, 70), radarFriend = Color3.fromRGB(70, 200, 120),

	fullbright = false, noFlash = false, noSmoke = false, camFov = false, camFovValue = 100,

	skinChanger = false, autoRebuy = false, antiAfk = false, infJump = false, bhop = false, bhopCrouch = true,
}

H.CODES = {
	"1MGROUPMEMBERS", "MYFAULTYALL", "RIANOMINATED2026", "LORE", "DUST_II", "MICHAELSRETURN", "FREEDOM",
	"HAPPYBDAYYUUTO", "GAMEBROKE318", "OHNEPIXEL", "NEBULA", "REACTORDELAY", "BUTTERFLYCASE", "TRADEUPS",
}

H.BONES = {
	Head = { "Head" },
	Torso = { "UpperTorso", "Torso", "HumanoidRootPart" },
}

H.PASS_FOLDERS = { "Characters", "Debris", "ThirdPersonWeaponStash" }
H.BUY_PHASES = { ["Buy Period"] = true, ["Warmup"] = true }
H.SAVE_FOLDER = "Facility/7633926880"
H.SKIN_FILE = H.SAVE_FOLDER .. "/skins.json"
H.WEARS = { "Factory New", "Minimal Wear", "Field-Tested", "Well-Worn", "Battle-Scarred" }
H.KINDS = { Melee = "Knives", Glove = "Gloves", Grenade = "Grenades", C4 = "Gear", ["Zeus x27"] = "Gear" }
H.CATEGORY_ORDER = { "Pistol", "SMG", "Rifle", "Sniper", "Heavy", "Shotgun", "Machine Gun", "Knives", "Gloves", "Grenades", "Gear" }
H.RANKS = { Forbidden = 9, Special = 8, Red = 7, Pink = 6, Purple = 5, Blue = 4, LightBlue = 3, Gray = 2, White = 1 }
H.ARM_PARTS = { ["Left Arm"] = true, ["Right Arm"] = true }
H.GLOVE_KEY = "@Glove"

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

function H.decode(raw)
	if type(raw) ~= "string" then return nil end
	local ok, value = pcall(HttpService.JSONDecode, HttpService, raw)
	return ok and value or nil
end

function H.roll(percent)
	return percent >= 100 or math.random() * 100 < percent
end

function H.menuOpen()
	local ok, open = pcall(function() return Library:MenuOpen() end)
	return ok and open == true
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
	gui.DisplayOrder = 40
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

function H.require(module)
	if not (module and module:IsA("ModuleScript")) then return nil end
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
	if okAgain then return again end
	return nil
end

function H.locate(parent, name, home)
	local found = parent and parent:FindFirstChild(name)
	if found then return found end
	for _, item in ipairs(ReplicatedStorage:GetDescendants()) do
		if item.Name == name and item.Parent and item.Parent.Name == home then return item end
	end
	return nil
end

function H.loadGame()
	local database = ReplicatedStorage:FindFirstChild("Database")
	local security = database and database:FindFirstChild("Security")
	local custom = database and database:FindFirstChild("Custom")
	local controllers = ReplicatedStorage:FindFirstChild("Controllers")
	local components = ReplicatedStorage:FindFirstChild("Components")
	local vfx = components and components:FindFirstChild("VFXLibary", true)

	local wanted = {
		{ "Net", security, "Remotes", "Security" },
		{ "Character", controllers, "CharacterController", "Controllers" },
		{ "Camera", controllers, "CameraController", "Controllers" },
		{ "Rarities", custom, "Rarities", "GameStats" },
		{ "Smoke", vfx, "CreateVoxelSmoke", "VFXLibary" },
		{ "Flash", vfx, "FlashEffect", "VFXLibary" },
	}

	for _, entry in ipairs(wanted) do
		local module = H.require(H.locate(entry[2], entry[3], entry[4]))
		if module ~= nil then
			S.lib[entry[1]] = module
		else
			table.insert(moduleErrors, "game module " .. entry[3] .. " unavailable")
		end
	end

	local folder = H.locate(custom, "Weapons", "Custom")
	for _, module in ipairs(folder and folder:GetChildren() or {}) do
		if module:IsA("ModuleScript") then
			local data = H.require(module)
			if type(data) == "table" and data.FireRate then S.weapons[module.Name] = data end
		end
	end
end

H.loadGame()

function H.packet(group, name)
	local net = S.lib.Net
	local holder = type(net) == "table" and net[group]
	local packet = type(holder) == "table" and holder[name]
	return type(packet) == "table" and packet or nil
end

function H.hook(key, fn, replacement)
	if S.hooks[key] or type(fn) ~= "function" or type(hookfunction) ~= "function" then return nil end
	local ok, original = pcall(hookfunction, fn, replacement)
	if not ok or type(original) ~= "function" then return nil end
	S.hooks[key] = { fn = fn, original = original }
	table.insert(S.hookOrder, key)
	return original
end

function H.unhookAll()
	for index = #S.hookOrder, 1, -1 do
		local entry = S.hooks[S.hookOrder[index]]
		if entry then
			local restored = type(restorefunction) == "function" and pcall(restorefunction, entry.fn)
			if not restored then pcall(hookfunction, entry.fn, entry.original) end
		end
	end
	table.clear(S.hooks)
	table.clear(S.hookOrder)
end

function H.characters()
	return workspace:FindFirstChild("Characters")
end

function H.myChar()
	local folder = H.characters()
	return (folder and folder:FindFirstChild(LocalPlayer.Name)) or LocalPlayer.Character
end

function H.isAlive()
	local character = H.myChar()
	return character ~= nil and character.Parent ~= nil and tostring(LocalPlayer:GetAttribute("Dead")) ~= "true"
end

function H.humanoid()
	local character = H.myChar()
	return character and character:FindFirstChildOfClass("Humanoid")
end

function H.body()
	local controller = S.lib.Character
	if type(controller) ~= "table" or type(controller.getCurrentCharacter) ~= "function" then return nil end
	local ok, body = pcall(controller.getCurrentCharacter)
	return ok and body or nil
end

function H.equipped(player)
	return H.decode((player or LocalPlayer):GetAttribute("CurrentEquipped"))
end

function H.owner(model)
	local player = model and Players:FindFirstChild(model.Name)
	return player and player:IsA("Player") and player or nil
end

function H.ffa()
	return string.find(tostring(workspace:GetAttribute("Gamemode")), "Deathmatch", 1, true) ~= nil
end

function H.teamOf(model)
	local owner = H.owner(model)
	local team = owner and owner:GetAttribute("Team")
	if team then return team end
	local look = model and model:GetAttribute("CharacterName")
	if not look then return nil end
	if look == workspace:GetAttribute("CTCharacter") then return "Counter-Terrorists" end
	if look == workspace:GetAttribute("TCharacter") then return "Terrorists" end
	return nil
end

function H.myTeam()
	return LocalPlayer:GetAttribute("Team") or H.teamOf(H.myChar())
end

function H.dead(model, owner)
	if model and (tostring(model:GetAttribute("Dead")) == "true" or (tonumber(model:GetAttribute("Health")) or 1) <= 0) then return true end
	if owner and (tostring(owner:GetAttribute("Dead")) == "true" or (tonumber(owner:GetAttribute("Health")) or 1) <= 0) then return true end
	return false
end

function H.health(model)
	local owner = H.owner(model)
	local health = tonumber(owner and owner:GetAttribute("Health")) or tonumber(model:GetAttribute("Health")) or 100
	return health, tonumber(model:GetAttribute("MaxHealth")) or 100
end

function H.candidates()
	local list = {}
	local folder = H.characters()
	if not folder then return list end
	for _, model in ipairs(folder:GetChildren()) do
		if model:IsA("Model") and model.Name ~= LocalPlayer.Name then
			local owner = H.owner(model)
			if owner or (F.bots and model:GetAttribute("Health") ~= nil) then table.insert(list, model) end
		end
	end
	return list
end

function H.hostile(model)
	if H.ffa() then return true end
	local mine = H.myTeam()
	if mine == nil then return true end
	return H.teamOf(model) ~= mine
end

function H.isEnemy(model, teamCheck)
	if not model or not model.Parent then return false end
	if H.dead(model, H.owner(model)) then return false end
	if teamCheck == false then return true end
	return H.hostile(model)
end

function H.part(model, bone)
	for _, name in ipairs(H.BONES[bone] or H.BONES.Head) do
		local part = model:FindFirstChild(name)
		if part and part:IsA("BasePart") then return part end
	end
	return model:FindFirstChild("HumanoidRootPart")
end

S.wallParams = RaycastParams.new()
S.wallParams.FilterType = Enum.RaycastFilterType.Exclude
S.lookParams = RaycastParams.new()
S.lookParams.FilterType = Enum.RaycastFilterType.Exclude

function H.clear(origin, model, point)
	local skip = { workspace.CurrentCamera, model }
	for _, name in ipairs(H.PASS_FOLDERS) do
		local folder = workspace:FindFirstChild(name)
		if folder then table.insert(skip, folder) end
	end
	S.wallParams.FilterDescendantsInstances = skip
	return workspace:Raycast(origin, point - origin, S.wallParams) == nil
end

function H.pick(cfg)
	local camera = workspace.CurrentCamera
	if not camera then return nil end
	local origin = camera.CFrame.Position
	local center = camera.ViewportSize / 2
	local best, bestPart, bestScore = nil, nil, nil

	for _, model in ipairs(H.candidates()) do
		if H.isEnemy(model, F.teamCheck) then
			local part = H.part(model, cfg.bone)
			if part then
				local distance = (part.Position - origin).Magnitude
				if distance <= cfg.range then
					local screen, onScreen = camera:WorldToViewportPoint(part.Position)
					local offset = (Vector2.new(screen.X, screen.Y) - center).Magnitude
					local inside = not cfg.fov or (onScreen and screen.Z > 0 and offset <= cfg.fov)
					if inside and (not cfg.visible or H.clear(origin, model, part.Position)) then
						local score = distance
						if cfg.priority == "Crosshair" then
							score = (onScreen and screen.Z > 0) and offset or 1e6 + distance
						elseif cfg.priority == "Health" then
							score = H.health(model) * 1e4 + distance
						end
						if not bestScore or score < bestScore then best, bestPart, bestScore = model, part, score end
					end
				end
			end
		end
	end

	return best, bestPart
end

function H.stillValid(model, part, cfg)
	if not (model and part and part.Parent and H.isEnemy(model, F.teamCheck)) then return false end
	local camera = workspace.CurrentCamera
	local origin = camera.CFrame.Position
	if (part.Position - origin).Magnitude > cfg.range then return false end
	if cfg.visible and not H.clear(origin, model, part.Position) then return false end
	if not cfg.fov then return true end
	local screen, onScreen = camera:WorldToViewportPoint(part.Position)
	return onScreen and screen.Z > 0 and (Vector2.new(screen.X, screen.Y) - camera.ViewportSize / 2).Magnitude <= cfg.fov * 1.5
end

function H.trackMotion()
	local now = os.clock()
	for _, model in ipairs(H.candidates()) do
		local head = model:FindFirstChild("Head")
		if head then
			local last = S.motion[head]
			if last and now > last.time then
				local step = (head.Position - last.pos) / (now - last.time)
				last.vel = last.vel:Lerp(step, 0.5)
				last.pos, last.time = head.Position, now
			elseif not last then
				S.motion[head] = { pos = head.Position, time = now, vel = Vector3.zero }
			end
		end
	end
end

function H.lead(part)
	if not F.silentPredict then return part.Position end
	local head = part.Parent and part.Parent:FindFirstChild("Head")
	local sample = S.motion[part] or (head and S.motion[head])
	local velocity = sample and sample.vel or Vector3.zero
	if velocity.Magnitude > 60 then return part.Position end
	local ok, ping = pcall(LocalPlayer.GetNetworkPing, LocalPlayer)
	return part.Position + velocity * ((ok and ping or 0.05) + 0.02)
end

function H.aimCfg()
	return { bone = F.aimBone, fov = F.aimFov, visible = F.aimVisible, range = F.aimRange, priority = F.aimPriority }
end

function H.silentCfg(bone)
	if F.rage then return { bone = bone, visible = F.rageVisible, range = F.rageRange, priority = "Distance" } end
	return { bone = bone, fov = F.silentFov, visible = F.silentVisible, range = F.silentRange, priority = F.silentPriority }
end

function H.aimActive()
	return F.aim and (F.aimAlways or S.aimHeld)
end

function H.aimStep()
	if not H.aimActive() then
		S.aimTarget, S.aimPart = nil, nil
		return
	end
	local cfg = H.aimCfg()
	if F.aimSticky and H.stillValid(S.aimTarget, S.aimPart, cfg) then return end
	S.aimTarget, S.aimPart = H.pick(cfg)
end

function H.rageStep()
	if not F.rage then
		S.rageTarget, S.ragePart = nil, nil
		return false
	end
	S.rageTarget, S.ragePart = H.pick(H.silentCfg("Head"))
	return S.rageTarget ~= nil
end

function H.lockView(dt)
	if not alive() then return end
	local part, smooth = nil, 1
	if F.rage and S.ragePart and S.ragePart.Parent then
		part = S.ragePart
	elseif H.aimActive() and S.aimPart and S.aimPart.Parent then
		part, smooth = S.aimPart, math.max(F.aimSmooth, 1)
	end
	if not part then return end

	local camera = workspace.CurrentCamera
	local origin = camera.CFrame.Position
	local want = (part.Position - origin).Unit
	local look = want
	if smooth > 1 then
		local alpha = 1 - (1 - 1 / smooth) ^ ((dt or 1 / 60) * 60)
		look = camera.CFrame.LookVector:Lerp(want, alpha).Unit
	end
	camera.CFrame = CFrame.lookAt(origin, origin + look)
end

function H.silentPart()
	S.silentTarget = nil
	if not (F.silent or F.rage) or not H.isAlive() then return nil end
	if not F.rage and not H.roll(F.silentHit) then return nil end
	local bone = (F.rage or H.roll(F.silentHead)) and "Head" or "Torso"
	local model, part = H.pick(H.silentCfg(bone))
	S.silentTarget = model
	return part
end

function H.flick()
	if not alive() then return end
	local ok, part = pcall(H.silentPart)
	local camera = workspace.CurrentCamera
	if not (ok and part and camera) then return end
	S.viewSaved = S.viewSaved or camera.CFrame
	camera.CFrame = CFrame.lookAt(camera.CFrame.Position, H.lead(part))
end

function H.restoreView()
	if not S.viewSaved then return end
	local camera = workspace.CurrentCamera
	if camera then camera.CFrame = S.viewSaved end
	S.viewSaved = nil
end

function H.scanGc(test)
	if type(getgc) ~= "function" then return nil end
	local ok, list = pcall(getgc, true)
	if not ok or type(list) ~= "table" then return nil end
	for _, entry in ipairs(list) do
		if type(entry) == "table" and test(entry) then return entry end
	end
	return nil
end

H.SPREAD_METHODS = { "getTrueSpread", "getSpreadForConfig", "getMovementSpreadForConfig", "getBaseSpreadForConfig", "getBaseSpread" }

function H.installGunHooks()
	if S.gunHooked then return true end
	if type(hookfunction) ~= "function" then return false end
	if os.clock() - (S.gunScanAt or 0) < 3 then return false end
	S.gunScanAt = os.clock()

	local gun = H.scanGc(function(entry)
		return rawget(entry, "getSpread") ~= nil and rawget(entry, "shoot") ~= nil and rawget(entry, "setupRecoil") ~= nil
	end)
	local bullet = H.scanGc(function(entry)
		return rawget(entry, "getTrueSpread") ~= nil and rawget(entry, "getSpreadForConfig") ~= nil
	end)
	if not bullet then return false end

	if gun and type(gun.shoot) == "function" then
		local shoot
		shoot = H.hook("shoot", gun.shoot, function(...)
			S.lastShot = os.clock()
			return shoot(...)
		end)
	end

	if type(bullet.create) == "function" then
		local create
		create = H.hook("bullet", bullet.create, function(...)
			if alive() and (F.silent or F.rage) then pcall(H.flick) end
			return create(...)
		end)
	end

	for _, method in ipairs(H.SPREAD_METHODS) do
		if type(bullet[method]) == "function" then
			local original
			original = H.hook("spread:" .. method, bullet[method], function(...)
				local value = original(...)
				if alive() and type(value) == "number" and (F.noSpread or S.viewSaved) then return 0 end
				return value
			end)
		end
	end

	local packet = H.packet("Inventory", "ShootWeapon")
	if packet and type(packet.Send) == "function" then
		local send
		send = H.hook("send", packet.Send, function(...)
			S.lastShot = os.clock()
			if alive() then H.restoreView() end
			return send(...)
		end)
	end

	S.gunHooked = true
	return true
end

function H.installRecoilHooks()
	if S.recoilHooked then return true end
	local camera = S.lib.Camera
	if type(camera) ~= "table" or type(hookfunction) ~= "function" then return false end

	local kick, recoil, rotation
	kick = H.hook("kick", camera.weaponKick, function(...)
		if alive() and F.noRecoil then return end
		return kick(...)
	end)
	recoil = H.hook("recoil", camera.setWeaponRecoil, function(...)
		if alive() and F.noRecoil then return end
		return recoil(...)
	end)
	rotation = H.hook("kickRotation", camera.getWeaponKickRotation, function(...)
		if alive() and F.noRecoil then return Vector3.zero end
		return rotation(...)
	end)

	S.recoilHooked = kick ~= nil or recoil ~= nil or rotation ~= nil
	return S.recoilHooked
end

function H.ensureGun(label)
	if H.installGunHooks() then return true end
	if label then H.notify(label, "Weapon classes not found yet, equip a gun once and toggle again.", 5) end
	return false
end

function H.press(down)
	if down and H.menuOpen() then return end
	S.press.down = down
	if down then S.press.at = os.clock() end
	local camera = workspace.CurrentCamera
	local center = camera and camera.ViewportSize / 2 or Vector2.zero
	pcall(function() VirtualInputManager:SendMouseButtonEvent(center.X, center.Y, 0, down, game, 0) end)
end

function H.release()
	if S.press.down then H.press(false) end
end

function H.hold()
	if not S.press.down then
		H.press(true)
		return
	end
	local now = os.clock()
	if now - S.press.at > 0.12 and now - S.lastShot > 0.12 then H.press(false) end
end

function H.tap(gap)
	local now = os.clock()
	if S.press.down then
		if now - S.press.at > 0.03 then H.press(false) end
		return
	end
	if now - S.press.tapAt >= gap then
		S.press.tapAt = now
		H.press(true)
	end
end

function H.modelOf(instance)
	local folder = H.characters()
	local node = instance
	while node and node.Parent ~= folder do node = node.Parent end
	return node
end

function H.triggerTarget()
	local camera = workspace.CurrentCamera
	if not camera then return nil end

	if F.triggerMode == "Target" then
		local model, part = S.aimTarget, S.aimPart
		if model and part and part.Parent and H.isEnemy(model, F.triggerTeam) and H.clear(camera.CFrame.Position, model, part.Position) then
			return model
		end
		return nil
	end

	if F.triggerMode == "Fov" then
		local center = camera.ViewportSize / 2
		local origin = camera.CFrame.Position
		local best, bestDistance = nil, F.triggerFov > 0 and F.triggerFov or 12
		for _, model in ipairs(H.candidates()) do
			if H.isEnemy(model, F.triggerTeam) then
				local head = H.part(model, "Head")
				if head then
					local point, onScreen = camera:WorldToViewportPoint(head.Position)
					local distance = (Vector2.new(point.X, point.Y) - center).Magnitude
					if onScreen and point.Z > 0 and distance <= bestDistance and H.clear(origin, model, head.Position) then
						best, bestDistance = model, distance
					end
				end
			end
		end
		return best
	end

	S.lookParams.FilterDescendantsInstances = { H.myChar(), camera }
	local hit = workspace:Raycast(camera.CFrame.Position, camera.CFrame.LookVector * 2000, S.lookParams)
	if not hit then return nil end
	local model = H.modelOf(hit.Instance)
	if model and model:IsA("Model") and model.Name ~= LocalPlayer.Name and H.isEnemy(model, F.triggerTeam) then
		if H.owner(model) or (F.bots and model:GetAttribute("Health") ~= nil) then return model end
	end
	return nil
end

function H.triggerWanted()
	if not F.trigger then return false end
	local model = H.triggerTarget()
	local now = os.clock()
	if model ~= S.trig.model then
		S.trig.model = model
		S.trig.since = now
		S.trig.pass = model ~= nil and H.roll(F.triggerChance)
	end
	if not model or not S.trig.pass then return false end
	return now - S.trig.since >= F.triggerReaction / 1000
end

function H.combatRest()
	S.aimTarget, S.aimPart, S.rageTarget, S.ragePart, S.silentTarget = nil, nil, nil, nil, nil
	S.trig.model = nil
	H.release()
end

function H.combatStep()
	if not H.isAlive() then
		H.combatRest()
		return
	end
	if (F.silent or F.rage) and F.silentPredict then H.trackMotion() end
	H.aimStep()

	if H.rageStep() then
		H.hold()
		return
	end

	if not H.triggerWanted() then
		H.release()
		return
	end

	if F.triggerDelay <= 0 then H.hold() else H.tap(F.triggerDelay) end
end

U.aimCircle = H.drawing("Circle", { Visible = false, Thickness = 1.5, NumSides = 64, Filled = false, Transparency = 1, Color = F.aimFovColor })
U.silentCircle = H.drawing("Circle", { Visible = false, Thickness = 1.5, NumSides = 64, Filled = false, Transparency = 1, Color = F.silentFovColor })
U.triggerCircle = H.drawing("Circle", { Visible = false, Thickness = 1, NumSides = 48, Filled = false, Transparency = 0.6, Color = Color3.fromRGB(255, 255, 255) })

function H.circles()
	local camera = workspace.CurrentCamera
	if not camera then return end
	local center = camera.ViewportSize / 2
	local function place(circle, show, radius, color)
		if not circle then return end
		circle.Visible = show
		if show then
			circle.Position = center
			circle.Radius = radius
			circle.Color = color
		end
	end
	place(U.aimCircle, F.aim and F.aimShowFov, F.aimFov, F.aimFovColor)
	place(U.silentCircle, F.silent and F.silentShowFov, F.silentFov, F.silentFovColor)
	place(U.triggerCircle, F.trigger and F.triggerMode == "Fov" and F.triggerFov > 0, F.triggerFov, Color3.fromRGB(255, 255, 255))
end

function H.scoped()
	if LocalPlayer:GetAttribute("IsSniperScoped") == true then return true end
	local camera = S.lib.Camera
	local getter = type(camera) == "table" and camera.getTargetFOV
	if type(getter) ~= "function" then return false end
	local ok, target = pcall(getter)
	if not ok or type(target) ~= "number" then return false end
	if target > S.fovBase then S.fovBase = target end
	return target < S.fovBase
end

function H.fovStep()
	if not alive() then return end
	local camera = workspace.CurrentCamera
	if not camera then return end
	if not F.camFov then
		if S.fovSaved then camera.FieldOfView, S.fovSaved = S.fovSaved, nil end
		S.fovBase = 0
		return
	end
	if H.scoped() then return end
	S.fovSaved = S.fovSaved or camera.FieldOfView
	camera.FieldOfView = F.camFovValue
end

S.renderNames = { "FacilityView" .. SESSION, "FacilityAim" .. SESSION, "FacilityFov" .. SESSION }
RunService:BindToRenderStep(S.renderNames[1], Enum.RenderPriority.First.Value, function()
	if alive() then H.restoreView() end
end)
RunService:BindToRenderStep(S.renderNames[2], Enum.RenderPriority.Camera.Value + 1, H.lockView)
RunService:BindToRenderStep(S.renderNames[3], Enum.RenderPriority.Camera.Value + 3, H.fovStep)

H.track(RunService.Heartbeat:Connect(function()
	pcall(H.circles)
	local ok = pcall(H.combatStep)
	if not ok then H.release() end
end))

task.spawn(function()
	task.wait(1)
	if not alive() then return end
	pcall(H.installRecoilHooks)
	pcall(H.installGunHooks)
end)

function H.stubSignal()
	return { Connect = function() return { Disconnect = function() end } end }
end

S.espStub = {
	Started = true,
	Settings = { TeamCheck = "Off" },
	Self = {},
	Entities = {},
	Added = H.stubSignal(),
	Removed = H.stubSignal(),
	Updated = H.stubSignal(),
	Start = function() end,
	Get = function() return nil end,
	GetAll = function() return {} end,
	RefreshTargets = function() end,
}

S.espSaved = {
	getWeapon = Esp.getWeapon,
	getBoxParts = Esp.getBoxParts,
	bodyPartsOnly = Esp.sharedSettings.bodyPartsOnly,
	teamCheck = Esp.sharedSettings.teamCheck,
}

H.BODY_PARTS = {
	Head = true, UpperTorso = true, LowerTorso = true, Torso = true,
	LeftUpperArm = true, LeftLowerArm = true, LeftHand = true, RightUpperArm = true, RightLowerArm = true, RightHand = true,
	LeftUpperLeg = true, LeftLowerLeg = true, LeftFoot = true, RightUpperLeg = true, RightLowerLeg = true, RightFoot = true,
	["Left Arm"] = true, ["Right Arm"] = true, ["Left Leg"] = true, ["Right Leg"] = true,
}

H.BOX_SIGNS = {
	Vector3.new(-1, -1, -1), Vector3.new(1, -1, -1), Vector3.new(-1, 1, -1), Vector3.new(1, 1, -1),
	Vector3.new(-1, -1, 1), Vector3.new(1, -1, 1), Vector3.new(-1, 1, 1), Vector3.new(1, 1, 1),
}

function H.espWeapon(entity)
	if typeof(entity) ~= "Instance" then return S.espSaved.getWeapon and S.espSaved.getWeapon(entity) or nil end
	local owner = entity:IsA("Player") and entity or H.owner(entity)
	local equipped = owner and H.equipped(owner)
	return equipped and (equipped.Name or equipped.Weapon) or nil
end

function H.espBoxParts(model)
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
					minX, maxX = math.min(minX, point.X), math.max(maxX, point.X)
					minY, maxY = math.min(minY, point.Y), math.max(maxY, point.Y)
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
	if S.espRenderClass then return end
	local meta = getmetatable(object)
	local class = meta and meta.__index
	if type(class) ~= "table" or type(class.Render) ~= "function" then return end

	local original = class.Render
	S.espRenderClass, S.espRenderOriginal = class, original
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
	S.espRenderClass, S.espRenderOriginal = nil, nil
end

function H.espDrop(model)
	pcall(function() Esp:RemoveInstance(model) end)
	S.espKeys[model] = nil
end

function H.espDropAll()
	for model in pairs(S.espKeys) do H.espDrop(model) end
	table.clear(S.espKeys)
end

function H.espSync()
	if not S.espOn then return end
	local seen = {}

	for _, model in ipairs(H.candidates()) do
		local owner = H.owner(model)
		if not H.dead(model, owner) and model:FindFirstChild("HumanoidRootPart") then
			local key = (not F.teamCheck or H.hostile(model)) and "enemy" or "friendly"
			seen[model] = true
			if S.espKeys[model] ~= key then
				if S.espKeys[model] then H.espDrop(model) end
				local name = owner and owner.DisplayName or ("BOT " .. model.Name)
				pcall(function()
					Esp:AddInstance(model, { Team = key, Text = name, Health = H.health })
				end)
				S.espKeys[model] = key
			end
		end
	end

	for model in pairs(S.espKeys) do
		if not seen[model] then H.espDrop(model) end
	end
end

function H.setEsp(state)
	S.espOn = state
	if state then
		Esp.getWeapon = H.espWeapon
		Esp.getBoxParts = H.espBoxParts
		Esp.sharedSettings.bodyPartsOnly = true
		Esp.sharedSettings.teamCheck = "Off"
		local ok, err = pcall(function() Esp:Load(S.espStub) end)
		if not ok and not string.find(tostring(err), "already loaded", 1, true) then
			Library:Error("Esp", tostring(err), 10)
			S.espOn = false
			return
		end
		H.espSync()
	else
		H.espDropAll()
		pcall(function() Esp:Unload() end)
	end
end

H.loop(0.25, H.espSync)

function H.forget(name)
	local ghost = S.ghosts[name]
	if ghost then ghost.seen, ghost.heard = 0, 0 end
end

function H.ghostDrawings(ghost)
	if ghost.box then return end
	ghost.box = H.drawing("Square", { Visible = false, Filled = false, Thickness = 1, Transparency = 1 })
	ghost.label = H.drawing("Text", { Visible = false, Center = true, Outline = true, Size = 13, Transparency = 1 })
end

function H.ghostHide(ghost)
	if ghost.box then ghost.box.Visible = false end
	if ghost.label then ghost.label.Visible = false end
end

function H.ghostStep()
	local now = os.clock()
	local camera = workspace.CurrentCamera
	local live = {}

	for _, model in ipairs(H.candidates()) do
		local owner = H.owner(model)
		local root = model:FindFirstChild("HumanoidRootPart")
		if owner and H.dead(model, owner) then
			H.forget(model.Name)
		elseif owner and root then
			local ghost = S.ghosts[model.Name] or { seen = 0, heard = 0 }
			S.ghosts[model.Name] = ghost
			ghost.pos, ghost.seen = root.Position, now
			ghost.friendly = F.teamCheck and not H.hostile(model)
			live[model.Name] = true
		end
	end

	for name, ghost in pairs(S.ghosts) do
		local owner = Players:FindFirstChild(name)
		if not owner then
			H.ghostHide(ghost)
			if ghost.box then pcall(function() ghost.box:Remove() end) end
			if ghost.label then pcall(function() ghost.label:Remove() end) end
			S.ghosts[name] = nil
		else
			local age = now - math.max(ghost.seen, ghost.heard or 0)
			local show = S.espOn and F.memory > 0 and not live[name] and not ghost.friendly and ghost.pos ~= nil
				and age <= F.memory and not H.dead(nil, owner) and camera ~= nil
			if show then
				local top, topOn = camera:WorldToViewportPoint(ghost.pos + Vector3.new(0, 2.6, 0))
				local bottom, bottomOn = camera:WorldToViewportPoint(ghost.pos - Vector3.new(0, 3, 0))
				show = topOn and bottomOn and top.Z > 0
				if show then
					H.ghostDrawings(ghost)
					local height = math.max(math.abs(bottom.Y - top.Y), 6)
					local width = height * 0.55
					local fade = 1 - (age / math.max(F.memory, 0.1)) * 0.7
					if ghost.box then
						ghost.box.Size = Vector2.new(width, height)
						ghost.box.Position = Vector2.new(top.X - width / 2, top.Y)
						ghost.box.Color = F.ghostColor
						ghost.box.Transparency = fade
						ghost.box.Visible = true
					end
					if ghost.label then
						local distance = math.floor((ghost.pos - camera.CFrame.Position).Magnitude)
						ghost.label.Text = owner.DisplayName .. " ? [" .. distance .. "]"
						ghost.label.Position = Vector2.new(top.X, top.Y - 16)
						ghost.label.Color = F.ghostColor
						ghost.label.Transparency = fade
						ghost.label.Visible = true
					end
				end
			end
			if not show then H.ghostHide(ghost) end
		end
	end
end

H.track(RunService.RenderStepped:Connect(function()
	if alive() then pcall(H.ghostStep) end
end))

function H.hear(position, weapon)
	local now = os.clock()
	local best, bestDistance = nil, 45
	for name, ghost in pairs(S.ghosts) do
		if not ghost.friendly and ghost.pos and now - ghost.seen >= 0.3 then
			local owner = Players:FindFirstChild(name)
			local equipped = owner and H.equipped(owner)
			local matches = not weapon or not (equipped and equipped.Name) or equipped.Name == weapon
			local distance = (ghost.pos - position).Magnitude
			if matches and distance < bestDistance then best, bestDistance = ghost, distance end
		end
	end
	if best then
		best.pos = position + Vector3.new(0, 2.5, 0)
		best.heard = now
	end
end

function H.soundFriendly(position)
	local mine = H.myChar()
	if mine and (mine:GetPivot().Position - position).Magnitude < 6 then return true end
	if not F.teamCheck or H.ffa() then return false end
	for _, model in ipairs(H.candidates()) do
		if not H.hostile(model) and (model:GetPivot().Position - position).Magnitude < 6 then return true end
	end
	return false
end

function H.soundMark(position, text)
	if #S.marks >= 24 then
		local oldest = table.remove(S.marks, 1)
		pcall(function() oldest.holder:Destroy() end)
	end
	local holder = Instance.new("Attachment")
	holder.WorldPosition = position
	local gui = Instance.new("BillboardGui")
	gui.AlwaysOnTop = true
	gui.Size = UDim2.fromOffset(120, 34)
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 13
	label.TextColor3 = F.soundColor
	label.TextStrokeTransparency = 0.3
	label.Parent = gui
	gui.Adornee = holder
	gui.Parent = holder
	holder.Parent = workspace.Terrain
	table.insert(S.marks, { holder = holder, label = label, text = text, born = os.clock() })
end

function H.soundStep()
	local camera = workspace.CurrentCamera
	for index = #S.marks, 1, -1 do
		local mark = S.marks[index]
		local age = os.clock() - mark.born
		if not F.soundEsp or age > F.soundLife or not mark.holder.Parent then
			pcall(function() mark.holder:Destroy() end)
			table.remove(S.marks, index)
		else
			local distance = camera and math.floor((mark.holder.WorldPosition - camera.CFrame.Position).Magnitude) or 0
			mark.label.Text = mark.text .. "\n" .. distance .. "m"
			mark.label.TextColor3 = F.soundColor
			mark.label.TextTransparency = age / F.soundLife * 0.8
		end
	end
end

H.loop(0.05, H.soundStep)

function H.heard(info)
	if not alive() or type(info) ~= "table" or typeof(info.Position) ~= "Vector3" then return end
	local steps = info.Class == "FloorSounds"
	if not steps and info.Name ~= "Shoot" then return end
	if H.soundFriendly(info.Position) then return end
	H.hear(info.Position, not steps and tostring(info.Class) or nil)
	if F.soundEsp then H.soundMark(info.Position, steps and "Steps" or tostring(info.Class)) end
end

function H.installSound()
	if S.soundEntry then return true end
	local packet = H.packet("Sound", "ReplicateSound")
	if not packet or type(packet.Listen) ~= "function" then return false end
	local reader = getupvalues or (debug and debug.getupvalues)
	if type(reader) ~= "function" then return false end
	local ok, values = pcall(reader, packet.Listen)
	local listeners = ok and type(values) == "table" and values[1]
	if type(listeners) ~= "table" then return false end

	for _, entry in ipairs(listeners) do
		if type(entry) == "table" and type(entry.callback) == "function" then
			local original = entry.callback
			S.soundEntry, S.soundOriginal = entry, original
			entry.callback = function(info, ...)
				pcall(H.heard, info)
				return original(info, ...)
			end
			return true
		end
	end
	return false
end

function H.uninstallSound()
	if S.soundEntry and S.soundOriginal then S.soundEntry.callback = S.soundOriginal end
	S.soundEntry, S.soundOriginal = nil, nil
	for _, mark in ipairs(S.marks) do pcall(function() mark.holder:Destroy() end) end
	table.clear(S.marks)
end

H.loop(3, function()
	if not S.soundEntry then H.installSound() end
end)

function H.buildRadar()
	if U.radar and U.radar.Parent then return U.radar end
	local frame = Instance.new("Frame")
	frame.Name = "Radar"
	frame.Size = UDim2.fromOffset(F.radarSize, F.radarSize)
	frame.Position = UDim2.new(0, 24, 0.5, -F.radarSize / 2)
	frame.BackgroundColor3 = Color3.fromRGB(14, 14, 18)
	frame.BackgroundTransparency = 0.25
	frame.BorderSizePixel = 0
	frame.Active = true
	frame.Visible = false
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(60, 60, 70)
	stroke.Parent = frame

	local horizontal = Instance.new("Frame")
	horizontal.Size = UDim2.new(1, 0, 0, 1)
	horizontal.Position = UDim2.fromScale(0, 0.5)
	horizontal.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
	horizontal.BorderSizePixel = 0
	horizontal.Parent = frame
	local vertical = horizontal:Clone()
	vertical.Size = UDim2.new(0, 1, 1, 0)
	vertical.Position = UDim2.fromScale(0.5, 0)
	vertical.Parent = frame

	local me = Instance.new("Frame")
	me.Size = UDim2.fromOffset(6, 6)
	me.AnchorPoint = Vector2.new(0.5, 0.5)
	me.Position = UDim2.fromScale(0.5, 0.5)
	me.BackgroundColor3 = Color3.new(1, 1, 1)
	me.BorderSizePixel = 0
	me.ZIndex = 3
	me.Parent = frame
	local meCorner = Instance.new("UICorner")
	meCorner.CornerRadius = UDim.new(1, 0)
	meCorner.Parent = me

	local dragging, dragStart, startPos = false, nil, nil
	H.track(frame.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging, dragStart, startPos = true, input.Position, frame.Position
		end
	end))
	H.track(UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local delta = input.Position - dragStart
			frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
		end
	end))
	H.track(UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then dragging = false end
	end))

	frame.Parent = H.overlay()
	U.radar = frame
	U.radarDots = {}
	return frame
end

function H.radarDot(index)
	local dot = U.radarDots[index]
	if dot then return dot end
	dot = Instance.new("Frame")
	dot.Size = UDim2.fromOffset(6, 6)
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.BorderSizePixel = 0
	dot.ZIndex = 2
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = dot
	dot.Parent = U.radar
	U.radarDots[index] = dot
	return dot
end

function H.radarStep()
	if not F.radar then
		if U.radar then U.radar.Visible = false end
		return
	end
	local frame = H.buildRadar()
	frame.Visible = true
	frame.Size = UDim2.fromOffset(F.radarSize, F.radarSize)

	local camera = workspace.CurrentCamera
	local mine = H.myChar()
	local origin = (mine and mine:GetPivot().Position) or (camera and camera.CFrame.Position)
	if not (camera and origin) then return end

	local look = camera.CFrame.LookVector
	local forward = Vector3.new(look.X, 0, look.Z)
	forward = forward.Magnitude > 0.01 and forward.Unit or Vector3.new(0, 0, -1)
	local right = Vector3.new(-forward.Z, 0, forward.X)
	local half = F.radarSize / 2
	local scale = half / F.radarRange
	local used = 0

	for _, model in ipairs(H.candidates()) do
		if not H.dead(model, H.owner(model)) then
			local offset = model:GetPivot().Position - origin
			local px, pz = offset:Dot(right) * scale, offset:Dot(forward) * scale
			local length = math.sqrt(px * px + pz * pz)
			if length > half - 4 then
				px, pz = px / length * (half - 4), pz / length * (half - 4)
			end
			used = used + 1
			local dot = H.radarDot(used)
			dot.Visible = true
			dot.Position = UDim2.fromOffset(half + px, half - pz)
			dot.BackgroundColor3 = (not F.teamCheck or H.hostile(model)) and F.radarEnemy or F.radarFriend
		end
	end

	for index = used + 1, #U.radarDots do U.radarDots[index].Visible = false end
end

H.loop(1 / 30, H.radarStep)

function H.lightingStep()
	if F.fullbright then
		S.lightSaved = S.lightSaved or { Lighting.Brightness, Lighting.ClockTime, Lighting.FogEnd, Lighting.GlobalShadows, Lighting.Ambient }
		Lighting.Brightness, Lighting.ClockTime, Lighting.FogEnd, Lighting.GlobalShadows = 2, 14, 1e6, false
		Lighting.Ambient = Color3.fromRGB(178, 178, 178)
	elseif S.lightSaved then
		Lighting.Brightness, Lighting.ClockTime, Lighting.FogEnd, Lighting.GlobalShadows, Lighting.Ambient = table.unpack(S.lightSaved)
		S.lightSaved = nil
	end
end

H.loop(0.5, H.lightingStep)

function H.installEffects()
	local smoke, flash = S.lib.Smoke, S.lib.Flash
	if type(smoke) == "table" and type(smoke.Create) == "function" and not S.hooks.smoke then
		local create
		create = H.hook("smoke", smoke.Create, function(...)
			if alive() and F.noSmoke then return nil end
			return create(...)
		end)
	end
	if type(flash) == "table" and type(flash.Flash) == "function" and not S.hooks.flash then
		local blind
		blind = H.hook("flash", flash.Flash, function(...)
			if alive() and F.noFlash then return nil end
			return blind(...)
		end)
	end
	if F.noSmoke and type(smoke) == "table" and type(smoke.DestroyAll) == "function" then pcall(smoke.DestroyAll) end
	if F.noFlash and type(flash) == "table" and type(flash.CancelFlash) == "function" then pcall(flash.CancelFlash) end
	return S.hooks.smoke ~= nil or S.hooks.flash ~= nil
end

function H.skinFolder()
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	return assets and assets:FindFirstChild("Skins")
end

function H.skinCategory(name, kind)
	if H.KINDS[kind] then return H.KINDS[kind] end
	if kind ~= "Weapon" then return nil end
	local data = S.weapons[name]
	return data and data.Type or "Other"
end

function H.buildCatalog()
	local folder = H.skinFolder()
	local listing = H.decode(ReplicatedStorage:GetAttribute("AvaiableSkins")) or {}
	local catalog = {}

	for name, entries in pairs(listing) do
		if type(entries) == "table" and folder and folder:FindFirstChild(name) then
			local _, first = next(entries)
			local category = H.skinCategory(name, type(first) == "table" and first.type or nil)
			if category then
				catalog[category] = catalog[category] or {}
				table.insert(catalog[category], name)
				S.skins.rank[name] = {}
				for skin, entry in pairs(entries) do
					if type(entry) == "table" then S.skins.rank[name][skin] = H.RANKS[entry.rarity] or 0 end
				end
			end
		end
	end

	for _, names in pairs(catalog) do table.sort(names) end
	S.skins.catalog = catalog
	return catalog
end

function H.skinCategories()
	local catalog = S.skins.catalog or H.buildCatalog()
	local list, seen = {}, {}
	for _, category in ipairs(H.CATEGORY_ORDER) do
		if catalog[category] then
			table.insert(list, category)
			seen[category] = true
		end
	end
	for category in pairs(catalog) do
		if not seen[category] then table.insert(list, category) end
	end
	return list
end

function H.skinItems(category)
	local catalog = S.skins.catalog or H.buildCatalog()
	return catalog[category or ""] or {}
end

function H.skinList(weapon)
	local folder = H.skinFolder()
	local holder = folder and weapon and folder:FindFirstChild(weapon)
	if not holder then return {} end
	local ranks = S.skins.rank[weapon] or {}
	local names = {}
	for _, child in ipairs(holder:GetChildren()) do table.insert(names, child.Name) end
	table.sort(names, function(a, b)
		local ra, rb = ranks[a] or 0, ranks[b] or 0
		if ra ~= rb then return ra > rb end
		return a < b
	end)
	return names
end

function H.skinSource(weapon, skin, view)
	local folder = H.skinFolder()
	local holder = folder and folder:FindFirstChild(weapon)
	local paint = holder and holder:FindFirstChild(skin)
	local side = paint and paint:FindFirstChild(view)
	if not side then return nil end
	for _, wear in ipairs(H.WEARS) do
		local found = side:FindFirstChild(wear)
		if found then return found end
	end
	return side:FindFirstChildOfClass("Folder")
end

function H.paint(model, weapon, skin, view)
	local source = H.skinSource(weapon, skin, view)
	if not source then return false end
	local whole = source:FindFirstChild("SurfaceAppearance")

	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			local current = part:FindFirstChildOfClass("SurfaceAppearance")
			local look = source:FindFirstChild(part.Name)
			if not look and whole and current and not H.ARM_PARTS[part.Name] then look = whole end
			if look then
				if S.skins.originals[part] == nil then S.skins.originals[part] = current and current:Clone() or false end
				if current then current:Destroy() end
				look:Clone().Parent = part
			end
		end
	end
	return true
end

function H.unpaint(model)
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			local saved = S.skins.originals[part]
			if saved ~= nil then
				local current = part:FindFirstChildOfClass("SurfaceAppearance")
				if current then current:Destroy() end
				if saved then saved:Clone().Parent = part end
				S.skins.originals[part] = nil
			end
		end
	end
end

function H.weaponOf(model)
	local folder = H.skinFolder()
	if folder and folder:FindFirstChild(model.Name) then return model.Name end
	local equipped = H.equipped()
	return equipped and (equipped.Weapon or equipped.Name)
end

function H.skinModels()
	local list = {}
	local camera = workspace.CurrentCamera
	for _, child in ipairs(camera and camera:GetChildren() or {}) do
		if child:IsA("Model") then table.insert(list, { child, "Camera" }) end
	end
	local character = H.myChar()
	local folder = H.skinFolder()
	if character and folder then
		for _, child in ipairs(character:GetChildren()) do
			if child:IsA("Model") and folder:FindFirstChild(child.Name) then table.insert(list, { child, "Character" }) end
		end
	end
	return list
end

function H.skinStep()
	local map = S.skins.map
	local on = F.skinChanger
	local glove = on and map[H.GLOVE_KEY] or nil
	local gloveSkin = glove and map[glove] or nil

	for _, entry in ipairs(H.skinModels()) do
		local model, view = entry[1], entry[2]
		local weapon = H.weaponOf(model)
		local skin = on and weapon and map[weapon] or nil
		local key = (skin or gloveSkin) and (tostring(weapon) .. "|" .. tostring(skin) .. "|" .. tostring(gloveSkin)) or nil
		if S.skins.applied[model] ~= key then
			if S.skins.applied[model] then H.unpaint(model) end
			if skin then H.paint(model, weapon, skin, view) end
			if gloveSkin and view == "Camera" then H.paint(model, glove, gloveSkin, view) end
			S.skins.applied[model] = key
		end
	end
end

H.loop(0.2, H.skinStep)

function H.skinSave()
	if type(writefile) ~= "function" then return end
	pcall(function()
		if type(isfolder) == "function" and type(makefolder) == "function" then
			if not isfolder("Facility") then makefolder("Facility") end
			if not isfolder(H.SAVE_FOLDER) then makefolder(H.SAVE_FOLDER) end
		end
		writefile(H.SKIN_FILE, HttpService:JSONEncode(S.skins.map))
	end)
end

function H.skinLoad()
	if type(readfile) ~= "function" or type(isfile) ~= "function" then return end
	local ok, raw = pcall(function()
		if isfile(H.SKIN_FILE) then return readfile(H.SKIN_FILE) end
		return nil
	end)
	local map = ok and H.decode(raw)
	if type(map) == "table" then S.skins.map = map end
end

H.skinLoad()

function H.isGlove(weapon)
	local catalog = S.skins.catalog or H.buildCatalog()
	return catalog.Gloves ~= nil and table.find(catalog.Gloves, weapon) ~= nil
end

function H.setSkin(weapon, skin, quiet)
	if not weapon or weapon == "" or not skin or skin == "" then return false end
	local map = S.skins.map
	if skin == "Default" then
		map[weapon] = nil
		if map[H.GLOVE_KEY] == weapon then map[H.GLOVE_KEY] = nil end
	else
		map[weapon] = skin
		if H.isGlove(weapon) then map[H.GLOVE_KEY] = weapon end
	end
	if not quiet then H.skinSave() end
	return true
end

function H.setAllSkins(pick)
	local count = 0
	for _, category in ipairs(H.skinCategories()) do
		if category ~= "Gloves" then
			for _, weapon in ipairs(H.skinItems(category)) do
				local list = H.skinList(weapon)
				if #list > 0 then
					H.setSkin(weapon, pick(list), true)
					count = count + 1
				end
			end
		end
	end
	H.skinSave()
	return count
end

function H.resetSkins()
	table.clear(S.skins.map)
	H.skinSave()
end

function H.skinCount()
	local count = 0
	for key in pairs(S.skins.map) do
		if key ~= H.GLOVE_KEY then count = count + 1 end
	end
	return count
end

function H.redeemAll()
	local packet = H.packet("Dashboard", "RedeemCode")
	if not packet or type(packet.Send) ~= "function" then return nil end
	if S.redeeming then return 0 end
	S.redeeming = true
	local sent = 0
	for _, code in ipairs(H.CODES) do
		if not alive() then break end
		if pcall(packet.Send, code) then sent = sent + 1 end
		task.wait(1.1)
	end
	S.redeeming = false
	return sent
end

function H.installBuyHook()
	if S.hooks.buy then return true end
	local packet = H.packet("Inventory", "BuyMenuPurchase")
	if not packet or type(packet.Send) ~= "function" then return false end
	local original
	original = H.hook("buy", packet.Send, function(payload, ...)
		if alive() and type(payload) == "table" and payload.Name and payload.Path and not S.replaying then
			for index, entry in ipairs(S.bought) do
				if entry.Name == payload.Name then
					table.remove(S.bought, index)
					break
				end
			end
			table.insert(S.bought, { Equipment = payload.Equipment, Path = payload.Path, Name = payload.Name })
		end
		return original(payload, ...)
	end)
	return original ~= nil
end

function H.rebuy()
	local packet = H.packet("Inventory", "BuyMenuPurchase")
	if not packet or #S.bought == 0 or S.replaying then return 0 end
	S.replaying = true
	local sent = 0
	for _, entry in ipairs(S.bought) do
		if not alive() then break end
		if pcall(packet.Send, { Equipment = entry.Equipment, Path = entry.Path, Name = entry.Name }) then sent = sent + 1 end
		task.wait(0.25)
	end
	S.replaying = false
	return sent
end

function H.loadoutText()
	local names = {}
	for _, entry in ipairs(S.bought) do table.insert(names, tostring(entry.Name)) end
	return #names > 0 and table.concat(names, ", ") or "nothing recorded yet"
end

H.loop(0.25, function()
	local phase = workspace:GetAttribute("GameState")
	local buying = H.BUY_PHASES[phase] == true
	if buying and phase ~= S.phase then S.rebuyPending = true end
	if not buying then S.rebuyPending = false end
	S.phase = phase
	if F.autoRebuy and S.rebuyPending and H.isAlive() then
		S.rebuyPending = false
		task.spawn(H.rebuy)
	end
end)

task.spawn(function()
	task.wait(1)
	if alive() then pcall(H.installBuyHook) end
end)

H.track(LocalPlayer.Idled:Connect(function()
	if not F.antiAfk then return end
	pcall(function()
		VirtualUser:CaptureController()
		VirtualUser:ClickButton2(Vector2.new())
	end)
end))

H.track(UserInputService.JumpRequest:Connect(function()
	if not F.infJump or H.body() then return end
	local humanoid = H.humanoid()
	if humanoid then humanoid:ChangeState(Enum.HumanoidStateType.Jumping) end
end))

H.track(UserInputService.InputBegan:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.Space and not UserInputService:GetFocusedTextBox() then S.hop.space = true end
end))

H.track(UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.Space then S.hop.space = false end
end))

function H.crouch(down)
	if S.hop.crouched == down then return end
	S.hop.crouched = down
	local controller = S.lib.Character
	if type(controller) ~= "table" or type(controller.crouch) ~= "function" then return end
	if not down and UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then return end
	pcall(controller.crouch, down)
end

function H.hopStep()
	local controller = S.lib.Character
	local body = F.bhop and S.hop.space and H.isAlive() and H.body()
	if not body or type(controller) ~= "table" or type(controller.jump) ~= "function" or UserInputService:GetFocusedTextBox() then
		H.crouch(false)
		return
	end
	local grounded = body.OnGround == true
	H.crouch(F.bhopCrouch and not grounded)
	pcall(controller.jump, false)
	if not grounded or os.clock() - S.hop.at < 0.05 then return end
	S.hop.at = os.clock()
	pcall(controller.jump)
end

H.track(RunService.Heartbeat:Connect(function()
	if alive() and (F.bhop or S.hop.crouched) then pcall(H.hopStep) end
end))

function H.spectators()
	local count = tonumber(LocalPlayer:GetAttribute("Spectators")) or 0
	if count == 0 then return "nobody" end
	local names = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer and tostring(player:GetAttribute("IsSpectating")) == "true" and tostring(player:GetAttribute("Dead")) == "true" then
			table.insert(names, player.DisplayName)
		end
	end
	return count .. (#names > 0 and (" (" .. table.concat(names, ", ") .. ")") or "")
end

function H.rejoin()
	pcall(function() TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer) end)
end

function H.serverHop()
	pcall(function() TeleportService:Teleport(game.PlaceId, LocalPlayer) end)
end

shared.FacilityCleanup = function()
	F.aim, F.silent, F.trigger, F.rage = false, false, false, false
	F.noRecoil, F.noSpread, F.noFlash, F.noSmoke = false, false, false, false
	F.fullbright, F.camFov, F.skinChanger, F.bhop, F.radar = false, false, false, false, false

	pcall(H.combatRest)
	pcall(H.restoreView)
	pcall(H.lightingStep)
	pcall(H.fovStep)
	pcall(H.skinStep)
	pcall(H.crouch, false)
	pcall(H.uninstallSound)
	pcall(H.unhookAll)

	for _, name in ipairs(S.renderNames or {}) do
		pcall(function() RunService:UnbindFromRenderStep(name) end)
	end

	for _, connection in ipairs(S.connections) do pcall(function() connection:Disconnect() end) end
	for _, thread in ipairs(S.threads) do pcall(task.cancel, thread) end
	for _, object in ipairs(S.drawings) do pcall(function() object:Remove() end) end
	for _, object in ipairs(S.instances) do pcall(function() object:Destroy() end) end
	if S.gui then pcall(function() S.gui:Destroy() end) end

	pcall(H.espDropAll)
	pcall(function() Esp:Unload() end)
	pcall(H.unpatchEspRender)
	Esp.getWeapon = S.espSaved.getWeapon
	Esp.getBoxParts = S.espSaved.getBoxParts
	Esp.sharedSettings.bodyPartsOnly = S.espSaved.bodyPartsOnly
	Esp.sharedSettings.teamCheck = S.espSaved.teamCheck

	pcall(function() Library:Destroy() end)
end

for _, message in ipairs(moduleErrors) do
	warn("[Facility] " .. message)
end

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
U.Rage     = Window:Tab("Rage", "zap")
U.Visuals  = Window:Tab("Visuals", "eye")
U.World    = Window:Tab("World", "globe")
U.Skins    = Window:Tab("Skins", "palette")
U.Misc     = Window:Tab("Misc", "package")
Window:TabDivider()
U.Settings = Window:Tab("Settings", "cog")

if #moduleErrors > 0 then
	U.failBox = U.Combat:Section("Game Modules", "full")
	for _, message in ipairs(moduleErrors) do
		U.failBox:Label(message, { Style = "dim" })
	end
end

U.aimBox = U.Combat:Section("Aim Assist", 1)

U.aimBox:Toggle({
	Text = "Enable",
	Flag = "bs_aim",
	Default = false,
	Hint = "pulls your view onto the target while the aim key is held",
	Callback = function(state)
		F.aim = state
		if not state then S.aimTarget, S.aimPart = nil, nil end
	end,
})
	:ColorPicker({ Flag = "bs_aim_fov_color", Default = F.aimFovColor, Callback = function(color) F.aimFovColor = color end })

U.aimBox:Keybind({
	Text = "Aim Key",
	Flag = "bs_aim_key",
	Default = "MB2",
	Mode = "hold",
	Callback = function(state) S.aimHeld = state == true end,
})

H.T(U.aimBox, "Always Active", "bs_aim_always", false, function(state) F.aimAlways = state end, "no key needed")
H.S(U.aimBox, "Smoothness", "bs_aim_smooth", 1, 20, 4, 0, function(value) F.aimSmooth = value end)
H.D(U.aimBox, "Aim Part", "bs_aim_bone", { "Head", "Torso" }, "Head", function(value) F.aimBone = value end)
H.D(U.aimBox, "Priority", "bs_aim_priority", { "Crosshair", "Distance", "Health" }, "Crosshair", function(value) F.aimPriority = value end)

U.aimTarget = U.Combat:Section("Aim Targeting", 2)
H.S(U.aimTarget, "Fov", "bs_aim_fov", 20, 800, 150, 0, function(value) F.aimFov = value end, " px")
H.T(U.aimTarget, "Show Fov", "bs_aim_show_fov", false, function(state) F.aimShowFov = state end)
H.T(U.aimTarget, "Visible Only", "bs_aim_visible", true, function(state) F.aimVisible = state end)
H.T(U.aimTarget, "Keep Target", "bs_aim_sticky", true, function(state) F.aimSticky = state end, "stays on the same enemy until it is lost")
H.S(U.aimTarget, "Max Distance", "bs_aim_range", 50, 3000, 1500, 0, function(value) F.aimRange = value end, " studs")

U.teamBox = U.Combat:Section("Targets", 2)
H.T(U.teamBox, "Team Check", "bs_team_check", true, function(state) F.teamCheck = state end, "deathmatch is detected on its own")
H.T(U.teamBox, "Include Bots", "bs_bots", true, function(state) F.bots = state end)

U.triggerBox = U.Combat:Section("Trigger Bot", 1)

U.triggerBox:Toggle({
	Text = "Enable",
	Flag = "bs_trigger",
	Default = false,
	Hint = "fires while an enemy sits under your crosshair",
	Callback = function(state)
		F.trigger = state
		if not state then H.release() end
	end,
})
	:Keybind({ Default = "None", Flag = "bs_trigger_key" })
	:Gear(function(panel)
		H.S(panel, "Reaction", "bs_trigger_reaction", 0, 400, 0, 0, function(value) F.triggerReaction = value end, " ms")
		H.S(panel, "Fire Chance", "bs_trigger_chance", 1, 100, 100, 0, function(value) F.triggerChance = value end, "%")
	end)

H.D(U.triggerBox, "Mode", "bs_trigger_mode", { "Crosshair", "Target", "Fov" }, "Crosshair", function(value) F.triggerMode = value end)
H.S(U.triggerBox, "Fov", "bs_trigger_fov", 0, 400, 0, 0, function(value) F.triggerFov = value end)
H.T(U.triggerBox, "Team Check", "bs_trigger_team", true, function(state) F.triggerTeam = state end)
H.S(U.triggerBox, "Shot Delay", "bs_trigger_delay", 0, 2, 0, 2, function(value)
	F.triggerDelay = value
	H.release()
end, " s")
U.triggerBox:Label("0 holds and sprays, higher values tap.", { Style = "dim" })

U.gunBox = U.Combat:Section("Gun Mods", 2)
H.T(U.gunBox, "No Recoil", "bs_no_recoil", false, function(state)
	F.noRecoil = state
	if state and not H.installRecoilHooks() then H.notify("No Recoil", "Camera controller hook unavailable.", 5) end
end, "your view stays still while spraying")
H.T(U.gunBox, "No Spread", "bs_no_spread", false, function(state)
	F.noSpread = state
	if state then H.ensureGun("No Spread") end
end, "every bullet lands on the crosshair")

U.silentBox = U.Silent:Section("Silent Aim", 1)

U.silentBox:Toggle({
	Text = "Enable",
	Flag = "bs_silent",
	Default = false,
	Hint = "your bullets go to the enemy inside the circle",
	Callback = function(state)
		F.silent = state
		if state then H.ensureGun("Silent Aim") end
	end,
})
	:Keybind({ Default = "None", Flag = "bs_silent_key" })
	:ColorPicker({ Flag = "bs_silent_fov_color", Default = F.silentFovColor, Callback = function(color) F.silentFovColor = color end })

H.S(U.silentBox, "Hit Chance", "bs_silent_hit", 1, 100, 100, 0, function(value) F.silentHit = value end, "%")
H.S(U.silentBox, "Head Chance", "bs_silent_head", 0, 100, 100, 0, function(value) F.silentHead = value end, "%")
U.silentBox:Label("Missed head rolls go to the body. Lower hit chance looks cleaner.", { Style = "dim" })

U.silentTarget = U.Silent:Section("Silent Targeting", 2)
H.D(U.silentTarget, "Priority", "bs_silent_priority", { "Crosshair", "Distance", "Health" }, "Crosshair", function(value) F.silentPriority = value end)
H.S(U.silentTarget, "Fov", "bs_silent_fov", 20, 1000, 220, 0, function(value) F.silentFov = value end, " px")
H.T(U.silentTarget, "Show Fov", "bs_silent_show_fov", false, function(state) F.silentShowFov = state end)
H.T(U.silentTarget, "Visible Only", "bs_silent_visible", true, function(state) F.silentVisible = state end, "off also shoots through walls")
H.S(U.silentTarget, "Max Distance", "bs_silent_range", 50, 3000, 2000, 0, function(value) F.silentRange = value end, " studs")
H.T(U.silentTarget, "Prediction", "bs_silent_predict", false, function(state) F.silentPredict = state end, "leads moving targets using your ping")

U.rageBox = U.Rage:Section("Ragebot", 1)

U.rageBox:Toggle({
	Text = "Enable",
	Flag = "bs_rage",
	Default = false,
	Hint = "turns to the closest reachable enemy and fires on its own",
	Callback = function(state)
		F.rage = state
		if state then
			H.ensureGun("Ragebot")
		else
			S.rageTarget, S.ragePart = nil, nil
			H.release()
		end
	end,
})
	:Keybind({ Default = "None", Flag = "bs_rage_key" })

H.T(U.rageBox, "Visible Only", "bs_rage_visible", true, function(state) F.rageVisible = state end, "off also shoots through walls")
H.S(U.rageBox, "Max Distance", "bs_rage_range", 50, 3000, 2000, 0, function(value) F.rageRange = value end, " studs")

U.rageInfo = U.Rage:Section("Info", 2)
U.rageInfo:Paragraph({
	Title = "How it works",
	Content = "Ragebot always aims for the head, ignores the Fov circle and takes over the trigger. Turn it off to go back to Aim Assist and Trigger Bot.",
})

U.PLAYER_TEAMS = { "enemy", "friendly" }

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
	Flag = "bs_esp",
	Default = false,
	Callback = function(state) H.setEsp(state) end,
})
	:Keybind({ Default = "None", Flag = "bs_esp_key" })

U.espBox:Toggle({
	Text = "Box",
	Flag = "bs_esp_box",
	Default = true,
	Callback = function(state) H.espSet("box", state) end,
})
	:ColorPicker({
		Flag = "bs_esp_box_color",
		Default = Color3.fromRGB(255, 60, 60),
		Callback = function(color, alpha)
			H.espPair("boxColor", color, alpha)
			H.espPair("box3dColor", color, alpha)
		end,
	})
	:Gear(function(panel)
		H.D(panel, "Style", "bs_esp_box_style", { "2D", "3D" }, "2D", function(value)
			H.espSet("box", value == "2D")
			H.espSet("box3d", value == "3D")
		end)
		H.D(panel, "Fit", "bs_esp_box_fit", { "Body", "Full Model" }, "Body", function(value) F.tightBox = value == "Body" end)
		H.T(panel, "Fill", "bs_esp_box_fill", false, function(state) H.espSet("boxFill", state) end)
	end)

U.espBox:Toggle({
	Text = "Health Bar",
	Flag = "bs_esp_health_bar",
	Default = true,
	Callback = function(state) H.espSet("healthBar", state) end,
})
	:ColorPicker({ Flag = "bs_esp_healthy", Default = Color3.fromRGB(82, 197, 148), Callback = function(color) H.espSet("healthyColor", color) end })
	:ColorPicker({ Flag = "bs_esp_dying", Default = Color3.fromRGB(240, 90, 102), Callback = function(color) H.espSet("dyingColor", color) end })

U.espBox:Toggle({
	Text = "Skeleton",
	Flag = "bs_esp_skeleton",
	Default = false,
	Callback = function(state) H.espSet("skeleton", state) end,
})
	:ColorPicker({ Flag = "bs_esp_skeleton_color", Default = Color3.new(1, 1, 1), Callback = function(color, alpha) H.espPair("skeletonColor", color, alpha) end })

U.espBox:Toggle({
	Text = "Tracers",
	Flag = "bs_esp_tracer",
	Default = false,
	Callback = function(state) H.espSet("tracer", state) end,
})
	:ColorPicker({ Flag = "bs_esp_tracer_color", Default = Color3.new(1, 1, 1), Callback = function(color, alpha) H.espPair("tracerColor", color, alpha) end })
	:Gear(function(panel)
		H.D(panel, "Origin", "bs_esp_tracer_origin", { "Bottom", "Middle", "Top", "Mouse" }, "Bottom", function(value) H.espSet("tracerOrigin", value) end)
	end)

U.espBox:Toggle({
	Text = "Highlight",
	Flag = "bs_esp_chams",
	Default = false,
	Callback = function(state) H.espSet("chams", state) end,
})
	:ColorPicker({ Flag = "bs_esp_chams_color", Default = Color3.fromRGB(255, 60, 60), Callback = function(color, alpha) H.espPair("chamsFillColor", color, alpha) end })

U.espBox:Toggle({
	Text = "Off Screen Arrow",
	Flag = "bs_esp_arrow",
	Default = false,
	Callback = function(state) H.espSet("offScreenArrow", state) end,
})
	:ColorPicker({ Flag = "bs_esp_arrow_color", Default = Color3.new(1, 1, 1), Callback = function(color, alpha) H.espPair("offScreenArrowColor", color, alpha) end })

U.displayBox = U.Visuals:Section("Display", 2)

U.displayBox:Toggle({
	Text = "Name",
	Flag = "bs_esp_name",
	Default = true,
	Callback = function(state) H.espSet("name", state) end,
})
	:ColorPicker({ Flag = "bs_esp_name_color", Default = Color3.fromRGB(236, 241, 250), Callback = function(color, alpha) H.espPair("nameColor", color, alpha) end })

U.displayBox:Toggle({
	Text = "Distance",
	Flag = "bs_esp_distance",
	Default = true,
	Callback = function(state) H.espSet("distance", state) end,
})
	:ColorPicker({ Flag = "bs_esp_distance_color", Default = Color3.fromRGB(170, 184, 205), Callback = function(color, alpha) H.espPair("distanceColor", color, alpha) end })

U.displayBox:Toggle({
	Text = "Weapon",
	Flag = "bs_esp_weapon",
	Default = false,
	Callback = function(state) H.espSet("weapon", state) end,
})
	:ColorPicker({ Flag = "bs_esp_weapon_color", Default = Color3.fromRGB(255, 255, 255), Callback = function(color, alpha) H.espPair("weaponColor", color, alpha) end })

H.T(U.displayBox, "Health Number", "bs_esp_health_text", false, function(state) H.espSet("healthText", state) end)
H.S(U.displayBox, "Text Size", "bs_esp_text_size", 8, 24, 13, 0, function(value) Esp.sharedSettings.textSize = value end)
H.S(U.displayBox, "Max Distance", "bs_esp_range", 50, 5000, 2000, 0, function(value) H.espSet("maxDistance", value) end, " studs")

U.displayBox:Toggle({
	Text = "Show Teammates",
	Flag = "bs_esp_allies",
	Default = false,
	Callback = function(state) Esp.teamSettings.friendly.enabled = state end,
})
	:ColorPicker({
		Flag = "bs_esp_ally_color",
		Default = Color3.fromRGB(60, 255, 120),
		Callback = function(color)
			Esp.teamSettings.friendly.boxColor = { color, 1 }
			Esp.teamSettings.friendly.nameColor = { color, 1 }
			Esp.teamSettings.friendly.chamsFillColor = { color, 0.5 }
		end,
	})

U.hiddenBox = U.Visuals:Section("Hidden Enemies", 1)

U.hiddenBox:Toggle({
	Text = "Last Known Position",
	Flag = "bs_memory_on",
	Default = true,
	Hint = "keeps a marker where an enemy was last seen or heard",
	Callback = function(state) F.memory = state and (Library.Flags["bs_memory"] or 5) or 0 end,
})
	:ColorPicker({ Flag = "bs_memory_color", Default = F.ghostColor, Callback = function(color) F.ghostColor = color end })

H.S(U.hiddenBox, "Remember For", "bs_memory", 1, 15, 5, 0, function(value)
	if Library.Flags["bs_memory_on"] ~= false then F.memory = value end
end, " s")

U.hiddenBox:Toggle({
	Text = "Sound Esp",
	Flag = "bs_sound_esp",
	Default = false,
	Hint = "shows where enemies walk and shoot, even behind walls",
	Callback = function(state)
		F.soundEsp = state
		if state and not H.installSound() then H.notify("Sound Esp", "Sound listener not found yet, retrying in the background.", 5) end
	end,
})
	:ColorPicker({ Flag = "bs_sound_color", Default = F.soundColor, Callback = function(color) F.soundColor = color end })

H.S(U.hiddenBox, "Marker Time", "bs_sound_life", 1, 8, 3, 0, function(value) F.soundLife = value end, " s")

U.radarBox = U.Visuals:Section("Radar", 2)

U.radarBox:Toggle({
	Text = "Radar",
	Flag = "bs_radar",
	Default = false,
	Hint = "minimap of nearby players, drag it to move",
	Callback = function(state) F.radar = state end,
})
	:ColorPicker({ Flag = "bs_radar_enemy", Default = F.radarEnemy, Callback = function(color) F.radarEnemy = color end })
	:ColorPicker({ Flag = "bs_radar_friend", Default = F.radarFriend, Callback = function(color) F.radarFriend = color end })

H.S(U.radarBox, "Range", "bs_radar_range", 50, 1000, 250, 0, function(value) F.radarRange = value end, " studs")
H.S(U.radarBox, "Size", "bs_radar_size", 120, 320, 180, 0, function(value) F.radarSize = value end, " px")

U.worldBox = U.World:Section("Effects", 1)
H.T(U.worldBox, "Fullbright", "bs_fullbright", false, function(state)
	F.fullbright = state
	H.lightingStep()
end)
H.T(U.worldBox, "No Flash", "bs_no_flash", false, function(state)
	F.noFlash = state
	if state and not H.installEffects() then H.notify("No Flash", "Flash effect module unavailable.", 5) end
end, "flashbangs do not blind you")
H.T(U.worldBox, "No Smoke", "bs_no_smoke", false, function(state)
	F.noSmoke = state
	if state and not H.installEffects() then H.notify("No Smoke", "Smoke effect module unavailable.", 5) end
end, "see through smoke grenades")

U.camBox = U.World:Section("Camera", 2)
H.T(U.camBox, "Custom Fov", "bs_cam_fov", false, function(state) F.camFov = state end, "scoped view is left alone")
H.S(U.camBox, "Field Of View", "bs_cam_fov_value", 70, 120, 100, 0, function(value) F.camFovValue = value end)

U.moveBox = U.World:Section("Movement", 1)
H.T(U.moveBox, "Bunny Hop", "bs_bhop", false, function(state) F.bhop = state end, "hold Space to keep hopping and carry speed")
H.T(U.moveBox, "Air Crouch", "bs_bhop_crouch", true, function(state) F.bhopCrouch = state end, "crouches mid air while hopping")
H.T(U.moveBox, "Infinite Jump", "bs_inf_jump", false, function(state) F.infJump = state end, "lobby only, use Bunny Hop in rounds")

U.skinBox = U.Skins:Section("Skin Changer", 1)

H.T(U.skinBox, "Enable", "bs_skins", false, function(state) F.skinChanger = state end, "client side, only you see it")

U.skinCategory, U.skinItem, U.skinPick = nil, nil, nil
S.skinSel = { category = nil, weapon = nil }

function H.firstOr(list, fallback)
	return list[1] or fallback
end

function H.refreshSkinPick()
	if not U.skinPick then return end
	local weapon = S.skinSel.weapon
	local list = { "Default" }
	for _, name in ipairs(H.skinList(weapon)) do table.insert(list, name) end
	pcall(function() U.skinPick:SetOptions(list) end)
	pcall(function() U.skinPick:Set(weapon and S.skins.map[weapon] or "Default") end)
end

function H.refreshSkinItems()
	if not U.skinItem then return end
	local items = H.skinItems(S.skinSel.category)
	S.skinSel.weapon = H.firstOr(items, nil)
	pcall(function() U.skinItem:SetOptions(#items > 0 and items or { "-" }) end)
	pcall(function() U.skinItem:Set(S.skinSel.weapon or "-") end)
	H.refreshSkinPick()
end

function H.refreshSkinCategories()
	S.skins.catalog = nil
	local categories = H.skinCategories()
	S.skinSel.category = H.firstOr(categories, nil)
	pcall(function() U.skinCategory:SetOptions(#categories > 0 and categories or { "-" }) end)
	pcall(function() U.skinCategory:Set(S.skinSel.category or "-") end)
	H.refreshSkinItems()
end

U.skinCategory = H.D(U.skinBox, "Category", "bs_skin_category", { "-" }, "-", function(value)
	if value == "-" or value == S.skinSel.category then return end
	S.skinSel.category = value
	H.refreshSkinItems()
end)

U.skinItem = H.D(U.skinBox, "Item", "bs_skin_item", { "-" }, "-", function(value)
	if value == "-" or value == S.skinSel.weapon then return end
	S.skinSel.weapon = value
	H.refreshSkinPick()
end)

U.skinPick = H.D(U.skinBox, "Skin", "bs_skin_pick", { "Default" }, "Default", function(value)
	local weapon = S.skinSel.weapon
	if not weapon or value == nil then return end
	if (S.skins.map[weapon] or "Default") == value then return end
	H.setSkin(weapon, value)
	if U.skinCountLabel then pcall(function() U.skinCountLabel:Set(H.skinCount() .. " items changed") end) end
end)

U.skinCountLabel = U.skinBox:Label(H.skinCount() .. " items changed", { Style = "dim" })

U.skinBulk = U.Skins:Section("Quick Set", 2)

function H.skinCountUpdate()
	if U.skinCountLabel then pcall(function() U.skinCountLabel:Set(H.skinCount() .. " items changed") end) end
	H.refreshSkinPick()
end

H.B(U.skinBulk, "Best Skin On Everything", function()
	local count = H.setAllSkins(function(list) return list[1] end)
	H.skinCountUpdate()
	H.notify("Skins", count .. " items set to their rarest skin.", 4)
end)

H.B(U.skinBulk, "Random Skin On Everything", function()
	local count = H.setAllSkins(function(list) return list[math.random(1, #list)] end)
	H.skinCountUpdate()
	H.notify("Skins", count .. " items randomised.", 4)
end)

H.B(U.skinBulk, "Reset All Skins", function()
	H.resetSkins()
	H.skinCountUpdate()
	H.notify("Skins", "Every item is back to stock.", 3)
end)

H.B(U.skinBulk, "Reload Skin List", function()
	H.refreshSkinCategories()
	H.notify("Skins", #H.skinCategories() .. " categories found.", 3)
end)

U.skinBulk:Label("Choices are saved and come back on the next run.", { Style = "dim" })

task.spawn(function()
	task.wait(0.5)
	if alive() then pcall(H.refreshSkinCategories) end
end)

U.buyBox = U.Misc:Section("Auto Buy", 1)
H.T(U.buyBox, "Auto Rebuy", "bs_auto_rebuy", false, function(state)
	F.autoRebuy = state
	if state and not H.installBuyHook() then H.notify("Auto Rebuy", "Buy menu packet not found.", 5) end
end, "buys your last loadout at the start of each buy phase")

U.loadoutLabel = U.buyBox:Label("Saved: " .. H.loadoutText(), { Style = "dim" })

H.B(U.buyBox, "Rebuy Now", function()
	local sent = H.rebuy()
	H.notify("Auto Buy", sent .. " items bought again.", 3)
end)

H.B(U.buyBox, "Forget Loadout", function()
	table.clear(S.bought)
	H.notify("Auto Buy", "Saved loadout cleared.", 3)
end)

U.buyBox:Label("Buy once yourself, the loadout is remembered from there.", { Style = "dim" })

U.codeBox = U.Misc:Section("Codes", 2)
U.codeButton = U.codeBox:Button({
	Text = "Redeem All Codes",
	Badge = tostring(#H.CODES),
	Callback = function()
		task.spawn(function()
			if S.redeeming then
				H.notify("Codes", "Already redeeming, wait a moment.", 3)
				return
			end
			H.notify("Codes", "Redeeming " .. #H.CODES .. " codes...", 3)
			local sent = H.redeemAll()
			if sent == nil then
				H.notify("Codes", "Redeem packet not found.", 4)
			else
				H.notify("Codes", sent .. " codes sent.", 4)
			end
		end)
	end,
})
U.codeBox:Label("Every known code is sent for you, one per second.", { Style = "dim" })

U.utilBox = U.Misc:Section("Utility", 1)
H.T(U.utilBox, "Anti AFK", "bs_anti_afk", false, function(state) F.antiAfk = state end)
H.B(U.utilBox, "Rejoin Server", H.rejoin)
H.B(U.utilBox, "Server Hop", H.serverHop)

U.statusBox = U.Misc:Section("Status", 2)
U.statusText = U.statusBox:Paragraph({ Title = "Session", Content = "loading..." })

function H.statusText()
	local lines = {
		"Spectating you: " .. H.spectators(),
		"Gun hooks: " .. (S.gunHooked and "ready" or "waiting"),
		"Recoil hooks: " .. (S.recoilHooked and "ready" or "unavailable"),
		"Sound listener: " .. (S.soundEntry and "ready" or "waiting"),
		"Mode: " .. tostring(workspace:GetAttribute("Gamemode") or "-") .. " / " .. tostring(workspace:GetAttribute("GameState") or "-"),
	}
	return table.concat(lines, "\n")
end

H.loop(1, function()
	pcall(function() U.statusText:Set({ Title = "Session", Content = H.statusText() }) end)
	pcall(function() U.loadoutLabel:Set("Saved: " .. H.loadoutText()) end)
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

Library:Notify("Facility", "BloxStrike loaded.", 4)

SaveManager:LoadAutoloadConfig()
ThemeManager:Load()
