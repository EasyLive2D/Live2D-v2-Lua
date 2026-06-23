# Embedding Live2D Cubism 3 (MOC3) in Python

[中文](Embedded2PythonCubism3_cn.md) | [日本語](Embedded2PythonCubism3_jp.md)

## Architecture Overview

```
Python GUI (PySide6 / PyQt6 / wxPython etc.)
  └─ QOpenGLWidget / GL canvas          ← creates and owns OpenGL context
       ├─ Initialization Phase
       │    ├─ Load Hiyori.model3.json                    ← Python reads + passes to Lua
       │    ├─ Load Hiyori.moc3 binary                    ← Python reads + passes to Lua
       │    ├─ Load textures (PNG → RGBA via QImage)      ← Python side
       │    ├─ Load motions / pose JSON files             ← Python reads + passes to Lua
       │    └─ Build ModelRuntime in Lua                   ← lupa LuaRuntime
       │
       ├─ Per-frame Update
       │    ├─ Tick motion player (delta time)
       │    ├─ Apply motion → runtime parameters
       │    ├─ Apply pose → part opacities
       │    └─ runtime:update_meshes()
       │
       ├─ Render
       │    ├─ Pass mesh list + texture IDs + projection matrix
       │    └─ OpenGL shader draws all 134 meshes
       │
       └─ QTimer(16ms)           ← drives refresh loop
```

**Core concept**: The Python side manages file I/O and texture decoding. The Lua side handles all Cubism 3 data processing — MOC3 binary parsing, parameter evaluation, deformer composition, and mesh generation. The OpenGL renderer handles drawing.

## Prerequisites

### 1. LuaJIT Runtime

This project depends on LuaJIT `ffi`. **Standard Lua interpreters will not work**.

| Approach | Library | Principle | Recommendation |
|----------|---------|-----------|----------------|
| lupa (LuaJIT build) | `pip install lupa` | `import lupa.luajit21` | ★★★ Recommended |
| ctypes + luajit.dll | System `luajit-2.1.dll` | ctypes loads DLL, calls Lua C API | ★★☆ Fallback |

### 2. OpenGL Widget

The Python GUI must provide an OpenGL-capable widget:
- **PySide6** / **PyQt6**: `QOpenGLWidget` (used in this guide)
- **wxPython**: `wx.GLCanvas`

> ⚠️ The Cubism 3 renderer uses GLSL shaders (GL `#version 120`). A GL 2.1+ context is required.

### 3. Dependency Installation

```bash
pip install PySide6 lupa
```

> **Critical**: The lupa wheel must be compiled against LuaJIT. Verify with:

```python
lua = LuaRuntime()
assert lua.execute(b'return require("ffi")'), "lupa must be built with LuaJIT FFI"
```

---

## Cubism 3 API Reference

The Lua module structure:

```
live2d.cubism3.
  init.lua                    # module entry
  core/                       # math, interpolation, deformers, physics
  json/                       # model3, motion3, physics3, pose3, cdi3
  moc3/                       # MOC3 binary parsing (14 sections)
  runtime.lua                 # ModelRuntime
  motion.lua                  # MotionPlayer
  opengl_renderer.lua         # OpenGLRenderer
```

### Loading a Model

```python
import os
from pathlib import Path
from lupa.luajit21 import LuaRuntime

lua = LuaRuntime(unpack_returned_tuples=True, encoding=None)
lua.execute(b'package.path = package.path .. ";./?.lua;./?/init.lua"')

# Load modules
ModelRuntime = lua.execute(b'return require("live2d.cubism3.runtime")')
model3       = lua.execute(b'return require("live2d.cubism3.json.model3")')
pose3        = lua.execute(b'return require("live2d.cubism3.json.pose3")')
motion3      = lua.execute(b'return require("live2d.cubism3.json.motion3")')
MotionPlayer = lua.execute(b'return require("live2d.cubism3.motion")')
moc3         = lua.execute(b'return require("live2d.cubism3.moc3")')

# Read model files
base = Path("resources/Hiyori")
model_json = (base / "Hiyori.model3.json").read_text()
moc_bytes  = (base / "Hiyori.moc3").read_bytes()
pose_json  = (base / "Hiyori.pose3.json").read_text()

# Parse JSON
model_data = model3.parse(model_json)
pose_data  = pose3.parse(pose_json)

# Parse MOC3 binary
canvas     = moc3.canvas.parse(moc_bytes)
ids        = moc3.ids.parse(moc_bytes)
bindings   = moc3.keyform_bindings.parse(moc_bytes)
parts      = moc3.parts.parse(moc_bytes)
deformers  = moc3.deformers.parse(moc_bytes)
art_meshes = moc3.art_meshes.parse(moc_bytes)
keyforms   = moc3.keyforms.parse(moc_bytes)
offscreen  = moc3.offscreen.parse(moc_bytes)

# Build runtime
runtime = ModelRuntime.new(
    model_data, canvas, art_meshes, keyforms,
    deformers, bindings, ids, offscreen, parts, pose_data
)
```

