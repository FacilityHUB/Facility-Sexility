-- FacilityUniversal: embedded-v1
local host = ...
-- Universal client menu. The loader provides the UI, entity tracker and ESP.
local F = assert(shared.Facility, "Start Facility with loader.luau")
local Library, Entity, Esp = F.Library, F.Entity, F.Esp
local load = host and host.Load or F.Load
local Aim = load("CModules/FAimbot.luau", "aimbot")
local Move = load("CModules/FMovement.luau", "movement")
local Cross = load("CModules/CCrosshair.luau", "crosshair")
local Visual = load("CModules/CVisual.luau", "visuals")
if host then
    -- Game scripts can replace the entity targeting rules and mutate team settings.
    Entity = load("Libraries/Entity.luau", "universal entities")
    Esp = load("CModules/FEsp.luau", "universal esp")
    assert(Esp ~= F.Esp, "Universal requires an independent ESP instance in combined mode")
end
assert(shared.Facility == F, "Universal load superseded")
local player = game:GetService("Players").LocalPlayer
local Lighting = game:GetService("Lighting")
local connections = {}
local clearCharacter
local stopped = false
F.StopUniversal = function()
    if stopped then return end
    stopped = true
    for _, connection in ipairs(connections) do connection:Disconnect() end
    if clearCharacter then clearCharacter() end
    if Move._loaded then Move:Unload() end
    Aim:Unload()
    Esp:Unload()
    Cross:Unload()
    Visual:Unload()
    if host then Entity:Destroy() end
end

local Window = host and host.Window or Library:Window({Title = "Facility", Suffix = ".universal", Width = 780, Height = 620, MinWidth = 580, SectionTitleStyle = "border"})
if host then
    Entity:Start()
    local originalDestroy = Library.Destroy
    local stop = F.StopUniversal
    local function destroy(self, ...)
        stop()
        return originalDestroy(self, ...)
    end
    Library.Destroy = destroy
    F.StopUniversal = function()
        if Library.Destroy == destroy then Library.Destroy = originalDestroy end
        stop()
    end
end

local function tab(name, icon)
    return Window:Tab(host and ("U · " .. name) or name, icon)
end
local function words(key)
    local label = key:gsub("_", " "):gsub("(%l)(%u)", "%1 %2")
    return label:sub(1, 1):upper() .. label:sub(2)
end
local function keys(t)
    local result = {}
    for key in pairs(t) do table.insert(result, key) end
    table.sort(result)
    return result
end

-- Each control has its own config flag. Defaults come from the active module.
local function controls(section, prefix, state, change)
    local ui = {}
    local function options(key, label)
        return {Text = label or words(key), Flag = "u_" .. prefix .. "_" .. key, Default = state[key],
            Callback = function(value)
                if stopped or state[key] == value then return end
                state[key] = value
                if change then change(key, value) end
            end}
    end
    function ui:toggle(key, label)
        return section:Toggle(options(key, label))
    end
    function ui:number(key, min, max, decimals, label)
        local o = options(key, label)
        o.Min, o.Max, o.Decimals = min, max, decimals or 0
        return section:Slider(o)
    end
    function ui:list(key, choices, multi, label)
        local o = options(key, label)
        o.Options, o.Multi = choices, multi or false
        return section:Dropdown(o)
    end
    function ui:text(key, label)
        return section:Input(options(key, label))
    end
    function ui:color(key, label)
        local o = options(key, label)
        if section.ColorPicker then return section:ColorPicker(o) end
        -- Some versions expose a color picker only inside a gear panel.
        local callback = o.Callback
        o.Default = state[key]:ToHex()
        o.Text = o.Text .. " (hex)"
        o.Callback = function(value)
            local hex = tostring(value):match("^#?(%x%x%x%x%x%x)$")
            if hex then callback(Color3.fromHex(hex)) end
        end
        return section:Input(o)
    end
    return ui
end
local function switches(ui, names)
    for _, key in ipairs(names) do ui:toggle(key) end
end
local function sliders(ui, specs)
    for _, spec in ipairs(specs) do ui:number(table.unpack(spec)) end
end
local function enumNames(enum)
    local names = {}
    for _, item in ipairs(enum:GetEnumItems()) do table.insert(names, item.Name) end
    return names
end

