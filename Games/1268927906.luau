local FH = shared.Facility
local Library = FH and FH.Library

if not Library then
	local BASE = "https://raw.githubusercontent.com/FacilityHUB/UI-Facility/refs/heads/main/"
	local source = game:HttpGet(BASE .. "main.luau")
	local chunk, err = loadstring(source)
	assert(chunk, "main.luau compile error: " .. tostring(err))
	Library = chunk()
	assert(type(Library) == "table", "main.luau returned nothing")
	Library.BaseUrl = BASE
end

local SESSION = (shared.FacilitySession or 0) + 1
shared.FacilitySession = SESSION

local function alive()
	return shared.FacilitySession == SESSION
end

if shared.FacilityCleanup then
	pcall(shared.FacilityCleanup)
	shared.FacilityCleanup = nil
end

local HUB_BASE = FH and FH.HubBase or "https://raw.githubusercontent.com/FacilityHUB/Facility-Sexility/refs/heads/main/"
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
if FH then FH.Movement = Movement end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")

local LocalPlayer = Players.LocalPlayer

local H = {}
local U = {}
local S = { connections = {}, threads = {}, waterParts = {}, visited = {}, whitelist = {}, lights = {} }
local F = {
	autoTrain = false,
	trainRate = 20,
	turbo = false,
	autoChests = false,
	autoRebirth = false,
	keepSize = false,
	fistSpam = false,
	killAll = false,
	killTarget = false,
	target = nil,
	autoBrawl = false,
	skyRefuge = false,
	antiKnock = false,
	water = false,
	antiAfk = true,
	lockPosition = false,
	walkOn = false,
	walkValue = 50,
	jumpOn = false,
	jumpValue = 100,
	location = nil,
	whitelistInput = "",
}

local WORKOUTS = { "Weight", "Pushups", "Handstands", "Situps" }
local COOLDOWN_VALUES = {
	Weight = "workoutTime",
	Pushups = "pushupTime",
	Situps = "situpTime",
	Handstands = "handstandTime",
}
local SKY_SPOT = CFrame.new(4011, 26043, -2394)
local FAST_PUNCH = 0.065
local NORMAL_PUNCH = 0.35

local LOCATIONS = {
	{ "Starter Island", CFrame.new(226.25, 13.15, 219.37) },
	{ "Tiny Island", CFrame.new(-31.86, 11.06, 2087.89) },
	{ "Beach", CFrame.new(-365.8, 49.51, -501.62) },
	{ "Jungle Gym", CFrame.new(-8137, 33, 2820) },
	{ "Jungle Bench", CFrame.new(-8629.88, 69.88, 1855.03) },
	{ "Jungle Bar Lift", CFrame.new(-8678.06, 19.5, 2089.26) },
	{ "Jungle Squat", CFrame.new(-8374.26, 39.59, 2932.45) },
	{ "Frost Gym", CFrame.new(-2933.48, 34.64, -579.95) },
	{ "Mythical Gym", CFrame.new(2659.51, 26.61, 934.69) },
	{ "Eternal Gym", CFrame.new(-7176.19, 50.39, -1106.31) },
	{ "Legend Gym", CFrame.new(4446.92, 1009.47, -3983.76) },
	{ "Muscle King Gym", CFrame.new(-8626, 20, -5730) },
	{ "Brawl Arena 1", CFrame.new(985.91, 168.8, -7037.81) },
	{ "Brawl Arena 2", CFrame.new(4466.75, 339.97, -8425.75) },
	{ "Brawl Arena 3", CFrame.new(-1901.88, 256.9, -5899.65) },
}
F.location = LOCATIONS[1][1]

function H.track(connection)
	table.insert(S.connections, connection)
	return connection
end

function H.spawn(fn, ...)
	local thread = task.spawn(fn, ...)
	table.insert(S.threads, thread)
	return thread
end

function H.loop(key, interval, fn)
	H.spawn(function()
		while F[key] and alive() do
			pcall(fn)
			local wait = type(interval) == "function" and interval() or interval
			if wait and wait > 0 then task.wait(wait) else task.wait() end
		end
	end)
