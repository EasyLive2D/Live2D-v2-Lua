# Embedding Live2D in Python

## 架构概览

```
Python GUI (PySide6 / PyQt6 / wxPython 等)
  └─ QOpenGLWidget / GL canvas          ← 创建并持有 OpenGL context
       ├─ initializeGL()                 ← 调 live2d_embed.init()
       │    └─ lupa (LuaJIT)             ← 加载并执行 Lua 代码
       │         └─ live2d_embed.lua     ← 窗口无关的渲染核心模块
       │              ├─ live2d_embed.init()
       │              ├─ live2d_embed.load_model(path, w, h)
       │              ├─ live2d_embed.resize(w, h)
       │              ├─ live2d_embed.drag(x, y)
       │              ├─ live2d_embed.draw()
       │              ├─ live2d_embed.start_motion(...)
       │              ├─ live2d_embed.set_parameter(...)
       │              └─ live2d_embed.dispose()
       │
       ├─ resizeGL(w, h)                 ← 调 embed.resize(w, h)
       ├─ paintGL()                      ← 调 embed.draw()
       │    └─ model:Update() + model:Draw()
       │
       └─ QTimer(16ms)                   ← 驱动 paintGL 循环刷新
```

## 前置条件

### 1. LuaJIT 运行时

本项目依赖 **LuaJIT** 的 `ffi` 模块（用于 C 函数调用和 FFI 缓冲区），**不能使用标准 Lua 解释器**。

你需要一个能被 Python 调用的 LuaJIT。提供三种方案：

| 方案 | 库 | 原理 | 推荐度 |
|------|-----|------|--------|
| lupa (LuaJIT 版本) | `pip install lupa` | `import lupa.luajit21` | ★★★ 推荐 |
| ctypes + luajit.dll | 系统自带的 `luajit-2.1.dll` | ctypes 加载 DLL，调 Lua C API | ★★☆ 备选 |
| 子进程 + IPC | `subprocess` + 共享内存/Socket | 独立进程渲染，传像素到 Python | ★☆☆ 最稳定但性能差 |

### 2. OpenGL 控件

Python GUI 必须提供一个支持 OpenGL 的控件。推荐：

- **PySide6** / **PyQt6**: `QOpenGLWidget`（本文示例使用）
- **wxPython**: `wx.GLCanvas`
- **Tkinter**: 不推荐（无原生 GL 控件，需借助 pyopengl 等 hack）

### 3. 操作系统

当前仓库的 `live2d/gl_loader.lua` **仅支持 Windows**（使用 `wglGetProcAddress` 加载 OpenGL 扩展）。如需 Linux/macOS，需要重写该文件。

### 4. 依赖安装

```bash
pip install PySide6 lupa
```

> **Critical**: lupa 的 wheel 必须基于 LuaJIT 编译，不是标准 Lua。如果 `require("ffi")` 在 lupa 中报错，说明你的 lupa 捆绑了标准 Lua，需要手动编译 LuaJIT 版本的 lupa，或改用 ctypes 方案。

## live2d_embed.lua 模块

### 设计原则

- **无窗口**：不创建 SDL 窗口，不调用 `swapWindow`，不跑事件循环
- **宿主持 context**：假定调用方已经创建并激活了 OpenGL context
- **延迟初始化**：`init()` 只在第一次调用时注册 GL 扩展和 Live2D 运行时
- **Singleton API**：提供简单全局接口，方便通过 lupa / ctypes 直接调
- **对象 API**：也提供面向对象风格的 `Renderer` 类，方便同时管多模型

### 公共 API

#### 初始化

```lua
local embed = require("live2d_embed")
embed.init()  -- 注册 GL 扩展 + 初始化 Live2D 运行时
```

必须在 OpenGL context 已激活之后调用。

#### 加载模型

```lua
embed.load_model("resources/kasumi2/kasumi2.model.json", 400, 650)
```

或带配置参数：

```lua
embed.load_model("resources/kasumi2/kasumi2.model.json", 400, 650, {
    auto_breath = true,
    auto_blink  = true,
    center      = true,
    model_width = 2.0,
    center_x    = 0,
    center_y    = 0,
})
```

第三个参数 `width/height` 是视口大小，不是模型大小。模型缩放通过 `model_width` 控制。

