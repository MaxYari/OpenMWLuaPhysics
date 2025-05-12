-- OpenMW Lua Physics - Authors: Maksim Eremenko, GPT-4o (Copilot)

local mp = 'scripts/MaxYari/LuaPhysics/'

local core = require('openmw.core')
local util = require('openmw.util')

local nstatus, nearby = pcall(require, "openmw.nearby")
local sstatus, omwself = pcall(require, "openmw.self")

local phUtils = require(mp..'scripts/physics_utils')
local gutils = require(mp..'scripts/gutils')
local EventsManager = require(mp..'scripts/events_manager')
local D = require(mp..'scripts/physics_defs')


local Gravity = util.vector3(0, 0, -9.8*D.GUtoM)
local SleepSpeed = 7
local SleepTime = 1
local ImpactAngVelDamping = 0.5 -- Multiplier for angular velocity impact
local ImpactAngVelMult = 6
local MaxAngularVelocity = 5000 -- Optional: Maximum angular velocity limit
local WaterHitVelDamping = 0.5

--if omwself.recordId ~= "food_kwama_egg_02" then return end


-- PhysicsObject class -----------------------------------------------------
----------------------------------------------------------------------------
local PhysicsObject = {}

function PhysicsObject:new(object, properties)
    local inst = {}
    setmetatable(inst, self)
    self.__index = self

    --print("Creating a physics object for: ", object)

    inst:init(object, properties)

    return inst
end

function PhysicsObject:init(object, properties)
    local box = object:getBoundingBox()
    
    local radius = 10
    local largestHalfExtent = radius    
    if properties.radius then
        radius = properties.radius        
    elseif object then
        radius = math.min(box.halfSize.x, box.halfSize.y, box.halfSize.z)
        largestHalfExtent = math.max(box.halfSize.x, box.halfSize.y, box.halfSize.z)
        if radius < 2 then radius = 2 end
        if largestHalfExtent < 2 then largestHalfExtent = 2 end
    end
    
    local origin = util.vector3(0, 0, 0)
    if properties.origin then
        origin = properties.origin
    elseif object then
        origin = object.rotation:inverse():apply(box.center-object.position)
    end    

    local position = nil
    local initialPosition = nil
    if properties.position then
        position = properties.position
    elseif object then
        position = object.position + object.rotation:apply(origin)
        initialPosition = position
    end    

    local rotation = util.transform.identity
    local initialRotation = nil
    if properties.rotation then
        rotation = properties.rotation
    elseif object then
        rotation = object.rotation
        initialRotation = rotation
    end   
    
    self.object = object
    self.position = position
    self.initialPosition = initialPosition
    self.initialRotation = initialRotation
    self.rotation = rotation
    self.origin = origin
    self.velocity = util.vector3(0, 0, 0)
    self.angularVelocity = util.vector3(0, 0, 0) -- Add angular velocity
    self.lockRotation = properties.lockRotation or false
    self.realignWhenRested = properties.realignWhenRested or false
    self.ignoreWorldCollisions = false
    self.ignorePhysObjectCollisions = false
    self.radius = radius
    self.largestHalfExtent = largestHalfExtent    
    self.drag = properties.drag or 0.33
    self.angularDrag = properties.angularDrag or 0.1 
    self.bounce = properties.bounce or 0.5    
    self.isSleeping = properties.isSleeping or false
    self.sleepTimer = 0
    self.gravity = Gravity
    self.resetOnLoad = false
    self.collisionMode = properties.collisionMode or "sphere" -- "sphere" or "aabb". "aabb" is experimental, works decent with lockRotation, only aabb can work on objects that have their own collider.
    self.isUnderwater = false
    
    self.cellBounds = nil -- Will be received later from global
    self.player = nil -- Will be received later from global

    -- Events
    self.onCollision = properties.onCollision or EventsManager:new()
    self.onPhysObjectCollision = properties.onPhysObjectCollision or EventsManager:new()
    self.onIntersection = properties.onIntersection or EventsManager:new()
    self.onMaterialUpdate = properties.onMaterialUpdate or EventsManager:new()

    self:updateMaterial(properties.material or nil) -- Will be received later from global
    -- updateMaterial calculates mass and buoyancy, reset them to ones provided to constructor, if necessary
    if properties.mass then self.mass = properties.mass end 
    if properties.buoyancy then self.buoyancy = properties.buoyancy end	

    self.initialized = true

    -- This will make global send back an event with material, cellBounds and player
    core.sendGlobalEvent(D.e.WhatIsMyPhysicsData, {
        object = object
    })

    local serialisedData = self:serialize()
    serialisedData.initialized = self.initialized
    core.sendGlobalEvent(D.e.PhysPropUpdReport, serialisedData)