end

function H.notify(text, duration)
	pcall(function() Library:Notify("Facility", text, duration or 3) end)
end

function H.character()
	return LocalPlayer.Character
end

function H.root()
	local character = LocalPlayer.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

function H.humanoid()
	local character = LocalPlayer.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

function H.events()
	return ReplicatedStorage:FindFirstChild("rEvents")
end

function H.fire(name, ...)
	local folder = H.events()
	local remote = folder and folder:FindFirstChild(name)
	if not remote then return false end
	local args = table.pack(...)
	return pcall(function()
		if remote:IsA("RemoteFunction") then
			return remote:InvokeServer(table.unpack(args, 1, args.n))
		end
		remote:FireServer(table.unpack(args, 1, args.n))
	end)
end

function H.muscle(...)
	local event = LocalPlayer:FindFirstChild("muscleEvent")
	if event then pcall(event.FireServer, event, ...) end
end

function H.findTool(name)
	local character = H.character()
	local backpack = LocalPlayer:FindFirstChild("Backpack")
	local names = { name }
	local singular = name:gsub("s$", "")
	if singular ~= name then table.insert(names, singular) end
	for _, candidate in ipairs(names) do
		local tool = (character and character:FindFirstChild(candidate)) or (backpack and backpack:FindFirstChild(candidate))
		if tool then return tool end
	end
	return nil
end

function H.equip(name)
	local character = H.character()
	local tool = H.findTool(name)
	if tool and character and tool.Parent ~= character then
		pcall(function() tool.Parent = character end)
	end
	return tool
end

function H.unequip(name)
	local character = H.character()
	local backpack = LocalPlayer:FindFirstChild("Backpack")
	if not character or not backpack then return end
	local tool = character:FindFirstChild(name) or character:FindFirstChild((name:gsub("s$", "")))
	if tool then pcall(function() tool.Parent = backpack end) end
end

function H.useWorkout(name)
	local tool = H.equip(name)
	local character = H.character()
	if tool and character and tool.Parent == character then
		local cooldown = tool:FindFirstChild(COOLDOWN_VALUES[name])
		if cooldown then pcall(function() cooldown.Value = 0 end) end
		pcall(function() tool:Activate() end)
	end
end

function H.punchSpeed(value)
	local tool = H.findTool("Punch")
	local attack = tool and tool:FindFirstChild("attackTime")
	if attack then pcall(function() attack.Value = value end) end
end

function H.hands()
	local character = H.character()
	return character and character:FindFirstChild("RightHand"), character and character:FindFirstChild("LeftHand")
end

function H.hit(root)
	local right, left = H.hands()
	if not right or not left or not firetouchinterest then return end
	pcall(function()
		firetouchinterest(right, root, 1)
		firetouchinterest(left, root, 1)
		firetouchinterest(right, root, 0)
		firetouchinterest(left, root, 0)
	end)
end

function H.teleport(cframe)
	local root = H.root()
	if not root then return false end
	root.CFrame = cframe
	root.AssemblyLinearVelocity = Vector3.zero
	return true
end

function H.playerNames()
	local names = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer then table.insert(names, player.Name) end
	end
	table.sort(names)
	return names
end

function H.short(value)
	value = tonumber(value) or 0
	local units = { { 1e15, "Qa" }, { 1e12, "T" }, { 1e9, "B" }, { 1e6, "M" }, { 1e3, "K" } }
	for _, unit in ipairs(units) do
		if math.abs(value) >= unit[1] then return string.format("%.1f%s", value / unit[1], unit[2]) end
	end
	return tostring(math.floor(value))
end

function H.antiKnock(state)
	local root = H.root()
	if not root then return end
	local existing = root:FindFirstChild("FacilityStabilizer")
	if state and not existing then
		local holder = Instance.new("BodyVelocity")
		holder.Name = "FacilityStabilizer"
		holder.MaxForce = Vector3.new(1e5, 0, 1e5)
		holder.Velocity = Vector3.zero
		holder.P = 1250
		holder.Parent = root
	elseif not state and existing then
		existing:Destroy()
	end
