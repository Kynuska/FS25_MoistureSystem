MoistureSettingsEvent = {}
MoistureSettingsEvent_mt = Class(MoistureSettingsEvent, Event)

InitEventClass(MoistureSettingsEvent, "MoistureSettingsEvent")

function MoistureSettingsEvent.emptyNew()
    local self = Event.new(MoistureSettingsEvent_mt)
    return self
end

function MoistureSettingsEvent.new()
    local self = MoistureSettingsEvent.emptyNew()
    self.environment = g_currentMission.MoistureSystem.settings.environment
    return self
end

function MoistureSettingsEvent:writeStream(streamId, connection)
    streamWriteInt32(streamId, self.environment)
end

function MoistureSettingsEvent:readStream(streamId, connection)
    self.environment = streamReadInt32(streamId)
    self:run(connection)
end

function MoistureSettingsEvent:run(connection)
    if not connection:getIsServer() then
        g_server:broadcastEvent(MoistureSettingsEvent.new())
    end

    g_currentMission.MoistureSystem.settings.environment = self.environment

    if connection:getIsServer() then
        -- Update UI controls if they exist
        for _, id in pairs(MoistureSettings.menuItems) do
            local menuOption = MoistureSettings.CONTROLS[id]
            if menuOption then
                local isAdmin = g_currentMission:getIsServer() or g_currentMission.isMasterUser
                menuOption:setState(MoistureSettings.getStateIndex(id))
                menuOption:setDisabled(not isAdmin)
            end
        end
    end
end
