-- Facility world and combat visuals. All effects start disabled.
-- SetWorld, SetWeather, SetTextures, SetCamera take a settings table or nil to reset.
-- Feed confirmed shots and hits to DrawTracer(origin, impact) and Hit(part, damage).
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local Visual = {}
local cleanups = {}

local function stop(group)
    local cleanup = cleanups[group]
    cleanups[group] = nil
    if cleanup then cleanup() end
end

-- Restore only properties written by this group, including when configuration fails.
local function configure(group, options, apply)
    stop(group)
    if not options then return end
    local undo = {}
    cleanups[group] = function()
        for i = #undo, 1, -1 do
            local ok, err = pcall(undo[i])
            if not ok then warn(err) end
        end
    end
    local function defer(fn) table.insert(undo, fn) end
    local function write(obj, key, value)
        local old = obj[key]
        obj[key] = value
        defer(function() if obj[key] == value then obj[key] = old end end)
    end
    local function create(class, parent)
        local obj = Instance.new(class)
        defer(function() obj:Destroy() end)
        obj.Parent = parent
        return obj
    end
    local ok, err = pcall(apply, options, defer, write, create)
    if not ok then
        stop(group)
        error(err, 3)
    end
end

local Skyboxes = {
    Default = { SkyboxBk = "rbxassetid://91458024", SkyboxDn = "rbxassetid://91457980", SkyboxFt = "rbxassetid://91458024", SkyboxLf = "rbxassetid://91458024", SkyboxRt = "rbxassetid://91458024", SkyboxUp = "rbxassetid://91458002" },
    Neptune = { SkyboxBk = "rbxassetid://218955819", SkyboxDn = "rbxassetid://218953419", SkyboxFt = "rbxassetid://218954524", SkyboxLf = "rbxassetid://218958493", SkyboxRt = "rbxassetid://218957134", SkyboxUp = "rbxassetid://218950090" },
    ["Among Us"] = { SkyboxBk = "rbxassetid://5752463190", SkyboxDn = "rbxassetid://5752463190", SkyboxFt = "rbxassetid://5752463190", SkyboxLf = "rbxassetid://5752463190", SkyboxRt = "rbxassetid://5752463190", SkyboxUp = "rbxassetid://5752463190" },
    Nebula = { SkyboxBk = "rbxassetid://159454299", SkyboxDn = "rbxassetid://159454296", SkyboxFt = "rbxassetid://159454293", SkyboxLf = "rbxassetid://159454286", SkyboxRt = "rbxassetid://159454300", SkyboxUp = "rbxassetid://159454288" },
    Vaporwave = { SkyboxBk = "rbxassetid://1417494030", SkyboxDn = "rbxassetid://1417494146", SkyboxFt = "rbxassetid://1417494253", SkyboxLf = "rbxassetid://1417494402", SkyboxRt = "rbxassetid://1417494499", SkyboxUp = "rbxassetid://1417494643" },
    Clouds = { SkyboxBk = "rbxassetid://570557514", SkyboxDn = "rbxassetid://570557775", SkyboxFt = "rbxassetid://570557559", SkyboxLf = "rbxassetid://570557620", SkyboxRt = "rbxassetid://570557672", SkyboxUp = "rbxassetid://570557727" },
    Twilight = { SkyboxBk = "rbxassetid://264908339", SkyboxDn = "rbxassetid://264907909", SkyboxFt = "rbxassetid://264909420", SkyboxLf = "rbxassetid://264909758", SkyboxRt = "rbxassetid://264908886", SkyboxUp = "rbxassetid://264907379" },
    DaBaby = { SkyboxBk = "rbxassetid://7245418472", SkyboxDn = "rbxassetid://7245418472", SkyboxFt = "rbxassetid://7245418472", SkyboxLf = "rbxassetid://7245418472", SkyboxRt = "rbxassetid://7245418472", SkyboxUp = "rbxassetid://7245418472" },
    Minecraft = { SkyboxBk = "rbxassetid://1876545003", SkyboxDn = "rbxassetid://1876544331", SkyboxFt = "rbxassetid://1876542941", SkyboxLf = "rbxassetid://1876543392", SkyboxRt = "rbxassetid://1876543764", SkyboxUp = "rbxassetid://1876544642" },
    Chill = { SkyboxBk = "rbxassetid://5084575798", SkyboxDn = "rbxassetid://5084575916", SkyboxFt = "rbxassetid://5103949679", SkyboxLf = "rbxassetid://5103948542", SkyboxRt = "rbxassetid://5103948784", SkyboxUp = "rbxassetid://5084576400" },
    Redshift = { SkyboxBk = "rbxassetid://401664839", SkyboxDn = "rbxassetid://401664862", SkyboxFt = "rbxassetid://401664960", SkyboxLf = "rbxassetid://401664881", SkyboxRt = "rbxassetid://401664901", SkyboxUp = "rbxassetid://401664936" },
    ["Blue Stars"] = { SkyboxBk = "rbxassetid://149397684", SkyboxDn = "rbxassetid://149397686", SkyboxFt = "rbxassetid://149397688", SkyboxLf = "rbxassetid://149397692", SkyboxRt = "rbxassetid://149397697", SkyboxUp = "rbxassetid://149397702" },
    ["Blue Aurora"] = { SkyboxBk = "rbxassetid://12063984", SkyboxDn = "rbxassetid://12064107", SkyboxFt = "rbxassetid://12064152", SkyboxLf = "rbxassetid://12064121", SkyboxRt = "rbxassetid://12064115", SkyboxUp = "rbxassetid://12064131" },
    Realistic = { SkyboxBk = "rbxassetid://144933338", SkyboxDn = "rbxassetid://144931530", SkyboxFt = "rbxassetid://144933262", SkyboxLf = "rbxassetid://144933244", SkyboxRt = "rbxassetid://144933299", SkyboxUp = "rbxassetid://144931564" },
    StarsShader = { SkyboxBk = "rbxassetid://169210090", SkyboxDn = "rbxassetid://169210108", SkyboxFt = "rbxassetid://169210121", SkyboxLf = "rbxassetid://169210133", SkyboxRt = "rbxassetid://169210143", SkyboxUp = "rbxassetid://169210149" },
    Gloomy = { SkyboxBk = "rbxassetid://5346760450", SkyboxDn = "rbxassetid://5346760689", SkyboxFt = "rbxassetid://5346760919", SkyboxLf = "rbxassetid://5346761102", SkyboxRt = "rbxassetid://5346761335", SkyboxUp = "rbxassetid://5346761509" },
    ["Nebula Purple"] = { SkyboxBk = "rbxassetid://129876530632297", SkyboxDn = "rbxassetid://108406529909981", SkyboxFt = "rbxassetid://104400530594543", SkyboxLf = "rbxassetid://73372229972523", SkyboxRt = "rbxassetid://87408857415924", SkyboxUp = "rbxassetid://13781740568136" },
    Jungle = { SkyboxBk = "rbxassetid://214399891", SkyboxDn = "rbxassetid://214399887", SkyboxFt = "rbxassetid://214399894", SkyboxLf = "rbxassetid://214405668", SkyboxRt = "rbxassetid://214399899", SkyboxUp = "rbxassetid://214399889" },
    Spongebob = { SkyboxBk = "rbxassetid://15962101128", SkyboxDn = "rbxassetid://15970246218", SkyboxFt = "rbxassetid://15962101128", SkyboxLf = "rbxassetid://15962101128", SkyboxRt = "rbxassetid://15962101128", SkyboxUp = "rbxassetid://15962901054" },
    ["mountain scape"] = { SkyboxBk = "rbxassetid://12474836637", SkyboxDn = "rbxassetid://12474837052", SkyboxFt = "rbxassetid://12474836748", SkyboxLf = "rbxassetid://12474836935", SkyboxRt = "rbxassetid://12474836446", SkyboxUp = "rbxassetid://12474835757" },
    ["yellowy cloud"] = { SkyboxBk = "rbxassetid://252760981", SkyboxDn = "rbxassetid://252763035", SkyboxFt = "rbxassetid://252761439", SkyboxLf = "rbxassetid://252760980", SkyboxRt = "rbxassetid://252760986", SkyboxUp = "rbxassetid://252762652" },
    Aurora = { SkyboxBk = "rbxassetid://340908398", SkyboxDn = "rbxassetid://340908450", SkyboxFt = "rbxassetid://340908468", SkyboxLf = "rbxassetid://340908504", SkyboxRt = "rbxassetid://340908530", SkyboxUp = "rbxassetid://340908586" },
    ["winter mountain"] = { SkyboxBk = "rbxassetid://402229526", SkyboxDn = "rbxassetid://402229596", SkyboxFt = "rbxassetid://402229293", SkyboxLf = "rbxassetid://402229368", SkyboxRt = "rbxassetid://402229417", SkyboxUp = "rbxassetid://402229564" },
    stormy = { SkyboxBk = "rbxassetid://255027929", SkyboxDn = "rbxassetid://255027967", SkyboxFt = "rbxassetid://255027923", SkyboxLf = "rbxassetid://255027938", SkyboxRt = "rbxassetid://255027946", SkyboxUp = "rbxassetid://255027960" },
}

