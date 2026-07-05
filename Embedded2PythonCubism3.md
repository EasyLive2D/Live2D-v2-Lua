# Embedding Live2D Cubism 3 (MOC3) in Python

[中文](Embedded2PythonCubism3_cn.md) | [日本語](Embedded2PythonCubism3_jp.md)

## Architecture Overview

```
Python GUI (PySide6 / PyQt6 / wxPython etc.)
  └─ QOpenGLWidget / GL canvas          ← creates and owns OpenGL context
       ├─ Initialization Phase
       │    ├─ Create Renderer via live2d_moc3_embed.load_model()
       │    │    ├─ Python reads model3.json / moc3 / textures
       │    │    ├─ Set resource_streams for in-memory file resolution
       │    │    └─ Lua internally parses MOC3, builds ModelRuntime
       │    ├─ Load textures (PNG → RGBA via QImage)           ← Python side
       │    └─ Set GL table via renderer:set_gl(gl)
       │
       ├─ Per-frame Update
       │    ├─ renderer:start_motion(group, no)                ← queue motions
       │    ├─ renderer:set_expression(name)                   ← queue expressions
       │    ├─ renderer:set_parameter(id, value)               ← drive params
       │    └─ renderer:update(delta_seconds)                  ← tick all + rebuild meshes
       │
       ├─ Render
       │    └─ renderer:render(projection, texture_paths)      ← OpenGL draw call
       │
       └─ QTimer(16ms)           ← drives refresh loop
```

**Core concept**: The `live2d_moc3_embed.lua` module wraps the entire Cubism 3 pipeline into a single `Renderer` object. Python only manages file I/O, texture decoding, and the OpenGL context. All Cubism logic — MOC3 parsing, parameter evaluation, deformer composition, motion/expression playback, pose application, mesh generation, and OpenGL draw calls — is handled by the Lua renderer internally.

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

## Embed API Reference

The single entry point is `live2d_moc3_embed.lua`. It provides a `Renderer` class (returned as a table by `require`) and module-level convenience functions that operate on a global "current" renderer.

```
live2d_moc3_embed.lua
  Renderer                        ← instance returned by embed.new() / embed.load_model()
  embed.new(opts)                 ← create Renderer without loading
  embed.load_model(path, opts)    ← create + load in one call (sets as "current")
  embed.current()                 ← get the "current" renderer
  embed.update(dt)                ← update current
  embed.get_meshes()              ← get meshes from current
  embed.set_parameter(id, val)    ← set param on current
  embed.start_motion(g, n, w)     ← start motion on current
  embed.clear_motions()           ← clear current
  embed.set_expression(name, w)   ← set expression on current
  embed.clear_expressions()       ← clear current
  embed.render(proj, tex_paths)   ← render current
  embed.dispose()                 ← dispose current
```

### Creating a Renderer

```python
from lupa.luajit21 import LuaRuntime

lua = LuaRuntime(unpack_returned_tuples=True, encoding=None)
lua.execute(b'package.path = package.path .. ";./?.lua;./?/init.lua"')

embed = lua.execute(b'return require("live2d_moc3_embed")')

# Option A: Create and load in one call
renderer = embed.load_model("resources/Hiyori/Hiyori.model3.json")

# Option B: Create first, then load
renderer = embed.new()
renderer:load_model("resources/Hiyori/Hiyori.model3.json")
```

The `load_model()` method:
- Reads `model3.json` → extracts `FileReferences`
- Reads `.moc3` binary → parses all 14 MOC3 sections
- Reads `.pose3.json` if present
- Builds a `ModelRuntime` internally
- Stores texture paths from `FileReferences.Textures`

### Resource Streams (In-Memory Loading)

Instead of reading files from disk, Python can pre-load data into memory and register it as resource streams. This lets the Lua side resolve files from Python-side byte buffers without touching disk.

```python
import json
from pathlib import Path

base = Path("resources/Hiyori")

renderer = embed.new({"resourceStreams": {
    "Hiyori.model3.json":     (base / "Hiyori.model3.json").read_text(),
    "Hiyori.moc3":            (base / "Hiyori.moc3").read_bytes(),
    "Hiyori.pose3.json":      (base / "Hiyori.pose3.json").read_text(),
    "motions/Hiyori_m01.motion3.json": (base / "motions/Hiyori_m01.motion3.json").read_text(),
}})

renderer:load_model("Hiyori.model3.json")
```

