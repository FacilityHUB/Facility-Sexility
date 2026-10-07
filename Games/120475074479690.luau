--!nocheck
--!nolint UnknownGlobal

local F       = shared.Facility
local Library = F.Library
local Entity  = F.Entity
local Esp     = F.Esp
local Webhook = F.Webhook

local MOVEMENT_URL = "https://raw.githubusercontent.com/FacilityHUB/Facility-Sexility/refs/heads/main/CModules/FMovement.luau"

local function fetchModule(url, label)
	local ok, result = pcall(function()
		return loadstring(game:HttpGet(url .. "?v=" .. tostring(tick()):gsub("%.", "")))()
	end)

	if not ok or type(result) ~= "table" then
		warn("Facility: could not load " .. label .. " from " .. url)
		return nil
	end

	return result
end

local Movement = fetchModule(MOVEMENT_URL, "movement")

if Movement then Movement:Load() end

F.Movement = Movement

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local Stats = game:GetService("Stats")

local LocalPlayer = Players.LocalPlayer

local RARITY_ORDER = {
	"Common", "Uncommon", "Rare", "Epic", "Legendary",
	"Mythic", "Cosmic", "Secret", "Eternal", "Divine",
}

local RARITY_RANK = {}
for index, name in ipairs(RARITY_ORDER) do
	RARITY_RANK[name] = index
end

local RARITY_CHOICES = { "Any" }
for _, name in ipairs(RARITY_ORDER) do
	table.insert(RARITY_CHOICES, name)
end

local RARITY_COLORS = {
	Common    = Color3.fromRGB(205, 210, 220),
	Uncommon  = Color3.fromRGB(120, 215, 135),
	Rare      = Color3.fromRGB(85, 160, 255),
	Epic      = Color3.fromRGB(185, 110, 255),
	Legendary = Color3.fromRGB(255, 190, 60),
	Mythic    = Color3.fromRGB(255, 85, 95),
	Cosmic    = Color3.fromRGB(130, 235, 255),
	Secret    = Color3.fromRGB(245, 245, 255),
	Eternal   = Color3.fromRGB(255, 140, 220),
	Divine    = Color3.fromRGB(255, 245, 170),
}

local cleanupTasks = {}

local function onCleanup(fn)
	table.insert(cleanupTasks, fn)
end

local function notify(title, text, style, duration)
	pcall(function()
		Library:Notify({
			Title = title,
			Text = tostring(text),
			Style = style or "info",
			Duration = duration or 5,
		})
	end)
end

local Game = { Status = "Idle" }

function Game.Character()
	local character = LocalPlayer.Character
	if character and character.Parent then return character end
	return nil
end

function Game.Humanoid()
	local character = Game.Character()
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then return humanoid end
	return nil
end

function Game.Root()
	local character = Game.Character()
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsDescendantOf(workspace) then return root end
	return nil
end

function Game.Teleport(cframe)
	local root = Game.Root()
	if not root or typeof(cframe) ~= "CFrame" then return false end

	local ok = pcall(function() root.CFrame = cframe end)
	return ok
end

local function safeZonePart()
	local map = workspace:FindFirstChild("Steal Map")
	local lobby = map and map:FindFirstChild("Lobby")
	local zone = lobby and lobby:FindFirstChild("safe zone")

	if zone and zone:IsA("BasePart") then return zone end
	if zone and zone:IsA("Model") then return zone.PrimaryPart or zone:FindFirstChildWhichIsA("BasePart", true) end

	return nil
end

local function anchorOf(instance)
	if not instance then return nil end
	if instance:IsA("BasePart") then return instance end
	if not instance:IsA("Model") then return nil end

	if instance.PrimaryPart and instance.PrimaryPart.Parent then return instance.PrimaryPart end

	local part = instance:FindFirstChildWhichIsA("BasePart", true)
	if not part then return nil end

	pcall(function() instance.PrimaryPart = part end)

	return part
end

local function positionOf(instance)
	local part = anchorOf(instance)
	if part then return part.Position end

	local ok, pivot = pcall(function() return instance:GetPivot().Position end)
	if ok then return pivot end

	return nil
end

local function tierOf(instance)
	if not instance then return nil end

	local raw = instance:GetAttribute("CrateTier")
	if type(raw) == "string" and RARITY_RANK[raw] then return raw end

	return nil
end

local function crateFromPrompt(prompt)
	local node = prompt.Parent
	local depth = 0

	while node and node ~= workspace and depth < 5 do
		if tierOf(node) then return node, tierOf(node) end
		node = node.Parent
		depth = depth + 1
	end

	node = prompt.Parent
	depth = 0

	while node and node ~= workspace and depth < 5 do
		if node:IsA("Model") and node.Parent and node.Parent.Name == "Crates" then
			return node, tierOf(node)
		end
		node = node.Parent
		depth = depth + 1
	end

	return nil, nil
end

local function promptIn(instance)
	if not instance then return nil end

	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("ProximityPrompt") then return descendant end
	end

	return nil
end

local function cratesFolder()
	return workspace:FindFirstChild("Crates")
end

local Prompts = {
	Global = false,
	Saved = {},
	Connections = {},
}

function Prompts:Patch(prompt)
	if typeof(prompt) ~= "Instance" or not prompt:IsA("ProximityPrompt") then return end
	if self.Saved[prompt] then return end

	local ok, saved = pcall(function()
		return {
			Distance = prompt.MaxActivationDistance,
			Hold = prompt.HoldDuration,
			Sight = prompt.RequiresLineOfSight,
			Enabled = prompt.Enabled,
		}
	end)

	if not ok or type(saved) ~= "table" then return end

	self.Saved[prompt] = saved

	pcall(function()
		prompt.MaxActivationDistance = 2000
		prompt.HoldDuration = 0
		prompt.RequiresLineOfSight = false
	end)
end

function Prompts:Restore(prompt)
	local saved = self.Saved[prompt]
	if not saved then return end

	self.Saved[prompt] = nil

	pcall(function()
		prompt.MaxActivationDistance = saved.Distance
		prompt.HoldDuration = saved.Hold
		prompt.RequiresLineOfSight = saved.Sight
	end)
end

function Prompts:RestoreAll()
	for prompt in pairs(self.Saved) do
		self:Restore(prompt)
	end

	table.clear(self.Saved)
end

function Prompts:SetGlobal(state)
	self.Global = state

	for _, connection in ipairs(self.Connections) do
		pcall(function() connection:Disconnect() end)
	end

	table.clear(self.Connections)

	if not state then
		self:RestoreAll()
		return
	end

	for _, descendant in ipairs(workspace:GetDescendants()) do
		if descendant:IsA("ProximityPrompt") then self:Patch(descendant) end
	end

	table.insert(self.Connections, workspace.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("ProximityPrompt") then
			task.defer(function() if self.Global then self:Patch(descendant) end end)
		end
	end))

	table.insert(self.Connections, ProximityPromptService.PromptShown:Connect(function(prompt)
		if self.Global then self:Patch(prompt) end
	end))
end

onCleanup(function()
	Prompts.Global = false
	Prompts:SetGlobal(false)
end)

local function fireable()
	return type(fireproximityprompt) == "function"
end

local function firePrompt(prompt)
	if not fireable() then return false end
	return pcall(fireproximityprompt, prompt)
end

local function userIdFromImage(image)
	if type(image) ~= "string" then return nil end

	local tagged = image:match("id=(%d+)")
	if tagged then return tonumber(tagged) end

	local loose = image:match("(%d%d%d%d+)")
	if loose then return tonumber(loose) end

	return nil
end

local Plots = {
	List = {},
	ByUser = {},
	Mine = nil,
	ScannedAt = 0,
}

local function plotSignOf(plot)
	local floor = plot:FindFirstChild("floor")
	local sign = floor and floor:FindFirstChild("PlotSign")
	return sign, floor
end

local function plotOwnerId(plot)
	local sign = plotSignOf(plot)
	local avatar = sign and sign:FindFirstChild("Avatar")

	if not avatar then return nil end

	local ok, image = pcall(function() return avatar.Image end)
	if not ok then return nil end

	return userIdFromImage(image)
end

function Plots:Scan(force)
	if not force and os.clock() - self.ScannedAt < 1.5 then return self.List end

	self.ScannedAt = os.clock()

	local list = {}
	local byUser = {}
	local mine = nil

	for _, child in ipairs(workspace:GetChildren()) do
		if child.Name:find("Plot Building") then
			local sign, floor = plotSignOf(child)

			if floor then
				local userId = plotOwnerId(child)
				local owner = userId and Players:GetPlayerByUserId(userId) or nil

				local record = {
					Plot = child,
					Floor = floor,
					Sign = sign,
					UserId = userId,
					Owner = owner,
					Name = owner and owner.Name or (userId and ("user " .. tostring(userId)) or "empty"),
					Mine = userId == LocalPlayer.UserId,
				}

				table.insert(list, record)

				if userId then byUser[userId] = record end
				if record.Mine then mine = record end
			end
		end
	end

	self.List = list
	self.ByUser = byUser
	self.Mine = mine

	return list
