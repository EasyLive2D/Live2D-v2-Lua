# Embedding Live2D in Python

## 架构概览

```
Python GUI (PySide6 / PyQt6 / wxPython 等)
  └─ QOpenGLWidget / GL canvas          ← 创建并持有 OpenGL context
       ├─ 初始化阶段
       │    ├─ 递归读取模型目录所有文件          ← Python 侧
       │    ├─ 用 QImage 解码纹理为 RGBA8888     ← Python 侧
       │    ├─ 构建 resource_streams 表           ← lupa Lua 表
       │    ├─ 构建 texture_streams 表            ← lupa Lua 表
       │    └─ opts = { resource_streams, texture_streams }
       │
       ├─ 加载 & 渲染
       │    ├─ embed.load_model(path, w, h, opts) ← 所有资源走流，零文件系统读
       │    ├─ resizeGL(w, h)    → embed.resize(w, h)
       │    └─ paintGL()         → embed.draw()
       │
       └─ QTimer(16ms)           ← 驱动循环刷新
```

**核心理念**：Python 侧全权管理文件读取和解码，Lua 侧只接收内存字节流，不再依赖文件系统和 `image_loader.lua`。

## 前置条件

### 1. LuaJIT 运行时

本项目依赖 **LuaJIT** 的 `ffi` 模块，**不能使用标准 Lua 解释器**。

| 方案 | 库 | 原理 | 推荐度 |
|------|-----|------|--------|
| lupa (LuaJIT 版本) | `pip install lupa` | `import lupa.luajit21` | ★★★ 推荐 |
| ctypes + luajit.dll | 系统自带的 `luajit-2.1.dll` | ctypes 加载 DLL，调 Lua C API | ★★☆ 备选 |
| 子进程 + IPC | `subprocess` + 共享内存/Socket | 独立进程渲染，传像素到 Python | ★☆☆ 最稳定但性能差 |

### 2. OpenGL 控件

Python GUI 必须提供一个支持 OpenGL 的控件。推荐：

- **PySide6** / **PyQt6**: `QOpenGLWidget`（本文示例使用）
- **wxPython**: `wx.GLCanvas`

### 3. 操作系统

当前仓库的 `live2d/gl_loader.lua` **支持 Windows 与 Linux**，MacOS未测试兼容性

### 4. 依赖安装

```bash
pip install PySide6 lupa
```

> **Critical**: lupa 的 wheel 必须基于 LuaJIT 编译。如果 `require("ffi")` 在 lupa 中报错，说明你的 lupa 捆绑了标准 Lua。

---

## 流式传输（推荐方式）

从 Python 直接传入字节流给 Lua，完全绕过文件系统读取和纹理解码。这是推荐方式，因为：

- **无文件系统依赖**：模型可以从 zip/网络/内存加载
- **零 I/O 耦合**：Python 侧决定数据来源，Lua 侧只消费字节
- **绕过 GDI+ 限制**：不用 `image_loader.lua`，避免 Windows GDI+ 解码的坑
- **跨平台纹理解码**：用 Qt 的 `QImage` 解码纹理，不依赖 `wincodec`

### 流式 API 速查

#### 资源流（resource_streams）—— 替代所有文件读取

```lua
-- Lua 侧
embed.set_resource_stream(path, bytes)        -- 单条
embed.set_resource_streams(resource_streams)  -- 批量
embed.clear_resource_streams()                -- 清空
```

`load_model` 时也可通过 opts 传入：

```lua
embed.load_model("resources/kasumi2/kasumi2.model.json", 400, 650, {
    resource_streams = {
        ["resources/kasumi2/kasumi2.model.json"] = json_bytes,
        ["resources/kasumi2/live2d/kasumi_school_winter_t03.moc"] = moc_bytes,
        ["resources/kasumi2/live2d/001_live_event_47_ssr_idle01.mtn"] = mtn_bytes,
        -- ... 物理、pose、表情等全部通过此表
    },
})
```

