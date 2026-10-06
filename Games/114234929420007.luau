--!nocheck
--!nolint UnknownGlobal
--[[
	Facility — 114234929420007
	Pure PvP: ESP + Aimbot + Movement
]]

local F       = shared.Facility
local Library = F.Library
local Entity  = F.Entity
local Esp     = F.Esp

local Aimbot   = F.Load("CModules/FAimbot.luau",   "aimbot")
local Movement = F.Load("CModules/FMovement.luau",  "movement")

Movement:Load()
Aimbot:Load(Entity)

-- ================================================================
-- Window
-- ================================================================

local Window = Library:Window({
	Title             = "Facility",
	Suffix            = ".pvp",
	Width             = 640,
	Height            = 560,
	SectionTitleStyle = "border",
})

local Visuals  = Window:Tab("Visuals",  "eye")
local Combat   = Window:Tab("Combat",   "crosshair")
local Move     = Window:Tab("Movement", "person")
local Settings = Window:Tab("Settings", "cog")

-- ================================================================
-- VISUALS — ESP
-- ================================================================

local espSection = Visuals:Section("ESP", 1)

espSection:Toggle({
	Text    = "Enable",
	Flag    = "esp_enable",
	Default = false,
	Callback = function(state)
		if state then
			pcall(function() Esp:Load(Entity) end)
		else
			pcall(function() Esp:Unload() end)
		end
	end,
}):Keybind({ Default = "RightAlt", Flag = "esp_key" })

espSection:Toggle({
	Text    = "Enemies",
	Flag    = "esp_enemy",
	Default = true,
	Callback = function(state) Esp.teamSettings.enemy.enabled = state end,
}):ColorPicker({
	Flag    = "esp_enemy_color",
	Default = Color3.fromRGB(255, 60, 60),
	Callback = function(color)
		Esp.teamSettings.enemy.boxColor  = { color, 1 }
		Esp.teamSettings.enemy.nameColor = { color, 1 }
	end,
}):Gear(function(panel)
	panel:Toggle({
		Text     = "Box",
		Flag     = "esp_enemy_box",
		Default  = true,
		Callback = function(state) Esp.teamSettings.enemy.box = state end,
	})
	panel:Toggle({
		Text     = "Name",
		Flag     = "esp_enemy_name",
		Default  = true,
		Callback = function(state) Esp.teamSettings.enemy.name = state end,
	})
	panel:Toggle({
		Text     = "Health Bar",
		Flag     = "esp_enemy_health",
		Default  = true,
		Callback = function(state) Esp.teamSettings.enemy.healthBar = state end,
	})
	panel:Toggle({
		Text     = "Distance",
		Flag     = "esp_enemy_distance",
		Default  = true,
		Callback = function(state) Esp.teamSettings.enemy.distance = state end,
	})
	panel:Toggle({
		Text     = "Tracer",
		Flag     = "esp_enemy_tracer",
		Default  = false,
		Callback = function(state) Esp.teamSettings.enemy.tracer = state end,
	})
	panel:Toggle({
		Text     = "Chams",
		Flag     = "esp_enemy_chams",
		Default  = false,
		Callback = function(state) Esp.teamSettings.enemy.chams = state end,
	})
	panel:Slider({
		Text     = "Max Distance",
		Flag     = "esp_enemy_maxdist",
		Min      = 100, Max = 3000, Default = 1500,
		Suffix   = " studs",
		Callback = function(value) Esp.teamSettings.enemy.maxDistance = value end,
	})
end)

espSection:Toggle({
	Text     = "Teammates",
	Flag     = "esp_friendly",
	Default  = false,
	Callback = function(state) Esp.teamSettings.friendly.enabled = state end,
}):ColorPicker({
	Flag    = "esp_friendly_color",
	Default = Color3.fromRGB(60, 180, 255),
	Callback = function(color)
		Esp.teamSettings.friendly.boxColor  = { color, 1 }
		Esp.teamSettings.friendly.nameColor = { color, 1 }
	end,
})

-- ================================================================
-- COMBAT — Aimbot
-- ================================================================

local aimSection = Combat:Section("Aimbot", 1)

aimSection:Toggle({
	Text     = "Enable",
	Flag     = "aim_enable",
	Default  = false,
	Callback = function(state)
		Aimbot.Enabled = state
		if not state then Aimbot.Active = false end
	end,
}):Keybind({
	Default  = "MouseButton2",
	Flag     = "aim_key",
	Callback = function(key) Aimbot:SetKey(key) end,
})

aimSection:Slider({
	Text     = "FOV",
	Flag     = "aim_fov",
	Min      = 10, Max = 500, Default = 120,
	Callback = function(value) Aimbot:SetFov(value) end,
})

