local FH      = shared.Facility
local Library = FH.Library
local Webhook = FH.Webhook

local MOVEMENT_URL = "https://raw.githubusercontent.com/FacilityHUB/Facility-Sexility/refs/heads/main/CModules/FMovement.luau"
local LOADER_URL = "https://raw.githubusercontent.com/FacilityHUB/Facility-Sexility/refs/heads/main/loader.luau"

local function fetchModule(url, label)
	local ok, result = pcall(function()
		return loadstring(game:HttpGet(url .. "?v=" .. tostring(tick()):gsub("%.", "")))()
	end)

	if not ok or type(result) ~= "table" then
		warn("Facility: could not load " .. label)
		return nil
	end

	return result
end

local Movement = fetchModule(MOVEMENT_URL, "movement")

if Movement then Movement:Load() end

FH.Movement = Movement

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local VirtualUser = game:GetService("VirtualUser")
local Lighting = game:GetService("Lighting")

local LocalPlayer = Players.LocalPlayer

local Alive = true
local H = {}
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

local CFG_FOLDER = "Facility/SellLemons"

local function ensureFolder()
	pcall(function()
		if type(isfolder) == "function" and type(makefolder) == "function" then
			if not isfolder("Facility") then makefolder("Facility") end
			if not isfolder(CFG_FOLDER) then makefolder(CFG_FOLDER) end
		end
	end)
end

ensureFolder()

local function userFile(name)
	return CFG_FOLDER .. "/" .. name .. "_" .. tostring(LocalPlayer.UserId) .. ".json"
end

local function readJson(path)
	if type(readfile) ~= "function" or type(isfile) ~= "function" then return nil end

	local ok, raw = pcall(function()
		if isfile(path) then return readfile(path) end
		return nil
	end)

	if not ok or type(raw) ~= "string" then return nil end

	local fine, decoded = pcall(function() return HttpService:JSONDecode(raw) end)
	if not fine or type(decoded) ~= "table" then return nil end

	return decoded
end

local function writeJson(path, value)
	if type(writefile) ~= "function" then return false end

	ensureFolder()

	local ok, raw = pcall(function() return HttpService:JSONEncode(value) end)
	if not ok then return false end

	return pcall(writefile, path, raw)
end

local LOG_LIMIT = 200
local logLines = {}
local logDirty = true

local function clog(text)
	table.insert(logLines, os.date("%H:%M:%S") .. "  " .. tostring(text))

	while #logLines > LOG_LIMIT do
		table.remove(logLines, 1)
	end

	logDirty = true
end

local Status = "Idle"

local F = {
	buy = false, buyDelay = 0.05, buyForever = false,
	upgrade = false, upgradeDelay = 0.25, upgradeEarners = {}, upgradeReserve = 0,
	orchardUnlock = false,
	rebirth = false, rebirthMaxPerEvolve = 0, rebirthMinPotential = 0, rebirthFactor = 10,
	rebirthOnStuck = false, rebirthStuckWait = 30, rebirthOnTimer = false, rebirthTimerWait = 60,
	evolve = false, evolveMax = 0,
	ascend = false, ascendMax = 0,
	powers = false, powerPicks = {}, powerBudget = 50,
	wake = false,
	phone = false,
	fruit = false, fruitMode = "Reach", fruitDelay = 0.08, fruitReturn = true,
	orchard = false, orchardPlant = true, orchardFertilize = false, orchardFertilizer = "FertilizerMutate",
	orchardKeep = {}, orchardAction = "Eat", orchardUpgrades = {}, orchardAutoUpgrade = false,
	orchardTokenFloor = 0, orchardDelay = 1,
	noRender = false, afk = true, fps = false, reexec = false,
	hookRebirth = false, hookEvolve = false, hookAscend = false, hookMutation = false,
	hookMutationKeep = true,
}

local Busy = { buy = false, upgrade = false, rebirth = false, ascend = false, orchard = false }

local Tally = {
	bought = 0, upgraded = 0, rebirths = 0, evolves = 0, ascends = 0,
	powers = 0, woken = 0, offers = 0, fruit = 0,
	planted = 0, harvested = 0, eaten = 0, sold = 0, razed = 0, tokens = 0,
	best = nil, bestValue = 0,
}

local G = { missing = {} }

do
	local deadline = os.clock() + 30

	while os.clock() < deadline do
		local ok, ready = pcall(function()
			return ReplicatedStorage:FindFirstChild("Modules") ~= nil
				and ReplicatedStorage:FindFirstChild("Config") ~= nil
		end)

		if ok and ready then break end

		task.wait(0.5)
	end
end

local function need(name, fn)
	local ok, value = pcall(fn)

	if ok and value ~= nil then
		G[name] = value
		return value
	end

	table.insert(G.missing, name)

	return nil
end

need("Tycoon", function() return require(ReplicatedStorage.Modules.Tycoon.Tycoon) end)
need("Analyzer", function() return require(ReplicatedStorage.Modules.Tycoon.Component.TycoonAnalyzer) end)
need("Balances", function() return require(ReplicatedStorage.Modules.Tycoon.Component.Client.ClientTycoonBalances) end)
need("Upgrades", function() return require(ReplicatedStorage.Modules.Tycoon.Component.Client.ClientTycoonUpgrades) end)
need("Rebirth", function() return require(ReplicatedStorage.Modules.Tycoon.Component.Client.ClientTycoonRebirth) end)
need("Evolution", function() return require(ReplicatedStorage.Modules.Tycoon.Component.Client.ClientTycoonEvolution) end)
need("Ascension", function() return require(ReplicatedStorage.Modules.Tycoon.Component.Client.ClientTycoonAscension) end)
need("Powers", function() return require(ReplicatedStorage.Modules.Tycoon.Component.Client.ClientTycoonPowers) end)
need("PhoneOffers", function() return require(ReplicatedStorage.Modules.Tycoon.Component.Client.ClientTycoonPhoneOffers) end)
need("Balance", function() return require(ReplicatedStorage.Balance) end)
need("Config", function() return require(ReplicatedStorage.Config) end)
need("Huge", function() return require(ReplicatedStorage.Modules.Huge) end)

local Plot = nil

function H.findTycoon()
	for _, child in ipairs(workspace:GetChildren()) do
		if child.Name:match("Tycoon%d") then
			local owner = child:FindFirstChild("Owner")
			if owner and owner.Value == LocalPlayer then return child end
		end
	end

	return nil
end

do
	local deadline = os.clock() + 30

	repeat
		Plot = H.findTycoon()
		if not Plot then task.wait(0.4) end
	until Plot or os.clock() > deadline
end

local Ready = Plot ~= nil and G.Tycoon ~= nil and G.Balances ~= nil

function H.remote(name)
	if not Plot then return nil end

	local remotes = Plot:FindFirstChild("Remotes")
	if not remotes then return nil end

	return remotes:FindFirstChild(name)
end

function H.coreRequest(name)
	local core = ReplicatedStorage:FindFirstChild("Core")
	local folder = core and core:FindFirstChild("RemoteRequest")
	if not folder then return nil end

	return folder:FindFirstChild(name)
end

function H.live()
	if not G.Tycoon then return nil end

	local ok, value = pcall(function() return G.Tycoon.getLocal() end)
	return ok and value or nil
end

function H.comp(class)
	local live = H.live()
	if not (live and class) then return nil end

	local ok, value = pcall(function() return live:GetComponent(class) end)
	return ok and value or nil
end

function H.values(path)
	if not Plot then return nil end

	local node = Plot:FindFirstChild("Values")
	if not node then return nil end

	for part in tostring(path):gmatch("[^%.]+") do
		node = node:FindFirstChild(part)
		if not node then return nil end
	end

	return node
end

function H.attr(path, key, fallback)
	local node = H.values(path)
	if not node then return fallback end

	local ok, value = pcall(function() return node:GetAttribute(key) end)
	if ok and value ~= nil then return value end

	return fallback
end

function H.cash()
	local comp = H.comp(G.Balances)
	if not comp then return -math.huge end

	local ok, value = pcall(function() return comp:GetCash() end)
	return ok and tonumber(value) or -math.huge
end

function H.investors()
	local comp = H.comp(G.Balances)
	if not comp then return -math.huge end

	local ok, value = pcall(function() return comp:GetInvestors() end)
	return ok and tonumber(value) or -math.huge
end

function H.potential()
	local comp = H.comp(G.Rebirth)
	if not comp then return -math.huge end

	local ok, value = pcall(function() return comp:GetPotentialInvestors() end)
	return ok and tonumber(value) or -math.huge
end

function H.tokens()
	return tonumber(H.attr("Values", "Tokens", 0)) or 0
end

function H.rebirthCount()
	return tonumber(H.attr("Values", "Rebirths", 0)) or 0
end

function H.evolution()
	local comp = H.comp(G.Evolution)

	if comp then
		local ok, value = pcall(function() return comp:GetEvolution() end)
		if ok and tonumber(value) then return tonumber(value) end
	end

	return tonumber(H.attr("Values", "Evolution", 0)) or 0
end

function H.ascension()
	local comp = H.comp(G.Ascension)

	if comp then
		local ok, value = pcall(function() return comp:GetAscension() end)
		if ok and tonumber(value) then return tonumber(value) end
	end

	return tonumber(H.attr("Values", "Ascension", 0)) or 0
end

function H.evolveProgress()
	local comp = H.comp(G.Evolution)
	if not comp then return 0 end

	local ok, value = pcall(function() return comp:GetEvolutionProgress() end)
	return ok and tonumber(value) or 0
end

function H.ascendProgress()
	local comp = H.comp(G.Ascension)
	if not comp then return 0 end

	local ok, value = pcall(function() return comp:GetAscensionProgress() end)
	return ok and tonumber(value) or 0
end

function H.money(logValue)
	if logValue == nil or logValue ~= logValue then return "-" end
	if logValue == -math.huge then return "0" end

	if G.Huge then
		local ok, text = pcall(function() return G.Huge.formatAbbreviated(logValue) end)
		if ok and text then return tostring(text) end

		local fine, short = pcall(function() return G.Huge.formatShort(logValue) end)
		if fine and short then return tostring(short) end
	end

	return string.format("1e%.2f", logValue)
end

function H.subtractLog(a, b)
	if b == -math.huge then return a end
	if a == -math.huge or b >= a then return -math.huge end

	local gap = b - a

	if gap < -15 then return a end

	return a + math.log10(1 - 10 ^ gap)
end

function H.logOf(plain)
	plain = tonumber(plain) or 0
	if plain <= 0 then return -math.huge end
	return math.log10(plain)
end