路径会自动归一化（`\` → `/`，去掉前导 `./`），匹配 `.model.json` 里相对引用的路径。

被覆盖的加载入口：
- `.model.json` 本身（`loadBytes` 读取 JSON）
- `.moc` 模型文件（`loadLive2DModel` → `loadBytes`）
- `.mtn` 动作文件（`loadMotion` → `loadBytes`）
- `.json` 表情 / pose / 物理（对应 `loadExpression`、`loadPose`、`loadPhysics` → `loadBytes`）
- 所有其他通过 `PlatformManager:loadBytes()` 读取的文件

#### 纹理流（texture_streams）—— 替代 PNG 文件解码和 GL 上传

```lua
-- Lua 侧
embed.set_texture_stream(no, width, height, rgba_bytes)   -- 单张
embed.set_texture_streams(texture_streams)                 -- 批量
embed.clear_texture_streams()                              -- 清空
```

纹理编号 **从 0 开始**，对应模型 JSON 中 `textures` 数组的顺序。

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

流水线：Python 侧用任意图像库解码 PNG → RGBA8888 字节 → 通过 lupa 传给 Lua → `platform_manager.lua` 直接用 `glTexImage2D` 上传 OpenGL 纹理，完全跳过 `image_loader.lua`。

### lupa 接入完整示例

`examples/pyside6_lupa_kasumi2.py`

核心流程：

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

        # 1. 创建 LuaJIT 运行时（encoding=None 让 lupa 直接传 Python bytes）
        self.lua = LuaRuntime(unpack_returned_tuples=True, encoding=None)
        self.lua.execute(b'assert(require("ffi"), "lupa must be built with LuaJIT FFI")')

        # 2. 加载 live2d_embed
        self.embed = self.lua.execute(b'return require("live2d_embed")')

        # 3. 预编译高频函数
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

        # 4. 构建流表
        opts = self.lua.table()
        opts[b"resource_streams"] = load_resource_streams(self.lua, ROOT / "resources" / "kasumi2")
        opts[b"texture_streams"]  = load_texture_streams(self.lua, ROOT / MODEL_PATH)

        # 5. 加载模型（全部走流）
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


# ---- 流构建辅助函数 -----------------------------------------------------

def load_resource_streams(lua, model_dir):
    """递归读取模型目录所有文件，构建 Lua table。
    Key 为仓库相对路径（如 "resources/kasumi2/live2d/xxx.mtn"），Value 为 bytes."""
    streams = lua.table()
    for path in model_dir.rglob("*"):
        if path.is_file():
            key = path.relative_to(ROOT).as_posix().encode()
            streams[key] = path.read_bytes()
    return streams


def load_texture_streams(lua, model_json_path):
    """读取模型 JSON，解码纹理为 RGBA8888，构建 Lua table。
    Key 为纹理编号（0-based），Value 为 { width, height, data }."""
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
    """用 QImage 解码图片为 RGBA8888 bytes。"""
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

运行：

```bash
python examples/pyside6_lupa_kasumi2.py
```

---

## lupa 关键注意事项

### 1. encoding=None

```python
self.lua = LuaRuntime(unpack_returned_tuples=True, encoding=None)
```

`encoding=None` 让 `lua.execute()` 和 `lua.eval()` 接受 Python `bytes`，直接传给 Lua 成为 Lua string —— 对于资源字节流这是必须的，否则编码转换会破坏二进制数据。

### 2. 全局函数缓存

每次 `lua.eval("...")` 会解析并编译一个新 Lua 闭包，不要在 `paintGL()` 里使用。在 `initializeGL()` 中一次性预缓存：

```python
# Good: 预编译
self._draw = self.lua.eval(b"function(e) return e.draw() end")
self._draw(self.embed)

# Bad: 每帧 eval
self.lua.eval(b"embed.draw()")
```

### 3. GC step

`live2d_embed.lua` 的 `draw()` 已经在内部执行了 `collectgarbage("step", 200)`，Python 侧不需要额外处理。如果直接调 `model:Draw()` 而不走 `draw()`，需要手动触发：

```python
self.lua.execute(b"collectgarbage('step', 200)")
```

### 4. OpenGL context 线程亲和性

QOpenGLWidget 的 `initializeGL` / `paintGL` 在 GL 线程中运行，Qt 会确保 context 已绑定。**不要在非 GL 线程中调用 `embed.draw()`**。

### 5. 字节流数据类型

Lua 侧通过 `ffi.cast("const uint8_t*", data)` 处理传入的数据。Python 的 `bytes` 对象在 encoding=None 模式下会被 lupa 作为 Lua string 传递，FFI 可以安全 cast 其地址。如果从其他语言传入，直接传指针也可以。

---

## live2d_embed.lua 完整 API

### Singleton API（全局单模型）

```lua
local embed = require("live2d_embed")

-- 初始化（延迟执行，OpenGL context 激活后首次调用自动触发）
embed.init()

-- 加载模型（推荐通过 opts 传入流）
embed.load_model("resources/kasumi2/kasumi2.model.json", 400, 650, {
    resource_streams = { ... },
    texture_streams  = { ... },
    auto_breath = true,   -- 自动呼吸
    auto_blink  = true,   -- 自动眨眼
    center      = true,   -- 模型居中
    model_width = 2.0,    -- 模型缩放
    center_x    = 0,      -- X 偏移
    center_y    = 0,      -- Y 偏移
})

-- 资源流管理
embed.set_resource_stream(path, bytes)        -- 注入单条资源
embed.set_resource_streams(resource_streams)  -- 批量注入
embed.clear_resource_streams()                -- 清空所有资源流

-- 纹理流管理
embed.set_texture_stream(no, width, height, rgba_bytes)  -- 注入单纹理
embed.set_texture_streams(texture_streams)               -- 批量注入
embed.clear_texture_streams()                            -- 清空所有纹理流

-- 全部流清空
embed.clear_streams()

-- 绘制（内置 clear + update + draw + GC step）
embed.draw()               -- 默认 clear
embed.draw({ clear = false, gc_step = 200 })

