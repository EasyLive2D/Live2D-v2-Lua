-- Cubism3 module init - exports all types
local cubism3 = {}

cubism3.core = {
    ids = require("live2d.cubism3.core.ids"),
    math = require("live2d.cubism3.core.math"),
    interpolation = require("live2d.cubism3.core.interpolation"),
    parameters = require("live2d.cubism3.core.parameters"),
    blend = require("live2d.cubism3.core.blend"),
    keyforms = require("live2d.cubism3.core.keyforms"),
    deformers = require("live2d.cubism3.core.deformers"),
    art_mesh = require("live2d.cubism3.core.art_mesh"),
    physics = require("live2d.cubism3.core.physics"),
    update_order = require("live2d.cubism3.core.update_order"),
}

cubism3.json = {
    model3 = require("live2d.cubism3.json.model3"),
    cdi3 = require("live2d.cubism3.json.cdi3"),
    motion3 = require("live2d.cubism3.json.motion3"),
    physics3 = require("live2d.cubism3.json.physics3"),
    pose3 = require("live2d.cubism3.json.pose3"),
}

cubism3.moc3 = require("live2d.cubism3.moc3")

return cubism3
