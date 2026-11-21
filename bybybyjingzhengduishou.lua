--[[
=====================================================================
  Zaka Rivals Suite  v4.0  (Mobile First)
  Game : Rivals (Roblox / Nosniy Games)
  Exec : Delta 等支持 loadstring / Drawing / gethui / hookmetamethod
  UI   : 手机优先内置面板（悬浮球 + 大号触摸控件 + 六个分类）
         WindUI 可用时也会加载，窗口自动按屏幕缩放
  Phone: 右上角悬浮球开关面板 · 右侧快捷条（滑铲/飞行/穿墙/连跳/跳敌）
         飞行时左下出现摇杆，拖动即可移动
  PC   : 右Shift 面板 · C 滑铲 · F 飞行 · V 穿墙 · G 连跳
  模块 : ESP / 自瞄 / 静默 / 自动扳机 / 无后坐 / 无扩散 / 秒换弹
         变速(可抖动) / 飞行 / 穿墙 / 滑铲 / 连跳 / 瞬移敌人
         皮肤替换(本地可见·可染色·资源库扫描) / 世界视觉 / 相机 FOV
         反检测（属性锁定 + 实例隐藏 + 反踢 + 向量限幅 + 脚本屏蔽）
=====================================================================
]]

--=====================================================================
-- 1. 环境
--=====================================================================
local cloneref  = cloneref or function(o) return o end
local Players   = cloneref(game:GetService("Players"))
local RunService= cloneref(game:GetService("RunService"))
local UIS       = cloneref(game:GetService("UserInputService"))
local Tween     = cloneref(game:GetService("TweenService"))
local Workspace = cloneref(game:GetService("Workspace"))
local Http      = cloneref(game:GetService("HttpService"))

local LP = Players.LocalPlayer
while not LP do task.wait(0.1); LP = Players.LocalPlayer end

local isCaller  = checkcaller or function() return true end
local getMethod = getnamecallmethod or function() return "" end
local typeOf    = typeof or type
local setRO     = setreadonly or set_readonly
local hasHooks  = (getrawmetatable ~= nil) and (hookmetamethod ~= nil) and (setRO ~= nil)

local clamp = math.clamp or function(v, a, b)
    if v < a then return a elseif v > b then return b else return v end
end

local hasDrawing = pcall(function()
    local d = Drawing.new("Square")
    d:Remove()
end)

--=====================================================================
-- 2. 配置
--=====================================================================
local CFG_FILE = "ZakaRivals_cfg.json"

local C = {
    -- ESP
    esp = false, espBox = true, espName = true, espDist = true, espHP = true,
    espSkel = false, espChams = false, espWeapon = true, espTracer = false,
    espTeam = true, espMax = 900,
    -- 战斗
    aim = false, aimPart = "Head", aimFov = 130, aimSmooth = 40, aimVis = false,
    aimTeam = true, aimPred = 0.12, aimPriority = "距离",
    autoFire = false,
    silent = false, silentFov = 170, silentTeam = true,
    -- 移动
    speed = false, speedVal = 46, fly = false, flyVal = 55,
    noclip = false, slidePower = 92, jumpPower = 50, bhop = false,
    moveLimit = true, mobilePad = true,
    -- 反检测
    antiKick = true, propSpoof = true, lockProps = true, hideInst = true,
    scriptScan = true, scriptScanLoop = true, velCap = 60,

    -- 手机
    mobile = true, fab = true, padScale = 1, drawer = true,

    -- 视觉增强 (世界)
    wFullbright = false, wNoFog = false, wNoShadow = false, wAmbient = false,
    wFps = false, fpsCap = 240, wNoParticles = false,

    -- 战斗增强
    noRecoil = false, noSpread = false, autoTrigger = false, triggerFov = 40,
    triggerRange = 220, hitSound = false, instantReload = false,

    -- 相机
    camFov = 70, camZoom = 12, camThird = false, showStats = true,

    -- 皮肤
    speedJitter = false, autoRejoin = false,
    skin = false, skinAuto = true, skinMesh = "", skinTexture = "",
    skinColorMode = false, skinColorR = 255, skinColorG = 255, skinColorB = 255,
    skinMaterial = "保持", skinForceShow = false, skinNeon = false,
}

local function loadCfg()
    if not (isfile and readfile) then return end
    if not isfile(CFG_FILE) then return end
    local ok, data = pcall(function() return Http:JSONDecode(readfile(CFG_FILE)) end)
    if ok and type(data) == "table" then
        for k, v in pairs(data) do
            if C[k] ~= nil and type(v) == type(C[k]) then C[k] = v end
        end
    end
end

local function saveCfg()
    if not (writefile and isfile) then return end
    pcall(function() writefile(CFG_FILE, Http:JSONEncode(C)) end)
end

loadCfg()

--=====================================================================
-- 3. 工具
--=====================================================================
local function getChar(p) p = p or LP; return p.Character end
local function getHum(p)
    local ch = getChar(p)
    if ch then return ch:FindFirstChildOfClass("Humanoid") end
end
local function getHRP(p)
    local ch = getChar(p)
    if not ch then return nil end
    return ch:FindFirstChild("HumanoidRootPart") or ch.PrimaryPart
end
local function isAlive(p)
    local h = getHum(p)
    return h ~= nil and h.Health > 0
end
local function sameTeam(p)
    local a, b = p.Team, LP.Team
    if a == nil or b == nil then return false end
    return a == b
end

local baseSpeed, baseJump = 16, 50
do
    local h = getHum()
    if h then
        baseSpeed = h.WalkSpeed
        pcall(function() baseJump = h.JumpPower end)
    end
end

local hiddenInst = setmetatable({}, {__mode = "k"})
local notify = function() end
local uiCleanup = function() end
local panelToggle = function() end
local widgets = {}
local setWidget = function(name, value)
    local w = widgets[name]
    if w and w.Set then
        pcall(function() w:Set(value) end)
    end
end

--=====================================================================
-- 4. ESP
--=====================================================================
local ACCENT = Color3.fromRGB(0, 214, 255)
local VIS_ACCENT = Color3.fromRGB(180, 120, 255)
local espCache = {}
local chamCache = {}
local chamFolder = nil

local function ensureChamFolder()
    local cam = Workspace.CurrentCamera
    if not cam then return nil end
    if chamFolder and chamFolder.Parent then return chamFolder end
    chamFolder = Instance.new("Folder")
    chamFolder.Name = "Effects"
    chamFolder.Parent = cam
    return chamFolder
end

local BONES = {
    {"Head", "UpperTorso"}, {"UpperTorso", "LowerTorso"},
    {"UpperTorso", "LeftUpperArm"}, {"LeftUpperArm", "LeftLowerArm"}, {"LeftLowerArm", "LeftHand"},
    {"UpperTorso", "RightUpperArm"}, {"RightUpperArm", "RightLowerArm"}, {"RightLowerArm", "RightHand"},
    {"LowerTorso", "LeftUpperLeg"}, {"LeftUpperLeg", "LeftLowerLeg"}, {"LeftLowerLeg", "LeftFoot"},
    {"LowerTorso", "RightUpperLeg"}, {"RightUpperLeg", "RightLowerLeg"}, {"RightLowerLeg", "RightFoot"},
    {"Head", "Torso"}, {"Torso", "Left Arm"}, {"Torso", "Right Arm"},
    {"Torso", "Left Leg"}, {"Torso", "Right Leg"},
}

