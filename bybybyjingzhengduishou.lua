--[[
=====================================================================
  Zaka Strike  v3.3   (BloxStrike 专用 · 手机优先 · 强自瞄 · 流畅版)
  -------------------------------------------------------------------
  · ESP 透视      方框/名字/距离/血条/骨骼/高亮/武器/指向线
  · 自瞄(强化)    目标评分(威胁/可见/距离/血量/锁头) · 多点可见探测
                  多帧速度估计预判 · 距离自适应提前量
                  两级平滑 + 死区 + 每帧转角限速 · 强锁模式(瞬时贴脸)
                  粘性锁定 · 丢目标缓冲 · 快速切目标 · 人手抖动
  · 静默自瞄      鼠标命中点 / 屏幕射线劫持 · 命中点复核
  · 自动扳机      反应延迟随机
  · 强制第三人称  覆盖游戏开镜锁第一人称 · 距离/高度/偏移/防穿墙/环绕
  · 人物旋转      全身自转 · 速度/方向可调
  · 反检测        属性伪装 · 锁定 · 实例隐藏 · 拦截踢出 · 屏蔽检测脚本
  -------------------------------------------------------------------
  性能: 每帧只做一次候选扫描 · 可见性缓存 · 列表节流 · 异步加载 WindUI
        脚本扫描低频 · 绘制对象复用 · 开局预热空转 · 相机一帧只写一次
  已移除: 飞行 / 穿墙移动 / 瞬移 / 变速 / 改跳跃（封号高发）
  执行: Delta / Codex（需 Drawing / hookmetamethod / BindToRenderStep）
  按键: 右Shift 面板 · 手机点右上角 Z
=====================================================================
]]

--=====================================================================
-- 1. 环境
--=====================================================================
local cloneref   = cloneref or function(o) return o end
local Players    = cloneref(game:GetService("Players"))
local RunService = cloneref(game:GetService("RunService"))
local UIS        = cloneref(game:GetService("UserInputService"))
local Tween      = cloneref(game:GetService("TweenService"))
local Workspace  = cloneref(game:GetService("Workspace"))
local Http       = cloneref(game:GetService("HttpService"))

local LP = Players.LocalPlayer
while not LP do task.wait(0.1); LP = Players.LocalPlayer end

local isCaller  = checkcaller or function() return true end
local getMethod = getnamecallmethod or function() return "" end
local typeOf    = typeof or type
local setRO     = setreadonly or set_readonly
local hasHooks  = (getrawmetatable ~= nil) and (hookmetamethod ~= nil) and (setRO ~= nil)
local spawnTask = task.spawn or function(f, ...) return coroutine.wrap(f)(...) end
local clock     = os.clock

local clamp = math.clamp or function(v, a, b)
    if v < a then return a elseif v > b then return b else return v end
end
local rad, deg = math.rad, math.deg

local hasDrawing = pcall(function()
    local d = Drawing.new("Square")
    d:Remove()
end)

local ACCENT  = Color3.fromRGB(0, 210, 255)
local ACC_TGT = Color3.fromRGB(255, 80, 80)
local ACC_TM  = Color3.fromRGB(120, 255, 160)

--=============================================================-
-- 2. 配置
--=====================================================================
local CFG_FILE = "ZakaStrike_cfg.json"

local C = {
    esp = false, espBox = true, espName = true, espDist = true, espHP = true,
    espChams = false, espSkel = false, espWeapon = true, espTracer = false,
    espTeam = false, espMax = 1200,

    aim = false, aimPart = "Head", aimFov = 130, aimSmooth = 38,
    aimVis = true, aimTeam = true, aimPred = 0.09, aimGravity = 0,
    aimSwitchDelay = 0.16, aimMaxTurn = 460, aimRandomize = true,
    aimOffsetY = 0, aimSticky = true, aimHysteresis = 1.5,
    aimDeadzone = 0.22, aimPriority = "威胁", aimMultipoint = true,
    aimNearBoost = true, aimPreset = "平衡",
    aimSmart = true, aimFireBoost = true, aimCamLock = false,
    aimRage = false, aimHeadBias = true, aimLostTime = 0.45,
    aimQuickSwitch = true,

    silent = false, silentFov = 220, silentTeam = true, silentValidate = true,
    autoTrigger = false, triggerFov = 16, triggerRange = 320, triggerDelay = 0.06,

    tp = false, tpDistance = 9, tpHeight = 1.6, tpSide = 0,
    tpCollide = true, tpOrbit = false, tpOrbitSpeed = 24, tpHideSelf = false,

    spin = false, spinSpeed = 220, spinReverse = false,

    antiKick = true, propSpoof = true, lockProps = true, hideInst = true,
    scriptScan = true, scriptScanLoop = true,

    showStats = true, showTarget = true, mobile = true, fab = true, padScale = 1,
}

local function loadCfg()
    if not (readfile and isfile) then return end
    local ok, exists = pcall(isfile, CFG_FILE)
    if not ok or not exists then return end
    local ok2, raw = pcall(readfile, CFG_FILE)
    if not ok2 or not raw then return end
    local ok3, data = pcall(function() return Http:JSONDecode(raw) end)
    if ok3 and type(data) == "table" then
        for k, v in pairs(data) do
            if C[k] ~= nil and type(v) == type(C[k]) then C[k] = v end
        end
    end
end

local function saveCfg()
    if not writefile then return end
    pcall(function() writefile(CFG_FILE, Http:JSONEncode(C)) end)
end

loadCfg()

--=====================================================================
-- 3. 玩家工具
--=====================================================================
local function getChar(p) p = p or LP; return p.Character end

local function getHum(p)
    local ch = getChar(p)
    if not ch then return nil end
    return ch:FindFirstChildOfClass("Humanoid")
end

local function getHRP(p)
    local ch = getChar(p)
    if not ch then return nil end
    return ch:FindFirstChild("HumanoidRootPart") or ch:FindFirstChild("Torso")
end

local function isAlive(p)
    local hum = getHum(p)
    return hum ~= nil and hum.Health > 0
end

local function sameTeam(p)
    if not p.Team or not LP.Team then return false end
    return p.Team == LP.Team
end

local function teamColor(p)
    local t = p.Team
    if t then return t.TeamColor.Color end
    return ACCENT
end

--=====================================================================
-- 4. ESP 透视
--=====================================================================
local notify = function() end
local espCache, chamCache = {}, {}
local chamFolder = nil
local aimLock = nil

