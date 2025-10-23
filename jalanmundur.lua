local ROTATE_DEGREE = 180 
local ROTATE_RAD = math.rad(ROTATE_DEGREE)

task.wait(1) 

local allRoutes = _G.routes
if not allRoutes or #allRoutes == 0 then
    warn("[Axa Rotator] Gagal: routes belum tersedia.")
    return
end

for _, routeData in ipairs(allRoutes) do
    local frames = routeData[2]
    for i, cf in ipairs(frames) do
        local pos = cf.Position
        local originalRot = cf - cf.Position          
        local rotOnly = CFrame.Angles(0, ROTATE_RAD, 0)
        frames[i] = CFrame.new(pos) * (rotOnly * originalRot)
    end
end

print(("[Axa Rotator] ✅ Arah route diputar %d° (orientasi saja)."):format(ROTATE_DEGREE))