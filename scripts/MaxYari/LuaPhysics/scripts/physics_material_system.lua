local I = require('openmw.interfaces')
local types = require("openmw.types")

local module = {
    initialized = false,
}

local function init()
    if I.impactEffects then
        print("Adding fallbacks to impactEffects")
        I.impactEffects.registerFallback("_bed_", "Fabric")
        I.impactEffects.registerFallback("_pillow_", "Fabric")
        I.impactEffects.registerFallback("_fabric_", "Fabric")
        I.impactEffects.registerFallback("_pot_", "Ceramic")
        I.impactEffects.registerFallback("_bowl_", "Ceramic")
        I.impactEffects.registerFallback("_soulgem_", "Soulgem")
        module.initialized = true
    end
end
module.init = init

local function getMaterialFromObject(object)
    if not object then return "Unknown" end
    if not I.impactEffects then return "Unknown" end

    local mat = nil

    -- type book override here
    if object.type == types.Book then
        local modelName = object.type.record(object).model:lower()
        if string.find(modelName,"_scroll") or string.find(modelName,"_parchment") then
            mat = "Paper"
        else
            mat = "Book"
        end
    else
        mat = I.impactEffects.getMaterialByObject(object)
    end
    
    if mat == nil or mat == "Unknown" then
        -- Potential additional material fallback here        
    end

    --print(object,"material",mat)
    return mat
end
module.getMaterialFromObject = getMaterialFromObject

local function spawnMaterialEffect(material, position)
    if not I.impactEffects then return end
    I.impactEffects.spawnEffect({                
        hitPos = position,
        material = material             
    })
end
module.spawnMaterialEffect = spawnMaterialEffect

local function spawnCollilsionEffects(data)
    if not I.impactEffects then return end

    local om = getMaterialFromObject(data.object)
    local sm = getMaterialFromObject(data.surface)

    local spawnProb = 0.75
    local effectMaterial = sm

    if sm == "Metal" or sm == "Stone" then
        effectMaterial = "Unknown"
    end
    if (sm == "Metal" or sm == "Stone") and (om == "Metal" or om == "Stone") then
        effectMaterial = sm
        spawnProb = 0.25
    end
    if sm == "Wood" or om == "Wood" then
        effectMaterial = "Wood"
    end

    if math.random() > spawnProb then return end

    spawnMaterialEffect(effectMaterial, data.position)
end
module.spawnCollilsionEffects = spawnCollilsionEffects

return module