local function ensureFolder()
    local cam = Workspace.CurrentCamera
    if not cam then return nil end
    if chamFolder and chamFolder.Parent then return chamFolder end
    chamFolder = Instance.new("Folder")
    chamFolder.Name = "fx"
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
            for k, v in pairs(props) do pcall(function() d[k] = v end) end
        end
        e.draws[#e.draws + 1] = d
        return d
    end
    e.box    = n("Square", {Filled = false, Thickness = 1, Transparency = 1, Color = ACCENT})
    e.name   = n("Text", {Size = 14, Center = true, Outline = true, OutlineColor = Color3.fromRGB(0, 0, 0), Transparency = 1, Color = Color3.fromRGB(255, 255, 255)})
    e.dist   = n("Text", {Size = 12, Center = true, Outline = true, OutlineColor = Color3.fromRGB(0, 0, 0), Transparency = 1, Color = ACCENT})
    e.wep    = n("Text", {Size = 11, Center = true, Outline = true, OutlineColor = Color3.fromRGB(0, 0, 0), Transparency = 1, Color = Color3.fromRGB(215, 215, 215)})
    e.hpBg   = n("Square", {Filled = true, Thickness = 1, Transparency = 0.45, Color = Color3.fromRGB(20, 20, 24)})
    e.hp     = n("Square", {Filled = true, Thickness = 1, Transparency = 0.12, Color = Color3.fromRGB(60, 230, 140)})
    e.tracer = n("Line", {Thickness = 1, Transparency = 0.55, Color = ACCENT})
    for i = 1, #BONES do
        e.lines[i] = n("Line", {Thickness = 1, Transparency = 1, Color = ACCENT})
    end
    return e
end

local function hideAll(e)
    for _, d in ipairs(e.draws) do pcall(function() d.Visible = false end) end
end

local function removeESP(p)
    local e = espCache[p]
    if e then
        for _, d in ipairs(e.draws) do pcall(function() d:Remove() end) end
        espCache[p] = nil
    end
    local hl = chamCache[p]
    if hl then pcall(function() hl:Destroy() end); chamCache[p] = nil end
end

local function applyCham(p)
    local ch = p.Character
    if not ch then return end
    local hl = chamCache[p]
    if not hl or not hl.Parent then
        hl = Instance.new("Highlight")
        hl.Name = "fx"
        hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        local f = ensureFolder()
        hl.Parent = f or ch
        chamCache[p] = hl
    end
    hl.Adornee = ch
    hl.FillTransparency = 0.68
    hl.OutlineTransparency = 0
    hl.FillColor = (p == aimLock) and ACC_TGT or ACC_TM
    hl.OutlineColor = Color3.fromRGB(255, 255, 255)
end

local function heldWeapon(ch)
    for _, d in ipairs(ch:GetChildren()) do
        if d:IsA("Tool") then return d.Name end
    end
    return ""
end

-- 玩家列表节流：0.15 秒刷一次，别每帧重建
local espList, espListAt = {}, 0
local function refreshESPList()
    local now = clock()
    if now - espListAt < 0.15 then return espList end
    espListAt = now
    local n = 0
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP and isAlive(p) and (C.espTeam or not (C.aimTeam and sameTeam(p))) then
            n = n + 1
            espList[n] = p
        end
    end
    for i = n + 1, #espList do espList[i] = nil end
    return espList
end

local espHiddenAt = 0

local function updateESP(cam)
    if not hasDrawing then return end

    if not C.esp then
        local now = clock()
        if now - espHiddenAt < 0.5 then return end
        espHiddenAt = now
        for p in pairs(espCache) do removeESP(p) end
        return
    end

    if not cam then return end
    local myHrp = getHRP()
    local seen = {}
    local list = refreshESPList()

    for i = 1, #list do
        local p = list[i]
        local ch = p.Character
        local hrp = getHRP(p)
        if ch and hrp then
            local dist = myHrp and (myHrp.Position - hrp.Position).Magnitude or 0
            if dist > C.espMax then
                local e = espCache[p]
                if e then hideAll(e) end
            else
                local cf, sz = nil, nil
                pcall(function()
                    local a, b = ch:GetBoundingBox()
                    cf, sz = a, b
                end)

                if cf and sz then
                    local e = espCache[p]
                    if not e then e = buildESP(); espCache[p] = e end
                    seen[p] = true

                    local top = cam:WorldToViewportPoint(cf.Position + Vector3.new(0, sz.Y / 2, 0))
                    local bot = cam:WorldToViewportPoint(cf.Position - Vector3.new(0, sz.Y / 2, 0))

                    if top.Z <= 0 or bot.Z <= 0 then
                        hideAll(e)
                    else
                        local h = math.abs(bot.Y - top.Y)
                        local w = h * 0.62
                        local x = math.min(top.X, bot.X) - w / 2
                        local y = math.min(top.Y, bot.Y)
                        local col = (p == aimLock) and ACC_TGT or teamColor(p)

                        e.box.Visible = C.espBox
                        e.box.Color = col
                        e.box.Size = Vector2.new(w, h)
                        e.box.Position = Vector2.new(x, y)

                        local hum = getHum(p)
                        local hp = hum and hum.Health or 0
                        local maxHp = hum and hum.MaxHealth or 100
                        local ratio = maxHp > 0 and clamp(hp / maxHp, 0, 1) or 0

                        if C.espHP then
                            e.hpBg.Visible, e.hp.Visible = true, true
                            e.hpBg.Size = Vector2.new(3, h)
                            e.hpBg.Position = Vector2.new(x - 7, y)
                            e.hp.Size = Vector2.new(3, h * ratio)
                            e.hp.Position = Vector2.new(x - 7, y + h * (1 - ratio))
                            e.hp.Color = Color3.fromRGB(
                                math.floor(60 + 195 * (1 - ratio)),
                                math.floor(60 + 170 * ratio), 90)
                        else
                            e.hpBg.Visible, e.hp.Visible = false, false
                        end

                        e.name.Visible = C.espName
                        e.name.Text = tostring(p.DisplayName or p.Name)
                        e.name.Position = Vector2.new(x + w / 2, y - 18)
                        e.name.Color = col

                        e.dist.Visible = C.espDist
                        e.dist.Text = tostring(math.floor(dist + 0.5)) .. "m"
                        e.dist.Position = Vector2.new(x + w / 2, y + h + 2)

                        e.wep.Visible = C.espWeapon
                        e.wep.Text = heldWeapon(ch)
                        e.wep.Position = Vector2.new(x + w / 2, y + h + 18)

                        if C.espTracer and myHrp then
                            local sp = cam:WorldToViewportPoint(myHrp.Position)
                            e.tracer.Visible = true
                            e.tracer.From = Vector2.new(sp.X, sp.Y + 40)
                            e.tracer.To = Vector2.new(x + w / 2, y + h / 2)
                            e.tracer.Color = col
                        else
                            e.tracer.Visible = false
                        end

                        if C.espSkel then
                            for k, pair in ipairs(BONES) do
                                local a, b = ch:FindFirstChild(pair[1]), ch:FindFirstChild(pair[2])
                                local ln = e.lines[k]
                                if a and b and a:IsA("BasePart") and b:IsA("BasePart") then
                                    local pa = cam:WorldToViewportPoint(a.Position)
                                    local pb = cam:WorldToViewportPoint(b.Position)
                                    if pa.Z > 0 and pb.Z > 0 then
                                        ln.Visible = true
                                        ln.From = Vector2.new(pa.X, pa.Y)
                                        ln.To = Vector2.new(pb.X, pb.Y)
                                        ln.Color = col
                                    else
                                        ln.Visible = false
                                    end
                                else
                                    ln.Visible = false
                                end
                            end
                        else
                            for k = 1, #BONES do e.lines[k].Visible = false end
                        end

                        if C.espChams then applyCham(p) else
                            local hl = chamCache[p]
                            if hl then pcall(function() hl:Destroy() end); chamCache[p] = nil end
                        end
                    end
                end
            end
        end
    end

    for p in pairs(espCache) do
        if not seen[p] then removeESP(p) end
    end
end

--=====================================================================
-- 5. 自瞄核心（强化 + 性能优化）
--=====================================================================
local silentTarget = nil
local lastFire = 0
local lastTargetSwitch = 0
local mouse = nil
pcall(function() mouse = LP:GetMouse() end)

local velTrack = {}
local visCache = {}
local facing = {}

local function pingSec()
    local ok, p = pcall(function() return LP:GetNetworkPing() end)
    if not ok or not p then return 0 end
    return clamp(p, 0, 0.3)
end

-- 多帧指数平滑估计速度，比读单帧 Velocity 稳
local function estVel(p, part)
    local now = clock()
    local t = velTrack[p]
    if not t then
        local raw = part.AssemblyLinearVelocity
        if typeOf(raw) ~= "Vector3" then raw = part.Velocity end
        if typeOf(raw) ~= "Vector3" then raw = Vector3.zero end
        local rec = {}
        rec.v, rec.pos, rec.t = raw, part.Position, now
        velTrack[p] = rec
        return raw
    end
    local dt = now - t.t
    if dt <= 0.0001 then return t.v end
    local inst = (part.Position - t.pos) / dt
    if inst.Magnitude > 300 then inst = inst.Unit * 300 end
    t.v = t.v:Lerp(inst, clamp(dt * 14, 0.15, 0.65))
    t.pos = part.Position
    t.t = now
    return t.v
end

local function predictPos(p, part)
    local v = estVel(p, part)
    local lead = clamp(C.aimPred + pingSec() * 0.45, 0, 0.6)
    -- 距离自适应：越远飞行时间越长，提前量按距离放大（近距离不过度前压）
    local cam = Workspace.CurrentCamera
    local myHrp = getHRP()
    local dist = 100
    if myHrp then dist = (part.Position - myHrp.Position).Magnitude end
    if dist > 80 then
        lead = lead * clamp(1 + (dist - 80) / 420, 1, 2.1)
    elseif dist < 25 then
        lead = lead * 0.75
    end
    if C.aimRage then lead = lead * 1.08 end
    local pos = part.Position + v * lead
    if C.aimGravity > 0 then
        pos = pos + Vector3.new(0, -0.5 * 196.2 * C.aimGravity * lead * lead, 0)
    end
    return pos
end

-- 复用的 RaycastParams，别每次都 new
local rayParams = RaycastParams.new()
do
    local ok = pcall(function() rayParams.FilterType = Enum.RaycastFilterType.Exclude end)
    if not ok then pcall(function() rayParams.FilterType = Enum.RaycastFilterType.Blacklist end) end
    rayParams.IgnoreWater = true
end

local rayIgnore = {}

local function isVisiblePoint(point, ch)
    local cam = Workspace.CurrentCamera
    if not cam then return true end
    local origin = cam.CFrame.Position
    local n = 0
    if ch then n = n + 1; rayIgnore[n] = ch end
    if LP.Character then n = n + 1; rayIgnore[n] = LP.Character end
    if chamFolder then n = n + 1; rayIgnore[n] = chamFolder end
    for i = n + 1, #rayIgnore do rayIgnore[i] = nil end
    rayParams.FilterDescendantsInstances = rayIgnore
    local hit = Workspace:Raycast(origin, point - origin, rayParams)
    if not hit then return true end
    return ch ~= nil and hit.Instance:IsDescendantOf(ch)
end

local CHECK_PARTS = {"Head", "UpperTorso", "HumanoidRootPart", "Torso"}

-- 多点可见：头/上躯干/根骨 任一点通即算可见，并回报第一个通的部位
local function visibleAny(ch)
    for i = 1, #CHECK_PARTS do
        local part = ch:FindFirstChild(CHECK_PARTS[i])
        if part and part:IsA("BasePart") and isVisiblePoint(part.Position, ch) then
            return true, part
        end
    end
    return false, nil
end

-- 可见性缓存 0.1 秒，避免每帧对整个视野做射线
local function getVisible(p, ch)
    local now = clock()
    local c = visCache[p]
    if c and now - c.t < 0.1 then return c.v, c.part end
    local v, part = visibleAny(ch)
    visCache[p] = {v = v, t = now, part = v and part or nil}
    return v, visCache[p].part
end

local function aimPartOf(ch)
    local p = ch:FindFirstChild(C.aimPart)
    if p and p:IsA("BasePart") then return p end
    local head = ch:FindFirstChild("Head")
    if head then return head end
    return ch:FindFirstChild("UpperTorso") or ch:FindFirstChild("HumanoidRootPart") or ch:FindFirstChild("Torso")
end

local function threatOf(p)
    local now = clock()
    local cache = facing[p]
    if cache and now - cache.t < 0.3 then return cache.v end
    local v = 0
    local hrp = getHRP(p)
    local me = getHRP()
    if hrp and me then
        local toMe = me.Position - hrp.Position
        if toMe.Magnitude > 0.1 then
            local dot = hrp.CFrame.LookVector:Dot(toMe.Unit)
            if dot > 0.55 then v = 1 elseif dot > 0.2 then v = 0.5 end
        end
    end
    facing[p] = {t = now, v = v}
    return v
end

-- 每帧只扫一次的候选池（复用表，零分配）
local cands = {}
local candN = 0
local aliveList, aliveAt = {}, 0

local function refreshAlive()
    local now = clock()
    if now - aliveAt < 0.15 then return aliveList end
    aliveAt = now
    local n = 0
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP and isAlive(p) and not (C.aimTeam and sameTeam(p)) then
            n = n + 1
            aliveList[n] = p
        end
    end
    for i = n + 1, #aliveList do aliveList[i] = nil end
    return aliveList
end

local function buildCands(cam)
    candN = 0
    if not cam then return end
    local vp = cam.ViewportSize
    local cx, cy = vp.X / 2, vp.Y / 2
    local myHrp = getHRP()
    local maxFov = C.aimFov * C.aimHysteresis
    if C.silent and C.silentFov > maxFov then maxFov = C.silentFov end
    if C.autoTrigger and C.triggerFov > maxFov then maxFov = C.triggerFov end
    local visOnly = C.aimVis
    local list = refreshAlive()

    for i = 1, #list do
        local p = list[i]
        local ch = p.Character
        local part = ch and aimPartOf(ch)
        if part then
            local sp, on = cam:WorldToViewportPoint(part.Position)
            if on then
                local dx, dy = sp.X - cx, sp.Y - cy
                local d = math.sqrt(dx * dx + dy * dy)
                if d <= maxFov then
                    local visible, visPart = getVisible(p, ch)
                    -- 智能选点：头被掩体挡住就打可见的那个部位（上躯干/根骨）
                    if C.aimSmart and visPart then part = visPart end
                    if visible or not visOnly then
                        candN = candN + 1
                        local c = cands[candN]
                        if not c then c = {}; cands[candN] = c end
                        c.plr = p
                        c.part = part
                        c.dist = d
                        c.world = myHrp and (part.Position - myHrp.Position).Magnitude or 0
                        c.visible = visible
                    end
                end
            end
        end
    end
end

local function scoreOf(c)
    local s = c.dist
    if not c.visible then s = s * 2.2 end
    -- 锁头优先：同一个目标能打到头就别打身子
    if C.aimHeadBias and c.part and c.part.Name == "Head" then
        s = s - (c.visible and 70 or 40)
    end
    if C.aimPriority == "威胁" then
        s = s - threatOf(c.plr) * 90
    elseif C.aimPriority == "血量" then
        local hum = getHum(c.plr)
        local hp = hum and hum.Health or 999
        s = s + hp * 1.6
    elseif C.aimPriority == "距离" then
        s = s * 0.5 + c.world * 0.8
    end
    return s
end

-- 从候选池里挑：范围 fov 内，按 score 最小
local function pickFromCands(fov, requireVisible)
    local best, bestScore = nil, math.huge
    for i = 1, candN do
        local c = cands[i]
        if c.dist <= fov and ((not requireVisible) or c.visible) then
            local s = scoreOf(c)
            if s < bestScore then bestScore, best = s, c end
        end
    end
    return best, bestScore
end

local function humanize(pos, dist)
    if not C.aimRandomize then return pos end
    local scale = clamp(dist / 320, 0.12, 1) * 0.09
    local t = clock()
    local ox = math.sin(t * 5.3) * scale + (math.random() - 0.5) * scale
    local oy = math.cos(t * 4.1) * scale + (math.random() - 0.5) * scale
    return pos + Vector3.new(ox, oy, 0)
end

local function chooseTarget(cam)
    local best = pickFromCands(C.aimFov, C.aimVis)

    -- 目标暂时掉出 FOV 时给个缓冲，别来回跳
    if not best and aimLock and isAlive(aimLock) then
        local ch = aimLock.Character
        local part = ch and aimPartOf(ch)
        if part then
            local sp, on = cam:WorldToViewportPoint(part.Position)
            if on then
                local vp = cam.ViewportSize
                local dx, dy = sp.X - vp.X / 2, sp.Y - vp.Y / 2
                if math.sqrt(dx * dx + dy * dy) <= C.aimFov * math.max(C.aimHysteresis, 1.6) then
                    return {plr = aimLock, part = part, dist = 0, world = 0, visible = true}
                end
            end
        end
    end

    if not best then return nil end

    -- 切目标冷却：强锁模式下打折，粘手但不拖沓
    local switchGap = C.aimSwitchDelay
    if C.aimQuickSwitch then switchGap = switchGap * 0.5 end
    if C.aimRage then switchGap = switchGap * 0.5 end

    if C.aimSticky and aimLock then
        local cur = nil
        local curScore = math.huge
        for i = 1, candN do
            if cands[i].plr == aimLock then
                cur = cands[i]
                curScore = scoreOf(cur)
                break
            end
        end
        if cur then
            local canSwitch = clock() - lastTargetSwitch > switchGap
            local bestScore = scoreOf(best)
            if best.plr == aimLock or not canSwitch then return cur end
            if bestScore < curScore * (C.aimQuickSwitch and 0.75 or 0.6) then
                lastTargetSwitch = clock()
                return best
            end
            return cur
        end
    end

    if best.plr ~= aimLock then
        if clock() - lastTargetSwitch < switchGap then
            if aimLock and isAlive(aimLock) then
                local ch = aimLock.Character
                local part = ch and aimPartOf(ch)
                if part then
                    return {plr = aimLock, part = part, dist = 99, world = best.world, visible = true}
                end
            end
            return nil
        end
        lastTargetSwitch = clock()
    end
    return best
end

-- 自瞄只计算"想看哪儿"，真正转相机交给相机驱动统一做（避免和第三人称互相盖）
local aimGoalPos = nil
local aimActiveAt = 0
local firingNow = false

local function fireWeapon()
    if mouse1click then
        pcall(mouse1click)
    elseif mouse1press and mouse1release then
        pcall(mouse1press); pcall(mouse1release)
    end
end

local fovCircle, statText, targetText
if hasDrawing then
    fovCircle = Drawing.new("Circle")
    fovCircle.Thickness = 1
    fovCircle.NumSides = 72
    fovCircle.Filled = false
    fovCircle.Transparency = 0.8
    fovCircle.Color = ACCENT
    fovCircle.Visible = false

    statText = Drawing.new("Text")
    statText.Size = 14
    statText.Center = false
    statText.Outline = true
    statText.OutlineColor = Color3.fromRGB(0, 0, 0)
    statText.Color = ACCENT
    statText.Visible = false

    targetText = Drawing.new("Text")
    targetText.Size = 13
    targetText.Center = false
    targetText.Outline = true
    targetText.OutlineColor = Color3.fromRGB(0, 0, 0)
    targetText.Color = ACC_TGT
    targetText.Visible = false
end

local function updateAim(cam, dt)
    if not cam then return end

    -- 一帧只扫一次，自瞄/静默/扳机共用
    buildCands(cam)

    local target = nil
    if C.aim then target = chooseTarget(cam) end

    if target then
        aimLock = target.plr
    elseif aimLock and not isAlive(aimLock) then
        aimLock = nil
    end

    silentTarget = nil
    if C.silent then
        local c = pickFromCands(C.silentFov, false)
        if c and ((not C.silentValidate) or c.visible) then
            silentTarget = {plr = c.plr, part = c.part, pos = predictPos(c.plr, c.part)}
        end
    end

    if fovCircle then
        local show = C.aim or C.silent
        fovCircle.Visible = show
        if show then
            local vp = cam.ViewportSize
            fovCircle.Position = Vector2.new(vp.X / 2, vp.Y / 2)
            fovCircle.Radius = C.aim and C.aimFov or C.silentFov
            fovCircle.Color = C.aim and ACCENT or ACC_TM
        end
    end

    if target and target.part then
        local goalPos = predictPos(target.plr, target.part) + Vector3.new(0, C.aimOffsetY, 0)
        aimGoalPos = humanize(goalPos, target.world)
        aimActiveAt = clock()
    else
        -- 目标丢了先留一会儿，别一抖一抖地放手
        if clock() - aimActiveAt > C.aimLostTime then aimGoalPos = nil end
    end

    if C.aimFireBoost then
        local ok, pressed = pcall(function() return UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) end)
        firingNow = ok and pressed or false
    end

    if C.autoTrigger then
        local t = pickFromCands(C.triggerFov, true)
        if t and t.world <= C.triggerRange then
            if clock() - lastFire > C.triggerDelay + math.random() * 0.04 then
                lastFire = clock()
                fireWeapon()
            end
        end
    end

    if targetText then
        if C.showTarget and target then
            local hum = getHum(target.plr)
            local tag = target.visible and "" or " [墙后]"
            targetText.Text = "锁定 " .. tostring(target.plr.Name) .. tag ..
                "  " .. math.floor(target.dist) .. "px  HP " .. math.floor(hum and hum.Health or 0)
            targetText.Position = Vector2.new(14, 40)
            targetText.Visible = true
        else
            targetText.Visible = false
        end
    end