-- World options: Lighting properties, Atmosphere, Sky (preset name or properties),
-- ColorCorrection, Bloom, and Shaders (boolean).
function Visual:SetWorld(options)
    configure("World", options, function(cfg, _, write, create)
        local function apply(obj, props)
            for key, value in pairs(props or {}) do write(obj, key, value) end
        end
        local function worldObject(class)
            return Lighting:FindFirstChildOfClass(class) or create(class, Lighting)
        end
        if cfg.Shaders then
            apply(Lighting, {
                Brightness = 2.1, Ambient = Color3.fromRGB(20, 23, 35),
                OutdoorAmbient = Color3.fromRGB(88, 108, 140), ShadowSoftness = 0.2,
                EnvironmentDiffuseScale = 0.95, EnvironmentSpecularScale = 0.98,
                ColorShift_Top = Color3.fromRGB(12, 16, 32), ColorShift_Bottom = Color3.fromRGB(6, 10, 25),
                ExposureCompensation = 0.18,
            })
            apply(worldObject("Atmosphere"), { Density = 0.30, Offset = 0.07, Haze = 0.78, Glare = 0.15,
                Color = Color3.fromRGB(175, 195, 225), Decay = Color3.fromRGB(85, 125, 195) })
            apply(worldObject("Sky"), { SunAngularSize = 7.8, MoonAngularSize = 9 })
            apply(create("SunRaysEffect", Lighting), { Intensity = 0.075, Spread = 0.90 })
            apply(create("DepthOfFieldEffect", Lighting), { FarIntensity = 0.045, NearIntensity = 0, FocusDistance = 80, InFocusRadius = 58 })
        end
        apply(Lighting, cfg.Lighting)
        if cfg.Atmosphere then apply(worldObject("Atmosphere"), cfg.Atmosphere) end
        if cfg.Sky then
            local sky = cfg.Sky
            if type(sky) == "string" then sky = assert(Skyboxes[sky], "Unknown sky preset") end
            apply(worldObject("Sky"), sky)
        end
        if cfg.Bloom or cfg.Shaders then
            apply(create("BloomEffect", Lighting), cfg.Bloom or {Intensity = 0.14, Size = 16, Threshold = 1.85})
        end
        if cfg.ColorCorrection or cfg.Shaders then
            apply(create("ColorCorrectionEffect", Lighting), cfg.ColorCorrection or {
                Brightness = 0.015, Contrast = 0.20, Saturation = 0.22, TintColor = Color3.fromRGB(255, 249, 238),
            })
        end
    end)
end

