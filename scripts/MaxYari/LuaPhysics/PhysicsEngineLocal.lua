-- OpenMW Lua Physics - Authors: Maksim Eremenko, GPT-4o (Copilot)

local mp = 'scripts/MaxYari/LuaPhysics/'

local core = require('openmw.core')
local util = require('openmw.util')
local vfs = require('openmw.vfs')
local nearby = require('openmw.nearby')

local omwself = require('openmw.self')

local PhysicsObject = require(mp..'PhysicsObject')

local D = require(mp..'scripts/physics_defs')


-- if omwself.recordId ~= "p_restore_health_s" then return end
-- if omwself.recordId ~= "food_kwama_egg_02" then return end
-- TO DO: save serialised state of the physics object in onsave



-- Main stuff ----------------------------------------------
------------------------------------------------------------
local frame = 0
local lastCell = omwself.cell
local physicsObject = PhysicsObject:new(omwself, { drag = 0.1, bounce = 0.5, isSleeping = true })
local lastUnderwater = physicsObject.isUnderwater
local crossedWater = false
local lastSleeping = physicsObject.isSleeping
local persistentData = {}


local soundPause = 0.23;
local lastSoundTime = 0.0;
local sfxMinSpeed = 50;
local fenagledMinSpeed = 50;

local function volumeFromVelocity(velocity)
    local volume = 0
    if velocity:length() >= sfxMinSpeed then
        volume = util.remap(velocity:length(), sfxMinSpeed, 600, 0.33, 1)
        -- print("Volume:", volume)
    end
    return volume
end

local function tryPlayCollisionSounds(hitResult)
    local now = core.getRealTime()
    local velocity = physicsObject.velocity
    local volume = volumeFromVelocity(velocity)
    
    local pitch = 0.8 + math.random() * 0.2
    local params = { volume = volume, pitch = pitch, loop = false }

    if volume > 0 and now - lastSoundTime > soundPause then
        -- Play sounds
        core.sendGlobalEvent(D.e.PlayCollisionSounds, {
            object = omwself,
            surface = hitResult.hitObject,                              
            params = params
        })

        -- Spawn visual effect
        core.sendGlobalEvent(D.e.SpawnCollilsionEffects, {
            object = omwself,
            surface = hitResult.hitObject, 
            position = hitResult.hitPos
        })

        lastSoundTime = now
    end
end

local function tryPlayWaterSounds()
    local now = core.getRealTime()
    if not physicsObject.isSleeping and physicsObject.velocity:length() > 50 and now - lastSoundTime > soundPause then
        core.sendGlobalEvent(D.e.SpawnMaterialEffect, {
            material = "Water",
            position = physicsObject.position
        })
        core.sendGlobalEvent(D.e.PlayWaterSplashSound, {
            object = omwself,
            params = { volume = volumeFromVelocity(physicsObject.velocity), pitch = 0.8 + math.random() * 0.2, loop = false }
        })
        lastSoundTime = now
    end
end


local lastOOBCheck = math.random()
local function checkOutOfBounds()
    if physicsObject.isSleeping then return end
    local now = core.getRealTime()
    if now - lastOOBCheck < 1 then return end

    local position = physicsObject.position
    local initialPosition = physicsObject.initialPosition
    local isOOB = false

    if omwself.cell and not omwself.cell.isExterior then
        -- Interior cell: check if object is 100 meters below its initial position
        if position.z < initialPosition.z - 100 * 72 then
            print("Interior cell out of bounds detectewd, resetting", omwself)
            physicsObject:resetPosition(true)
            isOOB = true
        end
    elseif omwself.cell and omwself.cell.isExterior then
        -- Exterior cell: track underwater status and cast ray upwards if status changes
        if crossedWater then
            if physicsObject.isUnderwater then
                local rayStart = position
                local rayEnd = position + util.vector3(0, 0, 10000 * 72)
                local hitResult = nearby.castRay(rayStart, rayEnd, { collisionType = nearby.COLLISION_TYPE.HeightMap })

                if hitResult and hitResult.hit then
                    print("Exterior cell out of bounds detectewd, resetting", omwself)
                    physicsObject:resetPosition(true)
                    isOOB = true
                end
            end
        end
    end
    lastOOBCheck = now
    return isOOB
