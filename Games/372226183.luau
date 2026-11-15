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

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

local H = {}
local U = {}
local S = {
	connections = {},
	threads = {},
	highlights = { Computer = {}, FreezePod = {}, ExitDoor = {}, Closet = {}, Vent = {} },
	playerHighlights = {},
	pods = {},
	lastPodScan = 0,
	lastComputerTeleport = 0,
	lastHackDone = 0,
}
local F = {
	playerEsp = false,
	Computer = false,
	FreezePod = false,
	ExitDoor = false,
	Closet = false,
	Vent = false,
	autoHack = true,
	fastCrawl = false,
	crawlSpeed = 26,
	antiRope = false,
	antiAfk = true,
}

local COMPUTER_COOLDOWN = 2.5
local AFTER_HACK_DELAY = 1.9
local CLOSET_WORDS = { "closet", "locker", "wardrobe", "cabinet" }

local COLORS = {
	beast = Color3.fromRGB(255, 60, 60),
	survivor = Color3.fromRGB(255, 255, 255),
	computerTodo = Color3.fromRGB(0, 150, 255),
	computerDone = Color3.fromRGB(0, 255, 0),
	FreezePod = Color3.fromRGB(0, 200, 255),
	ExitDoor = Color3.fromRGB(255, 255, 0),
	Closet = Color3.fromRGB(139, 69, 19),
	Vent = Color3.fromRGB(128, 128, 128),
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

function H.notify(text, duration)
	pcall(function() Library:Notify("Facility", text, duration or 3) end)
end

function H.root()
	local character = LocalPlayer.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

function H.teleport(cframe)
	local root = H.root()
	if not root then return false end
	root.CFrame = cframe
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	return true
end

function H.isBeast(player)
	local stats = player:FindFirstChild("TempPlayerStatsModule")
		or (player.Character and player.Character:FindFirstChild("TempPlayerStatsModule"))
	local flag = stats and stats:FindFirstChild("IsBeast")
	return flag ~= nil and flag.Value == true
end

function H.gameRemote()
	return ReplicatedStorage:FindFirstChild("RemoteEvent")
end

function H.computerColor(screen)
	if not screen then return COLORS.computerDone end
	if screen.BrickColor == BrickColor.new("Bright blue") then return COLORS.computerTodo end
	if screen.BrickColor == BrickColor.new("Dark green") then return COLORS.computerDone end
	local color = screen.Color
	return (color.B > 0.5 and color.R < 0.5) and COLORS.computerTodo or COLORS.computerDone
end

function H.computerTodo(computer)
	local done = computer:GetAttribute("Completed")
	if done == nil then done = computer:GetAttribute("Done") end
	if done == nil then done = computer:GetAttribute("IsComplete") end
	if done ~= nil then return not done end
	local progress = computer:GetAttribute("Progress")
	if progress ~= nil then return progress < 100 end
	local fire = computer:FindFirstChild("Fire") or computer:FindFirstChild("FirePart")
	if fire then
		if fire:IsA("Fire") and fire.Enabled then return true end
		if fire:IsA("BasePart") and fire.Transparency < 1 then return true end
	end
	local screen = computer:FindFirstChild("Screen")
	if not screen then return false end
	return H.computerColor(screen) == COLORS.computerTodo
end

function H.isClosetName(name)
	local lower = name:lower()
	for _, word in ipairs(CLOSET_WORDS) do
		if lower:find(word, 1, true) then return true end
	end
	return false
end

function H.isHidePrompt(prompt)
	local action = (prompt.ActionText or ""):lower()
	local object = (prompt.ObjectText or ""):lower()
	return action:find("hide", 1, true) or object:find("locker", 1, true) or object:find("closet", 1, true)
end

function H.promptOwner(prompt)
	local parent = prompt.Parent
	if not parent then return nil end
	if parent:IsA("Model") then return parent end
	local current = parent
	for _ = 1, 4 do
		current = current.Parent
		if not current or current == workspace then break end
		if current:IsA("Model") then return current end
	end
	if parent:IsA("BasePart") then return parent end
	return nil
end

function H.closetCFrame(object)
	local cframe
	for _, item in ipairs(object:GetDescendants()) do
		if item:IsA("ProximityPrompt") then
			local parent = item.Parent
			if parent and parent:IsA("BasePart") then
				cframe = parent.CFrame
			elseif parent and parent:IsA("Attachment") and parent.Parent and parent.Parent:IsA("BasePart") then
				cframe = parent.Parent.CFrame
			end
			if cframe then break end
		end
	end
	if not cframe then
		for _, name in ipairs({ "Handle", "Door", "Front", "Entry", "Open", "Face", "Panel" }) do
			local part = object:FindFirstChild(name, true)
			if part and part:IsA("BasePart") then
				cframe = part.CFrame
				break
			end
		end
	end
	if not cframe and object:IsA("Model") then
		local ok, pivot = pcall(object.GetPivot, object)
		if ok then cframe = pivot end
	end
	if not cframe and object:IsA("BasePart") then cframe = object.CFrame end
	if not cframe then
		local part = object:FindFirstChildWhichIsA("BasePart", true)
		if part then cframe = part.CFrame end
	end
	if not cframe then return nil end
	local look = Vector3.new(cframe.LookVector.X, 0, cframe.LookVector.Z)
	if look.Magnitude < 0.01 then look = Vector3.new(0, 0, 1) end
	local origin = cframe.Position + Vector3.new(0, 3, 0)
	return CFrame.lookAt(origin, origin + look.Unit)
end

function H.closets()
	local result, seen = {}, {}
	for _, object in ipairs(workspace:GetDescendants()) do
		if (object:IsA("Model") or object:IsA("BasePart")) and not seen[object] and H.isClosetName(object.Name) then
			local cframe = H.closetCFrame(object)
			if cframe then
				seen[object] = true
				table.insert(result, { model = object, cframe = cframe })
			end
		end
	end
	if #result == 0 then
		for _, object in ipairs(workspace:GetDescendants()) do
			if object:IsA("ProximityPrompt") and H.isHidePrompt(object) then
				local owner = H.promptOwner(object)
				if owner and not seen[owner] then
					local cframe = H.closetCFrame(owner)
					if cframe then
						seen[owner] = true
						table.insert(result, { model = owner, cframe = cframe })
					end
				end
			end
		end
	end
	return result
end

function H.mark(object, category, color)
	local name = "FacilityMark_" .. category
	local existing = object:FindFirstChild(name)
	if existing then
		existing.FillColor = color
		return
	end
	local highlight = Instance.new("Highlight")
	highlight.Name = name
	highlight.Adornee = object
	highlight.FillColor = color
	highlight.OutlineColor = color
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = object
	table.insert(S.highlights[category], highlight)
end

function H.clear(category)
	for _, highlight in ipairs(S.highlights[category]) do
		pcall(function() highlight:Destroy() end)
	end
	S.highlights[category] = {}
end

function H.categoryOf(object)
	local name = object.Name
	if name == "ComputerTable" then return "Computer" end
	if name == "FreezePod" then return "FreezePod" end
	if name == "ExitDoor" then return "ExitDoor" end
	if name == "AirVent" or name == "Vent" then return "Vent" end
	return nil
end

function H.markObject(object)
	local category = H.categoryOf(object)
	if category and F[category] then
		if category == "Computer" then
			H.mark(object, category, H.computerColor(object:FindFirstChild("Screen")))
		else
			H.mark(object, category, COLORS[category])
		end
		return
	end
	if F.Closet then
		if (object:IsA("Model") or object:IsA("BasePart")) and H.isClosetName(object.Name) then
			H.mark(object, "Closet", COLORS.Closet)
		elseif object:IsA("ProximityPrompt") and H.isHidePrompt(object) then
			local owner = H.promptOwner(object)
			if owner then H.mark(owner, "Closet", COLORS.Closet) end
		end
	end
end

function H.scan(category)
	H.clear(category)
	if not F[category] then return end
	if category == "Closet" then
		for _, closet in ipairs(H.closets()) do H.mark(closet.model, "Closet", COLORS.Closet) end
		return
	end
	for _, object in ipairs(workspace:GetDescendants()) do
		if H.categoryOf(object) == category then H.markObject(object) end
	end
end

function H.playerMark(player)
	if player == LocalPlayer then return end
	local character = player.Character
	if not character then return end
	local highlight = S.playerHighlights[player]
	if not highlight or highlight.Parent ~= character then
		if highlight then pcall(function() highlight:Destroy() end) end
		highlight = Instance.new("Highlight")
		highlight.Name = "FacilityMark_Player"
		highlight.Adornee = character
		highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		highlight.Parent = character
		S.playerHighlights[player] = highlight
	end
	local color = H.isBeast(player) and COLORS.beast or COLORS.survivor
	highlight.FillColor = color
	highlight.OutlineColor = color
end

function H.clearPlayers()
	for player, highlight in pairs(S.playerHighlights) do
		pcall(function() highlight:Destroy() end)
		S.playerHighlights[player] = nil
	end
end

function H.refreshPlayers()
	if not F.playerEsp then
		H.clearPlayers()
		return
	end
	for _, player in ipairs(Players:GetPlayers()) do H.playerMark(player) end
end

function H.pods()
	local now = os.clock()
	if now - S.lastPodScan < 1 then return S.pods end
	S.lastPodScan = now
	local list = {}
	for _, object in ipairs(workspace:GetDescendants()) do
		if object.Name == "FreezePod" then
			local root = (object:IsA("Model") and object.PrimaryPart) or object:FindFirstChildWhichIsA("BasePart")
			if root then table.insert(list, { model = object, root = root }) end
		end
	end
	S.pods = list
	return list
end

function H.capturedPod(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or humanoid.Health <= 0 then return nil end
	local held = root.Anchored
	if not held then
		for _, name in ipairs({ "Frozen", "Captured", "IsFrozen", "IsCaptured", "FrozenPlayer" }) do
			if character:GetAttribute(name) == true or root:GetAttribute(name) == true then
				held = true
				break
			end
		end
	end
	if not held then
		local state = humanoid:GetState()
		held = state == Enum.HumanoidStateType.Physics or state == Enum.HumanoidStateType.PlatformStanding
			or state == Enum.HumanoidStateType.GettingUp or state == Enum.HumanoidStateType.Ragdoll
			or humanoid.WalkSpeed <= 1
	end
	if not held then return nil end
	for _, pod in ipairs(H.pods()) do
		if (pod.root.Position - root.Position).Magnitude < 10 then return pod.model end
	end
	return nil
end

function H.rescue()
	local target, pod
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer then
			pod = H.capturedPod(player)
			if pod then
				target = player
				break
			end
		end
	end
	if not target then
		H.notify("No frozen player found.")
		return
	end
	local root = H.root()
	local podRoot = (pod:IsA("Model") and pod.PrimaryPart) or pod:FindFirstChildWhichIsA("BasePart")
	if not root or not podRoot then return end

	local spot = CFrame.new(podRoot.Position + Vector3.new(0, 3, 0))
	H.teleport(spot)
	task.wait(0.2)
	H.teleport(spot)
	task.wait(0.15)
	root = H.root()
	if not root then return end
	local direction = Vector3.new(podRoot.Position.X - root.Position.X, 0, podRoot.Position.Z - root.Position.Z)
	if direction.Magnitude > 0.1 then root.CFrame = CFrame.lookAt(root.Position, root.Position + direction.Unit) end

	local interacted = false
	local trigger = pod:FindFirstChild("PodTrigger", true)
	local event = trigger and trigger:FindFirstChild("Event")
	local remote = H.gameRemote()
	if event and remote then
		pcall(function() remote:FireServer("Input", "Trigger", false, event) end)
		interacted = true
	end
	if firetouchinterest then
		pcall(firetouchinterest, root, podRoot, 0)
		task.wait(0.05)
		pcall(firetouchinterest, root, podRoot, 1)
	end
	task.wait(0.1)
	for _, item in ipairs(pod:GetDescendants()) do
		if item:IsA("ProximityPrompt") and fireproximityprompt then
			pcall(function()
				item.HoldDuration = 0
				item.RequiresLineOfSight = false
				fireproximityprompt(item)
			end)
			interacted = true
		elseif item:IsA("ClickDetector") and fireclickdetector then
			pcall(fireclickdetector, item)
			interacted = true
		end
	end
	H.notify(interacted and ("Rescue attempted on " .. target.Name .. ".") or ("Reached " .. target.Name .. " but found nothing to use."))
end

function H.nearest(list)
	local root = H.root()
	if not root then return nil end
	local best, bestDistance
	for _, entry in ipairs(list) do
		local distance = (root.Position - entry.position).Magnitude
		if not bestDistance or distance < bestDistance then best, bestDistance = entry, distance end
	end
	return best
end

function H.toComputer()
	local now = os.clock()
	local sinceHack = now - S.lastHackDone
	if sinceHack < AFTER_HACK_DELAY then
		H.notify(string.format("Wait %.1fs after finishing a computer.", AFTER_HACK_DELAY - sinceHack), 2)
		return
	end
	local remaining = COMPUTER_COOLDOWN - (now - S.lastComputerTeleport)
	if remaining > 0 then
		H.notify(string.format("Wait %.1fs before the next computer.", remaining), 2)
		return
	end
	local list = {}
	for _, object in ipairs(workspace:GetDescendants()) do
		if object.Name == "ComputerTable" then
			local screen = object:FindFirstChild("Screen")
			if screen and H.computerTodo(object) then table.insert(list, { position = screen.Position }) end
		end
	end
	local target = H.nearest(list)
	if not target then
		H.notify("Every computer is already done.")
		return
	end
	local spot = CFrame.new(target.position + Vector3.new(0, 2, 2.5))
	task.wait(0.8)
	H.teleport(spot)
	task.wait(0.3)
	H.teleport(spot)
	S.lastComputerTeleport = os.clock()
end

function H.toCloset()
	local list = {}
	for _, closet in ipairs(H.closets()) do
		table.insert(list, { position = closet.cframe.Position, cframe = closet.cframe })
	end
	local target = H.nearest(list)
	if not target then
		H.notify("No hiding spot found.")
		return
	end
	H.teleport(target.cframe)
	task.wait(0.15)
	H.teleport(target.cframe)
end

function H.toNamed(name, partName)
	local list = {}
	for _, object in ipairs(workspace:GetDescendants()) do
		if object.Name == name then
			local part = object:FindFirstChild(partName)
			if part and part:IsA("BasePart") then table.insert(list, { position = part.Position }) end
		end
	end
	local target = H.nearest(list)
	if target then
		H.teleport(CFrame.new(target.position + Vector3.new(0, 3, 0)))
	else
		H.notify("Nothing found on this map.")
	end
end

function H.toBucket()
	for _, object in ipairs(workspace:GetDescendants()) do
		if object.Name == "Bucket" and object:IsA("Model")
			and (object:FindFirstChild("CandyBucketScript") or (object.Parent and object.Parent.Name:find("Facility"))) then
			local part = object.PrimaryPart or object:FindFirstChildWhichIsA("BasePart")
			if part then
				H.teleport(CFrame.new(part.Position + Vector3.new(0, 3, 0)))
				return
			end
		end
	end
	H.notify("No event bucket on this map.")
end

H.track(workspace.DescendantAdded:Connect(function(object)
	if not alive() then return end
	if F.Computer or F.FreezePod or F.ExitDoor or F.Vent or F.Closet then H.markObject(object) end
end))

H.track(Players.PlayerRemoving:Connect(function(player)
	local highlight = S.playerHighlights[player]
	if highlight then pcall(function() highlight:Destroy() end) end
	S.playerHighlights[player] = nil
end))

H.spawn(function()
	while alive() do
		task.wait(2)
		if F.playerEsp then H.refreshPlayers() end
		if F.Computer then
			for _, highlight in ipairs(S.highlights.Computer) do
				local screen = highlight.Parent and highlight.Parent:FindFirstChild("Screen")
				if screen and screen:IsA("BasePart") then highlight.FillColor = H.computerColor(screen) end
			end
		end
	end
end)

H.spawn(function()
	while alive() do
		if F.autoHack then
			local remote = H.gameRemote()
			if remote then pcall(remote.FireServer, remote, "SetPlayerMinigameResult", true) end
		end
		task.wait(0.1)
	end
end)

H.track(RunService.Heartbeat:Connect(function()
	if not alive() then return end
	local character = LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	if F.fastCrawl then
		local speed = humanoid.WalkSpeed
		local state = humanoid:GetState()
		local crawling = (speed > 0 and speed <= 12) or (humanoid.HipHeight > 0 and humanoid.HipHeight <= 1.5)
			or state == Enum.HumanoidStateType.Physics or state == Enum.HumanoidStateType.Ragdoll
			or state == Enum.HumanoidStateType.GettingUp
		if crawling and speed < F.crawlSpeed then humanoid.WalkSpeed = F.crawlSpeed end
	end

	if F.antiRope and not H.isBeast(LocalPlayer) then
		local state = humanoid:GetState()
		if state == Enum.HumanoidStateType.Physics or state == Enum.HumanoidStateType.PlatformStanding
			or state == Enum.HumanoidStateType.Ragdoll or state == Enum.HumanoidStateType.GettingUp then
			humanoid:ChangeState(Enum.HumanoidStateType.Running)
			humanoid.PlatformStand = false
			local root = character:FindFirstChild("HumanoidRootPart")
			if root then
				root.AssemblyLinearVelocity = Vector3.zero
				root.AssemblyAngularVelocity = Vector3.zero
			end
		end
		for _, item in ipairs(character:GetDescendants()) do
			if item:IsA("RopeConstraint") or item:IsA("AlignPosition") or item:IsA("AlignOrientation")
				or item:IsA("BodyPosition") or item:IsA("BodyVelocity") then
				pcall(function() item:Destroy() end)
			end
		end
	end
end))

pcall(function()
	local virtualUser = game:GetService("VirtualUser")
	H.track(LocalPlayer.Idled:Connect(function()
		if not alive() or not F.antiAfk then return end
		virtualUser:CaptureController()
		virtualUser:ClickButton2(Vector2.new())
	end))
end)

if not shared.FacilityFleeHook then
	shared.FacilityFleeHook = { autoHack = false, antiRope = false, onHack = nil }
	local state = shared.FacilityFleeHook
	if hookmetamethod and getnamecallmethod and newcclosure and checkcaller then
		local original
		original = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
			if (state.autoHack or state.antiRope) and not checkcaller() and getnamecallmethod() == "FireServer"
				and typeof(self) == "Instance" and self.Name == "RemoteEvent" then
				local args = table.pack(...)
				if args[1] == "SetPlayerMinigameResult" and state.autoHack then
					if state.onHack then pcall(state.onHack) end
					if args[2] == false then
						args[2] = true
						return self.FireServer(self, table.unpack(args, 1, args.n))
					end
				elseif args[1] == "Flop" and state.antiRope and not (state.isBeast and state.isBeast()) then
					return nil
				end
			end
			return original(self, ...)
		end))
	end