local aimTab = tab("Aim", "crosshair")
local aimBox = aimTab:Section("Targeting", 1)
local a = Aim.Settings
local aim = controls(aimBox, "aim", a, function(key, value)
    if key == "Fov" then Aim:SetFov(value) end
    if key == "Parts" and #value == 0 then a.Parts = {"Head"} end
end)
controls(aimBox, "aim_master", {Enabled = false}, function(_, value)
    Aim.Enabled = value
    if value then Aim:Load(Entity) else Aim:Unload() end
end):toggle("Enabled")
aimBox:Keybind({Text = "Aim key", Flag = "u_aim_key", Default = "MB2", Mode = "toggle",
    OnChanged = function(key)
        local mouse = {MB1 = Enum.UserInputType.MouseButton1, MB2 = Enum.UserInputType.MouseButton2, MB3 = Enum.UserInputType.MouseButton3}
        if typeof(key) == "EnumItem" then Aim:SetKey(key)
        elseif type(key) == "string" then
            local ok, item = pcall(function() return mouse[key] or Enum.KeyCode[key] end)
            if ok and item then Aim:SetKey(item) end
        end
    end})
aim:toggle("ToggleMode")
aim:list("Mode", {"Camera", "Mouse"})
aim:list("Priority", {"Cursor", "Closest", "LowestHealth"})
aim:list("Parts", {"Head","UpperTorso","LowerTorso","HumanoidRootPart","Torso"}, true)
switches(aim, {"AliveCheck","TeamCheck","WallCheck","IgnoreDowned","IgnoreForcefield","Sticky","Multipoint","RandomPart"})
sliders(aim, {{"MaxDistance",1,10000},{"StickyFov",1,5,2},{"RandomInterval",0.05,5,2},{"SwitchDelay",0,2,2},{"Deadzone",0,100}})
local motion = controls(aimTab:Section("Aim movement and prediction", 2), "aim", a)
sliders(motion, {{"Smoothness",0.01,1,2},{"Sensitivity",0.01,1,2},{"Stiffness",1,100},{"Damping",0.01,2,2},{"MaxOvershoot",0,180}})
motion:list("EasingStyle", enumNames(Enum.EasingStyle))
motion:list("EasingDirection", enumNames(Enum.EasingDirection))
switches(motion, {"Elastic","Prediction","PingPrediction","TriggerBot"})
sliders(motion, {{"PredictionTime",0,1,3},{"TriggerDelay",0,2,2},{"TriggerCooldown",0,2,2},{"HitChance",0,100}})
local fov = controls(aimTab:Section("Field of view and target overlay", 2), "aim", a, function(key,value)
    if key == "Fov" then Aim:SetFov(value) end
end)
switches(fov, {"FovCheck","FovVisible","FovFilled","TargetLine","TargetInfo"})
sliders(fov, {{"Fov",1,2000},{"FovThickness",1,8},{"FovTransparency",0,1,2},{"TargetLineThickness",1,8},{"TargetInfoSize",8,40}})
for _, key in ipairs({"FovColor","FovLockColor","TargetLineColor","TargetInfoColor"}) do fov:color(key) end
fov:list("TargetLineOrigin", {"Mouse","Center"})

local moveTab = tab("Movement", "move")
local travel = moveTab:Section("Movement", 1)
local toggles = {}
local actions = {"Noclip","Swim","Float","Spider","InfiniteJump"}
for _, key in ipairs(actions) do toggles[key] = false end
local activeMove = controls(travel, "move_active", toggles, function(key, value)
    if value then Move:Load() end
    Move[key](Move, value)
end)
switches(activeMove, actions)
controls(travel, "move_flight", {Flight="Off"}, function(_, value)
    if value == "Off" then
        if Move.State.VehicleFly then Move:VehicleFly(false) else Move:Fly(false) end
    else
        Move:Load()
        if value == "Vehicle" then Move:VehicleFly(true) else Move:Fly(true) end
    end
end):list("Flight", {"Off","Character","Vehicle"}, false, "Flight (velocity)")
local tuning = controls(travel, "move", Move.Settings)
sliders(tuning, {{"FlySpeed",0.1,30,1},{"VehicleFlySpeed",0.1,30,1},{"FloatHeight",0.1,40,1},{"SpiderSpeed",0.1,20,1}})
tuning:toggle("NoclipVehicle")
local velocity = moveTab:Section("Walk and jump", 2)
for _, spec in ipairs({{"WalkSpeed","WalkSpeedMode",16,250,{"Humanoid","Velocity","CFrame"}},{"JumpPower","JumpMode",50,300,{"Humanoid","Height"}}}) do
    local key, mode, default = spec[1], spec[2], spec[3]
    local state = {Enabled = false, Value = Move.Settings[key], Mode = Move.Settings[mode]}
    local ui = controls(velocity, "move_" .. key, state, function(changed)
        if state.Enabled then
            Move:Load()
            Move[key](Move, state.Value, state.Mode)
        elseif changed == "Enabled" then Move[key](Move, default, "Humanoid") end
    end)
    ui:toggle("Enabled", words(key))
    ui:number("Value", 0, spec[4], 0, words(key) .. " value")
    ui:list("Mode", spec[5], false, words(key) .. " mode")