The renderer resolves file paths against `resource_streams` first, then falls back to disk. Stream values can be:
- Raw string/bytes
- A zero-argument function returning the data
- A table with `.data` or `.bytes` or `[1]` fields

### Parameter Control

```python
# By string ID
renderer:set_parameter("ParamAngleX", 30.0)            # raw value
renderer:set_parameter_normalized("ParamEyeLOpen", 0.8) # normalized 0-1

# By index
renderer:set_parameter_by_index(0, 15.0)

# Read current values
value = renderer:get_parameter("ParamAngleX")           # raw
value = renderer:get_parameter_normalized("ParamAngleX") # 0-1
value = renderer:get_parameter_by_index(0)

# Parameter metadata
info = renderer:get_parameter_info("ParamAngleX")
print(info.id, info.minimum, info.maximum, info.default)

# Reset all to defaults
renderer:reset_parameters()
```

**Parameter Overrides** — applied *after* motions and expressions, useful for blending or additive offsets:

```python
renderer:set_parameter_override("ParamEyeLOpen", 1.0)
renderer:set_parameter_override_normalized("ParamMouthOpenY", 0.5)
renderer:clear_parameter_override("ParamEyeLOpen")
renderer:clear_parameter_overrides()  # clear all
```

### Part Opacity Control

```python
renderer:set_part_opacity("PartArmL", 0.5)
renderer:set_part_opacity_by_index(0, 1.0)
renderer:reset_part_opacities()
```

### Motion Playback

Motions are organized by groups (e.g. `"Idle"`, `"TapBody"`) and indexed from 0 within each group, matching the `model3.json` `FileReferences.Motions` structure.

```python
# Start a motion (group name, motion index, optional weight 0-1)
renderer:start_motion("Idle", 0, 1.0)

# Start multiple motions simultaneously
renderer:start_motion("Idle", 0)
renderer:start_motion("TapBody", 2, 0.5)

# Clear all playing motions
renderer:clear_motions()
```

Motions are parsed and cached automatically on first use. Finished motions are automatically removed during `update()`.

### Expression Playback

```python
# By name (from FileReferences.Expressions)
renderer:set_expression("f01", 1.0)

# By index
renderer:set_expression(0)

# Clear all expressions (restores base parameter values)
renderer:clear_expressions()
```

Expressions use the `ExpressionManager` internally, supporting Add/Multiply/Overwrite blend modes as defined in `.exp3.json` files. Fade times from `FadeInTime`/`FadeOutTime` are honored; negative values mean "inherit model default."

### Per-Frame Update

```python
def on_frame(delta_seconds: float):
    # This single call:
    #   1. Ticks all active motion players
    #   2. Applies motion parameter changes to runtime
    #   3. Ticks expression manager
    #   4. Applies expression blends to runtime
    #   5. Applies parameter overrides
    #   6. Applies pose fade (part opacities)
    #   7. Rebuilds meshes (deformer composition + vertex generation)
    renderer:update(delta_seconds)
```

### Accessing Meshes

```python
meshes = renderer:get_meshes()  # Lua table, 1-indexed
for i in range(1, len(meshes) + 1):
    mesh = meshes[i]
    print(f"mesh[{i}]: tex={mesh.texture_index}, opacity={mesh.opacity}, "
          f"verts={len(mesh.vertices)}, indices={len(mesh.indices)}")
```

### Mesh Data Structure

Each `Moc3DrawableMesh` contains:

| Field | Type | Description |
|-------|------|-------------|
| `texture_index` | int | Index into texture array |
| `drawable_flags` | int | Blend mode + mask invert flags |
| `opacity` | float | Final computed opacity (0.0–1.0) |
| `draw_order` | float | Interpolated draw order from keyforms |
| `render_order` | int | MOC3-specified render order (slot 87) |
| `multiply_color` | `{r,g,b,a}` | Multiply blend color (premultiplied) |
| `screen_color` | `{r,g,b,a}` | Screen blend color (premultiplied) |
| `vertices` | table | Array of `{position={x,y}, uv={u,v}}` |
| `indices` | table | Array of uint16 triangle indices |
| `masks` | table | Array of clipping mask drawable IDs |