end

function Plots:MyPlot()
	if self.Mine and self.Mine.Plot.Parent then return self.Mine end

	self:Scan(true)

	return self.Mine
end

local function plotContents(record)
	local floor = record and record.Floor
	if not floor then return 0, nil, 0, {} end

	local count = 0
	local score = 0
	local best = nil
	local bestRank = 0
	local crates = {}

	for _, descendant in ipairs(floor:GetDescendants()) do
		local tier = tierOf(descendant)

		if tier then
			local rank = RARITY_RANK[tier] or 0

			count = count + 1
			score = score + rank
			table.insert(crates, { Model = descendant, Tier = tier, Rank = rank })

			if rank > bestRank then
				bestRank = rank
				best = tier
			end
		end
	end

	return count, best, score, crates
end

local Steal = {
	Enabled = false,
	Tiers = {},
	MinRank = 0,
	World = true,
	FromPlots = false,
	Mode = "Teleport",
	Priority = "Highest Tier",
	Return = "Safe Zone",
	Grab = 1.2,
	Cooldown = 1,
	Height = 20,
	Notify = true,
	Hook = false,
	Grabbed = 0,
	Last = "-",
	Running = false,
}

local function tierAllowed(tier)
	if next(Steal.Tiers) ~= nil then
		return tier ~= nil and Steal.Tiers[tier] == true
	end

	if not tier then return Steal.MinRank <= 0 end

	return (RARITY_RANK[tier] or 0) >= Steal.MinRank
end

local function worldCandidates(out)
	local folder = cratesFolder()
	if not folder then return end

	for _, descendant in ipairs(folder:GetDescendants()) do
		if descendant:IsA("ProximityPrompt") and descendant.Enabled then
			local crate, tier = crateFromPrompt(descendant)

			if crate and tierAllowed(tier) then
				local position = positionOf(descendant.Parent) or positionOf(crate)

				if position then
					table.insert(out, {
						Prompt = descendant,
						Crate = crate,
						Tier = tier or "Unknown",
						Rank = tier and RARITY_RANK[tier] or 0,
						Position = position,
						Source = "world",
						Owner = "-",
					})
				end
			end
		end
	end
end

local function plotCandidates(out)
	for _, record in ipairs(Plots:Scan()) do
		if not record.Mine then
			for _, descendant in ipairs(record.Floor:GetDescendants()) do
				if descendant:IsA("ProximityPrompt") and descendant.Enabled then
					local node = descendant.Parent
					local tier = nil
					local depth = 0

					while node and node ~= record.Floor and depth < 5 do
						tier = tierOf(node)
						if tier then break end
						node = node.Parent
						depth = depth + 1
					end

					if tier and tierAllowed(tier) then
						local position = positionOf(descendant.Parent) or positionOf(node)

						if position then
							table.insert(out, {
								Prompt = descendant,
								Crate = node,
								Tier = tier or "Unknown",
								Rank = tier and RARITY_RANK[tier] or 0,
								Position = position,
								Source = "plot",
								Owner = record.Name,
							})
						end
					end
				end
			end
		end
	end
end

local function pickTarget()
	local candidates = {}

	if Steal.World then pcall(worldCandidates, candidates) end
	if Steal.FromPlots then pcall(plotCandidates, candidates) end

	if #candidates == 0 then return nil end

	local root = Game.Root()
	local origin = root and root.Position or Vector3.zero

	for _, candidate in ipairs(candidates) do
		candidate.Distance = (candidate.Position - origin).Magnitude
	end

	if Steal.Priority == "Closest" then
		table.sort(candidates, function(a, b) return a.Distance < b.Distance end)
	elseif Steal.Priority == "Lowest Tier" then
		table.sort(candidates, function(a, b)
			if a.Rank ~= b.Rank then return a.Rank < b.Rank end
			return a.Distance < b.Distance
		end)
	else
		table.sort(candidates, function(a, b)
			if a.Rank ~= b.Rank then return a.Rank > b.Rank end
			return a.Distance < b.Distance
		end)
	end

	return candidates[1]
end

local StealHook = nil

local function reportSteal(target)
	Steal.Grabbed = Steal.Grabbed + 1
	Steal.Last = target.Tier .. (target.Source == "plot" and (" from " .. target.Owner) or "")

	if Steal.Notify then
		notify("Steal", Steal.Last, "success", 3)
	end

	if Steal.Hook and StealHook then
		pcall(function()
			StealHook:Embed({
				Title = "Crate stolen",
				Color = RARITY_COLORS[target.Tier],
				Fields = {
					{ Name = "Tier", Value = target.Tier, Inline = true },
					{ Name = "Source", Value = target.Source == "plot" and target.Owner or "world", Inline = true },
					{ Name = "Total", Value = tostring(Steal.Grabbed), Inline = true },
				},
				Footer = "Steal From The Rich",
			})
		end)
	end
end

local function returnHome(saved)
	if Steal.Return == "None" then return end

	if Steal.Return == "Previous" and saved then
		Game.Teleport(saved)
		return
	end

	if Steal.Return == "My Plot" then
		local mine = Plots:MyPlot()
		local part = mine and anchorOf(mine.Floor)

		if part then
			Game.Teleport(CFrame.new(part.Position + Vector3.new(0, 6, 0)))
			return
		end
	end

	local zone = safeZonePart()

	if zone then
		Game.Teleport(zone.CFrame * CFrame.new(0, Steal.Height, 0))
	elseif saved then
		Game.Teleport(saved)
	end
end

local function stealOnce()
	local target = pickTarget()

	if not target then
		Game.Status = "No crate"
		return false
	end

	Game.Status = "Stealing " .. target.Tier

	if Steal.Mode == "Reach" then
		Prompts:Patch(target.Prompt)
		task.wait(0.05)

		if not target.Prompt.Parent then return false end

		firePrompt(target.Prompt)
		task.wait(0.15)
		reportSteal(target)

		return true
	end

	local root = Game.Root()
	if not root then return false end

	local saved = root.CFrame

	Game.Teleport(CFrame.new(target.Position))
	task.wait(math.clamp(Steal.Grab, 0.1, 6))

	if not target.Prompt.Parent then
		returnHome(saved)
		return false
	end

	firePrompt(target.Prompt)
	task.wait(0.2)

	reportSteal(target)
	returnHome(saved)

	return true
end

task.spawn(function()
	while true do
		task.wait(0.2)

		if Steal.Enabled and fireable() then
			Steal.Running = true

			local ok, err = pcall(stealOnce)

			if not ok then
				Game.Status = "Steal error"
				warn("Facility steal: " .. tostring(err))
			end

			Steal.Running = false

			task.wait(math.clamp(Steal.Cooldown, 0, 10))
		elseif Steal.Enabled then
			Game.Status = "No fireproximityprompt"
			task.wait(2)
		end
	end
end)

onCleanup(function() Steal.Enabled = false end)

local Place = {
	Enabled = false,
	Layout = "Grid",
	Spacing = 7,
	Rotation = 0,
	Height = 2.7,
	All = true,
	Delay = 0.35,
	Index = 0,
	Placed = 0,
}

local function placeRemote()
	return ReplicatedStorage:FindFirstChild("re_PLACE_AT")
end

local function crateTool()
	local character = Game.Character()

	if character then
		for _, item in ipairs(character:GetChildren()) do
			if item:IsA("Tool") and item.Name:find("Crate") then return item end
		end
	end

	local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")

	if backpack then
		for _, item in ipairs(backpack:GetChildren()) do
			if item:IsA("Tool") and item.Name:find("Crate") then return item end
		end
	end

	return nil
end

local function crateToolCount()
	local count = 0
	local character = Game.Character()

	if character then
		for _, item in ipairs(character:GetChildren()) do
			if item:IsA("Tool") and item.Name:find("Crate") then count = count + 1 end
		end
	end

	local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")

	if backpack then
		for _, item in ipairs(backpack:GetChildren()) do
			if item:IsA("Tool") and item.Name:find("Crate") then count = count + 1 end
		end
	end

	return count
end

local function placementPoint(floor)
	local size = floor.Size
	local spacing = math.clamp(Place.Spacing, 2, 40)

	if Place.Layout == "Center" then
		local world = floor.Position
		return Vector3.new(world.X, Place.Height, world.Z)
	end

	if Place.Layout == "Random" then
		local x = (math.random() * size.X) - (size.X / 2)
		local z = (math.random() * size.Z) - (size.Z / 2)
		local world = floor.CFrame:PointToWorldSpace(Vector3.new(x, 0, z))
		return Vector3.new(world.X, Place.Height, world.Z)
	end

	local columns = math.max(1, math.floor((size.X - spacing) / spacing))
	local rows = math.max(1, math.floor((size.Z - spacing) / spacing))

	Place.Index = (Place.Index % (columns * rows)) + 1

	local slot = Place.Index - 1
	local column = slot % columns
	local row = math.floor(slot / columns)

	local x = -size.X / 2 + spacing / 2 + column * spacing
	local z = -size.Z / 2 + spacing / 2 + row * spacing

	local world = floor.CFrame:PointToWorldSpace(Vector3.new(x, 0, z))

	return Vector3.new(world.X, Place.Height, world.Z)