local weathercfgs = {
    rain = {
        enabled = false,
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
        enabled = false,
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
        enabled = false,
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
        enabled = false,
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
        enabled = false,
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

local function applyparticle(p, cfg)
    p.EmissionDirection = Enum.NormalId.Bottom
    p.LockedToPart = cfg.locked
    p.Orientation = cfg.orientation
    p.Texture = cfg.texture
    p.Speed = NumberRange.new(cfg.speed_min, math.max(cfg.speed_min, cfg.speed_max))
    p.Lifetime = NumberRange.new(cfg.lifetime_min, math.max(cfg.lifetime_min, cfg.lifetime_max))
    p.SpreadAngle = Vector2.new(cfg.spread, cfg.spread)
    p.LightInfluence = cfg.light_influence

    local glow = math.clamp(tonumber(cfg.glowScale) or 0, 0, 5)
    if glow > 0 then
        local glowNorm = glow / 5
        p.Brightness = cfg.brightness * (1 + glow * 1.75)
        p.LightEmission = math.clamp((cfg.light_emission or 0) + glow * 0.2, 0, 1)
        p.LightInfluence = math.clamp((cfg.light_influence or 1) * (1 - glowNorm * 0.98), 0, 1)
    else
        p.Brightness = cfg.brightness
        p.LightEmission = cfg.light_emission
    end

    if cfg.amount then
        p.Rate = math.clamp(cfg.amount, 1, 1000)
    else
        p.Rate = cfg.base_rate * (cfg.rate / 100)
    end

    p.Size = NumberSequence.new{
        NumberSequenceKeypoint.new(0, cfg.size_min * (cfg.sizeScale or 1)),
        NumberSequenceKeypoint.new(1, cfg.size_max * (cfg.sizeScale or 1))
    }
    p.Transparency = NumberSequence.new{
        NumberSequenceKeypoint.new(0, cfg.transparency_max),
        NumberSequenceKeypoint.new(0.25, cfg.transparency_min),
        NumberSequenceKeypoint.new(0.75, cfg.transparency_min),
        NumberSequenceKeypoint.new(1, cfg.transparency_max)
    }
    p.Color = ColorSequence.new(cfg.color)
end

-- Example: SetWeather({rain = {rate = 50}, snow = true}).
function Visual:SetWeather(options)
    configure("Weather", options, function(types, defer, _, create)
        local parts = {}
        for name, overrides in pairs(types) do
            if overrides then
                local cfg = table.clone(assert(weathercfgs[name], "Unknown weather preset"))
                if type(overrides) == "table" then
                    for key, value in pairs(overrides) do cfg[key] = value end
                end
                local part = create("Part", nil)
                part.Name = "FacilityWeather"
                part.Anchored = true
                part.CanCollide, part.CanTouch, part.CanQuery, part.CastShadow = false, false, false, false
                part.Transparency = 1
                part.Size = Vector3.new(40, 1, 85)
                local emitter = Instance.new("ParticleEmitter", part)
                applyparticle(emitter, cfg)
                table.insert(parts, part)
            end
        end
        local function follow()
            local camera = workspace.CurrentCamera
            for _, part in ipairs(parts) do
                if camera then part.Position = camera.CFrame.Position + Vector3.new(0, 20, 0) end
                part.Parent = camera and workspace or nil
            end
        end
        follow()
        local conn = RunService.RenderStepped:Connect(follow)
        defer(function() conn:Disconnect() end)
    end)
end

-- Dark (boolean), Transparency (0..1), Smooth (hide source texture 7658055825).
function Visual:SetTextures(options)
    configure("Textures", options, function(cfg, defer, write)
        local function apply(obj)
            if obj:FindFirstAncestorOfClass("Camera") then return end
            local ancestor = obj.Parent
            while ancestor and ancestor ~= workspace do
                if ancestor:IsA("Model") and ancestor:FindFirstChildOfClass("Humanoid") then return end
                if ancestor.Name == "ViewModels" or ancestor.Name == "Effects" then return end
                ancestor = ancestor.Parent
            end
            if obj:IsA("BasePart") then
                if cfg.Dark then write(obj, "Color", obj.Color:Lerp(Color3.new(0, 0, 0), 0.55)) end
                if cfg.Transparency and obj.Transparency < 0.95 then
                    write(obj, "LocalTransparencyModifier", math.clamp(cfg.Transparency, 0, 1))
                end
            elseif cfg.Smooth and obj:IsA("Decal") then
                if string.find(obj.Texture, "7658055825", 1, true) then write(obj, "Transparency", 1) end
            elseif cfg.Smooth and obj:IsA("SurfaceAppearance") then
                for _, key in ipairs({"ColorMap", "NormalMap", "MetalnessMap", "RoughnessMap"}) do
                    pcall(function()
                        if string.find(obj[key], "7658055825", 1, true) then write(obj, key, "") end
                    end)
                end
            end
        end
        for _, obj in ipairs(workspace:GetDescendants()) do apply(obj) end
        local conn = workspace.DescendantAdded:Connect(apply)
        defer(function() conn:Disconnect() end)
    end)
end

local cameraBind = "FacilityVisual_" .. game:GetService("HttpService"):GenerateGUID(false)

-- AspectRatio is X/Y (13/10 in the source). Blur defaults to amount 8 and gain 2.
function Visual:SetCamera(options)
    configure("Camera", options, function(cfg, defer, _, create)
        local blur = cfg.MotionBlur and create("BlurEffect", Lighting)
        if blur then blur.Size = 0 end
        local lastCamera, original, applied, direction
        local function restore()
            if lastCamera and applied and lastCamera.CFrame == applied then lastCamera.CFrame = original end
            applied = nil
        end
        local function render()
            local camera = workspace.CurrentCamera
            if not camera then return end
            if lastCamera ~= camera then direction = nil end
            lastCamera = camera
            original = camera.CFrame
            if blur then
                local look = original.LookVector
                blur.Size = direction and math.clamp((look - direction).Magnitude * (cfg.Amount or 8) * (cfg.Gain or 2) / 2, 0, 56) or 0
                direction = look
            end
            if cfg.AspectRatio then
                camera.CFrame = CFrame.fromMatrix(original.Position, original.RightVector, original.UpVector * cfg.AspectRatio, -original.LookVector)
                applied = camera.CFrame
            end
        end
        defer(restore)
        for _, entry in ipairs({{"Before", -1, restore}, {"After", 2, render}}) do
            local name = cameraBind .. entry[1]
            RunService:BindToRenderStep(name, Enum.RenderPriority.Camera.Value + entry[2], entry[3])
            defer(function() RunService:UnbindFromRenderStep(name) end)
        end
    end)
end

local combat
local transient = {}
local function impactObject(class, parent)
    local obj = Instance.new(class)
    transient[obj] = true
    obj.Destroying:Connect(function() transient[obj] = nil end)
    obj.Parent = parent
    return obj
end

local function getHitEffectPart(adornee)
    if adornee:IsA("BasePart") then
        return adornee
    elseif adornee:IsA("Attachment") then
        return adornee.Parent
    elseif adornee:IsA("Model") and adornee.PrimaryPart then
        return adornee.PrimaryPart
    end
end

local function blendHitColor(base, amount)
    amount = amount or 0.35
    return Color3.new(
        math.clamp(base.R + amount, 0, 1),
        math.clamp(base.G + amount * 0.5, 0, 1),
        math.clamp(base.B + amount * 0.25, 0, 1)
    )
end

local function darkenHitColor(base, amount)
    amount = amount or 0.45
    return Color3.new(
        math.clamp(base.R - amount, 0, 1),
        math.clamp(base.G - amount, 0, 1),
        math.clamp(base.B - amount * 0.5, 0, 1)
    )
end

local function getHitEffectAliveScale()
    return (combat.Impacts.Duration or 2.8) / 2.8
end

local function scaleHitDuration(seconds)
    return seconds * getHitEffectAliveScale()
end



local function spawnHitRing(targetPart, color, config)
    config = config or {}
    local ring = impactObject("Part")
    ring.Name = config.Name or "HitRing"
    ring.Shape = Enum.PartType.Cylinder
    ring.Anchored = true
    ring.CanCollide = false
    ring.CanQuery = false
    ring.CanTouch = false
    ring.Material = config.Material or Enum.Material.Neon
    ring.Color = color
    ring.Transparency = config.StartTransparency or 0.35
    local startSize = config.StartSize or 0.35
    ring.Size = Vector3.new(0.05, startSize, startSize)
    ring.CFrame = targetPart.CFrame * CFrame.Angles(0, 0, math.rad(90))
    ring.Parent = workspace.CurrentCamera
    local endSize = config.EndSize or 5
    local duration = scaleHitDuration(config.Duration or 0.55)
    TweenService:Create(ring, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Size = Vector3.new(0.05, endSize, endSize),
        Transparency = 1
    }):Play()
    task.delay(duration + 0.1, function()
        if ring and ring.Parent then ring:Destroy() end
    end)
    return ring
end

local function spawnHitFlash(targetPart, color, brightness, range, duration)
    duration = scaleHitDuration(duration or 0.35)
    local light = impactObject("PointLight")
    light.Name = "HitFlash"
    light.Color = color
    light.Brightness = brightness or 6
    light.Range = range or 14
    light.Parent = targetPart
    TweenService:Create(light, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Brightness = 0,
        Range = 0
    }):Play()
    task.delay(duration + 0.05, function()
        if light and light.Parent then light:Destroy() end
    end)
end

