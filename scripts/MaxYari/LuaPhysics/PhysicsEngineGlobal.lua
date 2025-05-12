local mp = 'scripts/MaxYari/LuaPhysics/'

local world = require('openmw.world')
local storage = require("openmw.storage")

local PhysicsObject = require(mp..'PhysicsObject')
local PhysSoundSystem = require(mp..'scripts/physics_sound_system')
local PhysMatSystem = require(mp..'scripts/physics_material_system')
local PhysAiSystem = require(mp..'scripts/physics_ai_system')
local D = require(mp..'scripts/physics_defs')
local gutils = require(mp..'scripts/gutils')

local settings = storage.globalSection('SettingsLuaPhysics')
local doSelfCollisions = settings:get("SelfCollisions")
local crimeSystemActive = settings:get("CrimeSystemActive")


-- local physicsObjectScript = mp.."PhysicsEngineLocal.lua"
-- if true then return end

-- Defines -----------------
local frame = 0
PhysSoundSystem.masterVolume = 2

local physObjectsMap = {}
local objectsToRemove = {}


-- Grid collision system for dynamic objects ----------------------------------------------
-------------------------------------------------------------------------------------------
local grid = {}
local gridSize = 150
local function getGridCellCoord(position)
    return math.floor(position.x / gridSize), math.floor(position.y / gridSize), math.floor(position.z / gridSize)
end

local function updateInGrid(physObject)
    local lastGridCell = physObject.gridCell
    local id = physObject.object.id
    if lastGridCell then lastGridCell[id] = nil end
    
    local cellX, cellY, cellZ = getGridCellCoord(physObject.position)
    --local cellKey = string.format("%d,%d,%d", cellX, cellY, cellZ)
    if not grid[cellX] then
        grid[cellX] = {}
    end
    if not grid[cellX][cellY] then
        grid[cellX][cellY] = {}
    end
    local gridCell = grid[cellX][cellY][cellZ]
    if not gridCell then
        gridCell = {}
        grid[cellX][cellY][cellZ] = gridCell
    end
    gridCell[id] = physObject
    physObject.gridCell = gridCell
end

local function removeFromGrid(physObject)
    if not physObject.gridCell then return end
    --print("Removing",physObject.object,"from cell",physObject.gridCell)
    physObject.gridCell[physObject.object.id] = nil
end

local function serialize(physObject) 
    return {
        object = physObject.object,
        position = physObject.position,
        velocity = physObject.velocity,
        mass = physObject.mass,
        culprit = physObject.culprit,
        bounce = physObject.bounce,
        radius = physObject.radius
    }
end

local function checkCollisionsInGrid()    
    local alreadyChecked = {}    
    for cellX, cellYs in pairs(grid) do        
        for cellY, cellZs in pairs(grid[cellX]) do            
            for cellZ, objects in pairs(grid[cellX][cellY]) do           
                for id, physObj1 in pairs(objects) do
                    for id, physObj2 in pairs(objects) do                        
                        if physObj1.object == physObj2.object or alreadyChecked[physObj2] then goto continue end
                        if physObj1.isSleeping and physObj2.isSleeping then goto continue end
                        if PhysicsObject.isCollidingWith(physObj1, physObj2) then
                            --print("2 objects colliding, here they are",gutils.tableToString(physObj1),gutils.tableToString(physObj2))
                            physObj1.object:sendEvent(D.e.CollidingWithPhysObj, { other = serialize(physObj2) })
                            physObj2.object:sendEvent(D.e.CollidingWithPhysObj, { other = serialize(physObj1) })
                        end
                        ::continue::
                    end
                    alreadyChecked[physObj1] = true
                end
            end
        end
    end
end
---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------



-- Moving objects and checking grid-optimised collisions with other physics objects -------------------
---------------------------------------------------------------------------------------------------------

local function onPhysObjPropsUpdate(props)
    local id = props.object.id
    local physObj = physObjectsMap[id]
    if not physObj then
        physObj = {}
        physObjectsMap[id] = physObj
    end
    local prevSleepState = physObj.isSleeping
    gutils.shallowMergeTables(physObj, props)
    --print("Updated phys obj",physObj.object,"with props",gutils.tableToString(props))
    if doSelfCollisions and not physObj.ignorePhysObjectCollisions then
        if physObj.position then updateInGrid(physObj) end
    end