### Rendering

```python
# Once during GL initialization:
renderer:set_gl(gl_table)  # pass the PyOpenGL module or equivalent GL binding

# Upload textures to OpenGL (Python side):
texture_paths = renderer:get_texture_paths()  # returns resolved absolute paths
for i, path in enumerate(texture_paths):
    rgba = decode_png_to_rgba(path)
    gl.glBindTexture(GL_TEXTURE_2D, texture_ids[i])
    gl.glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, w, h, 0, GL_RGBA, GL_UNSIGNED_BYTE, rgba)

# Per-frame render:
projection = compute_ortho_matrix(w, h)
renderer:render(projection, texture_paths)
```

`render()` handles:
- Sorting draw calls by `render_order` (primary) and `draw_order` (tiebreaker)
- Clipping mask setup (stencil buffer)
- Blend mode selection (normal / additive / multiplicative)
- Shader uniform upload (projection, base color, multiply/screen colors)

### Blend Modes

| Flag bit | Blend Mode | GL Blend Setup |
|----------|-----------|----------------|
| bit 0 | Additive | `glBlendFunc(GL_ONE, GL_ONE)` |
| bit 1 | Multiplicative | `glBlendFunc(GL_DST_COLOR, GL_ONE_MINUS_SRC_ALPHA)` |
| neither | Normal | `glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA)` |

> The renderer uses premultiplied alpha: fragment output is `vec4(rgb * alpha, alpha)`, and blend equations account for this.

### Cleanup

```python
renderer:dispose()    # clears runtime, caches, texture refs, triggers GC
```

---

## Complete PySide6 Integration Example

```python
import os
from pathlib import Path
from lupa.luajit21 import LuaRuntime

from PySide6.QtCore import QTimer
from PySide6.QtGui import QImage
from PySide6.QtOpenGLWidgets import QOpenGLWidget

ROOT = Path(__file__).resolve().parents[1]
MODEL_PATH = "resources/Hiyori"
MODEL_BASE = ROOT / MODEL_PATH

class Cubism3Widget(QOpenGLWidget):
    def initializeGL(self):
        os.chdir(ROOT)

        self.lua = LuaRuntime(unpack_returned_tuples=True, encoding=None)
        self.lua.execute(
            b'package.path = package.path .. ";./?.lua;./?/init.lua"'
        )
        self.embed = self.lua.execute(
            b'return require("live2d_moc3_embed")'
        )

        # Pre-load model files as resource streams (no disk I/O during Lua execution)
        self.renderer = self.embed.new({"resourceStreams": {
            "Hiyori.model3.json": (MODEL_BASE / "Hiyori.model3.json").read_text(),
            "Hiyori.moc3":        (MODEL_BASE / "Hiyori.moc3").read_bytes(),
            "Hiyori.pose3.json":  (MODEL_BASE / "Hiyori.pose3.json").read_text(),
        }})
        self.renderer:load_model("Hiyori.model3.json")

        # Setup GL
        import OpenGL.GL as gl
        self.renderer:set_gl(gl)  # pass PyOpenGL module as the GL binding

        # Load textures
        self.texture_ids = {}
        for i, tex_path in enumerate(self.renderer:get_texture_paths()):
            img = QImage(tex_path).convertToFormat(QImage.Format_RGBA8888)
            self.texture_ids[i] = gl.glGenTextures(1)
            gl.glBindTexture(gl.GL_TEXTURE_2D, self.texture_ids[i])
            gl.glTexImage2D(gl.GL_TEXTURE_2D, 0, gl.GL_RGBA8,
                            img.width(), img.height(), 0,
                            gl.GL_RGBA, gl.GL_UNSIGNED_BYTE,
                            img.constBits().tobytes())

        # Start default idle motion
        self.renderer:start_motion("Idle", 0, 1.0)

        self.timer = QTimer()
        self.timer.timeout.connect(self.update)
        self.timer.start(16)    # ~60fps

    def paintGL(self):
        self.renderer:update(16 / 1000.0)

        import OpenGL.GL as gl
        gl.glClear(gl.GL_COLOR_BUFFER_BIT | gl.GL_STENCIL_BUFFER_BIT)
        gl.glClearStencil(0)

        width = self.width()
        height = self.height()
        projection = [2.0/width, 0, 0, 0,
                      0, -2.0/height, 0, 0,
                      0, 0, 1, 0,
                      -1.0, 1.0, 0, 1.0]

        self.renderer:render(projection, self.renderer:get_texture_paths())

    def closeEvent(self, event):
        self.renderer:dispose()
        super().closeEvent(event)
```