end

local fpsAcc, fpsFrames, fpsShown, pingShown = 0, 0, 0, 0

local function updateStats(dt)
    if not statText then return end
    if not C.showStats then statText.Visible = false; return end

    fpsAcc, fpsFrames = fpsAcc + dt, fpsFrames + 1
    if fpsAcc >= 0.5 then
        fpsShown = math.floor(fpsFrames / fpsAcc + 0.5)
        fpsAcc, fpsFrames = 0, 0
        pingShown = math.floor(pingSec() * 1000)
    end
    local cam = Workspace.CurrentCamera
    local h = cam and cam.ViewportSize.Y or 400
    statText.Text = "FPS " .. fpsShown .. "  |  " .. pingShown .. "ms"
    statText.Position = Vector2.new(14, h - 64)
    statText.Visible = true
end

local function applyPreset(name)
    C.aimPreset = name
    if name == "稳健" then
        C.aimSmooth, C.aimMaxTurn, C.aimSwitchDelay = 65, 150, 0.35
        C.aimFov, C.aimPred, C.aimRandomize = 80, 0.06, true
        C.aimRage, C.aimHeadBias = false, true
    elseif name == "平衡" then
        C.aimSmooth, C.aimMaxTurn, C.aimSwitchDelay = 38, 460, 0.16
        C.aimFov, C.aimPred, C.aimRandomize = 130, 0.09, true
        C.aimRage = false
    elseif name == "强硬" then
        C.aimSmooth, C.aimMaxTurn, C.aimSwitchDelay = 20, 620, 0.07
        C.aimFov, C.aimPred, C.aimRandomize = 170, 0.1, false
        C.aimRage = false
    elseif name == "强锁" then
        C.aimSmooth, C.aimMaxTurn, C.aimSwitchDelay = 6, 900, 0.03
        C.aimFov, C.aimPred, C.aimRandomize = 200, 0.11, false
        C.aimRage, C.aimHeadBias = true, true
    end
    saveCfg()