end

local function placeOnce()
	local remote = placeRemote()
	if not remote then
		Game.Status = "re_PLACE_AT missing"
		return false
	end

	local mine = Plots:MyPlot()
	local floor = mine and mine.Floor
	if not floor or not floor:IsA("BasePart") then
		Game.Status = "Plot not found"
		return false
	end

	local humanoid = Game.Humanoid()
	local root = Game.Root()
	if not humanoid or not root then return false end

	local tool = crateTool()
	if not tool then return false end

	if tool.Parent ~= Game.Character() then
		pcall(function() humanoid:EquipTool(tool) end)
		task.wait(0.2)
	end

	Game.Status = "Placing"

	Game.Teleport(CFrame.new(floor.Position) * CFrame.new(0, 5, 0))
	task.wait(0.2)

	local point = placementPoint(floor)

	pcall(function() remote:FireServer(point, math.floor(Place.Rotation)) end)

	Place.Placed = Place.Placed + 1

	task.wait(math.clamp(Place.Delay, 0.1, 3))

	return true
end

task.spawn(function()
	while true do
		task.wait(0.4)

		if Place.Enabled then
			local ok = pcall(function()
				if Place.All then
					local guard = 0

					while Place.Enabled and crateTool() and guard < 25 do
						guard = guard + 1
						if not placeOnce() then break end
					end
				else
					placeOnce()
				end
			end)

			if not ok then Game.Status = "Place error" end
		end
	end
end)

onCleanup(function() Place.Enabled = false end)

local Open = {
	Enabled = false,
	Tiers = {},
	Teleport = true,
	Delay = 0.4,
	Opened = 0,
}

local function appraisingOf(prompt)
	local node = prompt.Parent
	local depth = 0

	while node and depth < 5 do
		if node.Name == "AppraisingCrate" then return node end
		node = node.Parent
		depth = depth + 1
	end

	return nil
end

local function openAllowed(model)
	if next(Open.Tiers) == nil then return true end

	local tier = tierOf(model)

	if not tier then
		for _, descendant in ipairs(model:GetDescendants()) do
			tier = tierOf(descendant)
			if tier then break end
		end
	end

	if not tier then return true end

	return Open.Tiers[tier] == true
end

local function openOnce()
	local mine = Plots:MyPlot()
	local floor = mine and mine.Floor
	if not floor then return false end

	local opened = false

	for _, descendant in ipairs(floor:GetDescendants()) do
		if not Open.Enabled then break end

		if descendant:IsA("ProximityPrompt") and descendant.Enabled then
			local crate = appraisingOf(descendant)

			if crate and openAllowed(crate) then
				Game.Status = "Appraising"

				if Open.Teleport then
					local position = positionOf(descendant.Parent) or positionOf(crate)
					if position then Game.Teleport(CFrame.new(position)) end
				else
					Prompts:Patch(descendant)
				end

				if firePrompt(descendant) then
					Open.Opened = Open.Opened + 1
					opened = true
				end

				task.wait(math.clamp(Open.Delay, 0.1, 3))
			end
		end
	end

	return opened
end

task.spawn(function()
	while true do
		task.wait(0.5)

		if Open.Enabled and fireable() then
			pcall(openOnce)
		end
	end
end)

onCleanup(function() Open.Enabled = false end)

local Equip = {
	Enabled = false,
	Interval = 2,
}

local function equipBestButton()
	local gui = LocalPlayer:FindFirstChild("PlayerGui")
	local root = gui and gui:FindFirstChild("Gui")
	local main = root and root:FindFirstChild("Main")
	local frames = main and main:FindFirstChild("Frames")
	local items = frames and frames:FindFirstChild("Items")

	return items and items:FindFirstChild("EquipBest") or nil
end

task.spawn(function()
	while true do
		task.wait(math.clamp(Equip.Interval, 0.5, 30))

		if Equip.Enabled and type(getconnections) == "function" then
			pcall(function()
				local button = equipBestButton()
				if not button then return end

				for _, connection in ipairs(getconnections(button.Activated)) do
					pcall(function() connection:Fire() end)
					task.wait(0.15)
				end
			end)
		end
	end
end)

onCleanup(function() Equip.Enabled = false end)

local Defense = {
	Enabled = false,
	Radius = 70,
	Notify = true,
	Hook = false,
	Seen = {},
	Intruders = 0,
}

task.spawn(function()
	while true do
		task.wait(1)

		if Defense.Enabled then
			pcall(function()
				local mine = Plots:MyPlot()
				local floor = mine and mine.Floor
				if not floor then return end

				local center = floor.Position
				local radius = math.clamp(Defense.Radius, 10, 400)
				local now = os.clock()
				local count = 0

				for _, player in ipairs(Players:GetPlayers()) do
					if player ~= LocalPlayer then
						local character = player.Character
						local root = character and character:FindFirstChild("HumanoidRootPart")

						if root and (root.Position - center).Magnitude <= radius then
							count = count + 1

							local last = Defense.Seen[player] or 0

							if now - last > 20 then
								Defense.Seen[player] = now

								if Defense.Notify then
									notify("Plot", player.Name .. " is on your plot", "warning", 6)
								end

								if Defense.Hook and StealHook then
									pcall(function()
										StealHook:Embed({
											Title = "Intruder on your plot",
											Color = Color3.fromRGB(255, 90, 90),
											Fields = {
												{ Name = "Player", Value = player.Name, Inline = true },
												{ Name = "Distance", Value = string.format("%.0f", (root.Position - center).Magnitude), Inline = true },
											},
										})
									end)
								end
							end
						end
					end
				end

				Defense.Intruders = count
			end)
		end
	end
end)

onCleanup(function() Defense.Enabled = false end)

local Scanner = {
	Ranked = {},
	Interval = 2,
	Cursor = 0,
	Running = true,
}

local function rankPlots()
	local ranked = {}

	for _, record in ipairs(Plots:Scan(true)) do
		local count, best, score = plotContents(record)

		table.insert(ranked, {
			Record = record,
			Name = record.Name,
			Mine = record.Mine,
			Count = count,
			Best = best,
			BestRank = best and RARITY_RANK[best] or 0,
			Score = score,
		})
	end

	table.sort(ranked, function(a, b)
		if a.Score ~= b.Score then return a.Score > b.Score end
		return a.Count > b.Count
	end)

	Scanner.Ranked = ranked

	return ranked
end

task.spawn(function()
	while Scanner.Running do
		task.wait(math.clamp(Scanner.Interval, 1, 15))
		pcall(rankPlots)
	end
end)

onCleanup(function() Scanner.Running = false end)

local function teleportToPlot(entry)
	local record = entry and entry.Record
	local floor = record and record.Floor

	if not floor then
		notify("Scanner", "That plot is gone.", "error", 4)
		return
	end

	Game.Teleport(CFrame.new(floor.Position + Vector3.new(0, 8, 0)))
end

local PLAYER_TEAMS = { "enemy", "friendly", "whitelist" }

local function setPlayerTeams(key, value)
	for _, name in ipairs(PLAYER_TEAMS) do
		local team = Esp.teamSettings[name]
		if team then team[key] = value end
	end
end

local function setPlayerPair(key, color, alpha)
	local packed = { color, alpha ~= nil and (1 - alpha) or 1 }

	for _, name in ipairs(PLAYER_TEAMS) do
		local team = Esp.teamSettings[name]
		if team then team[key] = packed end
	end
end

Entity.Settings.TeamCheck = "Off"
Esp.sharedSettings.teamCheck = "Off"

Esp.teamSettings.enemy.enabled = false
Esp.teamSettings.friendly.enabled = false
Esp.teamSettings.whitelist.enabled = false

for _, rarity in ipairs(RARITY_ORDER) do
	local color = RARITY_COLORS[rarity]

	Esp:AddTeam("crate" .. rarity, {
		enabled       = true,
		box           = true,
		boxColor      = { color, 1 },
		name          = true,
		nameColor     = { color, 1 },
		distance      = true,
		distanceColor = { color, 1 },
		healthBar     = false,
		healthText    = false,
		weapon        = false,
		skeleton      = false,
		chams         = false,
		tracer        = false,
		tracerColor   = { color, 1 },
		maxDistance   = 4000,
	})
end

Esp:AddTeam("plot", {
	enabled       = true,
	box           = true,
	boxColor      = { Color3.fromRGB(255, 215, 90), 1 },
	name          = true,
	nameColor     = { Color3.fromRGB(255, 215, 90), 1 },
	distance      = true,
	distanceColor = { Color3.fromRGB(255, 215, 90), 1 },
	healthBar     = false,
	healthText    = false,
	weapon        = false,
	skeleton      = false,
	chams         = false,
	tracer        = false,
	tracerColor   = { Color3.fromRGB(255, 215, 90), 1 },
	maxDistance   = 6000,
})

