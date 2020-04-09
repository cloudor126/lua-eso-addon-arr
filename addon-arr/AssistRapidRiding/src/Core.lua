--========================================
--        vars
--========================================
local addon = AssistRapidRiding -- Addon#M
local settings = addon.load("Settings#M") -- Settings#M
local m = {} -- #M
local l = {} -- #L

---
--@type SlotedSkill
--@field #number weaponPair
--@field #number slotNum
--@field #SkillInfo info

---
--@type SkillInfo
--@field #number skillType
--@field #number skillLine
--@field #number abilityIndex
--@field #number abilityId
--@field #string abilityName
--@field #number progressionIndex

---
--@type CoreSavedVars
local coreSavedVarsDefaults = {
  switchAtAbilitySlot = 5,
  autoSwitchWhenMounted = true,
  autoSwitchOnlyInNonPvpZones = false,
  alwaysSwitchWhenMounted = false,
  switchBackWhenMounted = true,-- this option ignore mounting status since murkmire
  autoSwitchAgainBeforeEffectFades = true,
  secondsLeftToSwitchAgain = 1,
  soundEnabled = false,
  soundIndex = 28,
  oldSlotedSkill = nil--#SlotedSkill
}

--========================================
--        l
--========================================
l.token = 0 --#number
l.waitRecover = false --#boolean
l.rmSkillInfo = nil --#SkillInfo
l.coverTime = 0 --#number
l.progressionIndexToSkillInfo = {} --#map<#number,#SkillInfo>

l.debug -- #(#number:level)->(#(#string:format, #string:...)->())
=function(level)
  return function(format, ...)
    if m.debugLevel>=level then
      d(string.format(format, ...))
    end
  end
end

l.getSavedVars -- #()->(#CoreSavedVars)
= function()
  return settings.getSavedVars()
end

l.getCharacterSavedVars -- #()->(#CoreSavedVars)
= function()
  return settings.getCharacterSavedVars()
end

l.getDuration -- #(#number:abilityId)->(#number)
= function(abilityId)
  local duration = GetAbilityDuration(abilityId)
  -- longer duration in description
  local description = GetAbilityDescription(abilityId)
  local init = 1
  local s = 0
  local e = 0
  while true do
    s,e = description:find("[0-9]+",init,false)
    if s and s> 0 and tonumber(description:sub(s,e)) then
      init = e+1
      local percentLoc = description:find("%%",e,false)
      if not percentLoc or percentLoc > e+5 then
        local num = tonumber(description:sub(s,e)) * 1000
        duration = math.max(duration,num)
      end
    else
      break
    end
  end
  return duration
end

l.loadSkillInfo -- #()->()
= function()
  if not IsPlayerActivated() then return end
  l.rmSkillInfo = nil
  l.progressionIndexToSkillInfo = {}
  for skillType = 1, GetNumSkillTypes() do
    for skillLine = 1, GetNumSkillLines(skillType) do
      for abilityIndex = 1, math.min(7, GetNumAbilities(skillType, skillLine)) do
        local abilityId = GetSkillAbilityId(skillType, skillLine, abilityIndex, false)
        local abilityName,texture,earnedRank,passive,ultimate,purchased,progressionIndex,rankIndex =
          GetSkillAbilityInfo(skillType, skillLine, abilityIndex)
        local info = {
          skillType = skillType,
          skillLine = skillLine,
          abilityIndex = abilityIndex,
          abilityId = abilityId,
          abilityName = abilityName,
          progressionIndex = progressionIndex,
        }--#SkillInfo
        if string.find(texture,'ability_ava_002',1,true) then
          l.rmSkillInfo = info
        elseif progressionIndex then
          l.progressionIndexToSkillInfo[progressionIndex] = info
        end
      end
    end
  end
end

