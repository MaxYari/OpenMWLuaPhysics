local mp = 'scripts/MaxYari/LuaPhysics/'


local world = require('openmw.world')
local types = require('openmw.types')
local I = require('openmw.interfaces')
local vfs = require('openmw.vfs')
local storage = require("openmw.storage")
local util = require("openmw.util")

local gutils = require(mp..'scripts/gutils')
local moveUtils = require(mp..'scripts/movement_utils')
local PhysicsUtils = require(mp..'scripts/physics_utils')
local PhysAiSystem = require(mp..'scripts/physics_ai_system')
local EventsManager = require(mp.."scripts/events_manager")
local D = require(mp..'scripts/physics_defs')

local settings = storage.globalSection('SettingsLuaPhysics')
local debrisPerExteriorCell = settings:get("DebrisPerExteriorCell")
local debrisPerInteriorCell = settings:get("DebrisPerInteriorCell")

local publicPropertyDamageRating = 0
local publicPropertyDamageLimit = 3
local ppDamageReductionRate = 0.1

local debrisMap = {}
local vfxMap = {}
local activeChunks = {}
local objectsToRemove = {}

local onPreFracture = EventsManager:new()


-- Extract clean name from the model path
local function getCleanName(modelPath)
    local filename = modelPath:match("([^/\\]+)$") -- Extract the filename from the path
    filename = filename:gsub("^x", "") -- Remove leading "x" if it exists
    local cleanName = filename:gsub("%.nif$", "") -- Remove the .nif extension
    return cleanName
end



-- Build debris map at startup
local function buildDebrisMap()
    --print("Building debris map")
    for filePath in vfs.pathsWithPrefix("meshes/debris") do
        if filePath:find("%.nif$") then
            local fileName = getCleanName(filePath)
            local objectName = fileName:gsub("__.+$", "") -- Remove trailing "__something" for debris chunks
            
            -- Handle _&number... pattern
            local andPattern = objectName:match("_(%&.+)$")
            local recordId = nil
            local forMeshNames = {}
            if andPattern then
                local baseName = objectName:gsub("_(%&.+)$", "")
                for num in andPattern:gmatch("&(%d+)") do
                    table.insert(forMeshNames,baseName .. "_" .. num)
                end
            else
                table.insert(forMeshNames,objectName)
            end

            for _, meshName in ipairs(forMeshNames) do
                if not debrisMap[meshName] then
                    debrisMap[meshName] = {}
                end
                --print("Checking debris map for", meshName, filePath)
                if not debrisMap[meshName][filePath] then
                    if not recordId then
                        -- No record for that filePath yet
                        local tempRecord = types.Miscellaneous.createRecordDraft({
                            name = "Debris",
                            model = filePath,
                            icon = "icons/m/debris.dds",
                        })
                        recordId = world.createRecord(tempRecord).id
                    end
                    --print("Adding record",recordId,"to debris map mesh name",meshName)
                    debrisMap[meshName][filePath] = recordId
                    --print("Adding debris map entry", meshName, filePath, recordId)
                end
            end
        end
    end
    --print("Debris map built")
end

local function findInObjectsMap(map, object)
    local cleanName = getCleanName(object.type.record(object).model)
    -- look for shatter meshes (generated records) made specifically for this mesh
    local result = map[cleanName]
    if not result then
        -- fallback to a non-specific shatter mesh for that group of objects (if such exists)
        cleanName = cleanName:gsub("_[%d]+$", "") -- Remove trailing "_number" for model names
        result = map[cleanName]
    end
    return result
end

-- Saves chunk into per-cell map of chunks, to later destroy chunks if too many accumulated
local function rememberActiveChunk(chunk, cell)
    if not activeChunks[cell.id] then 
        activeChunks[cell.id] = {
            chunksMap = {},
            chunksAmount = 0
        } 
    end
    local d = activeChunks[cell.id]
    if not d.chunksMap[chunk.id] then
        d.chunksMap[chunk.id] = chunk
        d.chunksAmount = d.chunksAmount + 1
    end
end


-- Function to split an item stack into smaller stacks
local function splitItemStack(item, nSplits)
    if item.count == 1 then return { item } end
    local nPerStack = math.ceil(item.count / nSplits)
    local stacks = {}
    while item.count > nPerStack do
        local splitStack = item:split(nPerStack) -- Split off a stack of size nPerStack
        table.insert(stacks, splitStack)
    end
    table.insert(stacks, item) -- Add the remaining stack
    return stacks
end