end

local espTab = tab("ESP", "eye")
local espBox = espTab:Section("ESP and teams", 1)
controls(espBox, "esp", {Enabled = false}, function(_, value)
    if value then Esp:Load(Entity) else Esp:Unload() end
end):toggle("Enabled")
local sharedEsp = controls(espBox, "esp_shared", Esp.sharedSettings, function(key, value)
    if key == "teamCheck" then Entity.Settings.TeamCheck = value; Entity:RefreshTargets() end
end)
switches(sharedEsp, {"aliveCheck","useTeamColor","rainbow","debug"})
sliders(sharedEsp, {{"textSize",8,40},{"textFont",0,3},{"slowInterval",0.02,1,2},{"rainbowSpeed",1,1000}})
sharedEsp:list("teamCheck", {"Off","Team","TeamColor"})
sharedEsp:list("whitelistMode", {"highlight","filter"})
local entitySettings = controls(espBox, "entity", Entity.Settings, function() Entity:RefreshTargets() end)
entitySettings:toggle("IgnoreSingleTeam")
entitySettings:number("LoadTimeout",1,30,0,"Character load timeout")
controls(espBox, "esp_list", {Ids=""}, function(_, text)
    local ids = {}
    for id in tostring(text):gmatch("%d+") do table.insert(ids, tonumber(id)) end
    Esp.whitelist = ids
end):text("Ids","Whitelist user IDs (comma separated)")

local espRanges = {maxDistance={1,20000},offScreenArrowRadius={1,1500},offScreenArrowSize={1,100},skeletonThickness={1,10}}
for index, group in ipairs({"enemy","friendly","whitelist","default"}) do
    local cfg = Esp.teamSettings[group]
    local box = espTab:Section(words(group) .. " appearance", index % 2 + 1)
    local ui = controls(box, "esp_" .. group, cfg)
    for _, key in ipairs(keys(cfg)) do
        local value = cfg[key]
        if type(value) == "boolean" then ui:toggle(key)
        elseif espRanges[key] then ui:number(key, table.unpack(espRanges[key]))
        elseif key == "tracerOrigin" then ui:list(key, {"Bottom","Middle","Top","Mouse"})
        elseif typeof(value) == "Color3" then ui:color(key)
        elseif type(value) == "table" and typeof(value[1]) == "Color3" then
            local pair = {Color=value[1], Opacity=value[2]}
            local color = controls(box, "esp_" .. group .. "_" .. key, pair, function()
                cfg[key] = {pair.Color, pair.Opacity}
            end)
            color:color("Color", words(key))
            color:number("Opacity",0,1,2,words(key) .. " opacity")
        end
    end
end

