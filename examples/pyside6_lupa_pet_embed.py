"""PySide6 + lupa host for Live2D Rana via live2d_moc3_pet_embed.lua.

Run from the repository root:

    python examples/pyside6_lupa_pet_embed.py

Requirements:

    pip install PySide6 lupa

The lupa build must expose LuaJIT's `ffi` module.
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


class Live2DPetWidget(QOpenGLWidget):
    def __init__(self) -> None:
        super().__init__()
        self.setWindowTitle("Live2D Rana - Pet Embed - PySide6 + lupa")
        self.setMouseTracking(True)
        self.setMinimumSize(500, 700)

        self.lua: LuaRuntime | None = None
        self.pet: object | None = None
        self._load_model: object | None = None
        self._resize: object | None = None
        self._drag: object | None = None
        self._draw: object | None = None
        self._start_motion: object | None = None
        self._dispose: object | None = None
        self._last_time_ms = perf_counter() * 1000.0
        self._motion_index = 0

        self._timer = QTimer(self)
        self._timer.timeout.connect(self.update)
        self._timer.start(4)

    def initializeGL(self) -> None:
        os.chdir(ROOT)

        try:
            self.lua = LuaRuntime(unpack_returned_tuples=True, encoding=None)
            self.lua.execute(
                b'assert(require("ffi"), "lupa must be built with LuaJIT FFI")'
            )

            pet_module = self.lua.execute(
                b'return require("live2d_moc3_pet_embed")'
            )
            pet_module.init()

            self.pet = pet_module.new(self.width(), self.height())

            resource_streams = self.lua.table()
            for item in MODEL_DIR.rglob("*"):
                if item.is_file() and item.suffix.lower() != ".png":
                    key = item.relative_to(ROOT).as_posix().encode("utf-8")
                    resource_streams[key] = item.read_bytes()

            self._load_model = self.lua.eval(
                b"function(pet, model_path, w, h, opts) "
                b"return pet:load_model(model_path, w, h, opts) "
                b"end"
            )
            self._load_model(
                self.pet,
                MODEL_PATH.encode("utf-8"),
                self.width(),
                self.height(),
                self.lua.table_from({b"resource_streams": resource_streams}),
            )

            self._resize = self.lua.eval(
                b"function(pet, w, h) return pet:resize(w, h) end"
            )
            self._drag = self.lua.eval(
                b"function(pet, x, y) return pet:drag(x, y) end"
            )
            self._start_motion = self.lua.eval(
                b"function(pet, no) return pet:start_motion('Idle', no, 3) end"
            )
            self._draw = self.lua.eval(
                b"function(pet, w, h, time_ms) "
                b"return pet:draw({r=0.18, g=0.20, b=0.22, a=1.0, time_msec=time_ms}) "
                b"end"
            )
            self._dispose = self.lua.eval(
                b"function(pet) return pet:dispose() end"
            )
        except (LuaError, RuntimeError) as exc:
            self._show_error(str(exc))
            raise

    def resizeGL(self, width: int, height: int) -> None:
        if self.pet is not None and self._resize is not None:
            self._resize(self.pet, width, height)

    def paintGL(self) -> None:
        if self.pet is None or self._draw is None:
            return

        now_ms = perf_counter() * 1000.0
        self._last_time_ms = now_ms

        self._draw(self.pet, self.width(), self.height(), now_ms)

    def mouseMoveEvent(self, event) -> None:  # noqa: N802 - Qt override
        if self.pet is not None and self._drag is not None:
            pos = event.position()
            self._drag(self.pet, pos.x(), pos.y())
        super().mouseMoveEvent(event)

    def mousePressEvent(self, event) -> None:  # noqa: N802 - Qt override
        if event.button() == Qt.MouseButton.LeftButton:
            if self.pet is not None and self._start_motion is not None:
                self._motion_index = (self._motion_index + 1) % 9
                self._start_motion(self.pet, self._motion_index)
        super().mousePressEvent(event)

    def closeEvent(self, event) -> None:  # noqa: N802 - Qt override
        if self.pet is not None and self._dispose is not None:
            self._dispose(self.pet)
        super().closeEvent(event)

    def _show_error(self, message: str) -> None:
        QMessageBox.critical(
            self,
            "Live2D Pet Embed initialization failed",
            "Failed to initialize Live2D through pet embed + lupa.\n\n" + message,
        )


def main() -> int:
    if not (ROOT / MODEL_PATH).exists():
        print(f"Model not found: {ROOT / MODEL_PATH}", file=sys.stderr)
        return 1

    QSurfaceFormat.setDefaultFormat(_make_gl_format())

    app = QApplication(sys.argv)
    widget = Live2DPetWidget()
    widget.resize(500, 700)
    widget.show()
    return app.exec()


def _make_gl_format() -> QSurfaceFormat:
    fmt = QSurfaceFormat()
    fmt.setRenderableType(QSurfaceFormat.RenderableType.OpenGL)
    fmt.setProfile(QSurfaceFormat.OpenGLContextProfile.CompatibilityProfile)
    fmt.setVersion(2, 1)
    fmt.setDepthBufferSize(24)
    fmt.setStencilBufferSize(8)
    fmt.setSwapInterval(0)
    return fmt


if __name__ == "__main__":
    raise SystemExit(main())
