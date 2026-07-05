-- MOC3 module init - exports all MOC3 types
-- Ported from Mocari src/moc3/mod.rs

local init = {}

init.header = require("live2d.cubism3.moc3.header")
init.offsets = require("live2d.cubism3.moc3.offsets")
init.counts = require("live2d.cubism3.moc3.counts")
init.parse = require("live2d.cubism3.moc3.parse")
init.ids = require("live2d.cubism3.moc3.ids")
init.canvas = require("live2d.cubism3.moc3.canvas")
init.parts = require("live2d.cubism3.moc3.parts")
init.keyform_bindings = require("live2d.cubism3.moc3.keyform_bindings")
init.art_meshes = require("live2d.cubism3.moc3.art_meshes")
init.keyforms = require("live2d.cubism3.moc3.keyforms")
init.deformers = require("live2d.cubism3.moc3.deformers")
init.drawable = require("live2d.cubism3.moc3.drawable")
init.glues = require("live2d.cubism3.moc3.glues")
init.draw_order_groups = require("live2d.cubism3.moc3.draw_order_groups")
init.offscreen = require("live2d.cubism3.moc3.offscreen")
init.mesh_build = require("live2d.cubism3.moc3.mesh_build")

return init