local MAX_ACTIVE_PARTICLES = 120
local getActiveParticles
local function spawnHitEmitter(targetPart, config)
    if getActiveParticles() >= MAX_ACTIVE_PARTICLES then
        return nil
    end

    local emitter = impactObject("ParticleEmitter")
    emitter.Name = config.Name or "HitEffect"
    emitter.Texture = config.Texture or "rbxassetid://6603835352"
    if typeof(config.Color) == "ColorSequence" then
        emitter.Color = config.Color
    else
        emitter.Color = ColorSequence.new(config.Color or combat.Impacts.Color or Color3.fromRGB(159, 133, 195))
    end
    emitter.LightEmission = config.LightEmission or 1
    emitter.Brightness = config.Brightness or 8
    emitter.LightInfluence = config.LightInfluence or 0
    emitter.Orientation = config.Orientation or Enum.ParticleOrientation.FacingCamera
    emitter.LockedToPart = config.LockedToPart or false
    emitter.Size = config.Size or NumberSequence.new(0.12)
    emitter.Transparency = config.Transparency or NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0),
        NumberSequenceKeypoint.new(1, 1)
    })
    emitter.Speed = config.Speed or NumberRange.new(12, 18)
    emitter.SpreadAngle = config.SpreadAngle or Vector2.new(120, 120)
    emitter.EmissionDirection = config.EmissionDirection or Enum.NormalId.Top
    local lifetime = config.Lifetime or NumberRange.new(0.6, 1.2)
    local aliveScale = getHitEffectAliveScale()
    emitter.Lifetime = NumberRange.new(lifetime.Min * aliveScale, lifetime.Max * aliveScale)
    emitter.Drag = config.Drag or 2
    emitter.Acceleration = config.Acceleration or Vector3.new(0, 4, 0)
    emitter.RotSpeed = config.RotSpeed or NumberRange.new(0, 0)
    emitter.Rate = 0
    emitter.Enabled = true
    emitter.Parent = targetPart
    emitter:Emit(config.EmitCount or 48)
    task.delay(scaleHitDuration(config.Cleanup or 4), function()
        if emitter and emitter.Parent then emitter:Destroy() end
    end)
end

local function particledesign(adornee, color)
    color = color or combat.Impacts.Color or Color3.fromRGB(159, 133, 195)
    local targetPart = getHitEffectPart(adornee)
    if not targetPart or not targetPart:IsA("BasePart") then return end

    local emitter = impactObject("ParticleEmitter")
    emitter.Name = "TinyGlowingDots"
    emitter.Texture = "rbxassetid://6603835352"
    emitter.Color = ColorSequence.new(color)
    emitter.LightEmission = 1
    emitter.Brightness = 13
    emitter.LightInfluence = 0
    emitter.Orientation = Enum.ParticleOrientation.FacingCamera
    emitter.LockedToPart = false
    emitter.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.09),
        NumberSequenceKeypoint.new(0.5, 0.135),
        NumberSequenceKeypoint.new(1, 0.068)
    })
    emitter.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0),
        NumberSequenceKeypoint.new(0.25, 0),
        NumberSequenceKeypoint.new(1, 1)
    })
    emitter.Speed = NumberRange.new(22, 29)
    emitter.SpreadAngle = Vector2.new(130, 130)
    emitter.EmissionDirection = Enum.NormalId.Top
    local particleLife = scaleHitDuration(4)
    emitter.Lifetime = NumberRange.new(particleLife, particleLife + 0.1)
    emitter.Drag = 3.2
    emitter.Acceleration = Vector3.new(0, 5, 0)
    emitter.Rate = 0
    emitter.Enabled = true
    emitter.Parent = targetPart
    emitter:Emit(64)

    task.delay(scaleHitDuration(5), function()
        if emitter and emitter.Parent then emitter:Destroy() end
    end)
end

local activeposes = {}
local MIN_DIST = 5.5
local MAX_ACTIVE_HIT_EFFECTS = 45


local X_MIN, X_MAX = -10, 10
local Y_MIN, Y_MAX = 1, 8
local Z_MIN, Z_MAX = -4, 4

local function randFloat(min, max)
    return min + math.random() * (max - min)
end

local function pickpos(key)
    local occupied = activeposes[key] or {}
    local best = nil
    local bestDist = -1

    for attempt = 1, 60 do
        local candidate = Vector3.new(
            randFloat(X_MIN, X_MAX),
            randFloat(Y_MIN, Y_MAX),
            randFloat(Z_MIN, Z_MAX)
        )

        local minDist = math.huge
        for _, pos in ipairs(occupied) do
            local d = (candidate - pos).Magnitude
            if d < minDist then minDist = d end
        end

        if minDist >= MIN_DIST then
            return candidate
        end

        if minDist > bestDist then
            bestDist = minDist
            best = candidate
        end
    end

    return best
end

local function getActiveFortniteBillboards()
    local count = 0
    for _, child in ipairs(workspace.CurrentCamera:GetChildren()) do
        if child:IsA("BillboardGui") and child.Name == "FortniteDamageNumber" then
            count = count + 1
        end
    end
    return count
end

getActiveParticles = function()
    local count = 0
    for obj in pairs(transient) do
        if obj:IsA("ParticleEmitter") then count = count + 1 end
    end
    return count
end

local function fortniteffect(adornee, color, damageText)
    color = color or combat.Impacts.Color or Color3.fromRGB(159, 133, 195)

    local currentBbs = getActiveFortniteBillboards()
    if currentBbs >= MAX_ACTIVE_HIT_EFFECTS then
        return
    end

    local targetPart = nil
    if adornee:IsA("BasePart") then
        targetPart = adornee
    elseif adornee:IsA("Model") and adornee.PrimaryPart then
        targetPart = adornee.PrimaryPart
    end
    if not targetPart then return end

    local key = targetPart
    if not activeposes[key] then activeposes[key] = {} end

    local offset2 = pickpos(key)
    local floatHeight = combat.Impacts.FloatHeight or 7
    local aliveDuration = combat.Impacts.Duration or 2.8
    local endOffset = offset2 + Vector3.new(0, floatHeight, 0)

    local posEntry = offset2
    table.insert(activeposes[key], posEntry)

    local bb = impactObject("BillboardGui")
    bb.Name = "FortniteDamageNumber"
    bb.Size = UDim2.new(0, 70, 0, 40)
    bb.StudsOffset = offset2
    bb.AlwaysOnTop = true
    bb.LightInfluence = 0
    bb.Adornee = targetPart
    bb.Parent = workspace.CurrentCamera

    local lbl = impactObject("TextLabel", bb)
    lbl.Size = UDim2.new(1, 0, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = damageText
    lbl.TextColor3 = color
    lbl.TextTransparency = 1
    lbl.TextStrokeColor3 = Color3.new(0, 0, 0)
    lbl.TextStrokeTransparency = 1
    lbl.TextScaled = true
    lbl.Font = Enum.Font.GothamBold
    lbl.ZIndex = 1

    local fadeOutTime = scaleHitDuration(0.5)
    TweenService:Create(lbl, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {TextTransparency = 0, TextStrokeTransparency = 0.55}):Play()
    TweenService:Create(bb, TweenInfo.new(aliveDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {StudsOffset = endOffset}):Play()

    task.delay(aliveDuration, function()
        if not bb or not bb.Parent then return end
        TweenService:Create(lbl, TweenInfo.new(fadeOutTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {TextTransparency = 1, TextStrokeTransparency = 1}):Play()
        task.delay(fadeOutTime + 0.02, function()
            if bb and bb.Parent then bb:Destroy() end
            if activeposes[key] then
                for i, pos in ipairs(activeposes[key]) do
                    if pos == posEntry then
                        table.remove(activeposes[key], i)
                        break
                    end
                end
                if #activeposes[key] == 0 then
                    activeposes[key] = nil
                end
            end
        end)
    end)
end

local function shockwaveEffect(adornee, color)
    local targetPart = getHitEffectPart(adornee)
    if not targetPart then return end
    spawnHitFlash(targetPart, color, 8, 18, 0.4)
    spawnHitRing(targetPart, color, {Name = "ShockwaveRing", StartSize = 0.5, EndSize = 7, Duration = 0.5})
    spawnHitRing(targetPart, blendHitColor(color, 0.2), {Name = "ShockwaveRing2", StartSize = 0.25, EndSize = 5, Duration = 0.35, StartTransparency = 0.55})
    spawnHitEmitter(targetPart, {
        Name = "ShockwaveBurst",
        Texture = "rbxassetid://243660364",
        Color = color,
        EmitCount = 28,
        Speed = NumberRange.new(14, 24),
        SpreadAngle = Vector2.new(180, 180),
        EmissionDirection = Enum.NormalId.Front,
        Lifetime = NumberRange.new(0.25, 0.45),
        Drag = 5,
        Size = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.35),
            NumberSequenceKeypoint.new(1, 0.05)
        }),
        Cleanup = 1.5,
    })