end

function H.syncHook()
	local state = shared.FacilityFleeHook
	state.autoHack = F.autoHack and alive()
	state.antiRope = F.antiRope and alive()
	state.isBeast = function() return H.isBeast(LocalPlayer) end
	state.onHack = function() S.lastHackDone = os.clock() end
end
H.syncHook()

shared.FacilityCleanup = function()
	for key, value in pairs(F) do
		if value == true then F[key] = false end
	end
	H.syncHook()
	shared.FacilityFleeHook.onHack = nil
	for _, connection in ipairs(S.connections) do pcall(function() connection:Disconnect() end) end
	table.clear(S.connections)
	for _, thread in ipairs(S.threads) do
		if thread ~= coroutine.running() then pcall(task.cancel, thread) end
	end
	table.clear(S.threads)
	for category in pairs(S.highlights) do H.clear(category) end
	H.clearPlayers()
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

U.Visuals = Window:Tab("Visuals", "eye")
U.Survivor = Window:Tab("Survivor", "shield")
U.Teleport = Window:Tab("Teleport", "navigation")
U.Player = Window:Tab("Player", "user")
Window:TabDivider()
U.Settings = Window:Tab("Settings", "settings")

local players = U.Visuals:Section("Players", 1)
players:Toggle({ Text = "Player Highlight", Flag = "ftf_player_esp", Default = false, Callback = function(v)
	F.playerEsp = v
	H.refreshPlayers()
end })
players:Label("Red is the beast, white are survivors.")

