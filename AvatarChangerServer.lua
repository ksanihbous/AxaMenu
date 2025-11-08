--// ServerScriptService.AvatarChangerServer
-- Server handler untuk AvatarCatalog (AvatarChangerClient)
-- Menangani:
--  - ChangeAvatarEvent: ganti avatar ke userId target
--  - ResetAvatarEvent : reset ke avatar default player
--  - AddAccessoryEvent: tambah aksesoris (assetId)
--  - RemoveAccessoryEvent: hapus aksesoris (assetId)
-- RemoteEvent DIHARAPKAN berada langsung di ReplicatedStorage
--   (sesuai yang di-WaitForChild di LocalScript)

local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

---------------------------------------------------------------------
-- HELPERS
---------------------------------------------------------------------

-- Pastikan RemoteEvent ada di ReplicatedStorage (kalau sudah ada, pakai yang itu)
local function ensureRemoteEvent(name)
    local ev = ReplicatedStorage:FindFirstChild(name)
    if not ev then
        ev = Instance.new("RemoteEvent")
        ev.Name = name
        ev.Parent = ReplicatedStorage
        warn("[AvatarChangerServer] RemoteEvent '" .. name .. "' tidak ditemukan, membuat baru di ReplicatedStorage.")
    end
    return ev
end

local ChangeAvatarEvent  = ensureRemoteEvent("ChangeAvatarEvent")
local ResetAvatarEvent   = ensureRemoteEvent("ResetAvatarEvent")
local AddAccessoryEvent  = ensureRemoteEvent("AddAccessoryEvent")
local RemoveAccessoryEvent = ensureRemoteEvent("RemoveAccessoryEvent")

-- Map AssetTypeId -> nama field di HumanoidDescription
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

-- cache untuk mapping assetId -> field
local AssetFieldCache = {}  -- [assetId] = fieldName / false

local function getFieldForAssetId(assetId : number) : string?
    local cached = AssetFieldCache[assetId]
    if cached ~= nil then
        -- bisa string (fieldName) atau false (tidak valid)
        return cached or nil
    end

    local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, assetId, Enum.InfoType.Asset)
    local fieldName = nil

    if ok and info and info.AssetTypeId then
        fieldName = ACC_FIELD_BY_TYPEID[info.AssetTypeId]
    end

    -- kalau fieldName nil, simpan false supaya nggak request terus
    AssetFieldCache[assetId] = fieldName or false
    return fieldName
end

local function getHumanoid(player : Player) : Humanoid?
    local character = player.Character
    if not character then return nil end
    return character:FindFirstChildOfClass("Humanoid")
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

-- Tambah assetId ke field (kalau belum ada)
local function addAccessoryId(desc : HumanoidDescription, fieldName : string, assetId : number)
    local current = splitIds(desc[fieldName])
    for _, v in ipairs(current) do
        if v == assetId then
            -- sudah ada, tidak perlu apa-apa
            return
        end
    end
    table.insert(current, assetId)
    desc[fieldName] = joinIds(current)
end

-- Hapus assetId dari field (kalau ada)
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

---------------------------------------------------------------------
-- HANDLER: Ganti Avatar
---------------------------------------------------------------------

ChangeAvatarEvent.OnServerEvent:Connect(function(player, targetUserId)
    if typeof(targetUserId) ~= "number" then
        return
    end

    local humanoid = getHumanoid(player)
    if not humanoid then
        return
    end

    -- Ambil HumanoidDescription dari userId target (Boys/Girls list)
    local ok, desc = pcall(function()
        return Players:GetHumanoidDescriptionFromUserId(targetUserId)
    end)

    if not ok or not desc then
        warn("[AvatarChangerServer] Gagal ambil HumanoidDescription dari userId:", targetUserId)
        return
    end

    -- Apply ke humanoid player
    humanoid:ApplyDescription(desc)
end)

---------------------------------------------------------------------
-- HANDLER: Reset Avatar ke default player
---------------------------------------------------------------------

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

---------------------------------------------------------------------
-- HANDLER: Tambah Aksesoris
---------------------------------------------------------------------

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

---------------------------------------------------------------------
-- HANDLER: Hapus Aksesoris
---------------------------------------------------------------------

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

print("[AvatarChangerServer] Ready: ChangeAvatarEvent, ResetAvatarEvent, AddAccessoryEvent, RemoveAccessoryEvent aktif.")