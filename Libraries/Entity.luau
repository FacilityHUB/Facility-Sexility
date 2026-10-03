--!nocheck
--!nolint UnknownGlobal

local Players    = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local cloneref = cloneref or function(o) return o end
Players = cloneref(Players)

local LocalPlayer = Players.LocalPlayer

local function Signal()
	local bindable = Instance.new("BindableEvent")
	return {
		Connect = function(_, fn) return bindable.Event:Connect(fn) end,
		connect = function(_, fn) return bindable.Event:Connect(fn) end,
		Once    = function(_, fn) return bindable.Event:Once(fn) end,
		Fire    = function(_, ...) bindable:Fire(...) end,
		Destroy = function() bindable:Destroy() end,
		_bindable = bindable,
	}
end

local Entity = {
	Entities    = {},
	Connections = {},
	Ids         = {},
	Started     = false,

	Self = {
		Alive     = false,
		Character = nil,
		Humanoid  = nil,
		Head      = nil,
		RootPart  = nil,
	},

	Settings = {
		TeamCheck = "Team",

		IgnoreSingleTeam = true,

		LoadTimeout = 5,
	},
}

Entity.Added   = Signal()
Entity.Removed = Signal()
Entity.Updated = Signal()

function Entity:IsTargetable(player)
	if player == LocalPlayer then return false end

	local mode = self.Settings.TeamCheck
	if mode == "Off" then return true end

	if not self:_gameHasTeams() then return true end

	if mode == "TeamColor" then
		local mine, theirs = LocalPlayer.TeamColor, player.TeamColor
		if mine == nil or theirs == nil then return true end
		if mine ~= theirs then return true end
		return self.Settings.IgnoreSingleTeam and self:_everyoneOnOneTeam()
	end

	if LocalPlayer.Team == nil or player.Team == nil then return true end
	if player.Team ~= LocalPlayer.Team then return true end

	return self.Settings.IgnoreSingleTeam and self:_everyoneOnOneTeam()
end

function Entity:_gameHasTeams()
	if LocalPlayer.Team ~= nil then return true end
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Team ~= nil then return true end
	end
	return false
end

function Entity:_everyoneOnOneTeam()
	local team = LocalPlayer.Team
	if not team then return false end
	return #team:GetPlayers() >= #Players:GetPlayers()
end

local function fakeHead(rootPart)
	return setmetatable({
		Name   = "Head",
		Size   = Vector3.new(1, 1, 1),
		Parent = rootPart.Parent,
	}, {
		__index = function(_, key)
			if key == "Position" then
				return rootPart.Position + Vector3.new(0, 3, 0)
			elseif key == "CFrame" then
				return rootPart.CFrame + Vector3.new(0, 3, 0)
			end
			return rootPart[key]
		end,
	})
end

function Entity:Remove(player)
	local ent = self.Entities[player]
	if not ent then return end

	self.Entities[player] = nil

	for _, connection in ipairs(ent.Connections) do
		pcall(function() connection:Disconnect() end)
	end
	ent.Connections = {}
	ent.Alive = false

	self.Removed:Fire(ent)
end

function Entity:_build(player, character, isLocal)
	local id = HttpService:GenerateGUID(true)
	self.Ids[player] = id

	if not character then return end

	task.spawn(function()
		local timeout = self.Settings.LoadTimeout

		local humanoid = character:FindFirstChildWhichIsA("Humanoid")
			or character:WaitForChild("Humanoid", timeout)
		if self.Ids[player] ~= id then return end

		local rootPart = character:FindFirstChild("HumanoidRootPart")
		if not rootPart then
			local deadline = tick() + timeout
			repeat
				task.wait(0.05)
				rootPart = character:FindFirstChild("HumanoidRootPart")
					or (humanoid and humanoid.RigType ~= Enum.HumanoidRigType.R6 and character.PrimaryPart)
			until rootPart or tick() > deadline or self.Ids[player] ~= id
		end
		if self.Ids[player] ~= id then return end
		if not humanoid or not rootPart then return end

		local head = character:FindFirstChild("Head") or fakeHead(rootPart)

		if isLocal then
			self.Self.Alive     = true
			self.Self.Character = character
			self.Self.Humanoid  = humanoid
			self.Self.Head      = head
			self.Self.RootPart  = rootPart
			return
		end

		local ent = {
			Player      = player,
			Character   = character,
			Humanoid    = humanoid,
			Head        = head,
			RootPart    = rootPart,
			Team        = player.Team,
			Targetable  = self:IsTargetable(player),
			Health      = humanoid.Health,
			MaxHealth   = humanoid.MaxHealth,
			Alive       = true,
			Connections = {},
		}

		local function watch(signal, fn)
			table.insert(ent.Connections, signal:Connect(fn))
		end

		watch(humanoid:GetPropertyChangedSignal("Health"), function()
			ent.Health = humanoid.Health
			self.Updated:Fire(ent)
		end)

		watch(humanoid:GetPropertyChangedSignal("MaxHealth"), function()
			ent.MaxHealth = humanoid.MaxHealth
			self.Updated:Fire(ent)
		end)

		watch(character.ChildRemoved, function(child)
			if child ~= rootPart and child ~= humanoid
				and not (typeof(head) == "Instance" and child == head) then
				return
			end

			task.delay(0.2, function()
				if self.Entities[player] ~= ent then return end

				if character.Parent == nil or player.Character ~= character then
					self:Remove(player)
					return
				end

				local alive = character:FindFirstChildWhichIsA("Humanoid")
					and (character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart)

				if alive then
					self:Refresh(player, false)
				else
					self:Remove(player)
				end
			end)
		end)

		self.Entities[player] = ent
		self.Added:Fire(ent)
	end)