local map = U.Visuals:Section("Map", 2)
local mapEntries = {
	{ "Computer", "Computers", "Blue to hack, green done." },
	{ "FreezePod", "Freeze Pods" },
	{ "ExitDoor", "Exit Doors" },
	{ "Closet", "Hiding Spots" },
	{ "Vent", "Air Vents" },
}
for _, entry in ipairs(mapEntries) do
	map:Toggle({ Text = entry[2], Flag = "ftf_esp_" .. entry[1]:lower(), Default = false, Callback = function(v)
		F[entry[1]] = v
		if v then H.scan(entry[1]) else H.clear(entry[1]) end
	end })
	if entry[3] then map:Label(entry[3]) end
end

local hacking = U.Survivor:Section("Hacking", 1)
hacking:Toggle({ Text = "Never Fail Hacks", Flag = "ftf_auto_hack", Default = true, Callback = function(v)
	F.autoHack = v
	H.syncHook()
end })
hacking:Label("Turns failed hacking checks into successes.")

local escape = U.Survivor:Section("Escape", 2)
escape:Toggle({ Text = "Fast Crawl", Flag = "ftf_fast_crawl", Default = false, Callback = function(v)
	F.fastCrawl = v
end })
escape:Slider({ Text = "Crawl Speed", Flag = "ftf_crawl_speed", Min = 10, Max = 60, Default = 26, Callback = function(v)
	F.crawlSpeed = v
end })
escape:Toggle({ Text = "Anti Knockdown", Flag = "ftf_anti_rope", Default = false, Callback = function(v)
	F.antiRope = v
	H.syncHook()
end })
escape:Label("Stops the beast from knocking you down and breaks ropes.")