end

--=====================================================================
-- 6. 相机统一驱动（强制第三人称 + 自瞄，一个出口，绝不互相盖）
--=====================================================================
local tpOrbitAngle = 0
local camBound = false
local camOwned, savedCamType = false, nil
local visRestoreAt = 0

local function restoreSelfVisibility(force)
    local now = clock()
    if not force and now - visRestoreAt < 0.1 then return end
    visRestoreAt = now
    local ch = LP.Character
    if not ch then return end
    local want = (C.tp and C.tpHideSelf) and 1 or 0
    for _, d in ipairs(ch:GetDescendants()) do
        if d:IsA("BasePart") then
            pcall(function() d.LocalTransparencyModifier = want end)
        end
    end
end

-- 游戏想锁第一人称（开镜/强制模式）时，把它按回第三人称
local function enforceThirdPerson()
    pcall(function()
        if LP.CameraMode ~= Enum.CameraMode.Classic then
            LP.CameraMode = Enum.CameraMode.Classic
        end
        if LP.CameraMaxZoomDistance < C.tpDistance + 2 then
            LP.CameraMaxZoomDistance = C.tpDistance + 2
        end
        if LP.CameraMinZoomDistance > 0.5 then
            LP.CameraMinZoomDistance = 0.5
        end
    end)
end

local function tpFocus(hrp)
    return hrp.Position + Vector3.new(0, C.tpHeight, 0)
end

-- 相机被挡时收缩距离（复用 rayParams，不新建对象）
local function safeCamDist(focus, dir, want)
    if not C.tpCollide then return want end
    local n = 0
    if LP.Character then n = n + 1; rayIgnore[n] = LP.Character end
    if chamFolder then n = n + 1; rayIgnore[n] = chamFolder end
    for i = n + 1, #rayIgnore do rayIgnore[i] = nil end
    rayParams.FilterDescendantsInstances = rayIgnore
    local res = Workspace:Raycast(focus, -dir * want, rayParams)
    if res then
        return clamp((res.Position - focus).Magnitude - 0.6, 1.2, want)
    end
    return want
end

-- 方向插值：用 CFrame 的四元数插值，反向目标也不会退化成乱转
local function rotLerpDir(curDir, goalDir, alpha)
    local ok, nd = pcall(function()
        local c0 = CFrame.lookAt(Vector3.zero, curDir)
        local c1 = CFrame.lookAt(Vector3.zero, goalDir)
        return c0:Lerp(c1, alpha).LookVector
    end)
    if ok and nd and nd.Magnitude > 0.01 then return nd.Unit end
    local v = curDir:Lerp(goalDir, alpha)
    if v.Magnitude < 0.01 then return goalDir end
    return v.Unit
end

-- 自瞄收敛：给定当前朝向，返回本帧该用的朝向（只算，不碰相机）
local function convergeDir(curDir, dt)
    if not aimGoalPos then return curDir end
    local cam = Workspace.CurrentCamera
    if not cam then return curDir end
    local toGoal = aimGoalPos - cam.CFrame.Position
    if toGoal.Magnitude < 0.6 then return curDir end
    local goalDir = toGoal.Unit

    local ang = deg(math.acos(clamp(curDir:Dot(goalDir), -1, 1)))
    if ang <= C.aimDeadzone then return curDir end

    local gain, maxTurn
    if C.aimRage then
        -- 强锁：几乎瞬时贴上去
        gain = 0.9
        maxTurn = math.max(C.aimMaxTurn, 900)
    else
        local base = clamp((100 - C.aimSmooth) / 100, 0.02, 0.98)
        gain = base
        if ang > 60 then
            gain = clamp(base * 1.9 + 0.12, 0.05, 0.96)
        elseif ang > 20 then
            gain = clamp(base * 1.35 + 0.06, 0.04, 0.92)
        end
        if C.aimNearBoost then gain = clamp(gain * 1.15, 0, 0.98) end
        if C.aimFireBoost and firingNow then gain = clamp(gain * 1.35, 0, 0.99) end
        maxTurn = C.aimMaxTurn
    end

    local maxStep = maxTurn * math.max(dt, 1 / 240)
    local step = math.min(ang * gain, maxStep)
    local alpha = clamp(step / math.max(ang, 0.0001), 0.004, 1)
    return rotLerpDir(curDir, goalDir, alpha)
end

-- 只有开了"相机锁定"才接管镜头类型；接管后游戏镜头脚本盖不掉
local function acquireCam()
    local cam = Workspace.CurrentCamera
    if not cam or camOwned then return end
    savedCamType = cam.CameraType
    camOwned = true
    pcall(function() cam.CameraType = Enum.CameraType.Scriptable end)
end

local function releaseCam()
    if not camOwned then return end
    local cam = Workspace.CurrentCamera
    pcall(function()
        if cam and savedCamType then cam.CameraType = savedCamType end
    end)
    camOwned = false
end

-- 每帧相机总装：先定方向，再定位置，最后只写一次
-- 第三人称和自瞄都走这里，物理上不可能互相盖
local function camStep(dt)
    local cam = Workspace.CurrentCamera
    if not cam then return end

    if C.tp then enforceThirdPerson() end

    -- 1) 基准方向
    local dir = cam.CFrame.LookVector
    if C.tp and C.tpOrbit then
        tpOrbitAngle = tpOrbitAngle + rad(C.tpOrbitSpeed) * dt
        dir = (CFrame.Angles(0, tpOrbitAngle, 0)).LookVector
    end

    -- 2) 自瞄叠方向
    local aiming = aimGoalPos ~= nil and (C.aim or C.silent)
    if aiming then
        if C.aimCamLock then acquireCam() end
        dir = convergeDir(dir, dt)
    elseif camOwned then
        releaseCam()
    end

    -- 3) 定位置 + 唯一一次写入
    local hrp = getHRP()
    if C.tp and hrp then
        local focus = tpFocus(hrp)
        local dist = safeCamDist(focus, dir, C.tpDistance)
        local pos = focus - dir * dist
        if C.tpSide ~= 0 then
            local right = Vector3.new(dir.Z, 0, -dir.X)
            if right.Magnitude > 0.01 then pos = pos + right.Unit * C.tpSide end
        end
        pcall(function() cam.CFrame = CFrame.lookAt(pos, pos + dir) end)
        restoreSelfVisibility()
    elseif aiming then
        local pos = cam.CFrame.Position
        pcall(function() cam.CFrame = CFrame.lookAt(pos, pos + dir) end)
    end
end
local function bindTP()
    if camBound then return end
    camBound = true
    pcall(function()
        RunService:BindToRenderStep("ZakaCam", Enum.RenderPriority.Camera.Value + 1, camStep)
    end)
end

local function unbindTP()
    if not camBound then return end
    pcall(function() RunService:UnbindFromRenderStep("ZakaCam") end)
    pcall(releaseCam)
    camBound = false
end

--=====================================================================
-- 7. 人物旋转
--=====================================================================
local spinAngle = 0

local function spinStep(dt)
    local hrp = getHRP()
    local hum = getHum()
    if not hrp or not hum then return end
    pcall(function() hum.AutoRotate = false end)
    local speed = rad(C.spinSpeed) * (C.spinReverse and -1 or 1)
    spinAngle = (spinAngle + speed * dt) % (math.pi * 2)
    pcall(function()
        hrp.CFrame = CFrame.new(hrp.Position) * CFrame.Angles(0, spinAngle, 0)
    end)
end

local function stopSpin()
    local hum = getHum()
    if hum then pcall(function() hum.AutoRotate = true end) end
end

--=====================================================================
-- 8. 反检测层
--=====================================================================
local kickCount, blockCount = 0, 0
local mt, oldIndex, oldNamecall, oldNewindex = nil, nil, nil, nil
local filtering = false
local hiddenInst = setmetatable({}, {__mode = "k"})
local baseSpeed = 16

local function installedOK() return mt ~= nil end

