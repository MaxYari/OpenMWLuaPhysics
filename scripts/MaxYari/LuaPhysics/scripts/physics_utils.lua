local mp = 'scripts/MaxYari/LuaPhysics/'

local core = require('openmw.core')
local util = require('openmw.util')
local types = require('openmw.types')
local nstatus, nearby = pcall(require, "openmw.nearby")
local ustatus, ui = pcall(require, 'openmw.ui')
local cstatus, camera = pcall(require, 'openmw.camera')
local sstatus, omwself = pcall(require, 'openmw.self')
local itatus, input = pcall(require, 'openmw.input')
local async = require('openmw.async')

local gutils = require(mp..'scripts/gutils')
local D = require(mp..'scripts/physics_defs')

local module = {activeObject = nil}

local grabDistance = 200;
local maxDragImpulse = 300;
local throwImpulse = 500.0;


local holdDistance;
local holdOffset;

-- Utilities ------------------------------------------------------
-------------------------------------------------------------------
-- Calculate sphere position along the ray based on sphere cast hit position
local function calcSpherePosAtHit(from, to, hitPos, radius) 
    local c = hitPos
    local r = radius
    local o = from
    local u = (to - from):normalize()
    local v1 = util.vector3(1, 1, 1)
    local dist = 0

    local Det = 0
    local dist1 = 0
    local dist2 = 0

    if (from - hitPos):length() < radius then        
        dist = 0
        goto out
    end
    
    Det = u:dot(o - c)^2 - (o - c):length()^2 + r * r
    
    if Det < 0 and Det > -0.1 then Det = 0
    elseif Det <= -0.1 then 
        dist = 0 
        goto out
    end

    dist1 = - u:dot(o - c) + math.sqrt(Det)
    dist2 = - u:dot(o - c) - math.sqrt(Det)
    
    if dist1 < 0 and dist2 < 0 then        
        dist = 0
        goto out
    end

    if dist1 < 0 then dist = dist2
    elseif dist2 < 0 then dist = dist1
    else dist = math.min(dist1, dist2) end

    ::out::

    local pos = o + u * dist
    
    return pos
end
module.calcSpherePosAtHit = calcSpherePosAtHit

-- Custom implementation of slerp for rotations (interpolates all axes)
local function slerpRotation(from, to, t)
    local fZ, fY, fX = from:getAnglesZYX()
    local tZ, tY, tX = to:getAnglesZYX()

    --local lpZ = util.remap(t, 0, 1, fZ, tZ)
    local lpY = util.remap(t, 0, 1, fY, tY)
    local lpX = util.remap(t, 0, 1, fX, tX)
    return util.transform.rotateX(lpX) * util.transform.rotateY(lpY) * util.transform.rotateZ(fZ)
end
module.slerpRotation = slerpRotation



local function GrabObject()
    local position = camera.getPosition()
    local direction = camera.viewportToWorldVector(util.vector2(0.5, 0.5)):normalize()
    local pickupDistance = grabDistance
    local castResult = nearby.castRenderingRay(position, position + direction * pickupDistance)
    local object = castResult.hitObject
 
    if not object then return end
    --local physObject = it.DumbPhysics.getPhysicsObject(object)
    --if not physObject then return end
    
    module.activeObject = object
    holdDistance = (castResult.hitPos - position):length()
    holdOffset = castResult.hitPos - module.activeObject.position
 
    --ui.showMessage("Grabbing " .. module.activeObject.recordId)    
    
    module.activeObject:sendEvent(D.e.HeldBy, { actor = omwself.object });
end
module.GrabObject = GrabObject


local function DropObject()
    if not module.activeObject then return end
    --module.activeObject.ignorePhysObjectCollisions = false
    --module.activeObject.ignoreWorldCollisions = false
    module.activeObject:sendEvent(D.e.HeldBy, { actor = nil });
    module.activeObject = nil
end
module.DropObject = DropObject

