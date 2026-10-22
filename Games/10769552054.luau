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
local Terrain = workspace:FindFirstChildOfClass("Terrain")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local H = {}
local U = {}
local S = {
	connections = {}, drawings = {}, instances = {}, threads = {}, originals = {},
	firing = false, perf = {}, weapons = nil, bloom = nil,
}

local F = {
	teamMode = "Team",

	trigger = false, triggerTeam = true, triggerDelay = 0, triggerMode = "Crosshair", triggerFov = 0,

	noRecoil = false, noSpread = false,

	lowGraphics = false, noTextures = false, noEffects = false, noShadows = false, whiteScreen = false,
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
		if LocalPlayer.Neutral or player.Neutral then return true end
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

H.track(UserInputService.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then S.firing = true end
end))

H.track(UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then S.firing = false end
end))
S.rayParams = RaycastParams.new()
S.rayParams.FilterType = Enum.RaycastFilterType.Exclude
S.rayParams.IgnoreWater = true

function H.shootable(instance)
	local map = workspace:FindFirstChild("CurrentMap")
	local folder = map and map:FindFirstChild("Shootable")
	return folder ~= nil and (instance == folder or instance:IsDescendantOf(folder))
end

function H.pierce(origin, point, ignore)
	local skip = table.clone(ignore)
	local from = origin
	for _ = 1, 4 do
		local direction = point - from
		if direction.Magnitude < 0.1 then return true end
		S.rayParams.FilterDescendantsInstances = skip
		local hit = workspace:Raycast(from, direction, S.rayParams)
		if not hit then return true end
		local model = hit.Instance:FindFirstAncestorOfClass("Model")
		if model and Players:GetPlayerFromCharacter(model) then return true end
		if not H.shootable(hit.Instance) then return false end
		table.insert(skip, hit.Instance)
		from = hit.Position + direction.Unit * 0.05
	end
	return false
end

function H.clear(point)
	local camera = workspace.CurrentCamera
	local character = LocalPlayer.Character
	local root = H.root(character)
	if not (camera and character and root) then return false end
	local ignore = { character, camera }
	return H.pierce(camera.CFrame.Position, point, ignore) and H.pierce(root.Position, point, ignore)
end

function H.targets(teamCheck)
	local list = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if player ~= LocalPlayer and character and H.root(character) and H.aliveChar(character) then
			if not teamCheck or H.enemy(player) then table.insert(list, { model = character, player = player }) end
		end
	end
	return list
end


function H.triggerValid(model, player)
	if not model or not H.aliveChar(model) or not player or player == LocalPlayer then return nil end
	if F.triggerTeam and not H.enemy(player) then return nil end
	return model
end

function H.visibleHead(model)
	local head = model:FindFirstChild("Head") or H.root(model)
	return head and H.clear(head.Position)
end

function H.triggerTarget()
	local camera = workspace.CurrentCamera
	if not camera then return nil end

	if F.triggerMode == "Target" then
		local target = Aimbot and Aimbot.Target
		local player = nil
		if typeof(target) == "Instance" and target:IsA("Player") then player = target end
		if type(target) == "table" and typeof(target.Player) == "Instance" then player = target.Player end
		return player and H.triggerValid(player.Character, player) or nil
	end

	if F.triggerMode == "Fov" then
		local center = camera.ViewportSize / 2
		local best, bestDistance = nil, F.triggerFov > 0 and F.triggerFov or 12
		for _, target in ipairs(H.targets(F.triggerTeam)) do
			local part = target.model:FindFirstChild("Head") or H.root(target.model)
			if part then
				local point, onScreen = camera:WorldToViewportPoint(part.Position)
				if onScreen and point.Z > 0 then
					local distance = (Vector2.new(point.X, point.Y) - center).Magnitude
					if distance <= bestDistance and H.visibleHead(target.model) then
						best, bestDistance = target.model, distance
					end
				end
			end
		end
		return best
	end

	S.rayParams.FilterDescendantsInstances = { LocalPlayer.Character, camera }
	local hit = workspace:Raycast(camera.CFrame.Position, camera.CFrame.LookVector * 2000, S.rayParams)
	if not hit then return nil end
	local model = hit.Instance:FindFirstAncestorOfClass("Model")
	while model and not model:FindFirstChildOfClass("Humanoid") do
		model = model:FindFirstAncestorOfClass("Model")
	end
	if not model then return nil end
	return H.triggerValid(model, Players:GetPlayerFromCharacter(model))