function H.timeText(seconds)
	seconds = math.max(0, math.floor(tonumber(seconds) or 0))

	if seconds >= 3600 then return string.format("%dh%02dm", seconds // 3600, (seconds % 3600) // 60) end
	if seconds >= 60 then return string.format("%dm%02ds", seconds // 60, seconds % 60) end

	return seconds .. "s"
end

function H.contains(list, value)
	if value == nil then return false end

	for _, item in ipairs(list) do
		if item == value then return true end
	end

	return false
end

function H.selection(selected)
	local out = {}

	if type(selected) == "table" then
		for _, name in ipairs(selected) do table.insert(out, tostring(name)) end
	end

	return out
end

function H.purchases()
	local comp = H.comp(G.Analyzer)
	if not comp then return nil end

	local ok, value = pcall(function() return comp:GetPurchases() end)
	return ok and type(value) == "table" and value or nil
end

function H.earners()
	local comp = H.comp(G.Analyzer)
	if not comp then return nil end

	local ok, value = pcall(function() return comp:GetEarners() end)
	return ok and type(value) == "table" and value or nil
end

function H.nextPurchase()
	local purchases = H.purchases()
	if not purchases or not G.Balance or type(G.Balance.PurchaseOrder) ~= "table" then return nil end

	for index, id in ipairs(G.Balance.PurchaseOrder) do
		local purchase = purchases[id]

		if purchase then
			local ok, enabled = pcall(function() return purchase:IsEnabled() end)
			local fine, bought = pcall(function() return purchase:IsPurchased() end)

			if ok and fine and enabled and not bought then
				return purchase, id, index
			end
		end
	end

	return nil
end

function H.anythingToBuy()
	if not Plot then return false end

	local root = Plot:FindFirstChild("Purchases")
	if not root then return false end

	for _, child in ipairs(root:GetDescendants()) do
		if child:IsA("Model") then
			local shown = child:GetAttribute("Shown")
			local bought = child:GetAttribute("Purchased")

			if shown == true and bought ~= true then return true end
		end
	end

	return false
end

function H.earnerNames()
	local names = {}
	local earners = H.earners()

	if earners then
		for name in pairs(earners) do table.insert(names, tostring(name)) end
	end

	table.sort(names)

	if #names == 0 then
		for _, name in ipairs({
			"LemonStand", "LemonDash", "LemonDepot", "LemonTrading",
			"LemonLabs", "LemonRobotics", "LemonRepublic", "LemonX",
		}) do
			table.insert(names, name)
		end
	end

	return names
end

function H.powerNames()
	local names = {}

	if G.Config and type(G.Config.Powers) == "table" then
		for name in pairs(G.Config.Powers) do table.insert(names, tostring(name)) end
	end

	table.sort(names)

	if #names == 0 then
		names = { "AutoFruit", "BuyNext", "ClickFruitValue", "Jetpack", "Manage", "UpgradeStack", "WalkSpeed" }
	end

	return names
end

local ORCHARD = (G.Config and type(G.Config.Orchard) == "table") and G.Config.Orchard or {}

function H.mutationList()
	local list = {}

	if type(ORCHARD.Mutations) == "table" then
		for key, def in pairs(ORCHARD.Mutations) do
			if type(def) == "table" then
				table.insert(list, {
					Key = tostring(key),
					Name = tostring(def.DisplayName or key),
					Effect = tostring(def.Effect or "?"),
					Value = tonumber(def.EffectValue) or 0,
					Good = def.Good == true,
					Weight = tonumber(def.Weight) or 0,
					SoftMax = tonumber(def.SoftMax) or 0,
					Tokens = tonumber(def.TokenValue) or 0,
					Order = tonumber(def.Order) or 999,
				})
			end
		end
	end

	table.sort(list, function(a, b)
		if a.Order ~= b.Order then return a.Order < b.Order end
		return a.Key < b.Key
	end)

	return list
end

local MUTATIONS = H.mutationList()
local MUTATION_BY_NAME = {}
local MUTATION_BY_KEY = {}

for _, entry in ipairs(MUTATIONS) do
	MUTATION_BY_KEY[entry.Key] = entry
	MUTATION_BY_NAME[entry.Name] = entry
end

local MUTATION_CHOICES = {}

for _, entry in ipairs(MUTATIONS) do
	table.insert(MUTATION_CHOICES, entry.Name .. (entry.Good and "" or " (bad)"))
end

local MUTATION_BY_LABEL = {}

for index, entry in ipairs(MUTATIONS) do
	MUTATION_BY_LABEL[MUTATION_CHOICES[index]] = entry
end

function H.orchardItems(kind)
	local list = {}

	if type(ORCHARD.Items) == "table" then
		for key, def in pairs(ORCHARD.Items) do
			if type(def) == "table" then
				local isUpgrade = def.Upgrade ~= nil

				if (kind == "upgrade") == isUpgrade then
					table.insert(list, {
						Key = tostring(key),
						Name = tostring(def.DisplayName or key),
						Price = tonumber(def.Price) or 0,
						Upgrade = def.Upgrade and tostring(def.Upgrade) or nil,
						Blurb = tostring(def.Blurb or ""),
						Order = tonumber(def.Order) or 999,
					})
				end
			end
		end
	end

	table.sort(list, function(a, b) return a.Order < b.Order end)

	return list
end

local FERTILIZERS = H.orchardItems("item")
local PLOT_ITEMS = H.orchardItems("upgrade")

local FERTILIZER_CHOICES = {}
local FERTILIZER_BY_LABEL = {}

for _, entry in ipairs(FERTILIZERS) do
	local label = entry.Name .. "  " .. tostring(entry.Price) .. "t"
	table.insert(FERTILIZER_CHOICES, label)
	FERTILIZER_BY_LABEL[label] = entry
end

if #FERTILIZER_CHOICES == 0 then
	FERTILIZER_CHOICES = { "(orchard config missing)" }
end

local UPGRADE_CHOICES = {}
local UPGRADE_BY_LABEL = {}

for _, entry in ipairs(PLOT_ITEMS) do
	local label = entry.Name .. "  " .. tostring(entry.Price) .. "t"
	table.insert(UPGRADE_CHOICES, label)
	UPGRADE_BY_LABEL[label] = entry
end

if #UPGRADE_CHOICES == 0 then
	UPGRADE_CHOICES = { "(orchard config missing)" }
end

function H.orchardRoot()
	if not Plot then return nil end
	return Plot:FindFirstChild("Orchard")
end

function H.plotFolder()
	local orchard = H.orchardRoot()
	if not orchard then return nil end

	return orchard:FindFirstChild("Plots") or orchard
end

function H.plots()
	local folder = H.plotFolder()
	local list = {}

	if not folder then return list end

	for _, child in ipairs(folder:GetChildren()) do
		if child.Name:match("^Plot%d+$") then table.insert(list, child) end
	end

	table.sort(list, function(a, b)
		local ai = tonumber(a:GetAttribute("ID")) or 0
		local bi = tonumber(b:GetAttribute("ID")) or 0
		return ai < bi
	end)

	return list
end

function H.plotInfo(plot)
	local info = {
		Plot = plot,
		ID = tonumber(plot:GetAttribute("ID")) or 0,
		State = tonumber(plot:GetAttribute("State")) or 0,
		Available = plot:GetAttribute("Available") == true,
		Enabled = plot:GetAttribute("Enabled") == true,
		Base = plot:GetAttribute("BaseUnlocked") == true,
		Mound = plot:GetAttribute("DirtMoundUnlocked") == true,
		Irrigation = plot:GetAttribute("IrrigationUnlocked") == true,
		Enricher = plot:GetAttribute("EnricherUnlocked") == true,
		Clover = plot:GetAttribute("CloverUnlocked") == true,
		Radioactive = plot:GetAttribute("RadioactiveUnlocked") == true,
	}

	local owned = {}

	if info.Radioactive then table.insert(owned, "Radio") end
	if info.Clover then table.insert(owned, "Clover") end
	if info.Irrigation then table.insert(owned, "Irrig") end
	if info.Enricher then table.insert(owned, "Enrich") end
	if info.Mound then table.insert(owned, "Mound") end

	info.Owned = #owned > 0 and table.concat(owned, "+") or "-"

	return info
end

function H.getFruit(plot)
	local remote = H.coreRequest("OrchardPlot.GetFruit")
	if not remote then return nil end

	local ok, result = pcall(function() return remote:InvokeServer(plot) end)
	if not ok then return nil end

	return result
end

function H.fruitMutations(fruit)
	local found = {}

	if type(fruit) ~= "table" then return found end

	local function absorb(value)
		if type(value) ~= "table" then return end

		for key, item in pairs(value) do
			if type(key) == "string" and MUTATION_BY_KEY[key] then
				local count = tonumber(item) or (item == true and 1) or 0
				if count > 0 then found[key] = (found[key] or 0) + count end
			elseif type(item) == "string" and MUTATION_BY_KEY[item] then
				found[item] = (found[item] or 0) + 1
			elseif type(item) == "table" then
				local name = item.Mutation or item.Name or item.Key or item.Type

				if type(name) == "string" and MUTATION_BY_KEY[name] then
					found[name] = (found[name] or 0) + (tonumber(item.Count) or 1)
				end
			end
		end
	end

	absorb(fruit)
	absorb(fruit.Mutations)
	absorb(fruit.Mutation)
	absorb(fruit.Attributes)

	return found
end

function H.fruitScore(found)
	local value, tokens = 1, 0
	local good, bad = 0, 0

	for key, count in pairs(found) do
		local entry = MUTATION_BY_KEY[key]

		if entry then
			tokens = tokens + entry.Tokens * count

			if entry.Effect == "Value" then
				if entry.Good then
					value = value * (1 + entry.Value * count)
				else
					value = value * (entry.Value ^ count)
				end
			end

			if entry.Good then good = good + count else bad = bad + count end
		end
	end

	return value, tokens, good, bad
end

function H.fruitLabel(found)
	local parts = {}

	for key, count in pairs(found) do
		local entry = MUTATION_BY_KEY[key]
		local name = entry and entry.Name or key
		table.insert(parts, count > 1 and (name .. " x" .. count) or name)
	end

	table.sort(parts)

	if #parts == 0 then return "-" end

	return table.concat(parts, ", ")
end

function H.wantedMutation(found)
	if #F.orchardKeep == 0 then return false end

	for key in pairs(found) do
		local entry = MUTATION_BY_KEY[key]
		if entry and H.contains(F.orchardKeep, entry.Name) then return true end
	end

	return false
end

local StealHook = nil

function H.hook(title, fields, color)
	if not StealHook then return end

	pcall(function()
		StealHook:Embed({
			Title = title,
			Fields = fields,
			Color = color or Color3.fromRGB(255, 220, 90),
			Footer = LocalPlayer.DisplayName,
		})
	end)
end

function H.doBuy()
	if Busy.buy then return end
	Busy.buy = true

	pcall(function()
		local purchase, id = H.nextPurchase()
		if not purchase then return end

		if F.buyForever then
			-- .Instance requires Plugin capability — find the model in the plot directly
			local remote = nil

			if Plot then
				local root = Plot:FindFirstChild("Purchases")

				if root then
					-- match by purchase id (key in PurchaseOrder)
					local model = root:FindFirstChild(tostring(id), true)

					if model then
						remote = model:FindFirstChild("Purchase", true)

						-- fallback: any RemoteFunction one level down
						if not remote then
							for _, child in ipairs(model:GetDescendants()) do
								if child:IsA("RemoteFunction") then
									remote = child
									break
								end
							end
						end
					end
				end
			end

			if remote and remote:IsA("RemoteFunction") then
				local ok = pcall(function() remote:InvokeServer(true) end)

				if ok then
					Tally.bought = Tally.bought + 1
					Busy.buy = false
					return
				end
			end
		end

		local ok = pcall(function() purchase:TryPurchaseAsync() end)
		if ok then Tally.bought = Tally.bought + 1 end
	end)

	Busy.buy = false
end

function H.doUpgrade()
	if Busy.upgrade then return end
	Busy.upgrade = true

	pcall(function()
		local earners = H.earners()
		if not earners then return end

		local wallet = H.cash()
		local reserve = tonumber(F.upgradeReserve) or 0
		local floor = reserve > 0 and H.logOf(reserve) or -math.huge

		for name, earner in pairs(earners) do
			if not F.upgrade or not Alive then break end

			local wanted = #F.upgradeEarners == 0 or H.contains(F.upgradeEarners, tostring(name))

			if wanted then
				local ok, enabled = pcall(function() return earner:IsEnabled() end)

				if ok and enabled then
					local fine, info = pcall(function() return earner:GetNextUpgradeInfo() end)

					if fine and type(info) == "table" and not info.Max then
						local price = tonumber(info.Price)
						local affordable = price ~= nil and price <= wallet

						if affordable and floor ~= -math.huge then
							affordable = H.subtractLog(wallet, price) >= floor
						end

						if affordable then
							local bought = pcall(function() earner:Upgrade(info.Count, true) end)

							if bought then
								Tally.upgraded = Tally.upgraded + 1
								wallet = H.cash()
							end

							task.wait(0.01)
						end
					end
				end
			end
		end
	end)

	Busy.upgrade = false
end

local rebirthStuckAt = 0
local rebirthTimerAt = tick()
local rebirthLastAt = 0
local rebirthConflictAt = 0

function H.shouldRebirth()
	if F.rebirthOnStuck and F.rebirthOnTimer then
		if tick() - rebirthConflictAt > 10 then
			rebirthConflictAt = tick()
			clog("Pick one rebirth trigger, the stuck check and the timer fight each other")
		end

		return false
	end

	local maxPer = math.floor(tonumber(F.rebirthMaxPerEvolve) or 0)

	if maxPer > 0 and H.rebirthCount() >= maxPer then return false end

	if F.rebirthOnTimer then
		return tick() - rebirthTimerAt >= math.max(1, tonumber(F.rebirthTimerWait) or 60)
	end

	if F.rebirthOnStuck then
		if H.anythingToBuy() then
			rebirthStuckAt = 0
		else
			if rebirthStuckAt == 0 then rebirthStuckAt = tick() end

			if tick() - rebirthStuckAt >= math.max(1, tonumber(F.rebirthStuckWait) or 30) then
				return true
			end
		end
	end

	local potential = H.potential()
	if potential == -math.huge then return false end

	local minimum = tonumber(F.rebirthMinPotential) or 0

	if minimum > 0 and potential < H.logOf(minimum) then return false end

	local factor = tonumber(F.rebirthFactor) or 0

	if factor > 0 then
		local current = H.investors()
		local base = current == -math.huge and 0 or current
		return potential >= base + math.log10(factor)
	end

	if minimum > 0 then return true end

	return false
end

function H.doRebirth()
	if Busy.rebirth then return end
	if tick() - rebirthLastAt < 3 then return end
	if not H.shouldRebirth() then return end

	Busy.rebirth = true

	local before = H.rebirthCount()
	local potential = H.potential()

	local comp = H.comp(G.Rebirth)
	local done = false

	if comp then
		done = pcall(function() comp:RebirthAsync() end)
	end

	if not done then
		local remote = H.remote("Rebirth")
		if remote then done = pcall(function() remote:InvokeServer() end) end
	end

	if done then
		Tally.rebirths = Tally.rebirths + 1
		rebirthLastAt = tick()
		rebirthTimerAt = tick()
		rebirthStuckAt = 0

		clog("Rebirthed, brought in " .. H.money(potential) .. " investors")

		if F.hookRebirth then
			H.hook("Rebirth", {
				{ Name = "Investors gained", Value = H.money(potential), Inline = true },
				{ Name = "Rebirths this evolution", Value = tostring(before + 1), Inline = true },
				{ Name = "Evolution", Value = tostring(H.evolution()), Inline = true },
			}, Color3.fromRGB(120, 200, 255))
		end

		task.wait(2)
	end

	Busy.rebirth = false
end

function H.doEvolve()
	if H.evolveProgress() < 1 then return end

	local cap = math.floor(tonumber(F.evolveMax) or 0)

	if cap > 0 and H.evolution() >= cap then return end

	local before = H.evolution()
	local comp = H.comp(G.Evolution)
	local done = false

	if comp then
		done = pcall(function() comp:EvolveAsync() end)
	end

	if not done then
		local remote = H.remote("Evolve")
		if remote then done = pcall(function() remote:InvokeServer() end) end
	end

	if done then
		Tally.evolves = Tally.evolves + 1
		rebirthTimerAt = tick()

		clog("Evolved, now at tier " .. tostring(before + 1))

		if F.hookEvolve then
			H.hook("Evolution", {
				{ Name = "Tier", Value = tostring(before + 1), Inline = true },
				{ Name = "Rebirths spent", Value = tostring(H.rebirthCount()), Inline = true },
			}, Color3.fromRGB(190, 140, 255))
		end

		task.wait(3)
	end
end

function H.finalStaircase()
	local purchases = H.purchases()
	if not purchases then return nil end

	for _, key in ipairs({ "StaircaseStepFinal", "StaircasePlatformFinal", "StaircaseFinal" }) do
		if purchases[key] then return purchases[key] end
	end

	for key, purchase in pairs(purchases) do
		local lower = tostring(key):lower()
		if lower:find("staircase") and lower:find("final") then return purchase end
	end

	return nil
end

function H.doAscend()
	if Busy.ascend then return end

	local cap = math.floor(tonumber(F.ascendMax) or 0)
	if cap > 0 and H.ascension() >= cap then return end

	local comp = H.comp(G.Ascension)
	if not comp then return end

	if H.ascendProgress() < 1 then
		local final = H.finalStaircase()
		if not final then return end

		local ok, bought = pcall(function() return final:IsPurchased() end)
		if ok and bought then return end

		local fine, price = pcall(function() return final:GetPrice() end)
		if not fine or not tonumber(price) then return end
		if H.cash() < price then return end

		Busy.ascend = true

		local saved = { upgrade = F.upgrade, rebirth = F.rebirth, evolve = F.evolve, powers = F.powers }

		F.upgrade, F.rebirth, F.evolve, F.powers = false, false, false, false
		F.buy = true

		clog("Buying the last staircase step to open the ascend")

		local deadline = tick() + 60
		local broke = false

		repeat
			task.wait(0.25)

			local stillOk, stillBought = pcall(function() return final:IsPurchased() end)

			if stillOk and stillBought then break end

			local priceOk, current = pcall(function() return final:GetPrice() end)

			if priceOk and tonumber(current) and H.cash() < current then
				broke = true
			else
				pcall(function() final:TryPurchaseAsync() end)
				final = H.finalStaircase() or final
			end
		until broke or tick() > deadline

		F.upgrade, F.rebirth, F.evolve, F.powers = saved.upgrade, saved.rebirth, saved.evolve, saved.powers

		if broke or tick() > deadline then
			clog(broke and "Ran out of cash before the last step" or "The last step timed out")
			Busy.ascend = false
			return
		end
	end

	Busy.ascend = true

	local before = H.ascension()
	local tries = 0

	repeat
		pcall(function() comp:AscendAsync() end)
		task.wait(0.5)
		tries = tries + 1
	until H.ascension() > before or tries >= 26 or not Alive

	if H.ascension() > before then
		Tally.ascends = Tally.ascends + 1
		rebirthTimerAt = tick()

		clog("Ascended, now at " .. tostring(H.ascension()))

		if F.hookAscend then
			H.hook("Ascension", {
				{ Name = "Ascension", Value = tostring(H.ascension()), Inline = true },
				{ Name = "Evolutions spent", Value = tostring(H.evolution()), Inline = true },
			}, Color3.fromRGB(255, 180, 90))
		end
	else
		clog("The ascend did not take after 26 tries")
	end

	Busy.ascend = false
end

function H.doPowers()
	local comp = H.comp(G.Powers)
	if not comp then return end

	local ok, levels = pcall(function() return comp:GetLevels() end)
	if not ok or type(levels) ~= "table" then return end

	local investors = H.investors()
	if investors == -math.huge then return end

	local share = math.clamp(tonumber(F.powerBudget) or 50, 1, 100) / 100
	local budget = investors + math.log10(share)

	for name, level in pairs(levels) do
		if not F.powers or not Alive then break end

		local wanted = #F.powerPicks == 0 or H.contains(F.powerPicks, tostring(name))

		if wanted then
			local maxOk, maximum = pcall(function() return comp:GetMaxLevel(name) end)

			if not maxOk or not maximum or level < maximum then
				local priceOk, price = pcall(function() return comp:GetUpgradePrice(name) end)

				if priceOk and tonumber(price) and price <= budget then
					local done = pcall(function() comp:UpgradeAsync(name) end)

					if done then
						Tally.powers = Tally.powers + 1
						clog("Power up: " .. tostring(name) .. " to " .. tostring(level + 1))
					end

					task.wait(0.15)
				end
			end
		end
	end
end

function H.doWake()
	local remote = H.remote("WakeIncomeStream")
	if not remote then return end

	local streams = H.values("Income.Streams")
	if not streams then return end

	for _, stream in ipairs(streams:GetChildren()) do
		if not F.wake or not Alive then break end

		local automatic = stream:GetAttribute("Automatic")

		if automatic ~= true then
			local ok = pcall(function() remote:InvokeServer(stream.Name) end)

			if ok then
				Tally.woken = Tally.woken + 1
			end

			task.wait(0.05)
		end
	end
end

local phoneConnected = false

function H.watchPhone()
	if phoneConnected then return end

	local remote = H.remote("PhoneOffer")
	if not remote or not remote:IsA("RemoteEvent") then return end

	phoneConnected = true

	local connection = remote.OnClientEvent:Connect(function(value)
		if not F.phone then return end
		if type(value) ~= "number" then return end

		pcall(function() remote:FireServer("Accept") end)
		Tally.offers = Tally.offers + 1
		clog("Took the call, offer worth " .. H.money(value))
	end)

	onCleanup(function() pcall(function() connection:Disconnect() end) end)
end

function H.doPhone()
	local comp = H.comp(G.PhoneOffers)
	if not comp then return end

	local ok, offer = pcall(function() return comp:GetCurrentOffer() end)
	if not ok or type(offer) ~= "number" then return end

	local remote = H.remote("PhoneOffer")
	if not remote then return end

	pcall(function() remote:FireServer("Accept") end)
	Tally.offers = Tally.offers + 1
end

local fruitSaved = nil
local fruitPatched = {}

function H.restoreDetectors()
	for detector, distance in pairs(fruitPatched) do
		pcall(function() detector.MaxActivationDistance = distance end)
	end

	table.clear(fruitPatched)
end

onCleanup(H.restoreDetectors)

function H.treeFolder()
	if not Plot then return nil end

	local constant = Plot:FindFirstChild("Constant")
	return constant and constant:FindFirstChild("Trees") or nil
end

function H.doFruit()
	if type(fireclickdetector) ~= "function" then
		Status = "No fireclickdetector"
		return
	end

	local folder = H.treeFolder()
	if not folder then return end

	local character = LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return end

	if F.fruitMode == "Teleport" and not fruitSaved then
		fruitSaved = root.CFrame
	end

	for _, tree in ipairs(folder:GetChildren()) do
		if not F.fruit or not Alive then break end

		for _, child in ipairs(tree:GetChildren()) do
			if not F.fruit or not Alive then break end

			if child.Name == "Fruit" then
				local clickPart = child:FindFirstChild("ClickPart") or child:FindFirstChild("ClickFruitPart")
				local detector = clickPart and clickPart:FindFirstChildOfClass("ClickDetector")

				if detector then
					if F.fruitMode == "Reach" then
						if not fruitPatched[detector] then
							local ok, saved = pcall(function() return detector.MaxActivationDistance end)
							if ok then
								fruitPatched[detector] = saved
								pcall(function() detector.MaxActivationDistance = 2000 end)
							end
						end
					else
						pcall(function()
							root.CFrame = clickPart.CFrame + Vector3.new(0, 4, 0)
						end)
						task.wait(0.04)
					end

					pcall(fireclickdetector, detector)
					Tally.fruit = Tally.fruit + 1

					task.wait(math.clamp(tonumber(F.fruitDelay) or 0.08, 0.02, 1))
				end
			end
		end
	end

	if F.fruitMode == "Teleport" and F.fruitReturn and fruitSaved then
		pcall(function() root.CFrame = fruitSaved end)
		fruitSaved = nil
	end
end

function H.plantPlot(plot)
	local remote = H.coreRequest("OrchardPlot.Plant")
	if not remote then return false end

	local ok = pcall(function() return remote:InvokeServer(plot) end)

	if ok then
		Tally.planted = Tally.planted + 1
		return true
	end

	return false
end

function H.harvestPlot(plot)
	local remote = H.coreRequest("OrchardPlot.Harvest")
	if not remote then return false end

	local ok = pcall(function() return remote:InvokeServer(plot) end)

	if ok then
		Tally.harvested = Tally.harvested + 1
		return true
	end

	return false
end

function H.razePlot(plot)
	local remote = H.coreRequest("OrchardPlot.DestroyTree")
	if not remote then return false end

	local ok = pcall(function() return remote:InvokeServer(plot) end)

	if ok then
		Tally.razed = Tally.razed + 1
		return true
	end

	return false
end

function H.useItem(plot, itemKey)
	local remote = H.coreRequest("OrchardPlot.UseItem")
	if not remote then return false end

	for _, args in ipairs({ { plot, itemKey }, { plot, itemKey, 1 }, { itemKey, plot } }) do
		local ok, result = pcall(function() return remote:InvokeServer(table.unpack(args)) end)
		if ok and result ~= false then return true end
	end

	return false
end

function H.buyOrchardItem(itemKey, amount)
	local remote = H.remote("BuyOrchardItems")
	if not remote then return false end

	for _, args in ipairs({ { itemKey, amount or 1 }, { itemKey }, { { [itemKey] = amount or 1 } } }) do
		local ok, result = pcall(function() return remote:InvokeServer(table.unpack(args)) end)
		if ok and result ~= false then return true end
	end

	return false
end

function H.eatFruit(plot)
	local remote = H.remote("EatFruit")
	if not remote then return false end

	for _, args in ipairs({ { plot }, {} }) do
		local ok, result = pcall(function() return remote:InvokeServer(table.unpack(args)) end)

		if ok and result ~= false then
			Tally.eaten = Tally.eaten + 1
			return true
		end
	end

	return false
end

function H.sellFruits(plot)
	local remote = H.remote("SellFruits")
	if not remote then return false end

	for _, args in ipairs({ { plot }, {} }) do
		local ok, result = pcall(function() return remote:InvokeServer(table.unpack(args)) end)

		if ok and result ~= false then
			Tally.sold = Tally.sold + 1
			return true
		end
	end

	return false
end

function H.unlockPlot(plot)
	local remote = H.remote("UnlockPlot")
	if not remote then return false end

	for _, args in ipairs({ { plot }, { plot:GetAttribute("ID") } }) do
		local ok, result = pcall(function() return remote:InvokeServer(table.unpack(args)) end)
		if ok and result ~= false then return true end
	end

	return false
end

local orchardSeen = {}

function H.orchardTick()
	if Busy.orchard then return end

	local plots = H.plots()
	if #plots == 0 then return end

	Busy.orchard = true

	pcall(function()
		local tokens = H.tokens()
		local floor = math.max(0, tonumber(F.orchardTokenFloor) or 0)

		for _, plot in ipairs(plots) do
			if not F.orchard or not Alive then break end

			local info = H.plotInfo(plot)

			if info.Enabled then
				if F.orchardAutoUpgrade and #F.orchardUpgrades > 0 then
					for _, label in ipairs(F.orchardUpgrades) do
						local item = UPGRADE_BY_LABEL[label]

						if item and item.Upgrade then
							local already = info[item.Upgrade] == true

							if not already and tokens - item.Price >= floor then
								if H.buyOrchardItem(item.Key, 1) and H.useItem(plot, item.Key) then
									tokens = H.tokens()
									clog("Plot " .. info.ID .. " now runs " .. item.Name)
									task.wait(0.3)
								end
							end
						end
					end
				end

				local fruit = H.getFruit(plot)
				local found = H.fruitMutations(fruit)
				local hasFruit = fruit ~= nil and fruit ~= false

				if hasFruit and next(found) ~= nil then
					local value, worth, good, bad = H.fruitScore(found)
					local label = H.fruitLabel(found)
					local keep = H.wantedMutation(found)

					if orchardSeen[info.ID] ~= label then
						orchardSeen[info.ID] = label
						clog("Plot " .. info.ID .. " grew " .. label)

						if value > Tally.bestValue then
							Tally.bestValue = value
							Tally.best = label
						end

						if F.hookMutation and (keep or not F.hookMutationKeep) then
							H.hook("Mutation rolled", {
								{ Name = "Plot", Value = tostring(info.ID), Inline = true },
								{ Name = "Cash factor", Value = string.format("x%.2f", value), Inline = true },
								{ Name = "Tokens", Value = string.format("%.1f", worth), Inline = true },
								{ Name = "Mutations", Value = label, Inline = false },
							}, keep and Color3.fromRGB(120, 230, 150) or Color3.fromRGB(150, 150, 160))
						end
					end

					if keep then
						if H.harvestPlot(plot) then
							task.wait(0.2)

							if F.orchardAction == "Eat" then
								H.eatFruit(plot)
							elseif F.orchardAction == "Sell" then
								H.sellFruits(plot)
								Tally.tokens = Tally.tokens + worth
							end

							orchardSeen[info.ID] = nil
							task.wait(0.2)
						end
					elseif #F.orchardKeep > 0 then
						if F.orchardAction == "Sell" then
							if H.harvestPlot(plot) then
								task.wait(0.2)
								H.sellFruits(plot)
								Tally.tokens = Tally.tokens + worth
								orchardSeen[info.ID] = nil
							end
						elseif H.razePlot(plot) then
							orchardSeen[info.ID] = nil
							clog("Plot " .. info.ID .. " razed, nothing worth keeping")
							task.wait(0.2)
						end
					end
				elseif not hasFruit and F.orchardPlant then
					if info.State == 0 and H.plantPlot(plot) then
						orchardSeen[info.ID] = nil
						task.wait(0.25)

						if F.orchardFertilize then
							local item = FERTILIZER_BY_LABEL[F.orchardFertilizer]

							if item and tokens - item.Price >= floor then
								if H.buyOrchardItem(item.Key, 1) and H.useItem(plot, item.Key) then
									tokens = H.tokens()
									task.wait(0.2)
								end
							end
						end
					end
				end
			elseif info.Available and F.orchardUnlock then
				H.unlockPlot(plot)
				task.wait(0.3)
			end
		end
	end)

	Busy.orchard = false
end

local VISIT_TTL = 2700
local hopBusy = false
local lastHopAt = 0

function H.loadVisited()
	local out = {}
	local data = readJson(userFile("visited"))
	if type(data) ~= "table" then return out end

	local now = os.time()

	for job, stamp in pairs(data) do
		stamp = tonumber(stamp)
		if type(job) == "string" and stamp and now - stamp < VISIT_TTL then out[job] = stamp end
	end

	return out
end

function H.saveVisited(visited)
	local list = {}
	for job, stamp in pairs(visited) do table.insert(list, { job = job, ts = stamp }) end

	if #list > 200 then
		table.sort(list, function(a, b) return a.ts > b.ts end)
		local kept = {}
		for index = 1, 200 do kept[list[index].job] = list[index].ts end
		visited = kept
	end

	writeJson(userFile("visited"), visited)
end

function H.hop(lowPop)
	task.spawn(function()
		if os.clock() - lastHopAt < 30 then
			notify("Server Hop", "On cooldown.", "warning", 4)
			return
		end

		lastHopAt = os.clock()
		notify("Server Hop", "Looking for a server.", "info", 3)

		local visited = H.loadVisited()
		local candidates, cursor, pages = {}, nil, 0
		local order = lowPop and "Asc" or "Desc"

		while pages < 3 do
			local url = "https://games.roblox.com/v1/games/" .. tostring(game.PlaceId)
				.. "/servers/Public?sortOrder=" .. order .. "&limit=100&excludeFullGames=true"

			if cursor then url = url .. "&cursor=" .. HttpService:UrlEncode(cursor) end

			local ok, body = pcall(function() return game:HttpGet(url) end)
			if not ok then break end

			local fine, payload = pcall(function() return HttpService:JSONDecode(body) end)
			if not (fine and type(payload) == "table" and payload.data) then break end

			for _, server in ipairs(payload.data) do
				if server.id ~= game.JobId and not visited[server.id]
					and (tonumber(server.playing) or 0) < (tonumber(server.maxPlayers) or 99) then
					table.insert(candidates, server)
				end
			end

			cursor = payload.nextPageCursor
			pages = pages + 1
			if not cursor then break end
		end

		local myJob = game.JobId
		visited[myJob] = os.time()

		if #candidates == 0 then
			local oldest, oldestAt = nil, nil

			for job, stamp in pairs(visited) do
				if job ~= myJob and (not oldestAt or stamp < oldestAt) then oldest, oldestAt = job, stamp end
			end

			H.saveVisited(visited)
			hopBusy = true

			if oldest then
				notify("Server Hop", "All recent ones visited, going back to the oldest.", "info", 5)
				if not pcall(function()
					TeleportService:TeleportToPlaceInstance(game.PlaceId, oldest, LocalPlayer)
				end) then
					pcall(function() TeleportService:Teleport(game.PlaceId, LocalPlayer) end)
				end
			else
				pcall(function() TeleportService:Teleport(game.PlaceId, LocalPlayer) end)
			end

			hopBusy = false
			return
		end

		table.sort(candidates, function(a, b)
			if lowPop then return (a.playing or 0) < (b.playing or 0) end
			return (a.playing or 0) > (b.playing or 0)
		end)

		hopBusy = true

		local failMessage, pending = nil, false

		local connection = TeleportService.TeleportInitFailed:Connect(function(player, result, message)
			if player == LocalPlayer then
				pending = false
				failMessage = tostring((message and message ~= "") and message or result)
			end
		end)

		for index = 1, math.min(5, #candidates) do
			local server = candidates[index]
			visited[server.id] = os.time()
			H.saveVisited(visited)

			failMessage, pending = nil, true

			local ok = pcall(function()
				TeleportService:TeleportToPlaceInstance(game.PlaceId, server.id, LocalPlayer)
			end)

			if ok then
				local waited = 0

				while waited < 10 and pending and game.JobId == myJob do
					task.wait(1)
					waited = waited + 1
				end

				if game.JobId ~= myJob or pending then
					pcall(function() connection:Disconnect() end)
					hopBusy = false
					return
				end
			end

			notify("Server Hop", "Try " .. index .. " failed (" .. tostring(failMessage or "unknown") .. ").", "warning", 4)
		end

		pcall(function() connection:Disconnect() end)
		hopBusy = false
		pcall(function() TeleportService:Teleport(game.PlaceId, LocalPlayer) end)
	end)
end

pcall(function()
	TeleportService.TeleportInitFailed:Connect(function(_, result, message)
		if hopBusy then return end
		notify("Teleport", tostring(message ~= "" and message or result), "error", 6)
	end)
end)

local fpsRestore = {}

function H.setFps(state)
	if state then
		table.clear(fpsRestore)

		pcall(function()
			table.insert(fpsRestore, { o = Lighting, p = "GlobalShadows", v = Lighting.GlobalShadows })
			Lighting.GlobalShadows = false
			table.insert(fpsRestore, { o = Lighting, p = "FogEnd", v = Lighting.FogEnd })
			Lighting.FogEnd = 100000
		end)

		pcall(function()
			local terrain = workspace.Terrain
			table.insert(fpsRestore, { o = terrain, p = "Decoration", v = terrain.Decoration })
			terrain.Decoration = false
			table.insert(fpsRestore, { o = terrain, p = "WaterWaveSize", v = terrain.WaterWaveSize })
			terrain.WaterWaveSize = 0
		end)

		pcall(function()
			local rendering = settings().Rendering
			table.insert(fpsRestore, { o = rendering, p = "QualityLevel", v = rendering.QualityLevel })
			rendering.QualityLevel = Enum.QualityLevel.Level01
		end)

		pcall(function()
			for _, object in ipairs(workspace:GetDescendants()) do
				if object:IsA("ParticleEmitter") or object:IsA("Trail") or object:IsA("Beam") then
					if object.Enabled then
						table.insert(fpsRestore, { o = object, p = "Enabled", v = true })
						object.Enabled = false
					end
				end
			end
		end)
	else
		for _, record in ipairs(fpsRestore) do
			pcall(function() record.o[record.p] = record.v end)
		end

		table.clear(fpsRestore)
	end
end

onCleanup(function() pcall(H.setFps, false) end)

function H.setRender(state)
	pcall(function() RunService:Set3dRenderingEnabled(not state) end)
end

onCleanup(function() pcall(H.setRender, false) end)

pcall(function()
	local connection = LocalPlayer.Idled:Connect(function()
		if not F.afk then return end

		pcall(function()
			VirtualUser:CaptureController()
			VirtualUser:ClickButton2(Vector2.new())
		end)
	end)

	onCleanup(function() pcall(function() connection:Disconnect() end) end)
end)

function H.armReexec()
	if not F.reexec then return end

	local queue = queue_on_teleport or queueonteleport

	if type(queue) ~= "function" then
		notify("Auto Execute", "This executor has no queue_on_teleport.", "error", 6)
		return
	end

	pcall(queue, 'loadstring(game:HttpGet("' .. LOADER_URL .. '"))()')
end

local HOOK_FILE = CFG_FOLDER .. "/webhooks.json"

local Hooks = { List = {}, Index = 0 }

function H.hookId(url)
	return tostring(url):match("/webhooks/(%d+)") or "unknown"
end

function H.validUrl(url)
	url = tostring(url or ""):gsub("^%s+", ""):gsub("%s+$", "")

	if not url:match("^https://[%w%.%-]*discord") then return nil end
	if not url:match("/webhooks/%d+/") then return nil end

	return url
end

function H.hookChoices()
	local names = { "None" }

	for index, entry in ipairs(Hooks.List) do
		table.insert(names, string.format("%d. %s", index, entry.Name))
	end

	return names
end

function H.saveHooks()
	writeJson(HOOK_FILE, Hooks.List)
end

function H.loadHooks()
	local data = readJson(HOOK_FILE)
	if type(data) ~= "table" then return end

	for _, entry in ipairs(data) do
		if type(entry) == "table" and H.validUrl(entry.Url) then
			table.insert(Hooks.List, {
				Url = entry.Url,
				Name = entry.Name or ("hook " .. H.hookId(entry.Url):sub(-6)),
			})
		end
	end
end

H.loadHooks()

local U = {}

local Window = Library:Window({
	Title             = "Facility",
	Suffix            = ".Sexility",
	Width             = 880,
	Height            = 620,
	MinWidth          = 700,
	MinHeight         = 400,
	SectionTitleStyle = "border",
	MobileButton      = true,
	TabStyle          = "side",
	TabWidth          = 150,
})

U.FarmTab = Window:Tab("Farm", "circle-dollar-sign")
U.ResetTab = Window:Tab("Resets", "rotate-ccw")
U.PowerTab = Window:Tab("Powers", "zap")

Window:TabDivider()

U.OrchardTab = Window:Tab("Orchard", "sprout")
U.MutationTab = Window:Tab("Mutations", "flask-conical")

Window:TabDivider()

U.StatsTab = Window:Tab("Stats", "chart-no-axes-column")
U.MoveTab = Window:Tab("Movement", "move")
U.MiscTab = Window:Tab("Misc", "wrench")
U.HookTab = Window:Tab("Webhooks", "send")
U.Settings = Window:Tab("Settings", "cog")

local EARNER_NAMES = H.earnerNames()
local POWER_NAMES = H.powerNames()
local MUTATION_NAME_LIST = {}

for _, entry in ipairs(MUTATIONS) do
	table.insert(MUTATION_NAME_LIST, entry.Name)
end

if #MUTATION_NAME_LIST == 0 then MUTATION_NAME_LIST = { "(config missing)" } end

U.statusBox = U.FarmTab:Section("Status", 1)

U.statusLabel = U.statusBox:Label("Idle")
U.cashLabel = U.statusBox:Label("-", { Style = "dim" })
U.investorLabel = U.statusBox:Label("-", { Style = "dim" })
U.readyLabel = U.statusBox:Label("-", { Style = "dim" })

if not Ready then
	U.readyLabel:Set("tycoon or framework not found, nothing will run")
	notify("Facility", "Your tycoon was not found. Claim one, then reload.", "error", 10)
elseif #G.missing > 0 then
	U.readyLabel:Set("missing: " .. table.concat(G.missing, ", "))
else
	U.readyLabel:Set("tycoon " .. Plot.Name .. ", framework loaded")
end

U.buyBox = U.FarmTab:Section("Buy Buttons", 2)

U.buyBox:Toggle({
	Text = "Auto Buy",
	Flag = "sl_buy",
	Default = false,
	Hint = "walks Balance.PurchaseOrder and buys the first affordable button",
	Callback = function(state) F.buy = state end,
})

U.buyBox:Slider({
	Text = "Interval",
	Flag = "sl_buy_delay",
	Min = 0, Max = 2, Default = 0.05,
	Decimals = 2,
	Suffix = " s",
	Callback = function(value) F.buyDelay = tonumber(value) or 0.05 end,
})

U.buyBox:Toggle({
	Text = "Forever Purchase",
	Flag = "sl_buy_forever",
	Default = false,
	Hint = "sends the remote with true, falls back to a normal buy",
	Callback = function(state) F.buyForever = state end,
})

U.buyBox:Button({
	Text = "Buy One Now",
	Callback = function() task.spawn(H.doBuy) end,
})

U.upgradeBox = U.FarmTab:Section("Upgrade Earners", 1)

U.upgradeBox:Toggle({
	Text = "Auto Upgrade",
	Flag = "sl_upgrade",
	Default = false,
	Hint = "reads the real next-upgrade price instead of spamming the remote",
	Callback = function(state) F.upgrade = state end,
})

U.upgradeBox:Dropdown({
	Text = "Earners",
	Flag = "sl_upgrade_earners",
	Options = EARNER_NAMES,
	Default = {},
	Multi = true,
	Empty = "Every earner",
	Callback = function(selected) F.upgradeEarners = H.selection(selected) end,
})

U.upgradeBox:Input({
	Text = "Keep This Much Cash",
	Flag = "sl_upgrade_reserve",
	Default = "0",
	Placeholder = "1e9",
	Callback = function(text)
		F.upgradeReserve = tonumber(tostring(text):gsub("[^%d%.eE%+%-]", "")) or 0
	end,
})

U.upgradeBox:Label("Upgrades stop before dipping under this. Plain number, 1e9 works.", { Style = "dim" })

U.upgradeBox:Slider({
	Text = "Interval",
	Flag = "sl_upgrade_delay",
	Min = 0.05, Max = 5, Default = 0.25,
	Decimals = 2,
	Suffix = " s",
	Callback = function(value) F.upgradeDelay = tonumber(value) or 0.25 end,
})

U.incomeBox = U.FarmTab:Section("Income And Offers", 2)

U.incomeBox:Toggle({
	Text = "Wake Sleeping Streams",
	Flag = "sl_wake",
	Default = false,
	Hint = "only pokes streams whose Automatic attribute is false",
	Callback = function(state) F.wake = state end,
})

U.incomeBox:Toggle({
	Text = "Take Phone Offers",
	Flag = "sl_phone",
	Default = false,
	Callback = function(state)
		F.phone = state
		if state then H.watchPhone() end
	end,
})

U.fruitBox = U.FarmTab:Section("Tree Fruit", "full")

U.fruitBox:Toggle({
	Text = "Click The Trees",
	Flag = "sl_fruit",
	Default = false,
	Callback = function(state)
		F.fruit = state
		if not state then H.restoreDetectors() end
	end,
})

U.fruitBox:Dropdown({
	Text = "Method",
	Flag = "sl_fruit_mode",
	Options = { "Reach", "Teleport" },
	Default = "Reach",
	Callback = function(value)
		F.fruitMode = tostring(value)
		if F.fruitMode == "Teleport" then H.restoreDetectors() end
	end,
})

U.fruitBox:Label("Reach widens the click detectors so you never leave your spot. Teleport hops tree to tree and comes back.", { Style = "dim" })

U.fruitBox:Slider({
	Text = "Click Gap",
	Flag = "sl_fruit_delay",
	Min = 0.02, Max = 1, Default = 0.08,
	Decimals = 2,
	Suffix = " s",
	Callback = function(value) F.fruitDelay = tonumber(value) or 0.08 end,
})

U.fruitBox:Toggle({
	Text = "Return To My Spot",
	Flag = "sl_fruit_return",
	Default = true,
	Callback = function(state) F.fruitReturn = state end,
})

U.rebirthBox = U.ResetTab:Section("Rebirth", 1)

U.rebirthBox:Toggle({
	Text = "Auto Rebirth",
	Flag = "sl_rebirth",
	Default = false,
	Callback = function(state)
		F.rebirth = state
		rebirthTimerAt = tick()
		rebirthStuckAt = 0
	end,
})

U.rebirthBox:Input({
	Text = "Investor Multiplier",
	Flag = "sl_rebirth_factor",
	Default = "10",
	Placeholder = "10",
	Callback = function(text)
		F.rebirthFactor = tonumber(tostring(text):gsub("[^%d%.]", "")) or 0
	end,
})

U.rebirthBox:Label("Rebirths when the pending investors reach your current count times this. 0 turns it off.", { Style = "dim" })

U.rebirthBox:Input({
	Text = "Minimum Pending",
	Flag = "sl_rebirth_min",
	Default = "0",
	Placeholder = "1000",
	Callback = function(text)
		F.rebirthMinPotential = tonumber(tostring(text):gsub("[^%d%.]", "")) or 0
	end,
})

U.rebirthBox:Slider({
	Text = "Cap Per Evolution",
	Flag = "sl_rebirth_cap",
	Min = 0, Max = 200, Default = 0,
	ZeroText = "0 - no cap",
	Callback = function(value) F.rebirthMaxPerEvolve = math.floor(tonumber(value) or 0) end,
})

U.triggerBox = U.ResetTab:Section("Other Triggers", 2)

U.triggerBox:Toggle({
	Text = "Rebirth When Nothing Left To Buy",
	Flag = "sl_rebirth_stuck",
	Default = false,
	Callback = function(state)
		F.rebirthOnStuck = state
		rebirthStuckAt = 0
	end,
})
	:Gear(function(panel)
		panel:Slider({
			Text = "Wait First",
			Flag = "sl_rebirth_stuck_wait",
			Min = 5, Max = 300, Default = 30,
			Suffix = " s",
			Callback = function(value) F.rebirthStuckWait = tonumber(value) or 30 end,
		})
	end)

U.triggerBox:Toggle({
	Text = "Rebirth On A Timer",
	Flag = "sl_rebirth_timer",
	Default = false,
	Callback = function(state)
		F.rebirthOnTimer = state
		rebirthTimerAt = tick()
	end,
})
	:Gear(function(panel)
		panel:Slider({
			Text = "Every",
			Flag = "sl_rebirth_timer_wait",
			Min = 10, Max = 600, Default = 60,
			Suffix = " s",
			Callback = function(value) F.rebirthTimerWait = tonumber(value) or 60 end,
		})
	end)

U.triggerBox:Label("Pick one of these two, not both. The multiplier still applies on top.", { Style = "dim" })

U.evolveBox = U.ResetTab:Section("Evolution", 1)

U.evolveBox:Toggle({
	Text = "Auto Evolve",
	Flag = "sl_evolve",
	Default = false,
	Hint = "fires when the progress bar is full",
	Callback = function(state) F.evolve = state end,
})

U.evolveBox:Slider({
	Text = "Stop At Tier",
	Flag = "sl_evolve_max",
	Min = 0, Max = 50, Default = 0,
	ZeroText = "0 - no cap",
	Callback = function(value) F.evolveMax = math.floor(tonumber(value) or 0) end,
})

U.evolveBox:Button({
	Text = "Evolve Now",
	Callback = function() task.spawn(H.doEvolve) end,
})

U.ascendBox = U.ResetTab:Section("Ascension", 2)

U.ascendBox:Toggle({
	Text = "Auto Ascend",
	Flag = "sl_ascend",
	Default = false,
	Hint = "buys the last staircase step first, pausing the other loops",
	Callback = function(state) F.ascend = state end,
})

U.ascendBox:Slider({
	Text = "Stop At",
	Flag = "sl_ascend_max",
	Min = 0, Max = 50, Default = 0,
	ZeroText = "0 - no cap",
	Callback = function(value) F.ascendMax = math.floor(tonumber(value) or 0) end,
})

U.ascendBox:Button({
	Text = "Ascend Now",
	Callback = function() task.spawn(H.doAscend) end,
})

U.progressBox = U.ResetTab:Section("Where You Are", "full")

U.progressTable = U.progressBox:Table({
	Columns = { "Track", "Now", "Progress", "Detail" },
	MaxRows = 6,
	EmptyText = "No data yet",
})

U.powerBox = U.PowerTab:Section("Auto Buy", 1)

U.powerBox:Toggle({
	Text = "Auto Buy Powers",
	Flag = "sl_powers",
	Default = false,
	Hint = "spends investors, so it only runs while you hold some",
	Callback = function(state) F.powers = state end,
})

U.powerBox:Dropdown({
	Text = "Powers",
	Flag = "sl_power_picks",
	Options = POWER_NAMES,
	Default = {},
	Multi = true,
	Empty = "Every power",
	Callback = function(selected) F.powerPicks = H.selection(selected) end,
})

U.powerBox:Slider({
	Text = "Spend At Most",
	Flag = "sl_power_budget",
	Min = 1, Max = 100, Default = 50,
	Suffix = " % of investors",
	Callback = function(value) F.powerBudget = tonumber(value) or 50 end,
})

U.powerBox:Button({
	Text = "Buy Round Now",
	Callback = function() task.spawn(H.doPowers) end,
})

U.powerListBox = U.PowerTab:Section("Levels", "full")

U.powerTable = U.powerListBox:Table({
	Columns = { "Power", "Level", "Max", "Next Price", "Affordable" },
	MaxRows = 10,
	EmptyText = "Powers component not loaded",
})

U.orchardBox = U.OrchardTab:Section("Farm Loop", 1)

U.orchardBox:Toggle({
	Text = "Run The Orchard",
	Flag = "sl_orchard",
	Default = false,
	Callback = function(state) F.orchard = state end,
})

U.orchardBox:Toggle({
	Text = "Plant Empty Plots",
	Flag = "sl_orchard_plant",
	Default = true,
	Callback = function(state) F.orchardPlant = state end,
})

U.orchardBox:Toggle({
	Text = "Unlock Plots When Offered",
	Flag = "sl_orchard_unlock",
	Default = false,
	Hint = "calls UnlockPlot on any plot the game marks Available",
	Callback = function(state) F.orchardUnlock = state end,
})

U.orchardBox:Slider({
	Text = "Sweep Every",
	Flag = "sl_orchard_delay",
	Min = 0.5, Max = 30, Default = 1,
	Decimals = 1,
	Suffix = " s",
	Callback = function(value) F.orchardDelay = tonumber(value) or 1 end,
})

U.fertBox = U.OrchardTab:Section("Fertilizer", 2)

U.fertBox:Toggle({
	Text = "Fertilize After Planting",
	Flag = "sl_orchard_fert",
	Default = false,
	Callback = function(state) F.orchardFertilize = state end,
})

U.fertBox:Dropdown({
	Text = "Use",
	Flag = "sl_orchard_fert_pick",
	Options = FERTILIZER_CHOICES,
	Default = FERTILIZER_CHOICES[1],
	Callback = function(value) F.orchardFertilizer = tostring(value) end,
})

U.fertBox:Slider({
	Text = "Keep At Least",
	Flag = "sl_orchard_token_floor",
	Min = 0, Max = 100000, Default = 0,
	Suffix = " tokens",
	Callback = function(value) F.orchardTokenFloor = tonumber(value) or 0 end,
})

U.fertBox:Label("Mysterious costs 20 and adds +2 mutations, the cheapest way to roll. Ascendant adds a guaranteed good one but wants 77777.", { Style = "dim" })

U.plotUpBox = U.OrchardTab:Section("Plot Upgrades", 1)

U.plotUpBox:Toggle({
	Text = "Auto Buy Upgrades",
	Flag = "sl_orchard_upgrade",
	Default = false,
	Callback = function(state) F.orchardAutoUpgrade = state end,
})

U.plotUpBox:Dropdown({
	Text = "Buy These",
	Flag = "sl_orchard_upgrades",
	Options = UPGRADE_CHOICES,
	Default = {},
	Multi = true,
	Empty = "None",
	Callback = function(selected) F.orchardUpgrades = H.selection(selected) end,
})

U.plotUpBox:Label("Radioactive is the big one, +2 guaranteed mutations and it stacks additively. Clover multiplies rare luck by 2.5. Irrigation and Enricher each halve the grow time.", { Style = "dim" })

U.plotTableBox = U.OrchardTab:Section("Plots", "full")

U.plotCount = U.plotTableBox:Label("-", { Style = "bright" })

U.plotTable = U.plotTableBox:Table({
	Columns = { "Plot", "State", "Upgrades", "Fruit" },
	MaxRows = 14,
	EmptyText = "Orchard locked or not loaded",
})

U.plotTableBox:Button({
	Text = "Read Every Plot Now",
	Callback = function() task.spawn(H.orchardTick) end,
})

U.keepBox = U.MutationTab:Section("What To Keep", 1)

U.keepBox:Dropdown({
	Text = "Target Mutations",
	Flag = "sl_orchard_keep",
	Options = MUTATION_NAME_LIST,
	Default = {},
	Multi = true,
	Empty = "Nothing selected, nothing is touched",
	Callback = function(selected) F.orchardKeep = H.selection(selected) end,
})

U.keepBox:Dropdown({
	Text = "When A Keeper Shows Up",
	Flag = "sl_orchard_action",
	Options = { "Eat", "Sell", "Leave" },
	Default = "Eat",
	Callback = function(value) F.orchardAction = tostring(value) end,
})

U.keepBox:Label("Eat takes the boost. Sell turns the fruit into tokens. Leave harvests nothing and lets you decide by hand.", { Style = "dim" })

U.keepBox:Button({
	Text = "Select Every Good Mutation",
	Callback = function()
		local picks = {}

		for _, entry in ipairs(MUTATIONS) do
			if entry.Good then table.insert(picks, entry.Name) end
		end

		F.orchardKeep = picks
		notify("Mutations", #picks .. " good mutations selected.", "success", 4)
	end,
})

U.keepBox:Button({
	Text = "Select Only The Top Tier",
	Callback = function()
		local picks = {}

		for _, entry in ipairs(MUTATIONS) do
			if entry.Good and entry.Weight <= 0.05 then table.insert(picks, entry.Name) end
		end

		F.orchardKeep = picks
		notify("Mutations", #picks .. " rare mutations selected.", "success", 4)
	end,
})

U.rollBox = U.MutationTab:Section("Rolls", 2)

U.rollLabel = U.rollBox:Label("-", { Style = "bright" })
U.bestLabel = U.rollBox:Label("best: -", { Style = "dim" })

U.rollBox:Button({
	Text = "Reset Counters",
	Callback = function()
		Tally.planted = 0
		Tally.harvested = 0
		Tally.eaten = 0
		Tally.sold = 0
		Tally.razed = 0
		Tally.tokens = 0
		Tally.best = nil
		Tally.bestValue = 0
	end,
})

U.mutTableBox = U.MutationTab:Section("Every Mutation In The Game", "full")

U.mutTable = U.mutTableBox:Table({
	Columns = { "Mutation", "Effect", "Value", "Good", "Odds", "Stack", "Tokens" },
	MaxRows = 20,
	EmptyText = "Config.Orchard not readable",
})

do
	local rows = {}

	for _, entry in ipairs(MUTATIONS) do
		local odds = entry.Weight > 0 and string.format("%.3f", entry.Weight) or "-"

		table.insert(rows, {
			entry.Name,
			entry.Effect,
			string.format("%.2f", entry.Value),
			entry.Good and "yes" or "no",
			odds,
			tostring(entry.SoftMax),
			string.format("%.2f", entry.Tokens),
			Style = (not entry.Good) and "warning" or (entry.Weight <= 0.05 and "bright" or nil),
		})
	end

	pcall(function() U.mutTable:SetRows(rows) end)
end

U.dashBox = U.StatsTab:Section("Dashboard", "full")

U.dashTable = U.dashBox:Table({
	Columns = { "Metric", "Value" },
	MaxRows = 12,
	EmptyText = "No data yet",
})

U.sessionBox = U.StatsTab:Section("This Session", 1)

U.sessionTable = U.sessionBox:Table({
	Columns = { "Action", "Count" },
	MaxRows = 12,
	EmptyText = "Nothing done yet",
})

U.playerBox = U.StatsTab:Section("Everyone Here", 2)

U.playerTable = U.playerBox:Table({
	Columns = { "Player", "Rebirths", "Evolves", "Ascension" },
	MaxRows = 12,
	EmptyText = "No tycoon claimed",
})

U.logBox = U.StatsTab:Section("Log", "full")

U.logTable = U.logBox:Table({
	Columns = { "Time", "Event" },
	MaxRows = 12,
	EmptyText = "Nothing logged",
})

U.logBox:Button({
	Text = "Copy Log",
	Callback = function()
		if type(setclipboard) ~= "function" then
			notify("Log", "This executor has no setclipboard.", "error", 5)
			return
		end

		pcall(setclipboard, table.concat(logLines, "\n"))
		notify("Log", #logLines .. " lines copied.", "success", 3)
	end,
})

if Movement then

Movement.Settings.WalkSpeedMode = "Velocity"
Movement.Settings.JumpMode = "Humanoid"

U.flyBox = U.MoveTab:Section("Fly", 1)

U.flyBox:Toggle({
	Text = "Fly",
	Flag = "sl_fly",
	Default = false,
	Callback = function(state) Movement:Fly(state) end,
})
	:Keybind({ Default = "F", Flag = "sl_fly_key" })

U.flyBox:Slider({
	Text = "Speed",
	Flag = "sl_fly_speed",
	Min = 1, Max = 20, Default = 2,
	Decimals = 1,
	Callback = function(value) Movement.Settings.FlySpeed = value end,
})

U.speedBox = U.MoveTab:Section("Speed", 2)

U.speedBox:Toggle({
	Text = "Walk Speed",
	Flag = "sl_walkspeed",
	Default = false,
	Callback = function(state)
		Movement:WalkSpeed(state and Movement.Settings.WalkSpeed or 16)
	end,
})

U.speedBox:Slider({
	Text = "Value",
	Flag = "sl_walkspeed_value",
	Min = 16, Max = 300, Default = 16,
	Callback = function(value)
		Movement.Settings.WalkSpeed = value
		if Library.Flags["sl_walkspeed"] then Movement:WalkSpeed(value) end
	end,
})

U.otherMoveBox = U.MoveTab:Section("Other", 1)

U.otherMoveBox:Toggle({
	Text = "Noclip",
	Flag = "sl_noclip",
	Default = false,
	Callback = function(state) Movement:Noclip(state) end,
})
	:Keybind({ Default = "N", Flag = "sl_noclip_key" })

U.otherMoveBox:Toggle({
	Text = "Infinite Jump",
	Flag = "sl_infjump",
	Default = false,
	Callback = function(state) Movement:InfiniteJump(state) end,
})

U.otherMoveBox:Button({
	Text = "Teleport To The Orchard",
	Callback = function()
		local orchard = H.orchardRoot()
		local pad = orchard and orchard:FindFirstChild("Teleport")
		local character = LocalPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")

		if not pad or not root then
			notify("Travel", "No orchard teleport pad found.", "error", 5)
			return
		end

		pcall(function() root.CFrame = pad.CFrame + Vector3.new(0, 5, 0) end)
	end,
})

end

U.serverBox = U.MiscTab:Section("Server", 1)

U.serverBox:Button({
	Text = "Hop, Busy Server",
	Callback = function() H.hop(false) end,
})

U.serverBox:Button({
	Text = "Hop, Quiet Server",
	Callback = function() H.hop(true) end,
})

U.serverBox:Button({
	Text = "Rejoin",
	Callback = function()
		pcall(function()
			TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
		end)
	end,
})

U.serverBox:Button({
	Text = "Forget Visited Servers",
	Callback = function()
		writeJson(userFile("visited"), {})
		notify("Server Hop", "Visited list cleared.", "success", 3)
	end,
})

U.serverBox:Label("Hopping remembers where you came from for 45 minutes so you stop landing on the same empty server.", { Style = "dim" })

U.browserBox = U.MiscTab:Section("Browser", 2)

U.browserApi = nil

U.browserBox:Button({
	Text = "Open Server Browser",
	Callback = function()
		if not U.browserApi then
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

			U.browserApi = result
		end

		U.browserApi:Toggle()
	end,
})

U.perfBox = U.MiscTab:Section("Performance", 1)

U.perfBox:Toggle({
	Text = "Stop Drawing The World",
	Flag = "sl_render",
	Default = false,
	Hint = "kills 3D rendering entirely, the UI still works",
	Callback = function(state)
		F.noRender = state
		H.setRender(state)
	end,
})

U.perfBox:Toggle({
	Text = "Trim Effects",
	Flag = "sl_fps",
	Default = false,
	Callback = function(state)
		F.fps = state
		task.spawn(function() pcall(H.setFps, state) end)
	end,
})

U.perfBox:Toggle({
	Text = "Anti AFK",
	Flag = "sl_afk",
	Default = true,
	Callback = function(state) F.afk = state end,
})

U.perfBox:Toggle({
	Text = "Follow Me Across Servers",
	Flag = "sl_reexec",
	Default = false,
	Callback = function(state)
		F.reexec = state
		if state then H.armReexec() end
	end,
})

U.panel = Library:Panel({
	Title = "lemons",
	Icon = "activity",
	Width = 190,
	Position = UDim2.fromOffset(18, 320),
	Visible = false,
})

U.panel:SetVisible(false)

U.panel.Content:Label("cash", { Style = "dim" })
U.panelCash = U.panel.Content:Label("-", { Style = "bright" })

U.panel.Content:Divider()

U.panel.Content:Label("investors", { Style = "dim" })
U.panelInvestors = U.panel.Content:Label("-", { Style = "bright" })

U.panel.Content:Divider()

U.panel.Content:Label("tokens", { Style = "dim" })
U.panelTokens = U.panel.Content:Label("-", { Style = "bright" })

U.panel.Content:Divider()

U.panel.Content:Label("status", { Style = "dim" })
U.panelStatus = U.panel.Content:Label("Idle")

U.panelBox = U.MiscTab:Section("Panel", 2)

local panelShown = false

U.panelBox:Toggle({
	Text = "Show The Little Panel",
	Flag = "sl_panel",
	Default = false,
	Callback = function(state)
		panelShown = state
		U.panel:SetVisible(state)
	end,
})
	:Keybind({ Default = "RightControl", Flag = "sl_panel_key" })

onCleanup(function()
	pcall(function() U.panel:SetVisible(false) end)
end)

U.manageBox = U.HookTab:Section("Webhook", 1)

U.hookStatus = U.manageBox:Label("no webhook saved", { Style = "bright" })

U.manageBox:Input({
	Text = "Webhook URL",
	Flag = "sl_hook_url",
	Default = "",
	Placeholder = "https://discord.com/api/webhooks/...",
	Callback = function(value)
		local url = H.validUrl(value)
		if not url then return end

		for _, entry in ipairs(Hooks.List) do
			if entry.Url == url then return end
		end

		table.insert(Hooks.List, { Url = url, Name = "hook " .. H.hookId(url):sub(-6) })
		H.saveHooks()

		pcall(function() U.hookDropdown:SetOptions(H.hookChoices()) end)
		notify("Webhooks", "Saved, now pick it below.", "success", 5)
	end,
})

U.manageBox:Label("Paste the url and press enter, then select it as active.", { Style = "dim" })

U.hookDropdown = U.manageBox:Dropdown({
	Text = "Active",
	Flag = "sl_hook_active",
	Options = H.hookChoices(),
	Default = "None",
	Callback = function(value)
		local index = tonumber(tostring(value or ""):match("^(%d+)%."))
		local entry = index and Hooks.List[index]

		if not entry then
			Hooks.Index = 0
			StealHook = nil
			pcall(function() U.hookStatus:Set(#Hooks.List .. " saved, none active") end)
			return
		end

		if not Webhook then
			notify("Webhooks", "The webhook library is not loaded.", "error", 6)
			return
		end

		local ok, built = pcall(function()
			return Webhook.new(entry.Url, { Username = "Facility" })
		end)

		if not ok or type(built) ~= "table" then
			notify("Webhooks", tostring(built), "error", 8)
			return
		end

		StealHook = built
		Hooks.Index = index

		pcall(function() U.hookStatus:Set("active: " .. entry.Name) end)
	end,
})

U.manageBox:Button({
	Text = "Test",
	Callback = function()
		if not StealHook then
			notify("Webhooks", "Pick an active webhook first.", "warning", 5)
			return
		end

		H.hook("Facility connected", {
			{ Name = "Game", Value = "Sell Lemons", Inline = true },
			{ Name = "Tycoon", Value = Plot and Plot.Name or "-", Inline = true },
		}, Color3.fromRGB(90, 200, 255))

		notify("Webhooks", "Test sent.", "success", 3)
	end,
})

U.manageBox:Button({
	Text = "Clear Saved",
	Callback = function()
		table.clear(Hooks.List)
		Hooks.Index = 0
		StealHook = nil

		if type(delfile) == "function" then pcall(delfile, HOOK_FILE) end

		pcall(function() U.hookDropdown:SetOptions(H.hookChoices()) end)
		pcall(function() U.hookStatus:Set("no webhook saved") end)
	end,
})

U.eventBox = U.HookTab:Section("What To Report", 2)

U.eventBox:Toggle({
	Text = "Rebirths",
	Flag = "sl_hook_rebirth",
	Default = false,
	Callback = function(state) F.hookRebirth = state end,
})

U.eventBox:Toggle({
	Text = "Evolutions",
	Flag = "sl_hook_evolve",
	Default = true,
	Callback = function(state) F.hookEvolve = state end,
})

U.eventBox:Toggle({
	Text = "Ascensions",
	Flag = "sl_hook_ascend",
	Default = true,
	Callback = function(state) F.hookAscend = state end,
})

U.eventBox:Toggle({
	Text = "Mutations",
	Flag = "sl_hook_mutation",
	Default = true,
	Callback = function(state) F.hookMutation = state end,
})

U.eventBox:Toggle({
	Text = "Only Mutations I Target",
	Flag = "sl_hook_mutation_keep",
	Default = true,
	Callback = function(state) F.hookMutationKeep = state end,
})

U.eventBox:Label("Rebirths fire often, leave them off unless you want the spam.", { Style = "dim" })

pcall(function()
	if #Hooks.List > 0 then
		U.hookStatus:Set(#Hooks.List .. " saved, none active")
	end
end)

local function startLoop(delayFn, body)
	task.spawn(function()
		while Alive do
			task.wait(math.max(0.02, tonumber(delayFn()) or 1))
			if Alive and Ready then pcall(body) end
		end
	end)
end

startLoop(function() return F.buyDelay end, function()
	if F.buy then H.doBuy() end
end)

startLoop(function() return F.upgradeDelay end, function()
	if F.upgrade then H.doUpgrade() end
end)

startLoop(function() return 0.5 end, function()
	if F.rebirth then H.doRebirth() end
end)

startLoop(function() return 1 end, function()
	if F.evolve then H.doEvolve() end
end)

startLoop(function() return 1 end, function()
	if F.ascend then H.doAscend() end
end)

startLoop(function() return 2 end, function()
	if F.powers then H.doPowers() end
end)

startLoop(function() return 1 end, function()
	if F.wake then H.doWake() end
end)

startLoop(function() return 2 end, function()
	if F.phone then H.doPhone() end
end)

startLoop(function() return 0.5 end, function()
	if F.fruit then H.doFruit() end
end)

startLoop(function() return F.orchardDelay end, function()
	if F.orchard then H.orchardTick() end
end)

task.spawn(function()
	while Alive do
		task.wait(1)

		local parts = {}

		if Busy.ascend then table.insert(parts, "Ascending") end
		if Busy.rebirth then table.insert(parts, "Rebirthing") end
		if Busy.orchard then table.insert(parts, "Orchard sweep") end

		if #parts == 0 then
			local active = {}

			if F.buy then table.insert(active, "buy") end
			if F.upgrade then table.insert(active, "upgrade") end
			if F.rebirth then table.insert(active, "rebirth") end
			if F.evolve then table.insert(active, "evolve") end
			if F.ascend then table.insert(active, "ascend") end
			if F.powers then table.insert(active, "powers") end
			if F.wake then table.insert(active, "wake") end
			if F.fruit then table.insert(active, "fruit") end
			if F.orchard then table.insert(active, "orchard") end

			Status = #active > 0 and ("Running: " .. table.concat(active, ", ")) or "Idle"
		else
			Status = table.concat(parts, "  ·  ")
		end
	end
end)

task.spawn(function()
	local shown = {}

	while Alive do
		task.wait(0.6)

		pcall(function()
			if Status ~= shown.status then
				shown.status = Status
				U.statusLabel:Set(Status)
			end

			local cash = string.format("Cash %s  ·  Tokens %d", H.money(H.cash()), H.tokens())

			if cash ~= shown.cash then
				shown.cash = cash
				U.cashLabel:Set(cash)
			end

			local current = H.investors()
			local pending = H.potential()
			local ratio = "-"

			if pending ~= -math.huge then
				local base = current == -math.huge and 0 or current
				ratio = string.format("x%s", H.money(pending - base))
			end

			local investors = string.format("Investors %s  ·  pending %s  ·  %s",
				H.money(current), H.money(pending), ratio)

			if investors ~= shown.investors then
				shown.investors = investors
				U.investorLabel:Set(investors)
			end

			local rolls = string.format("Planted %d  ·  harvested %d  ·  eaten %d  ·  sold %d  ·  razed %d",
				Tally.planted, Tally.harvested, Tally.eaten, Tally.sold, Tally.razed)

			if rolls ~= shown.rolls then
				shown.rolls = rolls
				U.rollLabel:Set(rolls)
			end

			local best = Tally.best
				and string.format("best: x%.2f  %s", Tally.bestValue, Tally.best)
				or "best: nothing yet"

			if best ~= shown.best then
				shown.best = best
				U.bestLabel:Set(best)
			end
		end)

		if logDirty then
			logDirty = false

			pcall(function()
				local rows = {}
				local from = math.max(1, #logLines - 11)

				for index = from, #logLines do
					local line = logLines[index]
					local stamp, body = line:match("^(%S+)%s%s(.+)$")
					table.insert(rows, { stamp or "-", body or line })
				end

				U.logTable:SetRows(rows)
			end)
		end

		if panelShown then
			pcall(function()
				U.panelCash:Set(H.money(H.cash()))
				U.panelInvestors:Set(H.money(H.investors()))
				U.panelTokens:Set(tostring(H.tokens()))
				U.panelStatus:Set(Status)
			end)
		end
	end
end)

task.spawn(function()
	while Alive do
		task.wait(2)

		pcall(function()
			local purchase, id = H.nextPurchase()
			local price = purchase and select(2, pcall(function() return purchase:GetPrice() end)) or nil
			local display = purchase and select(2, pcall(function() return purchase.DisplayName end)) or nil

			local rows = {
				{ "Cash", H.money(H.cash()) },
				{ "Investors", H.money(H.investors()) },
				{ "Pending investors", H.money(H.potential()) },
				{ "Tokens", tostring(H.tokens()) },
				{ "Rebirths this evolution", tostring(H.rebirthCount()) },
				{ "Evolution", tostring(H.evolution()) },
				{ "Ascension", tostring(H.ascension()) },
			}

			if purchase then
				table.insert(rows, {
					"Next button",
					string.format("%s, %s", tostring(display or id), H.money(tonumber(price) or -math.huge)),
				})
			else
				table.insert(rows, { "Next button", "nothing left to buy" })
			end

			U.dashTable:SetRows(rows)
		end)

		pcall(function()
			U.sessionTable:SetRows({
				{ "Buttons bought", tostring(Tally.bought) },
				{ "Earner upgrades", tostring(Tally.upgraded) },
				{ "Rebirths", tostring(Tally.rebirths) },
				{ "Evolutions", tostring(Tally.evolves) },
				{ "Ascensions", tostring(Tally.ascends) },
				{ "Powers bought", tostring(Tally.powers) },
				{ "Streams woken", tostring(Tally.woken) },
				{ "Phone offers", tostring(Tally.offers) },
				{ "Fruit clicked", tostring(Tally.fruit) },
				{ "Tokens earned", string.format("%.0f", Tally.tokens) },
			})
		end)

		pcall(function()
			local progress = {
				{
					"Evolution",
					tostring(H.evolution()),
					string.format("%.1f%%", H.evolveProgress() * 100),
					F.evolveMax > 0 and ("cap " .. F.evolveMax) or "no cap",
				},
				{
					"Ascension",
					tostring(H.ascension()),
					string.format("%.1f%%", H.ascendProgress() * 100),
					F.ascendMax > 0 and ("cap " .. F.ascendMax) or "no cap",
				},
				{
					"Rebirth",
					tostring(H.rebirthCount()),
					H.potential() ~= -math.huge and H.money(H.potential()) or "-",
					F.rebirthMaxPerEvolve > 0 and ("cap " .. F.rebirthMaxPerEvolve) or "no cap",
				},
			}

			U.progressTable:SetRows(progress)
		end)

		pcall(function()
			local comp = H.comp(G.Powers)
			local rows = {}

			if comp then
				local ok, levels = pcall(function() return comp:GetLevels() end)

				if ok and type(levels) == "table" then
					local names = {}
					for name in pairs(levels) do table.insert(names, tostring(name)) end
					table.sort(names)

					local wallet = H.investors()

					for _, name in ipairs(names) do
						local level = tonumber(levels[name]) or 0
						local maximum = select(2, pcall(function() return comp:GetMaxLevel(name) end))
						local price = select(2, pcall(function() return comp:GetUpgradePrice(name) end))
						local maxed = maximum and level >= maximum

						table.insert(rows, {
							name,
							tostring(level),
							tostring(maximum or "-"),
							maxed and "maxed" or H.money(tonumber(price) or -math.huge),
							maxed and "-" or ((tonumber(price) and wallet >= price) and "yes" or "no"),
							Style = maxed and "dim" or ((tonumber(price) and wallet >= price) and "bright" or nil),
						})
					end
				end
			end

			U.powerTable:SetRows(rows)
		end)

		pcall(function()
			local rows = {}

			for _, child in ipairs(workspace:GetChildren()) do
				if child.Name:match("Tycoon%d") then
					local owner = child:FindFirstChild("Owner")
					local player = owner and owner.Value

					if player then
						local values = child:FindFirstChild("Values")
						local inner = values and values:FindFirstChild("Values")

						local function readAttr(key)
							if not inner then return "-" end
							local ok, value = pcall(function() return inner:GetAttribute(key) end)
							return (ok and value ~= nil) and tostring(value) or "-"
						end

						table.insert(rows, {
							player.Name,
							readAttr("TotalRebirths"),
							readAttr("TotalEvolves"),
							readAttr("Ascension"),
							Style = player == LocalPlayer and "bright" or nil,
						})
					end
				end
			end

			table.sort(rows, function(a, b)
				return (tonumber(a[2]) or -1) > (tonumber(b[2]) or -1)
			end)

			U.playerTable:SetRows(rows)
		end)
	end
end)

task.spawn(function()
	while Alive do
		task.wait(3)

		pcall(function()
			local plots = H.plots()
			local rows = {}
			local unlocked, planted = 0, 0

			for _, plot in ipairs(plots) do
				local info = H.plotInfo(plot)

				if info.Enabled then unlocked = unlocked + 1 end
				if info.State > 0 then planted = planted + 1 end

				if #rows < 14 then
					local state = "locked"

					if info.Enabled then
						state = info.State == 0 and "empty" or ("state " .. info.State)
					elseif info.Available then
						state = "buyable"
					end

					table.insert(rows, {
						tostring(info.ID),
						state,
						info.Owned,
						orchardSeen[info.ID] or "-",
						Style = (orchardSeen[info.ID] and "bright")
							or (info.Enabled and nil)
							or "dim",
					})
				end
			end

			U.plotTable:SetRows(rows)
			U.plotCount:Set(string.format("%d plots  ·  %d unlocked  ·  %d growing",
				#plots, unlocked, planted))
		end)
	end
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
SaveManager:SetFolder("Facility/79268393072444")

InterfaceManager:BuildInterfaceSection(U.Settings, 1)
SaveManager:BuildConfigSection(U.Settings, 2)
ThemeManager:Mount(Window)

Window:SetTab(U.FarmTab)

Library:Notify("Facility", "Loaded.", 4)

SaveManager:LoadAutoloadConfig()
ThemeManager:Load()

clog("Hub up on " .. (Plot and Plot.Name or "no tycoon"))

if #MUTATIONS == 0 then
	clog("Config.Orchard did not load, the mutation tab will stay empty")
else
	clog(#MUTATIONS .. " mutations and " .. #FERTILIZERS .. " items read from the game config")
end

if H.orchardRoot() then
	local plots = H.plots()
	clog(#plots .. " orchard plots found")
else
	clog("No orchard on this tycoon yet, that tab waits")
end

task.spawn(function()
	task.wait(2)
	if F.reexec then H.armReexec() end
	if F.phone then H.watchPhone() end
end)

local libraryDestroy = Library.Destroy

function Library:Destroy(...)
	Alive = false

	for index = #cleanupTasks, 1, -1 do
		pcall(cleanupTasks[index])
	end

	table.clear(cleanupTasks)

	return libraryDestroy(self, ...)
end

FH.Unload = function()
	pcall(function() Library:Destroy() end)
end