-- 仅更新动画（不渲染）
embed.update()

-- 手动清屏
embed.clear(r, g, b, a)

-- 视口大小
embed.resize(w, h)

-- 鼠标交互
embed.drag(x, y)           -- 视线 / 头部追踪
embed.set_offset(x, y)     -- 模型平移
embed.set_scale(scale)     -- 模型缩放

-- 动作
embed.start_motion(name, no, priority)  -- priority: embed.MotionPriority.FORCE (3)
embed.clear_motions()

-- 参数
embed.set_parameter("PARAM_ANGLE_X", 30)
embed.add_parameter("PARAM_BODY_ANGLE_X", 5)

-- 表达式
embed.set_expression("SMILE")
embed.reset_expression()

-- 点击测试
local part = embed.hit_test(x, y)

-- 获取当前 renderer / 模型
local r = embed.current()
local l2d_model = r:get_model():getLive2DModel()

-- 清理
embed.dispose()
```

### 对象 API（多模型场景）

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

-- 所有 Singleton API 的方法在 Renderer 实例上均可用
r1:draw()
r1:resize(800, 600)
r1:drag(x, y)
```

---

## 平台兼容性

### lupa 不可用时的备选方案

#### ctypes + luajit.dll

如果 lupa 无法安装，可以通过 ctypes 直接调用 LuaJIT 的 C API：

```python
import ctypes

luajit = ctypes.CDLL("luajit-2.1.dll")

# 创建 Lua 状态机
L = luajit.luaL_newstate()
luajit.luaL_openlibs(L)

# 加载 live2d_embed
luajit.luaL_dofile(L, b"live2d_embed.lua")

# 调用 embed.load_model（流表需要通过 lua_newtable + lua_pushstring + lua_settable 构建）
...
```

ctypes 方案的缺点：
- 需要手动管理 Lua 栈
- 流表的构建非常繁琐（每个键值对需要多次 push + settable）
- 错误调试困难

**仍然推荐优先安装 lupa。**

---

## 常见问题

### Q: 纹理空白 / 白模型 / 模型不显示

A: 检查纹理流是否传入正确的 RGBA8888 数据。确保 `texture_streams` 的 key 是 `0` 而不是 `1`（0-based 编号）。使用 QImage 解码时确认格式是 `Format_RGBA8888`。

### Q: 动作 / 物理 / 表情不工作

A: 确认对应的 `.mtn` / `.json` 文件已包含在 `resource_streams` 中。路径 key 必须是仓库根目录的相对路径（例如 `resources/kasumi2/live2d/001_idle01.mtn`），且路径分隔符为 `/`。

### Q: 模型 JSON 加载失败

A: `.model.json` 本身也需要在 `resource_streams` 中。`load_model` 的第一个参数（如 `"resources/kasumi2/kasumi2.model.json"`）仅用于日志和解析 json 里的相对路径，实际 JSON 内容从流表读取。

### Q: `gl.ensureExtensions()` 失败

A: 确认在调用 `embed.init()` 或首次 `load_model()` 时 OpenGL context 已经激活。QOpenGLWidget 在 `initializeGL()` 中自动 makeCurrent。

### Q: GC 崩溃 / 内存持续增长

A: `embed.draw()` 已内置 `collectgarbage("step", 200)`。如果不用 `draw()` 而是手动 `update()` + `Draw()`，需要在 Python 侧触发 GC：

```python
self.lua.execute(b"collectgarbage('step', 200)")
```

### Q: 多模型同时渲染

A: 使用对象 API：

```python
self._draw_a = self.lua.eval(b"function(r) return r.draw() end")
self._draw_b = self.lua.eval(b"function(r) return r.draw() end")

def paintGL(self):
    self._draw_a(self.renderer_a)
    self._draw_b(self.renderer_b)
```

注意多个模型共享同一个 PlatformManager 和流表。

### Q: 如何支持非文件来源（网络 / zip / 加密包）

A: 这正是流式传输的优势。Python 侧只需把远程数据下载或解压为 `bytes`，构建 `resource_streams` 和 `texture_streams`，注入 Lua 即可：

```python
import zipfile, requests

zip_data = requests.get("https://example.com/model.zip").content
with zipfile.ZipFile(io.BytesIO(zip_data)) as zf:
    resource_streams[key.encode()] = zf.read(name)  # for each file in zip
```

Lua 侧完全无感知数据来源。

---

## 文件清单

```
live2d-v2/
├── live2d_embed.lua                       ← 窗口无关渲染核心模块
├── Embedded2Python.md                     ← 本文档
├── examples/
│   └── pyside6_lupa_kasumi2.py            ← Python 接入完整示例（流式）
├── live2d/
│   ├── platform_manager.lua               ← 文件 I/O + 流路由
│   ├── gl_loader.lua                      ← OpenGL 扩展加载器 (wglGetProcAddress)
│   ├── image_loader.lua                   ← GDI+ 纹理加载（流模式下不触发）
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