local crossTab = tab("Crosshair", "target")
local crossBox = crossTab:Section("Reticle", 1)
controls(crossBox, "cross_master", {Enabled=false}, function(_, value)
    if value then Cross:Load() else Cross:Unload() end
end):toggle("Enabled")
local c = Cross.Settings
local cross = controls(crossBox, "cross", c)
cross:list("mode", {"mouse","center","position"}, false, "Anchor")
cross:list("crosshair_mode", {"static","follow muzzle"}, false, "Tracking")
local point = {X=c.position.X, Y=c.position.Y}
local pos = controls(crossBox, "cross_pos", point, function() c.position = Vector2.new(point.X, point.Y) end)
pos:number("X",0,8192); pos:number("Y",0,8192)
switches(cross, {"show_lines","show_ammo"})
cross:color("crosshair_color")
sliders(cross, {{"width",0.5,12,1},{"length",1,120},{"radius",0,120},{"refreshrate",0,1,3}})
local animBox = crossTab:Section("Animation", 2)
local anim = controls(animBox, "cross", c)
switches(anim, {"spin","resize"})
sliders(anim, {{"spin_speed",0,720},{"spin_max",1,360},{"resize_speed",0,720},{"resize_min",0,100},{"resize_max",0,100},{"scale_min",0.1,5,2},{"scale_max",0.1,5,2}})
controls(animBox, "cross_enum", {Style=c.spin_style.Name}, function(_, value)
    c.spin_style = Enum.EasingStyle[value]
end):list("Style", enumNames(Enum.EasingStyle))
local worldTab = tab("World", "sun")
local world = {}
local function updateWorld() Visual:SetWorld(next(world) and world or nil) end
local function feature(box, prefix, target, key, cfg, update)
    controls(box, prefix .. "_master", {Enabled=false}, function(_, enabled)
        target[key] = enabled and cfg or nil
        update()
    end):toggle("Enabled")
    return controls(box, prefix, cfg, function()
        if target[key] then update() end
    end)
end
local lightBox = worldTab:Section("Lighting", 1)
local light = {}
local lightRanges = {Brightness={0,10,2}, ClockTime={0,24,2}, GeographicLatitude={-90,90,1},
    ShadowSoftness={0,1,2}, FogStart={0,100000},FogEnd={0,100000},EnvironmentDiffuseScale={0,1,2},
    EnvironmentSpecularScale={0,1,2},ExposureCompensation={-5,5,2}}
for key in pairs(lightRanges) do light[key] = Lighting[key] end
for _, key in ipairs({"Ambient","OutdoorAmbient","ColorShift_Top","ColorShift_Bottom","FogColor","GlobalShadows"}) do light[key] = Lighting[key] end
local lightUI = feature(lightBox,"world_light",world,"Lighting",light,updateWorld)
for _, key in ipairs(keys(lightRanges)) do lightUI:number(key, table.unpack(lightRanges[key])) end
for _, key in ipairs({"Ambient","OutdoorAmbient","ColorShift_Top","ColorShift_Bottom","FogColor"}) do lightUI:color(key) end
lightUI:toggle("GlobalShadows")
controls(lightBox, "world_shader", {Shaders=false}, function(_,value)
    world.Shaders = value or nil
    updateWorld()
end):toggle("Shaders")
local atmBox = worldTab:Section("Atmosphere", 2)
local atm = feature(atmBox,"world_atm",world,"Atmosphere",{
    Density=0.3,Offset=0.25,Haze=8,Glare=0.6,Color=Color3.fromRGB(140,160,190),Decay=Color3.fromRGB(90,110,140)},updateWorld)
sliders(atm, {{"Density",0,1,2},{"Offset",-1,1,2},{"Haze",0,10,2},{"Glare",0,10,2}})
atm:color("Color"); atm:color("Decay")
local bloom = feature(worldTab:Section("Bloom",1),"world_bloom",world,"Bloom",{Intensity=0.3,Size=4,Threshold=0.7},updateWorld)
sliders(bloom, {{"Intensity",0,5,2},{"Size",0,56},{"Threshold",0,5,2}})
local grade = feature(worldTab:Section("Color correction",2),"world_grade",world,"ColorCorrection",{
    Brightness=0,Contrast=0,Saturation=0,TintColor=Color3.new(1,1,1)}, updateWorld)
sliders(grade, {{"Brightness",-1,1,2},{"Contrast",-1,1,2},{"Saturation",-1,1,2}})
grade:color("TintColor")
local skyBox = worldTab:Section("Sky", 2)
local skyState = {Enabled=false, Preset="Default"}
local customSky = {SunAngularSize=20,MoonAngularSize=11,StarCount=3000,CelestialBodiesShown=true}
local currentSky = Lighting:FindFirstChildOfClass("Sky")
for _, face in ipairs({"SkyboxBk","SkyboxDn","SkyboxFt","SkyboxLf","SkyboxRt","SkyboxUp"}) do
    customSky[face] = currentSky and currentSky[face] or ""
