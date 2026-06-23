"""PySide6 + lupa host for the Cubism 3 (MOC3) renderer (Hiyori model).

Run from the repository root:

    python examples/pyside6_lupa_cubism3.py

Requirements:

    pip install PySide6 lupa PyOpenGL

The lupa build must expose LuaJIT's `ffi` module. Cubism 3 rendering uses
GLSL shaders — the QOpenGLWidget provides a GL 2.1 compatibility context
via QSurfaceFormat.

IMPORTANT: lupa with encoding=None passes Python str as Lua userdata, not
as a Lua string. Always pass bytes (encode or read_bytes) when feeding data
into Lua functions like JSON parsers.

Architecture:
  +-- Python (PySide6) ----------------------------------+
  |  QOpenGLWidget  <- creates and owns OpenGL context    |
  |  QTimer(16ms)   <- drives render loop                 |
  |  Decodes PNG -> RGBA via QImage                       |
  |  Draws meshes via PyOpenGL (glDrawElements)           |
  +------------------------------------------------------+
                          | lupa |
  +-- Lua (LuaJIT) --------------------------------------+
  |  live2d.cubism3.json.*   <- JSON parsers              |
  |  live2d.cubism3.moc3.*   <- MOC3 binary parser        |
  |  live2d.cubism3.runtime  <- ModelRuntime state machine|
  |  live2d.cubism3.motion   <- MotionPlayer              |
  |  Returns 134 drawable meshes per frame                |
  +------------------------------------------------------+
"""

from __future__ import annotations

import ctypes
import math
import os
import sys
import time
from pathlib import Path

from PySide6.QtCore import QTimer, Qt
from PySide6.QtGui import QImage, QSurfaceFormat
from PySide6.QtOpenGLWidgets import QOpenGLWidget
from PySide6.QtWidgets import QApplication, QMessageBox
from lupa.luajit21 import LuaRuntime, LuaError

from OpenGL import GL
from OpenGL.GL import shaders

ROOT = Path(__file__).resolve().parents[1]
MODEL_BASE = Path("resources/Hiyori")

# ── GLSL shaders (1.20) ────────────────────────────────────────────────────

VERTEX_SHADER = """
#version 120
attribute vec2 a_position;
attribute vec2 a_uv;
attribute float a_opacity;
attribute vec3 a_multiply;
attribute vec3 a_screen;
varying vec2 v_uv;
varying float v_opacity;
varying vec3 v_multiply;
varying vec3 v_screen;
uniform mat4 u_projection;
void main() {
    gl_Position = u_projection * vec4(a_position, 0.0, 1.0);
    v_uv = a_uv;
    v_opacity = a_opacity;
    v_multiply = a_multiply;
    v_screen = a_screen;
}
"""

FRAGMENT_SHADER = """
#version 120
varying vec2 v_uv;
varying float v_opacity;
varying vec3 v_multiply;
varying vec3 v_screen;
uniform sampler2D u_texture;
void main() {
    vec4 tex = texture2D(u_texture, v_uv);
    vec3 blended = tex.rgb * v_multiply;
    blended = blended + v_screen * (1.0 - tex.rgb);
    gl_FragColor = vec4(blended, tex.a * v_opacity);
}
"""

_DRAW_ORDER_EPSILON = 0.001


def _draw_order_from_raw(raw: float) -> int:
    tr = raw + _DRAW_ORDER_EPSILON
    return max(0, min(1000, math.floor(tr) if tr >= 0 else math.ceil(tr)))


