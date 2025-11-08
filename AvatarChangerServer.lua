--// ServerScriptService.AvatarChangerServer
-- Versi AUTO-CREATE RemoteEvent (untuk project yang belum punya RemoteEvent sama sekali)
-- Bekerja dengan AvatarChangerClient yang sudah kamu kirim:
--   - ReplicatedStorage.ChangeAvatarEvent
--   - ReplicatedStorage.ResetAvatarEvent
--   - ReplicatedStorage.AddAccessoryEvent
--   - ReplicatedStorage.RemoveAccessoryEvent

local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

------------------------------------------------------------
-- BUAT REMOTEEVENT DARI NOL
------------------------------------------------------------

local function createRemote(name : string)
    -- kalau ada sisa lama dengan nama sama, hapus dulu biar nggak dobel
    local old = ReplicatedStorage:FindFirstChild(name)
    if old and old:IsA("RemoteEvent") then
        old:Destroy()
    end

    local ev = Instance.new("RemoteEvent")
    ev.Name = name
    ev.Parent = ReplicatedStorage
    return ev
end

local ChangeAvatarEvent    = createRemote("ChangeAvatarEvent")
local ResetAvatarEvent     = createRemote("ResetAvatarEvent")
local AddAccessoryEvent    = createRemote("AddAccessoryEvent")
local RemoveAccessoryEvent = createRemote("RemoveAccessoryEvent")

------------------------------------------------------------
-- HELPER: Humanoid, AssetType mapping, dll
------------------------------------------------------------

local function getHumanoid(player : Player) : Humanoid?
    local character = player.Character
    if not character then return nil end
    return character:FindFirstChildOfClass("Humanoid")
end

-- Map AssetTypeId -> field HumanoidDescription
local ACC_FIELD_BY_TYPEID = {
    [Enum.AssetType.Hat.Value]               = "HatAccessory",
    [Enum.AssetType.HairAccessory.Value]     = "HairAccessory",
    [Enum.AssetType.FaceAccessory.Value]     = "FaceAccessory",
    [Enum.AssetType.NeckAccessory.Value]     = "NeckAccessory",
    [Enum.AssetType.ShoulderAccessory.Value] = "ShoulderAccessory",
    [Enum.AssetType.FrontAccessory.Value]    = "FrontAccessory",
    [Enum.AssetType.BackAccessory.Value]     = "BackAccessory",
    [Enum.AssetType.WaistAccessory.Value]    = "WaistAccessory",
}

-- cache assetId -> fieldName
local AssetFieldCache : {[number]: string|false} = {}

local function getFieldForAssetId(assetId : number) : string?
    local cached = AssetFieldCache[assetId]
    if cached ~= nil then
        return cached or nil
    end

    local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, assetId, Enum.InfoType.Asset)
    local fieldName = nil

    if ok and info and info.AssetTypeId then
        fieldName = ACC_FIELD_BY_TYPEID[info.AssetTypeId]
    end

    AssetFieldCache[assetId] = fieldName or false
    return fieldName
end

-- "1,2,3" -> {1,2,3}
local function splitIds(str : string?)
    local t = {}
    if not str or str == "" then
        return t
    end
    for token in string.gmatch(str, "[^,]+") do
        local n = tonumber(token)
        if n then
            table.insert(t, n)
        end
    end
    return t
end

-- {1,2,3} -> "1,2,3"
local function joinIds(t : {number})
    local parts = {}
    for _, n in ipairs(t) do
        table.insert(parts, tostring(n))
    end
    return table.concat(parts, ",")
end

local function addAccessoryId(desc : HumanoidDescription, fieldName : string, assetId : number)
    local current = splitIds(desc[fieldName])
    for _, v in ipairs(current) do
        if v == assetId then
            return -- sudah ada
        end
    end
    table.insert(current, assetId)
    desc[fieldName] = joinIds(current)
end

local function removeAccessoryId(desc : HumanoidDescription, fieldName : string, assetId : number)
    local current = splitIds(desc[fieldName])
    local changed = false

    for i = #current, 1, -1 do
        if current[i] == assetId then
            table.remove(current, i)
            changed = true
        end
    end

    if changed then
        desc[fieldName] = joinIds(current)
    end
end

------------------------------------------------------------
-- HANDLER: GANTI AVATAR (ChangeAvatarEvent)
------------------------------------------------------------

ChangeAvatarEvent.OnServerEvent:Connect(function(player, targetUserId)
    if typeof(targetUserId) ~= "number" then
        return
    end

    local humanoid = getHumanoid(player)
    if not humanoid then
        return
    end

    -- Ambil HumanoidDescription dari userId target (Boys/Girls list di client)
    local ok, desc = pcall(function()
        return Players:GetHumanoidDescriptionFromUserId(targetUserId)
    end)

    if not ok or not desc then
        warn("[AvatarChangerServer] Gagal ambil HumanoidDescription dari userId:", targetUserId)
        return
    end

    humanoid:ApplyDescription(desc)
end)

------------------------------------------------------------
-- HANDLER: RESET AVATAR (ResetAvatarEvent)
------------------------------------------------------------

ResetAvatarEvent.OnServerEvent:Connect(function(player)
    local humanoid = getHumanoid(player)
    if not humanoid then
        return
    end

    local ok, desc = pcall(function()
        return Players:GetHumanoidDescriptionFromUserId(player.UserId)
    end)

    if not ok or not desc then
        warn("[AvatarChangerServer] Gagal ambil HumanoidDescription default untuk", player.Name)
        return
    end

    humanoid:ApplyDescription(desc)
end)

------------------------------------------------------------
-- HANDLER: TAMBAH AKSESORIS (AddAccessoryEvent)
------------------------------------------------------------

AddAccessoryEvent.OnServerEvent:Connect(function(player, assetId)
    if typeof(assetId) ~= "number" then
        return
    end

    local humanoid = getHumanoid(player)
    if not humanoid then
        return
    end

    local fieldName = getFieldForAssetId(assetId)
    if not fieldName then
        warn(("[AvatarChangerServer] AssetId %d bukan jenis aksesoris yang didukung."):format(assetId))
        return
    end

    local desc = humanoid:GetAppliedDescription()
    addAccessoryId(desc, fieldName, assetId)
    humanoid:ApplyDescription(desc)
end)

------------------------------------------------------------
-- HANDLER: HAPUS AKSESORIS (RemoveAccessoryEvent)
------------------------------------------------------------

RemoveAccessoryEvent.OnServerEvent:Connect(function(player, assetId)
    if typeof(assetId) ~= "number" then
        return
    end

    local humanoid = getHumanoid(player)
    if not humanoid then
        return
    end

    local fieldName = getFieldForAssetId(assetId)
    if not fieldName then
        warn(("[AvatarChangerServer] AssetId %d bukan jenis aksesoris yang didukung."):format(assetId))
        return
    end

    local desc = humanoid:GetAppliedDescription()
    removeAccessoryId(desc, fieldName, assetId)
    humanoid:ApplyDescription(desc)
end)

print("[AvatarChangerServer] Ready (AUTO-CREATE RemoteEvents di ReplicatedStorage).")
