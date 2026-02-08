-- OpenMW Lua Physics - Authors: Maksim Eremenko, GPT-4o (Copilot)

local mp = 'scripts/MaxYari/LuaPhysics/'

local core = require('openmw.core')
local util = require('openmw.util')
local types = require('openmw.types')
local nearby = require('openmw.nearby')
local vfs = require('openmw.vfs')
local omwself = require('openmw.self')
local interfaces = require('openmw.interfaces')

local gutils = require(mp..'scripts/gutils')
local PhysAiSystem = require(mp..'scripts/physics_ai_system')
local D = require(mp..'scripts/physics_defs')

--if omwself.recordId ~= "p_restore_health_s" then return end
-- print("Destructible object script attached to", omwself.recordId)


local eventHandlersAttached = false
local heldByActor = nil
local minCollisionDmgSpeed = 2*D.GUtoM

local inst = {
    maxHp = 10,
    hp = 10
}


local crashMaxDetecDist = 15*D.GUtoM
local function checkHeardByOwnerOrGuards(culprit)
    --if not culprit then return nil end
    --if PhysAiSystem.canTouch(omwself, culprit) then return false end

    local ownerId = omwself.owner.recordId
    if ownerId == culprit.recordId then return end

    -- print("Checking if ",culprit,"is detected")

    local factionId = omwself.owner.factionId
    local owner, guards, factionMembers = PhysAiSystem.findRelevantNPCsInCell(omwself.cell, nearby.actors, ownerId, factionId)
    local checkDetection = function(npcs)
        for _, npc in ipairs(npcs) do
            if (omwself.position - npc.position):length() < crashMaxDetecDist then return npc end
        end
    end
    local detectedBy = checkDetection(owner)
    if not detectedBy then detectedBy = checkDetection(guards) end
    if not detectedBy then detectedBy = checkDetection(factionMembers) end
    return detectedBy
end

local function onHitReceived(e)
    -- This logic will be moved to destructible containers mod
    --[[ local lockLevel = types.Lockable.getLockLevel(omwself)
    if not e.ignoreLock and lockLevel and lockLevel > 0 then
        return
    end ]]

    
    inst.hp = inst.hp - e.damage
    -- print("Destructible object received a hit", e.damage, inst.hp)

    if inst.hp <= 0 then
        core.sendGlobalEvent(D.e.FractureMe, {
            object = omwself,
            culprit = e.culprit,
            baseImpulse = e.impulse,
            detectedBy = checkHeardByOwnerOrGuards(e.culprit)
        })
    end
end

local function onCollision(hitResult)
    -- print(omwself.recordId,"On collision")
    local physObject = interfaces.LuaPhysics.physicsObject
    
    if hitResult.hitObject and hitResult.hitObject == heldByActor then return end

    if physObject.velocity:length() >= minCollisionDmgSpeed then
        onHitReceived({
            damage = 1,
            impulse = physObject.velocity * 1.2,
            culprit = physObject.culprit
        })
    end
end

local function onMaterialUpdate(mat)
    -- print(omwself.recordId, "On material update", mat)
    if mat == "Glass" then
        inst.maxHp = 5
        if inst.hp > inst.maxHp then inst.hp = inst.maxHp end
    end
end

local physObject = interfaces.LuaPhysics.physicsObject
physObject.onCollision:addEventHandler(onCollision)
--physObject.onPhysObjectCollision:addEventHandler(onCollision)
physObject.onIntersection:addEventHandler(onCollision)
physObject.onMaterialUpdate:addEventHandler(onMaterialUpdate)
-- print("Destr object is adding event handlers to physObject")




return {
    eventHandlers = {
        [D.e.HeldBy] = function (e)
            heldByActor = e.actor
        end,
        [D.e.DestructibleHit] = function (e)
            onHitReceived(e)
        end
    },
    interfaceName = "LuaPhysicsDestructibles",
    interface = {
        version = 1.0,
        destructibleObject = inst
    },
    
}







