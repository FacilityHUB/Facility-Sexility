--!nocheck
--!nolint UnknownGlobal

local HttpService = game:GetService("HttpService")
local Players     = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer

local request = request
	or http_request
	or (syn and syn.request)
	or (http and http.request)
	or (fluxus and fluxus.request)

local Webhook = {}
Webhook.__index = Webhook

Webhook.Available = request ~= nil

Webhook.Colors = {
	Default = 0x2B2D31,
	Blurple = 0x5865F2,
	Green   = 0x57F287,
	Yellow  = 0xFEE75C,
	Red     = 0xED4245,
	Orange  = 0xE67E22,
	Pink    = 0xEB459E,
	White   = 0xFFFFFF,
}

local MIN_INTERVAL = 0.6
local MAX_QUEUE    = 40
local MAX_RETRIES  = 3

local function colorOf(value)
	if type(value) == "number" then return value end
	if typeof(value) == "Color3" then
		return math.floor(value.R * 255) * 65536
			+ math.floor(value.G * 255) * 256
			+ math.floor(value.B * 255)
	end
	return Webhook.Colors.Default
end

local function trim(text, limit)
	text = tostring(text or "")
	if #text <= limit then return text end
	return string.sub(text, 1, limit - 1) .. "…"
end

local function isoNow()
	return DateTime.now():ToIsoDate()
end

function Webhook.new(url, options)
	options = options or {}

	local self = setmetatable({}, Webhook)
	self.Url      = url
	self.Username = options.Username or "Facility"
	self.Avatar   = options.Avatar
	self.Enabled  = options.Enabled ~= false

	self._queue   = {}
	self._running = false
	self._lastSend = 0

	return self
end

function Webhook:SetUrl(url)
	self.Url = url
	return self
end

function Webhook:SetEnabled(state)
	self.Enabled = state and true or false
	return self
end

function Webhook:_push(payload)
	if not self.Enabled or not self.Url or self.Url == "" then return false end

	if not Webhook.Available then
		warn("Facility Webhook: this executor has no request function")
		return false
	end

	if #self._queue >= MAX_QUEUE then
		table.remove(self._queue, 1)
	end

	table.insert(self._queue, payload)
	self:_drain()
	return true
end

function Webhook:_drain()
	if self._running then return end
	self._running = true

	task.spawn(function()
		while #self._queue > 0 do
			local payload = table.remove(self._queue, 1)

			local wait = MIN_INTERVAL - (tick() - self._lastSend)
			if wait > 0 then task.wait(wait) end

			local attempt = 0
			repeat
				attempt = attempt + 1

				local ok, response = pcall(request, {
					Url = self.Url,
					Method = "POST",
					Headers = { ["Content-Type"] = "application/json" },
					Body = HttpService:JSONEncode(payload),
				})

				self._lastSend = tick()

				local status = ok and response and (response.StatusCode or response.Status_Code)
				local retry = false

				if not ok then
					warn("Facility Webhook: " .. tostring(response))

				elseif status == 429 then
					local delay = 2
					pcall(function()
						local body = HttpService:JSONDecode(response.Body)
						if body and body.retry_after then
							delay = tonumber(body.retry_after) or 2
							if delay > 100 then delay = delay / 1000 end
						end
					end)
					task.wait(delay + 0.1)
					retry = true

				elseif status and status >= 500 then
					task.wait(1)
					retry = true

				elseif status and status >= 400 then
					local detail = ""
					pcall(function()
						if response and response.Body then
							detail = " " .. tostring(response.Body):sub(1, 300)
						end
					end)
					warn("Facility Webhook: rejected with status "
						.. tostring(status) .. detail)
				end
			until not retry or attempt >= MAX_RETRIES
		end

		self._running = false
	end)
end

function Webhook:Send(content, options)
	options = options or {}
	local text = trim(content, 1900)
	if text == "" then return false end

	local payload = {
		content = text,
		username = options.Username or self.Username,
	}

	local avatar = options.Avatar or self.Avatar
	if type(avatar) == "string" and avatar:match("^https?://") then
		payload.avatar_url = avatar
	end

	return self:_push(payload)
end

