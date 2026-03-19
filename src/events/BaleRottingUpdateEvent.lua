---
-- BaleRottingUpdateEvent
-- Syncs bale rotting exposure data to clients for HUD display
---

BaleRottingUpdateEvent = {}
BaleRottingUpdateEvent_mt = Class(BaleRottingUpdateEvent, Event)

InitEventClass(BaleRottingUpdateEvent, "BaleRottingUpdateEvent")

function BaleRottingUpdateEvent.emptyNew()
    local self = Event.new(BaleRottingUpdateEvent_mt)
    return self
end

---
-- Create new event with bale rotting data
-- @param baleData: Table of bale data { [uniqueId] = { exposure, peakExposure, status } }
---
function BaleRottingUpdateEvent.new(baleData)
    local self = BaleRottingUpdateEvent.emptyNew()
    self.baleData = baleData or {}
    return self
end

function BaleRottingUpdateEvent:writeStream(streamId, connection)
    local count = 0
    for uniqueId, _ in pairs(self.baleData) do
        local object = g_currentMission:getObjectByUniqueId(uniqueId)
        if object ~= nil then
            count = count + 1
        end
    end

    streamWriteInt32(streamId, count)

    for uniqueId, data in pairs(self.baleData) do
        local object = g_currentMission:getObjectByUniqueId(uniqueId)
        if object ~= nil then
            streamWriteInt32(streamId, NetworkUtil.getObjectId(object))
            streamWriteFloat32(streamId, data.exposure)
            streamWriteFloat32(streamId, data.peakExposure)
            streamWriteInt32(streamId, data.status)
        end
    end
end

function BaleRottingUpdateEvent:readStream(streamId, connection)
    self.baleData = {}
    self.pendingBaleData = {}

    local count = streamReadInt32(streamId)
    for i = 1, count do
        local objectId = streamReadInt32(streamId)
        local exposure = streamReadFloat32(streamId)
        local peakExposure = streamReadFloat32(streamId)
        local status = streamReadInt32(streamId)

        local baleData = {
            exposure = exposure,
            peakExposure = peakExposure,
            status = status
        }

        local object = NetworkUtil.getObject(objectId)
        if object ~= nil and object.uniqueId ~= nil then
            self.baleData[object.uniqueId] = baleData
        else
            table.insert(self.pendingBaleData, { objectId = objectId, baleData = baleData })
        end
    end

    self:run(connection)
end

function BaleRottingUpdateEvent:run(connection)
    if not connection:getIsServer() then
        g_server:broadcastEvent(BaleRottingUpdateEvent.new(self.baleData))
    end

    local baleRottingSystem = g_currentMission.baleRottingSystem
    if baleRottingSystem then
        baleRottingSystem.baleRainExposureTimes = self.baleData
        if self.pendingBaleData and #self.pendingBaleData > 0 then
            for _, pending in ipairs(self.pendingBaleData) do
                table.insert(baleRottingSystem.pendingBaleRotting, pending)
            end
        end
    end
end