end

function PhysicsObject:updateMaterial(mat, recalcMass, recalcBuoyancy)
    if recalcMass == nil then recalcMass = true end
    if recalcBuoyancy == nil then recalcBuoyancy = true end
    
    -- print(omwself,"phys obj update material")

    self.material = mat
    
    -- Volume-based mass
    if recalcMass then
        local box = self.object:getBoundingBox()
        local volume = (box.halfSize.x/D.GUtoM) * (box.halfSize.y/D.GUtoM) * (box.halfSize.z/D.GUtoM) --In meters^3
        local density = 25 -- In kg/m^3 -- Density is so low since bbox-based volume is very innacurate
        if self.material and self.material == "Metal" then density = 50 end
        local mass = volume * density -- In kg
        if mass < 1 then mass = 1 end
        self.mass = mass
    end

    -- Material-based boyancy
    if recalcBuoyancy then
        self.buoyancy = 0.5
        if self.material == "Wood" or self.material == "Glass" or self.material == "Organic" then
            self.buoyancy = 1.05
        elseif self.material == "Metal" then
            self.buoyancy = 0.25
        end
    end

    -- print("emitting mat upd event")
    self.onMaterialUpdate:emit(self.material)
end


function PhysicsObject:reInit()
    --print("Reinitialising a physics object for: ", self.object)
    self.position = nil
    self.rotation = nil
    self.origin = nil
    self.radius = nil
    self:init(self.object, self)
end

function PhysicsObject:updateProperties(props)
    gutils.shallowMergeTables(self, props)
    core.sendGlobalEvent(D.e.PhysPropUpdReport, self:serialize())
end


function PhysicsObject:serialize()
    return {
        object = self.object,
        position = self.position,
        velocity = self.velocity,
        radius = self.radius,
        origin = self.origin,
        rotation = self.rotation,
        isSleeping = self.isSleeping,
        bounce = self.bounce,
        mass = self.mass,
        culprit = self.culprit,
        ignorePhysObjectCollisions = self.ignorePhysObjectCollisions
    }
end

function PhysicsObject:serializeMotionData()
    return {
        object = self.object,
        position = self.position,
        velocity = self.velocity,        
        rotation = self.rotation
    }
end

function PhysicsObject:resetPosition(sleep)
    if sleep == nil then sleep = true end
    if self.initialPosition then self.position = self.initialPosition end
    if self.initialRotation then self.rotation = self.initialRotation end
    if sleep then self:sleep() end
end

function PhysicsObject:getPersistentData()
    return {
        initialPosition = self.initialPosition,
        initialRotation = self.initialRotation,
        resetOnLoad = self.resetOnLoad,
        ignorePhysObjectCollisions = self.ignorePhysObjectCollisions
    }
end

function PhysicsObject:loadPersistentData(data)
    self:updateProperties(data)
    if self.resetOnLoad then self:resetPosition(false) end
end

function PhysicsObject:setPositionUnadjusted(position)
    self.position = position + self.rotation:apply(self.origin)
end

function PhysicsObject:sleep()
    self.isSleeping = true   
    self:setCulprit(nil)
    core.sendGlobalEvent(D.e.PhysPropUpdReport, {object = self.object, isSleeping = self.isSleeping})
end

function PhysicsObject:wakeUp()
    self.isSleeping = false    
    self.sleepTimer = 0 -- Reset sleep timer when waking up
    core.sendGlobalEvent(D.e.PhysPropUpdReport, {object = self.object, isSleeping = self.isSleeping})
end

