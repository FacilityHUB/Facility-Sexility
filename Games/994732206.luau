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

repeat task.wait() until game:IsLoaded()

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local H = {}
local U = { Tabs = {}, Flags = {}, Columns = {} }
local S = { kaitun = false, savePath = "Facility/994732206/speedhub.json" }

local FacilityLib = { Unloaded = false }

function FacilityLib:SetNotification(data)
	if type(data) ~= "table" then return end
	local title = (data[2] and data[2] ~= "") and data[2] or "Facility"
	pcall(function() Library:Notify(title, tostring(data[3] or ""), tonumber(data[4]) or 4) end)
end

function H.flag(title)
	local base = "bf_" .. string.gsub(string.lower(tostring(title)), "[^%w]+", "_")
	local name, index = base, 1
	while U.Flags[name] do
		index = index + 1
		name = base .. "_" .. index
	end
	U.Flags[name] = true
	return name
end

local SectionAdapter = {}
SectionAdapter.__index = SectionAdapter

function SectionAdapter:AddSeperator(data)
	local text = type(data) == "table" and (data[1] or data.Title) or data
	self.Section:Label(tostring(text or ""), { Style = "bright" })
end

function SectionAdapter:AddLine()
	self.Section:Divider()
end

function SectionAdapter:AddParagraph(data)
	data = data or {}
	local title = data.Title or data[1] or ""
	local content = data.Content or data[2] or ""
	local paragraph = self.Section:Paragraph({ Title = tostring(title), Content = tostring(content) })
	local api = {}
	function api:Set(new)
		new = new or {}
		pcall(function()
			paragraph:Set({ Title = new.Title or new[1], Content = new.Content or new[2] })
		end)
	end
	return api
end

local TabAdapter = {}
TabAdapter.__index = TabAdapter

function TabAdapter:AddSection(name)
	self.Count = (self.Count or 0) + 1
	local column = (self.Count % 2 == 1) and 1 or 2
	local section = self.Tab:Section(tostring(name), column)
	return setmetatable({ Section = section, Name = name }, SectionAdapter)
end

local FacilityFuncs = { State = {} }

function FacilityFuncs:SetTable(state)
	self.State = state
end

function FacilityFuncs:Initial(title, default)
	if default == "Save" then
		local saved = self.State[title]
		return saved
	end
	return default
end

function FacilityFuncs:Toggle(section, title, desc, default, callback)
	local initial = self:Initial(title, default) == true
	local toggle = section.Section:Toggle({
		Text = title,
		Hint = desc,
		Flag = H.flag(title),
		Default = initial,
		Callback = function(state)
			if callback then callback(state) end
		end,
	})
	if callback then task.spawn(callback, initial) end

	local api = { Instance = toggle }
	function api:SetValue(state)
		pcall(function() toggle:Set(state and true or false) end)
	end
	function api:Set(state) self:SetValue(state) end
	return api
end

function FacilityFuncs:Dropdown(section, title, desc, multi, options, default, callback)
	options = options or {}
	local initial = self:Initial(title, default)
	local selected

	if multi then
		selected = type(initial) == "table" and initial or {}
	else
		if type(initial) == "table" then initial = initial[1] end
		selected = initial
		if selected == nil or selected == "" or not table.find(options, selected) then selected = options[1] end
	end

	local function fire(value)
		if not callback then return end
		if multi then
			callback(type(value) == "table" and value or { value })
		else
			callback({ value })
		end
	end

	local dropdown = section.Section:Dropdown({
		Text = title,
		Flag = H.flag(title),
		Options = options,
		Default = selected,
		Multi = multi and true or false,
		Chips = multi and true or nil,
		Empty = "none",
		Callback = fire,
	})
	if selected ~= nil then task.spawn(fire, selected) end

	local api = { Instance = dropdown }
	function api:Clear() end
	function api:Refresh(list, value)
		pcall(function()
			dropdown:SetOptions(list or {})
			local pick = type(value) == "table" and value[1] or value
			if pick and pick ~= "" then dropdown:Set(pick) end
		end)
	end
	function api:Set(value) pcall(function() dropdown:Set(value) end) end
	return api
end

function FacilityFuncs:Button(section, title, desc, callback)
	return section.Section:Button({ Text = title, Callback = function() if callback then callback() end end })
end

function FacilityFuncs:Textbox(section, title, desc, default, callback)
	local initial = self:Initial(title, default)
	return section.Section:Input({
		Text = title,
		Placeholder = desc,
		Flag = H.flag(title),
		Default = initial ~= nil and tostring(initial) or "",
		Callback = function(text)
			if callback then callback(text) end
		end,
	})
end

shared.FacilityCleanup = function()
	FacilityLib.Unloaded = true
	S.kaitun = false
	pcall(function() Library:Destroy() end)
end

local Window = Library:Window({
	Title             = "Facility",
	Suffix            = ".Sexility",
	Width             = 760,
	Height            = 620,
	MinWidth          = 600,
	SectionTitleStyle = "border",
	MobileButton      = true,
	TabStyle          = "side",
})

function H.tab(name, icon)
	local tab = Window:Tab(name, icon)
	local adapter = setmetatable({ Tab = tab, Name = name }, TabAdapter)
	U.Tabs[name] = adapter
	return adapter
end

local TabHome      = H.tab("Home", "house")
local TabMain      = H.tab("Main", "swords")
local TabAuto      = H.tab("Automatically", "bot")
local TabSea       = H.tab("Sea Event", "waves")
local TabTeleport  = H.tab("Teleport", "map-pin")
local TabShop      = H.tab("Shop", "shopping-cart")
local TabMisc      = H.tab("Misc", "wrench")
local TabKaitun    = H.tab("Kaitun", "rocket")
Window:TabDivider()
local TabSettings  = H.tab("Settings", "cog")

function H.ensureFolders(path)
	if not (isfolder and makefolder) then return end
	local current = ""
	for part in string.gmatch(path, "[^/]+") do
		current = current == "" and part or (current .. "/" .. part)
		pcall(function()
			if not isfolder(current) then makefolder(current) end
		end)
	end
end

function H.codes()
	local list = {}
	local ok, body = pcall(function()
		return game:HttpGet("https://raw.githubusercontent.com/AhmadV99/Main/main/Codes_BloxFruit")
	end)
	if ok and type(body) == "string" then
		for code in string.gmatch(body, "\"([%w_%-%.!]+)\"") do
			table.insert(list, code)
		end
	end
	return list
end
local function SpeedHub()
	local now = tick()
	local v9 = FacilityLib
	local result2 = FacilityFuncs
	local v11, v12, v13, v14, v15, v16, v17, v18 = TabHome, TabMain, TabAuto, TabSea, TabTeleport, TabShop, TabMisc, TabSettings

	local tbl4 = {
		__spawn = task.spawn,
		__isLoaded = false,
		__unloadRequested = false,
		__locks = {},
		__timers = {},
		__hooks = {},
	}

	local function fn5(arg)
		return ({ [arg] = game:GetService(arg) })[arg]
	end

	local tbl5 = {
		Players = fn5("Players"),
		ReplicatedStorage = fn5("ReplicatedStorage"),
		HttpService = fn5("HttpService"),
		UserInputService = fn5("UserInputService"),
		Workspace = fn5("Workspace"),
		VirtualInputManager = fn5("VirtualInputManager"),
		TweenService = fn5("TweenService"),
		RunService = fn5("RunService"),
		Lighting = fn5("Lighting"),
		CollectionService = fn5("CollectionService"),
		TeleportService = fn5("TeleportService"),
	}

	local localPlayer = tbl5.Players.LocalPlayer
	local playerGui = localPlayer.PlayerGui

	local tbl6 = {
		Enemies = tbl5.Workspace:FindFirstChild("Enemies"),
		Characters = tbl5.Workspace:FindFirstChild("Characters"),
		Map = tbl5.Workspace:FindFirstChild("Map"),
		WorldOrigin = tbl5.Workspace:FindFirstChild("_WorldOrigin"),
		Remotes = tbl5.ReplicatedStorage:FindFirstChild("Remotes"),
		CommF_ = nil,
		Modules = tbl5.ReplicatedStorage:FindFirstChild("Modules"),
		Net = nil,
	}

	tbl6.CommF_ = tbl6.Remotes:WaitForChild("CommF_")
	tbl6.Net = tbl6.Modules:WaitForChild("Net")

	local tbl7 = {
		RegisterAttack = tbl6.Net:WaitForChild("RE/RegisterAttack"),
		RegisterHit = tbl6.Net:WaitForChild("RE/RegisterHit"),
		ReceivedHit = tbl6.Net:WaitForChild("RE/ReceivedHit"),
		ShootGunEvent = tbl6.Net:WaitForChild("RE/ShootGunEvent"),
	}

	local placeId = game.PlaceId

	local tbl8 = {
		placeId == 2753915549 or placeId == 85211729168715,
		placeId == 4442272183 or placeId == 79091703265657,
		placeId == 7449423635 or placeId == 100117331123089,
	}

	local tbl9 = {
		BoatShop = {
			[2] = CFrame.new(-13.488054275512695, 10.311711311340332, 2927.69287109375),
			[3] = CFrame.new(-16927.17578125, 9.0563430786132812, 435.248779296875),
		},
		BoatShopPos = {
			[2] = Vector3.new(-13.488054, 10.311711, 2927.6929),
			[3] = Vector3.new(-16927.176, 9.056343, 435.24878),
		},
		LevelSea = {
			["1"] = CFrame.new(-21332.876953125, 0, 1356.6005859375),
			["2"] = CFrame.new(-25077.7109375, 0, 2876.619140625),
			["3"] = CFrame.new(-29325.326171875, 0, 4763.1796875),
			["4"] = CFrame.new(-31615.3671875, 0, 5669.40478515625),
			["5"] = CFrame.new(-36453.9921875, 0, 6484.83056640625),
			["6"] = CFrame.new(-42170.15234375, 0, 4071.352294921875),
			Infinite = CFrame.new(0, 5, -1e14),
		},
		Islands = {
			["Sky 2"] = Vector3.new(-4607.8228, 872.5425, -1667.5569),
			["Sky 3"] = Vector3.new(-7894.6177, 5547.1416, -380.2912),
		},
	}

	local tbl10 = {
		"Rocket Fruit",
		"Spin Fruit",
		"Chop Fruit",
		"Spring Fruit",
		"Bomb Fruit",
		"Smoke Fruit",
		"Spike Fruit",
		"Flame Fruit",
		"Falcon Fruit",
		"Ice Fruit",
		"Sand Fruit",
		"Dark Fruit",
		"Ghost Fruit",
		"Diamond Fruit",
		"Light Fruit",
		"Rubber Fruit",
		"Barrier Fruit",
		"Magma Fruit",
		"Quake Fruit",
		"Buddha Fruit",
		"Love Fruit",
		"Spider Fruit",
		"Sound Fruit",
		"Phoenix Fruit",
		"Portal Fruit",
		"Rumble Fruit",
		"Pain Fruit",
		"Blizzard Fruit",
		"Gravity Fruit",
		"Mammoth Fruit",
		"T-Rex Fruit",
		"Dough Fruit",
		"Shadow Fruit",
		"Venom Fruit",
		"Control Fruit",
		"Spirit Fruit",
		"Dragon Fruit",
		"Leopard Fruit",
		"Yeti Fruit",
		"Kitsune Fruit",
		"Gas Fruit",
		"Blade Fruit",
	}

	local tbl11 = {
		Frags = {
			{ "Race Rerol", { "BlackbeardReward", "Reroll", "2" } },
			{ "Reset Stats", { "BlackbeardReward", "Refund", "2" } },
		},
		["Fighting Style"] = {
			{ "Buy Black Leg", { "BuyBlackLeg" } },
			{ "Buy Electro", { "BuyElectro" } },
			{ "Buy Fishman Karate", { "BuyFishmanKarate" } },
			{ "Buy Dragon Claw", { "BlackbeardReward", "DragonClaw", "2" } },
			{ "Buy Superhuman", { "BuySuperhuman" } },
			{ "Buy Death Step", { "BuyDeathStep" } },
			{ "Buy Sharkman Karate", { "BuySharkmanKarate" } },
			{ "Buy Electric Claw", { "BuyElectricClaw" } },
			{ "Buy Dragon Talon", { "BuyDragonTalon" } },
			{ "Buy GodHuman", { "BuyGodhuman" } },
			{ "Buy Sanguine Art", { "BuySanguineArt" } },
		},
		["Ability Teacher"] = {
			{ "Buy Geppo", { "BuyHaki", "Geppo" } },
			{ "Buy Buso", { "BuyHaki", "Buso" } },
			{ "Buy Soru", { "BuyHaki", "Soru" } },
			{ "Buy Ken", { "KenTalk", "Buy" } },
		},
		Sword = {
			{ "Buy Katana", { "BuyItem", "Katana" } },
			{ "Buy Cutlass", { "BuyItem", "Cutlass" } },
			{ "Buy Dual Katana", { "BuyItem", "Dual Katana" } },
			{ "Buy Iron Mace", { "BuyItem", "Iron Mace" } },
			{ "Buy Triple Katana", { "BuyItem", "Triple Katana" } },
			{ "Buy Pipe", { "BuyItem", "Pipe" } },
			{ "Buy Dual-Headed Blade", { "BuyItem", "Dual-Headed Blade" } },
			{ "Buy Soul Cane", { "BuyItem", "Soul Cane" } },
			{ "Buy Bisento", { "BuyItem", "Bisento" } },
		},
		Gun = {
			{ "Buy Musket", { "BuyItem", "Musket" } },
			{ "Buy Slingshot", { "BuyItem", "Slingshot" } },
			{ "Buy Flintlock", { "BuyItem", "Flintlock" } },
			{ "Buy Refined Slingshot", { "BuyItem", "Refined Slingshot" } },
			{ "Buy Refined Flintlock", { "BuyItem", "Refined Flintlock" } },
			{ "Buy Cannon", { "BuyItem", "Cannon" } },
			{ "Buy Kabucha", { "BlackbeardReward", "Slingshot", "2" } },
		},
		Accessories = {
			{ "Buy Black Cape", { "BuyItem", "Black Cape" } },
			{ "Buy Swordsman Hat", { "BuyItem", "Swordsman Hat" } },
			{ "Buy Tomoe Ring", { "BuyItem", "Tomoe Ring" } },
		},
		Race = {
			{ "Ghoul Race", { "Ectoplasm", "Change", 4 } },
			{ "Cyborg Race", { "CyborgTrainer", "Buy" } },
		},
	}

	local tbl12 = {
		"Flame",
		"Ice",
		"Quake",
		"Light",
		"Dark",
		"Spider",
		"Rumble",
		"Magma",
		"Buddha",
		"Sand",
		"Phoenix",
		"Dough",
	}

	local ItemReplicationService = require(tbl5.ReplicatedStorage.ItemReplicationService)
	local KEYS = require(tbl5.ReplicatedStorage.ItemReplicationService.KEYS)
	local ItemId = require(tbl5.ReplicatedStorage.Economy.ItemId)
	local ItemConfig = require(tbl5.ReplicatedStorage.ItemConfig)
	local RarityUtil = require(tbl5.ReplicatedStorage.Modules.Asset.RarityUtil)
	local PriceService = require(tbl5.ReplicatedStorage.PriceService)

	local tbl13 = {
		Moveset = "Melee",
		PhysicalMoveset = "Blox Fruit",
		Material = "Material",
		Accessory = "Accessory",
	}

	local function fn6()
		local tbl14 = {}

		local ok3, result3 = pcall(function()
			return tbl5.ReplicatedStorage.Remotes.CommF_:InvokeServer("GetFruits")
		end)

		if ok3 and typeof(result3) == "table" then
			for _, v19 in ipairs(result3) do
				if v19.Name and v19.Price then
					tbl14[v19.Name] = v19.Price
				end
			end
		end

		return tbl14
	end

	local function fn7(arg, arg2)
		local v19 = ItemConfig.match(arg, arg2)
		local v20 = nil

		if v19 then
			if v19.asNullable then
				v20 = v19:asNullable()
			else
				v20 = nil

				if v19.unwrap then
					v20 = v19:unwrap()
				end
			end
		end

		if not v20 then
			return nil
		end
		local rarity = v20.Quality and v20.Quality.Rarity
		if not rarity then
			return nil
		end
		return RarityUtil.tryGetRarity(rarity)
	end

	local function fn8()
		local tbl14 = {}
		local items = ItemReplicationService:GetItems(KEYS.QUANTITY)
		if not items then
			return tbl14
		end
		local v19 = fn6()

		for _, item in pairs(items) do
			local n = item.Value or 0

			if n > 0 then
				local itemId = item.ItemId
				local v20 = ItemConfig.match(itemId)
				local str = "Other"

				if v20:isOk() then
					local v21 = v20:unwrap()
					local index = v21.Index or v21.Data or v21
					str = index.IdType or index.Type or "Other"
				end

				local v21 = tbl13[str]

				if v21 then
					local v22 = ItemId.getDataFromId(itemId)
					local storageKey = nil

					if v22:isOk() then
						storageKey = v22:unwrap().StorageKey
					end

					local name = fn7(itemId)
					name = name and name.Name or "Unknown"

					local tbl15 = {
						Name = storageKey or "Item_" .. tostring(itemId),
						Count = n,
						Type = v21,
						Rarity = name,
						ItemId = itemId,
					}

					if v21 == "Blox Fruit" and storageKey then
						local price = v19[storageKey] or 0
						local robuxPrice = 0

						if PriceService:GetIfInitialized() then
							local v23 = ItemId.getId("Permanent " .. storageKey, "Redeemable"):asNullable()

							if v23 then
								robuxPrice = PriceService.getPrice(v23) or 0
							end
						end

						tbl15.Price = price
						tbl15.RobuxPrice = robuxPrice
					end

					table.insert(tbl14, tbl15)
				end
			end
		end

		return tbl14
	end

	local tbl14 = {}
	local str = S.savePath
	local tbl15 = {}
	local n = 0
	local n2 = 0.5

	local tbl16 = {
		SetSave = function(arg, arg2, arg3, arg4)
			if not (arg4 or false) and type(arg3) == "table" then
				for _, v19 in pairs(arg3) do
					tbl14[arg2] = v19
					tbl15[arg2] = true
				end
			else
				tbl14[arg2] = arg3
				tbl15[arg2] = true
			end

			if n2 <= tick() - n then
				n = tick()

				pcall(function()
					local json = tbl5.HttpService:JSONEncode(tbl14)

					if writefile and isfolder and makefolder then
						H.ensureFolders("Facility/994732206")

						writefile(str, json)
						table.clear(tbl15)
					end
				end)
			end
		end,
		SetLoad = function()
			if not isfile then
				return
			end

			pcall(function()
				if isfile(str) then
					local data = tbl5.HttpService:JSONDecode(readfile(str))

					if data and type(data) == "table" then
						for k, v19 in pairs(data) do
							tbl14[k] = v19
						end
					end
				end
			end)
		end,
	}

	tbl16:SetLoad()
	result2:SetTable(tbl14)
	tbl14["Fast Attack Delay"] = 0
	local tbl17 = { __spawn = task.spawn, __loops = {}, __connections = {}, __metadata = {}, __running = true }

	tbl4.__spawn(function()
		if not _G.ExecutedRemove then
			_G.ExecutedRemove = true
			local container = tbl5.ReplicatedStorage.Effect.Container
			local CameraShaker = require(tbl5.ReplicatedStorage.Util.CameraShaker)

			hookfunction(require(container:FindFirstChild("Death")), function()
			end)

			CameraShaker:Stop()
		end
	end)

	tbl4.__spawn(function()
		local enemySpawns = tbl5.Workspace:FindFirstChild("EnemySpawns") or Instance.new("Folder", tbl5.Workspace)
		enemySpawns.Name = "EnemySpawns"
		local enemyCDKSpawns = tbl5.Workspace:FindFirstChild("EnemyCDKSpawns") or Instance.new("Folder", tbl5.Workspace)
		enemyCDKSpawns.Name = "EnemyCDKSpawns"

		local function fn9(arg)
			if arg:IsA("Model") and arg:FindFirstChild("HumanoidRootPart") or arg:IsA("Part") then
				local clone = arg:IsA("Model") and arg.HumanoidRootPart:Clone() or arg:Clone()
				clone.Name = arg.Name:gsub("Lv. ", ""):gsub("[%[%] %d]", "")
				clone.Parent = enemySpawns
				clone.Anchored = true
			end
		end

		local tbl18 = {}

		for _, v19 in pairs({ tbl6.WorldOrigin.EnemySpawns, tbl6.Enemies, tbl5.ReplicatedStorage }) do
			for _, child in pairs(v19:GetChildren()) do
				table.insert(tbl18, child)
			end
		end

		for _, v19 in ipairs(tbl18) do
			fn9(v19)
		end

		local tbl19 = {}

		for _, child in ipairs(enemySpawns:GetChildren()) do
			local name = child.Name

			if not tbl19[name] then
				tbl19[name] = true

				if not enemyCDKSpawns:FindFirstChild(name) then
					local clone = child:Clone()
					clone.Parent = enemyCDKSpawns
					clone.Anchored = true
				end
			end
		end
	end)

	local tbl18

	tbl18 = {
		ValidateState = function(arg, arg2, arg3)
			if not arg2 then
				tbl18:HandleError(arg3 or "State validation failed")
				return false
			end
			return true
		end,
		HandleError = function(arg, arg2)
			if FH.Dev then warn("[Facility] " .. tostring(arg2)) end
		end,
		CreateLoop = function(arg, arg2, arg3, arg4)
			local n3 = math.max(arg4 or 0, 0)
			if tbl17.__loops[arg2] then
				return
			end
			tbl17.__loops[arg2] = true
			tbl17.__metadata[arg2] = { start = tick(), errors = 0, runs = 0, lastRun = 0 }

			local function fn9()
				local ok3, result3 = pcall(arg3)
				local v19 = tbl17.__metadata[arg2]

				if v19 then
					if ok3 then
						v19.runs = v19.runs + 1
						v19.lastRun = tick()
					else
						v19.errors = v19.errors + 1
						tbl18:HandleError(result3)
					end
				end

				return ok3
			end

			tbl4.__spawn(function()
				while true do
					if tbl17.__loops[arg2] and tbl17.__running then
						if not v9.Unloaded then
							if tbl14[arg2] then
								fn9()
							end

							if n3 > 0 then
								task.wait(n3)
							else
								task.wait()
							end

							continue
						end
					end

					break
				end

				tbl17.__loops[arg2] = nil
				tbl17.__metadata[arg2] = nil
			end)
		end,
	}

	local tbl19 = {
		__features = {
			"Auto Farm Level",
			"Auto Farm Nearest",
			"Auto Farm Mastery",
			"Auto Collect Chest",
			"Auto Collect Berry",
			"Auto Factory",
			"Auto Attack Boss",
			"Auto Attack All Boss",
			"Auto Pirates Sea",
			"Auto Farm Material",
			"Auto Get Sword",
			"Auto Get Serpent Bow",
			"Auto Farm Bones",
			"Auto Cake Prince",
			"Auto Dough King",
			"Auto Elite Hunter",
			"Auto Soul Reaper",
			"Auto Citizen Quest",
			"Auto Summon Kitsune Island",
			"Tween to Kitsune Island",
			"Auto Collect Azure Ember",
			"Auto Farm Sea",
			"Tween to Frozen Dimension",
			"Auto Find Leviathan",
			"Auto Attack Leviathan",
			"Auto Attack Leviathan Segment",
			"Auto Attack Leviathan Tail",
			"Auto Wood Planks",
			"Tween To Island",
			"Auto Find Fruit",
			"Auto Gets Fruit Spawner",
			"Auto Summon Mirage Island",
			"Tween To Mirage Island",
			"Auto Raid",
			"Auto Collect Gift",
			"Auto Summon Prehistoric Island",
			"Tween To Prehistoric Island",
			"Auto Dragon Hunter Quests",
			"Auto Kill Player After Trial",
			"Auto Trial",
			"Auto V2",
			"Auto V3",
		},
	}

	tbl18.IsAnyFeatureActive = function()
		for i = 1, #tbl19.__features do
			if tbl14[tbl19.__features[i]] then
				return true
			end
		end

		return false
	end

	tbl18.FindNearestTeleporter = function(arg, arg2)
		local position = arg2.Position
		local placeId2 = game.PlaceId
		local tbl20 = {}

		if placeId2 == 7449423635 then
			tbl20 = {
				["Castle On The Sea"] = Vector3.new(-5058.775, 314.5155, -3155.8833),
				Hydra = Vector3.new(5756.8374, 610.424, -253.9254),
				Mansion = Vector3.new(-12463.874, 374.9145, -7523.774),
				["Great Tree"] = Vector3.new(28282.57, 14896.851, 105.1043),
				["Temple Clock"] = Vector3.new(28282.57, 14896.851, 105.10427),
			}
		elseif placeId2 == 4442272183 then
			tbl20 = {
				Mansion = Vector3.new(-288.4625, 306.1306, 597.9988),
				Flamingo = Vector3.new(2284.912, 15.152, 905.4829),
				["122"] = Vector3.new(923.2125, 126.976, 32852.832),
				["3032"] = Vector3.new(-6508.558, 89.035, -132.8395),
			}
		elseif placeId2 == 2753915549 then
			tbl20 = {
				["1"] = Vector3.new(-7894.62, 5545.4917, -380.2467),
				["2"] = Vector3.new(-4607.8228, 872.5423, -1667.5569),
				["3"] = Vector3.new(61163.85, 11.7595, 1819.7842),
				["4"] = Vector3.new(3876.2805, 35.1061, -1939.3202),
			}
		end

		if not next(tbl20) then
			return nil
		end
		local huge = math.huge
		local v19 = nil

		for _, v20 in pairs(tbl20) do
			local magnitude = (v20 - position).Magnitude

			if magnitude < huge then
				huge = magnitude
				v19 = v20
			end
		end

		local character = localPlayer.Character
		local humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart")
		if not humanoidRootPart then
			return nil
		end

		if huge <= (position - humanoidRootPart.Position).Magnitude then
			return v19
		end
		return nil
	end

	local tbl20 = { __activeController = nil }

	tbl18.CreateTweenController = function(arg, arg2)
		local tbl21 = {}
		if not arg2 or not arg2.Parent then
			return nil
		end
		local v19 = arg2
		local assemblyLinearVelocity = v19.AssemblyLinearVelocity
		local tbl22 = {}
		local tbl23 = {}
		local tween = nil
		local bodyVelocity = nil
		local flag = false
		local connection = nil

		local function fn9()
			if connection then
				connection:Disconnect()
				connection = nil
			end

			if tween then
				tween:Cancel()
				tween = nil
			end

			if bodyVelocity then
				bodyVelocity:Destroy()
				bodyVelocity = nil
			end

			for _, descendant in pairs(v19.Parent:GetDescendants()) do
				if descendant:IsA("BasePart") then
					if tbl22[descendant] ~= nil then
						descendant.CanCollide = tbl22[descendant]
					else
						descendant.CanCollide = true
					end

					tbl22[descendant] = nil

					if tbl23[descendant] ~= nil then
						descendant.Anchored = tbl23[descendant]
						tbl23[descendant] = nil
					end
				end
			end

			v19.AssemblyLinearVelocity = assemblyLinearVelocity
			v19.AssemblyAngularVelocity = Vector3.zero
			flag = false
		end

		tbl21.ExecuteTween = function(arg3, arg4, arg5)
			if flag then
				fn9()
			end

			assemblyLinearVelocity = v19.AssemblyLinearVelocity

			for _, descendant in pairs(v19.Parent:GetDescendants()) do
				if descendant:IsA("BasePart") then
					tbl22[descendant] = descendant.CanCollide
					tbl23[descendant] = descendant.Anchored
					descendant.CanCollide = false
				end
			end

			v19.AssemblyLinearVelocity = Vector3.zero
			v19.AssemblyAngularVelocity = Vector3.zero
			bodyVelocity = Instance.new("BodyVelocity")
			bodyVelocity.MaxForce = Vector3.new(4000, 4000, 4000)
			bodyVelocity.Velocity = Vector3.zero
			bodyVelocity.Parent = v19
			local n3 = math.max(0.05, (v19.CFrame.Position - arg4.Position).Magnitude / math.max(arg5 or 100, 0.01))
			flag = true
			tween = tbl5.TweenService:Create(v19, TweenInfo.new(n3, Enum.EasingStyle.Linear), { CFrame = arg4 })

			connection = tween.Completed:Connect(function()
				fn9()
			end)

			tween:Play()
		end

		tbl21.Destroy = function()
			fn9()
		end

		return tbl21
	end

	tbl18.ExecuteTween = function(arg, arg2, arg3)
		local character = localPlayer.Character
		character = character and character:FindFirstChild("HumanoidRootPart")
		if not character then
			return
		end

		if tbl20.__activeController then
			pcall(function()
				tbl20.__activeController:Destroy()
			end)
		end

		tbl20.__activeController = tbl18:CreateTweenController(character)
		local n3 = tonumber(arg3) or tonumber(tbl14["Tween Speed"]) or 100

		if n3 <= 0 then
			n3 = 100
		end

		local position = arg2.Position

		if (Vector3.new(10213.701, -1733.5026, 9940.189) - position).Magnitude <= 3500 and localPlayer:DistanceFromCharacter(Vector3.new(10213.701, -1733.5026, 9940.189)) > 3500 then
			if localPlayer:DistanceFromCharacter(Vector3.new(-16267, 25, 1371)) > 5 then
				tbl20.__activeController:ExecuteTween(CFrame.new(-16267, 25, 1371), n3)
			else
				tbl5.ReplicatedStorage.Modules.Net["RF/SubmarineWorkerSpeak"]:InvokeServer("TravelToSubmergedIsland")
			end

			return
		end

		if localPlayer:GetAttribute("CurrentLocation") == "Submerged Island" and (Vector3.new(10213.701, -1733.5026, 9940.189) - position).Magnitude > 3500 then
			if localPlayer:DistanceFromCharacter(Vector3.new(11426, -2155, 9730)) > 5 then
				tbl20.__activeController:ExecuteTween(CFrame.new(11426, -2155, 9730), n3)
			else
				tbl5.ReplicatedStorage.Modules.Net:FindFirstChild("RF/SubmarineTransportation"):InvokeServer("InitiateTeleport", "Tiki Outpost")
			end

			return
		end

		if not _G.Teleporting then
			local v19 = tbl18:FindNearestTeleporter(arg2)

			if v19 then
				_G.Teleporting = true
				character.AssemblyLinearVelocity = Vector3.zero
				character.AssemblyAngularVelocity = Vector3.zero
				tbl5.ReplicatedStorage.Remotes.CommF_:InvokeServer("requestEntrance", v19)

				task.delay(1, function()
					_G.Teleporting = false
				end)

				return
			end
		end

		if tbl20.__activeController then
			tbl20.__activeController:ExecuteTween(arg2, n3)
		end
	end

	tbl18.StopTween = function(arg, arg2)
		tbl4.__spawn(function()
			if not arg2 then
				if tbl20.__activeController then
					tbl20.__activeController:Destroy()
					tbl20.__activeController = nil
				end
			end
		end)
	end

	local tbl21 = {
		__connection = nil,
		__characterConnection = nil,
		__currentCharacter = nil,
		__lastUpdate = 0,
		__updateInterval = 0.2,
		__disabledParts = {},
	}

	local function fn9(arg)
		if not arg or not arg.Parent then
			return
		end

		for _, descendant in pairs(arg:GetDescendants()) do
			if descendant:IsA("BasePart") and descendant.CanCollide then
				if not tbl21.__disabledParts[descendant] then
					tbl21.__disabledParts[descendant] = true
					descendant.CanCollide = false
				end
			end
		end

		if tbl21.__characterConnection then
			tbl21.__characterConnection:Disconnect()
			tbl21.__characterConnection = nil
		end

		tbl21.__characterConnection = arg.DescendantAdded:Connect(function(descendant)
			if descendant:IsA("BasePart") and descendant.CanCollide then
				if not tbl21.__disabledParts[descendant] then
					tbl21.__disabledParts[descendant] = true

					task.defer(function()
						descendant.CanCollide = false
					end)
				end
			end
		end)
	end

	local function fn10(arg)
		if not arg then
			return
		end

		for k in pairs(tbl21.__disabledParts) do
			if k and k.Parent and k:IsA("BasePart") then
				k.CanCollide = true
			end

			tbl21.__disabledParts[k] = nil
		end

		if tbl21.__characterConnection then
			tbl21.__characterConnection:Disconnect()
			tbl21.__characterConnection = nil
		end
	end

	tbl21.__connection = tbl5.RunService.Stepped:Connect(function()
		local now2 = tick()
		if now2 - tbl21.__lastUpdate < tbl21.__updateInterval then
			return
		end
		tbl21.__lastUpdate = now2
		local character = localPlayer.Character

		if v9.Unloaded then
			tbl21.__connection:Disconnect()

			if tbl21.__characterConnection then
				tbl21.__characterConnection:Disconnect()
				tbl21.__characterConnection = nil
			end

			fn10(tbl21.__currentCharacter)
			return
		end

		if tbl18:IsAnyFeatureActive() and character and character ~= tbl21.__currentCharacter then
			if tbl21.__currentCharacter then
				fn10(tbl21.__currentCharacter)
			end

			tbl21.__currentCharacter = character
			fn9(character)
		elseif not tbl18:IsAnyFeatureActive() and tbl21.__currentCharacter then
			fn10(tbl21.__currentCharacter)
			tbl21.__currentCharacter = nil
		end
	end)

	tbl18.TweenToTargetIfFar = function(arg, arg2, arg3)
		if tbl18:GetDistance(arg2) > arg3 then
			tbl18:ExecuteTween(arg2)
			return true
		end
		return false
	end

	tbl18.ExecuteBoatTween = function(arg, arg2, arg3)
		if not (arg2 and arg2.PrimaryPart and arg3) then
			return
		end
		local primaryPart = arg2.PrimaryPart

		if not primaryPart:FindFirstChild("Speed_Hub_X_Boat_BodyVelocity") then
			local bodyVelocity = Instance.new("BodyVelocity")
			bodyVelocity.Name = "Speed_Hub_X_Boat_BodyVelocity"
			bodyVelocity.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
			bodyVelocity.Velocity = Vector3.zero
			bodyVelocity.Parent = primaryPart
		end

		local linear = Enum.EasingStyle.Linear
		local out = Enum.EasingDirection.Out
		local tween = tbl5.TweenService:Create(primaryPart, TweenInfo.new(math.max(0.1, (primaryPart.Position - arg3.p).Magnitude / 250), linear, out), { CFrame = arg3 })

		pcall(function()
			tween:Play()
		end)
	end

	tbl18.ServerHop = function(arg, text, arg2)
		local n3 = arg2 or tonumber(tbl14["Count Player"]) or 5
		text = text or "Singapore"

		for i = 1, 100 do
			pcall(function()
				playerGui.ServerBrowser.Frame.Filters.SearchRegion.TextBox.Text = text
			end)

			local response = tbl5.ReplicatedStorage.__ServerBrowser:InvokeServer(i)

			for k, v19 in pairs(response) do
				if k ~= game.JobId and v19.Count <= n3 and not string.find(tostring(v19.Private), "true") then
					tbl4.__spawn(function()
						tbl5.ReplicatedStorage.__ServerBrowser:InvokeServer("teleport", k)
					end)
				end
			end
		end
	end

	tbl18.FireRemote = function(...)
		return tbl6.CommF_:InvokeServer(select(2, ...))
	end

	tbl18.IsEntityAlive = function(arg, arg2)
		local humanoid = arg2:FindFirstChild("Humanoid")
		return humanoid and humanoid.Health > 0
	end

	tbl18.GetDistance = function(arg, arg2)
		local character = localPlayer.Character
		if not character or not character.PrimaryPart then
			return math.huge
		end
		local position

		if typeof(arg2) == "CFrame" then
			position = arg2.Position
		else
			if typeof(arg2) ~= "Vector3" then
				return math.huge
			end
			position = arg2
		end

		return (character.PrimaryPart.Position - position).Magnitude
	end

	tbl18.ActivateHaki = function()
		local character = localPlayer.Character

		if not character or not character:FindFirstChild("HasBuso") then
			tbl18:FireRemote("Buso")
		end
	end

	tbl18.EquipToolByName = function(arg, arg2)
		local backpack = localPlayer.Backpack
		local character = localPlayer.Character
		if not (backpack and character) then
			return
		end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local v19 = backpack:FindFirstChild(arg2)

		if humanoid and v19 and v19:IsA("Tool") then
			humanoid:EquipTool(v19)
		end
	end

	tbl18.EquipToolByTip = function(arg, arg2)
		local backpack = localPlayer.Backpack
		if not backpack then
			return
		end
		local children = backpack:GetChildren()

		for i = 1, #children do
			local v19 = children[i]
			if v19:IsA("Tool") and v19.ToolTip == arg2 then
				tbl18:EquipToolByName(v19.Name)
				return
			end
		end
	end

	tbl18.EquipSelectedTool = function()
		local backpack = localPlayer.Backpack
		if not backpack then
			return
		end
		local weaponTool = tbl14["Weapon Tool"]
		local children = backpack:GetChildren()

		for i = 1, #children do
			local v19 = children[i]
			if v19:IsA("Tool") and v19.ToolTip == weaponTool then
				tbl18:EquipToolByName(v19.Name)
				return
			end
		end
	end

	tbl18.UnequipTool = function(arg, arg2)
		local character = localPlayer.Character
		if not character then
			return
		end
		local v19 = character:FindFirstChild(arg2)

		if v19 and v19:IsA("Tool") then
			v19.Parent = localPlayer.Backpack
		end
	end

	tbl18.HasTool = function(arg, arg2)
		local character = localPlayer.Character
		if not character then
			return false
		end
		return character:FindFirstChild(arg2) ~= nil or localPlayer.Backpack:FindFirstChild(arg2) ~= nil
	end

	tbl18.FindToolByTip = function(arg, arg2)
		local function fn11(arg3)
			if not arg3 then
				return nil
			end
			local children = arg3:GetChildren()

			for i = 1, #children do
				local v19 = children[i]
				if v19:IsA("Tool") and v19.ToolTip == arg2 then
					return v19
				end
			end

			return nil
		end

		return fn11(localPlayer.Backpack) or fn11(localPlayer.Character)
	end

	tbl18.SendKeyPress = function(arg, arg2, arg3)
		local n3 = arg3 or 0
		tbl5.VirtualInputManager:SendKeyEvent(true, arg2, false, game)

		if n3 > 0 then
			task.wait(n3)
		end

		tbl5.VirtualInputManager:SendKeyEvent(false, arg2, false, game)
	end

	local tbl22 = {
		["rbxassetid://9802959564"] = true,
		["rbxassetid://507766388"] = true,
		["http://www.roblox.com/asset/?id=9884584522"] = true,
	}

	tbl18.MonitorSkillUsage = function(arg, arg2)
		if not arg2 or not arg2.Parent then
			return
		end
		local humanoid = arg2:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			return
		end
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if not animator then
			return
		end

		animator.AnimationPlayed:Connect(function(arg3)
			if not arg3 or not arg3.Animation then
				return
			end

			if tbl22[arg3.Animation.AnimationId] then
				return
			end
			local n3 = math.max(arg3.TimePosition or 1.5, 1.5)

			if tbl14["Auto Dodge Skill"] then
				local dodgeTime = _G.DodgeTime or 0

				if tick() < dodgeTime then
					_G.DodgeTime = dodgeTime + math.floor(n3)
				else
					_G.DodgeTime = tick() + math.floor(n3)
				end
			end
		end)
	end

	tbl18.isInTable = function(arg, arg2, arg3)
		for _, v19 in pairs(arg2) do
			if v19 == arg3 then
				return true
			end
		end

		return false
	end

	tbl18.converttoTable = function(arg, arg2)
		local tbl23 = {}

		for match in arg2:gmatch("[^%[%],%s]+") do
			local str2 = match:gsub("^'", ""):gsub("'$", "")

			if tonumber(str2) then
				table.insert(tbl23, tonumber(str2))
			else
				table.insert(tbl23, str2)
			end
		end

		return tbl23
	end

	tbl18.smartBossTeleport = function(arg, arg2, arg3, arg4, arg5)
		for _, v19 in pairs(arg2) do
			if arg:isInTable(v19, arg3) then
				if arg4 and arg4 ~= "" then
					local v20 = v9
					local setNotification = v20.SetNotification
					local tbl23 = {}
					local str2 = "JobId: " .. tostring(arg4) .. " | Boss: " .. tostring(arg3)
					tbl23[1] = "Facility"
					tbl23[2] = "Hop Boss"
					tbl23[3] = str2
					tbl23[4] = 5
					tbl23[5] = 0.5
					setNotification(v20, tbl23)
					task.wait(1)
					game:GetService("TeleportService"):TeleportToPlaceInstance(arg5, arg4, localPlayer)
					return
				end
			end
		end
	end

	tbl18.bossData = function(arg, arg2)
		local tbl23 = {}
		local request_ = syn and syn.request
		local request_2

		if request_ then
			request_2 = request_
		else
			request_2 = http and http.request
		end

		local v19 = (request_2 or http_request or request)({ Url = "https://prvf.onrender.com/data", Method = "GET" })
		if not v19 or not v19.Body then
			return {}
		end
		local data = game:GetService("HttpService"):JSONDecode(v19.Body)

		for k, v20 in pairs(data) do
			for _, v21 in v20, nil, nil do
				if v21 == arg2 then
					tbl23[#tbl23 + 1] = { id = k, name = v20 }
				end
			end
		end

		local n3 = math.random(1, #tbl23)
		return #tbl23 > 0 and tbl23[n3]
	end

	local str2 = tostring(localPlayer.UserId):sub(2, 4) .. "078da"

	local function fn11()
		local ok3, result3 = pcall(function()
			local global = tbl5.ReplicatedStorage and tbl5.ReplicatedStorage:FindFirstChild("Global")

			if global then
				for _, v19 in pairs(getupvalues(require(global).SendHitsToServer)) do
					if type(v19) == "thread" and coroutine.status(v19) ~= "dead" then
						return v19
					end
				end
			end
		end)

		return ok3 and result3 or nil
	end

	local tbl23

	tbl23 = {
		__cache = {
			enemy = { t = 0, list = {} },
			enemySnapshot = { t = 0, list = nil },
			attack = { t = 0, isAttacking = false, lastGunTime = 0, hit = { [2] = {} } },
		},
		__m1State = { last = 0, delay = 0 },
		__animCache = {},
		__snapshotExpiry = 0,
		__cachedSnapshot = nil,
		__range = 4225,
		__cacheInterval = 0.5,
		ExecuteFruitM1 = function(arg, arg2)
			local ok3, result3 = pcall(function()
				local now2 = tick()
				local last = tbl23.__m1State.last or 0
				local delay_ = tbl23.__m1State.delay or 0
				local delay_2

				if now2 - last <= 0.4 then
					delay_2 = math.min(delay_ + 1, 4)
				else
					delay_2 = 1
				end

				tbl23.__m1State.last = now2
				tbl23.__m1State.delay = delay_2
				local character = localPlayer.Character
				if not character then
					return
				end
				local primaryPart = character.PrimaryPart
				if not primaryPart then
					return
				end
				local position = primaryPart.Position
				local children = tbl6.Enemies and tbl6.Enemies:GetChildren() or {}

				for i = 1, #children do
					local v19 = children[i]

					if v19 and v19.Parent then
						local primaryPart2 = v19.PrimaryPart

						if primaryPart2 and tbl18 and tbl18:IsEntityAlive(v19) then
							local n3 = primaryPart2.Position.X - position.X
							local n4 = primaryPart2.Position.Y - position.Y
							local n5 = primaryPart2.Position.Z - position.Z

							if n3 * n3 + n4 * n4 + n5 * n5 <= 2500 then
								arg2.LeftClickRemote:FireServer((primaryPart2.Position - position).Unit, delay_2)
							end
						end
					end
				end
			end)

			if not ok3 then
				warn("[FruitM1 Error]: " .. tostring(result3))
			end
		end,
	}

	local thread = coroutine.create(function()
		pcall(function()
			if not tbl7.RegisterHit then
				return
			end
			tbl7.RegisterHit:FireServer(str2)

			while true do
				local v19, v20 = coroutine.yield()
				tbl7.RegisterHit:FireServer(v19, v20, nil, str2)
			end
		end)
	end)

	coroutine.resume(thread)

	tbl23.GetHits = function(arg, arg2)
		local tbl24 = {}
		local character = localPlayer.Character
		local humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart")
		if not humanoidRootPart then
			return tbl24
		end

		for _, v19 in ipairs({ workspace.Enemies, workspace.Characters }) do
			for _, child in ipairs(v19:GetChildren()) do
				local humanoid = child:FindFirstChildOfClass("Humanoid")
				local humanoidRootPart2 = child:FindFirstChild("HumanoidRootPart")

				if child ~= character and humanoid and humanoidRootPart2 and humanoid.Health > 0 and (humanoidRootPart2.Position - humanoidRootPart.Position).Magnitude <= arg2 then
					local insert = table.insert
					local tbl25 = {}
					local head = child:FindFirstChild("Head") or humanoidRootPart2
					tbl25[1] = child
					tbl25[2] = head
					insert(tbl24, tbl25)
				end
			end
		end

		return tbl24
	end

	tbl23.ExecuteAttack = function(arg)
		local character = localPlayer.Character
		local tool = character and character:FindFirstChildOfClass("Tool")
		if not (tool and table.find({ "Melee", "Sword", "Blox Fruit", "Gun" }, tool.ToolTip)) then
			return
		end
		local hits = arg:GetHits(60)

		if #hits > 0 then
			tbl7.RegisterAttack:FireServer(0)
			local v19 = table.remove(hits, 1)[2]
			local v20 = fn11() or thread

			if v20 then
				coroutine.resume(v20, v19, hits)
			else
				tbl7.RegisterHit:FireServer(v19, hits, nil, str2)
			end
		end
	end

	tbl18.ExecuteBladeHits = function()
		xpcall(function()
			local character = localPlayer.Character
			if not character then
				return
			end
			local tool = character:FindFirstChildWhichIsA("Tool")
			if not tool then
				return
			end
			local toolTip = tool.ToolTip

			if toolTip == "Blox Fruit" and tool:FindFirstChild("LeftClickRemote") then
				tbl23:ExecuteFruitM1(tool)
			elseif toolTip ~= "Gun" then
				tbl23:ExecuteAttack()
			else
				task.wait(0.5)
			end
		end, function(arg)
			warn("[ExecuteBladeHits Error]: " .. tostring(arg))
			tbl23.__cache.attack.isAttacking = false
		end)
	end

	tbl18.InteractWithMirror = function()
		local character = localPlayer.Character
		character = character and character:FindFirstChild("HumanoidRootPart")
		if not character then
			return
		end
		local main = tbl5.Workspace.Map.CakeLoaf.BigMirror.Main
		firetouchinterest(character, main, 0)
		task.wait()
		firetouchinterest(character, main, 1)
	end

	tbl18.CheckStackPriority = function(arg, arg2)
		if not tbl14["Stack Farming Enabled"] then
			return true
		end
		local tbl24 = {}

		local tbl25 = {
			name = "Auto Farm Level",
			priority = tonumber(tbl14["Priority: Auto Farm Level"]) or 1,
			check = function()
				if not tbl14["Auto Farm Level"] then
					return false
				end

				local ok3, result3 = pcall(function()
					return tbl18:GetQuestInfo(tbl14["Auto Farm Level"])
				end)

				if not ok3 or not result3 or not result3[3] then
					return false
				end
				return tbl18:FindEnemy({ result3[3] }) ~= nil
			end,
		}

		local tbl26 = {
			name = "Auto Farm Nearest",
			priority = tonumber(tbl14["Priority: Auto Farm Nearest"]) or 2,
			check = function()
				if not tbl14["Auto Farm Nearest"] then
					return false
				end

				for _, child in pairs(tbl6.Enemies:GetChildren()) do
					if child and tbl18:IsEntityAlive(child) and child:FindFirstChild("HumanoidRootPart") then
						return true
					end
				end

				return false
			end,
		}

		local tbl27 = {
			name = "Auto Farm Mastery",
			priority = tonumber(tbl14["Priority: Auto Farm Mastery"]) or 3,
			check = function()
				if not tbl14["Auto Farm Mastery"] then
					return false
				end

				if not tbl14["Choose Mastery Mode"] then
					return false
				end
				local chooseMasteryMode = tbl14["Choose Mastery Mode"]

				if chooseMasteryMode == "Level" then
					local ok3, result3 = pcall(function()
						return tbl18:GetQuestInfo(tbl14["Auto Farm Mastery"])
					end)

					if ok3 and result3 and result3[3] then
						return tbl18:FindEnemy({ result3[3] }) ~= nil
					end
				else
					if chooseMasteryMode == "Bone" then
						return tbl18:FindEnemy({ "Reborn Skeleton", "Demonic Soul", "Living Zombie", "Possessed Mummy" }) ~= nil
					end

					if chooseMasteryMode == "Cake Prince" then
						return tbl18:FindEnemy({ "Baking Staff", "Head Baker", "Cake Guard", "Cookie Crafter" }) ~= nil
					end

					if chooseMasteryMode == "Neareast" then
						for _, child in pairs(tbl6.Enemies:GetChildren()) do
							if child and tbl18:IsEntityAlive(child) and child:FindFirstChild("HumanoidRootPart") then
								return true
							end
						end
					end
				end

				return false
			end,
		}

		local tbl28 = {
			name = "Auto Collect Chest",
			priority = tonumber(tbl14["Priority: Auto Collect Chest"]) or 4,
			check = function()
				if not tbl14["Auto Collect Chest"] then
					return false
				end
				local tagged = tbl5.CollectionService:GetTagged("_ChestTagged")
				local flag = false

				for _, v19 in ipairs(tagged) do
					v19 = v19 and not v19:GetAttribute("IsDisabled")
					if v19 then
						flag = true
						break
					end
				end

				return flag
			end,
		}

		local tbl29 = {
			name = "Auto Collect Berry",
			priority = tonumber(tbl14["Priority: Auto Collect Berry"]) or 5,
			check = function()
				if not tbl14["Auto Collect Berry"] then
					return false
				end

				for _, descendant in pairs(tbl5.Workspace.Map:GetDescendants()) do
					if descendant.Name ~= "Berries" then
						continue
					end

					for i = 1, 8 do
						if descendant:GetAttribute("_BerryCFrame" .. i) then
							return true
						end
					end
				end

				return false
			end,
		}

		local tbl30 = {
			name = "Auto Farm Material",
			priority = tonumber(tbl14["Priority: Auto Farm Material"]) or 6,
			check = function()
				if not tbl14["Auto Farm Material"] then
					return false
				end
				local chooseMaterial = tbl14["Choose Material"]
				if not chooseMaterial or chooseMaterial == "" then
					return false
				end
				local materialData = tbl18:GetMaterialData(chooseMaterial)
				if not materialData or not materialData.NPCs then
					return false
				end
				return tbl18:FindEnemy(materialData.NPCs) ~= nil
			end,
		}

		local tbl31 = {
			name = "Auto Farm Bones",
			priority = tonumber(tbl14["Priority: Auto Farm Bones"]) or 7,
			check = function()
				if not tbl14["Auto Farm Bones"] then
					return false
				end
				return tbl18:FindEnemy({ "Soul Reaper" }) ~= nil or tbl18:FindEnemy({ "Reborn Skeleton", "Living Zombie", "Demonic Soul", "Possessed Mummy" }) ~= nil
			end,
		}

		local tbl32 = {
			name = "Auto Attack Boss",
			priority = tonumber(tbl14["Priority: Auto Attack Boss"]) or 8,
			check = function()
				if not tbl14["Auto Attack Boss"] then
					return false
				end
				local chooseBoss = tbl14["Choose Boss"]
				if not chooseBoss or chooseBoss == "" then
					return false
				end
				return tbl18:FindEnemy({ chooseBoss }) ~= nil
			end,
		}

		local tbl33 = {
			name = "Auto Attack All Boss",
			priority = tonumber(tbl14["Priority: Auto Attack All Boss"]) or 9,
			check = function()
				if not tbl14["Auto Attack All Boss"] then
					return false
				end

				for _, child in pairs(tbl5.ReplicatedStorage:GetChildren()) do
					if child and child:GetAttribute("IsBoss") and child:FindFirstChild("HumanoidRootPart") then
						return true
					end
				end

				for _, child in pairs(tbl6.Enemies:GetChildren()) do
					if child and child:GetAttribute("IsBoss") and tbl18:IsEntityAlive(child) and child:FindFirstChild("HumanoidRootPart") then
						return true
					end
				end

				return false
			end,
		}

		local tbl34 = {
			name = "Auto Soul Reaper",
			priority = tonumber(tbl14["Priority: Auto Soul Reaper"]) or 10,
			check = function()
				if not tbl14["Auto Soul Reaper"] then
					return false
				end
				return tbl18:FindEnemy({ "Soul Reaper" }) ~= nil or tbl18:HasTool("Hallow Essence")
			end,
		}

		local tbl35 = {
			name = "Auto Elite Hunter",
			priority = tonumber(tbl14["Priority: Auto Elite Hunter"]) or 11,
			check = function()
				if not tbl14["Auto Elite Hunter"] then
					return false
				end
				return tbl18:FindEnemy({ "Diablo", "Deandre", "Urban" }) ~= nil or tbl18:isQuestOn()
			end,
		}

		local tbl36 = {
			name = "Auto Kill Tyrant of the Skies",
			priority = tonumber(tbl14["Priority: Auto Kill Tyrant of the Skies"]) or 12,
			check = function()
				if not tbl14["Auto Kill Tyrant of the Skies"] then
					return false
				end
				return tbl18:FindEnemy({ "Auto Kill Tyrant of the Skies" }) ~= nil
			end,
		}

		local tbl37 = {
			name = "Auto Citizen Quest",
			priority = tonumber(tbl14["Priority: Auto Citizen Quest"]) or 13,
			check = function()
				if not tbl14["Auto Citizen Quest"] then
					return false
				end
				return tbl18:FindEnemy({ "Stone", "Island Empress", "Kilo Admiral", "Captain Elephant", "Beautiful Pirate" }) ~= nil
			end,
		}

		local tbl38 = {
			name = "Auto Dough King",
			priority = tonumber(tbl14["Priority: Auto Dough King"]) or 14,
			check = function()
				if not tbl14["Auto Dough King"] then
					return false
				end
				return tbl18:HasTool("God's Chalice") or tbl18:HasTool("Sweet Chalice") or tbl18:FindEnemy({ "Dough King" }) ~= nil
			end,
		}

		local tbl39 = {
			name = "Auto Cake Prince",
			priority = tonumber(tbl14["Priority: Auto Cake Prince"]) or 15,
			check = function()
				if not tbl14["Auto Cake Prince"] then
					return false
				end
				return tbl18:FindEnemy({ "Cake Prince", "Dough King" }) ~= nil or tbl18:FindEnemy({ "Baking Staff", "Head Baker", "Cake Guard", "Cookie Crafter" }) ~= nil
			end,
		}

		tbl24[1] = tbl25
		tbl24[2] = tbl26
		tbl24[3] = tbl27
		tbl24[4] = tbl28
		tbl24[5] = tbl29
		tbl24[6] = tbl30
		tbl24[7] = tbl31
		tbl24[8] = tbl32
		tbl24[9] = tbl33
		tbl24[10] = tbl34
		tbl24[11] = tbl35
		tbl24[12] = tbl36
		tbl24[13] = tbl37
		tbl24[14] = tbl38
		tbl24[15] = tbl39
		local v19, v20, v21 = ipairs(tbl24)
		local v22 = nil

		for _, v23 in v19, v20, v21 do
			if v23.name == arg2 then
				v22 = v23
				break
			else
				v22 = nil
			end
		end

		if not v22 or not tbl14[arg2] then
			return false
		end
		local priority = v22.priority

		for _, v23 in ipairs(tbl24) do
			if tbl14[v23.name] and v23.priority < priority then
				local ok3, result3 = pcall(v23.check)
				if ok3 and result3 then
					return false
				end
			end
		end

		return true
	end

	tbl18.BringEnemyToPosition = function(arg, arg2, cFrame)
		if not tbl14["Bring Mob"] then
			return
		end

		if not arg2 or not arg2.Parent or not cFrame then
			return
		end
		local n3 = tonumber(tbl14["Bring Mob Radius"]) or 300
		local n4 = n3 * n3
		local position = cFrame.Position

		pcall(function()
			sethiddenproperty(localPlayer, "SimulationRadius", math.huge)
			sethiddenproperty(localPlayer, "MaxSimulationRadius", math.huge)
		end)

		local children = tbl6.Enemies:GetChildren()

		for i = 1, #children do
			local v19 = children[i]

			if v19 and v19.Name == arg2.Name and not table.find({ "Shark", "Piranha", "Terrorshark" }, v19.Name) then
				local humanoid = v19:FindFirstChildOfClass("Humanoid")
				local humanoidRootPart = v19:FindFirstChild("HumanoidRootPart")
				local characterReady = v19:FindFirstChild("CharacterReady")

				if humanoid and humanoidRootPart and characterReady and humanoid.Health > 0 and humanoidRootPart:IsDescendantOf(tbl5.Workspace) then
					local n5 = humanoidRootPart.Position.X - position.X
					local n6 = humanoidRootPart.Position.Y - position.Y
					local n7 = humanoidRootPart.Position.Z - position.Z

					if n5 * n5 + n6 * n6 + n7 * n7 <= n4 then
						if not humanoidRootPart:GetAttribute("BeingBrought") then
							humanoidRootPart:SetAttribute("BeingBrought", true)
							humanoidRootPart.CanCollide = false
							humanoidRootPart.Massless = true
							local descendants = v19:GetDescendants()

							for i2 = 1, #descendants do
								local v20 = descendants[i2]

								if v20:IsA("BasePart") then
									v20.CanCollide = false
									v20.CanTouch = false
									v20.Massless = true
									v20.AssemblyLinearVelocity = Vector3.zero
									v20.AssemblyAngularVelocity = Vector3.zero
								end
							end

							local lock = humanoidRootPart:FindFirstChild("Lock")

							if not lock or not lock.Parent then
								lock = Instance.new("BodyVelocity")
								lock.Name = "Lock"
								lock.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
								lock.P = 9000
								lock.Velocity = Vector3.zero
								lock.Parent = humanoidRootPart
							end

							local bringGyro = humanoidRootPart:FindFirstChild("BringGyro")

							if not bringGyro or not bringGyro.Parent then
								bringGyro = Instance.new("BodyGyro")
								bringGyro.Name = "BringGyro"
								bringGyro.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
								bringGyro.P = 30000
								bringGyro.D = 1000
								bringGyro.Parent = humanoidRootPart
							end

							lock.P = 9000
							bringGyro.CFrame = cFrame
							humanoid.AutoRotate = false
							humanoid.PlatformStand = false
							humanoid.BreakJointsOnDeath = false

							pcall(function()
								humanoid:ChangeState(Enum.HumanoidStateType.Physics)
							end)

							humanoidRootPart.AssemblyLinearVelocity = Vector3.zero
							humanoidRootPart.AssemblyAngularVelocity = Vector3.zero

							tbl4.__spawn(function()
								local n8 = position + Vector3.new(math.random(-20, 20) / 100, math.random(-20, 20) / 100, math.random(-20, 20) / 100)
								local n9 = n8 - humanoidRootPart.Position
								local magnitude = n9.Magnitude

								if magnitude > 0.5 then
									lock.Velocity = n9.Unit * math.clamp(magnitude * 10, 20, 1200)
								else
									lock.Velocity = Vector3.zero

									pcall(function()
										humanoidRootPart.CFrame = CFrame.new(n8)
									end)
								end

								bringGyro.CFrame = cFrame
								humanoid.AutoRotate = false
								humanoid.PlatformStand = false
								humanoid.BreakJointsOnDeath = false

								pcall(function()
									humanoid:ChangeState(Enum.HumanoidStateType.Physics)
								end)

								humanoidRootPart.AssemblyLinearVelocity = Vector3.zero
								humanoidRootPart.AssemblyAngularVelocity = Vector3.zero
								task.wait(0.12)

								pcall(function()
									if lock and lock.Parent then
										lock:Destroy()
									end

									if bringGyro and bringGyro.Parent then
										bringGyro:Destroy()
									end

									if humanoidRootPart and humanoidRootPart.Parent then
										humanoidRootPart:SetAttribute("BeingBrought", false)
									end
								end)
							end)
						end
					end
				end
			end
		end
	end

	local tbl24 = {}

	updateES = function()
		for _, child in pairs(tbl5.ReplicatedStorage.FortBuilderReplicatedSpawnPositionsFolder:GetChildren()) do
			if child:IsA("Part") and child:GetAttribute("Active") then
				tbl24[child.Name] = child:GetPivot()
			end
		end
	end

	updateES()

	getEnemySpawn = function(arg)
		for k, v19 in tbl24, nil, nil do
			if k == arg then
				return v19
			end
		end
	end

	local tbl25 = {}

	tbl18.FindEnemy = function(arg, arg2, arg3, arg4)
		local character = localPlayer.Character
		character = character and character:FindFirstChild("HumanoidRootPart")
		if not character then
			return nil
		end
		local position = character.Position
		local huge = arg3 and arg3 * arg3 or math.huge
		local tbl26 = {}

		for _, v19 in ipairs(arg2) do
			tbl26[v19] = true
		end

		local children = tbl6.Enemies:GetChildren()
		local v19 = nil

		for i = 1, #children do
			local v20 = children[i]
			local humanoid = v20:FindFirstChild("Humanoid")

			if humanoid and humanoid.Health > 0 then
				local match = tbl25[v20.Name] or v20.Name:match("^(.-)%s*%[") or v20.Name
				tbl25[v20.Name] = match

				if tbl26[match] then
					local vehicleSeat = arg4 == "Boat" and v20:FindFirstChild("VehicleSeat") or v20:FindFirstChild("HumanoidRootPart")

					if vehicleSeat then
						local n3 = vehicleSeat.Position.X - position.X
						local n4 = vehicleSeat.Position.Y - position.Y
						local n5 = vehicleSeat.Position.Z - position.Z
						local n6 = n3 * n3 + n4 * n4 + n5 * n5

						if n6 < huge then
							huge = n6
							v19 = v20
						end
					end
				end
			end
		end

		return v19
	end

	local tbl26 = { angle = 0, radius = 35 }

	local function fn12(arg)
		tbl26.angle = (tbl26.angle + 5) % 360
		local v19 = math.rad(tbl26.angle)
		local n3 = tonumber(tbl14["Farm Distance"]) or 20
		local radius = tbl26.radius
		local radius2 = tbl26.radius
		return arg + Vector3.new(math.sin(v19) * radius, n3, math.cos(v19) * radius2)
	end

	local function fn13(arg)
		return fn12(arg)
	end

	tbl18.EngageEnemy = function(arg, arg2)
		for _, child in pairs(tbl6.Enemies:GetChildren()) do
			if child and table.find(arg2, child.Name) then
				local primaryPart = child.PrimaryPart
				local cFrame = primaryPart and primaryPart.CFrame

				if primaryPart and tbl18:IsEntityAlive(child) then
					tbl18:MonitorSkillUsage(child)

					while true do
						tbl5.RunService.Heartbeat:Wait()

						if not _G.DodgeTime or _G.DodgeTime < tick() then
							tbl18:EquipSelectedTool()
							tbl18:ActivateHaki()
							tbl18:BringEnemyToPosition(child, cFrame)
							tbl18:ExecuteTween(fn13(cFrame))
						else
							localPlayer.Character.PrimaryPart.CFrame = child.PrimaryPart.CFrame * CFrame.new(0, 500, 0)
						end

						if not (not tbl18:IsAnyFeatureActive() or v9.Unloaded or not child or not child.Parent or not tbl18:IsEntityAlive(child)) then
							continue
						end
						break
					end
				end
			end
		end

		for _, child in pairs(tbl5.ReplicatedStorage:GetChildren()) do
			if table.find(arg2, child.Name) and child and child.PrimaryPart then
				tbl18:ExecuteTween(CFrame.new(child.PrimaryPart.CFrame.Position + Vector3.new(0, tbl14["Farm Distance"], 10)))
			end
		end
	end

	tbl18.GetQuestInfo = function()
		local value = localPlayer.Data.Level.Value
		local str3 = tostring(localPlayer.Team)
		local character = localPlayer.Character
		character = character and character:FindFirstChild("HumanoidRootPart")
		local n3 = nil
		local cframe = nil
		local str4 = nil
		local str5 = nil
		local n4 = nil
		local str6 = nil

		local function fn14()
			return { n3, cframe, str4, str5, n4, str6 }
		end

		if value >= 1 and value <= 9 then
			if str3 == "Marines" then
				n3 = 1
				str5 = "MarineQuest"
				str4 = "Trainee"
				str6 = "Trainee"
				cframe = CFrame.new
				cframe = cframe(-2709.67944, 24.5206585, 2104.24585)
			else
				n3 = 1
				str5 = "BanditQuest1"
				str4 = "Bandit"
				str6 = "Bandit"
				cframe = CFrame.new
				cframe = cframe(1059.99731, 16.9222069, 1549.28162)
			end

			n4 = 1
			return (fn14())
		end

		if value >= 210 and value <= 249 then
			n3 = 2
			str5 = "PrisonerQuest"
			str4 = "Dangerous Prisoner"
			str6 = "Dangerous Prisoner"
			n4 = 210
			cframe = CFrame.new
			cframe = cframe(5308.93115, 1.65517521, 475.120514)
			return (fn14())
		end

		n4 = 0

		for k, v19 in pairs(require(tbl5.ReplicatedStorage.GuideModule).Data.NPCList) do
			local levels = v19.Levels

			for i = 1, #levels do
				local v20 = levels[i]

				if value >= v20 and v20 > n4 then
					n4 = v20
					n3 = #levels == 3 and i == 3 and 2 or i
					cframe = k.CFrame
				end
			end
		end

		if character and cframe then
			local magnitude = (cframe.Position - character.Position).Magnitude

			if value >= 375 and value <= 449 and magnitude > 3000 then
				tbl18:FireRemote("requestEntrance", Vector3.new(61163.85, 11.6797, 1819.7842))
			elseif value >= 450 and value <= 474 and magnitude > 3000 then
				tbl18:FireRemote("requestEntrance", Vector3.new(-4607.8228, 872.5425, -1667.5569))
			elseif value >= 475 and value <= 624 and magnitude > 5000 then
				tbl18:FireRemote("requestEntrance", Vector3.new(-7894.6177, 5547.1416, -380.2912))
			end
		end

		local Quests = require(tbl5.ReplicatedStorage.Quests)

		for k, Quest in pairs(Quests) do
			if k ~= "CitizenQuest" then
				for k2, v19 in pairs(Quest) do
					if v19.LevelReq == n4 then
						str5 = k
						n3 = k2

						for k3 in pairs(v19.Task) do
							str4 = k3
							str6 = string.split(k3, " [Lv. " .. v19.LevelReq .. "]")[1]
						end
					end
				end
			end
		end

		if str5 == "ImpelQuest" then
			str5 = "PrisonerQuest"
			n3 = 2
			str4 = "Dangerous Prisoner"
			str6 = "Dangerous Prisoner"
			n4 = 210
			cframe = CFrame.new
			cframe = cframe(5310.60547, 0.350014925, 474.946594)
		elseif str5 == "Area2Quest" and n3 == 2 then
			n3 = 1
			str4 = "Swan Pirate"
			str6 = "Swan Pirate"
			n4 = 775
		end

		if value >= 2500 and value <= 2524 then
			str4 = "Sun-kissed Warrior"
			str6 = "Sun-kissed Warriors"
		end

		return (fn14())
	end

	local n3 = 1

	tbl18.NavigateToSpawn = function(arg, arg2)
		n3 = n3 or 1
		local tbl27 = {}

		for i = 1, #arg2 do
			tbl27[arg2[i]:gsub("Lv%.", ""):gsub("[%[%] %d]", ""):gsub("%s+", "")] = true
		end

		local tbl28 = {}
		local fortBuilderReplicatedSpawnPositi = game:GetService("ReplicatedStorage"):FindFirstChild("FortBuilderReplicatedSpawnPositionsFolder")

		if fortBuilderReplicatedSpawnPositi then
			for _, child in ipairs(fortBuilderReplicatedSpawnPositi:GetChildren()) do
				if child:IsA("Part") and child:GetAttribute("Active") then
					if tbl27[child.Name:gsub("Lv%.", ""):gsub("[%[%] %d]", ""):gsub("%s+", "")] then
						table.insert(tbl28, child:GetPivot())
					end
				end
			end
		end

		if #tbl28 == 0 then
			return false
		end

		if #tbl28 < n3 then
			n3 = 1
		end

		local v19 = tbl28[n3]
		if not v19 then
			return false
		end
		local distance = tbl18:GetDistance(v19.Position)

		if distance > 20 then
			if distance > 150 then
				tbl18:ExecuteTween(v19 * CFrame.new(0, 65, 5))
			else
				tbl18:ExecuteTween(v19 * CFrame.new(0, 30, 5))
			end
		end

		n3 = n3 % #tbl28 + 1
		return true
	end

	tbl18.IsSkillAvailable = function(arg, arg2)
		local tool = localPlayer.Character:FindFirstChildOfClass("Tool")
		if not tool then
			return false
		end
		local v19 = playerGui.Main.Skills[tool.Name]
		if not v19 then
			return false
		end
		local v20 = next
		local children, v21 = v19:GetChildren()

		for _, v22 in v20, children, v21 do
			if v22 and v22:IsA("Frame") and v22.Name == arg2 then
				local title = v22:FindFirstChild("Title")
				if title and title.TextColor3 == Color3.fromRGB(255, 255, 255) then
					return true
				end
			end
		end

		return false
	end

	tbl18.InteractWithPrompt = function(arg, arg2, maxActivationDistance)
		if not (arg2 and arg2:IsA("ProximityPrompt")) then
			return
		end
		arg2.MaxActivationDistance = maxActivationDistance or 10

		pcall(function()
			arg2:InputHoldBegin()
			task.wait(arg2.HoldDuration + 1)
			arg2:InputHoldEnd()
		end)
	end

	tbl18.FindNearestPrompt = function(arg, arg2)
		local v19 = next
		local descendants, v20 = tbl5.Workspace:GetDescendants()

		for _, v21 in v19, descendants, v20 do
			if v21:IsA("ProximityPrompt") then
				if ((v21.Parent:IsA("BasePart") and v21.Parent.Position or v21.Parent:IsA("Model") and v21.Parent:GetPivot().Position) - localPlayer.Character:FindFirstChild("HumanoidRootPart").Position).Magnitude <= arg2 then
					tbl18:InteractWithPrompt(v21)
				end
			end
		end
	end

	tbl18.GetBossList = function()
		local tbl27 = {}

		local function fn14(arg)
			for _, v19 in ipairs(arg) do
				local humanoid = v19:FindFirstChildOfClass("Humanoid")

				if humanoid and humanoid.DisplayName:find("Boss") then
					table.insert(tbl27, v19.Name)
				end
			end
		end

		fn14(tbl5.ReplicatedStorage:GetDescendants())
		fn14(tbl6.Enemies:GetDescendants())
		return tbl27
	end

	tbl18.GetBossID = function()
		return nil
	end

	tbl18.GetMaterialList = function()
		if tbl8[1] then
			return { "Angel Wings", "Leather + Scrap Metal", "Magma Ore", "Fish Tail" }
		end

		if tbl8[2] then
			return {
				"Leather + Scrap Metal",
				"Magma Ore",
				"Mystic Droplet",
				"Radioactive Material",
				"Vampire Fang",
			}
		end

		if tbl8[3] then
			return {
				"Leather + Scrap Metal",
				"Fish Tail",
				"Gunpowder",
				"Mini Tusk",
				"Conjured Cocoa",
				"Dragon Scale",
			}
		end
	end

	tbl18.GetMaterialData = function(arg, arg2)
		local tbl27 = {
			Sea1 = {
				["Angel Wings"] = { { "Royal Soldier", "Royal Squad" }, CFrame.new(-7742, 5634, -1564) },
				["Leather + Scrap Metal"] = { { "Pirate", "Brute" }, CFrame.new(-1257, 54, 4091) },
				["Magma Ore"] = { { "Military Soldier" }, CFrame.new(-5408, 11, 8456) },
				["Fish Tail"] = { { "Fishman Warrior" }, CFrame.new(60931, 19, 1574) },
			},
			Sea2 = {
				["Leather + Scrap Metal"] = { { "Scrap Metal" }, CFrame.new(-1026, 73, 1375) },
				["Magma Ore"] = { { "Lava Pirate" }, CFrame.new(-5241, 50, -4713) },
				["Mystic Droplet"] = { { "Water Fighter" }, CFrame.new(-3350, 282, -10527) },
				["Radioactive Material"] = { { "Factory Staff" }, CFrame.new(-73, 149, -112) },
				["Vampire Fang"] = { { "Vampire" }, CFrame.new(-6030, 6, -1281) },
			},
			Sea3 = {
				["Leather + Scrap Metal"] = { { "Pirate Millionaire" }, CFrame.new(-364, 116, 5692) },
				["Fish Tail"] = { { "Fishman Captain", "Fishman Raider" }, CFrame.new(-10679, 398, -8975) },
				Gunpowder = { { "Pistol Billionaire" }, CFrame.new(-394, 135, 5981) },
				["Mini Tusk"] = { { "Mythological Pirate" }, CFrame.new(-13510, 584, -6986) },
				["Conjured Cocoa"] = { { "Cocoa Warrior", "Chocolate Bar Battler" }, CFrame.new(400, 81, -12257) },
				["Dragon Scale"] = { { "Dragon Crew Archer" }, CFrame.new(6689, 378, 331) },
			},
		}

		local v19 = tbl8[1] or tbl8[2] or tbl8[3]
		local value = nil
		local v20 = nil

		if v19 then
			local v21 = tbl27[tbl8[1] and "Sea1" or tbl8[2] and "Sea2" or "Sea3"][arg2]
			value = nil
			v20 = nil

			if v21 then
				value, v20 = unpack(v21)
			end
		end

		return { NPCs = value, Position = v20 }
	end

	tbl18.GetMaterialCount = function(arg, arg2)
		for _, v19 in pairs(fn8()) do
			if type(v19) == "table" and v19.Type == "Material" then
				if v19.Name == arg2 then
					return v19.Count
				end
			end
		end

		return 0
	end

	tbl18.GetRaceInfo = function()
		local value = localPlayer.Data.Race.Value
		local commF = tbl5.ReplicatedStorage.Remotes.CommF_
		if localPlayer.Character:FindFirstChild("RaceTransformed") then
			return value .. " V4"
		end

		if commF:InvokeServer("Wenlocktoad", "1") == -2 then
			return value .. " V3"
		end

		if commF:InvokeServer("Alchemist", "1") == -2 then
			return value .. " V2"
		end
		return value .. " V1"
	end

	tbl18.GetPlayerBoat = function()
		for _, child in pairs(tbl5.Workspace.Boats:GetChildren()) do
			if child:IsA("Model") then
				local owner = child:FindFirstChild("Owner")
				local humanoid = child:FindFirstChild("Humanoid")
				local v19 = owner and humanoid
				local flag

				if v19 then
					local name = localPlayer.Name
					flag = tostring(owner.Value) == name
				else
					flag = v19
				end

				flag = flag and humanoid.Value > 0
				if flag then
					return child
				end
			end
		end

		return nil
	end

	tbl18.FindTree = function()
		for _, child in pairs(tbl5.Workspace.Map["Boat Castle"].IslandModel:GetChildren()) do
			if child and child:FindFirstChild("Tree") then
				local v19 = nil

				for _, child2 in pairs(child:GetChildren()) do
					if child2 and child2.PrimaryPart then
						if not v19 or tbl18:GetDistance(child2.PrimaryPart.Position) < tbl18:GetDistance(v19.PrimaryPart.Position) then
							v19 = child2
						end
					end
				end

				return v19
			end
		end
	end

	tbl18.GetIslandList = function()
		local tbl27 = {}
		local tbl28 = {}
		local tbl29 = { "Sky 2", "Sky 3" }
		local v19 = next
		local children, v20 = tbl6.WorldOrigin.Locations:GetChildren()

		for _, v21 in v19, children, v20 do
			if v21 and not tbl28[v21.name] then
				table.insert(tbl27, v21.name)
				tbl28[v21.name] = true
			end
		end

		if tbl8[1] then
			for _, v21 in next, tbl29, nil do
				table.insert(tbl27, v21)
			end
		end

		return tbl27
	end

	tbl18.TeleportToTemple = function()
		local humanoidRootPart = localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart")

		if localPlayer.Character then
			humanoidRootPart.CFrame = CFrame.new(28286.35546875, 14895.301757812, 102.62469482422)
		end

		local mapStash = tbl5.ReplicatedStorage:FindFirstChild("MapStash")
		local templeOfTime = mapStash and mapStash:FindFirstChild("Temple of Time")

		if templeOfTime then
			templeOfTime.Parent = tbl5.Workspace.Map
		end
	end

	tbl18.NavigateToIsland = function(arg, arg2)
		if tbl9.Islands[arg2] then
			tbl18:FireRemote("requestEntrance", tbl9.Islands[arg2])
		else
			for _, child in pairs(tbl6.WorldOrigin.Locations:GetChildren()) do
				if child.Name == arg2 then
					tbl18:ExecuteTween(child.CFrame * CFrame.new(0, 180, 0))
				end
			end
		end
	end

	local tbl27 = {}

	tbl18.ProcessHumanV3 = function()
		local v19 = tbl18:FindEnemy({ "Jeremy", "Fajita", "Diamond" })
		if not v19 then
			return
		end

		while true do
			task.wait()
			tbl18:EngageEnemy({ v19.Name })
			if not (not v19 or not v19.Parent or v19.Humanoid.Health <= 0 or not tbl14["Auto V3"]) then
				continue
			end
			break
		end

		if v19 and not table.find(tbl27, v19.Name) then
			v9:SetNotification({ "Facility", "Auto V3", "Killed: " .. v19.Name, 5, 0.5 })
			table.insert(tbl27, v19.Name)
		end
	end

	tbl18.HandleFishmanV2 = function()
		local seaBeast1 = tbl5.Workspace.SeaBeasts:FindFirstChild("SeaBeast1")
		local character = localPlayer.Character
		local humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart")

		if not seaBeast1 then
			local playerBoat = tbl18:GetPlayerBoat()

			if not playerBoat then
				local cframe = CFrame.new(-13.5, 10, 2928)

				if localPlayer:DistanceFromCharacter(cframe.Position) > 8 then
					tbl18:ExecuteTween(cframe)
				else
					tbl5.ReplicatedStorage.Remotes.CommF_:InvokeServer("BuyBoat", "PirateBasic")
				end

				return
			end

			local vehicleSeat = playerBoat:FindFirstChild("VehicleSeat")
			local cframe = CFrame.new(48.41, 11.23, 3690)
			if vehicleSeat and (vehicleSeat.Position - cframe.Position).Magnitude > 50 then
				vehicleSeat.CFrame = cframe
				return
			end

			if not character or not character:FindFirstChildOfClass("Humanoid") then
				return
			end
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Sit then
				return
			end

			if vehicleSeat and humanoidRootPart then
				if (vehicleSeat.Position - humanoidRootPart.Position).Magnitude > 50 then
					tbl18:ExecuteTween(vehicleSeat.CFrame)
				else
					humanoidRootPart.CFrame = vehicleSeat.CFrame
				end
			end

			return
		end

		local humanoidRootPart2 = seaBeast1:FindFirstChild("HumanoidRootPart")
		if not humanoidRootPart2 then
			return
		end
		local distance = tbl18:GetDistance(humanoidRootPart2.Position)

		if distance <= 5000 then
			TeleportToSeaBeast(seaBeast1)

			if distance <= 800 then
				SetAim(humanoidRootPart2.CFrame)
				tbl18:EquipToolByTip(tbl14["Choose Equip "] == "Random" and ({ "Melee", "Blox Fruit", "Sword", "Gun" })[math.random(1, 4)] or tbl14["Choose Equip "])
				local v19 = next
				local skill = tbl14["Skill  "] or {}

				for _, v20 in v19, skill, nil do
					if tbl18:IsSkillAvailable(v20) then
						tbl18:SendKeyPress(v20)
					end
				end
			end
		end
	end

	tbl18.IsInSafeZone = function(arg, arg2)
		if not arg2 then
			return false
		end
		local humanoidRootPart = arg2:FindFirstChild("HumanoidRootPart")
		local humanoid = arg2:FindFirstChildOfClass("Humanoid")
		if not humanoidRootPart or not humanoid then
			return false
		end

		for _, child in pairs(tbl6.WorldOrigin.SafeZones:GetChildren()) do
			if child:IsA("BasePart") then
				if (child.Position - humanoidRootPart.Position).Magnitude <= 400 and humanoid.Health / humanoid.MaxHealth >= 0.9 then
					return true
				end
			end
		end

		return false
	end

	tbl18.CheckRecentDeath = function()
		for _, child in pairs(playerGui.Notifications:GetChildren()) do
			if child:IsA("TextLabel") and (string.find(string.lower(child.Text), "player") or string.find(string.lower(child.Text), "người chơi")) then
				return true
			end
		end

		return false
	end

	tbl18.CountSkypieaPlayers = function()
		local n4 = 0

		for _, player in pairs(tbl5.Players:GetPlayers()) do
			if player ~= localPlayer then
				local data = player:FindFirstChild("Data")
				data = data and data:FindFirstChild("Race")

				if data and data.Value == "Skypiea" then
					n4 += 1
				end
			end
		end

		return n4
	end

	local tbl28 = {}
	local tbl29 = {}

	tbl18.HandleSkypieaV3 = function()
		local players = tbl5.Players:GetPlayers()

		for _, player in pairs(players) do
			if player.Name ~= localPlayer.Name then
				local data = player:FindFirstChild("Data")
				data = data and data:FindFirstChild("Race")

				if tostring(data and data.Value) ~= "Skypiea" then
					if not table.find(tbl29, player.Name) then
						table.insert(tbl29, player.Name)
						v9:SetNotification({ "Facility", "Auto V3", "Blacklisted: " .. player.Name, 5, 0.5 })
					end

					if #players - 2 <= #tbl29 then
						v9:SetNotification({ "Facility", "Auto V3", "No Skypiea Players Found | Server Hopping", 5, 0.5 })
						tbl18:ServerHop("Singapore", 10)
					end
				elseif not table.find(tbl28, player.Name) then
					v9:SetNotification({ "Facility", "Auto V3", "Target: " .. player.Name, 5, 0.5 })
					local character = player.Character
					character = character and character:FindFirstChild("HumanoidRootPart")
					local humanoid = player:FindFirstChildOfClass("Humanoid")

					if character and humanoid then
						while true do
							task.wait()

							if tbl18:CheckRecentDeath() then
								table.insert(tbl28, player.Name)
							end

							tbl18:ExecuteTween(character.CFrame * CFrame.new(0, 8, 0) * CFrame.Angles(-0.78539816339744828, 0, 0))
							if not (not humanoid or humanoid.Health <= 0 or not tbl14["Auto V3"] or table.find(tbl28, player.Name)) then
								continue
							end
							break
						end
					end
				else
					v9:SetNotification({
						"Facility",
						"Auto V3",
						"Skipped: " .. player.Name .. " | Reason: " .. (tbl18:CheckRecentDeath() and "Dead Recent" or "Unknown"),
						5,
						0.5,
					})

					if not table.find(tbl28, player.Name) then
						table.insert(tbl28, player.Name)
					end

					local n4 = #tbl28

					if tbl18:CountSkypieaPlayers() <= n4 then
						tbl18:ServerHop("Singapore", 10)
					end
				end
			end
		end
	end

	tbl18.FindNearestChest = function()
		local character = localPlayer.Character
		local humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart")
		if not humanoidRootPart then
			return nil
		end
		local huge = math.huge
		local v19 = nil

		for _, child in pairs(tbl5.Workspace.ChestModels:GetChildren()) do
			if string.match(child.Name, "Chest") then
				local magnitude = (child.Position - humanoidRootPart.Position).Magnitude

				if magnitude < huge then
					huge = magnitude
					v19 = child
				end
			end
		end

		if not v19 then
			for _, descendant in pairs(tbl5.Workspace.Map:GetDescendants()) do
				if descendant:IsA("Part") and string.match(descendant.Name, "Chest") then
					local magnitude = (descendant.Position - humanoidRootPart.Position).Magnitude

					if magnitude < huge then
						huge = magnitude
						v19 = descendant
					end
				end
			end
		end

		return v19
	end

	tbl18.HandleMinkV2 = function()
		local v19 = tbl18:FindNearestChest()
		if not v19 then
			return
		end
		local character = localPlayer.Character
		character = character and character:FindFirstChild("HumanoidRootPart")
		if not character then
			return
		end

		while true do
			task.wait()
			local magnitude = (character.Position - v19.Position).Magnitude

			if magnitude <= 2 then
				firetouchinterest(v19, character, 0)
				firetouchinterest(v19, character, 1)
			elseif magnitude <= 5 then
				tbl5.VirtualInputManager:SendKeyEvent(true, "W", false, game)
				task.wait()
				tbl5.VirtualInputManager:SendKeyEvent(false, "W", false, game)
			end

			tbl18:ExecuteTween(v19.CFrame * CFrame.new(0, 1, 0))
			if not (not v19 or not v19.Parent or not tbl14["Auto V3"]) then
				continue
			end
			break
		end
	end

	tbl18.GetEquippedFruit = function()
		local character = localPlayer.Character
		local name = nil

		for _, child in pairs(localPlayer.Backpack:GetChildren()) do
			if string.find(child.Name, "Fruit") then
				name = child.Name
				break
			else
				name = nil
			end
		end

		if not name and character then
			for _, child in pairs(character:GetChildren()) do
				if string.find(child.Name, "Fruit") then
					name = child.Name
					break
				end
			end
		end

		return name
	end

	local tbl30 = {}
	local v19 = next
	local response, v20 = tbl5.ReplicatedStorage:WaitForChild("Remotes").CommF_:InvokeServer("GetFruits")

	for _, v21 in v19, response, v20 do
		if v21.Price >= 1000000 then
			tbl30[v21.Name] = v21.Price
		end
	end

	tbl18.GetFruitInventory = function(arg, arg2)
		local flag = arg2 or true
		local huge = math.huge
		local name = nil

		for _, v21 in next, fn8(), nil do
			if v21.Type ~= "Blox Fruit" then
				continue
			end

			if not flag then
				local v22 = tbl30[v21.Name]

				if v22 and v22 < huge then
					name = v21.Name
					huge = v22
				end

				continue
			end

			if not tbl30[v21.Name] then
				return v21.Name
			end
		end

		return name
	end

	tbl18.GetCurrentFruit = function()
		local tbl31 = {}

		local function fn14(arg)
			local parts = arg:split(":")
			return (parts[1] .. "-" .. parts[1] .. (parts[2] and ":" .. parts[2] or "")):gsub(" Fruit", "")
		end

		local v21 = next
		local children, v22 = localPlayer.Character:GetChildren()

		for _, v23 in v21, children, v22 do
			if string.find(v23.Name, "Fruit") and not tbl31[v23.Name] then
				tbl31[v23.Name] = true
				return v23.Name, fn14(v23.Name), v23
			end
		end

		local v23 = next
		local children2, v24 = localPlayer.Backpack:GetChildren()

		for _, v25 in v23, children2, v24 do
			if string.find(v25.Name, "Fruit") and not tbl31[v25.Name] then
				tbl31[v25.Name] = true
				return v25.Name, fn14(v25.Name), v25
			end
		end

		return nil, nil, nil
	end

	tbl18.FindGroundFruit = function()
		local character = localPlayer.Character
		character = character and character.PrimaryPart
		if not character then
			return nil
		end
		local huge = math.huge
		local v21 = nil

		for _, child in pairs(tbl5.Workspace:GetChildren()) do
			if child then
				local handle = child:FindFirstChild("Handle")

				if handle and child:IsA("Tool") then
					local magnitude = (character.Position - handle.Position).Magnitude

					if magnitude <= huge then
						huge = magnitude
						v21 = child
					end
				elseif handle and string.find(child.Name, "Fruit") then
					local magnitude = (character.Position - handle.Position).Magnitude

					if magnitude <= huge then
						huge = magnitude
						v21 = child
					end
				end
			end
		end

		return v21 and v21:FindFirstChild("Handle")
	end

	tbl18.AttackMob = function(arg, arg2)
		for _, child in pairs(tbl6.Enemies:GetChildren()) do
			if child:FindFirstChild("Humanoid") and child:FindFirstChild("HumanoidRootPart") and child.Humanoid.Health > 0 then
				tbl4.__spawn(function()
					while tbl14[arg2] and child.Parent and child.Humanoid.Health > 0 and not v9.Unloaded do
						tbl18:EquipSelectedTool()
						tbl18:ActivateHaki()
						child.HumanoidRootPart.CFrame = localPlayer.Character.CFrame * CFrame.new(0, -30, 0)
						tbl5.RunService.Heartbeat:Wait()
					end
				end)
			end
		end
	end

	tbl18.CreateESP = function(arg, arg2, textColor3)
		if not arg2 or arg2:FindFirstChild("SpeedHubX_ESP") then
			return
		end
		local primaryPart = arg2
		local str3 = nil

		if arg2:IsA("Model") then
			primaryPart = arg2:FindFirstChild("PrimaryPart") or arg2:FindFirstChildWhichIsA("BasePart")
			str3 = "Model"
			if not primaryPart then
				return
			end
		end

		local folder = Instance.new("Folder")
		folder.Name = "SpeedHubX_ESP"
		folder.Parent = primaryPart
		local boxHandleAdornment = Instance.new("BoxHandleAdornment")
		boxHandleAdornment.Size = Vector3.new(1, 0, 1)
		boxHandleAdornment.Name = "SpeedHubX_ESP"
		boxHandleAdornment.AlwaysOnTop = true
		boxHandleAdornment.ZIndex = 10
		boxHandleAdornment.Transparency = 0
		boxHandleAdornment.Adornee = primaryPart
		boxHandleAdornment.Parent = folder
		local billboardGui = Instance.new("BillboardGui")
		billboardGui.Adornee = primaryPart
		billboardGui.Size = UDim2.new(0, 100, 0, 150)
		billboardGui.StudsOffset = Vector3.new(0, 1, 0)
		billboardGui.AlwaysOnTop = true
		billboardGui.Parent = boxHandleAdornment
		local textLabel = Instance.new("TextLabel")
		textLabel.BackgroundTransparency = 1
		textLabel.Position = UDim2.new(0, 0, 0, -50)
		textLabel.Size = UDim2.new(0, 100, 0, 100)
		textLabel.TextSize = 10
		textLabel.TextColor3 = textColor3 or Color3.fromRGB(255, 255, 255)
		textLabel.TextStrokeTransparency = 0
		textLabel.Font = Enum.Font.GothamBold
		textLabel.TextYAlignment = Enum.TextYAlignment.Bottom
		textLabel.Text = ""
		textLabel.ZIndex = 15
		textLabel.Parent = billboardGui
		local humanoidRootPart = localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart")

		tbl5.RunService.Heartbeat:Connect(function()
			if not humanoidRootPart then
				return
			end

			pcall(function()
				local n4 = math.floor((humanoidRootPart.Position - primaryPart.Position).Magnitude / 3)

				if primaryPart.Name == "HumanoidRootPart" and primaryPart.Parent:FindFirstChild("Humanoid") then
					textLabel.Text = string.format(" [ Name : %s ] \n [ HP : %d ] \n [ Location : %d ] ", primaryPart.Parent.Name, math.floor(primaryPart.Parent.Humanoid.Health), n4)
				elseif primaryPart.Name == "HumanoidRootPart" then
					textLabel.Text = string.format(" [ Name : %s ] \n [ Location : %d ] ", primaryPart.Parent.Name, n4)
				elseif primaryPart.Name == "Handle" then
					textLabel.Text = string.format(" [ Name : %s ] \n [ Location : %d ] ", primaryPart.Parent.Name, n4)
				elseif str3 == "Model" then
					textLabel.Text = string.format(" [ Name : %s ] \n [ Location : %d ] ", primaryPart.Parent.Name, n4)
				else
					textLabel.Text = string.format(" [ Name : %s ] \n [ Location : %d ] ", primaryPart.Name, n4)
				end
			end)
		end)
	end

	tbl18.RemoveESP = function(arg, arg2)
		if arg2 and arg2:FindFirstChild("SpeedHubX_ESP") then
			arg2.SpeedHubX_ESP:Destroy()
		end
	end

	local tbl31 = nil
	local vector = Vector3.zero
	local n4 = 0
	local n5 = 0.1

	local function fn14()
		local tbl32 = {
			"Auto Farm Mastery",
			"Auto Farm Sea",
			"Auto Attack Leviathan",
			"Auto Attack Leviathan Segment",
			"Auto Attack Leviathan Tail",
		}

		for i = 1, #tbl32 do
			if tbl14[tbl32[i]] then
				return true
			end
		end

		return false
	end

	local function fn15()
		if not tbl31 then
			return Vector3.zero
		end
		local now2 = tick()

		if n5 < now2 - n4 then
			vector = tbl31[1] and tbl31[1].Position or tbl31[2] or Vector3.zero
			n4 = now2
		end

		return vector
	end

	tbl18.isQuestOn = function()
		return game.Players.LocalPlayer.PlayerGui:FindFirstChild("TrackedQuestFrame") and game.Players.LocalPlayer.PlayerGui:WaitForChild("TrackedQuestFrame").Frame.Visible or false
	end

	SetAim = function(target)
		if not target then
			tbl31 = nil
			vector = Vector3.zero
			return
		end

		local Mouse = require(tbl5.ReplicatedStorage:WaitForChild("Mouse"))

		if Mouse then
			Mouse.Hit = CFrame.new(target.Position)
			Mouse.Target = target
		end

		tbl31 = { target, target.Position }
		vector = target.Position
		n4 = tick()
	end

	TeleportToSeaBeast = function(arg)
		local humanoidRootPart = arg:FindFirstChild("HumanoidRootPart")
		if not humanoidRootPart then
			return
		end
		local waterBasePlane = tbl5.Workspace.Map:FindFirstChild("WaterBase-Plane")
		if not waterBasePlane then
			return
		end

		if (Vector3.new(0, humanoidRootPart.Position.Y, 0) - Vector3.new(0, waterBasePlane.Position.Y, 0)).Magnitude <= 175 then
			if tbl14["Auto Dodge Sea Beasts Skill"] and IsPlayingSeaBeast() then
				tbl18:ExecuteTween(humanoidRootPart.CFrame * _G.DodgeSeaPos, 500)
			else
				tbl18:ExecuteTween(humanoidRootPart.CFrame * CFrame.new(0, 300, 50))
			end
		else
			tbl18:ExecuteTween(CFrame.new(humanoidRootPart.Position.X, waterBasePlane.Position.Y + 200, humanoidRootPart.Position.Z))
		end
	end

	IsPlayingSeaBeast = function()
		for _, descendant in pairs(tbl5.Workspace.SeaBeasts:GetDescendants()) do
			if descendant:IsA("Animator") then
				for _, v21 in pairs(descendant:GetPlayingAnimationTracks()) do
					local animationId = v21.Animation.AnimationId

					if animationId == "rbxassetid://8708221792" or animationId == "rbxassetid://8708222556" then
						local random = math.random
						_G.DodgeSeaPos = CFrame.new(math.random(0, 700), 300, random(0, 700))
						return true
					end
				end
			end
		end

		return false
	end

	tbl4.__spawn(function()
		if _G.EnabledAimBot then
			return
		end
		_G.EnabledAimBot = true
		local main = playerGui:FindFirstChild("Main")

		if main then
			local whatsNew = main:FindFirstChild("WhatsNew")

			if whatsNew then
				whatsNew:Destroy()
			end
		end

		local v21 = getrawmetatable(game)
		local namecall = v21.__namecall
		local index = v21.__index
		local newindex = v21.__newindex
		setreadonly(v21, false)

		local function fn16()
			return tbl31 ~= nil and fn14()
		end

		v21.__namecall = function(arg, arg2, arg3, ...)
			local v22 = table.pack(...)
			local str3 = getnamecallmethod():lower()

			if tostring(arg) == "RemoteEvent" then
				if str3 == "fireserver" and typeof(arg2) == "Vector3" then
					if fn16() then
						local v23 = fn15()
						if v23 ~= Vector3.zero then
							return namecall(arg, v23, arg3, ...)
						end
					end
				end

				if str3 == "invokeserver" then
					local tbl32 = { "Z", "X", "C", "V", "F" }
					local flag = false

					for i = 1, #tbl32 do
						if tbl32[i] == arg2 then
							flag = true
							break
						end
					end

					if flag and typeof(arg3) == "Vector3" then
						if not select(1, ...) then
							if fn16() then
								local v23 = fn15()
								if v23 ~= Vector3.zero then
									return namecall(arg, v23, arg3, table.unpack(v22, 1, v22.n))
								end
							end
						end

						return namecall(arg, arg2, arg3, table.unpack(v22, 1, v22.n))
					end
				end
			end

			return namecall(arg, arg2, arg3, ...)
		end

		v21.__index = function(arg, arg2)
			if arg2 == "Part_Aim" and fn16() then
				return tbl31 and tbl31[1]
			end
			return index(arg, arg2)
		end

		v21.__newindex = function(arg, arg2, arg3)
			if arg2 == "Part_Aim" and arg3 == nil then
				tbl31 = nil
				vector = Vector3.zero
				return
			end

			return newindex(arg, arg2, arg3)
		end

		setreadonly(v21, true)
	end)


	local Configuration = v11:AddSection("Configuration")

	result2:Dropdown(Configuration, "Weapon Tool", "Select weapon type", false, { "Melee", "Sword", "Blox Fruit", "Gun" }, { "Melee" }, function(arg)
		tbl16:SetSave("Weapon Tool", arg)
	end)

	Configuration:AddSeperator({ "Tween & Movement" })

	result2:Dropdown(Configuration, "Farm Distance", "Distance from enemies", false, { "10", "20", "30", "40", "50", "60" }, { "20" }, function(arg)
		tbl16:SetSave("Farm Distance", arg)
	end)

	result2:Dropdown(Configuration, "Tween Speed", "Movement speed", false, { "100", "200", "300", "400", "500" }, { "300" }, function(arg)
		tbl16:SetSave("Tween Speed", arg)
	end)

	Configuration:AddSeperator({ "Mob Control" })

	result2:Toggle(Configuration, "Bring Mob", "Pull enemies closer", true, function(arg)
		tbl16:SetSave("Bring Mob", arg)
	end)

	result2:Dropdown(Configuration, "Bring Mob Radius", "Pull radius", false, { "100", "200", "300", "400", "500" }, { "300" }, function(arg)
		tbl16:SetSave("Bring Mob Radius", arg)
	end)

	Configuration:AddSeperator({ "Combat Settings" })

	result2:Toggle(Configuration, "Fast Attack", "Faster attack speed", true, function(arg)
		tbl16:SetSave("Fast Attack", arg)
	end)

	tbl4.__spawn(function()
		local v21 = nil
		local n6 = 0

		while task.wait() do
			if tbl14["Fast Attack"] and not v9.Unloaded then
				local n7 = (tbl14["Fast Attack Delay"] or 1) / 100

				if n7 ~= v21 then
					n6 = 0
					v21 = n7
				end

				if tick() - n6 >= n7 then
					n6 = tick()
					tbl18:ExecuteBladeHits()
				end
			end
		end
	end)

	Configuration:AddSeperator({ "Auto Abilities" })

	result2:Toggle(Configuration, "Auto Dodge Skill", "Dodge enemy skills", false, function(arg)
		tbl16:SetSave("Auto Dodge Skill", arg)
	end)

	result2:Toggle(Configuration, "Auto Use Race V3", "Auto activate V3", false, function(arg)
		tbl16:SetSave("Auto Use Race V3", arg)
	end)

	result2:Toggle(Configuration, "Auto Use Race V4", "Auto activate V4", false, function(arg)
		tbl16:SetSave("Auto Use Race V4", arg)
	end)

	tbl4.__spawn(function()
		tbl18:CreateLoop("Auto Use Race V3", function()
			tbl5.ReplicatedStorage.Remotes.CommE:FireServer("ActivateAbility")
		end)

		tbl18:CreateLoop("Auto Use Race V4", function()
			if not localPlayer.Character.RaceTransformed.Value then
				tbl18:SendKeyPress("Y", 0.1)
			end
		end)
	end)

	local v21 = v11:AddSection("Local Player")

	result2:Textbox(v21, "Dash Length", "Custom dash distance", "Save", function(arg)
		tbl16:SetSave("Set Length", arg)
	end)

	result2:Button(v21, "Apply Dash Length", "Apply dash length", function()
		localPlayer.Character:SetAttribute("DashLength", tbl14["Set Length"] and tonumber(tbl14["Set Length"]) or 70)
	end)

	result2:Textbox(v21, "Speed Multiplier", "Movement speed (1-10)", "Save", function(arg)
		tbl16:SetSave("Set Speed", arg)
	end)

	result2:Button(v21, "Apply Speed", "Apply speed multiplier", function()
		localPlayer.Character:SetAttribute("SpeedMultiplier", tbl14["Set Speed"] and tonumber(tbl14["Set Speed"]) or 3)
	end)

	local v22 = v11:AddSection("Server Manager")

	result2:Dropdown(v22, "Max Player Count", "Max players before hop", false, { "1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "12" }, { "5" }, function(arg)
		tbl16:SetSave("Count Player", arg)
	end)

	result2:Button(v22, "Hop Server", "Teleport to another server", function()
		tbl18:ServerHop("Singapore", tonumber(tbl14["Count Player"]))
	end)

	result2:Button(v22, "Rejoin Server", "Reconnect to current server", function()
		tbl5.TeleportService:Teleport(game.PlaceId, localPlayer)
	end)

	local v23 = v11:AddSection("Stat Manager")

	result2:Dropdown(v23, "Points Per Stat", "Points per click", false, { "1", "5", "10", "15", "20", "25", "30", "35", "40", "50" }, { "1" }, function(arg)
		tbl16:SetSave("Point Stats", arg)
	end)

	for _, v24 in next, { "Melee", "Defense", "Sword", "Gun", "Demon Fruit" }, nil do
		result2:Toggle(v23, "Auto " .. v24, "Auto allocate points", "Save", function(arg)
			tbl16:SetSave("Auto " .. v24, arg)
		end)
	end

	tbl4.__spawn(function()
		for _, v24 in pairs({ "Melee", "Defense", "Sword", "Gun", "Demon Fruit" }) do
			tbl18:CreateLoop("Auto " .. v24, function()
				tbl18:FireRemote("AddPoint", v24, tonumber(tbl14["Point Stats"]))
			end)
		end
	end)

	local lighting = tbl5.Lighting
	local sky = lighting:FindFirstChildOfClass("Sky") or lighting:WaitForChild("Sky")
	local data = localPlayer:WaitForChild("Data")
	local leaderstats = localPlayer:WaitForChild("leaderstats")
	local c = data:WaitForChild("Race"):WaitForChild("C")
	local visionRadius = localPlayer:WaitForChild("VisionRadius")
	local level = data:WaitForChild("Level")
	local exp = data:WaitForChild("Exp")
	local bountyHonor = leaderstats:WaitForChild("Bounty/Honor")
	local beli = data:WaitForChild("Beli")
	local fragments = data:WaitForChild("Fragments")

	local tbl32 = {
		["http://www.roblox.com/asset/?id=9709149431"] = "Full Moon (5/5)",
		["http://www.roblox.com/asset/?id=9709149052"] = "Gibbous (4/5)",
		["http://www.roblox.com/asset/?id=9709143733"] = "Quarter (3/5)",
		["http://www.roblox.com/asset/?id=9709150401"] = "Crescent (2/5)",
		["http://www.roblox.com/asset/?id=9709149680"] = "New Moon (1/5)",
	}

	local v24 = v12:AddSection("Server & Player Status", true):AddParagraph({ Title = "Status", Content = "" })

	local function fn16()
		local str3 = sky and tbl32[sky.MoonTextureId] or "Unknown"
		local str4 = tostring(c.Value)
		local str5 = (({ ["1"] = "", ["2"] = "", ["3"] = "", ["4"] = "" })[str4] or "") .. " Tier " .. str4 .. "/4"
		local str6 = visionRadius.Value .. " / 5000 XP"
		local str7 = "Lv. " .. level.Value .. " | XP: " .. exp.Value .. " (" .. math.floor(exp.Value / (level.Value * 100 + 50) * 100) .. "%)"
		local value = bountyHonor.Value

		v24:Set({
			Title = "Status",
			Content = string.format("🌙 %s\n👤 %s\n👁️ %s\n📊 %s\n💰 %s\n💎 %s", str3, str5, str6, str7, (value >= 1000000 and string.format("%.1fM", value / 1000000) or tostring(value)) .. " (" .. value .. ")", (beli.Value >= 1000000 and string.format("%.1fM", beli.Value / 1000000) or tostring(beli.Value)) .. " Beli | " .. fragments.Value .. " Frags"),
		})
	end

	fn16()

	local function fn17()
		if sky then
			sky:GetPropertyChangedSignal("MoonTextureId"):Connect(fn16)
		end

		c.Changed:Connect(fn16)
		visionRadius.Changed:Connect(fn16)
		level.Changed:Connect(fn16)
		exp.Changed:Connect(fn16)
		bountyHonor.Changed:Connect(fn16)
		beli.Changed:Connect(fn16)
		fragments.Changed:Connect(fn16)
	end

	fn17()
	local v25 = v12:AddSection("Stack Farming System")

	v25:AddParagraph({
		"Priority-Based Farming",
		"Only the highest priority enabled feature with available targets will run.",
	})

	result2:Toggle(v25, "Enable Stack Farming", "Activate priority system", "Save", function(arg)
		tbl16:SetSave("Stack Farming Enabled", arg)
	end)

	v25:AddLine()

	for _, v26 in ipairs({
		{ "Auto Farm Level", "1", "Farm quest enemies" },
		{ "Auto Farm Nearest", "2", "Farm nearest enemies" },
		{ "Auto Farm Mastery", "3", "Farm for mastery" },
		{ "Auto Collect Chest", "4", "Collect chests" },
		{ "Auto Collect Berry", "5", "Collect berries" },
		{ "Auto Farm Material", "6", "Farm materials" },
		{ "Auto Farm Bones", "7", "Farm bones" },
		{ "Auto Attack Boss", "8", "Attack selected boss" },
		{ "Auto Attack All Boss", "9", "Attack all bosses" },
		{ "Auto Soul Reaper", "10", "Farm Soul Reaper" },
		{ "Auto Elite Hunter", "11", "Hunt elites" },
		{ "Auto Kill Tyrant of the Skies", "12", "Kill Tyrant" },
		{ "Auto Citizen Quest", "13", "Complete citizen quests" },
		{ "Auto Dough King", "14", "Fight Dough King" },
		{ "Auto Cake Prince", "15", "Fight Cake Prince" },
	}) do
		local priority, v27, v28 = unpack(v26)

		result2:Dropdown(v25, "Priority: " .. priority, v28, false, { "1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "12", "13", "14", "15" }, { v27 }, function(arg)
			tbl16:SetSave("Priority: " .. priority, arg)
		end)
	end

	local v26 = v12:AddSection("Hop Boss")

	local tbl33 = {
		"Greybeard",
		"The Saw",
		"Saber Expert",
		"The Gorilla King",
		"Bobby",
		"Yeti",
		"Vice Admiral",
		"Warden",
		"Chief Warden",
		"Swan",
		"Magma Admiral",
		"Fishman Lord",
		"Wysper",
		"Thunder God",
		"Cyborg",
	}

	local tbl34 = {
		"Darkbeard",
		"Cursed Captain",
		"Order",
		"Don Swan",
		"Diamond",
		"Jeremy",
		"Fajita",
		"Smoke Admiral",
		"Awakened Ice Admiral",
		"Tide Keeper",
	}

	local tbl35 = {
		"Dough King",
		"Cake Prince",
		"rip_indra True Form",
		"Soul Reaper",
		"Stone",
		"Island Empress",
		"Kilo Admiral",
		"Captain Elephant",
		"Beautiful Pirate",
		"Cake Queen",
		"Longma",
	}

	result2:Dropdown(v26, "Select World", "Choose world to hop", false, { "First", "Second", "Third" }, { "Third" }, function(arg)
		tbl16:SetSave("Choose World", arg)
	end)

	result2:Dropdown(v26, "Select Boss [1st World]", "Choose boss in first world", false, tbl33, { "Greybeard" }, function(arg)
		tbl16:SetSave("Choose Boss 1", arg)
	end)

	result2:Dropdown(v26, "Select Boss [2nd World]", "Choose boss in second world", false, tbl34, { "Darkbread" }, function(arg)
		tbl16:SetSave("Choose Boss 2", arg)
	end)

	result2:Dropdown(v26, "Select Boss [3rd World]", "Choose boss in third world", false, tbl35, { "rip_indra True Form" }, function(arg)
		tbl16:SetSave("Choose Boss 3", arg)
	end)

	result2:Button(v26, "Hop", "Find server with boss", function()
		local chooseBoss1 = tbl14["Choose World"] == "First" and tbl14["Choose Boss 1"]
		local chooseBoss2

		if chooseBoss1 then
			chooseBoss2 = chooseBoss1
		else
			chooseBoss2 = tbl14["Choose World"] == "Second" and tbl14["Choose Boss 2"]
		end

		chooseBoss2 = chooseBoss2 or tbl14["Choose World"] == "Third" and tbl14["Choose Boss 3"]
		local v27 = tbl18:bossData(chooseBoss2)

		if v27 and v27.id then
			local v28 = tbl18:converttoTable(v27.id)
			tbl18:smartBossTeleport({ tbl33, tbl34, tbl35 }, chooseBoss2, v28[2], v28[1])
		else
			v9:SetNotification({ "Facility", "Hop Boss", "No server with boss found", 5, 0.5 })
		end
	end)

	local v27 = v12:AddSection("Level Farming")

	if identifyexecutor():find("Solara") or identifyexecutor():find("Xeno") then
		v27:AddParagraph({
			"Incompatible Executor",
			"Solara and Xeno are not supported.\nUse 'Auto Farm Nearest' instead.",
		})
	else
		result2:Toggle(v27, "No Quest Mode", "Skip quests and farm directly", "Save", function(arg)
			tbl16:SetSave("No Quest", arg)
		end)

		result2:Toggle(v27, "Auto Take Quest", "Auto-accept quests", "Save", function(arg)
			tbl16:SetSave("Take Quest", arg)
		end)

		v27:AddLine()

		result2:Toggle(v27, "Auto Farm Level", "Farm based on level", "Save", function(arg)
			tbl16:SetSave("Auto Farm Level", arg)
			tbl18:StopTween(arg)
		end)

		tbl4.__spawn(function()
			tbl18:CreateLoop("Auto Farm Level", function()
				if not tbl18:CheckStackPriority("Auto Farm Level") then
					return
				end
				local questInfo = tbl18:GetQuestInfo(tbl14["Auto Farm Level"])

				if tbl14["No Quest"] and not tbl14["Take Quest"] then
					if tbl18:FindEnemy({ questInfo[3] }) then
						tbl18:EngageEnemy({ questInfo[3] })
					else
						tbl18:NavigateToSpawn({ questInfo[3] })
						task.wait(1)
					end
				elseif tbl14["Take Quest"] and not tbl14["No Quest"] then
					if tbl18:isQuestOn() then
						if tbl18:FindEnemy({ questInfo[3] }) then
							tbl18:EngageEnemy({ questInfo[3] })
						else
							tbl18:NavigateToSpawn({ questInfo[3] })
							task.wait(1)
						end
					else
						tbl18:FireRemote("StartQuest", questInfo[4], questInfo[1])
					end
				elseif tbl18:isQuestOn() then
					if tbl18:FindEnemy({ questInfo[3] }) then
						tbl18:EngageEnemy({ questInfo[3] })
					else
						tbl18:NavigateToSpawn({ questInfo[3] })
						task.wait(1)
					end
				else
					local distance = tbl18:GetDistance(questInfo[2])

					if distance and distance <= 5 then
						tbl18:FireRemote("StartQuest", questInfo[4], questInfo[1])
					else
						tbl18:ExecuteTween(questInfo[2])
					end
				end
			end)
		end)
	end

	local v28 = v12:AddSection("Nearest Enemy Farming")

	result2:Dropdown(v28, "Search Range", "Maximum search distance", false, { "1000", "2000", "3000", "Infinite" }, { "Infinite" }, function(arg)
		tbl16:SetSave("Neareast Range", arg)
	end)

	v28:AddLine()

	result2:Toggle(v28, "Auto Farm Nearest", "Farm closest enemy", "Save", function(arg)
		tbl16:SetSave("Auto Farm Nearest", arg)
		tbl18:StopTween(arg)
	end)

	tbl4.__spawn(function()
		tbl18:CreateLoop("Auto Farm Nearest", function()
			if not tbl18:CheckStackPriority("Auto Farm Nearest") then
				return
			end
			local huge = tbl14["Neareast Range"] == "Infinite" and math.huge or tonumber(tbl14["Neareast Range"])
			local huge2 = math.huge
			local v29 = nil

			for _, child in pairs(tbl6.Enemies:GetChildren()) do
				if child and child.PrimaryPart and tbl18:IsEntityAlive(child) then
					local magnitude = (child.PrimaryPart.Position - localPlayer.Character.PrimaryPart.Position).Magnitude

					if magnitude < huge2 and magnitude <= huge then
						huge2 = magnitude
						v29 = child
					end
				end
			end

			if v29 then
				tbl18:EngageEnemy({ v29.Name })
			end
		end)
	end)

	local v29 = v12:AddSection("Mastery Farming")

	result2:Dropdown(v29, "Farm Mode", "Enemy selection mode", false, { "Level", "Bone", "Cake Prince", "Neareast" }, { "Level" }, function(arg)
		tbl16:SetSave("Choose Mastery Mode", arg)
	end)

	result2:Dropdown(v29, "Weapon Type", "Weapon to gain mastery for", false, { "Blox Fruit", "Sword", "Gun", "Melee" }, { "Blox Fruit" }, function(arg)
		tbl16:SetSave("Choose Mastery Tool", arg)
	end)

	result2:Dropdown(v29, "Health Threshold", "HP % to use skills", false, { "10", "20", "25", "30", "45", "50", "60", "70", "75", "85", "95" }, { "45" }, function(arg)
		tbl16:SetSave("Mastery Health", arg)
	end)

	result2:Dropdown(v29, "Combat Skills", "Skills to use", true, { "Z", "X", "C", "V", "F" }, { "Z", "X", "C", "V" }, function(arg)
		tbl16:SetSave("Skill", arg, true)
	end)

	v29:AddLine()

	result2:Toggle(v29, "Auto Farm Mastery", "Farm for mastery", "Save", function(arg)
		tbl16:SetSave("Auto Farm Mastery", arg)
		tbl18:StopTween(arg)
	end)

	tbl4.__spawn(function()
		tbl18:CreateLoop("Auto Farm Mastery", function()
			if not tbl18:CheckStackPriority("Auto Farm Mastery") then
				return
			end

			local function fn18(arg, arg2)
				local v30 = tbl18:FindEnemy(arg)
				if not v30 then
					return
				end
				local primaryPart = v30.PrimaryPart
				local cFrame = primaryPart.CFrame
				local n6 = tonumber(tbl14["Mastery Health"]) or 45

				while true do
					task.wait()

					if not (not v30 or not v30.Parent or not tbl18:IsEntityAlive(v30)) then
						if not (not tbl14["Auto Farm Mastery"] or tbl14["Choose Mastery Mode"] ~= arg2) then
							if v30.Humanoid.Health / v30.Humanoid.MaxHealth * 100 <= n6 then
								tbl18:EquipToolByTip(tbl14["Choose Mastery Tool"])
								tbl18:ExecuteTween(cFrame + Vector3.new(0, tonumber(tbl14["Farm Distance"]) or 20, 1))
								tbl18:ActivateHaki()
								tbl18:BringEnemyToPosition(v30, cFrame)
								SetAim(primaryPart)
								local v31 = next
								local skill = tbl14.Skill or {}

								for _, v32 in v31, skill, nil do
									if tbl18:IsSkillAvailable(v32) then
										tbl18:SendKeyPress(v32)
									end
								end
							else
								tbl18:EquipSelectedTool()
								tbl18:BringEnemyToPosition(v30, cFrame)
								tbl18:ExecuteTween(cFrame + Vector3.new(0, tonumber(tbl14["Farm Distance"]) or 20, 1))
								tbl18:ActivateHaki()
							end

							if not (not v30 or not v30.Parent or not tbl18:IsEntityAlive(v30) or not tbl14["Auto Farm Mastery"]) then
								continue
							end
						end
					end

					break
				end
			end

			local chooseMasteryMode = tbl14["Choose Mastery Mode"]

			if chooseMasteryMode == "Level" then
				local questInfo = tbl18:GetQuestInfo(tbl14["Auto Farm Mastery"])

				if tbl18:isQuestOn() then
					fn18({ questInfo[3] }, "Level")
				else
					local distance = tbl18:GetDistance(questInfo[2])

					if distance and distance <= 5 then
						tbl18:FireRemote("StartQuest", questInfo[4], questInfo[1])
					else
						tbl18:ExecuteTween(questInfo[2])
					end
				end
			elseif chooseMasteryMode == "Bone" then
				fn18({ "Reborn Skeleton", "Demonic Soul", "Living Zombie", "Possessed Mummy" }, "Bone")
			elseif chooseMasteryMode == "Cake Prince" then
				fn18({ "Baking Staff", "Head Baker", "Cake Guard", "Cookie Crafter" }, "Cake Prince")
			elseif chooseMasteryMode == "Neareast" then
				local huge = math.huge
				local v30 = nil

				for _, child in pairs(tbl6.Enemies:GetChildren()) do
					if child and child.PrimaryPart and tbl18:IsEntityAlive(child) then
						local magnitude = (child.PrimaryPart.Position - localPlayer.Character.PrimaryPart.Position).Magnitude

						if magnitude < huge and magnitude <= 3500 then
							huge = magnitude
							v30 = child
						end
					end
				end

				if v30 then
					fn18({ v30.Name }, "Neareast")
				end
			end
		end)
	end)

	local v30 = v12:AddSection("Collection Farming")
	v30:AddSeperator({ "Chest Collection" })

	result2:Toggle(v30, "Auto Hop If No Chest", "Hop if no chests found", "Save", function(arg)
		tbl16:SetSave("Auto Hop If Chest Is Not Found", arg)
	end)

	result2:Toggle(v30, "Stop on Rare Items", "Stop if rare items owned", "Save", function(arg)
		tbl16:SetSave("Disable Auto Collect Chest If Have Item", arg)
	end)

	local v31 = result2:Toggle(v30, "Auto Collect Chest", "Collect chests", "Save", function(arg)
		tbl16:SetSave("Auto Collect Chest", arg)
		tbl18:StopTween(arg)
	end)

	tbl4.__spawn(function()
		tbl18:CreateLoop("Auto Collect Chest", function()
			if not tbl18:CheckStackPriority("Auto Collect Chest") then
				return
			end
			local disableAutoCollectChestIfHaveIte = tbl14["Disable Auto Collect Chest If Have Item"]
			local v32

			if disableAutoCollectChestIfHaveIte then
				v32 = tbl18:HasTool("God's Chalice") or tbl18:HasTool("Fist of Darkness")
			else
				v32 = disableAutoCollectChestIfHaveIte
			end

			if v32 then
				v31:SetValue(false)
				return
			end

			if not tbl18:IsEntityAlive(localPlayer.Character) then
				return
			end
			local position = localPlayer.Character.PrimaryPart.Position
			local huge = math.huge
			local v33 = nil

			for _, v34 in ipairs(tbl5.CollectionService:GetTagged("_ChestTagged")) do
				if not v34:GetAttribute("IsDisabled") then
					local magnitude = (v34:GetPivot().Position - position).Magnitude

					if magnitude < huge then
						huge = magnitude
						v33 = v34
					end
				end
			end

			if v33 then
				tbl18:ExecuteTween(v33.CFrame)
			elseif tbl14["Auto Hop If Chest Is Not Found"] then
				tbl18:ServerHop("Singapore", 8)
			end
		end)
	end)

	v30:AddSeperator({ "Berry Collection" })

	result2:Toggle(v30, "Auto Collect Berry", "Collect berries", "Save", function(arg)
		tbl16:SetSave("Auto Collect Berry", arg)
		tbl18:StopTween(arg)
	end)

	tbl4.__spawn(function()
		tbl18:CreateLoop("Auto Collect Berry", function()
			if not tbl18:CheckStackPriority("Auto Collect Berry") then
				return
			end

			for _, descendant in pairs(tbl5.Workspace.Map:GetDescendants()) do
				if descendant.Name == "Berries" then
					for i = 1, 8 do
						if descendant:GetAttribute("_BerryCFrame" .. i) then
							tbl18:ExecuteTween(descendant.Parent.WorldPivot)

							for _, child in pairs(descendant:GetChildren()) do
								if tbl18:GetDistance(child.WorldPivot) > 5 then
									tbl18:ExecuteTween(child.WorldPivot)
								else
									tbl18:FindNearestPrompt(10)
								end
							end
						end
					end
				end
			end
		end)
	end)

	if not tbl8[1] then
		local v32 = v12:AddSection("Farming " .. (tbl8[2] and "Factory" or tbl8[3] and "Pirates Sea" or "Other"))

		if tbl8[2] then
			result2:Toggle(v32, "Auto Factory", "Destroy factory core", "Save", function(arg)
				tbl16:SetSave("Auto Factory", arg)
				tbl18:StopTween(arg)
			end)

			tbl4.__spawn(function()
				tbl18:CreateLoop("Auto Factory", function()
					if tbl18:FindEnemy({ "Core" }) then
						tbl18:EngageEnemy({ "Core" })
					else
						tbl18:ExecuteTween(CFrame.new(502.7349853515625, 143.07490539550781, -379.078125))
					end
				end)
			end)
		elseif tbl8[3] then
			result2:Toggle(v32, "Auto Pirates Sea", "Farm in Pirates Sea", "Save", function(arg)
				tbl16:SetSave("Auto Pirates Sea", arg)
				tbl18:StopTween(arg)
			end)

			tbl4.__spawn(function()
				tbl18:CreateLoop("Auto Pirates Sea", function()
					local v33 = nil

					for _, child in pairs(tbl6.Enemies:GetChildren()) do
						if child.Name ~= "rip_indra True Form" and child.Name ~= "Blank Buddy" then
							local humanoid = child:FindFirstChild("Humanoid")

							if humanoid and humanoid.Health > 0 and child.PrimaryPart then
								if (child.PrimaryPart.Position - Vector3.new(-5556, 314, -2988)).Magnitude < 700 then
									v33 = child
									break
								else
									v33 = nil
								end
							else
								v33 = nil
							end
						else
							v33 = nil
						end
					end

					if v33 then
						tbl18:EngageEnemy({ v33.Name })
					else
						tbl18:ExecuteTween(CFrame.new(Vector3.new(-5556, 314, -2988)))
					end
				end)
			end)
		end
	end

	local v32 = v12:AddSection("Boss Farming")

	local v33 = result2:Dropdown(v32, "Select Boss", "Choose boss to farm", false, tbl18:GetBossList(), "Save", function(arg)
		tbl16:SetSave("Choose Boss", arg)
	end)

	result2:Button(v32, "Refresh Boss List", "Update boss list", function()
		v33:Clear()
		v33:Refresh(tbl18:GetBossList(), { "" })
	end)

	result2:Toggle(v32, "Auto Attack Boss", "Attack selected boss", "Save", function(arg)
		tbl16:SetSave("Auto Attack Boss", arg)
		tbl18:StopTween(arg)
	end)

	tbl4.__spawn(function()
		tbl18:CreateLoop("Auto Attack Boss", function()
			if not tbl18:CheckStackPriority("Auto Attack Boss") then
				return
			end
			tbl18:EngageEnemy({ tbl14["Choose Boss"] })
		end)
	end)

	result2:Toggle(v32, "Auto Attack All Bosses", "Attack all bosses", "Save", function(arg)
		tbl16:SetSave("Auto Attack All Boss", arg)
		tbl18:StopTween(arg)
	end)

	tbl4.__spawn(function()
		tbl18:CreateLoop("Auto Attack All Boss", function()
			if not tbl18:CheckStackPriority("Auto Attack All Boss") then
				return
			end

			tbl18:EngageEnemy({
				"Greybeard",
				"The Saw",
				"Saber Expert",
				"The Gorilla King",
				"Bobby",
				"Yeti",
				"Vice Admiral",
				"Warden",
				"Chief Warden",
				"Swan",
				"Magma Admiral",
				"Fishman Lord",
				"Wysper",
				"Thunder God",
				"Cyborg",
				"Darkbeard",
				"Cursed Captain",
				"Order",
				"Don Swan",
				"Diamond",
				"Jeremy",
				"Fajita",
				"Smoke Admiral",
				"Awakened Ice Admiral",
				"Tide Keeper",
				"Dough King",
				"Cake Prince",
				"rip_indra True Form",
				"Soul Reaper",
				"Stone",
				"Island Empress",
				"Kilo Admiral",
				"Captain Elephant",
				"Beautiful Pirate",
				"Cake Queen",
				"Longma",
			})
		end)
	end)

	local v34 = v12:AddSection("Material Farming")

	result2:Dropdown(v34, "Select Material", "Choose material to farm", false, tbl18:GetMaterialList(), "Save", function(arg)
		tbl16:SetSave("Choose Material", arg)
	end)

	result2:Toggle(v34, "Auto Farm Material", "Farm selected material", "Save", function(arg)
		tbl16:SetSave("Auto Farm Material", arg)
		tbl18:StopTween(arg)
	end)

	tbl4.__spawn(function()
		tbl18:CreateLoop("Auto Farm Material", function()
			if not tbl18:CheckStackPriority("Auto Farm Material") then
				return
			end
			local materialData = tbl18:GetMaterialData(tbl14["Choose Material"])

			if materialData then
				if tbl18:FindEnemy(materialData.NPCs) then
					tbl18:EngageEnemy(materialData.NPCs)
				else
					tbl18:ExecuteTween(materialData.Position)
				end
			end
		end)
	end)

	local v35 = v13:AddSection("Third World")
	v35:AddSeperator({ "Sword Collection" })

	result2:Dropdown(v35, "Select Sword", "Sword to obtain", false, {
		"Twin Hooks",
		"Buddy Sword",
		"Canvander",
		"Dark Dagger",
		"Fox Lamp",
		"Spikey Trident",
		"Yama",
		"Hallow Scythe",
	}, "Save", function(arg)
		tbl16:SetSave("Choose Sword", arg)
	end)

	result2:Toggle(v35, "Auto Get Sword", "Obtain selected sword", "Save", function(arg)
		tbl16:SetSave("Auto Get Sword", arg)
		tbl18:StopTween(arg)
	end)

	tbl4.__spawn(function()
		tbl18:CreateLoop("Auto Get Sword", function()
			local chooseSword = tbl14["Choose Sword"]

			if chooseSword == "Twin Hooks" then
				tbl18:EngageEnemy({ "Captain Elephant" })
			elseif chooseSword == "Buddy Sword" then
				tbl18:EngageEnemy({ "Cake Queen" })
			elseif chooseSword == "Canvander" then
				tbl18:EngageEnemy({ "Beautiful Pirate" })
			elseif chooseSword == "Dark Dagger" then
				tbl18:EngageEnemy({ "rip_indra True Form" })
			elseif chooseSword == "Fox Lamp" then
				if tbl5.Workspace:FindFirstChild("KitsuneIsland") then
					if tbl18:GetMaterialCount("Azure Ember") >= 20 then
						tbl6.Net:FindFirstChild("RF/KitsuneStatuePray"):InvokeServer()
					elseif tbl5.Workspace:FindFirstChild("AttachedAzureEmber") then
						tbl18:ExecuteTween(tbl5.Workspace:WaitForChild("EmberTemplate"):FindFirstChild("Part").CFrame, 500)
					end
				end
			elseif chooseSword == "Spikey Trident" then
				tbl18:EngageEnemy({ "Dough King" })
			elseif chooseSword == "Yama" then
				if tbl18:FireRemote("EliteHunter", "Progress") >= 30 then
					fireclickdetector(tbl5.Workspace.Map.Waterfall.SealedKatana.Handle.ClickDetecter)
				end
			elseif chooseSword == "Hallow Scythe" then
				if tbl18:FindEnemy({ "Soul Reaper" }) then
					tbl18:EngageEnemy({ "Soul Reaper" })
				elseif tbl18:HasTool("Hallow Essence") then
					tbl18:EquipToolByName("Hallow Essence")

					pcall(function()
						tbl18:ExecuteTween(tbl5.Workspace.Map["Haunted Castle"].Summoner.Detection.CFrame)
					end)
				else
					tbl18:ExecuteTween(CFrame.new(-9529, 316, 6712))
				end
			end
		end)
	end)

	v35:AddSeperator({ "Gun Collection" })

	result2:Toggle(v35, "Auto Get Serpent Bow", "Farm Island Empress for bow", "Save", function(arg)
		tbl16:SetSave("Auto Get Serpent Bow", arg)
		tbl18:StopTween(arg)
	end)

	tbl4.__spawn(function()
		tbl18:CreateLoop("Auto Get Serpent Bow", function()
			if tbl18:FindEnemy({ "Island Empress" }) then
				tbl18:EngageEnemy({ "Island Empress" })
			else
				tbl18:ExecuteTween(CFrame.new(5659, 602, 244))
			end
		end)
	end)

	v35:AddSeperator({ "Bone Farming" })
	local v36 = v35:AddParagraph({ Title = "Bones Collected", Content = "0" })

	tbl4.__spawn(function()
		while task.wait(2) do
			v36:Set({ Title = "Bones Collected", Content = tostring(tbl18:GetMaterialCount("Bones")) })
		end
	end)

	result2:Toggle(v35, "Auto Soul Reaper", "Farm Soul Reaper", "Save", function(arg)
		tbl16:SetSave("Auto Soul Reaper", arg)
		tbl18:StopTween(arg)
	end)

	tbl4.__spawn(function()
		tbl18:CreateLoop("Auto Soul Reaper", function()
			if not tbl18:CheckStackPriority("Auto Soul Reaper") then
				return
			end

			if tbl18:FindEnemy({ "Soul Reaper" }) then
				tbl18:EngageEnemy({ "Soul Reaper" })
			elseif tbl18:HasTool("Hallow Essence") then
				tbl18:EquipToolByName("Hallow Essence")

				pcall(function()
					tbl18:ExecuteTween(tbl5.Workspace.Map["Haunted Castle"].Summoner.Detection.CFrame)
				end)
			else
				tbl18:ExecuteTween(CFrame.new(-9529, 316, 6712))
			end
		end)
	end)

	result2:Toggle(v35, "Auto Farm Bones", "Farm skeletons", "Save", function(arg)
		tbl16:SetSave("Auto Farm Bones", arg)
		tbl18:StopTween(arg)
	end)

	tbl4.__spawn(function()
		tbl18:CreateLoop("Auto Farm Bones", function()
			if not tbl18:CheckStackPriority("Auto Farm Bones") then
				return
			end
			local tbl36 = { "Reborn Skeleton", "Demonic Soul", "Living Zombie", "Possessed Mummy" }

			if tbl18:FindEnemy({ "Soul Reaper" }) then
				tbl18:EngageEnemy({ "Soul Reaper" })
			elseif tbl18:FindEnemy(tbl36) then
				tbl18:EngageEnemy(tbl36)
			else
				tbl18:ExecuteTween(CFrame.new(-9516.9853515625, 142.47166442871094, 5536.74755859375))
			end
		end)
	end)

	result2:Toggle(v35, "Auto Trade Bones", "Trade bones for rewards", "Save", function(arg)
		tbl16:SetSave("Auto Trade Bones", arg)
		tbl18:StopTween(arg)
	end)

	tbl4.__spawn(function()
		tbl18:CreateLoop("Auto Trade Bones", function()
			tbl18:FireRemote("Bones", "Buy", 1, 1)
		end)
	end)

	v35:AddSeperator({ "Cake Prince & Dough King" })
	local v37 = v35:AddParagraph({ Title = "Boss Status", Content = "Checking..." })

	tbl4.__spawn(function()
		while task.wait(2) do
			if tbl18:FindEnemy({ "Dough King" }) then
				v37:Set({ Title = "Boss Status", Content = "Dough King is Spawned!" })
			elseif tbl18:FindEnemy({ "Cake Prince" }) then
				v37:Set({ Title = "Boss Status", Content = "Cake Prince is Spawned!" })
			else
				v37:Set({
					Title = "Boss Status",
					Content = "Progress: " .. (tbl8[3] and string.gsub(tostring(tbl6.CommF_:InvokeServer("CakePrinceSpawner", true)), "%D", "") or "N/A") .. "%",
				})
			end
		end
	end)

	result2:Toggle(v35, "Auto Cake Prince", "Farm Cake Prince", "Save", function(arg)
		tbl16:SetSave("Auto Cake Prince", arg)
		tbl18:StopTween(arg)
	end)

	tbl4.__spawn(function()
		tbl18:CreateLoop("Auto Cake Prince", function()
			if not tbl18:CheckStackPriority("Auto Cake Prince") then
				return
			end
			local cframe = CFrame.new(-2090.6201171875, 70.349876403808594, -12125.5556640625)

			if tbl18:FindEnemy({ "Cake Prince", "Dough King" }) then
				if localPlayer:DistanceFromCharacter(Vector3.new(-1990.6726, 4532.9995, -14973.675)) > 5294.99853515625 then
					tbl18:ExecuteTween(cframe)
				elseif localPlayer:DistanceFromCharacter(Vector3.new(-1990.6726, 4532.9995, -14973.675)) <= 5294.99853515625 then
					tbl18:InteractWithMirror()
				else
					tbl18:EngageEnemy({ "Cake Prince", "Dough King" })
				end
			elseif tbl18:FindEnemy({ "Baking Staff", "Head Baker", "Cake Guard", "Cookie Crafter" }) then
				tbl18:EngageEnemy({ "Baking Staff", "Head Baker", "Cake Guard", "Cookie Crafter" })
				local response2 = tbl6.CommF_:InvokeServer("CakePrinceSpawner", true)

				if response2 and response2:find("open the portal now") then
					tbl6.CommF_:InvokeServer("CakePrinceSpawner")
				end
			else
				tbl18:ExecuteTween(CFrame.new(-2072.1494140625, 70.133811950683594, -12097.0849609375))
			end
		end)
	end)

	result2:Toggle(v35, "Auto Dough King", "Summon and fight Dough King", "Save", function(arg)
		tbl16:SetSave("Auto Dough King", arg)
		tbl18:StopTween(arg)
	end)

	tbl4.__spawn(function()
		tbl18:CreateLoop("Auto Dough King", function()
			if not tbl18:CheckStackPriority("Auto Dough King") then
				return
			end

			if tbl18:HasTool("God's Chalice") then
				local response2 = tbl6.CommF_:InvokeServer("SweetChaliceNpc")

				if response2 and string.find(response2, "Where") then
					tbl18:EngageEnemy({ "Chocolate Bar Battler", "Cocoa Warrior" })
				else
					tbl6.CommF_:InvokeServer("SweetChaliceNpc")
				end
			elseif tbl18:HasTool("Sweet Chalice") then
				local response2 = tbl6.CommF_:InvokeServer("CakePrinceSpawner")

				if response2 and string.find(response2, "Do you want to open the portal now?") then
					tbl6.CommF_:InvokeServer("CakePrinceSpawner")
				else
					tbl18:EngageEnemy({ "Baking Staff", "Head Baker", "Cake Guard", "Cookie Crafter" })
				end
			elseif tbl18:FindEnemy({ "Dough King" }) then
				tbl18:EngageEnemy({ "Dough King" })
			end
		end)
	end)

	v35:AddSeperator({ "Elite Hunter" })
	local v38 = v35:AddParagraph({ Title = "Elite Status", Content = "Checking..." })
	local v39 = v35:AddParagraph({ Title = "Elite Progress", Content = "0/30" })

	tbl4.__spawn(function()
		while task.wait(2) do
			v38:Set({
				Title = "Elite Status",
				Content = tbl18:FindEnemy({ "Diablo", "Deandre", "Urban" }) and "Elite is Spawned!" or "Elite is not Spawned",
			})
		end
	end)

	tbl4.__spawn(function()
		while task.wait(2) do
			v39:Set({
				Title = "Elite Progress",
				Content = (tbl8[3] and tostring(tbl6.CommF_:InvokeServer("EliteHunter", "Progress")) or "N/A") .. "/30",
			})
		end
	end)

	result2:Toggle(v35, "Auto Elite Hunter", "Complete elite quests", "Save", function(arg)
		tbl16:SetSave("Auto Elite Hunter", arg)
		tbl18:StopTween(arg)
	end)

	tbl4.__spawn(function()
		tbl18:CreateLoop("Auto Elite Hunter", function()
			if not tbl18:CheckStackPriority("Auto Elite Hunter") then
				return
			end
			local tbl36 = { "Diablo", "Deandre", "Urban" }

			if tbl18:FindEnemy(tbl36) and tbl18:isQuestOn() then
				tbl18:EngageEnemy(tbl36)
			else
				if tbl18:HasTool("God's Chalice") then
					tbl18:FireRemote("requestEntrance", Vector3.new(-12471.17, 374.94025, -7551.6777))
					return
				end

				if not tbl18:isQuestOn() then
					tbl18:FireRemote("EliteHunter")
				end
			end
		end)
	end)

	v35:AddSeperator({ "Haki Color" })

	result2:Toggle(v35, "Auto Buy Haki Colors", "Purchase all Haki colors", "Save", function(arg)
		tbl16:SetSave("Auto Buy Haki Color", arg)
		tbl18:StopTween(arg)
	end)

	tbl4.__spawn(function()
		tbl18:CreateLoop("Auto Buy Haki Color", function()
			tbl18:FireRemote("ColorsDealer", "1")
			tbl18:FireRemote("ColorsDealer", "2")
		end)
	end)

	result2:Toggle(v35, "Auto Rainbow Haki", "Complete quests for Rainbow Haki", "Save", function(arg)
		tbl16:SetSave("Auto Rainbow Haki", arg)
		tbl18:StopTween(arg)
	end)

	tbl4.__spawn(function()
		tbl18:CreateLoop("Auto Rainbow Haki", function()
			local tbl36 = {}
			local tbl37 = { name = "Stone", pos = CFrame.new(-1049, 40, 6791) }
			local tbl38 = { name = "Island Empress", pos = CFrame.new(5730, 602, 199) }
			local tbl39 = { name = "Kilo Admiral", pos = CFrame.new(2889, 424, -7233) }
			local tbl40 = { name = "Captain Elephant", pos = CFrame.new(-13393, 319, -8423) }
			local tbl41 = { name = "Beautiful Pirate", pos = CFrame.new(5241, 23, 129) }
			tbl36[1] = tbl37
			tbl36[2] = tbl38
			tbl36[3] = tbl39
			tbl36[4] = tbl40
			tbl36[5] = tbl41
			local v40, v41, v42 = ipairs(tbl36)
			local flag = false

			for _, v43 in v40, v41, v42 do
				if tbl18:FindEnemy({ v43.name }) then
					tbl18:EngageEnemy({ v43.name })
					flag = true
					break
				end
			end

			if not flag then
				for _, v43 in ipairs(tbl36) do
					if not tbl18:FindEnemy({ v43.name }) then
						tbl18:ExecuteTween(v43.pos)
						break
					end
				end

				tbl18:FireRemote("HornedMan", "Bet")
			end
		end)
	end)

	result2:Toggle(v13:AddSection("Dragon Hunter"), "Auto Dragon Hunter Quests", "Complete Dragon Hunter quests", "Save", function(arg)
		tbl16:SetSave("Auto Dragon Hunter Quests", arg)
		tbl18:StopTween(arg)
	end)

	tbl4.__spawn(function()
		local flag = true
		local v40 = nil
		local cframe = CFrame.new(5863.67725, 1209.87292, 809.94458)

		local function fn18()
			local response2 = tbl6.Net["RF/DragonHunter"]:InvokeServer({ Context = "Check" })
			if response2 and response2.Text then
				return response2.Text
			end
			return tbl6.Net["RF/DragonHunter"]:InvokeServer({ Context = "RequestQuest" }).Text
		end

		local function fn19()
			if not tbl5.Workspace:FindFirstChild("EmberTemplate") then
				return false
			end

			for _, child in pairs(tbl5.Workspace:GetChildren()) do
				if child.Name == "EmberTemplate" and child:FindFirstChild("Part") then
					while true do
						tbl5.RunService.Heartbeat:Wait()
						tbl18:ExecuteTween(child.Part.CFrame)
						if not (not child or not child:FindFirstChild("Part") or not child.Parent or not tbl14["Auto Dragon Hunter Quests"]) then
							continue
						end
						break
					end

					return true
				end
			end

			return false
		end

		local function fn20(arg)
			local tbl36 = {}

			for _, child in pairs(tbl5.Workspace.Map.Waterfall.IslandModel:GetChildren()) do
				if child.Name == "Tree" and child:FindFirstChild("Group") then
					if child.Group:FindFirstChild("Meshes/bambootree") then
						table.insert(tbl36, child)
					end
				end
			end

			local n6 = 0

			for _, v41 in ipairs(tbl36) do
				if not (arg <= n6) then
					while true do
						tbl5.RunService.Heartbeat:Wait()

						if not tbl14["Auto Dragon Hunter Quests"] then
							break
						else
							tbl18:ExecuteTween(v41.WorldPivot)
							tbl18:EquipToolByTip("Melee")

							for _, v42 in ipairs({ "Z", "X", "C", "V", "F" }) do
								if tbl18:IsSkillAvailable(v42) then
									tbl18:SendKeyPress(v42)
								end
							end

							if not (not v41 or not v41.Parent or tbl5.Workspace:FindFirstChild("EmberTemplate") or flag or n6 >= arg or not tbl14["Auto Dragon Hunter Quests"]) then
								continue
							end
							break
						end
					end

					n6 += 1
					continue
				end

				break
			end

			if n6 < arg then
				flag = true
			end

			return n6
		end

		tbl18:CreateLoop("Auto Dragon Hunter Quests", function()
			if flag then
				if not tbl18:TweenToTargetIfFar(cframe, 10) then
					v40 = fn18()

					while true do
						tbl5.RunService.Heartbeat:Wait()
						if not (type(v40) == "string" or not tbl14["Auto Dragon Hunter Quests"] or not flag) then
							continue
						end
						break
					end

					flag = false
				end
			end

			if v40 and not flag then
				local str3 = string.find(v40, "Hydra Enforcers")
				local v41 = string.find(v40, "Venomous Assailants")

				if str3 or v41 then
					if not flag then
						str3 = str3 and "Hydra Enforcer" or "Venomous Assailant"
						local cframe2 = CFrame.new(5257.92285, 1005.51074, 383.1138, -0.277849764, -0.000232859355, 0.960624516, -2.70488472e-05, 1, 0.000234580555, -0.960624516, 3.91943649e-05, -0.277849764)

						if tbl18:FindEnemy({ str3 }) then
							tbl18:EngageEnemy({ str3 })
						else
							tbl18:ExecuteTween(cframe2)
						end

						if tbl5.Workspace:FindFirstChild("EmberTemplate") then
							flag = fn19()
						end
					end
				else
					local n6 = 10

					if string.find(v40, "/") then
						local v42 = string.split(v40, " ")

						if #v42 >= 2 then
							n6 = tonumber(string.split(v42[2], "/")[2]) or 10
						end
					end

					if fn20(n6) < n6 then
						if not flag then
							flag = fn19()
						end
					end
				end
			end
		end)
	end)

	result2:Toggle(v13:AddSection("Tyrant of the Skies"), "Auto Kill Tyrant of the Skies", "Defeat Tyrant of the Skies", "Save", function(arg)
		tbl16:SetSave("Auto Kill Tyrant of the Skies", arg)
		tbl18:StopTween(arg)
	end)

	tbl4.__spawn(function()
		tbl18:CreateLoop("Auto Kill Tyrant of the Skies", function()
			if not tbl18:CheckStackPriority("Auto Kill Tyrant of the Skies") then
				return
			end

			if tbl18:FindEnemy({ "Auto Kill Tyrant of the Skies" }) then
				tbl18:EngageEnemy({ "Auto Kill Tyrant of the Skies" })
			else
				tbl18:ExecuteTween(CFrame.new(-16557, 202, 508))
			end
		end)
	end)

	result2:Toggle(v13:AddSection("Citizen Quest"), "Auto Citizen Quest", "Complete citizen quests", "Save", function(arg)
		tbl16:SetSave("Auto Citizen Quest", arg)
		tbl18:StopTween(arg)
	end)

	tbl4.__spawn(function()
		tbl18:CreateLoop("Auto Citizen Quest", function()
			if not tbl18:CheckStackPriority("Auto Citizen Quest") then
				return
			end
			local tbl36 = { "Stone", "Island Empress", "Kilo Admiral", "Captain Elephant", "Beautiful Pirate" }

			if tbl18:isQuestOn() then
				if tbl18:FindEnemy(tbl36) then
					tbl18:EngageEnemy(tbl36)
				end
			elseif tbl18:GetDistance(Vector3.new(-11893.7, 929.661, -8760.59)) < 8 then
				tbl18:FireRemote("HornedMan", "Bet")
			else
				tbl18:ExecuteTween(CFrame.new(Vector3.new(-11893.7, 929.661, -8760.59)))
			end
		end)
	end)

	local v40 = v14:AddSection("Kitsune Island")
	local v41 = v40:AddParagraph({ Title = "Island Status", Content = "Checking..." })
	local v42 = v40:AddParagraph({ Title = "Azure Ember", Content = "0" })

	tbl4.__spawn(function()
		while task.wait(2) do
			v41:Set({
				Title = "Island Status",
				Content = tbl5.Workspace.Map:FindFirstChild("KitsuneIsland") and "Kitsune Island is Spawned!" or "Kitsune Island is not Spawned",
			})
		end
	end)

	tbl4.__spawn(function()
		while task.wait(2) do
			v42:Set({ Title = "Azure Ember", Content = tostring(tbl18:GetMaterialCount("Azure Ember")) })
		end
	end)

	result2:Toggle(v40, "Auto Summon Kitsune Island", "Sail to summon Kitsune Island", "Save", function(arg)
		tbl16:SetSave("Auto Summon Kitsune Island", arg)
		tbl18:StopTween(arg)
	end)

	tbl4.__spawn(function()
		tbl18:CreateLoop("Auto Summon Kitsune Island", function()
			if not tbl5.Workspace.Map:FindFirstChild("KitsuneIsland") then
				local playerBoat = tbl18:GetPlayerBoat()

				if not playerBoat then
					if localPlayer:DistanceFromCharacter(tbl9.BoatShopPos[2]) < 10 and localPlayer.Character and localPlayer.Character.Humanoid.Health > 0 then
						tbl18:FireRemote("BuyBoat", "PirateBrigade")
					else
						tbl18:ExecuteTween(tbl9.BoatShop[2])
					end
				elseif playerBoat then
					local vehicleSeat = playerBoat:FindFirstChild("VehicleSeat")
					local humanoid = localPlayer.Character and localPlayer.Character:FindFirstChildOfClass("Humanoid")

					if not humanoid or not humanoid.Sit then
						if vehicleSeat then
							tbl18:ExecuteTween(vehicleSeat.CFrame)
						end
					else
						tbl18:ExecuteBoatTween(playerBoat, playerBoat.PrimaryPart.CFrame * CFrame.new(0, 5, -50000))
					end
				end
			elseif tbl5.Workspace.Map:FindFirstChild("KitsuneIsland") then
				local shrineActive = tbl5.Workspace.Map.KitsuneIsland:FindFirstChild("ShrineActive")

				if shrineActive and shrineActive:FindFirstChild("NeonShrinePart") then
					tbl18:ExecuteTween(shrineActive.NeonShrinePart.CFrame * CFrame.new(0, 40, 10))
				end
			end
		end)
	end)

	result2:Toggle(v40, "Tween to Kitsune Island", "Teleport to Kitsune Island", "Save", function(arg)
		tbl16:SetSave("Tween to Kitsune Island", arg)
		tbl18:StopTween(arg)
	end)

	tbl4.__spawn(function()
		tbl18:CreateLoop("Tween to Kitsune Island", function()
			if tbl5.Workspace.Map and tbl5.Workspace.Map:FindFirstChild("KitsuneIsland") then
				local shrineActive = tbl5.Workspace.Map.KitsuneIsland:FindFirstChild("ShrineActive")

				if shrineActive and shrineActive:FindFirstChild("NeonShrinePart") then
					tbl18:ExecuteTween(shrineActive.NeonShrinePart.CFrame + Vector3.new(0, 0, 5))
				end
			end
		end)
	end)

	result2:Toggle(v40, "Auto Collect Azure Ember", "Collect Azure Ember", "Save", function(arg)
		tbl16:SetSave("Auto Collect Azure Ember", arg)
		tbl18:StopTween(arg)
	end)

	tbl4.__spawn(function()
		tbl18:CreateLoop("Auto Collect Azure Ember", function()
			if tbl5.Workspace:FindFirstChild("AttachedAzureEmber") then
				local emberTemplate = tbl5.Workspace:FindFirstChild("EmberTemplate")

				if emberTemplate and emberTemplate:FindFirstChild("Part") then
					tbl18:ExecuteTween(emberTemplate.Part.CFrame, 500)
				end
			end
		end)
	end)

	result2:Toggle(v40, "Auto Trade Azure Ember", "Trade Azure Ember", "Save", function(arg)
		tbl16:SetSave("Auto Trade Azure Ember", arg)
	end)

	tbl4.__spawn(function()
		tbl18:CreateLoop("Auto Trade Azure Ember", function()
			local rfKitsuneStatuePray = tbl6.Net:FindFirstChild("RF/KitsuneStatuePray")

			if rfKitsuneStatuePray then
				rfKitsuneStatuePray:InvokeServer()
			end

			tbl18:FireRemote("KitsuneStatuePray")
		end)
	end)

	local v43 = v14:AddSection("Sea Event")

	result2:Dropdown(v43, "Danger Level", "Sea danger level", false, { "1", "2", "3", "4", "5", "6", "infinite" }, { "6" }, function(arg)
		tbl16:SetSave("Select Level Danger", arg)
	end)

	result2:Dropdown(v43, "Boat Type", "Boat to purchase", false, { "PirateBrigade", "PirateGrandBrigade", "Beast Hunter", "MarineBrigade", "MarineGrandBrigade" }, { "PirateBrigade" }, function(arg)
		tbl16:SetSave("Select Buy Boat", arg)
	end)

	result2:Dropdown(v43, "Combat Weapon", "Weapon for sea combat", false, { "Melee", "Blox Fruit", "Gun", "Sword", "Random" }, { "Random" }, function(arg)
		tbl16:SetSave("Choose Equip ", arg)
	end)

	result2:Dropdown(v43, "Combat Skills", "Skills to use", true, { "Z", "X", "C", "V", "F" }, { "Z", "X", "C", "V" }, function(arg)
		tbl16:SetSave("Skill  ", arg, true)
	end)

	result2:Toggle(v43, "Protect Boat", "Auto-repair boat", true, function(arg)
		tbl16:SetSave("Protect Boat", arg)
	end)

	tbl4.__spawn(function()
		local cFrame = nil

		tbl18:CreateLoop("Protect Boat", function()
			if tbl14["Auto Summon Prehistoric Island"] or tbl14["Auto Summon Mirage Island"] or tbl14["Auto Summon Kitsune Island"] then
				return
			end
			local playerBoat = tbl18:GetPlayerBoat()
			local character = localPlayer.Character
			if not (tbl18:IsEntityAlive(character) and playerBoat and playerBoat:FindFirstChild("VehicleSeat")) then
				return
			end
			local humanoid = character:FindFirstChildOfClass("Humanoid")

			if humanoid and not humanoid.Sit then
				local flag = tbl18:FindEnemy({ "PirateGrandBrigade", "PirateBrigade", "FishBoat" }, 9e9, "Boat") or tbl18:FindEnemy({ "Terrorshark", "Piranha", "Fish Crew Member", "Shark" }, 9e9)

				if not flag then
					local seaBeast1 = tbl5.Workspace.SeaBeasts:FindFirstChild("SeaBeast1")
					seaBeast1 = seaBeast1 and seaBeast1:FindFirstChild("HumanoidRootPart")

					if seaBeast1 and tbl18:GetDistance(seaBeast1.Position) <= 9e9 then
						flag = true
					end
				end

				if flag then
					if not cFrame then
						cFrame = playerBoat.VehicleSeat.CFrame
					end

					local random = math.random
					playerBoat.VehicleSeat.CFrame = cFrame + Vector3.new(math.random(75, 100), math.random(75, 100), random(75, 100))
				elseif cFrame then
					playerBoat.VehicleSeat.CFrame = cFrame
					cFrame = nil
				end
			else
				cFrame = nil
			end
		end)
	end)

	result2:Toggle(v43, "No Fog", "Remove fog", "Save", function(arg)
		tbl16:SetSave("No Fog", arg)
	end)

	tbl4.__spawn(function()
		tbl18:CreateLoop("No Fog", function()
			tbl5.Lighting.FogEnd = 1e10
			tbl5.Lighting.Brightness = 2
			tbl5.Lighting.GlobalShadows = false
			tbl5.Lighting.ClockTime = 14
			tbl5.Lighting.ExposureCompensation = 0
		end)
	end)

	result2:Toggle(v43, "Auto Dodge Rough Sea", "Avoid rough sea", true, function(arg)
		tbl16:SetSave("Auto Dodge Rough Sea", arg)
	end)

	result2:Toggle(v43, "No Clip Rock", "Pass through rocks", true, function(arg)
		tbl16:SetSave("No Clip Rock", arg)
	end)

	tbl4.__spawn(function()
		tbl18:CreateLoop("No Clip Rock", function()
			local flag = localPlayer.Character and localPlayer.Character:FindFirstChildOfClass("Humanoid") and localPlayer.Character.Humanoid.Sit == true

			for _, descendant in pairs(tbl5.Workspace.Boats:GetDescendants()) do
				if descendant:IsA("BasePart") and descendant.CanCollide == flag then
					descendant.CanCollide = not flag
				end
			end

			for _, descendant in pairs(localPlayer.Character:GetDescendants()) do
				if descendant:IsA("BasePart") and descendant.CanCollide == flag then
					descendant.CanCollide = not flag
				end
			end
		end)
	end)

	v43:AddLine()

	result2:Toggle(v43, "Auto Farm Sea", "Farm sea enemies", "Save", function(arg)
		tbl16:SetSave("Auto Farm Sea", arg)
		tbl18:StopTween(arg)
	end)

	v43:AddLine()

	result2:Toggle(v43, "Farm Terrorshark", "Attack Terrorshark", true, function(arg)
		tbl16:SetSave("Terrorshark", arg)
	end)

	result2:Toggle(v43, "Dodge Terrorshark Skill", "Avoid Terrorshark attacks", true, function(arg)
		tbl16:SetSave("Auto Dodge Terrorshark Skill", arg)
	end)

	v43:AddLine()

	result2:Toggle(v43, "Attack Sea Beasts", "Attack Sea Beasts", true, function(arg)
		tbl16:SetSave("Attack Sea Beasts", arg)
	end)

	result2:Toggle(v43, "Dodge Sea Beasts Skill", "Avoid Sea Beast attacks", true, function(arg)
		tbl16:SetSave("Auto Dodge Sea Beasts Skill", arg)
	end)

	v43:AddLine()

	result2:Toggle(v43, "Attack Ghost Ship", "Attack Ghost Ships", true, function(arg)
		tbl16:SetSave("Attack Ghost Ship", arg)
	end)

	v43:AddLine()

	result2:Toggle(v43, "Attack Piranha", "Attack Piranha", true, function(arg)
		tbl16:SetSave("Attack Piranha", arg)
	end)

	result2:Toggle(v43, "Attack Shark", "Attack Shark", true, function(arg)
		tbl16:SetSave("Attack Shark", arg)
	end)

	result2:Toggle(v43, "Attack Fish Crew", "Attack Fish Crew", true, function(arg)
		tbl16:SetSave("Attack Fish Crew Member", arg)
	end)

	tbl4.__spawn(function()
		tbl18:CreateLoop("Auto Farm Sea", function()
			if not tbl18:IsEntityAlive(localPlayer.Character) then
				return
			end
			local playerBoat = tbl18:GetPlayerBoat()
			local v44 = tbl18:FindEnemy({ "Terrorshark" }, 1000)
			local v45 = tbl18:FindEnemy({ "Piranha" }, 1000)
			local v46 = tbl18:FindEnemy({ "Shark" }, 1000)
			local v47 = tbl18:FindEnemy({ "Fish Crew Member" }, 1000)
			local v48 = tbl18:FindEnemy({ "PirateGrandBrigade", "PirateBrigade", "FishBoat" }, 1000, "Boat")
			local seaBeast1 = tbl5.Workspace.SeaBeasts:FindFirstChild("SeaBeast1")
			local v49 = tbl9.LevelSea[tbl14["Select Level Danger"]]

			if tbl14.Terrorshark and v44 and playerBoat then
				if v44.PrimaryPart then
					if tbl14["Auto Dodge Terrorshark Skill"] and v44.PrimaryPart.CFrame.Y > -3 then
						tbl18:ExecuteTween(v44.PrimaryPart.CFrame * CFrame.new(0, 600, 0))
					else
						tbl18:EngageEnemy({ "Terrorshark" })
					end
				end
			elseif tbl14["Attack Piranha"] and v45 and playerBoat then
				tbl18:EngageEnemy({ "Piranha" })
			elseif tbl14["Attack Shark"] and v46 and playerBoat then
				tbl18:EngageEnemy({ "Shark" })
			elseif tbl14["Attack Fish Crew Member"] and v47 and playerBoat then
				tbl18:EngageEnemy({ "Fish Crew Member" })
			elseif tbl14["Attack Ghost Ship"] and v48 and playerBoat then
				if v48.VehicleSeat then
					while true do
						task.wait()
						local humanoid = localPlayer.Character and localPlayer.Character:FindFirstChildOfClass("Humanoid")
						tbl18:ExecuteTween(humanoid and humanoid.Health <= 5000 and v48.VehicleSeat.CFrame * CFrame.new(0, 400, 0) or v48.VehicleSeat.CFrame)

						if tbl18:GetDistance(v48.VehicleSeat.CFrame) <= 50 then
							SetAim(v48.VehicleSeat.CFrame)
							tbl18:EquipToolByTip(tbl14["Choose Equip "] == "Random" and ({ "Melee", "Blox Fruit", "Sword", "Gun" })[math.random(1, 4)] or tbl14["Choose Equip "])

							for _, v50 in next, tbl14["Skill  "], nil do
								if tbl18:IsSkillAvailable(v50) then
									tbl18:SendKeyPress(v50)
								end
							end
						end

						if not (not v48 or not v48.Parent or not v48.VehicleSeat or not tbl14["Attack Ghost Ship"] or not tbl14["Auto Farm Sea"] or v9.Unloaded) then
							continue
						end
						break
					end
				end
			elseif tbl14["Attack Sea Beasts"] and seaBeast1 and playerBoat then
				local humanoidRootPart = seaBeast1:FindFirstChild("HumanoidRootPart")

				if humanoidRootPart and tbl18:GetDistance(humanoidRootPart.Position) <= 5000 then
					TeleportToSeaBeast(seaBeast1)

					if tbl18:GetDistance(humanoidRootPart.Position) <= 800 then
						SetAim(humanoidRootPart.CFrame)
						tbl18:EquipToolByTip(tbl14["Choose Equip "] == "Random" and ({ "Melee", "Blox Fruit", "Sword", "Gun" })[math.random(1, 4)] or tbl14["Choose Equip "])

						for _, v50 in next, tbl14["Skill  "], nil do
							if tbl18:IsSkillAvailable(v50) then
								tbl18:SendKeyPress(v50)
							end
						end
					end
				end
			elseif playerBoat then
				local humanoid = localPlayer.Character:FindFirstChildOfClass("Humanoid")

				if not humanoid or not humanoid.Sit then
					local vehicleSeat = playerBoat:FindFirstChild("VehicleSeat")

					if vehicleSeat then
						tbl18:ExecuteTween(vehicleSeat.CFrame)
					end
				elseif tbl18:GetDistance(v49) > 15500 then
					tbl18:ExecuteBoatTween(playerBoat, v49 * CFrame.new(0, 20, 0))
				elseif tbl5.Lighting.RainCorrection and tbl5.Lighting.RainCorrection.Enabled and tbl14["Auto Dodge Rough Sea"] then
					tbl18:ExecuteBoatTween(playerBoat, localPlayer.Character.HumanoidRootPart.CFrame * CFrame.new(-150, 20, 15))
				elseif tbl5.Workspace.SeaBeasts:FindFirstChild("SeaBeast1") and not tbl14["Attack Sea Beasts"] then
					tbl18:ExecuteBoatTween(playerBoat, localPlayer.Character.HumanoidRootPart.CFrame * CFrame.new(-150, 20, 15))
				end
			elseif localPlayer:DistanceFromCharacter(tbl9.BoatShopPos[2]) < 10 and localPlayer.Character and localPlayer.Character.Humanoid.Health > 0 then
				tbl18:FireRemote("BuyBoat", tbl14["Select Buy Boat"])
				task.wait(1)
			else
				tbl18:ExecuteTween(tbl9.BoatShop[2])
			end
		end)
	end)

	local v44 = v14:AddSection("Leviathan Farming")
	v44:AddParagraph({ "Frozen Dimension" })
	local v45 = v44:AddParagraph({ Title = "Dimension Status", Content = "Checking..." })

	tbl4.__spawn(function()
		while task.wait(2) do
			v45:Set({
				Title = "Dimension Status",
				Content = tbl6.WorldOrigin.Locations:FindFirstChild("Frozen Dimension") and "Frozen Dimension is Spawned!" or "Frozen Dimension is not Spawned",
			})
		end
	end)

	result2:Toggle(v44, "Tween to Frozen Dimension", "Teleport to Frozen Dimension", "Save", function(arg)
		tbl16:SetSave("Tween to Frozen Dimension", arg)
		tbl18:StopTween(arg)
	end)

	tbl4.__spawn(function()
		tbl18:CreateLoop("Tween to Frozen Dimension", function()
			local frozenDimension = tbl6.WorldOrigin.Locations:FindFirstChild("Frozen Dimension")

			if frozenDimension then
				tbl18:ExecuteTween(frozenDimension * CFrame.new(2, 20, 2))
			end
		end)
	end)

	v44:AddLine()

	result2:Toggle(v44, "Auto Find Leviathan", "Sail to find Leviathan", "Save", function(arg)
		tbl16:SetSave("Auto Find Leviathan", arg)
		tbl18:StopTween(arg)
	end)

	tbl4.__spawn(function()
		tbl18:CreateLoop("Auto Find Leviathan", function()
			if not tbl6.WorldOrigin.Locations:FindFirstChild("Frozen Dimension") then
				local playerBoat = tbl18:GetPlayerBoat()

				if not playerBoat then
					if localPlayer:DistanceFromCharacter(tbl9.BoatShopPos[2]) < 10 and localPlayer.Character and localPlayer.Character.Humanoid.Health > 0 then
						tbl18:FireRemote("BuyBoat", "Beast Hunter")
					else
						tbl18:ExecuteTween(tbl9.BoatShop[2])
					end
				elseif playerBoat then
					local humanoid = localPlayer.Character and localPlayer.Character:FindFirstChildOfClass("Humanoid")

					if not humanoid or not humanoid.Sit then
						local vehicleSeat = playerBoat:FindFirstChild("VehicleSeat")

						if vehicleSeat then
							tbl18:ExecuteTween(vehicleSeat.CFrame)
						end
					else
						tbl18:ExecuteBoatTween(playerBoat, CFrame.new(-118140.65625, 31.783639907836914, 172404.875))
					end
				end
			else
				local frozenDimension = tbl6.WorldOrigin.Locations:FindFirstChild("Frozen Dimension")

				if frozenDimension then
					tbl18:ExecuteTween(frozenDimension * CFrame.new(2, 20, 2))
				end
			end
		end)
	end)

	result2:Toggle(v44, "Auto Attack Leviathan", "Attack Leviathan", "Save", function(arg)
		tbl16:SetSave("Auto Attack Leviathan", arg)
		tbl18:StopTween(arg)
	end)

	tbl4.__spawn(function()
		tbl18:CreateLoop("Auto Attack Leviathan", function()
			for _, child in pairs(tbl5.Workspace.SeaBeasts:GetChildren()) do
				if child and child.Name == "Leviathan" and child.Health and child.Health.Value > 0 then
					local humanoidRootPart = child:FindFirstChild("HumanoidRootPart")

					if humanoidRootPart then
						while true do
							task.wait()
							tbl18:ExecuteTween(humanoidRootPart.CFrame * CFrame.new(0, 900, 100))

							if tbl18:GetDistance(humanoidRootPart.CFrame) <= 500000 then
								SetAim(humanoidRootPart.CFrame)
								tbl18:EquipToolByTip(({ "Melee", "Blox Fruit", "Sword", "Gun" })[math.random(1, 4)])

								for _, v46 in next, { "Z", "X", "C", "V", "F" }, nil do
									if tbl18:IsSkillAvailable(v46) then
										tbl18:SendKeyPress(v46)
									end
								end
							end

							if not (not child.Parent or child.Health.Value <= 0 or not tbl14["Auto Attack Leviathan"] or v9.Unloaded) then
								continue
							end
							break
						end
					end
				end
			end
		end)
	end)

	result2:Toggle(v44, "Auto Attack Leviathan Segment", "Attack Leviathan segments", "Save", function(arg)
		tbl16:SetSave("Auto Attack Leviathan Segment", arg)
		tbl18:StopTween(arg)
	end)

	tbl4.__spawn(function()
		tbl18:CreateLoop("Auto Attack Leviathan Segment", function()
			for _, child in pairs(tbl5.Workspace.SeaBeasts:GetChildren()) do
				if child and child.Name == "Leviathan Segment" and child.Health and child.Health.Value > 0 then
					local humanoidRootPart = child:FindFirstChild("HumanoidRootPart")

					if humanoidRootPart then
						while true do
							task.wait()
							tbl18:ExecuteTween(humanoidRootPart.CFrame * CFrame.new(0, 900, math.random(0, 350)))

							if tbl18:GetDistance(humanoidRootPart.CFrame) <= 500000 then
								SetAim(humanoidRootPart.CFrame)
								tbl18:EquipToolByTip(({ "Melee", "Blox Fruit", "Sword", "Gun" })[math.random(1, 4)])

								for _, v46 in next, { "Z", "X", "C", "V", "F" }, nil do
									if tbl18:IsSkillAvailable(v46) then
										tbl18:SendKeyPress(v46)
									end
								end
							end

							if not (not child.Parent or child.Health.Value <= 0 or not tbl14["Auto Attack Leviathan Segment"] or v9.Unloaded) then
								continue
							end
							break
						end
					end
				end
			end
		end)
	end)

	result2:Toggle(v44, "Auto Attack Leviathan Tail", "Attack Leviathan tail", "Save", function(arg)
		tbl16:SetSave("Auto Attack Leviathan Tail", arg)
		tbl18:StopTween(arg)
	end)

	tbl4.__spawn(function()
		tbl18:CreateLoop("Auto Attack Leviathan Tail", function()
			for _, child in pairs(tbl5.Workspace.SeaBeasts:GetChildren()) do
				if child and child.Name == "Leviathan Tail" and child.Health and child.Health.Value > 0 then
					local humanoidRootPart = child:FindFirstChild("HumanoidRootPart")

					if humanoidRootPart then
						while true do
							task.wait()
							tbl18:ExecuteTween(humanoidRootPart.CFrame * CFrame.new(0, 900, math.random(0, 350)))

							if tbl18:GetDistance(humanoidRootPart.CFrame) <= 500000 then
								SetAim(humanoidRootPart.CFrame)
								tbl18:EquipToolByTip(({ "Melee", "Blox Fruit", "Sword", "Gun" })[math.random(1, 4)])

								for _, v46 in next, { "Z", "X", "C", "V", "F" }, nil do
									if tbl18:IsSkillAvailable(v46) then
										tbl18:SendKeyPress(v46)
									end
								end
							end

							if not (not child.Parent or child.Health.Value <= 0 or not tbl14["Auto Attack Leviathan Tail"] or v9.Unloaded) then
								continue
							end
							break
						end
					end
				end
			end
		end)
	end)

	result2:Toggle(v14:AddSection("Wood Planks"), "Auto Wood Planks", "Farm wood planks from trees", "Save", function(arg)
		tbl16:SetSave("Auto Wood Planks", arg)
		tbl18:StopTween(arg)
	end)

	tbl4.__spawn(function()
		tbl18:CreateLoop("Auto Wood Planks", function()
			local v46 = tbl18:FindTree()

			if v46 and v46.PrimaryPart then
				while true do
					task.wait()
					tbl18:ExecuteTween(v46.PrimaryPart.CFrame)

					if tbl18:GetDistance(v46.PrimaryPart.Position) < 10 then
						tbl18:EquipToolByTip(({ "Melee", "Blox Fruit", "Sword", "Gun" })[math.random(1, 4)])

						for _, v47 in next, { "Z", "X", "C", "V", "F" }, nil do
							if tbl18:IsSkillAvailable(v47) then
								tbl18:SendKeyPress(v47)
							end
						end
					end

					if not (not v46 or not v46.Parent or not tbl14["Auto Wood Planks"] or v9.Unloaded) then
						continue
					end
					break
				end
			end
		end)
	end)

	local v46 = v14:AddSection("Prehistoric Island")
	local v47 = v46:AddParagraph({ Title = "Island Status", Content = "Checking..." })

	tbl4.__spawn(function()
		while task.wait(2) do
			v47:Set({
				Title = "Island Status",
				Content = tbl5.Workspace.Map:FindFirstChild("PrehistoricIsland") and "Prehistoric Island is Spawned!" or "Prehistoric Island is not Spawned",
			})
		end
	end)

	result2:Toggle(v46, "Auto Summon Prehistoric Island", "Sail to summon island", "Save", function(arg)
		tbl16:SetSave("Auto Summon Prehistoric Island", arg)
		tbl18:StopTween(arg)
	end)

	tbl4.__spawn(function()
		tbl18:CreateLoop("Auto Summon Prehistoric Island", function()
			if not tbl5.Workspace.Map:FindFirstChild("PrehistoricIsland") then
				local playerBoat = tbl18:GetPlayerBoat()

				if not playerBoat then
					if localPlayer:DistanceFromCharacter(tbl9.BoatShopPos[2]) < 10 and localPlayer.Character and localPlayer.Character.Humanoid.Health > 0 then
						tbl18:FireRemote("BuyBoat", "PirateBrigade")
					else
						tbl18:ExecuteTween(tbl9.BoatShop[2])
					end
				elseif playerBoat then
					local humanoid = localPlayer.Character and localPlayer.Character:FindFirstChildOfClass("Humanoid")

					if not humanoid or not humanoid.Sit then
						local vehicleSeat = playerBoat:FindFirstChild("VehicleSeat")

						if vehicleSeat then
							tbl18:ExecuteTween(vehicleSeat.CFrame)
						end
					else
						tbl18:ExecuteBoatTween(playerBoat, CFrame.new(-118140.65625, 31.783639907836914, 172404.875))
					end
				end
			else
				local prehistoricIsland = tbl5.Workspace.Map:FindFirstChild("PrehistoricIsland")

				if prehistoricIsland then
					tbl18:ExecuteTween(prehistoricIsland:GetPivot() * CFrame.new(2, 20, 2))
				end
			end
		end)
	end)

	result2:Toggle(v46, "Tween To Prehistoric Island", "Teleport to island", "Save", function(arg)
		tbl16:SetSave("Tween To Prehistoric Island", arg)
		tbl18:StopTween(arg)
	end)

	tbl4.__spawn(function()
		tbl18:CreateLoop("Tween To Prehistoric Island", function()
			local prehistoricIsland = tbl5.Workspace.Map:FindFirstChild("PrehistoricIsland")

			if prehistoricIsland then
				tbl18:ExecuteTween(prehistoricIsland:GetPivot() * CFrame.new(2, 20, 2))
			end
		end)
	end)

	local v48 = v14:AddSection("Sea Items")

	result2:Toggle(v48, "Auto Shark Tooth Necklace", "Craft Shark Tooth Necklace", "Save", function(arg)
		tbl16:SetSave("Auto Shark Tooth Necklace", arg)
		tbl18:StopTween(arg)
	end)

	tbl4.__spawn(function()
		tbl18:CreateLoop("Auto Shark Tooth Necklace", function()
			if not tbl18:HasTool("Shark Tooth Necklace") then
				if tbl18:GetMaterialCount("Mutant Tooth") >= 1 and tbl18:GetMaterialCount("Shark Teeth") >= 5 then
					tbl18:FireRemote("CraftItem", "PossibleHardcode", "SharkAnchor")
					tbl18:FireRemote("CraftItem", "Check", "ToothNecklace")
					tbl18:FireRemote("CraftItem", "Craft", "ToothNecklace")
				elseif not tbl14["Auto Farm Sea"] then
					tbl14["Auto Farm Sea"] = true

					while true do
						task.wait()
						if not (tbl18:GetMaterialCount("Mutant Tooth") >= 1 and tbl18:GetMaterialCount("Shark Teeth") >= 5 or not tbl14["Auto Shark Tooth Necklace"] or v9.Unloaded) then
							continue
						end
						break
					end

					tbl14["Auto Farm Sea"] = false
				end
			end
		end)
	end)

	result2:Toggle(v48, "Auto Terror Jaw", "Craft Terror Jaw", "Save", function(arg)
		tbl16:SetSave("Auto Terror Jaw", arg)
		tbl18:StopTween(arg)
	end)

	tbl4.__spawn(function()
		tbl18:CreateLoop("Auto Terror Jaw", function()
			if not tbl18:HasTool("Terror Jaw") then
				if tbl18:GetMaterialCount("Terror Jaw") >= 1 and tbl18:GetMaterialCount("Mutant Teeth") >= 2 and tbl18:GetMaterialCount("Fool's Gold") >= 10 and tbl18:GetMaterialCount("Shark Teeth") >= 5 then
					tbl18:FireRemote("CraftItem", "PossibleHardcode", "SharkAnchor")
					tbl18:FireRemote("CraftItem", "Check", "TerrorJaw")
					tbl18:FireRemote("CraftItem", "Craft", "TerrorJaw")
				elseif not tbl14["Auto Farm Sea"] then
					tbl14["Auto Farm Sea"] = true

					while true do
						task.wait()
						if not (tbl18:GetMaterialCount("Terror Jaw") >= 1 and tbl18:GetMaterialCount("Mutant Teeth") >= 2 and tbl18:GetMaterialCount("Fool's Gold") >= 10 and tbl18:GetMaterialCount("Shark Teeth") >= 5 or not tbl14["Auto Terror Jaw"] or v9.Unloaded) then
							continue
						end
						break
					end

					tbl14["Auto Farm Sea"] = false
				end
			end
		end)
	end)

	result2:Toggle(v48, "Auto Monster Magnet", "Craft Monster Magnet", "Save", function(arg)
		tbl16:SetSave("Auto Monster Magnet", arg)
		tbl18:StopTween(arg)
	end)

	tbl4.__spawn(function()
		tbl18:CreateLoop("Auto Monster Magnet", function()
			if tbl18:GetMaterialCount("Monster Magnet") < 1 then
				if tbl18:GetMaterialCount("Terror Eyes") >= 2 and tbl18:GetMaterialCount("Electric Wings") >= 8 and tbl18:GetMaterialCount("Fool's Gold") >= 20 and tbl18:GetMaterialCount("Shark Teeth") >= 10 then
					tbl18:FireRemote("CraftItem", "Check", "SharkAnchor")
					tbl18:FireRemote("CraftItem", "Craft", "SharkAnchor")
				elseif not tbl14["Auto Farm Sea"] then
					tbl14["Auto Farm Sea"] = true

					while true do
						task.wait()
						if not (tbl18:GetMaterialCount("Terror Eyes") >= 2 and tbl18:GetMaterialCount("Electric Wings") >= 8 and tbl18:GetMaterialCount("Fool's Gold") >= 20 and tbl18:GetMaterialCount("Shark Teeth") >= 10 or not tbl14["Auto Monster Magnet"] or v9.Unloaded) then
							continue
						end
						break
					end

					tbl14["Auto Farm Sea"] = false
				end
			end
		end)
	end)

	result2:Toggle(v48, "Auto Shark Anchor", "Craft Shark Anchor", "Save", function(arg)
		tbl16:SetSave("Auto Shark Anchor", arg)
		tbl18:StopTween(arg)
	end)

	tbl4.__spawn(function()
		tbl18:CreateLoop("Auto Shark Anchor", function()
			if not tbl18:HasTool("Shark Anchor") then
				if tbl18:GetMaterialCount("Monster Magnet") >= 1 then
					if not tbl14["Auto Farm Sea"] then
						tbl14["Auto Farm Sea"] = true

						while true do
							task.wait()
							if not (tbl18:HasTool("Shark Anchor") or not tbl14["Auto Shark Anchor"] or v9.Unloaded) then
								continue
							end
							break
						end

						tbl14["Auto Farm Sea"] = false
					end
				elseif not tbl14["Auto Monster Magnet"] then
					tbl14["Auto Monster Magnet"] = true

					while true do
						task.wait()
						if not (tbl18:GetMaterialCount("Monster Magnet") >= 1 or not tbl14["Auto Shark Anchor"] or v9.Unloaded) then
							continue
						end
						break
					end

					tbl14["Auto Monster Magnet"] = false
				end
			end
		end)
	end)

	local Maps = v15:AddSection("Maps", true)

	result2:Dropdown(Maps, "Select Island", "Island to teleport to", false, tbl18:GetIslandList(), "Save", function(arg)
		tbl16:SetSave("Select Island", arg)
	end)

	result2:Toggle(Maps, "Tween To Island", "Auto teleport to island", "Save", function(arg)
		tbl16:SetSave("Tween To Island", arg)
		tbl18:StopTween(arg)
	end)

	tbl4.__spawn(function()
		tbl18:CreateLoop("Tween To Island", function()
			tbl18:NavigateToIsland(tbl14["Select Island"])
		end)
	end)

	Maps:AddLine()

	result2:Button(Maps, "First World", "Teleport to First World", function()
		tbl18:FireRemote("TravelMain")
	end)

	result2:Button(Maps, "Second World", "Teleport to Second World", function()
		tbl18:FireRemote("TravelDressrosa")
	end)

	result2:Button(Maps, "Third World", "Teleport to Third World", function()
		tbl18:FireRemote("TravelZou")
	end)

	local Fruits = v16:AddSection("Fruits")
	Fruits:AddSeperator({ "Fruit Sniper" })
	local tbl36 = {}
	tbl6.CommF_:InvokeServer("GetFruits")
	local response2

	while true do
		task.wait()
		response2 = tbl6.CommF_:InvokeServer("GetFruits")
		if not (response2 and #response2 > 0) then
			continue
		end
		break
	end

	for _, v49 in response2, nil, nil do
		table.insert(tbl36, v49.Name)
	end

	result2:Dropdown(Fruits, "Sniper Fruits", "Fruits to buy", true, tbl36, "Save", function(arg)
		tbl16:SetSave("Sniper Fruits", arg, true)
	end)

	result2:Toggle(Fruits, "Auto Buy Fruits Sniper", "Buy fruits from Sniper", "Save", function(arg)
		tbl16:SetSave("Auto Buy Fruits Sniper", arg)
	end)

	tbl4.__spawn(function()
		tbl18:CreateLoop("Auto Buy Fruits Sniper", function()
			for _, v49 in next, tbl14["Sniper Fruits"], nil do
				tbl18:FireRemote("PurchaseRawFruit", v49, false)
			end
		end)
	end)

	Fruits:AddLine()

	result2:Dropdown(Fruits, "Sniper Fruits (Mirage)", "Fruits from Mirage Sniper", true, tbl36, "Save", function(arg)
		tbl16:SetSave("Sniper Fruits (Mirage Island)", arg, true)
	end)

	result2:Toggle(Fruits, "Auto Buy Fruits Sniper (Mirage)", "Buy fruits from Mirage Sniper", "Save", function(arg)
		tbl16:SetSave("Auto Buy Fruits Sniper (Mirage Island)", arg)
	end)

	tbl4.__spawn(function()
		tbl18:CreateLoop("Auto Buy Fruits Sniper (Mirage Island)", function()
			for _, v49 in next, tbl14["Sniper Fruits (Mirage Island)"], nil do
				tbl18:FireRemote("PurchaseRawFruit", v49, true)
			end
		end)
	end)

	Fruits:AddSeperator({ "Fruit Management" })

	result2:Toggle(Fruits, "Auto Random Fruit", "Buy random fruit from Cousin", "Save", function(arg)
		tbl16:SetSave("Auto Random Fruit", arg)
	end)

	tbl4.__spawn(function()
		tbl18:CreateLoop("Auto Random Fruit", function()
			tbl18:FireRemote("Cousin", "Buy")
		end)
	end)

	result2:Toggle(Fruits, "Auto Store Fruit", "Store fruits in inventory", "Save", function(arg)
		tbl16:SetSave("Auto Store Fruit", arg)
	end)

	tbl4.__spawn(function()
		tbl18:CreateLoop("Auto Store Fruit", function()
			local currentFruit, v49, v50 = tbl18:GetCurrentFruit()

			if v49 and v50 then
				tbl18:FireRemote("StoreFruit", v49, v50)
			end
		end)
	end)

	result2:Toggle(Fruits, "Auto Drop Fruit", "Drop fruits from inventory", "Save", function(arg)
		tbl16:SetSave("Auto Drop Fruit", arg)
	end)

	tbl4.__spawn(function()
		tbl18:CreateLoop("Auto Drop Fruit", function()
			local currentFruit, v49, v50 = tbl18:GetCurrentFruit()

			if v49 and v50 then
				tbl18:FireRemote("Drop", v49, v50)
			end
		end)
	end)

	result2:Toggle(Fruits, "Auto Eat Fruit", "Eat fruits automatically", "Save", function(arg)
		tbl16:SetSave("Auto Eat Fruit", arg)
	end)

	tbl4.__spawn(function()
		tbl18:CreateLoop("Auto Eat Fruit", function()
			local eatRemote = localPlayer.Character and localPlayer.Character:FindFirstChild("EatRemote", true)

			if eatRemote then
				eatRemote:InvokeServer()
			end
		end)
	end)

	result2:Toggle(Fruits, "Auto Find Fruit", "Find and collect fruits on ground", "Save", function(arg)
		tbl16:SetSave("Auto Find Fruit", arg)
		tbl18:StopTween(arg)
	end)

	tbl4.__spawn(function()
		tbl18:CreateLoop("Auto Find Fruit", function()
			local v49 = tbl18:FindGroundFruit()

			if v49 then
				tbl18:ExecuteTween(v49.CFrame)
			end
		end)
	end)

	Fruits:AddSeperator({ "Fruit Spawner" })

	result2:Dropdown(Fruits, "Spawner Fruits", "Fruits to collect from spawner", true, tbl10, "Save", function(arg)
		tbl16:SetSave("Choose Spawner Fruit", arg, true)
	end)

	result2:Toggle(Fruits, "Auto Get Spawner Fruit", "Collect fruits from spawner", "Save", function(arg)
		tbl16:SetSave("Auto Gets Fruit Spawner", arg)
		tbl18:StopTween(arg)
	end)

	tbl4.__spawn(function()
		tbl5.Workspace.ChildAdded:Connect(function(child)
			local tbl37 = {}

			if tbl14["Auto Gets Fruit Spawner"] and not v9.Unloaded then
				if table.find(tbl14["Choose Spawner Fruit"], child.Name) and child:FindFirstChild("Handle") then
					for k, v49 in pairs(tbl14) do
						if k ~= "Auto Gets Fruit Spawner" and k ~= "Auto Random Fruit" and k ~= "Auto Store Fruit" and v49 == true then
							tbl37[k] = v49
							tbl14[k] = false
						end
					end

					tbl18:ExecuteTween(child.Handle.CFrame)

					while true do
						task.wait()
						if not (not tbl14["Auto Gets Fruit Spawner"] or not child:FindFirstChild("Handle") or tbl18:GetDistance(child.Handle.CFrame) <= 4 or v9.Unloaded) then
							continue
						end
						break
					end

					task.wait(2)

					for k, v49 in pairs(tbl37) do
						tbl14[k] = v49
					end
				end
			end
		end)
	end)

	local Shop = v16:AddSection("Shop")

	result2:Toggle(Shop, "Auto Buy Legendary Sword", "Buy all legendary swords", "Save", function(arg)
		tbl16:SetSave("Auto Buy Legendary Sword", arg)
	end)

	tbl4.__spawn(function()
		tbl18:CreateLoop("Auto Buy Legendary Sword", function()
			tbl18:FireRemote("LegendarySwordDealer", "1")
			tbl18:FireRemote("LegendarySwordDealer", "2")
			tbl18:FireRemote("LegendarySwordDealer", "3")
		end)
	end)

	result2:Toggle(Shop, "Auto Buy True Triple Katana", "Buy True Triple Katana", "Save", function(arg)
		tbl16:SetSave("Auto Buy True Triple Katana", arg)
	end)

	tbl4.__spawn(function()
		tbl18:CreateLoop("Auto Buy True Triple Katana", function()
			tbl18:FireRemote("MysteriousMan", "1")
			tbl18:FireRemote("MysteriousMan", "2")
		end)
	end)

	for _, v49 in ipairs(tbl11) do
		local v50 = v49[2]
		Shop:AddSeperator({ v49[1] })

		for _, v51 in ipairs(v50) do
			local v52 = v51[1]
			local v53 = v51[2]

			result2:Button(Shop, v52, "Purchase " .. v52, type(v53) == "table" and function()
				tbl6.CommF_:InvokeServer(unpack(v53))
			end or v53)
		end
	end

	local v49 = v13:AddSection("Automation Fishing")

	result2:Toggle(v49, "Auto Equip Rod", "Auto-equip fishing rod", "Save", function(arg)
		tbl16:SetSave("Auto Equip Rod", arg)
	end)

	tbl4.__spawn(function()
		tbl18:CreateLoop("Auto Equip Rod", function()
			local tool = localPlayer.Character:FindFirstChildWhichIsA("Tool")

			if not tool or tool:GetAttribute("InventoryCategory") ~= "Rod" then
				for _, child in pairs(localPlayer.Backpack:GetChildren()) do
					if child:IsA("Tool") and child:GetAttribute("InventoryCategory") == "Rod" then
						localPlayer.Character.Humanoid:EquipTool(child)
						break
					end
				end
			end
		end)
	end)

	result2:Toggle(v49, "Auto Fishing", "Auto-fish in current location", "Save", function(arg)
		tbl16:SetSave("Auto Fishing", arg)
	end)

	tbl4.__spawn(function()
		local function fn18(arg)
			if not arg then
				return
			end
			local humanoid = (localPlayer.Character or localPlayer.CharacterAdded:Wait()):WaitForChild("Humanoid")

			if typeof(arg) == "Instance" and arg:IsA("Animation") then
				local v50 = humanoid:LoadAnimation(arg)
				v50:Play()
				return v50
			end
		end

		tbl18:CreateLoop("Auto Fishing", function()
			local character = localPlayer.Character
			local tool = character and character:FindFirstChildWhichIsA("Tool")
			local humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart")
			if not tool or tool:GetAttribute("InventoryCategory") ~= "Rod" then
				return
			end

			if tool:GetAttribute("SkillChargeAlpha") >= 1 then
				tbl6.Net:FindFirstChild("RF/JobToolAbilities"):InvokeServer("Z", true)
			end

			local attribute = tool:GetAttribute("State")
			local position = humanoidRootPart.Position
			local v50 = require(tbl5.ReplicatedStorage.Util.GetWaterHeightAtLocation)(position)
			local tbl37 = { character, tbl5.Workspace.Characters, tbl5.Workspace.Enemies }
			local v51, v52 = tbl5.Workspace:FindPartOnRayWithIgnoreList(Ray.new(character.Head.Position, humanoidRootPart.CFrame.LookVector * require(tbl5.ReplicatedStorage.FishReplicated.FishingClient.Config).Rod.MaxLaunchDistance * 0.99751243781094523), tbl37)
			local tbl38 = { character, tbl5.Workspace.Characters, tbl5.Workspace.Enemies }
			local v53, v54 = tbl5.Workspace:FindPartOnRayWithIgnoreList(Ray.new(v52 + Vector3.new(0, 3, 0), Vector3.new(0, -500, 0)), tbl38)
			local vector2 = v54 and v54.Y < v50 and Vector3.new(v52.X, math.max(v54.Y, v50), v52.Z) or nil

			if attribute == "ReeledIn" then
				pcall(function()
					fn18(tbl5.ReplicatedStorage.Util.Anims.Storage["2"].Fishing.Fishing_Cast)
				end)

				tbl5.ReplicatedStorage.FishReplicated.FishingRequest:InvokeServer("StartCasting")
				task.wait(0.7)

				if vector2 then
					tbl5.ReplicatedStorage.FishReplicated.FishingRequest:InvokeServer("CastLineAtLocation", vector2, 100, true)
				end
			elseif attribute == "Biting" then
				pcall(function()
					fn18(tbl5.ReplicatedStorage.Util.Anims.Storage["2"].Fishing.Fishing_PullFishOut)
				end)

				tbl5.ReplicatedStorage.FishReplicated.FishingRequest:InvokeServer("Catching", true)
				task.wait(0.25)
				tbl5.ReplicatedStorage.FishReplicated.FishingRequest:InvokeServer("Catch", 1)
			else
				pcall(function()
					fn18(tbl5.ReplicatedStorage.Util.Anims.Storage["2"].Fishing.Fishing_Idle)
				end)
			end
		end)
	end)

	result2:Toggle(v49, "Auto Sell Fish", "Sell caught fish", "Save", function(arg)
		tbl16:SetSave("Auto Sell Fish", arg)
	end)

	tbl4.__spawn(function()
		tbl18:CreateLoop("Auto Sell Fish", function()
			tbl6.Net:FindFirstChild("RF/JobsRemoteFunction"):InvokeServer("FishingNPC", "SellFish")
			task.wait(0.5)
		end)
	end)

	result2:Toggle(v49, "Auto Sell Corrupted Fish", "Sell corrupted fish", "Save", function(arg)
		tbl16:SetSave("Auto Sell Corrupted Fish", arg)
	end)

	tbl4.__spawn(function()
		tbl18:CreateLoop("Auto Sell Corrupted Fish", function()
			tbl6.Net:FindFirstChild("RF/JobsRemoteFunction"):InvokeServer("FishingNPC", "SellCorruptedFish")
			task.wait(0.5)
		end)
	end)

	local v50 = v14:AddSection("Mirage Island")
	local v51 = v50:AddParagraph({ Title = "Island Status", Content = "Checking..." })

	tbl4.__spawn(function()
		while task.wait(2) do
			v51:Set({
				Title = "Island Status",
				Content = tbl6.WorldOrigin.Locations:FindFirstChild("Mirage Island") and "Mirage Island is Spawned!" or "Mirage Island is not Spawned",
			})
		end
	end)

	result2:Toggle(v50, "Auto Summon Mirage Island", "Sail to summon Mirage Island", "Save", function(arg)
		tbl16:SetSave("Auto Summon Mirage Island", arg)
		tbl18:StopTween(arg)
	end)

	tbl4.__spawn(function()
		tbl18:CreateLoop("Auto Summon Mirage Island", function()
			if not tbl6.WorldOrigin.Locations:FindFirstChild("Mirage Island") then
				local playerBoat = tbl18:GetPlayerBoat()

				if not playerBoat then
					if localPlayer:DistanceFromCharacter(tbl9.BoatShopPos[2]) < 10 and localPlayer.Character and localPlayer.Character.Humanoid.Health > 0 then
						tbl18:FireRemote("BuyBoat", "PirateBrigade")
					else
						tbl18:ExecuteTween(tbl9.BoatShop[2])
					end
				elseif playerBoat then
					local humanoid = localPlayer.Character and localPlayer.Character:FindFirstChildOfClass("Humanoid")

					if not humanoid or not humanoid.Sit then
						local vehicleSeat = playerBoat:FindFirstChild("VehicleSeat")

						if vehicleSeat then
							tbl18:ExecuteTween(vehicleSeat.CFrame)
						end
					else
						tbl18:ExecuteBoatTween(playerBoat, playerBoat.PrimaryPart.CFrame * CFrame.new(0, 5, -500000))
					end
				end
			else
				local mirageIsland = tbl6.WorldOrigin.Locations:FindFirstChild("Mirage Island")

				if mirageIsland and mirageIsland.PrimaryPart then
					tbl18:ExecuteTween(mirageIsland.PrimaryPart.CFrame * CFrame.new(0, 500, 0))
				end
			end
		end)
	end)

	result2:Toggle(v50, "Tween To Mirage Island", "Teleport to Mirage Island", "Save", function(arg)
		tbl16:SetSave("Tween To Mirage Island", arg)
		tbl18:StopTween(arg)
	end)

	tbl4.__spawn(function()
		tbl18:CreateLoop("Tween To Mirage Island", function()
			local mirageIsland = tbl6.WorldOrigin.Locations:FindFirstChild("Mirage Island")

			if mirageIsland and mirageIsland.PrimaryPart then
				tbl18:ExecuteTween(mirageIsland.PrimaryPart.CFrame * CFrame.new(0, 500, 0))
			end
		end)
	end)

	local v52 = v13:AddSection("Upgrade Race")

	result2:Toggle(v52, "Auto V2", "Upgrade race to V2", "Save", function(arg)
		tbl16:SetSave("Auto V2", arg)
	end)

	result2:Toggle(v52, "Auto V3", "Upgrade race to V3", "Save", function(arg)
		tbl16:SetSave("Auto V3", arg)
	end)

	tbl4.__spawn(function()
		tbl18:CreateLoop("Auto V2", function()
			if string.find(tbl18:GetRaceInfo(), "V1") then
				if not localPlayer.Data.Race:FindFirstChild("Evolved") then
					local response3 = tbl5.ReplicatedStorage.Remotes.CommF_:InvokeServer("Alchemist", "1")

					if response3 == 0 then
						local cframe = CFrame.new(-2779.83521, 72.9661407, -3574.02002)
						tbl18:ExecuteTween(cframe)

						if localPlayer:DistanceFromCharacter(cframe.Position) <= 4 then
							task.wait(1.3)
							tbl5.ReplicatedStorage.Remotes.CommF_:InvokeServer("Alchemist", "2")
						end
					elseif response3 == 1 then
						pcall(function()
							local flag = false

							for _, v53 in ipairs({ "Flower 1", "Flower 2", "Flower 3" }) do
								if not localPlayer.Backpack:FindFirstChild(v53) and not localPlayer.Character:FindFirstChild(v53) then
									local v54 = tbl5.Workspace:FindFirstChild(v53)

									if v54 then
										tbl18:ExecuteTween(v54.CFrame)
										flag = true
										break
									end
								end
							end

							if not flag then
								local zombie = tbl6.Enemies:FindFirstChild("Zombie")

								if zombie then
									tbl18:EngageEnemy({ zombie.Name })
								else
									tbl18:ExecuteTween(CFrame.new(-5685.9233398438, 48.480125427246, -853.23724365234))
								end
							end
						end)
					elseif response3 == 2 then
						tbl5.ReplicatedStorage.Remotes.CommF_:InvokeServer("Alchemist", "3")
					end
				end
			else
				v9:SetNotification({ "Facility", "Auto V2", "Your race is already V2 or higher", 5, 0.5 })
			end
		end)

		tbl18:CreateLoop("Auto V3", function()
			local raceInfo = tbl18:GetRaceInfo()
			local response3 = tbl5.ReplicatedStorage.Remotes.CommF_:InvokeServer("Wenlocktoad", "1")

			if response3 == 0 then
				tbl5.ReplicatedStorage.Remotes.CommF_:InvokeServer("Wenlocktoad", "2")
			elseif response3 == 2 then
				tbl5.ReplicatedStorage.Remotes.CommF_:InvokeServer("Wenlocktoad", "3")
			elseif response3 == 1 then
				if raceInfo == "Human V2" then
					tbl18:ProcessHumanV3()
				elseif raceInfo == "Mink V2" then
					tbl18:HandleMinkV2()
				elseif raceInfo == "Skypiea V2" then
					tbl18:HandleSkypieaV3()
				elseif raceInfo == "Cyborg V2" then
					if not tbl18:GetEquippedFruit() and tbl18:GetFruitInventory() then
						tbl5.ReplicatedStorage.Remotes.CommF_:InvokeServer("LoadFruit", tbl18:GetFruitInventory())
					end
				elseif raceInfo == "Fishman V2" then
					tbl18:HandleFishmanV2()
				end
			elseif response3 == -1 then
				v9:SetNotification({ "Facility", "Auto V3", "You need more than 2M Beli", 5, 0.5 })
			end
		end)
	end)

	v52:AddParagraph({ Title = "V4 Race", Content = "Upgrade to V4" })

	result2:Button(v52, "Teleport To Temple", "Teleport to Temple of Time", function()
		tbl18:TeleportToTemple()
	end)

	result2:Button(v52, "Teleport To Ancient One", "Teleport to Ancient One", function()
		tbl18:TeleportToTemple()
		tbl18:ExecuteTween(CFrame.new(28981, 14888, -120))
	end)

	result2:Button(v52, "Teleport To Ancient Clock", "Teleport to Ancient Clock", function()
		tbl18:TeleportToTemple()
		tbl18:ExecuteTween(CFrame.new(29549, 15069, -88))
	end)

	result2:Button(v52, "Teleport To Race Door", "Teleport to your race's door", function()
		local tbl37 = {
			Mink = CFrame.new(29020.66015625, 14889.426757812, -379.2682800293),
			Fishman = CFrame.new(28224.056640625, 14889.426757812, -210.58720397949),
			Cyborg = CFrame.new(28492.4140625, 14894.426757812, -422.11001586914),
			Skypiea = CFrame.new(28967.408203125, 14918.075195312, 234.31198120117),
			Ghoul = CFrame.new(28672.720703125, 14889.127929688, 454.59616088867),
			Human = CFrame.new(29237.294921875, 14889.426757812, -206.94955444336),
		}

		tbl18:TeleportToTemple()
		local v53 = tbl37[localPlayer.Data.Race.Value]

		if v53 then
			tbl18:ExecuteTween(v53)
		end
	end)

	result2:Button(v52, "Pull Lever", "Pull the lever in Temple of Time", function()
		for _, descendant in pairs(tbl5.Workspace.Map["Temple of Time"]:GetDescendants()) do
			if descendant.Name == "ProximityPrompt" then
				fireproximityprompt(descendant, math.huge)
			end
		end
	end)

	result2:Toggle(v52, "Auto Trial", "Complete race trial automatically", "Save", function(arg)
		tbl16:SetSave("Auto Trial", arg)
	end)

	local function fn18()
		if not tbl5.Workspace.Map:FindFirstChild("FishmanTrial") then
			return
		end
		local trialOfWater = tbl6.WorldOrigin.Locations:FindFirstChild("Trial of Water")
		if not trialOfWater then
			return
		end

		for _, child in pairs(tbl5.Workspace.SeaBeasts:GetChildren()) do
			local humanoidRootPart = child:FindFirstChild("HumanoidRootPart")
			local health = child:FindFirstChild("Health")
			if humanoidRootPart and health and health.Value > 0 and (humanoidRootPart.Position - trialOfWater.Position).Magnitude <= 1500 then
				return child
			end
		end
	end

	tbl4.__spawn(function()
		tbl18:CreateLoop("Auto Trial", function()
			pcall(function()
				if not tbl14["Auto Trial"] then
					return
				end
				local str3 = tostring(localPlayer.Data.Race.Value)
				local character = localPlayer.Character
				character = character and character:FindFirstChild("HumanoidRootPart")

				if str3 == "Mink" and character then
					character.CFrame = tbl5.Workspace.Map.MinkTrial.Ceiling.CFrame * CFrame.new(0, -20, 0)
				elseif str3 == "Fishman" then
					local v53 = fn18()
					if not v53 then
						return
					end

					while true do
						task.wait()
						local humanoidRootPart = v53:FindFirstChild("HumanoidRootPart")

						if not humanoidRootPart then
							break
						else
							tbl18:ExecuteTween(CFrame.new(humanoidRootPart.Position.X, tbl5.Workspace.Map["WaterBase-Plane"].Position.Y + 300, humanoidRootPart.Position.Z))
							SetAim(humanoidRootPart.CFrame)
							tbl18:EquipToolByTip(tbl14["Choose Equip "] == "Random" and ({ "Melee", "Blox Fruit", "Sword", "Gun" })[math.random(1, 4)] or tbl14["Choose Equip "])

							for _, v54 in next, tbl14["Skill  "], nil do
								if tbl18:IsSkillAvailable(v54) then
									tbl18:SendKeyPress(v54)
								end
							end

							if not (not tbl14["Auto Trial"] or not v53.Parent or v53.Health.Value <= 0) then
								continue
							end
							break
						end
					end
				elseif str3 == "Cyborg" then
					tbl18:ExecuteTween(tbl5.Workspace.Map.CyborgTrial.Floor.CFrame * CFrame.new(0, 500, 0))
				elseif str3 == "Skypiea" and character then
					character.CFrame = tbl5.Workspace.Map.SkyTrial.Model.FinishPart.CFrame
				elseif str3 == "Human" or str3 == "Ghoul" then
					local v53 = tbl18:FindEnemy({ "Ancient Vampire", "Ancient Zombie" })

					if v53 then
						while true do
							task.wait()
							tbl18:EngageEnemy({ v53.Name })
							if not (not tbl14["Auto Trial"] or not v53.Parent or v53.Humanoid.Health <= 0) then
								continue
							end
							break
						end
					end
				end
			end)
		end)
	end)

	result2:Toggle(v52, "Auto Kill Players After Trial", "Kill players after trial", "Save", function(arg)
		tbl16:SetSave("Auto Kill Player After Trial", arg)
	end)

	tbl4.__spawn(function()
		tbl18:CreateLoop("Auto Kill Player After Trial", function()
			pcall(function()
				if not tbl14["Auto Kill Player After Trial"] then
					return
				end
				local humanoidRootPart = localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart")
				if not humanoidRootPart then
					return
				end

				for _, child in pairs(tbl5.Workspace.Characters:GetChildren()) do
					if child.Name ~= localPlayer.Name then
						local humanoid = child:FindFirstChild("Humanoid")
						local humanoidRootPart2 = child:FindFirstChild("HumanoidRootPart")

						if humanoid and humanoidRootPart2 and humanoid.Health > 0 then
							if (humanoidRootPart.Position - humanoidRootPart2.Position).Magnitude <= 250 and playerGui.Main.Timer.Visible then
								while true do
									task.wait()
									tbl18:ExecuteTween(humanoidRootPart2.CFrame * CFrame.new(0, 0, 15))
									SetAim(humanoidRootPart2.CFrame)
									tbl18:EquipToolByTip(tbl14["Choose Equip "] == "Random" and ({ "Melee", "Blox Fruit", "Sword", "Gun" })[math.random(1, 4)] or tbl14["Choose Equip "])

									for _, v53 in next, tbl14["Skill  "], nil do
										if tbl18:IsSkillAvailable(v53) then
											tbl18:SendKeyPress(v53)
										end
									end

									sethiddenproperty(localPlayer, "SimulationRadius", math.huge)
									if not (not tbl14["Auto Kill Player After Trial"] or humanoid.Health <= 0 or not child.Parent) then
										continue
									end
									break
								end
							end
						end
					end
				end
			end)
		end)
	end)

	local Raid = v13:AddSection("Raid")

	result2:Dropdown(Raid, "Select Raid", "Choose raid", false, tbl12, "Save", function(arg)
		tbl16:SetSave("Choose Chips", arg)
	end)

	result2:Toggle(Raid, "Auto Buy Chips", "Buy raid chips", "Save", function(arg)
		tbl16:SetSave("Auto Buy Chips", arg)
	end)

	tbl4.__spawn(function()
		tbl18:CreateLoop("Auto Buy Chips", function()
			if not tbl18:HasTool("Special Microchip") then
				if tbl14["Choose Chips"] == "Rumble" then
					tbl18:FireRemote("ThunderGodTalk", true)
					tbl18:FireRemote("ThunderGodTalk")
				else
					tbl18:FireRemote("RaidsNpc", "Select", tbl14["Choose Chips"])
				end
			end
		end)
	end)

	result2:Toggle(Raid, "Auto Raid", "Complete raids automatically", "Save", function(arg)
		tbl16:SetSave("Auto Raid", arg)
		tbl18:StopTween(arg)
	end)

	tbl4.__spawn(function()
		tbl18:CreateLoop("Auto Raid", function()
			local flag

			if not playerGui.Main.TopHUDList.RaidTimer.Visible then
				flag = false

				if tbl8[2] then
					if not tbl6.WorldOrigin:FindFirstChild("Island 1") then
						if tbl18:HasTool("Special Microchip") then
							local main = tbl5.Workspace.Map.CircleIsland.RaidSummon2.Button:FindFirstChild("Main")

							if main then
								fireclickdetector(main.ClickDetector)
							else
								tbl18:ExecuteTween(tbl5.Workspace.Map.CircleIsland.RaidSummon2:GetPivot())
							end
						end

						while true do
							task.wait()
							if not (tbl6.WorldOrigin:FindFirstChild("Island 1") or not tbl14["Auto Raid"] or v9.Unloaded) then
								continue
							end
							break
						end
					end
				elseif tbl8[3] then
					if not tbl6.WorldOrigin:FindFirstChild("Island 1") then
						if tbl18:HasTool("Special Microchip") then
							local main = tbl5.Workspace.Map["Boat Castle"].RaidSummon2.Button:FindFirstChild("Main")

							if main then
								fireclickdetector(main.ClickDetector)
							else
								tbl18:ExecuteTween(tbl5.Workspace.Map["Boat Castle"].RaidSummon2:GetPivot())
							end
						end

						while true do
							task.wait()
							if not (tbl6.WorldOrigin:FindFirstChild("Island 1") or not tbl14["Auto Raid"] or v9.Unloaded) then
								continue
							end
							break
						end
					end
				end
			else
				flag = true

				tbl6.WorldOrigin.Locations.ChildAdded:Connect(function(child)
					if not child:IsA("Part") then
						return
					end

					if not child.Name:match("^Island %d+$") then
						return
					end
					local v53 = tbl6.WorldOrigin.Locations:FindFirstChild(child.Name)

					if v53 then
						tbl18:ExecuteTween(v53.CFrame * CFrame.new(4, 40, 10))
					end
				end)
			end

			local n6 = 3000

			tbl4.__spawn(function()
				while flag do
					for _, child in pairs(tbl6.Enemies:GetChildren()) do
						if child and child.PrimaryPart then
							local magnitude = (child.PrimaryPart.Position - localPlayer.Character.PrimaryPart.Position).Magnitude

							if magnitude < n6 then
								n6 = magnitude
								tbl18:EngageEnemy({ child.Name })
							end
						end
					end

					task.wait()
				end
			end)

			pcall(function()
				tbl18:FireRemote("Awakener", "Check")
				tbl18:FireRemote("Awakener", "Awaken")
			end)
		end)
	end)

	local esp = v17:AddSection("ESP")

	result2:Toggle(esp, "ESP Player", "Show player locations", "Save", function(arg)
		tbl16:SetSave("ESP Player", arg)

		tbl4.__spawn(function()
			while tbl14["ESP Player"] do
				task.wait(1)

				for _, player in pairs(tbl5.Players:GetPlayers()) do
					if player.Name ~= localPlayer.Name and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
						tbl18:CreateESP(player.Character.HumanoidRootPart, Color3.fromRGB(0, 230, 0))
					end
				end
			end

			for _, player in pairs(tbl5.Players:GetPlayers()) do
				if player.Name ~= localPlayer.Name and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
					tbl18:RemoveESP(player.Character.HumanoidRootPart)
				end
			end
		end)
	end)

	result2:Toggle(esp, "ESP Chest", "Show chest locations", "Save", function(arg)
		tbl16:SetSave("ESP Chest", arg)

		tbl4.__spawn(function()
			while tbl14["ESP Chest"] do
				task.wait(1)

				for _, v53 in ipairs(tbl5.CollectionService:GetTagged("_ChestTagged")) do
					if not v53:GetAttribute("IsDisabled") then
						tbl18:CreateESP(v53, Color3.fromRGB(237, 233, 9))
					end
				end
			end

			for _, v53 in ipairs(tbl5.CollectionService:GetTagged("_ChestTagged")) do
				if not v53:GetAttribute("IsDisabled") then
					tbl18:RemoveESP(v53)
				end
			end
		end)
	end)

	result2:Toggle(esp, "ESP Berry", "Show berry locations", "Save", function(arg)
		tbl16:SetSave("ESP Berry", arg)

		tbl4.__spawn(function()
			while tbl14["ESP Berry"] do
				task.wait(1)

				for _, descendant in ipairs(tbl5.Workspace.Map:GetDescendants()) do
					if descendant.Name == "Berries" then
						for i = 1, 8 do
							if descendant:GetAttribute("_BerryCFrame" .. i) then
								tbl18:CreateESP(descendant.Parent, Color3.fromRGB(237, 233, 9))
							end
						end
					end
				end
			end

			for _, descendant in ipairs(tbl5.Workspace.Map:GetDescendants()) do
				if descendant.Name == "Berries" then
					for i = 1, 8 do
						if descendant:GetAttribute("_BerryCFrame" .. i) then
							tbl18:RemoveESP(descendant.Parent)
						end
					end
				end
			end
		end)
	end)

	result2:Toggle(esp, "ESP Flower", "Show flower locations", "Save", function(arg)
		tbl16:SetSave("ESP Flower", arg)

		tbl4.__spawn(function()
			while tbl14["ESP Flower"] do
				task.wait(1)

				for _, child in pairs(tbl5.Workspace:GetChildren()) do
					if child and child:IsA("BasePart") and string.find(child.Name, "Flower") then
						tbl18:CreateESP(child, child.Color)
					end
				end
			end

			for _, child in pairs(tbl5.Workspace:GetChildren()) do
				if child and child:IsA("BasePart") and string.find(child.Name, "Flower") then
					tbl18:RemoveESP(child)
				end
			end
		end)
	end)

	result2:Toggle(esp, "ESP Devil Fruit", "Show fruit locations", "Save", function(arg)
		tbl16:SetSave("ESP Devil Fruit", arg)

		tbl4.__spawn(function()
			while tbl14["ESP Devil Fruit"] do
				task.wait(1)

				for _, child in pairs(tbl5.Workspace:GetChildren()) do
					if child and child:IsA("Tool") and child:FindFirstChild("Handle") or child and string.find(child.Name, "Fruit") and child:FindFirstChild("Handle") then
						tbl18:CreateESP(child.Handle, Color3.fromRGB(247, 47, 7))
					end
				end
			end

			for _, child in pairs(tbl5.Workspace:GetChildren()) do
				if child and child:IsA("Tool") and child:FindFirstChild("Handle") or child and string.find(child.Name, "Fruit") and child:FindFirstChild("Handle") then
					tbl18:RemoveESP(child.Handle)
				end
			end
		end)
	end)

	result2:Toggle(esp, "ESP Island", "Show island locations", "Save", function(arg)
		tbl16:SetSave("ESP Island", arg)

		tbl4.__spawn(function()
			while tbl14["ESP Island"] do
				task.wait(1)
				local v53 = pairs
				local locations = tbl6.WorldOrigin:WaitForChild("Locations", 9e9)

				for _, child in v53(locations:GetChildren()) do
					if child then
						tbl18:CreateESP(child, Color3.fromRGB(0, 255, 255))
					end
				end
			end

			local v53 = pairs
			local locations = tbl6.WorldOrigin:WaitForChild("Locations", 9e9)

			for _, child in v53(locations:GetChildren()) do
				if child then
					tbl18:RemoveESP(child)
				end
			end
		end)
	end)

	result2:Toggle(esp, "ESP Mirage Island", "Show Mirage Island location", "Save", function(arg)
		tbl16:SetSave("ESP Mirage Island", arg)

		tbl4.__spawn(function()
			while tbl14["ESP Mirage Island"] do
				task.wait(1)

				for _, child in pairs(tbl6.WorldOrigin.Locations:GetChildren()) do
					if child and child.Name == "Mirage Island" then
						tbl18:CreateESP(child, child.Color)
					end
				end
			end

			for _, child in pairs(tbl6.WorldOrigin.Locations:GetChildren()) do
				if child and child.Name == "Mirage Island" then
					tbl18:RemoveESP(child)
				end
			end
		end)
	end)

	result2:Toggle(esp, "ESP Kitsune Island", "Show Kitsune Island location", "Save", function(arg)
		tbl16:SetSave("ESP Kitsune Island", arg)

		tbl4.__spawn(function()
			while tbl14["ESP Kitsune Island"] do
				task.wait(1)

				for _, child in pairs(tbl6.WorldOrigin.Locations:GetChildren()) do
					if child and child.Name == "Kitsune Island" then
						tbl18:CreateESP(child, child.Color)
					end
				end
			end

			for _, child in pairs(tbl6.WorldOrigin.Locations:GetChildren()) do
				if child and child.Name == "Kitsune Island" then
					tbl18:RemoveESP(child)
				end
			end
		end)
	end)

	result2:Toggle(v17:AddSection("Anti-Cheat Bypass"), "Anti-Flag", "Auto-rejoin every 30 minutes", false, function(arg)
		tbl16:SetSave("Anti-Flag", arg)

		tbl4.__spawn(function()
			while tbl14["Anti-Flag"] do
				task.wait(1800)
				tbl5.TeleportService:Teleport(game.PlaceId, localPlayer)
			end
		end)
	end)

	local Team = v17:AddSection("Team")

	result2:Button(Team, "Join Pirates", "Join Pirates team", function()
		tbl6.CommF_:InvokeServer("SetTeam", "Pirates")
	end)

	result2:Button(Team, "Join Marines", "Join Marines team", function()
		tbl6.CommF_:InvokeServer("SetTeam", "Marines")
	end)

	local v53 = v17:AddSection("Menu UI")

	result2:Button(v53, "Fruit Shop", "Open fruit shop", function()
		require(tbl5.ReplicatedStorage.Controllers.UI.FruitShop):Open()
	end)

	result2:Button(v53, "Titles", "Open titles menu", function()
		tbl6.CommF_:InvokeServer("getTitles")
		playerGui.Main.Titles.Visible = true
	end)

	result2:Button(v53, "Haki Color", "Open haki color menu", function()
		playerGui.Main.Colors.Visible = true
	end)

	result2:Button(v17:AddSection("Redeem"), "Redeem All Codes", "Redeem all available codes", function()
		for _, v54 in ipairs(H.codes()) do
			pcall(function() tbl5.ReplicatedStorage.Remotes.Redeem:InvokeServer(v54) end)
		end
	end)

	result2:Toggle(v17:AddSection("Water"), "Walk On Water", "Enable walking on water", true, function(arg)
		tbl16:SetSave("Walk On Water", arg)

		tbl4.__spawn(function()
			local connection = nil

			connection = tbl5.RunService.Heartbeat:Connect(function()
				if v9.Unloaded then
					connection:Disconnect()
					return
				end
				local waterBasePlane = tbl5.Workspace.Map:WaitForChild("WaterBase-Plane")

				if waterBasePlane then
					waterBasePlane.Size = tbl14["Walk On Water"] and Vector3.new(1000, 113, 1000) or Vector3.new(1000, 80, 1000)
				end
			end)
		end)
	end)

	local v54 = v17:AddSection("Remove Effects")

	result2:Toggle(v54, "Remove Damage Numbers", "Hide damage numbers", "Save", function(arg)
		tbl16:SetSave("Remove Damage", arg)
	end)

	tbl4.__spawn(function()
		tbl18:CreateLoop("Remove Damage", function()
			while true do
				task.wait()
				tbl5.ReplicatedStorage.Assets.GUI.DamageCounter.Enabled = false
				if not (not tbl14["Remove Damage"] or v9.Unloaded) then
					continue
				end
				break
			end

			tbl5.ReplicatedStorage.Assets.GUI.DamageCounter.Enabled = true
		end)
	end)

	result2:Toggle(v54, "Remove Notifications", "Hide notifications", "Save", function(arg)
		tbl16:SetSave("Remove Notifications", arg)
	end)

	tbl4.__spawn(function()
		tbl18:CreateLoop("Remove Notifications", function()
			while true do
				task.wait()
				localPlayer.PlayerGui.Notifications.Enabled = false
				if not (not tbl14["Remove Notifications"] or v9.Unloaded) then
					continue
				end
				break
			end

			localPlayer.PlayerGui.Notifications.Enabled = true
		end)
	end)

	local Automations = v17:AddSection("Automations")

	result2:Toggle(Automations, "Auto Haki", "Auto-activate Haki", true, function(arg)
		tbl16:SetSave("Auto Haki", arg)
	end)

	tbl4.__spawn(function()
		tbl18:CreateLoop("Auto Haki", function()
			tbl18:ActivateHaki()
		end)
	end)

	result2:Toggle(Automations, "Auto Ken", "Auto-activate Ken", "Save", function(arg)
		tbl16:SetSave("Auto Ken", arg)
	end)

	tbl4.__spawn(function()
		tbl18:CreateLoop("Auto Ken", function()
			tbl18:FireRemote("Ken", true)
		end)
	end)

	result2:Button(v18:AddSection("Reset Config"), "Reset Script Config", "Delete all saved configuration", function()
		pcall(function()
			if isfile and isfile(S.savePath) and delfile then delfile(S.savePath) end
		end)
		table.clear(tbl14)
		FacilityLib:SetNotification({ "Facility", "Config", "Saved state cleared.", 4 })
	end)

end

do
	local ok, err = pcall(SpeedHub)
	if not ok then
		warn("[Facility] Blox Fruits load error: " .. tostring(err))
		task.delay(1, function() pcall(function() Library:Error("Facility", "Load error: " .. tostring(err), 15) end) end)
	end
end
local function KaitunFull()
	local Config = getgenv().Configs

	local LogCache = {}
	local function LogChange(key, message)
		if LogCache[key] ~= message then
			LogCache[key] = message
			print(message)
		end
	end

	print("waiting for game...")
	repeat task.wait() until game:IsLoaded() and game.Players.LocalPlayer
	print("game loaded")

	local TweenService = cloneref(game:GetService("TweenService"))
	local ReplicatedStorage = cloneref(game:GetService("ReplicatedStorage"))
	local TeleportService = cloneref(game:GetService("TeleportService"))
	local Players = cloneref(game:GetService("Players"))
	local LocalPlayer = Players.LocalPlayer
	local RunService = game:GetService("RunService")
	local Lighting = game:GetService("Lighting")
	local CollectionService = game:GetService("CollectionService")
	local HttpService = game:GetService("HttpService")
	local CoreGui = cloneref(game:GetService("CoreGui"))
	local VirtualInputManager = game:GetService("VirtualInputManager")
	local CommF_ = ReplicatedStorage.Remotes.CommF_
	local CommE = ReplicatedStorage.Remotes.CommE
	local MaxLevel = (workspace:GetAttribute("LEVEL_CAP") or 2800)
	CoreGui.RobloxPromptGui.promptOverlay.ChildAdded:Connect(function(v)
		if v.Name == "ErrorPrompt" and v:FindFirstChild("MessageArea") and v.MessageArea:FindFirstChild("ErrorFrame") then
			ReplicatedStorage.__ServerBrowser:InvokeServer("teleport", game.JobId)
		end
	end)
	game.NetworkClient.ChildRemoved:Connect(function()
		ReplicatedStorage.__ServerBrowser:InvokeServer("teleport", game.JobId)
		task.wait(5)
		TeleportService:Teleport(game.PlaceId)
	end)

	TeleportService.TeleportInitFailed:Connect(function(player, result, err)
		if result ~= Enum.TeleportResult.GameFull then
			ReplicatedStorage.__ServerBrowser:InvokeServer("teleport", game.JobId)
		end
	end)

	if Config.WhiteScreen then
		RunService:Set3dRenderingEnabled(false)
		print("white screen applied")
	end
	if Config.FixLag then
		pcall(function()
			for _,v in pairs(Lighting:GetChildren()) do
				if v:IsA("PostEffect") then
					v.Enabled = false
				end
			end
			local function optimize(obj)
				if obj:IsA("BasePart") then
					obj.Material = Enum.Material.Plastic
					obj.Reflectance = 0
				elseif obj:IsA("Decal") or obj:IsA("Texture") then
					obj:Destroy()
				elseif obj:IsA("ParticleEmitter") or obj:IsA("Trail") then
					obj.Enabled = false
				elseif obj:IsA("Explosion") then
					obj.BlastPressure = 0
					obj.BlastRadius = 0
				end
			end
			for _,v in pairs(game:GetDescendants()) do
				optimize(v)
			end
			game.DescendantAdded:Connect(optimize)
			Lighting.GlobalShadows = false
			Lighting.FogEnd = 9e9
			Lighting.Brightness = 0
			Lighting.EnvironmentDiffuseScale = 0
			Lighting.EnvironmentSpecularScale = 0
			settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
			for _, v in workspace.Map:GetDescendants() do
				if v:IsA('BasePart') and v.Transparency ~= 1 then
					v.Transparency = 1
				end
			end
		end)
		print("lag fix applied")
	end

	if Config.FPS then
		setfpscap(Config.FPS)
		print("fps cap set to " .. Config.FPS)
	end

	print("waiting for team...")

	if not LocalPlayer.Team then
		repeat task.wait()
			CommF_:InvokeServer("SetTeam", Configs.Team)
		until LocalPlayer.Team
	end
	print("waiting for character...")
	repeat task.wait(0.1) until LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid") and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
	print("character ready")

	print("team selected")

	task.wait(2.5)

	pcall(function() require(ReplicatedStorage.Util.CameraShaker):Stop() end)

	print("camera shaker disabled")

	print("initializing...")

	local Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
	LocalPlayer.CharacterAdded:Connect(function(v)
		Character = v
		print("character respawned")
	end)

	pcall(function()
		LocalPlayer.PlayerGui.ChildAdded:Connect(function(child)
			if child.Name == "SpinnerWindow" then
				child:Destroy()
			end
		end)
		workspace.ChildAdded:Connect(function(df)
			if df:IsA('Tool') then
				df:Destroy()
			end
		end)
	end)

	task.spawn(function()
		while true do
			local hrp = Character:FindFirstChild("HumanoidRootPart")
			if hrp and not hrp:FindFirstChild("fixvelo") then
				local bv = Instance.new("BodyVelocity")
				bv.Name = "fixvelo"
				bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
				bv.Velocity = Vector3.new(0, 0, 0)
				bv.P = 1000
				bv.Parent = hrp
			end
			task.wait(0.5)
		end
	end)

	RunService.Stepped:Connect(function()
		if Character ~= nil then
			for _, child in Character:GetDescendants() do
				if child:IsA("BasePart") and child.CanCollide == true then
					child.CanCollide = false
				end
			end
		end
	end)

	local ScreenGui = Instance.new("ScreenGui")
	ScreenGui.Name = "KaitunUIKrita"
	ScreenGui.ResetOnSpawn = false
	ScreenGui.IgnoreGuiInset = true
	ScreenGui.Parent = LocalPlayer.PlayerGui
	local frame = Instance.new("Frame", ScreenGui)
	frame.Size = UDim2.new(0, 560, 0, 130)
	frame.Position = UDim2.new(0.5, -280, 0, 60)
	frame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	frame.BackgroundTransparency = 0.05
	local corner = Instance.new("UICorner", frame)
	corner.CornerRadius = UDim.new(0, 12)
	local gradient = Instance.new("UIGradient", frame)
	gradient.Color = ColorSequence.new({
	    ColorSequenceKeypoint.new(0, Color3.fromRGB(172, 224, 112)),
	    ColorSequenceKeypoint.new(0.5, Color3.fromRGB(80, 199, 164)),
	    ColorSequenceKeypoint.new(1, Color3.fromRGB(72, 133, 245))
	})
	gradient.Rotation = 0
	local edge = Instance.new("UIStroke", frame)
	edge.Color = Color3.fromRGB(196, 196, 196)
	edge.Thickness = 3
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	local layout = Instance.new("UIListLayout", frame)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	local title = Instance.new("TextLabel", frame)
	title.Size = UDim2.new(1, -20, 0, 35)
	title.BackgroundTransparency = 1
	title.Text = "facility kaitun | initializing"
	title.Font = Enum.Font.GothamBold
	title.TextSize = 24
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.LayoutOrder = 1
	local timeLabel = Instance.new("TextLabel", frame)
	timeLabel.Size = UDim2.new(1, -20, 0, 30)
	timeLabel.BackgroundTransparency = 1
	timeLabel.Text = "00:00:00"
	timeLabel.Font = Enum.Font.GothamSemibold
	timeLabel.TextSize = 18
	timeLabel.TextColor3 = Color3.fromRGB(226, 246, 255)
	timeLabel.LayoutOrder = 3
	function SetStatus(text)
	    local status = string.lower(tostring(text))
	    if title.Text ~= status then
	        print("ui: " .. status)
	    end
	    title.Text = status
	end
	task.spawn(function()
	    while task.wait(1) do
	        local t = os.date("*t")
	        timeLabel.Text = string.format("%02d:%02d:%02d  |  %s, %s %d, %d", t.hour, t.min, t.sec, os.date("%A"), os.date("%B"), t.day, t.year)
	    end
	end)
	print("ui initialized")

	pcall(function()
	    assert(getrawmetatable)
	    local grm = getrawmetatable(game)
	    setreadonly(grm, false)
	    local old = grm.__namecall
	    grm.__namecall = newcclosure(function(self, ...)
	        local args = {...}
	        local name = tostring(args[1])
	        for _, remote in ipairs({"TeleportDetect", "CHECKER_1", "CHECKER", "GUI_CHECK", "OneMoreTime", "checkingSPEED", "BANREMOTE", "PERMAIDBAN", "KICKREMOTE", "BR_KICKPC", "BR_KICKMOBILE"}) do
	            if name == remote then
	                return
	            end
	        end
	        return old(self, ...)
	    end)
	end)

	print("anti anticheat initialized")

	local function EquipTool(v)
		Character.Humanoid:EquipTool(LocalPlayer.Backpack:FindFirstChild(v))
	end

	local function EquipWeapon(type)
		if not type then
			type = "Melee"
		end
		for _, v in LocalPlayer.Backpack:GetChildren() do
			if v.ToolTip == type then
				if not Character:FindFirstChild("HasBuso") then
					CommF_:InvokeServer("Buso")
				end
				Character.Humanoid:EquipTool(v)
				return
			end
		end
	end

	local function HasItem(name)
		if not Character then
			return
		end
		return Character:FindFirstChild(name) or LocalPlayer.Backpack:FindFirstChild(name)
	end

	local function CheckItem(Name)
		local data = IRS:GetItems(KEYS.QUANTITY)
		for _, v in data do
			local item = MATCH(v.ItemId)._ok
			local c = item.Display.Category
			if (c == "Sword" or c == "Gun" or c == "Accessory") and item.Index.StorageKey == Name then
				return true
			end
		end
		return false
	end

	local tw, conn
	local function StopTween()
		if tw then
	        LogChange("tween_stop", "tween: stopped")
			tw:Cancel()
			tw = nil
		end
		if conn then
			conn:Disconnect()
			conn = nil
		end
		local r = Character and Character:FindFirstChild("Root")
		if r then
			r:Destroy()
		end
	end

	local World = {}
	World.Sea1 = function()
		return require(ReplicatedStorage.Util.Realm).getCurrentSeaAsync() == "Sea1"
	end
	World.Sea2 = function()
		return require(ReplicatedStorage.Util.Realm).getCurrentSeaAsync() == "Sea2"
	end
	World.Sea3 = function()
		return require(ReplicatedStorage.Util.Realm).getCurrentSeaAsync() == "Sea3"
	end

	local LastTravel = 0

	local function RunTween(v, high)
	    while not Character or not Character.PrimaryPart or not Character:FindFirstChild("Humanoid") do
	        LogChange("tween_wait", "tween: waiting for character")
	        task.wait()
	    end
	    local rootPart = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
	    if not rootPart then
	        LogChange("tween_root", "tween: root missing")
	        return
	    end
	    if typeof(v) == "CFrame" then
	        v = v.Position
	    end
	    Character.Humanoid.Sit = false
	    local targetCFrame = typeof(v) == "Vector3" and CFrame.new(v) or v
	    local pos = targetCFrame.Position + Vector3.new(0, high or 0, 0)
	    local rot = rootPart.CFrame - rootPart.Position
	    local finalCFrame = CFrame.new(pos) * rot
	    local distance = (rootPart.Position - finalCFrame.Position).Magnitude
	    local speed
	    if distance < 250 then
	        speed = 285
	    elseif distance < 500 then
	        speed = 260
	    elseif distance < 1000 then
	        speed = 240
	    else
	        speed = 200
	    end
	    local travelTime = distance / speed
	    if distance >= 1000 then
	        LogChange("long_tween", "tween: long travel")
	    end
	    tw = TweenService:Create(rootPart, TweenInfo.new(travelTime, Enum.EasingStyle.Linear, Enum.EasingDirection.Out), { CFrame = finalCFrame })
	    tw:Play()
	    return tw
	end
	local function BreakClouds()
		if workspace.Map:FindFirstChild("Sky") then
			for _, v in workspace.Map.Sky:GetChildren() do
				if v:IsA("MeshPart") and v.Name == "cloud" and (Vector3.new(-4208.15869140625, 1089.8868408203125, -373.052490234375) - v.Position).Magnitude < 50 and not v:GetAttribute("Broken") then
					EquipWeapon()
	                Character.HumanoidRootPart:PivotTo(v.CFrame)
					task.wait(0.25)
					ReplicatedStorage.Modules.Net["RE/RegisterAttack"]:FireServer(0.4)
					ReplicatedStorage.Modules.Net["RE/RegisterHit"]:FireServer(v)
	                task.wait(0.5)
				end
			end
		end
	end
	local function SmartTween(t)
	    if World.Sea3() then
	        if not CheckItem("Valkyrie Helm") then
	            LogChange("entrance_block", "travel: missing valkyrie helm")
	            return
	        end
	    end
	    if typeof(t) == "CFrame" then
	        t = t.Position
	    end
	    while not Character or not Character.PrimaryPart or not Character:FindFirstChild("Humanoid") do
	        task.wait()
	    end
	    local _is
	    if World.Sea3() then
	        _is = {
				{ Vector3.new(-5027.0302734375, 316.5475769042969, -3206.70361328125), Vector3.new(5650.94775390625, 1017.2747802734375, -350.37918090820312) },
	            { Vector3.new(5650.94775390625, 1017.2747802734375, -350.37918090820312), Vector3.new(-5027.0302734375, 316.5475769042969, -3206.70361328125) },
	            { Vector3.new(-12463.6025390625, 378.32705688476562, -7566.0830078125), Vector3.new(-5060.41162109375, 316.5475769042969, -3193.224853515625) },
	            { Vector3.new(-5060.41162109375, 318.50201416015625, -3193.224853515625), Vector3.new(-12463.6025390625, 376.3725280761719, -7566.0830078125) },
	        }
	    elseif World.Sea2() then
	        _is = {
	            { Vector3.new(-390, 332, 673), Vector3.new(-390, 332, 673) },
	            { Vector3.new(2285, 15, 905), Vector3.new(2285, 15, 905) },
	            { Vector3.new(923, 126, 32852), Vector3.new(923, 126, 32852) },
	            { Vector3.new(-6509, 83, -133), Vector3.new(-6509, 83, -133) },
	        }
	    elseif World.Sea1() then
	        _is = {
				{ Vector3.new(61163.8515625, 11.6796875, 1819.7841796875), Vector3.new(4050.31103515625, -1.6880035400390625, -1814.1240234375) },
	            { Vector3.new(3864.8515625, 6.6796875, -1926.7841796875), Vector3.new(61170.046875, -2, 1952.833984375) },
	            { Vector3.new(-4166.60986328125, 1093.697998046875, -347.16226196289062), Vector3.new(-6020.27734375, 5469.15625, 2209.776123046875) },
	        }
	    else
	        return
	    end

	    local min = nil
	    local pos = 1
	    for i, v in ipairs(_is) do
	        local distanceToTarget = (t - v[1]).Magnitude
	        if min == nil then
	            min = distanceToTarget
	        else
	            if distanceToTarget < min then
	                min = distanceToTarget
	                pos = i
	            end
	        end
	    end
	    local dist = LocalPlayer:DistanceFromCharacter(t)
		local disttotp = LocalPlayer:DistanceFromCharacter(_is[pos][2])
	    if (min + disttotp) < dist and (tick() - LastTravel) >= 1 then
	        LastTravel = tick()
	        print("travel: using entrance")
	        tw = RunTween(_is[pos][2])
	        if tw then
	            tw.Completed:Wait()
	        end
			task.wait(0.25)
			print("travel: requesting entrance")
			task.wait(0.25)
			if not CollectionService:HasTag(LocalPlayer, "Teleporting") then
				CommF_:InvokeServer("requestEntrance", _is[pos][1])
			end
			repeat task.wait() until (LocalPlayer:DistanceFromCharacter(_is[pos][1]) < LocalPlayer:DistanceFromCharacter(_is[pos][2]))
	        print("travel: entrance reached")
	        task.wait(0.25)
	    end
	end
	local function Tween(v, speed, high)
	    while not Character or not Character.PrimaryPart or not Character:FindFirstChild("Humanoid") do
	        task.wait()
	    end
	    SmartTween(v)
	    return RunTween(v, high)
	end

	local function WaitForAliveCharacter()
	    while true do
	        local character = LocalPlayer.Character
	        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	        local root = character and character:FindFirstChild("HumanoidRootPart")
	        if character and humanoid and humanoid.Health > 0 and root then
	            return character, humanoid, root
	        end
	        task.wait(0.1)
	    end
	end

	local function TweenWithRespawnRetry(target, speed, high)
	    while true do
	        local currentCharacter = LocalPlayer.Character
	        local currentHumanoid = currentCharacter and currentCharacter:FindFirstChildOfClass("Humanoid")
	        local currentRoot = currentCharacter and currentCharacter:FindFirstChild("HumanoidRootPart")
	        if not currentCharacter or not currentHumanoid or currentHumanoid.Health <= 0 or not currentRoot then
	            LogChange("respawn_wait", "tween: waiting for respawn")
	        end
	        local startCharacter, humanoid, root = WaitForAliveCharacter()
	        LogChange("respawn_wait", "tween: character ready")
	        local died = false
	        local activeTween = nil

	        local diedConnection = humanoid.Died:Connect(function()
	            died = true
	            if activeTween then
	                pcall(function()
	                    activeTween:Cancel()
	                end)
	            end
	        end)

	        local ok, tweenOrError = pcall(function()
	            return Tween(target, speed, high)
	        end)

	        if ok and tweenOrError then
	            activeTween = tweenOrError

	            local finished = false
	            local playbackState = nil
	            local completedConnection = activeTween.Completed:Connect(function(state)
	                playbackState = state
	                finished = true
	            end)

	            local currentState = activeTween.PlaybackState
	            if currentState == Enum.PlaybackState.Completed or currentState == Enum.PlaybackState.Cancelled then
	                playbackState = currentState
	                finished = true
	            end

	            if died then
	                pcall(function()
	                    activeTween:Cancel()
	                end)
	            end

	            while not finished do
	                task.wait(0.05)
	            end

	            completedConnection:Disconnect()
	            diedConnection:Disconnect()

	            local currentCharacter = LocalPlayer.Character
	            local stillSameCharacter = currentCharacter == startCharacter
	                and humanoid.Parent ~= nil
	                and humanoid.Health > 0
	                and root.Parent ~= nil
	                and not died

	            if not stillSameCharacter then
	                print("tween: retry after respawn")
	                task.wait(0.1)
	            elseif playbackState == Enum.PlaybackState.Completed then
	                LogChange("tween_result", "tween: complete")
	                return true
	            else
	                LogChange("tween_result", "tween: cancelled")
	                return false
	            end
	        else
	            diedConnection:Disconnect()
	            local characterChanged = LocalPlayer.Character ~= startCharacter
	            if died or characterChanged or humanoid.Health <= 0 or not root.Parent then
	                task.wait(0.1)
	            else
	                if not ok then
	                    warn("tween retry failed: " .. tostring(tweenOrError))
	                end
	                return false
	            end
	        end
	    end
	end

	task.spawn(function()
		while true do
			pcall(function()
				local char = LocalPlayer.Character
				if char and char.PrimaryPart and char:FindFirstChildOfClass("Humanoid") and char.Humanoid.Health > 0 then
					CommE:FireServer("Dodge", nil, 30, true, workspace:GetServerTimeNow())
				end
			end)
			task.wait(2.5)
		end
	end)

	task.spawn(function()
		while task.wait(0.5) do
			for _, v in LocalPlayer.PlayerGui:GetDescendants() do
				if v:IsA("TextLabel") and v.Text:find("Confront the prisoner") then
					local BonusMomentsRemoteFunction = ReplicatedStorage.Remotes.BonusMomentsRemoteFunction
					BonusMomentsRemoteFunction:InvokeServer("Escape from Alcatraz", "Provoke", "Puncher")
					BonusMomentsRemoteFunction:InvokeServer("Escape from Alcatraz", "Provoke", "Digger")
					BonusMomentsRemoteFunction:InvokeServer("Escape from Alcatraz", "Provoke", "Raft")
					local success, controllerModule = pcall(require,  ReplicatedStorage.Controllers.BonusMomentsController)
					if success and type(controllerModule) == "table" and rawget(controllerModule, "GetLoadedMoments") then
						local loadedMoments = controllerModule:GetLoadedMoments()
						for momentName, momentInstance in pairs(loadedMoments) do
							if type(momentInstance) == "table" then
								if type(momentInstance.Trove and momentInstance.Trove.Clean) == "function" then
									pcall(function() momentInstance.Trove:Clean() end)
								end
								if type(momentInstance._MainMaid and momentInstance._MainMaid.DoCleaning) == "function" then
									pcall(function() momentInstance._MainMaid:DoCleaning() end)
								end
								if type(momentInstance._Maid and momentInstance._Maid.DoCleaning) == "function" then
									pcall(function() momentInstance._Maid:DoCleaning() end)
								end
							end
							loadedMoments[momentName] = nil
						end
					end
				end
			end
		end
	end)

	local function TeleportSeabeast(c5)
		local a = Vector3.new(0, c5:FindFirstChild("HumanoidRootPart").Position.Y, 0)
		local ab = Vector3.new(0, workspace.Map["WaterBase-Plane"].Position.Y, 0)
		if (a - ab).Magnitude <= 175 then
			Tween(c5.HumanoidRootPart.CFrame * CFrame.new(0, 300, 50), 280).Completed:Wait()
		else
			Tween(CFrame.new(c5.HumanoidRootPart.Position.X,workspace.Map["WaterBase-Plane"].Position.Y + 200,c5.HumanoidRootPart.Position.Z),280).Completed:Wait()
		end
	end

	local function CheckPirateBoat()
		for _, v in workspace.Enemies:GetChildren() do
			if table.find({"PirateBasic","PirateBrigade"}, v.Name) and v:FindFirstChild("Health") and v.Health.Value > 0 then
				return v
			end
		end
	end

	local function CheckSeabeast()
		if not workspace:FindFirstChild("SeaBeasts") then
			return
		end
		for _, v in workspace.SeaBeasts:GetChildren() do
			if v.Name == "SeaBeast1" then
				if v.Health.Value >= 34500 then
					return v
				end
			end
		end
		return false
	end

	local function CheckBoat()
		for _, v in workspace.Boats:GetChildren() do
			if v:IsA("Model") then
				if v:FindFirstChild("Owner") and tostring(v.Owner.Value) == LocalPlayer.Name and v.Humanoid.Value > 0 and v:FindFirstChild("Engine") then
					if LocalPlayer:DistanceFromCharacter(v.Engine.CFrame.Position) <= 1750 then
						return v
					end
				end
			end
		end
		return false
	end

	local function GetElite()
		for _, v in {"Diablo", "Deandre", "Urban", "Tyrant of the Skies"} do
			local e = ReplicatedStorage:FindFirstChild(v) or workspace.Enemies:FindFirstChild(v)
			if e and e:FindFirstChild("Humanoid") then
				if e.Humanoid.Health > 0 then
					return e
				end
			end
		end
		return false
	end

	local r, id
	for _, v in {ReplicatedStorage.Util, ReplicatedStorage.Common, ReplicatedStorage.Remotes, ReplicatedStorage.Assets, ReplicatedStorage.FX} do
		for _, n in v:GetChildren() do
			if n:IsA("RemoteEvent") and n:GetAttribute("Id") then
				r, id = n, n:GetAttribute("Id")
			end
		end
		v.ChildAdded:Connect(function(n)
			if n:IsA("RemoteEvent") and n:GetAttribute("Id") then
				r, id = n, n:GetAttribute("Id")
			end
		end)
	end

	local function Attack()
		local char = Character
		local parts = {}
		for _, v in workspace.Enemies:GetChildren() do
			local hrp = v:FindFirstChild("HumanoidRootPart")
			local hum = v:FindFirstChild("Humanoid")
			if v ~= char and hrp and hum and hum.Health > 0 and LocalPlayer:DistanceFromCharacter(hrp.Position) <= 35 then
				for _, _v in v:GetChildren() do
					if _v:IsA("BasePart") and LocalPlayer:DistanceFromCharacter(hrp.Position) <= 35 then
						parts[#parts + 1] = { v, _v }
					end
				end
			end
		end
		if #parts == 0 then
			return
		end
		local tool = char:FindFirstChildOfClass("Tool")
		if #parts > 0 and tool and (tool.ToolTip == "Melee" or tool.ToolTip == "Sword") then
			if (tool.Name == "Black Leg" and tool.Level.Value >= 150) or (tool.Name == "Death Step" and tool.Level.Value >= 400) then
				if LocalPlayer.PlayerGui.Main.Skills:FindFirstChild(tool.Name) and LocalPlayer.PlayerGui.Main.Skills[tool.Name].V.Cooldown.AbsoluteSize.X <= 0 then
					VirtualInputManager:SendKeyEvent(true, "V", false, game)
					VirtualInputManager:SendKeyEvent(false, "V", false, game)
					task.wait(1.5)
				end
			end
			ReplicatedStorage.Modules.Net["RE/RegisterAttack"]:FireServer()
			local head = parts[1][1]:FindFirstChild("Head")
			ReplicatedStorage.Modules.Net["RE/RegisterHit"]:FireServer( head, parts, {}, tostring(LocalPlayer.UserId):sub(2, 4) .. tostring(coroutine.running()):sub(11, 15) )
			cloneref(r):FireServer(
				string.gsub("RE/RegisterHit", ".", function(c)
					return string.char(bit32.bxor(string.byte(c), math.floor(workspace:GetServerTimeNow() / 10 % 10) + 1))
				end),
				bit32.bxor(id + 909090, ReplicatedStorage.Modules.Net.seed:InvokeServer() * 2),
				head,
				parts
			)
		end
	end

	local function GetNearestChests()
		local nearest, minDist = nil, 99999
		for _, v in workspace:GetDescendants() do
			if v.Name == "Chest1" or v.Name == "Chest2" or v.Name == "Chest3" then
				if v:IsA("Part") and v.CanTouch then
					local dist = LocalPlayer:DistanceFromCharacter(v:GetPivot().Position)
					if dist < minDist then
						minDist = dist
						nearest = v
					end
				end
			end
		end
		return nearest
	end

	local function IfTableHaveIndex(k)
		for _ in k do
			return true
		end
	end
	LastServersDataPulled = 0
	CachedServers = {}
	local function GetServers()
		if LastServersDataPulled then
			if os.time() - LastServersDataPulled < 60 then
				return CachedServers
			end
		end
		for i = 1, 100, 1 do
			local W = ReplicatedStorage:WaitForChild("__ServerBrowser"):InvokeServer(i)
			if IfTableHaveIndex(W) then
				LastServersDataPulled = os.time()
				CachedServers = W
				return W
			end
		end
	end

	local function HopLowServer()
		for i, v in GetServers() do
			if v.Count <= 5 then
				return ReplicatedStorage.__ServerBrowser:InvokeServer("teleport", i)
			end
		end
	end

	local function CheckSafezone(p)
		if not Character then
			return
		end
		if not Character:FindFirstChild("Humanoid") then
			return
		end
		if Character.Humanoid.Health > 0 then
			for _, v in workspace["_WorldOrigin"].SafeZones:GetChildren() do
				if v:IsA("Part") then
					if p and p:FindFirstChild("PrimaryPart") and (v.Position - p.PrimaryPart.Position).magnitude <= 200 and p.Humanoid.Health / p.Humanoid.MaxHealth >= 90 / 100 then
						return true
					end
				end
			end
		end
		return false
	end

	BlacklistedPlayers = {
		LocalPlayer.Name,
	}
	local Hop

	local function GetSkyRacePlayer()
		for _, Player in Players:GetPlayers() do
			if Player and Player.Character then
				local Humanoid = Player.Character:FindFirstChild("Humanoid")
				if not table.find(BlacklistedPlayers, Player.Name) and Humanoid and Humanoid.Health > 0 then
					Hop()
					if Player.Data.Race.Value == "Skypiea" and not Player:GetAttribute("IslandRaiding") then
						if not CheckSafezone(Player) and LocalPlayer:DistanceFromCharacter(Player.Character.PrimaryPart.Position) < 12000 and Player.Character.PrimaryPart.CFrame.Y > 0 then
							table.insert(BlacklistedPlayers, Player.Name)
							return Player
						end
					end
				end
			end
		end
	end

	local function GetPlayerBoat()
		for _, boat in workspace.Boats:GetChildren() do
			if boat:IsA("Model") then
				local Owner = boat:FindFirstChild("Owner")
				local HD = boat:FindFirstChild("Humanoid")
				if Owner and HD and tostring(Owner.Value) == LocalPlayer.Name and HD.Value > 0 then
					return boat
				end
			end
		end
	end

	local function SendKey(key, hold)
		VirtualInputManager:SendKeyEvent(true, key, false, game)
		task.wait(hold)
		VirtualInputManager:SendKeyEvent(false, key, false, game)
	end

	local function GetSeabeast()
		for _, sb in workspace.SeaBeasts:GetChildren() do
			if sb.Health.Value > 30000 then
				return sb
			end
		end
	end

	task.spawn(function()
		while true do
			GetServers()
			task.wait(180)
		end
	end)

	Hop = function(k, W)
		local check_isvalid = false
		local h = GetServers()
		local X = {}
		for w, D in h do
			table.insert(X, { JobId = w, Players = D.Count, LastUpdate = D.__LastUpdate, Region = D.Region, })
		end
		for _ = 1, #X do
			while task.wait() do
				local h = math.random(1, #X)
				ServerData = X[h]
				if ServerData then
					if not k or ServerData.Players < k then
						if not W or ServerData.Region == W then
							break
						else
							check_isvalid = true
						end
					end
				end
			end
		end
		if not check_isvalid then
			ReplicatedStorage:WaitForChild("__ServerBrowser"):InvokeServer("teleport", ServerData.JobId)
		else
			local servers = {}
			local ok, req = pcall(function()
				return game:HttpGet( "https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=100&excludeFullGames=true" )
			end)
			if not ok or not req then
				return
			end
			local ok2, body = pcall(function()
				return HttpService:JSONDecode(req)
			end)
			if not ok2 or not body or not body.data then
				return
			end
			for _, v in body.data do
				if type(v) == "table" and tonumber(v.playing) and tonumber(v.maxPlayers) and v.playing < 2 and v.id ~= game.JobId then
					table.insert(servers, 1, v.id)
				end
			end
			if #servers > 0 then
				ReplicatedStorage.__ServerBrowser:InvokeServer("teleport", servers[math.random(1, #servers)])
			end
		end
	end

	local BringMob = function(v, s)
		if not Character or not Character.PrimaryPart then
			return
		end
		local targets = {}
		for _, x in workspace.Enemies:GetChildren() do
			local h = x:FindFirstChildOfClass("Humanoid")
			if x.PrimaryPart and h and h.Health > 0 and (not v or x.Name == v) and LocalPlayer:DistanceFromCharacter(x.PrimaryPart.Position) <= 180 then
				targets[#targets + 1] = x
				if #targets == 3 then
					break
				end
			end
		end
		if #targets == 0 then
			return
		end
		local t = targets[1].PrimaryPart.CFrame
		for _, x in targets do
			if isnetworkowner(x.PrimaryPart) then
				x.PrimaryPart.CFrame = t
			end
		end
	end

	local function WaitUntilNoBusy()
		pcall(function()
			task.wait(0.1)
			if Character.Busy.Value then
				repeat
					task.wait(0.1)
				until not Character.Busy.Value
			end
		end)
	end

	local function AutoSkill()
		for _, v in LocalPlayer.Backpack:GetChildren() do
			if v.ToolTip == "Melee" or v.ToolTip == "Sword" or v.ToolTip == "Blox Fruit" or v.ToolTip == "Gun" then
				Character.Humanoid:EquipTool(v)
				VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Z, false, game)
				VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Z, false, game)
				WaitUntilNoBusy()
				VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.X, false, game)
				VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.X, false, game)
				WaitUntilNoBusy()
				VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.C, false, game)
				VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.C, false, game)
				break
			end
		end
	end

	local function Seabeast()
		if not CheckSeabeast() and not CheckPirateBoat() then
			if not CheckBoat() then
				if (Vector3.new(-12.7291985, 10.3120461, 2955.1543) - Character.HumanoidRootPart.Position).Magnitude > 8 then
					Tween(CFrame.new(-12.7291985, 10.3120461, 2955.1543), 280).Completed:Wait()
					CommF_:InvokeServer("BuyBoat", "PirateBrigade")
				else
					CommF_:InvokeServer("BuyBoat", "PirateBrigade")
				end
			else
				if (CheckBoat().VehicleSeat.Position - Vector3.new(28.4108, 1.2327, 3679.99)).Magnitude > 50 then
					CheckBoat().VehicleSeat.CFrame = CFrame.new(28.4108 + 20, 1.2327 + 10, 3679.99 + 20)
				else
					if not Character.Humanoid.Sit then
						if (CheckBoat().VehicleSeat.Position - Character.HumanoidRootPart.Position).Magnitude > 50 then
							Tween(CheckBoat().VehicleSeat.CFrame, 280).Completed:Wait()
						else
							Character.HumanoidRootPart.CFrame = CheckBoat().VehicleSeat.CFrame
						end
					end
				end
			end
		elseif CheckPirateBoat() then
			local v = CheckPirateBoat()
			repeat
				task.wait()
				Tween(v.Engine.CFrame * CFrame.new(0, -20, 0), 250).Completed:Wait()
				AutoSkill()
			until not v or not v.Parent or v.Health.Value <= 0 or not CheckPirateBoat()
		elseif CheckSeabeast() then
			local v = CheckSeabeast()
			repeat
				task.wait()
				TeleportSeabeast(v)
				AutoSkill()
			until not v or not v.Parent or v.Health.Value <= 0 or not CheckSeabeast()
		end
	end

	local function KillMonster(_v)
	    LogChange("combat_target", "combat: target " .. string.lower(tostring(_v)))
	    SetStatus("combat | target " .. string.lower(tostring(_v)))
		while not (Character and Character:FindFirstChildOfClass("Humanoid")) do
			task.wait()
		end
		if Character.Humanoid.Health > 0 then
			for _, v2 in {workspace.Enemies, ReplicatedStorage} do
				for _, v in v2:GetChildren() do
					if v.Name:find(_v) and v.PrimaryPart and v:FindFirstChildOfClass("Humanoid") then
						repeat
							task.wait()
							if not v or not v.PrimaryPart or not v:FindFirstChildOfClass("Humanoid") or v.Humanoid.Health <= 0 then
								break
							end
							Tween(v.PrimaryPart.Position + Vector3.new(0, 25, 7), 350)
							if LocalPlayer:DistanceFromCharacter(v.PrimaryPart.CFrame.Position) <= 200 then
								Tween(v.PrimaryPart.Position + Vector3.new(0, 25, 7), math.huge)
								if LocalPlayer:DistanceFromCharacter(v.PrimaryPart.CFrame.Position) <= 50 then
									EquipWeapon()
									Attack()
								end
							end
						until not v
							or not v.PrimaryPart
							or not v:FindFirstChildOfClass("Humanoid")
							or v.Humanoid.Health <= 0
							or Character.Humanoid.Health <= 0
							or not Character:FindFirstChild("Humanoid")
						break
					end
				end
			end
		end
	end

	local lastTakeQuest = 0
	local QuestController, GetQuest, GetQuestData, GetQuestPosition

	GetQuestPosition = function()
	    local nearestPos = nil
	    local shortestdist = math.huge
	    for _, v in require(ReplicatedStorage.GuideModule).Data.NPCList do
	        if typeof(v) == "table" and v.Position then
	            for _, x in v do
	                if x == GetQuest()["NameQuest"] then
	                    local distance = LocalPlayer:DistanceFromCharacter(v.Position)
	                    if distance < shortestdist then
	                        shortestdist = distance
	                        nearestPos = v.Position
	                    end
	                end
	            end
	        end
	    end
	    return nearestPos
	end

	local function TakeQuest()
		if (tick() - lastTakeQuest) < 0.75 then
			return
		end
		local q = GetQuest()
	    if q and q.NameQuest then
	        LogChange("quest_target", "quest: " .. string.lower(tostring(q.NameQuest)) .. " / " .. string.lower(tostring(q.NameMonster or "unknown")))
	    else
	        LogChange("quest_target", "quest: no target")
	    end
		if q and q.NameQuest and q.ID and (not GetQuestData() or QuestController.CurrentQuestName ~= q.NameQuest) then
			local questPos = GetQuestPosition()
	        LogChange("quest_travel", questPos and "quest: traveling to npc" or "quest: npc position missing")
			if not questPos then
				LogChange("quest_travel", "quest: npc position missing, hopping server")
				Hop()
			end
			if questPos and TweenWithRespawnRetry(questPos, 350) then
				task.wait(0.25)
				if LocalPlayer:DistanceFromCharacter(questPos) <= 15 then
	                LogChange("quest_start", "quest: starting " .. string.lower(tostring(q.NameQuest)))
	                SetStatus("quest | starting " .. string.lower(tostring(q.NameQuest)))
					CommF_:InvokeServer("StartQuest", q.NameQuest, q.ID)
				end
			end
		end
		lastTakeQuest = tick()
	end

	local MobsCakePrince = {
		"Cookie Crafter",
		"Cake Guard",
		"Baking Staff",
		"Head Baker",
	}
	local CakePrinceBosses = {
		"Dough King",
		"Cake Prince",
	}
	local function GetCakePrince()
		for _, v in {workspace.Enemies, ReplicatedStorage} do
			for _, v2 in v:GetChildren() do
				if table.find(CakePrinceBosses, v2.Name) and v2:FindFirstChild("Humanoid") and v2:FindFirstChild("HumanoidRootPart") and v2.Humanoid.Health > 0 then
					return v2
				end
			end
		end
	end

	QuestController = {
		CurrentQuest = "",
		CurrentQuestName = "",
		CachedQuestData = require(ReplicatedStorage.Quests),
		QuestConnection = nil,
	}
	QuestController.Set = function(self, data)
		self.CurrentQuest = (function()
			for i, _ in data.Progress do
				return i
			end
		end)()
		self.CurrentQuestName = data.InternalQuestName
	end
	QuestController.Reset = function(self)
		self.CurrentQuest = ""
		self.CurrentQuestName = ""
	end

	QuestController.QuestConnection = ReplicatedStorage.Remotes.QuestUpdate.OnClientEvent:Connect(function(a2, a3)
		if a2 and typeof(a2) == "table" then
			QuestController:Set(a2)
			return
		end
		QuestController:Reset()
	end)

	GetQuestData = function()
		return QuestController.CurrentQuest ~= ""
	end

	local function GetLastQuest()
		local data = require(ReplicatedStorage.GuideModule).Data
		if data and data.QuestData and data.QuestData.Task then
			for i, _ in data.QuestData.Task do
				return i
			end
		end
	end

	local function GetBestQuest()
		local bestLevelReq = -1
		local bestRnq, bestTaskName, bestRidq = nil, nil, nil
		for rnq, v in QuestController.CachedQuestData do
			if table.find({ "BartiloQuest", "Trainees", "MarineQuest", "CitizenQuest", }, tostring(rnq)) then
				continue
			end
			for ridq, ct in v do
				if ct.LevelReq < 0 or LocalPlayer.Data.Level.Value < ct.LevelReq then
					continue
				end
				for O, taskValue in ct.Task do
					if taskValue > 1 and ct.LevelReq > bestLevelReq then
						bestLevelReq = ct.LevelReq
						bestRnq = rnq
						bestTaskName = tostring(O)
						bestRidq = ridq
					end
				end
			end
		end
		if not bestRnq then
			return
		end
		return bestLevelReq, bestRnq, bestTaskName, bestRidq
	end

	GetQuest = function()
		local Level = LocalPlayer.Data.Level.Value
		local msn, nq, idq
		local min = 0
		if Level >= 275 and Level < 300 then
			nq, msn, idq = "ColosseumQuest", "Togga Warrior", 1
		elseif Level >= 1450 and World.Sea2() then
			nq, msn, idq = "ForgottenQuest", "Water Fighter", 2
		elseif Level >= 700 and World.Sea1() then
			nq, msn, idq = "FountainQuest", "Galley Captain", 2
		else
			min, nq, msn, idq = GetBestQuest()
		end
		local q = {}
		if Level >= 10 and not GetQuestData() and GetLastQuest() == msn then
			for rnq, v in QuestController.CachedQuestData do
				for _, N in v do
					for x, _ in N.Task do
						if tostring(x) == msn then
							for iq, v2 in v do
								for n, ct in v2.Task do
									if n ~= msn and ct > 1 then
										q.NameMonster = v2.LevelReq <= Level and tostring(n) or msn
										q.NameQuest = v2.LevelReq <= Level and rnq or nq
										q.ID = v2.LevelReq <= Level and iq or idq
										return q
									end
								end
							end
						end
					end
				end
			end
		end
		q.NameMonster = msn
		q.NameQuest = nq
		q.ID = idq
		return q
	end

	local function TakeQuestCake(b)
		if not GetQuestData() then
	        LogChange("cake_quest", "quest: cake " .. string.lower(tostring(b)))
			local r = require(ReplicatedStorage.Quests)
			local t = {
				r.CakeQuest1,
				r.CakeQuest2,
			}
			local qn, id, lvrq
			for c, v in t do
				if typeof(v) == "table" then
					for i, v2 in v do
						if v2.Name == b then
							id = i
							qn = "CakeQuest" .. c
							lvrq = v2.LevelReq
						end
					end
				end
			end
			local p
			for _, v in require(ReplicatedStorage.GuideModule).Data.NPCList do
				if typeof(v) == "table" then
					for _, x in v do
						if x == qn then
							if LocalPlayer.Data.Level.Value >= lvrq then
								p = v.Position
							else
								return
							end
						end
					end
				end
			end

			if p and TweenWithRespawnRetry(p, 350) and LocalPlayer:DistanceFromCharacter(p) < 5 then
				task.wait(1)
				CommF_:InvokeServer("StartQuest", tostring(qn), id)
				task.wait(0.5)
			end
		end
	end

	local function TakeQuestBone(b)
		if not GetQuestData() then
	        LogChange("bone_quest", "quest: bones " .. string.lower(tostring(b)))
			local r = require(ReplicatedStorage.Quests)
			local t = { r.HauntedQuest1, r.HauntedQuest2 }
			local qn, id, lvrq
			for c, v in t do
				if typeof(v) == "table" then
					for i, v2 in v do
						if v2.Name == b then
							id = i
							qn = "HauntedQuest" .. c
							lvrq = v2.LevelReq
						end
					end
				end
			end
			local p
			for _, v in require(ReplicatedStorage.GuideModule).Data.NPCList do
				if typeof(v) == "table" then
					for _, x in v do
						if x == qn then
							if LocalPlayer.Data.Level.Value >= lvrq then
								p = v.Position
							else
								return
							end
						end
					end
				end
			end

			if p and TweenWithRespawnRetry(p, 350) and LocalPlayer:DistanceFromCharacter(p) < 5 then
				task.wait(1)
				CommF_:InvokeServer("StartQuest", tostring(qn), id)
				task.wait(0.5)
			end
		end
	end

	local function GetMonsterName()
		local _v = {}
		for _, v in workspace.Enemies:GetChildren() do
			if not table.find(_v, v.Name) and v:IsA("Model") and v.Name ~= "PirateBasic" and not v.Name:find("Brigade") and not v.Name:find("FishBoat") and v:FindFirstChildOfClass("Humanoid") and v.Humanoid.Health > 0 and v:FindFirstChild("HumanoidRootPart") then
				table.insert(_v, v.Name)
			end
		end
		for _, v in _v do
			local name = v:gsub(" %pLv%. ?%d+%p", "")
			if QuestController.CurrentQuest == name then
				return name
			end
		end
		return false
	end

	local function LoadItem(v, t)
		CommF_:InvokeServer("LoadItem", v, { t, })
	end

	local function GetMaterial(name)
		local data = IRS:GetItems(KEYS.QUANTITY)
		for _, v in data do
			local item = MATCH(v.ItemId)._ok
			if item.Display.Category == "Material" and item.Index.StorageKey == name then
				return v.Value
			end
		end
		return 0
	end

	local function BringSG(v)
		while not (Character and Character.PrimaryPart) do
			task.wait()
		end
		local targets = {}
		for _, x in workspace.Enemies:GetChildren() do
			if x:FindFirstChild("HumanoidRootPart") and x:FindFirstChild("Humanoid") and x.Humanoid.Health > 0 and (not v or x.Name == v) and (p.Position - x.HumanoidRootPart.Position).Magnitude <= math.huge then
				targets[#targets + 1] = x
				if #targets == 6 then
					break
				end
			end
		end
		if #targets == 0 then
			return
		end
		local t = targets[1].HumanoidRootPart.CFrame
		for _, x in targets do
			sethiddenproperty(x.HumanoidRootPart, "NetworkOwnershipRule", Enum.NetworkOwnership.Manual)
			x.HumanoidRootPart.CFrame = t
		end
	end

	local function GetSG()
	    LogChange("soul_guitar", "soul guitar: checking puzzle")
		local check = CommF_:InvokeServer("GuitarPuzzleProgress", "Check")
		if not check then
			if Lighting.Sky.MoonTextureId == "http://www.roblox.com/asset/?id=9709149431" and (Lighting.ClockTime > 16 or Lighting.ClockTime < 5) then
	            LogChange("soul_guitar_stage", "soul guitar: doing gravestone ritual")
	            SetStatus("soul guitar | doing gravestone ritual")
				if LocalPlayer:DistanceFromCharacter(Vector3.new(-8654, 140, 6167)) > 50 then
					Tween(CFrame.new(-8654, 140, 6167), 350).Completed:Wait()
				end
				CommF_:InvokeServer("gravestoneEvent", 2)
				CommF_:InvokeServer("gravestoneEvent", 2, true)
	        else
	            LogChange("soul_guitar_stage", "soul guitar: waiting for full moon")
	            SetStatus("soul guitar | waiting for full moon")
			end
		elseif check.Swamp == false then
	        LogChange("soul_guitar_stage", "soul guitar: clearing swamp")
	        SetStatus("soul guitar | clearing swamp")
			if (function() local b = 0 for _, v in workspace.Enemies:GetChildren() do if v.Name == "Living Zombie" and v.Humanoid and v.Humanoid.Health > 0 then
							b = b + 1
						end
					end
					return b
				end)() == 6
			then
				repeat
					for _, v in workspace.Enemies:GetChildren() do
						if v.Name == "Living Zombie" and v.Humanoid and v.Humanoid.Health > 0 then
							repeat
								task.wait()
								if not v or not v.PrimaryPart or not v:FindFirstChild("Humanoid") or v.Humanoid.Health <= 0 then
									break
								end
								Tween(v.PrimaryPart.CFrame * CFrame.new(0, 15, 10), 350)
								if LocalPlayer:DistanceFromCharacter(v.PrimaryPart.CFrame.Position) <= 220 then
									Tween(v.PrimaryPart.CFrame * CFrame.new(0, 15, 10), math.huge)
									if LocalPlayer:DistanceFromCharacter(v.PrimaryPart.CFrame.Position) <= 40 then
										BringSG(v.Name)
										EquipWeapon()
										Attack()
									end
								end
							until not v or not v.PrimaryPart or not v:FindFirstChild("Humanoid") or v.Humanoid.Health <= 0
						end
					end
				until CommF_:InvokeServer("GuitarPuzzleProgress", "Check").Swamp
					or (function()
							local b = 0
							for _, v in workspace.Enemies:GetChildren() do
								if v.Name == "Living Zombie" and v.PrimaryPart and v:FindFirstChild("Humanoid") and v.Humanoid.Health > 0 then
									b = b + 1
								end
							end
							return b
						end)()
						== 0
			end
		elseif check.Gravestones == false then
	        LogChange("soul_guitar_stage", "soul guitar: solving gravestones")
	        SetStatus("soul guitar | solving gravestones")
			CommF_:InvokeServer("GuitarPuzzleProgress", "Gravestones")
		elseif check.Ghost == false then
	        LogChange("soul_guitar_stage", "soul guitar: completing ghost challenge")
	        SetStatus("soul guitar | completing ghost challenge")
			CommF_:InvokeServer("GuitarPuzzleProgress", "Ghost")
		elseif check.Trophies == false then
	        LogChange("soul_guitar_stage", "soul guitar: completing trophy challenge")
	        SetStatus("soul guitar | completing trophy challenge")
			CommF_:InvokeServer("GuitarPuzzleProgress", "Trophies")
		elseif check.Pipes == false then
	        LogChange("soul_guitar_stage", "soul guitar: solving pipes")
	        SetStatus("soul guitar | solving pipes")
			CommF_:InvokeServer("GuitarPuzzleProgress", "Pipes")
		elseif check.CraftedOnce == false then
			if LocalPlayer.Data.Fragments.Value >= 5000 and GetMaterial("Bones") >= 500 and GetMaterial("Ectoplasm") >= 250 then
	            LogChange("soul_guitar_stage", "soul guitar: crafting")
	            SetStatus("soul guitar | crafting")
				CommF_:InvokeServer("soulGuitarBuy")
	        else
	            LogChange("soul_guitar_stage", "soul guitar: collecting materials")
	            SetStatus("soul guitar | collecting materials")
	            LogChange("soul_guitar_materials", "soul guitar: fragments " .. tostring(LocalPlayer.Data.Fragments.Value) .. "/5000, bones " .. tostring(GetMaterial("Bones")) .. "/500, ectoplasm " .. tostring(GetMaterial("Ectoplasm")) .. "/250")
			end
		end
	end

	local CheckMonster

	local function UnlockSecondSea()
	    LogChange("sea_unlock", "sea: unlocking second sea")
		local travel = CommF_:InvokeServer("TravelDressrosa")
		if travel:find("Cannot") then
			local data = CommF_:InvokeServer("DressrosaQuestProgress")
			if not data.UsedKey then
				if not data.TalkedDetective then
	                LogChange("sea2_stage", "sea 2: talking to detective")
	                SetStatus("sea 2 | talking to detective")
					CommF_:InvokeServer("DressrosaQuestProgress", "Detective")
				elseif LocalPlayer.Backpack:FindFirstChild("Key") then
					Character.Humanoid:EquipTool(LocalPlayer.Backpack["Key"])
				end
				CommF_:InvokeServer("DressrosaQuestProgress", "UseKey")
			elseif not data.KilledIceBoss then
	            LogChange("sea2_stage", "sea 2: defeating ice admiral")
	            SetStatus("sea 2 | defeating ice admiral")
				if CheckMonster("Ice Admiral") then
					KillMonster("Ice Admiral")
				else
					Tween(CFrame.new(1328, 43, -1346), 300)
				end
			else
				CommF_:InvokeServer("TravelDressrosa")
			end
		end
	end

	local function GetFruitValue(_v)
		local data = IRS:GetItems(KEYS.QUANTITY)
		for _, v in data do
			local item = MATCH(v.ItemId)._ok
			if item.Display.Category == "Blox Fruit" and item.Quality.MoneyPrice >= _v then
				return item.Index.StorageKey
			end
		end
		return nil
	end

	local function GetFruitId(g)
		local ok = string.match(g, "((%u)[^%-]+)$")
		return ok .. "Fruit"
	end

	local zQuestProRemote = ReplicatedStorage.Remotes:FindFirstChild("RefreshZQuestPro")
	if World.Sea2() and zQuestProRemote then
		local zQuestProConnection = zQuestProRemote.OnClientEvent:Connect(function(a)
			if a == "promptDialogue" then
				print("cutscene finished")
				HopLowServer()
			end
		end)
	end

	local GetFruits

	local function UnlockThirdSea()
	    LogChange("sea_unlock", "sea: unlocking third sea")
		local check = CommF_:InvokeServer("ZQuestProgress", "Check")
		if CommF_:InvokeServer("GetUnlockables").FlamingoAccess then
			print("check: " .. tostring(check))
			if check == 0 then
	            LogChange("sea3_stage", "sea 3: starting rip indra quest")
	            SetStatus("sea 3 | starting rip indra quest")
				CommF_:InvokeServer("TravelZou")
				if LocalPlayer:DistanceFromCharacter(Vector3.new(0, 0, 0)) < 20000 then
					CommF_:InvokeServer("ZQuestProgress", "Begin")
				end
				if CheckMonster("rip_indra") then
					KillMonster("rip_indra")
				else
					LocalPlayer:Kick("Rejoin to fix blox kid")
				end
			elseif check == 1 then
	            LogChange("sea3_stage", "sea 3: continuing quest")
	            SetStatus("sea 3 | continuing quest")
				CommF_:InvokeServer("TravelZou")
			else
				if CheckMonster("Don Swan") then
	                LogChange("sea3_stage", "sea 3: defeating don swan")
	                SetStatus("sea 3 | defeating don swan")
					KillMonster("Don Swan")
					SWAN_KILLED = true
					CommF_:InvokeServer("ZQuestProgress", "Begin")
				else
					if LocalPlayer:DistanceFromCharacter(Vector3.new(2288, 15, 863)) > 15 then
						Tween(CFrame.new(2288, 15, 863), 350).Completed:Wait()
						return true
					end
				end
			end
		else
	        LogChange("sea3_stage", "sea 3: unlocking flamingo access")
	        SetStatus("sea 3 | unlocking flamingo access")
			local talk = CommF_:InvokeServer("TalkTrevor", "1")
			if talk then
				if talk == 1 or talk ~= 2 then
					local df = GetFruitValue(1000000)
					if df then
						if talk == 1 then
							CommF_:InvokeServer("TalkTrevor", "2")
							task.wait(0.75)
						end
						PAUSE_AUTO_STORE = true
						CommF_:InvokeServer("LoadFruit", df)
						EquipTool(GetFruitId(df))
						CommF_:InvokeServer("TalkTrevor", "1")
						CommF_:InvokeServer("TalkTrevor", "2")
						CommF_:InvokeServer("TalkTrevor", "3")
						PAUSE_AUTO_STORE = false
					else
						local df = GetFruits()
						if df then
							pcall(function()
								Tween(df:GetPivot(), 350).Completed:Wait()
							end)
						end
						hop()
						task.wait(5)
					end
				end
			end
		end
	end

	GetFruits = function()
		for _, v in workspace:GetChildren() do
			if string.find(v.Name, "Fruit") and (v:IsA("Tool") or v:IsA("Model")) and (v.Name ~= "Fruit ") then
				return v
			end
		end
		return nil
	end

	local function GetCastleRaid()
		for _, v in {workspace.Enemies, ReplicatedStorage} do
			for _, v2 in v:GetChildren() do
				if v2:GetAttribute("Level") and v2:GetAttribute("Level") <= 1500 and v2:IsA("Model") and (v2:GetPivot().Position - Vector3.new(-5000, 350, -3035)).Magnitude <= 1000 then
					return true
				end
			end
		end
		return nil
	end

	task.spawn(function()
		while true do
			if not PAUSE_AUTO_STORE then
				pcall(function()
					local gg = {}
					for _, _v in {LocalPlayer.Backpack, LocalPlayer.Character} do
						if _v then
							for _, v in _v:GetChildren() do
								if v.Name:find("Fruit") and v:IsA("Tool") then
									local ori = v:GetAttribute("OriginalName") or v.Name
									if not CheckItem(v.Name) and not CheckItem(ori) then
										table.insert(gg, { tool = v, ori = ori, })
									end
								end
							end
						end
					end
					if #gg > 0 then
						local sf = {}
						local inv = CommF_:InvokeServer("getInventoryFruits")
						if type(inv) == "table" then
							for _, _v in inv do
								if type(_v) == "table" and _v.Name then
									sf[_v.Name] = true
								end
							end
						end
						for _, v in gg do
							if not sf[v.ori] then
								CommF_:InvokeServer("StoreFruit", v.ori, v.tool)
								sf[v.ori] = true
							end
						end
					end
				end)
			end
			CommF_:InvokeServer("Cousin", "DLCBoxData")
			task.wait(1)
		end
	end)

	local materialMon, materialPos
	local function GetMaterialMon(material)
		if not Character or not Character.PrimaryPart then
			return
		end
		if World.Sea1() then
			if material == "Angel Wings" then
				materialMon = {
					"Shanda",
					"Royal Squad",
					"Royal Soldier",
					"Wysper",
					"Thunder God",
				}
				materialPos = CFrame.new(-4698, 845, -1912)
			elseif material == "Leather + Scrap Metal" then
				materialMon = {
					"Brute",
					"Pirate",
				}
				materialPos = CFrame.new(-1145, 15, 4350)
			elseif material == "Magma Ore" then
				materialMon = {
					"Military Soldier",
					"Military Spy",
					"Magma Admiral",
				}
				materialPos = CFrame.new(-5815, 84, 8820)
			elseif material == "Fish Tail" then
				materialMon = {
					"Fishman Warrior",
					"Fishman Commando",
					"Fishman Lord",
				}
				materialPos = CFrame.new(61123, 19, 1569)
			end
		elseif World.Sea2() then
			if material == "Leather + Scrap Metal" then
				materialMon = {
					"Marine Captain",
				}
				materialPos = CFrame.new(-2010.5059814453125, 73.00115966796875, -3326.620849609375)
			elseif material == "Magma Ore" then
				materialMon = {
					"Magma Ninja",
					"Lava Pirate",
				}
				materialPos = CFrame.new(-5428, 78, -5959)
			elseif material == "Ectoplasm" then
				materialMon = {
					"Ship Deckhand",
					"Ship Engineer",
					"Ship Steward",
					"Ship Officer",
				}
				materialPos = CFrame.new(911.35827636719, 125.95812988281, 33159.5390625)
			elseif material == "Mystic Droplet" then
				materialMon = {
					"Water Fighter",
				}
				materialPos = CFrame.new(-3385, 239, -10542)
			elseif material == "Radioactive Material" then
				materialMon = {
					"Factory Staff",
				}
				materialPos = CFrame.new(295, 73, -56)
			elseif material == "Vampire Fang" then
				materialMon = {
					"Vampire",
				}
				materialPos = CFrame.new(-6033, 7, -1317)
			end
		elseif World.Sea3() then
			if material == "Leather + Scrap Metal" then
				materialMon = {
					"Jungle Pirate",
					"Forest Pirate",
				}
				materialPos = CFrame.new(-11975.78515625, 331.7734069824219, -10620.0302734375)
			elseif material == "Fish Tail" then
				materialMon = {
					"Fishman Raider",
					"Fishman Captain",
				}
				materialPos = CFrame.new(-10993, 332, -8940)
			elseif material == "Conjured Cocoa" then
				materialMon = {
					"Chocolate Bar Battler",
					"Cocoa Warrior",
				}
				materialPos = CFrame.new(620, 78, -12581.369140625)
			elseif material == "Dragon Scale" then
				materialMon = {
					"Dragon Crew Warrior",
					"Dragon Crew Archer"
				}
				materialPos = CFrame.new(6594, 383, 139)
			elseif material == "Gunpowder" then
				materialMon = {
					"Pistol Billionaire",
				}
				materialPos = CFrame.new(-469, 74, 5904)
			elseif material == "Mini Tusk" then
				materialMon = {
					"Mythological Pirate",
				}
				materialPos = CFrame.new(-13545, 470, -6917)
			end
		end
	end

	local function FarmMaterial(material)
	    LogChange("material", "material: farming " .. string.lower(tostring(material)))
		GetMaterialMon(material)
		local mob = nil
		local min = math.huge
		for _, v in workspace.Enemies:GetChildren() do
			if v.PrimaryPart and v:FindFirstChild("Humanoid") and v.Humanoid.Health > 0 and table.find(materialMon, v.Name) then
				local dist = LocalPlayer:DistanceFromCharacter(v.PrimaryPart.Position)
				if dist < min then
					min = dist
					mob = v
				end
			end
		end
		if mob and mob.PrimaryPart and mob.Humanoid and mob.Humanoid.Health > 0 then
	        LogChange("material_target", "material: target found for " .. string.lower(tostring(material)))
	        SetStatus("material | fighting for " .. string.lower(tostring(material)))
			repeat
				task.wait()
				EquipWeapon()
				Tween(mob.PrimaryPart.CFrame * CFrame.new(0, 20, 10), 350)
				if LocalPlayer:DistanceFromCharacter(mob.PrimaryPart.CFrame.Position) <= 200 then
					Tween(mob.PrimaryPart.CFrame * CFrame.new(0, 20, 10), math.huge)
					if LocalPlayer:DistanceFromCharacter(mob.PrimaryPart.CFrame.Position) <= 45 then
						BringMob(mob.Name)
						Attack()
					end
				end
			until not mob or not mob.PrimaryPart or not mob:FindFirstChild("Humanoid") or mob.Humanoid.Health <= 0
		else
	        LogChange("material_target", "material: waiting for " .. string.lower(tostring(material)) .. " spawn")
	        SetStatus("material | waiting for " .. string.lower(tostring(material)) .. " spawn")
			Tween(materialPos, 350).Completed:Wait()
		end
	end

	local function GetRaceGrade()
		local race = LocalPlayer.Data.Race
		if LocalPlayer.Backpack:FindFirstChild("Awakening") or Character:FindFirstChild("Awakening") then
			return "V4"
		elseif LocalPlayer.Backpack:FindFirstChild("Last Resort") or Character:FindFirstChild("Last Resort") or LocalPlayer.Backpack:FindFirstChild("Agility") or LocalPlayer.Character:FindFirstChild("Agility") or LocalPlayer.Backpack:FindFirstChild("Water Body") or Character:FindFirstChild("Water Body") or LocalPlayer.Backpack:FindFirstChild("Heavenly Blood") or Character:FindFirstChild("Heavenly Blood") or LocalPlayer.Backpack:FindFirstChild("Heightened Senses") or Character:FindFirstChild("Heightened Senses") or LocalPlayer.Backpack:FindFirstChild("Energy Core") or Character:FindFirstChild("Energy Core") or LocalPlayer.Backpack:FindFirstChild("Primordial Reign") or Character:FindFirstChild("Primordial Reign") then
			return "V3"
		elseif race:FindFirstChild("Evolved") then
			return "V2"
		else
			return "V1"
		end
	end

	BindedMeleeNPCNames = {}
	local function MeleeNPCPosition(a, b, c)
		for i, v in {a, b, c} do
			if v and World["Sea" .. i]() then
				return v
			end
		end
		return nil
	end

	BindedMeleeNPCNames.BlackLeg =
		MeleeNPCPosition(Vector3.new(-985, 14, 3988), Vector3.new(-4754, 35, -4849), Vector3.new(-5045, 372, -3178))
	BindedMeleeNPCNames.Electro =
		MeleeNPCPosition(Vector3.new(-5384, 14, -2149), Vector3.new(-4864, 35, -4765), Vector3.new(-4994, 315, -3201))
	BindedMeleeNPCNames.FishmanKarate =
		MeleeNPCPosition(Vector3.new(61585, 19, 987), Vector3.new(-4957, 35, -4668), Vector3.new(-5022, 372, -3187))

	BindedMeleeNPCNames.SharkmanKarate =
		MeleeNPCPosition(nil, Vector3.new(-2602, 239, -10317), Vector3.new(-4974, 315, -3221))
	BindedMeleeNPCNames.DeathStep = MeleeNPCPosition(nil, Vector3.new(6356, 296, -6763), Vector3.new(-4997, 315, -3220))
	BindedMeleeNPCNames.Superhuman = MeleeNPCPosition(nil, Vector3.new(1379, 247, -5190), Vector3.new(-5004, 372, -3194))
	BindedMeleeNPCNames.DragonClaw = MeleeNPCPosition(nil, Vector3.new(702, 187, 653), Vector3.new(-4980, 372, -3205))

	BindedMeleeNPCNames.ElectricClaw = MeleeNPCPosition(nil, nil, Vector3.new(-10371, 331, -10131))
	BindedMeleeNPCNames.DragonTalon = MeleeNPCPosition(nil, nil, Vector3.new(5661, 1210, 863))
	BindedMeleeNPCNames.Godhuman = MeleeNPCPosition(nil, nil, Vector3.new(-13774, 333, -9879))

	local function TweenToMeleeBuyer(name)
		local p = BindedMeleeNPCNames[name]
		if p then
			return TweenWithRespawnRetry(p, 300)
		end
		return false
	end
	local function GetMastery(name)
		local melee = {
			"DeathStep",
			"Superhuman",
			"ElectricClaw",
			"DragonTalon",
			"SharkmanKarate",
			"BlackLeg",
			"Electro",
			"FishmanKarate",
			"SanguineArt",
			"DragonClaw",
		}
		if table.find(melee, name) then
			return MeleeData[name] or 0
		elseif CheckItem(name) then
			LoadItem(name)
			task.wait(1)
			local tool = LocalPlayer.Backpack:FindFirstChild(name)
			if tool then
				return tool.Level.Value
			end
		end
		return 0
	end

	local function DoRaceV2()
	    LogChange("race_mode", "race v2: checking progress")
		if not World.Sea2() then
	        LogChange("race_v2_travel", "race v2: traveling to sea 2")
	        SetStatus("race v2 | traveling to sea 2")
			while true do
				CommF_:InvokeServer("TravelDressrosa")
				task.wait(5)
			end
		end
		if not LocalPlayer.Data.Race:FindFirstChild("Evolved") then
			local check = CommF_:InvokeServer("Alchemist", "1")
			if check == 0 then
	            LogChange("race_v2_stage", "race v2: talking to alchemist")
	            SetStatus("race v2 | talking to alchemist")
				CommF_:InvokeServer("Alchemist", "2")
			elseif check == 1 then
	            if LocalPlayer.Backpack:FindFirstChild("Flower 1") or Character:FindFirstChild("Flower 1") then
	                LogChange("race_v2_flower1", "race v2: flower 1 collected")
	            end
	            if LocalPlayer.Backpack:FindFirstChild("Flower 2") or Character:FindFirstChild("Flower 2") then
	                LogChange("race_v2_flower2", "race v2: flower 2 collected")
	            end
	            if LocalPlayer.Backpack:FindFirstChild("Flower 3") or Character:FindFirstChild("Flower 3") then
	                LogChange("race_v2_flower3", "race v2: flower 3 collected")
	            end
				if not LocalPlayer.Backpack:FindFirstChild("Flower 1") and not Character:FindFirstChild("Flower 1") then
	                LogChange("race_v2_stage", "race v2: collecting flower 1")
	                SetStatus("race v2 | collecting flower 1")
					Tween(workspace.Flower1.CFrame, 350)
					firetouchinterest(workspace.Flower1, Character.HumanoidRootPart, 1)
					firetouchinterest(workspace.Flower1, Character.HumanoidRootPart, 0)
	                LogChange("race_v2_flower1", "race v2: flower 1 collected")
				elseif not LocalPlayer.Backpack:FindFirstChild("Flower 2") and not Character:FindFirstChild("Flower 2") then
	                LogChange("race_v2_stage", "race v2: collecting flower 2")
	                SetStatus("race v2 | collecting flower 2")
					Tween(workspace.Flower2.CFrame, 350)
					firetouchinterest(workspace.Flower2, Character.HumanoidRootPart, 1)
					firetouchinterest(workspace.Flower2, Character.HumanoidRootPart, 0)
	                LogChange("race_v2_flower2", "race v2: flower 2 collected")
				elseif not LocalPlayer.Backpack:FindFirstChild("Flower 3") and not Character:FindFirstChild("Flower 3") then
					if workspace.Enemies:FindFirstChild("Zombie") then
	                    LogChange("race_v2_stage", "race v2: farming zombie for flower 3")
	                    SetStatus("race v2 | farming zombie for flower 3")
						for _, v in workspace.Enemies:GetChildren() do
							if v.Name == "Zombie" then
								repeat
									task.wait()
									if not v or not v.PrimaryPart or not v:FindFirstChild("Humanoid") or v.Humanoid.Health <= 0 then
										break
									end
									Tween(v.PrimaryPart.CFrame * CFrame.new(0, 15, 10), 350)
									if LocalPlayer:DistanceFromCharacter(v.PrimaryPart.Position) <= 200 then
										Tween(v.PrimaryPart.CFrame * CFrame.new(0, 15, 10), math.huge)
										EquipWeapon()
										BringMob(v.Name)
										Attack()
									end
								until LocalPlayer.Backpack:FindFirstChild("Flower 3")
									or not v
									or not v.PrimaryPart
									or not v:FindFirstChild("Humanoid")
									or v.Humanoid.Health <= 0
							end
						end
					else
	                    LogChange("race_v2_stage", "race v2: waiting for zombie spawn")
	                    SetStatus("race v2 | waiting for zombie spawn")
						Tween(CFrame.new(-5685, 48, -853), 350).Completed:Wait()
					end
				end
			elseif check == 2 then
	            LogChange("race_v2_stage", "race v2: submitting flowers")
	            SetStatus("race v2 | submitting flowers")
				CommF_:InvokeServer("Alchemist", "3")
			end
	    else
	        LogChange("race_v2_stage", "race v2: already evolved")
	        SetStatus("race v2 | already evolved")
		end
	end

	CheckMonster = function(name)
		return workspace.Enemies:FindFirstChild(name) or ReplicatedStorage:FindFirstChild(name)
	end

	MinkQuestStage = 0
	HumanQuestStage = 0
	local function DoRaceV3()
	    LogChange("race_mode", "race v3: checking progress")
		if not World.Sea2() then
	        LogChange("race_v3_travel", "race v3: traveling to sea 2")
	        SetStatus("race v3 | traveling to sea 2")
			while true do
				CommF_:InvokeServer("TravelDressrosa")
				task.wait(5)
			end
		end
		local race = LocalPlayer.Data.Race.Value
		local check = CommF_:InvokeServer("Wenlocktoad", "1")
		if check == 0 then
	        LogChange("race_v3_stage", "race v3: starting quest")
	        SetStatus("race v3 | starting quest")
			CommF_:InvokeServer("Wenlocktoad", "2")
		elseif check == 1 then
			if race == "Human" then
				if HumanQuestStage == 0 then
	                LogChange("race_v3_stage", "race v3: fighting jeremy")
	                SetStatus("race v3 | fighting jeremy")
					if CheckMonster("Jeremy") then
						KillMonster("Jeremy")
						HumanQuestStage = 1
					else
						Tween(CFrame.new(2333.209228515625, 449.2427062988281, 699.5128784179688), 300).Completed:Wait()
					end
				elseif HumanQuestStage == 1 then
	                LogChange("race_v3_stage", "race v3: fighting diamond")
	                SetStatus("race v3 | fighting diamond")
					if CheckMonster("Diamond") then
						KillMonster("Diamond")
						HumanQuestStage = 2
					else
						Tween(CFrame.new(-1713.5589599609375, 198.99554443359375, -104.31584167480469), 300).Completed:Wait()
					end
				elseif HumanQuestStage == 2 then
	                LogChange("race_v3_stage", "race v3: fighting orbitus")
	                SetStatus("race v3 | fighting orbitus")
					if CheckMonster("Orbitus") then
						KillMonster("Orbitus")
						HumanQuestStage = 3
					else
						Tween(CFrame.new(-2148.7568359375, 73.27831268310547, -4304.4130859375), 300).Completed:Wait()
					end
				elseif HumanQuestStage == 3 then
	                LogChange("race_v3_stage", "race v3: completing human trial")
	                SetStatus("race v3 | completing human trial")
					CommF_:InvokeServer("Wenlocktoad", "3")
				end
			elseif race == "Rabbit" then
				for _, v in workspace.ChestModels:GetChildren() do
					if MinkQuestStage < 30 then
	                    LogChange("race_v3_chests", "race v3: collecting chest " .. tostring(MinkQuestStage + 1) .. "/30")
	                    SetStatus("race v3 | collecting chest " .. tostring(MinkQuestStage + 1) .. "/30")
						Tween(v.WorldPivot.Position, 350).Completed:Wait()
						MinkQuestStage = MinkQuestStage + 1
					elseif MinkQuestStage >= 30 then
	                    LogChange("race_v3_stage", "race v3: completing rabbit trial")
	                    SetStatus("race v3 | completing rabbit trial")
						CommF_:InvokeServer("Wenlocktoad", "3")
					end
				end
			elseif race == "Fishman" then
	            LogChange("race_v3_stage", "race v3: farming sea beasts")
	            SetStatus("race v3 | farming sea beasts")
				repeat
					Seabeast()
					task.wait(1)
					CommF_:InvokeServer("Wenlocktoad", "3")
				until GetRaceGrade() == "V3" or not string.find(race, "Fish")
			end
		elseif check == 2 then
	        LogChange("race_v3_stage", "race v3: completing trial")
	        SetStatus("race v3 | completing trial")
			CommF_:InvokeServer("Wenlocktoad", "3")
	    else
	        LogChange("race_v3_stage", "race v3: waiting for trial")
	        SetStatus("race v3 | waiting for trial")
		end
	end

	local Travel = {
		Sea1 = function()
			if not World.Sea1() then
				while true do
					CommF_:InvokeServer("TravelMain")
					task.wait(10)
				end
			end
		end,
		Sea2 = function()
			if not World.Sea2() then
				while true do
					CommF_:InvokeServer("TravelDressrosa")
					task.wait(10)
				end
			end
		end,
		Sea3 = function()
			if not World.Sea3() then
				while true do
					CommF_:InvokeServer("TravelZou")
					task.wait(10)
				end
			end
		end
	}

	local function GetGodHuman()
	    LogChange("godhuman", "godhuman: checking requirements")
		local check = CommF_:InvokeServer("BuyGodhuman", true)
		if check ~= 0 and check ~= 1 then
			for i, v in {"Dragon Scale", "Fish Tail", "Mystic Droplet", "Magma Ore"} do
				local max = 0
				if (i % 2) > 0 then
					max = 10
				else
					max = 20
				end
				if GetMaterial(v) < max then
	                LogChange("godhuman_material", "godhuman: " .. string.lower(v) .. " " .. tostring(GetMaterial(v)) .. "/" .. tostring(max))
					if (i == 1 or i == 2) and not World.Sea3() then
						Travel.Sea3()
					elseif (i == 3 or i == 4) and not World.Sea2() then
						Travel.Sea2()
					end
					repeat
						FarmMaterial(v)
						task.wait(0.2)
					until GetMaterial(v) >= max
				end
			end
	        LogChange("godhuman_stage", "godhuman: traveling to buyer")
	        SetStatus("godhuman | traveling to buyer")
			Travel.Sea3()
			TweenToMeleeBuyer("Godhuman")
	        LogChange("godhuman_stage", "godhuman: purchasing style")
	        SetStatus("godhuman | purchasing style")
			CommF_:InvokeServer("BuyGodhuman", true)
			CommF_:InvokeServer("BuyGodhuman")
		else
	        LogChange("godhuman_stage", "godhuman: purchasing style")
	        SetStatus("godhuman | purchasing style")
			Travel.Sea3()
			TweenToMeleeBuyer("Godhuman")
			CommF_:InvokeServer("BuyGodhuman")
		end
	end

	local function GetSaber()
	    LogChange("saber", "saber: checking progress")
		Travel.Sea1()
		CommF_:InvokeServer("AbandonQuest")
		local data = CommF_:InvokeServer("ProQuestProgress")
		if data.UsedRelic == false then
	        LogChange("saber_stage", "saber: solving jungle puzzle")
	        SetStatus("saber | solving jungle puzzle")
			while not (workspace.Map:FindFirstChild("Jungle") and workspace.Map.Jungle:FindFirstChild("QuestPlates") and workspace.Map.Jungle.QuestPlates:FindFirstChild("Door")) do
				task.wait()
				Tween(CFrame.new(-1254.25439453125, 18.39460563659668, 342.31976318359375), 350)
			end
			if workspace.Map.Jungle.QuestPlates.Door.Transparency == 0 then
	            LogChange("saber_stage", "saber: activating jungle plates")
	            SetStatus("saber | activating jungle plates")
				for _, v in workspace.Map.Jungle.QuestPlates:GetChildren() do
					if v:IsA("Model") and string.find(v.Name, "Plate") then
						firetouchinterest(v.Button, Character.HumanoidRootPart, 1)
						firetouchinterest(v.Button, Character.HumanoidRootPart, 0)
					end
				end
			else
				if data.UsedTorch == false then
	                LogChange("saber_stage", "saber: collecting torch")
	                SetStatus("saber | collecting torch")
					if LocalPlayer.Backpack:FindFirstChild("Torch") or Character:FindFirstChild("Torch") then
						CommF_:InvokeServer("ProQuestProgress", "DestroyTorch")
					else
						CommF_:InvokeServer("ProQuestProgress", "GetTorch")
					end
				else
					if data.UsedCup then
						if data.TalkedSon and data.KilledMob then
	                        LogChange("saber_stage", "saber: placing relic")
	                        SetStatus("saber | placing relic")
							if not data.UsedRelic then
								CommF_:InvokeServer("ProQuestProgress", "RichSon")
								if not Character:FindFirstChild("Relic") then
									Character.Humanoid:EquipTool(LocalPlayer.Backpack:FindFirstChild("Relic"))
								end
								CommF_:InvokeServer("ProQuestProgress", "PlaceRelic")
							end
						elseif data.TalkedSon == false then
	                        LogChange("saber_stage", "saber: talking to rich son")
	                        SetStatus("saber | talking to rich son")
							CommF_:InvokeServer("ProQuestProgress", "RichSon")
						elseif data.KilledMob == false then
	                        LogChange("saber_stage", "saber: defeating mob leader")
	                        SetStatus("saber | defeating mob leader")
							if CheckMonster("Mob Leader") then
								KillMonster("Mob Leader")
							end
						end
					else
	                    LogChange("saber_stage", "saber: filling cup")
	                    SetStatus("saber | filling cup")
						CommF_:InvokeServer("ProQuestProgress", "GetCup")
						if not Character:FindFirstChild("Cup") then
							Character.Humanoid:EquipTool(LocalPlayer.Backpack:FindFirstChild("Cup"))
						end
						CommF_:InvokeServer("ProQuestProgress", "FillCup", Character.Cup)
						CommF_:InvokeServer("ProQuestProgress", "SickMan")
					end
				end
			end
		else
	        LogChange("saber_stage", "saber: fighting saber expert")
	        SetStatus("saber | fighting saber expert")
			if CheckMonster("Saber Expert") then
				KillMonster("Saber Expert")
			else
				Tween( ReplicatedStorage.FortBuilderReplicatedSpawnPositionsFolder["Saber Expert"].CFrame * CFrame.new(0, 25, 0), 350 )
			end
		end
	end

	local function DoBartiloQuest()
	    LogChange("bartilo", "bartilo: checking progress")
		if not World.Sea2() then
	        LogChange("bartilo_travel", "bartilo: traveling to sea 2")
	        SetStatus("bartilo | traveling to sea 2")
			while true do
				CommF_:InvokeServer("TravelDressrosa")
				task.wait(7.5)
			end
		end
		local function CheckKilledBanit()
			return CommF_:InvokeServer("BartiloQuestProgress").KilledBandits
		end
		local data = CommF_:InvokeServer("BartiloQuestProgress", "Bartilo")
		if CheckKilledBanit() == false then
	        LogChange("bartilo_stage", "bartilo: farming swan pirates")
	        SetStatus("bartilo | farming swan pirates")
			repeat
				if QuestController.CurrentQuestName ~= "BartiloQuest" then
					CommF_:InvokeServer("StartQuest", "BartiloQuest", 1)
				end
				if workspace.Enemies:FindFirstChild("Swan Pirate") then
					for _, v in workspace.Enemies:GetChildren() do
						if v.Name == "Swan Pirate" and v:FindFirstChildOfClass("Humanoid") and v.Humanoid.Health > 0 and v.PrimaryPart then
							repeat
								task.wait()
								if not v or not v.PrimaryPart or not v:FindFirstChildOfClass("Humanoid") or v.Humanoid.Health <= 0 then
									break
								end
								Tween(v.PrimaryPart.Position + Vector3.new(0, 20, 10), 350)
								if LocalPlayer:DistanceFromCharacter(v.PrimaryPart.Position) <= 200 then
									Tween(v.PrimaryPart.Position + Vector3.new(0, 20, 10), math.huge)
									EquipWeapon()
									BringMob(v.Name)
									Attack()
								end
							until not v or not v.PrimaryPart or v.Humanoid.Health <= 0
						end
					end
				else
					Tween(CFrame.new(932.624451, 156.106079, 1180.27466), 350).Completed:Wait()
				end
			until CheckKilledBanit()
		elseif data == 1 then
	        LogChange("bartilo_stage", "bartilo: defeating jeremy")
	        SetStatus("bartilo | defeating jeremy")
			if CheckMonster("Jeremy") then
				KillMonster("Jeremy")
			else
				Tween(Vector3.new(2129, 469, 779), 300).Completed:Wait()
			end
		elseif data == 2 then
			for i = 1, 8 do
	            LogChange("bartilo_plate", "bartilo: activating plate " .. tostring(i) .. "/8")
	            SetStatus("bartilo | activating plate " .. tostring(i) .. "/8")
				firetouchinterest(workspace.Map.Dressrosa.BartiloPlates["Plate" .. i], Character.PrimaryPart, 0)
				task.wait(0.1)
				firetouchinterest(workspace.Map.Dressrosa.BartiloPlates["Plate" .. i], Character.PrimaryPart, 1)
			end
		end
	end
	local function CheckDataLevel()
		local lv = LocalPlayer.Data.Level.Value
		if lv < 10 then
			return 1
		elseif lv < 70 then
			return 2
		elseif lv < 120 then
			return 3
		else
			return 4
		end
	end
	local function FarmLevelLogic()
		local levelData = CheckDataLevel()
	    LogChange("farm_band", "farm: level band " .. tostring(levelData))
		if levelData == 2 then
	        LogChange("farm_target", "farm: targeting shanda")
	        SetStatus("farm | targeting shanda | lv " .. tostring(LocalPlayer.Data.Level.Value))
			local foundMob = false
			for _, v in {workspace.Enemies, ReplicatedStorage} do
				for _, v2 in v:GetChildren() do
					if v2:IsA("Model") then
						local hrp = v2:FindFirstChild("HumanoidRootPart") or v2.PrimaryPart
						if v2.Name == "Shanda" and hrp and v2:FindFirstChildOfClass("Humanoid") and v2:FindFirstChildOfClass("Humanoid").Health > 0 then
							foundMob = true
							repeat
								task.wait()
								local t = Tween(hrp.Position + Vector3.new(0, 20, 5), 350)
								if LocalPlayer:DistanceFromCharacter(hrp.Position) <= 160 then
									if t then
										t:Cancel()
									end
									Tween(hrp.Position + Vector3.new(0, 20, 5), math.huge)
									if LocalPlayer:DistanceFromCharacter(hrp.Position) <= 40 then
										BringMob(v2.Name)
										EquipWeapon()
										Attack()
									end
								end
							until not v2 or not v2:FindFirstChildOfClass("Humanoid") or v2.Humanoid.Health == 0
							pcall(function()
								v2:Destroy()
							end)
							if not CheckMonster("Shanda") then
								break
							end
						end
					end
				end
				if foundMob then
					break
				end
			end
			if not foundMob then
				local n = ReplicatedStorage.FortBuilderReplicatedSpawnPositionsFolder:FindFirstChild("Shanda")
				if n then
					Tween(n:GetPivot().Position + Vector3.new(0, 25, 0), 350).Completed:Wait()
				end
			end
		elseif levelData == 3 then
	        LogChange("farm_target", "farm: targeting god's guard")
	        SetStatus("farm | targeting god's guard | lv " .. tostring(LocalPlayer.Data.Level.Value))
			local foundMob = false
			for _, v in {workspace.Enemies, ReplicatedStorage} do
				for _, v2 in v:GetChildren() do
					if v2:IsA("Model") then
						local hrp = v2:FindFirstChild("HumanoidRootPart") or v2.PrimaryPart
						if v2.Name == "God's Guard" and hrp and v2:FindFirstChildOfClass("Humanoid") and v2:FindFirstChildOfClass("Humanoid").Health > 0 then
							foundMob = true
							repeat
								task.wait()
								local t = Tween(hrp.Position + Vector3.new(0, 25, 5), 350)
								if LocalPlayer:DistanceFromCharacter(hrp.Position) <= 160 then
									if t then
										t:Cancel()
									end
									Tween(hrp.Position + Vector3.new(0, 25, 5), math.huge)
									if LocalPlayer:DistanceFromCharacter(hrp.Position) <= 40 then
										BringMob(v2.Name)
										EquipWeapon()
										Attack()
									end
								end
							until not v2
								or not v2.Parent
								or not v2:FindFirstChildOfClass("Humanoid")
								or v2:FindFirstChildOfClass("Humanoid").Health <= 0
								or not v2.Name:find("God's Guard")
							pcall(function()
								v2:Destroy()
							end)
							if not CheckMonster("God's Guard") then
								break
							end
						end
					end
				end
				if foundMob then
					break
				end
			end
			if not foundMob then
				local n = ReplicatedStorage.FortBuilderReplicatedSpawnPositionsFolder:FindFirstChild("God's Guard")
				if n then
					Tween(n:GetPivot().Position + Vector3.new(0, 25, 0), 350).Completed:Wait()
				end
			end
		elseif levelData == 4 or levelData == 1 then
			if GetMonsterName() then
	            LogChange("farm_target", "farm: targeting quest mob")
	            SetStatus("farm | targeting quest mob | lv " .. tostring(LocalPlayer.Data.Level.Value))
				for _, v2 in {workspace.Enemies, ReplicatedStorage} do
					for _, v in v2:GetChildren() do
						if v.Name == GetMonsterName() and v.PrimaryPart and v:FindFirstChildOfClass("Humanoid") and v:FindFirstChildOfClass("Humanoid").Health > 0 then
							local startKillThisNPC = tick()
							repeat
								task.wait()
								TakeQuest()
								local t = Tween(v:GetPivot().Position + Vector3.new(0, 20, 5), 350)
								if LocalPlayer:DistanceFromCharacter(v:GetPivot().Position) <= 160 then
									if t then
										t:Cancel()
									end
									Tween(v:GetPivot().Position + Vector3.new(0, 20, 5), math.huge)
									if LocalPlayer:DistanceFromCharacter(v:GetPivot().Position) <= 40 then
										BringMob(v.Name)
										EquipWeapon()
										Attack()
									end
								end
							until not v
								or not v.PrimaryPart
								or not v:FindFirstChildOfClass("Humanoid")
								or v:FindFirstChildOfClass("Humanoid").Health <= 0
								or v.Name ~= GetMonsterName()
								or (tick() - startKillThisNPC) >= 90
							pcall(function()
								v:Destroy()
							end)
							if not CheckMonster(GetMonsterName()) then
								break
							end
						end
					end
				end
			else
	            LogChange("farm_target", "farm: waiting for quest mob")
	            SetStatus("farm | waiting for quest mob | lv " .. tostring(LocalPlayer.Data.Level.Value))
				TakeQuest()
				for _, v in {ReplicatedStorage.FortBuilderReplicatedSpawnPositionsFolder, workspace._WorldOrigin.EnemySpawns} do
					for _, v2 in v:GetChildren() do
						if not v2.Name:find("Boss") and QuestController.CurrentQuest == v2.Name then
							repeat task.wait()
								Tween(v2:GetPivot().Position + Vector3.new(0, 25, 0), 350)
							until GetMonsterName()
							break
						end
					end
				end
				task.wait(0.25)
			end
		end
	end

	boneNPCs = {
		"Reborn Skeleton",
		"Living Zombie",
		"Demonic Soul",
		"Posessed Mummy",
	}
	local function FarmBoneLogic()
	    LogChange("bone_farm", "bone: searching for mobs")
		local mob = nil
		local min = math.huge
		for _, v in workspace.Enemies:GetChildren() do
			if v.PrimaryPart and v:FindFirstChildOfClass("Humanoid") and v.Humanoid.Health > 0 and table.find(boneNPCs, v.Name) then
				local dist = LocalPlayer:DistanceFromCharacter(v.PrimaryPart.Position)
				if dist < min then
					min = dist
					mob = v
				end
			end
		end
		if mob and mob.PrimaryPart and mob:FindFirstChildOfClass("Humanoid") and mob:FindFirstChildOfClass("Humanoid").Health > 0 then
	        LogChange("bone_target", "bone: farming " .. string.lower(mob.Name))
	        SetStatus("bone farm | " .. string.lower(mob.Name))
			TakeQuestBone(mob.Name)
			startKillThisNPC = tick()
			repeat
				task.wait()
				Tween(mob.PrimaryPart.CFrame * CFrame.new(0, 15, 5), 350)
				if LocalPlayer:DistanceFromCharacter(mob.PrimaryPart.Position) <= 210 then
					Tween(mob.PrimaryPart.CFrame * CFrame.new(0, 15, 5), math.huge)
					if LocalPlayer:DistanceFromCharacter(mob.PrimaryPart.Position) <= 30 then
						BringMob(mob.Name)
						EquipWeapon()
						Attack()
					end
				end
			until not mob or not mob.PrimaryPart or not mob:FindFirstChildOfClass("Humanoid") or mob.Humanoid.Health <= 0 or (tick() - startKillThisNPC) >= 90
		else
	        LogChange("bone_target", "bone: waiting for spawn")
	        SetStatus("bone farm | waiting for spawn")
			Tween(CFrame.new(-9515, 164, 5786), 350).Completed:Wait()
		end
	end

	local function FarmKataLogic()
	    LogChange("cake_farm", "cake: checking prince")
		Travel.Sea3()
		if LocalPlayer:DistanceFromCharacter(Vector3.new(-2132, 70, -12319)) >= 1200 and not GetCakePrince() then
			Tween(CFrame.new(-2251, 146, -12196), 350).Completed:Wait()
		end
		if GetCakePrince() then
	        LogChange("cake_target", "cake: fighting cake prince")
	        SetStatus("cake farm | fighting cake prince")
			local Target = GetCakePrince()
			repeat
				if LocalPlayer:DistanceFromCharacter(Target.PrimaryPart.CFrame.Position) >= 1200 and GetCakePrince() then
					StopTween()
					Tween(workspace.Map.CakeLoaf.BigMirror.Main.CFrame, 350).Completed:Wait()
					task.wait(0.75)
				end
				Tween(Target.PrimaryPart.CFrame * CFrame.new(0, 17.5, 10), 350)
				if LocalPlayer:DistanceFromCharacter(Target.PrimaryPart.CFrame.Position) <= 200 then
					Tween(Target.PrimaryPart.CFrame * CFrame.new(0, 17.5, 10), math.huge)
					if LocalPlayer:DistanceFromCharacter(Target.PrimaryPart.CFrame.Position) <= 40 then
						EquipWeapon()
						Attack()
					end
				end
				task.wait()
			until not Target or not GetCakePrince() or Character.Humanoid.Health <= 0
		else
			local mob = nil
			local min = math.huge
			for _, v in workspace.Enemies:GetChildren() do
				if v:FindFirstChild("HumanoidRootPart") and v:FindFirstChild("Humanoid") and v.Humanoid.Health > 0 then
					local dist = LocalPlayer:DistanceFromCharacter(v.HumanoidRootPart.Position)
					if dist < min then
						min = dist
						mob = v
					end
				end
			end
			if mob and table.find(MobsCakePrince, mob.Name) and mob:FindFirstChild("Humanoid") and mob:FindFirstChild("HumanoidRootPart") and mob.Humanoid.Health > 0 then
	            LogChange("cake_target", "cake: farming " .. string.lower(mob.Name))
	            SetStatus("cake farm | " .. string.lower(mob.Name))
				TakeQuestCake(mob.Name)
				startKillThisNPC = tick()
				repeat
					task.wait()
					Tween(mob.HumanoidRootPart.CFrame * CFrame.new(0, 15, 0), 350)
					if LocalPlayer:DistanceFromCharacter(mob.HumanoidRootPart.Position) <= 200 then
						Tween(mob.HumanoidRootPart.CFrame * CFrame.new(0, 15, 0), math.huge)
						if LocalPlayer:DistanceFromCharacter(mob.HumanoidRootPart.Position) <= 40 then
							BringMob(mob.Name)
							EquipWeapon()
							Attack()
						end
					end
				until not mob
					or not mob:FindFirstChild("Humanoid")
					or mob.Humanoid.Health <= 0
					or not mob:FindFirstChild("HumanoidRootPart")
					or (tick() - startKillThisNPC) >= 90
			end
		end
	end

	local function GetCDKLogic()
	    LogChange("cdk", "cdk: checking progress")
		Travel.Sea3()
		if CommF_:InvokeServer("CDKQuest", "OpenDoor") == "can" then
			CommF_:InvokeServer("CDKQuest", "OpenDoor", true)
		end
		local q = CommF_:InvokeServer("CDKQuest", "Progress")
	    LogChange("cdk_progress", "cdk: evil " .. tostring(q.Evil) .. " / good " .. tostring(q.Good))
		if q.Evil == 0 or q.Evil == -3 then
	        LogChange("cdk_stage", "cdk: evil trial - mythological pirate")
	        SetStatus("cdk | evil trial - mythological pirate")
			CommF_:InvokeServer("CDKQuest", "StartTrial", "Evil")
			if workspace.Enemies:FindFirstChild("Mythological Pirate") then
				repeat
					task.wait()
					Tween( workspace.Enemies:FindFirstChild("Mythological Pirate").HumanoidRootPart.CFrame * CFrame.new(5, 0, 0), 350 )
				until CommF_:InvokeServer("CDKQuest", "Progress").Evil ~= -3
					and GetMaterial("Alucard Fragment") == 1
			else
				Tween(Vector3.new(-13239, 520, -6813), 350).Completed:Wait()
			end
		elseif q.Evil == 1 or q.Evil == -4 then
	        LogChange("cdk_stage", "cdk: evil trial - haze mobs")
	        SetStatus("cdk | evil trial - haze mobs")
			CommF_:InvokeServer("CDKQuest", "StartTrial", "Evil")
			if LocalPlayer:FindFirstChild("QuestHaze") then
				for _, v in LocalPlayer.QuestHaze:GetChildren() do
					if v.Value > 0 then
	                    LogChange("cdk_haze_target", "cdk: clearing " .. string.lower(v.Name) .. " " .. tostring(v.Value))
	                    SetStatus("cdk | clearing " .. string.lower(v.Name))
						repeat
							task.wait()
							if LocalPlayer:DistanceFromCharacter( ReplicatedStorage.FortBuilderReplicatedSpawnPositionsFolder[v.Name].CFrame.Position ) >= 600 then
								Tween(ReplicatedStorage.FortBuilderReplicatedSpawnPositionsFolder[v.Name].CFrame, 350).Completed:Wait()
							end
							for _, v2 in workspace.Enemies:GetChildren() do
								if v2.Name == v.Name and v2:FindFirstChild("HumanoidRootPart") and v2:FindFirstChild("Humanoid") and v2.Humanoid.Health > 0 then
									repeat
										task.wait()
										Tween(v2.HumanoidRootPart.Position + Vector3.new(0, 25, 10), 350)
										if LocalPlayer:DistanceFromCharacter(v2.HumanoidRootPart.Position) <= 40 then
											BringMob(v2.Name)
											EquipWeapon()
											Attack()
										end
									until not v2.Humanoid or not v2.HumanoidRootPart or v2.Humanoid.Health <= 0 or not v2
									break
								end
							end
						until not v or v.Value == 0 or not LocalPlayer:FindFirstChild("QuestHaze")
					end
				end
			end
		elseif q.Evil == 2 or q.Evil == -5 then
	        LogChange("cdk_stage", "cdk: evil trial - hell dimension")
	        SetStatus("cdk | evil trial - hell dimension")
			CommF_:InvokeServer("CDKQuest", "StartTrial", "Evil")
			if workspace.Enemies:FindFirstChild("Soul Reaper") or workspace.Map:FindFirstChild("HellDimension") then
				if workspace.Enemies:FindFirstChild("Soul Reaper") and not workspace.Map:FindFirstChild("HellDimension") then
					repeat
						Tween(workspace.Enemies:FindFirstChild("Soul Reaper").HumanoidRootPart.CFrame, 350).Completed:Wait()
						task.wait()
					until workspace.Map:FindFirstChild("HellDimension")
				end
				if tw then
					tw:Cancel()
				end
				task.wait(1)
				for i = 1, 3 do
	                LogChange("cdk_torch", "cdk: lighting hell torch " .. tostring(i) .. "/3")
	                SetStatus("cdk | lighting hell torch " .. tostring(i) .. "/3")
					Tween(workspace.Map.HellDimension["Torch" .. i].CFrame, 350).Completed:Wait()
					fireproximityprompt(workspace.Map.HellDimension["Torch" .. i].ProximityPrompt)
					repeat
						task.wait()
					until #workspace.Enemies:GetChildren() > 0
					for _, v in workspace.Enemies:GetChildren() do
						if LocalPlayer:DistanceFromCharacter(v.HumanoidRootPart.CFrame.Position) <= 300 and v.HumanoidRootPart and v.Humanoid and v.Humanoid.Health > 0 then
							repeat
								task.wait()
								Tween(v.HumanoidRootPart.CFrame * CFrame.new(0, 25, 10), 350)
								if LocalPlayer:DistanceFromCharacter(v.HumanoidRootPart.Position) <= 210 then
									Tween(v.HumanoidRootPart.CFrame * CFrame.new(0, 25, 10), math.huge)
									if LocalPlayer:DistanceFromCharacter(v.HumanoidRootPart.Position) <= 40 then
										BringMob(v.Name)
										EquipWeapon()
										Attack()
									end
								end
							until not v
								or not v:FindFirstChild("Humanoid")
								or v.Humanoid.Health <= 0
								or not v:FindFirstChild("HumanoidRootPart")
						end
					end
				end
			else
				local boneNPCs = {
					"Reborn Skeleton",
					"Living Zombie",
					"Demonic Soul",
					"Posessed Mummy",
				}
				repeat
					task.wait()
					local mob = nil
					local min = math.huge
					for _, v in workspace.Enemies:GetChildren() do
						if v:FindFirstChild("HumanoidRootPart") and v:FindFirstChild("Humanoid") and v.Humanoid.Health > 0 and table.find(boneNPCs, v.Name) then
							local dist = LocalPlayer:DistanceFromCharacter(v.HumanoidRootPart.Position)
							if dist < min then
								min = dist
								mob = v
							end
						end
					end
					if mob and mob.HumanoidRootPart and mob.Humanoid and mob.Humanoid.Health > 0 then
						repeat
							task.wait()
							Tween(mob.HumanoidRootPart.CFrame * CFrame.new(0, 15, 5), 350)
							if LocalPlayer:DistanceFromCharacter(mob.HumanoidRootPart.Position) <= 210 then
								Tween(mob.HumanoidRootPart.CFrame * CFrame.new(0, 15, 5), math.huge)
								if LocalPlayer:DistanceFromCharacter(mob.HumanoidRootPart.Position) <= 30 then
									BringMob(mob.Name)
									EquipWeapon()
									Attack()
								end
							end
						until not mob
							or not mob:FindFirstChild("Humanoid")
							or mob.Humanoid.Health <= 0
							or not mob:FindFirstChild("HumanoidRootPart")
					else
						Tween(CFrame.new(-9515, 164, 5786), 350).Completed:Wait()
					end
				until LocalPlayer.Backpack:FindFirstChild("Hallow Essence") or CheckMonster("Soul Reaper")
				if LocalPlayer.Backpack:FindFirstChild("Hallow Essence") then
					EquipTool("Hallow Essence")
					if Character:FindFirstChild("Hallow Essence") then
						firetouchinterest(Character.HumanoidRootPart, workspace.Map["Haunted Castle"].Summoner.Detection, 1)
						firetouchinterest(Character.HumanoidRootPart, workspace.Map["Haunted Castle"].Summoner.Detection, 0)
					end
				end
			end
		elseif q.Good == 0 or q.Good == -3 then
	        LogChange("cdk_stage", "cdk: good trial - finding boats")
	        SetStatus("cdk | good trial - finding boats")
			CommF_:InvokeServer("CDKQuest", "StartTrial", "Good")
			for _, x in {CFrame.new(-9550, 21, 4690), CFrame.new(-6120, 16, -2250), CFrame.new(-9530, 7, -8370)} do
				repeat
					LocalPlayer.Character.HumanoidRootPart.CFrame = x
					task.wait()
				until workspace.NPCs:FindFirstChildWhichIsA("Model")
					and workspace.NPCs:FindFirstChildWhichIsA("Model").Name:find("Boat")
				for _, n in workspace.NPCs:GetChildren() do
					if n.Name:find("Boat") then
						CommF_:InvokeServer("CDKQuest", "BoatQuest", n)
					end
				end
			end
		elseif q.Good == 1 or q.Good == -4 then
	        LogChange("cdk_stage", "cdk: good trial - reaching objective")
	        SetStatus("cdk | good trial - reaching objective")
			CommF_:InvokeServer("CDKQuest", "StartTrial", "Good")
			Tween(CFrame.new(6148.4116210938, 294.38687133789, -6741.1166992188), 350)
		elseif q.Good == 2 or q.Good == -5 then
	        LogChange("cdk_stage", "cdk: good trial - heavenly dimension")
	        SetStatus("cdk | good trial - heavenly dimension")
			CommF_:InvokeServer("CDKQuest", "StartTrial", "Good")
			if workspace.Map:FindFirstChild("HeavenlyDimension") ~= nil and workspace.Map:FindFirstChild("Heavenly Dimension") then
				if workspace.Map.HeavenlyDimension.Exit.Color ~= Color3.fromRGB(0, 0, 0) then
					firetouchinterest( workspace.Map.HeavenlyDimension.Exit.Touchinterest, LocalPlayer.Character.HumanoidRootPart, 0 )
				else
					for i = 1, 3 do
	                    LogChange("cdk_heaven_torch", "cdk: lighting heaven torch " .. tostring(i) .. "/3")
	                    SetStatus("cdk | lighting heaven torch " .. tostring(i) .. "/3")
						repeat
							task.wait()
							local e = workspace.Enemies:FindFirstChildWhichIsA("Model", true)
							if e and (e.Name:find("Cursed Skeleton") or e.Name:find("Heaven")) then
								KillMonster(e.Name)
							else
								if workspace.Map.HeavenlyDimension["Torch" .. i].ProximityPrompt.Enabled then
									Tween(workspace.Map.HeavenlyDimension["Torch" .. i].CFrame, 350).Completed:Wait()
									fireproximityprompt(workspace.Map.HeavenlyDimension["Torch" .. i].ProximityPrompt)
								end
							end
						until not workspace.Map.HeavenlyDimension["Torch" .. i].ProximityPrompt.Enabled
							or workspace.Map.HeavenlyDimension.Exit.Color ~= Color3.fromRGB(0, 0, 0)
							or Character.Humanoid.Health <= 0
						StopTween()
					end
				end
			else
				if CheckMonster("Cake Queen") then
					KillMonster("Cake Queen")
					StopTween()
				else
					HopLowServer()
				end
			end
		end
	end

	CheckedMelee = false
	MeleeData = {

		BlackLeg = 0,
		Electro = 0,
		FishmanKarate = 0,

		SharkmanKarate = 0,
		DeathStep = 0,
		DragonClaw = 0,
		Superhuman = 0,

		ElectricClaw = 0,
		DragonTalon = 0,
		GodHuman = 0,
		SanguineArt = 0,
	}

	MeleePrices = {
		BlackLeg = {
			Price = {
				Beli = 150000,
			},
			Id = "BlackLeg",
			NextLevelRequirement = 400,
		},
		Electro = {
			Price = {
				Beli = 500000,
			},
			Id = "Electro",
			NextLevelRequirement = 400,
		},
		FishmanKarate = {
			Price = {
				Beli = 750000,
			},
			NextLevelRequirement = 400,
		},
		DragonClaw = {
			Price = {
				Fragments = 1500,
			},
			NextLevelRequirement = 400,
		},
		Superhuman = {
			Price = {
				Beli = 3000000,
			},
			NextLevelRequirement = 400,
		},
		DeathStep = {
			Price = {
				Beli = 2500000,
				Fragments = 5000,
			},
			NextLevelRequirement = 400,
		},
		SharkmanKarate = {
			Price = {
				Beli = 2500000,
				Fragments = 5000,
			},
			NextLevelRequirement = 400,
		},
		ElectricClaw = {
			Price = {
				Beli = 2500000,
				Fragments = 5000,
			},
			NextLevelRequirement = 400,
		},
		DragonTalon = {
			Price = {
				Beli = 2500000,
				Fragments = 5000,
			},
			NextLevelRequirement = 400,
		},
		Godhuman = {
			Price = {
				Beli = 5000000,
				Fragments = 5000,
			},
			NextLevelRequirement = 350,
		},
	}

	Name2Name = {
		["Water Kung Fu"] = "FishmanKarate",
		["Electric"] = "Electro",
		["Dark Step"] = "BlackLeg",
		["Dragon Breath"] = "DragonClaw",
	}
	local lastMeleeDataCheck = 0
	local function CheckMeleeMastery()
		local now = tick()
		if (now - lastMeleeDataCheck) < 10 then
			return
		end
		lastMeleeDataCheck = now

		if not CheckedMelee then
	        LogChange("melee_data", "melee: checking data")
		end

		local success = pcall(function()
			local data = IRS:GetItems(KEYS.MASTERY)
			for _, v in data do
				local matched = MATCH(v.ItemId)
				local item = matched and matched._ok
				if item and item.Index and item.Display then
					local n = item.Index.StorageKey
					if item.Display.Category == "Fighting Style" and n then
						local key = Name2Name[n] or n:gsub(" ", "")
						if MeleeData[key] ~= nil then
							MeleeData[key] = tonumber(v.Value) or MeleeData[key]
						end
					end
				end
			end
		end)

		if success then
			CheckedMelee = true
	        LogChange("melee_data", "melee: data loaded")
	    else
	        LogChange("melee_data", "melee: data load failed")
		end
	end

	local CheckCanDungeon, AutoDungeon

	local GetMeleeLogics = {
		SharkmanKarate = function()
			if not World.Sea2() then
				while true do
					CommF_:InvokeServer("TravelDressrosa")
					task.wait(10)
				end
			end
			local check = CommF_:InvokeServer("BuySharkmanKarate", true)
			if (not HasItem("Water Key")) and check ~= 0 and check ~= 1 and typeof(check) == "string" then
				if CheckMonster("Tide Keeper") then
					KillMonster("Tide Keeper")
				else
					HopLowServer()
					task.wait(5)
				end
			else
				TweenToMeleeBuyer("SharkmanKarate")
				CommF_:InvokeServer("BuySharkmanKarate", true)
				CommF_:InvokeServer("BuySharkmanKarate")
			end
		end,
		DeathStep = function()
			if not World.Sea2() then
				while true do
					CommF_:InvokeServer("TravelDressrosa")
					task.wait(10)
				end
			end
			local check = CommF_:InvokeServer("OpenLibrary")
			if not HasItem("Library Key") and not check then
				if CheckMonster("Awakened Ice Admiral") then
					KillMonster("Awakened Ice Admiral")
				else
					HopLowServer()
					task.wait(5)
				end
			elseif HasItem("Library Key") then
				CommF_:InvokeServer("OpenLibrary")
			elseif check == true then
				TweenToMeleeBuyer("DeathStep")
				CommF_:InvokeServer("BuyDeathStep")
			end
		end,
		ElectricClaw = function()
			Travel.Sea3()
			TweenToMeleeBuyer("ElectricClaw")
			CommF_:InvokeServer("BuyElectricClaw", "Start")
			Tween(CFrame.new(-12550, 336, -7510), 350).Completed:Wait()
			task.wait(0.5)
			TweenToMeleeBuyer("ElectricClaw")
			CommF_:InvokeServer("BuyElectricClaw")
		end,
		DragonTalon = function()
			Travel.Sea3()
			repeat
				task.wait()
				FarmBoneLogic()
				if GetMaterial("Bones") >= 50 then
					CommF_:InvokeServer("Bones", "Buy", 1, 1)
				end
			until HasItem("Fire Essence")
			TweenToMeleeBuyer("DragonTalon")
			CommF_:InvokeServer("BuyDragonTalon", true)
			CommF_:InvokeServer("BuyDragonTalon")
		end,
	}

	local function CheckYama()
		return CommF_:InvokeServer("EliteHunter", "Progress") or 0
	end

	local function MeleeKaitunLogic()
	    LogChange("melee_logic", "melee: checking styles")
		if Character then
			local beli = LocalPlayer.Data.Beli.Value
			if not CollectionService:HasTag(Character, "Buso") and (beli >= 25000) then
				CommF_:InvokeServer("BuyHaki", "Buso")
			end
			if not CollectionService:HasTag(Character, "Geppo") and (beli >= 10000) then
				CommF_:InvokeServer("BuyHaki", "Geppo")
			end
			if not CollectionService:HasTag(Character, "Soru") and (beli >= 100000) then
				CommF_:InvokeServer("BuyHaki", "Soru")
			end
		else
			return
		end
		if not CheckedMelee then
			CheckMeleeMastery()
		end
		for _, v in {"BlackLeg", "Electro", "FishmanKarate"} do
			local realName = v:gsub("(%l)(%u)", "%1 %2")

				if (MeleeData[v] or 0) < 400 then
	            LogChange("melee_progress", "melee: " .. string.lower(realName) .. " " .. tostring(MeleeData[v] or 0) .. "/400")

				if (MeleeData[v] or 0) == 0 and LocalPlayer.Data.Beli.Value < MeleePrices[v].Price.Beli then
	                LogChange("melee_wait", "melee: need beli for " .. string.lower(realName))

					return
				end
				if not HasItem(realName) then
	                LogChange("melee_action", "melee: getting " .. string.lower(realName))
					if not TweenToMeleeBuyer(v) then
						return
					end
					task.wait(0.5)
					CommF_:InvokeServer("Buy" .. v)
				end
				return
			end
		end

		if not World.Sea1() then
			for _, v in {"DragonClaw", "Superhuman", "DeathStep", "SharkmanKarate"} do
				local realName = v:gsub("(%l)(%u)", "%1 %2")
				if (MeleeData[v] or 0) < 400 then
					local hasEnoughEco = (
						(MeleePrices[v].Price.Beli == nil) or (LocalPlayer.Data.Beli.Value >= MeleePrices[v].Price.Beli)
					)
						and (
							(MeleePrices[v].Price.Fragments == nil)
							or (LocalPlayer.Data.Fragments.Value >= MeleePrices[v].Price.Fragments)
						)
					if (MeleeData[v] or 0) == 0 and hasEnoughEco then
	                    LogChange("melee_action", "melee: unlocking " .. string.lower(realName))
						if v ~= "DragonClaw" and v ~= "Superhuman" then
							GetMeleeLogics[v]()
							return true
						else
							TweenToMeleeBuyer(v)
							if v == "Superhuman" then
								CommF_:InvokeServer("Buy" .. v)
							else
								CommF_:InvokeServer("BlackbeardReward", "DragonClaw", "2")
							end
						end
					elseif (MeleeData[v] or 0) == 0 and (MeleePrices[v].Price.Fragments and (LocalPlayer.Data.Fragments.Value < MeleePrices[v].Price.Fragments)) and CheckCanDungeon() then
	                    LogChange("melee_action", "melee: farming fragments")
						if (not World.Sea1()) and LocalPlayer.Data.Level.Value >= 1250 then
							AutoDungeon()
						end
					elseif (MeleeData[v] or 0) == 0 and not hasEnoughEco then
	                    LogChange("melee_wait", "melee: waiting for " .. string.lower(realName) .. " resources")
					elseif (MeleeData[v] or 0) > 0 and not HasItem(realName) then
						if not TweenToMeleeBuyer(v) then
							break
						end
						if v == "DragonClaw" then
							CommF_:InvokeServer("BlackbeardReward", "DragonClaw", "2")
						else
							CommF_:InvokeServer("Buy" .. v)
						end
					end
					return
				end
			end
			for _, v in {"ElectricClaw", "DragonTalon", "Godhuman"} do
				local realName = v:gsub("(%l)(%u)", "%1 %2")
				if (MeleeData[v] or 0) < 400 then
					local hasEnoughEco = (
						(MeleePrices[v].Price.Beli == nil) or (LocalPlayer.Data.Beli.Value >= MeleePrices[v].Price.Beli)
					)
						and (
							(MeleePrices[v].Price.Fragments == nil)
							or (LocalPlayer.Data.Fragments.Value >= MeleePrices[v].Price.Fragments)
						)
					if (MeleeData[v] or 0) == 0 and hasEnoughEco then
	                    LogChange("melee_action", "melee: unlocking " .. string.lower(realName))
						if v == "Godhuman" then
							print("godhuman...")
							GetGodHuman()
						else
							GetMeleeLogics[v]()
						end
						return true
					elseif (MeleeData[v] or 0) == 0 and (MeleePrices[v].Price.Fragments and (LocalPlayer.Data.Fragments.Value < MeleePrices[v].Price.Fragments)) and CheckCanDungeon() then
						if (not World.Sea1()) and LocalPlayer.Data.Level.Value >= 1250 then
							AutoDungeon()
						end
					elseif (MeleeData[v] or 0) == 0 and not hasEnoughEco then
	                    LogChange("melee_wait", "melee: waiting for " .. string.lower(realName) .. " resources")
					elseif (MeleeData[v] or 0) > 0 and not Character:FindFirstChild(realName) and not LocalPlayer.Backpack:FindFirstChild(realName) then
						if not TweenToMeleeBuyer(v) then
							break
						end
						CommF_:InvokeServer("Buy" .. v)
					end
					return
				end
			end
		end
	end

	KEYS = require(ReplicatedStorage.ItemReplicationService.KEYS)
	IRS = require(ReplicatedStorage.ItemReplicationService)
	MATCH = require(ReplicatedStorage.ItemConfig.Storage).match
	local function GetUseableFruit()
		local data = IRS:GetItems(KEYS.QUANTITY)
		for _, v in data do
			local item = MATCH(v.ItemId)._ok
			if item.Display.Category == "Blox Fruit" and item.Quality.MoneyPrice < 1000000 then
				return item.Index.StorageKey
			end
		end
	end

	CheckCanDungeon = function()
		local res = CommF_:InvokeServer("RaidsNpc", "Select", "Dark")
		if HasItem("Special Microchip") then
			return true
		elseif GetUseableFruit() then
			return true
		elseif LocalPlayer.Data.Beli.Value >= 100000 and ((type(res) == "number" and res == 1) or (type(res) == "string" and not res:find("wait"))) then
			return true
		end
	end

	local RaidController = {
		isRaiding = false,
	}
	RaidController.RaidState_Connection = nil
	if World.Sea2() or World.Sea3() then
		if ReplicatedStorage.Remotes:FindFirstChild("Raids") then
			while not RaidController.RaidState_Connection do
				RaidController.RaidState_Connection = ReplicatedStorage.Remotes.Raids.OnClientEvent:Connect(function(a)
					if a == "StartTimer" then
						RaidController.isRaiding = true
					else
						RaidController.isRaiding = false
					end
				end)
				task.wait(0.5)
			end
		end
	end

	local function KillAura(distance)
		for _, v in workspace.Enemies:GetChildren() do
			if v:FindFirstChild("HumanoidRootPart") and v:FindFirstChildOfClass("Humanoid") then
				if LocalPlayer:DistanceFromCharacter(v.PrimaryPart.Position) <= distance then
					v.Humanoid:ChangeState(15)
				end
			end
		end
	end

	AutoDungeon = function()
	    LogChange("raid", "raid: preparing")
		local res = CommF_:InvokeServer("RaidsNpc", "Select", "Dark")
		while not Character or not Character.PrimaryPart do
			task.wait()
		end
		if not RaidController.isRaiding then
			if not (LocalPlayer.Backpack:FindFirstChild("Special Microchip") or Character:FindFirstChild("Special Microchip")) then
	            LogChange("raid_stage", "raid: getting microchip")
	            SetStatus("raid | getting microchip")
				if LocalPlayer.Data.Beli.Value >= 100000 and ((type(res) == "number" and res == 1) or (type(res) == "string" and not res:find("wait"))) then
					CommF_:InvokeServer("RaidsNpc", "Select", "Dark")
				else
					PAUSE_AUTO_STORE = true
					CommF_:InvokeServer("LoadFruit", GetUseableFruit())
					task.wait(0.5)
					CommF_:InvokeServer("RaidsNpc", "Select", "Dark")
					PAUSE_AUTO_STORE = false
				end
			end
			if World.Sea2() then
	            LogChange("raid_stage", "raid: summoning at sea 2")
	            SetStatus("raid | summoning at sea 2")
				local clickDetector = workspace.Map.CircleIsland.RaidSummon2:FindFirstChildWhichIsA("ClickDetector", true)
				if clickDetector then
					pcall(fireclickdetector, clickDetector)
				end
			elseif World.Sea3() then
	            LogChange("raid_stage", "raid: summoning at sea 3")
	            SetStatus("raid | summoning at sea 3")
				Tween(Vector3.new(-5018, 315, -2828), 300).Completed:Wait()
				task.wait(1)
				local clickDetector = workspace.Map["Boat Castle"].RaidSummon2:FindFirstChildWhichIsA("ClickDetector", true)
				if clickDetector then
					pcall(fireclickdetector, clickDetector)
				end
			end
			local startWait = tick()
	        LogChange("raid_state", "raid: waiting to join")
	        SetStatus("raid | waiting to join")
			repeat
				SetStatus("raid | waiting to join")
				StopTween()
				task.wait(0.25)
			until RaidController.isRaiding or (tick() - startWait) >= 30
	        LogChange("raid_state", RaidController.isRaiding and "raid: started" or "raid: join timed out")
	        SetStatus(RaidController.isRaiding and "raid | started" or "raid | join timed out")
			task.wait(0.5)
			while RaidController.isRaiding do
	            LogChange("raid_state", "raid: clearing island")
				SetStatus("raid | clearing island")
				for _, v in workspace.Enemies:GetChildren() do
					if v.PrimaryPart and v:FindFirstChildOfClass("Humanoid") and v:FindFirstChildOfClass("Humanoid").Health > 0 and LocalPlayer:DistanceFromCharacter(v.PrimaryPart.Position) <= 2000 then
						repeat
							task.wait()
							pcall(sethiddenproperty, LocalPlayer, "SimulationRadius", math.huge)
							pcall(function()
								Tween(v.PrimaryPart.Position + Vector3.new(0, 28, 15), 350)
								if LocalPlayer:DistanceFromCharacter(v.PrimaryPart.Position) <= 200 then
									Tween(v.PrimaryPart.Position + Vector3.new(0, 28, 15), math.huge)
									if LocalPlayer:DistanceFromCharacter(v.PrimaryPart.Position) <= 50 then
										EquipWeapon()
										Attack()
									end
								end
							end)
						until not v
							or not v.PrimaryPart
							or not v:FindFirstChildOfClass("Humanoid")
							or v:FindFirstChildOfClass("Humanoid").Health == 0
						break
					end
				end
				local found = false
				for i = 5, 1, -1 do
					for _, z in workspace["_WorldOrigin"].Locations:GetChildren() do
						if z.Name == ("Island " .. i) and LocalPlayer:DistanceFromCharacter( workspace["_WorldOrigin"].Locations["Island " .. i]:GetPivot().Position ) <= 6000 then
	                        LogChange("raid_island", "raid: moving to island " .. tostring(i))
	                        SetStatus("raid | moving to island " .. tostring(i))
							found = true
							Tween( workspace["_WorldOrigin"].Locations["Island " .. i]:GetPivot() * CFrame.new(100, 70, 100), 350 )
							task.wait(0.5)
							break
						end
					end
					if found then
						break
					end
				end
				task.wait()
			end
		end
		 task.wait(5)
	    LogChange("raid_state", "raid: cycle ended")
	end

	local function GetYama()
	    LogChange("yama", "yama: unlocking")
	    SetStatus("yama | unlocking")
		repeat
			fireclickdetector(workspace.Map.Waterfall.SealedKatana.Hitbox.ClickDetector)
			task.wait(0.5)
		until LocalPlayer.Backpack:FindFirstChild("Yama")
	end

	local function CheckTushita()
		return LocalPlayer.Data.Level.Value >= 2200
	end

	local function GetTushita()
	    LogChange("tushita", "tushita: checking progress")
		if not workspace.Map.Turtle:FindFirstChild("TushitaGate") then
	        LogChange("tushita_stage", "tushita: defeating longma")
	        SetStatus("tushita | defeating longma")
			if CheckMonster("Longma") then
				KillMonster("Longma")
			end
		elseif (function() for _, v in {workspace.Enemies, ReplicatedStorage} do for _, v2 in v:GetChildren() do if v2:IsA("Model") and v2:FindFirstChild("Humanoid") and v2.Humanoid.Health > 0 and v2.Name:find("indra") then
							return true
						end
					end
				end
			end)()
		then
			if not Character:FindFirstChild("Holy Torch") and not LocalPlayer.Backpack:FindFirstChild("Holy Torch") then
	            LogChange("tushita_stage", "tushita: collecting holy torch")
	            SetStatus("tushita | collecting holy torch")
				Tween(workspace.Map.Waterfall.SecretRoom.Room.Door.Door.Hitbox.CFrame, 350).Completed:Wait()
				task.wait(1)
			else
				for i = 1, 5, 1 do
	                LogChange("tushita_torch", "tushita: lighting torch " .. tostring(i) .. "/5")
	                SetStatus("tushita | lighting torch " .. tostring(i) .. "/5")
					EquipTool("Holy Torch")
					Tween(workspace.Map.Turtle.QuestTorches["Torch" .. tostring(i)].Particles.Main.Enabled, 350).Completed:Wait()
				end
			end
		end
	end

	local c = 0
	local function AutoChest()
		local m = workspace.Map:GetDescendants()
		local h = Character:FindFirstChild("Humanoid") or false
		for i = 1, #m do
			local v = m[i]
			if v:IsA("BasePart") and v.Name:find("Chest") and (v.Name:match("%d+") or v.Name:find("Frag")) and v.CanTouch then
				if (function() for _, v in {Character, LocalPlayer.Backpack} do for _, v2 in v:GetChildren() do if v2.Name == "God's Chalice" or v2.Name == "Fist of Darkness" or v2.Name == "Sweet Chalice" then
									return true
								end
							end
						end
						return false
					end)()
				then
					break
				end
				if c >= 10 then
					c = 0
					h.Health = 0
				else
					if Character.PrimaryPart and Character:FindFirstChildOfClass("Humanoid") then
						if Character.Humanoid.Health > 0 then
							Character:SetPrimaryPartCFrame(v.CFrame * CFrame.new(0, 2, 0))
							c = c + 1
						end
					end
				end
				task.wait(0.2)
			end
		end
	end

	local function CheckHakiLegendInTitles(NAME_HAKI)
		local res, kl = pcall(function()
			CommF_:InvokeServer("getTitles")
		end)
		if not res or not kl or typeof(kl) ~= "table" then
			return false
		end
		local gg = kl[NAME_HAKI]
		if not gg then
			return false
		end
		for _, v in kl do
			if v.Unlocked and v.Description and v.Description:find(gg) then
				return true
			end
		end
		return false
	end

	local function GetTitle(title)
		local a = CommF_:InvokeServer("getTitles") or {}
		for _, v in a do
			if v.InternalName == title and v.Name ~= "(LOCKED)" then
				return true
			end
		end
		return false
	end

	SWAN_KILLED = false
	if GetTitle("Heavenly Devil") then
		SWAN_KILLED = true
	end
	local function GetSwanKilled()
		return SWAN_KILLED
	end

	task.spawn(function()
		for _, v in {"EASTEREXP", "BANEXPLOIT", "NOMOREHACKS", "WildDares", "BossBuild", "GetPranked", "EARN_FRUITS", "Sub2UncleKizaru", "FIGHT4FRUIT", "kittgaming", "TRIPLEABUSE", "Sub2CaptainMaui", "Sub2Fer999", "Enyu_is_Pro", "Magicbus", "JCWK", "Starcodeheo", "Bluxxy", "SUB2GAMERROBOT_EXP1", "Sub2NoobMaster123", "Sub2Daigrock", "Axiore", "TantaiGaming", "StrawHatMaine", "Sub2OfficialNoobie", "TheGreatAce", "SEATROLLIN", "24NOADMIN", "ADMIN_TROLL", "NEWTROLL", "SECRET_ADMIN", "staffbattle", "NOEXPLOIT", "NOOB2ADMIN", "CODESLIDE", "fruitconcepts"} do
			ReplicatedStorage.Remotes.Redeem:InvokeServer(v)
		end
	end)

	task.spawn(function()
		while task.wait() do
			if LocalPlayer.Data.Points.Value > 0 then
				local Melee = LocalPlayer.Data.Stats.Melee.Level.Value
				local Defense = LocalPlayer.Data.Stats.Defense.Level.Value
				local Sword = LocalPlayer.Data.Stats.Sword.Level.Value
				CommF_:InvokeServer("AddPoint","Melee",LocalPlayer.Data.Level.Value * 2 - Melee)
				CommF_:InvokeServer("AddPoint","Defense",LocalPlayer.Data.Level.Value - Defense)
				if Melee == MaxLevel and Defense == MaxLevel then
					CommF_:InvokeServer("AddPoint","Sword",LocalPlayer.Data.Level.Value * 3 - MaxLevel * 2)
				end
			end
		end
	end)

	CAN_SPAWN_CAKE_PRINCE = true
	task.spawn(function()
		while World.Sea3() do
			if CAN_SPAWN_CAKE_PRINCE then
				CommF_:InvokeServer("CakePrinceSpawner")
			end
			if GetMaterial("Bones") >= 50 then
				CommF_:InvokeServer("Bones", "Buy", 1, 1)
			end
			task.wait(0.5)
		end
	end)

	print("initialized")
	task.spawn(function()
	    print("main loop started")
		while task.wait() do
			if MeleeKaitunLogic() then
				continue
			end
			if Config.CursedDualKatana and (function() local b = 0 for i in {"Tushita", "Yama"} do if CheckItem(i) then
							LoadItem(i, "Sword")
							for _, v in {LocalPlayer.Backpack, Character} do
								if v.Name == i and v.ToolTip == "Sword" and v.Level.Value >= 350 then
									b = b + 1
								end
							end
						end
					end
					return b
				end)() == 2
				and LocalPlayer.Data.Level.Value >= 2200
			then
	            LogChange("main_mode", "mode: cursed dual katana")
				GetCDKLogic()
			elseif Config.Saber and LocalPlayer.Data.Level.Value >= 200 and not CheckItem("Saber") then
	            LogChange("main_mode", "mode: saber")
				GetSaber()
			elseif World.Sea3() and ( (HasItem("Sweet Chalice") or HasItem("Sweet Chalice")) or (function() for _, v in {workspace.Enemies, ReplicatedStorage} do for _, v2 in v:GetChildren() do if v2.Name:find("indra") or v2.Name:find("Dough King") then
									return true
								end
							end
						end
						return false
					end)()
				)
			then
	            LogChange("main_mode", "mode: farm indra / dough king")
				if (function() for _, v in {workspace.Enemies, ReplicatedStorage} do for _, v2 in v:GetChildren() do if v2.Name:find("indra") or v2.Name:find("Dough King") then
									return true
								end
							end
						end
						return false
					end)()
				then
					for _, v in {workspace.Enemies, ReplicatedStorage} do
						for _, v2 in v:GetChildren() do
							if (v2.Name:find("indra") or v2.Name:find("Dough King")) and v2:FindFirstChildOfClass("Humanoid") then
								return KillMonster(v2.Name)
							end
						end
					end
				elseif HasItem("Sweet Chalice") then
					local msg = CommF_:InvokeServer("CakePrinceSpawner")
					if type(msg) == "string" and msg:find("defeat") then
						pcall(FarmKataLogic)
					end
				elseif HasItem("God's Chalice") then
					if (function() local b = 0 pcall(function() for _, v in workspace.Map["Boat Castle"].Summoner:GetChildren() do if v:IsA("Part") and v.Name == "Part" then
										if v.Color ~= Color3.fromRGB(99, 95, 98) then
											b = b + 1
										end
									end
								end
							end)
							return b
						end)() == 3
					then
						if not Character:FindFirstChild("God's Chalice") then
	                        LogChange("chalice_stage", "chalice: summoning boss")
	                        SetStatus("chalice | summoning boss")
							EquipTool("God's Chalice")
						end
						pcall(firetouchinterest, workspace.Map["Boat Castle"].Summoner.Detection, Character.PrimaryPart)
					else
						if GetMaterial("Conjured Cocoa") >= 10 then
							CommF_:InvokeServer("SweetChaliceNpc")
						else
							pcall(FarmMaterial, "Conjured Cocoa")
						end
					end
				end
			elseif LocalPlayer.Data.Level.Value >= 850 and not CheckItem("Warrior Helmet") then
	            LogChange("main_mode", "mode: bartilo quest")
				DoBartiloQuest()
			elseif Config.RaceV3 and LocalPlayer.Data.Level.Value >= 850 and LocalPlayer.Data.Beli.Value >= 500000 and GetRaceGrade() == "V1" and CheckItem("Warrior Helmet") then
	            LogChange("main_mode", "mode: race v2")
				DoRaceV2()
			elseif Config.RaceV3 and (LocalPlayer.Data.Level.Value >= 1000) and (LocalPlayer.Data.Beli.Value >= 2000000) and GetRaceGrade() == "V2" and GetSwanKilled() then
	            LogChange("main_mode", "mode: race v3")
				DoRaceV3()
			elseif Config.CursedDualKatana and World.Sea3() and GetElite() then
	            LogChange("main_mode", "mode: farm elite")
				pcall(function()
					for _, v2 in {workspace.Enemies, ReplicatedStorage} do
						for _, v in v2:GetChildren() do
							if v:IsA("Model") and v:GetAttribute("Level") and v:FindFirstChild("Humanoid") and v.Humanoid.Health > 0 then
								if table.find({"Tyrant of the Skies", "Diablo", "Urban", "Deandre"}, v.Name) then
									if QuestController.CurrentQuest:find(v.Name) then
										return KillMonster(v.Name)
									else
										CommF_:InvokeServer("EliteHunter")
									end
								end
							end
						end
					end
				end)
			elseif Config.SkullGuitar and LocalPlayer.Data.Level.Value >= 2300 then
	            LogChange("main_mode", "mode: skull guitar")
				GetSG()
			elseif World.Sea3() and GetCastleRaid() and false then
				SetStatus("farm castle raid")
				if LocalPlayer:DistanceFromCharacter(Vector3.new(-5000, 350, -3035)) > 700 then
					CommF_:InvokeServer("requestEntrance", Vector3.new(-5000, 350, -3035))
				end
				for _, v in workspace.Enemies:GetChildren() do
					if v.PrimaryPart and v:FindFirstChild("Humanoid") and LocalPlayer:DistanceFromCharacter(v.WorldPivot.Position) <= 700 then
						repeat
							task.wait()
							EquipWeapon()
							Tween(v:GetPivot() * CFrame.new(0, 20, 10), 350)
							Attack()
						until not v or not v.PrimaryPart or not v:FindFirstChild("Humanoid") or v.Humanoid.Health <= 0
					end
					break
				end
			elseif World.Sea2() and workspace.Enemies:FindFirstChild("Factory") and false then
				SetStatus("farm factory")
				local coreEnemy = workspace.Enemies:FindFirstChild("Core")
				if coreEnemy and coreEnemy.Humanoid.Health > 0 then
					repeat
						task.wait()
						EquipWeapon()
						Tween(coreEnemy.HumanoidRootPart.CFrame, 300)
						Attack()
					until coreEnemy.Humanoid.Health <= 0
				end
			elseif Config.CursedDualKatana and CheckYama() >= 30 and not CheckItem("Yama") then
	            LogChange("main_mode", "mode: get yama")
				SetStatus("yama | unlocking")
				GetYama()
			elseif Config.CursedDualKatana and World.Sea3() and not CheckItem("Tushita") and CheckMonster("rip_indra") then
	            LogChange("main_mode", "mode: get tushita")

				GetTushita()
			elseif LocalPlayer.Data.Level.Value >= 700 and World.Sea1() then
	            LogChange("main_mode", "mode: unlock second sea")
				UnlockSecondSea()
			elseif LocalPlayer.Data.Level.Value >= 1500 and World.Sea2() then
	            LogChange("main_mode", "mode: unlock third sea")
				UnlockThirdSea()
			elseif World.Sea2() and CheckMonster("Darkbeard") then
				KillMonster("Darkbeard")
			else
	            LogChange("main_mode", "mode: farm level")
	            if not title.Text:find("^farm |") then
	                SetStatus("farm level | level " .. tostring(LocalPlayer.Data.Level.Value))
	            end
				if World.Sea2() then
					if HasItem("Hidden Key") and not CheckItem("Rengoku") then
						EquipTool("Hidden Key")
						Tween(CFrame.new(6571, 298, -6967), 300).Completed:Wait()
						task.wait(1)
					elseif HasItem("Library Key") and workspace.Map.IceCastle.Hall.LibraryDoor.PhoeyuDoor.Transparency == 0 then
						CommF_:InvokeServer("OpenLibrary")
						task.wait(1)
					elseif HasItem("Water Key") and CommF_:InvokeServer("BuySharkmanKarate", true):find("lost") then
						if TweenToMeleeBuyer("SharkmanKarate") then
							CommF_:InvokeServer("BuySharkmanKarate", true)
							CommF_:InvokeServer("BuySharkmanKarate")
						end
					end
				elseif World.Sea3() then
					if HasItem("Fire Essence") and CommF_:InvokeServer("BuyDragonTalon", true):find("your") then
						if TweenToMeleeBuyer("DragonTalon") then
							CommF_:InvokeServer("BuyDragonTalon", true)
							CommF_:InvokeServer("BuyDragonTalon")
						end
					end
				end
				if LocalPlayer.Data.Level.Value == MaxLevel then
					pcall(FarmKataLogic)
				else
					pcall(FarmLevelLogic)
				end
			end
		end
	end)
end
local function KaitunClassic()
	if not game:IsLoaded() then
	    game.Loaded:Wait()
	end
	if not game.Players.LocalPlayer.Team then
		repeat task.wait()
			game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("SetTeam",getgenv().Configs.Team)
		until game.Players.LocalPlayer.Team
	end
	repeat wait() until game.Players.LocalPlayer.Character
	local v106 = tostring(game.Players.LocalPlayer.UserId):sub(2, 4) .. tostring(coroutine.running()):sub(11, 15)
	local placeid = game.PlaceId
	local AttackRotation = 0
	local LastRotate = 0

	local TweenService = game:GetService("TweenService")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Players = game:GetService("Players")
	local CollectionService = game:GetService("CollectionService")
	local LocalPlayer = Players.LocalPlayer
	local CommF_ = game:GetService("ReplicatedStorage").Remotes.CommF_

	local MaxLevel = game:GetAttribute("LEVEL_CAP") or 2800
	local IsSaber = false
	local IsPoleV1 = false
	local IsPoleV2 = false
	local Entrance = {}

	local function TeleportServer(cursor)
	    cursor = cursor or ""
	    local placeId = game.PlaceId
	    local data = game:GetService("HttpService"):JSONDecode(game:HttpGet(string.format("https://games.roblox.com/v1/games/%s/servers/Public?sortOrder=Asc&limit=100&cursor=%s",tostring(placeId),tostring(cursor))))
	    if not data.data or #data.data == 0 then
	        return false, ""
	    end
	    local chosenJobId = nil
	    for _, server in ipairs(data.data) do
	        if server.playing < server.maxPlayers then
	            chosenJobId = server.id
	            break
	        end
	    end
	    if not chosenJobId and data.nextPageCursor then
	        return TeleportServer(data.nextPageCursor)
	    elseif not chosenJobId then
	        return false, ""
	    end
	    local res = ReplicatedStorage.__ServerBrowser:InvokeServer("teleport",chosenJobId)
	    return true, res
	end
	local IsTweening = false
	local function Tween(target, speed)
		speed = 325
	    local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
	    local hrp = character:FindFirstChild("HumanoidRootPart")
	    if not hrp then return nil end
	    local closestEntrance = nil
	    local minEntranceDist = math.huge
	    for _, entrancePos in ipairs(Entrance) do
	        local dist = (entrancePos - target.Position).Magnitude
	        if dist < minEntranceDist then
	            minEntranceDist = dist
	            closestEntrance = entrancePos
	        end
	    end
	    if not hrp:FindFirstChild("fixvelo") then
	        local fixvelo = Instance.new("BodyVelocity")
	        fixvelo.Name = "fixvelo"
	        fixvelo.MaxForce = Vector3.new(0, 100000, 0)
	        fixvelo.Velocity = Vector3.zero
	        fixvelo.Parent = hrp
	    end
		IsTweening = true
	    if closestEntrance and minEntranceDist < (hrp.Position - target.Position).Magnitude then
	        CommF_:InvokeServer("requestEntrance", closestEntrance)
	    end
	    local distance = (hrp.Position - target.Position).Magnitude
	    local tweenInfo = TweenInfo.new(distance / speed, Enum.EasingStyle.Linear)
	    local tween = TweenService:Create(hrp, tweenInfo, {CFrame = target})
	    tween:Play()
		task.spawn(function()
			while tween.PlaybackState == Enum.PlaybackState.Playing do
				IsTweening = true
				task.wait()
			end
			IsTweening = false
		end)
	    return tween
	end
	local r = nil
	task.spawn(function()
		while task.wait() do
			local paths = {ReplicatedStorage.Util,ReplicatedStorage.Remotes,ReplicatedStorage.Assets,ReplicatedStorage.Common,ReplicatedStorage.FX}
			for _, v in paths do
				for _, v1 in v:GetChildren() do
					if v1:GetAttribute("Id") and v1:IsA("RemoteEvent") then
						r = v1
						break
					end
				end
			end
		end
	end)
	local seed = ReplicatedStorage.Modules.Net.seed:InvokeServer() * 2
	local LastAttackTime = 0
	local function IsOwn(name)
		if LocalPlayer.Backpack:FindFirstChild(name) then
			return LocalPlayer.Backpack:FindFirstChild(name)
		end
		local k
		for _,v in LocalPlayer.Character:GetChildren() do
			if v:IsA("Tool") then
				if v.Name == name then
					k = v
				end
			end
		end
		return k or LocalPlayer.Character:FindFirstChild(name)
	end
	local function Attack(v)
		if tick() - LastAttackTime >= 0.2 then
			if not LocalPlayer.Character:FindFirstChild("HasBuso") then
				CommF_:InvokeServer("Buso")
			end
			local h = "RE/RegisterHit"
			local key = math.floor(workspace:GetServerTimeNow() / 10 % 10)
			local encoded = ""
			for i = 1, #h do
				encoded = encoded .. string.char(bit32.bxor(string.byte(h, i), key + 1))
			end
			if LocalPlayer.PlayerGui.Main.Skills:FindFirstChild("Black Leg") or LocalPlayer.PlayerGui.Main.Skills:FindFirstChild("Death Step") then
				if LocalPlayer.PlayerGui.Main.Skills:FindFirstChild("Black Leg") then
					if LocalPlayer.PlayerGui.Main.Skills["Black Leg"]:FindFirstChild("V") and IsOwn("Black Leg").Level.Value >= 150 then
						if LocalPlayer.PlayerGui.Main.Skills["Black Leg"].V.Cooldown.AbsoluteSize.X <= 0.1 then
							game:GetService("VirtualInputManager"):SendKeyEvent(true, "V", false, game)
							game:GetService("VirtualInputManager"):SendKeyEvent(false, "V", false, game)
							task.wait(1)
						end
					end
				elseif LocalPlayer.PlayerGui.Main.Skills:FindFirstChild("Death Step") then
					if LocalPlayer.PlayerGui.Main.Skills["Death Step"]:FindFirstChild("V") and IsOwn("Black Leg").Level.Value >= 400 then
						if LocalPlayer.PlayerGui.Main.Skills["Death Step"].V.Cooldown.AbsoluteSize.X <= 0.1 then
							game:GetService("VirtualInputManager"):SendKeyEvent(true, "V", false, game)
							game:GetService("VirtualInputManager"):SendKeyEvent(false, "V", false, game)
							task.wait(1)
						end
					end
				end
			end
		end
	    if type(v) == "table" then
	        ReplicatedStorage.Modules.Net["RE/RegisterAttack"]:FireServer(0)
	        r:FireServer(encoded,bit32.bxor(r:GetAttribute("Id")+909090,seed),
	            v[1]:FindFirstChild("Head"),
	            {
	                { v[1], v[1]:FindFirstChild("Head") },
	                v[1],
	                { v[2], v[2]:FindFirstChild("Head") },
	                v[2]
	            },
	            nil,
	            v106
	        )
	        ReplicatedStorage.Modules.Net["RE/RegisterHit"]:FireServer(
	            v[1]:FindFirstChild("Head"),
	            {
	                { v[1], v[1]:FindFirstChild("Head") },
	                v[1],
	                { v[2], v[2]:FindFirstChild("Head") },
	                v[2]
	            },
	            nil,
	            v106
	        )
	    else
	        ReplicatedStorage.Modules.Net["RE/RegisterAttack"]:FireServer(0)
	        r:FireServer(encoded,bit32.bxor(r:GetAttribute("Id")+909090,seed),v:FindFirstChild("Head"),{v,v:FindFirstChild("Head")},v106)
	        ReplicatedStorage.Modules.Net["RE/RegisterHit"]:FireServer(v:FindFirstChild("Head"),{v,v:FindFirstChild("Head")},v106)
	    end
		LastAttackTime = tick()
	end
	local function DieWait()
	    if LocalPlayer.Character:WaitForChild("Humanoid").Health == 0 or not LocalPlayer.Character:FindFirstChild("Head") then
	        repeat
	            task.wait()
	        until LocalPlayer.Character:WaitForChild("Humanoid").Health > 0
	        if not LocalPlayer.Character:FindFirstChild("HasBuso") then
	            CommF_:InvokeServer("Buso")
	        end
	    end
	end
	local function EquipWeapon(type)
	    local SixSeven = ""
		for i ,v in pairs(LocalPlayer.Backpack:GetChildren()) do
			if v:IsA("Tool") then
				if v.ToolTip == type then
					SixSeven = v.Name
				end
			end
		end
		for i ,v in pairs(LocalPlayer.Character:GetChildren()) do
			if v:IsA("Tool") then
				if v.ToolTip == type then
					SixSeven = v.Name
				end
			end
		end
		if LocalPlayer.Backpack:FindFirstChild(SixSeven) then
			local tool = LocalPlayer.Backpack:FindFirstChild(SixSeven)
			task.wait()
			LocalPlayer.Character.Humanoid:EquipTool(tool)
		end
	end
	local function EquipName(toolName)
	    local character = LocalPlayer.Character
	    local tool = character:FindFirstChild(toolName) or LocalPlayer.Backpack:FindFirstChild(toolName)
	    if not tool then return end
	    character.Humanoid:EquipTool(tool)
	end
	local function CheckInv()
	    local inv = CommF_:InvokeServer("getInventory")
	    if type(inv) == "table" then
	        for _,v in pairs(inv) do
	            if type(v) == "table" then
	                if v.Name == "Saber" and not IsSaber then
	                    IsSaber = true
	                end
	                if v.Name == "Pole (1st Form)" and not IsPoleV1 then
	                    IsPoleV1 = true
	                end
	                if v.Name == "Pole (2nd Form)" and not IsPoleV2 then
	                    IsPoleV2 = true
	                end
	            end
	        end
	    end
	end
	local function BringMob(a)
	    pcall(sethiddenproperty,LocalPlayer,"SimulationRadius",math.huge)
	    local aname = a.Name
	    local acf = a.HumanoidRootPart.CFrame
	    local targets = {}
	    table.insert(targets, {a, a:FindFirstChild("Head")})
	    for _, v in ipairs(workspace.Enemies:GetChildren()) do
	        if string.find(v.Name:lower(), aname:lower(), 1, true) and not v:FindFirstChild("BringCheck") and v:FindFirstChild("Humanoid") and v:FindFirstChild("HumanoidRootPart") and v.Humanoid.Health > 0 and (acf.Position - v.HumanoidRootPart.Position).Magnitude <= 350 then
	            local bv = v.HumanoidRootPart:FindFirstChild("BringVelocity")
	            if not bv then
	                bv = Instance.new("BodyVelocity")
	                bv.Name = "BringVelocity"
	                bv.MaxForce = Vector3.new(10000, 10000, 10000)
	                bv.Parent = v.HumanoidRootPart
	            end
	            bv.Velocity = Vector3.zero
	            v.HumanoidRootPart.CFrame = acf
	            table.insert(targets, {v, v:FindFirstChild("Head")})
	            break
	        end
	    end
	    return targets
	end

	local ScreenGui = Instance.new("ScreenGui")
	ScreenGui.ResetOnSpawn = false
	ScreenGui.Parent = game.CoreGui
	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(0, 500, 0, 75)
	frame.Position = UDim2.new(0.5, -250, 0, 30)
	frame.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	frame.BackgroundTransparency = 0.2
	frame.Parent = ScreenGui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = frame
	local edge = Instance.new("UIStroke")
	edge.Color = Color3.fromRGB(0, 0, 0)
	edge.Thickness = 3.5
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edge.Parent = frame
	local layout = Instance.new("UIListLayout")
	layout.Parent = frame
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 5)
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -20, 0, 40)
	title.BackgroundTransparency = 1
	title.Text = "Idling"
	title.Font = Enum.Font.GothamBold
	title.TextScaled = false
	title.TextSize = 22
	title.TextColor3 = Color3.fromRGB(200, 200, 200)
	title.LayoutOrder = 1
	title.Parent = frame
	local subtitle = Instance.new("TextLabel")
	subtitle.Size = UDim2.new(1, -20, 0, 30)
	subtitle.BackgroundTransparency = 1
	subtitle.Text = "No Subtask"
	subtitle.Font = Enum.Font.GothamSemibold
	subtitle.TextScaled = false
	subtitle.TextSize = 20
	subtitle.TextColor3 = Color3.fromRGB(200, 200, 200)
	subtitle.LayoutOrder = 2
	subtitle.Parent = frame
	local TimeL = Instance.new("TextLabel")
	TimeL.Size = UDim2.new(0, 500, 0, 30)
	TimeL.Position = UDim2.new(0.5, -250, 0, 0)
	TimeL.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	TimeL.BackgroundTransparency = 0.2
	TimeL.Text = ""
	TimeL.Font = Enum.Font.GothamBold
	TimeL.TextScaled = false
	TimeL.TextSize = 20
	TimeL.TextColor3 = Color3.fromRGB(200, 200, 200)
	TimeL.Parent = ScreenGui
	local TimeC = Instance.new("UICorner")
	TimeC.CornerRadius = UDim.new(0, 10)
	TimeC.Parent = TimeL
	local TimeS = Instance.new("UIStroke")
	TimeS.Color = Color3.fromRGB(0, 0, 0)
	TimeS.Thickness = 3.5
	TimeS.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	TimeS.Parent = TimeL
	task.spawn(function()
	    while task.wait(1) do
			local t = os.date("*t")
	        TimeL.Text = string.format("%02d:%02d:%02d  |  %s, %s %d, %d",t.hour,t.min,t.sec,os.date("%A"),os.date("%B"),t.day,t.year)
	    end
	end)
	local LevelQuest
	local Monster
	local NameQuest
	local NameCheckQuest
	local CFrameQ
	local CFrameMon
	if not identifyexecutor() == "Solara" then require(ReplicatedStorage.Util.CameraShaker):Stop() end
	local World1 = false
	local World2 = false
	local World3 = false
	if placeid == 2753915549 then
	    World1 = true
		Entrance = {
			Vector3.new(61163.8515625, 11.6796875, 1819.7841796875),
			Vector3.new(3864.8515625, 6.6796875, -1926.7841796875),
			Vector3.new(-4607.8227539063, 872.54248046875, -1667.5568847656),
			Vector3.new(-7894.6176757813, 5547.1416015625, -380.29119873047),
		}
	elseif placeid == 79091703265657 then
	    World2 = true
		Entrance = {
			Vector3.new(923.21252441406, 126.9760055542, 32852.83203125),
			Vector3.new(-6508.5581054688, 89.034996032715, -132.83953857422),
			Vector3.new(2284,15,905),
			Vector3.new(-286.98907470703125, 306.1379089355469, 597.8827514648438),
		}
	elseif placeid == 7449423635 then
	    World3 = true
	end
	local function GetWorld()
	    if World1 then
	        return 1
	    elseif World2 then
	        return 2
	    elseif World3 then
	        return 3
	    else
	        return 0
	    end
	end
	local function CheckQuest()
	    local Level = LocalPlayer.Data.Level.Value
	    if World1 then
			if Level == 1 or Level <= 9 then
				Monster = "Bandit"
				NameQuest = "BanditQuest1"
	            LevelQuest = 1
				NameCheckQuest = "Bandit"
				CFrameQ = CFrame.new(1060, 17, 1547)
				CFrameMon = CFrame.new(1145, 17, 1634)
	        elseif Level == 10 or Level <= 14 then
				Monster = "Monkey"
				NameQuest = "JungleQuest"
	            LevelQuest = 1
				NameCheckQuest = "Monkey"
				CFrameQ = CFrame.new(-1602, 37, 152)
				CFrameMon = CFrame.new(-1496, 39, 35)
			elseif Level == 15 or Level <= 29 then
				Monster = "Gorilla"
				NameQuest = "JungleQuest"
				LevelQuest = 2
				NameCheckQuest = "Gorilla"
				CFrameQ = CFrame.new(-1602, 37, 152)
				CFrameMon = CFrame.new(-1237, 6, -486)
			elseif Level == 30 or Level <= 39 then
				Monster = "Pirate"
				NameQuest = "BuggyQuest1"
				LevelQuest = 1
				NameCheckQuest = "Pirate"
				CFrameQ = CFrame.new(-1140, 5, 3828)
				CFrameMon = CFrame.new(-1115, 14, 3938)
			elseif Level == 40 or Level <= 59 then
				Monster = "Brute"
				NameQuest = "BuggyQuest1"
				LevelQuest = 2
				NameCheckQuest = "Brute"
				CFrameQ = CFrame.new(-1140, 5, 3828)
				CFrameMon = CFrame.new(-1145, 15, 4350)
			elseif Level == 60 or Level <= 74 then
				Monster = "Desert Bandit"
				NameQuest = "DesertQuest"
				LevelQuest = 1
				NameCheckQuest = "Desert Bandit"
				CFrameQ = CFrame.new(897, 7, 4388)
				CFrameMon = CFrame.new(932, 7, 4484)
			elseif Level == 75 or Level <= 89 then
				Monster = "Desert Officer"
				NameQuest = "DesertQuest"
				LevelQuest = 2
				NameCheckQuest = "Desert Officers"
				CFrameQ = CFrame.new(897, 7, 4388)
				CFrameMon = CFrame.new(1572, 10, 4373)
			elseif Level == 90 or Level <= 99 then
				Monster = "Snow Bandit"
				NameQuest = "SnowQuest"
				LevelQuest = 1
				NameCheckQuest = "Snow Bandits"
				CFrameQ = CFrame.new(1386, 87, -1297)
				CFrameMon = CFrame.new(1289, 150, -1442)
			elseif Level == 100 or Level <= 119 then
				Monster = "Snowman"
				NameQuest = "SnowQuest"
				LevelQuest = 2
				NameCheckQuest = "Snowman"
				CFrameMon = CFrame.new(1289, 150, -1442)
				CFrameQ = CFrame.new(1386, 87, -1297)
			elseif Level == 120 or Level <= 149 then
				Monster = "Chief Petty Officer"
				NameQuest = "MarineQuest2"
				LevelQuest = 1
				NameCheckQuest = "Chief Petty Officer"
				CFrameMon = CFrame.new(-4855, 23, 4308)
				CFrameQ = CFrame.new(-5036, 29, 4325)
			elseif Level == 150 or Level <= 174 then
				Monster = "Sky Bandit"
				NameQuest = "SkyQuest"
				LevelQuest = 1
				NameCheckQuest = "Sky Bandit"
				CFrameMon = CFrame.new(-4981, 278, -2830)
				CFrameQ = CFrame.new(-4842, 718, -2623)
			elseif Level == 175 or Level <= 189 then
				Monster = "Dark Master"
				NameQuest = "SkyQuest"
				LevelQuest = 2
				NameCheckQuest = "Dark Master"
				CFrameMon = CFrame.new(-5250, 389, -2272)
				CFrameQ = CFrame.new(-4842, 718, -2623)
			elseif Level == 190 or Level <= 209 then
				Monster = "Prisoner"
				NameQuest = "PrisonerQuest"
				LevelQuest = 1
				NameCheckQuest = "Prisoners"
				CFrameMon = CFrame.new(5411, 96, 690)
				CFrameQ = CFrame.new(5308, 2, 474)
			elseif Level == 210 or Level <= 249 then
				Monster = "Dangerous Prisoner"
				NameQuest = "PrisonerQuest"
				LevelQuest = 2
				NameCheckQuest = "Dangerous Prisoner"
				CFrameMon = CFrame.new(5411, 96, 690)
				CFrameQ = CFrame.new(5308, 2, 474)
			elseif Level == 250 or Level <= 299 then
				Monster = "Toga Warrior"
				NameQuest = "ColosseumQuest"
				LevelQuest = 1
				NameCheckQuest = "Toga Warrior"
				CFrameMon = CFrame.new(-1641.4344482421875, 7.415142059326172, -2864.462646484375)
				CFrameQ = CFrame.new(-1576, 8, -2985)

			elseif Level == 300 or Level <= 329 then
				Monster = "Military Soldier"
				NameQuest = "MagmaQuest"
				LevelQuest = 1
				NameCheckQuest = "Military Soldier"
				CFrameMon = CFrame.new(-5408, 11, 8447)
				CFrameQ = CFrame.new(-5316, 12, 8517)
			elseif Level == 330 or Level <= 374 then
				Monster = "Military Spy"
				NameQuest = "MagmaQuest"
				LevelQuest = 2
				NameCheckQuest = "Military Spy"
				CFrameMon = CFrame.new(-5815, 84, 8820)
				CFrameQ = CFrame.new(-5316, 12, 8517)
			elseif Level == 375 or Level <= 399 then
				Monster = "Fishman Warrior"
				NameQuest = "FishmanQuest"
				LevelQuest = 1
				NameCheckQuest = "Fishman Warrior"
				CFrameMon = CFrame.new(60859, 19, 1501)
				CFrameQ = CFrame.new(61123, 19, 1569)
			elseif Level == 400 or Level <= 449 then
				Monster = "Fishman Commando"
				NameQuest = "FishmanQuest"
				LevelQuest = 2
				NameCheckQuest = "Fishman Commando"
				CFrameMon = CFrame.new(61891, 19, 1470)
				CFrameQ = CFrame.new(61123, 19, 1569)
			elseif Level == 450 or Level <= 474 then
				Monster = "God's Guard"
				NameQuest = "SkyExp1Quest"
				LevelQuest = 1
				NameCheckQuest = "God's Guards"
				CFrameMon = CFrame.new(-4698, 845, -1912)
				CFrameQ = CFrame.new(-4722, 845, -1954)
			elseif Level == 475 or Level <= 524 then
				Monster = "Shanda"
				NameQuest = "SkyExp1Quest"
				LevelQuest = 2
				NameCheckQuest = "Shandas"
				CFrameMon = CFrame.new(-7685, 5567, -502)
				CFrameQ = CFrame.new(-7862, 5546, -380)
			elseif Level == 525 or Level <= 549 then
				Monster = "Royal Squad"
				NameQuest = "SkyExp2Quest"
				LevelQuest = 1
				NameCheckQuest = "Royal Squad"
				CFrameMon = CFrame.new(-7670, 5607, -1460)
				CFrameQ = CFrame.new(-7904, 5636, -1412)
			elseif Level == 550 or Level <= 624 then
				Monster = "Royal Soldier"
				NameQuest = "SkyExp2Quest"
				LevelQuest = 2
				NameCheckQuest = "Royal Soldier"
				CFrameMon = CFrame.new(-7828, 5607, -1744)
				CFrameQ = CFrame.new(-7904, 5636, -1412)
			elseif Level == 625 or Level <= 649 then
				Monster = "Galley Pirate"
				NameQuest = "FountainQuest"
				LevelQuest = 1
				NameCheckQuest = "Galley Pirate"
				CFrameMon = CFrame.new(5589, 45, 3996)
				CFrameQ = CFrame.new(5256, 39, 4050)
			elseif Level >= 650 then
				Monster = "Galley Captain"
				NameQuest = "FountainQuest"
				LevelQuest = 2
				NameCheckQuest = "Galley Captain"
				CFrameMon = CFrame.new(5649, 39, 4936)
				CFrameQ = CFrame.new(5256, 39, 4050)
	        end
		end
	    if World2 then
			if Level == 700 or Level <= 724 then
				Monster = "Raider"
				NameQuest = "Area1Quest"
				LevelQuest = 1
				NameCheckQuest = "Raider"
				CFrameQ = CFrame.new(-425, 73, 1837)
				CFrameMon = CFrame.new(-746, 39, 2390)
			elseif Level == 725 or Level <= 774 then
				Monster = "Mercenary"
				NameQuest = "Area1Quest"
				LevelQuest = 2
				NameCheckQuest = "Mercenary"
				CFrameQ = CFrame.new(-425, 73, 1837)
				CFrameMon = CFrame.new(-874, 141, 1312)
			elseif Level == 775 or Level <= 799 then
				Monster = "Swan Pirate"
				NameQuest = "Area2Quest"
				LevelQuest = 1
				NameCheckQuest = "Swan Pirate"
				CFrameQ = CFrame.new(634, 73, 918)
				CFrameMon = CFrame.new(878, 122, 1235)
			elseif Level == 800 or Level <= 874 then
				Monster = "Factory Staff"
				NameQuest = "Area2Quest"
				LevelQuest = 2
				NameCheckQuest = "Factory Staff"
				CFrameQ = CFrame.new(634, 73, 918)
				CFrameMon = CFrame.new(295, 73, -56)
			elseif Level == 875 or Level <= 899 then
				Monster = "Marine Lieutenant"
				NameQuest = "MarineQuest3"
				LevelQuest = 1
				NameCheckQuest = "Marine Lieutenant"
				CFrameMon = CFrame.new(-2806, 73, -3038)
				CFrameQ = CFrame.new(-2443, 73, -3219)
			elseif Level == 900 or Level <= 949 then
				Monster = "Marine Captain"
				NameQuest = "MarineQuest3"
				LevelQuest = 2
				NameCheckQuest = "Marine Captain"
				CFrameMon = CFrame.new(-1869, 73, -3320)
				CFrameQ = CFrame.new(-2443, 73, -3219)
			elseif Level == 950 or Level <= 974 then
				Monster = "Zombie"
				NameQuest = "ZombieQuest"
				LevelQuest = 1
				NameCheckQuest = "Zombie"
				CFrameMon = CFrame.new(-5736, 126, -728)
				CFrameQ = CFrame.new(-5494, 49, -795)
			elseif Level == 975 or Level <= 999 then
				Monster = "Vampire"
				NameQuest = "ZombieQuest"
				LevelQuest = 2
				NameCheckQuest = "Vampire"
				CFrameMon = CFrame.new(-6033, 7, -1317)
				CFrameQ = CFrame.new(-5494, 49, -795)
			elseif Level == 1000 or Level <= 1049 then
				Monster = "Snow Trooper"
				NameQuest = "SnowMountainQuest"
				LevelQuest = 1
				NameCheckQuest = "Snow Trooper"
				CFrameMon = CFrame.new(478, 402, -5362)
				CFrameQ = CFrame.new(605, 402, -5371)
			elseif Level == 1050 or Level <= 1099 then
				Monster = "Winter Warrior"
				NameQuest = "SnowMountainQuest"
				LevelQuest = 2
				NameCheckQuest = "Winter Warrior"
				CFrameMon = CFrame.new(1157, 430, -5188)
				CFrameQ = CFrame.new(605, 402, -5371)
			elseif Level == 1100 or Level <= 1124 then
				Monster = "Lab Subordinate"
				NameQuest = "IceSideQuest"
				LevelQuest = 1
				NameCheckQuest = "Lab Subordinate"
				CFrameMon = CFrame.new(-5782, 42, -4484)
				CFrameQ = CFrame.new(-6060, 16, -4905)
			elseif Level == 1125 or Level <= 1174 then
				Monster = "Horned Warrior"
				NameQuest = "IceSideQuest"
				LevelQuest = 2
				NameCheckQuest = "Horned Warrior"
				CFrameMon = CFrame.new(-6406, 24, -5805)
				CFrameQ = CFrame.new(-6060, 16, -4905)
			elseif Level == 1175 or Level <= 1199 then
				Monster = "Magma Ninja"
				NameQuest = "FireSideQuest"
				LevelQuest = 1
				NameCheckQuest = "Magma Ninja"
				CFrameMon = CFrame.new(-5428, 78, -5959)
				CFrameQ = CFrame.new(-5430, 16, -5295)
			elseif Level == 1200 or Level <= 1249 then
				Monster = "Lava Pirate"
				NameQuest = "FireSideQuest"
				LevelQuest = 2
				NameCheckQuest = "Lava Pirate"
				CFrameMon = CFrame.new(-5270, 42, -4800)
				CFrameQ = CFrame.new(-5430, 16, -5295)
			elseif Level == 1250 or Level <= 1274 then
				Monster = "Ship Deckhand"
				NameQuest = "ShipQuest1"
				LevelQuest = 1
				NameCheckQuest = "Ship Deckhand"
				CFrameMon = CFrame.new(1198, 126, 33031)
				CFrameQ = CFrame.new(1038, 125, 32913)
			elseif Level == 1275 or Level <= 1299 then
				Monster = "Ship Engineer"
				NameQuest = "ShipQuest1"
				LevelQuest = 2
				NameCheckQuest = "Ship Engineer"
				CFrameMon = CFrame.new(918, 44, 32787)
				CFrameQ = CFrame.new(1038, 125, 32913)
			elseif Level == 1300 or Level <= 1324 then
				Monster = "Ship Steward"
				NameQuest = "ShipQuest2"
				LevelQuest = 1
				NameCheckQuest = "Ship Steward"
				CFrameMon = CFrame.new(915, 130, 33419)
				CFrameQ = CFrame.new(969, 125, 33245)
			elseif Level == 1325 or Level <= 1349 then
				Monster = "Ship Officer"
				NameQuest = "ShipQuest2"
				LevelQuest = 2
				NameCheckQuest = "Ship Officer"
				CFrameMon = CFrame.new(916, 181, 33335)
				CFrameQ = CFrame.new(969, 125, 33245)
			elseif Level == 1350 or Level <= 1374 then
				Monster = "Arctic Warrior"
				NameQuest = "FrostQuest"
				LevelQuest = 1
				NameCheckQuest = "Arctic Warrior"
				CFrameMon = CFrame.new(6038, 29, -6231)
				CFrameQ = CFrame.new(5669, 28, -6482)
			elseif Level == 1375 or Level <= 1424 then
				Monster = "Snow Lurker"
				NameQuest = "FrostQuest"
				LevelQuest = 2
				NameCheckQuest = "Snow Lurker"
				CFrameMon = CFrame.new(5560, 42, -6826)
				CFrameQ = CFrame.new(5669, 28, -6482)
			elseif Level == 1425 or Level <= 1449 then
				Monster = "Sea Soldier"
				NameQuest = "ForgottenQuest"
				LevelQuest = 1
				NameCheckQuest = "Sea Soldier"
				CFrameMon = CFrame.new(-3022, 16, -9722)
				CFrameQ = CFrame.new(-3054, 237, -10148)
			elseif Level >= 1450 then
				Monster = "Water Fighter"
				NameQuest = "ForgottenQuest"
				LevelQuest = 2
				NameCheckQuest = "Water Fighter"
				CFrameMon = CFrame.new(-3385, 239, -10542)
				CFrameQ = CFrame.new(-3054, 237, -10148)
			end
		end

	    if World3 then

	    end
	end
	task.spawn(function()
		local codes = {"BANEXPLOIT", "NOMOREHACKS", "WildDares", "BossBuild", "GetPranked", "EARN_FRUITS", "Sub2UncleKizaru", "FIGHT4FRUIT", "kittgaming", "TRIPLEABUSE", "Sub2CaptainMaui", "Sub2Fer999", "Enyu_is_Pro", "Magicbus", "JCWK", "Starcodeheo", "Bluxxy", "SUB2GAMERROBOT_EXP1", "Sub2NoobMaster123", "Sub2Daigrock", "Axiore", "TantaiGaming", "StrawHatMaine", "Sub2OfficialNoobie", "TheGreatAce", "SEATROLLIN", "24NOADMIN", "ADMIN_TROLL", "NEWTROLL", "SECRET_ADMIN", "staffbattle", "NOEXPLOIT", "NOOB2ADMIN", "CODESLIDE", "fruitconcepts"}
		for _, v in ipairs(codes) do
			ReplicatedStorage.Remotes.Redeem:InvokeServer(v)
		end
	end)
	local function GetNearestMob(originMob, maxDistance)
	    if not originMob or not originMob:FindFirstChild("HumanoidRootPart") then
	        return nil
	    end
	    local nearest
	    local nearestDistance = math.huge
	    for _, mob in ipairs(workspace.Enemies:GetChildren()) do
	        if mob ~= originMob
	        and mob.Name == originMob.Name
	        and mob.Parent
	        and mob:FindFirstChild("Humanoid")
	        and mob:FindFirstChild("HumanoidRootPart")
	        and mob.Humanoid.Health > 0 then
	            local dist = (mob.HumanoidRootPart.Position - originMob.HumanoidRootPart.Position).Magnitude
	            if dist <= maxDistance and dist < nearestDistance then
	                nearest = mob
	                nearestDistance = dist
	            end
	        end
	    end

	    return nearest
	end

	local function SmartMoveAndAttack(mainMob, QuestTitle, Quest, IsCheckQuest, CustomName)
		if IsCheckQuest == nil then IsCheckQuest = true end
		CustomName = CustomName or NameCheckQuest
	    pcall(sethiddenproperty, LocalPlayer, "SimulationRadius", math.huge)
	    if not mainMob or not mainMob.Parent or not mainMob:FindFirstChild("Humanoid") or not mainMob:FindFirstChild("HumanoidRootPart") then
	        return false
	    end
	    local humanoid = mainMob.Humanoid
	    local hrp = mainMob.HumanoidRootPart
	    mainMob.Humanoid.JumpPower = 0
	    mainMob.Humanoid.WalkSpeed = 0
	    hrp.CanCollide = false
	    local bv = mainMob.HumanoidRootPart:FindFirstChild("BringVelocity")
	    if not bv then
	        bv = Instance.new("BodyVelocity")
	        bv.Name = "BringVelocity"
	        bv.MaxForce = Vector3.new(100000, 100000, 100000)
	        bv.Parent = mainMob.HumanoidRootPart
	    end
	    bv.Velocity = Vector3.zero
	    local secondMob = nil
	    local tween
	    repeat task.wait()
			title.Text = "Auto Farming Level | Kill " .. mainMob.Name
	        if not secondMob then
	            secondMob = GetNearestMob(mainMob, 350)
	        end
	        if secondMob and secondMob.Parent and secondMob:FindFirstChild("Humanoid") and secondMob.Humanoid.Health > 0 and secondMob:FindFirstChild("HumanoidRootPart") then
	            secondMob.HumanoidRootPart.CFrame = hrp.CFrame
	            secondMob.Humanoid.JumpPower = 0
	            secondMob.Humanoid.WalkSpeed = 0
	            secondMob.HumanoidRootPart.CanCollide = false
	            local bv = secondMob.HumanoidRootPart:FindFirstChild("BringVelocity")
	            if not bv then
	                bv = Instance.new("BodyVelocity")
	                bv.Name = "BringVelocity"
	                bv.MaxForce = Vector3.new(100000, 100000, 100000)
	                bv.Parent = secondMob.HumanoidRootPart
	            end
	            bv.Velocity = Vector3.zero
	        else
	            secondMob = nil
	        end
	        local myHRP = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
	        if not myHRP then
	            break
	        end
	        local distance = (myHRP.Position - hrp.Position).Magnitude
	        if distance > 150 then
	            if not tween or tween.PlaybackState ~= Enum.PlaybackState.Playing then
	                tween = Tween(hrp.CFrame * CFrame.new(0,30,0),350)
	            end
	        else
	            if tween then
	                tween:Cancel()
	                tween = nil
	            end
	            EquipWeapon("Melee")
	            if tick() - LastRotate >= 0.25 then
	                AttackRotation = (AttackRotation + 180) % 360
	                LastRotate = tick()
	            end
	            myHRP.CFrame = hrp.CFrame * CFrame.new(0,30,0) * CFrame.Angles(0, math.rad(AttackRotation), 0)
	            if secondMob then
	                Attack({mainMob, secondMob})
	            else
	                Attack(mainMob)
	            end
	        end

	    until (IsCheckQuest and (not string.find(QuestTitle.Text, NameCheckQuest)) or false)
	        or not mainMob
	        or not mainMob:FindFirstChild("Humanoid")
	        or (mainMob.Humanoid.Health <= 0)
	        or (IsCheckQuest and not Quest.Visible or false)
			or (secondMob and (not secondMob:FindFirstChild("Humanoid") and not secondMob.Humanoid.Health <= 0) or false)
	    return humanoid.Health <= 0
	end
	local function KaitunWorld1(Quest,QuestTitle,Level)
		CheckInv()
		if Level >= 700 then
			title.Text = "Doing Second Sea Puzzle"
			if not CommF_:InvokeServer("DressrosaQuestProgress", "Dressrosa") then
				if CommF_:InvokeServer("DressrosaQuestProgress").TalkedDetective and CommF_:InvokeServer("DressrosaQuestProgress").UsedKey then
					if workspace.Enemies:FindFirstChild("Ice Admiral") then
						for _, v in workspace.Enemies:GetChildren() do
							if v:IsA("Model") and v:FindFirstChild("Humanoid") and v:FindFirstChild("HumanoidRootPart") and v.Humanoid.Health > 0 and v.Name == "Ice Admiral" then
	                            SmartMoveAndAttack(v, QuestTitle, Quest, false)
								title.Text = "Travel To Second Sea"
								CommF_:InvokeServer("TravelDressrosa")
							end
						end
					else
						local t0 = Tween(CFrame.new(1382.562255859375, 26.999441146850586, -1458.77783203125),350)
						t0.Completed:Wait()
					end
				elseif IsOwn("Key") then
					CommF_:InvokeServer("DressrosaQuestProgress","UseKey")
				elseif not IsOwn("Key") then
					CommF_:InvokeServer("DressrosaQuestProgress","Detective")
				end
			else
				title.Text = "Travel To Second Sea"
				CommF_:InvokeServer("TravelDressrosa")
			end
		elseif Level >= 200 and getgenv().Configs.Saber and workspace.Map.Jungle.Final.Part.CanCollide and not IsSaber then
			title.Text = "Saber Quest | Solve Puzzle"
			if not workspace.Map.Jungle.QuestPlates.Door.CanCollide then
				if CommF_:InvokeServer("ProQuestProgress").UsedTorch then
					if CommF_:InvokeServer("ProQuestProgress","SickMan") == 0 then
						if CommF_:InvokeServer("ProQuestProgress","RichSon") == 0 then
							if workspace.Enemies:FindFirstChild("Mob Leader") then
								for _, v in workspace.Enemies:GetChildren() do
									if v:IsA("Model") and v:FindFirstChild("Humanoid") and v:FindFirstChild("HumanoidRootPart") and v.Humanoid.Health > 0 and v.Name == "Mob Leader" then
	                                    SmartMoveAndAttack(v, QuestTitle, Quest, false)
									end
								end
							else
								if (CFrame.new(-2848, 8, 5342).Position - LocalPlayer.Character.HumanoidRootPart.Position).Magnitude > 150 then
									t0 = Tween(CFrame.new(-2848, 8, 5342),350)
								elseif (CFrame.new(-2848, 8, 5342).Position - LocalPlayer.Character.HumanoidRootPart.Position).Magnitude <= 150 then
									if t0 then
										t0:Cancel()
									end
									LocalPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(-2848, 8, 5342)
								end
							end
						elseif CommF_:InvokeServer("ProQuestProgress","RichSon") == 1 then
							CommF_:InvokeServer("ProQuestProgress","PlaceRelic")
						else
							CommF_:InvokeServer("ProQuestProgress","RichSon")
						end
					else
						CommF_:InvokeServer("ProQuestProgress","GetCup")
						task.wait(0.2)
						EquipName("Cup")
						task.wait(0.2)
						local cup = IsOwn("Cup")
						CommF_:InvokeServer("ProQuestProgress","FillCup",cup)
						CommF_:InvokeServer("ProQuestProgress","SickMan")
					end
				elseif IsOwn("Torch") then
					CommF_:InvokeServer("ProQuestProgress","DestroyTorch")
				elseif not IsOwn("Torch") then
					CommF_:InvokeServer("ProQuestProgress","GetTorch")
				end
			else
				for i, v in workspace.Map.Jungle.QuestPlates:GetChildren() do
					if v:IsA("Model") then
						if v.Button.BrickColor ~= BrickColor.new("Camo") then
	                        title.Text = "Doing Saber Quest | Touching Plates " .. i .. "/5"
	                        local tbar = Tween(v.Button.CFrame,350)
	                        tbar.Completed:Wait()
							task.wait(0.5)

						end
					end
				end
			end
		elseif Level >= 200 and getgenv().Configs.Saber and not IsSaber and (ReplicatedStorage:FindFirstChild("Saber Expert") or workspace.Enemies:FindFirstChild("Saber Expert")) then
			title.Text = "Saber Quest | Kill Saber Expert"
			if workspace.Enemies:FindFirstChild("Saber Expert") then
				for _, v in workspace.Enemies:GetChildren() do
					if v.Name == "Saber Expert" and v:FindFirstChild("HumanoidRootPart") and v:FindFirstChild("Humanoid") and v.Humanoid.Health > 0 then
	                    SmartMoveAndAttack(v, QuestTitle, Quest, false)
					end
				end
			elseif ReplicatedStorage:FindFirstChild("Saber Expert") then
				if (CFrame.new(-1458.89502, 29.8870335, -50.633564).Position - LocalPlayer.Character.HumanoidRootPart.Position).Magnitude > 150 then
					t920 = Tween(CFrame.new(-1458.89502, 29.8870335, -50.633564),350)
				elseif (CFrame.new(-1458.89502, 29.8870335, -50.633564).Position - LocalPlayer.Character.HumanoidRootPart.Position).Magnitude <= 150 then
					if t920 then
						t920:Cancel()
					end
					LocalPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(-1458.89502, 29.8870335, -50.633564)
				end
				CommF_:InvokeServer("SetSpawnPoint")
			end
		elseif Level >= 200 and getgenv().Configs.Pole and not IsPoleV1 and (ReplicatedStorage:FindFirstChild("Thunder God") or workspace.Enemies:FindFirstChild("Thunder God")) then
			title.Text = "Get Pole | Kill Thunder God"
			if workspace.Enemies:FindFirstChild("Thunder God") then
				for _, v in workspace.Enemies:GetChildren() do
					if v.Name == "Thunder God" and v:FindFirstChild("HumanoidRootPart") and v:FindFirstChild("Humanoid") and v.Humanoid.Health > 0 then
	                    SmartMoveAndAttack(v, QuestTitle, Quest, false)
					end
				end
			elseif ReplicatedStorage:FindFirstChild("Thunder God") then
				if (CFrame.new(-7795.9287109375, 5605.951171875, -2231.444580078125).Position - LocalPlayer.Character.HumanoidRootPart.Position).Magnitude > 150 then
					t920 = Tween(CFrame.new(-7795.9287109375, 5605.951171875, -2231.444580078125),350)
				elseif (CFrame.new(-7795.9287109375, 5605.951171875, -2231.444580078125).Position - LocalPlayer.Character.HumanoidRootPart.Position).Magnitude <= 150 then
					if t920 then
						t920:Cancel()
					end
					LocalPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(-7795.9287109375, 5605.951171875, -2231.444580078125)
				end
				CommF_:InvokeServer("SetSpawnPoint")
			end
		elseif getgenv().Configs.SkipFarmLevel and (Level >= 0 and Level <= 24) then
			if workspace.Enemies:FindFirstChild("Dark Master") then
				for _,v in pairs(workspace.Enemies:GetChildren()) do
					if LocalPlayer.Data.Level.Value >= 25 then
						break
					end
					if v.Name == "Dark Master" and v:FindFirstChild("HumanoidRootPart") and v:FindFirstChild("Humanoid") and v.Humanoid.Health > 0 then
	                    SmartMoveAndAttack(v, QuestTitle, Quest, false)
					end
				end
			else
				title.Text = "Skip Farming Level | Waiting"
				local t0 = Tween(CFrame.new(-5250, 389, -2272),350)
				if (CFrame.new(-5250, 389, -2272).Position - LocalPlayer.Character.HumanoidRootPart.Position).Magnitude <= 150 then
					if t0 then
						t0:Cancel()
					end
					LocalPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(-5250, 389, -2272)
				end
			end
		elseif getgenv().Configs.SkipFarmLevel and (Level >= 25 and Level <= 59) then
			if workspace.Enemies:FindFirstChild("Royal Squad") then
				for _,v in pairs(workspace.Enemies:GetChildren()) do
					if LocalPlayer.Data.Level.Value >= 60 then
						break
					end
					if v.Name == "Royal Squad" and v:FindFirstChild("HumanoidRootPart") and v:FindFirstChild("Humanoid") and v.Humanoid.Health > 0 then
	                    SmartMoveAndAttack(v, QuestTitle, Quest, false)
					end
				end
			else
				title.Text = "Skip Farming Level | Waiting"
				local t0 = Tween(CFrame.new(-7670, 5607, -1460),350)
				if (CFrame.new(-7670, 5607, -1460).Position - LocalPlayer.Character.HumanoidRootPart.Position).Magnitude <= 150 then
					if t0 then
						t0:Cancel()
					end
					LocalPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(-7670, 5607, -1460)
				end
			end
	    elseif not Quest.Visible then
			title.Text = "Auto Farming Level | Get Quest"
			if (CFrameQ.Position - LocalPlayer.Character.HumanoidRootPart.Position).Magnitude > 150 then
				t2 = Tween(CFrameQ,350)
			elseif (CFrameQ.Position - LocalPlayer.Character.HumanoidRootPart.Position).Magnitude <= 150 then
				if t2 then
					t2:Cancel()
				end
				LocalPlayer.Character.HumanoidRootPart.CFrame = CFrameQ
				CommF_:InvokeServer("StartQuest",NameQuest,LevelQuest)
				CommF_:InvokeServer("SetSpawnPoint")
			end
		elseif Quest.Visible then
			if workspace.Enemies:FindFirstChild(Monster) then
				for _,v in pairs(workspace.Enemies:GetChildren()) do
					if v.Name == Monster and v:FindFirstChild("HumanoidRootPart") and v:FindFirstChild("Humanoid") and v.Humanoid.Health > 0 then
						if string.find(QuestTitle.Text, NameCheckQuest) then
	                        SmartMoveAndAttack(v, QuestTitle, Quest)
						else
							CommF_:InvokeServer("AbandonQuest")
						end
					end
				end
			else
				title.Text = "Auto Farming Level | Wait For " .. Monster
				if (CFrameMon.Position - LocalPlayer.Character.HumanoidRootPart.Position).Magnitude > 150 then
					t0 = Tween(CFrameMon,350)
				elseif (CFrameMon.Position - LocalPlayer.Character.HumanoidRootPart.Position).Magnitude <= 150 then
					if t0 then
						t0:Cancel()
					end
					LocalPlayer.Character.HumanoidRootPart.CFrame = CFrameMon
				end
			end
		end
	end
	local function KaitunWorld2(Quest,QuestTitle,Level)
		CheckInv()
		if workspace.Enemies:FindFirstChild("Core") or ReplicatedStorage:FindFirstChild("Core") then
			if workspace.Enemies:FindFirstChild("Core") then
				for _,v in pairs(workspace.Enemies:GetChildren()) do
					if v.Name == "Core" and v:FindFirstChild("HumanoidRootPart") and v:FindFirstChild("Humanoid") then
	                    SmartMoveAndAttack(v, QuestTitle, Quest, false)
					end
				end
			elseif ReplicatedStorage:FindFirstChild("Core") then
				Tween(CFrame.new(448.46756, 199.356781, -441.389252),350)
			end
		elseif Level >= 850 and (CommF_:InvokeServer("BartiloQuestProgress","Bartilo") == 0 or CommF_:InvokeServer("BartiloQuestProgress","Bartilo") == 2 or (CommF_:InvokeServer("BartiloQuestProgress","Bartilo") == 1 and (workspace.Enemies:FindFirstChild("Jeremy") or ReplicatedStorage:FindFirstChild("Jeremy")))) then
	        if CommF_:InvokeServer("BartiloQuestProgress","Bartilo") == 0 then
	            if LocalPlayer.PlayerGui.Main.Quest.Visible then
	                if string.find(LocalPlayer.PlayerGui.Main.Quest.Container.QuestTitle.Title.Text, "50 Swan Pirates") then
	                    if workspace.Enemies:FindFirstChild("Swan Pirate") then
	                        for _, v in pairs(workspace.Enemies:GetChildren()) do
	                            if v.Name == "Swan Pirate" and v:FindFirstChild("HumanoidRootPart") and v:FindFirstChild("Humanoid") and v.Humanoid.Health > 0 then
	                                SmartMoveAndAttack(v, QuestTitle, Quest, false, "Swan Pirate")
	                            end
	                        end
	                    else
	                        title.Text = "Doing Bartilo Quest | Wait For Swan Pirates"
	                        if (CFrame.new(878, 122, 1235).Position - LocalPlayer.Character.HumanoidRootPart.Position).Magnitude > 150 then
	                            t0 = Tween(CFrame.new(878, 122, 1235),350)
	                        elseif (CFrame.new(878, 122, 1235).Position - LocalPlayer.Character.HumanoidRootPart.Position).Magnitude <= 150 then
	                            if t0 then
	                                t0:Cancel()
	                            end
	                            LocalPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(878, 122, 1235)
	                        end
	                    end
	                else
	                    CommF_:InvokeServer("AbandonQuest")
	                end
	            else
	                CommF_:InvokeServer("StartQuest","BartiloQuest",1)
	            end
	        elseif CommF_:InvokeServer("BartiloQuestProgress","Bartilo") == 1 and (workspace.Enemies:FindFirstChild("Jeremy") or ReplicatedStorage:FindFirstChild("Jeremy")) then
	            if workspace.Enemies:FindFirstChild("Jeremy") then
	                for _,v in pairs(workspace.Enemies:GetChildren()) do
	                    if v.Name == "Jeremy" and v:FindFirstChild("HumanoidRootPart") and v:FindFirstChild("Humanoid") and v.Humanoid.Health > 0 then
	                        SmartMoveAndAttack(v, QuestTitle, Quest, false)
	                    end
	                end
	            elseif ReplicatedStorage:FindFirstChild("Jeremy") then
	                if (CFrame.new(2099.88159, 448.931, 648.997375).Position - LocalPlayer.Character.HumanoidRootPart.Position).Magnitude > 150 then
	                    t920 = Tween(CFrame.new(2099.88159, 448.931, 648.997375),350)
	                elseif (CFrame.new(2099.88159, 448.931, 648.997375).Position - LocalPlayer.Character.HumanoidRootPart.Position).Magnitude <= 150 then
	                    if t920 then
	                        t920:Cancel()
	                    end
	                    LocalPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(2099.88159, 448.931, 648.997375)
	                end
	                CommF_:InvokeServer("SetSpawnPoint")
	            end
	        elseif CommF_:InvokeServer("BartiloQuestProgress","Bartilo") == 2 then
	            local plates = {}
	            for _, v in ipairs(workspace.Map.Dressrosa.BartiloPlates:GetChildren()) do
	                local num = tonumber(string.match(v.Name, "%d+$"))
	                if num then
	                    table.insert(plates, {num = num, plate = v})
	                end
	            end
	            table.sort(plates, function(a, b)
	                return a.num < b.num
	            end)

						LocalPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(-1837.46155, 44.2921753, 1656.1987, 0.999881566, -1.03885048e-22, -0.0153914848, 1.07805858e-22, 1, 2.53909284e-22, 0.0153914848, -2.55538502e-22, 0.999881566)
						task.wait(1)
						LocalPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(-1836.0, 11, 1714)
						task.wait(.5)
						LocalPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(-1850.49329, 13.1789551, 1750.89685)
						task.wait(1)
						LocalPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(-1858.87305, 19.3777466, 1712.01807)
						task.wait(1)
						LocalPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(-1803.94324, 16.5789185, 1750.89685)
						task.wait(1)
						LocalPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(-1858.55835, 16.8604317, 1724.79541)
						task.wait(1)
						LocalPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(-1869.54224, 15.987854, 1681.00659)
						task.wait(1)
						LocalPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(-1800.0979, 16.4978027, 1684.52368)
						task.wait(1)
						LocalPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(-1819.26343, 14.795166, 1717.90625)
						task.wait(1)
						LocalPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(-1813.51843, 14.8604736, 1724.79541)

	        end
	    elseif not Quest.Visible then
			title.Text = "Auto Farming Level | Get Quest"
			if (CFrameQ.Position - LocalPlayer.Character.HumanoidRootPart.Position).Magnitude > 150 then
				t2 = Tween(CFrameQ,350)
			elseif (CFrameQ.Position - LocalPlayer.Character.HumanoidRootPart.Position).Magnitude <= 150 then
				if t2 then
					t2:Cancel()
				end
				LocalPlayer.Character.HumanoidRootPart.CFrame = CFrameQ
				CommF_:InvokeServer("StartQuest",NameQuest,LevelQuest)
				CommF_:InvokeServer("SetSpawnPoint")
			end
		elseif Quest.Visible then
			if workspace.Enemies:FindFirstChild(Monster) then
				for _,v in pairs(workspace.Enemies:GetChildren()) do
					if v.Name == Monster and v:FindFirstChild("HumanoidRootPart") and v:FindFirstChild("Humanoid") and v.Humanoid.Health > 0 then
						if string.find(QuestTitle.Text, NameCheckQuest) then
	                        SmartMoveAndAttack(v, QuestTitle, Quest)
						else
							CommF_:InvokeServer("AbandonQuest")
						end
					end
				end
			else
				title.Text = "Auto Farming Level | Wait For " .. Monster
				if (CFrameMon.Position - LocalPlayer.Character.HumanoidRootPart.Position).Magnitude > 150 then
					t0 = Tween(CFrameMon,350)
				elseif (CFrameMon.Position - LocalPlayer.Character.HumanoidRootPart.Position).Magnitude <= 150 then
					if t0 then
						t0:Cancel()
					end
					LocalPlayer.Character.HumanoidRootPart.CFrame = CFrameMon
				end
			end
		end
	end
	local Melees = {
	    ["Black Leg"] = {
	        NPC = "Dark Step Teacher",
	        Price = {
	            Beli = 150000,
	            Fragments = 0
	        },
	        BuyID = "BuyBlackLeg",
	        RequiredMastery = 400,
	        IsCompleted = false,
			World = 1
	    },
	    ["Electro"] = {
	        NPC = "Mad Scientist",
	        Price = {
	            Beli = 500000,
	            Fragments = 0
	        },
	        BuyID = "BuyElectro",
	        RequiredMastery = 400,
	        IsCompleted = false,
			World = 1
	    },
	    ["Fishman Karate"] = {
	        NPC = "Water Kung-fu Teacher",
	        Price = {
	            Beli = 750000,
	            Fragments = 0
	        },
	        BuyID = "BuyFishmanKarate",
	        RequiredMastery = 400,
	        IsCompleted = false,
			World = 1
	    },
	    ["Dragon Claw"] = {
	        NPC = "Sabi",
	        Price = {
	            Beli = 0,
	            Fragments = 1500
	        },
	        BuyID = "BuyDragonClaw",
	        RequiredMastery = 400,
	        IsCompleted = false,
			World = 2
	    },
	    ["Superhuman"] = {
	        NPC = "Martial Arts Master",
	        Price = {
	            Beli = 3000000,
	            Fragments = 0
	        },
	        BuyID = "BuySuperhuman",
	        RequiredMastery = 300,
	        IsCompleted = false,
			World = 2
	    },
	    ["Death Step"] = {
	        NPC = "Phoeyu, the Reformed",
	        Price = {
	            Beli = 2500000,
	            Fragments = 5000
	        },
	        BuyID = "BuyDeathStep",
	        RequiredMastery = 400,
	        IsCompleted = false,
			World = 2
	    },
	    ["Sharkman Karate"] = {
	        NPC = "Sharkman Teacher",
	        Price = {
	            Beli = 2500000,
	            Fragments = 5000
	        },
	        BuyID = "BuySharkmanKarate",
	        RequiredMastery = 400,
	        IsCompleted = false,
			World = 2
	    },
	    ["Electric Claw"] = {
	        NPC = "Previous Hero",
	        Price = {
	            Beli = 3000000,
	            Fragments = 5000
	        },
	        BuyID = "BuyElectricClaw",
	        RequiredMastery = 400,
	        IsCompleted = false,
			World = 3
	    },
	    ["Dragon Talon"] = {
	        NPC = "Uzoth",
	        Price = {
	            Beli = 3000000,
	            Fragments = 5000
	        },
	        BuyID = "BuyDragonTalon",
	        RequiredMastery = 400,
	        IsCompleted = false,
			World = 3
	    },
	    ["Godhuman"] = {
	        NPC = "Ancient Monk",
	        Price = {
	            Beli = 5000000,
	            Fragments = 5000
	        },
	        BuyID = "BuyGodhuman",
	        RequiredMastery = 400,
	        IsCompleted = false,
			World = 3
	    }
	}
	local Prerequisites = {
	    ["Death Step"] = {"Black Leg"},
	    ["Sharkman Karate"] = {"Fishman Karate"},
	    ["Electric Claw"] = {"Electro"},
	    ["Dragon Talon"] = {"Dragon Claw"},
	    ["Godhuman"] = {"Superhuman", "Death Step", "Sharkman Karate", "Electric Claw", "Dragon Talon"}
	}
	for i,v in pairs(Melees) do
		if CommF_:InvokeServer(v.BuyID,true) == 1 then
			if Prerequisites[i] then
	            for _, v1 in ipairs(Prerequisites[i]) do
	                if Melees[v1] then
	                    Melees[v1].IsCompleted = true
	                end
	            end
			end
		end
	end
	task.spawn(function()
		while task.wait() do
			DieWait()
			for _, v in workspace:GetChildren() do
				if string.find(v.Name:lower(), "fruit") and v:IsA("Model") and v:FindFirstChild("Handle") then
					local inv = CommF_:InvokeServer("getInventory")
					local doesnothave = true
					if type(inv) == "table" then
						for _, v1 in ipairs(inv) do
							if v1.Name == v:GetAttribute("OriginalName") then
								doesnothave = false
								break
							end
						end
					end
					if doesnothave and v then
						if v:FindFirstChild("Handle") then
							if (v.Handle.Position - LocalPlayer.Character.HumanoidRootPart.Position).Magnitude > 150 then
								local riyu = Tween(v.Handle.CFrame,350)
								title.Text = "Get " .. v.Name
								riyu.Completed:Wait()
								task.wait(0.5)
							elseif (v.Handle.Position - LocalPlayer.Character.HumanoidRootPart.Position).Magnitude <= 150 then
								LocalPlayer.Character.HumanoidRootPart.CFrame = v.Handle.CFrame
								title.Text = "Get " .. v.Name
								task.wait(0.1)
							end
						end
					end
				end
			end
			for _, v in LocalPlayer.Character:GetChildren() do
				if string.find(v.Name:lower(), "fruit") and v:IsA("Tool") and v:FindFirstChild("Handle") then
					local inv = CommF_:InvokeServer("getInventory")
					local doesnothave = true
					if type(inv) == "table" then
						for _, v1 in ipairs(inv) do
							if v1.Name == v:GetAttribute("OriginalName") then
								doesnothave = false
								break
							end
						end
					end
					if doesnothave and v then
						CommF_:InvokeServer("StoreFruit",v:GetAttribute("OriginalName"),v)
					end
				end
			end
			for _, v in LocalPlayer.Backpack:GetChildren() do
				if string.find(v.Name:lower(), "fruit") and v:IsA("Tool") and v:FindFirstChild("Handle") then
					local inv = CommF_:InvokeServer("getInventory")
					local doesnothave = true
					if type(inv) == "table" then
						for _, v1 in ipairs(inv) do
							if v1.Name == v:GetAttribute("OriginalName") then
								doesnothave = false
								break
							end
						end
					end
					if doesnothave and v then
						EquipName(v.Name)
						CommF_:InvokeServer("StoreFruit",v:GetAttribute("OriginalName"),v)
					end
				end
			end
			CheckQuest()
			local Quest = LocalPlayer.PlayerGui.Main.Quest
			local QuestTitle = Quest.Container.QuestTitle.Title
			local CurLevel = LocalPlayer.Data.Level.Value
			local CurMelee
			for _,v in LocalPlayer.Backpack:GetChildren() do
				if v:IsA("Tool") and v.ToolTip == "Melee" then
					CurMelee = v.Name
					break
				end
			end
			for _,v in LocalPlayer.Character:GetChildren() do
				if v:IsA("Tool") and v.ToolTip == "Melee" then
					CurMelee = v.Name
					break
				end
			end

			if CurMelee == "Combat" or tonumber(IsOwn(CurMelee).Level.Value) >= Melees[CurMelee].RequiredMastery then
				for i, v in pairs(Melees) do
					if v.IsCompleted then
						continue
					else
						if GetWorld() >= v.World then
							local isfrag = true
							if GetWorld() >= 2 then
								if LocalPlayer.Data.Fragments.Value < v.Price.Fragments then
									isfrag = false
								end
							end
							if CommF_:InvokeServer(v.BuyID,true) == 1 then
								local tmelee
								if workspace.NPCs:FindFirstChild(v.NPC) then
									tmelee = Tween(workspace.NPCs:FindFirstChild(v.NPC).HumanoidRootPart.CFrame,350)
								elseif ReplicatedStorage.NPCs:FindFirstChild(v.NPC) then
									tmelee = Tween(ReplicatedStorage.NPCs:FindFirstChild(v.NPC).HumanoidRootPart.CFrame,350)
								end
								if tmelee then
									title.Text = "Get " .. i
									tmelee.Completed:Wait()
								end
								CommF_:InvokeServer(v.BuyID)
							elseif LocalPlayer.Data.Beli.Value >= v.Price.Beli and isfrag then
								local tmelee
								if workspace.NPCs:FindFirstChild(v.NPC) then
									tmelee = Tween(workspace.NPCs:FindFirstChild(v.NPC).HumanoidRootPart.CFrame,350)
								elseif ReplicatedStorage.NPCs:FindFirstChild(v.NPC) then
									tmelee = Tween(ReplicatedStorage.NPCs:FindFirstChild(v.NPC).HumanoidRootPart.CFrame,350)
								end
								if tmelee then
									title.Text = "Get " .. i
									tmelee.Completed:Wait()
								end
								CommF_:InvokeServer(v.BuyID)
								break
							else
								subtitle.Text = "Farming Until Has Enough Resources For " .. i
								break
							end
							if tonumber(IsOwn(i).Level.Value) >= v.RequiredMastery then
								v.IsCompleted = true
								continue
							else
								subtitle.Text = "Farming Until " .. i .. " Reaches " .. Melees[i].RequiredMastery .. " Mastery"
								break
							end
						else
							v.IsCompleted = true
						end
					end
				end
			else
				subtitle.Text = "Farming Until " .. CurMelee .. " Reaches " .. Melees[CurMelee].RequiredMastery .. " Mastery"
			end
			if World1 then
				KaitunWorld1(Quest,QuestTitle,CurLevel)
			elseif World2 then
				KaitunWorld2(Quest,QuestTitle,CurLevel)
			end
		end
	end)
	task.spawn(function()
		while task.wait() do
			if LocalPlayer.Data.Points.Value > 0 then
				local Melee = LocalPlayer.Data.Stats.Melee.Level.Value
				local Defense = LocalPlayer.Data.Stats.Defense.Level.Value
				local Sword = LocalPlayer.Data.Stats.Sword.Level.Value
				CommF_:InvokeServer("AddPoint","Melee",LocalPlayer.Data.Level.Value * 2 - Melee)
				CommF_:InvokeServer("AddPoint","Defense",LocalPlayer.Data.Level.Value - Defense)
				if Melee == MaxLevel and Defense == MaxLevel then
					CommF_:InvokeServer("AddPoint","Sword",LocalPlayer.Data.Level.Value * 3 - MaxLevel * 2)
				end
			end
			if not CollectionService:HasTag(LocalPlayer.Character, "Buso") and LocalPlayer.Data.Beli.Value >= 25000 then
				CommF_:InvokeServer("BuyHaki","Buso")
			end
			if not CollectionService:HasTag(LocalPlayer.Character, "Geppo") and LocalPlayer.Data.Beli.Value >= 10000 then
				CommF_:InvokeServer("BuyHaki","Geppo")
			end
			if not CollectionService:HasTag(LocalPlayer.Character, "Soru") and LocalPlayer.Data.Beli.Value >= 100000 then
				CommF_:InvokeServer("BuyHaki","Soru")
			end
			if not CollectionService:HasTag(LocalPlayer.Character, "Ken") and World1 and LocalPlayer.Data.Beli.Value >= 750000 then
				CommF_:InvokeServer("KenTalk","Buy")
			end
			CommF_:InvokeServer("Cousin","Buy")
		end
	end)
end

S.full = { Team = "Pirates", Saber = true, CursedDualKatana = true, SkullGuitar = true, RaceV3 = true, FixLag = false, WhiteScreen = false, FPS = 0 }
S.classic = { Team = "Pirates", Saber = true, Pole = true, SkipFarmLevel = true }

function H.startKaitun(mode)
	if S.kaitun then
		Library:Warn("Kaitun", "A Kaitun mode is already running. Rejoin to stop it.", 6)
		return
	end

	Window:Confirm({
		Title = "kaitun",
		Text = "Start the " .. mode .. " Kaitun? It plays on its own until you rejoin. Turn off the other farm options first.",
		Confirm = "start",
		Cancel = "cancel",
		OnConfirm = function()
			S.kaitun = true
			local config = {}
			for key, value in pairs(mode == "full" and S.full or S.classic) do config[key] = value end
			if mode == "full" and (tonumber(config.FPS) or 0) <= 0 then config.FPS = nil end
			if getgenv then getgenv().Configs = config end
			task.spawn(function()
				local ok, err = pcall(mode == "full" and KaitunFull or KaitunClassic)
				if not ok then
					warn("[Facility] Kaitun error: " .. tostring(err))
					pcall(function() Library:Error("Kaitun", tostring(err), 10) end)
				end
			end)
			Library:Success("Kaitun", "Kaitun " .. mode .. " started.", 5)
		end,
	})
end

U.full = TabKaitun.Tab:Section("Kaitun Full", 1)

U.full:Paragraph({
	Title = "full progression",
	Content = "Levels, seas, Saber, Cursed Dual Katana, Skull Guitar and Race V3 on autopilot. It runs until you rejoin.",
})

U.full:Dropdown({
	Text = "Team",
	Flag = "bf_kf_team",
	Options = { "Pirates", "Marines" },
	Default = "Pirates",
	Callback = function(value) S.full.Team = type(value) == "table" and value[1] or value end,
})

U.full:Toggle({ Text = "Saber", Flag = "bf_kf_saber", Default = true, Callback = function(state) S.full.Saber = state end })
U.full:Toggle({ Text = "Cursed Dual Katana", Flag = "bf_kf_cdk", Default = true, Callback = function(state) S.full.CursedDualKatana = state end })
U.full:Toggle({ Text = "Skull Guitar", Flag = "bf_kf_skull", Default = true, Callback = function(state) S.full.SkullGuitar = state end })
U.full:Toggle({ Text = "Race V3", Flag = "bf_kf_race", Default = true, Callback = function(state) S.full.RaceV3 = state end })
U.full:Toggle({ Text = "Fix Lag", Flag = "bf_kf_fixlag", Default = false, Hint = "strips textures and effects, cannot be undone", Callback = function(state) S.full.FixLag = state end })
U.full:Toggle({ Text = "White Screen", Flag = "bf_kf_white", Default = false, Hint = "stops 3D rendering to save resources", Callback = function(state) S.full.WhiteScreen = state end })
U.full:Slider({ Text = "FPS Cap", Flag = "bf_kf_fps", Min = 0, Max = 240, Default = 0, ZeroText = "off", Callback = function(value) S.full.FPS = value end })
U.full:Button({ Text = "Start Kaitun Full", Callback = function() H.startKaitun("full") end })

U.classic = TabKaitun.Tab:Section("Kaitun Classic", 2)

U.classic:Paragraph({
	Title = "first and second sea",
	Content = "Lighter Kaitun for the early game: quests, Saber, Pole and stats. It runs until you rejoin.",
})

U.classic:Dropdown({
	Text = "Team",
	Flag = "bf_kc_team",
	Options = { "Pirates", "Marines" },
	Default = "Pirates",
	Callback = function(value) S.classic.Team = type(value) == "table" and value[1] or value end,
})

U.classic:Toggle({ Text = "Saber", Flag = "bf_kc_saber", Default = true, Callback = function(state) S.classic.Saber = state end })
U.classic:Toggle({ Text = "Pole", Flag = "bf_kc_pole", Default = true, Callback = function(state) S.classic.Pole = state end })
U.classic:Toggle({ Text = "Skip Farm Level", Flag = "bf_kc_skip", Default = true, Hint = "skips the first levels by farming stronger enemies", Callback = function(state) S.classic.SkipFarmLevel = state end })
U.classic:Button({ Text = "Start Kaitun Classic", Callback = function() H.startKaitun("classic") end })

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
SaveManager:SetFolder("Facility/994732206")

InterfaceManager:BuildInterfaceSection(TabSettings.Tab, 1)
SaveManager:BuildConfigSection(TabSettings.Tab, 2)
ThemeManager:Mount(Window)

Window:SetTab(TabHome.Tab)

Library:Notify("Facility", "Blox Fruits loaded.", 4)

SaveManager:LoadAutoloadConfig()
ThemeManager:Load()
