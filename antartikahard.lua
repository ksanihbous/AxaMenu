-- AxaXyz Menu — AutoWalk + Jalan Mundur (sesuai rotator kamu)
-- Fitur: Start/Stop, Speed, Dock (merah/kuning), Medium Fullscreen (hijau), Drag header,
--        Tombol "Jalan Mundur: ON/Normal" di bawah START.
-- Catatan: Toggle Jalan Mundur di tengah run akan langsung rebase ke frame terdekat (tanpa stop).

-- ========= Services =========
local Players            = game:GetService("Players")
local RunService         = game:GetService("RunService")
local TweenService       = game:GetService("TweenService")
local UserInputService   = game:GetService("UserInputService")

local player = Players.LocalPlayer
local hrp

-- ========= ROUTE CONFIG =========
local ROUTE_LINKS = {
    "https://raw.githubusercontent.com/ksanihbous/AxaSc/refs/heads/main/antartikahard.lua",
}

-- ========= State Replay =========
local baseRoutes = {}     -- rute dasar (sudah disesuaikan tinggi), tidak diubah-ubah
_G.routes = {}            -- rute aktif (forward atau sudah diputar orientasinya) — sesuai rotatormu
local animConn
local isMoving = false
local frameTime = 1/30
local playbackRate = 1
local isReplayRunning = false
local isRunning = false

-- Jalan Mundur state + versi mode agar loop tahu kapan harus rebase
local isBackward = false
local modeVersion = 0

-- ========= Utils =========
local function tween(obj, t, props, style, dir)
    local info = TweenInfo.new(t or 0.18, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out)
    local tw = TweenService:Create(obj, info, props)
    tw:Play(); return tw
end