local function buildESP()
    local e = {draws = {}, lines = {}}
    local function n(kind, props)
        local d = Drawing.new(kind)
        if props then
            for k, v in pairs(props) do
                pcall(function() d[k] = v end)
            end
        end
        e.draws[#e.draws + 1] = d
        return d
    end
    e.box  = n("Square", {Filled = false, Thickness = 1, Transparency = 1, Color = ACCENT})
    e.bg   = n("Square", {Filled = false, Thickness = 1, Transparency = 0.65, Color = Color3.fromRGB(0, 0, 0)})
    e.name = n("Text", {Size = 14, Center = true, Outline = true, OutlineColor = Color3.fromRGB(0, 0, 0), Transparency = 1, Color = Color3.fromRGB(255, 255, 255)})
    e.dist = n("Text", {Size = 12, Center = true, Outline = true, OutlineColor = Color3.fromRGB(0, 0, 0), Transparency = 1, Color = ACCENT})
    e.wep  = n("Text", {Size = 11, Center = true, Outline = true, OutlineColor = Color3.fromRGB(0, 0, 0), Transparency = 1, Color = Color3.fromRGB(220, 220, 220)})
    e.hpBg = n("Square", {Filled = true, Thickness = 1, Transparency = 0.4, Color = Color3.fromRGB(20, 20, 24)})
    e.hp   = n("Square", {Filled = true, Thickness = 1, Transparency = 0.15, Color = Color3.fromRGB(60, 230, 140)})
    e.tracer = n("Line", {Thickness = 1, Transparency = 0.55, Color = ACCENT})
    for i = 1, #BONES do
        e.lines[i] = n("Line", {Thickness = 1, Transparency = 1, Color = ACCENT})
    end
    return e
end

local function hideESP(e)
    for _, d in ipairs(e.draws) do
        pcall(function() d.Visible = false end)
    end
end

local function removeESP(p)
    local e = espCache[p]
    if e then
        for _, d in ipairs(e.draws) do pcall(function() d:Remove() end) end
        espCache[p] = nil
    end
    local hl = chamCache[p]
    if hl then
        pcall(function() hl:Destroy() end)
        chamCache[p] = nil
    end
end

local function partPos(ch, name)
    local p = ch:FindFirstChild(name)
    if p and p:IsA("BasePart") then return p.Position end
    return nil
end

local function updateESP()
    if not hasDrawing then return end

    if not C.esp then
        local keys = {}
        for p in pairs(espCache) do keys[#keys + 1] = p end
        for _, p in ipairs(keys) do removeESP(p) end
        return
    end

    local cam = Workspace.CurrentCamera
    if not cam then return end
    local myHrp = getHRP()
    local vp = cam.ViewportSize
    local seen = {}

    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP and isAlive(p) and not (C.espTeam and sameTeam(p)) then
            local ch = p.Character
            local hrp = getHRP(p)
            if ch and hrp then
                local dist = myHrp and (myHrp.Position - hrp.Position).Magnitude or 0
                local cf, sz = nil, nil
                pcall(function()
                    local a, b = ch:GetBoundingBox()
                    cf, sz = a, b
                end)
                if not cf then
                    cf = hrp.CFrame
                    sz = Vector3.new(2, 5, 1)
                end

                local topP = cf.Position + Vector3.new(0, sz.Y / 2, 0)
                local botP = cf.Position - Vector3.new(0, sz.Y / 2, 0)
                local top, onScreen = cam:WorldToViewportPoint(topP)
                local bot = cam:WorldToViewportPoint(botP)

                if onScreen and dist <= C.espMax then
                    seen[p] = true
                    local e = espCache[p]
                    if not e then
                        e = buildESP()
                        espCache[p] = e
                    end

                    local h = math.abs(bot.Y - top.Y)
                    if h < 6 then h = 6 end
                    local w = h * 0.55
                    local x = top.X - w / 2
                    local y = top.Y

                    local color = ACCENT
                    if p.Team and LP.Team and p.Team ~= LP.Team then
                        color = p.Team.TeamColor.Color
                    end

                    e.box.Visible = C.espBox
                    e.bg.Visible = C.espBox
                    e.box.Color = color
                    e.box.Size = Vector2.new(w, h)
                    e.box.Position = Vector2.new(x, y)
                    e.bg.Size = Vector2.new(w + 2, h + 2)
                    e.bg.Position = Vector2.new(x - 1, y - 1)

                    e.name.Visible = C.espName
                    e.name.Text = p.Name
                    e.name.Position = Vector2.new(x + w / 2, y - 18)
                    e.name.Color = color

                    e.dist.Visible = C.espDist
                    e.dist.Text = tostring(math.floor(dist)) .. "m"
                    e.dist.Position = Vector2.new(x + w / 2, y + h + 2)

                    local tool = nil
                    pcall(function() tool = ch:FindFirstChildOfClass("Tool") end)
                    e.wep.Visible = C.espWeapon and tool ~= nil
                    if tool then
                        e.wep.Text = "[" .. tool.Name .. "]"
                        e.wep.Position = Vector2.new(x + w / 2, y + h + 16)
                    end

                    if C.espTracer then
                        e.tracer.Visible = true
                        e.tracer.From = Vector2.new(vp.X / 2, vp.Y)
                        e.tracer.To = Vector2.new(x + w / 2, y + h)
                        e.tracer.Color = color
                    else
                        e.tracer.Visible = false
                    end

                    local hum = getHum(p)
                    local ratio = 0
                    if hum and hum.MaxHealth > 0 then
                        ratio = clamp(hum.Health / hum.MaxHealth, 0, 1)
                    end
                    e.hpBg.Visible = C.espHP
                    e.hp.Visible = C.espHP
                    e.hpBg.Size = Vector2.new(3, h)
                    e.hpBg.Position = Vector2.new(x - 6, y)
                    e.hp.Size = Vector2.new(3, math.max(1, h * ratio))
                    e.hp.Position = Vector2.new(x - 6, y + h * (1 - ratio))
                    e.hp.Color = Color3.fromRGB(
                        math.floor(255 * (1 - ratio)),
                        math.floor(255 * ratio), 70)

                    local idx = 0
                    if C.espSkel then
                        for _, seg in ipairs(BONES) do
                            local a = partPos(ch, seg[1])
                            local b = partPos(ch, seg[2])
                            idx = idx + 1
                            local line = e.lines[idx]
                            if a and b then
                                local sa, oka = cam:WorldToViewportPoint(a)
                                local sb = cam:WorldToViewportPoint(b)
                                if oka then
                                    line.Visible = true
                                    line.From = Vector2.new(sa.X, sa.Y)
                                    line.To = Vector2.new(sb.X, sb.Y)
                                    line.Color = color
                                else
                                    line.Visible = false
                                end
                            else
                                line.Visible = false
                            end
                        end
                    else
                        for _, line in ipairs(e.lines) do line.Visible = false end
                    end

                    if C.espChams then
                        local hl = chamCache[p]
                        if not hl then
                            local folder = ensureChamFolder()
                            if folder then
                                hl = Instance.new("Highlight")
                                hl.Name = "Selection"
                                hl.Adornee = ch
                                hl.FillColor = color
                                hl.FillTransparency = 0.55
                                hl.OutlineColor = Color3.fromRGB(0, 0, 0)
                                hl.OutlineTransparency = 0.35
                                pcall(function()
                                    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                                end)
                                hl.Parent = folder
                                chamCache[p] = hl
                                hiddenInst[hl] = true
                            end
                        end
                    elseif chamCache[p] then
                        pcall(function() chamCache[p]:Destroy() end)
                        hiddenInst[chamCache[p]] = nil
                        chamCache[p] = nil
                    end
                else
                    local e = espCache[p]
                    if e then hideESP(e) end
                end
            end
        else
            local e = espCache[p]
            if e then hideESP(e) end
            if chamCache[p] then
                pcall(function() chamCache[p]:Destroy() end)
                hiddenInst[chamCache[p]] = nil
                chamCache[p] = nil
            end
        end
    end

    for p, e in pairs(espCache) do
        if not seen[p] then hideESP(e) end
    end
end

--=====================================================================
-- 5. 战斗
--=====================================================================
local aimTarget = nil
local silentTarget = nil
local lastFire = 0

local function isVisible(part, ch)
    local cam = Workspace.CurrentCamera
    if not cam then return true end
    local origin = cam.CFrame.Position
    local dir = part.Position - origin
    local list = {}
    if ch then list[#list + 1] = ch end
    if LP.Character then list[#list + 1] = LP.Character end
    if chamFolder then list[#list + 1] = chamFolder end

    local rp = RaycastParams.new()
    local ok = pcall(function() rp.FilterType = Enum.RaycastFilterType.Exclude end)
    if not ok then pcall(function() rp.FilterType = Enum.RaycastFilterType.Blacklist end) end
    rp.FilterDescendantsInstances = list
    rp.IgnoreWater = true

    local hit = Workspace:Raycast(origin, dir, rp)
    if not hit then return true end
    return ch ~= nil and hit.Instance:IsDescendantOf(ch)
end

local function targetScore(cand)
    if C.aimPriority == "血量" then
        local hum = getHum(cand.plr)
        local hp = hum and hum.Health or 999
        return hp + cand.dist * 0.01
    end
    return cand.dist
end

local function findTarget(fov, teamCheck, partName, visOnly)
    local cam = Workspace.CurrentCamera
    if not cam then return nil end
    local vp = cam.ViewportSize
    local center = Vector2.new(vp.X / 2, vp.Y / 2)
    local best, bestScore = nil, math.huge

    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP and isAlive(p) and not (teamCheck and sameTeam(p)) then
            local ch = p.Character
            if ch then
                local part = ch:FindFirstChild(partName)
                if not part or not part:IsA("BasePart") then
                    part = ch:FindFirstChild("Head") or ch:FindFirstChild("UpperTorso")
                end
                if part and part:IsA("BasePart") then
                    local sp, on = cam:WorldToViewportPoint(part.Position)
                    if on then
                        local d = (Vector2.new(sp.X, sp.Y) - center).Magnitude
                        if d < fov then
                            if (not visOnly) or isVisible(part, ch) then
                                local cand = {plr = p, part = part, pos = part.Position, dist = d}
                                local score = targetScore(cand)
                                if score < bestScore then
                                    bestScore = score
                                    best = cand
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return best
end

local function predictPos(t)
    local ping = 0
    pcall(function() ping = LP:GetNetworkPing() end)
    local v = Vector3.zero
    pcall(function() v = t.part.AssemblyLinearVelocity end)
    if typeOf(v) ~= "Vector3" then
        pcall(function() v = t.part.Velocity end)
    end
    if typeOf(v) ~= "Vector3" then v = Vector3.zero end
    return t.part.Position + v * (C.aimPred + ping * 0.5)
end

local fovCircle = nil
if hasDrawing then
    fovCircle = Drawing.new("Circle")
    fovCircle.Thickness = 1
    fovCircle.NumSides = 64
    fovCircle.Filled = false
    fovCircle.Transparency = 0.75
    fovCircle.Color = ACCENT
    fovCircle.Visible = false
end

local statText = nil
if hasDrawing then
    statText = Drawing.new("Text")
    statText.Size = 14
    statText.Center = false
    statText.Outline = true
    statText.OutlineColor = Color3.fromRGB(0, 0, 0)
    statText.Color = ACCENT
    statText.Visible = false
end

local fpsAcc, fpsFrames, fpsShown, pingShown = 0, 0, 0, 0

local function updateStats(dt)
    if not statText then return end
    if not C.showStats then
        statText.Visible = false
        return
    end
    fpsAcc = fpsAcc + dt
    fpsFrames = fpsFrames + 1
    if fpsAcc >= 0.5 then
        fpsShown = math.floor(fpsFrames / fpsAcc + 0.5)
        fpsAcc, fpsFrames = 0, 0
        local ok, p = pcall(function() return LP:GetNetworkPing() end)
        pingShown = ok and math.floor((p or 0) * 1000) or 0
    end
    local cam = Workspace.CurrentCamera
    local h = cam and cam.ViewportSize.Y or 400
    statText.Text = "FPS " .. tostring(fpsShown) .. "  |  " .. tostring(pingShown) .. "ms"
    statText.Position = Vector2.new(14, h - 96)
    statText.Visible = true
end

local function updateCombat(cam)
    if not cam then return end

    aimTarget = nil
    silentTarget = nil

    if C.aim then
        aimTarget = findTarget(C.aimFov, C.aimTeam, C.aimPart, C.aimVis)
    end
    if C.silent then
        silentTarget = findTarget(C.silentFov, C.silentTeam, C.aimPart, C.aimVis)
        if silentTarget then
            silentTarget.pos = predictPos(silentTarget)
        end
    end

    if fovCircle then
        local show = C.aim or C.silent
        fovCircle.Visible = show
        if show then
            local vp = cam.ViewportSize
            fovCircle.Position = Vector2.new(vp.X / 2, vp.Y / 2)
            fovCircle.Radius = C.aim and C.aimFov or C.silentFov
            fovCircle.Color = C.aim and ACCENT or VIS_ACCENT
        end
    end

    if C.aim and aimTarget then
        local alpha = clamp((100 - C.aimSmooth) / 100, 0.02, 1)
        local goal = CFrame.lookAt(cam.CFrame.Position, aimTarget.pos)
        pcall(function()
            cam.CFrame = cam.CFrame:Lerp(goal, alpha)
        end)
    end

    -- 自动开火
    if C.autoFire and silentTarget and os.clock() - lastFire > 0.08 then
        lastFire = os.clock()
        if mouse1click then
            pcall(mouse1click)
        elseif mouse1press and mouse1release then
            pcall(mouse1press)
            task.wait(0.03)
            pcall(mouse1release)
        end
    end

    -- 自动扳机：准星压到人身上就开火（手机最吃这个）
    if C.autoTrigger then
        local t = findTarget(C.triggerFov, C.aimTeam, C.aimPart, true)
        local dist = math.huge
        if t then
            local a, b = getHRP(), getHRP(t.plr)
            if a and b then dist = (a.Position - b.Position).Magnitude end
        end
        if t and dist <= C.triggerRange and os.clock() - lastFire > 0.05 then
            lastFire = os.clock()
            if mouse1click then
                pcall(mouse1click)
            elseif mouse1press and mouse1release then
                pcall(mouse1press)
                task.wait(0.02)
                pcall(mouse1release)
            end
        end
    end
end

--=====================================================================
-- 6. 反检测钩子
--=====================================================================
local kickCount = 0
local blockCount = 0
local mt, oldIndex, oldNamecall, oldNewindex = nil, nil, nil, nil
local filtering = false
local mouse = nil
pcall(function() mouse = LP:GetMouse() end)

local function installedOK() return mt ~= nil end

local function installHooks()
    if not hasHooks then return false end
    mt = getrawmetatable(game)
    if not mt then return false end
    pcall(setRO, mt, false)
    oldIndex = mt.__index
    oldNamecall = mt.__namecall
    oldNewindex = mt.__newindex
    if type(oldIndex) ~= "function" or type(oldNamecall) ~= "function" then return false end

    local wrap = newcclosure or function(f) return f end

    -- 读拦截：属性伪装 / 静默
    mt.__index = wrap(function(self, key)
        if not isCaller() then
            local isCharHum = false
            if key == "WalkSpeed" or key == "JumpPower" or key == "PlatformStand" then
                if typeOf(self) == "Instance" and self:IsA("Humanoid") and self.Parent == LP.Character then
                    isCharHum = true
                end
            end

            if C.propSpoof and isCharHum then
                if key == "WalkSpeed" then return baseSpeed end
                if key == "JumpPower" then return baseJump or 50 end
                if key == "PlatformStand" and C.fly then return false end
            end

            if C.propSpoof and (key == "Velocity" or key == "AssemblyLinearVelocity")
                and typeOf(self) == "Instance" and self:IsA("BasePart")
                and LP.Character and self:IsDescendantOf(LP.Character) then
                local v = oldIndex(self, key)
                if typeOf(v) == "Vector3" and v.Magnitude > C.velCap then
                    return v.Unit * C.velCap
                end
                return v
            end

            if C.noclip and key == "CanCollide" and typeOf(self) == "Instance" and self:IsA("BasePart") then
                return true
            end

            if C.silent and silentTarget and mouse and self == mouse then
                if key == "Hit" then return CFrame.new(silentTarget.pos) end
                if key == "Target" then return silentTarget.part end
                if key == "HitPosition" then return silentTarget.pos end
                if key == "UnitRay" then
                    local cam = Workspace.CurrentCamera
                    if cam then
                        return Ray.new(cam.CFrame.Position, (silentTarget.pos - cam.CFrame.Position).Unit)
                    end
                end
            end

            -- 后坐力 / 扩散 / 换弹 归零
            if typeOf(self) == "Instance" then
                if C.noRecoil and (key == "Recoil" or key == "RecoilAmount" or key == "RecoilForce"
                    or key == "CameraShake" or key == "Kickback" or key == "CamShake") then
                    return 0
                end
                if C.noSpread and (key == "Spread" or key == "SpreadAmount" or key == "Bloom"
                    or key == "Sway" or key == "SwayAmount") then
                    return 0
                end
                if C.instantReload and (key == "ReloadTime" or key == "ReloadDuration") then
                    return 0.05
                end
                if C.skinForceShow and (key == "Owned" or key == "IsOwned" or key == "Unlocked") then
                    return true
                end
            end
        end
        return oldIndex(self, key)
    end)

    -- 写拦截 + 名字调用拦截
    if type(oldNewindex) == "function" then
        mt.__newindex = wrap(function(self, key, value)
            if not isCaller() and C.lockProps and typeOf(self) == "Instance" then
                if (key == "WalkSpeed" or key == "JumpPower" or key == "PlatformStand") then
                    if self:IsA("Humanoid") and self.Parent == LP.Character then
                        blockCount = blockCount + 1
                        return
                    end
                end
                if key == "CanCollide" and C.noclip and self:IsA("BasePart") then
                    if value == true and LP.Character and self:IsDescendantOf(LP.Character) then
                        blockCount = blockCount + 1
                        return
                    end
                end
                if C.noRecoil and (key == "Recoil" or key == "RecoilAmount" or key == "RecoilForce"
                    or key == "CameraShake" or key == "Kickback") then
                    blockCount = blockCount + 1
                    return
                end
                if C.noSpread and (key == "Spread" or key == "SpreadAmount" or key == "Bloom") then
                    blockCount = blockCount + 1
                    return
                end
            end
            return oldNewindex(self, key, value)
        end)
    end

    mt.__namecall = wrap(function(self, ...)
        local method = getMethod()
        if not isCaller() then
            -- 反踢
            if C.antiKick and method == "Kick" and (self == LP or self == Players) then
                kickCount = kickCount + 1
                task.spawn(function() notify("已拦截一次踢出 (" .. tostring(kickCount) .. ")") end)
                return nil
            end

            -- 静默：屏幕射线
            if C.silent and silentTarget and self == Workspace.CurrentCamera then
                if method == "ScreenPointToRay" or method == "ViewportPointToRay" then
                    local origin = Workspace.CurrentCamera.CFrame.Position
                    return Ray.new(origin, (silentTarget.pos - origin).Unit)
                end
            end

            -- 隐藏本脚本实例，避免检测脚本枚举到
            if C.hideInst and not filtering and LP.Character and self == LP.Character then
                if method == "GetChildren" or method == "GetDescendants" then
                    filtering = true
                    local res = oldNamecall(self, ...)
                    filtering = false
                    local out = {}
                    if type(res) == "table" then
                        for _, v in ipairs(res) do
                            if not hiddenInst[v] then out[#out + 1] = v end
                        end
                    end
                    return out
                end
                if method == "FindFirstChildOfClass" or method == "FindFirstChildWhichIsA" then
                    local res = oldNamecall(self, ...)
                    if res and hiddenInst[res] then return nil end
                    return res
                end
                if method == "FindFirstChild" then
                    local res = oldNamecall(self, ...)
                    if res and hiddenInst[res] then return nil end
                    return res
                end
            end
        end
        return oldNamecall(self, ...)
    end)

    return true
end

local function removeHooks()
    if not mt or not oldIndex or not oldNamecall then return end
    pcall(function()
        mt.__index = oldIndex
        mt.__namecall = oldNamecall
        if oldNewindex then mt.__newindex = oldNewindex end
        if setRO then setRO(mt, true) end
    end)
    mt, oldIndex, oldNamecall, oldNewindex = nil, nil, nil, nil
end

--=====================================================================
-- 7. 移动
--=====================================================================
local flyInput = {f = false, b = false, u = false, d = false}
local joyVec = Vector2.zero
local flying = false
local slideUntil = 0
local sliding = false
local savedPos = nil

local function applySpeed()
    local hum = getHum()
    if not hum then return end
    local v = C.speed and C.speedVal or baseSpeed
    if C.speed and C.speedJitter and v > 20 then
        v = v + (math.random() * 2 - 1) * math.max(1, v * 0.06)
    end
    hum.WalkSpeed = v
end

local function applyJump()
    local hum = getHum()
    if not hum then return end
    pcall(function()
        hum.UseJumpPower = true
        hum.JumpPower = C.jumpPower
    end)
end

local function applyNoclip()
    local ch = getChar()
    if not ch then return end
    for _, v in ipairs(ch:GetDescendants()) do
        if v:IsA("BasePart") then
            v.CanCollide = false
        end
    end
end

local function stopFly()
    if not flying then return end
    flying = false
    local hum = getHum()
    if hum then
        pcall(function() hum.PlatformStand = false end)
    end
end

local function updateFly(cam)
    if not C.fly then
        stopFly()
        return
    end
    local hrp, hum = getHRP(), getHum()
    if not hrp or not hum then return end
    if not flying then
        flying = true
        pcall(function() hum.PlatformStand = true end)
    end

    -- 滑铲爆冲优先
    if sliding and os.clock() < slideUntil and cam then
        local dir = cam.CFrame.LookVector
        hrp.AssemblyLinearVelocity = dir * (C.slidePower * 1.8)
        return
    end

    local dir = Vector3.zero
    if cam then
        local lv = cam.CFrame.LookVector
        local rv = cam.CFrame.RightVector
        if UIS:IsKeyDown(Enum.KeyCode.W) or flyInput.f then dir = dir + lv end
        if UIS:IsKeyDown(Enum.KeyCode.S) or flyInput.b then dir = dir - lv end
        if UIS:IsKeyDown(Enum.KeyCode.A) then dir = dir - rv end
        if UIS:IsKeyDown(Enum.KeyCode.D) then dir = dir + rv end

        -- 手机：虚拟摇杆 / 系统摇杆
        if dir.Magnitude < 0.01 then
            if joyVec.Magnitude > 0.05 then
                local fwd = Vector3.new(lv.X, 0, lv.Z)
                local right = Vector3.new(rv.X, 0, rv.Z)
                if fwd.Magnitude > 0.01 then fwd = fwd.Unit end
                if right.Magnitude > 0.01 then right = right.Unit end
                dir = fwd * joyVec.Y + right * joyVec.X
            else
                local md = hum.MoveDirection
                if md.Magnitude > 0.05 then dir = dir + md end
            end
        end
    end
    if UIS:IsKeyDown(Enum.KeyCode.Space) or flyInput.u then dir = dir + Vector3.new(0, 1, 0) end
    if UIS:IsKeyDown(Enum.KeyCode.LeftControl) or flyInput.d then dir = dir - Vector3.new(0, 1, 0) end

    if dir.Magnitude > 0.01 then
        hrp.AssemblyLinearVelocity = dir.Unit * C.flyVal
    else
        hrp.AssemblyLinearVelocity = Vector3.zero
    end
end

local function doSlide()
    if sliding then return end
    local hrp, hum = getHRP(), getHum()
    if not hrp or not hum then return end

    local cam = Workspace.CurrentCamera
    local dir
    if C.fly then
        dir = cam and cam.CFrame.LookVector or Vector3.new(0, 0, -1)
    else
        dir = hum.MoveDirection
        if dir.Magnitude < 0.1 then
            dir = cam and cam.CFrame.LookVector or Vector3.new(0, 0, -1)
        end
        dir = Vector3.new(dir.X, 0, dir.Z)
        if dir.Magnitude < 0.01 then
            dir = Vector3.new(0, 0, -1)
        else
            dir = dir.Unit
        end
    end

    sliding = true
    slideUntil = os.clock() + 0.4
    pcall(function() hum.CameraOffset = Vector3.new(0, -1.3, 0) end)

    local t0 = os.clock()
    while os.clock() - t0 < 0.4 do
        if C.fly then
            hrp.AssemblyLinearVelocity = dir * (C.slidePower * 1.8)
        else
            local cur = hrp.AssemblyLinearVelocity
            hrp.AssemblyLinearVelocity = dir * C.slidePower + Vector3.new(0, cur.Y, 0)
        end
        task.wait(0.03)
    end

    if hum and hum.Parent then
        pcall(function() hum.CameraOffset = Vector3.zero end)
    end
    sliding = false
end

local function bhopStep()
    if not C.bhop then return end
    local hum = getHum()
    if not hum then return end
    local grounded = false
    pcall(function() grounded = hum.FloorMaterial ~= Enum.Material.Air end)
    if grounded then
        hum.Jump = true
    end
end

local function teleportTo(pos)
    local hrp = getHRP()
    if not hrp then return end
    if C.moveLimit then
        local cur = hrp.Position
        local delta = pos - cur
        local steps = math.ceil(delta.Magnitude / 12)
        if steps < 1 then steps = 1 end
        for i = 1, steps do
            local target = cur + delta * (i / steps)
            pcall(function()
                hrp.CFrame = CFrame.new(target)
            end)
            task.wait(0.02)
        end
    else
        pcall(function()
            hrp.CFrame = CFrame.new(pos)
        end)
    end
end

--=====================================================================
-- 8. 皮肤（本地视觉替换 + 染色 + 资源库扫描）
--=====================================================================
local skinColor3 = Color3.fromRGB(255, 255, 255)
local skinAppliedParts = setmetatable({}, {__mode = "k"})
local skinPool = {}
local skinPoolBuilt = false

local SKIN_NAME_HINTS = {
    "skin", "camo", "paint", "wrap", "gun", "knife", "weapon",
    "mesh", "view", "arm", "sword", "blade",
}

local function nameHasSkinHint(n)
    n = string.lower(n or "")
    for _, h in ipairs(SKIN_NAME_HINTS) do
        if string.find(n, h, 1, true) then return true end
    end
    return false
end

-- 手里的武器容器（Tool / 相机下的 viewmodel / 角色内模型）
local function getWeaponContainers()
    local list = {}
    local ch = getChar()
    if ch then
        for _, v in ipairs(ch:GetChildren()) do
            if v:IsA("Tool") then
                list[#list + 1] = v
            elseif v:IsA("Model") and nameHasSkinHint(v.Name) then
                list[#list + 1] = v
            end
        end
    end
    local cam = Workspace.CurrentCamera
    if cam then
        for _, v in ipairs(cam:GetChildren()) do
            if v:IsA("Model") then list[#list + 1] = v end
        end
    end
    local pg = LP:FindFirstChildOfClass("PlayerGui")
    if pg then
        for _, v in ipairs(pg:GetDescendants()) do
            if v:IsA("Model") and nameHasSkinHint(v.Name) then
                list[#list + 1] = v
                if #list > 40 then break end
            end
        end
    end
    return list
end

local function applySkinToPart(p)
    if not p or not p.Parent then return end
    if p:IsA("MeshPart") then
        if C.skinMesh ~= "" then
            pcall(function() p.MeshId = C.skinMesh end)
        end
        if C.skinTexture ~= "" then
            pcall(function() p.TextureID = C.skinTexture end)
        end
    elseif p:IsA("BasePart") then
        local sm = p:FindFirstChildOfClass("SpecialMesh")
        if sm and C.skinMesh ~= "" then
            pcall(function() sm.MeshId = C.skinMesh end)
        end
        if sm and C.skinTexture ~= "" then
            pcall(function() sm.TextureId = C.skinTexture end)
        end
    end
    if C.skinColorMode then
        pcall(function() p.Color = skinColor3 end)
    end
    if C.skinNeon then
        pcall(function() p.Material = Enum.Material.Neon end)
    end
    if C.skinMaterial ~= "保持" then
        local map = {
            ["金属"] = Enum.Material.Metal,
            ["塑料"] = Enum.Material.Plastic,
            ["光滑"] = Enum.Material.SmoothPlastic,
            ["霓虹"] = Enum.Material.Neon,
            ["力场"] = Enum.Material.ForceField,
            ["玻璃"] = Enum.Material.Glass,
        }
        local m = map[C.skinMaterial]
        if m then pcall(function() p.Material = m end) end
    end
end

local function applySkin()
    if not C.skin then return 0 end
    local n = 0
    for _, c in ipairs(getWeaponContainers()) do
        local parts = {}
        pcall(function()
            for _, d in ipairs(c:GetDescendants()) do
                if d:IsA("MeshPart") or d:IsA("BasePart") then parts[#parts + 1] = d end
            end
        end)
        for _, p in ipairs(parts) do
            if not skinAppliedParts[p] then
                applySkinToPart(p)
                skinAppliedParts[p] = true
                n = n + 1
            end
        end
    end
    return n
end

local function resetSkin()
    skinAppliedParts = setmetatable({}, {__mode = "k"})
end

-- 扫描游戏里已加载的皮肤网格资源，做成可选列表
local function buildSkinPool()
    local ids, seen = {}, {}
    local roots = {}
    pcall(function() roots[#roots + 1] = game:GetService("ReplicatedStorage") end)
    pcall(function() roots[#roots + 1] = game:GetService("StarterPack") end)
    pcall(function() roots[#roots + 1] = game:GetService("Players") end)
    local scanned = 0
    for _, root in ipairs(roots) do
        local descs
        local ok = pcall(function() descs = root:GetDescendants() end)
        if ok and descs then
            for _, d in ipairs(descs) do
                scanned = scanned + 1
                if scanned > 30000 then break end
                if d:IsA("MeshPart") and d.MeshId ~= "" and nameHasSkinHint(d.Name) then
                    if not seen[d.MeshId] then
                        seen[d.MeshId] = true
                        ids[#ids + 1] = {name = d.Name, mesh = d.MeshId, tex = (d.TextureID or "")}
                    end
                elseif d:IsA("SpecialMesh") and d.MeshId ~= "" and nameHasSkinHint(d.Name) then
                    if not seen[d.MeshId] then
                        seen[d.MeshId] = true
                        ids[#ids + 1] = {name = d.Name, mesh = d.MeshId, tex = (d.TextureId or "")}
                    end
                end
                if #ids >= 300 then break end
            end
        end
    end
    skinPool = ids
    skinPoolBuilt = true
    return #ids
end

local function skinPoolNames()
    local out = {}
    for i, v in ipairs(skinPool) do
        out[i] = v.name .. " #" .. i
    end
    if #out == 0 then out[1] = "（还没扫描到）" end
    return out
end

local function useSkinIndex(i)
    local v = skinPool[i]
    if not v then return false end
    C.skinMesh = v.mesh
    C.skinTexture = v.tex or ""
    skinAppliedParts = setmetatable({}, {__mode = "k"})
    applySkin()
    return true
end

--=====================================================================
-- 9. 世界视觉 / 性能
--=====================================================================
local Lighting = cloneref(game:GetService("Lighting"))
local wOrig = {}
local wCaptured = false

local function captureWorld()
    if wCaptured then return end
    wCaptured = true
    pcall(function()
        wOrig.Brightness = Lighting.Brightness
        wOrig.ClockTime = Lighting.ClockTime
        wOrig.FogEnd = Lighting.FogEnd
        wOrig.FogStart = Lighting.FogStart
        wOrig.GlobalShadows = Lighting.GlobalShadows
        wOrig.Ambient = Lighting.Ambient
        wOrig.OutdoorAmbient = Lighting.OutdoorAmbient
        wOrig.ExposureCompensation = Lighting.ExposureCompensation
    end)
end

local function applyWorld()
    if not wCaptured then captureWorld() end
    pcall(function()
        Lighting.Brightness = C.wFullbright and 3 or wOrig.Brightness
        Lighting.ClockTime = C.wFullbright and 12 or wOrig.ClockTime
        Lighting.GlobalShadows = not C.wNoShadow
        Lighting.FogEnd = C.wNoFog and 1000000 or wOrig.FogEnd
        Lighting.FogStart = C.wNoFog and 1000000 or wOrig.FogStart
        Lighting.Ambient = C.wAmbient and Color3.fromRGB(180, 180, 180) or wOrig.Ambient
        Lighting.OutdoorAmbient = C.wAmbient and Color3.fromRGB(180, 180, 180) or wOrig.OutdoorAmbient
        Lighting.ExposureCompensation = C.wFullbright and 0.4 or wOrig.ExposureCompensation
    end)
    if C.wFps and setfpscap then
        pcall(setfpscap, C.fpsCap)
    end
    if C.wNoParticles then
        pcall(function()
            local n = 0
            for _, d in ipairs(Workspace:GetDescendants()) do
                if d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Trail") then
                    d.Enabled = false
                    n = n + 1
                    if n > 3000 then break end
                end
            end
        end)
    end
end

local function applyCamera()
    local cam = Workspace.CurrentCamera
    if not cam then return end
    pcall(function() cam.FieldOfView = C.camFov end)
    pcall(function()
        LP.CameraMaxZoomDistance = C.camZoom
        if C.camThird then
            LP.CameraMinZoomDistance = math.max(4, C.camZoom * 0.4)
            LP.CameraMode = Enum.CameraMode.Classic
        end
    end)
end

local function restoreCamera()
    local cam = Workspace.CurrentCamera
    if cam then pcall(function() cam.FieldOfView = 70 end) end
    pcall(function()
        LP.CameraMaxZoomDistance = 128
        LP.CameraMinZoomDistance = 0.5
    end)
end

local function doRejoin()
    pcall(function()
        game:GetService("TeleportService"):Teleport(game.PlaceId, LP)
    end)
end

local function restoreWorld()
    if not wCaptured then return end
    pcall(function()
        Lighting.Brightness = wOrig.Brightness
        Lighting.ClockTime = wOrig.ClockTime
        Lighting.GlobalShadows = wOrig.GlobalShadows
        Lighting.FogEnd = wOrig.FogEnd
        Lighting.FogStart = wOrig.FogStart
        Lighting.Ambient = wOrig.Ambient
        Lighting.OutdoorAmbient = wOrig.OutdoorAmbient
        Lighting.ExposureCompensation = wOrig.ExposureCompensation
    end)
end

local function teleportToPlayer(p, above)
    local hrp = getHRP()
    local t = p and getHRP(p)
    if not hrp or not t then return false end
    teleportTo(t.Position + Vector3.new(0, above and 5 or 0, 0))
    return true
end

local function nearestEnemy()
    local best, bestD = nil, math.huge
    local hrp = getHRP()
    if not hrp then return nil end
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP and isAlive(p) and not sameTeam(p) then
            local t = getHRP(p)
            if t then
                local d = (hrp.Position - t.Position).Magnitude
                if d < bestD then bestD = d; best = p end
            end
        end
    end
    return best
end


local SCAN_PATTERNS = {
    "anticheat", "anti_cheat", "anti-cheat", "_ac_", "ac_", "guard",
    "shield", "detector", "detection", "watchdog", "banhammer",
    "exploitcheck", "speedcheck", "flycheck", "suspicious",
}

local function scanScripts(report)
    local count = 0
    local roots = {LP:FindFirstChild("PlayerScripts"), LP:FindFirstChild("PlayerGui")}
    for _, root in ipairs(roots) do
        if root then
            for _, d in ipairs(root:GetDescendants()) do
                if d:IsA("LocalScript") then
                    local n = string.lower(d.Name)
                    for _, pat in ipairs(SCAN_PATTERNS) do
                        if string.find(n, pat, 1, true) then
                            if not d.Disabled then
                                pcall(function() d.Disabled = true end)
                                count = count + 1
                            end
                            break
                        end
                    end
                end
            end
        end
    end
    if report then
        notify("已屏蔽 " .. tostring(count) .. " 个检测脚本")
    end
    return count
end

local function acStatus()
    local lines = {}
    lines[#lines + 1] = "hook: " .. (installedOK() and "启用" or "不可用")
    lines[#lines + 1] = "gethui: " .. (gethui and "可用" or "不可用")
    lines[#lines + 1] = "拦截踢出: " .. tostring(kickCount)
    lines[#lines + 1] = "拦截改写: " .. tostring(blockCount)
    lines[#lines + 1] = "属性伪装: " .. (C.propSpoof and "开" or "关")
    lines[#lines + 1] = "实例隐藏: " .. (C.hideInst and "开" or "关")
    return table.concat(lines, "   |   ")
end

--=====================================================================
-- 9. 卸载
--=====================================================================
local function unload()
    pcall(saveCfg)
    stopFly()
    pcall(restoreWorld)
    pcall(restoreCamera)
    pcall(resetSkin)
    for p in pairs(espCache) do removeESP(p) end
    for _, hl in pairs(chamCache) do pcall(function() hl:Destroy() end) end
    if fovCircle then pcall(function() fovCircle:Remove() end) end
    if statText then pcall(function() statText:Remove() end) end
    removeHooks()
    pcall(uiCleanup)
    if getgenv then getgenv().ZakaRivals = nil end
end

--=====================================================================
-- 10. 界面
--=====================================================================
local WINDUI_URLS = {
    "https://github.com/Footagesus/WindUI/releases/latest/download/main.lua",
    "https://raw.githubusercontent.com/Footagesus/WindUI/main/main.lua",
}

local WindUI = nil
if loadstring and game.HttpGet then
    for _, url in ipairs(WINDUI_URLS) do
        local ok, res = pcall(function()
            return loadstring(game:HttpGet(url))()
        end)
        if ok and type(res) == "table" and res.CreateWindow then
            WindUI = res
            break
        end
    end
end

local pad = nil
local slideBtn = nil
local fabBtn = nil
local quickBar = nil

-----------------------------------------------------------------------
-- 10-A. WindUI
-----------------------------------------------------------------------
local uiBuilt = false
if WindUI then
    uiBuilt = pcall(function()
    local _vp = (Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize) or Vector2.new(600, 460)
    local _phone = _vp.X < 900
    local Window = WindUI:CreateWindow({
        Title = "Zaka Rivals",
        Icon = "crosshair",
        Author = "Zaka",
        Folder = "ZakaRivals",
        Size = UDim2.fromOffset(
            math.floor(math.min(_vp.X * 0.9, _phone and 380 or 620)),
            math.floor(math.min(_vp.Y * 0.78, _phone and 620 or 470))
        ),
        Transparent = true,
        Theme = "Dark",
        SideBarWidth = _phone and 110 or 190,
        KeySystem = false,
    })

    if Window.SetToggleKey then
        pcall(function() Window:SetToggleKey(Enum.KeyCode.RightShift, false) end)
    end

    notify = function(msg)
        pcall(function()
            WindUI:Notify({
                Title = "Zaka Rivals",
                Content = tostring(msg),
                Icon = "info",
                Duration = 3,
            })
        end)
    end

    uiCleanup = function()
        pcall(function() if Window.Destroy then Window:Destroy() end end)
        pcall(function() if Window.Close then Window:Close() end end)
    end

    panelToggle = function()
        local ok = pcall(function()
            if Window.Toggle then Window:Toggle() end
        end)
        if not ok then pcall(function() if Window.Open then Window:Open() end end) end
    end

    local TabVisual = Window:Tab({Title = "视觉", Icon = "eye"})
    local TabCombat = Window:Tab({Title = "战斗", Icon = "crosshair"})
    local TabMove   = Window:Tab({Title = "移动", Icon = "move"})
    local TabSafe   = Window:Tab({Title = "反检测", Icon = "shield"})
    local TabSkin   = Window:Tab({Title = "皮肤", Icon = "paintbrush"})
    local TabWorld  = Window:Tab({Title = "世界", Icon = "sun"})
    local TabMisc   = Window:Tab({Title = "工具", Icon = "settings"})

    local function num(v)
        if type(v) == "table" then return tonumber(v.Value or v[1]) or 0 end
        return tonumber(v) or 0
    end

    -- 视觉
    TabVisual:Section({Title = "ESP"})
    widgets.esp = TabVisual:Toggle({Title = "ESP 总开关", Value = C.esp, Callback = function(v) C.esp = v end})
    TabVisual:Toggle({Title = "方框", Value = C.espBox, Callback = function(v) C.espBox = v end})
    TabVisual:Toggle({Title = "名字", Value = C.espName, Callback = function(v) C.espName = v end})
    TabVisual:Toggle({Title = "距离", Value = C.espDist, Callback = function(v) C.espDist = v end})
    TabVisual:Toggle({Title = "血条", Value = C.espHP, Callback = function(v) C.espHP = v end})
    TabVisual:Toggle({Title = "骨骼", Value = C.espSkel, Callback = function(v) C.espSkel = v end})
    TabVisual:Toggle({Title = "高亮 Chams", Value = C.espChams, Callback = function(v) C.espChams = v end})
    TabVisual:Toggle({Title = "手持武器", Value = C.espWeapon, Callback = function(v) C.espWeapon = v end})
    TabVisual:Toggle({Title = "指向线", Value = C.espTracer, Callback = function(v) C.espTracer = v end})
    TabVisual:Toggle({Title = "忽略队友", Value = C.espTeam, Callback = function(v) C.espTeam = v end})
    TabVisual:Slider({Title = "距离上限", Value = {Min = 100, Max = 3000, Default = C.espMax},
        Callback = function(v) C.espMax = num(v) end})

    -- 战斗
    TabCombat:Section({Title = "自瞄"})
    widgets.aim = TabCombat:Toggle({Title = "自瞄", Value = C.aim, Callback = function(v)
        C.aim = v
        if v then notify("自瞄开启 · FOV " .. math.floor(C.aimFov)) end
    end})
    TabCombat:Slider({Title = "平滑", Value = {Min = 0, Max = 95, Default = C.aimSmooth},
        Callback = function(v) C.aimSmooth = num(v) end})
    TabCombat:Slider({Title = "FOV", Value = {Min = 20, Max = 600, Default = C.aimFov},
        Callback = function(v) C.aimFov = num(v) end})
    TabCombat:Dropdown({
        Title = "部位",
        Values = {"Head", "UpperTorso", "HumanoidRootPart"},
        Options = {"Head", "UpperTorso", "HumanoidRootPart"},
        Value = C.aimPart,
        Callback = function(v)
            if type(v) == "table" then v = v.Value or v[1] end
            if v then C.aimPart = v end
        end,
    })
    TabCombat:Dropdown({
        Title = "目标优先",
        Values = {"距离", "血量"},
        Options = {"距离", "血量"},
        Value = C.aimPriority,
        Callback = function(v)
            if type(v) == "table" then v = v.Value or v[1] end
            if v then C.aimPriority = v end
        end,
    })
    TabCombat:Slider({Title = "预判补偿", Value = {Min = 0, Max = 0.6, Default = C.aimPred},
        Callback = function(v) C.aimPred = num(v) end})
    TabCombat:Toggle({Title = "只锁可见目标", Value = C.aimVis, Callback = function(v) C.aimVis = v end})
    TabCombat:Toggle({Title = "忽略队友", Value = C.aimTeam, Callback = function(v) C.aimTeam = v end})

    TabCombat:Section({Title = "静默"})
    widgets.silent = TabCombat:Toggle({Title = "静默自瞄", Value = C.silent, Callback = function(v)
        C.silent = v
        if v and not hasHooks then notify("执行器缺少 hook，静默不可用") end
    end})
    TabCombat:Slider({Title = "静默 FOV", Value = {Min = 30, Max = 600, Default = C.silentFov},
        Callback = function(v) C.silentFov = num(v) end})
    TabCombat:Toggle({Title = "静默忽略队友", Value = C.silentTeam, Callback = function(v) C.silentTeam = v end})
    TabCombat:Toggle({Title = "自动开火", Value = C.autoFire, Callback = function(v)
        C.autoFire = v
        if v and not (mouse1click or mouse1press) then notify("执行器不支持模拟点击") end
    end})

    -- 移动
    widgets.speed = TabMove:Toggle({Title = "变速", Value = C.speed, Callback = function(v)
        C.speed = v
        applySpeed()
    end})
    TabMove:Slider({Title = "速度值 (正常 16)", Value = {Min = 16, Max = 200, Default = C.speedVal},
        Callback = function(v)
            C.speedVal = num(v)
            if C.speed then applySpeed() end
        end})
    widgets.fly = TabMove:Toggle({Title = "飞行", Value = C.fly, Callback = function(v)
        C.fly = v
        if not v then stopFly() end
        if pad then pad.Visible = v and C.mobilePad end
    end})
    TabMove:Slider({Title = "飞行速度", Value = {Min = 10, Max = 250, Default = C.flyVal},
        Callback = function(v) C.flyVal = num(v) end})
    widgets.noclip = TabMove:Toggle({Title = "穿墙", Value = C.noclip, Callback = function(v)
        C.noclip = v
        if v then applyNoclip() end
    end})
    TabMove:Slider({Title = "滑铲推力", Value = {Min = 20, Max = 250, Default = C.slidePower},
        Callback = function(v) C.slidePower = num(v) end})
    TabMove:Button({Title = "立即滑铲", Callback = function() task.spawn(doSlide) end})
    widgets.bhop = TabMove:Toggle({Title = "自动连跳", Value = C.bhop, Callback = function(v) C.bhop = v end})
    TabMove:Slider({Title = "跳跃力", Value = {Min = 30, Max = 200, Default = C.jumpPower},
        Callback = function(v) C.jumpPower = num(v) applyJump() end})
    TabMove:Section({Title = "定位"})
    TabMove:Button({Title = "保存当前位置", Callback = function()
        local hrp = getHRP()
        if hrp then
            savedPos = hrp.Position
            notify("位置已保存")
        end
    end})
    TabMove:Button({Title = "传送回保存点", Callback = function()
        if savedPos then task.spawn(function() teleportTo(savedPos) end) else notify("没有保存点") end
    end})
    TabMove:Toggle({Title = "显示移动端按键", Value = C.mobilePad, Callback = function(v)
        C.mobilePad = v
        if pad then pad.Visible = v and C.fly end
        if slideBtn then slideBtn.Visible = v end
    end})

    -- 战斗增强
    TabCombat:Section({Title = "扳机 / 枪械手感"})
    TabCombat:Toggle({Title = "自动扳机（准星压住就开火）", Value = C.autoTrigger, Callback = function(v) C.autoTrigger = v end})
    TabCombat:Slider({Title = "扳机 FOV", Value = {Min = 10, Max = 300, Default = C.triggerFov},
        Callback = function(v) C.triggerFov = num(v) end})
    TabCombat:Slider({Title = "扳机有效距离", Value = {Min = 20, Max = 800, Default = C.triggerRange},
        Callback = function(v) C.triggerRange = num(v) end})
    TabCombat:Toggle({Title = "无后坐力", Value = C.noRecoil, Callback = function(v) C.noRecoil = v end})
    TabCombat:Toggle({Title = "无扩散", Value = C.noSpread, Callback = function(v) C.noSpread = v end})
    TabCombat:Toggle({Title = "秒换弹", Value = C.instantReload, Callback = function(v) C.instantReload = v end})

    -- 移动增强
    TabMove:Section({Title = "手机 / 瞬移"})
    TabMove:Button({Title = "瞬移到最近敌人头顶", Callback = function()
        local p = nearestEnemy()
        if p then
            task.spawn(function()
                teleportToPlayer(p, true)
                notify("已到 " .. p.Name .. " 头上")
            end)
        else
            notify("附近没敌人")
        end
    end})
    TabMove:Toggle({Title = "速度随机抖动（防检测）", Value = C.speedJitter, Callback = function(v) C.speedJitter = v end})
    TabMove:Toggle({Title = "显示悬浮球", Value = C.fab, Callback = function(v)
        C.fab = v
        if fabBtn then fabBtn.Visible = v end
    end})
    TabMove:Toggle({Title = "显示快捷条", Value = C.mobilePad, Callback = function(v)
        C.mobilePad = v
        if quickBar then quickBar.Visible = v end
    end})
    TabMove:Slider({Title = "按键大小 %", Value = {Min = 70, Max = 160, Default = math.floor(C.padScale * 100)},
        Callback = function(v) C.padScale = num(v) / 100 end})

    -- 皮肤
    TabSkin:Section({Title = "皮肤替换（只在本机显示）"})
    widgets.skin = TabSkin:Toggle({Title = "皮肤总开关", Value = C.skin, Callback = function(v)
        C.skin = v
        if v then
            skinAppliedParts = setmetatable({}, {__mode = "k"})
            task.spawn(applySkin)
            notify("皮肤已套用")
        else
            resetSkin()
            notify("皮肤已关闭")
        end
    end})
    TabSkin:Toggle({Title = "自动套到新武器", Value = C.skinAuto, Callback = function(v) C.skinAuto = v end})
    TabSkin:Button({Title = "扫描游戏里的皮肤资源", Callback = function()
        local n = buildSkinPool()
        notify("扫到 " .. tostring(n) .. " 个，用下面的序号选")
    end})
    local wSkinIdx = 1
    TabSkin:Slider({Title = "皮肤序号（扫完再选）", Value = {Min = 1, Max = 60, Default = 1},
        Callback = function(v) wSkinIdx = math.floor(num(v)) end})
    TabSkin:Button({Title = "应用这个皮肤", Callback = function()
        if not skinPoolBuilt then buildSkinPool() end
        if useSkinIndex(wSkinIdx) then
            C.skin = true
            resetSkin()
            applySkin()
            notify("已应用：" .. tostring(skinPool[wSkinIdx] and skinPool[wSkinIdx].name or wSkinIdx))
        else
            notify("这个序号没有资源")
        end
    end})
    TabSkin:Section({Title = "染色 / 材质"})
    TabSkin:Toggle({Title = "开启染色", Value = C.skinColorMode, Callback = function(v)
        C.skinColorMode = v
        skinAppliedParts = setmetatable({}, {__mode = "k"})
        applySkin()
    end})
    TabSkin:Slider({Title = "红", Value = {Min = 0, Max = 255, Default = C.skinColorR},
        Callback = function(v) C.skinColorR = num(v) skinColor3 = Color3.fromRGB(C.skinColorR, C.skinColorG, C.skinColorB) skinAppliedParts = setmetatable({}, {__mode = "k"}) applySkin() end})
    TabSkin:Slider({Title = "绿", Value = {Min = 0, Max = 255, Default = C.skinColorG},
        Callback = function(v) C.skinColorG = num(v) skinColor3 = Color3.fromRGB(C.skinColorR, C.skinColorG, C.skinColorB) skinAppliedParts = setmetatable({}, {__mode = "k"}) applySkin() end})
    TabSkin:Slider({Title = "蓝", Value = {Min = 0, Max = 255, Default = C.skinColorB},
        Callback = function(v) C.skinColorB = num(v) skinColor3 = Color3.fromRGB(C.skinColorR, C.skinColorG, C.skinColorB) skinAppliedParts = setmetatable({}, {__mode = "k"}) applySkin() end})
    TabSkin:Dropdown({
        Title = "材质",
        Values = {"保持", "金属", "塑料", "光滑", "霓虹", "力场", "玻璃"},
        Options = {"保持", "金属", "塑料", "光滑", "霓虹", "力场", "玻璃"},
        Value = C.skinMaterial,
        Callback = function(v)
            if type(v) == "table" then v = v.Value or v[1] end
            C.skinMaterial = v
            skinAppliedParts = setmetatable({}, {__mode = "k"})
            applySkin()
        end,
    })
    TabSkin:Toggle({Title = "霓虹发光", Value = C.skinNeon, Callback = function(v)
        C.skinNeon = v
        skinAppliedParts = setmetatable({}, {__mode = "k"})
        applySkin()
    end})
    TabSkin:Toggle({Title = "强制显示已拥有（本地 UI）", Value = C.skinForceShow, Callback = function(v)
        C.skinForceShow = v
        notify(v and "已开启本地拥有伪装" or "已关闭")
    end})
    TabSkin:Button({Title = "立即套用一次", Callback = function()
        skinAppliedParts = setmetatable({}, {__mode = "k"})
        local n = applySkin()
        notify("已处理 " .. tostring(n) .. " 个部件")
    end})
    TabSkin:Button({Title = "还原武器外观", Callback = function()
        resetSkin()
        notify("已重置，换把枪就会恢复")
    end})
    TabSkin:Paragraph({Title = "皮肤替换是本地视觉：自己看得到，别人看不到，重进服务器会恢复"})

    -- 世界视觉
    TabWorld:Section({Title = "画面增强"})
    TabWorld:Toggle({Title = "全亮（夜视）", Value = C.wFullbright, Callback = function(v) C.wFullbright = v applyWorld() end})
    TabWorld:Toggle({Title = "去雾", Value = C.wNoFog, Callback = function(v) C.wNoFog = v applyWorld() end})
    TabWorld:Toggle({Title = "关闭阴影", Value = C.wNoShadow, Callback = function(v) C.wNoShadow = v applyWorld() end})
    TabWorld:Toggle({Title = "提亮环境光", Value = C.wAmbient, Callback = function(v) C.wAmbient = v applyWorld() end})
    TabWorld:Section({Title = "性能"})
    TabWorld:Toggle({Title = "解锁帧率", Value = C.wFps, Callback = function(v) C.wFps = v applyWorld() end})
    TabWorld:Slider({Title = "帧率上限", Value = {Min = 60, Max = 360, Default = C.fpsCap},
        Callback = function(v) C.fpsCap = num(v) if C.wFps and setfpscap then pcall(setfpscap, C.fpsCap) end end})
    TabWorld:Toggle({Title = "关闭粒子特效", Value = C.wNoParticles, Callback = function(v)
        C.wNoParticles = v
        if v then applyWorld() end
    end})
    TabWorld:Section({Title = "相机"})
    TabWorld:Slider({Title = "视野 FOV", Value = {Min = 70, Max = 120, Default = C.camFov},
        Callback = function(v) C.camFov = num(v) applyCamera() end})
    TabWorld:Slider({Title = "最远视距", Value = {Min = 10, Max = 300, Default = C.camZoom},
        Callback = function(v) C.camZoom = num(v) applyCamera() end})
    TabWorld:Toggle({Title = "第三人称锁定", Value = C.camThird, Callback = function(v)
        C.camThird = v
        applyCamera()
    end})

    -- 反检测
    TabSafe:Paragraph({Title = "属性锁定 + 实例隐藏 + 拦截本地踢出 + 检测脚本屏蔽 + 速度向量限幅"})
    widgets.antiKick = TabSafe:Toggle({Title = "拦截踢出", Value = C.antiKick, Callback = function(v) C.antiKick = v end})
    widgets.propSpoof = TabSafe:Toggle({Title = "属性伪装", Value = C.propSpoof, Callback = function(v) C.propSpoof = v end})
    widgets.lockProps = TabSafe:Toggle({Title = "锁定属性 (反改写)", Value = C.lockProps, Callback = function(v) C.lockProps = v end})
    widgets.hideInst = TabSafe:Toggle({Title = "实例隐藏", Value = C.hideInst, Callback = function(v) C.hideInst = v end})
    widgets.scriptScan = TabSafe:Toggle({Title = "屏蔽检测脚本", Value = C.scriptScan, Callback = function(v)
        C.scriptScan = v
        if v then scanScripts(true) end
    end})
    TabSafe:Toggle({Title = "持续扫描", Value = C.scriptScanLoop, Callback = function(v) C.scriptScanLoop = v end})
    TabSafe:Slider({Title = "速度向量上限", Value = {Min = 20, Max = 200, Default = C.velCap},
        Callback = function(v) C.velCap = num(v) end})
    TabSafe:Button({Title = "检测状态自检", Callback = function() notify(acStatus()) end})

    -- 工具
    TabMisc:Button({Title = "保存配置", Callback = function() saveCfg() notify("配置已保存") end})
    TabMisc:Toggle({Title = "显示 FPS / 延迟", Value = C.showStats, Callback = function(v) C.showStats = v end})
    TabMisc:Button({Title = "卸载辅助", Callback = function() unload() end})
    TabMisc:Paragraph({Title = "热键: 右Shift 面板 · C 滑铲 · F 飞行 · V 穿墙 · G 连跳"})

-----------------------------------------------------------------------
-- 10-B. 回退面板
-----------------------------------------------------------------------
    end)
end

if not uiBuilt then
    local T = {
        panel  = Color3.fromRGB(16, 17, 23),
        card   = Color3.fromRGB(27, 29, 39),
        card2  = Color3.fromRGB(38, 41, 55),
        stroke = Color3.fromRGB(64, 68, 92),
        text   = Color3.fromRGB(236, 240, 250),
        dim    = Color3.fromRGB(146, 150, 170),
        accent = ACCENT,
        red    = Color3.fromRGB(255, 92, 110),
    }

    local function mk(cls, props, parent)
        local o = Instance.new(cls)
        for k, v in pairs(props) do o[k] = v end
        if parent ~= nil then o.Parent = parent end
        return o
    end
    local function round(o, r) return mk("UICorner", {CornerRadius = UDim.new(0, r or 10)}, o) end
    local function stroke(o, c, t)
        return mk("UIStroke", {Color = c or T.stroke, Transparency = t or 0.55, Thickness = 1}, o)
    end

    local camNow = Workspace.CurrentCamera
    local vp = (camNow and camNow.ViewportSize) or Vector2.new(420, 820)
    local PW = math.floor(math.min(vp.X * 0.94, 440))
    local PH = math.floor(math.min(vp.Y * 0.78, 620))

    local holder = (gethui and gethui()) or game:GetService("CoreGui")
    local gui = mk("ScreenGui", {
        Name = "zk" .. tostring(math.random(1000000, 9000000)),
        ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 999,
    }, nil)
    if syn and syn.protect_gui then pcall(syn.protect_gui, gui) elseif protect_gui then pcall(protect_gui, gui) end
    local okParent = pcall(function() gui.Parent = holder end)
    if not okParent or not gui.Parent then
        pcall(function() gui.Parent = LP:WaitForChild("PlayerGui", 5) end)
    end

    ------------------------------------------------------------------
    -- 主体
    ------------------------------------------------------------------
    local main = mk("Frame", {
        Size = UDim2.fromOffset(PW, PH),
        Position = UDim2.new(0.5, -math.floor(PW / 2), 1, -PH - 88),
        BackgroundColor3 = T.panel, BorderSizePixel = 0, ClipsDescendants = true,
    }, gui)
    round(main, 16)
    stroke(main, T.stroke, 0.35)

    local head = mk("Frame", {Size = UDim2.new(1, 0, 0, 48), BackgroundTransparency = 1}, main)
    mk("TextLabel", {
        Size = UDim2.new(1, -110, 1, 0), Position = UDim2.fromOffset(14, 0),
        BackgroundTransparency = 1, Text = "ZAKA · RIVALS",
        TextColor3 = T.text, TextSize = 14, Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, head)

    local btnHide = mk("TextButton", {
        Size = UDim2.fromOffset(44, 34), Position = UDim2.new(1, -100, 0, 7),
        BackgroundColor3 = T.card, Text = "收起", TextColor3 = T.dim, TextSize = 12,
        Font = Enum.Font.GothamBold, AutoButtonColor = false, BorderSizePixel = 0,
    }, head)
    round(btnHide, 10)

    local btnClose = mk("TextButton", {
        Size = UDim2.fromOffset(44, 34), Position = UDim2.new(1, -50, 0, 7),
        BackgroundColor3 = T.card, Text = "×", TextColor3 = T.red, TextSize = 22,
        Font = Enum.Font.GothamBold, AutoButtonColor = false, BorderSizePixel = 0,
    }, head)
    round(btnClose, 10)

    local CATS = {"视觉", "战斗", "皮肤", "移动", "反检测", "工具"}
    local catBar = mk("ScrollingFrame", {
        Size = UDim2.new(1, -16, 0, 36), Position = UDim2.new(0, 8, 0, 50),
        BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 0,
        CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.X,
        ScrollingDirection = Enum.ScrollingDirection.X,
    }, main)
    mk("UIListLayout", {
        Padding = UDim.new(0, 6), FillDirection = Enum.FillDirection.Horizontal,
        SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center,
    }, catBar)

    local body = mk("Frame", {
        Size = UDim2.new(1, -16, 1, -98), Position = UDim2.new(0, 8, 0, 92),
        BackgroundTransparency = 1, BorderSizePixel = 0,
    }, main)

    local pages, tabBtns = {}, {}
    for i, name in ipairs(CATS) do
        local sc = mk("ScrollingFrame", {
            Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0,
            ScrollBarThickness = 3, ScrollBarImageColor3 = T.accent,
            CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
            Visible = (i == 1), LayoutOrder = i, ClipsDescendants = true,
        }, body)
        mk("UIListLayout", {Padding = UDim.new(0, 7), SortOrder = Enum.SortOrder.LayoutOrder}, sc)
        mk("UIPadding", {
            PaddingBottom = UDim.new(0, 16), PaddingLeft = UDim.new(0, 2),
            PaddingRight = UDim.new(0, 4), PaddingTop = UDim.new(0, 2),
        }, sc)
        pages[name] = sc

        local b = mk("TextButton", {
            Size = UDim2.fromOffset(62, 34), BackgroundColor3 = (i == 1) and T.card2 or T.card,
            Text = name, TextColor3 = (i == 1) and T.accent or T.dim, TextSize = 12,
            Font = Enum.Font.GothamBold, AutoButtonColor = false, BorderSizePixel = 0,
            LayoutOrder = i,
        }, catBar)
        round(b, 10)
        tabBtns[name] = b
        b.MouseButton1Click:Connect(function()
            for n, p in pairs(pages) do p.Visible = (n == name) end
            for n, bb in pairs(tabBtns) do
                bb.BackgroundColor3 = (n == name) and T.card2 or T.card
                bb.TextColor3 = (n == name) and T.accent or T.dim
            end
        end)
    end

    ------------------------------------------------------------------
    -- 控件
    ------------------------------------------------------------------
    local ROW = {}
    local function rowBase(page, height)
        ROW[page] = (ROW[page] or 0) + 1
        local r = mk("Frame", {
            Size = UDim2.new(1, 0, 0, height), BackgroundColor3 = T.card,
            BorderSizePixel = 0, LayoutOrder = ROW[page],
        }, page)
        round(r, 11)
        stroke(r, T.stroke, 0.78)
        return r
    end

    local function addLabel(page, text)
        ROW[page] = (ROW[page] or 0) + 1
        mk("TextLabel", {
            Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1,
            Text = text, TextColor3 = T.dim, TextSize = 11, Font = Enum.Font.GothamBold,
            TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = ROW[page],
        }, page)
    end

    local function addToggle(page, title, get, set)
        local r = rowBase(page, 50)
        mk("TextLabel", {
            Size = UDim2.new(1, -84, 1, 0), Position = UDim2.fromOffset(14, 0),
            BackgroundTransparency = 1, Text = title, TextColor3 = T.text, TextSize = 13,
            Font = Enum.Font.Gotham, TextXAlignment = Enum.TextXAlignment.Left,
        }, r)
        local track = mk("Frame", {
            Size = UDim2.fromOffset(48, 28), Position = UDim2.new(1, -62, 0.5, -14),
            BackgroundColor3 = T.card2, BorderSizePixel = 0,
        }, r)
        round(track, 14)
        local knob = mk("Frame", {
            Size = UDim2.fromOffset(22, 22), Position = UDim2.new(0, 3, 0.5, -11),
            BackgroundColor3 = Color3.fromRGB(122, 126, 142), BorderSizePixel = 0,
        }, track)
        round(knob, 11)

        local state = get() and true or false
        local function render()
            if state then
                track.BackgroundColor3 = T.accent
                knob.Position = UDim2.new(1, -25, 0.5, -11)
                knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
            else
                track.BackgroundColor3 = T.card2
                knob.Position = UDim2.new(0, 3, 0.5, -11)
                knob.BackgroundColor3 = Color3.fromRGB(122, 126, 142)
            end
        end
        render()

        local hit = mk("TextButton", {
            Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "",
            AutoButtonColor = false, BorderSizePixel = 0,
        }, r)
        hit.MouseButton1Click:Connect(function()
            state = not state
            render()
            pcall(set, state)
            saveCfg()
        end)
        return {Set = function(_, v) state = v and true or false render() end}
    end

    local function addSlider(page, title, min, max, get, set)
        local r = rowBase(page, 62)
        mk("TextLabel", {
            Size = UDim2.new(1, -90, 0, 22), Position = UDim2.fromOffset(14, 8),
            BackgroundTransparency = 1, Text = title, TextColor3 = T.text, TextSize = 12,
            Font = Enum.Font.Gotham, TextXAlignment = Enum.TextXAlignment.Left,
        }, r)
        local valLbl = mk("TextLabel", {
            Size = UDim2.fromOffset(80, 22), Position = UDim2.new(1, -94, 0, 8),
            BackgroundTransparency = 1, Text = "", TextColor3 = T.accent, TextSize = 12,
            Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Right,
        }, r)
        local track = mk("Frame", {
            Size = UDim2.new(1, -28, 0, 5), Position = UDim2.new(0, 14, 1, -18),
            BackgroundColor3 = Color3.fromRGB(52, 55, 72), BorderSizePixel = 0,
        }, r)
        round(track, 3)
        local fill = mk("Frame", {
            Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = T.accent, BorderSizePixel = 0,
        }, track)
        round(fill, 3)
        local dot = mk("Frame", {
            Size = UDim2.fromOffset(16, 16), Position = UDim2.new(0, -8, 0.5, -8),
            BackgroundColor3 = Color3.fromRGB(255, 255, 255), BorderSizePixel = 0,
        }, track)
        round(dot, 8)

        local function apply(v, fire)
            v = clamp(v, min, max)
            local a = (max > min) and ((v - min) / (max - min)) or 0
            fill.Size = UDim2.new(a, 0, 1, 0)
            dot.Position = UDim2.new(a, -8, 0.5, -8)
            valLbl.Text = tostring(math.floor(v + 0.5))
            if fire then pcall(set, v) end
        end

        local hit = mk("TextButton", {
            Size = UDim2.new(1, 0, 0, 34), Position = UDim2.new(0, 0, 1, -36),
            BackgroundTransparency = 1, Text = "",
            AutoButtonColor = false, BorderSizePixel = 0, ZIndex = 4,
        }, r)
        local dragging = false
        local function fromX(x)
            local w = track.AbsoluteSize.X
            if w <= 0 then return end
            local rel = (x - track.AbsolutePosition.X) / w
            apply(min + (max - min) * clamp(rel, 0, 1), true)
        end
        hit.InputBegan:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.Touch
            or i.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging = true
                fromX(i.Position.X)
            end
        end)
        hit.InputChanged:Connect(function(i)
            if not dragging then return end
            if i.UserInputType == Enum.UserInputType.Touch
            or i.UserInputType == Enum.UserInputType.MouseMovement then
                fromX(i.Position.X)
            end
        end)
        hit.InputEnded:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.Touch
            or i.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging = false
                saveCfg()
            end
        end)
        apply(get(), false)
    end

    local function addButton(page, title, cb, color)
        local r = rowBase(page, 50)
        local b = mk("TextButton", {
            Size = UDim2.fromScale(1, 1), BackgroundColor3 = T.card2, Text = title,
            TextColor3 = color or T.accent, TextSize = 13, Font = Enum.Font.GothamBold,
            AutoButtonColor = false, BorderSizePixel = 0, ZIndex = 2,
        }, r)
        round(b, 11)
        b.MouseButton1Click:Connect(function()
            pcall(cb)
            saveCfg()
        end)
    end

    local function addCycle(page, title, options, get, set)
        local r = rowBase(page, 50)
        mk("TextLabel", {
            Size = UDim2.new(1, -142, 1, 0), Position = UDim2.fromOffset(14, 0),
            BackgroundTransparency = 1, Text = title, TextColor3 = T.text, TextSize = 13,
            Font = Enum.Font.Gotham, TextXAlignment = Enum.TextXAlignment.Left,
        }, r)
        local idx = 1
        local cur = tostring(get())
        for i, o in ipairs(options) do if tostring(o) == cur then idx = i end end
        local b = mk("TextButton", {
            Size = UDim2.fromOffset(120, 34), Position = UDim2.new(1, -132, 0.5, -17),
            BackgroundColor3 = T.card2, Text = tostring(options[idx]), TextColor3 = T.accent,
            TextSize = 12, Font = Enum.Font.GothamBold, AutoButtonColor = false, BorderSizePixel = 0,
        }, r)
        round(b, 10)
        b.MouseButton1Click:Connect(function()
            idx = idx % #options + 1
            b.Text = tostring(options[idx])
            pcall(set, options[idx])
            saveCfg()
        end)
    end

    local function addInput(page, title, placeholder, get, set)
        local r = rowBase(page, 84)
        mk("TextLabel", {
            Size = UDim2.new(1, -28, 0, 20), Position = UDim2.fromOffset(14, 8),
            BackgroundTransparency = 1, Text = title, TextColor3 = T.text, TextSize = 12,
            Font = Enum.Font.Gotham, TextXAlignment = Enum.TextXAlignment.Left,
        }, r)
        local box = mk("TextBox", {
            Size = UDim2.new(1, -28, 0, 40), Position = UDim2.new(0, 14, 1, -48),
            BackgroundColor3 = T.card2, Text = tostring(get() or ""), PlaceholderText = placeholder,
            PlaceholderColor3 = T.dim, TextColor3 = T.accent, TextSize = 12,
            Font = Enum.Font.Code, ClearTextOnFocus = false, BorderSizePixel = 0,
            TextXAlignment = Enum.TextXAlignment.Left,
        }, r)
        round(box, 9)
        mk("UIPadding", {PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10)}, box)
        box.FocusLost:Connect(function()
            pcall(set, box.Text)
            saveCfg()
        end)
    end

    ------------------------------------------------------------------
    -- 视觉
    ------------------------------------------------------------------
    local P = pages["视觉"]
    addLabel(P, "ESP 敌人透视")
    widgets.esp = addToggle(P, "ESP 总开关", function() return C.esp end, function(v) C.esp = v end)
    addToggle(P, "方框", function() return C.espBox end, function(v) C.espBox = v end)
    addToggle(P, "名字", function() return C.espName end, function(v) C.espName = v end)
    addToggle(P, "距离", function() return C.espDist end, function(v) C.espDist = v end)
    addToggle(P, "血条", function() return C.espHP end, function(v) C.espHP = v end)
    addToggle(P, "骨骼连线", function() return C.espSkel end, function(v) C.espSkel = v end)
    addToggle(P, "高亮 Chams", function() return C.espChams end, function(v) C.espChams = v end)
    addToggle(P, "手持武器名", function() return C.espWeapon end, function(v) C.espWeapon = v end)
    addToggle(P, "指向线", function() return C.espTracer end, function(v) C.espTracer = v end)
    addToggle(P, "忽略队友", function() return C.espTeam end, function(v) C.espTeam = v end)
    addSlider(P, "显示距离上限", 100, 3000, function() return C.espMax end, function(v) C.espMax = v end)

    addLabel(P, "世界视觉")
    addToggle(P, "全亮 (夜视)", function() return C.wFullbright end, function(v) C.wFullbright = v; applyWorld() end)
    addToggle(P, "去雾", function() return C.wNoFog end, function(v) C.wNoFog = v; applyWorld() end)
    addToggle(P, "关阴影", function() return C.wNoShadow end, function(v) C.wNoShadow = v; applyWorld() end)
    addToggle(P, "提亮环境光", function() return C.wAmbient end, function(v) C.wAmbient = v; applyWorld() end)
    addToggle(P, "解锁帧率", function() return C.wFps end, function(v) C.wFps = v; applyWorld() end)
    addSlider(P, "帧率上限", 60, 360, function() return C.fpsCap end, function(v)
        C.fpsCap = v
        if C.wFps and setfpscap then pcall(setfpscap, v) end
    end)
    addToggle(P, "关粒子特效 (省电)", function() return C.wNoParticles end, function(v) C.wNoParticles = v; if v then applyWorld() end end)

    addLabel(P, "相机")
    addSlider(P, "视野 FOV", 70, 120, function() return C.camFov end, function(v)
        C.camFov = v; applyCamera()
    end)
    addSlider(P, "最远视距", 10, 300, function() return C.camZoom end, function(v)
        C.camZoom = v; applyCamera()
    end)
    addToggle(P, "第三人称锁定（看得更远）", function() return C.camThird end, function(v)
        C.camThird = v; applyCamera()
    end)

    ------------------------------------------------------------------
    -- 战斗
    ------------------------------------------------------------------
    local PC = pages["战斗"]
    addLabel(PC, "自瞄")
    widgets.aim = addToggle(PC, "自瞄 (转视角)", function() return C.aim end, function(v) C.aim = v end)
    addSlider(PC, "平滑 (越小越硬)", 0, 95, function() return C.aimSmooth end, function(v) C.aimSmooth = v end)
    addSlider(PC, "自瞄范围 FOV", 20, 600, function() return C.aimFov end, function(v) C.aimFov = v end)
    addSlider(PC, "预判补偿", 0, 60, function() return math.floor(C.aimPred * 100) end, function(v) C.aimPred = v / 100 end)
    addCycle(PC, "瞄准部位", {"Head", "UpperTorso", "HumanoidRootPart"}, function() return C.aimPart end, function(v) C.aimPart = v end)
    addCycle(PC, "目标优先", {"距离", "血量"}, function() return C.aimPriority end, function(v) C.aimPriority = v end)
    addToggle(PC, "只锁可见目标", function() return C.aimVis end, function(v) C.aimVis = v end)
    addToggle(PC, "自瞄忽略队友", function() return C.aimTeam end, function(v) C.aimTeam = v end)

    addLabel(PC, "静默 / 开火")
    widgets.silent = addToggle(PC, "静默自瞄 (准星不动)", function() return C.silent end, function(v) C.silent = v end)
    addSlider(PC, "静默 FOV", 30, 600, function() return C.silentFov end, function(v) C.silentFov = v end)
    addToggle(PC, "静默忽略队友", function() return C.silentTeam end, function(v) C.silentTeam = v end)
    addToggle(PC, "自动开火", function() return C.autoFire end, function(v) C.autoFire = v end)
    addToggle(PC, "自动扳机 (准星压住就打)", function() return C.autoTrigger end, function(v) C.autoTrigger = v end)
    addSlider(PC, "扳机范围 FOV", 10, 300, function() return C.triggerFov end, function(v) C.triggerFov = v end)
    addSlider(PC, "扳机有效距离", 20, 800, function() return C.triggerRange end, function(v) C.triggerRange = v end)

    addLabel(PC, "枪械手感")
    addToggle(PC, "无后坐力", function() return C.noRecoil end, function(v) C.noRecoil = v end)
    addToggle(PC, "无扩散", function() return C.noSpread end, function(v) C.noSpread = v end)
    addToggle(PC, "秒换弹", function() return C.instantReload end, function(v) C.instantReload = v end)

    ------------------------------------------------------------------
    -- 皮肤
    ------------------------------------------------------------------
    local PS = pages["皮肤"]
    addLabel(PS, "皮肤替换 · 仅本地可见")
    widgets.skin = addToggle(PS, "皮肤总开关", function() return C.skin end, function(v)
        C.skin = v
        if v then
            skinAppliedParts = setmetatable({}, {__mode = "k"})
            task.spawn(function() applySkin(); notify("皮肤已套用") end)
        else
            resetSkin()
            notify("皮肤已关闭")
        end
    end)
    addToggle(PS, "自动套到新武器", function() return C.skinAuto end, function(v) C.skinAuto = v end)
    addButton(PS, "扫描游戏皮肤资源", function()
        local n = buildSkinPool()
        notify("扫到 " .. tostring(n) .. " 个皮肤资源，去下面列表里选")
    end)
    local skinList = {"（先点上面的扫描）"}
    local skinIdx = 1
    do
        local r = rowBase(PS, 50)
        mk("TextLabel", {
            Size = UDim2.new(0, 62, 1, 0), Position = UDim2.fromOffset(14, 0),
            BackgroundTransparency = 1, Text = "皮肤库", TextColor3 = T.text,
            TextSize = 13, Font = Enum.Font.Gotham, TextXAlignment = Enum.TextXAlignment.Left,
        }, r)
        local b = mk("TextButton", {
            Size = UDim2.new(1, -92, 0, 34), Position = UDim2.new(0, 78, 0.5, -17),
            BackgroundColor3 = T.card2, Text = "点这里切换 →", TextColor3 = T.accent,
            TextSize = 11, Font = Enum.Font.GothamBold, AutoButtonColor = false,
            BorderSizePixel = 0, TextTruncate = Enum.TextTruncate.AtEnd,
        }, r)
        round(b, 9)
        b.MouseButton1Click:Connect(function()
            if not skinPoolBuilt then
                buildSkinPool()
            end
            if #skinPool == 0 then
                b.Text = "没扫到，试点下面手动填"
                return
            end
            skinIdx = skinIdx % #skinPool + 1
            local it = skinPool[skinIdx]
            b.Text = it.name .. " (" .. tostring(skinIdx) .. "/" .. tostring(#skinPool) .. ")"
            useSkinIndex(skinIdx)
            if not C.skin then
                C.skin = true
                setWidget("skin", true)
            end
            skinAppliedParts = setmetatable({}, {__mode = "k"})
            applySkin()
            saveCfg()
        end)
    end

    addLabel(PS, "手动指定 (填 rbxassetid://数字)")
    addInput(PS, "武器网格 MeshId", "rbxassetid://1234567890",
        function() return C.skinMesh end,
        function(v) C.skinMesh = v; skinAppliedParts = setmetatable({}, {__mode = "k"}); applySkin() end)
    addInput(PS, "贴图 TextureId (可空)", "rbxassetid://1234567890",
        function() return C.skinTexture end,
        function(v) C.skinTexture = v; skinAppliedParts = setmetatable({}, {__mode = "k"}); applySkin() end)

    addLabel(PS, "染色 / 材质")
    addToggle(PS, "开启染色", function() return C.skinColorMode end, function(v)
        C.skinColorMode = v; skinAppliedParts = setmetatable({}, {__mode = "k"}); applySkin()
    end)
    addSlider(PS, "红", 0, 255, function() return C.skinColorR end, function(v)
        C.skinColorR = v; skinColor3 = Color3.fromRGB(C.skinColorR, C.skinColorG, C.skinColorB)
        skinAppliedParts = setmetatable({}, {__mode = "k"}); applySkin()
    end)
    addSlider(PS, "绿", 0, 255, function() return C.skinColorG end, function(v)
        C.skinColorG = v; skinColor3 = Color3.fromRGB(C.skinColorR, C.skinColorG, C.skinColorB)
        skinAppliedParts = setmetatable({}, {__mode = "k"}); applySkin()
    end)
    addSlider(PS, "蓝", 0, 255, function() return C.skinColorB end, function(v)
        C.skinColorB = v; skinColor3 = Color3.fromRGB(C.skinColorR, C.skinColorG, C.skinColorB)
        skinAppliedParts = setmetatable({}, {__mode = "k"}); applySkin()
    end)
    addCycle(PS, "材质", {"保持", "金属", "塑料", "光滑", "霓虹", "力场", "玻璃"},
        function() return C.skinMaterial end,
        function(v) C.skinMaterial = v; skinAppliedParts = setmetatable({}, {__mode = "k"}); applySkin() end)
    addToggle(PS, "霓虹发光", function() return C.skinNeon end, function(v)
        C.skinNeon = v; skinAppliedParts = setmetatable({}, {__mode = "k"}); applySkin()
    end)
    addToggle(PS, "强制显示已拥有（本地 UI）", function() return C.skinForceShow end, function(v)
        C.skinForceShow = v
    end)
    addButton(PS, "立即套用一次", function()
        skinAppliedParts = setmetatable({}, {__mode = "k"})
        local n = applySkin()
        notify("已处理 " .. tostring(n) .. " 个部件")
    end)
    addButton(PS, "还原武器外观", function()
        resetSkin()
        notify("已重置，换把枪就会恢复原样")
    end, T.red)

    ------------------------------------------------------------------
    -- 移动
    ------------------------------------------------------------------
    local PM = pages["移动"]
    addLabel(PM, "基础")
    widgets.speed = addToggle(PM, "变速", function() return C.speed end, function(v)
        C.speed = v; applySpeed()
    end)
    addSlider(PM, "速度值 (正常16)", 16, 200, function() return C.speedVal end, function(v)
        C.speedVal = v; if C.speed then applySpeed() end
    end)
    widgets.fly = addToggle(PM, "飞行 (跟摇杆走)", function() return C.fly end, function(v)
        C.fly = v
        if not v then stopFly() end
    end)
    addSlider(PM, "飞行速度", 10, 250, function() return C.flyVal end, function(v) C.flyVal = v end)
    addToggle(PM, "速度随机抖动（防检测）", function() return C.speedJitter end, function(v) C.speedJitter = v end)
    widgets.noclip = addToggle(PM, "穿墙", function() return C.noclip end, function(v)
        C.noclip = v; if v then applyNoclip() end
    end)
    addSlider(PM, "滑铲推力", 20, 250, function() return C.slidePower end, function(v) C.slidePower = v end)
    addButton(PM, "立即滑铲", function() task.spawn(doSlide) end)
    widgets.bhop = addToggle(PM, "自动连跳", function() return C.bhop end, function(v) C.bhop = v end)
    addSlider(PM, "跳跃力", 30, 200, function() return C.jumpPower end, function(v)
        C.jumpPower = v; applyJump()
    end)

    addLabel(PM, "定位")
    addButton(PM, "保存当前位置", function()
        local hrp = getHRP()
        if hrp then savedPos = hrp.Position; notify("位置已保存") end
    end)
    addButton(PM, "传送回保存点", function()
        if savedPos then task.spawn(function() teleportTo(savedPos) end)
        else notify("还没保存点") end
    end)
    addButton(PM, "瞬移到最近敌人", function()
        local p = nearestEnemy()
        if p then
            task.spawn(function()
                if teleportToPlayer(p, false) then notify("已瞬移到 " .. p.Name) end
            end)
        else
            notify("附近没敌人")
        end
    end)
    addButton(PM, "瞬移到敌人头顶", function()
        local p = nearestEnemy()
        if p then
            task.spawn(function()
                if teleportToPlayer(p, true) then notify("已到 " .. p.Name .. " 头上") end
            end)
        else
            notify("附近没敌人")
        end
    end)

    addLabel(PM, "手机")
    addToggle(PM, "显示悬浮球", function() return C.fab end, function(v)
        C.fab = v
        if fabBtn then fabBtn.Visible = v end
    end)
    addToggle(PM, "显示快捷按键", function() return C.mobilePad end, function(v)
        C.mobilePad = v
        if quickBar then quickBar.Visible = v end
    end)
    addSlider(PM, "按键大小 %", 70, 160, function() return math.floor(C.padScale * 100) end, function(v)
        C.padScale = v / 100
        if quickBar then
            for _, c in ipairs(quickBar:GetChildren()) do
                if c:IsA("TextButton") then
                    c.Size = UDim2.fromOffset(math.floor(52 * C.padScale), math.floor(52 * C.padScale))
                end
            end
        end
    end)

    ------------------------------------------------------------------
    -- 反检测
    ------------------------------------------------------------------
    local PA = pages["反检测"]
    addLabel(PA, "本机层防护")
    widgets.antiKick = addToggle(PA, "拦截踢出", function() return C.antiKick end, function(v) C.antiKick = v end)
    widgets.propSpoof = addToggle(PA, "属性伪装 (读到的永远正常)", function() return C.propSpoof end, function(v) C.propSpoof = v end)
    widgets.lockProps = addToggle(PA, "锁定属性 (防游戏改回)", function() return C.lockProps end, function(v) C.lockProps = v end)
    widgets.hideInst = addToggle(PA, "实例隐藏", function() return C.hideInst end, function(v) C.hideInst = v end)
    widgets.scriptScan = addToggle(PA, "屏蔽检测脚本", function() return C.scriptScan end, function(v)
        C.scriptScan = v; if v then scanScripts(true) end
    end)
    addToggle(PA, "持续扫描", function() return C.scriptScanLoop end, function(v) C.scriptScanLoop = v end)
    addSlider(PA, "速度向量上限", 20, 200, function() return C.velCap end, function(v) C.velCap = v end)
    addButton(PA, "检测状态自检", function() notify(acStatus()) end)
    addLabel(PA, "服务端判定仍权威：飞太高、瞬移太远会被拉回，建议配合变速走小步。")

    ------------------------------------------------------------------
    -- 工具
    ------------------------------------------------------------------
    local PT = pages["工具"]
    addToggle(PT, "显示 FPS / 延迟", function() return C.showStats end, function(v) C.showStats = v end)
    addButton(PT, "保存当前配置", function() saveCfg(); notify("配置已保存") end)
    addButton(PT, "重新进服（卡住时用）", function()
        notify("正在重新进服…")
        task.delay(1, doRejoin)
    end)
    addButton(PT, "恢复默认", function()
        C.speed, C.fly, C.noclip, C.bhop, C.aim, C.silent = false, false, false, false, false, false
        C.autoFire, C.autoTrigger, C.esp, C.skin = false, false, false, false
        stopFly(); restoreWorld(); resetSkin()
        saveCfg(); notify("已恢复默认，面板状态重开生效")
    end, T.red)
    addButton(PT, "卸载辅助", function() unload() end, T.red)
    addLabel(PT, "电脑热键：右Shift 面板 · C 滑铲 · F 飞行 · V 穿墙 · G 连跳")
    addLabel(PT, "手机上直接用右下角悬浮球开关面板，快捷条点一下就走。")

    notify = function(msg)
        local box = mk("TextLabel", {
            Size = UDim2.new(0, math.min(PW - 40, 320), 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            Position = UDim2.new(0.5, -math.floor(math.min(PW - 40, 320) / 2), 0, 70),
            BackgroundColor3 = Color3.fromRGB(20, 21, 30), BackgroundTransparency = 0.03,
            Text = "  " .. tostring(msg) .. "  ", TextColor3 = T.text, TextSize = 12,
            Font = Enum.Font.Gotham, TextWrapped = true, ZIndex = 30,
        }, gui)
        round(box, 10)
        stroke(box, T.accent, 0.5)
        task.delay(2.4, function()
            if box and box.Parent then box:Destroy() end
        end)
    end

    uiCleanup = function()
        pcall(function() gui:Destroy() end)
    end

    ------------------------------------------------------------------
    -- 拖动 / 开关
    ------------------------------------------------------------------
    local dragging, startPos, startOff = false, nil, nil
    head.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            startPos = Vector2.new(input.Position.X, input.Position.Y)
            startOff = main.Position
        end
    end)
    UIS.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType ~= Enum.UserInputType.MouseMovement
        and input.UserInputType ~= Enum.UserInputType.Touch then return end
        local d = Vector2.new(input.Position.X, input.Position.Y) - startPos
        main.Position = UDim2.new(startOff.X.Scale, startOff.X.Offset + d.X,
            startOff.Y.Scale, startOff.Y.Offset + d.Y)
    end)
    UIS.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)

    btnHide.MouseButton1Click:Connect(function() main.Visible = false end)
    btnClose.MouseButton1Click:Connect(function() main.Visible = false end)
    panelToggle = function() main.Visible = not main.Visible end
    UIS.InputBegan:Connect(function(input, processed)
        if processed then return end
        if input.KeyCode == Enum.KeyCode.RightShift then
            main.Visible = not main.Visible
        end
    end)
end

--=====================================================================
-- 11. 移动端按键
--=====================================================================
do
    local function mkX(cls, props, parent)
        local o = Instance.new(cls)
        for k, v in pairs(props) do o[k] = v end
        if parent then o.Parent = parent end
        return o
    end
    local function rnd(o, r) return mkX("UICorner", {CornerRadius = UDim.new(0, r or 12)}, o) end

    local holder = (gethui and gethui()) or game:GetService("CoreGui")
    local mholder = mkX("ScreenGui", {
        Name = "zkpad" .. tostring(math.random(1000000, 9000000)),
        ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 998,
    }, nil)
    local okPad = pcall(function() mholder.Parent = holder end)
    if not okPad or not mholder.Parent then
        pcall(function() mholder.Parent = LP:WaitForChild("PlayerGui", 5) end)
    end

    ----------------------------------------------------------------
    -- 悬浮球
    ----------------------------------------------------------------
    fabBtn = mkX("TextButton", {
        Size = UDim2.fromOffset(58, 58),
        Position = UDim2.new(1, -78, 0, 100),
        BackgroundColor3 = Color3.fromRGB(18, 20, 28), BackgroundTransparency = 0.12,
        Text = "Z", TextColor3 = ACCENT, TextSize = 24, Font = Enum.Font.GothamBold,
        AutoButtonColor = false, BorderSizePixel = 0, Visible = C.fab,
    }, mholder)
    rnd(fabBtn, 29)
    mkX("UIStroke", {Color = ACCENT, Transparency = 0.4, Thickness = 1.6}, fabBtn)

    do
        local fabInput, moved, sPos, sOff = nil, false, nil, nil
        fabBtn.InputBegan:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.Touch
            or i.UserInputType == Enum.UserInputType.MouseButton1 then
                fabInput = i
                moved = false
                sPos = Vector2.new(i.Position.X, i.Position.Y)
                sOff = fabBtn.Position
            end
        end)
        UIS.InputChanged:Connect(function(i)
            if not fabInput or i ~= fabInput then return end
            local d = Vector2.new(i.Position.X, i.Position.Y) - sPos
            if d.Magnitude > 8 then moved = true end
            fabBtn.Position = UDim2.new(sOff.X.Scale, sOff.X.Offset + d.X, sOff.Y.Scale, sOff.Y.Offset + d.Y)
        end)
        UIS.InputEnded:Connect(function(i)
            if fabInput and i == fabInput then
                if not moved then pcall(panelToggle) end
                fabInput = nil
            end
        end)
    end

    ----------------------------------------------------------------
    -- 右侧快捷条
    ----------------------------------------------------------------
    quickBar = mkX("Frame", {
        Size = UDim2.fromOffset(58, 360),
        Position = UDim2.new(1, -74, 0.5, -70),
        BackgroundTransparency = 1, Visible = C.mobilePad,
    }, mholder)
    mkX("UIListLayout", {
        Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder,
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
    }, quickBar)

    local qOrd = 0
    local function quickBtn(text, cb)
        qOrd = qOrd + 1
        local size = math.floor(52 * C.padScale)
        local b = mkX("TextButton", {
            Size = UDim2.fromOffset(size, size), LayoutOrder = qOrd,
            BackgroundColor3 = Color3.fromRGB(18, 20, 28), BackgroundTransparency = 0.18,
            Text = text, TextColor3 = ACCENT, TextSize = 11, Font = Enum.Font.GothamBold,
            AutoButtonColor = false, BorderSizePixel = 0,
        }, quickBar)
        rnd(b, 14)
        mkX("UIStroke", {Color = Color3.fromRGB(90, 96, 130), Transparency = 0.5}, b)
        b.MouseButton1Click:Connect(function() pcall(cb) end)
        return b
    end

    quickBtn("滑铲", function() task.spawn(doSlide) end)
    quickBtn("飞行", function()
        C.fly = not C.fly
        setWidget("fly", C.fly)
        if not C.fly then stopFly() end
    end)
    quickBtn("穿墙", function()
        C.noclip = not C.noclip
        setWidget("noclip", C.noclip)
        if C.noclip then applyNoclip() end
    end)
    quickBtn("连跳", function()
        C.bhop = not C.bhop
        setWidget("bhop", C.bhop)
    end)
    quickBtn("跳敌", function()
        local p = nearestEnemy()
        if p then task.spawn(function() teleportToPlayer(p, true) end) end
    end)

    ----------------------------------------------------------------
    -- 飞行摇杆
    ----------------------------------------------------------------
    local joyBase = mkX("Frame", {
        Size = UDim2.fromOffset(132, 132),
        Position = UDim2.new(0, 24, 0.5, -60),
        BackgroundColor3 = Color3.fromRGB(16, 18, 26), BackgroundTransparency = 0.72,
        Visible = false, BorderSizePixel = 0,
    }, mholder)
    rnd(joyBase, 66)
    mkX("UIStroke", {Color = ACCENT, Transparency = 0.55, Thickness = 1.5}, joyBase)
    local joyKnob = mkX("Frame", {
        Size = UDim2.fromOffset(54, 54), Position = UDim2.new(0.5, -27, 0.5, -27),
        BackgroundColor3 = Color3.fromRGB(30, 34, 46), BackgroundTransparency = 0.08,
        BorderSizePixel = 0,
    }, joyBase)
    rnd(joyKnob, 27)
    mkX("UIStroke", {Color = ACCENT, Transparency = 0.3}, joyKnob)

    local joyInput = nil
    local function joyReset()
        joyInput = nil
        joyVec = Vector2.zero
        joyKnob.Position = UDim2.new(0.5, -27, 0.5, -27)
    end
    local function joyMove(px, py)
        local cx = joyBase.AbsolutePosition.X + joyBase.AbsoluteSize.X / 2
        local cy = joyBase.AbsolutePosition.Y + joyBase.AbsoluteSize.Y / 2
        local d = Vector2.new(px - cx, py - cy)
        local r = joyBase.AbsoluteSize.X / 2 - 10
        if r <= 0 or d.Magnitude < 1 then
            joyVec = Vector2.zero
            joyKnob.Position = UDim2.new(0.5, -27, 0.5, -27)
            return
        end
        local m = math.min(d.Magnitude, r)
        local u = d.Unit * m
        joyKnob.Position = UDim2.new(0.5, u.X - 27, 0.5, u.Y - 27)
        joyVec = Vector2.new(u.X / r, -u.Y / r)
    end
    joyBase.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.Touch
        or i.UserInputType == Enum.UserInputType.MouseButton1 then
            joyInput = i
            joyMove(i.Position.X, i.Position.Y)
        end
    end)
    UIS.InputChanged:Connect(function(i)
        if not joyInput or i ~= joyInput then return end
        joyMove(i.Position.X, i.Position.Y)
    end)
    UIS.InputEnded:Connect(function(i)
        if joyInput and i == joyInput then joyReset() end
    end)

    -- 之前版本遗留的滑铲按钮（保留兼容）
    slideBtn = mkX("TextButton", {
        Size = UDim2.fromOffset(1, 1), Position = UDim2.new(0, -100, 0, -100),
        BackgroundTransparency = 1, Text = "", AutoButtonColor = false, BorderSizePixel = 0,
    }, mholder)

    task.spawn(function()
        while true do
            task.wait(0.25)
            pcall(function()
                joyBase.Visible = C.fly and C.mobilePad
                fabBtn.Visible = C.fab
                quickBar.Visible = C.mobilePad
            end)
        end
    end)

    local oldCleanup = uiCleanup
    uiCleanup = function()
        pcall(oldCleanup)
        pcall(function() mholder:Destroy() end)
    end
end

--=====================================================================
-- 12. 主循环
--=====================================================================
RunService.RenderStepped:Connect(function(dt)
    local cam = Workspace.CurrentCamera
    if not cam then return end
    pcall(function()
        updateESP()
        updateCombat(cam)
        updateFly(cam)
        updateStats(dt or 0.016)
    end)
end)

local scanTick = 0
local camTick = 0

task.spawn(function()
    while true do
        task.wait(0.12)
        camTick = camTick + 1
        if C.noclip then pcall(applyNoclip) end
        if C.speed then pcall(applySpeed) end
        if C.bhop then pcall(bhopStep) end
        if C.skin and C.skinAuto and camTick % 8 == 0 then pcall(applySkin) end
        if camTick % 8 == 0 then pcall(applyCamera) end
        if C.scriptScan and C.scriptScanLoop then
            scanTick = scanTick + 1
            if scanTick >= 16 then
                scanTick = 0
                pcall(function() scanScripts(false) end)
            end
        end
    end
end)

LP.CharacterAdded:Connect(function()
    task.wait(0.8)
    local h = getHum()
    if h then
        baseSpeed = h.WalkSpeed
        pcall(function() baseJump = h.JumpPower end)
    end
    applySpeed()
    applyJump()
    if C.noclip then applyNoclip() end
    if C.fly then flying = false end
end)

--=====================================================================
-- 13. 热键
--=====================================================================
UIS.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == Enum.KeyCode.C then
        task.spawn(doSlide)
    elseif input.KeyCode == Enum.KeyCode.F then
        C.fly = not C.fly
        setWidget("fly", C.fly)
        if not C.fly then stopFly() end
        if pad then pad.Visible = C.fly and C.mobilePad end
    elseif input.KeyCode == Enum.KeyCode.V then
        C.noclip = not C.noclip
        setWidget("noclip", C.noclip)
        if C.noclip then applyNoclip() end
    elseif input.KeyCode == Enum.KeyCode.G then
        C.bhop = not C.bhop
        setWidget("bhop", C.bhop)
    end
end)

--=====================================================================
-- 14. 启动
--=====================================================================
if getgenv then
    getgenv().ZakaRivals = {
        Config = C,
        Unload = unload,
        Slide = doSlide,
        Status = acStatus,
    }
end

if not installHooks() then
    notify("执行器 hook 不可用：静默 / 反踢 失效，其余正常")
end

applySpeed()
applyJump()
skinColor3 = Color3.fromRGB(C.skinColorR, C.skinColorG, C.skinColorB)
if C.wFullbright or C.wNoFog or C.wNoShadow or C.wAmbient or C.wFps or C.wNoParticles then
    pcall(applyWorld)
end
if C.skin then
    task.spawn(function()
        task.wait(1)
        skinAppliedParts = setmetatable({}, {__mode = "k"})
        pcall(applySkin)
    end)
end

if C.scriptScan then pcall(function() scanScripts(false) end) end

notify("Zaka Rivals v4 已载入 · 点右上角悬浮球开面板")