local EspState = {
	Loaded = false,
	Players = false,
	Crates = false,
	Plots = false,
	IncludePlotCrates = false,
	MinRank = 0,
	ShowTier = true,
	TrackedCrates = {},
	TrackedPlots = {},
	Connections = {},
}

local function ensureEsp()
	if EspState.Loaded then return true end

	local ok, err = pcall(function() Esp:Load(Entity) end)

	if not ok then
		notify("Esp", tostring(err), "error", 10)
		return false
	end

	EspState.Loaded = true

	return true
end

local function releaseEspIfIdle()
	if not EspState.Loaded then return end
	if EspState.Players or EspState.Crates or EspState.Plots then return end

	pcall(function() Esp:Unload() end)
	EspState.Loaded = false
end

local function carriedCrate(player)
	local character = player and player.Character
	if not character then return nil end

	for _, item in ipairs(character:GetChildren()) do
		if item:IsA("Tool") and item.Name:find("Crate") then
			return item.Name
		end
	end

	return nil
end

Esp.getWeapon = function(player)
	local name = carriedCrate(player)
	if name then return name end
	return ""
end

local function crateLabel(model, tier)
	local parts = { (string.gsub(model.Name, "%s*%[.*$", "")) }

	if EspState.ShowTier and tier then
		table.insert(parts, tier)
	end

	return table.concat(parts, "  ")
end

local function untrackCrate(model)
	if not EspState.TrackedCrates[model] then return end

	EspState.TrackedCrates[model] = nil
	pcall(function() Esp:RemoveInstance(model) end)
end

local function trackCrate(model)
	if not EspState.Crates then return end
	if EspState.TrackedCrates[model] then return end

	local tier = tierOf(model)
	if not tier then return end
	if (RARITY_RANK[tier] or 0) < EspState.MinRank then return end
	if not anchorOf(model) then return end

	local object = Esp:AddInstance(model, {
		Team = "crate" .. tier,
		Text = crateLabel(model, tier),
	})

	EspState.TrackedCrates[model] = { Tier = tier, Object = object }
end

local function crateSources()
	local sources = {}

	local folder = cratesFolder()
	if folder then table.insert(sources, folder) end

	if EspState.IncludePlotCrates then
		for _, record in ipairs(Plots:Scan()) do
			table.insert(sources, record.Floor)
		end
	end

	return sources
end

local function refreshCrateEsp()
	if not EspState.Crates then
		for model in pairs(EspState.TrackedCrates) do
			untrackCrate(model)
		end
		return
	end

	local present = {}

	for _, source in ipairs(crateSources()) do
		for _, descendant in ipairs(source:GetDescendants()) do
			if tierOf(descendant) then
				present[descendant] = true
				if not EspState.TrackedCrates[descendant] then trackCrate(descendant) end
			end
		end
	end

	for model, state in pairs(EspState.TrackedCrates) do
		if not present[model] or not model.Parent then
			untrackCrate(model)
		elseif state.Object then
			state.Object._displayName = crateLabel(model, state.Tier)
		end
	end
end

local function untrackPlot(sign)
	if not EspState.TrackedPlots[sign] then return end

	EspState.TrackedPlots[sign] = nil
	pcall(function() Esp:RemoveInstance(sign) end)
end

local PLOT_ANCHOR = "FacilityPlotAnchor"

local function plotMarker(record)
	local sign = record.Sign

	if sign and sign.Parent and anchorOf(sign) then return sign end

	local floor = record.Floor
	if not floor or not floor:IsA("BasePart") then return nil end

	local existing = record.Plot:FindFirstChild(PLOT_ANCHOR)

	if existing and existing.Parent then
		existing.CFrame = CFrame.new(floor.Position + Vector3.new(0, 8, 0))
		return existing
	end

	local marker = nil

	local ok = pcall(function()
		marker = Instance.new("Part")
		marker.Name = PLOT_ANCHOR
		marker.Size = Vector3.new(4, 6, 4)
		marker.Anchored = true
		marker.CanCollide = false
		marker.CanQuery = false
		marker.CanTouch = false
		marker.Massless = true
		marker.Transparency = 1
		marker.CFrame = CFrame.new(floor.Position + Vector3.new(0, 8, 0))
		marker.Parent = record.Plot
	end)

	if not ok then return nil end

	return marker
end

local function clearPlotMarkers()
	for _, child in ipairs(workspace:GetChildren()) do
		if child.Name:find("Plot Building") then
			local marker = child:FindFirstChild(PLOT_ANCHOR)
			if marker then pcall(function() marker:Destroy() end) end
		end
	end
end

local function refreshPlotEsp()
	if not EspState.Plots then
		for sign in pairs(EspState.TrackedPlots) do
			untrackPlot(sign)
		end
		return
	end

	local present = {}

	for _, entry in ipairs(Scanner.Ranked) do
		local record = entry.Record
		local sign = not record.Mine and record.Plot.Parent and plotMarker(record) or nil

		if sign then
			present[sign] = true

			local text = string.format("%s  %d crate%s%s",
				entry.Name,
				entry.Count,
				entry.Count == 1 and "" or "s",
				entry.Best and ("  " .. entry.Best) or "")

			local state = EspState.TrackedPlots[sign]

			if not state then
				local object = Esp:AddInstance(sign, { Team = "plot", Text = text })
				EspState.TrackedPlots[sign] = { Object = object, Text = text }
			elseif state.Text ~= text then
				state.Text = text
				if state.Object then state.Object._displayName = text end
			end
		end
	end

	for sign in pairs(EspState.TrackedPlots) do
		if not present[sign] then untrackPlot(sign) end
	end
end

local function stopPlotEsp()
	EspState.Plots = false
	pcall(refreshPlotEsp)
	pcall(clearPlotMarkers)
end

task.spawn(function()
	while true do
		task.wait(1)

		if EspState.Crates then pcall(refreshCrateEsp) end
		if EspState.Plots then pcall(refreshPlotEsp) end
	end
end)

task.spawn(function()
	local folder = cratesFolder() or workspace:WaitForChild("Crates", 60)
	if not folder then return end

	table.insert(EspState.Connections, folder.DescendantAdded:Connect(function(descendant)
		if not EspState.Crates then return end

		task.wait(0.15)

		if tierOf(descendant) then trackCrate(descendant) end
	end))

	table.insert(EspState.Connections, folder.DescendantRemoving:Connect(untrackCrate))
end)

onCleanup(function()
	EspState.Crates = false
	EspState.Players = false

	pcall(refreshCrateEsp)
	pcall(stopPlotEsp)

	for _, connection in ipairs(EspState.Connections) do
		pcall(function() connection:Disconnect() end)
	end

	if EspState.Loaded then
		pcall(function() Esp:Unload() end)
		EspState.Loaded = false
	end
end)

local Hop = {
	Mode = "Least Players",
	Running = false,
	Token = 0,
	Cache = nil,
	CacheMode = nil,
	CacheAt = 0,
	Blocked = {},
	Pending = nil,
	Denied = false,
	Auto = false,
	Patience = 25,
	EmptySince = 0,
}

local CACHE_LIFETIME = 25

local function blockServer(id)
	Hop.Pending = nil
	if id then Hop.Blocked[id] = true end
end

pcall(function()
	TeleportService.TeleportInitFailed:Connect(function(_, result, message)
		if not Hop.Pending then return end

		blockServer(Hop.Pending)
		Hop.Denied = true

		if not Hop.Running then
			notify("Server Hop", message ~= "" and message or result, "error", 6)
		end
	end)
end)