### Parameter Control

```python
# Get parameter index by name
idx = runtime:parameter_index_of("ParamAngleX")
if idx is not None:
    runtime:set_parameter_by_index(idx, 0.5)

# Set by string ID
runtime:set_parameter("ParamEyeLOpen", 0.8)

# Get current values
params = runtime.parameter_values  # Lua table, iterable from Python

# Reset to defaults
runtime:reset_parameters()
```

### Motion Playback

```python
# Load a motion
motion_json = (base / "motions/Hiyori_m01.motion3.json").read_text()
motion_data = motion3.parse(motion_json)
player = MotionPlayer.new(motion_data)

# Per-frame:
player:tick(delta_seconds)
player:apply(runtime)
runtime:update_meshes()

# Check status
if player:is_finished():
    player:restart()
```

### Rendering

```python
# Setup OpenGL context, then:

# Load textures
for i, tex_rel in enumerate(model_data.file_references.textures):
    tex_path = base / tex_rel
    # Decode PNG to RGBA (QImage, PIL, etc.)
    rgba = decode_png_to_rgba(tex_path)
    gl.glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, w, h, 0, GL_RGBA, GL_UNSIGNED_BYTE, rgba)

# Per-frame render:
meshes = runtime.meshes  # Lua table of 134 Moc3DrawableMesh
for mesh_idx in range(len(meshes)):
    mesh = meshes[mesh_idx + 1]  # Lua 1-indexed
    if mesh.opacity > 0.001:
        draw_mesh(mesh, projection_matrix)
```

### Mesh Data Structure

Each `Moc3DrawableMesh` contains:

| Field | Type | Description |
|-------|------|-------------|
| `texture_index` | int | Index into texture array (0 or 1 for Hiyori) |
| `drawable_flags` | int | Blend mode + mask invert flags |
| `opacity` | float | Final computed opacity (0.0–1.0) |
| `draw_order` | float | Raw draw order from model |
| `render_order` | int | Resolved render order |
| `multiply_color` | `{r,g,b}` | Multiply blend color |
| `screen_color` | `{r,g,b}` | Screen blend color |
| `vertices` | table | Array of `{position={x,y}, uv={u,v}}` |
| `indices` | table | Array of uint16 triangle indices |
| `masks` | table | Array of clipping mask IDs |

### Blend Modes

| Flag bit | Blend Mode | GL Blend Setup |
|----------|-----------|----------------|
| bit 0 | Additive | `glBlendFunc(GL_SRC_ALPHA, GL_ONE)` |
| bit 1 | Multiplicative | `glBlendFunc(GL_DST_COLOR, GL_ONE_MINUS_SRC_ALPHA)` |
| neither | Normal | `glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)` |

---

## Complete lupa Integration Example