end

function H.water(state)
	if state and #S.waterParts == 0 then
		local size = 2048
		local base = Vector3.new(-2, -9.5, -2)
		for x = -5, 5 do
			for z = -5, 5 do
				local part = Instance.new("Part")
				part.Name = "FacilityWater"
				part.Size = Vector3.new(size, 1, size)
				part.Position = base + Vector3.new(x * size, 0, z * size)
				part.Anchored = true
				part.Transparency = 1
				part.CanCollide = true
				part.Parent = workspace
				table.insert(S.waterParts, part)
			end
		end
	end
	for _, part in ipairs(S.waterParts) do
		if part.Parent then part.CanCollide = state end
	end
end

function H.invisible()
	local root = H.root()
	if not root then return end
	local home = root.CFrame
	root.CFrame = CFrame.new(915.1, 37.53, 349.81)
	task.wait(0.5)
	local character = H.character()
	local lower = character and character:FindFirstChild("LowerTorso")
	local joint = lower and lower:FindFirstChild("Root")
	if joint then
		local copy = joint:Clone()
		joint:Destroy()
		copy.Parent = lower
	end
	task.wait(0.5)
	H.teleport(home)
	H.notify("Invisibility applied until you respawn.")
end

function H.serverHop()
	local ok, body = pcall(function()
		return game:HttpGet("https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=100")
	end)
	if not ok then
		H.notify("Could not list servers.")
		return
	end
	local decoded, data = pcall(HttpService.JSONDecode, HttpService, body)
	if decoded and type(data) == "table" and data.data then
		for _, server in ipairs(data.data) do
			if server.id ~= game.JobId and not S.visited[server.id] and server.playing < server.maxPlayers then
				S.visited[server.id] = true
				pcall(function() TeleportService:TeleportToPlaceInstance(game.PlaceId, server.id, LocalPlayer) end)
				return
			end
		end
	end
	H.notify("No other server found.")
end

function H.reduceLag()
	local count = 0
	for _, object in ipairs(workspace:GetDescendants()) do
		if object:IsA("ParticleEmitter") or object:IsA("PointLight") or object:IsA("SpotLight") or object:IsA("SurfaceLight") then
			if object.Enabled then
				pcall(function() object.Enabled = false end)
				table.insert(S.lights, object)
				count += 1
			end
		end
	end
	Lighting.FogEnd = 100000
	H.notify(count .. " effects disabled.")
end

H.track(LocalPlayer.Idled:Connect(function()
	if not alive() or not F.antiAfk then return end
	pcall(function()
		local virtualUser = game:GetService("VirtualUser")
		virtualUser:CaptureController()
		virtualUser:ClickButton2(Vector2.new())
	end)
end))

H.track(LocalPlayer.CharacterAdded:Connect(function(character)
	if not alive() then return end
	character:WaitForChild("Humanoid", 10)
	task.wait(0.5)
	if not alive() then return end
	local root = character:FindFirstChild("HumanoidRootPart")
	if F.lockPosition and root then root.Anchored = true end
	if F.antiKnock then H.antiKnock(true) end
	if F.skyRefuge then H.teleport(SKY_SPOT) end
	if F.autoTrain then
		task.wait(0.5)
		for _, name in ipairs(WORKOUTS) do H.equip(name) end
	end
end))

shared.FacilityCleanup = function()
	for key, value in pairs(F) do
		if value == true then F[key] = false end
	end
	for _, connection in ipairs(S.connections) do pcall(function() connection:Disconnect() end) end
	table.clear(S.connections)
	for _, thread in ipairs(S.threads) do
		if thread ~= coroutine.running() then pcall(task.cancel, thread) end
	end
	table.clear(S.threads)
	for _, part in ipairs(S.waterParts) do pcall(function() part:Destroy() end) end
	table.clear(S.waterParts)
	for _, object in ipairs(S.lights) do pcall(function() object.Enabled = true end) end
	table.clear(S.lights)
	pcall(H.antiKnock, false)
	pcall(function()
		local root = H.root()
		if root then root.Anchored = false end
	end)
	pcall(H.punchSpeed, NORMAL_PUNCH)
	if Movement then pcall(function() Movement:Unload() end) end
	pcall(function() Library:Destroy() end)