local function installHooks()
    if not hasHooks then return false end
    mt = getrawmetatable(game)
    if not mt then return false end
    pcall(setRO, mt, false)
    oldIndex, oldNamecall, oldNewindex = mt.__index, mt.__namecall, mt.__newindex
    if type(oldIndex) ~= "function" or type(oldNamecall) ~= "function" then return false end
    local wrap = newcclosure or function(f) return f end

    mt.__index = wrap(function(self, key)
        if not isCaller() then
            if C.propSpoof and key == "WalkSpeed" then
                if typeOf(self) == "Instance" and self:IsA("Humanoid")
                    and LP.Character and self.Parent == LP.Character then
                    return baseSpeed
                end
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
        end
        return oldIndex(self, key)
    end)

    if type(oldNewindex) == "function" then
        mt.__newindex = wrap(function(self, key, value)
            if not isCaller() and C.lockProps and typeOf(self) == "Instance" then
                if key == "WalkSpeed" or key == "JumpPower" then
                    if self:IsA("Humanoid") and LP.Character and self.Parent == LP.Character then
                        blockCount = blockCount + 1
                        return
                    end
                end
            end
            return oldNewindex(self, key, value)
        end)
    end

    mt.__namecall = wrap(function(self, ...)
        local method = getMethod()
        if not isCaller() then
            if C.antiKick and method == "Kick" and (self == LP or self == Players) then
                kickCount = kickCount + 1
                spawnTask(function() notify("已拦截一次踢出 (" .. kickCount .. ")") end)
                return nil
            end

            if C.silent and silentTarget and self == Workspace.CurrentCamera then
                if method == "ScreenPointToRay" or method == "ViewportPointToRay" then
                    local origin = Workspace.CurrentCamera.CFrame.Position
                    return Ray.new(origin, (silentTarget.pos - origin).Unit)
                end
            end

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
                if method == "FindFirstChild" or method == "FindFirstChildOfClass" or method == "FindFirstChildWhichIsA" then
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
    if not mt then return end
    pcall(function()
        if oldIndex then mt.__index = oldIndex end
        if oldNamecall then mt.__namecall = oldNamecall end
        if oldNewindex then mt.__newindex = oldNewindex end
        if setRO then setRO(mt, true) end
    end)
    mt, oldIndex, oldNamecall, oldNewindex = nil, nil, nil, nil
end

-- 低频扫描：整棵游戏树遍历很贵，20 秒一次且限量
local blocked = {}
local function scanScripts(report)
    local found, walked = 0, 0
    local pats = {"anticheat", "anti_cheat", "detect", "guard", "watchdog", "shield", "exploit"}
    pcall(function()
        for _, d in ipairs(game:GetDescendants()) do
            walked = walked + 1
            if walked > 12000 then break end
            if (d:IsA("Script") or d:IsA("LocalScript")) and not blocked[d] then
                local n = string.lower(d.Name)
                for _, p in ipairs(pats) do
                    if string.find(n, p, 1, true) and d.Parent ~= LP.Character then
                        blocked[d] = true
                        pcall(function() d.Disabled = true end)
                        found = found + 1
                        break
                    end
                end
            end
        end
    end)
    if report then
        notify(found > 0 and ("已屏蔽 " .. found .. " 个检测脚本") or "没扫到明显的检测脚本")
    end
    return found
end

local function acStatus()
    local n = 0
    for _ in pairs(blocked) do n = n + 1 end
    return "钩子: " .. (installedOK() and "已安装" or "不可用") ..
        "\n拦截写入: " .. blockCount ..
        "\n拦截踢出: " .. kickCount ..
        "\n屏蔽脚本: " .. n
end

--=====================================================================
-- 9. 界面基础件
--=====================================================================
local uiCleanup = function() end
local panelToggle = function() end
local fabBtn, quickBar, mainFrame, fallbackGui
local uiConns = {}
local function track(c) uiConns[#uiConns + 1] = c; return c end

local function newGui(name, holder)
    local gui = Instance.new("ScreenGui")
    gui.Name = name
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    if not holder then
        local ok, h = pcall(function() return gethui and gethui() or game:GetService("CoreGui") end)
        holder = ok and h or LP:FindFirstChildOfClass("PlayerGui")
    end
    gui.Parent = holder
    if syn and syn.protect_gui then pcall(syn.protect_gui, gui)
    elseif protect_gui then pcall(protect_gui, gui) end
    return gui
end

local function corner(f, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r or 8)
    c.Parent = f
end

local function stroke(f, col, th)
    local s = Instance.new("UIStroke")
    s.Color = col or Color3.fromRGB(60, 70, 80)
    s.Thickness = th or 1
    s.Parent = f
end

local function mkText(parent, txt, size, bold)
    local t = Instance.new("TextLabel")
    t.BackgroundTransparency = 1
    t.Text = txt
    t.TextSize = size or 14
    t.Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham
    t.TextColor3 = Color3.fromRGB(235, 240, 245)
    t.TextXAlignment = Enum.TextXAlignment.Left
    t.Parent = parent
    return t
end

local function addLabel(parent, txt)
    local l = mkText(parent, txt, 12)
    l.Size = UDim2.new(1, -16, 0, 30)
    l.TextWrapped = true
    l.TextColor3 = Color3.fromRGB(140, 195, 225)
    return l
end

local function addButton(parent, txt, cb)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, -16, 0, 42)
    b.BackgroundColor3 = Color3.fromRGB(38, 46, 56)
    b.TextColor3 = Color3.fromRGB(235, 240, 245)
    b.Font = Enum.Font.GothamMedium
    b.TextSize = 14
    b.Text = txt
    b.Parent = parent
    corner(b, 8); stroke(b, Color3.fromRGB(70, 85, 100))
    track(b.MouseButton1Click:Connect(function() pcall(cb) end))
    return b
end

local function addToggle(parent, txt, getter, setter)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, -16, 0, 46)
    row.BackgroundColor3 = Color3.fromRGB(28, 34, 42)
    row.Parent = parent
    corner(row, 8)

    local label = mkText(row, txt, 14)
    label.Size = UDim2.new(1, -76, 1, 0)
    label.Position = UDim2.new(0, 12, 0, 0)

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0, 54, 0, 30)
    btn.Position = UDim2.new(1, -64, 0.5, -15)
    btn.BackgroundColor3 = Color3.fromRGB(60, 70, 80)
    btn.Text = ""
    btn.Parent = row
    corner(btn, 15)

    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0, 24, 0, 24)
    knob.Position = UDim2.new(0, 3, 0.5, -12)
    knob.BackgroundColor3 = Color3.fromRGB(222, 228, 236)
    knob.Parent = btn
    corner(knob, 12)

    local state = getter() and true or false
    local function render()
        Tween:Create(btn, TweenInfo.new(0.15), {BackgroundColor3 = state and ACCENT or Color3.fromRGB(60, 70, 80)}):Play()
        Tween:Create(knob, TweenInfo.new(0.15), {Position = state and UDim2.new(1, -27, 0.5, -12) or UDim2.new(0, 3, 0.5, -12)}):Play()
    end
    render()

    track(btn.MouseButton1Click:Connect(function()
        state = not state
        render()
        pcall(setter, state)
        saveCfg()
    end))
    return {set = function(v) state = v; render() end}
end

local function addSlider(parent, txt, min, max, getter, setter, step)
    step = step or 1
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, -16, 0, 62)
    row.BackgroundColor3 = Color3.fromRGB(28, 34, 42)
    row.Parent = parent
    corner(row, 8)

    local label = mkText(row, txt, 13)
    label.Size = UDim2.new(0.7, -12, 0, 24)
    label.Position = UDim2.new(0, 12, 0, 4)

    local val = mkText(row, tostring(math.floor(getter())), 13)
    val.Size = UDim2.new(0.3, -12, 0, 24)
    val.Position = UDim2.new(0.7, 0, 0, 4)
    val.TextXAlignment = Enum.TextXAlignment.Right
    val.TextColor3 = ACCENT

    local bar = Instance.new("TextButton")
    bar.Size = UDim2.new(1, -24, 0, 10)
    bar.Position = UDim2.new(0, 12, 0, 38)
    bar.BackgroundColor3 = Color3.fromRGB(48, 58, 70)
    bar.Text = ""
    bar.Parent = row
    corner(bar, 5)

    local fill = Instance.new("Frame")
    fill.Size = UDim2.new(0, 0, 1, 0)
    fill.BackgroundColor3 = ACCENT
    fill.BorderSizePixel = 0
    fill.Parent = bar
    corner(fill, 5)

    local function render()
        local v = clamp(getter(), min, max)
        local rel = (max > min) and ((v - min) / (max - min)) or 0
        fill.Size = UDim2.new(rel, 0, 1, 0)
        val.Text = tostring(math.floor(v))
    end
    render()

    local dragging = false
    local function setFromX(x)
        local rel = clamp((x - bar.AbsolutePosition.X) / math.max(bar.AbsoluteSize.X, 1), 0, 1)
        local v = min + (max - min) * rel
        v = math.floor(v / step + 0.5) * step
        pcall(setter, v)
        render()
    end

    track(bar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            setFromX(input.Position.X)
        end
    end))
    track(UIS.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            setFromX(input.Position.X)
        end
    end))
    track(UIS.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            if dragging then dragging = false; saveCfg() end
        end
    end))
    return {set = function(v) pcall(setter, v); render() end}
end