```python
import os
from pathlib import Path
from lupa.luajit21 import LuaRuntime

from PySide6.QtCore import QTimer
from PySide6.QtGui import QImage
from PySide6.QtOpenGLWidgets import QOpenGLWidget

ROOT = Path(__file__).resolve().parents[1]
MODEL_PATH = "resources/Hiyori"

class Cubism3Widget(QOpenGLWidget):
    def initializeGL(self):
        os.chdir(ROOT)

        self.lua = LuaRuntime(unpack_returned_tuples=True, encoding=None)
        self.lua.execute(
            b'package.path = package.path .. ";./?.lua;./?/init.lua"'
        )

        # Cache frequently called Lua functions
        self._runtime_new = self.lua.eval(
            b"function(md,c,am,kf,df,bd,ids,off,prt,ps)"
            b" return require('live2d.cubism3.runtime').new("
            b"  md,c,am,kf,df,bd,ids,off,prt,ps) end"
        )
        self._update_meshes = self.lua.eval(
            b"function(rt) return rt:update_meshes() end"
        )
        self._apply_pose = self.lua.eval(
            b"function(rt,dt) return rt:apply_pose(dt) end"
        )

        # Load model (see section above)
        self.runtime = self._build_runtime()

        # Setup textures
        self.textures = self._load_textures()

        # Motion players
        self.motion_players = self._load_motions()

        # Timer
        self.timer = QTimer()
        self.timer.timeout.connect(self.update)
        self.timer.start(16)

    def _build_runtime(self):
        base = Path(MODEL_PATH)
        model3 = self.lua.execute(b'return require("live2d.cubism3.json.model3")')
        pose3  = self.lua.execute(b'return require("live2d.cubism3.json.pose3")')
        moc3   = self.lua.execute(b'return require("live2d.cubism3.moc3")')

        model_data = model3.parse((base / "Hiyori.model3.json").read_text())
        moc_bytes  = (base / "Hiyori.moc3").read_bytes()
        pose_data  = pose3.parse((base / "Hiyori.pose3.json").read_text())

        canvas     = moc3.canvas.parse(moc_bytes)
        ids        = moc3.ids.parse(moc_bytes)
        bindings   = moc3.keyform_bindings.parse(moc_bytes)
        parts      = moc3.parts.parse(moc_bytes)
        deformers  = moc3.deformers.parse(moc_bytes)
        art_meshes = moc3.art_meshes.parse(moc_bytes)
        keyforms   = moc3.keyforms.parse(moc_bytes)
        offscreen  = moc3.offscreen.parse(moc_bytes)

        return self._runtime_new(
            model_data, canvas, art_meshes, keyforms,
            deformers, bindings, ids, offscreen, parts, pose_data
        )

    def _load_textures(self):
        base = Path(MODEL_PATH)
        textures = []
        for tex_rel in ["Hiyori.2048/texture_00.png", "Hiyori.2048/texture_01.png"]:
            img = QImage(str(base / tex_rel)).convertToFormat(QImage.Format_RGBA8888)
            ptr = img.constBits()
            # Upload to OpenGL...
        return textures

    def paintGL(self):
        import OpenGL.GL as gl
        gl.glClear(GL_COLOR_BUFFER_BIT)

        # Apply motion
        if self.active_motion:
            self.active_motion:tick(16/1000)
            self.active_motion:apply(self.runtime)

        # Apply pose fade
        self._apply_pose(self.runtime, 16/1000)

        # Regenerate meshes
        self._update_meshes(self.runtime)

        # Draw meshes (sorted by draw_order, then render_order)
        meshes = self.runtime.meshes
        for i in range(1, len(meshes) + 1):
            mesh = meshes[i]
            if mesh.opacity > 0.001:
                self._draw_mesh(mesh)
```

---

## Key Differences from Cubism 2.1

| Aspect | Cubism 2.1 | Cubism 3 |
|--------|-----------|----------|
| Model format | `.moc` (binary v2) | `.moc3` (binary v3/v4/v5) |
| Config format | `.model.json` (v1) | `.model3.json` (v3) |
| Motions | `.mtn` (binary) | `.motion3.json` (JSON) |
| Art meshes | ~80 | 134 (Hiyori) |
| Deformers | Rotation only | Warp + Rotation |
| Keyforms | Per-part | Per-art-mesh with color blending |
| Renderer | Fixed-function GL | GLSL shader (#version 120) |
| Embed module | `live2d_embed.lua` | Direct `live2d.cubism3.*` API |
| Texture count | 1 | 2+ |

---

## Troubleshooting

### `require("ffi")` fails in lupa
Your lupa is compiled against standard Lua, not LuaJIT. Reinstall: `pip install lupa --force-reinstall` (ensure your environment has LuaJIT development headers).

### Module not found
Ensure `package.path` is set and the working directory is the repo root. Lupa does not inherit Lua's search paths by default.

### Vertices look corrupted (stretched / flipped)
The renderer applies Y-axis flip (`-vertex.y`) to convert from Live2D coordinate system (Y-up) to OpenGL (Y-up screen). Ensure your projection matrix is set correctly.

### Parameter changes have no visual effect
Some parameters (like `ParamAngleX`) affect deformer positions, not opacities. Visual changes depend on which meshes the deformer affects. Check `runtime:update_meshes()` is called after parameter changes.