end

local Window = Library:Window({
	Title = "Facility",
	Suffix = ".Sexility",
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

U.Farm = Window:Tab("Farm", "dumbbell")
U.Combat = Window:Tab("Combat", "swords")
U.Player = Window:Tab("Player", "user")
U.Teleport = Window:Tab("Teleport", "map-pin")
U.Stats = Window:Tab("Stats", "trending-up")
Window:TabDivider()
U.Settings = Window:Tab("Settings", "settings")

local trainSub = H.sub(U.Farm, "Training", "dumbbell")
local progressSub = H.sub(U.Farm, "Progress", "star")

local train = trainSub:Section("Training", 1)
train:Toggle({ Text = "Auto Train All", Flag = "ml_auto_train", Default = false, Callback = function(v)
	F.autoTrain = v
	if v then
		H.loop("autoTrain", function() return 1 / math.max(F.trainRate, 1) end, function()
			H.muscle("rep")
			for _, name in ipairs(WORKOUTS) do H.useWorkout(name) end
		end)
	else
		for _, name in ipairs(WORKOUTS) do H.unequip(name) end
	end
end })
train:Slider({ Text = "Reps Per Second", Flag = "ml_train_rate", Min = 5, Max = 100, Default = 20, Callback = function(v)
	F.trainRate = v
end })
train:Toggle({ Text = "Turbo Reps", Flag = "ml_turbo", Default = false, Callback = function(v)
	F.turbo = v
	if v then
		for _ = 1, 12 do
			H.loop("turbo", 0.083, function() H.muscle("rep") end)
		end
	end
end })
train:Label("Sends reps on 12 parallel loops, no tool needed.")

local single = trainSub:Section("Single Workout", 2)
for _, name in ipairs(WORKOUTS) do
	local key = "workout_" .. name
	F[key] = false
	single:Toggle({ Text = "Auto " .. name, Flag = "ml_" .. key:lower(), Default = false, Callback = function(v)
		F[key] = v
		if v then
			H.loop(key, 0.1, function() H.useWorkout(name) end)
		else
			H.unequip(name)
		end
	end })
end

local rebirth = progressSub:Section("Rebirth", 1)
rebirth:Toggle({ Text = "Auto Rebirth", Flag = "ml_auto_rebirth", Default = false, Callback = function(v)
	F.autoRebirth = v
	if v then H.loop("autoRebirth", 0.1, function() H.fire("rebirthRemote", "rebirthRequest") end) end
end })
rebirth:Button({ Text = "Rebirth Now", Callback = function()
	local ok = H.fire("rebirthRemote", "rebirthRequest")
	H.notify(ok and "Rebirth request sent." or "Rebirth remote not found.")
end })
rebirth:Toggle({ Text = "Keep Size 2", Flag = "ml_keep_size", Default = false, Callback = function(v)
	F.keepSize = v
	if v then H.loop("keepSize", 0.1, function() H.fire("changeSpeedSizeRemote", "changeSize", 2) end) end
end })
rebirth:Button({ Text = "Set Size 1", Callback = function()
	H.fire("changeSpeedSizeRemote", "changeSize", 1)
end })

local rewards = progressSub:Section("Rewards", 2)
rewards:Toggle({ Text = "Auto Collect Chests", Flag = "ml_auto_chests", Default = false, Callback = function(v)
	F.autoChests = v
	if v then
		H.loop("autoChests", 1, function()
			local root = H.root()
			if not root then return end
			for _, object in ipairs(workspace:GetDescendants()) do
				if not F.autoChests or not alive() then break end
				local name = object.Name:lower()
				if object:IsA("BasePart") and (name:find("chest") or name:find("gem")) then
					root.CFrame = object.CFrame * CFrame.new(0, 1, object.Size.Z / 2 + 2)
					task.wait(0.1)
					H.fire("checkChestRemote", object.Name)
				end
			end
		end)
	end
end })

local punch = U.Combat:Section("Punch", 1)
punch:Button({ Text = "Fast Punch", Callback = function()
	H.equip("Punch")
	H.punchSpeed(FAST_PUNCH)
	H.notify("Fast punch applied.", 2)
end })
punch:Button({ Text = "Normal Punch", Callback = function()
	H.punchSpeed(NORMAL_PUNCH)
	H.notify("Punch speed restored.", 2)
end })
punch:Toggle({ Text = "Fist Spam", Flag = "ml_fist_spam", Default = false, Callback = function(v)
	F.fistSpam = v
	if v then
		H.loop("fistSpam", 0, function()
			H.equip("Punch")
			H.punchSpeed(FAST_PUNCH)
			H.muscle("punch", "rightHand")
			H.muscle("punch", "leftHand")
		end)
	else
		H.unequip("Punch")
	end
end })
punch:Label("Punches without playing the animation.")

local kill = U.Combat:Section("Kill", 1)
kill:Toggle({ Text = "Kill All", Flag = "ml_kill_all", Default = false, Callback = function(v)
	F.killAll = v
	if v then
		if not firetouchinterest then H.notify("Your executor has no firetouchinterest.") end
		H.loop("killAll", 0.1, function()
			H.equip("Punch")
			H.punchSpeed(FAST_PUNCH)
			for _, player in ipairs(Players:GetPlayers()) do
				if player ~= LocalPlayer and not S.whitelist[player.Name] then
					local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
					if root then H.hit(root) end
				end
			end
		end)
	else
		H.unequip("Punch")
	end
end })
U.targetDropdown = kill:Dropdown({ Text = "Target", Flag = "ml_target", Options = H.playerNames(), Empty = "No players",
	Callback = function(v)
		if type(v) == "table" then v = v[1] end
		F.target = v
	end })
kill:Toggle({ Text = "Kill Target", Flag = "ml_kill_target", Default = false, Callback = function(v)
	F.killTarget = v
	if v then
		H.loop("killTarget", 0.1, function()
			local player = F.target and Players:FindFirstChild(F.target)
			if not player or player == LocalPlayer then return end
			H.equip("Punch")
			H.punchSpeed(FAST_PUNCH)
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if root then H.hit(root) end
		end)
	else
		H.unequip("Punch")
	end
end })

local whitelist = U.Combat:Section("Kill All Whitelist", 2)
whitelist:Input({ Text = "Username", Flag = "ml_whitelist_input", Default = "", Callback = function(v)
	F.whitelistInput = tostring(v or "")
end })
function H.refreshWhitelist()
	local names = {}
	for name in pairs(S.whitelist) do table.insert(names, name) end
	table.sort(names)
	if U.whitelistLabel then
		pcall(function() U.whitelistLabel:Set(#names > 0 and table.concat(names, ", ") or "Nobody") end)
	end
end
whitelist:Button({ Text = "Add", Callback = function()
	local name = F.whitelistInput:gsub("^%s+", ""):gsub("%s+$", "")
	if name ~= "" then
		S.whitelist[name] = true
		H.refreshWhitelist()
	end
end })
whitelist:Button({ Text = "Remove", Callback = function()
	S.whitelist[F.whitelistInput] = nil
	H.refreshWhitelist()
end })
U.whitelistLabel = whitelist:Label("Nobody")

local survival = U.Combat:Section("Survival", 2)
survival:Toggle({ Text = "Sky Refuge", Flag = "ml_sky", Default = false, Callback = function(v)
	F.skyRefuge = v
	if v then H.loop("skyRefuge", 0.05, function() H.teleport(SKY_SPOT) end) end
end })
survival:Label("Keeps you far above the map, out of reach.")
survival:Toggle({ Text = "Anti Knockback", Flag = "ml_anti_knock", Default = false, Callback = function(v)
	F.antiKnock = v
	H.antiKnock(v)
end })
survival:Toggle({ Text = "Auto Join Brawl", Flag = "ml_auto_brawl", Default = false, Callback = function(v)
	F.autoBrawl = v
	if v then H.loop("autoBrawl", 2, function() H.fire("brawlEvent", "joinBrawl") end) end
end })
survival:Button({ Text = "Invisible To Others", Callback = function() H.spawn(H.invisible) end })

local move = U.Player:Section("Movement", 1)
if Movement then
	move:Toggle({ Text = "Walk Speed", Flag = "ml_walk_on", Default = false, Callback = function(v)
		F.walkOn = v
		Movement:WalkSpeed(v and F.walkValue or 16, "Humanoid")
	end })
	move:Slider({ Text = "Speed", Flag = "ml_walk_value", Min = 16, Max = 300, Default = F.walkValue, Callback = function(v)
		F.walkValue = v
		if F.walkOn then Movement:WalkSpeed(v, "Humanoid") end
	end })
	move:Toggle({ Text = "Jump Power", Flag = "ml_jump_on", Default = false, Callback = function(v)
		F.jumpOn = v
		Movement:JumpPower(v and F.jumpValue or 50, "Humanoid")
	end })
	move:Slider({ Text = "Power", Flag = "ml_jump_value", Min = 50, Max = 500, Default = F.jumpValue, Callback = function(v)
		F.jumpValue = v
		if F.jumpOn then Movement:JumpPower(v, "Humanoid") end
	end })
	move:Toggle({ Text = "Infinite Jump", Flag = "ml_inf_jump", Default = false, Callback = function(v)
		Movement:InfiniteJump(v)
	end })
	move:Toggle({ Text = "Noclip", Flag = "ml_noclip", Default = false, Callback = function(v)
		Movement:Noclip(v)
	end })
else
	move:Label("Movement module failed to load.")
end
move:Toggle({ Text = "Walk On Water", Flag = "ml_water", Default = false, Callback = function(v)
	F.water = v
	H.water(v)
end })

local misc = U.Player:Section("Misc", 2)
misc:Toggle({ Text = "Anti AFK", Flag = "ml_anti_afk", Default = true, Callback = function(v)
	F.antiAfk = v
end })
misc:Toggle({ Text = "Freeze Position", Flag = "ml_lock", Default = false, Callback = function(v)
	F.lockPosition = v
	local root = H.root()
	if root then root.Anchored = v end
end })
misc:Toggle({ Text = "Hide Pets", Flag = "ml_hide_pets", Default = false, Callback = function(v)
	H.fire("showPetsEvent", v and "hidePets" or "showPets")
end })
misc:Toggle({ Text = "Block Trades", Flag = "ml_block_trades", Default = false, Callback = function(v)
	H.fire("tradingEvent", v and "disableTrading" or "enableTrading")
end })
misc:Button({ Text = "Reduce Lag", Callback = H.reduceLag })
misc:Dropdown({ Text = "Time Of Day", Flag = "ml_time", Options = { "Default", "Day", "Morning", "Night" }, Default = "Default",
	Callback = function(v)
		if v == "Day" then Lighting.ClockTime = 12
		elseif v == "Morning" then Lighting.ClockTime = 6
		elseif v == "Night" then Lighting.ClockTime = 0 end
	end })

local places = U.Teleport:Section("Locations", 1)
local names = {}
for _, entry in ipairs(LOCATIONS) do table.insert(names, entry[1]) end
places:Dropdown({ Text = "Location", Flag = "ml_location", Options = names, Default = names[1], Callback = function(v)
	F.location = v
end })
places:Button({ Text = "Teleport", Callback = function()
	for _, entry in ipairs(LOCATIONS) do
		if entry[1] == F.location then
			if H.teleport(entry[2]) then H.notify("Teleported to " .. entry[1] .. ".", 2) end
			return
		end
	end
end })
places:Button({ Text = "Random Player", Callback = function()
	local others = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local head = player ~= LocalPlayer and player.Character and player.Character:FindFirstChild("Head")
		if head then table.insert(others, head) end
	end
	if #others > 0 then H.teleport(CFrame.new(others[math.random(1, #others)].Position)) end
end })

local server = U.Teleport:Section("Server", 2)
server:Button({ Text = "Rejoin", Callback = function()
	pcall(function() TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer) end)
end })
server:Button({ Text = "Server Hop", Callback = function() H.spawn(H.serverHop) end })
server:Button({ Text = "Copy Server Link", Callback = function()
	local link = "https://www.roblox.com/games/" .. game.PlaceId .. "/?serverId=" .. game.JobId
	if setclipboard then
		setclipboard(link)
		H.notify("Server link copied.", 2)
	end
end })

local session = U.Stats:Section("This Session", "full")
U.stats = {
	time = session:Paragraph({ Title = "Time", Content = "00:00" }),
	strength = session:Paragraph({ Title = "Strength Gained", Content = "0" }),
	durability = session:Paragraph({ Title = "Durability Gained", Content = "0" }),
	agility = session:Paragraph({ Title = "Agility Gained", Content = "0" }),
	kills = session:Paragraph({ Title = "Kills Gained", Content = "0" }),
	evil = session:Paragraph({ Title = "Evil Karma Gained", Content = "0" }),
	good = session:Paragraph({ Title = "Good Karma Gained", Content = "0" }),
}

function H.setStat(key, title, value)
	local paragraph = U.stats[key]
	if paragraph then pcall(function() paragraph:Set({ Title = title, Content = value }) end) end
end

H.spawn(function()
	local leaderstats = LocalPlayer:WaitForChild("leaderstats", 30)
	local sources = {
		{ "strength", "Strength Gained", leaderstats and leaderstats:WaitForChild("Strength", 15) },
		{ "kills", "Kills Gained", leaderstats and leaderstats:WaitForChild("Kills", 15) },
		{ "durability", "Durability Gained", LocalPlayer:WaitForChild("Durability", 15) },
		{ "agility", "Agility Gained", LocalPlayer:WaitForChild("Agility", 15) },
		{ "evil", "Evil Karma Gained", LocalPlayer:FindFirstChild("evilKarma") },
		{ "good", "Good Karma Gained", LocalPlayer:FindFirstChild("goodKarma") },
	}
	for _, entry in ipairs(sources) do
		local value = entry[3]
		if value then
			local start = value.Value
			H.track(value.Changed:Connect(function()
				if alive() then H.setStat(entry[1], entry[2], H.short(value.Value - start)) end
			end))
		end
	end
	local started = os.clock()
	while alive() do
		local spent = math.floor(os.clock() - started)
		H.setStat("time", "Time", string.format("%02d:%02d:%02d", spent // 3600, (spent % 3600) // 60, spent % 60))
		task.wait(1)
	end
end)

function H.refreshPlayers()
	if U.targetDropdown and U.targetDropdown.SetOptions then
		pcall(function() U.targetDropdown:SetOptions(H.playerNames()) end)
	end
end
H.track(Players.PlayerAdded:Connect(function() if alive() then H.refreshPlayers() end end))
H.track(Players.PlayerRemoving:Connect(function() if alive() then task.defer(H.refreshPlayers) end end))

local SaveManager = Library.SaveManager
local InterfaceManager = Library.InterfaceManager
local ThemeManager = Library.ThemeManager

SaveManager:SetLibrary(Library)
InterfaceManager:SetLibrary(Library)
InterfaceManager:SetWindow(Window)
ThemeManager:SetLibrary(Library)

SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({ "ml_target", "ml_kill_target", "ml_kill_all", "ml_whitelist_input" })
InterfaceManager:SetFolder("Facility")
ThemeManager:SetFolder("Facility")
SaveManager:SetFolder("Facility/1268927906")

InterfaceManager:BuildInterfaceSection(U.Settings, 1)
SaveManager:BuildConfigSection(U.Settings, 2)
ThemeManager:Mount(Window)

Window:SetTab(U.Farm)

if #moduleErrors > 0 then
	task.delay(1, function()
		for _, message in ipairs(moduleErrors) do
			Library:Notify({ Title = "Facility", Text = message, Duration = 20, Style = "Error" })
		end
	end)
end

Library:Notify("Facility", "Muscle Legends loaded.", 4)

SaveManager:LoadAutoloadConfig()
ThemeManager:Load()