local function pageList(holder, names)
    local pages, tabs = {}, {}

    local bar = Instance.new("Frame")
    bar.Size = UDim2.new(1, -16, 0, 34)
    bar.Position = UDim2.new(0, 8, 0, 46)
    bar.BackgroundTransparency = 1
    bar.Parent = holder

    local list = Instance.new("UIListLayout")
    list.FillDirection = Enum.FillDirection.Horizontal
    list.Padding = UDim.new(0, 6)
    list.Parent = bar

    local body = Instance.new("ScrollingFrame")
    body.Size = UDim2.new(1, -16, 1, -90)
    body.Position = UDim2.new(0, 8, 0, 86)
    body.BackgroundColor3 = Color3.fromRGB(16, 20, 26)
    body.BorderSizePixel = 0
    body.ScrollBarThickness = 4
    body.Parent = holder
    corner(body, 10)
    body.AutomaticCanvasSize = Enum.AutomaticSize.Y

    local pad = Instance.new("UIPadding")
    pad.PaddingTop = UDim.new(0, 8)
    pad.PaddingLeft = UDim.new(0, 8)
    pad.PaddingRight = UDim.new(0, 8)
    pad.Parent = body

    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 8)
    layout.Parent = body

    for _, name in ipairs(names) do
        local page = Instance.new("Frame")
        page.Size = UDim2.new(1, 0, 0, 0)
        page.BackgroundTransparency = 1
        page.Visible = false
        page.Parent = body
        page.AutomaticSize = Enum.AutomaticSize.Y

        local pl = Instance.new("UIListLayout")
        pl.Padding = UDim.new(0, 8)
        pl.Parent = page

        local tab = Instance.new("TextButton")
        tab.Size = UDim2.new(0, 0, 1, 0)
        tab.AutomaticSize = Enum.AutomaticSize.X
        tab.BackgroundColor3 = Color3.fromRGB(32, 40, 50)
        tab.Text = name
        tab.Font = Enum.Font.GothamMedium
        tab.TextSize = 13
        tab.TextColor3 = Color3.fromRGB(210, 220, 230)
        tab.Parent = bar
        corner(tab, 8)

        local tp = Instance.new("UIPadding")
        tp.PaddingLeft = UDim.new(0, 10)
        tp.PaddingRight = UDim.new(0, 10)
        tp.Parent = tab

        pages[name] = page
        tabs[name] = tab

        track(tab.MouseButton1Click:Connect(function()
            for n, pg in pairs(pages) do pg.Visible = (n == name) end
            for n, tb in pairs(tabs) do
                tb.BackgroundColor3 = (n == name) and ACCENT or Color3.fromRGB(32, 40, 50)
            end
        end))
    end

    pages[names[1]].Visible = true
    tabs[names[1]].BackgroundColor3 = ACCENT
    return pages
end

--=====================================================================
-- 9-A. 手机面板（先建，保证秒开）
--=====================================================================
local function buildFallback()
    local gui = newGui("ZakaStrikeUI")
    fallbackGui = gui

    mainFrame = Instance.new("Frame")
    mainFrame.Size = UDim2.new(0, 334, 0, 468)
    mainFrame.Position = UDim2.new(0.5, -167, 0.5, -234)
    mainFrame.BackgroundColor3 = Color3.fromRGB(20, 24, 30)
    mainFrame.BackgroundTransparency = 0.05
    mainFrame.Visible = false
    mainFrame.Parent = gui
    corner(mainFrame, 14)
    stroke(mainFrame, Color3.fromRGB(60, 80, 96), 1)

    local title = mkText(mainFrame, "Zaka Strike v3.3", 15, true)
    title.Size = UDim2.new(1, -70, 0, 44)
    title.Position = UDim2.new(0, 14, 0, 4)
    title.TextColor3 = ACCENT

    local close = Instance.new("TextButton")
    close.Size = UDim2.new(0, 40, 0, 32)
    close.Position = UDim2.new(1, -50, 0, 8)
    close.BackgroundColor3 = Color3.fromRGB(50, 58, 68)
    close.Text = "×"
    close.TextSize = 20
    close.TextColor3 = Color3.fromRGB(235, 240, 245)
    close.Font = Enum.Font.GothamBold
    close.Parent = mainFrame
    corner(close, 8)
    track(close.MouseButton1Click:Connect(function() mainFrame.Visible = false end))

    local pages = pageList(mainFrame, {"自瞄", "透视", "视角", "反检测", "设置"})

    do
        local p = pages["自瞄"]
        addLabel(p, "强度预设")
        addButton(p, "稳健 (最难被看出)", function() applyPreset("稳健"); notify("已切到稳健") end)
        addButton(p, "平衡 (推荐)", function() applyPreset("平衡"); notify("已切到平衡") end)
        addButton(p, "强硬 (跟手最快)", function() applyPreset("强硬"); notify("已切到强硬") end)
        addButton(p, "强锁 (瞬时贴脸)", function() applyPreset("强锁"); notify("已切到强锁") end)
        addToggle(p, "自瞄", function() return C.aim end, function(v) C.aim = v end)
        addToggle(p, "强锁模式", function() return C.aimRage end, function(v) C.aimRage = v end)
        addToggle(p, "锁头优先", function() return C.aimHeadBias end, function(v) C.aimHeadBias = v end)
        addToggle(p, "快速切目标", function() return C.aimQuickSwitch end, function(v) C.aimQuickSwitch = v end)
        addSlider(p, "FOV", 20, 400, function() return C.aimFov end, function(v) C.aimFov = v end)
        addSlider(p, "平滑(大=慢)", 0, 95, function() return C.aimSmooth end, function(v) C.aimSmooth = v end)
        addSlider(p, "单帧最大转角", 30, 900, function() return C.aimMaxTurn end, function(v) C.aimMaxTurn = v end)
        addSlider(p, "预判 x100", 0, 60, function() return math.floor(C.aimPred * 100) end, function(v) C.aimPred = v / 100 end)
        addSlider(p, "切目标冷却 x100", 0, 150, function() return math.floor(C.aimSwitchDelay * 100) end, function(v) C.aimSwitchDelay = v / 100 end)
        addToggle(p, "只锁可见", function() return C.aimVis end, function(v) C.aimVis = v end)
        addToggle(p, "粘性锁定", function() return C.aimSticky end, function(v) C.aimSticky = v end)
        addToggle(p, "人手抖动", function() return C.aimRandomize end, function(v) C.aimRandomize = v end)
        addToggle(p, "智能选点", function() return C.aimSmart end, function(v) C.aimSmart = v end)
        addToggle(p, "开火加速", function() return C.aimFireBoost end, function(v) C.aimFireBoost = v end)
        addToggle(p, "相机锁定", function() return C.aimCamLock end, function(v) C.aimCamLock = v end)
        addToggle(p, "静默自瞄", function() return C.silent end, function(v) C.silent = v end)
        addSlider(p, "静默 FOV", 20, 500, function() return C.silentFov end, function(v) C.silentFov = v end)
        addToggle(p, "自动扳机", function() return C.autoTrigger end, function(v) C.autoTrigger = v end)
        addSlider(p, "扳机 FOV", 4, 120, function() return C.triggerFov end, function(v) C.triggerFov = v end)
    end

    do
        local p = pages["透视"]
        addToggle(p, "透视总开关", function() return C.esp end, function(v) C.esp = v end)
        addToggle(p, "方框", function() return C.espBox end, function(v) C.espBox = v end)
        addToggle(p, "名字 / 距离", function() return C.espName end, function(v) C.espName = v; C.espDist = v end)
        addToggle(p, "血条", function() return C.espHP end, function(v) C.espHP = v end)
        addToggle(p, "骨骼", function() return C.espSkel end, function(v) C.espSkel = v end)
        addToggle(p, "高亮", function() return C.espChams end, function(v) C.espChams = v end)
        addToggle(p, "武器名", function() return C.espWeapon end, function(v) C.espWeapon = v end)
        addToggle(p, "指向线", function() return C.espTracer end, function(v) C.espTracer = v end)
        addToggle(p, "显示队友", function() return C.espTeam end, function(v) C.espTeam = v end)
        addSlider(p, "最远距离", 100, 3000, function() return C.espMax end, function(v) C.espMax = v end)
    end

    do
        local p = pages["视角"]
        addToggle(p, "强制第三人称", function() return C.tp end, function(v)
            C.tp = v
            if v then bindTP() end
        end)
        addSlider(p, "距离", 3, 60, function() return math.floor(C.tpDistance) end, function(v) C.tpDistance = v end)
        addSlider(p, "高度", -2, 12, function() return math.floor(C.tpHeight) end, function(v) C.tpHeight = v end)
        addSlider(p, "左右偏移", -6, 6, function() return math.floor(C.tpSide) end, function(v) C.tpSide = v end)
        addToggle(p, "相机防穿墙", function() return C.tpCollide end, function(v) C.tpCollide = v end)
        addToggle(p, "隐藏自己模型", function() return C.tpHideSelf end, function(v) C.tpHideSelf = v end)
        addToggle(p, "自动环绕", function() return C.tpOrbit end, function(v) C.tpOrbit = v end)
        addSlider(p, "环绕速度", 5, 180, function() return C.tpOrbitSpeed end, function(v) C.tpOrbitSpeed = v end)
        addToggle(p, "人物自转", function() return C.spin end, function(v)
            C.spin = v
            if not v then stopSpin() end
        end)
        addSlider(p, "转速 °/秒", 30, 1080, function() return C.spinSpeed end, function(v) C.spinSpeed = v end)
        addToggle(p, "反向旋转", function() return C.spinReverse end, function(v) C.spinReverse = v end)
    end

    do
        local p = pages["反检测"]
        addToggle(p, "拦截踢出", function() return C.antiKick end, function(v) C.antiKick = v end)
        addToggle(p, "属性伪装", function() return C.propSpoof end, function(v) C.propSpoof = v end)
        addToggle(p, "锁定属性", function() return C.lockProps end, function(v) C.lockProps = v end)
        addToggle(p, "实例隐藏", function() return C.hideInst end, function(v) C.hideInst = v end)
        addToggle(p, "屏蔽检测脚本", function() return C.scriptScan end, function(v)
            C.scriptScan = v
            if v then spawnTask(function() scanScripts(true) end) end
        end)
        addButton(p, "状态自检", function() notify(acStatus()) end)
        addLabel(p, "已移除飞行/穿墙/瞬移/变速——这几项是封号高发。")
    end

    do
        local p = pages["设置"]
        addToggle(p, "显示 FPS", function() return C.showStats end, function(v) C.showStats = v end)
        addToggle(p, "显示锁定目标", function() return C.showTarget end, function(v) C.showTarget = v end)
        addToggle(p, "显示悬浮球", function() return C.fab end, function(v)
            C.fab = v
            if fabBtn then fabBtn.Visible = v end
        end)
        addButton(p, "卸载脚本", function() unload() end)
    end

    fabBtn = Instance.new("TextButton")
    fabBtn.Size = UDim2.new(0, 52, 0, 52)
    fabBtn.Position = UDim2.new(1, -68, 0, 110)
    fabBtn.BackgroundColor3 = Color3.fromRGB(24, 30, 38)
    fabBtn.Text = "Z"
    fabBtn.Font = Enum.Font.GothamBold
    fabBtn.TextSize = 22
    fabBtn.TextColor3 = ACCENT
    fabBtn.Parent = gui
    corner(fabBtn, 26)
    stroke(fabBtn, ACCENT, 2)
    fabBtn.Visible = C.fab

    local fabDrag, fabStart, fabOrigin = false, nil, nil
    track(fabBtn.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            fabDrag = true
            fabStart = input.Position
            fabOrigin = fabBtn.Position
        end
    end))
    track(UIS.InputChanged:Connect(function(input)
        if fabDrag and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local d = input.Position - fabStart
            fabBtn.Position = UDim2.new(fabOrigin.X.Scale, fabOrigin.X.Offset + d.X, fabOrigin.Y.Scale, fabOrigin.Y.Offset + d.Y)
        end
    end))
    track(UIS.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            fabDrag = false
        end
    end))
    track(fabBtn.MouseButton1Click:Connect(function()
        mainFrame.Visible = not mainFrame.Visible
    end))

    panelToggle = function() mainFrame.Visible = not mainFrame.Visible end

    quickBar = Instance.new("Frame")
    quickBar.Size = UDim2.new(0, 60, 0, 270)
    quickBar.Position = UDim2.new(1, -68, 0.5, -135)
    quickBar.BackgroundTransparency = 1
    quickBar.Parent = gui

    local ql = Instance.new("UIListLayout")
    ql.Padding = UDim.new(0, 8)
    ql.Parent = quickBar

    local function quickBtn(txt, cb)
        local b = Instance.new("TextButton")
        b.Size = UDim2.fromOffset(math.floor(52 * C.padScale), math.floor(52 * C.padScale))
        b.BackgroundColor3 = Color3.fromRGB(24, 30, 38)
        b.BackgroundTransparency = 0.15
        b.Text = txt
        b.Font = Enum.Font.GothamBold
        b.TextSize = 14
        b.TextColor3 = Color3.fromRGB(230, 238, 245)
        b.Parent = quickBar
        corner(b, 14)
        stroke(b, Color3.fromRGB(60, 80, 96), 1)
        track(b.MouseButton1Click:Connect(function() pcall(cb) end))
        return b
    end

    quickBtn("透", function() C.esp = not C.esp; notify("透视 " .. (C.esp and "开" or "关")) end)
    quickBtn("瞄", function() C.aim = not C.aim; notify("自瞄 " .. (C.aim and "开" or "关")) end)
    quickBtn("三", function()
        C.tp = not C.tp
        if C.tp then bindTP() end
        notify("第三人称 " .. (C.tp and "开" or "关"))
    end)
    quickBtn("旋", function()
        C.spin = not C.spin
        if not C.spin then stopSpin() end
        notify("旋转 " .. (C.spin and "开" or "关"))
    end)

    uiCleanup = function() pcall(function() gui:Destroy() end) end
