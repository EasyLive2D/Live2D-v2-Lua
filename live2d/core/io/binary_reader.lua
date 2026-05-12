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
    local h = ffi.new("float_holder")
    local ptr = ffi.cast("int32_t*", h)
    ptr[0] = ib
    return h.v
end

-- Big-endian double from string at position
local function be_double(buf, offset)
    local b1, b2, b3, b4, b5, b6, b7, b8 = string.byte(buf, offset + 1, offset + 8)
    local high = bit.bor(bit.lshift(b1, 24), bit.lshift(b2, 16), bit.lshift(b3, 8), b4)
    local low = bit.bor(bit.lshift(b5, 24), bit.lshift(b6, 16), bit.lshift(b7, 8), b8)
    local h = ffi.new("double_holder")
    local ptr = ffi.cast("int32_t*", h)
    ptr[0] = low
    ptr[1] = high
    return h.v
end

-- Big-endian int16 from string at position
local function be_int16(buf, offset)
    local b1, b2 = string.byte(buf, offset + 1, offset + 2)
    local u = bit.bor(bit.lshift(b1, 8), b2)
    if bit.band(u, 32768) ~= 0 then
        u = u - 65536
    end
    return u
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

function BinaryReader:setFormatVersion(aH)
    self.formatVersion = aH
end

function BinaryReader:readType()
    return self:readNumber()
end

function BinaryReader:readDouble()
    self:checkBits()
    local ret = self.offset
    self.offset = self.offset + 8
    return be_double(self.buf, ret)
end

function BinaryReader:readFloat32()
    self:checkBits()
    local ret = self.offset
    self.offset = self.offset + 4
    return be_float32(self.buf, ret)
end

function BinaryReader:readInt32()
    self:checkBits()
    local ret = self.offset
    self.offset = self.offset + 4
    return be_int32(self.buf, ret)
end

function BinaryReader:readByte()
    self:checkBits()
    local ret = self.offset
    self.offset = self.offset + 1
    return string.byte(self.buf, ret + 1)
end

function BinaryReader:readUShort()
    self:checkBits()
    local ret = self.offset
    self.offset = self.offset + 2
    return be_int16(self.buf, ret)
end

function BinaryReader:readLong()
    self:checkBits()
    self.offset = self.offset + 8
    error("_L _q read long")
end

function BinaryReader:readBoolean()
    self:checkBits()
    local ret = self.offset
    self.offset = self.offset + 1
    return string.byte(self.buf, ret + 1) ~= 0
end

function BinaryReader:readUTF8String()
    self:checkBits()
    local aH = self:readType()
    local result = string.sub(self.buf, self.offset + 1, self.offset + aH)
    self.offset = self.offset + aH
    return result
end

function BinaryReader:readInt32Array()
    self:checkBits()
    local aI = self:readType()
    local aH = Int32Array(aI)
    for aJ = 1, aI do
        aH[aJ] = self:readInt32()
    end
    return aH
end

function BinaryReader:readFloat32Array()
    self:checkBits()
    local aI = self:readType()
    local aH = Float32Array(aI)
    for aJ = 1, aI do
        aH[aJ] = self:readFloat32()
    end
    return aH
end

function BinaryReader:readFloat64Array()
    self:checkBits()
    local aI = self:readType()
    local aH = Float64Array(aI)
    for aJ = 1, aI do
        aH[aJ] = self:readDouble()
    end
    return aH
end

function BinaryReader:readObject(aJ)
    self:checkBits()
    if aJ == nil then aJ = -1 end
    if aJ < 0 then
        aJ = self:readType()
    end
    if aJ == def.OBJECT_REF then
        local aH = self:readInt32()
        if 0 <= aH and aH < #self.objects then
            return self.objects[aH + 1]
        else
            error("_sL _4i @_m0 ref=" .. tostring(aH) .. " len=" .. tostring(#self.objects))
        end
    else
        local aI = self:readKnownTypeObject(aJ)
        self.objects[#self.objects + 1] = aI
        return aI
    end
end

function BinaryReader:readKnownTypeObject(aN)
    if aN == 0 then
        return nil
    elseif aN == 50 or aN == 51 or aN == 134 or aN == 60 then
        return Id.getID(self:readUTF8String())
    elseif aN >= 48 then
        local aL = Live2DObjectFactory.create(aN)
        aL:read(self)
        return aL
    elseif aN == 1 then
        return self:readUTF8String()
    elseif aN == 15 then
        local aH = self:readType()
        local aI = {}
        for aJ = 1, aH do
            aI[aJ] = self:readObject()
        end
        return aI
    elseif aN == 23 then
        error("type not implemented")
    elseif aN == 16 or aN == 25 then
        return self:readInt32Array()
    elseif aN == 26 then
        return self:readFloat64Array()
    elseif aN == 27 then
        return self:readFloat32Array()
    end
    error("type error " .. tostring(aN))
end

function BinaryReader:readBit()
    if self.offset8Bit == 0 then
        self.current8Bit = self:readByte()
    elseif self.offset8Bit == 8 then
        self.current8Bit = self:readByte()
        self.offset8Bit = 0
    end
    local ret = bit.band(bit.rshift(self.current8Bit, 7 - self.offset8Bit), 1) == 1
    self.offset8Bit = self.offset8Bit + 1
    return ret
end

function BinaryReader:checkBits()
    if self.offset8Bit ~= 0 then
        self.offset8Bit = 0
    end
end

return BinaryReader