local rescue = U.Survivor:Section("Rescue", 1)
rescue:Button({ Text = "Free A Frozen Player", Callback = function() H.spawn(H.rescue) end })

local quick = U.Teleport:Section("Quick Teleport", 1)
quick:Button({ Text = "Nearest Computer To Hack", Callback = function() H.spawn(H.toComputer) end })
quick:Button({ Text = "Nearest Hiding Spot", Callback = function() H.spawn(H.toCloset) end })
quick:Button({ Text = "Nearest Exit", Callback = function() H.toNamed("ExitDoor", "ExitDoorTrigger") end })
quick:Button({ Text = "Nearest Freeze Pod", Callback = function() H.toNamed("FreezePod", "BasePart") end })
quick:Button({ Text = "Event Bucket", Callback = H.toBucket })

local utility = U.Player:Section("Utility", 1)
utility:Toggle({ Text = "Anti AFK", Flag = "ftf_anti_afk", Default = true, Callback = function(v)
	F.antiAfk = v
end })

local server = U.Player:Section("Server", 2)
server:Button({ Text = "Rejoin", Callback = function()
	pcall(function() TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer) end)
end })
server:Button({ Text = "New Server", Callback = function()
	pcall(function() TeleportService:Teleport(game.PlaceId, LocalPlayer) end)
end })

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
SaveManager:SetFolder("Facility/372226183")

InterfaceManager:BuildInterfaceSection(U.Settings, 1)
SaveManager:BuildConfigSection(U.Settings, 2)
ThemeManager:Mount(Window)

Window:SetTab(U.Visuals)

Library:Notify("Facility", "Flee the Facility loaded.", 4)

SaveManager:LoadAutoloadConfig()
ThemeManager:Load()