local function deepCopyRoutes(src)
    local out = table.create(#src)
    for i, r in ipairs(src) do
        local name, frames = r[1], r[2]
        local framesCopy = table.create(#frames)
        for j, cf in ipairs(frames) do
            framesCopy[j] = cf
        end
        out[i] = {name, framesCopy}
    end
    return out
end

-- ========= Load Routes (raw) =========
local rawRoutes = {}
for i, link in ipairs(ROUTE_LINKS) do
    if link ~= "" then
        local ok, data = pcall(function()
            return loadstring(game:HttpGet(link))()
        end)
        if ok and typeof(data) == "table" and #data > 0 then
            table.insert(rawRoutes, {"Route "..i, data})
        end
    end
end
if #rawRoutes == 0 then warn("Tidak ada route valid ditemukan.") return end

-- ========= HRP / Character =========
local function refreshHRP(char)
    if not char then char = player.Character or player.CharacterAdded:Wait() end
    hrp = char:WaitForChild("HumanoidRootPart")
end
player.CharacterAdded:Connect(refreshHRP)
if player.Character then refreshHRP(player.Character) end

-- ========= Movement Bindings =========
local function stopMovement() isMoving = false end
local function startMovement() isMoving = true end

local function setupMovement(char)
    task.spawn(function()
        if not char then
            char = player.Character or player.CharacterAdded:Wait()
        end
        local humanoid = char:WaitForChild("Humanoid", 5)
        local root = char:WaitForChild("HumanoidRootPart", 5)
        if not humanoid or not root then return end

        humanoid.Died:Connect(function()
            print("[AxaXyz Menu] Karakter mati, replay otomatis berhenti.")
            isReplayRunning = false
            stopMovement()
            isRunning = false
            if toggleBtn and toggleBtn.Parent then
                toggleBtn.Text = "▶ Start"
                toggleBtn.BackgroundColor3 = Color3.fromRGB(70,200,120)
            end
        end)

        if animConn then animConn:Disconnect() end
        local lastPos = root.Position
        local jumpCooldown = false

        animConn = RunService.RenderStepped:Connect(function()
            if not isMoving then return end

            -- Auto-recover HRP saat respawn
            if not hrp or not hrp.Parent or not hrp:IsDescendantOf(workspace) then
                if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
                    hrp = player.Character:FindFirstChild("HumanoidRootPart")
                    root = hrp
                else
                    return
                end
            end

            if not humanoid or humanoid.Health <= 0 then return end

            local direction = root.Position - lastPos
            local dist = direction.Magnitude

            if dist > 0.01 then
                humanoid:Move(direction.Unit * math.clamp(dist * 5, 0, 1), false)
            else
                humanoid:Move(Vector3.zero, false)
            end

            local deltaY = root.Position.Y - lastPos.Y
            if deltaY > 0.9 and not jumpCooldown then
                humanoid.Jump = true
                jumpCooldown = true
                task.delay(0.4, function() jumpCooldown = false end)
            end

            lastPos = root.Position
        end)
    end)
end

player.CharacterAdded:Connect(function(char)
    refreshHRP(char)
    setupMovement(char)
end)
if player.Character then
    refreshHRP(player.Character)
    setupMovement(player.Character)
end

-- ========= Replay Core =========
local DEFAULT_HEIGHT = 2.9
local function getCurrentHeight()
    local char = player.Character or player.CharacterAdded:Wait()
    local humanoid = char:WaitForChild("Humanoid")
    return humanoid.HipHeight + (char:FindFirstChild("Head") and char.Head.Size.Y or 2)
end

local function adjustRoute(frames)
    local adjusted = table.create(#frames)
    local offsetY = getCurrentHeight() - DEFAULT_HEIGHT
    for i, cf in ipairs(frames) do
        local pos, rot = cf.Position, cf - cf.Position
        adjusted[i] = CFrame.new(Vector3.new(pos.X, pos.Y + offsetY, pos.Z)) * rot
    end
    return adjusted
end

-- Siapkan baseRoutes (tinggi disesuaikan)
for _, r in ipairs(rawRoutes) do
    local name, frames = r[1], r[2]
    table.insert(baseRoutes, {name, adjustRoute(frames)})
end

-- === Rotator JALAN MUNDUR (menyesuaikan script kamu) ===
local ROTATE_DEGREE = 180
local ROTATE_RAD = math.rad(ROTATE_DEGREE)

local function applyBackwardRotationInPlace(axRoutes)
    -- Persis seperti snippet kamu: putar ORIENTASI saja, in-place pada _G.routes
    for _, routeData in ipairs(axRoutes) do
        local frames = routeData[2]
        for i, cf in ipairs(frames) do
            local pos = cf.Position
            local originalRot = cf - pos
            local rotOnly = CFrame.Angles(0, ROTATE_RAD, 0)
            frames[i] = CFrame.new(pos) * (rotOnly * originalRot)
        end
    end
end

-- Terapkan mode (tanpa menimbun rotasi): selalu reset dari baseRoutes -> (opsional) rotate
local function applyMode(toBackward)
    _G.routes = deepCopyRoutes(baseRoutes)     -- reset
    if toBackward then
        applyBackwardRotationInPlace(_G.routes)
        print(("[Axa Rotator] ✅ Arah route diputar %d° (orientasi saja)."):format(ROTATE_DEGREE))
    else
        print("[Axa Rotator] ▶ Mode Normal (forward).")
    end
    modeVersion += 1
end

-- Default: forward
applyMode(false)

local function getNearestRoute()
    local nearestIdx, dist = 1, math.huge
    if hrp then
        local pos = hrp.Position
        for i, data in ipairs(_G.routes) do
            for _, cf in ipairs(data[2]) do
                local d = (cf.Position - pos).Magnitude
                if d < dist then dist = d; nearestIdx = i end
            end
        end
    end
    return nearestIdx
end

local function getNearestFrameIndex(frames)
    local startIdx, dist = 1, math.huge
    if hrp then
        local pos = hrp.Position
        for i, cf in ipairs(frames) do
            local d = (cf.Position - pos).Magnitude
            if d < dist then dist = d; startIdx = i end
        end
    end
    if startIdx >= #frames then startIdx = math.max(1, #frames - 1) end
    return startIdx
end

local function lerpCF(fromCF, toCF)
    local duration = frameTime / math.max(0.05, playbackRate)
    local t = 0
    while t < duration do
        if not isReplayRunning then break end
        local dt = task.wait()
        t += dt
        local alpha = math.min(t / duration, 1)
        if hrp and hrp.Parent and hrp:IsDescendantOf(workspace) then
            hrp.CFrame = fromCF:Lerp(toCF, alpha)
        end
    end
end

local function runRoute()
    if #_G.routes == 0 then return end
    if not hrp then refreshHRP() end
    isReplayRunning = true
    startMovement()

    local idx = getNearestRoute()
    local frames = _G.routes[idx][2]
    if #frames < 2 then isReplayRunning = false; stopMovement(); return end

    local i = getNearestFrameIndex(frames)
    local localVersion = modeVersion

    while isReplayRunning do
        -- Batas akhir?
        frames = _G.routes[idx][2]
        if i >= #frames then break end

        -- Lerp segmen saat ini
        lerpCF(frames[i], frames[i+1])

        -- Jika mode berubah di tengah jalan, rebase ke rute/frame terdekat pada mode baru
        if localVersion ~= modeVersion then
            localVersion = modeVersion
            idx = getNearestRoute()
            frames = _G.routes[idx][2]
            i = getNearestFrameIndex(frames)
        else
            i += 1
        end
    end

    isReplayRunning = false
    stopMovement()
end

local function stopRoute()
    isReplayRunning = false
    stopMovement()
end

-- ========= UI: MacOS Tahoe =========
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "AxaXyzMenuUI"
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.IgnoreGuiInset = true
screenGui.ResetOnSpawn = false
screenGui.Parent = game.CoreGui

-- Window
local window = Instance.new("Frame")
window.Name = "Window"
window.Size = UDim2.fromOffset(260, 196) -- tinggi ditambah untuk tombol Jalan Mundur
window.AnchorPoint = Vector2.new(1, 0)
window.Position = UDim2.new(1, -24, 0, 64)
window.BackgroundColor3 = Color3.fromRGB(28, 28, 32)
window.BackgroundTransparency = 0.15
window.Parent = screenGui
Instance.new("UICorner", window).CornerRadius = UDim.new(0, 14)
local windowStroke = Instance.new("UIStroke", window)
windowStroke.Color = Color3.fromRGB(210, 210, 220)
windowStroke.Thickness = 1
windowStroke.Transparency = 0.7

-- Header
local header = Instance.new("Frame")
header.Name = "Header"
header.Size = UDim2.new(1, 0, 0, 32)
header.BackgroundTransparency = 1
header.Parent = window

local headerGlass = Instance.new("Frame")
headerGlass.Size = UDim2.new(1, -16, 0, 24)
headerGlass.Position = UDim2.new(0, 8, 0, 4)
headerGlass.BackgroundColor3 = Color3.fromRGB(255,255,255)
headerGlass.BackgroundTransparency = 0.88
headerGlass.Parent = header
Instance.new("UICorner", headerGlass).CornerRadius = UDim.new(0, 10)
local headerStroke = Instance.new("UIStroke", headerGlass)
headerStroke.Color = Color3.fromRGB(255,255,255)
headerStroke.Transparency = 0.8

local title = Instance.new("TextLabel")
title.Name = "Title"
title.Size = UDim2.new(1, -120, 1, 0)
title.Position = UDim2.new(0, 60, 0, 0)
title.BackgroundTransparency = 1
title.Text = "AxaXyz Menu"
title.TextColor3 = Color3.fromRGB(230,230,238)
title.Font = Enum.Font.GothamMedium
title.TextScaled = true
title.Parent = headerGlass

local function newDot(parent, rgb)
    local b = Instance.new("TextButton")
    b.AutoButtonColor = false
    b.Text = ""
    b.Size = UDim2.fromOffset(16, 16)
    b.BackgroundColor3 = Color3.fromRGB(rgb[1], rgb[2], rgb[3])
    b.Parent = parent
    Instance.new("UICorner", b).CornerRadius = UDim.new(1, 0)
    local s = Instance.new("UIStroke", b)
    s.Color = Color3.fromRGB(0,0,0)
    s.Transparency = 0.6
    return b
end

local lights = Instance.new("Frame")
lights.Name = "TrafficLights"
lights.Size = UDim2.fromOffset(54, 16)
lights.Position = UDim2.new(0, 10, 0.5, -8)
lights.BackgroundTransparency = 1
lights.Parent = headerGlass

local red    = newDot(lights, {255, 95, 86})
local yellow = newDot(lights, {255, 189, 46})
local green  = newDot(lights, {39, 201, 63})
yellow.Position = UDim2.new(0, 19, 0, 0)
green.Position  = UDim2.new(0, 38, 0, 0)

-- Body
local body = Instance.new("Frame")
body.Name = "Body"
body.Size = UDim2.new(1, -16, 1, -44)
body.Position = UDim2.new(0, 8, 0, 36)
body.BackgroundColor3 = Color3.fromRGB(38,38,44)
body.BackgroundTransparency = 0.2
body.Parent = window
Instance.new("UICorner", body).CornerRadius = UDim.new(0, 12)
local bodyStroke = Instance.new("UIStroke", body)
bodyStroke.Color = Color3.fromRGB(255,255,255)
bodyStroke.Transparency = 0.85

-- Controls
toggleBtn = Instance.new("TextButton")
toggleBtn.Size = UDim2.new(1, -16, 0, 40)
toggleBtn.Position = UDim2.new(0, 8, 0, 8)
toggleBtn.Text = "▶ Start"
toggleBtn.TextScaled = true
toggleBtn.Font = Enum.Font.GothamBold
toggleBtn.BackgroundColor3 = Color3.fromRGB(70,200,120)
toggleBtn.TextColor3 = Color3.fromRGB(255,255,255)
toggleBtn.AutoButtonColor = true
toggleBtn.Parent = body
Instance.new("UICorner", toggleBtn).CornerRadius = UDim.new(0, 10)
local toggleStroke = Instance.new("UIStroke", toggleBtn)
toggleStroke.Color = Color3.fromRGB(0,0,0)
toggleStroke.Transparency = 0.75

-- Tombol Jalan Mundur (tepat di bawah START)
local backBtn = Instance.new("TextButton")
backBtn.Size = UDim2.new(1, -16, 0, 32)
backBtn.Position = UDim2.new(0, 8, 0, 52)
backBtn.Text = "Jalan Mundur: Normal"
backBtn.TextScaled = true
backBtn.Font = Enum.Font.GothamMedium
backBtn.BackgroundColor3 = Color3.fromRGB(60,90,130)
backBtn.TextColor3 = Color3.fromRGB(240,240,255)
backBtn.AutoButtonColor = true
backBtn.Parent = body
Instance.new("UICorner", backBtn).CornerRadius = UDim.new(0, 10)
local backStroke = Instance.new("UIStroke", backBtn)
backStroke.Color = Color3.fromRGB(0,0,0)
backStroke.Transparency = 0.75

local speedLabel = Instance.new("TextLabel")
speedLabel.Size = UDim2.new(0, 64, 0, 32)
speedLabel.Position = UDim2.new(0.5, -32, 0, 92)
speedLabel.BackgroundTransparency = 1
speedLabel.TextColor3 = Color3.fromRGB(200,200,220)
speedLabel.Font = Enum.Font.GothamBold
speedLabel.TextScaled = true
speedLabel.Text = tostring(playbackRate).."x"
speedLabel.Parent = body

local speedDown = Instance.new("TextButton")
speedDown.Size = UDim2.new(0, 44, 0, 32)
speedDown.Position = UDim2.new(0, 12, 0, 92)
speedDown.Text = "-"
speedDown.Font = Enum.Font.GothamBold
speedDown.TextScaled = true
speedDown.BackgroundColor3 = Color3.fromRGB(90,90,100)
speedDown.TextColor3 = Color3.fromRGB(255,255,255)
speedDown.AutoButtonColor = true
speedDown.Parent = body
Instance.new("UICorner", speedDown).CornerRadius = UDim.new(0, 8)

local speedUp = Instance.new("TextButton")
speedUp.Size = UDim2.new(0, 44, 0, 32)
speedUp.Position = UDim2.new(1, -56, 0, 92)
speedUp.Text = "+"
speedUp.Font = Enum.Font.GothamBold
speedUp.TextScaled = true
speedUp.BackgroundColor3 = Color3.fromRGB(90,90,120)
speedUp.TextColor3 = Color3.fromRGB(255,255,255)
speedUp.AutoButtonColor = true
speedUp.Parent = body
Instance.new("UICorner", speedUp).CornerRadius = UDim.new(0, 8)

-- ========= Interaksi Kontrol =========
toggleBtn.MouseButton1Click:Connect(function()
    if not isRunning then
        isRunning = true
        toggleBtn.Text = "■ Stop"
        toggleBtn.BackgroundColor3 = Color3.fromRGB(220,90,90)
        task.spawn(runRoute)
    else
        isRunning = false
        toggleBtn.Text = "▶ Start"
        toggleBtn.BackgroundColor3 = Color3.fromRGB(70,200,120)
        stopRoute()
    end
end)

backBtn.MouseButton1Click:Connect(function()
    isBackward = not isBackward
    applyMode(isBackward) -- reset dari baseRoutes lalu (opsional) putar orientasi sesuai script kamu
    if isBackward then
        backBtn.Text = "Jalan Mundur: ON"
        backBtn.BackgroundColor3 = Color3.fromRGB(120,70,160)
    else
        backBtn.Text = "Jalan Mundur: Normal"
        backBtn.BackgroundColor3 = Color3.fromRGB(60,90,130)
    end
    -- Jika sedang berjalan, loop akan otomatis rebase ke mode baru (lihat modeVersion di runRoute)
end)

speedDown.MouseButton1Click:Connect(function()
    playbackRate = math.max(0.25, playbackRate - 0.25)
    speedLabel.Text = tostring(playbackRate).."x"
end)
speedUp.MouseButton1Click:Connect(function()
    playbackRate = math.min(6, playbackRate + 0.25)
    speedLabel.Text = tostring(playbackRate).."x"
end)

-- ========= Drag via Header =========
do
    local dragging = false
    local dragStart, startPos

    header.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = window.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)

    header.InputChanged:Connect(function(input)
        if (input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch) and dragging then
            local delta = input.Position - dragStart
            window.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end)
end

-- ========= Dock (merah/kuning) & Fullscreen (hijau) =========
local dockBtn = Instance.new("TextButton")
dockBtn.Name = "AxaDock"
dockBtn.AnchorPoint = Vector2.new(1, 0.5)
dockBtn.Size = UDim2.fromOffset(160, 32)
dockBtn.Position = UDim2.new(1, -10, 0.5, 0)
dockBtn.Text = "Axa AutoWalk"
dockBtn.Font = Enum.Font.GothamBold
dockBtn.TextScaled = true
dockBtn.TextColor3 = Color3.fromRGB(245,245,255)
dockBtn.BackgroundColor3 = Color3.fromRGB(44,44,52)
dockBtn.AutoButtonColor = true
dockBtn.Visible = false
dockBtn.Parent = screenGui
Instance.new("UICorner", dockBtn).CornerRadius = UDim.new(0, 14)
local dockStroke = Instance.new("UIStroke", dockBtn)
dockStroke.Color = Color3.fromRGB(255,255,255)
dockStroke.Transparency = 0.8

dockBtn.MouseButton1Click:Connect(function()
    dockBtn.Visible = false
    window.Visible = true
    tween(window, 0.12, {BackgroundTransparency = 0.15})
end)

local isFullscreen = false
local saved = { size = window.Size, pos = window.Position, anchor = window.AnchorPoint }

local function saveNormalGeometry()
    saved.size = window.Size
    saved.pos = window.Position
    saved.anchor = window.AnchorPoint
end

local function applyMediumFullscreen()
    saveNormalGeometry()
    local targetSize = UDim2.fromOffset(520, 300)
    window.AnchorPoint = Vector2.new(0.5, 0.5)
    tween(window, 0.12, {Size = targetSize})
    tween(window, 0.12, {Position = UDim2.new(0.5, 0, 0.5, 0)})
end

local function exitMediumFullscreen()
    tween(window, 0.12, {Size = saved.size})
    tween(window, 0.12, {Position = saved.pos})
    task.delay(0.12, function()
        window.AnchorPoint = saved.anchor
    end)
end

local function toggleFullscreen()
    if not window.Visible then
        dockBtn.Visible = false
        window.Visible = true
    end
    if not isFullscreen then
        applyMediumFullscreen()
        isFullscreen = true
    else
        exitMediumFullscreen()
        isFullscreen = false
    end
end

local function minimizeToDock()
    if window.Visible then
        tween(window, 0.10, {BackgroundTransparency = 0.5})
        tween(window, 0.10, {Position = UDim2.new(window.Position.X.Scale, window.Position.X.Offset,
                                                  window.Position.Y.Scale, window.Position.Y.Offset + 10)})
        task.delay(0.10, function()
            window.Visible = false
            dockBtn.Visible = true
        end)
    end
end

red.MouseButton1Click:Connect(minimizeToDock)
yellow.MouseButton1Click:Connect(minimizeToDock)
green.MouseButton1Click:Connect(toggleFullscreen)