end

--=====================================================================
-- 9-B. WindUI（后台异步加载，不挡启动）
--=====================================================================
local WINDUI_URLS = {
    "https://github.com/Footagesus/WindUI/releases/latest/download/main.lua",
    "https://raw.githubusercontent.com/Footagesus/WindUI/main/main.lua",
}

-- 记住上次拉通的源，下次直接命中，不再两个源挨个等
local SRC_HINT = "ZakaStrike_src.txt"

local function srcHint()
    if not (readfile and isfile) then return 1 end
    local ok, ex = pcall(isfile, SRC_HINT)
    if not ok or not ex then return 1 end
    local ok2, raw = pcall(readfile, SRC_HINT)
    local n = ok2 and tonumber(raw) or nil
    if n and WINDUI_URLS[n] then return n end
    return 1
end

local function saveSrc(n)
    if writefile then pcall(writefile, SRC_HINT, tostring(n)) end
end

-- 有异步接口就用异步的，手机上不占渲染线程
local function fetchLua(url)
    local fn = game.HttpGetAsync or game.HttpGet
    local ok, body = pcall(function() return fn(game, url) end)
    if not ok or type(body) ~= "string" or #body < 200 then
        ok, body = pcall(function() return game:HttpGet(url) end)
    end
    if not ok or type(body) ~= "string" or #body < 200 then return nil end
    return body
end