local function fetchServers(mode)
	local current = tostring(game.JobId or "")
	local found = {}
	local isRandom = mode == "Random"
	local order = mode == "Least Players" and "Asc" or "Desc"
	local pages = isRandom and 3 or 6
	local cursor = nil

	for _ = 1, pages do
		local url = string.format(
			"https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=%s&excludeFullGames=true&limit=100",
			game.PlaceId, order)

		if cursor and cursor ~= "" then
			url = url .. "&cursor=" .. HttpService:UrlEncode(cursor)
		end

		local ok, payload = pcall(function()
			return HttpService:JSONDecode(game:HttpGet(url))
		end)

		if not ok or type(payload) ~= "table" then
			return found, false
		end

		for _, entry in ipairs(payload.data or {}) do
			local id = tostring(entry.id or "")
			local playing = tonumber(entry.playing) or math.huge
			local maximum = tonumber(entry.maxPlayers) or 0

			if id ~= "" and id ~= current and playing < maximum then
				found[#found + 1] = { Id = id, Playing = playing, Room = maximum - playing }
			end
		end

		if #found > 0 and not isRandom then break end

		cursor = payload.nextPageCursor
		if not cursor or cursor == "" then break end
	end

	return found, true
end

local function serverHop(mode)
	local list

	if Hop.Cache and Hop.CacheMode == mode and os.clock() - Hop.CacheAt < CACHE_LIFETIME then
		list = Hop.Cache
	else
		local fetched, ok = fetchServers(mode)
		if not ok then return "fetch" end

		list = fetched
		Hop.Cache = fetched
		Hop.CacheMode = mode
		Hop.CacheAt = os.clock()
	end

	local function usable(minimumRoom)
		local out = {}

		for _, server in ipairs(list) do
			if not Hop.Blocked[server.Id] and server.Room >= minimumRoom then
				out[#out + 1] = server
			end
		end

		return out
	end

	local pool = usable(2)

	if #pool == 0 then pool = usable(1) end

	if #pool == 0 and next(Hop.Blocked) ~= nil then
		table.clear(Hop.Blocked)
		pool = usable(1)
	end

	if #pool == 0 then
		blockServer(nil)
		Hop.Cache = nil
		return "empty"
	end

	local id

	if mode == "Random" then
		id = pool[math.random(1, #pool)].Id
	else
		table.sort(pool, function(a, b)
			if mode == "Least Players" then return a.Playing < b.Playing end
			return a.Playing > b.Playing
		end)

		id = pool[1].Id
	end

	Hop.Denied = false
	Hop.Pending = id

	if not pcall(function()
		TeleportService:TeleportToPlaceInstance(game.PlaceId, id, LocalPlayer)
	end) then
		blockServer(id)
		return "failed"
	end

	local deadline = os.clock() + CACHE_LIFETIME

	while os.clock() < deadline do
		if Hop.Denied then return "denied" end
		task.wait(0.25)
	end

	return "waiting"
end

local function startHop()
	Hop.Token = Hop.Token + 1
	local token = Hop.Token

	task.spawn(function()
		Hop.Running = true
		local attempts = 0

		while token == Hop.Token do
			attempts = attempts + 1
			local result = serverHop(Hop.Mode)

			if result == "waiting" then break end

			if result == "empty" then
				Hop.Cache = nil
				table.clear(Hop.Blocked)
			end

			if attempts % 10 == 0 then
				notify("Server Hop", string.format("Every server was full so far, %d tries.", attempts), "warning", 4)
			end

			task.wait(result == "fetch" and 1 or 0.1)
		end

		Hop.Running = false
	end)
end

task.spawn(function()
	while true do
		task.wait(2)

		if Hop.Auto and not Hop.Running then
			local found = false

			pcall(function()
				local folder = cratesFolder()
				if not folder then return end

				for _, descendant in ipairs(folder:GetDescendants()) do
					local tier = tierOf(descendant)

					if tier and tierAllowed(tier) then
						found = true
						break
					end
				end
			end)

			if found then
				Hop.EmptySince = 0
			else
				if Hop.EmptySince == 0 then Hop.EmptySince = os.clock() end

				if os.clock() - Hop.EmptySince >= math.clamp(Hop.Patience, 5, 300) then
					Hop.EmptySince = 0
					notify("Server Hop", "No target crate on this map, hopping.", "info", 4)
					startHop()
				end
			end
		end
	end
end)

local fpsCapWarned = false

local function setFpsCap(value)
	local capped = math.clamp(math.floor(tonumber(value) or 240), 30, 1000)

	if type(setfpscap) == "function" and pcall(setfpscap, capped) then
		fpsCapWarned = false
		return
	end

	if not fpsCapWarned then
		fpsCapWarned = true
		notify("FPS Cap", "This executor does not support setfpscap.", "error", 6)
	end
end

local Window = Library:Window({
	Title             = "Facility",
	Suffix            = ".Sexility",
	Width             = 700,
	Height            = 580,
	MinWidth          = 580,
	SectionTitleStyle = "border",
	MobileButton      = true,
})

local StealTab   = Window:Tab("Steal", "hand")
local PlotTab    = Window:Tab("Plot", "box")
local ScannerTab = Window:Tab("Scanner", "search")
local VisualsTab = Window:Tab("Visuals", "eye")
local MovementTab = Window:Tab("Movement", "move")
local ServerTab  = Window:Tab("Server", "globe")
local MiscTab    = Window:Tab("Misc", "wrench")
local Settings   = Window:Tab("Settings", "cog")

local statusBox = StealTab:Section("Status", 1)

local statusLabel = statusBox:Label("Idle")
local stealLabel = statusBox:Label("Stolen 0  ·  last -", { Style = "dim" })
local plotLabel = statusBox:Label("Plot -", { Style = "dim" })

task.spawn(function()
	local shownStatus, shownSteal, shownPlot = nil, nil, nil

	while true do
		task.wait(0.3)

		if Game.Status ~= shownStatus then
			shownStatus = Game.Status
			pcall(function() statusLabel:Set(shownStatus) end)
		end

		local steal = string.format("Stolen %d  ·  last %s  ·  carrying %d",
			Steal.Grabbed, Steal.Last, crateToolCount())

		if steal ~= shownSteal then
			shownSteal = steal
			pcall(function() stealLabel:Set(steal) end)
		end

		local mine = Plots.Mine
		local plot = "Plot not found"

		if mine then
			local count, best = plotContents(mine)
			plot = string.format("Plot %d crate%s%s",
				count,
				count == 1 and "" or "s",
				best and ("  ·  best " .. best) or "")
		end

		if plot ~= shownPlot then
			shownPlot = plot
			pcall(function() plotLabel:Set(plot) end)
		end
	end
end)

local autoBox = StealTab:Section("Auto Steal", 2)

autoBox:Toggle({
	Text = "Auto Steal",
	Flag = "steal_enable",
	Default = false,
	Callback = function(state)
		Steal.Enabled = state
		if not state then Game.Status = "Idle" end
	end,
})
	:Keybind({ Default = "RightBracket", Flag = "steal_enable_key" })

autoBox:Dropdown({
	Text = "Target Tiers",
	Flag = "steal_tiers",
	Options = RARITY_ORDER,
	Default = {},
	Multi = true,
	Empty = "Use min tier",
	Callback = function(selected)
		local set = {}
		for _, name in ipairs(selected) do set[name] = true end
		Steal.Tiers = set
	end,
})

autoBox:Dropdown({
	Text = "Min Tier",
	Flag = "steal_min_tier",
	Options = RARITY_CHOICES,
	Default = RARITY_CHOICES[1],
	Callback = function(value)
		Steal.MinRank = RARITY_RANK[tostring(value)] or 0
	end,
})

autoBox:Dropdown({
	Text = "Priority",
	Flag = "steal_priority",
	Options = { "Highest Tier", "Closest", "Lowest Tier" },
	Default = "Highest Tier",
	Callback = function(value) Steal.Priority = tostring(value) end,
})

autoBox:Dropdown({
	Text = "Method",
	Flag = "steal_mode",
	Options = { "Teleport", "Reach" },
	Default = "Teleport",
	Callback = function(value)
		Steal.Mode = tostring(value)

		if Steal.Mode == "Teleport" and not Prompts.Global then
			Prompts:RestoreAll()
		end
	end,
})
	:Gear(function(panel)
		panel:Label("Reach raises the prompt range instead of teleporting. Quieter, but some servers check distance.", { Style = "dim" })
	end)

local sourceBox = StealTab:Section("Sources", 1)

sourceBox:Toggle({
	Text = "World Crates",
	Flag = "steal_world",
	Default = true,
	Callback = function(state) Steal.World = state end,
})

sourceBox:Toggle({
	Text = "Other Players' Plots",
	Flag = "steal_plots",
	Default = false,
	Callback = function(state) Steal.FromPlots = state end,
})

local timingBox = StealTab:Section("Timing", 2)

timingBox:Dropdown({
	Text = "Return To",
	Flag = "steal_return",
	Options = { "Safe Zone", "My Plot", "Previous", "None" },
	Default = "Safe Zone",
	Callback = function(value) Steal.Return = tostring(value) end,
})

timingBox:Slider({
	Text = "Grab Wait",
	Flag = "steal_grab_wait",
	Min = 0.1, Max = 4, Default = 1.2,
	Decimals = 2,
	Suffix = " s",
	Callback = function(value) Steal.Grab = tonumber(value) or 1.2 end,
})

timingBox:Slider({
	Text = "Cooldown",
	Flag = "steal_cooldown",
	Min = 0, Max = 8, Default = 1,
	Decimals = 2,
	Suffix = " s",
	Callback = function(value) Steal.Cooldown = tonumber(value) or 1 end,
})

timingBox:Slider({
	Text = "Safe Zone Height",
	Flag = "steal_height",
	Min = 0, Max = 80, Default = 20,
	Suffix = " studs",
	Callback = function(value) Steal.Height = tonumber(value) or 20 end,
})

local alertBox = StealTab:Section("Alerts", 1)

alertBox:Toggle({
	Text = "Notify On Steal",
	Flag = "steal_notify",
	Default = true,
	Callback = function(state) Steal.Notify = state end,
})

alertBox:Toggle({
	Text = "Webhook On Steal",
	Flag = "steal_webhook",
	Default = false,
	Callback = function(state) Steal.Hook = state end,
})

alertBox:Button({
	Text = "Steal Once",
	Callback = function()
		task.spawn(function()
			local ok, err = pcall(stealOnce)
			if not ok then notify("Steal", tostring(err), "error", 8) end
		end)
	end,
})

alertBox:Button({
	Text = "Reset Counter",
	Callback = function()
		Steal.Grabbed = 0
		Steal.Last = "-"
	end,
})

local placeBox = PlotTab:Section("Auto Place", 1)

placeBox:Toggle({
	Text = "Auto Place",
	Flag = "place_enable",
	Default = false,
	Callback = function(state) Place.Enabled = state end,
})

placeBox:Toggle({
	Text = "Place Every Crate",
	Flag = "place_all",
	Default = true,
	Callback = function(state) Place.All = state end,
})

placeBox:Dropdown({
	Text = "Layout",
	Flag = "place_layout",
	Options = { "Grid", "Random", "Center" },
	Default = "Grid",
	Callback = function(value)
		Place.Layout = tostring(value)
		Place.Index = 0
	end,
})

placeBox:Slider({
	Text = "Grid Spacing",
	Flag = "place_spacing",
	Min = 2, Max = 30, Default = 7,
	Decimals = 1,
	Suffix = " studs",
	Callback = function(value) Place.Spacing = tonumber(value) or 7 end,
})

placeBox:Slider({
	Text = "Rotation",
	Flag = "place_rotation",
	Min = 0, Max = 3, Default = 0,
	Callback = function(value) Place.Rotation = tonumber(value) or 0 end,
})

placeBox:Slider({
	Text = "Drop Height",
	Flag = "place_height",
	Min = 0, Max = 12, Default = 2.7,
	Decimals = 1,
	Suffix = " studs",
	Callback = function(value) Place.Height = tonumber(value) or 2.7 end,
})

placeBox:Slider({
	Text = "Delay",
	Flag = "place_delay",
	Min = 0.1, Max = 2, Default = 0.35,
	Decimals = 2,
	Suffix = " s",
	Callback = function(value) Place.Delay = tonumber(value) or 0.35 end,
})

placeBox:Button({
	Text = "Place Once",
	Callback = function()
		task.spawn(function() pcall(placeOnce) end)
	end,
})

local openBox = PlotTab:Section("Auto Open", 2)

openBox:Toggle({
	Text = "Auto Open",
	Flag = "open_enable",
	Default = false,
	Callback = function(state) Open.Enabled = state end,
})

openBox:Dropdown({
	Text = "Tiers To Open",
	Flag = "open_tiers",
	Options = RARITY_ORDER,
	Default = {},
	Multi = true,
	Empty = "All tiers",
	Callback = function(selected)
		local set = {}
		for _, name in ipairs(selected) do set[name] = true end
		Open.Tiers = set
	end,
})

openBox:Toggle({
	Text = "Teleport To Crate",
	Flag = "open_teleport",
	Default = true,
	Callback = function(state) Open.Teleport = state end,
})

openBox:Slider({
	Text = "Delay",
	Flag = "open_delay",
	Min = 0.1, Max = 3, Default = 0.4,
	Decimals = 2,
	Suffix = " s",
	Callback = function(value) Open.Delay = tonumber(value) or 0.4 end,
})

openBox:Button({
	Text = "Open Once",
	Callback = function()
		task.spawn(function() pcall(openOnce) end)
	end,
})

local gearBox = PlotTab:Section("Gear", 1)

gearBox:Toggle({
	Text = "Auto Equip Best",
	Flag = "equip_enable",
	Default = false,
	Callback = function(state) Equip.Enabled = state end,
})

gearBox:Slider({
	Text = "Interval",
	Flag = "equip_interval",
	Min = 0.5, Max = 20, Default = 2,
	Decimals = 1,
	Suffix = " s",
	Callback = function(value) Equip.Interval = tonumber(value) or 2 end,
})

gearBox:Button({
	Text = "Equip Best Now",
	Callback = function()
		if type(getconnections) ~= "function" then
			notify("Gear", "This executor has no getconnections.", "error", 6)
			return
		end

		local button = equipBestButton()

		if not button then
			notify("Gear", "EquipBest button not found.", "error", 6)
			return
		end

		for _, connection in ipairs(getconnections(button.Activated)) do
			pcall(function() connection:Fire() end)
		end
	end,
})

local defenseBox = PlotTab:Section("Defense", 2)

defenseBox:Toggle({
	Text = "Intruder Alerts",
	Flag = "defense_enable",
	Default = false,
	Callback = function(state) Defense.Enabled = state end,
})

defenseBox:Slider({
	Text = "Radius",
	Flag = "defense_radius",
	Min = 10, Max = 300, Default = 70,
	Suffix = " studs",
	Callback = function(value) Defense.Radius = tonumber(value) or 70 end,
})

defenseBox:Toggle({
	Text = "Notify",
	Flag = "defense_notify",
	Default = true,
	Callback = function(state) Defense.Notify = state end,
})

defenseBox:Toggle({
	Text = "Webhook",
	Flag = "defense_webhook",
	Default = false,
	Callback = function(state) Defense.Hook = state end,
})

local travelBox = PlotTab:Section("Travel", 1)

travelBox:Button({
	Text = "Teleport To My Plot",
	Callback = function()
		local mine = Plots:MyPlot()
		local floor = mine and mine.Floor

		if not floor then
			notify("Travel", "Your plot was not found.", "error", 5)
			return
		end

		Game.Teleport(CFrame.new(floor.Position + Vector3.new(0, 8, 0)))
	end,
})

travelBox:Button({
	Text = "Teleport To Safe Zone",
	Callback = function()
		local zone = safeZonePart()

		if not zone then
			notify("Travel", "Safe zone was not found.", "error", 5)
			return
		end

		Game.Teleport(zone.CFrame * CFrame.new(0, Steal.Height, 0))
	end,
})

travelBox:Button({
	Text = "Rescan Plots",
	Callback = function()
		Plots:Scan(true)
		rankPlots()
		notify("Plots", string.format("%d plots found.", #Plots.List), "success", 4)
	end,
})

local rankBox = ScannerTab:Section("Richest Plots", "full")

local rankRows = {}

for index = 1, 8 do
	rankRows[index] = rankBox:Label("-", { Style = index == 1 and "bright" or nil })
end

local rankFooter = rankBox:Label("scanning", { Style = "dim" })

local function rowText(index, entry)
	if not entry then return "-" end

	return string.format("%d. %s  ·  %d crate%s  ·  best %s  ·  score %d",
		index,
		entry.Name .. (entry.Mine and " (you)" or ""),
		entry.Count,
		entry.Count == 1 and "" or "s",
		entry.Best or "none",
		entry.Score)
end

task.spawn(function()
	local shown = {}

	while true do
		task.wait(1)

		for index = 1, 8 do
			local text = rowText(index, Scanner.Ranked[index])

			if shown[index] ~= text then
				shown[index] = text
				pcall(function() rankRows[index]:Set(text) end)
			end
		end

		local footer = string.format("%d plots  ·  refresh every %.0fs", #Scanner.Ranked, Scanner.Interval)

		if shown.footer ~= footer then
			shown.footer = footer
			pcall(function() rankFooter:Set(footer) end)
		end
	end
end)

local scannerBox = ScannerTab:Section("Controls", 1)

scannerBox:Slider({
	Text = "Refresh Interval",
	Flag = "scanner_interval",
	Min = 1, Max = 15, Default = 2,
	Decimals = 1,
	Suffix = " s",
	Callback = function(value) Scanner.Interval = tonumber(value) or 2 end,
})

scannerBox:Button({
	Text = "Teleport To Richest",
	Callback = function()
		for _, entry in ipairs(Scanner.Ranked) do
			if not entry.Mine and entry.Count > 0 then
				Scanner.Cursor = 1
				teleportToPlot(entry)
				return
			end
		end

		notify("Scanner", "No loaded plot has crates on it.", "warning", 5)
	end,
})

scannerBox:Button({
	Text = "Teleport To Next Plot",
	Callback = function()
		local pool = {}

		for _, entry in ipairs(Scanner.Ranked) do
			if not entry.Mine then table.insert(pool, entry) end
		end

		if #pool == 0 then
			notify("Scanner", "No other plot found.", "warning", 5)
			return
		end

		Scanner.Cursor = (Scanner.Cursor % #pool) + 1
		teleportToPlot(pool[Scanner.Cursor])
	end,
})

scannerBox:Button({
	Text = "Copy Ranking",
	Callback = function()
		if type(setclipboard) ~= "function" then
			notify("Scanner", "This executor has no setclipboard.", "error", 5)
			return
		end

		local lines = {}

		for index, entry in ipairs(Scanner.Ranked) do
			table.insert(lines, rowText(index, entry))
		end

		pcall(setclipboard, table.concat(lines, "\n"))
		notify("Scanner", "Ranking copied.", "success", 3)
	end,
})

local crateEspBox = VisualsTab:Section("Crate Esp", 1)

crateEspBox:Toggle({
	Text = "Crate Esp",
	Flag = "esp_crates",
	Default = false,
	Callback = function(state)
		if state and not ensureEsp() then return end

		EspState.Crates = state
		pcall(refreshCrateEsp)
		releaseEspIfIdle()
	end,
})
	:Keybind({ Default = "RightAlt", Flag = "esp_crates_key" })

crateEspBox:Dropdown({
	Text = "Min Tier",
	Flag = "esp_crate_min",
	Options = RARITY_CHOICES,
	Default = RARITY_CHOICES[1],
	Callback = function(value)
		EspState.MinRank = RARITY_RANK[tostring(value)] or 0

		for model in pairs(EspState.TrackedCrates) do
			untrackCrate(model)
		end

		pcall(refreshCrateEsp)
	end,
})

crateEspBox:Toggle({
	Text = "Show Tier",
	Flag = "esp_crate_tier",
	Default = true,
	Callback = function(state)
		EspState.ShowTier = state
		pcall(refreshCrateEsp)
	end,
})

crateEspBox:Toggle({
	Text = "Include Plot Crates",
	Flag = "esp_crate_plots",
	Default = false,
	Callback = function(state)
		EspState.IncludePlotCrates = state

		for model in pairs(EspState.TrackedCrates) do
			untrackCrate(model)
		end

		pcall(refreshCrateEsp)
	end,
})

crateEspBox:Slider({
	Text = "Max Distance",
	Flag = "esp_crate_distance",
	Min = 100, Max = 8000, Default = 4000,
	Suffix = " studs",
	Callback = function(value)
		for _, rarity in ipairs(RARITY_ORDER) do
			Esp.teamSettings["crate" .. rarity].maxDistance = value
		end
	end,
})

crateEspBox:Toggle({
	Text = "Tracers",
	Flag = "esp_crate_tracer",
	Default = false,
	Callback = function(state)
		for _, rarity in ipairs(RARITY_ORDER) do
			Esp.teamSettings["crate" .. rarity].tracer = state
		end
	end,
})

local plotEspBox = VisualsTab:Section("Plot Esp", 2)

plotEspBox:Toggle({
	Text = "Plot Esp",
	Flag = "esp_plots",
	Default = false,
	Callback = function(state)
		if state and not ensureEsp() then return end

		if state then
			EspState.Plots = true
			pcall(refreshPlotEsp)
		else
			stopPlotEsp()
		end

		releaseEspIfIdle()
	end,
})

plotEspBox:Toggle({
	Text = "Tracers",
	Flag = "esp_plot_tracer",
	Default = false,
	Callback = function(state) Esp.teamSettings.plot.tracer = state end,
})

plotEspBox:ColorPicker({
	Flag = "esp_plot_color",
	Default = Color3.fromRGB(255, 215, 90),
	Callback = function(color, alpha)
		local packed = { color, alpha ~= nil and (1 - alpha) or 1 }
		Esp.teamSettings.plot.boxColor = packed
		Esp.teamSettings.plot.nameColor = packed
		Esp.teamSettings.plot.distanceColor = packed
		Esp.teamSettings.plot.tracerColor = packed
	end,
})

plotEspBox:Slider({
	Text = "Max Distance",
	Flag = "esp_plot_distance",
	Min = 100, Max = 12000, Default = 6000,
	Suffix = " studs",
	Callback = function(value) Esp.teamSettings.plot.maxDistance = value end,
})

local playerEspBox = VisualsTab:Section("Player Esp", 1)

playerEspBox:Toggle({
	Text = "Player Esp",
	Flag = "esp_players",
	Default = false,
	Callback = function(state)
		if state and not ensureEsp() then return end

		EspState.Players = state

		for _, name in ipairs(PLAYER_TEAMS) do
			local team = Esp.teamSettings[name]
			if team then team.enabled = state end
		end

		releaseEspIfIdle()
	end,
})

playerEspBox:Toggle({
	Text = "Box",
	Flag = "esp_player_box",
	Default = true,
	Callback = function(state) setPlayerTeams("box", state) end,
})
	:ColorPicker({
		Flag = "esp_player_box_color",
		Default = Color3.fromRGB(0, 255, 100),
		Callback = function(color, alpha)
			setPlayerPair("boxColor", color, alpha)
			setPlayerPair("box3dColor", color, alpha)
		end,
	})

playerEspBox:Toggle({
	Text = "Name",
	Flag = "esp_player_name",
	Default = true,
	Callback = function(state) setPlayerTeams("name", state) end,
})

playerEspBox:Toggle({
	Text = "Distance",
	Flag = "esp_player_distance",
	Default = true,
	Callback = function(state) setPlayerTeams("distance", state) end,
})

playerEspBox:Toggle({
	Text = "Carried Crate",
	Flag = "esp_player_carry",
	Default = true,
	Callback = function(state) setPlayerTeams("weapon", state) end,
})

playerEspBox:Toggle({
	Text = "Health Bar",
	Flag = "esp_player_health",
	Default = false,
	Callback = function(state) setPlayerTeams("healthBar", state) end,
})

playerEspBox:Toggle({
	Text = "Chams",
	Flag = "esp_player_chams",
	Default = false,
	Callback = function(state) setPlayerTeams("chams", state) end,
})
	:ColorPicker({
		Flag = "esp_player_chams_fill",
		Default = Color3.fromRGB(0, 255, 100),
		DefaultAlpha = 0.5,
		Callback = function(color, alpha) setPlayerPair("chamsFillColor", color, alpha) end,
	})

playerEspBox:Toggle({
	Text = "Tracers",
	Flag = "esp_player_tracer",
	Default = false,
	Callback = function(state) setPlayerTeams("tracer", state) end,
})

playerEspBox:Toggle({
	Text = "Off Screen Arrow",
	Flag = "esp_player_arrow",
	Default = false,
	Callback = function(state) setPlayerTeams("offScreenArrow", state) end,
})

local displayBox = VisualsTab:Section("Display", 2)

displayBox:Slider({
	Text = "Text Size",
	Flag = "esp_text_size",
	Min = 8, Max = 24, Default = 13,
	Callback = function(value) Esp.sharedSettings.textSize = value end,
})

displayBox:Toggle({
	Text = "Rainbow",
	Flag = "esp_rainbow",
	Default = false,
	Callback = function(state) Esp.sharedSettings.rainbow = state end,
})

displayBox:Slider({
	Text = "Refresh Interval",
	Flag = "esp_slow_interval",
	Min = 0, Max = 1, Default = 0.1,
	Decimals = 2,
	Suffix = " s",
	Callback = function(value) Esp.sharedSettings.slowInterval = value end,
})

if Movement then

Movement.Settings.WalkSpeedMode = "Velocity"
Movement.Settings.JumpMode = "Humanoid"

local flyBox = MovementTab:Section("Fly", 1)

flyBox:Toggle({
	Text = "Fly",
	Flag = "move_fly",
	Default = false,
	Callback = function(state) Movement:Fly(state) end,
})
	:Keybind({ Default = "F", Flag = "move_fly_key" })

flyBox:Slider({
	Text = "Speed",
	Flag = "move_fly_speed",
	Min = 1, Max = 20, Default = 2,
	Decimals = 1,
	Callback = function(value) Movement.Settings.FlySpeed = value end,
})

local speedBox = MovementTab:Section("Speed", 2)

speedBox:Toggle({
	Text = "Walk Speed",
	Flag = "move_walkspeed",
	Default = false,
	Callback = function(state)
		Movement:WalkSpeed(state and Movement.Settings.WalkSpeed or 16)
	end,
})

speedBox:Slider({
	Text = "Value",
	Flag = "move_walkspeed_value",
	Min = 16, Max = 300, Default = 16,
	Callback = function(value)
		Movement.Settings.WalkSpeed = value
		if Library.Flags["move_walkspeed"] then Movement:WalkSpeed(value) end
	end,
})

local jumpBox = MovementTab:Section("Jump", 2)

jumpBox:Toggle({
	Text = "Jump Power",
	Flag = "move_jumppower",
	Default = false,
	Callback = function(state)
		Movement:JumpPower(state and Movement.Settings.JumpPower or 50)
	end,
})

jumpBox:Slider({
	Text = "Value",
	Flag = "move_jumppower_value",
	Min = 50, Max = 500, Default = 50,
	Callback = function(value)
		Movement.Settings.JumpPower = value
		if Library.Flags["move_jumppower"] then Movement:JumpPower(value) end
	end,
})

jumpBox:Toggle({
	Text = "Infinite Jump",
	Flag = "move_infinite_jump",
	Default = false,
	Callback = function(state) Movement:InfiniteJump(state) end,
})

local otherBox = MovementTab:Section("Other", 1)

otherBox:Toggle({
	Text = "Noclip",
	Flag = "move_noclip",
	Default = false,
	Callback = function(state) Movement:Noclip(state) end,
})
	:Keybind({ Default = "N", Flag = "move_noclip_key" })

otherBox:Toggle({
	Text = "Float",
	Flag = "move_float",
	Default = false,
	Callback = function(state) Movement:Float(state) end,
})
	:Gear(function(panel)
		panel:Slider({
			Text = "Height",
			Flag = "move_float_height",
			Min = 1, Max = 10, Default = 3.1,
			Decimals = 1,
			Callback = function(value) Movement.Settings.FloatHeight = value end,
		})
	end)

otherBox:Toggle({
	Text = "Spider",
	Flag = "move_spider",
	Default = false,
	Callback = function(state) Movement:Spider(state) end,
})
	:Gear(function(panel)
		panel:Slider({
			Text = "Climb Speed",
			Flag = "move_spider_speed",
			Min = 0.5, Max = 5, Default = 1,
			Decimals = 1,
			Callback = function(value) Movement.Settings.SpiderSpeed = value end,
		})
	end)

end

local hopBox = ServerTab:Section("Hop", 1)

hopBox:Dropdown({
	Text = "Mode",
	Flag = "hop_mode",
	Options = { "Least Players", "Most Players", "Random" },
	Default = "Least Players",
	Callback = function(value) Hop.Mode = tostring(value or "Least Players") end,
})

hopBox:Toggle({
	Text = "Hop When No Target Crate",
	Flag = "hop_auto",
	Default = false,
	Callback = function(state)
		Hop.Auto = state
		Hop.EmptySince = 0
	end,
})

hopBox:Slider({
	Text = "Patience",
	Flag = "hop_patience",
	Min = 5, Max = 180, Default = 25,
	Suffix = " s",
	Callback = function(value) Hop.Patience = tonumber(value) or 25 end,
})

hopBox:Button({
	Text = "Hop Now",
	Callback = startHop,
})

hopBox:Button({
	Text = "Rejoin Server",
	Callback = function()
		pcall(function()
			TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
		end)
	end,
})

hopBox:Button({
	Text = "Copy Job ID",
	Callback = function()
		if type(setclipboard) == "function" then
			pcall(setclipboard, tostring(game.JobId))
			notify("Server", "Job ID copied.", "success", 3)
		else
			notify("Server", "This executor has no setclipboard.", "error", 5)
		end
	end,
})

local browserBox = ServerTab:Section("Browser", 2)

local browserApi = nil

browserBox:Button({
	Text = "Open Server Browser",
	Callback = function()
		if not browserApi then
			local ok, result = pcall(function()
				return Library:ServerBrowser({
					PlaceId = game.PlaceId,
					MaxRows = 50,
					OnJoin = function(jobId, placeId)
						TeleportService:TeleportToPlaceInstance(placeId or game.PlaceId, jobId, LocalPlayer)
					end,
				})
			end)

			if not ok or type(result) ~= "table" then
				notify("Server", tostring(result), "error", 8)
				return
			end

			browserApi = result
		end

		browserApi:Toggle()
	end,
})

local promptBox = MiscTab:Section("Prompts", 1)

promptBox:Toggle({
	Text = "Instant Prompts",
	Flag = "misc_instant_prompts",
	Default = false,
	Callback = function(state) Prompts:SetGlobal(state) end,
})
	:Gear(function(panel)
		panel:Label("Zeroes hold time and widens range on every prompt in the map.", { Style = "dim" })
	end)

promptBox:Button({
	Text = "Restore Prompts",
	Callback = function()
		Prompts.Global = false
		Prompts:SetGlobal(false)
		notify("Prompts", "Originals restored.", "success", 3)
	end,
})

local perfBox = MiscTab:Section("Performance", 2)

perfBox:Toggle({
	Text = "FPS Cap",
	Flag = "misc_fps_cap",
	Default = false,
	Callback = function(state)
		if state then
			setFpsCap(Library.Flags["misc_fps_value"] or 240)
		else
			setFpsCap(1000)
		end
	end,
})

perfBox:Slider({
	Text = "Cap",
	Flag = "misc_fps_value",
	Min = 30, Max = 1000, Default = 240,
	Suffix = " fps",
	Callback = function(value)
		if Library.Flags["misc_fps_cap"] then setFpsCap(value) end
	end,
})

local hookBox = MiscTab:Section("Webhook", 1)

hookBox:Input({
	Text = "Webhook URL",
	Flag = "misc_webhook_url",
	Placeholder = "https://discord.com/api/webhooks/...",
	Callback = function(value)
		local url = tostring(value or "")

		if url == "" then
			StealHook = nil
			return
		end

		if not Webhook then
			notify("Webhook", "The webhook library is not loaded.", "error", 6)
			return
		end

		local ok, result = pcall(function()
			return Webhook.new(url, { Username = "Facility" })
		end)

		if not ok or type(result) ~= "table" then
			StealHook = nil
			notify("Webhook", tostring(result), "error", 8)
			return
		end

		StealHook = result
	end,
})

hookBox:Button({
	Text = "Test Webhook",
	Callback = function()
		if not StealHook then
			notify("Webhook", "Set a URL first.", "error", 5)
			return
		end

		pcall(function()
			StealHook:Embed({
				Title = "Facility connected",
				Description = "Steal From The Rich",
				Color = Color3.fromRGB(90, 200, 255),
			})
		end)

		notify("Webhook", "Test sent.", "success", 3)
	end,
})

local hudPanel = Library:Panel({
	Title = "stats",
	Icon = "activity",
	Width = 180,
	Position = UDim2.fromOffset(18, 320),
	Visible = false,
})

hudPanel:SetVisible(false)

hudPanel.Content:Label("fps", { Style = "dim" })
local fpsLabel = hudPanel.Content:Label("-", { Style = "bright" })

hudPanel.Content:Divider()

hudPanel.Content:Label("ping", { Style = "dim" })
local pingLabel = hudPanel.Content:Label("-", { Style = "bright" })

hudPanel.Content:Divider()

hudPanel.Content:Label("stolen", { Style = "dim" })
local stolenLabel = hudPanel.Content:Label("0", { Style = "bright" })

hudPanel.Content:Divider()

hudPanel.Content:Label("status", { Style = "dim" })
local panelStatus = hudPanel.Content:Label("Idle")

local counterBox = MiscTab:Section("Counters", 2)

local counterShown = false

counterBox:Toggle({
	Text = "Show Stats Panel",
	Flag = "misc_counters",
	Default = false,
	Callback = function(state)
		counterShown = state
		hudPanel:SetVisible(state)
	end,
})
	:Keybind({ Default = "RightControl", Flag = "misc_counters_key" })

task.spawn(function()
	local frames = 0
	local since = os.clock()
	local fps = 0

	local connection = RunService.RenderStepped:Connect(function()
		frames = frames + 1
		local now = os.clock()

		if now - since >= 0.5 then
			fps = math.floor(frames / (now - since) + 0.5)
			frames = 0
			since = now
		end
	end)

	onCleanup(function() connection:Disconnect() end)

	local lastStatus, lastStolen = nil, nil

	while true do
		task.wait(0.5)

		if counterShown then
			local ping = 0

			pcall(function()
				ping = math.floor(Stats.Network.ServerStatsItem["Data Ping"]:GetValue())
			end)

			pcall(function() fpsLabel:Set(tostring(fps)) end)
			pcall(function() pingLabel:Set(string.format("%d ms", ping)) end)

			local stolen = tostring(Steal.Grabbed)

			if stolen ~= lastStolen then
				lastStolen = stolen
				pcall(function() stolenLabel:Set(stolen) end)
			end

			if Game.Status ~= lastStatus then
				lastStatus = Game.Status
				pcall(function() panelStatus:Set(Game.Status) end)
			end
		end
	end
end)

onCleanup(function()
	pcall(function() hudPanel:SetVisible(false) end)
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
SaveManager:SetFolder("Facility/120475074479690")

InterfaceManager:BuildInterfaceSection(Settings, 1)
SaveManager:BuildConfigSection(Settings, 2)
ThemeManager:Mount(Window)

Window:SetTab(StealTab)

task.spawn(function()
	Plots:Scan(true)
	rankPlots()

	if not Plots.Mine then
		notify("Facility", "Your plot was not found yet, it will be picked up on the next scan.", "warning", 6)
	end

	if not fireable() then
		notify("Facility", "This executor has no fireproximityprompt, stealing and opening will not work.", "error", 10)
	end
end)

Library:Notify("Facility", "Loaded.", 4)

SaveManager:LoadAutoloadConfig()
ThemeManager:Load()

local libraryDestroy = Library.Destroy

function Library:Destroy(...)
	for index = #cleanupTasks, 1, -1 do
		pcall(cleanupTasks[index])
	end

	table.clear(cleanupTasks)

	return libraryDestroy(self, ...)
end

F.Unload = function()
	pcall(function() Library:Destroy() end)
end