end


local function onCollision(hitResult)
    tryPlayCollisionSounds(hitResult)
    if physicsObject.velocity:length() >= fenagledMinSpeed then
        core.sendGlobalEvent(D.e.ObjectFenagled, {
            object = omwself,
            culprit = physicsObject.culprit,
            isOffensive = true
        })
    end
end

physicsObject.onCollision:addEventHandler(onCollision)
physicsObject.onPhysObjectCollision:addEventHandler(onCollision)

local function onUpdate(dt)
    if physicsObject.isSleeping or not omwself.count then return end   
    
    local cell = omwself.cell
    
    if cell and not lastCell then
        -- Reset physics state if was just taken out of the inventory
        physicsObject:reInit()
    end
    lastCell = cell

    -- nil cell == we are in the inventory/container, no physics are needed
    if cell == nil then         
        return
    end

    -- Update physics simulation
    physicsObject:update(dt)
    physicsObject:trySleep(dt)

    -- Sending owner event if just awoken
    if physicsObject.isSleeping == false and physicsObject.isSleeping ~= lastSleeping then
        lastSleeping = physicsObject.isSleeping
        core.sendGlobalEvent(D.e.ObjectFenagled, {
            object = omwself,
            culprit = physicsObject.culprit
        })
    end
    
    -- Detecting crossing of a water boundary line
    if lastUnderwater ~= physicsObject.isUnderwater then
        crossedWater = true        
    else
        crossedWater = false
    end
    lastUnderwater = physicsObject.isUnderwater
    
    -- Check if object is out of bounds -- should be done after water threshold crossing was detected
    local isOOB = checkOutOfBounds()

    -- Water splash sounds
    if crossedWater and not isOOB then tryPlayWaterSounds() end

    frame = frame + 1
end

onUpdate(0)



local function onSave()
    return {
        physicsObjectPersistentData = physicsObject:getPersistentData(),
        persistentData = persistentData
    }
end

local function onLoad(data)
    if not data then return end
    if data.persistentData then 
        persistentData = data.persistentData 
        core.sendGlobalEvent(D.e.PersistentDataReport, {
            source = omwself,
            data = persistentData
        })
    end
    physicsObject:loadPersistentData(data.physicsObjectPersistentData)
end

local function onInactive(data)
    print("Object", omwself.recordId, "is inactive")
    core.sendGlobalEvent(D.e.InactivationReport, {
        object = omwself
    })
end



return {
    engineHandlers = {
        onUpdate = onUpdate,
        onSave = onSave,
        onLoad = onLoad,
        onInactive = onInactive
    },
    eventHandlers = {
        [D.e.MoveTo] = function(e)
            local currentVelocity = physicsObject.velocity;
            local pushVector = e.position - physicsObject.position - currentVelocity/4;
    
            if pushVector:length() > e.maxImpulse then
                pushVector = pushVector:normalize() * e.maxImpulse
            end

            physicsObject:applyImpulse(pushVector, e.culprit)
        end,
        [D.e.ApplyImpulse] = function(e)
            physicsObject:applyImpulse(e.impulse, e.culprit)
        end,
        [D.e.SetPhysicsProperties] = function(props)
            --print("Received physics properties",gutils.tableToString(props))
            physicsObject:updateProperties(props)
        end,
        [D.e.SetMaterial] = function(e)
            physicsObject:updateMaterial(e.material, e.recalcMass, e.recalcBuoyancy)
        end,
        [D.e.SetPositionUnadjusted] = function(e)
            physicsObject:setPositionUnadjusted(e.position)
        end,
        [D.e.CollidingWithPhysObj] = function(e)
            --print("Received phys object collide event",e.other.object.recordId)
            physicsObject:handlePhysObjectCollision(e.other)
        end,
        [D.e.UpdatePersistentData] = function(data)
            persistentData = data
            core.sendGlobalEvent(D.e.PersistentDataReport, {
                source = omwself,
                data = persistentData
            })
        end
    },
    interfaceName = "LuaPhysics",
    interface = {version=1.0, physicsObject=physicsObject}
    
}