end
local function updateSky()
    world.Sky = skyState.Enabled and (skyState.Preset == "Custom" and customSky or skyState.Preset) or nil
    updateWorld()
end
local sky = controls(skyBox, "world_sky", skyState, updateSky)
sky:toggle("Enabled")
sky:list("Preset", {"Default", "Neptune", "Among Us", "Nebula", "Vaporwave", "Clouds", "Twilight", "DaBaby", "Minecraft", "Chill", "Redshift", "Blue Stars", "Blue Aurora", "Realistic", "StarsShader", "Gloomy", "Nebula Purple", "Jungle", "Spongebob", "mountain scape", "yellowy cloud", "Aurora", "winter mountain", "stormy", "Custom"})
local skyFields = controls(skyBox, "world_sky_custom", customSky, function()
    if skyState.Enabled and skyState.Preset == "Custom" then updateSky() end
end)
for _, face in ipairs({"SkyboxBk","SkyboxDn","SkyboxFt","SkyboxLf","SkyboxRt","SkyboxUp"}) do skyFields:text(face, "Custom " .. face) end
sliders(skyFields, {{"SunAngularSize",0,60,1},{"MoonAngularSize",0,60,1},{"StarCount",0,10000}})
skyFields:toggle("CelestialBodiesShown")

local weatherTab = tab("Weather", "cloud")
local weather = {}
local function updateWeather() Visual:SetWeather(next(weather) and weather or nil) end
-- Defaults match each particle preset so enabling one preserves its original appearance.
local weatherDefaults = {
    rain = {
        color = Color3.fromRGB(255, 255, 255),
        sizeScale = 1,
        rate = 100,
        speed_min = 60, speed_max = 60,
        size_min = 10, size_max = 10,
        transparency_min = 0.22, transparency_max = 1,
        spread = 0,
        brightness = 1,
        light_emission = 0.05,
        glowScale = 0,
        base_rate = 600,
        texture = "rbxassetid://1822883048",
        locked = true,
        orientation = Enum.ParticleOrientation.FacingCameraWorldUp,
        light_influence = 0.9,
        lifetime_min = 0.8, lifetime_max = 0.8,
    },
    snow = {
        color = Color3.fromRGB(255, 255, 255),
        sizeScale = 1,
        rate = 100,
        amount = 100,
        speed_min = 30, speed_max = 30,
        size_min = 0.33, size_max = 0.40,
        transparency_min = 0.74, transparency_max = 1,
        spread = 0,
        brightness = 1,
        light_emission = 0.5,
        glowScale = 0,
        base_rate = 1000,
        texture = "http://www.roblox.com/asset/?id=99851851",
        locked = false,
        orientation = Enum.ParticleOrientation.FacingCamera,
        light_influence = 1,
        lifetime_min = 4, lifetime_max = 4,
    },
    lightrain = {
        color = Color3.fromRGB(255, 255, 255),
        sizeScale = 1,
        rate = 100,
        speed_min = 30, speed_max = 50,
        size_min = 0.2, size_max = 0.2,
        transparency_min = 0, transparency_max = 0,
        spread = 0,
        brightness = 2,
        light_emission = 0.5,
        glowScale = 0,
        base_rate = 500,
        texture = "rbxasset://textures/particles/sparkles_main.dds",
        locked = true,
        orientation = Enum.ParticleOrientation.FacingCameraWorldUp,
        light_influence = 0.3,
        lifetime_min = 9, lifetime_max = 9,
    },
    stars = {
        color = Color3.fromRGB(255, 255, 255),
        sizeScale = 1,
        rate = 100,
        amount = 100,
        speed_min = 30, speed_max = 30,
        size_min = 0.33, size_max = 0.40,
        transparency_min = 0.74, transparency_max = 1,
        spread = 0,
        brightness = 1,
        light_emission = 0.5,
        glowScale = 0,
        base_rate = 1000,
        texture = "http://www.roblox.com/asset/?id=6822501679",
        locked = false,
        orientation = Enum.ParticleOrientation.FacingCamera,
        light_influence = 1,
        lifetime_min = 4, lifetime_max = 4,
    },
    hearts = {
        color = Color3.fromRGB(255, 255, 255),
        sizeScale = 1,
        rate = 100,
        amount = 100,
        speed_min = 30, speed_max = 30,
        size_min = 0.33, size_max = 0.40,
        transparency_min = 0.74, transparency_max = 1,
        spread = 0,
        brightness = 1,
        light_emission = 0.5,
        glowScale = 0,
        base_rate = 1000,
        texture = "http://www.roblox.com/asset/?id=36721240",
        locked = false,
        orientation = Enum.ParticleOrientation.FacingCamera,
        light_influence = 1,
        lifetime_min = 4, lifetime_max = 4,
    },
}
for i, name in ipairs({"rain","snow","lightrain","stars","hearts"}) do
    local cfg = weatherDefaults[name]
    local weatherBox = weatherTab:Section(name == "lightrain" and "Light rain" or words(name), (i-1)%2+1)
    local w = feature(weatherBox,"weather_" .. name,weather,name,cfg,updateWeather)
    w:color("color")
    if cfg.amount then w:number("amount",1,1000) else w:number("rate",0,200); w:number("base_rate",1,2000) end
    sliders(w, {{"speed_min",0,150,1},{"speed_max",0,150,1},{"size_min",0,25,2},{"size_max",0,25,2},{"sizeScale",0.01,10,2},
        {"transparency_min",0,1,2},{"transparency_max",0,1,2},{"spread",0,180},{"brightness",0,10,2},
        {"light_emission",0,1,2},{"light_influence",0,1,2},{"glowScale",0,5,2},{"lifetime_min",0.1,15,1},{"lifetime_max",0.1,15,1}})
    w:toggle("locked"); w:text("texture")
    controls(weatherBox,"weather_" .. name .. "_enum",{Orientation=cfg.orientation.Name},function(_, value)
        cfg.orientation=Enum.ParticleOrientation[value]
        if weather[name] then updateWeather() end
    end):list("Orientation",enumNames(Enum.ParticleOrientation))
