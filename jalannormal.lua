-- Axa Rotator — Balik Arah Normal
local DEG = -180
local RAD = math.rad(DEG)

task.wait(0.5)

local routes = _G.routes
if type(routes) ~= "table" or #routes == 0 then
	warn("[Axa Rotator] Gagal: routes belum tersedia."); return
end

for _, routeData in ipairs(routes) do
	local frames = routeData[2]
	if type(frames) == "table" then
		for i, cf in ipairs(frames) do
			local pos = cf.Position
			local rot = cf - cf.Position
			frames[i] = CFrame.new(pos) * (CFrame.Angles(0, RAD, 0) * rot)
		end
	end
end

print("[Axa Rotator] ✅ Arah route dikembalikan ke normal (membatalkan 180°).")