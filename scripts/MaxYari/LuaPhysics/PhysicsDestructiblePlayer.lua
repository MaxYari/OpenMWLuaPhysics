-- OpenMW Lua Physics - Authors: Maksim Eremenko, GPT-4o (Copilot)

local mp = 'scripts/MaxYari/LuaPhysics/'

local types = require('openmw.types')
local omwself = require('openmw.self')
local interfaces = require('openmw.interfaces')
local core = require('openmw.core')
local util = require('openmw.util')
local camera = require('openmw.camera')
local animation = require('openmw.animation')
local I = require('openmw.interfaces')

local gutils = require(mp..'scripts/gutils')
local animManager = require(mp..'scripts/anim_manager')
local PhysicsUtils = require(mp..'scripts/physics_utils')
local D = require(mp..'scripts/physics_defs')

local selfActor = gutils.Actor:new(omwself)

local MaxHitImpulse = 600
local frame = 0
local hitProcessedFrame = -1


animManager.onHitKey:addEventHandler(function(groupname, key, isMax)
    --print("Animation event", groupname,"Key",key)
    if frame == hitProcessedFrame then return end

    local damage = 5
    local hitImpulse = MaxHitImpulse
    if isMax then damage = 10 end
    if not isMax then hitImpulse = MaxHitImpulse/2 end

    PhysicsUtils.GetLookAtObject(selfActor:getAttackRange(), function(obj)            
        if obj then
            local direction = camera.viewportToWorldVector(util.vector2(0.5, 0.5)):normalize()
            local finalImpulse = direction * hitImpulse + util.vector3(0, 0, 1) * hitImpulse
            obj:sendEvent(D.e.ApplyImpulse, {
                impulse = finalImpulse,
                culprit = omwself
            })
            obj:sendEvent(D.e.DestructibleHit, {
                damage = damage,
                culprit = omwself,
                impulse = finalImpulse,
            })
        end
    end)

    hitProcessedFrame = frame
end)


local function onUpdate(dt)
    frame = frame + 1
end

return {
    engineHandlers = {        
        onUpdate = onUpdate        
    }
}