end

local view = tab("View", "eye")
local tex = {Dark=false,Smooth=false,Transparent=false,Transparency=0.6}
local textures = controls(view:Section("World textures",1),"texture",tex,function()
    Visual:SetTextures((tex.Dark or tex.Smooth or tex.Transparent) and {
        Dark=tex.Dark,Smooth=tex.Smooth,Transparency=tex.Transparent and tex.Transparency or nil} or nil)
end)
switches(textures, {"Dark","Smooth","Transparent"})
textures:number("Transparency",0,1,2)
local cam = {MotionBlur=false,Amount=8,Gain=2,Stretch=false,X=13,Y=10}
local camera = controls(view:Section("Camera",2),"camera",cam,function()
    Visual:SetCamera((cam.MotionBlur or cam.Stretch) and {
        MotionBlur=cam.MotionBlur,Amount=cam.Amount,Gain=cam.Gain,AspectRatio=cam.Stretch and cam.X/cam.Y or nil} or nil)
end)
switches(camera, {"MotionBlur","Stretch"})
sliders(camera, {{"Amount",1,20},{"Gain",1,10},{"X",1,32},{"Y",1,32}})

local feedback = tab("Effects", "zap")
local combat = {}
local observer = {DamageNumbers=true}
local function updateCombat()
    combat.ObserveDamageNumbers = (combat.Impacts or combat.Notifications) and observer.DamageNumbers or nil
    Visual:SetCombat(next(combat) and combat or nil)
end
local tracerBox = feedback:Section("Shot tracers", 1)
local tracers = feature(tracerBox,"tracers",combat,"Tracers",{
    Style="Line", Color=Color3.new(1,1,1), Size=1, Duration=3, Fade=0.5, LerpSpeed=0},updateCombat)
tracers:list("Style", {"Line","Beam","Lightning","Heartrate","Chain","Glitch","Swirl","Neon","Plasma","Laser"})
tracers:color("Color")
sliders(tracers, {{"Size",0.5,5,1},{"Duration",0.1,10,1},{"Fade",0,2,2},{"LerpSpeed",0,5,2}})
-- Standard Roblox Tools expose activation, but do not expose the authoritative shot.
-- Use this optional cursor ray only when there is no game-specific shot adapter.
local rayMode = {ToolRay=true}
controls(tracerBox,"tracer_source",rayMode):toggle("ToolRay","Estimate tracer from equipped Tool")
local toolConnections = {}
local childAdded, childRemoved
clearCharacter = function()
    if childAdded then childAdded:Disconnect() end
    if childRemoved then childRemoved:Disconnect() end
    for _, conn in pairs(toolConnections) do conn:Disconnect() end
    table.clear(toolConnections)