#### 每帧绘制

```lua
embed.draw()  -- 等价于 Update() + Draw()，先 clear 再渲染
```

当宿主已经手动清屏时，可以跳过内置的 clear：

```lua
embed.draw({ clear = false })
```

GC step size 可调（默认 200）：

```lua
embed.draw({ gc_step = 100 })
```

#### 视口大小

```lua
embed.resize(800, 600)
```

#### 鼠标交互

```lua
embed.drag(x, y)  -- 视线追踪 / 头部朝向
```

#### 动作控制

```lua
-- 播放指定动作
embed.start_motion("tap_body", 0)  -- motion_name, motion_no

-- 播放 idle 动作（kasumi2 通常预加载了 3 个 idle）
embed.start_motion("idle", 0)
embed.start_motion("idle", 1)
embed.start_motion("idle", 2)
```

#### 参数控制

```lua
embed.set_parameter("PARAM_ANGLE_X", 20)     -- 设置到绝对值
embed.add_parameter("PARAM_BODY_ANGLE_X", 5)  -- 累加偏移
```

#### 表达式

```lua
embed.set_expression("SMILE")
embed.reset_expression()
```

#### 清理

```lua
embed.dispose()
```

### 对象 API（多模型场景）

```lua
local renderer1 = embed.new(400, 650)
renderer1:load_model("resources/model1.json", 400, 650)

local renderer2 = embed.new(400, 650)
renderer2:load_model("resources/model2.json", 400, 650)

-- 切换渲染
renderer1:draw()
-- 或者
renderer2:draw()
```

## lupa 接入方案（推荐）

### 完整示例

`examples/pyside6_lupa_kasumi2.py`

核心代码结构：

```python
import os
from pathlib import Path
from lupa.luajit21 import LuaRuntime

from PySide6.QtCore import QTimer, Qt
from PySide6.QtOpenGLWidgets import QOpenGLWidget
from PySide6.QtWidgets import QApplication, QMessageBox

ROOT = Path(__file__).resolve().parents[1]
MODEL_PATH = "resources/kasumi2/kasumi2.model.json"

class Live2DWidget(QOpenGLWidget):
    def initializeGL(self):
        # 1. 确保 cwd 在仓库根目录（Lua 的 package.path 从 cwd 拼路径）
        os.chdir(ROOT)

        # 2. 创建 LuaJIT 运行时
        self.lua = LuaRuntime(unpack_returned_tuples=True)

        # 3. 验证 FFI 模块可用
        self.lua.execute('assert(require("ffi"), "lupa needs LuaJIT, not plain Lua")')

        # 4. 加载 live2d_embed 模块
        self.embed = self.lua.execute('return require("live2d_embed")')

        # 5. 缓存高频函数引用（避免每次 paintGL 都 eval 字面量）
        self._draw = self.lua.eval("function(e) return e.draw() end")
        self._resize = self.lua.eval("function(e,w,h) return e.resize(w,h) end")
        self._drag = self.lua.eval("function(e,x,y) return e.drag(x,y) end")

        # 6. 加载模型
        self.embed.load_model(MODEL_PATH, self.width(), self.height())

    def resizeGL(self, w, h):
        self._resize(self.embed, w, h)

    def paintGL(self):
        self._draw(self.embed)

    def mouseMoveEvent(self, event):
        pos = event.position()
        self._drag(self.embed, pos.x(), pos.y())

    def mousePressEvent(self, event):
        if event.button() == Qt.MouseButton.LeftButton:
            self._motion_index = (self._motion_index + 1) % 3
            self._start_motion(self.embed, "idle", self._motion_index)

    def closeEvent(self, event):
        self.embed.dispose()
```

运行：

```bash
python examples/pyside6_lupa_kasumi2.py
```

### lupa 关键注意事项

#### 1. 全局函数缓存

每次 `lua.eval("...")` 会解析字符串并编译一个新 Lua 闭包，如果放在 `paintGL()` 里频繁调用会很慢。解决方案：在 `initializeGL()` 里预先 eval，只一次编译，之后只传参数。

```python
# Good: 预编译
self._draw = self.lua.eval("function(e) return e.draw() end")
self._draw(self.embed)

# Bad: 每帧 eval
self.lua.eval(f"embed.draw()")  # 每次都在编译
```