function PhysicsObject:setCulprit(culprit)
    self.culprit = culprit
    core.sendGlobalEvent(D.e.PhysPropUpdReport, {object = self.object, culprit = self.culprit})
end

function PhysicsObject:applyImpulse(impulse, culprit) 
    -- print(self.mass)
    self.velocity = self.velocity + impulse / self.mass
    self:setCulprit(culprit)
    self:wakeUp() -- Wake up the object when an impulse is applied
end

function PhysicsObject:applyForce(force, culprit, wakeUp)
    if wakeUp == nil then wakeUp = true end
    if not wakeUp and self.isSleeping then return end
    if not self.forceToApply then
        self.forceToApply = util.vector3(0, 0, 0)
    end
    self.forceToApply = self.forceToApply + force
    self:setCulprit(culprit)
    if wakeUp then self:wakeUp() end -- Wake up the object when a force is applied
end

function PhysicsObject:isCollidingWith(physObject)
    local distance = (self.position - physObject.position):length()
    return distance < (self.radius + physObject.radius)
end

function PhysicsObject:handleCollision(hitResult)
    local normal = hitResult.hitNormal
    local velocity = self.velocity
    local dot = velocity:dot(normal)    
    
    local newInContact = true
    local newInContactWith = hitResult.hitObject
    local isNewContact = newInContact ~= self.inContact or newInContactWith ~= self.inContactWith
    
    self.inContact = newInContact
    self.inContactWith = newInContactWith

    if dot < 0 then
        -- Run collision callback
        if isNewContact then 
            self.onCollision:emit(hitResult) 
            if hitResult.hitObject then 
                hitResult.hitObject:sendEvent(D.e.CollidingWithPhysObj, {other = self:serialize()})
            end
        end    

        -- Reflect velocity and apply bounce factor
        self.velocity = -(normal * normal:dot(velocity) * 2 - velocity)
        self.velocity = self.velocity * self.bounce

        -- Apply impact torque damping
        self.angularVelocity = self.angularVelocity * ImpactAngVelDamping

        if not self.lockRotation then
            -- Calculate torque from collision impact
            local impactPoint = hitResult.hitPos        
            local relativePosition = impactPoint - self.position
            local torque = relativePosition:cross(-self.velocity)
            local tangVelocity = torque
            local angularVeloctiy = tangVelocity/self.largestHalfExtent
            
            -- 6 (ImpactAngVelDamping) is a magic number that makes collistion look fun, essentially its (probably) related to moment of inertia which is not accounted for at all
            self.angularVelocity = self.angularVelocity + angularVeloctiy * ImpactAngVelMult

            -- Clamp angular velocity to prevent it from growing uncontrollably
            if self.angularVelocity:length() > MaxAngularVelocity then
                self.angularVelocity = self.angularVelocity:normalize() * MaxAngularVelocity
            end
        end

        return true
    else
        -- Run intersection callback
        if isNewContact then self.onIntersection:emit(hitResult) end
        return false
    end
end

function PhysicsObject:handlePhysObjectCollision(physObject)
    if physObject.culprit then self.culprit = physObject.culprit end

    local normal = (self.position - physObject.position):normalize()
    --print(normal, physObject.radius)
    local hitPos = physObject.position + normal*physObject.radius

    local relativeVelocity = self.velocity - physObject.velocity
    local dot = relativeVelocity:dot(normal)
    
    if dot < 0 and math.abs(dot) > SleepSpeed then
        -- print("Handling object collision", object1, object2, dot)
        -- Calculate impulse magnitude
        local impulseMagnitude = -(1 + math.min(self.bounce, physObject.bounce)) * dot / (1 / self.mass + 1 / physObject.mass)

        -- Apply impulses to both objects
        local impulse = normal * impulseMagnitude
        self.velocity = self.velocity + impulse / self.mass
        --physObject.velocity = physObject.velocity - impulse / physObject.mass

        self:wakeUp()
        self.onPhysObjectCollision:emit({
            hitPos = hitPos,
            hitNormal = normal,
            hitObject = physObject.object,
            hitPhysObject = physObject
        })

        --data2:wakeUp()
    end
end