local function HoldGrabbedObject(dt, ignoreCollisions)
    if not module.activeObject then return end
    
    local position = camera.getPosition()
    local direction = camera.viewportToWorldVector(util.vector2(0.5, 0.5)):normalize()
    local objectHoldPos = position + direction*holdDistance;

    module.activeObject:sendEvent(D.e.SetPhysicsProperties, {
        ignorePhysObjectCollisions = ignoreCollisions,
        ignoreWorldCollisions = ignoreCollisions
    })
    module.activeObject:sendEvent(D.e.MoveTo, { position = objectHoldPos, maxImpulse = maxDragImpulse, culprit = omwself.object })

    
end
module.HoldGrabbedObject = HoldGrabbedObject

local function randomizeImpulse(impulse, randomisationAmount)
    local unrandWeight = 1 - randomisationAmount
    -- local direction = impulse:normalize()
    local strength = impulse:length()
    local randomDirection = gutils.randomDirection()
    return impulse * unrandWeight + randomDirection * strength * randomisationAmount
end
module.randomizeImpulse = randomizeImpulse

local function PushObjects()
    local position = camera.getPosition()
    local direction = camera.viewportToWorldVector(util.vector2(0.5, 0.5)):normalize()
    local cylinderRadius = 100 -- Radius of the cylinder
    local cylinderLength = 500 -- Length of the cylinder
    local impulseStrength = 500

    -- Iterate through all nearby items
    for _, object in ipairs(nearby.items) do
        --local physObject = it.DumbPhysics.getPhysicsObject(object)
        if object:isValid() then
            -- Calculate the vector from the camera position to the object
            local toObject = object.position - position

            -- Project the vector onto the camera direction
            local projectionLength = toObject:dot(direction)
            if projectionLength > 0 and projectionLength <= cylinderLength then
                -- Calculate the perpendicular distance from the object to the cylinder axis
                local perpendicularDistance = (toObject - direction * projectionLength):length()
                if perpendicularDistance <= cylinderRadius then
                    -- Apply impulse to the object
                    local impulse = randomizeImpulse(direction * impulseStrength,0.25)
                    object:sendEvent(D.e.ApplyImpulse, {impulse=impulse, culprit = omwself.object })
                end
            end
        end
    end
    ui.showMessage("N'wah!")
end
module.PushObjects = PushObjects

local function ExplodeObjects()
    local position = camera.getPosition()
    local direction = camera.viewportToWorldVector(util.vector2(0.5, 0.5)):normalize()
    local rayLength = 500 -- Length of the ray
    local explosionRadius = 200 -- Radius of the explosion
    local explosionForce = 1000 -- Strength of the explosion

    -- Perform a raycast to find the explosion center
    local rayEnd = position + direction * rayLength
    local castResult = nearby.castRenderingRay(position, rayEnd)

    -- Determine the explosion center
    local explosionCenter = castResult.hit and castResult.hitPos or rayEnd

    -- Iterate through all nearby items
    for _, object in ipairs(nearby.items) do
        --local physObject = it.DumbPhysics.getPhysicsObject(object)
        if object:isValid() then
            -- Calculate the distance from the object to the explosion center
            local toObject = object.position - explosionCenter
            local distance = toObject:length()

            if distance <= explosionRadius then
                -- Calculate the explosion impulse
                local directionAway = toObject:normalize()
                local impulse = directionAway * (explosionForce * (1 - distance / explosionRadius))
                object:sendEvent(D.e.ApplyImpulse, {impulse=impulse, culprit = omwself.object })
            end
        end
    end

    ui.showMessage("Explode!")
end
module.ExplodeObjects = ExplodeObjects

local function GetLookAtObject(dist, cb)
    local position = camera.getPosition()
    local direction = camera.viewportToWorldVector(util.vector2(0.5, 0.5)):normalize()   
    if cb then
        nearby.asyncCastRenderingRay(async:callback(function(castResult)
            cb(castResult.hitObject)
        end), position, position + direction * dist)
    else
        local castResult = nearby.castRenderingRay(position, position + direction * dist)
        return castResult.hitObject
    end