class Cubism3Widget(QOpenGLWidget):
    def __init__(self) -> None:
        super().__init__()
        self.setWindowTitle("Live2D Cubism3 Hiyori - PySide6 + lupa")
        self.setMouseTracking(True)
        self.setMinimumSize(400, 700)

        self.lua: LuaRuntime | None = None
        self.runtime = None

        self._update_meshes = None
        self._apply_pose = None
        self._tick_player = None
        self._apply_player = None
        self._is_player_finished = None
        self._restart_player = None
        self._reset_params = None
        self._reset_part_opacities = None

        self.shader_program = 0
        self.textures: list[tuple[int, int, int]] = []
        self.vbo = 0
        self.ibo = 0

        self.model_data = None
        self.motion_players: list = []
        self._motion_idx = 0
        self._motion_names: list[str] = []

        self._last_time = 0.0

        self._timer = QTimer(self)
        self._timer.timeout.connect(self.update)
        self._timer.start(16)

    # ══════════════════════════════════════════════════════════════════════
    # Initialization
    # ══════════════════════════════════════════════════════════════════════

    def initializeGL(self) -> None:
        os.chdir(ROOT)

        vs = shaders.compileShader(VERTEX_SHADER, GL.GL_VERTEX_SHADER)
        fs = shaders.compileShader(FRAGMENT_SHADER, GL.GL_FRAGMENT_SHADER)
        self.shader_program = shaders.compileProgram(vs, fs)
        self.vbo = GL.glGenBuffers(1)
        self.ibo = GL.glGenBuffers(1)

        try:
            self.lua = LuaRuntime(unpack_returned_tuples=True, encoding=None)
            self.lua.execute(
                b'package.path = package.path .. ";./?.lua;./?/init.lua"'
            )
            self.lua.execute(
                b'assert(require("ffi"), "lupa must be built with LuaJIT FFI")'
            )
            self._precompile_funcs()
            self._load_model()
            self._load_textures()
            self._load_motions()
        except (LuaError, RuntimeError, OSError, FileNotFoundError) as exc:
            self._show_error(str(exc))
            raise

        self._last_time = time.time()
        print(
            "[Cubism3] Loaded.  Meshes:",
            _lua_len(self.runtime.meshes),
            "  Motions:",
            len(self.motion_players),
        )

    # ══════════════════════════════════════════════════════════════════════
    # Lua helpers
    # ══════════════════════════════════════════════════════════════════════

    def _precompile_funcs(self) -> None:
        _E = self.lua.eval
        self._update_meshes = _E(b"function(rt) return rt:update_meshes() end")
        self._apply_pose = _E(b"function(rt, dt) return rt:apply_pose(dt) end")
        self._tick_player = _E(b"function(pl, dt) pl:tick(dt) end")
        self._apply_player = _E(b"function(pl, rt) pl:apply(rt) end")
        self._is_player_finished = _E(b"function(pl) return pl:is_finished() end")
        self._restart_player = _E(b"function(pl) pl:restart() end")
        self._reset_params = _E(b"function(rt) rt:reset_parameters() end")
        self._reset_part_opacities = _E(b"function(rt) rt:reset_part_opacities() end")

    # ══════════════════════════════════════════════════════════════════════
    # Model loading  (critical: pass bytes, never str, to Lua)
    # ══════════════════════════════════════════════════════════════════════

    def _load_model(self) -> None:
        base = ROOT / MODEL_BASE

        model3_mod = self.lua.execute(b'return require("live2d.cubism3.json.model3")')
        pose3_mod = self.lua.execute(b'return require("live2d.cubism3.json.pose3")')
        moc3_mod = self.lua.execute(b'return require("live2d.cubism3.moc3")')
        Runtime = self.lua.execute(b'return require("live2d.cubism3.runtime")')

        # Always read as bytes, never use .read_text() for Lua-bound data.
        # lupa (encoding=None) passes Python str as userdata, not Lua string.
        model_json = (base / "Hiyori.model3.json").read_bytes()
        moc_bytes = (base / "Hiyori.moc3").read_bytes()
        pose_json = (base / "Hiyori.pose3.json").read_bytes()

        self.model_data = model3_mod.parse(model_json)
        pose_data = pose3_mod.parse(pose_json)

        canvas = moc3_mod.canvas.parse(moc_bytes)
        ids = moc3_mod.ids.parse(moc_bytes)
        bindings = moc3_mod.keyform_bindings.parse(moc_bytes)
        parts = moc3_mod.parts.parse(moc_bytes)
        deforms = moc3_mod.deformers.parse(moc_bytes)
        art_meshes = moc3_mod.art_meshes.parse(moc_bytes)
        keyforms = moc3_mod.keyforms.parse(moc_bytes)
        offscreen = moc3_mod.offscreen.parse(moc_bytes)

        self.runtime = Runtime.new(
            self.model_data, canvas, art_meshes, keyforms,
            deforms, bindings, ids, offscreen, parts, pose_data,
        )
        if self.runtime is None:
            raise RuntimeError("ModelRuntime.new() returned nil")

    # ══════════════════════════════════════════════════════════════════════
    # Textures
    # ══════════════════════════════════════════════════════════════════════

    def _load_textures(self) -> None:
        base = ROOT / MODEL_BASE
        tex_table = self.model_data.file_references.textures
        for i in range(1, _lua_len(tex_table) + 1):
            tex_rel = _lua_str(tex_table[i])
            img_path = base / tex_rel
            width, height, data = _load_rgba_texture(img_path)

            tex_id = GL.glGenTextures(1)
            GL.glBindTexture(GL.GL_TEXTURE_2D, tex_id)
            GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_MIN_FILTER, GL.GL_LINEAR)
            GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_MAG_FILTER, GL.GL_LINEAR)
            GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_WRAP_S, GL.GL_CLAMP_TO_EDGE)
            GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_WRAP_T, GL.GL_CLAMP_TO_EDGE)
            GL.glTexImage2D(
                GL.GL_TEXTURE_2D, 0, GL.GL_RGBA,
                width, height, 0, GL.GL_RGBA, GL.GL_UNSIGNED_BYTE, data,
            )
            self.textures.append((tex_id, width, height))
            print(f"  Texture: {tex_rel} ({width}x{height})")

    # ══════════════════════════════════════════════════════════════════════
    # Motions
    # ══════════════════════════════════════════════════════════════════════

    def _load_motions(self) -> None:
        base = ROOT / MODEL_BASE
        motion3_mod = self.lua.execute(b'return require("live2d.cubism3.json.motion3")')
        MotionPlayer = self.lua.execute(b'return require("live2d.cubism3.motion")')

        motions_map = self.model_data.file_references.motions
        for group_name_lua, refs in _lua_items(motions_map):
            group_name = _lua_str(group_name_lua)
            for ref in _lua_ivalues(refs):
                motion_file = _lua_str(ref.File)
                motion_path = base / motion_file
                if not motion_path.exists():
                    continue
                motion_data = motion3_mod.parse(motion_path.read_bytes())
                player = MotionPlayer.new(motion_data)
                self.motion_players.append(player)
                self._motion_names.append(group_name)
                print(f"  Motion: [{group_name}] {motion_file}")

    # ══════════════════════════════════════════════════════════════════════
    # Resize
    # ══════════════════════════════════════════════════════════════════════

    def resizeGL(self, width: int, height: int) -> None:
        GL.glViewport(0, 0, width, height)

    # ══════════════════════════════════════════════════════════════════════
    # Paint
    # ══════════════════════════════════════════════════════════════════════

    def paintGL(self) -> None:
        now = time.time()
        if self._last_time == 0.0:
            self._last_time = now
        delta = min(now - self._last_time, 0.1)
        self._last_time = now

        if self.runtime is None:
            return

        # ── motion ────────────────────────────────────────────────────────
        if self.motion_players:
            player = self.motion_players[self._motion_idx % len(self.motion_players)]
            self._tick_player(player, delta)
            self._apply_player(player, self.runtime)
            if self._is_player_finished(player):
                self._motion_idx = (self._motion_idx + 1) % len(self.motion_players)
                self._reset_params(self.runtime)
                self._reset_part_opacities(self.runtime)

        # ── pose ──────────────────────────────────────────────────────────
        self._apply_pose(self.runtime, delta)

        # ── rebuild ───────────────────────────────────────────────────────
        self._update_meshes(self.runtime)

        # ── clear ─────────────────────────────────────────────────────────
        GL.glClearColor(0.18, 0.20, 0.22, 1.0)
        GL.glClear(GL.GL_COLOR_BUFFER_BIT)
        GL.glEnable(GL.GL_BLEND)

        # ── projection (orthographic, fit model to view) ─────────────────
        canvas = self.runtime.canvas
        model_w = canvas.width / canvas.pixels_per_unit
        model_h = canvas.height / canvas.pixels_per_unit
        scale = min(self.width() / model_w, self.height() / model_h) * 0.8
        sx = scale * 2.0 / self.width()
        sy = scale * 2.0 / self.height()
        projection = [
            sx, 0.0, 0.0, 0.0,
            0.0, sy, 0.0, 0.0,
            0.0, 0.0, 1.0, 0.0,
            0.0, 0.0, 0.0, 1.0,
        ]

        GL.glUseProgram(self.shader_program)

        loc_proj = GL.glGetUniformLocation(self.shader_program, "u_projection")
        GL.glUniformMatrix4fv(loc_proj, 1, GL.GL_FALSE, projection)

        loc_pos = GL.glGetAttribLocation(self.shader_program, "a_position")
        loc_uv = GL.glGetAttribLocation(self.shader_program, "a_uv")
        loc_opac = GL.glGetAttribLocation(self.shader_program, "a_opacity")
        loc_mult = GL.glGetAttribLocation(self.shader_program, "a_multiply")
        loc_scr = GL.glGetAttribLocation(self.shader_program, "a_screen")
        loc_tex = GL.glGetUniformLocation(self.shader_program, "u_texture")

        # ── draw-order sort ──────────────────────────────────────────────
        meshes = self.runtime.meshes
        n = _lua_len(meshes)
        order = [
            (_draw_order_from_raw(meshes[i].draw_order),
             meshes[i].render_order, i)
            for i in range(1, n + 1)
        ]
        order.sort(key=lambda x: (x[0], x[1], x[2]))

        # ── draw ─────────────────────────────────────────────────────────
        for _, _, idx in order:
            mesh = meshes[idx]
            if mesh.opacity <= 0.001:
                continue
            nv = _lua_len(mesh.vertices)
            ni = _lua_len(mesh.indices)
            if nv == 0 or ni == 0:
                continue
            self._draw_mesh(
                mesh, nv, ni, loc_pos, loc_uv, loc_opac, loc_mult, loc_scr, loc_tex,
            )

        GL.glUseProgram(0)

    # ══════════════════════════════════════════════════════════════════════

    def _draw_mesh(self, mesh, nv: int, ni: int,
                   a_pos, a_uv, a_opac, a_mult, a_scr, u_tex) -> None:
        STRIDE = 11
        verts = mesh.vertices
        inds = mesh.indices

        data = (ctypes.c_float * (nv * STRIDE))()
        for i in range(nv):
            v = verts[i + 1]
            off = i * STRIDE
            # Lua tables are 1-indexed: position[1]=x, position[2]=y
            pos = v.position
            uv = v.uv
            data[off + 0] = float(pos[1])
            data[off + 1] = float(pos[2])
            data[off + 2] = float(uv[1])
            data[off + 3] = float(uv[2])
            data[off + 4] = float(mesh.opacity)
            mc = mesh.multiply_color
            data[off + 5] = float(mc[1])
            data[off + 6] = float(mc[2])
            data[off + 7] = float(mc[3])
            sc = mesh.screen_color
            data[off + 8] = float(sc[1])
            data[off + 9] = float(sc[2])
            data[off + 10] = float(sc[3])

        idx_data = (ctypes.c_uint16 * ni)()
        for i in range(ni):
            idx_data[i] = int(inds[i + 1])

        flags = int(mesh.drawable_flags)
        if flags & 1:
            GL.glBlendFunc(GL.GL_SRC_ALPHA, GL.GL_ONE)
        elif flags & 2:
            GL.glBlendFunc(GL.GL_DST_COLOR, GL.GL_ONE_MINUS_SRC_ALPHA)
        else:
            GL.glBlendFunc(GL.GL_SRC_ALPHA, GL.GL_ONE_MINUS_SRC_ALPHA)

        ss = STRIDE * 4
        offset = ctypes.c_void_p

        GL.glBindBuffer(GL.GL_ARRAY_BUFFER, self.vbo)
        GL.glBufferData(GL.GL_ARRAY_BUFFER, ctypes.sizeof(data), data, GL.GL_DYNAMIC_DRAW)
        GL.glBindBuffer(GL.GL_ELEMENT_ARRAY_BUFFER, self.ibo)
        GL.glBufferData(GL.GL_ELEMENT_ARRAY_BUFFER, ctypes.sizeof(idx_data), idx_data, GL.GL_DYNAMIC_DRAW)

        if a_pos  >= 0:  GL.glEnableVertexAttribArray(a_pos);  GL.glVertexAttribPointer(a_pos,  2, GL.GL_FLOAT, GL.GL_FALSE, ss, offset(0))
        if a_uv   >= 0:  GL.glEnableVertexAttribArray(a_uv);   GL.glVertexAttribPointer(a_uv,   2, GL.GL_FLOAT, GL.GL_FALSE, ss, offset(8))
        if a_opac >= 0:  GL.glEnableVertexAttribArray(a_opac); GL.glVertexAttribPointer(a_opac, 1, GL.GL_FLOAT, GL.GL_FALSE, ss, offset(16))
        if a_mult >= 0:  GL.glEnableVertexAttribArray(a_mult); GL.glVertexAttribPointer(a_mult, 3, GL.GL_FLOAT, GL.GL_FALSE, ss, offset(20))
        if a_scr  >= 0:  GL.glEnableVertexAttribArray(a_scr);  GL.glVertexAttribPointer(a_scr,  3, GL.GL_FLOAT, GL.GL_FALSE, ss, offset(32))

        tex_idx = int(mesh.texture_index)
        if 0 <= tex_idx < len(self.textures):
            GL.glActiveTexture(GL.GL_TEXTURE0)
            GL.glBindTexture(GL.GL_TEXTURE_2D, self.textures[tex_idx][0])
            GL.glUniform1i(u_tex, 0)

        GL.glDrawElements(GL.GL_TRIANGLES, ni, GL.GL_UNSIGNED_SHORT, ctypes.c_void_p(0))

        if a_pos  >= 0: GL.glDisableVertexAttribArray(a_pos)
        if a_uv   >= 0: GL.glDisableVertexAttribArray(a_uv)
        if a_opac >= 0: GL.glDisableVertexAttribArray(a_opac)
        if a_mult >= 0: GL.glDisableVertexAttribArray(a_mult)
        if a_scr  >= 0: GL.glDisableVertexAttribArray(a_scr)

    # ══════════════════════════════════════════════════════════════════════
    # Input
    # ══════════════════════════════════════════════════════════════════════

    def mousePressEvent(self, event) -> None:
        if event.button() == Qt.MouseButton.LeftButton and self.motion_players:
            self._motion_idx = (self._motion_idx + 1) % len(self.motion_players)
            player = self.motion_players[self._motion_idx]
            self._restart_player(player)
            self._reset_params(self.runtime)
            self._reset_part_opacities(self.runtime)
            name = self._motion_names[self._motion_idx]
            print(f"  Motion: [{name}]")
        super().mousePressEvent(event)

    # ══════════════════════════════════════════════════════════════════════
    # Cleanup
    # ══════════════════════════════════════════════════════════════════════

    def closeEvent(self, event) -> None:
        if self.vbo:
            GL.glDeleteBuffers(1, ctypes.c_uint32(self.vbo))
        if self.ibo:
            GL.glDeleteBuffers(1, ctypes.c_uint32(self.ibo))
        for tex_id, _, _ in self.textures:
            GL.glDeleteTextures(1, ctypes.c_uint32(tex_id))
        if self.shader_program:
            GL.glDeleteProgram(self.shader_program)
        self.lua = None
        super().closeEvent(event)

    def _show_error(self, message: str) -> None:
        QMessageBox.critical(
            self,
            "Cubism3 initialization failed",
            "Failed to initialize Cubism 3 through lupa.\n\n" + message,
        )