#### 2. GC step

`live2d_embed.lua` 已经在每次 `draw()` 内部调用了 `collectgarbage("step", 200)`，Python 侧不需要额外处理。

但如果你自己调 `renderer:update()` 然后 `renderer:get_model():Draw()`（不走 `draw()`），需要在 Python 侧周期性触发 Lua GC：

```python
self.lua.execute("collectgarbage('step', 200)")
```

否则在高帧率下，FFI 临时缓冲区会堆积导致内存爆炸。

#### 3. OpenGL context 线程亲和性

QOpenGLWidget 的 `initializeGL` / `paintGL` 在独立线程中运行（具体的线程行为由 Qt 控制）。Lua 代码直接调用 GL 函数时，必须确保 OpenGL context 已经 `makeCurrent` — QOpenGLWidget 会自动处理这一点。

**不要在非 GL 线程中调用 `embed.draw()`**。

#### 4. 模型路径

所有路径都相对于 `os.chdir(ROOT)` 设置的工作目录。模型 JSON 文件里的纹理路径也是相对路径，所以确保 cwd 正确。

## ctypes 接入方案（备选）

如果 lupa 不能用，可以直接通过 ctypes 加载 `luajit-2.1.dll`，走原生 Lua C API。

### 原理

```python
import ctypes

luajit = ctypes.CDLL("luajit-2.1.dll")

# 创建 Lua 状态机
lua_newstate = luajit.luaL_newstate
lua_newstate.restype = ctypes.c_void_p
L = lua_newstate(None, None)

# 打开标准库
luajit.luaL_openlibs(L)

# 加载并执行 live2d_embed.lua
luajit.luaL_dofile(L, b"live2d_embed.lua")

# 获取全局函数 embed.load_model
luajit.lua_getglobal(L, b"embed")       # push embed table
luajit.lua_getfield(L, -1, b"load_model")  # push embed.load_model

# 压入参数
luajit.lua_pushstring(L, b"resources/kasumi2/kasumi2.model.json")
luajit.lua_pushinteger(L, 400)
luajit.lua_pushinteger(L, 650)

# 调用
luajit.lua_pcall(L, 3, 0, 0)
```

### ctypes 模式的问题

- 需要手动管理 Lua 栈
- 错误处理复杂（`lua_pcall` 失败需要读栈顶错误消息）
- 返回值需要手动从栈中取出并转换
- 参数压栈容易出错
- Python 对象和 Lua 对象之间无自动转换

**建议**：只有在 lupa 实在装不上时才用 ctypes。

## ctypes 完整封装（生产环境可参考）

如果必须用 ctypes 方案，最好先封装一个 Python 类来隐藏 Lua 栈细节：

```python
import ctypes
from pathlib import Path

class LuaJITRuntime:
    """Minimal LuaJIT binding via ctypes."""

    def __init__(self, lib_path: str = "luajit-2.1.dll"):
        self.lib = ctypes.CDLL(lib_path)
        self.L = None

    def open(self) -> None:
        f_newstate = self.lib.luaL_newstate
        f_newstate.restype = ctypes.c_void_p
        self.L = f_newstate(None, None)
        self.lib.luaL_openlibs(self.L)

    def dofile(self, path: str) -> int:
        return self.lib.luaL_dofile(self.L, path.encode("utf-8"))

    def get_global(self, name: str) -> None:
        self.lib.lua_getglobal(self.L, name.encode("utf-8"))

    def push_string(self, s: str) -> None:
        self.lib.lua_pushstring(self.L, s.encode("utf-8"))

    def push_number(self, n: float) -> None:
        self.lib.lua_pushnumber(self.L, ctypes.c_double(n))

    def push_integer(self, n: int) -> None:
        self.lib.lua_pushinteger(self.L, n)

    def call(self, nargs: int, nresults: int) -> int:
        return self.lib.lua_pcall(self.L, nargs, nresults, 0)

    def close(self) -> None:
        if self.L:
            self.lib.lua_close(self.L)
            self.L = None
```

## 子进程 + IPC 方案（应急备选）

当 lupa 和 ctypes 都无法正常工作时，可以选择"分离进程渲染，传回像素"的方式。

### 架构