l.onActionSlotAbilityUsed -- #(#number:eventCode,#number:slotNum, #boolean:force)->()
= function(eventCode,slotNum, force)
  if not l.getSavedVars().switchBackWhenMounted then return end

  local oss = l.getCharacterSavedVars().oldSlotedSkill
  if not oss then return end
  if oss.slotNum ~= slotNum then return end
  local weaponPair,locked = GetActiveWeaponPairInfo()
  if oss.weaponPair ~= weaponPair then return end


  l.debug(1)("arr-core:l.onActionSlotAbilityUsed %i:%s",slotNum,GetSlotName(slotNum))
  local abilityId = GetSlotBoundId(slotNum)
  local hasProgression,progressionIndex,lastRankXp,nextRankXP,currentXP,atMorph = GetAbilityProgressionXPInfoFromAbilityId(abilityId)
  if progressionIndex == l.rmSkillInfo.progressionIndex then
    l.coverTime = GetGameTimeMilliseconds() + l.getDuration(abilityId)
    if l.getSavedVars().autoSwitchAgainBeforeEffectFades then
      l.coverTime = l.coverTime - l.getSavedVars().secondsLeftToSwitchAgain*1000
    end
    -- recover
    l.debug(1)('arr-core: call later to recover')
    zo_callLater(
      function()
        l.recover()
        if l.getSavedVars().autoSwitchOnlyInNonPvpZones and IsPlayerInAvAWorld() then return end
        if l.getSavedVars().autoSwitchAgainBeforeEffectFades then
          l.token = l.token +1
          l.switch(l.token)
        end
      end,
      500
    )
    return
  end
end

l.onActiveWeaponPairChanged -- #(#number:eventCode,#ActiveWeaponPair:activeWeaponPair,#boolean:locked)->()
= function(eventCode,activeWeaponPair,locked)
  if l.waitRecover and l.getCharacterSavedVars().oldSlotedSkill then
    zo_callLater(l.recover, 300)
  end
end

l.onMountedStateChanged -- #(#number:eventCode,#boolean:mounted)->()
= function(eventCode, mounted)
  if not l.getSavedVars().autoSwitchWhenMounted then return end
  if l.getSavedVars().autoSwitchOnlyInNonPvpZones and IsPlayerInAvAWorld() then return end
  if not mounted then
    if l.getCharacterSavedVars().oldSlotedSkill ~= nil then
      l.recover()
    end
    return
  end
  if l.getSavedVars().alwaysSwitchWhenMounted then l.coverTime = 0 end
  l.switch(l.token, IsMounted()~=mounted)
end

l.onPlayerActivated -- #(#number:eventCode,#boolean:initial)->()
= function(eventCode,initial)
  l.loadSkillInfo()
  if not IsMounted() then
    l.recover()
  end
end

l.onSkillPointsChanged -- #(#number:eventCode,#integer:pointsBefore,#integer:pointsNow,#integer:partialPointsBefore,#integer:partialPointsNow,#SkillPointReason:skillPointChangeReason)->()
= function(eventCode,pointsBefore,pointsNow,partialPointsBefore,partialPointsNow,skillPointChangeReason)
  l.loadSkillInfo()
end

l.onStart -- #()->()
= function()

  l.loadSkillInfo()

  EVENT_MANAGER:RegisterForEvent(addon.name, EVENT_MOUNTED_STATE_CHANGED, l.onMountedStateChanged)
  EVENT_MANAGER:RegisterForEvent(addon.name, EVENT_ACTION_SLOT_ABILITY_USED, l.onActionSlotAbilityUsed)
  EVENT_MANAGER:RegisterForEvent(addon.name, EVENT_ACTIVE_WEAPON_PAIR_CHANGED, l.onActiveWeaponPairChanged)
  EVENT_MANAGER:RegisterForEvent(addon.name, EVENT_PLAYER_ACTIVATED, l.onPlayerActivated)
  EVENT_MANAGER:RegisterForEvent(addon.name, EVENT_SKILL_POINTS_CHANGED, l.onSkillPointsChanged )
end

l.recover -- #()->()
= function()
  l.debug(1)('recover called')
  local oss = l.getCharacterSavedVars().oldSlotedSkill
  if oss ~= nil then
    if IsUnitInCombat('player') then
      zo_callLater(l.recover, 1000)
      return
    end
    local weaponPair,locked = GetActiveWeaponPairInfo()
    if weaponPair ~= oss.weaponPair then
      l.waitRecover = true -- try again when player switch weapon pair
      return
    end
    l.waitRecover = false -- clean flag
    local info = oss.info;
    l.debug(1)('arr-core:l.recover %s,%s,%s abilityId:%i', info.skillType,info.skillLine,info.abilityIndex, (info.abilityId or 'not saved'))
    SlotSkillAbilityInSlot(info.skillType, info.skillLine, info.abilityIndex, oss.slotNum)
    l.getCharacterSavedVars().oldSlotedSkill = nil
  end