end

local function lightningEffect(adornee, color)
    local targetPart = getHitEffectPart(adornee)
    if not targetPart then return end
    local boltColor = Color3.new(0.85, 0.92, 1)
    spawnHitFlash(targetPart, boltColor, 14, 22, 0.2)
    spawnHitEmitter(targetPart, {
        Name = "LightningCore",
        Texture = "rbxassetid://446111271",
        Color = boltColor,
        Brightness = 16,
        EmitCount = 22,
        Speed = NumberRange.new(32, 48),
        SpreadAngle = Vector2.new(18, 18),
        Lifetime = NumberRange.new(0.08, 0.22),
        Drag = 0.2,
        Acceleration = Vector3.new(0, -20, 0),
        Cleanup = 1,
    })
    spawnHitEmitter(targetPart, {
        Name = "LightningArcs",
        Texture = "rbxassetid://12781852245",
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, boltColor),
            ColorSequenceKeypoint.new(0.5, color),
            ColorSequenceKeypoint.new(1, boltColor)
        }),
        Brightness = 12,
        EmitCount = 40,
        Speed = NumberRange.new(20, 38),
        SpreadAngle = Vector2.new(120, 120),
        Lifetime = NumberRange.new(0.12, 0.35),
        Drag = 1,
        Acceleration = Vector3.new(0, -14, 0),
        Cleanup = 1.5,
    })
end

local function bloodEffect(adornee, color)
    local targetPart = getHitEffectPart(adornee)
    if not targetPart then return end
    local bloodColor = Color3.new(math.clamp(color.R * 0.9 + 0.35, 0, 1), math.clamp(color.G * 0.15, 0, 0.35), math.clamp(color.B * 0.15, 0, 0.35))
    spawnHitEmitter(targetPart, {
        Name = "BloodSplatter",
        Texture = "rbxassetid://243660364",
        Color = bloodColor,
        EmitCount = 70,
        Speed = NumberRange.new(12, 28),
        SpreadAngle = Vector2.new(175, 175),
        Lifetime = NumberRange.new(0.7, 1.3),
        Drag = 5,
        Acceleration = Vector3.new(0, -22, 0),
        Size = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.22),
            NumberSequenceKeypoint.new(0.6, 0.14),
            NumberSequenceKeypoint.new(1, 0.04)
        }),
    })
    spawnHitEmitter(targetPart, {
        Name = "BloodMist",
        Texture = "rbxassetid://6603835352",
        Color = darkenHitColor(bloodColor, 0.15),
        EmitCount = 20,
        Speed = NumberRange.new(4, 10),
        SpreadAngle = Vector2.new(180, 180),
        Lifetime = NumberRange.new(0.4, 0.8),
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.35),
            NumberSequenceKeypoint.new(1, 1)
        }),
        Size = NumberSequence.new(0.5),
        Cleanup = 2,
    })
end

local function fireEffect(adornee, color)
    local targetPart = getHitEffectPart(adornee)
    if not targetPart then return end
    local fireCore = Color3.new(math.clamp(color.R + 0.25, 0, 1), math.clamp(color.G * 0.6 + 0.2, 0, 1), math.clamp(color.B * 0.2, 0, 0.4))
    spawnHitFlash(targetPart, fireCore, 10, 16, 0.45)
    spawnHitEmitter(targetPart, {
        Name = "FireFlames",
        Texture = "rbxassetid://241650108",
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 240, 120)),
            ColorSequenceKeypoint.new(0.45, fireCore),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(120, 20, 10))
        }),
        EmitCount = 55,
        Speed = NumberRange.new(8, 18),
        SpreadAngle = Vector2.new(70, 70),
        Lifetime = NumberRange.new(0.45, 0.95),
        Acceleration = Vector3.new(0, 14, 0),
        LightEmission = 1,
        Brightness = 14,
        Size = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.5),
            NumberSequenceKeypoint.new(1, 0.05)
        }),
    })
    spawnHitEmitter(targetPart, {
        Name = "FireEmbers",
        Texture = "rbxassetid://12781852245",
        Color = fireCore,
        EmitCount = 25,
        Speed = NumberRange.new(14, 26),
        SpreadAngle = Vector2.new(180, 180),
        Lifetime = NumberRange.new(0.6, 1.1),
        Drag = 2,
        Acceleration = Vector3.new(0, 6, 0),
        Cleanup = 2.5,
    })
end

local function iceEffect(adornee, color)
    local targetPart = getHitEffectPart(adornee)
    if not targetPart then return end
    local iceColor = Color3.new(
        math.clamp(color.R * 0.35 + 0.55, 0, 1),
        math.clamp(color.G * 0.5 + 0.55, 0, 1),
        math.clamp(color.B * 0.4 + 0.75, 0, 1)
    )
    spawnHitFlash(targetPart, iceColor, 6, 12, 0.35)
    spawnHitEmitter(targetPart, {
        Name = "IceShards",
        Texture = "rbxassetid://243660364",
        Color = iceColor,
        EmitCount = 48,
        Speed = NumberRange.new(10, 20),
        SpreadAngle = Vector2.new(110, 110),
        Lifetime = NumberRange.new(0.9, 1.5),
        Drag = 1.5,
        RotSpeed = NumberRange.new(-180, 180),
        Acceleration = Vector3.new(0, -6, 0),
        Size = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.28),
            NumberSequenceKeypoint.new(1, 0.06)
        }),
    })
    spawnHitEmitter(targetPart, {
        Name = "IceFrost",
        Texture = "rbxassetid://6603835352",
        Color = Color3.new(1, 1, 1),
        EmitCount = 24,
        Speed = NumberRange.new(2, 6),
        SpreadAngle = Vector2.new(180, 180),
        Lifetime = NumberRange.new(1.2, 1.8),
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.5),
            NumberSequenceKeypoint.new(1, 1)
        }),
        Size = NumberSequence.new(0.4),
        Cleanup = 2.5,
    })
end

local function heartsEffect(adornee, color)
    local targetPart = getHitEffectPart(adornee)
    if not targetPart then return end
    local heartColor = Color3.new(math.clamp(color.R + 0.15, 0, 1), math.clamp(color.G * 0.35 + 0.2, 0, 1), math.clamp(color.B * 0.4 + 0.35, 0, 1))
    spawnHitEmitter(targetPart, {
        Name = "HeartsHit",
        Texture = "rbxassetid://120777973",
        Color = heartColor,
        EmitCount = 24,
        Speed = NumberRange.new(5, 12),
        SpreadAngle = Vector2.new(55, 55),
        Lifetime = NumberRange.new(1.1, 1.9),
        Acceleration = Vector3.new(0, 8, 0),
        Drag = 1,
        Size = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.45),
            NumberSequenceKeypoint.new(1, 0.2)
        }),
        LightEmission = 0.6,
    })
