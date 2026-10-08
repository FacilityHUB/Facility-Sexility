--!nocheck
--!nolint UnknownGlobal

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
		warn("Facility: could not load " .. label .. " from " .. url)
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
local UserInputService = game:GetService("UserInputService")
local VirtualUser = game:GetService("VirtualUser")
local Lighting = game:GetService("Lighting")
local Stats = game:GetService("Stats")

local LocalPlayer = Players.LocalPlayer

local Alive = true
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

local CFG_FOLDER = "Facility/AnimeDice"

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

local F = {
	collect = false, collectDelay = 2, collectMin = 0,
	levelup = false, maxLevel = 40, levelDelay = 2.5, smartLevel = false,
	placeBest = false, placeDelay = 5, replaceWorst = true, lockedSlots = {},
	rebirth = false, rebirthDelay = 5,
	upgrades = false, upgradeDelay = 2, upgradeCats = {}, upgradeOrder = {}, upgradeReserve = 0,
	buyDice = false, equipDice = true, diceDelay = 5,
	autoRoll = false, hideRolls = false,
	sellThreshold = 0, sellSync = false, sellAuto = false, sellDelay = 10, keepBest = 0, smartSell = false,
	sellGrades = {}, sellTraits = {}, sellMutations = {}, sellMode = "Chance",
	tower = false, towerName = "Dragon Tower", towerEquipBest = true, smartTower = false,
	towerExitOn = false, towerExitFloor = 0,
	potionAuto = false, potionDelay = 5, potionBest = true, potionExtend = false, potions = {},
	gradeAuto = false, gradeDelay = 2, gradeTargets = {}, gradeUnits = {}, gradeAll = false,
	gradePlacedOnly = false, gemReserve = 0,
	traitAuto = false, traitDelay = 2, traitTargets = {}, traitUnits = {}, traitAll = false,
	traitPlacedOnly = false, rerollReserve = 0,
	claimQuests = false, codesAuto = false, codesDelay = 300,
	tradeAuto = false, tradeMoney = 0, tradeRetries = 3, tradeHop = true, tradeHopDelay = 8,
	tradeAutoGo = true, tradeNeedOffer = true, tradeMinItems = 1,
	rollHookOn = false, rollHookMin = 0, rollHookGrades = {}, rollHookTraits = {}, rollHookMutOnly = false,
	statHookOn = false, statHookInterval = 300, statHookFields = {},
	towerHookOn = false, tradeHookOn = false,
	afk = true, fpsOn = false, reexec = false,
	invSort = "Chance", invPlacedOnly = false,
}

local Busy = { place = false, dice = false, potion = false, grade = false, trait = false, tower = false, trade = false }

local Tally = {
	collected = 0, leveled = 0, upgraded = 0, rebirthed = 0, sold = 0, potions = 0,
	towerWins = {}, towerFloors = 0, towerGems = 0, towerTraits = 0, towerRewards = {},
	tradesSent = 0, tradesOpened = 0,
}

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

local G = { ok = false, missing = {} }

