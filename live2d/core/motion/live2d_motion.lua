local Motion = require("live2d.core.motion.motion")
local AMotion = require("live2d.core.motion.amotion")
local UtString = require("live2d.core.util.ut_string")

local Live2DMotion = setmetatable({}, { __index = AMotion })
Live2DMotion.__index = Live2DMotion

Live2DMotion.MTN_PREFIX_VISIBLE = "VISIBLE:"
Live2DMotion.MTN_PREFIX_LAYOUT = "LAYOUT:"
Live2DMotion.MTN_PREFIX_FADE_IN = "FADEIN:"
Live2DMotion.MTN_PREFIX_FADE_OUT = "FADEOUT:"

function Live2DMotion.new()
    local self = setmetatable(AMotion.new(), Live2DMotion)
    self.motions = {}
    self.srcFps = 30
    self.maxLength = 0
    self.loop = false
    self.loopFadeIn = true
    self.loopDurationMSec = -1
    self.lastWeight = 0
    return self
end

function Live2DMotion:getDurationMSec()
    if self.loop then return -1 end
    return self.loopDurationMSec
end

function Live2DMotion:getLoopDurationMSec()
    return self.loopDurationMSec
end

function Live2DMotion:updateParamExe(model, currentTimeMSec, weight, motionQueueEntry)
    local elapsedTimeMSec = currentTimeMSec - motionQueueEntry.startTimeMSec
    local framePosition = elapsedTimeMSec * self.srcFps / 1000
    local currentFrame = math.floor(framePosition)
    local frameFraction = framePosition - currentFrame

    for motionIndex = 1, #self.motions do
        local motionChannel = self.motions[motionIndex]
        local valueCount = #motionChannel.values
        local paramId = motionChannel.paramIdStr
        if motionChannel.mtnType == Motion.MOTION_TYPE_PARTS_VISIBLE then
            local keyframeIndex = currentFrame >= valueCount and valueCount or (currentFrame + 1)
            local keyframeValue = motionChannel.values[keyframeIndex]
            model:setParamFloat(paramId, keyframeValue)
        else
            if Motion.MOTION_TYPE_LAYOUT_X <= motionChannel.mtnType and motionChannel.mtnType <= Motion.MOTION_TYPE_LAYOUT_SCALE_Y then
                -- pass
            else
                local paramIndex = model:getParamIndex(paramId)
                local modelContext = model:getModelContext()
                local paramMax = modelContext:getParamMax(paramIndex)
                local paramMin = modelContext:getParamMin(paramIndex)
                local smoothFactor = 0.4
                local smoothThreshold = smoothFactor * (paramMax - paramMin)
                local currentValue = modelContext:getParamFloat(paramIndex)
                local idx1 = currentFrame >= valueCount and valueCount or (currentFrame + 1)
                local idx2 = currentFrame + 1 >= valueCount and valueCount or (currentFrame + 2)
                local startValue = motionChannel.values[idx1]
                local endValue = motionChannel.values[idx2]
                local interpolatedValue
                if (startValue < endValue and endValue - startValue > smoothThreshold) or (startValue > endValue and startValue - endValue > smoothThreshold) then
                    interpolatedValue = startValue
                else
                    interpolatedValue = startValue + (endValue - startValue) * frameFraction
                end
                local blendedValue = currentValue + (interpolatedValue - currentValue) * weight
                model:setParamFloat(paramIndex, blendedValue)
            end
        end
    end

    if currentFrame >= self.maxLength then
        if self.loop then
            motionQueueEntry.startTimeMSec = currentTimeMSec
            if self.loopFadeIn then
                motionQueueEntry.fadeInStartTimeMSec = currentTimeMSec
            end
        else
            motionQueueEntry.finished = true
        end
    end
    self.lastWeight = weight
end