end

local function handleUpdateVisPos(pObjData)
    
    -- print("Global received teleport request from",d.object,"At frame",frame)
    local object = pObjData.object
    local cell = object.cell

    -- print("Upd vis pos on ",object,cell)

    if objectsToRemove[object.id] then return end
        
    local physObj = physObjectsMap[object.id]
    if not physObj or not physObj.initialized then return end
    
    if not physObj.origin then
        print("WARNING WARNING, physics object without origin!")
        print(gutils.tableToString(physObj))
    end
    local position = pObjData.position - pObjData.rotation:apply(physObj.origin)
    local rotation = pObjData.rotation

    --local isChunk5 = string.find(object.type.record(object).model:lower(),"misc_com_bottle__chunk_5")
    --if isChunk5 then print("Chunk 5 teleport request", pObjData.position) end
    
    if object and object.count > 0 and cell ~= nil then
        object:teleport(cell, position, { rotation = rotation })
        onPhysObjPropsUpdate(pObjData) 
    end
end

local function removeObject(obj)
    objectsToRemove[obj.id] = obj
    local physObj = physObjectsMap[obj.id] 
    if physObj then
        removeFromGrid(physObj)
        physObjectsMap[obj.id] = nil
    end
    --obj:remove()
end



-- onUpdate ----- 
-----------------
local function onUpdate(dt)
    --print("Global Onupdate frame", frame)
    frame = frame + 1

    -- refetch settings
    doSelfCollisions = settings:get("SelfCollisions")
    crimeSystemActive = settings:get("CrimeSystemActive")

    -- removal of scheduled objects
    for id, obj in pairs(objectsToRemove) do
        obj:remove()
    end
    objectsToRemove = {}

    if not PhysMatSystem.initialized then
        PhysMatSystem.init()
    end

    if doSelfCollisions then
        checkCollisionsInGrid()        
    end

    if crimeSystemActive then
        PhysAiSystem.update()
    end
end



return {
    engineHandlers = {
        onUpdate = onUpdate,        
    },
    eventHandlers = {
        [D.e.UpdateVisPos] = handleUpdateVisPos,
        [D.e.PhysPropUpdReport] = function (data)
            onPhysObjPropsUpdate(data)
        end,
        [D.e.RemoveObject] = function(data)
            removeObject(data.object)
        end,
        [D.e.SpawnCollilsionEffects] = function (data)
            PhysMatSystem.spawnCollilsionEffects(data)
        end,
        [D.e.SpawnMaterialEffect] = function (data)
            PhysMatSystem.spawnMaterialEffect(data.material, data.position)
        end,
        [D.e.PlayCollisionSounds] = function(data)
            PhysSoundSystem.playCollisionSounds(data)
        end,
        [D.e.PlayCrashSound] = function(data)
            PhysSoundSystem.playCrashSound(data)            
        end,
        [D.e.PlaySound] = function(data)
            PhysSoundSystem.playSound(data)            
        end,
        [D.e.PlayWaterSplashSound] = function(data)
            PhysSoundSystem.playWaterSplashSound(data)            
        end,
        [D.e.WhatIsMyPhysicsData] = function(data)
            local mat = PhysMatSystem.getMaterialFromObject(data.object)
            data.object:sendEvent(D.e.SetMaterial, { material = mat})
            data.object:sendEvent(D.e.SetPhysicsProperties, { player = world.players[1]})
        end,
        [D.e.ObjectFenagled] = function(...)
            if not crimeSystemActive then return end
            PhysAiSystem.onObjectFenagled(...)
        end,
        [D.e.DetectCulpritResult] = function(...)
            if not crimeSystemActive then return end
            PhysAiSystem.onDetectCulpritResult(...)
        end
    },
    interfaceName = "LuaPhysics",
    interface = {
        version = 1.0,
        playCrashSound = PhysSoundSystem.playCrashSound,
        playSound = PhysSoundSystem.playSound,
        getMaterialFromObject = PhysMatSystem.getMaterialFromObject,
        removeObject = removeObject
    },
}
