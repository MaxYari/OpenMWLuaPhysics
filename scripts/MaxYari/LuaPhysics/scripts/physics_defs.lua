local prefix = "LuaPhysics_"

return {
    GUtoM = 69.99,
    e = {
        UpdateVisPos = prefix.."UpdateVisPos",
        RemoveObject = prefix .. "RemoveObject",
        SpawnCollilsionEffects = prefix.."SpawnCollilsionEffects",
        SpawnMaterialEffect = prefix.."SpawnMaterialEffect",
        PlayCollisionSounds = prefix.."PlayCollisionSounds",
        PlayCrashSound = prefix.."PlayCrashSound",
        PlaySound = prefix.."PlaySound",
        PlayWaterSplashSound = prefix.."PlayWaterSplashSound",
        WhatIsMyPhysicsData = prefix.."WhatIsMyPhysicsData",
        FractureMe = prefix.."FractureMe",
        HeldBy = prefix.."HeldBy",
        MoveTo = prefix.."MoveTo",
        ApplyImpulse = prefix.."ApplyImpulse",
        SetPhysicsProperties = prefix.."SetPhysicsProperties",
        PhysPropUpdReport = prefix.."PhysPropUpdReport",
        InactivationReport = prefix.."InactivationReport",
        SetMaterial = prefix.."SetMaterial",
        SetPositionUnadjusted = prefix.."SetPositionUnadjusted",
        CollidingWithPhysObj = prefix.."CollidingWithPhysObj",
        DestructibleHit = prefix.."DestructibleHit",
        ObjectFenagled = prefix .. "ObjectFenagled",
        DetectCulprit = prefix .. "DetectCulprit",
        DetectCulpritResult = prefix .. "DetectCulpritResult",
        UpdatePersistentData = prefix .. "UpdateObjectPersistentData",
        PersistentDataReport = prefix .. "PersistentDataReport"
    }
}