local maxDt = 1/20
function PhysicsObject:update(dt)
    if self.disabled then return end

    if dt > maxDt then dt = maxDt end    

    if not self.isSleeping then
        -- Consume accumulated forces
        if self.forceToApply and self.forceToApply:length() > 0 then
            self.velocity = self.velocity + (self.forceToApply / self.mass) * dt
            self.forceToApply = util.vector3(0, 0, 0) -- Reset accumulated forces after applying
        end

        -- Apply Gravity
        self.velocity = self.velocity + Gravity * dt

        -- Water Physics
        local waterline = self.object.cell.waterLevel
        if waterline and not PhysicsObject.isSleeping then
            if self.position.z < waterline then
                -- We are underwater
                if not self.isUnderwater then
                    -- We just transitioned from above water to underwater
                    self.velocity = self.velocity * WaterHitVelDamping
                end
                self.isUnderwater = true
                
                -- Apply Buoyoncy
                local buoyForce = Gravity * self.mass * -1 * self.buoyancy
                self.velocity = self.velocity + buoyForce * dt
            else
                self.isUnderwater = false
            end
        end

        -- Apply drag
        self.velocity = self.velocity * (1 - self.drag * dt)

        -- Calculate displacement
        local displacement = self.velocity * dt

        -- Perform collision detection
        local collided = false
        local hitResult = nil
        local rayStart = self.position
        local rayEnd = rayStart + displacement

        if not self.ignoreWorldCollisions then
            if self.collisionMode == "sphere" then
                hitResult = nearby.castRay(rayStart, rayEnd, { radius = self.radius })
            elseif self.collisionMode == "aabb" then
                hitResult = phUtils.customRaycastAABB(rayStart, rayEnd, self.radius, self.object:getBoundingBox(), self.rotation, { ignore = self.object })
            end

            if hitResult and hitResult.hit then
                collided = self:handleCollision(hitResult)
                if self.collisionMode == "sphere" then
                    -- Update position on collision to get close to a surface without penetrating
                    if collided then self.position = phUtils.calcSpherePosAtHit(self.position, displacement, hitResult.hitPos, self.radius) end
                elseif self.collisionMode == "aabb" then
                    -- Dont update position on collision, to ensure no penetration
                end
            end
        end

        if not collided then
            self.inContact = false
            self.inContactWith = nil
            self.position = rayEnd
        end

        if not self.lastPosition then self.lastPosition = self.position end
        self.actualVelocity = (self.position - self.lastPosition) / dt

        -- Apply angular drag to angular velocity
        self.angularVelocity = self.angularVelocity * (1 - self.angularDrag * dt)
        if self.lockRotation then self.angularVelocity = self.angularVelocity * 0 end -- Lock rotation if specified
        
        -- Update rotation based on angular velocity
        local angularDisplacement = self.angularVelocity * dt * 0.01
        local rotationDelta = util.transform.rotate(angularDisplacement:length(), angularDisplacement:normalize())
        self.rotation = rotationDelta * self.rotation

        -- Realign when close to rest state
        if self.realignWhenRested then
            -- FIX ME; rest is now based on speed, not angular speed, so realignment will probably not work as intended
            if not self.rotationInfluence then self.rotationInfluence = 0 end
            local speed = self.actualVelocity:length()
            if speed < SleepSpeed then
                self.rotationInfluence = self.sleepTimer / SleepTime
                if self.rotationInfluence > 0 then
                    self.rotation = phUtils.slerpRotation(self.rotation, util.transform.identity, self.rotationInfluence)
                end
            else
                self.rotationInfluence = 0
            end
        end
    end

    if not self.isSleeping then
        -- print("Not sleeping",omwself)
        core.sendGlobalEvent(D.e.UpdateVisPos, self:serializeMotionData())
    end
    
    
end

function PhysicsObject:trySleep(dt)    
    if self.isSleeping or not self.actualVelocity then return end

    local speed = self.actualVelocity:length()
    if speed < SleepSpeed then        
        self.sleepTimer = self.sleepTimer + dt
        if self.sleepTimer >= SleepTime then
            self:sleep()
        end
    else
        self.sleepTimer = 0 -- Reset sleep timer if velocity or angular velocity exceeds threshold
    end

    self.lastPosition = self.position
end

return PhysicsObject