---

## Embed Module-Level Convenience API

For quick scripts or single-model use, the embed module tracks a "current" renderer:

```python
embed = lua.execute(b'return require("live2d_moc3_embed")')

# One-liner load (sets as current)
r = embed.load_model("resources/Hiyori/Hiyori.model3.json")

# Module-level helpers operate on the current renderer
embed.set_parameter("ParamAngleX", 30.0)
embed.start_motion("Idle", 0, 1.0)
embed.update(0.016)
meshes = embed.get_meshes()
embed.render(projection, texture_paths)
embed.clear_motions()
embed.clear_expressions()
embed.dispose()
```

---

## Accessing Underlying Modules

The embed table exposes the underlying module references for advanced use:

```python
moc3        = embed.moc3           # live2d.cubism3.moc3
model3      = embed.model3         # live2d.cubism3.json.model3
motion3     = embed.motion3        # live2d.cubism3.json.motion3
expression3 = embed.expression3     # live2d.cubism3.json.expression3
pose3       = embed.pose3          # live2d.cubism3.json.pose3
Renderer    = embed.Renderer       # Renderer class (for subclassing in Lua)
ModelRuntime = embed.ModelRuntime  # ModelRuntime class
MotionPlayer = embed.MotionPlayer  # MotionPlayer class
```

```python
# Access the underlying runtime for direct low-level control
runtime = renderer:get_runtime()
model_data = renderer:get_model_data()
```

---

## Differences from Cubism 2.1

| Aspect | Cubism 2.1 | Cubism 3 |
|--------|-----------|----------|
| Model format | `.moc` (binary v2) | `.moc3` (binary v3/v4/v5) |
| Config format | `.model.json` (v1) | `.model3.json` (v3) |
| Motions | `.mtn` (binary) | `.motion3.json` (JSON) |
| Expressions | `.json` (legacy) | `.exp3.json` (Cubism 3) |
| Art meshes | ~80 | 134 (Hiyori), 311 (Rana v5) |
| Deformers | Rotation only | Warp + Rotation |
| Keyforms | Per-part | Per-art-mesh with color blending |
| Renderer | Fixed-function GL | GLSL shader (#version 120), stencil clipping |
| Embed module | `live2d_embed.lua` | `live2d_moc3_embed.lua` |
| Texture count | 1 | 2+ |
| Pose | — | `pose3.json` (part opacity + art mesh fade) |
| Draw order groups | — | Cubism 5 draw-order group expansion |

---

## Troubleshooting

### `require("ffi")` fails in lupa
Your lupa is compiled against standard Lua, not LuaJIT. Reinstall: `pip install lupa --force-reinstall` (ensure your environment has LuaJIT development headers).

### Module not found
Ensure `package.path` is set and the working directory is the repo root. Lupa does not inherit Lua's search paths by default.

### Resource stream not resolving
Resource stream keys are matched by normalized path (backslashes → forward slashes; trailing slashes stripped). Check that keys match what `model3.json` references produce.

### Vertices look corrupted (stretched / flipped)
The renderer applies Y-axis flip (`-vertex.y`) to convert from Live2D coordinate system (Y-up) to OpenGL screen coordinates. Ensure the projection matrix is set correctly.

### Clipping / transparency artifacts
Clipping masks require a stencil buffer (8-bit). Enable `GL_STENCIL_BUFFER_BIT` in `glClear` and request a stencil-capable framebuffer. The renderer forces mask mesh opacity to 1.0 during stencil writes — mask meshes with opacity 0 at their pose do not lose clipping capability.

### Parameter changes have no visual effect
Parameters like `ParamAngleX` affect deformer positions, not opacities. Visual changes depend on which deformer keys the parameter drives. Ensure `renderer:update()` is called after parameter changes to regenerate meshes.
