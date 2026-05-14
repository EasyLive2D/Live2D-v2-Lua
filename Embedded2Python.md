# Embedding Live2D in Python

[中文](Embedded2Python_cn.md) | [日本語](Embedded2Python_jp.md)

## Architecture Overview

```
Python GUI (PySide6 / PyQt6 / wxPython etc.)
  └─ QOpenGLWidget / GL canvas          ← creates and owns OpenGL context
       ├─ Initialization Phase
       │    ├─ Recursively read all files in model directory    ← Python side
       │    ├─ Decode textures to RGBA8888 via QImage           ← Python side
       │    ├─ Build resource_streams table                     ← lupa Lua table
       │    ├─ Build texture_streams table                      ← lupa Lua table
       │    └─ opts = { resource_streams, texture_streams }
       │
       ├─ Load & Render
       │    ├─ embed.load_model(path, w, h, opts) ← All resources via streams, zero filesystem reads
       │    ├─ resizeGL(w, h)    → embed.resize(w, h)
       │    └─ paintGL()         → embed.draw()
       │
       └─ QTimer(16ms)           ← drives refresh loop
```

**Core concept**: The Python side fully manages file reading and decoding. The Lua side only receives memory byte streams, no longer depending on the filesystem or `image_loader.lua`.

## Prerequisites

### 1. LuaJIT Runtime

This project depends on the LuaJIT `ffi` module. **Standard Lua interpreters will not work**.

| Approach | Library | Principle | Recommendation |
|----------|---------|-----------|----------------|
| lupa (LuaJIT build) | `pip install lupa` | `import lupa.luajit21` | ★★★ Recommended |
| ctypes + luajit.dll | System `luajit-2.1.dll` | ctypes loads DLL, calls Lua C API | ★★☆ Fallback |
| Subprocess + IPC | `subprocess` + shared memory/Socket | Separate process renders, passes pixels to Python | ★☆☆ Most stable but slowest |

### 2. OpenGL Widget

The Python GUI must provide an OpenGL-capable widget. Recommended:

- **PySide6** / **PyQt6**: `QOpenGLWidget` (used in this guide)
- **wxPython**: `wx.GLCanvas`

### 3. Operating System

The `live2d/gl_loader.lua` in this repo **supports Windows and Linux**. macOS compatibility has not been tested.

### 4. Dependency Installation

```bash
pip install PySide6 lupa
```

> **Critical**: The lupa wheel must be compiled against LuaJIT. If `require("ffi")` fails in lupa, your lupa is bundled with standard Lua.

---

## Stream-based Loading (Recommended)

Pass byte streams directly from Python to Lua, completely bypassing filesystem reads and texture decoding. This is the recommended approach because:

- **No filesystem dependency**: Models can load from zip/network/memory
- **Zero I/O coupling**: Python side decides data source, Lua side only consumes bytes
- **Bypasses GDI+ limitations**: Avoids `image_loader.lua` and Windows GDI+ decoding pitfalls
- **Cross-platform texture decoding**: Uses Qt's `QImage` to decode textures, no `wincodec` dependency

### Stream API Reference

#### Resource Streams — Replace All File Reads

```lua
-- Lua side
embed.set_resource_stream(path, bytes)        -- Single entry
embed.set_resource_streams(resource_streams)  -- Batch
embed.clear_resource_streams()                -- Clear all
```

Resource streams can also be passed via `opts` during `load_model`:

```lua
embed.load_model("resources/kasumi2/kasumi2.model.json", 400, 650, {
    resource_streams = {
        ["resources/kasumi2/kasumi2.model.json"] = json_bytes,
        ["resources/kasumi2/live2d/kasumi_school_winter_t03.moc"] = moc_bytes,
        ["resources/kasumi2/live2d/001_live_event_47_ssr_idle01.mtn"] = mtn_bytes,
        -- ... physics, pose, expressions, etc. all go through this table
    },
})
```

