MSTedderExtension = {}

function MSTedderExtension:onStartWorkAreaProcessing(dt)
    -- Initialize accumulator for tedded areas this frame
    local spec = self.spec_tedder
    if spec then
        spec.msTeddedAreasThisFrame = {}
        print(string.format("[TEDDER] onStartWorkAreaProcessing: vehicle=%s initialized accumulator",
            self:getName() or "unknown"))
    else
        print(string.format("[TEDDER] WARNING: onStartWorkAreaProcessing called but spec_tedder is nil on vehicle %s",
            self:getName() or "unknown"))
    end
end

function MSTedderExtension:processDropArea(superFunc, dropArea, fillType, amount)
    local tracker = g_currentMission.groundPropertyTracker
    if not g_currentMission.MoistureSystem:isGrassOnGroundFillType(fillType) then
        return superFunc(self, dropArea, fillType, amount)
    end

    -- Check if dropping grass into a recent hay cell - if so, convert to hay
    local sx, sy, sz = getWorldTranslation(dropArea.start)
    local wx, wy, wz = getWorldTranslation(dropArea.width)
    local hx, hy, hz = getWorldTranslation(dropArea.height)

    local fillTypeName = g_fillTypeManager:getFillTypeNameByIndex(fillType)
    
    -- Calculate drop area dimensions for diagnostics
    local minX = math.min(sx, wx, hx)
    local maxX = math.max(sx, wx, hx)
    local minZ = math.min(sz, wz, hz)
    local maxZ = math.max(sz, wz, hz)
    local widthX = maxX - minX
    local depthZ = maxZ - minZ
    
    print(string.format("[TEDDER] processDropArea: vehicle=%s fillType=%s amount=%.2f pos=(%.1f, %.1f, %.1f) area=%.2fm×%.2fm",
        self:getName() or "unknown", fillTypeName or "nil", amount, sx, sy, sz, widthX, depthZ))

    local startX, startY, startZ, endX, endY, endZ, radius = DensityMapHeightUtil.getLineByArea(dropArea.start,
        dropArea.width, dropArea.height, true)
    local dropped, lineOffset = DensityMapHeightUtil.tipToGroundAroundLine(self, amount, fillType, startX, startY, startZ,
        endX, endY, endZ, radius, nil, dropArea.lineOffset, false, nil, false)
    dropArea.lineOffset = lineOffset


    if dropped > 0 then
        print(string.format("[TEDDER] Grass dropped: %.2f liters, outputMoisture=%s",
            dropped, dropArea.outputMoisture and string.format("%.3f", dropArea.outputMoisture) or "nil"))
        
        -- Don't call addPile here - let updateGrassMoisture handle pile creation/update
        -- But store the pickup moisture so it can be used when recreating the pile

        -- Store the pickup moisture for affected grid cells
        if dropArea.outputMoisture then
            local affectedCells = tracker:getAffectedGridCells(sx, sz, wx, wz, hx, hz)
            print(string.format("[TEDDER] Storing moisture for %d affected cells", #affectedCells))
            for _, cell in ipairs(affectedCells) do
                local gridKey = tracker:getSimpleGridKey(cell.gridX, cell.gridZ)
                tracker.teddedGrassMoisture[gridKey] = dropArea.outputMoisture
                print(string.format("[TEDDER]   Cell gridKey=%s moisture=%.3f", gridKey, dropArea.outputMoisture))
            end
        end

        -- Accumulate area for unified marking at end of frame
        local spec = self.spec_tedder
        if spec and spec.msTeddedAreasThisFrame then
            table.insert(spec.msTeddedAreasThisFrame, {
                sx = sx, sz = sz,
                wx = wx, wz = wz,
                hx = hx, hz = hz
            })
            print(string.format("[TEDDER] Accumulated tedded area, total areas: %d", #spec.msTeddedAreasThisFrame))
        else
            print(string.format("[TEDDER] WARNING: spec_tedder or msTeddedAreasThisFrame is nil! spec=%s",
                spec and "exists" or "nil"))
        end
    else
        print("[TEDDER] No grass was dropped (dropped=0)")
    end
    return dropped
end

Tedder.processDropArea = Utils.overwrittenFunction(Tedder.processDropArea, MSTedderExtension.processDropArea)

function MSTedderExtension:processTedderArea(_, workArea, dt)
    local spec = self.spec_tedder
    local workAreaSpec = self.spec_workArea

    local tracker = g_currentMission.groundPropertyTracker

    local sx, sy, sz = getWorldTranslation(workArea.start)
    local wx, wy, wz = getWorldTranslation(workArea.width)
    local hx, hy, hz = getWorldTranslation(workArea.height)
    local centerX = (sx + wx + hx) / 3
    local centerZ = (sz + wz + hz) / 3

    local positionMoisture

    local farmland = g_farmlandManager:getFarmlandAtWorldPosition(centerX, centerZ)
    local isContract = false
    if farmland ~= nil then
        isContract = g_missionManager:getIsMissionRunningOnFarmland(farmland)
    end

    -- Check for existing grass pile moisture at this location
    local converter = g_fillTypeManager:getConverterDataByName("TEDDER")
    for fromFillType, to in pairs(converter) do
        if fromFillType == to.targetFillTypeIndex then
            continue
        end

        local existingProps = tracker:getPropertiesAtLocation(centerX, centerZ, fromFillType)
        if existingProps and existingProps.moisture then
            positionMoisture = existingProps.moisture
            print(string.format("[TEDDER] Found existing pile moisture at (%.1f, %.1f): %.3f", 
                centerX, centerZ, positionMoisture))
            break
        end
    end
    
    if not positionMoisture then
        print(string.format("[TEDDER] No existing pile moisture at (%.1f, %.1f)", centerX, centerZ))
    end

    local lsx, lsy, lsz, lex, ley, lez, lineRadius = DensityMapHeightUtil.getLineByAreaDimensions(sx, sy, sz, wx, wy, wz,
        hx, hy, hz, true)

    for targetFillType, inputFillTypes in pairs(spec.fillTypeConvertersReverse) do
        local pickedUpLiters = 0
        local pickedUpHay = 0
        for _, inputFillType in ipairs(inputFillTypes) do
            local inputFillTypeName = g_fillTypeManager:getFillTypeNameByIndex(inputFillType)
            local pickup = DensityMapHeightUtil.tipToGroundAroundLine(self, -math.huge, inputFillType, lsx, lsy, lsz, lex,
                ley, lez,
                lineRadius, nil, nil, false, nil)
            if pickup ~= 0 then
                pickedUpLiters = pickedUpLiters + pickup
                if g_currentMission.MoistureSystem:isHayFillType(inputFillType) then
                    pickedUpHay = pickedUpHay + pickup
                end
            end
        end

        if pickedUpLiters == 0 and workArea.lastDropFillType ~= FillType.UNKNOWN then
            targetFillType = workArea.lastDropFillType
        end

        local gridCells = tracker:getAffectedGridCells(sx, sz, wx, wz, hx, hz)
        if pickedUpLiters ~= 0 and g_currentMission.MoistureSystem:isHayFillType(targetFillType) then
            for _, cell in pairs(gridCells) do
                -- Check all grass types for cleanup
                for fromFillType, to in pairs(converter) do
                    if fromFillType == to.targetFillTypeIndex then
                        continue
                    end

                    tracker:checkPileHasContent(cell.gridX, cell.gridZ, fromFillType)
                end
            end
        end

        workArea.lastPickupLiters = -pickedUpLiters
        workArea.litersToDrop = workArea.litersToDrop + workArea.lastPickupLiters

        -- drop
        local dropArea = workAreaSpec.workAreas[workArea.dropWindrowWorkAreaIndex]
        if dropArea ~= nil and workArea.litersToDrop > 0 then
            local dropped

            if g_currentMission.MoistureSystem:isHayFillType(targetFillType) and pickedUpHay == 0 and not isContract then
                -- override default hay drop - convert back to appropriate grass type
                local grassTypeName = nil

                -- Find the grass type that converts to this hay type
                for fromFillType, to in pairs(converter) do
                    if fromFillType == targetFillType then
                        continue
                    end

                    if to.targetFillTypeIndex == targetFillType then
                        grassTypeName = g_fillTypeManager:getFillTypeNameByIndex(fromFillType)
                        break
                    end
                end

                if grassTypeName then
                    dropArea.outputMoisture = positionMoisture
                    dropped = self:processDropArea(dropArea, g_fillTypeManager:getFillTypeIndexByName(grassTypeName),
                        workArea.litersToDrop)
                    dropArea.outputMoisture = nil
                else
                    dropped = self:processDropArea(dropArea, targetFillType, workArea.litersToDrop)
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

function MSTedderExtension:onEndWorkAreaProcessing(dt, hasProcessed)
    -- Process all accumulated tedded areas as one unified area
    local spec = self.spec_tedder
    local tracker = g_currentMission.groundPropertyTracker
    
    if spec and spec.msTeddedAreasThisFrame and #spec.msTeddedAreasThisFrame > 0 and tracker then
        print(string.format("[TEDDER] onEndWorkAreaProcessing: vehicle=%s areas=%d",
            self:getName() or "unknown", #spec.msTeddedAreasThisFrame))
        
        -- Calculate unified bounding box from all areas
        local minX, minZ = math.huge, math.huge
        local maxX, maxZ = -math.huge, -math.huge
        
        for _, area in ipairs(spec.msTeddedAreasThisFrame) do
            minX = math.min(minX, area.sx, area.wx, area.hx)
            maxX = math.max(maxX, area.sx, area.wx, area.hx)
            minZ = math.min(minZ, area.sz, area.wz, area.hz)
            maxZ = math.max(maxZ, area.sz, area.wz, area.hz)
        end
        
        local bboxWidth = maxX - minX
        local bboxDepth = maxZ - minZ
        print(string.format("[TEDDER] Unified bounding box: (%.1f, %.1f) to (%.1f, %.1f) = %.2fm×%.2fm",
            minX, minZ, maxX, maxZ, bboxWidth, bboxDepth))
        
        -- Use full accumulated area - don't narrow
        -- The overlap filtering will handle ensuring cells are predominantly within working width
        local testSx, testSz = minX, minZ
        local testWx, testWz = maxX, minZ
        local testHx, testHz = minX, maxZ
        
        print(string.format("[TEDDER] Using full accumulated area: %.2fm×%.2fm",
            bboxWidth, bboxDepth))
        
        tracker:markAreaTedded(testSx, testSz, testWx, testWz, testHx, testHz)
        
        -- Clear accumulator
        spec.msTeddedAreasThisFrame = {}
    end
end

Tedder.onStartWorkAreaProcessing = Utils.prependedFunction(Tedder.onStartWorkAreaProcessing, MSTedderExtension.onStartWorkAreaProcessing)
Tedder.processTedderArea = Utils.overwrittenFunction(Tedder.processTedderArea, MSTedderExtension.processTedderArea)
Tedder.onEndWorkAreaProcessing = Utils.appendedFunction(Tedder.onEndWorkAreaProcessing, MSTedderExtension.onEndWorkAreaProcessing)