local function buildWindUI()
    if not (loadstring and (game.HttpGet or game.HttpGetAsync)) then return false end

    local first = srcHint()
    local order = {first}
    for i = 1, #WINDUI_URLS do
        if i ~= first then order[#order + 1] = i end
    end

    local WindUI = nil
    for _, idx in ipairs(order) do
        local t0 = tick()
        local body = fetchLua(WINDUI_URLS[idx])
        if body then
            local ok, res = pcall(function() return loadstring(body)() end)
            if ok and type(res) == "table" and res.CreateWindow then
                WindUI = res
                saveSrc(idx)
                break
            end
        end
        -- 这个源又慢又没内容，别再陪着它等下一个
        if not body and (tick() - t0) > 6 then break end
    end
    if not WindUI then return false end

    local ok = pcall(function()
        local vp = (Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize) or Vector2.new(600, 460)
        local phone = vp.X < 900

        local Window = WindUI:CreateWindow({
            Title = "Zaka Strike v3.3",
            Icon = "crosshair",
            Author = "Zaka",
            Folder = "ZakaStrike33",
            Size = UDim2.fromOffset(
                math.floor(math.min(vp.X * 0.92, phone and 380 or 620)),
                math.floor(math.min(vp.Y * 0.80, phone and 620 or 470))
            ),
            Transparent = true,
            Theme = "Dark",
            SideBarWidth = phone and 104 or 180,
            KeySystem = false,
        })

        if Window.SetToggleKey then
            pcall(function() Window:SetToggleKey(Enum.KeyCode.RightShift, false) end)
        end

        notify = function(msg)
            pcall(function()
                WindUI:Notify({Title = "Zaka Strike", Content = tostring(msg), Icon = "info", Duration = 2})
            end)
        end

        uiCleanup = function()
            pcall(function() if Window.Destroy then Window:Destroy() end end)
            if fallbackGui then pcall(function() fallbackGui:Destroy() end); fallbackGui = nil end
        end

        panelToggle = function()
            local ok2 = pcall(function() if Window.Toggle then Window:Toggle() end end)
            if not ok2 then pcall(function() if Window.Open then Window:Open() end end) end
        end

        local TabAim  = Window:Tab({Title = "自瞄", Icon = "crosshair"})
        local TabEsp  = Window:Tab({Title = "透视", Icon = "eye"})
        local TabCam  = Window:Tab({Title = "视角", Icon = "camera"})
        local TabSafe = Window:Tab({Title = "反检测", Icon = "shield"})
        local TabMisc = Window:Tab({Title = "设置", Icon = "settings"})

        local function num(v)
            if type(v) == "table" then return tonumber(v.Value or v[1]) or 0 end
            return tonumber(v) or 0
        end

        local S0 = TabAim:Section({Title = "强度预设"})
        S0:Dropdown({Title = "预设", Values = {"稳健", "平衡", "强硬", "强锁"}, Value = C.aimPreset,
            Callback = function(v) applyPreset(v); notify("已切换到 " .. tostring(v)) end})

        local S1 = TabAim:Section({Title = "主开关"})
        S1:Toggle({Title = "自瞄", Value = C.aim, Callback = function(v) C.aim = v; saveCfg() end})
        S1:Toggle({Title = "强锁模式(瞬时贴脸)", Value = C.aimRage, Callback = function(v) C.aimRage = v; saveCfg() end})
        S1:Toggle({Title = "锁头优先", Value = C.aimHeadBias, Callback = function(v) C.aimHeadBias = v end})
        S1:Toggle({Title = "快速切目标", Value = C.aimQuickSwitch, Callback = function(v) C.aimQuickSwitch = v end})
        S1:Dropdown({Title = "部位", Values = {"Head", "UpperTorso", "HumanoidRootPart"}, Value = C.aimPart,
            Callback = function(v) C.aimPart = v; saveCfg() end})
        S1:Dropdown({Title = "优先级", Values = {"威胁", "屏幕距离", "血量", "距离"}, Value = C.aimPriority,
            Callback = function(v) C.aimPriority = v; saveCfg() end})
        S1:Toggle({Title = "只锁可见", Value = C.aimVis, Callback = function(v) C.aimVis = v end})
        S1:Toggle({Title = "多点可见探测", Value = C.aimMultipoint, Callback = function(v) C.aimMultipoint = v end})
        S1:Toggle({Title = "粘性锁定", Value = C.aimSticky, Callback = function(v) C.aimSticky = v end})
        S1:Toggle({Title = "智能选点", Value = C.aimSmart, Callback = function(v) C.aimSmart = v end})
        S1:Toggle({Title = "开火加速", Value = C.aimFireBoost, Callback = function(v) C.aimFireBoost = v end})
        S1:Toggle({Title = "相机锁定(镜头脚本盖不掉)", Value = C.aimCamLock, Callback = function(v) C.aimCamLock = v end})

        local S2 = TabAim:Section({Title = "手感"})
        S2:Slider({Title = "FOV", Value = {C.aimFov, 20, 400}, Callback = function(v) C.aimFov = num(v) end})
        S2:Slider({Title = "平滑(大=慢)", Value = {C.aimSmooth, 0, 95}, Callback = function(v) C.aimSmooth = num(v) end})
        S2:Slider({Title = "单帧最大转角°", Value = {C.aimMaxTurn, 30, 900}, Callback = function(v) C.aimMaxTurn = num(v) end})
        S2:Slider({Title = "死区°", Value = {C.aimDeadzone, 0, 3, 0.05}, Callback = function(v) C.aimDeadzone = num(v) end})
        S2:Slider({Title = "预判", Value = {C.aimPred, 0, 0.6, 0.01}, Callback = function(v) C.aimPred = num(v) end})
        S2:Slider({Title = "重力补偿", Value = {C.aimGravity, 0, 1, 0.05}, Callback = function(v) C.aimGravity = num(v) end})
        S2:Slider({Title = "切目标冷却", Value = {C.aimSwitchDelay, 0, 1.5, 0.05}, Callback = function(v) C.aimSwitchDelay = num(v) end})
        S2:Slider({Title = "粘性范围倍率", Value = {C.aimHysteresis, 1, 2.5, 0.05}, Callback = function(v) C.aimHysteresis = num(v) end})
        S2:Slider({Title = "瞄准高度偏移", Value = {C.aimOffsetY, -1, 1, 0.05}, Callback = function(v) C.aimOffsetY = num(v) end})
        S2:Toggle({Title = "人手抖动", Value = C.aimRandomize, Callback = function(v) C.aimRandomize = v end})
        S2:Toggle({Title = "近距离加速", Value = C.aimNearBoost, Callback = function(v) C.aimNearBoost = v end})

        local S3 = TabAim:Section({Title = "静默 / 扳机"})
        S3:Toggle({Title = "静默自瞄", Value = C.silent, Callback = function(v) C.silent = v end})
        S3:Slider({Title = "静默 FOV", Value = {C.silentFov, 20, 500}, Callback = function(v) C.silentFov = num(v) end})
        S3:Toggle({Title = "静默命中点复核", Value = C.silentValidate, Callback = function(v) C.silentValidate = v end})
        S3:Toggle({Title = "自动扳机", Value = C.autoTrigger, Callback = function(v) C.autoTrigger = v end})
        S3:Slider({Title = "扳机 FOV", Value = {C.triggerFov, 4, 120}, Callback = function(v) C.triggerFov = num(v) end})
        S3:Slider({Title = "扳机延迟", Value = {C.triggerDelay, 0, 0.4, 0.01}, Callback = function(v) C.triggerDelay = num(v) end})

        local E1 = TabEsp:Section({Title = "透视"})
        E1:Toggle({Title = "总开关", Value = C.esp, Callback = function(v) C.esp = v; saveCfg() end})
        E1:Toggle({Title = "方框", Value = C.espBox, Callback = function(v) C.espBox = v end})
        E1:Toggle({Title = "名字", Value = C.espName, Callback = function(v) C.espName = v end})
        E1:Toggle({Title = "距离", Value = C.espDist, Callback = function(v) C.espDist = v end})
        E1:Toggle({Title = "血条", Value = C.espHP, Callback = function(v) C.espHP = v end})
        E1:Toggle({Title = "骨骼", Value = C.espSkel, Callback = function(v) C.espSkel = v end})
        E1:Toggle({Title = "高亮", Value = C.espChams, Callback = function(v) C.espChams = v end})
        E1:Toggle({Title = "武器名", Value = C.espWeapon, Callback = function(v) C.espWeapon = v end})
        E1:Toggle({Title = "指向线", Value = C.espTracer, Callback = function(v) C.espTracer = v end})
        E1:Toggle({Title = "显示队友", Value = C.espTeam, Callback = function(v) C.espTeam = v end})
        E1:Slider({Title = "最远距离", Value = {C.espMax, 100, 3000}, Callback = function(v) C.espMax = num(v) end})

        local C1 = TabCam:Section({Title = "第三人称"})
        C1:Toggle({Title = "强制第三人称", Value = C.tp, Callback = function(v) C.tp = v; if v then bindTP() end; saveCfg() end})
        C1:Slider({Title = "距离", Value = {C.tpDistance, 3, 30, 0.5}, Callback = function(v) C.tpDistance = num(v) end})
        C1:Slider({Title = "高度", Value = {C.tpHeight, -2, 6, 0.1}, Callback = function(v) C.tpHeight = num(v) end})
        C1:Slider({Title = "左右偏移", Value = {C.tpSide, -6, 6, 0.5}, Callback = function(v) C.tpSide = num(v) end})
        C1:Toggle({Title = "相机防穿墙", Value = C.tpCollide, Callback = function(v) C.tpCollide = v end})
        C1:Toggle({Title = "隐藏自己模型", Value = C.tpHideSelf, Callback = function(v) C.tpHideSelf = v end})
        C1:Toggle({Title = "自动环绕", Value = C.tpOrbit, Callback = function(v) C.tpOrbit = v end})
        C1:Slider({Title = "环绕速度", Value = {C.tpOrbitSpeed, 5, 180}, Callback = function(v) C.tpOrbitSpeed = num(v) end})

        local C2 = TabCam:Section({Title = "人物旋转"})
        C2:Toggle({Title = "人物自转", Value = C.spin, Callback = function(v) C.spin = v; if not v then stopSpin() end end})
        C2:Slider({Title = "转速 °/秒", Value = {C.spinSpeed, 30, 1080}, Callback = function(v) C.spinSpeed = num(v) end})
        C2:Toggle({Title = "反向旋转", Value = C.spinReverse, Callback = function(v) C.spinReverse = v end})

        local A1 = TabSafe:Section({Title = "本机层"})
        A1:Toggle({Title = "拦截踢出", Value = C.antiKick, Callback = function(v) C.antiKick = v end})
        A1:Toggle({Title = "属性伪装", Value = C.propSpoof, Callback = function(v) C.propSpoof = v end})
        A1:Toggle({Title = "锁定属性", Value = C.lockProps, Callback = function(v) C.lockProps = v end})
        A1:Toggle({Title = "实例隐藏", Value = C.hideInst, Callback = function(v) C.hideInst = v end})
        A1:Toggle({Title = "屏蔽检测脚本", Value = C.scriptScan, Callback = function(v)
            C.scriptScan = v
            if v then spawnTask(function() scanScripts(true) end) end
        end})
        A1:Button({Title = "状态自检", Callback = function() notify(acStatus()) end})
        A1:Paragraph({Title = "边界", Content = "飞行/穿墙/瞬移/变速已移除。客户端层只能压到这一步，服务端行为分析压不住——测试用小号。"})

        local M1 = TabMisc:Section({Title = "界面"})
        M1:Toggle({Title = "显示 FPS", Value = C.showStats, Callback = function(v) C.showStats = v end})
        M1:Toggle({Title = "显示锁定目标", Value = C.showTarget, Callback = function(v) C.showTarget = v end})
        M1:Button({Title = "卸载", Callback = function() unload() end})
    end)
    return ok
end

--=====================================================================
-- 10. 启动：先出面板，再后台补救 WindUI
--=====================================================================
buildFallback()

spawnTask(function()
    task.wait(0.35)              -- 先让面板跳出来，别和首帧抢资源
    local ok = buildWindUI()
    if ok then
        task.wait(0.05)
        if fallbackGui then
            pcall(function() fallbackGui:Destroy() end)
            fallbackGui = nil
        end
    end
end)

track(UIS.InputBegan:Connect(function(input, processed)
    if input.UserInputType == Enum.UserInputType.Keyboard and not processed then
        if input.KeyCode == Enum.KeyCode.RightShift then
            panelToggle()
        end
    end
end))

--=====================================================================
-- 11. 主循环 / 卸载
--=====================================================================
local conns = {}
local function addConn(c) conns[#conns + 1] = c; return c end

addConn(LP.CharacterAdded:Connect(function()
    task.wait(0.5)
    local hum = getHum()
    if hum then baseSpeed = hum.WalkSpeed end
    aimLock = nil
    velTrack = {}
    visCache = {}
end))

do
    local hum = getHum()
    if hum then baseSpeed = hum.WalkSpeed end
end

spawnTask(function()
    task.wait(0.2)
    pcall(installHooks)
    pcall(bindTP)
end)

local scanAcc = 0
local espSkip = 0
local warmFrames = 12

addConn(RunService.RenderStepped:Connect(function(dt)
    local cam = Workspace.CurrentCamera

    -- 开局预热：先把面板和 WindUI 送上来，头十几帧不抢资源
    if warmFrames > 0 then
        warmFrames = warmFrames - 1
        return
    end

    -- 低帧时 ESP 隔帧刷新，手感优先
    espSkip = espSkip + 1
    local every = (dt > 1 / 40) and 2 or 1
    if espSkip >= every then
        espSkip = 0
        updateESP(cam)
    end

    if cam then updateAim(cam, dt) end
    updateStats(dt)
    if C.spin then spinStep(dt) end

    if C.scriptScan and C.scriptScanLoop then
        scanAcc = scanAcc + dt
        if scanAcc > 20 then
            scanAcc = 0
            pcall(scanScripts, false)
        end
    end
end))

function unload()
    pcall(function()
        for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
        for _, c in ipairs(uiConns) do pcall(function() c:Disconnect() end) end
    end)
    pcall(function()
        for p in pairs(espCache) do removeESP(p) end
    end)
    pcall(unbindTP)
    pcall(stopSpin)
    pcall(function() C.tp = false; C.tpHideSelf = false; restoreSelfVisibility(true) end)
    pcall(removeHooks)
    pcall(uiCleanup)
    pcall(function()
        if fallbackGui then fallbackGui:Destroy() end
    end)
    pcall(function()
        if fovCircle then fovCircle:Remove() end
        if statText then statText:Remove() end
        if targetText then targetText:Remove() end
    end)
    notify("Zaka Strike 已卸载")
end

notify("Zaka Strike v3.3 已载入 · 点右上角 Z 或右Shift")
