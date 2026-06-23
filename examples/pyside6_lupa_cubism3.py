"""PySide6 + lupa host for the Cubism 3 (MOC3) renderer.

Run from the repository root:

    python examples/pyside6_lupa_cubism3.py

Requirements:

    pip install PySide6 lupa

The lupa build must expose LuaJIT's `ffi` module. If your installed wheel uses
standard Lua instead of LuaJIT, this example cannot load the renderer because
the project depends on LuaJIT FFI.
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

from PySide6.QtCore import QElapsedTimer, Qt, QTimer
from PySide6.QtGui import QSurfaceFormat
from PySide6.QtOpenGLWidgets import QOpenGLWidget
from PySide6.QtWidgets import QApplication, QMessageBox
from lupa.luajit21 import LuaRuntime, LuaError


ROOT = Path(__file__).resolve().parents[1]
MODEL_DIR = ROOT / "resources" / "Hiyori"
MODEL_JSON = MODEL_DIR / "Hiyori.model3.json"


class Cubism3Widget(QOpenGLWidget):
    def __init__(self) -> None:
        super().__init__()
        self.setWindowTitle("Live2D Cubism3 Hiyori - PySide6 + lupa")
        self.setMouseTracking(True)
        self.setMinimumSize(480, 720)

        self.lua: LuaRuntime | None = None
        self.runtime = None
        self.renderer = None
        self.textures = None
        self.motion_players: list[object] = []
        self.active_motion = None
        self._motion_index = -1

        self._render_frame = None
        self._resize_projection = None
        self._destroy_renderer = None
        self._set_parameter = None

        self._clock = QElapsedTimer()
        self._clock.start()
        self._last_time = 0.0

        self._timer = QTimer(self)
        self._timer.timeout.connect(self.update)
        self._timer.start(16)

    def initializeGL(self) -> None:
        os.chdir(ROOT)

        try:
            self.lua = LuaRuntime(unpack_returned_tuples=True, encoding=None)
            self.lua.execute(b'assert(require("ffi"), "lupa must be built with LuaJIT FFI")')
            self.lua.execute(b'package.path = package.path .. ";./?.lua;./?/init.lua"')

            self._cache_lua_functions()
            self.runtime = self._build_runtime()
            self.renderer = self._new_renderer()
            self.textures = self._load_texture_paths()
            self.motion_players = self._load_motion_players()
            self._resize_projection(self.runtime, self.width(), self.height())
            self._start_next_motion()
        except (LuaError, RuntimeError, OSError) as exc:
            self._show_error(str(exc))
            raise

    def resizeGL(self, width: int, height: int) -> None:
        if self.runtime is not None and self._resize_projection is not None:
            self._resize_projection(self.runtime, width, height)

    def paintGL(self) -> None:
        if self.runtime is None or self.renderer is None or self._render_frame is None:
            return

        now = self._clock.elapsed() / 1000.0
        delta = min(max(now - self._last_time, 0.0), 0.1)
        self._last_time = now

        motion_finished = self._render_frame(
            self.runtime,
            self.renderer,
            self.textures,
            self.active_motion,
            delta,
            self.width(),
            self.height(),
        )
        if motion_finished:
            self._start_next_motion()

    def mouseMoveEvent(self, event) -> None:  # noqa: N802 - Qt override
        if self.runtime is not None and self._set_parameter is not None:
            pos = event.position()
            x = (pos.x() / max(self.width(), 1) - 0.5) * 2.0
            y = (pos.y() / max(self.height(), 1) - 0.5) * -2.0
            self._set_parameter(self.runtime, b"ParamAngleX", x * 30.0)
            self._set_parameter(self.runtime, b"ParamAngleY", y * 30.0)
            self._set_parameter(self.runtime, b"ParamBodyAngleX", x * 10.0)
        super().mouseMoveEvent(event)

    def mousePressEvent(self, event) -> None:  # noqa: N802 - Qt override
        if event.button() == Qt.MouseButton.LeftButton:
            self._start_next_motion()
        super().mousePressEvent(event)

    def closeEvent(self, event) -> None:  # noqa: N802 - Qt override
        if self.renderer is not None and self._destroy_renderer is not None:
            self._destroy_renderer(self.renderer)
            self.renderer = None
        super().closeEvent(event)

    def _cache_lua_functions(self) -> None:
        assert self.lua is not None
        self._build_runtime_from_streams = self.lua.eval(
            b"function(model_json, moc_bytes, pose_json) "
            b"local model3 = require('live2d.cubism3.json.model3') "
            b"local pose3 = require('live2d.cubism3.json.pose3') "
            b"local moc3 = require('live2d.cubism3.moc3') "
            b"local Runtime = require('live2d.cubism3.runtime') "
            b"local model_data = assert(model3.parse(model_json)) "
            b"local pose_data = pose_json and assert(pose3.parse(pose_json)) or nil "
            b"local canvas = assert(moc3.canvas.parse(moc_bytes)) "
            b"local ids = assert(moc3.ids.parse(moc_bytes)) "
            b"local bindings = assert(moc3.keyform_bindings.parse(moc_bytes)) "
            b"local parts = assert(moc3.parts.parse(moc_bytes)) "
            b"local deformers = assert(moc3.deformers.parse(moc_bytes)) "
            b"local art_meshes = assert(moc3.art_meshes.parse(moc_bytes)) "
            b"local keyforms = assert(moc3.keyforms.parse(moc_bytes)) "
            b"local offscreen = assert(moc3.offscreen.parse(moc_bytes)) "
            b"return assert(Runtime.new(model_data, canvas, art_meshes, keyforms, "
            b"deformers, bindings, ids, offscreen, parts, pose_data)) "
            b"end"
        )
        self._new_renderer = self.lua.eval(
            b"function() "
            b"local gl = require('live2d.gl_loader') "
            b"gl.ensureExtensions() "
            b"return require('live2d.cubism3.opengl_renderer').new(gl) "
            b"end"
        )
        self._new_motion_player = self.lua.eval(
            b"function(motion_json) "
            b"local motion3 = require('live2d.cubism3.json.motion3') "
            b"local MotionPlayer = require('live2d.cubism3.motion') "
            b"return MotionPlayer.new(assert(motion3.parse(motion_json))) "
            b"end"
        )
        self._restart_motion = self.lua.eval(b"function(player) return player:restart() end")
        self._set_parameter = self.lua.eval(
            b"function(runtime, id, value) return runtime:set_parameter(id, value) end"
        )
        self._resize_projection = self.lua.eval(
            b"function(runtime, width, height) "
            b"local ffi = require('ffi') "
            b"local canvas = runtime.canvas "
            b"local model_w = canvas.width / canvas.pixels_per_unit "
            b"local model_h = canvas.height / canvas.pixels_per_unit "
            b"local scale = math.min(width / model_w, height / model_h) * 0.82 "
            b"runtime._projection = ffi.new('float[16]', { "
            b"scale * 2.0 / width, 0, 0, 0, "
            b"0, scale * 2.0 / height, 0, 0, "
            b"0, 0, 1, 0, "
            b"0, -0.10, 0, 1 }) "
            b"end"
        )
        self._render_frame = self.lua.eval(
            b"function(runtime, renderer, textures, motion, delta, width, height) "
            b"local gl = require('live2d.gl_loader') "
            b"gl.glViewport(0, 0, width, height) "
            b"gl.glEnable(0x0BE2) "
            b"gl.glClearColor(0.18, 0.20, 0.22, 1.0) "
            b"gl.glClear(0x00004000) "
            b"local finished = false "
            b"if motion then "
            b"motion:tick(delta) "
            b"motion:apply(runtime) "
            b"finished = motion:is_finished() "
            b"end "
            b"runtime:apply_pose(delta) "
            b"runtime:update_meshes() "
            b"renderer:render_meshes(runtime.meshes, textures, runtime._projection) "
            b"collectgarbage('step', 200) "
            b"return finished "
            b"end"
        )
        self._destroy_renderer = self.lua.eval(b"function(renderer) return renderer:destroy() end")

    def _build_runtime(self):
        model = _read_json(MODEL_JSON)
        moc_name = model["FileReferences"]["Moc"]
        pose_name = model["FileReferences"].get("Pose")
        pose_json = (MODEL_DIR / pose_name).read_bytes() if pose_name else None
        return self._build_runtime_from_streams(
            MODEL_JSON.read_bytes(),
            (MODEL_DIR / moc_name).read_bytes(),
            pose_json,
        )

    def _load_texture_paths(self):
        assert self.lua is not None
        model = _read_json(MODEL_JSON)
        texture_paths = self.lua.table()
        for index, rel_path in enumerate(model["FileReferences"].get("Textures", []), start=1):
            texture_paths[index] = str(MODEL_DIR / rel_path).encode("utf-8")
        return texture_paths

    def _load_motion_players(self) -> list[object]:
        model = _read_json(MODEL_JSON)
        motions = []
        for refs in model["FileReferences"].get("Motions", {}).values():
            for ref in refs:
                motion_path = MODEL_DIR / ref["File"]
                motions.append(self._new_motion_player(motion_path.read_bytes()))
        return motions

    def _start_next_motion(self) -> None:
        if not self.motion_players:
            self.active_motion = None
            return

        self._motion_index = (self._motion_index + 1) % len(self.motion_players)
        self.active_motion = self.motion_players[self._motion_index]
        self._restart_motion(self.active_motion)

    def _show_error(self, message: str) -> None:
        QMessageBox.critical(
            self,
            "Cubism3 initialization failed",
            "Failed to initialize Cubism3 through lupa.\n\n" + message,
        )


def main() -> int:
    if not MODEL_JSON.exists():
        print(f"Model not found: {MODEL_JSON}", file=sys.stderr)
        return 1

    QSurfaceFormat.setDefaultFormat(_make_gl_format())

    app = QApplication(sys.argv)
    widget = Cubism3Widget()
    widget.resize(480, 720)
    widget.show()
    return app.exec()


def _read_json(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as file:
        return json.load(file)


def _make_gl_format() -> QSurfaceFormat:
    fmt = QSurfaceFormat()
    fmt.setRenderableType(QSurfaceFormat.RenderableType.OpenGL)
    fmt.setProfile(QSurfaceFormat.OpenGLContextProfile.CompatibilityProfile)
    fmt.setVersion(2, 1)
    fmt.setDepthBufferSize(24)
    fmt.setStencilBufferSize(8)
    fmt.setSwapInterval(1)
    return fmt


if __name__ == "__main__":
    raise SystemExit(main())