do
	local deadline = os.clock() + 30

	while os.clock() < deadline do
		local ok, ready = pcall(function()
			return ReplicatedStorage:FindFirstChild("Packages") ~= nil
				and ReplicatedStorage:FindFirstChild("Framework") ~= nil
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

need("Network", function() return require(ReplicatedStorage.Packages.Network) end)
need("DC", function() return require(ReplicatedStorage.Framework.Features.Data.DataController) end)
need("EntryRegistry", function()
	pcall(function() require(ReplicatedStorage.Framework.Features.Inventory.EntryTypes) end)
	return require(ReplicatedStorage.Framework.Features.Inventory.EntryRegistry)
end)
need("PlotConfig", function() return require(ReplicatedStorage.Framework.Features.Plot.PlotConfig) end)
need("UnitUtil", function() return require(ReplicatedStorage.Framework.Features.Inventory.Kinds.Unit.UnitUtil) end)
need("UnitController", function() return require(ReplicatedStorage.Framework.Features.Inventory.Kinds.Unit.UnitController) end)
need("Upgrades", function() return require(ReplicatedStorage.Framework.Features.Upgrades.Upgrades) end)
need("TreeStructure", function() return require(ReplicatedStorage.Framework.Features.Upgrades.TreeStructure) end)
need("Rebirths", function() return require(ReplicatedStorage.Framework.Features.Rebirth.Rebirths) end)
need("DiceMod", function() return require(ReplicatedStorage.Framework.Features.Rolling.Dice) end)
need("TowersMod", function() return require(ReplicatedStorage.Framework.Features.Towers.Towers) end)
need("BoostConfig", function() return require(ReplicatedStorage.Framework.Features.Inventory.Kinds.Boost.BoostConfig) end)
need("MonetConfig", function() return require(ReplicatedStorage.Framework.Features.Monetization.MonetizationConfig) end)
need("QuestConfig", function() return require(ReplicatedStorage.Framework.Features.Quests.QuestConfig) end)
need("GradesMod", function() return require(ReplicatedStorage.Framework.Features.Grades.Grades) end)
need("TraitsMod", function() return require(ReplicatedStorage.Framework.Features.Traits.Traits) end)
need("Mutations", function() return require(ReplicatedStorage.Framework.Features.Inventory.Kinds.Unit.Mutations) end)
need("UIRefs", function() return require(ReplicatedStorage.Framework.Features.UI.UIReferences) end)
need("NF", function() return require(ReplicatedStorage.Packages.NumberFormatter) end)
need("BuffCtrl", function() return require(ReplicatedStorage.Framework.Features.Buffs.BuffController) end)

G.ok = G.Network ~= nil and G.DC ~= nil

local Sig, Fn = {}, {}

local function svcComm(service)
	return G.Network.ClientComm.new(ReplicatedStorage.Network, false, service)
end

local function getSig(service, name)
	local key = service .. "/" .. name
	if Sig[key] then return Sig[key] end

	local ok, signal = pcall(function() return svcComm(service):GetSignal(name) end)

	if ok and signal then
		Sig[key] = signal
		return signal
	end

	return nil
end

local function getFn(service, name)
	local key = service .. "/" .. name
	if Fn[key] then return Fn[key] end

	local ok, fn = pcall(function() return svcComm(service):GetFunction(name) end)

	if ok and fn then
		Fn[key] = fn
		return fn
	end

	return nil
end

local function buyUpgradeSig()
	if Sig.BuyUpgrade then return Sig.BuyUpgrade end

	local ok, signal = pcall(function()
		return G.Network.Client.GetSignal(ReplicatedStorage.Network, "BuyUpgrade")
	end)

	if ok and signal then
		Sig.BuyUpgrade = signal
		return signal
	end

	return nil
end

local function money()
	local ok, value = pcall(function() return G.DC.Money() end)
	return ok and (tonumber(value) or 0) or 0
end

local function rebirthCount()
	local ok, value = pcall(function() return G.DC.Rebirth() end)
	return ok and (tonumber(value) or 0) or 0
end

local function rollCount()
	local ok, value = pcall(function() return G.DC.Rolls() end)
	return ok and (tonumber(value) or 0) or 0
end

local function slotData()
	local ok, value = pcall(function() return G.DC.Slots() end)
	return (ok and type(value) == "table") and value or {}
end

local function inventory()
	local ok, value = pcall(function() return G.DC.Inventory() end)
	return (ok and type(value) == "table") and value or {}
end

local function invEntry(key)
	local entry

	local ok = pcall(function() entry = G.DC.Inventory[key]() end)
	if ok and entry then return entry end

	return inventory()[key]
end

local function equippedKey()
	local ok, value = pcall(function() return G.UnitController.EquippedUnit() end)
	return ok and value or nil
end

local function entryConfig(name)
	local ok, cfg = pcall(function() return G.EntryRegistry.getEntryConfig(name) end)
	return ok and cfg or nil
end

local function isUnitEntry(entry)
	if not entry or type(entry) ~= "table" or not entry.name then return false end
	local cfg = entryConfig(entry.name)
	return cfg ~= nil and cfg.kind == "Unit"
end

local function unitChance(entry)
	if not entry or type(entry) ~= "table" then return 0 end

	local cfg = entryConfig(entry.name)
	if not cfg or cfg.kind ~= "Unit" then return 0 end

	local ok, chance = pcall(function() return cfg.chance(entry.attributes) end)
	return (ok and tonumber(chance)) or 0
end

local function fmt(n)
	local ok, value = pcall(function() return G.NF.FormatCompact(n) end)
	return (ok and value) or tostring(n)
end

local function parseCompact(text)
	if not text or text == "" then return 0 end

	local clean = tostring(text):gsub("%$", ""):gsub(",", ""):gsub("%s+", "")
	if clean == "" then return 0 end

	local ok, value = pcall(function() return G.NF.ParseCompact(clean) end)
	if ok and tonumber(value) then return tonumber(value) end

	local number, suffix = clean:lower():match("^([%d%.]+)([a-z]*)$")
	number = tonumber(number)
	if not number then return nil end

	local mult = { k = 1e3, m = 1e6, b = 1e9, t = 1e12, q = 1e15, qd = 1e15, qn = 1e18, aa = 1e18 }

	return number * (mult[suffix] or 1)
end

local function currencyAmount(name)
	local total = 0

	for _, entry in pairs(inventory()) do
		if type(entry) == "table" and entry.name == name then
			total = total + (tonumber(entry.amount) or 0)
		end
	end

	return total
end

local function unlockedSlots()
	local list = {}
	local data = slotData()
	local maxSlots = 14

	pcall(function() maxSlots = G.PlotConfig.GetMaxSlots() end)

	local rb = rebirthCount()

	for index = 1, maxSlots do
		local required = 0
		pcall(function() required = G.PlotConfig.GetSlotRebirthRequirement(index) end)
		if rb >= required then table.insert(list, index) end
	end

	return list, data
end

local function slotLocked(slot)
	for _, value in ipairs(F.lockedSlots) do
		if tostring(value) == tostring(slot) then return true end
	end

	return false
end

local function placedUnitKeys()
	local out = {}

	for _, entry in pairs(slotData()) do
		if entry and entry.unitId then out[entry.unitId] = true end
	end

	return out
end

local function towerTeamKeys()
	local out = {}

	pcall(function()
		for _, key in pairs(G.DC.TowerTeam() or {}) do out[key] = true end
	end)

	return out
end

local function waitVerify(fn, timeout)
	timeout = timeout or 3
	local waited = 0

	while waited < timeout do
		local ok, result = pcall(fn)
		if ok and result then return true end
		task.wait(0.25)
		waited = waited + 0.25
	end

	return false
end

local function orderedNames(module)
	local list = {}

	if type(module) == "table" then
		for name, def in pairs(module) do
			if type(def) == "table" and def.order then
				table.insert(list, { name = name, order = def.order, ref = def })
			end
		end
	end

	table.sort(list, function(a, b) return a.order < b.order end)

	return list
end

local function mutationNames()
	local list = {}

	if type(G.Mutations) == "table" then
		for name, def in pairs(G.Mutations) do
			if type(name) == "string" and type(def) == "table" then table.insert(list, name) end
		end
	end

	table.sort(list)

	return list
end

local function gradeRank(name)
	if not name or not G.GradesMod then return 0 end
	local def = G.GradesMod[name]
	return (type(def) == "table" and tonumber(def.order)) or 0
end

local function traitRank(name)
	if not name or not G.TraitsMod then return 0 end
	local def = G.TraitsMod[name]
	return (type(def) == "table" and tonumber(def.order)) or 0
end

local activePotions

local function potionLeft(entry)
	if not entry or type(entry) ~= "table" then return 0 end

	if type(entry.startedAt) == "number" and type(entry.remaining) == "number" then
		local now = 0
		pcall(function() now = workspace:GetServerTimeNow() end)
		return math.max(0, entry.remaining - math.max(0, now - entry.startedAt))
	end

	if type(entry.expiresAt) == "number" then
		return math.max(0, entry.expiresAt - os.time())
	end

	if type(entry.remaining) == "number" then return math.max(0, entry.remaining) end

	return 1e9
end

function activePotions()
	local out = {}

	local ok, entries = pcall(function() return G.DC.ActiveEntries() end)
	if not ok or type(entries) ~= "table" then return out end

	for name, entry in pairs(entries) do
		if type(entry) == "table" then
			local left = potionLeft(entry)
			if left > 3 then out[name] = left end
		elseif entry then
			out[name] = 1e9
		end
	end

	return out
end

local function durationText(seconds)
	seconds = math.floor(tonumber(seconds) or 0)

	if seconds >= 1e8 then return "active" end
	if seconds >= 3600 then return string.format("%dh%02dm", seconds // 3600, (seconds % 3600) // 60) end
	if seconds >= 60 then return string.format("%dm%02ds", seconds // 60, seconds % 60) end

	return seconds .. "s"
end

local function effectiveLuck()
	local diceLuck, buff = 1, 1

	pcall(function()
		local current = G.DC.Dice()
		local all = G.DiceMod.GetAll()
		if current and all and all[current] then diceLuck = tonumber(all[current].luck) or 1 end
	end)

	pcall(function()
		local value = G.BuffCtrl.GetBuff("Luck")
		if tonumber(value) and tonumber(value) > 0 then buff = tonumber(value) end
	end)

	return math.max(1, diceLuck) * math.max(1, buff)
end

local function bestOwnedChance()
	local best = 0

	for _, entry in pairs(inventory()) do
		if isUnitEntry(entry) then
			local chance = unitChance(entry)
			if chance > best then best = chance end
		end
	end

	return best
end

local SMART_K = 100000
local smartSellAt, smartLevelAt = 0, 0
local sellInputText = ""

local function applySmartSell(force)
	if not F.smartSell then return end
	if not force and os.clock() - smartSellAt < 60 then return end

	smartSellAt = os.clock()

	pcall(function()
		local luck = effectiveLuck()
		local target = SMART_K * luck
		local best = bestOwnedChance()

		if best > 0 then target = math.min(target, best / 2) end

		if target > 0 then
			local magnitude = 10 ^ math.max(0, math.floor(math.log10(target) - 1))
			target = math.floor(target / magnitude) * magnitude
		end

		if target ~= F.sellThreshold then
			F.sellThreshold = target
			sellInputText = fmt(target)

			if F.sellSync and target > 0 then
				local signal = getSig("SellService", "UpdateAutoSell")
				if signal then pcall(function() signal:Fire(target) end) end
			end

			clog("Smart sell: keep 1 in " .. fmt(target) .. "+ (luck " .. fmt(luck) .. ")")
		end
	end)
end

local function applySmartLevel(force)
	if not F.smartLevel then return end
	if not force and os.clock() - smartLevelAt < 30 then return end

	smartLevelAt = os.clock()

	pcall(function()
		local list, data = unlockedSlots()
		local units = {}

		for _, slot in ipairs(list) do
			local entry = data[tostring(slot)]

			if entry and entry.unitId then
				local item = invEntry(entry.unitId)

				if item and item.attributes then
					table.insert(units, {
						name = item.name,
						level = tonumber(item.attributes.level) or 1,
						mutation = item.attributes.mutation,
					})
				end
			end
		end

		if #units == 0 then return end

		local wallet = money()

		local function costTo(minLevel)
			local total = 0

			for _, unit in ipairs(units) do
				if unit.level < minLevel then
					for level = unit.level, minLevel - 1 do
						local price = 0
						pcall(function()
							price = G.UnitUtil.GetLevelPrice(unit.name, { level = level, mutation = unit.mutation })
						end)
						total = total + price
					end
				end
			end

			return total
		end

		local lowest = 99
		for _, unit in ipairs(units) do lowest = math.min(lowest, unit.level) end

		local cap = math.clamp(lowest, 1, 99)
		local guard, moved = 0, true

		while moved and guard < 25 do
			moved = false
			guard = guard + 1

			if cap < 99 then
				local step = costTo(cap + 1)
				if step > 0 and step <= wallet * 0.1 then cap = cap + 1 moved = true end
			end

			if not moved and cap > 1 and costTo(cap) > wallet * 0.5 then cap = cap - 1 moved = true end
		end

		if cap ~= math.floor(tonumber(F.maxLevel) or 40) then
			F.maxLevel = cap
			clog("Smart level cap: " .. cap)
		end
	end)
end

local function doCollect()
	local signal = getSig("PlotService", "CollectBalance")
	if not signal then return end

	local list, data = unlockedSlots()
	local threshold = math.max(0, tonumber(F.collectMin) or 0)

	for _, slot in ipairs(list) do
		if not F.collect or not Alive then break end

		local entry = data[tostring(slot)]
		local amount = entry and (tonumber(entry.balance) or 0) or 0

		if amount > 0 and amount >= threshold then
			pcall(function() signal:Fire(slot) end)
			Tally.collected = Tally.collected + amount
			task.wait(0.15)
		end
	end
end

local function doLevelUp()
	local signal = getSig("PlotService", "LevelUpSlot")
	if not signal then return end

	local list, data = unlockedSlots()
	local candidates = {}

	for _, slot in ipairs(list) do
		if not F.levelup or not Alive then break end

		if not slotLocked(slot) then
			local entry = data[tostring(slot)]
			local uid = entry and entry.unitId

			if uid then
				local item = invEntry(uid)

				if item and item.attributes then
					local level = tonumber(item.attributes.level) or 1

					if level < F.maxLevel then
						local price = 0
						pcall(function() price = G.UnitUtil.GetLevelPrice(item.name, item.attributes) end)
						table.insert(candidates, { slot = slot, level = level, price = price })
					end
				end
			end
		end
	end

	table.sort(candidates, function(a, b) return a.level < b.level end)

	local wallet = money()

	for index = 1, math.min(2, #candidates) do
		local candidate = candidates[index]

		if wallet >= candidate.price then
			pcall(function() signal:Fire(candidate.slot) end)
			Tally.leveled = Tally.leveled + 1
			wallet = wallet - candidate.price
			task.wait(0.4)
		end
	end
end

local function equipUnit(key)
	local ok = pcall(function() return G.UnitController.Equip(key) end)

	if ok then
		task.wait(0.4)
		return true
	end

	return false
end

local function doPlaceBest()
	if Busy.place then return end
	Busy.place = true

	local ok, err = pcall(function()
		local list, data = unlockedSlots()
		local placed, placedKeys = {}, {}

		for _, slot in ipairs(list) do
			local entry = data[tostring(slot)]

			if entry and entry.unitId then
				local item = invEntry(entry.unitId)

				if item then
					placed[slot] = { key = entry.unitId, chance = unitChance(item), name = item.name }
					placedKeys[entry.unitId] = true
				end
			end
		end

		local best, bestChance = nil, 0
		local equipped = equippedKey()

		for key, item in pairs(inventory()) do
			if isUnitEntry(item) and not placedKeys[key] and key ~= equipped then
				if not (item.attributes and item.attributes.locked) then
					local chance = unitChance(item)
					if chance > bestChance then best, bestChance = key, chance end
				end
			end
		end

		if not best then return end

		for _, slot in ipairs(list) do
			if not slotLocked(slot) then
				local entry = data[tostring(slot)]

				if not entry or not entry.unitId then
					if equipUnit(best) then
						local signal = getSig("PlotService", "InteractSlot")
						if signal then pcall(function() signal:Fire(slot) end) end

						local ok2 = waitVerify(function()
							local fresh = slotData()[tostring(slot)]
							return fresh and fresh.unitId == best
						end, 3)

						local item = invEntry(best) or {}

						if ok2 then
							clog("Placed " .. tostring(item.name) .. " [1 in " .. fmt(bestChance) .. "] -> slot " .. slot)
						else
							clog("Place refused by server: " .. tostring(item.name) .. " -> slot " .. slot)
						end
					end

					return
				end
			end
		end

		if not F.replaceWorst then return end

		local worstSlot, worstChance = nil, nil

		for slot, info in pairs(placed) do
			if not slotLocked(slot) then
				if not worstChance or info.chance < worstChance then worstSlot, worstChance = slot, info.chance end
			end
		end

		if not worstSlot or bestChance <= worstChance then return end

		local signal = getSig("PlotService", "InteractSlot")
		if not signal then return end

		pcall(function() signal:Fire(worstSlot) end)

		local emptied = waitVerify(function()
			local fresh = slotData()[tostring(worstSlot)]
			return not (fresh and fresh.unitId)
		end, 3)

		if not emptied then
			local fallback = getSig("PlotService", "EquipBest")
			if fallback then pcall(function() fallback:Fire() end) end
			return
		end

		task.wait(0.3)

		if equipUnit(best) then
			pcall(function() signal:Fire(worstSlot) end)

			local ok3 = waitVerify(function()
				local fresh = slotData()[tostring(worstSlot)]
				return fresh and fresh.unitId == best
			end, 3)

			local item = invEntry(best) or {}
			local old = placed[worstSlot] or {}

			if ok3 then
				clog("Swapped slot " .. worstSlot .. ": " .. tostring(old.name)
					.. " [1 in " .. fmt(worstChance) .. "] -> " .. tostring(item.name)
					.. " [1 in " .. fmt(bestChance) .. "]")
			else
				clog("Swap refused by server on slot " .. worstSlot)
			end
		end
	end)

	if not ok then clog("Place error: " .. tostring(err)) end

	Busy.place = false
end

local UPGRADE_CATEGORIES = {
	"Roll Speed", "Unit Storage", "Money", "Luck", "Fortune",
	"Damage", "Sell", "Health", "Walkspeed", "Income",
}

local function upgradeCategory(name)
	for _, category in ipairs(UPGRADE_CATEGORIES) do
		if name:sub(1, #category) == category then return category end
	end

	return nil
end

local badUpgrades = {}
local lastUpgradeFail = 0

local function doUpgrades()
	local signal = buyUpgradeSig()
	if not signal or not G.Upgrades or not G.TreeStructure then return end

	local owned = {}
	pcall(function() owned = G.DC.Upgrades() or {} end)

	local seen, list = {}, {}

	local function childrenOf(parent)
		local ok, result = pcall(function() return G.TreeStructure.GetChildren(parent) end)
		if ok and type(result) == "table" then return result end
		return {}
	end

	local function consider(name)
		if type(name) ~= "string" or owned[name] or seen[name] then return end
		seen[name] = true

		local def = G.Upgrades[name]
		if type(def) == "table" and def.price then
			table.insert(list, { name = name, price = def.price })
		end
	end

	for _, name in ipairs(childrenOf("Start")) do consider(name) end
	consider("Start")

	for name in pairs(owned) do
		for _, child in ipairs(childrenOf(name)) do consider(child) end
	end

	local filtered = {}

	for _, upgrade in ipairs(list) do
		local category = upgradeCategory(upgrade.name)

		if #F.upgradeCats == 0 then
			upgrade.category = category
			table.insert(filtered, upgrade)
		else
			for _, want in ipairs(F.upgradeCats) do
				if category == want then
					upgrade.category = category
					table.insert(filtered, upgrade)
					break
				end
			end
		end
	end

	local priority = {}
	for index, name in ipairs(F.upgradeOrder) do priority[name] = index end

	table.sort(filtered, function(a, b)
		local pa = priority[a.category or ""] or math.huge
		local pb = priority[b.category or ""] or math.huge
		if pa ~= pb then return pa < pb end
		return a.price < b.price
	end)

	local wallet = money() - math.max(0, tonumber(F.upgradeReserve) or 0)

	for _, upgrade in ipairs(filtered) do
		if wallet < upgrade.price then break end

		if (badUpgrades[upgrade.name] or 0) <= os.clock() then
			pcall(function() signal:Fire(upgrade.name) end)
			task.wait(0.8)

			local bought = false
			pcall(function() bought = G.DC.Upgrades[upgrade.name]() == true end)

			if bought then
				badUpgrades[upgrade.name] = nil
				Tally.upgraded = Tally.upgraded + 1
				clog("Upgrade: " .. upgrade.name)
			else
				badUpgrades[upgrade.name] = os.clock() + 60

				if os.clock() - lastUpgradeFail > 10 then
					lastUpgradeFail = os.clock()
					clog("Upgrade refused by server: " .. upgrade.name)
				end
			end

			break
		end
	end
end

local function doRebirth()
	local nextTier = nil
	pcall(function() nextTier = G.Rebirths.GetNext(rebirthCount()) end)

	if not nextTier then return end

	if money() >= (nextTier.cost or math.huge) then
		local signal = getSig("RebirthService", "Rebirth")

		if signal then
			pcall(function() signal:Fire() end)
			Tally.rebirthed = Tally.rebirthed + 1
			clog("Rebirth done.")
			notify("Rebirth", "Rebirth done.", "success", 4)
			task.wait(8)
		end
	end
end

local function ownedDice()
	local owned = {}
	pcall(function() owned = G.DC.OwnedDice() or {} end)
	return owned
end

local function currentDice()
	local ok, value = pcall(function() return G.DC.Dice() end)
	return ok and value or nil
end

local function bestDiceOwned()
	local owned = ownedDice()
	local current = currentDice()
	local all = G.DiceMod and G.DiceMod.GetAll() or {}
	local best, bestLuck = current, -1

	for name in pairs(owned) do
		local def = all[name]
		if def and (def.luck or 0) > bestLuck then best, bestLuck = name, def.luck end
	end

	return best, current
end

local function doDice()
	if Busy.dice then return end
	Busy.dice = true

	pcall(function()
		if not G.DiceMod then return end

		local all = G.DiceMod.GetAll()
		local wallet = money()

		if F.buyDice then
			local ordered = {}

			for name, def in pairs(all) do
				if def.price then
					table.insert(ordered, { name = name, price = def.price, luck = def.luck or 0 })
				end
			end

			table.sort(ordered, function(a, b) return a.luck > b.luck end)

			local owned = ownedDice()

			for _, def in ipairs(ordered) do
				if not owned[def.name] and wallet >= def.price then
					local signal = getSig("DiceShopService", "BuyDice")
					if signal then pcall(function() signal:Fire(def.name) end) end
					clog("Dice bought: " .. def.name)
					task.wait(0.6)
					break
				end
			end
		end

		if F.equipDice then
			local best, current = bestDiceOwned()

			if best and best ~= current then
				local signal = getSig("DiceShopService", "EquipDice")
				if signal then pcall(function() signal:Fire(best) end) end
			end
		end
	end)

	Busy.dice = false
end

local function potionKeys()
	local out = {}

	for key, entry in pairs(inventory()) do
		if type(entry) == "table" and entry.name and (tonumber(entry.amount) or 0) >= 1 then
			local cfg = entryConfig(entry.name)
			if cfg and cfg.kind == "Boost" then out[entry.name] = key end
		end
	end

	return out
end

local function doPotion()
	if Busy.potion then return end
	if not G.BoostConfig or not G.BoostConfig.entries then return end

	Busy.potion = true

	pcall(function()
		if #F.potions == 0 then return end

		local entries = G.BoostConfig.entries
		local have = potionKeys()
		local active = activePotions()
		local candidates = {}

		for _, name in ipairs(F.potions) do
			local def = entries[name]

			if def and have[name] then
				table.insert(candidates, {
					name = name,
					category = def.category,
					tier = def.tier or 0,
					key = have[name],
				})
			end
		end

		if F.potionBest then
			local best = {}

			for _, candidate in ipairs(candidates) do
				if not best[candidate.category] or candidate.tier > best[candidate.category].tier then
					best[candidate.category] = candidate
				end
			end

			candidates = {}
			for _, candidate in pairs(best) do table.insert(candidates, candidate) end
		end

		local activeTier = {}

		for name in pairs(active) do
			local def = entries[name]

			if def then
				local tier = def.tier or 0
				if not activeTier[def.category] or tier > activeTier[def.category] then
					activeTier[def.category] = tier
				end
			end
		end

		local signal = getSig("BoostService", "Use")
		if not signal then return end

		for _, candidate in ipairs(candidates) do
			local alreadyUp = (active[candidate.name] or 0) > 0 and not F.potionExtend
			local outranked = (activeTier[candidate.category] or 0) > candidate.tier

			if not alreadyUp then
				if outranked then
					clog("Potion skipped, higher tier active: " .. candidate.name)
				else
					pcall(function() signal:Fire(candidate.key) end)
					Tally.potions = Tally.potions + 1
					clog("Potion used: " .. candidate.name)
					task.wait(0.5)
				end
			end
		end
	end)

	Busy.potion = false
end

local protectedKeys = {}

local function loadProtected()
	local data = readJson(userFile("protected"))
	if type(data) ~= "table" then return end

	for _, key in ipairs(data) do
		if type(key) == "string" then protectedKeys[key] = true end
	end
end

local function saveProtected()
	local list = {}
	for key in pairs(protectedKeys) do table.insert(list, key) end
	writeJson(userFile("protected"), list)
end

loadProtected()

local function setContains(set, value)
	if not value then return false end

	for _, name in ipairs(set) do
		if name == value then return true end
	end

	return false
end

local function sellWanted(entry, chance)
	local attributes = entry.attributes or {}

	if F.sellMode == "Chance" then
		return F.sellThreshold > 0 and chance > 0 and chance < F.sellThreshold
	end

	local hitGrade = #F.sellGrades > 0 and setContains(F.sellGrades, attributes.grade)
	local hitTrait = #F.sellTraits > 0 and setContains(F.sellTraits, attributes.trait)
	local hitMutation = #F.sellMutations > 0 and setContains(F.sellMutations, attributes.mutation)
	local hitChance = F.sellThreshold > 0 and chance > 0 and chance < F.sellThreshold

	if F.sellMode == "Grade" then return hitGrade end
	if F.sellMode == "Trait" then return hitTrait end
	if F.sellMode == "Mutation" then return hitMutation end

	if F.sellMode == "Keep Listed" then
		if hitGrade or hitTrait or hitMutation then return false end
		return hitChance or (F.sellThreshold <= 0)
	end

	return hitChance or hitGrade or hitTrait or hitMutation
end

local function doSell(manual)
	local fn = getFn("SellService", "SellInventory")

	if not fn then
		if manual then notify("Sell", "SellInventory remote missing.", "error", 6) end
		return 0
	end

	if F.sellMode == "Chance" and F.sellThreshold <= 0 then
		if manual then notify("Sell", "Set a threshold first, e.g. 1t.", "warning", 6) end
		return 0
	end

	local sold = 0

	local ok = pcall(function()
		local inSlot = placedUnitKeys()
		local inTower = towerTeamKeys()
		local equipped = equippedKey()
		local candidates = {}

		for key, entry in pairs(inventory()) do
			if isUnitEntry(entry) and key ~= equipped and not inSlot[key] and not inTower[key] then
				if not (entry.attributes and entry.attributes.locked) and not protectedKeys[key] then
					local chance = unitChance(entry)

					if sellWanted(entry, chance) then
						table.insert(candidates, { key = key, chance = chance })
					end
				end
			end
		end

		table.sort(candidates, function(a, b) return a.chance < b.chance end)

		local keys = {}
		local keep = math.max(0, math.floor(tonumber(F.keepBest) or 0))

		for index, candidate in ipairs(candidates) do
			if index > #candidates - keep then break end
			table.insert(keys, candidate.key)
		end

		if #keys == 0 then return end

		local _, count = fn(keys)
		sold = tonumber(count) or #keys
	end)

	if ok and sold > 0 then
		Tally.sold = Tally.sold + sold
		clog(sold .. " units sold (" .. F.sellMode .. ").")
		if manual then notify("Sell", sold .. " units sold.", "success", 4) end
	elseif manual then
		notify("Sell", "Nothing matched the filter.", "warning", 4)
	end

	return sold
end

local function gameProtected(listName, key)
	if not key or not G.DC then return false end

	local ok, value = pcall(function()
		local field = G.DC[listName][key]
		if type(field) == "function" or type(field) == "table" then return field() end
		return field
	end)

	return (ok and value) and true or false
end

local function targetAbove(module, current, wanted)
	if not module then return false end

	local currentOrder = 0
	if current and module[current] and module[current].order then currentOrder = module[current].order end

	for name in pairs(wanted) do
		local def = module[name]
		if def and def.order and def.order > currentOrder then return true end
	end

	return false
end

local rerollNoted = {}

local function rerollTick(kind, manual)
	local isGrade = kind == "grade"

	local module = isGrade and G.GradesMod or G.TraitsMod
	local service = isGrade and "GradeService" or "TraitService"
	local protectedList = isGrade and "ProtectedGrades" or "ProtectedTraits"
	local currency = isGrade and "Gems" or "Trait Reroll"
	local reserve = isGrade and F.gemReserve or F.rerollReserve
	local targets = isGrade and F.gradeTargets or F.traitTargets
	local picks = isGrade and F.gradeUnits or F.traitUnits
	local useAll = isGrade and F.gradeAll or F.traitAll
	local placedOnly = isGrade and F.gradePlacedOnly or F.traitPlacedOnly
	local attribute = isGrade and "grade" or "trait"

	if Busy[kind] then return end

	if #targets == 0 then
		if manual then notify("Reroll", "Select target " .. attribute .. "s first.", "warning", 5) end
		return
	end

	if not module then
		if manual then notify("Reroll", "The " .. attribute .. " module is not loaded.", "error", 6) end
		return
	end

	if currencyAmount(currency) <= reserve then
		local noteKey = kind .. "_currency"

		if os.clock() - (rerollNoted[noteKey] or 0) > 60 then
			rerollNoted[noteKey] = os.clock()
			clog("Reroll waiting for " .. currency .. " (reserve " .. tostring(reserve) .. ").")
		end

		return
	end

	local signal = getSig(service, "Roll")

	if not signal then
		if manual then notify("Reroll", "The roll remote is missing.", "error", 6) end
		return
	end

	Busy[kind] = true

	local rolled = false

	pcall(function()
		local wanted = {}
		for _, name in ipairs(targets) do wanted[name] = true end

		local selected = {}
		if not useAll then
			for _, key in ipairs(picks) do selected[key] = true end
		end

		local placed = placedOnly and placedUnitKeys() or nil

		for key, entry in pairs(inventory()) do
			if not Alive then return end

			if isUnitEntry(entry) and (not placed or placed[key]) then
				if useAll or placedOnly or selected[key] then
					local current = entry.attributes and entry.attributes[attribute]

					if not current or not wanted[current] then
						local def = current and module[current]

						if def and def.protected then
							if targetAbove(module, current, wanted) then
								pcall(function() signal:Fire(key, true) end)
								rolled = true
								clog("Forced past protected " .. attribute .. ": " .. tostring(entry.name)
									.. " (" .. tostring(current) .. ")")
								return
							end

							local noteKey = key .. "|" .. tostring(current)

							if not rerollNoted[noteKey] then
								rerollNoted[noteKey] = true
								clog("Kept protected " .. attribute .. ": " .. tostring(entry.name)
									.. " (" .. tostring(current) .. ")")
							end
						else
							if current and gameProtected(protectedList, current) then
								pcall(function() signal:Fire(key, true) end)
								rolled = true
								clog("Skip-confirmed " .. attribute .. ": " .. tostring(entry.name)
									.. " (" .. tostring(current) .. ")")
								return
							end

							pcall(function() signal:Fire(key) end)
							rolled = true
							clog(attribute .. " rolled: " .. tostring(entry.name) .. " (" .. tostring(current) .. ")")
							return
						end
					end
				end
			end
		end

		local noteKey = kind .. "_done"

		if not rolled and os.clock() - (rerollNoted[noteKey] or 0) > 60 then
			rerollNoted[noteKey] = os.clock()
			clog("Reroll: every selected unit is already at a target " .. attribute .. ".")
		end
	end)

	Busy[kind] = false
end

local towerFloor = 1
local towerRunDrops, towerRunStart = {}, 1
local smartCapOrder, smartCapUntil = nil, 0
local sendTowerHook

local function towerRewardsAdd(rewards)
	for name, amount in pairs(rewards or {}) do
		amount = tonumber(amount) or 0
		Tally.towerRewards[name] = (Tally.towerRewards[name] or 0) + amount

		if name == "Gems" then
			Tally.towerGems = Tally.towerGems + amount
		elseif name == "Trait Reroll" then
			Tally.towerTraits = Tally.towerTraits + amount
		end
	end
end

local function handleTowerSeq(sequence, sawAction)
	local done = false

	for _, action in ipairs(sequence) do
		if type(action) == "table" then
			if action.action == "floorStarted" and tonumber(action.floor) then
				towerFloor = tonumber(action.floor)
				if towerFloor % 10 == 0 then clog("Tower floor " .. towerFloor) end

			elseif action.action == "floorCompleted" and type(action.rewards) == "table" then
				towerRewardsAdd(action.rewards)

				for name, amount in pairs(action.rewards) do
					towerRunDrops[name] = (towerRunDrops[name] or 0) + (tonumber(amount) or 0)
				end

			elseif action.action == "ended" then
				done = true

				local hasRewards = action.rewards and next(action.rewards)

				if hasRewards then
					local parts = {}
					for name, amount in pairs(action.rewards) do table.insert(parts, amount .. "x " .. name) end
					clog("Tower ended: " .. table.concat(parts, ", "))
				end

				if hasRewards and sawAction then
					Tally.towerWins[F.towerName] = (Tally.towerWins[F.towerName] or 0) + 1
					smartCapOrder = nil
					clog("Tower win counted.")

					if F.towerHookOn and sendTowerHook then
						local name, from, to, drops, bonus = F.towerName, towerRunStart, towerFloor, towerRunDrops, action.rewards
						task.spawn(function() sendTowerHook(name, from, to, drops, bonus, "Cleared") end)
					end
				elseif not hasRewards then
					clog("Tower wiped at floor " .. towerFloor .. ", not counted.")

					pcall(function()
						local def = G.TowersMod.Get(F.towerName)
						if def and def.order then
							smartCapOrder = def.order - 1
							smartCapUntil = os.clock() + 300
						end
					end)
				end

				break
			end
		end
	end

	return done
end

local function towerExitRestart()
	local at = math.floor(tonumber(F.towerExitFloor) or 0)
	if not F.towerExitOn or at <= 0 or towerFloor < at then return false end

	pcall(function()
		local cancel = getFn("Towers", "CancelTower")
		if cancel then cancel() end
	end)

	clog("Tower exit floor " .. towerFloor .. " reached, restarting " .. tostring(F.towerName) .. ".")

	if F.towerHookOn and sendTowerHook then
		local name, from, to, drops = F.towerName, towerRunStart, towerFloor, towerRunDrops
		task.spawn(function() sendTowerHook(name, from, to, drops, nil, "Exited") end)
	end

	towerFloor = 1

	return true
end

local function driveTower(step)
	local done, fails = false, 0

	while F.tower and Alive and not done do
		local ok, sequence = pcall(step)

		if ok and type(sequence) == "table" then
			if #sequence > 0 then
				fails = 0
				Tally.towerFloors = Tally.towerFloors + 1

				local saw = false

				for _, action in ipairs(sequence) do
					if type(action) == "table" and action.action ~= "ended" then saw = true break end
				end

				done = handleTowerSeq(sequence, saw)
				if not done and towerExitRestart() then done = true end
			else
				task.wait(0.25)
			end
		else
			fails = fails + 1
			if fails >= 8 then
				done = true
				clog("Tower step failed 8 times, restarting the loop.")
			end
			task.wait(1)
		end
	end
end

local function towerMults()
	local damage, health = 1, 1

	pcall(function()
		if not G.Upgrades then return end

		local owned = {}
		pcall(function() owned = G.DC.Upgrades() or {} end)

		local dSum, hSum = 0, 0

		for name in pairs(owned) do
			local def = G.Upgrades[name]

			if type(def) == "table" and type(def.buffs) == "table" then
				for buffName, buff in pairs(def.buffs) do
					local amount = tonumber(type(buff) == "table" and buff.amount or buff) or 0
					local lower = tostring(buffName):lower()

					if lower:find("damage") then
						dSum = dSum + amount
					elseif lower:find("health") then
						hSum = hSum + amount
					end
				end
			end
		end

		damage = damage * (1 + dSum)
		health = health * (1 + hSum)
	end)

	pcall(function()
		if not (G.BoostConfig and G.BoostConfig.entries) then return end

		local active = activePotions()
		local bestDamage, bestHealth = {}, {}

		for name in pairs(active) do
			local def = G.BoostConfig.entries[name]

			if def and type(def.buffs) == "table" then
				local category = tostring(def.category or "?")

				for buffName, buff in pairs(def.buffs) do
					local amount = tonumber(type(buff) == "table" and buff.amount or buff) or 0

					if amount > 0 then
						local lower = tostring(buffName):lower()

						if lower:find("damage") then
							bestDamage[category] = math.max(bestDamage[category] or 0, amount)
						elseif lower:find("health") then
							bestHealth[category] = math.max(bestHealth[category] or 0, amount)
						end
					end
				end
			end
		end

		for _, amount in pairs(bestDamage) do damage = damage * amount end
		for _, amount in pairs(bestHealth) do health = health * amount end
	end)

	return damage, health
end

local function towerTeamMembers(damageMult, healthMult)
	local members = {}

	local ok, team = pcall(function() return G.DC.TowerTeam() end)
	if not (ok and type(team) == "table") then return members end

	for _, key in pairs(team) do
		local entry = invEntry(key)

		if entry and entry.attributes then
			local cfg = entryConfig(entry.name)

			if cfg then
				local health, damage = 0, 0
				pcall(function() health = cfg.health(entry.attributes) end)
				pcall(function() damage = cfg.damage(entry.attributes) end)

				health, damage = tonumber(health) or 0, tonumber(damage) or 0

				if health > 0 and damage > 0 then
					table.insert(members, { h = health * (healthMult or 1), d = damage * (damageMult or 1) })
				end
			end
		end
	end

	return members
end

local function simTower(ref, members)
	local maxFloors = 100
	pcall(function() maxFloors = ref.maxFloors or 100 end)

	local tiers = {}

	pcall(function()
		for _, drop in ipairs(ref.drops or {}) do
			if tonumber(drop.minFloor) then table.insert(tiers, tonumber(drop.minFloor)) end
		end
	end)

	table.sort(tiers)

	local order = 0
	pcall(function() order = ref.order or 0 end)

	local hp = {}
	for index, member in ipairs(members) do hp[index] = member.h end

	local reach, score = 0, 0

	for floor = 1, maxFloors do
		local enemyHealth, enemyDamage = 0, 0
		pcall(function() enemyHealth = ref.enemyHealth(floor) end)
		pcall(function() enemyDamage = ref.enemyDamage(floor) end)

		enemyHealth = tonumber(enemyHealth) or math.huge
		enemyDamage = tonumber(enemyDamage) or math.huge

		local index = 1

		while index <= #members and enemyHealth > 0 do
			if hp[index] <= 0 then
				index = index + 1
			else
				while enemyHealth > 0 and hp[index] > 0 do
					enemyHealth = enemyHealth - members[index].d
					if enemyHealth > 0 then hp[index] = hp[index] - enemyDamage end
				end

				if hp[index] <= 0 then index = index + 1 end
			end
		end

		if enemyHealth > 0 then break end

		reach = floor

		local tierCount = 0
		for _, minFloor in ipairs(tiers) do
			if floor >= minFloor then tierCount = tierCount + 1 end
		end

		score = score + order * 100 + tierCount * 10
	end

	return reach, score
end

local function towerNames()
	local list = {}

	pcall(function()
		for name in pairs(G.TowersMod.GetAll()) do
			table.insert(list, name)
		end
	end)

	table.sort(list, function(a, b)
		local oa, ob = 99, 99
		pcall(function() oa = G.TowersMod.Get(a).order or 99 end)
		pcall(function() ob = G.TowersMod.Get(b).order or 99 end)
		if oa ~= ob then return oa < ob end
		return a < b
	end)

	if #list == 0 then table.insert(list, F.towerName) end

	return list
end

local function smartTowerPick()
	if not G.TowersMod then return F.towerName, nil end

	local damageMult, healthMult = towerMults()
	local members = towerTeamMembers(damageMult, healthMult)

	if #members == 0 then return F.towerName, nil end

	local candidates = {}

	pcall(function()
		for name in pairs(G.TowersMod.GetAll()) do
			if name ~= "Infinity Tower" then
				local def = G.TowersMod.Get(name)
				if def and def.order then table.insert(candidates, { name = name, ref = def }) end
			end
		end
	end)

	if #candidates == 0 then return F.towerName, nil end

	local cap = (smartCapOrder and os.clock() < smartCapUntil) and smartCapOrder or nil
	local best, bestScore, bestReach, bestOrder = nil, -1, 0, -1
	local detail = {}

	for _, candidate in ipairs(candidates) do
		local order = 99
		pcall(function() order = candidate.ref.order or 99 end)

		if cap and order > cap then
			table.insert(detail, candidate.name .. "=capped")
		else
			local reach, score = simTower(candidate.ref, members)

			if (Tally.towerWins[candidate.name] or 0) > 0 then
				local maxFloors = 100
				pcall(function() maxFloors = candidate.ref.maxFloors or 100 end)

				if reach < maxFloors then
					reach = maxFloors
					local tierCount = 0

					pcall(function()
						for _, drop in ipairs(candidate.ref.drops or {}) do
							if tonumber(drop.minFloor) and tonumber(drop.minFloor) <= maxFloors then
								tierCount = tierCount + 1
							end
						end
					end)

					score = order * 100 * maxFloors + tierCount * 10
				end
			end

			table.insert(detail, candidate.name .. " f" .. tostring(reach))

			if score > bestScore or (score == bestScore and order > bestOrder) then
				best, bestScore, bestReach, bestOrder = candidate.name, score, reach, order
			end
		end
	end

	table.sort(detail)
	table.insert(detail, 1, "buffs " .. fmt(damageMult) .. "dmg/" .. fmt(healthMult) .. "hp")

	local info = best and { reach = bestReach, score = bestScore, detail = table.concat(detail, ", ") } or nil

	return best or F.towerName, info
end

local towerDropdown = nil

local function syncTowerDropdown()
	if not towerDropdown then return end
	pcall(function() towerDropdown:Set(F.towerName, true) end)
end

local function runSmartTower()
	local pick, info = smartTowerPick()

	if pick and pick ~= F.towerName then
		F.towerName = pick
		clog("Smart tower: " .. pick .. (info and (" (f~" .. info.reach .. " [" .. info.detail .. "])") or ""))
	elseif pick then
		clog("Smart tower checked: " .. pick .. (info and (" f~" .. info.reach) or "") .. ", already best")
	else
		clog("Smart tower: no team found, keeping " .. tostring(F.towerName))
	end

	syncTowerDropdown()
end

local function doTowerLoop()
	if Busy.tower then return end
	Busy.tower = true

	local play = getFn("Towers", "PlayTower")
	local step = getFn("Towers", "CompleteTowerFloor")

	if not play or not step then
		clog("Tower remotes missing.")
		Busy.tower = false
		return
	end

	while F.tower and Alive do
		if F.towerEquipBest then
			local signal = getSig("Towers", "EquipBestTowerTeam")
			if signal then pcall(function() signal:Fire() end) end
			task.wait(0.5)
		end

		if F.smartTower then runSmartTower() end

		local okStart, started = pcall(play, F.towerName)

		if okStart and started then
			clog("Tower started: " .. F.towerName)
			towerFloor = 1
			towerRunDrops, towerRunStart = {}, 1
			driveTower(step)
		else
			local okStep, sequence = pcall(step)

			if okStep and type(sequence) == "table" and #sequence > 0 then
				clog("Found an active tower run, continuing it.")
				towerRunDrops = {}
				Tally.towerFloors = Tally.towerFloors + 1

				local saw = false

				for _, action in ipairs(sequence) do
					if type(action) == "table" and action.action ~= "ended" then saw = true break end
				end

				local done = handleTowerSeq(sequence, saw)
				if not done and towerExitRestart() then done = true end
				if not done then driveTower(step) end
			else
				clog("Tower failed to start: " .. F.towerName .. " (team or cooldown)")
				task.wait(5)
			end
		end
	end

	pcall(function()
		local cancel = getFn("Towers", "CancelTower")
		if cancel then cancel() end
	end)

	Busy.tower = false
end

local function doRedeemCodes(manual)
	local signal = getSig("MonetizationService", "RedeemCode")

	if not signal then
		if manual then notify("Codes", "Redeem remote missing.", "error", 6) end
		return
	end

	local redeemed = {}

	pcall(function()
		local list = G.DC.RedeemedCodes()

		if type(list) == "table" then
			for key, value in pairs(list) do
				if value == true then redeemed[key] = true else redeemed[value] = true end
			end
		end
	end)

	local queue = {}

	pcall(function()
		local codes = G.MonetConfig and G.MonetConfig.Codes

		if type(codes) == "table" then
			for code in pairs(codes) do
				if type(code) == "string" and code ~= "" and not redeemed[code] then
					table.insert(queue, code)
				end
			end
		end
	end)

	table.sort(queue)

	if #queue == 0 then
		if manual then notify("Codes", "Every code is already redeemed.", "success", 4) end
		return
	end

	local worked = 0

	for _, code in ipairs(queue) do
		if not Alive then break end

		pcall(function() signal:Fire(code) end)
		task.wait(0.6)

		local got = false

		pcall(function()
			local list = G.DC.RedeemedCodes()
			if type(list) == "table" then got = list[code] == true end
		end)

		if got then
			worked = worked + 1
			clog("Code redeemed: " .. code)
		end
	end

	notify("Codes", worked .. " / " .. #queue .. " new codes redeemed.", worked > 0 and "success" or "warning", 5)
end

local function doClaimQuests()
	local signal = getSig("QuestService", "Claim")
	if not signal or not G.QuestConfig then return end

	local now = 0
	pcall(function() now = workspace:GetServerTimeNow() end)

	for _, period in ipairs({ "Daily", "Weekly" }) do
		if not Alive then break end

		local ok, quest = pcall(function() return G.DC.Quests[period]() end)

		if ok and type(quest) == "table" then
			local expires = tonumber(quest.expiresAt) or 0

			if expires == 0 or expires > math.floor(now) then
				local defs = {}
				pcall(function() defs = G.QuestConfig.Periods[period].quests end)

				local progress = quest.progress or {}
				local claimed = quest.claimed or {}

				for _, def in ipairs(defs or {}) do
					if not Alive then break end

					if def.id and not claimed[def.id]
						and (tonumber(progress[def.id]) or 0) >= (tonumber(def.target) or math.huge) then
						pcall(function() signal:Fire(period, def.id, expires) end)
						clog("Quest claimed: " .. period .. " " .. tostring(def.id))
						task.wait(0.5)
					end
				end
			end
		end
	end
end

local VISIT_TTL = 2700
local hopBusy = false
local lastHopAt = 0
local doHop

local function loadVisited()
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

local function saveVisited(visited)
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

pcall(function()
	TeleportService.TeleportInitFailed:Connect(function(_, result, message)
		if hopBusy then return end
		notify("Server Hop", "Teleport failed: " .. tostring(message ~= "" and message or result), "error", 6)
	end)
end)

function doHop(lowPop, isBlocked)
	task.spawn(function()
		if type(isBlocked) == "function" and isBlocked() then return end

		if os.clock() - lastHopAt < 30 then
			notify("Server Hop", "On cooldown, skipped.", "warning", 4)
			return
		end

		lastHopAt = os.clock()
		notify("Server Hop", "Searching servers.", "info", 3)

		local visited = loadVisited()
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

		if type(isBlocked) == "function" and isBlocked() then
			notify("Server Hop", "Cancelled.", "warning", 4)
			return
		end

		local myJob = game.JobId

		if #candidates == 0 then
			local oldest, oldestAt = nil, nil

			for job, stamp in pairs(visited) do
				if job ~= myJob and (not oldestAt or stamp < oldestAt) then oldest, oldestAt = job, stamp end
			end

			visited[myJob] = os.time()
			if oldest then visited[oldest] = os.time() end
			saveVisited(visited)

			hopBusy = true

			if oldest then
				notify("Server Hop", "Every recent server was visited, going back to the oldest.", "info", 5)
				local ok = pcall(function()
					TeleportService:TeleportToPlaceInstance(game.PlaceId, oldest, LocalPlayer)
				end)

				if not ok then
					pcall(function() TeleportService:Teleport(game.PlaceId, LocalPlayer) end)
				end
			else
				notify("Server Hop", "List empty, random hop.", "info", 4)
				pcall(function() TeleportService:Teleport(game.PlaceId, LocalPlayer) end)
			end

			hopBusy = false
			return
		end

		if lowPop then
			table.sort(candidates, function(a, b) return (a.playing or 0) < (b.playing or 0) end)
		else
			table.sort(candidates, function(a, b) return (a.playing or 0) > (b.playing or 0) end)
		end

		hopBusy = true

		local failMessage, pending = nil, false

		local connection = TeleportService.TeleportInitFailed:Connect(function(player, result, message)
			if player == LocalPlayer then
				pending = false
				failMessage = tostring((message and message ~= "") and message or result)
			end
		end)

		visited[myJob] = os.time()

		local tries = math.min(5, #candidates)

		for index = 1, tries do
			if type(isBlocked) == "function" and isBlocked() then
				pcall(function() connection:Disconnect() end)
				hopBusy = false
				notify("Server Hop", "Cancelled.", "warning", 4)
				return
			end

			local server = candidates[index]
			visited[server.id] = os.time()
			saveVisited(visited)

			notify("Server Hop", "Teleporting, " .. tostring(server.playing) .. " players.", "info", 3)

			failMessage, pending = nil, true

			local ok, err = pcall(function()
				TeleportService:TeleportToPlaceInstance(game.PlaceId, server.id, LocalPlayer)
			end)

			if ok then
				local waited = 0

				while waited < 10 and pending and game.JobId == myJob do
					task.wait(1)
					waited = waited + 1
				end

				if game.JobId ~= myJob or pending then
					pending = false
					pcall(function() connection:Disconnect() end)
					hopBusy = false
					return
				end
			else
				pending = false
				failMessage = tostring(err)
			end

			notify("Server Hop", "Attempt " .. index .. "/" .. tries .. " failed ("
				.. tostring(failMessage or "unknown") .. ").", "warning", 4)
		end

		pcall(function() connection:Disconnect() end)
		hopBusy = false
		notify("Server Hop", "Every try failed, random hop.", "warning", 5)
		pcall(function() TeleportService:Teleport(game.PlaceId, LocalPlayer) end)
	end)
end

local tradeEvent = { name = "", time = 0, data = nil }
local tradeOffers = { own = nil, other = nil }
local inTradeSession = false
local tradePartner = nil
local tradeCounted = false
local tradeListener = nil
local tradeDriving = false
local tradeActive = false
local lastTradeEnd = 0
local sendTradeHook

local function tradeScreenOpen()
	if inTradeSession then return true end
	local ok, visible = pcall(function() return G.UIRefs.Root.Trading.TradeScreen.Visible end)
	return ok and visible and true or false
end

local function offerCount(offer)
	if type(offer) ~= "table" then return 0 end

	local count = 0
	for _ in pairs(offer) do count = count + 1 end

	return count
end

local function offerText(offer)
	if type(offer) ~= "table" then return "(empty)" end

	local parts = {}

	for key, value in pairs(offer) do
		local name, extra = tostring(key), ""

		pcall(function()
			local entry = invEntry(key) or (type(value) == "string" and invEntry(value))

			if entry and type(entry) == "table" and entry.name then
				name = tostring(entry.name)
				local chance = unitChance(entry)

				if chance > 0 then
					extra = " [1 in " .. fmt(chance) .. "]"
				elseif tonumber(entry.amount) then
					extra = " x" .. tostring(entry.amount)
				end
			elseif type(value) == "table" then
				if value.name then name = tostring(value.name) end
				if tonumber(value.amount) then extra = " x" .. tostring(value.amount) end
			elseif type(value) ~= "boolean" and tostring(value) ~= "" then
				extra = " x" .. tostring(value)
			end
		end)

		table.insert(parts, name .. extra)
	end

	if #parts == 0 then return "(empty)" end

	table.sort(parts)

	local text = table.concat(parts, ", ")
	if #text > 900 then text = text:sub(1, 900) .. "..." end

	return text
end

local function tradeEnsureListener()
	if tradeListener then return end

	local signal = getSig("TradeService", "TradeEvent")
	if not signal then return end

	local ok = pcall(function()
		tradeListener = signal:Connect(function(event, payload)
			tradeEvent = { name = tostring(event), time = os.clock(), data = payload }

			local name = tostring(event)

			if type(payload) == "table" and payload.partner ~= nil then
				pcall(function()
					local partner = payload.partner
					tradePartner = partner.DisplayName or partner.Name or tostring(partner)
				end)
			end

			if name == "Started" then
				inTradeSession = true

				if not tradeCounted then
					tradeCounted = true
					Tally.tradesOpened = Tally.tradesOpened + 1
					tradeOffers = { own = nil, other = nil }
					clog("Trade open with " .. tostring(tradePartner or "?") .. ".")
				end

			elseif name == "Ended" then
				inTradeSession = false

				local reason = "Ended"

				pcall(function()
					if type(payload) == "table" and payload.reason ~= nil then
						reason = tostring(payload.reason)
					elseif payload ~= nil then
						reason = tostring(payload)
					end
				end)

				if tradeCounted then
					tradeCounted = false

					if reason == "Completed" then
						clog("Trade completed with " .. tostring(tradePartner or "?") .. ".")

						if F.tradeHookOn and sendTradeHook then
							local partner, own, other = tostring(tradePartner or "?"), tradeOffers.own, tradeOffers.other
							task.spawn(function() sendTradeHook(partner, own, other, "Completed") end)
						end
					else
						clog("Trade ended (" .. reason .. ") with " .. tostring(tradePartner or "?") .. ".")
					end
				end

			elseif name == "RequestExpired" or name == "RequestClosed" then
				inTradeSession = false
			end

			pcall(function()
				if type(payload) == "table" then
					if payload.otherOffer ~= nil then tradeOffers.other = payload.otherOffer end
					if payload.ownOffer ~= nil then tradeOffers.own = payload.ownOffer end
				end
			end)
		end)
	end)

	if not ok then tradeListener = nil end
end

local function otherMoney(player)
	local stats = player:FindFirstChild("leaderstats")
	local value = stats and stats:FindFirstChild("Money")
	if not (value and typeof(value.Value) == "string") then return 0 end
	return parseCompact(value.Value) or 0
end

local function otherRolls(player)
	local stats = player:FindFirstChild("leaderstats")
	local value = stats and stats:FindFirstChild("Rolls")
	if value then return tonumber(value.Value) or 0 end
	return 0
end

local function tradeTargets()
	local list = {}
	if F.tradeMoney <= 0 then return list end

	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer then
			local amount = otherMoney(player)
			if amount >= F.tradeMoney and otherRolls(player) >= 1000 then
				table.insert(list, { player = player, money = amount })
			end
		end
	end

	table.sort(list, function(a, b) return a.money > b.money end)

	return list
end

local function waitTradeEvent(names, timeout)
	local start = os.clock()

	while os.clock() - start < timeout do
		if not F.tradeAuto or not Alive then return nil end
		if tradeEvent.time > start and names[tradeEvent.name] then return tradeEvent.name end
		task.wait(0.25)
	end

	return nil
end

local function driveTrade()
	if tradeDriving then return end

	local advance = getSig("TradeService", "AdvanceTrade")
	if not advance then return end

	tradeDriving = true

	local readyTries, acceptTries = 0, 0
	local start = os.clock()

	while F.tradeAutoGo and Alive and tradeScreenOpen() and os.clock() - start < 45 do
		local data = tradeEvent.data

		if type(data) == "table" then
			local minItems = math.max(1, tonumber(F.tradeMinItems) or 1)
			local enough = (not F.tradeNeedOffer) or offerCount(data.otherOffer) >= minItems

			if data.phase == "Offer" then
				local ready = data.ownReady and true or false
				if ready then readyTries = 0 end

				if enough and not ready and readyTries < 3 then
					readyTries = readyTries + 1
					pcall(function() advance:Fire() end)
					clog("Trade auto ready.")
					task.wait(1)
				end

			elseif data.phase == "Confirm" then
				local accepted = data.ownAccepted and true or false
				if accepted then acceptTries = 0 end

				if enough and not accepted and acceptTries < 3 then
					acceptTries = acceptTries + 1
					pcall(function() advance:Fire() end)
					clog("Trade auto accept.")
					task.wait(2)
				end
			end
		end

		task.wait(0.5)
	end

	tradeDriving = false

	if F.tradeAutoGo and Alive and tradeScreenOpen() and os.clock() - start >= 45 then
		local cancel = getSig("TradeService", "CancelTrade")
		if cancel then pcall(function() cancel:Fire() end) end
		clog("Trade timed out, cancelled.")
	end
end

local function tradePlayer(player)
	local request = getSig("TradeService", "RequestTrade")
	if not request then return false end

	local tries = math.max(1, tonumber(F.tradeRetries) or 3)

	for attempt = 1, tries do
		if not F.tradeAuto or not Alive then return false end
		if not player.Parent then return false end

		if tradeScreenOpen() then
			clog("Trade already open, not requesting " .. player.DisplayName .. ".")
			return false
		end

		tradeEvent = { name = "", time = 0, data = nil }

		pcall(function() request:Fire(player) end)
		Tally.tradesSent = Tally.tradesSent + 1
		clog("Trade request: " .. player.DisplayName .. " (" .. attempt .. "/" .. tries .. ")")

		local event = waitTradeEvent({
			Started = true, RequestExpired = true, RequestClosed = true, Ended = true,
		}, 8)

		if event == "Started" then
			tradeActive = true
			tradeEvent.data = nil

			local ended = waitTradeEvent({ Ended = true }, 45)

			if ended == nil and F.tradeAuto and Alive then
				local cancel = getSig("TradeService", "CancelTrade")
				if cancel then pcall(function() cancel:Fire() end) end
				clog("Trade timed out after 45s, cancelled: " .. player.DisplayName .. ".")
				waitTradeEvent({ Ended = true }, 5)
			end

			lastTradeEnd = os.clock()
			tradeActive = false

			return true
		end

		task.wait(1)
	end

	clog("Trade: no answer from " .. player.DisplayName)

	return false
end

local tradeTried = {}
local tradeEmptySince = 0
local tradeWarned = false

local function doTradeLoop()
	if Busy.trade then return end
	Busy.trade = true
	tradeActive = false

	pcall(function()
		local enable = getSig("TradeService", "SetTradeRequestsEnabled")
		if enable then enable:Fire(true) end
	end)

	tradeEnsureListener()

	while F.tradeAuto and Alive do
		if (tonumber(F.tradeMoney) or 0) <= 0 then
			if not tradeWarned then
				tradeWarned = true
				clog("Trade: set a minimum money first, idling.")
				notify("Trade", "Set Min Money first.", "warning", 5)
			end

			task.wait(5)
		else

		tradeWarned = false

		local candidates = {}

		for _, candidate in ipairs(tradeTargets()) do
			if not tradeTried[candidate.player.UserId] then table.insert(candidates, candidate) end
		end

		if #candidates == 0 then
			if tradeEmptySince == 0 then tradeEmptySince = os.clock() end

			local delay = math.clamp(tonumber(F.tradeHopDelay) or 8, 1, 30)

			if F.tradeHop and not tradeActive and not tradeScreenOpen()
				and os.clock() - lastTradeEnd > delay and os.clock() - tradeEmptySince >= delay then
				clog("Trade: nobody matches, hopping.")
				tradeTried = {}
				tradeEmptySince = 0

				doHop(false, function() return (not F.tradeAuto) or tradeScreenOpen() end)

				local waited = 0
				while F.tradeAuto and Alive and waited < 12 do
					task.wait(1)
					waited = waited + 1
				end
			else
				task.wait(3)
			end
		else
			tradeEmptySince = 0

			if tradeScreenOpen() then
				task.wait(3)
			else
				local candidate = candidates[1]
				tradePlayer(candidate.player)
				tradeTried[candidate.player.UserId] = true
				task.wait(1)
			end
		end

		end
	end

	Busy.trade = false
end

local function stopTrades()
	F.tradeAuto = false
	F.tradeAutoGo = false

	local cancel = getSig("TradeService", "CancelTrade")
	if cancel then pcall(function() cancel:Fire() end) end

	pcall(function()
		local enable = getSig("TradeService", "SetTradeRequestsEnabled")
		if enable then enable:Fire(false) end
	end)

	tradeTried = {}
	clog("Trade stopped and cancelled.")
end

local fpsRestore, fpsHidden, fpsConnection, fpsKeptPlot = {}, {}, nil, nil

local function fpsDisable(instance)
	pcall(function()
		if instance:IsA("ParticleEmitter") or instance:IsA("Trail") or instance:IsA("Beam")
			or instance:IsA("Smoke") or instance:IsA("Fire") or instance:IsA("Sparkles") then
			if instance.Enabled then
				table.insert(fpsRestore, { o = instance, p = "Enabled", v = true })
				instance.Enabled = false
			end

		elseif instance:IsA("Decal") or instance:IsA("Texture") then
			if instance.Transparency < 1 then
				table.insert(fpsRestore, { o = instance, p = "Transparency", v = instance.Transparency })
				instance.Transparency = 1
			end

		elseif instance:IsA("MeshPart") then
			if instance.CastShadow then
				table.insert(fpsRestore, { o = instance, p = "CastShadow", v = true })
				instance.CastShadow = false
			end
			if instance.TextureID ~= "" then
				table.insert(fpsRestore, { o = instance, p = "TextureID", v = instance.TextureID })
				instance.TextureID = ""
			end

		elseif instance:IsA("BasePart") and not instance:IsA("Terrain") then
			if instance.CastShadow then
				table.insert(fpsRestore, { o = instance, p = "CastShadow", v = true })
				instance.CastShadow = false
			end

		elseif instance:IsA("PointLight") or instance:IsA("SpotLight") or instance:IsA("SurfaceLight")
			or instance:IsA("PostEffect") then
			if instance.Enabled then
				table.insert(fpsRestore, { o = instance, p = "Enabled", v = true })
				instance.Enabled = false
			end
		end
	end)
end

local function fpsHide(instance)
	pcall(function()
		if not instance or not instance.Parent then return end

		for _, record in ipairs(fpsHidden) do
			if record.o == instance then return end
		end

		table.insert(fpsHidden, { o = instance, parent = instance.Parent })
		instance.Parent = nil
	end)
end

local function ownPlot()
	local plots = workspace:FindFirstChild("Plots")
	local claimed = plots and plots:FindFirstChild("Claimed")
	if not claimed then return nil end

	local display, name = "", ""
	pcall(function() display = tostring(LocalPlayer.DisplayName or ""):lower() end)
	pcall(function() name = tostring(LocalPlayer.Name or ""):lower() end)

	for _, plot in ipairs(claimed:GetChildren()) do
		local hit = false

		pcall(function()
			for _, descendant in ipairs(plot:GetDescendants()) do
				if descendant:IsA("TextLabel") and descendant.Name == "PlayerName" then
					local text = tostring(descendant.Text or ""):lower()
					if (display ~= "" and text == display) or (name ~= "" and text == name) then hit = true end
					break
				end
			end
		end)

		if hit then return plot end
	end

	local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")

	if root then
		local best, bestDistance = nil, math.huge

		pcall(function()
			for _, plot in ipairs(claimed:GetChildren()) do
				local ok, pivot = pcall(function() return plot:GetPivot() end)

				if ok and pivot then
					local distance = (pivot.Position - root.Position).Magnitude
					if distance < bestDistance then best, bestDistance = plot, distance end
				end
			end
		end)

		if best then return best end
	end

	return nil
end

local function isDecor(child)
	local name = child.Name

	if child:IsA("Model") then
		return name == "Palm Tree" or name == "Mountain" or name == "LOW POLY ISLAND"
			or name == "LightHouse" or name == "Wind"
	elseif child:IsA("MeshPart") then
		return name == "Rock 1" or name == "Grass"
	end

	return false
end

local function stripMap()
	for _, name in ipairs({ "Leaderboards", "BestRollPoduium", "Limiteds" }) do
		pcall(function()
			local found = workspace:FindFirstChild(name)
			if found then fpsHide(found) end
		end)
	end

	pcall(function()
		local map = workspace:FindFirstChild("Map")
		local tower = map and map:FindFirstChild("CastleTower")
		if tower then fpsHide(tower) end
	end)

	pcall(function()
		local plots = workspace:FindFirstChild("Plots")
		local unclaimed = plots and plots:FindFirstChild("Unclaimed")
		if unclaimed then fpsHide(unclaimed) end
	end)

	pcall(function()
		local plots = workspace:FindFirstChild("Plots")
		local claimed = plots and plots:FindFirstChild("Claimed")

		if claimed then
			fpsKeptPlot = ownPlot()

			for _, plot in ipairs(claimed:GetChildren()) do
				if plot ~= fpsKeptPlot then fpsHide(plot) end
			end
		end
	end)

	pcall(function()
		local folder = workspace:FindFirstChild("Players")

		if folder then
			for _, model in ipairs(folder:GetChildren()) do
				if model:IsA("Model") and model.Name ~= LocalPlayer.Name then fpsHide(model) end
			end
		end
	end)

	pcall(function()
		local map = workspace:FindFirstChild("Map")
		if not map then return end

		for _, child in ipairs(map:GetChildren()) do
			if child:IsA("Model") and child.Name == "Model" and #child:GetDescendants() > 0 then
				local keep = false

				pcall(function()
					for _, descendant in ipairs(child:GetDescendants()) do
						if descendant.Name == "LobbyCircle" or descendant.Name == "Conveyor" then
							keep = true
							break
						end
					end
				end)

				if not keep then fpsHide(child) end
			end
		end

		for _, child in ipairs(map:GetDescendants()) do
			if isDecor(child) then fpsHide(child) end
		end
	end)
end

local function setFpsBoost(state)
	if state then
		pcall(function()
			local signal = getSig("SettingsService", "SetSetting")
			if signal then signal:Fire("Performance", true) end
		end)

		table.clear(fpsRestore)
		table.clear(fpsHidden)
		fpsKeptPlot = nil

		pcall(function()
			table.insert(fpsRestore, { o = Lighting, p = "GlobalShadows", v = Lighting.GlobalShadows })
			Lighting.GlobalShadows = false
			table.insert(fpsRestore, { o = Lighting, p = "FogEnd", v = Lighting.FogEnd })
			Lighting.FogEnd = 100000
			table.insert(fpsRestore, { o = Lighting, p = "EnvironmentDiffuseScale", v = Lighting.EnvironmentDiffuseScale })
			Lighting.EnvironmentDiffuseScale = 0
			table.insert(fpsRestore, { o = Lighting, p = "EnvironmentSpecularScale", v = Lighting.EnvironmentSpecularScale })
			Lighting.EnvironmentSpecularScale = 0
		end)

		pcall(function()
			local terrain = workspace.Terrain
			table.insert(fpsRestore, { o = terrain, p = "WaterWaveSize", v = terrain.WaterWaveSize })
			table.insert(fpsRestore, { o = terrain, p = "WaterWaveSpeed", v = terrain.WaterWaveSpeed })
			table.insert(fpsRestore, { o = terrain, p = "WaterReflectance", v = terrain.WaterReflectance })
			table.insert(fpsRestore, { o = terrain, p = "Decoration", v = terrain.Decoration })
			terrain.WaterWaveSize = 0
			terrain.WaterWaveSpeed = 0
			terrain.WaterReflectance = 0
			terrain.Decoration = false
		end)

		for _, object in ipairs(workspace:GetDescendants()) do fpsDisable(object) end
		stripMap()

		pcall(function()
			for _, object in ipairs(Lighting:GetDescendants()) do fpsDisable(object) end
		end)

		pcall(function()
			local rendering = settings().Rendering
			table.insert(fpsRestore, { o = rendering, p = "QualityLevel", v = rendering.QualityLevel })
			rendering.QualityLevel = Enum.QualityLevel.Level01
		end)

		if not fpsConnection then
			fpsConnection = workspace.DescendantAdded:Connect(function(object)
				if not F.fpsOn then return end

				fpsDisable(object)

				pcall(function()
					local parent = object.Parent
					if not parent then return end

					if parent == workspace:FindFirstChild("Players") then
						if object:IsA("Model") and object.Name ~= LocalPlayer.Name then fpsHide(object) end
					elseif parent.Name == "Claimed" and parent.Parent and parent.Parent.Name == "Plots" then
						if object ~= fpsKeptPlot then fpsHide(object) end
					end
				end)
			end)
		end

		task.delay(8, function()
			if F.fpsOn then
				for _, object in ipairs(workspace:GetDescendants()) do fpsDisable(object) end
				stripMap()
			end
		end)

		notify("Performance", "FPS boost on, other bases and effects hidden.", "success", 5)
	else
		if fpsConnection then
			pcall(function() fpsConnection:Disconnect() end)
			fpsConnection = nil
		end

		for index = #fpsHidden, 1, -1 do
			local record = fpsHidden[index]
			pcall(function() record.o.Parent = record.parent end)
		end

		table.clear(fpsHidden)
		fpsKeptPlot = nil

		for _, record in ipairs(fpsRestore) do
			pcall(function() record.o[record.p] = record.v end)
		end

		table.clear(fpsRestore)
		notify("Performance", "FPS boost off, map restored.", "info", 4)
	end
end

onCleanup(function() pcall(setFpsBoost, false) end)

local rollHideConns = {}

local function rollHideBackup(state)
	for _, connection in ipairs(rollHideConns) do
		pcall(function() connection:Disconnect() end)
	end

	table.clear(rollHideConns)

	if not state then return end

	pcall(function()
		local rolling = G.UIRefs.Root.Rolling

		for _, instance in ipairs({ rolling.Frame, rolling.DarkBackground }) do
			if instance.Visible then instance.Visible = false end

			table.insert(rollHideConns, instance:GetPropertyChangedSignal("Visible"):Connect(function()
				if F.hideRolls and instance.Visible then instance.Visible = false end
			end))
		end
	end)
end

onCleanup(function() rollHideBackup(false) end)

local function pressHiddenRoll()
	local ok, button = pcall(function() return G.UIRefs.Root.Rolling.Options.HiddenRoll end)
	if not ok or not button or type(getconnections) ~= "function" then return false end

	local fine, connections = pcall(getconnections, button.Activated)
	if not fine or type(connections) ~= "table" then return false end

	for _, connection in ipairs(connections) do
		pcall(function() connection.Function() end)
	end

	task.wait(0.7)

	return true
end

local function isRollHidden()
	local first, second = nil, nil

	pcall(function() first = G.UIRefs.Root.Rolling.Frame.Position end)
	task.wait(0.25)
	pcall(function() second = G.UIRefs.Root.Rolling.Frame.Position end)

	if not first or not second then return nil end

	if math.abs(first.Y.Scale - second.Y.Scale) > 0.05
		or math.abs(first.Y.Offset - second.Y.Offset) > 20 then
		return nil
	end

	return second.Y.Offset > 50
end

local function syncRollHidden()
	for _ = 1, 2 do
		local current = isRollHidden()
		if current == nil then return end
		if current == F.hideRolls then return end
		if not pressHiddenRoll() then return end
	end
end

local HOOK_FILE = CFG_FOLDER .. "/webhooks.json"

local Hooks = {
	List = {},
	Roll = nil,
	Stats = nil,
	Tower = nil,
	Trade = nil,
	Picks = { Roll = 0, Stats = 0, Tower = 0, Trade = 0 },
}

local HOOK_KINDS = { "Roll", "Stats", "Tower", "Trade" }

local function hookId(url)
	return tostring(url):match("/webhooks/(%d+)") or "unknown"
end

local function validUrl(url)
	url = tostring(url or ""):gsub("^%s+", ""):gsub("%s+$", "")

	if not url:match("^https://[%w%.%-]*discord") then return nil end
	if not url:match("/webhooks/%d+/") then return nil end

	return url
end

local function hookChoices()
	local names = { "None" }

	for index, entry in ipairs(Hooks.List) do
		table.insert(names, string.format("%d. %s", index, entry.Name))
	end

	return names
end

local function saveHooks()
	writeJson(HOOK_FILE, Hooks.List)
end

local function buildHook(url)
	if not Webhook then return nil end

	local ok, built = pcall(function()
		return Webhook.new(url, { Username = "Facility" })
	end)

	if not ok or type(built) ~= "table" then return nil end

	return built
end

local hookStatus, hookDropdowns = nil, {}

local function refreshHooks()
	local text

	if #Hooks.List == 0 then
		text = "no webhook saved"
	else
		local used = {}

		for _, kind in ipairs(HOOK_KINDS) do
			if Hooks.Picks[kind] > 0 then table.insert(used, kind) end
		end

		text = string.format("%d saved  ·  %s",
			#Hooks.List,
			#used > 0 and ("in use: " .. table.concat(used, ", ")) or "none assigned")
	end

	if hookStatus then
		pcall(function() hookStatus:Set(text) end)
	end

	for _, dropdown in pairs(hookDropdowns) do
		pcall(function() dropdown:SetOptions(hookChoices()) end)
	end
end

local function assignHook(kind, index)
	index = tonumber(index) or 0

	local entry = Hooks.List[index]

	if not entry then
		Hooks.Picks[kind] = 0
		Hooks[kind] = nil
		refreshHooks()
		return
	end

	local built = buildHook(entry.Url)

	if not built then
		notify("Webhooks", "Could not build that webhook.", "error", 6)
		return
	end

	Hooks.Picks[kind] = index
	Hooks[kind] = built

	refreshHooks()
end

local function addHook(url, quiet)
	url = validUrl(url)

	if not url then
		if not quiet then notify("Webhooks", "That is not a Discord webhook url.", "error", 6) end
		return false
	end

	for index, entry in ipairs(Hooks.List) do
		if entry.Url == url then
			if not quiet then notify("Webhooks", "Already saved.", "warning", 4) end
			return true, index
		end
	end

	local id = hookId(url)

	table.insert(Hooks.List, {
		Url = url,
		Id = "..." .. id:sub(-6),
		Name = "hook " .. id:sub(-6),
		Added = os.date("%H:%M"),
	})

	saveHooks()
	refreshHooks()

	notify("Webhooks", "Saved as hook " .. id:sub(-6) .. ", assign it below.", "success", 5)

	return true, #Hooks.List
end

local function loadHooks()
	local data = readJson(HOOK_FILE)
	if type(data) ~= "table" then return end

	for _, entry in ipairs(data) do
		if type(entry) == "table" and validUrl(entry.Url) then
			table.insert(Hooks.List, {
				Url = entry.Url,
				Id = entry.Id or ("..." .. hookId(entry.Url):sub(-6)),
				Name = entry.Name or ("hook " .. hookId(entry.Url):sub(-6)),
				Added = entry.Added or "-",
			})
		end
	end
end

local function thumbFor(asset)
	local id = tostring(asset or ""):match("%d+")
	if not id then return nil end
	return "https://www.roblox.com/asset-thumbnail/image?assetId=" .. id .. "&width=420&height=420&format=png"
end

local function sendRollHook(entry, chance)
	local hook = Hooks.Roll
	if not hook then return end

	local attributes = entry.attributes or {}
	local mutation = attributes.mutation

	local thumbnail = nil

	if mutation and G.Mutations and G.Mutations[mutation] then
		thumbnail = thumbFor(G.Mutations[mutation].image)
	end

	if not thumbnail then
		local current = currentDice()
		local all = G.DiceMod and G.DiceMod.GetAll() or {}
		if current and all[current] then thumbnail = thumbFor(all[current].image) end
	end

	local fields = {
		{ Name = "Chance", Value = "1 in " .. fmt(chance), Inline = true },
		{ Name = "Mutation", Value = tostring(mutation or "None"), Inline = true },
	}

	if attributes.grade then
		table.insert(fields, { Name = "Grade", Value = tostring(attributes.grade), Inline = true })
	end

	if attributes.trait then
		table.insert(fields, { Name = "Trait", Value = tostring(attributes.trait), Inline = true })
	end

	pcall(function()
		hook:Embed({
			Title = tostring(entry.name) .. " rolled",
			Fields = fields,
			Color = Color3.fromRGB(120, 200, 255),
			Footer = LocalPlayer.DisplayName,
			Thumbnail = thumbnail,
		})
	end)
end

local function rollHookWanted(entry, chance)
	if not F.rollHookOn or not Hooks.Roll then return false end

	local attributes = entry.attributes or {}

	if F.rollHookMutOnly and not attributes.mutation then return false end

	if #F.rollHookGrades > 0 and not setContains(F.rollHookGrades, attributes.grade) then return false end
	if #F.rollHookTraits > 0 and not setContains(F.rollHookTraits, attributes.trait) then return false end

	local minimum = tonumber(F.rollHookMin) or 0

	if minimum > 0 then return chance >= minimum end

	return #F.rollHookGrades > 0 or #F.rollHookTraits > 0 or F.rollHookMutOnly
end

local rollWatch = nil

local function watchRolls()
	pcall(function()
		rollWatch = G.DC.Inventory.OnKeyAdded(function(key)
			task.spawn(function()
				if not F.rollHookOn or not Hooks.Roll then return end

				local entry = invEntry(key)
				if not entry or not isUnitEntry(entry) then return end

				local cfg = entryConfig(entry.name)
				if not cfg then return end

				local chance = 0
				pcall(function() chance = cfg.chance(entry.attributes) or 0 end)

				if rollHookWanted(entry, chance) then sendRollHook(entry, chance) end
			end)
		end)
	end)
end

onCleanup(function()
	if rollWatch then pcall(function() rollWatch:Disconnect() end) end
end)

local STAT_FIELDS = { "Money", "Rolls", "Rebirth", "Gems", "Trait Reroll", "Sold", "Collected" }

local lastStatsHook = 0

local function sendStatsHook()
	local hook = Hooks.Stats
	if not hook then return end

	local selected = F.statHookFields

	local function want(name)
		if type(selected) ~= "table" or #selected == 0 then return true end
		return setContains(selected, name)
	end

	local fields = {}

	if want("Money") then table.insert(fields, { Name = "Money", Value = fmt(money()), Inline = true }) end
	if want("Rolls") then table.insert(fields, { Name = "Rolls", Value = tostring(rollCount()), Inline = true }) end
	if want("Rebirth") then table.insert(fields, { Name = "Rebirth", Value = tostring(rebirthCount()), Inline = true }) end
	if want("Gems") then table.insert(fields, { Name = "Gems", Value = fmt(currencyAmount("Gems")), Inline = true }) end
	if want("Trait Reroll") then table.insert(fields, { Name = "Trait Reroll", Value = fmt(currencyAmount("Trait Reroll")), Inline = true }) end
	if want("Sold") then table.insert(fields, { Name = "Sold", Value = tostring(Tally.sold), Inline = true }) end
	if want("Collected") then table.insert(fields, { Name = "Collected", Value = fmt(Tally.collected), Inline = true }) end

	pcall(function()
		hook:Embed({
			Title = "Session stats",
			Fields = fields,
			Color = Color3.fromRGB(90, 220, 130),
			Footer = LocalPlayer.DisplayName,
		})
	end)
end

local function statsHookTick()
	if os.clock() - lastStatsHook < (tonumber(F.statHookInterval) or 300) then return end
	lastStatsHook = os.clock()
	if F.statHookOn and Hooks.Stats then task.spawn(sendStatsHook) end
end

function sendTowerHook(name, fromFloor, toFloor, drops, bonus, result)
	local hook = Hooks.Tower
	if not hook then return end

	local parts = {}

	for item, amount in pairs(drops or {}) do
		table.insert(parts, tostring(amount) .. "x " .. tostring(item))
	end

	table.sort(parts)

	local bonusParts = {}

	for item, amount in pairs(bonus or {}) do
		table.insert(bonusParts, tostring(amount) .. "x " .. tostring(item))
	end

	table.sort(bonusParts)

	local fields = {
		{ Name = "Tower", Value = tostring(name), Inline = true },
		{ Name = "Result", Value = tostring(result), Inline = true },
		{ Name = "Floors", Value = tostring(fromFloor) .. " to " .. tostring(toFloor), Inline = true },
	}

	if #parts > 0 then
		table.insert(fields, { Name = "Drops", Value = table.concat(parts, ", "), Inline = false })
	end

	if #bonusParts > 0 then
		table.insert(fields, { Name = "Clear bonus", Value = table.concat(bonusParts, ", "), Inline = false })
	end

	pcall(function()
		hook:Embed({
			Title = "Tower " .. tostring(result):lower(),
			Fields = fields,
			Color = result == "Cleared" and Color3.fromRGB(255, 200, 70) or Color3.fromRGB(150, 150, 160),
			Footer = LocalPlayer.DisplayName,
		})
	end)
end

function sendTradeHook(partner, own, other, result)
	local hook = Hooks.Trade
	if not hook then return end

	pcall(function()
		hook:Embed({
			Title = "Trade " .. tostring(result):lower(),
			Fields = {
				{ Name = "Partner", Value = tostring(partner), Inline = true },
				{ Name = "Result", Value = tostring(result), Inline = true },
				{ Name = "You gave", Value = offerText(own), Inline = false },
				{ Name = "You got", Value = offerText(other), Inline = false },
			},
			Color = Color3.fromRGB(140, 160, 255),
			Footer = LocalPlayer.DisplayName,
		})
	end)
end

loadHooks()
watchRolls()

local function armReexec()
	if not F.reexec then return end

	local queue = queue_on_teleport or queueonteleport

	if type(queue) ~= "function" then
		notify("Auto Execute", "This executor has no queue_on_teleport.", "error", 6)
		return
	end

	pcall(queue, 'loadstring(game:HttpGet("' .. LOADER_URL .. '"))()')
end

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

local Window = Library:Window({
	Title             = "Facility",
	Suffix            = ".Sexility",
	Width             = 760,
	Height            = 600,
	MinWidth          = 620,
	SectionTitleStyle = "border",
	MobileButton      = true,
})

local FIELD_METHODS = { "Input", "Textbox", "TextBox", "Field", "Text", "Entry" }

local function buildField(box, options)
	for _, name in ipairs(FIELD_METHODS) do
		local ok, method = pcall(function() return box[name] end)

		if ok and type(method) == "function" then
			local fine, element = pcall(method, box, options)
			if fine and type(element) == "table" then return element, name end
		end
	end

	return nil
end

local MainTab     = Window:Tab("Main", "home")
local UnitsTab    = Window:Tab("Units", "users")
local InvTab      = Window:Tab("Inventory", "package")
local UpgradeTab  = Window:Tab("Upgrades", "trending-up")
local DiceTab     = Window:Tab("Dice", "dices")
local SellTab     = Window:Tab("Sell", "coins")
local TowerTab    = Window:Tab("Tower", "castle")
local PotionTab   = Window:Tab("Potion", "flask-conical")
local RerollTab   = Window:Tab("Reroll", "refresh-cw")
local TradeTab    = Window:Tab("Trade", "repeat")
local MovementTab = Window:Tab("Movement", "move")
local MiscTab     = Window:Tab("Misc", "wrench")
local HookTab     = Window:Tab("Webhooks", "send")
local Settings    = Window:Tab("Settings", "cog")

local GRADE_NAMES, TRAIT_NAMES, MUTATION_NAMES = {}, {}, {}

for _, entry in ipairs(orderedNames(G.GradesMod)) do table.insert(GRADE_NAMES, entry.name) end
for _, entry in ipairs(orderedNames(G.TraitsMod)) do table.insert(TRAIT_NAMES, entry.name) end
MUTATION_NAMES = mutationNames()

if #GRADE_NAMES == 0 then GRADE_NAMES = { "(unavailable)" } end
if #TRAIT_NAMES == 0 then TRAIT_NAMES = { "(unavailable)" } end
if #MUTATION_NAMES == 0 then MUTATION_NAMES = { "(unavailable)" } end

local function selectionSet(selected)
	local out = {}

	if type(selected) == "table" then
		for _, name in ipairs(selected) do table.insert(out, tostring(name)) end
	end

	return out
end

local statusBox = MainTab:Section("Status", 1)

local statusLabel = statusBox:Label("Idle")
local walletLabel = statusBox:Label("-", { Style = "dim" })
local currencyLabel = statusBox:Label("-", { Style = "dim" })
local frameworkLabel = statusBox:Label("-", { Style = "dim" })

if not G.ok then
	frameworkLabel:Set("framework not loaded, most features are off")
	notify("Facility", "The game framework did not load, reload in a fresh server.", "error", 10)
elseif #G.missing > 0 then
	frameworkLabel:Set("missing modules: " .. table.concat(G.missing, ", "))
else
	frameworkLabel:Set("framework loaded")
end

local collectBox = MainTab:Section("Money", 2)

collectBox:Toggle({
	Text = "Auto Collect",
	Flag = "ad_collect",
	Default = false,
	Callback = function(state) F.collect = state end,
})

collectBox:Slider({
	Text = "Collect Delay",
	Flag = "ad_collect_delay",
	Min = 0.5, Max = 30, Default = 2,
	Decimals = 1,
	Suffix = " s",
	Callback = function(value) F.collectDelay = tonumber(value) or 2 end,
})

collectBox:Slider({
	Text = "Only Above",
	Flag = "ad_collect_min",
	Min = 0, Max = 1000000, Default = 0,
	Suffix = " money",
	Callback = function(value) F.collectMin = tonumber(value) or 0 end,
})
	:Gear(function(panel)
		panel:Label("Skips slots holding less than this, fewer remote calls.", { Style = "dim" })
	end)

collectBox:Button({
	Text = "Collect Now",
	Callback = function() task.spawn(function() pcall(doCollect) end) end,
})

local rebirthBox = MainTab:Section("Rebirth", 1)

rebirthBox:Toggle({
	Text = "Auto Rebirth",
	Flag = "ad_rebirth",
	Default = false,
	Callback = function(state) F.rebirth = state end,
})

rebirthBox:Slider({
	Text = "Check Delay",
	Flag = "ad_rebirth_delay",
	Min = 1, Max = 60, Default = 5,
	Decimals = 1,
	Suffix = " s",
	Callback = function(value) F.rebirthDelay = tonumber(value) or 5 end,
})

rebirthBox:Button({
	Text = "Rebirth Now",
	Callback = function() task.spawn(function() pcall(doRebirth) end) end,
})

local rollBox = MainTab:Section("Roll", 2)

rollBox:Toggle({
	Text = "Auto Roll",
	Flag = "ad_auto_roll",
	Default = false,
	Callback = function(state)
		F.autoRoll = state
		local signal = getSig("RollService", "SetAutoRoll")
		if signal then pcall(function() signal:Fire(state) end) end
	end,
})

rollBox:Toggle({
	Text = "Hide Roll Animation",
	Flag = "ad_hide_rolls",
	Default = false,
	Callback = function(state)
		F.hideRolls = state
		task.spawn(function()
			syncRollHidden()
			rollHideBackup(state)
		end)
	end,
})

local questBox = MainTab:Section("Quests And Codes", 1)

questBox:Toggle({
	Text = "Auto Claim Quests",
	Flag = "ad_quests",
	Default = false,
	Callback = function(state) F.claimQuests = state end,
})

questBox:Toggle({
	Text = "Auto Redeem Codes",
	Flag = "ad_codes",
	Default = false,
	Callback = function(state) F.codesAuto = state end,
})

questBox:Slider({
	Text = "Retry Every",
	Flag = "ad_codes_delay",
	Min = 60, Max = 3600, Default = 300,
	Suffix = " s",
	Callback = function(value) F.codesDelay = tonumber(value) or 300 end,
})

questBox:Button({
	Text = "Redeem All Codes Now",
	Callback = function() task.spawn(function() pcall(doRedeemCodes, true) end) end,
})

questBox:Button({
	Text = "Claim Quests Now",
	Callback = function() task.spawn(function() pcall(doClaimQuests) end) end,
})

local logBox = MainTab:Section("Log", "full")

local logTable = logBox:Table({
	Columns = { "Time", "Event" },
	MaxRows = 12,
	EmptyText = "Nothing logged yet",
})

logBox:Button({
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

logBox:Button({
	Text = "Clear Log",
	Callback = function()
		table.clear(logLines)
		logDirty = true
	end,
})

local levelBox = UnitsTab:Section("Level Up", 1)

levelBox:Toggle({
	Text = "Auto Level Up",
	Flag = "ad_levelup",
	Default = false,
	Callback = function(state) F.levelup = state end,
})

levelBox:Slider({
	Text = "Max Level",
	Flag = "ad_max_level",
	Min = 1, Max = 99, Default = 40,
	Callback = function(value) F.maxLevel = math.floor(tonumber(value) or 40) end,
})

levelBox:Toggle({
	Text = "Smart Level Cap",
	Flag = "ad_smart_level",
	Default = false,
	Callback = function(state)
		F.smartLevel = state
		if state then task.spawn(function() applySmartLevel(true) end) end
	end,
})
	:Gear(function(panel)
		panel:Label("Moves the cap so levelling stays under 10 percent of your money.", { Style = "dim" })
	end)

levelBox:Slider({
	Text = "Level Delay",
	Flag = "ad_level_delay",
	Min = 0.5, Max = 30, Default = 2.5,
	Decimals = 1,
	Suffix = " s",
	Callback = function(value) F.levelDelay = tonumber(value) or 2.5 end,
})

local placeBox = UnitsTab:Section("Place Best", 2)

placeBox:Toggle({
	Text = "Auto Place Best",
	Flag = "ad_place",
	Default = false,
	Callback = function(state) F.placeBest = state end,
})

placeBox:Toggle({
	Text = "Replace Worst When Full",
	Flag = "ad_replace_worst",
	Default = true,
	Callback = function(state) F.replaceWorst = state end,
})

placeBox:Slider({
	Text = "Place Delay",
	Flag = "ad_place_delay",
	Min = 1, Max = 60, Default = 5,
	Decimals = 1,
	Suffix = " s",
	Callback = function(value) F.placeDelay = tonumber(value) or 5 end,
})

placeBox:Button({
	Text = "Game EquipBest (one shot)",
	Callback = function()
		local signal = getSig("PlotService", "EquipBest")

		if not signal then
			notify("Units", "EquipBest remote missing.", "error", 5)
			return
		end

		pcall(function() signal:Fire() end)
		notify("Units", "EquipBest fired.", "success", 3)
	end,
})

local slotBox = UnitsTab:Section("Slots", "full")

local slotTable = slotBox:Table({
	Columns = { "Slot", "Unit", "Lvl", "Chance", "Pending", "State" },
	MaxRows = 14,
	EmptyText = "No slot data yet",
})

local SLOT_CHOICES = {}
for index = 1, 14 do table.insert(SLOT_CHOICES, tostring(index)) end

slotBox:Dropdown({
	Text = "Locked Slots",
	Flag = "ad_locked_slots",
	Options = SLOT_CHOICES,
	Default = {},
	Multi = true,
	Empty = "None locked",
	Callback = function(selected) F.lockedSlots = selectionSet(selected) end,
})
	:Gear(function(panel)
		panel:Label("Auto place and auto level up never touch a locked slot.", { Style = "dim" })
	end)

local invBox = InvTab:Section("Owned Units", "full")

local invCount = invBox:Label("-", { Style = "bright" })

local invTable = invBox:Table({
	Columns = { "Unit", "Chance", "Grade", "Trait", "Mutation", "Lvl", "Where" },
	MaxRows = 16,
	EmptyText = "Inventory not read yet",
})

local invControls = InvTab:Section("View", 1)

invControls:Dropdown({
	Text = "Sort By",
	Flag = "ad_inv_sort",
	Options = { "Chance", "Grade", "Trait", "Level", "Name" },
	Default = "Chance",
	Callback = function(value) F.invSort = tostring(value) end,
})

invControls:Toggle({
	Text = "Placed Only",
	Flag = "ad_inv_placed",
	Default = false,
	Callback = function(state) F.invPlacedOnly = state end,
})

local protectBox = InvTab:Section("Protect From Selling", 2)

local protectCount = protectBox:Label("-", { Style = "dim" })

protectBox:Button({
	Text = "Protect Top Unit",
	Callback = function()
		local best, bestChance = nil, 0

		for key, entry in pairs(inventory()) do
			if isUnitEntry(entry) then
				local chance = unitChance(entry)
				if chance > bestChance and not protectedKeys[key] then best, bestChance = key, chance end
			end
		end

		if not best then
			notify("Inventory", "Nothing left to protect.", "warning", 4)
			return
		end

		protectedKeys[best] = true
		saveProtected()

		local entry = invEntry(best) or {}
		notify("Inventory", "Protected " .. tostring(entry.name) .. " [1 in " .. fmt(bestChance) .. "].", "success", 4)
	end,
})

protectBox:Button({
	Text = "Protect All Placed",
	Callback = function()
		local added = 0

		for key in pairs(placedUnitKeys()) do
			if not protectedKeys[key] then
				protectedKeys[key] = true
				added = added + 1
			end
		end

		saveProtected()
		notify("Inventory", added .. " placed units protected.", "success", 4)
	end,
})

protectBox:Button({
	Text = "Clear Protected",
	Callback = function()
		table.clear(protectedKeys)
		saveProtected()
		notify("Inventory", "Protection list cleared.", "success", 3)
	end,
})

local upgradeBox = UpgradeTab:Section("Skill Tree", 1)

upgradeBox:Toggle({
	Text = "Auto Upgrades",
	Flag = "ad_upgrades",
	Default = false,
	Callback = function(state) F.upgrades = state end,
})

upgradeBox:Slider({
	Text = "Upgrade Delay",
	Flag = "ad_upgrade_delay",
	Min = 0.5, Max = 30, Default = 2,
	Decimals = 1,
	Suffix = " s",
	Callback = function(value) F.upgradeDelay = tonumber(value) or 2 end,
})

upgradeBox:Dropdown({
	Text = "Category Filter",
	Flag = "ad_upgrade_cats",
	Options = UPGRADE_CATEGORIES,
	Default = {},
	Multi = true,
	Empty = "Every category",
	Callback = function(selected) F.upgradeCats = selectionSet(selected) end,
})

upgradeBox:Dropdown({
	Text = "Priority Order",
	Flag = "ad_upgrade_order",
	Options = UPGRADE_CATEGORIES,
	Default = {},
	Multi = true,
	Empty = "Cheapest first",
	Callback = function(selected) F.upgradeOrder = selectionSet(selected) end,
})
	:Gear(function(panel)
		panel:Label("Picked categories are bought before the rest, in the order you select them.", { Style = "dim" })
	end)

upgradeBox:Slider({
	Text = "Money Reserve",
	Flag = "ad_upgrade_reserve",
	Min = 0, Max = 1000000000, Default = 0,
	Suffix = " kept",
	Callback = function(value) F.upgradeReserve = tonumber(value) or 0 end,
})

local diceBox = DiceTab:Section("Dice Shop", 1)

diceBox:Toggle({
	Text = "Auto Buy Best Dice",
	Flag = "ad_buy_dice",
	Default = false,
	Callback = function(state) F.buyDice = state end,
})

diceBox:Toggle({
	Text = "Auto Equip Best Dice",
	Flag = "ad_equip_dice",
	Default = true,
	Callback = function(state) F.equipDice = state end,
})

diceBox:Slider({
	Text = "Check Delay",
	Flag = "ad_dice_delay",
	Min = 1, Max = 60, Default = 5,
	Decimals = 1,
	Suffix = " s",
	Callback = function(value) F.diceDelay = tonumber(value) or 5 end,
})

local diceListBox = DiceTab:Section("All Dice", "full")

local diceTable = diceListBox:Table({
	Columns = { "Dice", "Luck", "Price", "Owned" },
	MaxRows = 14,
	EmptyText = "Dice module not loaded",
})

local sellBox = SellTab:Section("Filter", 1)

sellBox:Dropdown({
	Text = "Sell What",
	Flag = "ad_sell_mode",
	Options = { "Chance", "Grade", "Trait", "Mutation", "Any Match", "Keep Listed" },
	Default = "Chance",
	Callback = function(value) F.sellMode = tostring(value) end,
})
	:Gear(function(panel)
		panel:Label("Chance uses the threshold. Grade, Trait and Mutation use their list. Any Match sells on any hit. Keep Listed sells everything except the listed grades, traits and mutations.", { Style = "dim" })
	end)

sellBox:Dropdown({
	Text = "Grades",
	Flag = "ad_sell_grades",
	Options = GRADE_NAMES,
	Default = {},
	Multi = true,
	Empty = "None",
	Callback = function(selected) F.sellGrades = selectionSet(selected) end,
})

sellBox:Dropdown({
	Text = "Traits",
	Flag = "ad_sell_traits",
	Options = TRAIT_NAMES,
	Default = {},
	Multi = true,
	Empty = "None",
	Callback = function(selected) F.sellTraits = selectionSet(selected) end,
})

sellBox:Dropdown({
	Text = "Mutations",
	Flag = "ad_sell_mutations",
	Options = MUTATION_NAMES,
	Default = {},
	Multi = true,
	Empty = "None",
	Callback = function(selected) F.sellMutations = selectionSet(selected) end,
})

local thresholdBox = SellTab:Section("Threshold", 2)

local thresholdLabel = thresholdBox:Label("threshold off", { Style = "bright" })

local function applyThreshold(value)
	F.sellThreshold = math.max(0, value or 0)
	sellInputText = F.sellThreshold > 0 and fmt(F.sellThreshold) or ""

	if F.sellSync then
		local signal = getSig("SellService", "UpdateAutoSell")
		if signal then pcall(function() signal:Fire(F.sellThreshold) end) end
	end
end

local thresholdField = buildField(thresholdBox, {
	Text = "Keep Above 1 In",
	Placeholder = "e.g. 1t",
	Default = "",
	Finished = true,
	ClearOnFocus = false,
	Callback = function(text)
		local parsed = parseCompact(text)

		if parsed == nil then
			notify("Sell", "Not understood, try 1t or 500b.", "error", 5)
			return
		end

		applyThreshold(parsed)
	end,
})

if not thresholdField then
	thresholdBox:Slider({
		Text = "Keep Above 1 In",
		Flag = "ad_sell_threshold",
		Min = 0, Max = 1000, Default = 0,
		Decimals = 1,
		Suffix = " x1e9",
		Callback = function(value) applyThreshold((tonumber(value) or 0) * 1e9) end,
	})
end

thresholdBox:Toggle({
	Text = "Smart Threshold",
	Flag = "ad_smart_sell",
	Default = false,
	Callback = function(state)
		F.smartSell = state
		if state then task.spawn(function() applySmartSell(true) end) end
	end,
})
	:Gear(function(panel)
		panel:Label("Recomputes the threshold from your luck and your best owned unit.", { Style = "dim" })
	end)

thresholdBox:Toggle({
	Text = "Apply To Game Auto Sell",
	Flag = "ad_sell_sync",
	Default = false,
	Callback = function(state)
		F.sellSync = state
		local signal = getSig("SellService", "UpdateAutoSell")
		if signal then pcall(function() signal:Fire(state and F.sellThreshold or 0) end) end
	end,
})

local sellRunBox = SellTab:Section("Run", 1)

sellRunBox:Toggle({
	Text = "Auto Sell",
	Flag = "ad_sell_auto",
	Default = false,
	Callback = function(state) F.sellAuto = state end,
})

sellRunBox:Slider({
	Text = "Sell Delay",
	Flag = "ad_sell_delay",
	Min = 2, Max = 120, Default = 10,
	Suffix = " s",
	Callback = function(value) F.sellDelay = tonumber(value) or 10 end,
})

sellRunBox:Slider({
	Text = "Keep Top N",
	Flag = "ad_keep_best",
	Min = 0, Max = 50, Default = 0,
	Callback = function(value) F.keepBest = math.floor(tonumber(value) or 0) end,
})

sellRunBox:Button({
	Text = "Sell Now",
	Callback = function() task.spawn(function() pcall(doSell, true) end) end,
})

local towerBox = TowerTab:Section("Run", 1)

towerDropdown = towerBox:Dropdown({
	Text = "Tower",
	Flag = "ad_tower_name",
	Options = towerNames(),
	Default = "Dragon Tower",
	Callback = function(value) F.towerName = tostring(value) end,
})

towerBox:Toggle({
	Text = "Auto Tower",
	Flag = "ad_tower",
	Default = false,
	Callback = function(state) F.tower = state end,
})

towerBox:Toggle({
	Text = "Equip Best Team First",
	Flag = "ad_tower_equip",
	Default = true,
	Callback = function(state) F.towerEquipBest = state end,
})

towerBox:Toggle({
	Text = "Smart Tower",
	Flag = "ad_smart_tower",
	Default = false,
	Callback = function(state) F.smartTower = state end,
})
	:Gear(function(panel)
		panel:Label("Simulates every tower against your team with upgrade and potion buffs, then picks the best.", { Style = "dim" })
	end)

towerBox:Button({
	Text = "Check Best Tower Now",
	Callback = function() task.spawn(function() pcall(runSmartTower) end) end,
})

towerBox:Button({
	Text = "Refresh Tower List",
	Callback = function()
		pcall(function() towerDropdown:SetOptions(towerNames()) end)
		notify("Tower", "List refreshed.", "success", 3)
	end,
})

local exitBox = TowerTab:Section("Exit", 2)

exitBox:Toggle({
	Text = "Exit At Floor",
	Flag = "ad_tower_exit",
	Default = false,
	Callback = function(state) F.towerExitOn = state end,
})

exitBox:Slider({
	Text = "Floor",
	Flag = "ad_tower_exit_floor",
	Min = 0, Max = 200, Default = 0,
	Callback = function(value) F.towerExitFloor = math.floor(tonumber(value) or 0) end,
})

exitBox:Button({
	Text = "Stop Tower",
	Callback = function()
		F.tower = false
		pcall(function()
			local cancel = getFn("Towers", "CancelTower")
			if cancel then cancel() end
		end)
		notify("Tower", "Stopped and cancelled.", "success", 3)
	end,
})

local towerStatBox = TowerTab:Section("Stats", "full")

local towerStatTable = towerStatBox:Table({
	Columns = { "Metric", "Value" },
	MaxRows = 8,
	EmptyText = "No tower run yet",
})

towerStatBox:Button({
	Text = "Reset Tower Stats",
	Callback = function()
		Tally.towerWins = {}
		Tally.towerFloors = 0
		Tally.towerGems = 0
		Tally.towerTraits = 0
		Tally.towerRewards = {}
		notify("Tower", "Stats reset.", "success", 3)
	end,
})

local function potionChoices()
	local names = {}

	if G.BoostConfig and G.BoostConfig.entries then
		for name, def in pairs(G.BoostConfig.entries) do
			if type(def) == "table" then table.insert(names, name) end
		end
	end

	table.sort(names)

	if #names == 0 then table.insert(names, "(unavailable)") end

	return names
end

local potionBox = PotionTab:Section("Auto Potion", 1)

local potionDropdown = potionBox:Dropdown({
	Text = "Potions",
	Flag = "ad_potions",
	Options = potionChoices(),
	Default = {},
	Multi = true,
	Empty = "None selected",
	Callback = function(selected) F.potions = selectionSet(selected) end,
})

potionBox:Toggle({
	Text = "Auto Potion",
	Flag = "ad_potion_auto",
	Default = false,
	Callback = function(state) F.potionAuto = state end,
})

potionBox:Toggle({
	Text = "Best Per Category",
	Flag = "ad_potion_best",
	Default = true,
	Callback = function(state) F.potionBest = state end,
})

potionBox:Toggle({
	Text = "Extend While Active",
	Flag = "ad_potion_extend",
	Default = false,
	Callback = function(state) F.potionExtend = state end,
})

potionBox:Slider({
	Text = "Check Delay",
	Flag = "ad_potion_delay",
	Min = 1, Max = 120, Default = 5,
	Decimals = 1,
	Suffix = " s",
	Callback = function(value) F.potionDelay = tonumber(value) or 5 end,
})

potionBox:Button({
	Text = "Refresh Potion List",
	Callback = function()
		pcall(function() potionDropdown:SetOptions(potionChoices()) end)
		notify("Potion", "List refreshed.", "success", 3)
	end,
})

local buffBox = PotionTab:Section("Active Buffs", "full")

local buffTable = buffBox:Table({
	Columns = { "Buff", "Category", "Tier", "Left" },
	MaxRows = 12,
	EmptyText = "No buff active",
})

local gradeBox = RerollTab:Section("Auto Grade", 1)

gradeBox:Toggle({
	Text = "Auto Grade",
	Flag = "ad_grade_auto",
	Default = false,
	Callback = function(state) F.gradeAuto = state end,
})

gradeBox:Dropdown({
	Text = "Target Grades",
	Flag = "ad_grade_targets",
	Options = GRADE_NAMES,
	Default = {},
	Multi = true,
	Empty = "None selected",
	Callback = function(selected) F.gradeTargets = selectionSet(selected) end,
})

gradeBox:Toggle({
	Text = "All Units",
	Flag = "ad_grade_all",
	Default = false,
	Callback = function(state)
		F.gradeAll = state
		if state then F.gradePlacedOnly = false end
	end,
})

gradeBox:Toggle({
	Text = "Placed Units Only",
	Flag = "ad_grade_placed",
	Default = false,
	Callback = function(state)
		F.gradePlacedOnly = state
		if state then F.gradeAll = false end
	end,
})

gradeBox:Slider({
	Text = "Grade Delay",
	Flag = "ad_grade_delay",
	Min = 0.5, Max = 30, Default = 2,
	Decimals = 1,
	Suffix = " s",
	Callback = function(value) F.gradeDelay = tonumber(value) or 2 end,
})

gradeBox:Slider({
	Text = "Gems Reserve",
	Flag = "ad_gem_reserve",
	Min = 0, Max = 100000, Default = 0,
	Callback = function(value) F.gemReserve = math.floor(tonumber(value) or 0) end,
})

gradeBox:Button({
	Text = "Grade Once",
	Callback = function() task.spawn(function() pcall(rerollTick, "grade", true) end) end,
})

local traitBox = RerollTab:Section("Auto Trait", 2)

traitBox:Toggle({
	Text = "Auto Trait",
	Flag = "ad_trait_auto",
	Default = false,
	Callback = function(state) F.traitAuto = state end,
})

traitBox:Dropdown({
	Text = "Target Traits",
	Flag = "ad_trait_targets",
	Options = TRAIT_NAMES,
	Default = {},
	Multi = true,
	Empty = "None selected",
	Callback = function(selected) F.traitTargets = selectionSet(selected) end,
})

traitBox:Toggle({
	Text = "All Units",
	Flag = "ad_trait_all",
	Default = false,
	Callback = function(state)
		F.traitAll = state
		if state then F.traitPlacedOnly = false end
	end,
})

traitBox:Toggle({
	Text = "Placed Units Only",
	Flag = "ad_trait_placed",
	Default = false,
	Callback = function(state)
		F.traitPlacedOnly = state
		if state then F.traitAll = false end
	end,
})

traitBox:Slider({
	Text = "Trait Delay",
	Flag = "ad_trait_delay",
	Min = 0.5, Max = 30, Default = 2,
	Decimals = 1,
	Suffix = " s",
	Callback = function(value) F.traitDelay = tonumber(value) or 2 end,
})

traitBox:Slider({
	Text = "Trait Reroll Reserve",
	Flag = "ad_reroll_reserve",
	Min = 0, Max = 100000, Default = 0,
	Callback = function(value) F.rerollReserve = math.floor(tonumber(value) or 0) end,
})

traitBox:Button({
	Text = "Trait Once",
	Callback = function() task.spawn(function() pcall(rerollTick, "trait", true) end) end,
})

local rerollInfo = RerollTab:Section("Currency", "full")

local rerollLabel = rerollInfo:Label("-", { Style = "bright" })

rerollInfo:Label("A protected grade or trait is only rerolled when one of your targets ranks above it.", { Style = "dim" })

local tradeBox = TradeTab:Section("Auto Trade", 1)

tradeBox:Toggle({
	Text = "Auto Trade",
	Flag = "ad_trade_auto",
	Default = false,
	Callback = function(state) F.tradeAuto = state end,
})

local tradeMoneyField = buildField(tradeBox, {
	Text = "Min Partner Money",
	Placeholder = "e.g. 1b",
	Default = "",
	Finished = true,
	ClearOnFocus = false,
	Callback = function(text)
		local parsed = parseCompact(text)

		if parsed == nil then
			notify("Trade", "Not understood, try 1b or 500m.", "error", 5)
			return
		end

		F.tradeMoney = math.max(0, parsed)
	end,
})

if not tradeMoneyField then
	tradeBox:Slider({
		Text = "Min Partner Money",
		Flag = "ad_trade_money",
		Min = 0, Max = 1000, Default = 0,
		Decimals = 1,
		Suffix = " x1e9",
		Callback = function(value) F.tradeMoney = (tonumber(value) or 0) * 1e9 end,
	})
end

tradeBox:Slider({
	Text = "Retries Per Player",
	Flag = "ad_trade_retries",
	Min = 1, Max = 10, Default = 3,
	Callback = function(value) F.tradeRetries = math.floor(tonumber(value) or 3) end,
})

tradeBox:Toggle({
	Text = "Hop When Nobody Matches",
	Flag = "ad_trade_hop",
	Default = true,
	Callback = function(state) F.tradeHop = state end,
})

tradeBox:Slider({
	Text = "Hop Delay",
	Flag = "ad_trade_hop_delay",
	Min = 1, Max = 30, Default = 8,
	Suffix = " s",
	Callback = function(value) F.tradeHopDelay = tonumber(value) or 8 end,
})

local tradeDriveBox = TradeTab:Section("Drive", 2)

tradeDriveBox:Toggle({
	Text = "Auto Ready And Accept",
	Flag = "ad_trade_go",
	Default = true,
	Callback = function(state) F.tradeAutoGo = state end,
})

tradeDriveBox:Toggle({
	Text = "Require Partner Offer",
	Flag = "ad_trade_need_offer",
	Default = true,
	Callback = function(state) F.tradeNeedOffer = state end,
})

tradeDriveBox:Slider({
	Text = "Min Partner Items",
	Flag = "ad_trade_min_items",
	Min = 1, Max = 20, Default = 1,
	Callback = function(value) F.tradeMinItems = math.floor(tonumber(value) or 1) end,
})

tradeDriveBox:Button({
	Text = "Stop And Cancel Trade",
	Callback = function()
		stopTrades()
		notify("Trade", "Stopped.", "success", 3)
	end,
})

local tradeStatBox = TradeTab:Section("Session", "full")

local tradeStatLabel = tradeStatBox:Label("-", { Style = "bright" })

if Movement then

Movement.Settings.WalkSpeedMode = "Velocity"
Movement.Settings.JumpMode = "Humanoid"

local flyBox = MovementTab:Section("Fly", 1)

flyBox:Toggle({
	Text = "Fly",
	Flag = "ad_fly",
	Default = false,
	Callback = function(state) Movement:Fly(state) end,
})
	:Keybind({ Default = "F", Flag = "ad_fly_key" })

flyBox:Slider({
	Text = "Speed",
	Flag = "ad_fly_speed",
	Min = 1, Max = 20, Default = 2,
	Decimals = 1,
	Callback = function(value) Movement.Settings.FlySpeed = value end,
})

local speedBox = MovementTab:Section("Speed", 2)

speedBox:Toggle({
	Text = "Walk Speed",
	Flag = "ad_walkspeed",
	Default = false,
	Callback = function(state)
		Movement:WalkSpeed(state and Movement.Settings.WalkSpeed or 16)
	end,
})

speedBox:Slider({
	Text = "Value",
	Flag = "ad_walkspeed_value",
	Min = 16, Max = 300, Default = 16,
	Callback = function(value)
		Movement.Settings.WalkSpeed = value
		if Library.Flags["ad_walkspeed"] then Movement:WalkSpeed(value) end
	end,
})

local otherBox = MovementTab:Section("Other", 1)

otherBox:Toggle({
	Text = "Noclip",
	Flag = "ad_noclip",
	Default = false,
	Callback = function(state) Movement:Noclip(state) end,
})
	:Keybind({ Default = "N", Flag = "ad_noclip_key" })

otherBox:Toggle({
	Text = "Infinite Jump",
	Flag = "ad_infinite_jump",
	Default = false,
	Callback = function(state) Movement:InfiniteJump(state) end,
})

otherBox:Toggle({
	Text = "Float",
	Flag = "ad_float",
	Default = false,
	Callback = function(state) Movement:Float(state) end,
})
	:Gear(function(panel)
		panel:Slider({
			Text = "Height",
			Flag = "ad_float_height",
			Min = 1, Max = 10, Default = 3.1,
			Decimals = 1,
			Callback = function(value) Movement.Settings.FloatHeight = value end,
		})
	end)

end

local serverBox = MiscTab:Section("Server", 1)

serverBox:Button({
	Text = "Hop To High Population",
	Callback = function() doHop(false) end,
})

serverBox:Button({
	Text = "Hop To Low Population",
	Callback = function() doHop(true) end,
})

serverBox:Button({
	Text = "Rejoin Server",
	Callback = function()
		pcall(function()
			TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
		end)
	end,
})

serverBox:Button({
	Text = "Clear Visited List",
	Callback = function()
		writeJson(userFile("visited"), {})
		notify("Server Hop", "Visited list cleared.", "success", 3)
	end,
})
	:Gear(function(panel)
		panel:Label("Hopping remembers the servers you came from for 45 minutes so you do not loop.", { Style = "dim" })
	end)

local browserBox = MiscTab:Section("Browser", 2)

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

local perfBox = MiscTab:Section("Performance", 1)

perfBox:Toggle({
	Text = "FPS Boost",
	Flag = "ad_fps",
	Default = false,
	Callback = function(state)
		F.fpsOn = state
		task.spawn(function() pcall(setFpsBoost, state) end)
	end,
})
	:Gear(function(panel)
		panel:Label("Hides other bases, leaderboards and statues, kills particles and shadows. Reversible.", { Style = "dim" })
	end)

perfBox:Toggle({
	Text = "Anti AFK",
	Flag = "ad_afk",
	Default = true,
	Callback = function(state) F.afk = state end,
})

perfBox:Toggle({
	Text = "Re-run On Teleport",
	Flag = "ad_reexec",
	Default = false,
	Callback = function(state)
		F.reexec = state
		if state then armReexec() end
	end,
})
	:Gear(function(panel)
		panel:Label("Queues the Facility loader so the hub comes back after a hop.", { Style = "dim" })
	end)

local statsPanel = Library:Panel({
	Title = "anime dice",
	Icon = "activity",
	Width = 190,
	Position = UDim2.fromOffset(18, 320),
	Visible = false,
})

statsPanel:SetVisible(false)

statsPanel.Content:Label("money", { Style = "dim" })
local panelMoney = statsPanel.Content:Label("-", { Style = "bright" })

statsPanel.Content:Divider()

statsPanel.Content:Label("rolls", { Style = "dim" })
local panelRolls = statsPanel.Content:Label("-", { Style = "bright" })

statsPanel.Content:Divider()

statsPanel.Content:Label("sold", { Style = "dim" })
local panelSold = statsPanel.Content:Label("-", { Style = "bright" })

statsPanel.Content:Divider()

statsPanel.Content:Label("tower floor", { Style = "dim" })
local panelFloor = statsPanel.Content:Label("-", { Style = "bright" })

statsPanel.Content:Divider()

statsPanel.Content:Label("status", { Style = "dim" })
local panelStatus = statsPanel.Content:Label("Idle")

local panelBox = MiscTab:Section("Panel", 2)

local panelShown = false

panelBox:Toggle({
	Text = "Show Stats Panel",
	Flag = "ad_panel",
	Default = false,
	Callback = function(state)
		panelShown = state
		statsPanel:SetVisible(state)
	end,
})
	:Keybind({ Default = "RightControl", Flag = "ad_panel_key" })

onCleanup(function()
	pcall(function() statsPanel:SetVisible(false) end)
end)

local manageBox = HookTab:Section("Manage", 1)

hookStatus = manageBox:Label("no webhook saved", { Style = "bright" })

local promptForUrl

local urlField = buildField(manageBox, {
	Text = "Webhook URL",
	Placeholder = "https://discord.com/api/webhooks/...",
	Default = "",
	Finished = true,
	ClearOnFocus = false,
	Callback = function(value) addHook(value, true) end,
})

if urlField then
	manageBox:Label("Paste the url above and press enter, then assign it below.", { Style = "dim" })
else
	manageBox:Button({
		Text = "Add Webhook",
		Callback = function() promptForUrl() end,
	})
end

manageBox:Button({
	Text = "Remove Last",
	Callback = function()
		if #Hooks.List == 0 then
			notify("Webhooks", "Nothing saved.", "warning", 4)
			return
		end

		table.remove(Hooks.List)
		saveHooks()

		for _, kind in ipairs(HOOK_KINDS) do
			if Hooks.Picks[kind] > #Hooks.List then
				Hooks.Picks[kind] = 0
				Hooks[kind] = nil
			end
		end

		refreshHooks()
		notify("Webhooks", "Last webhook removed.", "success", 3)
	end,
})

manageBox:Button({
	Text = "Clear All",
	Callback = function()
		table.clear(Hooks.List)

		for _, kind in ipairs(HOOK_KINDS) do
			Hooks.Picks[kind] = 0
			Hooks[kind] = nil
		end

		if type(delfile) == "function" then pcall(delfile, HOOK_FILE) end

		refreshHooks()
		notify("Webhooks", "All webhooks cleared.", "success", 3)
	end,
})

local assignBox = HookTab:Section("Assign", 2)

hookDropdowns.Roll = assignBox:Dropdown({
	Text = "Roll Alerts",
	Flag = "ad_hook_roll",
	Options = hookChoices(),
	Default = "None",
	Callback = function(value)
		local index = tonumber(tostring(value or ""):match("^(%d+)%."))
		assignHook("Roll", index or 0)
	end,
})

hookDropdowns.Stats = assignBox:Dropdown({
	Text = "Stat Reports",
	Flag = "ad_hook_stats",
	Options = hookChoices(),
	Default = "None",
	Callback = function(value)
		local index = tonumber(tostring(value or ""):match("^(%d+)%."))
		assignHook("Stats", index or 0)
	end,
})

hookDropdowns.Tower = assignBox:Dropdown({
	Text = "Tower Clears",
	Flag = "ad_hook_tower",
	Options = hookChoices(),
	Default = "None",
	Callback = function(value)
		local index = tonumber(tostring(value or ""):match("^(%d+)%."))
		assignHook("Tower", index or 0)
	end,
})

hookDropdowns.Trade = assignBox:Dropdown({
	Text = "Trade Results",
	Flag = "ad_hook_trade",
	Options = hookChoices(),
	Default = "None",
	Callback = function(value)
		local index = tonumber(tostring(value or ""):match("^(%d+)%."))
		assignHook("Trade", index or 0)
	end,
})

assignBox:Button({
	Text = "Test Assigned Hooks",
	Callback = function()
		local sent = 0

		for _, kind in ipairs(HOOK_KINDS) do
			local hook = Hooks[kind]

			if hook then
				sent = sent + 1
				pcall(function()
					hook:Embed({
						Title = "Facility connected",
						Description = "Anime Dice  ·  " .. kind .. " channel",
						Color = Color3.fromRGB(90, 200, 255),
					})
				end)
			end
		end

		if sent == 0 then
			notify("Webhooks", "No webhook assigned yet.", "warning", 5)
		else
			notify("Webhooks", sent .. " test embeds sent.", "success", 4)
		end
	end,
})

local rollHookBox = HookTab:Section("Roll Filter", 1)

rollHookBox:Toggle({
	Text = "Roll Alerts",
	Flag = "ad_roll_hook",
	Default = false,
	Callback = function(state) F.rollHookOn = state end,
})

local rollMinField = buildField(rollHookBox, {
	Text = "Min Chance 1 In",
	Placeholder = "e.g. 1t",
	Default = "",
	Finished = true,
	ClearOnFocus = false,
	Callback = function(text)
		local parsed = parseCompact(text)

		if parsed == nil then
			notify("Webhooks", "Not understood, try 1t.", "error", 5)
			return
		end

		F.rollHookMin = math.max(0, parsed)
	end,
})

if not rollMinField then
	rollHookBox:Slider({
		Text = "Min Chance 1 In",
		Flag = "ad_roll_hook_min",
		Min = 0, Max = 1000, Default = 0,
		Decimals = 1,
		Suffix = " x1e9",
		Callback = function(value) F.rollHookMin = (tonumber(value) or 0) * 1e9 end,
	})
end

rollHookBox:Dropdown({
	Text = "Only These Grades",
	Flag = "ad_roll_hook_grades",
	Options = GRADE_NAMES,
	Default = {},
	Multi = true,
	Empty = "Any grade",
	Callback = function(selected) F.rollHookGrades = selectionSet(selected) end,
})

rollHookBox:Dropdown({
	Text = "Only These Traits",
	Flag = "ad_roll_hook_traits",
	Options = TRAIT_NAMES,
	Default = {},
	Multi = true,
	Empty = "Any trait",
	Callback = function(selected) F.rollHookTraits = selectionSet(selected) end,
})

rollHookBox:Toggle({
	Text = "Mutated Only",
	Flag = "ad_roll_hook_mut",
	Default = false,
	Callback = function(state) F.rollHookMutOnly = state end,
})
	:Gear(function(panel)
		panel:Label("With no filter set, nothing is sent. Set a minimum chance, a grade, a trait or mutated only.", { Style = "dim" })
	end)

local statHookBox = HookTab:Section("Reports", 2)

statHookBox:Toggle({
	Text = "Stat Reports",
	Flag = "ad_stat_hook",
	Default = false,
	Callback = function(state) F.statHookOn = state end,
})

statHookBox:Slider({
	Text = "Every",
	Flag = "ad_stat_hook_interval",
	Min = 60, Max = 3600, Default = 300,
	Suffix = " s",
	Callback = function(value) F.statHookInterval = tonumber(value) or 300 end,
})

statHookBox:Dropdown({
	Text = "Fields",
	Flag = "ad_stat_hook_fields",
	Options = STAT_FIELDS,
	Default = {},
	Multi = true,
	Empty = "Every field",
	Callback = function(selected) F.statHookFields = selectionSet(selected) end,
})

statHookBox:Toggle({
	Text = "Tower Alerts",
	Flag = "ad_tower_hook",
	Default = false,
	Callback = function(state) F.towerHookOn = state end,
})

statHookBox:Toggle({
	Text = "Trade Alerts",
	Flag = "ad_trade_hook",
	Default = false,
	Callback = function(state) F.tradeHookOn = state end,
})

statHookBox:Button({
	Text = "Send Stats Now",
	Callback = function()
		if not Hooks.Stats then
			notify("Webhooks", "Assign a webhook to Stat Reports first.", "warning", 5)
			return
		end

		task.spawn(sendStatsHook)
		notify("Webhooks", "Report sent.", "success", 3)
	end,
})

local HOOK_GUI = "FacilityWebhookPrompt"

local function hookGuiParent()
	if type(gethui) == "function" then
		local ok, host = pcall(gethui)
		if ok and host then return host end
	end

	local ok, core = pcall(function() return game:GetService("CoreGui") end)
	if ok and core then return core end

	return LocalPlayer:WaitForChild("PlayerGui")
end

function promptForUrl()
	local parent = hookGuiParent()

	local existing = parent:FindFirstChild(HOOK_GUI)
	if existing then pcall(function() existing:Destroy() end) end

	local gui = Instance.new("ScreenGui")
	gui.Name = HOOK_GUI
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 2147483647
	gui.Parent = parent

	local shade = Instance.new("Frame")
	shade.Size = UDim2.fromScale(1, 1)
	shade.BackgroundColor3 = Color3.new(0, 0, 0)
	shade.BackgroundTransparency = 0.45
	shade.BorderSizePixel = 0
	shade.Parent = gui

	local card = Instance.new("Frame")
	card.Size = UDim2.fromOffset(460, 168)
	card.Position = UDim2.new(0.5, -230, 0.5, -84)
	card.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
	card.BorderSizePixel = 0
	card.Parent = gui

	local cardCorner = Instance.new("UICorner")
	cardCorner.CornerRadius = UDim.new(0, 8)
	cardCorner.Parent = card

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(58, 58, 66)
	stroke.Thickness = 1
	stroke.Parent = card

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -32, 0, 24)
	title.Position = UDim2.fromOffset(16, 14)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamMedium
	title.TextSize = 15
	title.TextColor3 = Color3.fromRGB(236, 236, 242)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "Paste your Discord webhook"
	title.Parent = card

	local hint = Instance.new("TextLabel")
	hint.Size = UDim2.new(1, -32, 0, 18)
	hint.Position = UDim2.fromOffset(16, 36)
	hint.BackgroundTransparency = 1
	hint.Font = Enum.Font.Gotham
	hint.TextSize = 12
	hint.TextColor3 = Color3.fromRGB(140, 142, 152)
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.Text = "https://discord.com/api/webhooks/..."
	hint.Parent = card

	local field = Instance.new("TextBox")
	field.Size = UDim2.new(1, -32, 0, 38)
	field.Position = UDim2.fromOffset(16, 62)
	field.BackgroundColor3 = Color3.fromRGB(12, 12, 15)
	field.BorderSizePixel = 0
	field.Font = Enum.Font.Code
	field.TextSize = 13
	field.TextColor3 = Color3.fromRGB(226, 226, 234)
	field.PlaceholderText = "paste here"
	field.PlaceholderColor3 = Color3.fromRGB(96, 98, 108)
	field.ClearTextOnFocus = false
	field.TextXAlignment = Enum.TextXAlignment.Left
	field.TextTruncate = Enum.TextTruncate.AtEnd
	field.Text = ""
	field.Parent = card

	local fieldCorner = Instance.new("UICorner")
	fieldCorner.CornerRadius = UDim.new(0, 5)
	fieldCorner.Parent = field

	local fieldPad = Instance.new("UIPadding")
	fieldPad.PaddingLeft = UDim.new(0, 10)
	fieldPad.PaddingRight = UDim.new(0, 10)
	fieldPad.Parent = field

	local function button(text, offset, accent)
		local element = Instance.new("TextButton")
		element.Size = UDim2.fromOffset(104, 32)
		element.Position = UDim2.new(1, offset, 1, -48)
		element.BackgroundColor3 = accent and Color3.fromRGB(44, 110, 70) or Color3.fromRGB(38, 38, 44)
		element.BorderSizePixel = 0
		element.AutoButtonColor = true
		element.Font = Enum.Font.GothamMedium
		element.TextSize = 13
		element.TextColor3 = accent and Color3.fromRGB(214, 255, 228) or Color3.fromRGB(214, 214, 222)
		element.Text = text
		element.Parent = card

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 5)
		corner.Parent = element

		return element
	end

	local cancel = button("Cancel", -232, false)
	local confirm = button("Save", -120, true)

	local function close()
		pcall(function() gui:Destroy() end)
	end

	local function submit()
		local value = field.Text

		if validUrl(value) then
			close()
			addHook(value)
		else
			field.Text = ""
			field.PlaceholderText = "not a webhook url, try again"
			hint.TextColor3 = Color3.fromRGB(255, 120, 120)
		end
	end

	cancel.MouseButton1Click:Connect(close)
	confirm.MouseButton1Click:Connect(submit)

	field.FocusLost:Connect(function(enterPressed)
		if enterPressed then submit() end
	end)

	shade.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then close() end
	end)

	task.defer(function()
		pcall(function() field:CaptureFocus() end)
	end)
end

onCleanup(function()
	local ok, parent = pcall(hookGuiParent)
	if not ok or not parent then return end

	local existing = parent:FindFirstChild(HOOK_GUI)
	if existing then pcall(function() existing:Destroy() end) end
end)

refreshHooks()

local function startLoop(delayFn, body)
	task.spawn(function()
		while Alive do
			task.wait(math.max(0.1, tonumber(delayFn()) or 1))
			if Alive then pcall(body) end
		end
	end)
end

startLoop(function() return F.collectDelay end, function()
	if F.collect then doCollect() end
end)

startLoop(function() return F.levelDelay end, function()
	if F.levelup then doLevelUp() end
end)

startLoop(function() return F.placeDelay end, function()
	if F.placeBest then doPlaceBest() end
end)

startLoop(function() return F.upgradeDelay end, function()
	if F.upgrades then doUpgrades() end
end)

startLoop(function() return F.rebirthDelay end, function()
	if F.rebirth then doRebirth() end
end)

startLoop(function() return F.diceDelay end, function()
	if F.buyDice or F.equipDice then doDice() end
end)

startLoop(function() return F.potionDelay end, function()
	if F.potionAuto then doPotion() end
end)

startLoop(function() return F.gradeDelay end, function()
	if F.gradeAuto then rerollTick("grade") end
end)

startLoop(function() return F.traitDelay end, function()
	if F.traitAuto then rerollTick("trait") end
end)

startLoop(function() return F.sellDelay end, function()
	if F.sellAuto then doSell(false) end
end)

startLoop(function() return 3 end, function()
	if F.hideRolls then
		syncRollHidden()
		rollHideBackup(true)
	end
end)

task.spawn(function()
	task.wait(8)
	if F.codesAuto and Alive then pcall(doRedeemCodes) end

	while Alive do
		task.wait(math.max(60, tonumber(F.codesDelay) or 300))
		if F.codesAuto then pcall(doRedeemCodes) end
	end
end)

task.spawn(function()
	local lastSync = 0

	while Alive do
		task.wait(30)

		if F.claimQuests then pcall(doClaimQuests) end
		if F.smartSell then pcall(applySmartSell) end
		if F.smartLevel then pcall(applySmartLevel) end

		pcall(statsHookTick)

		if F.sellSync and F.sellThreshold > 0 and os.clock() - lastSync > 120 then
			lastSync = os.clock()
			local signal = getSig("SellService", "UpdateAutoSell")
			if signal then pcall(function() signal:Fire(F.sellThreshold) end) end
		end
	end
end)

task.spawn(function()
	local running = false

	while Alive do
		task.wait(0.5)

		if F.tower and not running then
			running = true
			task.spawn(doTowerLoop)
		elseif not F.tower then
			running = false
		end
	end
end)

task.spawn(function()
	local running = false

	while Alive do
		task.wait(0.5)

		if F.tradeAuto and not running then
			running = true
			task.spawn(doTradeLoop)
		elseif not F.tradeAuto then
			running = false
		end
	end
end)

task.spawn(function()
	while Alive do
		task.wait(0.5)

		if F.tradeAutoGo and not tradeDriving and tradeScreenOpen() then
			task.spawn(driveTrade)
		end
	end
end)

local function sortedInventory()
	local rows = {}
	local placed = placedUnitKeys()
	local tower = towerTeamKeys()
	local equipped = equippedKey()

	for key, entry in pairs(inventory()) do
		if isUnitEntry(entry) then
			if not F.invPlacedOnly or placed[key] then
				local attributes = entry.attributes or {}

				local where = "bag"
				if placed[key] then where = "slot"
				elseif tower[key] then where = "tower"
				elseif key == equipped then where = "held" end

				if protectedKeys[key] then where = where .. "+" end

				table.insert(rows, {
					key = key,
					name = tostring(entry.name),
					chance = unitChance(entry),
					grade = attributes.grade,
					trait = attributes.trait,
					mutation = attributes.mutation,
					level = tonumber(attributes.level) or 1,
					where = where,
				})
			end
		end
	end

	local mode = F.invSort

	table.sort(rows, function(a, b)
		if mode == "Grade" then
			local ga, gb = gradeRank(a.grade), gradeRank(b.grade)
			if ga ~= gb then return ga > gb end
		elseif mode == "Trait" then
			local ta, tb = traitRank(a.trait), traitRank(b.trait)
			if ta ~= tb then return ta > tb end
		elseif mode == "Level" then
			if a.level ~= b.level then return a.level > b.level end
		elseif mode == "Name" then
			if a.name ~= b.name then return a.name < b.name end
		end

		if a.chance ~= b.chance then return a.chance > b.chance end

		return a.name < b.name
	end)

	return rows
end

task.spawn(function()
	local shown = {}

	while Alive do
		task.wait(1)

		pcall(function()
			if Status ~= shown.status then
				shown.status = Status
				statusLabel:Set(Status)
			end

			local wallet = string.format("Money %s  ·  Rolls %s  ·  Rebirth %s",
				fmt(money()), fmt(rollCount()), tostring(rebirthCount()))

			if wallet ~= shown.wallet then
				shown.wallet = wallet
				walletLabel:Set(wallet)
			end

			local currency = string.format("Collected %s  ·  Sold %d  ·  Levelled %d  ·  Upgrades %d",
				fmt(Tally.collected), Tally.sold, Tally.leveled, Tally.upgraded)

			if currency ~= shown.currency then
				shown.currency = currency
				currencyLabel:Set(currency)
			end

			local reroll = string.format("Gems %s  ·  Trait Reroll %s",
				fmt(currencyAmount("Gems")), fmt(currencyAmount("Trait Reroll")))

			if reroll ~= shown.reroll then
				shown.reroll = reroll
				rerollLabel:Set(reroll)
			end

			local threshold = F.sellThreshold > 0
				and ("keep 1 in " .. fmt(F.sellThreshold) .. " and above")
				or "threshold off"

			if threshold ~= shown.threshold then
				shown.threshold = threshold
				thresholdLabel:Set(threshold)
			end

			local protectedTotal = 0
			for _ in pairs(protectedKeys) do protectedTotal = protectedTotal + 1 end

			local protectedText = protectedTotal .. " unit" .. (protectedTotal == 1 and "" or "s") .. " protected"

			if protectedText ~= shown.protected then
				shown.protected = protectedText
				protectCount:Set(protectedText)
			end

			local tradeText = string.format("Requests %d  ·  Opened %d  ·  %s",
				Tally.tradesSent, Tally.tradesOpened,
				tradeScreenOpen() and ("in trade with " .. tostring(tradePartner or "?")) or "idle")

			if tradeText ~= shown.trade then
				shown.trade = tradeText
				tradeStatLabel:Set(tradeText)
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

				logTable:SetRows(rows)
			end)
		end

		if panelShown then
			pcall(function()
				panelMoney:Set(fmt(money()))
				panelRolls:Set(fmt(rollCount()))
				panelSold:Set(tostring(Tally.sold))
				panelFloor:Set(tostring(towerFloor))
				panelStatus:Set(Status)
			end)
		end
	end
end)

task.spawn(function()
	while Alive do
		task.wait(2)

		pcall(function()
			local list, data = unlockedSlots()
			local rows = {}

			for _, slot in ipairs(list) do
				local entry = data[tostring(slot)]
				local unit, level, chance, pending = "-", "-", "-", "-"

				if entry then
					pending = fmt(tonumber(entry.balance) or 0)

					if entry.unitId then
						local item = invEntry(entry.unitId)

						if item then
							unit = tostring(item.name)
							level = tostring((item.attributes and item.attributes.level) or 1)
							chance = "1 in " .. fmt(unitChance(item))
						end
					end
				end

				table.insert(rows, {
					tostring(slot),
					unit,
					level,
					chance,
					pending,
					slotLocked(slot) and "locked" or "open",
					Style = slotLocked(slot) and "warning" or (unit == "-" and "dim" or nil),
				})
			end

			slotTable:SetRows(rows)
		end)

		pcall(function()
			local rows = sortedInventory()
			local shown = {}

			for index = 1, math.min(16, #rows) do
				local row = rows[index]

				table.insert(shown, {
					row.name,
					row.chance > 0 and ("1 in " .. fmt(row.chance)) or "-",
					tostring(row.grade or "-"),
					tostring(row.trait or "-"),
					tostring(row.mutation or "-"),
					tostring(row.level),
					row.where,
					Style = row.mutation and "warning" or (row.where ~= "bag" and "bright" or nil),
				})
			end

			invTable:SetRows(shown)
			invCount:Set(#rows .. " unit" .. (#rows == 1 and "" or "s") .. " owned")
		end)

		pcall(function()
			local rows = {}

			if G.DiceMod then
				local all = G.DiceMod.GetAll()
				local owned = ownedDice()
				local current = currentDice()
				local list = {}

				for name, def in pairs(all) do
					table.insert(list, { name = name, luck = tonumber(def.luck) or 0, price = def.price })
				end

				table.sort(list, function(a, b) return a.luck > b.luck end)

				for _, def in ipairs(list) do
					local state = "no"
					if def.name == current then state = "equipped"
					elseif owned[def.name] then state = "yes" end

					table.insert(rows, {
						def.name,
						fmt(def.luck),
						def.price and fmt(def.price) or "-",
						state,
						Style = def.name == current and "warning" or (owned[def.name] and "bright" or "dim"),
					})
				end
			end

			diceTable:SetRows(rows)
		end)

		pcall(function()
			local rows = {}
			local active = activePotions()
			local entries = G.BoostConfig and G.BoostConfig.entries or {}

			for name, left in pairs(active) do
				local def = entries[name]

				table.insert(rows, {
					name,
					tostring(def and def.category or "-"),
					tostring(def and def.tier or "-"),
					durationText(left),
				})
			end

			table.sort(rows, function(a, b) return a[1] < b[1] end)

			local luck = effectiveLuck()
			table.insert(rows, 1, { "effective luck", "-", "-", fmt(luck), Style = "bright" })

			buffTable:SetRows(rows)
		end)

		pcall(function()
			local rows = {
				{ "Current floor", tostring(towerFloor) },
				{ "Floors cleared", tostring(Tally.towerFloors) },
				{ "Wins on " .. tostring(F.towerName), tostring(Tally.towerWins[F.towerName] or 0) },
				{ "Gems earned", fmt(Tally.towerGems) },
				{ "Trait rerolls earned", fmt(Tally.towerTraits) },
			}

			local extras = {}

			for name, amount in pairs(Tally.towerRewards) do
				if name ~= "Gems" and name ~= "Trait Reroll" then
					table.insert(extras, tostring(name) .. " x" .. fmt(amount))
				end
			end

			table.sort(extras)

			if #extras > 0 then
				table.insert(rows, { "Other drops", table.concat(extras, ", ") })
			end

			towerStatTable:SetRows(rows)
		end)
	end
end)

task.spawn(function()
	while Alive do
		task.wait(1)

		local parts = {}

		if Busy.tower then table.insert(parts, "Tower f" .. tostring(towerFloor)) end
		if Busy.trade then table.insert(parts, "Trading") end
		if Busy.place then table.insert(parts, "Placing") end
		if Busy.grade then table.insert(parts, "Grading") end
		if Busy.trait then table.insert(parts, "Trait rolling") end
		if Busy.potion then table.insert(parts, "Potions") end

		if #parts == 0 then
			local active = {}

			if F.collect then table.insert(active, "collect") end
			if F.levelup then table.insert(active, "level") end
			if F.placeBest then table.insert(active, "place") end
			if F.upgrades then table.insert(active, "upgrade") end
			if F.rebirth then table.insert(active, "rebirth") end
			if F.autoRoll then table.insert(active, "roll") end
			if F.sellAuto then table.insert(active, "sell") end

			Status = #active > 0 and ("Running: " .. table.concat(active, ", ")) or "Idle"
		else
			Status = table.concat(parts, "  ·  ")
		end
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
SaveManager:SetFolder("Facility/113290951185459")

InterfaceManager:BuildInterfaceSection(Settings, 1)
SaveManager:BuildConfigSection(Settings, 2)
ThemeManager:Mount(Window)

Window:SetTab(MainTab)

Library:Notify("Facility", "Loaded.", 4)

SaveManager:LoadAutoloadConfig()
ThemeManager:Load()

clog("Facility loaded for Anime Dice.")

if not G.ok then
	clog("The game framework is missing, automation will not run.")
elseif #G.missing > 0 then
	clog("Modules not loaded: " .. table.concat(G.missing, ", "))
end

task.spawn(function()
	task.wait(2)
	if F.reexec then armReexec() end
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