Paths are automatically normalized (`\` → `/`, leading `./` stripped) to match relative references in `.model.json`.

Overridden load entry points:
- `.model.json` itself (`loadBytes` reads JSON)
- `.moc` model files (`loadLive2DModel` → `loadBytes`)
- `.mtn` motion files (`loadMotion` → `loadBytes`)
- `.json` expression / pose / physics files (respective `loadExpression`, `loadPose`, `loadPhysics` → `loadBytes`)
- All other files read via `PlatformManager:loadBytes()`

#### Texture Streams — Replace PNG Decoding and GL Upload

```lua
-- Lua side
embed.set_texture_stream(no, width, height, rgba_bytes)   -- Single texture
embed.set_texture_streams(texture_streams)                 -- Batch
embed.clear_texture_streams()                              -- Clear all
```

Texture numbers are **0-based**, corresponding to the order in the model JSON's `textures` array.

```lua
embed.load_model("resources/kasumi2/kasumi2.model.json", 400, 650, {
    texture_streams = {
        [0] = {
            width  = 1024,
            height = 1024,
            data   = rgba_bytes,  -- Lua string / FFI pointer
        },
    },
})
```

Pipeline: Python side decodes PNG with any image library → RGBA8888 bytes → passes to Lua via lupa → `platform_manager.lua` uploads directly to OpenGL via `glTexImage2D`, completely skipping `image_loader.lua`.

### Complete lupa Integration Example

`examples/pyside6_lupa_kasumi2.py`

Core workflow:

```python
import json
import os
from pathlib import Path
from lupa.luajit21 import LuaRuntime

from PySide6.QtCore import QTimer, Qt
from PySide6.QtGui import QImage
from PySide6.QtOpenGLWidgets import QOpenGLWidget

ROOT = Path(__file__).resolve().parents[1]
MODEL_PATH = "resources/kasumi2/kasumi2.model.json"

class Live2DWidget(QOpenGLWidget):
    def initializeGL(self):
        os.chdir(ROOT)

        # 1. Create LuaJIT runtime (encoding=None allows lupa to pass Python bytes directly)
        self.lua = LuaRuntime(unpack_returned_tuples=True, encoding=None)
        self.lua.execute(b'assert(require("ffi"), "lupa must be built with LuaJIT FFI")')

        # 2. Load live2d_embed
        self.embed = self.lua.execute(b'return require("live2d_embed")')

        # 3. Pre-compile high-frequency functions
        self._load_model = self.lua.eval(
            b"function(embed, path, w, h, opts) "
            b"return embed.load_model(path, w, h, opts) end"
        )
        self._draw   = self.lua.eval(b"function(e) return e.draw() end")
        self._resize = self.lua.eval(b"function(e,w,h) return e.resize(w,h) end")
        self._drag   = self.lua.eval(b"function(e,x,y) return e.drag(x,y) end")
        self._start_motion = self.lua.eval(
            b"function(e,n,i) return e.start_motion(n,i,e.MotionPriority.FORCE) end"
        )

        # 4. Build stream tables
        opts = self.lua.table()
        opts[b"resource_streams"] = load_resource_streams(self.lua, ROOT / "resources" / "kasumi2")
        opts[b"texture_streams"]  = load_texture_streams(self.lua, ROOT / MODEL_PATH)

        # 5. Load model (all via streams)
        self._load_model(self.embed, MODEL_PATH.encode(), self.width(), self.height(), opts)

    def resizeGL(self, w, h):
        self._resize(self.embed, w, h)

    def paintGL(self):
        self._draw(self.embed)

    def mouseMoveEvent(self, event):
        pos = event.position()
        self._drag(self.embed, pos.x(), pos.y())

    def closeEvent(self, event):
        self.embed.dispose()
        super().closeEvent(event)


# ---- Stream Construction Helpers -------------------------------------------

def load_resource_streams(lua, model_dir):
    """Recursively read all files in the model directory, building a Lua table.
    Key is the repo-relative path (e.g. "resources/kasumi2/live2d/xxx.mtn"), Value is bytes."""
    streams = lua.table()
    for path in model_dir.rglob("*"):
        if path.is_file():
            key = path.relative_to(ROOT).as_posix().encode()
            streams[key] = path.read_bytes()
    return streams


def load_texture_streams(lua, model_json_path):
    """Read the model JSON, decode textures to RGBA8888, build a Lua table.
    Key is the texture number (0-based), Value is { width, height, data }."""
    with open(model_json_path, encoding="utf-8") as f:
        model_json = json.load(f)

    streams = lua.table()
    for no, tex_name in enumerate(model_json.get("textures", [])):
        w, h, rgba = decode_rgba(model_json_path.parent / tex_name)
        entry = lua.table()
        entry[b"width"]  = w
        entry[b"height"] = h
        entry[b"data"]   = rgba
        streams[no] = entry
    return streams


def decode_rgba(path):
    """Decode image to RGBA8888 bytes using QImage."""
    img = QImage(str(path))
    if img.isNull():
        raise RuntimeError(f"Failed to load: {path}")

    img = img.convertToFormat(QImage.Format.Format_RGBA8888)
    w, h = img.width(), img.height()
    stride = img.bytesPerLine()
    row_sz = w * 4
    data = bytes(img.constBits())

    if stride == row_sz:
        return w, h, data[: row_sz * h]

    rows = [data[y * stride : y * stride + row_sz] for y in range(h)]
    return w, h, b"".join(rows)
```

Run:

```bash
python examples/pyside6_lupa_kasumi2.py
```

---

## Key lupa Considerations

### 1. encoding=None

```python
self.lua = LuaRuntime(unpack_returned_tuples=True, encoding=None)
```

`encoding=None` allows `lua.execute()` and `lua.eval()` to accept Python `bytes`, passing them directly to Lua as Lua strings — this is essential for resource byte streams, otherwise encoding conversion would corrupt binary data.

### 2. Global Function Caching

Each `lua.eval("...")` parses and compiles a new Lua closure. Do not use it inside `paintGL()`. Pre-cache everything in `initializeGL()`:

```python
# Good: pre-compiled
self._draw = self.lua.eval(b"function(e) return e.draw() end")
self._draw(self.embed)

# Bad: eval every frame
self.lua.eval(b"embed.draw()")
```

### 3. GC Step

`live2d_embed.lua`'s `draw()` already executes `collectgarbage("step", 200)` internally. No additional handling is needed on the Python side. If directly calling `model:Draw()` without going through `draw()`, manual GC is required:

```python
self.lua.execute(b"collectgarbage('step', 200)")
```

### 4. OpenGL Context Thread Affinity

QOpenGLWidget's `initializeGL` / `paintGL` run on the GL thread. Qt ensures the context is already bound. **Never call `embed.draw()` from a non-GL thread**.

### 5. Byte Stream Data Type

The Lua side handles incoming data via `ffi.cast("const uint8_t*", data)`. Python `bytes` objects in `encoding=None` mode are passed by lupa as Lua strings, whose address can be safely cast by FFI. Passing raw pointers from other languages is also supported.

---

## live2d_embed.lua Full API

### Singleton API (Global Single Model)

```lua
local embed = require("live2d_embed")

-- Initialize (lazy — auto-triggers on first call with active OpenGL context)
embed.init()

-- Load model (recommended to pass streams via opts)
embed.load_model("resources/kasumi2/kasumi2.model.json", 400, 650, {
    resource_streams = { ... },
    texture_streams  = { ... },
    auto_breath = true,   -- auto breathing
    auto_blink  = true,   -- auto blinking
    center      = true,   -- center model
    model_width = 2.0,    -- model scaling
    center_x    = 0,      -- X offset
    center_y    = 0,      -- Y offset
})

-- Resource stream management
embed.set_resource_stream(path, bytes)        -- Inject single resource
embed.set_resource_streams(resource_streams)  -- Batch injection
embed.clear_resource_streams()                -- Clear all resource streams

-- Texture stream management
embed.set_texture_stream(no, width, height, rgba_bytes)  -- Inject single texture
embed.set_texture_streams(texture_streams)               -- Batch injection
embed.clear_texture_streams()                            -- Clear all texture streams

-- Clear all streams
embed.clear_streams()

-- Draw (built-in clear + update + draw + GC step)
embed.draw()               -- Default clear
embed.draw({ clear = false, gc_step = 200 })

-- Update animation only (no render)
embed.update()

-- Manual screen clear
embed.clear(r, g, b, a)

-- Viewport size
embed.resize(w, h)

-- Mouse interaction
embed.drag(x, y)           -- Gaze / head tracking
embed.set_offset(x, y)     -- Model translation
embed.set_scale(scale)     -- Model scale

-- Motions
embed.start_motion(name, no, priority)  -- priority: embed.MotionPriority.FORCE (3)
embed.clear_motions()

-- Parameters
embed.set_parameter("PARAM_ANGLE_X", 30)
embed.add_parameter("PARAM_BODY_ANGLE_X", 5)

-- Expressions
embed.set_expression("SMILE")
embed.reset_expression()

-- Hit testing
local part = embed.hit_test(x, y)

-- Get current renderer / model
local r = embed.current()
local l2d_model = r:get_model():getLive2DModel()

-- Cleanup
embed.dispose()
```

### Object API (Multi-Model Scenarios)

```lua
local r1 = embed.new(400, 650)
r1:load_model("model_a.json", 400, 650, {
    resource_streams = { ... },
    texture_streams  = { ... },
})

local r2 = embed.new(400, 650)
r2:load_model("model_b.json", 400, 650, {
    resource_streams = { ... },
    texture_streams  = { ... },
})

-- All Singleton API methods are available on Renderer instances
r1:draw()
r1:resize(800, 600)
r1:drag(x, y)
```

---

## Platform Compatibility

### Fallback When lupa Is Unavailable

#### ctypes + luajit.dll

If lupa cannot be installed, use ctypes to directly call LuaJIT's C API:

```python
import ctypes

luajit = ctypes.CDLL("luajit-2.1.dll")

# Create Lua state
L = luajit.luaL_newstate()
luajit.luaL_openlibs(L)

# Load live2d_embed
luajit.luaL_dofile(L, b"live2d_embed.lua")

# Call embed.load_model (stream tables must be built via lua_newtable + lua_pushstring + lua_settable)
...
```

Downsides of the ctypes approach:
- Requires manual Lua stack management
- Building stream tables is extremely tedious (each key-value pair requires multiple push + settable calls)
- Error debugging is difficult

**Installing lupa is still strongly recommended.**

---

## FAQ

### Q: Textures appear blank / white model / model not showing

A: Check that the texture stream has correct RGBA8888 data. Ensure `texture_streams` keys are `0`-based (not `1`). When using QImage for decoding, confirm the format is `Format_RGBA8888`.

### Q: Motions / physics / expressions not working

A: Verify the corresponding `.mtn` / `.json` files are included in `resource_streams`. The path key must be a repo-root relative path (e.g. `resources/kasumi2/live2d/001_idle01.mtn`) with `/` as the path separator.

### Q: Model JSON fails to load

A: The `.model.json` itself must also be in `resource_streams`. The first argument to `load_model` (e.g. `"resources/kasumi2/kasumi2.model.json"`) is only used for logging and resolving relative paths within the JSON — the actual JSON content is read from the stream table.

### Q: `gl.ensureExtensions()` fails

A: Ensure the OpenGL context is already active when calling `embed.init()` or your first `load_model()`. QOpenGLWidget auto-calls `makeCurrent()` in `initializeGL()`.

### Q: GC crash / memory keeps growing

A: `embed.draw()` already includes `collectgarbage("step", 200)` internally. If using `update()` + `Draw()` manually instead of `draw()`, trigger GC on the Python side:

```python
self.lua.execute(b"collectgarbage('step', 200)")
```

### Q: Rendering multiple models simultaneously

A: Use the Object API:

```python
self._draw_a = self.lua.eval(b"function(r) return r.draw() end")
self._draw_b = self.lua.eval(b"function(r) return r.draw() end")

def paintGL(self):
    self._draw_a(self.renderer_a)
    self._draw_b(self.renderer_b)
```

Note that multiple models share the same PlatformManager and stream tables.

### Q: How to support non-filesystem sources (network / zip / encrypted packages)

A: This is exactly where stream-based loading shines. The Python side simply downloads or decompresses remote data into `bytes`, builds `resource_streams` and `texture_streams`, and injects them into Lua:

```python
import zipfile, requests

zip_data = requests.get("https://example.com/model.zip").content
with zipfile.ZipFile(io.BytesIO(zip_data)) as zf:
    resource_streams[key.encode()] = zf.read(name)  # for each file in zip
```

The Lua side is completely unaware of the data source.

---

## File Inventory

```
live2d-v2/
├── live2d_embed.lua                       ← Headless rendering core module
├── Embedded2Python.md                     ← This document
├── examples/
│   └── pyside6_lupa_kasumi2.py            ← Complete Python integration example (stream-based)
├── live2d/
│   ├── platform_manager.lua               ← File I/O + stream routing
│   ├── gl_loader.lua                      ← OpenGL extension loader (wglGetProcAddress)
│   ├── image_loader.lua                   ← GDI+ texture loading (not triggered in stream mode)
│   └── ...
└── resources/
    └── kasumi2/
        ├── kasumi2.model.json
        ├── live2d/
        │   ├── kasumi_school_winter_t03.moc
        │   ├── texture_00.png
        │   ├── *.mtn
        │   └── ...
        └── ...
```