function Live2DMotion.loadMotion(motionData)
    local mtn = Live2DMotion.new()
    local parseOffset = {0}
    local dataLength = #motionData
    mtn.maxLength = 0
    local cursor = 0
    while cursor < dataLength do
        local currentByte = motionData:byte(cursor + 1)
        local currentChar = string.char(currentByte)
        if currentChar == "\n" or currentChar == "\r" then
            cursor = cursor + 1
        elseif currentChar == "#" then
            while cursor < dataLength do
                local c = motionData:sub(cursor + 1, cursor + 1)
                if c == "\n" or c == "\r" then break end
                cursor = cursor + 1
            end
            cursor = cursor + 1
        elseif currentChar == "" then
            local lineStart = cursor
            while cursor < dataLength do
                local c = motionData:sub(cursor + 1, cursor + 1)
                if c == "\r" or c == "\n" then break end
                if c == "=" then break end
                cursor = cursor + 1
            end
            while cursor < dataLength do
                local c = motionData:sub(cursor + 1, cursor + 1)
                if c == "\n" or c == "\r" then break end
                cursor = cursor + 1
            end
            cursor = cursor + 1
        else
            local isAlpha = (97 <= currentByte and currentByte <= 122) or (65 <= currentByte and currentByte <= 90) or currentChar == "_"
            if isAlpha then
                local keyStart = cursor
                local equalsPos = -1
                while cursor < dataLength do
                    local c = motionData:sub(cursor + 1, cursor + 1)
                    if c == "\r" or c == "\n" then break end
                    if c == "=" then
                        equalsPos = cursor
                        break
                    end
                    cursor = cursor + 1
                end

                if equalsPos >= 0 then
                    local motionEntry = Motion.new()
                    if UtString.startsWith(motionData, keyStart, Live2DMotion.MTN_PREFIX_VISIBLE) then
                        motionEntry.mtnType = Motion.MOTION_TYPE_PARTS_VISIBLE
                        motionEntry.paramIdStr = UtString.createString(motionData, keyStart, equalsPos - keyStart)
                    elseif UtString.startsWith(motionData, keyStart, Live2DMotion.MTN_PREFIX_LAYOUT) then
                        motionEntry.paramIdStr = UtString.createString(motionData, keyStart + 7, equalsPos - keyStart - 7)
                        if UtString.startsWith(motionData, keyStart + 7, "ANCHOR_X") then
                            motionEntry.mtnType = Motion.MOTION_TYPE_LAYOUT_ANCHOR_X
                        elseif UtString.startsWith(motionData, keyStart + 7, "ANCHOR_Y") then
                            motionEntry.mtnType = Motion.MOTION_TYPE_LAYOUT_ANCHOR_Y
                        elseif UtString.startsWith(motionData, keyStart + 7, "SCALE_X") then
                            motionEntry.mtnType = Motion.MOTION_TYPE_LAYOUT_SCALE_X
                        elseif UtString.startsWith(motionData, keyStart + 7, "SCALE_Y") then
                            motionEntry.mtnType = Motion.MOTION_TYPE_LAYOUT_SCALE_Y
                        elseif UtString.startsWith(motionData, keyStart + 7, "Y") then
                            motionEntry.mtnType = Motion.MOTION_TYPE_LAYOUT_Y
                        else
                            motionEntry.mtnType = Motion.MOTION_TYPE_LAYOUT_X
                        end
                    else
                        motionEntry.mtnType = Motion.MOTION_TYPE_PARAM
                        motionEntry.paramIdStr = UtString.createString(motionData, keyStart, equalsPos - keyStart)
                    end

                    mtn.motions[#mtn.motions + 1] = motionEntry
                    local valueCount = 0
                    local values = {}
                    cursor = equalsPos + 1
                    while cursor < dataLength do
                        local c = motionData:sub(cursor + 1, cursor + 1)
                        if c == "\r" or c == "\n" then break end
                        if c == "," or c == " " or c == "\t" then
                            cursor = cursor + 1
                        else
                            local parsedFloat = UtString.strToFloat(motionData, dataLength, cursor, parseOffset)
                            if parseOffset[1] > 0 then
                                values[#values + 1] = parsedFloat
                                valueCount = valueCount + 1
                                local newOffset = parseOffset[1]
                                if newOffset < cursor then
                                    print("invalid state during loadMotion")
                                    break
                                end
                                cursor = newOffset - 1
                            end
                            cursor = cursor + 1
                        end
                    end
                    motionEntry.values = values
                    if valueCount > mtn.maxLength then
                        mtn.maxLength = valueCount
                    end
                end
            end
            cursor = cursor + 1
        end
    end

    mtn.loopDurationMSec = math.floor((1000 * mtn.maxLength) / mtn.srcFps)
    return mtn
end

return Live2DMotion