function Webhook:Embed(data)
	data = data or {}

	local embed = {
		title = data.Title and trim(data.Title, 250) or nil,
		description = data.Description and trim(data.Description, 4000) or nil,
		color = colorOf(data.Color),
		url = data.Url,
	}

	if data.Fields then
		embed.fields = {}
		for index, field in ipairs(data.Fields) do
			if index > 25 then break end

			local name = trim(field.Name or field[1], 250)
			local value = trim(field.Value or field[2], 1000)
			if name == "" then name = "-" end
			if value == "" then value = "-" end

			table.insert(embed.fields, {
				name = name,
				value = value,
				inline = field.Inline ~= false,
			})
		end
	end

	if data.Author then
		embed.author = {
			name = trim(data.Author.Name or data.Author, 250),
			icon_url = type(data.Author) == "table" and data.Author.Icon or nil,
		}
	end

	if data.Footer then
		embed.footer = { text = trim(data.Footer, 2000) }
	end

	local function httpUrl(url)
		return type(url) == "string" and url:match("^https?://") ~= nil
	end

	if httpUrl(data.Thumbnail) then embed.thumbnail = { url = data.Thumbnail } end
	if httpUrl(data.Image) then embed.image = { url = data.Image } end
	if not httpUrl(embed.url) then embed.url = nil end
	if data.Timestamp ~= false then embed.timestamp = isoNow() end

	if embed.title == "" then embed.title = nil end
	if embed.description == "" then embed.description = nil end

	local payload = {
		username = data.Username or self.Username,
		embeds = { embed },
	}

	if type(data.Content) == "string" and data.Content ~= "" then
		payload.content = trim(data.Content, 1900)
	end

	local avatar = data.Avatar or self.Avatar
	if httpUrl(avatar) then payload.avatar_url = avatar end

	return self:_push(payload)
end

local function shorthand(name, color)
	Webhook[name] = function(self, title, description, extra)
		extra = extra or {}
		extra.Title = title
		extra.Description = description
		extra.Color = extra.Color or color
		return self:Embed(extra)
	end
end

shorthand("Info",    Webhook.Colors.Blurple)
shorthand("Success", Webhook.Colors.Green)
shorthand("Warn",    Webhook.Colors.Yellow)
shorthand("Error",   Webhook.Colors.Red)

local function getHwid()
	local id

	pcall(function()
		if gethwid then id = gethwid() end
	end)

	if type(id) ~= "string" or id == "" then
		pcall(function()
			id = game:GetService("RbxAnalyticsService"):GetClientId()
		end)
	end

	if type(id) ~= "string" or id == "" then
		pcall(function()
			if getexecutorname then id = getexecutorname() end
		end)
	end

	return id ~= nil and tostring(id) or "unknown"
end

Webhook.GetHwid = getHwid

function Webhook:Player(options)
	options = options or {}

	local player = options.Player or LocalPlayer
	local now = DateTime.now():FormatUniversalTime("YYYY-MM-DD HH:mm:ss", "en-us")

	local fields = {
		{ Name = "Player", Value = ("%s (@%s)"):format(player.DisplayName, player.Name), Inline = true },
		{ Name = "Hardware ID", Value = getHwid(), Inline = true },
		{ Name = "Place ID", Value = tostring(game.PlaceId), Inline = true },
		{ Name = "Time (UTC)", Value = now, Inline = true },
	}

	for _, field in ipairs(options.Fields or {}) do
		table.insert(fields, field)
	end

	return self:Embed({
		Title = options.Title or "Script executed",
		Color = options.Color or Webhook.Colors.Blurple,
		Fields = fields,
		Timestamp = false,
	})
end

function Webhook:Stats(title, stats, options)
	options = options or {}

	local fields = {}
	local keys = {}
	for key in pairs(stats) do table.insert(keys, key) end
	table.sort(keys)

	for _, key in ipairs(keys) do
		table.insert(fields, {
			Name = tostring(key),
			Value = tostring(stats[key]),
			Inline = options.Inline ~= false,
		})
	end

	return self:Embed({
		Title = title,
		Description = options.Description,
		Color = options.Color or Webhook.Colors.Default,
		Fields = fields,
		Footer = options.Footer or "Facility",
	})
end

function Webhook:Session(title)
	local session = {
		Title = title or "Session",
		Started = tick(),
		Counters = {},
	}

	function session:Count(key, amount)
		self.Counters[key] = (self.Counters[key] or 0) + (amount or 1)
		return self
	end

	function session:Set(key, value)
		self.Counters[key] = value
		return self
	end

	local hook = self
	function session:Report(options)
		local elapsed = math.floor(tick() - self.Started)
		local stats = {}
		for key, value in pairs(self.Counters) do stats[key] = value end

		stats["Duration"] = ("%02d:%02d:%02d"):format(
			math.floor(elapsed / 3600),
			math.floor(elapsed % 3600 / 60),
			elapsed % 60)

		return hook:Stats(self.Title, stats, options)
	end

	return session
end

return Webhook
