MSTedderExtension = {}

-- Configuration
MSTedderExtension.MOISTURE_REDUCTION_PER_PASS = 0.05
MSTedderExtension.DRY_THRESHOLD = 0.07

function MSTedderExtension:processDropArea(superFunc, dropArea, fillType, amount)
    if g_fillTypeManager:getFillTypeNameByIndex(fillType) ~= "GRASS_WINDROW" then
        return superFunc(self, dropArea,
            fillType, amount)
    end

    local startX, startY, startZ, endX, endY, endZ, radius = DensityMapHeightUtil.getLineByArea(dropArea.start,
        dropArea.width, dropArea.height, true)
    local dropped, lineOffset = DensityMapHeightUtil.tipToGroundAroundLine(self, amount, fillType, startX, startY, startZ,
        endX, endY, endZ, radius, nil, dropArea.lineOffset, false, nil, false)
    dropArea.lineOffset = lineOffset


    local sx, _, sz = getWorldTranslation(dropArea.start)
    local wx, _, wz = getWorldTranslation(dropArea.width)
    local hx, _, hz = getWorldTranslation(dropArea.height)

    local moistureSystem = g_currentMission.MoistureSystem
    local tracker = g_currentMission.harvestPropertyTracker

    local dropMoisture = dropArea.outputMoisture
    if dropMoisture == nil then
        local centerX = (sx + wx + hx) / 3
        local centerZ = (sz + wz + hz) / 3
        dropMoisture = moistureSystem:getMoistureAtPosition(centerX, centerZ)
    end

    tracker:addPile(sx, sz, wx, wz, hx, hz, fillType, dropped, {
        moisture = dropMoisture
    })

    return dropped
end

Tedder.processDropArea = Utils.overwrittenFunction(Tedder.processDropArea, MSTedderExtension.processDropArea)

function MSTedderExtension:processTedderArea(_, workArea, dt)
    local spec = self.spec_tedder
    local workAreaSpec = self.spec_workArea

    local moistureSystem = g_currentMission.MoistureSystem
    local tracker = g_currentMission.harvestPropertyTracker
    local grassFillTypeIndex = g_fillTypeManager:getFillTypeIndexByName("GRASS_WINDROW")
    local hayFillTypeIndex = g_fillTypeManager:getFillTypeIndexByName("DRYGRASS_WINDROW")

    local sx, sy, sz = getWorldTranslation(workArea.start)
    local wx, wy, wz = getWorldTranslation(workArea.width)
    local hx, hy, hz = getWorldTranslation(workArea.height)

    local centerX = (sx + wx + hx) / 3
    local centerZ = (sz + wz + hz) / 3

    local positionMoisture
    local existingProps = tracker:getPropertiesAtLocation(centerX, centerZ, grassFillTypeIndex)

    if existingProps and existingProps.moisture then
        -- Grass already here with metadata - use it
        positionMoisture = existingProps.moisture
        -- print(string.format("[TEDDER DROP] Found existing pile metadata: %.1f%% moisture", positionMoisture * 100))
    else
        -- Fresh grass - use field moisture
        positionMoisture = moistureSystem:getMoistureAtPosition(centerX, centerZ)
        -- print(string.format("[TEDDER DROP] No existing pile, using field moisture: %.1f%%", positionMoisture * 100))
    end

    -- pick up
    local lsx, lsy, lsz, lex, ley, lez, lineRadius = DensityMapHeightUtil.getLineByAreaDimensions(sx, sy, sz, wx, wy, wz,
        hx, hy, hz, true)

    for targetFillType, inputFillTypes in pairs(spec.fillTypeConvertersReverse) do
        local pickedUpLiters = 0
        for _, inputFillType in ipairs(inputFillTypes) do
            pickedUpLiters = pickedUpLiters +
                DensityMapHeightUtil.tipToGroundAroundLine(self, -math.huge, inputFillType, lsx, lsy, lsz, lex, ley, lez,
                    lineRadius, nil, nil, false, nil)
        end

        if pickedUpLiters == 0 and workArea.lastDropFillType ~= FillType.UNKNOWN then
            targetFillType = workArea.lastDropFillType
        end

        if pickedUpLiters < 0 and targetFillType == hayFillTypeIndex then
            tracker:checkPileHasContent(centerX, centerZ, grassFillTypeIndex)
        end

        workArea.lastPickupLiters = -pickedUpLiters
        workArea.litersToDrop = workArea.litersToDrop + workArea.lastPickupLiters

        -- drop
        local dropArea = workAreaSpec.workAreas[workArea.dropWindrowWorkAreaIndex]
        if dropArea ~= nil and workArea.litersToDrop > 0 then
            local dropped
            dropArea.outputMoisture = nil

            if g_fillTypeManager:getFillTypeNameByIndex(targetFillType) == "DRYGRASS_WINDROW" then
                -- override default hay drop
                local dropMoisture = math.max(0, positionMoisture - MSTedderExtension.MOISTURE_REDUCTION_PER_PASS)
                if dropMoisture > MSTedderExtension.DRY_THRESHOLD then
                    -- targetFillType = g_fillTypeManager:getFillTypeIndexByName("GRASS_WINDROW")
                    dropArea.outputMoisture = dropMoisture
                    dropped = self:processDropArea(dropArea, grassFillTypeIndex, workArea.litersToDrop)
                else
                    dropped = self:processDropArea(dropArea, hayFillTypeIndex, workArea.litersToDrop)
                end
            else
                dropped = self:processDropArea(dropArea, targetFillType, workArea.litersToDrop)
            end

            workArea.lastDropFillType = targetFillType
            workArea.lastDroppedLiters = dropped
            spec.lastDroppedLiters = spec.lastDroppedLiters + dropped
            workArea.litersToDrop = workArea.litersToDrop - dropped

            if self.isServer then
                local lastSpeed = self:getLastSpeed(true)
                if dropped > 0 and lastSpeed > 0.5 then
                    local changedFillType = false
                    if spec.tedderWorkAreaFillTypes[workArea.tedderWorkAreaIndex] ~= targetFillType then
                        spec.tedderWorkAreaFillTypes[workArea.tedderWorkAreaIndex] = targetFillType
                        self:raiseDirtyFlags(spec.fillTypesDirtyFlag)
                        changedFillType = true
                    end

                    local effects = spec.workAreaToEffects[workArea.index]
                    if effects ~= nil then
                        for _, effect in ipairs(effects) do
                            effect.activeTime = g_currentMission.time + effect.activeTimeDuration

                            if not effect.isActiveSent then
                                effect.isActiveSent = true
                                self:raiseDirtyFlags(spec.effectDirtyFlag)
                            end

                            if changedFillType then
                                g_effectManager:setEffectTypeInfo(effect.effects, targetFillType)
                            end

                            if not effect.isActive then
                                g_effectManager:setEffectTypeInfo(effect.effects, targetFillType)
                                g_effectManager:startEffects(effect.effects)
                            end

                            g_effectManager:setDensity(effect.effects, math.max(lastSpeed / self:getSpeedLimit(), 0.6))

                            effect.isActive = true
                        end
                    end
                end
            end
        end
    end

    if self:getLastSpeed() > 0.5 then
        spec.stoneLastState = FSDensityMapUtil.getStoneArea(sx, sz, wx, wz, hx, hz)
    else
        spec.stoneLastState = 0
    end

    local areaWidth = MathUtil.vector3Length(lsx - lex, lsy - ley, lsz - lez)
    local area = areaWidth * self.lastMovedDistance

    return area, area
end

Tedder.processTedderArea = Utils.overwrittenFunction(Tedder.processTedderArea, MSTedderExtension.processTedderArea)