aimSection:Slider({
	Text     = "Smoothness",
	Flag     = "aim_smooth",
	Min      = 1, Max = 100, Default = 25,
	Callback = function(value)
		Aimbot.Settings.Smoothness = value / 100
	end,
})

aimSection:Toggle({
	Text     = "Show FOV Circle",
	Flag     = "aim_fov_visible",
	Default  = true,
	Callback = function(state) Aimbot.Settings.FovVisible = state end,
})

aimSection:Toggle({
	Text     = "Team Check",
	Flag     = "aim_teamcheck",
	Default  = true,
	Callback = function(state) Aimbot.Settings.TeamCheck = state end,
})

aimSection:Toggle({
	Text     = "Wall Check",
	Flag     = "aim_wallcheck",
	Default  = false,
	Callback = function(state) Aimbot.Settings.WallCheck = state end,
})

aimSection:Toggle({
	Text     = "Prediction",
	Flag     = "aim_prediction",
	Default  = false,
	Callback = function(state) Aimbot.Settings.Prediction = state end,
}):Gear(function(panel)
	panel:Slider({
		Text     = "Prediction Time",
		Flag     = "aim_pred_time",
		Min      = 1, Max = 50, Default = 12,
		Suffix   = " ms",
		Callback = function(value)
			Aimbot.Settings.PredictionTime = value / 100
		end,
	})
	panel:Toggle({
		Text     = "Ping Compensation",
		Flag     = "aim_pred_ping",
		Default  = false,
		Callback = function(state) Aimbot.Settings.PingPrediction = state end,
	})
end)

aimSection:Dropdown({
	Text    = "Priority",
	Flag    = "aim_priority",
	Default = "Cursor",
	Options = { "Cursor", "Closest", "LowestHealth" },
	Callback = function(value) Aimbot.Settings.Priority = value end,
})

aimSection:Dropdown({
	Text    = "Target Part",
	Flag    = "aim_part",
	Default = "Head",
	Options = { "Head", "HumanoidRootPart", "UpperTorso", "Torso" },
	Callback = function(value) Aimbot.Settings.Parts = { value } end,
})

aimSection:Slider({
	Text     = "Hit Chance",
	Flag     = "aim_hitchance",
	Min      = 1, Max = 100, Default = 100,
	Suffix   = "%",
	Callback = function(value) Aimbot.Settings.HitChance = value end,
})

local triggerSection = Combat:Section("Triggerbot", 2)

triggerSection:Toggle({
	Text     = "Enable",
	Flag     = "trigger_enable",
	Default  = false,
	Callback = function(state) Aimbot.Settings.TriggerBot = state end,
})

triggerSection:Slider({
	Text     = "Delay",
	Flag     = "trigger_delay",
	Min      = 0, Max = 500, Default = 80,
	Suffix   = " ms",
	Callback = function(value)
		Aimbot.Settings.TriggerDelay = value / 1000
	end,
})

-- ================================================================
-- MOVEMENT
-- ================================================================

local flySection = Move:Section("Fly", 1)

flySection:Toggle({
	Text     = "Fly",
	Flag     = "move_fly",
	Default  = false,
	Callback = function(state) Movement:Fly(state) end,
}):Keybind({ Default = "V", Flag = "move_fly_key" })

flySection:Slider({
	Text     = "Speed",
	Flag     = "move_fly_speed",
	Min      = 1, Max = 200, Default = 2,
	Callback = function(value) Movement:SetFlySpeed(value) end,
})

local charSection = Move:Section("Character", 2)

charSection:Toggle({
	Text     = "Noclip",
	Flag     = "move_noclip",
	Default  = false,
	Callback = function(state) Movement:Noclip(state) end,
}):Keybind({ Default = "N", Flag = "move_noclip_key" })

charSection:Toggle({
	Text     = "Infinite Jump",
	Flag     = "move_infjump",
	Default  = false,
	Callback = function(state) Movement:InfiniteJump(state) end,
})

charSection:Slider({
	Text     = "Walk Speed",
	Flag     = "move_walkspeed",
	Min      = 16, Max = 500, Default = 16,
	Callback = function(value) Movement:WalkSpeed(value) end,
})

charSection:Slider({
	Text     = "Jump Power",
	Flag     = "move_jumppower",
	Min      = 50, Max = 500, Default = 50,
	Callback = function(value) Movement:JumpPower(value) end,
})

-- ================================================================
-- SETTINGS
-- ================================================================

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
SaveManager:SetFolder("Facility/pvp")

InterfaceManager:BuildInterfaceSection(Settings, 1)
SaveManager:BuildConfigSection(Settings, 2)
ThemeManager:Mount(Window)

Window:SetTab(Visuals)

Library:Notify("Facility", "Loaded.", 4)

SaveManager:LoadAutoloadConfig()
ThemeManager:Load()