local function handleContainer(eventData)
    
    -- Handle container contents if the object is a container
    local object = eventData.object
    local position = object.position
    local baseImpulse = eventData.baseImpulse    
    
    print("Handling container fracture",object)
    local inventory = types.Container.content(object)
    inventory:resolve()
    local contents = inventory:getAll()
    print(contents)
    for _, item in pairs(contents) do
        -- print("Item in container:", item.recordId)
        local splitItems = splitItemStack(item, 5) -- Split the item stack into 5 smaller stacks
        for _, it in ipairs(splitItems) do
            it:teleport(object.cell, position)
            it:sendEvent(D.e.ApplyImpulse, { impulse = PhysicsUtils.randomizeImpulse(baseImpulse, 0.33) })
        end
    end
    
end

local function handlePotion(e)
    local object = e.object
    if not e.source then return end
    -- Apply potion effect
    if e.source and types.Actor.objectIsInstance(e.source) and types.Potion.objectIsInstance(e.object) then
        types.Actor.activeSpells(e.source):add({
            id = object.recordId,
            effects = {0},
            name = "Struck by potion",
            caster = world.players[1],
            quiet = false
        })
        -- Commit a crime
        I.Crimes.commitCrime(world.players[1], {victim = e.source, type = types.Player.OFFENSE_TYPE.Assault})
    end
end

local function corkedBottleCheck(object, flags)
    if object.type == types.Miscellaneous then
        local cleanName = getCleanName(object.type.record(object).model)
        if cleanName:find("misc_com_bottle") then
            local excludedIndices = { "02", "06", "09", "11" }
            for _, index in ipairs(excludedIndices) do
                if cleanName:match("_" .. index .. "$") then
                    return
                end
            end
            table.insert(flags.additionalVFX, "meshes/e/physics/transparent_liquid_shatter.nif")
            table.insert(flags.additionalSFX, "sounds/physics/extra/liquid_spill.wav")
        end
    end
end

-- Handle the FractureMe event
local function handleFractureMe(eventData)
    local object = eventData.object
    if not object or not object:isValid() or object.count == 0 then return end

    local position = object.position
    local baseImpulse = eventData.baseImpulse
    local debris = findInObjectsMap(debrisMap, object)

    -- print("handleFractureMe",gutils.tableToString(eventData))
    
    -- Run events and gather any modifying flags from them
    local flags = {
        prevent = false,
        spawnChunks = true,
        additionalVFX = {},
        playBaseSFX = true,
        additionalSFX = {},
        handleCrime = true
    }
    corkedBottleCheck(object, flags)
    onPreFracture:emit(object, eventData.culprit, debris, flags)

    if flags.prevent then return end

    -- print("Please destrroy", object,debris)

    if flags.spawnChunks then
        -- Check if debris exists for this object
        if not debris then return end

        -- Spawn debris chunks
        for _, recordId in pairs(debris) do
            local chunkObject = world.createObject(recordId)
            chunkObject:teleport(object.cell, position, { rotation = object.rotation })
            chunkObject:setScale(object.scale)

            -- Apply impulse to the debris chunk
            chunkObject:sendEvent(D.e.UpdatePersistentData, {isChunk = true})
            chunkObject:sendEvent(D.e.SetPhysicsProperties, { ignorePhysObjectCollisions = true, material = I.LuaPhysics.getMaterialFromObject(object)})
            chunkObject:sendEvent(D.e.ApplyImpulse, { impulse = PhysicsUtils.randomizeImpulse(baseImpulse, 0.33), culprit = eventData.culprit })
        end
    end
    
    if flags.playBaseSFX then
        -- Play crash sound
        I.LuaPhysics.playCrashSound({
            object = object,
            params = { volume = 2, pitch =  0.8 + math.random() * 0.2, loop = false }
        })
    end

    if #flags.additionalSFX then
        for _, sfxPath in ipairs(flags.additionalSFX) do
            I.LuaPhysics.playSound({
                file = sfxPath,
                object = object,
                params = { volume = 1, pitch =  0.8 + math.random() * 0.2, loop = false }
            })
        end
    end

    if #flags.additionalVFX then
        for _, vfxPath in ipairs(flags.additionalVFX) do
            local opt = { useAmbientLight = false }    
	        world.vfx.spawn(vfxPath, object.position, opt)
        end
    end
    

    -- Handle crime
    if flags.handleCrime and settings:get("CrimeSystemActive") and eventData.detectedBy and eventData.culprit and eventData.culprit.type == types.Player then
        if not PhysAiSystem.canTouch(object, eventData.culprit) then
            -- Instant crime
            PhysAiSystem.reportCrime(object, eventData.culprit, eventData.detectedBy, true)
            print("Destructible CRIME, destroyed owner item!",eventData.culprit,eventData.detectedBy)
        else
            -- This is a public property, mess around too much and it will become a crime
            publicPropertyDamageRating = publicPropertyDamageRating + 1
        end
        if publicPropertyDamageRating >= publicPropertyDamageLimit then
            -- Too much public property damaged, its a petty crime
            print("Destructible CRIME, too much public property damage")
            PhysAiSystem.reportCrime(50, eventData.culprit, eventData.detectedBy, true)
            publicPropertyDamageRating = 0
        end
    end

    -- Remove the fractured object
    -- print("destroying", object)
    I.LuaPhysics.removeObject(object)