```
Python GUI                  │  独立 luajit 进程 (render_frames.lua)
  QLabel / QPixmap          │    render → glReadPixels → 共享内存 / socket
  (显示像素图)              │    等待 Python 发送 resize/drag 指令
                            │
  共享内存 (mmap / named pipe)
```

### 缺点

- **延迟高**：每帧从 GPU 回读像素 + IPC 传输
- **带宽大**：400×650 RGBA ≈ 1MB/帧，60fps = 60MB/s
- **不支持实时交互**：鼠标拖拽需要 IPC 把坐标传给 Lua 进程
- **无 GPU 共享**：需要两个 OpenGL context（Python 窗口 + Lua 进程各一个）

只有当 lupa 和 ctypes 方案都彻底行不通时才考虑这条路。

## 常见问题

### Q: `gl.ensureExtensions()` 失败 / 找不到 wglGetProcAddress

A: 确认在调用 `embed.init()` 时 OpenGL context 已经激活。QOpenGLWidget 会在 `initializeGL()` 之前自动 makeCurrent。

### Q: 纹理加载失败 / 模型是一片白

A: 检查工作目录。`live2d_embed.lua` 和模型 JSON 都假设 cwd 是仓库根目录。在 `initializeGL()` 开头加 `os.chdir(ROOT)`。

### Q: GC 崩溃 / 内存持续增长

A: 确保每次 `draw()` 调用后执行 `collectgarbage("step", 200)`。`live2d_embed.lua` 的 `draw()` 内部已做这一步，如果直接调 `model:Draw()` 则需要手动补充。

### Q: 帧率不稳定

A: Live2D 模型动画的 dt 由 Python 侧传入。如果帧率不固定，可以在 `update()` 前传入真实的 dt：

```lua
-- 需要在 live2d_embed.lua 或调用侧手动处理
model.startTimeMSec = model.startTimeMSec + dt_ms
model:Update()
```

当前示例用 QTimer(16ms) ≈ 60fps 驱动，配合 `setSwapInterval(1)` 实现 vsync 同步。

### Q: 如何在非 Qt 框架中使用

A: 任何能创建 OpenGL context 的库都可以。核心只有一个：在 GL context 激活后调用 `live2d_embed` 的对应接口。示例使用 QOpenGLWidget 只是因为它在 Python 中配置最简单。

对于 wxPython:

```python
import wx
import wx.glcanvas as gl

class Live2DCanvas(gl.GLCanvas):
    def __init__(self, parent):
        super().__init__(parent)
        self.context = gl.GLContext(self)

    def OnPaint(self, event):
        self.context.SetCurrent(self)  # 手动 makeCurrent
        self._draw(self.embed)
        self.SwapBuffers()
```

### Q: 多模型同时渲染

A: 使用对象 API 创建多个 `Renderer` 实例：

```lua
-- Lua 侧
local model_a = embed.new(400, 650)
model_a:load_model("model_a.json", 400, 650)

local model_b = embed.new(400, 650)
model_b:load_model("model_b.json", 400, 650)
```

Python 侧缓存两个不同的 lua 函数引用：

```python
self._draw_a = self.lua.eval("function(r) return r.draw() end")
self._draw_b = self.lua.eval("function(r) return r.draw() end")

def paintGL(self):
    self._draw_a(self.renderer_a)
    self._draw_b(self.renderer_b)
```

注意：Live2D 默认 viewport 会覆盖整个窗口，多模型渲染通常需要额外的 FBO 或裁剪区域管理。

## 文件清单

```
live2d-v2/
├── live2d_embed.lua                       ← 窗口无关渲染核心模块
├── examples/
│   └── pyside6_lupa_kasumi2.py            ← Python 接入完整示例
├── live2d/
│   ├── gl_loader.lua                      ← OpenGL 扩展加载器 (wglGetProcAddress)
│   ├── lapp_model.lua                     ← 高级模型封装 (LoadModelJson / Update / Draw)
│   ├── platform_manager.lua               ← 文件 I/O 抽象层
│   ├── sdl2.lua                           ← SDL2 FFI 绑定 (embed 模式不需要)
│   └── ...
└── resources/
    └── kasumi2/
        ├── kasumi2.model.json
        ├── kasumi2.moc
        └── textures/
```