end

function Entity:Refresh(player, isLocal)
	self:Remove(player)
	self:_build(player, player.Character, isLocal)
end

function Entity:_watch(player)
	local isLocal = player == LocalPlayer

	local function track(connection)
		table.insert(self.Connections, connection)
	end

	track(player:GetPropertyChangedSignal("Character"):Connect(function()
		if player.Character then
			self:Refresh(player, isLocal)
		elseif isLocal then
			self.Self.Alive = false
		else
			self:Remove(player)
		end
	end))

	track(player:GetPropertyChangedSignal("Team"):Connect(function()
		if isLocal then
			self:RefreshTargets()
			return
		end

		local ent = self.Entities[player]
		if not ent then return end

		ent.Team = player.Team
		local targetable = self:IsTargetable(player)
		if ent.Targetable ~= targetable then
			ent.Targetable = targetable
			self.Updated:Fire(ent)
		end
	end))

	if player.Character then
		self:Refresh(player, isLocal)
	end
end

function Entity:RefreshTargets()
	for _, ent in pairs(self.Entities) do
		local targetable = self:IsTargetable(ent.Player)
		if ent.Targetable ~= targetable then
			ent.Targetable = targetable
			self.Updated:Fire(ent)
		end
	end
end

function Entity:Get(player)
	return self.Entities[player]
end

function Entity:GetAll(targetableOnly)
	local list = {}
	for _, ent in pairs(self.Entities) do
		if ent.Alive and (not targetableOnly or ent.Targetable) then
			table.insert(list, ent)
		end
	end
	return list
end

function Entity:GetNearestToPosition(position, maxDistance, targetableOnly)
	local closest, best = maxDistance or math.huge, nil
	for _, ent in pairs(self.Entities) do
		if ent.Alive and (not targetableOnly or ent.Targetable) then
			local distance = (position - ent.RootPart.Position).Magnitude
			if distance < closest then
				closest, best = distance, ent
			end
		end
	end
	return best, closest
end

function Entity:GetNearestToMouse(maxRadius, targetableOnly, camera)
	camera = camera or workspace.CurrentCamera
	local mouse = game:GetService("UserInputService"):GetMouseLocation()
	local mousePos = Vector2.new(mouse.X, mouse.Y)

	local closest, best = maxRadius or math.huge, nil
	for _, ent in pairs(self.Entities) do
		if ent.Alive and (not targetableOnly or ent.Targetable) then
			local screen, onScreen = camera:WorldToViewportPoint(ent.RootPart.Position)
			if onScreen then
				local distance = (mousePos - Vector2.new(screen.X, screen.Y)).Magnitude
				if distance < closest then
					closest, best = distance, ent
				end
			end
		end
	end
	return best, closest
end

function Entity:GetWithinDistance(position, maxDistance, limit, targetableOnly)
	local list = {}
	for _, ent in pairs(self.Entities) do
		if ent.Alive and (not targetableOnly or ent.Targetable) then
			local distance = (position - ent.RootPart.Position).Magnitude
			if distance <= maxDistance then
				table.insert(list, { Entity = ent, Distance = distance })
			end
		end
	end

	table.sort(list, function(a, b) return a.Distance < b.Distance end)

	if limit and #list > limit then
		for index = #list, limit + 1, -1 do
			list[index] = nil
		end
	end
	return list
end

function Entity:IsVisible(ent, part, camera)
	camera = camera or workspace.CurrentCamera
	local target = ent[part or "Head"]
	if not target then return false end

	local ignore = { ent.Character }
	if self.Self.Character then table.insert(ignore, self.Self.Character) end

	local obscuring = camera:GetPartsObscuringTarget({ target.Position }, ignore)
	return #obscuring == 0
end

function Entity:Start()
	if self.Started then return self end
	self.Started = true

	for _, player in ipairs(Players:GetPlayers()) do
		self:_watch(player)
	end

	table.insert(self.Connections, Players.PlayerAdded:Connect(function(player)
		self:_watch(player)
	end))

	table.insert(self.Connections, Players.PlayerRemoving:Connect(function(player)
		self.Ids[player] = nil
		self:Remove(player)
	end))

	task.spawn(function()
		while self.Started do
			task.wait(2)
			for _, player in ipairs(Players:GetPlayers()) do
				if player ~= LocalPlayer
					and player.Character
					and player.Character.Parent ~= nil
					and not self.Entities[player] then
					self:Refresh(player, false)
				end
			end
		end
	end)

	return self
end

function Entity:Stop()
	for _, connection in ipairs(self.Connections) do
		pcall(function() connection:Disconnect() end)
	end
	self.Connections = {}

	for player in pairs(self.Entities) do
		self:Remove(player)
	end

	table.clear(self.Ids)
	self.Self.Alive = false
	self.Started = false
end

function Entity:Destroy()
	self:Stop()
	self.Added:Destroy()
	self.Removed:Destroy()
	self.Updated:Destroy()
end

return Entity
