"""PySide6 + lupa host for the windowless Cubism 3 renderer.

Run from the repository root:

    python examples/pyside6_lupa_cubism3.py

Requirements:

    pip install PySide6 lupa

The lupa build must expose LuaJIT's `ffi` module. If your installed wheel uses
standard Lua instead of LuaJIT, this example cannot load the renderer because
the project depends on LuaJIT FFI.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path
from time import perf_counter

from PySide6.QtCore import QTimer, Qt
from PySide6.QtGui import QSurfaceFormat
from PySide6.QtOpenGLWidgets import QOpenGLWidget
from PySide6.QtWidgets import QApplication, QMessageBox
from lupa.luajit21 import LuaError, LuaRuntime


ROOT = Path(__file__).resolve().parents[1]
MODEL_PATH = "resources/Rana/adv_live2d_rana_003_live_01.model3.json"
MODEL_DIR = ROOT / "resources" / "Rana"


class Live2DWidget(QOpenGLWidget):
    def __init__(self) -> None:
        super().__init__()
        self.setWindowTitle("Live2D Rana - PySide6 + lupa")
        self.setMouseTracking(True)
        self.setMinimumSize(500, 700)

        self.lua: LuaRuntime | None = None
        self.embed = None
        self._load_model = None
        self._draw = None
        self._resize = None
        self._drag = None
        self._start_motion = None
        self._dispose = None
        self._last_time = perf_counter()
        self._motion_index = 0

        self._timer = QTimer(self)
        self._timer.timeout.connect(self.update)
        # --- 修改点 1 ---
        # 1000ms / 240fps = 4.16ms，这里取整设为 4 毫秒以达到最高 240FPS 的刷新率
        self._timer.start(4)

    def initializeGL(self) -> None:
        os.chdir(ROOT)

        try:
            self.lua = LuaRuntime(unpack_returned_tuples=True, encoding=None)
            self.lua.execute(b'assert(require("ffi"), "lupa must be built with LuaJIT FFI")')

            self.embed = self.lua.execute(b'return require("live2d_moc3_embed")')
            self._load_model = self.lua.eval(
                b"function(embed, model_path, opts, w, h) "
                b"local gl = require('live2d.gl_loader'); "
                b"gl.ensureExtensions(); "
                b"local renderer = embed.load_model(model_path, opts); "
                b"renderer:set_gl(gl); "
                b"gl.glEnable(0x0BE2); "
                b"if gl.glBlendFunc then gl.glBlendFunc(0x0302, 0x0303) end; "
                b"return renderer "
                b"end"
            )
            self._draw = self.lua.eval(
                b"function(embed, w, h, delta) "
                b"local gl = require('live2d.gl_loader'); "
                b"gl.glViewport(0, 0, w, h); "
                b"gl.glClearColor(0.18, 0.20, 0.22, 1.0); "
                b"gl.glClear(0x00004000 + 0x00000400); "
                b"embed.update(delta); "
                b"return embed.render(make_projection(embed, w, h)) "
                b"end"
            )
            self._resize = self.lua.eval(
                b"function(w, h) "
                b"local gl = require('live2d.gl_loader'); "
                b"return gl.glViewport(0, 0, w, h) "
                b"end"
            )
            self._drag = self.lua.eval(
                b"function(embed, x, y, w, h) "
                b"local nx = (x / math.max(w, 1)) * 2.0 - 1.0; "
                b"local ny = 1.0 - (y / math.max(h, 1)) * 2.0; "
                b"embed.set_parameter('ParamAngleX', nx * 30.0); "
                b"embed.set_parameter('ParamAngleY', ny * 30.0); "
                b"embed.set_parameter('ParamBodyAngleX', nx * 10.0); "
                b"return true "
                b"end"
            )
            self._start_motion = self.lua.eval(
                b"function(embed, no) return embed.start_motion('Idle', no, 1.0) end"
            )
            self._dispose = self.lua.eval(b"function(embed) return embed.dispose() end")
            self.lua.execute(
                b"local ffi = require('ffi'); "
                b"function make_projection(embed, w, h) "
                b"w = math.max(tonumber(w) or 1, 1); "
                b"h = math.max(tonumber(h) or 1, 1); "
                b"local canvas = embed.current():get_runtime().canvas; "
                b"local model_w = canvas.width / canvas.pixels_per_unit; "
                b"local model_h = canvas.height / canvas.pixels_per_unit; "
                b"local scale = math.min(w / model_w, h / model_h) * 0.8; "
                b"return ffi.new('float[16]', { "
                b"scale * 2.0 / w, 0, 0, 0, "
                b"0, scale * 2.0 / h, 0, 0, "
                b"0, 0, 1, 0, "
                b"0, 0, 0, 1 }) "
                b"end"
            )

            opts = self.lua.table()
            opts[b"resource_streams"] = _load_resource_streams(self.lua, MODEL_DIR)
            self._load_model(
                self.embed,
                MODEL_PATH.encode("utf-8"),
                opts,
                self.width(),
                self.height(),
            )
        except (LuaError, RuntimeError) as exc:
            self._show_error(str(exc))
            raise

    def resizeGL(self, width: int, height: int) -> None:
        if self._resize is not None:
            self._resize(width, height)

    def paintGL(self) -> None:
        if self.embed is None or self._draw is None:
            return

        now = perf_counter()
        delta = min(now - self._last_time, 0.1)
        self._last_time = now
        self._draw(self.embed, self.width(), self.height(), delta)

    def mouseMoveEvent(self, event) -> None:  # noqa: N802 - Qt override
        if self.embed is not None and self._drag is not None:
            pos = event.position()
            self._drag(self.embed, pos.x(), pos.y(), self.width(), self.height())
        super().mouseMoveEvent(event)

    def mousePressEvent(self, event) -> None:  # noqa: N802 - Qt override
        if event.button() == Qt.MouseButton.LeftButton:
            if self.embed is not None and self._start_motion is not None:
                self._motion_index = (self._motion_index + 1) % 9
                self._start_motion(self.embed, self._motion_index)
        super().mousePressEvent(event)

    def closeEvent(self, event) -> None:  # noqa: N802 - Qt override
        if self.embed is not None and self._dispose is not None:
            self._dispose(self.embed)
        super().closeEvent(event)

    def _show_error(self, message: str) -> None:
        QMessageBox.critical(
            self,
            "Live2D Cubism3 initialization failed",
            "Failed to initialize Cubism3 Live2D through lupa.\n\n" + message,
        )


def main() -> int:
    if not (ROOT / MODEL_PATH).exists():
        print(f"Model not found: {ROOT / MODEL_PATH}", file=sys.stderr)
        return 1

    QSurfaceFormat.setDefaultFormat(_make_gl_format())

    app = QApplication(sys.argv)
    widget = Live2DWidget()
    widget.resize(500, 700)
    widget.show()
    return app.exec()


def _load_resource_streams(lua: LuaRuntime, model_dir: Path):
    resource_streams = lua.table()
    for path in model_dir.rglob("*"):
        if path.is_file() and path.suffix.lower() != ".png":
            resource_streams[_repo_path(path).encode("utf-8")] = path.read_bytes()
    return resource_streams


def _repo_path(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def _make_gl_format() -> QSurfaceFormat:
    fmt = QSurfaceFormat()
    fmt.setRenderableType(QSurfaceFormat.RenderableType.OpenGL)
    fmt.setProfile(QSurfaceFormat.OpenGLContextProfile.CompatibilityProfile)
    fmt.setVersion(2, 1)
    fmt.setDepthBufferSize(24)
    fmt.setStencilBufferSize(8)
    # --- 修改点 2 ---
    # 将交换间隔（Swap Interval）从 1 改为 0，关闭垂直同步（V-Sync），允许突破显示器默认刷新率锁定。
    fmt.setSwapInterval(0)
    return fmt


if __name__ == "__main__":
    raise SystemExit(main())