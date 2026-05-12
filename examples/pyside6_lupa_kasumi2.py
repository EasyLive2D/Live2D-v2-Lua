"""PySide6 + lupa host for the windowless Live2D renderer.

Run from the repository root:

    python examples/pyside6_lupa_kasumi2.py

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

from PySide6.QtCore import QTimer, Qt
from PySide6.QtGui import QSurfaceFormat
from PySide6.QtOpenGLWidgets import QOpenGLWidget
from PySide6.QtWidgets import QApplication, QMessageBox
from lupa.luajit21 import LuaRuntime, LuaError


ROOT = Path(__file__).resolve().parents[1]
MODEL_PATH = "resources/kasumi2/kasumi2.model.json"


class Live2DWidget(QOpenGLWidget):
    def __init__(self) -> None:
        super().__init__()
        self.setWindowTitle("Live2D kasumi2 - PySide6 + lupa")
        self.setMouseTracking(True)
        self.setMinimumSize(400, 650)

        self.lua: LuaRuntime | None = None
        self.embed = None
        self._draw = None
        self._resize = None
        self._drag = None
        self._start_motion = None
        self._motion_index = 0

        self._timer = QTimer(self)
        self._timer.timeout.connect(self.update)
        self._timer.start(16)

    def initializeGL(self) -> None:
        os.chdir(ROOT)

        try:
            self.lua = LuaRuntime(unpack_returned_tuples=True)
            self.lua.execute('assert(require("ffi"), "lupa must be built with LuaJIT FFI")')

            self.embed = self.lua.execute('return require("live2d_embed")')
            self._draw = self.lua.eval("function(embed) return embed.draw() end")
            self._resize = self.lua.eval("function(embed, w, h) return embed.resize(w, h) end")
            self._drag = self.lua.eval("function(embed, x, y) return embed.drag(x, y) end")
            self._start_motion = self.lua.eval(
                "function(embed, name, no) "
                "return embed.start_motion(name, no, embed.MotionPriority.FORCE) "
                "end"
            )

            self.embed.load_model(MODEL_PATH, self.width(), self.height())
        except (LuaError, RuntimeError) as exc:
            self._show_error(str(exc))
            raise

    def resizeGL(self, width: int, height: int) -> None:
        if self.embed is not None and self._resize is not None:
            self._resize(self.embed, width, height)

    def paintGL(self) -> None:
        if self.embed is not None and self._draw is not None:
            self._draw(self.embed)

    def mouseMoveEvent(self, event) -> None:  # noqa: N802 - Qt override
        if self.embed is not None and self._drag is not None:
            pos = event.position()
            self._drag(self.embed, pos.x(), pos.y())
        super().mouseMoveEvent(event)

    def mousePressEvent(self, event) -> None:  # noqa: N802 - Qt override
        if event.button() == Qt.MouseButton.LeftButton:
            # kasumi2 usually has idle motions preloaded. Cycling the index makes
            # clicks visible without needing a Lua-side motion-name enumerator.
            if self.embed is not None and self._start_motion is not None:
                self._motion_index = (self._motion_index + 1) % 3
                self._start_motion(self.embed, "idle", self._motion_index)
        super().mousePressEvent(event)

    def closeEvent(self, event) -> None:  # noqa: N802 - Qt override
        if self.embed is not None:
            self.embed.dispose()
        super().closeEvent(event)

    def _show_error(self, message: str) -> None:
        QMessageBox.critical(
            self,
            "Live2D initialization failed",
            "Failed to initialize Live2D through lupa.\n\n" + message,
        )


def main() -> int:
    if not (ROOT / MODEL_PATH).exists():
        print(f"Model not found: {ROOT / MODEL_PATH}", file=sys.stderr)
        return 1

    QSurfaceFormat.setDefaultFormat(_make_gl_format())

    app = QApplication(sys.argv)
    widget = Live2DWidget()
    widget.resize(400, 650)
    widget.show()
    return app.exec()


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