end
module.GetLookAtObject = GetLookAtObject

local function DupeObject()
    local object = GetLookAtObject(grabDistance)
 
    if not object then return end
 
    ui.showMessage("Duping " .. object.recordId)

    local randomPosRange = 50
    local randomPosDelta = util.vector3(math.random(-randomPosRange, randomPosRange), math.random(-randomPosRange, randomPosRange), 0)
 
    core.sendGlobalEvent("SpawnObject", {
        recordId = object.recordId,
        position = object.position + randomPosDelta,
        cell = object.cell.name,
        onGround = true
    })
end
module.DupeObject = DupeObject

local function customRaycastAABB(position, endPosition, radius, box, rotation, castOpts)
    local rays = {}
    local halfSize = box.halfSize
    local displacement = endPosition - position
    local endPos = position + displacement:normalize() * (displacement:length() + radius)

    -- Generate continuous collision detection ray
    table.insert(rays, { start = position, endPos = endPos })

    -- Generate corner-to-opposite-corner rays
    table.insert(rays, { 
        start = position + rotation:apply(util.vector3(-halfSize.x, -halfSize.y, -halfSize.z)), 
        endPos = position + rotation:apply(util.vector3(halfSize.x, halfSize.y, halfSize.z)) 
    })
    table.insert(rays, { 
        start = position + rotation:apply(util.vector3(halfSize.x, -halfSize.y, -halfSize.z)), 
        endPos = position + rotation:apply(util.vector3(-halfSize.x, halfSize.y, halfSize.z)) 
    })
    table.insert(rays, { 
        start = position + rotation:apply(util.vector3(-halfSize.x, halfSize.y, -halfSize.z)), 
        endPos = position + rotation:apply(util.vector3(halfSize.x, -halfSize.y, halfSize.z)) 
    })
    table.insert(rays, { 
        start = position + rotation:apply(util.vector3(halfSize.x, halfSize.y, -halfSize.z)), 
        endPos = position + rotation:apply(util.vector3(-halfSize.x, -halfSize.y, halfSize.z)) 
    })

    -- Generate face-center rays
    --[[ table.insert(rays, { 
        start = position + rotation:apply(util.vector3(0, 0, -halfSize.z)), 
        endPos = position + rotation:apply(util.vector3(0, 0, halfSize.z)) 
    })
    table.insert(rays, { 
        start = position + rotation:apply(util.vector3(0, -halfSize.y, 0)), 
        endPos = position + rotation:apply(util.vector3(0, halfSize.y, 0)) 
    })
    table.insert(rays, { 
        start = position + rotation:apply(util.vector3(-halfSize.x, 0, 0)), 
        endPos = position + rotation:apply(util.vector3(halfSize.x, 0, 0)) 
    }) ]]

    -- Perform raycasts and find the closest collision
    local closestHit = nil    
    for _, ray in ipairs(rays) do
        local engHitResult = nearby.castRay(ray.start, ray.endPos, castOpts)
        local hitResult = {
            hit = engHitResult.hit,
            hitPos = engHitResult.hitPos,
            hitNormal = engHitResult.hitNormal,
            hitObject = engHitResult.hitObject,
        }
        --gutils.shallowTableCopy(hitResult, engHitResult)	
        if hitResult.hit then
            hitResult.distance = (hitResult.hitPos - ray.start):length()
            local originToCollision = hitResult.hitPos - position
            local rayStartToCollision = hitResult.hitPos - ray.start
            if originToCollision:dot(rayStartToCollision) < 0 then
                hitResult.hitNormal = -hitResult.hitNormal -- Flip normal if necessary
            end
            
            if not closestHit or hitResult.distance < closestHit.distance then
                closestHit = hitResult                
            end
        end
    end

    return closestHit
end
module.customRaycastAABB = customRaycastAABB



return module