end

l.saveOldSlotedSkill -- #(#number:slotNum)->()
= function(slotNum)
  local abilityId = GetSlotBoundId(slotNum)
  if l.rmSkillInfo.abilityId == abilityId then return end
  if GetSkillAbilityId(l.rmSkillInfo.skillType,l.rmSkillInfo.skillLine,l.rmSkillInfo.abilityIndex,false)==abilityId then
    l.rmSkillInfo.abilityId = abilityId -- auto patch
    return
  end
  local _,progressionIndex = GetAbilityProgressionXPInfoFromAbilityId(abilityId)
  local info = l.progressionIndexToSkillInfo[progressionIndex]
  if not info then
    d('ARR can not find info for ability id:'..abilityId)
    return
  end
  local weaponPair,locked = GetActiveWeaponPairInfo()
  l.debug(1)('arr-core:l.saveOldSlotedSkill(%i)(%i,%i,%i) abilityId:%i',slotNum,info.skillType,
    info.skillLine,info.abilityIndex,info.abilityId)
  l.getCharacterSavedVars().oldSlotedSkill = {
    slotNum = slotNum,
    weaponPair = weaponPair,
    info = info,
  }
end

l.soundChoices = {} -- #list<#number>
for k,v in pairs(SOUNDS) do
  table.insert(l.soundChoices, k)
end
table.sort(l.soundChoices)

l.switch -- #(#number:token, #boolean:force)->()
= function(token, force)
  l.debug(1)('arr-core:l.switch token=%i,force=%s,l.token=%i,%s',token,force and 'true' or 'false',
    l.token, IsMounted() and 'mounted' or 'not mounted')
  local now = GetGameTimeMilliseconds()
  -- check
  if not l.rmSkillInfo then
    l.debug(1)('arr-core:l.switch no rmSkillInfo, try again.')
    l.loadSkillInfo()
    if not l.rmSkillInfo then
      l.debug(1)('arr-core:l.switch still no rmSkillInfo!!!')
      return
    end
  end
  if token ~= l.token then return end
  if not force and not IsMounted() then return end
  if not force and l.coverTime and l.coverTime > now then
    l.debug(2)('arr-core:l.switch l.coverTime>now')
    zo_callLater(function() l.switch(token) end, l.coverTime-now)
    return
  end
  if IsUnitInCombat('player') then
    l.debug(2)('arr-core:l.switch inCombat')
    zo_callLater(function() l.switch(token) end, 1000)
    return
  end

  --  save old info
  l.debug(2)('arr-core:l.switch saving oss')
  local slotNum = l.getSavedVars().switchAtAbilitySlot + 2
  if l.rmSkillInfo.abilityId == GetSlotBoundId(slotNum) then return end
  l.saveOldSlotedSkill(slotNum)
  l.debug(2)('arr-core:l.switch oss saved')

  -- switch ability
  l.waitRecover = false
  if l.getSavedVars().soundEnabled then PlaySound(SOUNDS[l.soundChoices[l.getSavedVars().soundIndex]]) end
  SlotSkillAbilityInSlot(l.rmSkillInfo.skillType, l.rmSkillInfo.skillLine, l.rmSkillInfo.abilityIndex, slotNum)
  if AddonForCloudor then
    local commander = AddonForCloudor.load('Commander#M')
    if commander then commander.send({'s 500','k '..(slotNum-2)}) end
  end
  l.debug(2)('arr-core:l.switch finished')
end

--========================================
--        m
--========================================
m.debugLevel = 0 -- #number exposed for console use. e.g. /script AssistRapidRiding.load('Core#M').debugLevel=1
m.reloadSkillInfo -- #()->() exposed for console use. e.g. /script AssistRapidRiding.load('Core#M').reloadSkillInfo()
= function()
  l.loadSkillInfo()
end

--========================================
--        register
--========================================
addon.register("Core#M",m)

addon.addAction("switch",function()
  local oss = l.getCharacterSavedVars().oldSlotedSkill
  if oss and oss.info then
    l.recover()
    return
  end
  l.token = l.token+1
  l.switch(l.token,true);
end)

addon.hookStart(l.onStart)

addon.extend(settings.EXTKEY_ADD_DEFAULTS,function()
  settings.addDefaults(coreSavedVarsDefaults)
end)