end

local press = 0
local function generateTestChunks(e)
    press = press + 1
    
    local recordId
    for objName, chunks in pairs(debrisMap) do
        for filePath, recId in pairs(chunks) do
            recordId = recId
            goto fullbreak
        end
    end
    ::fullbreak::

    if not recordId then
        print("No recordId found for test chunks.")
        return
    end

    for i = 1, 1 do
        local randomOffset = util.vector3(
            math.random(-25, 25),
            math.random(-25, 25),
            math.random(-25, 25)
        )
        local chunkPosition = e.position + randomOffset

        local chunkObject = world.createObject(recordId,1)
        chunkObject:sendEvent(D.e.UpdatePersistentData, {isChunk = true})
        chunkObject:teleport(e.player.cell, chunkPosition)
        
        -- Apply impulse to the debris chunk
        --[[ chunkObject:sendEvent(D.e.UpdatePersistentData, {isChunk = true})
        rememberActiveChunk(chunkObject, object.cell)
        chunkObject:sendEvent(D.e.SetPhysicsProperties, { ignorePhysObjectCollisions = true})
        chunkObject:sendEvent(D.e.ApplyImpulse, { impulse = PhysicsUtils.randomizeImpulse(baseImpulse, 0.33) }) ]]
    end
    I.LuaPhysics.removeObject(e.object)
end



local function onObjectPersData(e)
    local source = e.source
    local data = e.data

    if not source.cell then return end
    if not data.isChunk then return end

    --print("Remembering chunk",source)
    rememberActiveChunk(source, source.cell)
end

local function pruneChunks()
    local player = world.players[1]
    if not player or not player.cell then return end

    local cellChunksData = activeChunks[player.cell.id]
    if not cellChunksData then return end

    local chunkLimit = player.cell.isExterior and debrisPerExteriorCell or debrisPerInteriorCell
    local chunksAmount = cellChunksData.chunksAmount
    local chunksMap = cellChunksData.chunksMap  

    if chunksAmount > chunkLimit then
        local playerPos = player.position
        local playerLookDir = moveUtils.lookDirection(player)
        local excess = chunksAmount - chunkLimit

        for key, chunk in pairs(chunksMap) do
            local chunkPos = chunk.position
            local toChunk = (chunkPos - playerPos):normalize()
            if playerLookDir:dot(toChunk) < 0 then                
                --print("Sneakily removing a ".. chunk.recordId .. "chunk")
                chunksMap[key] = nil
                I.LuaPhysics.removeObject(chunk)
                cellChunksData.chunksAmount = cellChunksData.chunksAmount - 1
                excess = excess - 1
            end
            ::continue::
            if excess <= 0 then break end
        end
    end
end

local lastPlayerCell = nil
local function onUpdate(dt)
    -- Tracking player's cell
    local player = world.players[1]
    -- print("misc objs in cell",world.players[1].cell.id,#world.players[1].cell:getAll(types.Miscellaneous))
    if lastPlayerCell and player.cell and lastPlayerCell ~= player.cell then
        -- Player changed cells, cleanup chunk data from an inactive cell
        -- This might be inaccurate in exteriors, but this is purely for chunk removal if they exceed cell limit, so should be good enough
        activeChunks[lastPlayerCell.id] = nil
    end
    lastPlayerCell = player.cell

    -- Checking if chunks need to be pruned
    pruneChunks()

    -- Gradually reducing publicPropertyDamageRating
    publicPropertyDamageRating = publicPropertyDamageRating - (ppDamageReductionRate * dt)
    if publicPropertyDamageRating < 0 then publicPropertyDamageRating = 0 end
end

local function onSave()
    return {
        debrisMap = debrisMap,
    }
end

local function onLoad(data)
    --print("Destructibe OnLoad/OnInit")
    if data and data.debrisMap then
        --print("Found debris map, assigning", data.debrisMap)
        --print("OnLoad, debris map:", data.debrisMap)
        debrisMap = data.debrisMap
    end
    buildDebrisMap()    
end

return {
    engineHandlers = {
        onSave = onSave,
        onLoad = onLoad,
        onInit = onLoad,
        onUpdate = onUpdate
    },
    eventHandlers = {
        [D.e.FractureMe] = handleFractureMe,
        [D.e.PersistentDataReport] = onObjectPersData,
        GenerateTestChunks = generateTestChunks
    },
    interfaceName = "LuaPhysicsDestructibles",
    interface = {
        version = 1.0,
        onPreFracture = onPreFracture
    },
}
