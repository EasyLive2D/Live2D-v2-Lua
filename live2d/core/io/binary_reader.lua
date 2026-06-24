local ffi = require("ffi")
local def = require("live2d.core.def")
local Live2DObjectFactory = require("live2d.core.io.live2d_object_factory")
local Id = require("live2d.core.id.id")
local Int32Array = require("live2d.core.type.array").Int32Array
local Float32Array = require("live2d.core.type.array").Float32Array
local Float64Array = require("live2d.core.type.array").Float64Array

ffi.cdef[[
    typedef struct { float v; } float_holder;
    typedef struct { double v; } double_holder;
    typedef struct { int16_t v; } i16_holder;
]]

local BinaryReader = {}
BinaryReader.__index = BinaryReader

function BinaryReader.new(buf)
    local self = setmetatable({}, BinaryReader)
    self.offset8Bit = 0
    self.current8Bit = 0
    self.formatVersion = 0
    self.objects = {}
    self.objectCount = 0
    self.buf = buf
    self.len = #buf
    self.offset = 0
    return self
end

-- Big-endian int32 from string at position
local function be_int32(buf, offset)
    local b1, b2, b3, b4 = string.byte(buf, offset + 1, offset + 4)
    return bit.bor(bit.lshift(b1, 24), bit.lshift(b2, 16), bit.lshift(b3, 8), b4)
end

-- Big-endian float32 from string at position
local function be_float32(buf, offset)
    local ib = be_int32(buf, offset)
    local floatHolder = ffi.new("float_holder")
    local ptr = ffi.cast("int32_t*", floatHolder)
    ptr[0] = ib
    return floatHolder.v
end

-- Big-endian double from string at position
local function be_double(buf, offset)
    local b1, b2, b3, b4, b5, b6, b7, b8 = string.byte(buf, offset + 1, offset + 8)
    local high = bit.bor(bit.lshift(b1, 24), bit.lshift(b2, 16), bit.lshift(b3, 8), b4)
    local low = bit.bor(bit.lshift(b5, 24), bit.lshift(b6, 16), bit.lshift(b7, 8), b8)
    local doubleHolder = ffi.new("double_holder")
    local ptr = ffi.cast("int32_t*", doubleHolder)
    ptr[0] = low
    ptr[1] = high
    return doubleHolder.v
end

-- Big-endian int16 from string at position
local function be_int16(buf, offset)
    local b1, b2 = string.byte(buf, offset + 1, offset + 2)
    local unsignedInt16 = bit.bor(bit.lshift(b1, 8), b2)
    if bit.band(unsignedInt16, 32768) ~= 0 then
        unsignedInt16 = unsignedInt16 - 65536
    end
    return unsignedInt16
end

function BinaryReader:readNumber()
    local b1 = self:readByte()
    if bit.band(b1, 128) == 0 then
        return bit.band(b1, 255)
    end
    local b2 = self:readByte()
    if bit.band(b2, 128) == 0 then
        return bit.bor(bit.lshift(bit.band(b1, 127), 7), bit.band(b2, 127))
    end
    local b3 = self:readByte()
    if bit.band(b3, 128) == 0 then
        return bit.bor(bit.lshift(bit.band(b1, 127), 14),
                       bit.bor(bit.lshift(bit.band(b2, 127), 7), bit.band(b3, 255)))
    end
    local b4 = self:readByte()
    if bit.band(b4, 128) == 0 then
        return bit.bor(bit.lshift(bit.band(b1, 127), 21),
                       bit.bor(bit.lshift(bit.band(b2, 127), 14),
                       bit.bor(bit.lshift(bit.band(b3, 127), 7), bit.band(b4, 255))))
    end
    error("number parse error")
end

function BinaryReader:getFormatVersion()
    return self.formatVersion
end

function BinaryReader:setFormatVersion(version)
    self.formatVersion = version
end

function BinaryReader:readType()
    return self:readNumber()
end

function BinaryReader:readDouble()
    self:checkBits()
    local savedOffset = self.offset
    self.offset = self.offset + 8
    return be_double(self.buf, savedOffset)
end

function BinaryReader:readFloat32()
    self:checkBits()
    local savedOffset = self.offset
    self.offset = self.offset + 4
    return be_float32(self.buf, savedOffset)
