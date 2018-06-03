require "lib/utilities/generic"

-- Class that controls the behavior of the surface:
  -- control the darkness
  -- control the time (related to darkness)
PhaseCycler = {}

-- PHASES:
-- 1. Initial Day phase (inital long phase)
-- 2. Nightfall phase
-- 3. Night phase (BugZilla spawned)
-- 4. Dawn phase
-- 5. Day phase
-- 6. back to 2
PhaseCycler.initPhaseIndex = 0
PhaseCycler.dayPhaseIndex = 1
PhaseCycler.nightfallPhaseIndex = 2
PhaseCycler.nightPhaseIndex = 3
PhaseCycler.sunsetPhaseIndex = 4

-- next phase
PhaseCycler.getNextPhaseIndex = {
  [PhaseCycler.initPhaseIndex] = PhaseCycler.nightfallPhaseIndex,
  [PhaseCycler.dayPhaseIndex] = PhaseCycler.nightfallPhaseIndex,
  [PhaseCycler.nightfallPhaseIndex] = PhaseCycler.nightPhaseIndex,
  [PhaseCycler.nightPhaseIndex] = PhaseCycler.sunsetPhaseIndex,
  [PhaseCycler.sunsetPhaseIndex] = PhaseCycler.dayPhaseIndex
}
-- brightness config
PhaseCycler.dayBrightness = 1
PhaseCycler.nightBrightness = 0



function PhaseCycler:Init()

  -- Init the world
  game.map_settings.pollution.enabled = true
  game.map_settings.pollution.diffusion_ratio = 0.5
  game.map_settings.pollution.min_to_diffuse = 15
  game.map_settings.enemy_evolution.enabled = false
  game.map_settings.enemy_expansion.enabled = false
  game.map_settings.peaceful_mode = false
  game.surfaces['nauvis'].freeze_daytime = true

  -- Kill all biters in already discovered terrain, others gets destroyed on discovery
  local surface = game.surfaces['nauvis']
  for c in surface.get_chunks() do  -- kill all biters in visible area
     for key, entity in pairs(surface.find_entities_filtered({area={{c.x * 32, c.y * 32}, {c.x * 32 + 32, c.y * 32 + 32}}, force= "enemy"})) do
         entity.destroy()
     end
   end

  -- Init data if not existing
  if not global.BZ_data then
    global.BZ_data = self:InitGlobalData()
    if global.BZ_data == nil then
      game.print("BugZilla.lib.bugzilla.phaseCycler.lua: Initialisation of global.BZ_data went wrong")
    end
  end
end



function PhaseCycler:InitGlobalData()
  local data = {
    -- meta data
    Name = 'BZ_data',
    Version = '1',

    -- states
    previousState = nil,
    currentState = nil,

    -- state data
    initState = {
      phaseIndex = self.initPhaseIndex,
      phaseDuration = 0, -- time (seconds) we are in this phase
      phaseTotalDuration = settings.global["BZ-initial-day-length"].value * 60, -- how long this phase lasts (in seconds)

      currentBrightness = self.dayBrightness,
      startBrightness = self.dayBrightness,
      endBrightness = self.dayBrightness,

      nextPhaseIndex = self.nightfallPhaseIndex
    }
  }
  data.currentState = DeepCopy(data.initState)
  return data
end



function PhaseCycler:OnSettingsChanged(event)
  if event.setting_type == "runtime-global" then
    -- MessageAll(game.players[event.player_index].name .. " changed setting " .. event.setting)

    if global.BZ_data ~= nil then
      local currentState = global.BZ_data.currentState
      if (event.setting == "BZ-day-length" and currentState.phaseIndex == self.dayPhaseIndex)
      or (event.setting == "BZ-night-length" and currentState.phaseIndex == self.nightPhaseIndex)
      or event.setting == "BZ-initial-day-length" and currentState.phaseIndex == self.initPhaseIndex then
        currentState.phaseTotalDuration = 60 * settings.global[event.setting].value
        global.BZ_data.currentState = currentState
        -- game.print("updated global.BZ_data")
      end
    else
      game.print("BugZilla.lib.bugzilla.phaseCycler.lua: global.BZ_data hasn't been declared yet")
    end
  end
end



function PhaseCycler:OnChunkGenerated(event)
  local surface = event.surface
  if surface == game.surfaces['nauvis'] then
    for key, entity in pairs(surface.find_entities_filtered({area=event.area, force= "enemy"})) do
        entity.destroy()
    end
  end
end



function PhaseCycler:OnSecond()
  local currentState = global.BZ_data.currentState
  global.BZ_data.previousState = DeepCopy(currentState)

  currentState.phaseDuration = currentState.phaseDuration + 1
  -- game.print("This phase: " .. global.BZ_data.currentState.phaseDuration .. "/" .. global.BZ_data.currentState.phaseTotalDuration)

  -- Check if we are finished with the current phase
  if currentState.phaseDuration >= currentState.phaseTotalDuration then
    self:GoToNextPhase()
  end

  -- Check if we need to change the brightness
  if currentState.currentBrightness ~= currentState.endBrightness then
    currentState.currentBrightness = Math:Lerp(currentState.startBrightness, currentState.endBrightness, (currentState.phaseDuration + 1)/currentState.phaseTotalDuration)
    self:SetBrightness(currentState.currentBrightness)
  end

  global.BZ_data.currentState = currentState
end



function PhaseCycler:GoToNextPhase()
  -- game.print("BugZilla.lib.bugzilla.phaseCycler.lua: switching phases!")
  local currentState = global.BZ_data.currentState

  if currentState.phaseDuration > 1 then
    -- reset phase timer
    currentState.phaseDuration = 0

    -- update phase itself
    currentState.phaseIndex = currentState.nextPhaseIndex
    currentState.nextPhaseIndex = self.getNextPhaseIndex[currentState.phaseIndex]

    -- update phaseData depending on phaseIndex
       -- phaseTotalDuration
       -- startBrightness, endBrightness
    currentState.startBrightness = currentState.currentBrightness

    if currentState.phaseIndex == self.dayPhaseIndex then
      currentState.phaseTotalDuration = 60 * settings.global["BZ-day-length"].value
      currentState.endBrightness = self.dayBrightness

    elseif currentState.phaseIndex == self.nightfallPhaseIndex then
      currentState.phaseTotalDuration = 60
      currentState.endBrightness = self.nightBrightness
      MessageAll(Boss:GetSpawnMessage())

    elseif currentState.phaseIndex == self.nightPhaseIndex then
      currentState.phaseTotalDuration = 60 * settings.global["BZ-night-length"].value
      currentState.endBrightness = self.nightBrightness
      -- Spawn boss
      Boss:Spawn()

    elseif currentState.phaseIndex == self.sunsetPhaseIndex then
      currentState.phaseTotalDuration = 60
      currentState.endBrightness = self.dayBrightness
      -- despawn boss if it's not death
      if Boss:IsAlive() then
        Boss:Despawn()
      end


    else
      -- game.print("BugZilla.lib.bugzilla.phaseCycler.lua: Unknown phase:" .. currentState.phaseIndex)
    end
  else
    -- game.print("BugZilla.lib.bugzilla.phaseCycler.lua: switching phases too fast!")
  end

  global.BZ_data.currentState = currentState

end



function PhaseCycler:SetBrightness(brightness)
  -- game.print("brightness: " .. brightness)
  -- Lerp between day (0.5 = noon) and night (0.0 = midnight)
  game.surfaces.nauvis.daytime = Math:Lerp(0.42, 0.25, brightness)
end