end

S.trigger = { holding = false, tap = 0, seen = 0 }

function H.triggerRelease()
	if S.trigger.holding then
		H.mouseUp()
		S.trigger.holding = false
	end
end

H.track(RunService.RenderStepped:Connect(function(dt)
	if not alive() then return end
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

function H.loadWeapons()
	if S.weapons then return S.weapons end
	local ok, result = H.gcall(function()
		local folder = game:GetService("ReplicatedStorage"):WaitForChild("Weapons", 5)
		if not folder then return nil end
		local state = folder:WaitForChild("ClientState", 5)
		local config = folder:WaitForChild("Config", 5)
		return { state = state and require(state), config = config and require(config) }
	end)
	if ok and type(result) == "table" and type(result.state) == "table" then
		S.weapons = result
		local global = type(result.config) == "table" and result.config.Global
		if type(global) == "table" and S.bloom == nil then S.bloom = global.BloomScale end
	end
	return S.weapons
end

function H.setBloom(value)
	local weapons = S.weapons
	local global = weapons and type(weapons.config) == "table" and weapons.config.Global
	if type(global) == "table" and value ~= nil then pcall(function() global.BloomScale = value end) end
end

function H.gunsNeeded(label)
	if H.loadWeapons() then return true end
	H.notify(label, "Weapon modules not found in this game.", 5)
	return false
end

S.gunStep = "FacilityGunMods" .. SESSION
RunService:BindToRenderStep(S.gunStep, Enum.RenderPriority.Camera.Value - 1, function()
	if not alive() or not (F.noRecoil or F.noSpread) then return end
	local state = S.weapons and S.weapons.state
	if type(state) ~= "table" then return end
	pcall(function()
		if F.noRecoil then
			state.RecoilPitch = 0
			state.RecoilYaw = 0
		end
		if F.noSpread then
			state.Spread = 0
			state.SpreadRest = 0
			state.SpreadMultiplier = 0
		end
	end)
	if F.noSpread then H.setBloom(0) end
end)

H.EFFECT_CLASSES = { "ParticleEmitter", "Trail", "Beam", "Smoke", "Fire", "Sparkles" }

function H.restoreKey(key, filter)
	for node, values in pairs(S.originals) do
		if values[key] ~= nil and (not filter or filter(node)) then
			pcall(function() node[key] = values[key] end)
			values[key] = nil
		end
	end
end

function H.isEffect(item)
	for _, class in ipairs(H.EFFECT_CLASSES) do
		if item:IsA(class) then return true end
	end
	return false
end

function H.perfItem(item)
	if F.noEffects and H.isEffect(item) then H.setProp(item, "Enabled", false) end
	if F.noTextures then
		if item:IsA("Decal") or item:IsA("Texture") then
			H.setProp(item, "Transparency", 1)
		elseif item:IsA("BasePart") and not item:IsA("Terrain") then
			H.setProp(item, "Material", Enum.Material.SmoothPlastic)
			H.setProp(item, "Reflectance", 0)
		elseif item:IsA("SurfaceAppearance") then
			H.setProp(item, "Parent", nil)
		end
	end
	if F.noShadows and item:IsA("BasePart") then H.setProp(item, "CastShadow", false) end
end

function H.perfWanted()
	return F.noEffects or F.noTextures or F.noShadows
end

function H.perfScan()
	S.perf.scan = (S.perf.scan or 0) + 1
	local token = S.perf.scan
	task.spawn(function()
		for index, item in ipairs(workspace:GetDescendants()) do
			if not alive() or token ~= S.perf.scan or not H.perfWanted() then return end
			if index % 400 == 0 then task.wait() end
			pcall(H.perfItem, item)
		end
	end)

	if H.perfWanted() and not S.perf.added then
		S.perf.added = H.track(workspace.DescendantAdded:Connect(function(item)
			if alive() and H.perfWanted() then
				task.defer(function() pcall(H.perfItem, item) end)
			end
		end))
	end
end

function H.setEffects(state)
	F.noEffects = state
	if state then
		for _, effect in ipairs(Lighting:GetChildren()) do
			if effect:IsA("PostEffect") then H.setProp(effect, "Enabled", false) end
		end
		H.perfScan()
	else
		H.restoreKey("Enabled", function(node) return typeof(node) == "Instance" end)
	end
end

function H.setTextures(state)
	F.noTextures = state
	if state then
		H.perfScan()
	else
		H.restoreKey("Transparency")
		H.restoreKey("Material")
		H.restoreKey("Reflectance")
		H.restoreKey("Parent")
	end
end

function H.setShadows(state)
	F.noShadows = state
	if state then
		H.setProp(Lighting, "GlobalShadows", false)
		H.perfScan()
	else
		H.restoreKey("CastShadow")
		H.restoreProp(Lighting, "GlobalShadows")
	end
end

function H.setLowGraphics(state)
	F.lowGraphics = state
	local rendering = nil
	pcall(function() rendering = settings().Rendering end)
	if state then
		if rendering then H.setProp(rendering, "QualityLevel", Enum.QualityLevel.Level01) end
		H.setProp(Lighting, "EnvironmentDiffuseScale", 0)
		H.setProp(Lighting, "EnvironmentSpecularScale", 0)
		H.setProp(Lighting, "FogEnd", 1e6)
		if Terrain then
			H.setProp(Terrain, "Decoration", false)
			H.setProp(Terrain, "WaterWaveSize", 0)
			H.setProp(Terrain, "WaterWaveSpeed", 0)
			H.setProp(Terrain, "WaterReflectance", 0)
		end
		local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
		if atmosphere then H.setProp(atmosphere, "Density", 0) end
	else
		if rendering then H.restoreProp(rendering, "QualityLevel") end
		H.restoreProp(Lighting, "EnvironmentDiffuseScale")
		H.restoreProp(Lighting, "EnvironmentSpecularScale")
		H.restoreProp(Lighting, "FogEnd")
		if Terrain then
			H.restoreProp(Terrain, "Decoration")
			H.restoreProp(Terrain, "WaterWaveSize")
			H.restoreProp(Terrain, "WaterWaveSpeed")
			H.restoreProp(Terrain, "WaterReflectance")
		end
		local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
		if atmosphere then H.restoreProp(atmosphere, "Density") end
	end
end

function H.setWhiteScreen(state)
	F.whiteScreen = state
	pcall(function() RunService:Set3dRenderingEnabled(not state) end)
end

function H.setFpsCap(value)
	if type(setfpscap) ~= "function" then
		H.notify("Fps Cap", "Your executor has no setfpscap.", 4)
		return
	end
	pcall(setfpscap, value)
end

S.fps = { frames = 0, at = os.clock(), value = 0 }

H.track(RunService.RenderStepped:Connect(function()
	S.fps.frames = S.fps.frames + 1
	local now = os.clock()
	if now - S.fps.at >= 1 then
		S.fps.value = math.floor(S.fps.frames / (now - S.fps.at) + 0.5)
		S.fps.frames, S.fps.at = 0, now
	end
end))

function H.memoryText()
	local ok, total = pcall(function() return game:GetService("Stats"):GetTotalMemoryUsageMb() end)
	return ok and string.format("%.0f MB", total) or "-"
end

function H.pingText()
	local ok, ping = pcall(LocalPlayer.GetNetworkPing, LocalPlayer)
	return ok and string.format("%.0f ms", ping * 1000) or "-"
end

shared.FacilityCleanup = function()
	F.trigger, F.noRecoil, F.noSpread = false, false, false
	pcall(H.triggerRelease)
	pcall(function() RunService:UnbindFromRenderStep(S.gunStep) end)
	H.setBloom(S.bloom)
	if F.whiteScreen then pcall(H.setWhiteScreen, false) end
	pcall(H.restoreAll)

	for _, connection in ipairs(S.connections) do pcall(function() connection:Disconnect() end) end
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
U.Visuals  = Window:Tab("Visuals", "eye")
U.PlayerT  = Window:Tab("Player", "user-round")
U.Perf     = Window:Tab("Performance", "gauge")
Window:TabDivider()
U.Settings = Window:Tab("Settings", "cog")

if #moduleErrors > 0 then
	U.failBox = U.Combat:Section("Modules", "full")
	for _, message in ipairs(moduleErrors) do
		U.failBox:Label(message, { Style = "dim" })
	end
end

U.teamBox = U.Combat:Section("Targets", 2)
H.D(U.teamBox, "Team Check", "g7_team_mode", { "Team", "TeamColor", "Off" }, "Team", function(value) H.setTeamMode(value) end)

if Aimbot then

Aimbot.Settings.TeamCheck = true
Aimbot.Settings.WallCheck = true

U.aimBox = U.Combat:Section("Aimbot", 1)

U.aimBox:Toggle({
	Text = "Enable",
	Flag = "g7_aim_enable",
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
	Flag = "g7_aim_key",
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
	Flag = "g7_aim_toggle_mode",
	Default = false,
	Callback = function(state) Aimbot.Settings.ToggleMode = state end,
})

U.aimBox:Dropdown({
	Text = "Priority",
	Flag = "g7_aim_priority",
	Options = { "Cursor", "Closest", "LowestHealth" },
	Default = "Cursor",
	Callback = function(value) Aimbot.Settings.Priority = value end,
})

U.aimBox:Dropdown({
	Text = "Target Part",
	Flag = "g7_aim_parts",
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
	Flag = "g7_aim_random_part",
	Default = false,
	Callback = function(state) Aimbot.Settings.RandomPart = state end,
})
	:Gear(function(panel)
		panel:Slider({
			Text = "Interval",
			Flag = "g7_aim_random_interval",
			Min = 0.1, Max = 3, Default = 1,
			Decimals = 1,
			Suffix = " s",
			Callback = function(value) Aimbot.Settings.RandomInterval = value end,
		})
	end)

H.S(U.aimBox, "Smoothness", "g7_aim_smoothness", 0.05, 1, 0.3, 2, function(value) Aimbot.Settings.Smoothness = value end)
H.S(U.aimBox, "Sensitivity", "g7_aim_sensitivity", 0.02, 1, 0.5, 2, function(value) Aimbot.Settings.Sensitivity = value end)
H.D(U.aimBox, "Easing Style", "g7_aim_easing_style", { "Linear", "Sine", "Quad", "Cubic", "Quart", "Quint", "Exponential", "Back" }, "Quad", function(value) Aimbot.Settings.EasingStyle = value end)
H.D(U.aimBox, "Easing Direction", "g7_aim_easing_direction", { "In", "Out", "InOut" }, "Out", function(value) Aimbot.Settings.EasingDirection = value end)
H.S(U.aimBox, "Switch Delay", "g7_aim_switch_delay", 0, 2, 0, 2, function(value) Aimbot.Settings.SwitchDelay = value end, " s")
H.S(U.aimBox, "Max Distance", "g7_aim_max_distance", 100, 5000, 3000, 0, function(value) Aimbot.Settings.MaxDistance = value end, " studs")

U.fovBox = U.Combat:Section("Fov", 2)

U.fovBox:Toggle({
	Text = "Fov",
	Flag = "g7_aim_fov_enabled",
	Default = true,
	Callback = function(state)
		Aimbot.Settings.FovCheck = state
		Aimbot.Settings.FovVisible = state
	end,
})
	:ColorPicker({
		Flag = "g7_aim_fov_color",
		Default = Color3.fromRGB(255, 255, 255),
		Callback = function(color) Aimbot.Settings.FovColor = color end,
	})
	:ColorPicker({
		Flag = "g7_aim_fov_lock_color",
		Default = Color3.fromRGB(255, 70, 70),
		Callback = function(color) Aimbot.Settings.FovLockColor = color end,
	})

U.fovBox:Slider({
	Text = "Radius",
	Flag = "g7_aim_fov",
	Min = 20, Max = 600, Default = 180,
	Callback = function(value)
		Aimbot.Settings.Fov = value
		pcall(function() Aimbot:SetFov(value) end)
	end,
})

H.S(U.fovBox, "Thickness", "g7_aim_fov_thickness", 1, 5, 1, 0, function(value) Aimbot.Settings.FovThickness = value end)
H.S(U.fovBox, "Transparency", "g7_aim_fov_transparency", 0, 1, 0.4, 2, function(value) Aimbot.Settings.FovTransparency = value end)
H.T(U.fovBox, "Filled", "g7_aim_fov_filled", false, function(state) Aimbot.Settings.FovFilled = state end)

U.behaviourBox = U.Combat:Section("Behaviour", 2)

H.T(U.behaviourBox, "Team Check", "g7_aim_team_check", true, function(state) Aimbot.Settings.TeamCheck = state end)
H.T(U.behaviourBox, "Wall Check", "g7_aim_wall_check", true, function(state) Aimbot.Settings.WallCheck = state end)
H.T(U.behaviourBox, "Multipoint", "g7_aim_multipoint", false, function(state) Aimbot.Settings.Multipoint = state end)
H.S(U.behaviourBox, "Deadzone", "g7_aim_deadzone", 0, 200, 0, 0, function(value) Aimbot.Settings.Deadzone = value end)

U.behaviourBox:Toggle({
	Text = "Sticky Target",
	Flag = "g7_aim_sticky",
	Default = true,
	Callback = function(state) Aimbot.Settings.Sticky = state end,
})
	:Gear(function(panel)
		H.S(panel, "Hold Fov", "g7_aim_sticky_fov", 1, 3, 1.6, 1, function(value) Aimbot.Settings.StickyFov = value end)
	end)

U.behaviourBox:Toggle({
	Text = "Prediction",
	Flag = "g7_aim_prediction",
	Default = false,
	Callback = function(state) Aimbot.Settings.Prediction = state end,
})
	:Gear(function(panel)
		H.S(panel, "Time", "g7_aim_prediction_time", 0, 0.5, 0.1, 2, function(value) Aimbot.Settings.PredictionTime = value end, " s")
		H.T(panel, "Add Ping", "g7_aim_prediction_ping", false, function(state) Aimbot.Settings.PingPrediction = state end)
	end)

U.behaviourBox:Toggle({
	Text = "Target Line",
	Flag = "g7_aim_target_line",
	Default = false,
	Callback = function(state) Aimbot.Settings.TargetLine = state end,
})
	:ColorPicker({
		Flag = "g7_aim_target_line_color",
		Default = Color3.fromRGB(255, 70, 70),
		Callback = function(color) Aimbot.Settings.TargetLineColor = color end,
	})

H.T(U.behaviourBox, "Target Info", "g7_aim_target_info", false, function(state) Aimbot.Settings.TargetInfo = state end)

end

U.triggerBox = U.Combat:Section("Trigger Bot", 1)

U.triggerBox:Toggle({
	Text = "Enable",
	Flag = "g7_trigger",
	Default = false,
	Hint = "fires while an enemy sits under your crosshair",
	Callback = function(state)
		F.trigger = state
		if not state then H.triggerRelease() end
	end,
})
	:Keybind({ Default = "None", Flag = "g7_trigger_key" })

H.D(U.triggerBox, "Mode", "g7_trigger_mode", { "Crosshair", "Target", "Fov" }, "Crosshair", function(value) F.triggerMode = value end)
H.S(U.triggerBox, "Fov", "g7_trigger_fov", 0, 400, 0, 0, function(value) F.triggerFov = value end)
H.T(U.triggerBox, "Team Check", "g7_trigger_team", true, function(state) F.triggerTeam = state end)
H.S(U.triggerBox, "Shot Delay", "g7_trigger_delay", 0, 2, 0, 2, function(value)
	F.triggerDelay = value
	H.triggerRelease()
end, " s")
U.triggerBox:Label("0 holds and sprays, higher values tap.", { Style = "dim" })

U.gunBox = U.Combat:Section("Gun Mods", 2)
H.T(U.gunBox, "No Recoil", "g7_no_recoil", false, function(state)
	F.noRecoil = state and H.gunsNeeded("No Recoil")
end, "the view stays still while firing")
H.T(U.gunBox, "No Spread", "g7_no_spread", false, function(state)
	F.noSpread = state and H.gunsNeeded("No Spread")
	if not F.noSpread then H.setBloom(S.bloom) end
end, "every bullet goes to the crosshair, bloom removed")

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
	Flag = "g7_esp_enable",
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
	:Keybind({ Default = "None", Flag = "g7_esp_enable_key" })

U.espBox:Toggle({
	Text = "Box",
	Flag = "g7_esp_box",
	Default = true,
	Callback = function(state) H.espSet("box", state) end,
})
	:ColorPicker({
		Flag = "g7_esp_box_color",
		Default = Color3.fromRGB(255, 255, 255),
		Callback = function(color, alpha)
			H.espPair("boxColor", color, alpha)
			H.espPair("box3dColor", color, alpha)
		end,
	})
	:Gear(function(panel)
		H.D(panel, "Style", "g7_esp_box_style", { "2D", "3D" }, "2D", function(value)
			H.espSet("box", value == "2D")
			H.espSet("box3d", value == "3D")
		end)
	end)

U.espBox:Toggle({
	Text = "Health Bar",
	Flag = "g7_esp_health_bar",
	Default = true,
	Callback = function(state) H.espSet("healthBar", state) end,
})
	:ColorPicker({ Flag = "g7_esp_health_healthy", Default = Color3.fromRGB(82, 197, 148), Callback = function(color) H.espSet("healthyColor", color) end })
	:ColorPicker({ Flag = "g7_esp_health_dying", Default = Color3.fromRGB(240, 90, 102), Callback = function(color) H.espSet("dyingColor", color) end })

U.espBox:Toggle({
	Text = "Skeleton",
	Flag = "g7_esp_skeleton",
	Default = false,
	Callback = function(state) H.espSet("skeleton", state) end,
})
	:ColorPicker({ Flag = "g7_esp_skeleton_color", Default = Color3.new(1, 1, 1), Callback = function(color, alpha) H.espPair("skeletonColor", color, alpha) end })

U.espBox:Toggle({
	Text = "Tracers",
	Flag = "g7_esp_tracer",
	Default = false,
	Callback = function(state) H.espSet("tracer", state) end,
})
	:ColorPicker({ Flag = "g7_esp_tracer_color", Default = Color3.new(1, 1, 1), Callback = function(color, alpha) H.espPair("tracerColor", color, alpha) end })
	:Gear(function(panel)
		H.D(panel, "Origin", "g7_esp_tracer_origin", { "Bottom", "Middle", "Top", "Mouse" }, "Bottom", function(value) H.espSet("tracerOrigin", value) end)
	end)

U.espBox:Toggle({
	Text = "Highlight",
	Flag = "g7_esp_chams",
	Default = false,
	Callback = function(state) H.espSet("chams", state) end,
})
	:ColorPicker({ Flag = "g7_esp_chams_color", Default = Color3.fromRGB(255, 60, 60), Callback = function(color, alpha) H.espPair("chamsFillColor", color, alpha) end })

U.espBox:Toggle({
	Text = "Off Screen Arrow",
	Flag = "g7_esp_arrow",
	Default = false,
	Callback = function(state) H.espSet("offScreenArrow", state) end,
})
	:ColorPicker({ Flag = "g7_esp_arrow_color", Default = Color3.new(1, 1, 1), Callback = function(color, alpha) H.espPair("offScreenArrowColor", color, alpha) end })

U.displayBox = U.Visuals:Section("Display", 2)

U.displayBox:Toggle({
	Text = "Name",
	Flag = "g7_esp_name",
	Default = true,
	Callback = function(state) H.espSet("name", state) end,
})
	:ColorPicker({ Flag = "g7_esp_name_color", Default = Color3.fromRGB(236, 241, 250), Callback = function(color, alpha) H.espPair("nameColor", color, alpha) end })

U.displayBox:Toggle({
	Text = "Distance",
	Flag = "g7_esp_distance",
	Default = true,
	Callback = function(state) H.espSet("distance", state) end,
})
	:ColorPicker({ Flag = "g7_esp_distance_color", Default = Color3.fromRGB(170, 184, 205), Callback = function(color, alpha) H.espPair("distanceColor", color, alpha) end })

U.displayBox:Toggle({
	Text = "Weapon",
	Flag = "g7_esp_weapon",
	Default = false,
	Callback = function(state) H.espSet("weapon", state) end,
})
	:ColorPicker({ Flag = "g7_esp_weapon_color", Default = Color3.fromRGB(255, 255, 255), Callback = function(color, alpha) H.espPair("weaponColor", color, alpha) end })

H.T(U.displayBox, "Health", "g7_esp_health_text", false, function(state) H.espSet("healthText", state) end)
H.T(U.displayBox, "Team Color", "g7_esp_team_color", false, function(state) Esp.sharedSettings.useTeamColor = state end)
H.S(U.displayBox, "Text Size", "g7_esp_text_size", 8, 24, 13, 0, function(value) Esp.sharedSettings.textSize = value end)
H.S(U.displayBox, "Max Distance", "g7_esp_max_distance", 100, 5000, 1500, 0, function(value) H.espSet("maxDistance", value) end, " studs")

U.displayBox:Toggle({
	Text = "Show Teammates",
	Flag = "g7_esp_allies",
	Default = false,
	Callback = function(state) Esp.teamSettings.friendly.enabled = state end,
})
	:ColorPicker({
		Flag = "g7_esp_ally_color",
		Default = Color3.fromRGB(60, 255, 120),
		Callback = function(color)
			Esp.teamSettings.friendly.boxColor = { color, 1 }
			Esp.teamSettings.friendly.nameColor = { color, 1 }
		end,
	})

U.moveBox = U.PlayerT:Section("Movement", 1)

if Movement then

Movement.Settings.JumpMode = "Humanoid"

U.moveBox:Toggle({
	Text = "Fly",
	Flag = "g7_fly",
	Default = false,
	Callback = function(state) Movement:Fly(state) end,
})
	:Keybind({ Default = "None", Flag = "g7_fly_key" })
	:Gear(function(panel)
		H.S(panel, "Speed", "g7_fly_speed", 1, 20, 2, 1, function(value) Movement.Settings.FlySpeed = value end)
	end)

U.moveBox:Toggle({
	Text = "Jump Power",
	Flag = "g7_jump",
	Default = false,
	Callback = function(state) Movement:JumpPower(state and Movement.Settings.JumpPower or 50) end,
})
	:Gear(function(panel)
		H.S(panel, "Power", "g7_jump_value", 30, 300, 80, 0, function(value)
			Movement.Settings.JumpPower = value
			if Library.Flags["g7_jump"] then Movement:JumpPower(value) end
		end)
	end)

H.T(U.moveBox, "Infinite Jump", "g7_inf_jump", false, function(state) Movement:InfiniteJump(state) end)

U.moveBox:Toggle({
	Text = "Noclip",
	Flag = "g7_noclip",
	Default = false,
	Callback = function(state)
		Movement:Noclip(state)
		if not state then H.fixCollision() end
	end,
})
	:Keybind({ Default = "None", Flag = "g7_noclip_key" })

end

U.walkBox = U.PlayerT:Section("Walk Speed", 2)

U.walkBox:Toggle({
	Text = "Walk Speed",
	Flag = "g7_walk",
	Default = false,
	Callback = function(state)
		if Movement then Movement:WalkSpeed(state and (Library.Flags["g7_walk_value"] or 30) or 16, "Humanoid") end
	end,
})
	:Keybind({ Default = "None", Flag = "g7_walk_key" })

H.S(U.walkBox, "Speed", "g7_walk_value", 16, 120, 30, 0, function(value)
	if Movement and Library.Flags["g7_walk"] then Movement:WalkSpeed(value, "Humanoid") end
end)

U.gfxBox = U.Perf:Section("Graphics", 1)
H.T(U.gfxBox, "Low Graphics", "g7_low_gfx", false, function(state) H.setLowGraphics(state) end, "lowest quality level, no water waves, grass or fog")
H.T(U.gfxBox, "Remove Effects", "g7_no_effects", false, function(state) H.setEffects(state) end, "particles, trails, beams and post effects")
H.T(U.gfxBox, "Plain Textures", "g7_no_textures", false, function(state) H.setTextures(state) end, "flat materials, hides decals and textures")
H.T(U.gfxBox, "No Shadows", "g7_no_shadows", false, function(state) H.setShadows(state) end)
U.gfxBox:Label("Every option above is undone when you turn it off.", { Style = "dim" })

U.fpsBox = U.Perf:Section("Frame Rate", 2)
U.fpsBox:Toggle({
	Text = "Fps Cap",
	Flag = "g7_fps_cap",
	Default = false,
	Callback = function(state) H.setFpsCap(state and (Library.Flags["g7_fps_value"] or 240) or 60) end,
})
H.S(U.fpsBox, "Max Fps", "g7_fps_value", 30, 999, 240, 0, function(value)
	if Library.Flags["g7_fps_cap"] then H.setFpsCap(value) end
end)
U.fpsBox:Label("999 removes the limit. Off goes back to 60.", { Style = "dim" })

U.fpsBox:Toggle({
	Text = "White Screen",
	Flag = "g7_white_screen",
	Default = false,
	Hint = "stops 3D rendering, for farming in the background",
	Callback = function(state) H.setWhiteScreen(state) end,
})
	:Keybind({ Default = "None", Flag = "g7_white_screen_key" })

U.statBox = U.Perf:Section("Live Stats", 2)
U.statText = U.statBox:Paragraph({ Title = "Session", Content = "loading..." })
H.loop(1, function()
	pcall(function()
		U.statText:Set({ Title = "Session", Content = "Fps: " .. S.fps.value .. "\nPing: " .. H.pingText() .. "\nMemory: " .. H.memoryText() })
	end)
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
SaveManager:SetFolder("Facility/10769552054")

InterfaceManager:BuildInterfaceSection(U.Settings, 1)
SaveManager:BuildConfigSection(U.Settings, 2)
ThemeManager:Mount(Window)

Window:SetTab(U.Combat)

if #moduleErrors > 0 then
	task.delay(1, function()
		for _, message in ipairs(moduleErrors) do Library:Error("Facility", message, 20) end
	end)
end

Library:Notify("Facility", "Facility loaded.", 4)

SaveManager:LoadAutoloadConfig()
ThemeManager:Load()