end

local function starsEffect(adornee, color)
    local targetPart = getHitEffectPart(adornee)
    if not targetPart then return end
    spawnHitFlash(targetPart, color, 7, 14, 0.3)
    spawnHitEmitter(targetPart, {
        Name = "StarsBurst",
        Texture = "rbxassetid://1084982556",
        Color = color,
        EmitCount = 40,
        Speed = NumberRange.new(16, 28),
        SpreadAngle = Vector2.new(180, 180),
        Lifetime = NumberRange.new(0.6, 1.05),
        RotSpeed = NumberRange.new(-240, 240),
        Brightness = 12,
        Size = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.4),
            NumberSequenceKeypoint.new(1, 0.1)
        }),
    })
end

local function confettiEffect(adornee, color)
    local targetPart = getHitEffectPart(adornee)
    if not targetPart then return end
    local c2 = blendHitColor(color, 0.3)
    local c3 = Color3.new(color.G, color.B, color.R)
    spawnHitEmitter(targetPart, {
        Name = "ConfettiHit",
        Texture = "rbxassetid://243660364",
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, color),
            ColorSequenceKeypoint.new(0.33, c2),
            ColorSequenceKeypoint.new(0.66, c3),
            ColorSequenceKeypoint.new(1, blendHitColor(c2, 0.2))
        }),
        EmitCount = 80,
        Speed = NumberRange.new(14, 30),
        SpreadAngle = Vector2.new(180, 180),
        Lifetime = NumberRange.new(1.4, 2.4),
        Drag = 2.5,
        Acceleration = Vector3.new(0, -10, 0),
        RotSpeed = NumberRange.new(-420, 420),
        Size = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.22),
            NumberSequenceKeypoint.new(1, 0.08)
        }),
    })
end

local function rippleEffect(adornee, color)
    local targetPart = getHitEffectPart(adornee)
    if not targetPart then return end
    spawnHitRing(targetPart, color, {Name = "RippleHit1", StartSize = 0.3, EndSize = 4.5, Duration = 0.45, StartTransparency = 0.3})
    task.delay(0.12, function()
        if targetPart and targetPart.Parent then
            spawnHitRing(targetPart, blendHitColor(color, 0.15), {Name = "RippleHit2", StartSize = 0.2, EndSize = 6.5, Duration = 0.65, StartTransparency = 0.5})
        end
    end)
    spawnHitEmitter(targetPart, {
        Name = "RippleDroplets",
        Texture = "rbxassetid://6603835352",
        Color = color,
        EmitCount = 16,
        Speed = NumberRange.new(6, 12),
        SpreadAngle = Vector2.new(180, 180),
        Lifetime = NumberRange.new(0.5, 0.9),
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.2),
            NumberSequenceKeypoint.new(1, 1)
        }),
        Size = NumberSequence.new(0.12),
        Cleanup = 2,
    })
end

local function sparksEffect(adornee, color)
    local targetPart = getHitEffectPart(adornee)
    if not targetPart then return end
    spawnHitFlash(targetPart, color, 9, 12, 0.25)
    spawnHitEmitter(targetPart, {
        Name = "SparksHit",
        Texture = "rbxassetid://12781852245",
        Color = color,
        EmitCount = 65,
        Speed = NumberRange.new(22, 42),
        SpreadAngle = Vector2.new(180, 180),
        Lifetime = NumberRange.new(0.18, 0.5),
        Drag = 4,
        Brightness = 14,
        LightEmission = 1,
        Acceleration = Vector3.new(0, -16, 0),
    })
    spawnHitEmitter(targetPart, {
        Name = "SparksGlow",
        Texture = "rbxassetid://6603835352",
        Color = blendHitColor(color, 0.4),
        EmitCount = 12,
        Speed = NumberRange.new(4, 8),
        SpreadAngle = Vector2.new(180, 180),
        Lifetime = NumberRange.new(0.35, 0.6),
        Size = NumberSequence.new(0.25),
        Cleanup = 1.5,
    })
end

local function neonPulseEffect(adornee, color)
    local targetPart = getHitEffectPart(adornee)
    if not targetPart then return end
    spawnHitFlash(targetPart, color, 16, 20, 0.5)
    spawnHitRing(targetPart, color, {Name = "NeonPulseRing", StartSize = 0.15, EndSize = 4, Duration = 0.35, StartTransparency = 0.15})
    spawnHitEmitter(targetPart, {
        Name = "NeonPulseCore",
        Texture = "rbxassetid://6603835352",
        Color = color,
        Brightness = 16,
        LightEmission = 1,
        EmitCount = 50,
        Speed = NumberRange.new(4, 10),
        SpreadAngle = Vector2.new(180, 180),
        Lifetime = NumberRange.new(0.5, 0.9),
        Size = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.6),
            NumberSequenceKeypoint.new(0.5, 0.35),
            NumberSequenceKeypoint.new(1, 0)
        }),
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0),
            NumberSequenceKeypoint.new(1, 1)
        }),
    })
end

local function voidRiftEffect(adornee, color)
    local targetPart = getHitEffectPart(adornee)
    if not targetPart then return end
    local voidCore = darkenHitColor(color, 0.55)
    local voidEdge = blendHitColor(color, 0.1)
    spawnHitEmitter(targetPart, {
        Name = "VoidRiftCore",
        Texture = "rbxassetid://243660364",
        Color = voidCore,
        EmitCount = 35,
        Speed = NumberRange.new(2, 8),
        SpreadAngle = Vector2.new(180, 180),
        EmissionDirection = Enum.NormalId.Bottom,
        Lifetime = NumberRange.new(0.8, 1.4),
        Drag = 3,
        Acceleration = Vector3.new(0, -14, 0),
        Size = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.5),
            NumberSequenceKeypoint.new(1, 0.1)
        }),
        LightEmission = 0.2,
        Brightness = 2,
    })
    spawnHitEmitter(targetPart, {
        Name = "VoidRiftEdge",
        Texture = "rbxassetid://446111271",
        Color = voidEdge,
        EmitCount = 45,
        Speed = NumberRange.new(10, 22),
        SpreadAngle = Vector2.new(180, 180),
        Lifetime = NumberRange.new(0.4, 0.85),
        RotSpeed = NumberRange.new(-300, 300),
        Brightness = 10,
        LightEmission = 1,
        Cleanup = 2,
    })
end

local function plasmaEffect(adornee, color)
    local targetPart = getHitEffectPart(adornee)
    if not targetPart then return end
    local plasmaB = Color3.new(math.clamp(1 - color.R, 0, 1), math.clamp(color.G, 0, 1), math.clamp(color.B + 0.3, 0, 1))
    spawnHitFlash(targetPart, color, 12, 18, 0.35)
    spawnHitEmitter(targetPart, {
        Name = "PlasmaCore",
        Texture = "rbxassetid://446111271",
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, color),
            ColorSequenceKeypoint.new(0.5, plasmaB),
            ColorSequenceKeypoint.new(1, color)
        }),
        Brightness = 15,
        EmitCount = 55,
        Speed = NumberRange.new(6, 16),
        SpreadAngle = Vector2.new(180, 180),
        Lifetime = NumberRange.new(0.35, 0.7),
        Size = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.55),
            NumberSequenceKeypoint.new(1, 0.08)
        }),
        LightEmission = 1,
    })
    spawnHitRing(targetPart, plasmaB, {Name = "PlasmaRing", StartSize = 0.4, EndSize = 5.5, Duration = 0.4, StartTransparency = 0.25})