end
local function watchCharacter(character)
    clearCharacter()
    local function attach(tool)
        if not tool:IsA("Tool") or toolConnections[tool] then return end
        toolConnections[tool] = tool.Activated:Connect(function()
            if stopped or not rayMode.ToolRay or not combat.Tracers then return end
            local camNow = workspace.CurrentCamera
            if not camNow then return end
            local muzzle = tool:FindFirstChild("Muzzle", true) or tool:FindFirstChild("_muzzle", true)
            local handle = tool:FindFirstChild("Handle")
            local origin = muzzle and muzzle:IsA("Attachment") and muzzle.WorldPosition
                or handle and handle:IsA("BasePart") and handle.Position or camNow.CFrame.Position
            local ray = player:GetMouse().UnitRay
            local params = RaycastParams.new()
            params.FilterType = Enum.RaycastFilterType.Exclude
            params.FilterDescendantsInstances = {character, camNow}
            local hit = workspace:Raycast(ray.Origin, ray.Direction * 2000, params)
            Visual:DrawTracer(origin, hit and hit.Position or ray.Origin + ray.Direction * 2000)
        end)
    end
    childAdded = character.ChildAdded:Connect(attach)
    childRemoved = character.ChildRemoved:Connect(function(tool)
        local conn = toolConnections[tool]
        if conn then conn:Disconnect(); toolConnections[tool] = nil end
    end)
    for _, item in ipairs(character:GetChildren()) do attach(item) end
end
table.insert(connections, player.CharacterAdded:Connect(watchCharacter))
table.insert(connections, player.CharacterRemoving:Connect(clearCharacter))
if player.Character then watchCharacter(player.Character) end

local hitBox = feedback:Section("Impact effects",2)
local impacts = feature(hitBox,"impacts",combat,"Impacts",{
    Styles={"Particles"},Color=Color3.fromRGB(159,133,195),Duration=2.8,FloatHeight=7},updateCombat)
impacts:list("Styles",{"Particles","Fortnite","Shockwave","Lightning","Blood","Fire","Ice","Hearts","Stars","Confetti","Ripple","Sparks","Neon","Void","Plasma","Glitch","CosmicDust"},true)
impacts:color("Color")
sliders(impacts, {{"Duration",0.5,8,1},{"FloatHeight",1,25}})
-- The observer only runs when an impact or a notification is enabled.
controls(hitBox,"impact_source",observer,function() updateCombat() end):toggle("DamageNumbers","Read numeric damage billboards")
local noteBox = feedback:Section("Hit notifications",1)
local note = {Duration=2,Size=16,Max=4,Gap=4,In="fade bounce",Out="fade",Color=Color3.new(1,1,1),Position=UDim2.fromScale(0.5,0.65)}
local notices = feature(noteBox,"notices",combat,"Notifications",note,updateCombat)
local styles = {"fade","slide left","slide right","slide down","bounce","fade bounce","scale"}
notices:list("In",styles,false,"Entry animation"); notices:list("Out",styles,false,"Exit animation")
notices:color("Color")
sliders(notices, {{"Duration",0.3,12,1},{"Size",8,40},{"Max",1,20},{"Gap",0,40}})
local anchor = {X=0.5,Y=0.65}
local notePos = controls(noteBox,"notice_position",anchor,function()
    note.Position = UDim2.fromScale(anchor.X, anchor.Y)
    if combat.Notifications then updateCombat() end
end)
notePos:number("X",0,1,2); notePos:number("Y",0,1,2)

if host then return end

local settings = tab("Settings","cog")
local save, interface, theme = Library.SaveManager, Library.InterfaceManager, Library.ThemeManager
save:SetLibrary(Library)
interface:SetLibrary(Library)
interface:SetWindow(Window)
theme:SetLibrary(Library)
save:IgnoreThemeSettings()
interface:SetFolder("Facility")
theme:SetFolder("Facility")
save:SetFolder("Facility/Universal")
interface:BuildInterfaceSection(settings,1)
save:BuildConfigSection(settings,2)
theme:Mount(Window)
Window:SetTab(aimTab)
save:LoadAutoloadConfig()
theme:Load()
