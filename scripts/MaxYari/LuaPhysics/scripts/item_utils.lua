--Author: gnouc, 2024
--local g_itemUtils = require("scripts.gnouncUtils.item_util")

local core = require('openmw.core')
local types = require('openmw.types')

--methods in this link were included here, but not written by me.
--https://gitlab.com/OpenMW/openmw/-/blob/b33f5ead5ad486e4eff1af9c6ef28b905888105e/files/data/openmw_aux/item.lua

local armorWeightEpsilon = 0.0005;
local lightMultiplier = core.getGMST("fLightMaxMod") + armorWeightEpsilon
local medMultiplier = core.getGMST("fMedMaxMod") + armorWeightEpsilon

local armorType = types.Armor.TYPE
local weaponType = types.Weapon.TYPE
local SKILL = core.stats.Skill.records

local goldIds = { gold_001 = true, gold_005 = true, gold_010 = true, gold_025 = true, gold_100 = true }


local armorGMSTs = {
	[armorType.Boots] = "iBootsWeight",
	[armorType.Cuirass] = "iCuirassWeight",
	[armorType.Greaves] = "iGreavesWeight",
	[armorType.Shield] = "iShieldWeight",
	[armorType.LBracer] = "iGauntletWeight",
	[armorType.RBracer] = "iGauntletWeight",
	[armorType.RPauldron] = "iPauldronWeight",
	[armorType.LPauldron] = "iPauldronWeight",
	[armorType.Helmet] = "iHelmWeight",
	[armorType.LGauntlet] = "iGauntletWeight",
	[armorType.RGauntlet] = "iGauntletWeight",
}

local weaponTypeNames = {
	[weaponType.Arrow] = "Arrow",
	[weaponType.AxeOneHand] = "AxeOneHand",
	[weaponType.AxeTwoHand] = "AxeTwoHand",
	[weaponType.BluntOneHand] = "BluntOneHand",
	[weaponType.BluntTwoClose] = "BluntTwoClose",
	[weaponType.BluntTwoWide] = "BluntTwoWide",
	[weaponType.Bolt] = "Bolt",
	[weaponType.LongBladeOneHand] = "LongBladeOneHand",
	[weaponType.LongBladeTwoHand] = "LongBladeTwoHand",
	[weaponType.MarksmanBow] = "MarksmanBow",
	[weaponType.MarksmanCrossbow] = "MarksmanCrossbow",
	[weaponType.MarksmanThrown] = "MarksmanThrown",
	[weaponType.ShortBladeOneHand] = "ShortBladeOneHand",
	[weaponType.SpearTwoWide] = "SpearTwoWide",
}

local weaponSound = {
	[weaponType.BluntOneHand] = "Weapon Blunt",
	[weaponType.BluntTwoClose] = "Weapon Blunt",
	[weaponType.BluntTwoWide] = "Weapon Blunt",
	[weaponType.MarksmanThrown] = "Weapon Blunt",
	[weaponType.Arrow] = "Ammo",
	[weaponType.Bolt] = "Ammo",
	[weaponType.SpearTwoWide] = "Weapon Spear",
	[weaponType.MarksmanBow] = "Weapon Bow",
	[weaponType.MarksmanCrossbow] = "Weapon Crossbow",
	[weaponType.AxeOneHand] = "Weapon Blunt",
	[weaponType.AxeTwoHand] = "Weapon Blunt",
	[weaponType.ShortBladeOneHand] = "Weapon Shortblade",
	[weaponType.LongBladeOneHand] = "Weapon Longblade",
	[weaponType.LongBladeTwoHand] = "Weapon Longblade",
}