addon.extend(settings.EXTKEY_ADD_MENUS,function()
  settings.addMenuOptions(
    --
    {
      type = "slider",
      name = addon.text("Ability slot to use"),
      min = 1, max = 5, step = 1,
      getFunc = function() return l.getSavedVars().switchAtAbilitySlot end,
      setFunc = function(value) l.getSavedVars().switchAtAbilitySlot=value end,
      width = "full",
      default = coreSavedVarsDefaults.switchAtAbilitySlot,
    },
    --
    {
      type = "checkbox",
      name = addon.text("Enable autoswitch upon mounting/dismounting"),
      getFunc = function() return l.getSavedVars().autoSwitchWhenMounted end,
      setFunc = function(value) l.getSavedVars().autoSwitchWhenMounted=value end,
      width = "full",
      default =coreSavedVarsDefaults.autoSwitchWhenMounted,
    },
    --
    {
      type = "checkbox",
      name = addon.text("Only autoswitch in non-pvp zones"),
      getFunc = function() return l.getSavedVars().autoSwitchOnlyInNonPvpZones end,
      setFunc = function(value) l.getSavedVars().autoSwitchOnlyInNonPvpZones=value end,
      width = "full",
      default =coreSavedVarsDefaults.autoSwitchOnlyInNonPvpZones,
      disabled = function() return not l.getSavedVars().autoSwitchWhenMounted end
    },
    --
    {
      type = "checkbox",
      name = addon.text("Always autoswitch dispite of the effect"),
      getFunc = function() return l.getSavedVars().alwaysSwitchWhenMounted end,
      setFunc = function(value) l.getSavedVars().alwaysSwitchWhenMounted=value end,
      disabled = function() return not l.getSavedVars().autoSwitchWhenMounted end,
      width = "full",
      default =coreSavedVarsDefaults.alwaysSwitchWhenMounted,
    },
    --
    {
      type = "checkbox",
      name = addon.text("Revert when skill is used"),
      getFunc = function() return l.getSavedVars().switchBackWhenMounted end,
      setFunc = function(value) l.getSavedVars().switchBackWhenMounted=value end,
      width = "full",
      default =coreSavedVarsDefaults.switchBackWhenMounted,
    },
    --
    {
      type = "checkbox",
      name = addon.text("Re-switch when effect fades *"),
      getFunc = function() return l.getSavedVars().autoSwitchAgainBeforeEffectFades end,
      setFunc = function(value) l.getSavedVars().autoSwitchAgainBeforeEffectFades=value end,
      width = "full",
      default =coreSavedVarsDefaults.autoSwitchAgainBeforeEffectFades,
    },
    --
    {
      type = "slider",
      name = addon.text("How long before effects fades (seconds)"),
      min = 0, max = 5, step = 1,
      getFunc = function() return l.getSavedVars().secondsLeftToSwitchAgain end,
      setFunc = function(value) l.getSavedVars().secondsLeftToSwitchAgain=value end,
      width = "full",
      disabled = function() return not l.getSavedVars().autoSwitchAgainBeforeEffectFades end,
      default = coreSavedVarsDefaults.secondsLeftToSwitchAgain,
    },
    --
    {
      type = "checkbox",
      name = addon.text("Play sound when switch"),
      getFunc = function() return l.getSavedVars().soundEnabled end,
      setFunc = function(value) l.getSavedVars().soundEnabled = value end,
      width = "full",
      default = coreSavedVarsDefaults.soundEnabled,
    },
    --
    {
      type = "slider",
      name = addon.text("Sound index"),
      --tooltip = "",
      min = 1, max = #l.soundChoices, step = 1,
      getFunc = function() return l.getSavedVars().soundIndex end,
      setFunc = function(value) l.getSavedVars().soundIndex=value; PlaySound(SOUNDS[l.soundChoices[value]]) end,
      width = "full",
      disabled = function() return not l.getSavedVars().soundEnabled end,
      default = coreSavedVarsDefaults.soundIndex,
    },
    {
      type = "description",
      text = addon.text("* Only when player is mounted."), -- or string id or function returning a string
      title = "", -- or string id or function returning a string (optional)
      width = "full", --or "half" (optional)
    },
    {
      type = "description",
      text = addon.text("There is a hot key to switch manually."), -- or string id or function returning a string
      title = addon.text("Hint"), -- or string id or function returning a string (optional)
      width = "full", --or "half" (optional)
    }
  )
end)