end

function BinaryReader:readInt32()
    self:checkBits()
    local savedOffset = self.offset
    self.offset = self.offset + 4
    return be_int32(self.buf, savedOffset)
end

function BinaryReader:readByte()
    self:checkBits()
    local savedOffset = self.offset
    self.offset = self.offset + 1
    return string.byte(self.buf, savedOffset + 1)
end

function BinaryReader:readUShort()
    self:checkBits()
    local savedOffset = self.offset
    self.offset = self.offset + 2
    return be_int16(self.buf, savedOffset)
end

function BinaryReader:readBoolean()
    self:checkBits()
    local savedOffset = self.offset
    self.offset = self.offset + 1
    return string.byte(self.buf, savedOffset + 1) ~= 0
end

function BinaryReader:readUTF8String()
    self:checkBits()
    local stringLength = self:readType()
    local result = string.sub(self.buf, self.offset + 1, self.offset + stringLength)
    self.offset = self.offset + stringLength
    return result
end

function BinaryReader:readInt32Array()
    self:checkBits()
    local arrayLength = self:readType()
    local intArray = Int32Array(arrayLength)
    for i = 1, arrayLength do
        intArray[i] = self:readInt32()
    end
    return intArray
end

function BinaryReader:readFloat32Array()
    self:checkBits()
    local arrayLength = self:readType()
    local floatArray = Float32Array(arrayLength)
    for i = 1, arrayLength do
        floatArray[i] = self:readFloat32()
    end
    return floatArray
end

function BinaryReader:readFloat64Array()
    self:checkBits()
    local arrayLength = self:readType()
    local doubleArray = Float64Array(arrayLength)
    for i = 1, arrayLength do
        doubleArray[i] = self:readDouble()
    end
    return doubleArray
end

function BinaryReader:readObject(typeHint)
    self:checkBits()
    if typeHint == nil then typeHint = -1 end
    if typeHint < 0 then
        typeHint = self:readType()
    end
    if typeHint == def.OBJECT_REF then
        local objectReferenceIndex = self:readInt32()
        if 0 <= objectReferenceIndex and objectReferenceIndex < self.objectCount then
            return self.objects[objectReferenceIndex + 1]
        else
            error("_sL _4i @_m0 ref=" .. tostring(objectReferenceIndex) .. " len=" .. tostring(self.objectCount))
        end
    else
        local deserializedObject = self:readKnownTypeObject(typeHint)
        self.objectCount = self.objectCount + 1
        self.objects[self.objectCount] = deserializedObject
        return deserializedObject
    end
end

function BinaryReader:readKnownTypeObject(objectType)
    if objectType == 0 then
        return nil
    elseif objectType == 50 or objectType == 51 or objectType == 134 or objectType == 60 then
        return Id.getID(self:readUTF8String())
    elseif objectType >= 48 then
        local live2dObject = Live2DObjectFactory.create(objectType)
        live2dObject:read(self)
        return live2dObject
    elseif objectType == 1 then
        return self:readUTF8String()
    elseif objectType == 15 then
        local arrayLength = self:readType()
        local objectArray = {}
        for i = 1, arrayLength do
            objectArray[i] = self:readObject()
        end
        return objectArray
    elseif objectType == 23 then
        error("type not implemented")
    elseif objectType == 16 or objectType == 25 then
        return self:readInt32Array()
    elseif objectType == 26 then
        return self:readFloat64Array()
    elseif objectType == 27 then
        return self:readFloat32Array()
    end
    error("type error " .. tostring(objectType))
end

function BinaryReader:readBit()
    if self.offset8Bit == 0 then
        self.current8Bit = self:readByte()
    elseif self.offset8Bit == 8 then
        self.current8Bit = self:readByte()
        self.offset8Bit = 0
    end
    local bitValue = bit.band(bit.rshift(self.current8Bit, 7 - self.offset8Bit), 1) == 1
    self.offset8Bit = self.offset8Bit + 1
    return bitValue
end

function BinaryReader:checkBits()
    if self.offset8Bit ~= 0 then
        self.offset8Bit = 0
    end
end

return BinaryReader