local weaponEquipmentSkills = {
	[weaponType.Arrow] = SKILL.marksman,
	[weaponType.AxeOneHand] = SKILL.axe,
	[weaponType.AxeTwoHand] = SKILL.axe,
	[weaponType.BluntOneHand] = SKILL.bluntweapon,
	[weaponType.BluntTwoClose] = SKILL.bluntweapon,
	[weaponType.BluntTwoWide] = SKILL.bluntweapon,
	[weaponType.Bolt] = SKILL.marksman,
	[weaponType.LongBladeOneHand] = SKILL.longblade,
	[weaponType.LongBladeTwoHand] = SKILL.longblade,
	[weaponType.MarksmanBow] = SKILL.marksman,
	[weaponType.MarksmanCrossbow] = SKILL.marksman,
	[weaponType.MarksmanThrown] = SKILL.marksman,
	[weaponType.ShortBladeOneHand] = SKILL.shortblade,
	[weaponType.SpearTwoWide] = SKILL.spear
}


local function getWeaponType(weapon)
	return types.Weapon.record(weapon).type
end

local function getWeaponTypeName(weapon)
	return weaponTypeNames[getWeaponType(weapon)]
end

--use this to get armor class
local function getArmorSkill(armor)
	if armor.type ~= types.Armor and not armor.baseArmor then error("Not Armor") end

	local record = nil
	if armor.baseArmor then --A record was supplied, not a gameObject
		record = armor
	else
		record = types.Armor.record(armor)
	end

	local armorType = record.type
	local weight = record.weight
	local armorTypeWeight = math.floor(core.getGMST(armorGMSTs[armorType]))

	if weight <= armorTypeWeight * lightMultiplier then
		return SKILL.lightarmor
	elseif weight <= armorTypeWeight * medMultiplier then
		return SKILL.mediumarmor
	else
		return SKILL.heavyarmor
	end
end


local function getItemSoundId(object, suffix)
	local rec = object.type.record(object)
	local soundId = tostring(type) -- .. " Up"

	if object.type.baseType ~= types.Item or not object then error("Invalid object supplied") end

	if object.type == types.Armor then
		soundId = "Armor " .. string.gsub(getArmorSkill(object).name, " Armor", "")
	elseif object.type == types.Clothing then
		soundId = "Clothes"
		if rec.type == types.Clothing.TYPE.Ring then
			soundId = "Ring"
		end
	elseif object.type == types.Light or object.type == types.Miscellaneous then
		if goldIds[object.recordId] then
			soundId = "Gold"
		else
			soundId = "Misc"
		end
	elseif object.type == types.Weapon then
		soundId = weaponSound[rec.type]
	end

	return string.format("Item %s %s", soundId, suffix)
end

local function getDropSound(item)
	return getItemSoundId(item, "Down")
end

local function getPickupSound(item)
	return getItemSoundId(item, "Up")
end


local function getSkillTypeForEquipment(equipment)
	local rec = equipment.type.record(equipment)

	if equipment.type == types.Armor then
		if rec.type == types.Armor.armorTYPE.Shield then
			return SKILL.block
		else
			return getArmorSkill(equipment)
		end
	elseif equipment.type == types.Weapon then
		return weaponEquipmentSkills[rec.type]
	elseif equipment.type == types.Repair then
		return SKILL.armorer
	elseif equipment.type == types.Lockpick then
		return SKILL.security
	elseif equipment.type == types.Probe then
		return SKILL.security
	end

	return nil
end


local function getSkillStatForSkill(actor, skill)
	return types.NPC.stats.skills[skill.id](actor)
end


local function getSkillStatForEquipment(actor, equipment)
	return getSkillStatForSkill(actor, getSkillTypeForEquipment(equipment))
end



return {
	goldIds = goldIds,
	armorGMSTs = armorGMSTs,
	getArmorSkill = getArmorSkill,
	getDropSound = getDropSound,
	getWeaponType = getWeaponType,
	getItemSoundId = getItemSoundId,
	getPickupSound = getPickupSound,
	getWeaponTypeName = getWeaponTypeName,
	getSkillStatForSkill = getSkillStatForSkill,
	weaponEquipmentSkills = weaponEquipmentSkills,
	getSkillStatForEquipment = getSkillStatForEquipment,
	getSkillTypeForEquipment = getSkillTypeForEquipment,
}
