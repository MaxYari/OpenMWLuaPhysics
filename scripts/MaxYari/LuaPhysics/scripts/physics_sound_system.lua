local mp = 'scripts/MaxYari/LuaPhysics/'

local core = require('openmw.core')
local vfs = require('openmw.vfs')
local world = require('openmw.world')

local gutils = require(mp..'scripts/gutils')
local moveutils = require(mp..'scripts/movement_utils')
local physMatSystem = require(mp..'scripts/physics_material_system')
local D = require(mp..'scripts/physics_defs')

local module = {masterVolume = 1}

-- Sound Map ----------------------------------------------------
-----------------------------------------------------------------
-- Extract clean name from the file path
local function getCleanFileName(filePath)
    local filename = filePath:match("([^/\\]+)$") -- Extract the filename from the path    
    local cleanName = filename:gsub("%.wav$", "") -- Remove the .nif extension
    cleanName = cleanName:gsub("__.+$", "")
    return cleanName
end


local MaterialSounds = {}
local function buildSoundsMap()
    for filePath in vfs.pathsWithPrefix("sounds/physics") do
        if filePath:find("%.wav$") then
            local materialType = getCleanFileName(filePath)
            --print("Material type from sound file:", materialType)
            
            if not MaterialSounds[materialType] then
                MaterialSounds[materialType] = {}
            end

            table.insert(MaterialSounds[materialType], filePath)
        end
    end    
end
buildSoundsMap()

-- Water sounds from impact effects mod
local waterSounds = {}
for file in vfs.pathsWithPrefix("sound/Fx/impact/Water") do
    if file:find("wav$") then table.insert(waterSounds, file) end
end


local MaterialHardnessMap = {
    Wood = "hard",
    Metal = "hard",
    Stone = "hard",
    Glass = "hard",    
    Dirt = "soft",    
    Snow = "soft",    
    Fabric = "soft",
    Paper = "soft",    
    Ceramic = "hard",
    Organic = "soft",
    Carpet = "soft",
    Book = "soft",
    Soulgem = "hard"
}
local function getMaterialHardness(material)
    if not MaterialHardnessMap[material] then
       return "hard"
    end
    return MaterialHardnessMap[material]
end


-- Sound tracking and limiting system -------------------------------
------------------------------------------------------------------
local activeSounds = {}
local soundDuration = 0.2 -- Assume all sounds last 0.2 seconds
local sectorAngle = math.pi / 3 -- 60 degrees in radians

local function cleanUpActiveSounds()
    local currentTime = core.getRealTime()
    for _, sounds in pairs(activeSounds) do
        for i = #sounds, 1, -1 do
            if currentTime - sounds[i].startTime > soundDuration then
                table.remove(sounds, i)
            end
        end
    end
end

local function canPlaySound(material, angle)
    if not activeSounds[material] then
        activeSounds[material] = {}
        return true
    end

    local countInSector = 0
    for _, sound in ipairs(activeSounds[material]) do
        if math.abs(sound.angle - angle) <= sectorAngle / 2 then
            countInSector = countInSector + 1
            if countInSector >= 2 then
                return false
            end
        end
    end
    return true
end

local function registerActiveSound(material, angle)
    if not activeSounds[material] then
        activeSounds[material] = {}
    end
    table.insert(activeSounds[material], { angle = angle, startTime = core.getRealTime() })
end

-- Sound Effects -----------------------------------------------------
-------------------------------------------------------------------
local function getObjectSizeString(object)
    local box = object:getBoundingBox()
    local maxHE = math.max(box.halfSize.x, box.halfSize.y, box.halfSize.z)/D.GUtoM -- In meters
    local minHE = math.min(box.halfSize.x, box.halfSize.y, box.halfSize.z)/D.GUtoM -- In meters
    -- print("Object size finder",maxHE,minHE)
    if maxHE <= 0.15 then return "Small"
    elseif minHE >= 1 then return "Big"
    else return "" end
end

local function playMaterialSound(material, object, params)
    material = string.lower(material)

    local sizedMaterial = material .. "_" .. string.lower(getObjectSizeString(object))
    -- print("Sized mat", sizedMaterial)
    if MaterialSounds[sizedMaterial] then
        material = sizedMaterial
    end

    if not MaterialSounds[material] then return end
    local soundFile = MaterialSounds[material][math.random(#MaterialSounds[material])]
    params.volume = params.volume * module.masterVolume

    local pl = world.players[1]
    local lookDir = moveutils.lookDirection(pl)
    local angle = moveutils.flatAngleBetween(lookDir:normalize(), (object.position - pl.position):normalize())

    -- Only play a sound if a limit of same mat sounds in vicinity is not exceeded
    cleanUpActiveSounds()
    if canPlaySound(material, angle) then
        --print("Playing sound", params.volume, soundFile, "at angle", angle)
        core.sound.playSoundFile3d(soundFile, object, params)
        registerActiveSound(material, angle)
    else
        --print("Sound skipped due to sector limit:", material, "at angle", angle)
    end
end
module.playMaterialSound = playMaterialSound

local function playSound(d)
    d.params.volume = d.params.volume * module.masterVolume
    core.sound.playSoundFile3d(d.file, d.object, d.params)
end
module.playSound = playSound

local function playCollisionSounds(data)
    -- Determine materials
    local objMat = data.material or physMatSystem.getMaterialFromObject(data.object)
    local surfMat
    if data.surface then
        surfMat = physMatSystem.getMaterialFromObject(data.surface)
    else
        surfMat = "Dirt"
    end

    local objSoundParams = data.params
    local surfSoundParams = gutils.shallowTableCopy(data.params)
    local h1 = getMaterialHardness(objMat)    
    local h2 = getMaterialHardness(surfMat)
    if (h1 == "soft" and h2 == "hard") then
        objSoundParams.volume = objSoundParams.volume * 1.5
        surfSoundParams.volume = surfSoundParams.volume * 0.5
    end
    if (h2 == "soft" and h1 == "hard") then
        objSoundParams.volume = objSoundParams.volume * 0.5
        surfSoundParams.volume = surfSoundParams.volume * 1.5
    end
    --print("Colliding objects hardness", h1, "Surface hardness", h2)
    --print("Colliding objects material", objMat, "Surface material", surfMat)

    playMaterialSound(objMat, data.object, objSoundParams)
    playMaterialSound(surfMat, data.object, surfSoundParams)
end
module.playCollisionSounds = playCollisionSounds

local function playCrashSound(data)
    local objMat = data.material or physMatSystem.getMaterialFromObject(data.object)
    objMat = objMat .. "_crash"
    playMaterialSound(objMat, data.object, data.params)
end
module.playCrashSound = playCrashSound

local function playWaterSplashSound(data)
    local soundFile = waterSounds[math.random(#waterSounds)]
    if not soundFile then return end
    data.params.volume = data.params.volume * module.masterVolume
    core.sound.playSoundFile3d(soundFile, data.object, data.params)
end
module.playWaterSplashSound = playWaterSplashSound

return module