# ── lupa / texture utilities ───────────────────────────────────────────────


def _lua_len(tbl) -> int:
    try:
        return len(tbl)
    except TypeError:
        return 0


def _lua_items(tbl):
    try:
        return list(tbl.items())
    except AttributeError:
        return []


def _lua_ivalues(tbl):
    i = 1
    while True:
        try:
            yield tbl[i]
            i += 1
        except (KeyError, IndexError, TypeError):
            break


def _lua_str(val) -> str:
    """Convert lupa Lua value (possibly bytes) to Python str."""
    if isinstance(val, bytes):
        return val.decode("utf-8")
    if val is None:
        return ""
    return str(val)


def _load_rgba_texture(path: Path) -> tuple[int, int, bytes]:
    image = QImage(str(path))
    if image.isNull():
        raise RuntimeError(f"Failed to load texture: {path}")
    image = image.convertToFormat(QImage.Format.Format_RGBA8888)
    width, height = image.width(), image.height()
    stride = image.bytesPerLine()
    row_size = width * 4
    data = bytes(image.constBits())
    if stride == row_size:
        return width, height, data[: row_size * height]
    rows = [data[y * stride : y * stride + row_size] for y in range(height)]
    return width, height, b"".join(rows)


def _make_gl_format() -> QSurfaceFormat:
    fmt = QSurfaceFormat()
    fmt.setRenderableType(QSurfaceFormat.RenderableType.OpenGL)
    fmt.setProfile(QSurfaceFormat.OpenGLContextProfile.CompatibilityProfile)
    fmt.setVersion(2, 1)
    fmt.setDepthBufferSize(24)
    fmt.setStencilBufferSize(8)
    fmt.setSwapInterval(1)
    return fmt


# ── Entry ──────────────────────────────────────────────────────────────────


def main() -> int:
    if not (ROOT / MODEL_BASE).exists():
        print(f"Model not found: {ROOT / MODEL_BASE}", file=sys.stderr)
        return 1

    QSurfaceFormat.setDefaultFormat(_make_gl_format())
    app = QApplication(sys.argv)
    widget = Cubism3Widget()
    widget.resize(400, 700)
    widget.show()
    return app.exec()


if __name__ == "__main__":
    raise SystemExit(main())