end

local function glitchEffect(adornee, color)
    local targetPart = getHitEffectPart(adornee)
    if not targetPart then return end
    for i = 1, 6 do
        spawnHitEmitter(targetPart, {
            Name = "GlitchShard" .. i,
            Texture = "rbxassetid://243660364",
            Color = (i % 2 == 0) and color or blendHitColor(color, 0.5),
            EmitCount = 8,
            Speed = NumberRange.new(18, 32),
            SpreadAngle = Vector2.new(40, 40),
            EmissionDirection = Enum.NormalId.Top,
            Lifetime = NumberRange.new(0.1, 0.25),
            Drag = 0,
            RotSpeed = NumberRange.new(-500, 500),
            Size = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0.35),
                NumberSequenceKeypoint.new(1, 0.1)
            }),
            Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, math.random() * 0.4),
                NumberSequenceKeypoint.new(1, 1)
            }),
            Cleanup = 0.8,
        })
    end
    spawnHitFlash(targetPart, blendHitColor(color, 0.6), 8, 10, 0.15)
end

local function cosmicDustEffect(adornee, color)
    local targetPart = getHitEffectPart(adornee)
    if not targetPart then return end
    spawnHitFlash(targetPart, blendHitColor(color, 0.25), 5, 16, 0.6)
    spawnHitEmitter(targetPart, {
        Name = "CosmicDust",
        Texture = "rbxassetid://1084982556",
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
            ColorSequenceKeypoint.new(0.4, color),
            ColorSequenceKeypoint.new(1, darkenHitColor(color, 0.2))
        }),
        EmitCount = 60,
        Speed = NumberRange.new(3, 14),
        SpreadAngle = Vector2.new(180, 180),
        Lifetime = NumberRange.new(1.2, 2),
        Drag = 0.5,
        Acceleration = Vector3.new(0, 2, 0),
        RotSpeed = NumberRange.new(-80, 80),
        Brightness = 9,
        Size = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.08),
            NumberSequenceKeypoint.new(0.5, 0.18),
            NumberSequenceKeypoint.new(1, 0.04)
        }),
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.1),
            NumberSequenceKeypoint.new(1, 1)
        }),
    })
    spawnHitRing(targetPart, blendHitColor(color, 0.1), {Name = "CosmicRing", StartSize = 0.2, EndSize = 3.5, Duration = 0.8, StartTransparency = 0.65, Material = Enum.Material.Glass})
end

local hitEffectHandlers = {
    Particles = particledesign,
    Fortnite = fortniteffect,
    Shockwave = shockwaveEffect,
    Lightning = lightningEffect,
    Blood = bloodEffect,
    Fire = fireEffect,
    Ice = iceEffect,
    Hearts = heartsEffect,
    Stars = starsEffect,
    Confetti = confettiEffect,
    Ripple = rippleEffect,
    Sparks = sparksEffect,
    Neon = neonPulseEffect,
    Void = voidRiftEffect,
    Plasma = plasmaEffect,
    Glitch = glitchEffect,
    CosmicDust = cosmicDustEffect,
}
local textureAssets = {
    Line      = "",
    Beam      = "rbxassetid://12781852245",
    Lightning = "rbxassetid://446111271",
    Heartrate = "rbxassetid://5830549480",
    Chain     = "rbxassetid://9632168658",
    Glitch    = "rbxassetid://8089467613",
    Swirl     = "rbxassetid://5638168605",
    Neon      = "rbxassetid://6361963422",
    Plasma    = "rbxassetid://8993645509",
    Laser     = "rbxassetid://14549123968",
}
local function hnEaseOutCubic(t)
    return 1 - (1 - t) ^ 3
end

local function hnEaseInCubic(t)
    return t * t * t
end

local function hnEaseOutBack(t)
    local c1 = 1.70158
    return 1 + (c1 + 1) * (t - 1) ^ 3 + c1 * (t - 1) ^ 2
end

local HIT_NOTIF_IN_SAMPLERS = {}
local HIT_NOTIF_OUT_SAMPLERS = {}

HIT_NOTIF_IN_SAMPLERS.fade = function(t)
    return hnEaseOutCubic(t), 0, 0, 1
end
HIT_NOTIF_IN_SAMPLERS["slide left"] = function(t)
    local e = hnEaseOutCubic(t)
    return e, (1 - e) * -52, 0, 1
end
HIT_NOTIF_IN_SAMPLERS["slide right"] = function(t)
    local e = hnEaseOutCubic(t)
    return e, (1 - e) * 52, 0, 1
end
HIT_NOTIF_IN_SAMPLERS["slide down"] = function(t)
    local e = hnEaseOutCubic(t)
    return e, 0, (1 - e) * -32, 1
end
HIT_NOTIF_IN_SAMPLERS.bounce = function(t)
    return math.clamp(t * 6, 0, 1), 0, 0, hnEaseOutBack(t)
end
HIT_NOTIF_IN_SAMPLERS["fade bounce"] = function(t)
    return hnEaseOutCubic(t), 0, 0, 0.78 + hnEaseOutBack(t) * 0.28
end
HIT_NOTIF_IN_SAMPLERS.scale = function(t)
    local e = hnEaseOutCubic(t)
    return e, 0, 0, 0.62 + e * 0.38
end

HIT_NOTIF_OUT_SAMPLERS.fade = function(t)
    local e = hnEaseInCubic(t)
    return 1 - e, 0, 0, 1
end
HIT_NOTIF_OUT_SAMPLERS["slide left"] = function(t)
    local e = hnEaseInCubic(t)
    return 1 - e, e * -52, 0, 1
end
HIT_NOTIF_OUT_SAMPLERS["slide right"] = function(t)
    local e = hnEaseInCubic(t)
    return 1 - e, e * 52, 0, 1
end
HIT_NOTIF_OUT_SAMPLERS["slide down"] = function(t)
    local e = hnEaseInCubic(t)
    return 1 - e, 0, e * 32, 1
end
HIT_NOTIF_OUT_SAMPLERS.bounce = function(t)
    local e = hnEaseInCubic(t)
    return 1 - e, 0, 0, 1 - e * 0.1 + math.sin(t * math.pi) * 0.09 * (1 - e)
end
HIT_NOTIF_OUT_SAMPLERS["fade bounce"] = function(t)
    local e = hnEaseInCubic(t)
    return 1 - e, 0, 0, 1 - e * 0.08 + math.sin(t * math.pi * 1.5) * 0.07 * (1 - t)
end
HIT_NOTIF_OUT_SAMPLERS.scale = function(t)
    local e = hnEaseInCubic(t)
    return 1 - e, 0, 0, 1 - e * 0.4
end

local function sampleHitNotifAnim(style, t, isOut)
    t = math.clamp(t, 0, 1)
    local map = isOut and HIT_NOTIF_OUT_SAMPLERS or HIT_NOTIF_IN_SAMPLERS
    local fn = map[string.lower(style or "fade")] or map.fade
    local a, ox, oy, sc = fn(t)
    return math.clamp(a, 0, 1), ox, oy, math.clamp(sc, 0.01, 1.35)
end

local tracers, notices = {}, {}
local noticeGui

local function removeTracer(tracer)
    if tracer.line then
        tracer.line:Remove()
        tracer.outline:Remove()
    else
        tracer.beam:Destroy()
        tracer.start:Destroy()
        tracer.finish:Destroy()
    end
end

local function updateCombat()
    local now, camera = os.clock(), workspace.CurrentCamera
    for i = #tracers, 1, -1 do
        local tr = tracers[i]
        local age = now - tr.time
        if age >= tr.duration then
            removeTracer(tr)
            table.remove(tracers, i)
        else
            local alpha = tr.fade > 0 and math.clamp((tr.duration - age) / tr.fade, 0, 1) or 1
            local progress = tr.travel > 0 and math.min(1, age / tr.travel) or 1
            local finish = tr.origin:Lerp(tr.impact, progress)
            if tr.line then
                local visible = false
                if camera then
                    local a, aVisible = camera:WorldToViewportPoint(tr.origin)
                    local b, bVisible = camera:WorldToViewportPoint(finish)
                    visible = aVisible and bVisible
                    if visible then
                        for _, line in ipairs({tr.line, tr.outline}) do
                            line.From, line.To = Vector2.new(a.X, a.Y), Vector2.new(b.X, b.Y)
                            line.Transparency = alpha
                        end
                    end
                end
                tr.line.Visible, tr.outline.Visible = visible, visible
            else
                tr.finish.WorldPosition = finish
                tr.beam.Transparency = NumberSequence.new(1 - alpha)
            end
        end
    end
    for i = #notices, 1, -1 do
        local entry = notices[i]
        local cfg = combat.Notifications
        local age = now - entry.time
        local remaining = (cfg.Duration or 2) - age
        if remaining <= 0 then
            entry.label:Destroy()
            table.remove(notices, i)
        else
            local alpha, x, y, scale = 1, 0, 0, 1
            if remaining < 0.25 then
                alpha, x, y, scale = sampleHitNotifAnim(cfg.Out, 1 - remaining / 0.25, true)
            elseif age < 0.25 then
                alpha, x, y, scale = sampleHitNotifAnim(cfg.In or "fade bounce", age / 0.25, false)
            end
            entry.label.TextTransparency = 1 - alpha
            entry.label.TextStrokeTransparency = 1 - alpha * 0.65
            local size = cfg.Size or 16
            entry.label.TextSize = math.max(1, size * scale)
            entry.label.Position = (cfg.Position or UDim2.fromScale(0.5, 0.65))
                + UDim2.fromOffset(x, y + (i - 1) * (size + (cfg.Gap or 4)))
        end
    end
end

-- Tracers, Impacts and Notifications are optional settings tables.
function Visual:SetCombat(options)
    configure("Combat", options, function(cfg, defer, _, create)
        combat = cfg
        defer(function()
            combat = nil
            for _, tr in ipairs(tracers) do removeTracer(tr) end
            table.clear(tracers)
            table.clear(notices)
            for obj in pairs(transient) do obj:Destroy() end
            table.clear(activeposes)
            noticeGui = nil
        end)
        if cfg.Notifications then
            noticeGui = create("ScreenGui", Players.LocalPlayer:FindFirstChildOfClass("PlayerGui"))
            noticeGui.Name = "FacilityHitNotifications"
            noticeGui.ResetOnSpawn = false
        end
        if cfg.Tracers or cfg.Notifications then
            local conn = RunService.RenderStepped:Connect(updateCombat)
            defer(function() conn:Disconnect() end)
        end
        -- Optional adapter for games exposing damage through BillboardGui numbers.
        if cfg.ObserveDamageNumbers then
            local conn = workspace.DescendantAdded:Connect(function(obj)
                if not obj:IsA("BillboardGui") or obj.Name == "FortniteDamageNumber" then return end
                task.defer(function()
                    if combat ~= cfg or not obj.Parent then return end
                    local label = obj:FindFirstChildWhichIsA("TextLabel", true)
                    local value = label and tonumber(label.Text)
                    local target = obj.Adornee or obj.Parent
                    if value and value > 0 then self:Hit(target, value) end
                end)
            end)
            defer(function() conn:Disconnect() end)
        end
    end)
end

function Visual:DrawTracer(origin, impact)
    local cfg = combat and combat.Tracers
    if not cfg then return end
    assert(typeof(origin) == "Vector3" and typeof(impact) == "Vector3", "Expected world positions")
    local style = cfg.Style or "Line"
    assert(textureAssets[style], "Unknown tracer style")
    local size, color = cfg.Size or 1, cfg.Color or Color3.new(1, 1, 1)
    local tr = {origin = origin, impact = impact, time = os.clock(), duration = cfg.Duration or 3,
        fade = cfg.Fade or 0.5, travel = (cfg.LerpSpeed or 0) * 0.25}
    if style == "Line" then
        tr.outline = Drawing.new("Line")
        tr.outline.Color, tr.outline.Thickness = Color3.new(0, 0, 0), 4 * size
        tr.line = Drawing.new("Line")
        tr.line.Color, tr.line.Thickness = color, 2 * size
    else
        tr.start = Instance.new("Attachment", workspace.Terrain)
        tr.finish = Instance.new("Attachment", workspace.Terrain)
        tr.start.WorldPosition, tr.finish.WorldPosition = origin, origin
        local beam = Instance.new("Beam")
        tr.beam = beam
        beam.Attachment0, beam.Attachment1 = tr.start, tr.finish
        beam.Width0 = size * (style == "Laser" and 0.02 or 0.15)
        beam.Width1 = beam.Width0
        beam.FaceCamera, beam.Color = true, ColorSequence.new(color)
        beam.Texture, beam.TextureLength, beam.TextureSpeed = textureAssets[style], 4, 1
        beam.LightEmission, beam.LightInfluence = 0.8, 0.2
        beam.Parent = workspace.Terrain
    end
    table.insert(tracers, tr)
end

function Visual:Hit(target, damage)
    if not combat or typeof(target) ~= "Instance" or not workspace.CurrentCamera then return end
    local part = getHitEffectPart(target)
    if not part or not part:IsA("BasePart") then return end
    local cfg = combat.Impacts
    if cfg then
        local color = cfg.Color or Color3.fromRGB(159, 133, 195)
        for _, name in ipairs(cfg.Styles or {"Particles"}) do
            local handler = assert(hitEffectHandlers[name], "Unknown impact style")
            handler(part, color, damage and tostring(damage) or "Hit")
        end
    end
    cfg = combat.Notifications
    if cfg and noticeGui then
        while #notices >= math.max(1, cfg.Max or 4) do table.remove(notices, 1).label:Destroy() end
        local model = part:FindFirstAncestorOfClass("Model")
        local label = Instance.new("TextLabel")
        label.BackgroundTransparency = 1
        label.AnchorPoint, label.Size = Vector2.new(0.5, 0.5), UDim2.fromOffset(380, 32)
        label.Font = Enum.Font.Code
        label.Text = (model and model.Name or part.Name) .. "  " .. part.Name .. (damage and "  -" .. tostring(damage) or "")
        label.TextColor3 = cfg.Color or Color3.new(1, 1, 1)
        label.TextTransparency, label.TextStrokeTransparency = 1, 1
        label.Parent = noticeGui
        table.insert(notices, {label = label, time = os.clock()})
    end
end

function Visual:Unload()
    for _, group in ipairs({"Combat", "Camera", "Weather", "Textures", "World"}) do stop(group) end
end

return Visual
