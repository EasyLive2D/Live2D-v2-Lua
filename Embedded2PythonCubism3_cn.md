# Embedding Live2D Cubism 3 (MOC3) in Python

[English](Embedded2PythonCubism3.md) | [日本語](Embedded2PythonCubism3_jp.md)

## 架构概览

```
Python GUI (PySide6 / PyQt6 / wxPython 等)
  └─ QOpenGLWidget / GL canvas          ← 创建并持有 OpenGL context
       ├─ 初始化阶段
       │    ├─ 读取 Hiyori.model3.json                   ← Python 读取后传 Lua
       │    ├─ 读取 Hiyori.moc3 二进制                   ← Python 读取后传 Lua
       │    ├─ 纹理解码 (PNG → RGBA via QImage)          ← Python 侧
       │    ├─ 读取 motion / pose JSON                   ← Python 读取后传 Lua
       │    └─ 在 Lua 中构建 ModelRuntime                ← lupa LuaRuntime
       │
       ├─ 逐帧更新
       │    ├─ 驱动 motion player (delta time)
       │    ├─ 应用 motion → 修改 runtime 参数
       │    ├─ 应用 pose → 修改 part opacity
       │    └─ runtime:update_meshes()
       │
       ├─ 渲染
       │    ├─ 传入 mesh 列表 + 纹理 ID + 投影矩阵
       │    └─ OpenGL 着色器绘制全部 134 个 mesh
       │
       └─ QTimer(16ms)           ← 驱动刷新循环
```

**核心理念**：Python 侧管理文件 I/O 和纹理解码，Lua 侧处理全部 Cubism 3 数据处理——MOC3 二进制解析、参数求值、变形器组合、mesh 生成。OpenGL 渲染器负责任绘制。

## 前置条件

### 1. LuaJIT 运行时

本项目依赖 LuaJIT 的 `ffi` 模块，**不能使用标准 Lua 解释器**。

| 方案 | 库 | 原理 | 推荐度 |
|------|-----|------|--------|
| lupa (LuaJIT 版本) | `pip install lupa` | `import lupa.luajit21` | ★★★ 推荐 |
| ctypes + luajit.dll | 系统带的 `luajit-2.1.dll` | ctypes 加载 DLL，调 Lua C API | ★★☆ 备选 |

### 2. OpenGL 控件

Python GUI 必须提供 OpenGL 控件：
- **PySide6** / **PyQt6**：`QOpenGLWidget`（本指南使用）
- **wxPython**：`wx.GLCanvas`

> ⚠️ Cubism 3 渲染器使用 GLSL 着色器 (GL `#version 120`)，需要 GL 2.1+ 上下文。

### 3. 依赖安装

```bash
pip install PySide6 lupa
```

> **关键**：lupa 必须基于 LuaJIT 编译。验证方法：

```python
lua = LuaRuntime()
assert lua.execute(b'return require("ffi")'), "lupa 必须基于 LuaJIT FFI 构建"
```

---

## Cubism 3 API 参考

Lua 模块结构：

```
live2d.cubism3.
  init.lua                    # 模块入口
  core/                       # 数学、插值、变形器、物理
  json/                       # model3, motion3, physics3, pose3, cdi3
  moc3/                       # MOC3 二进制解析 (14 个 section)
  runtime.lua                 # ModelRuntime
  motion.lua                  # MotionPlayer
  opengl_renderer.lua         # OpenGLRenderer
```

### 加载模型

```python
import os
from pathlib import Path
from lupa.luajit21 import LuaRuntime

lua = LuaRuntime(unpack_returned_tuples=True, encoding=None)
lua.execute(b'package.path = package.path .. ";./?.lua;./?/init.lua"')

# 加载模块
ModelRuntime = lua.execute(b'return require("live2d.cubism3.runtime")')
model3       = lua.execute(b'return require("live2d.cubism3.json.model3")')
pose3        = lua.execute(b'return require("live2d.cubism3.json.pose3")')
motion3      = lua.execute(b'return require("live2d.cubism3.json.motion3")')
MotionPlayer = lua.execute(b'return require("live2d.cubism3.motion")')
moc3         = lua.execute(b'return require("live2d.cubism3.moc3")')

# 读取模型文件
base = Path("resources/Hiyori")
model_json = (base / "Hiyori.model3.json").read_text()
moc_bytes  = (base / "Hiyori.moc3").read_bytes()
pose_json  = (base / "Hiyori.pose3.json").read_text()

# 解析 JSON
model_data = model3.parse(model_json)
pose_data  = pose3.parse(pose_json)

# 解析 MOC3 二进制
canvas     = moc3.canvas.parse(moc_bytes)
ids        = moc3.ids.parse(moc_bytes)
bindings   = moc3.keyform_bindings.parse(moc_bytes)
parts      = moc3.parts.parse(moc_bytes)
deformers  = moc3.deformers.parse(moc_bytes)
art_meshes = moc3.art_meshes.parse(moc_bytes)
keyforms   = moc3.keyforms.parse(moc_bytes)
offscreen  = moc3.offscreen.parse(moc_bytes)

# 构建运行时
runtime = ModelRuntime.new(
    model_data, canvas, art_meshes, keyforms,
    deformers, bindings, ids, offscreen, parts, pose_data
)
```

### 参数控制

```python
# 按名称获取参数索引
idx = runtime:parameter_index_of("ParamAngleX")
if idx is not None:
    runtime:set_parameter_by_index(idx, 0.5)

# 按字符串 ID 设置
runtime:set_parameter("ParamEyeLOpen", 0.8)

# 获取当前值
params = runtime.parameter_values  # Lua 表，Python 可遍历

# 恢复默认值
runtime:reset_parameters()
```

### 动作播放

```python
# 加载一个动作
motion_json = (base / "motions/Hiyori_m01.motion3.json").read_text()
motion_data = motion3.parse(motion_json)
player = MotionPlayer.new(motion_data)

# 逐帧:
player:tick(delta_seconds)
player:apply(runtime)
runtime:update_meshes()

# 检查状态
if player:is_finished():
    player:restart()
```

### 渲染

```python
# 设置 OpenGL 上下文后:

# 加载纹理
for i, tex_rel in enumerate(model_data.file_references.textures):
    tex_path = base / tex_rel
    # 用 QImage / PIL 等解码 PNG 为 RGBA
    rgba = decode_png_to_rgba(tex_path)
    gl.glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, w, h, 0, GL_RGBA, GL_UNSIGNED_BYTE, rgba)

# 逐帧渲染:
meshes = runtime.meshes  # Lua 表，含 134 个 Moc3DrawableMesh
for mesh_idx in range(len(meshes)):
    mesh = meshes[mesh_idx + 1]  # Lua 是 1 索引
    if mesh.opacity > 0.001:
        draw_mesh(mesh, projection_matrix)
```

### Mesh 数据结构

每个 `Moc3DrawableMesh` 包含：

| 字段 | 类型 | 说明 |
|------|------|------|
| `texture_index` | int | 纹理数组索引 (Hiyori 为 0 或 1) |
| `drawable_flags` | int | 混合模式 + mask 反转标志 |
| `opacity` | float | 最终计算的不透明度 (0.0–1.0) |
| `draw_order` | float | 模型的原始绘制顺序 |
| `render_order` | int | 解析后的渲染顺序 |
| `multiply_color` | `{r,g,b}` | 正片叠底颜色 |
| `screen_color` | `{r,g,b}` | 滤色颜色 |
| `vertices` | table | `{position={x,y}, uv={u,v}}` 数组 |
| `indices` | table | uint16 三角形索引数组 |
| `masks` | table | 裁剪 mask ID 数组 |

### 混合模式

| 标志位 | 混合模式 | GL 混合设置 |
|--------|---------|------------|
| bit 0 | 加法 | `glBlendFunc(GL_SRC_ALPHA, GL_ONE)` |
| bit 1 | 正片叠底 | `glBlendFunc(GL_DST_COLOR, GL_ONE_MINUS_SRC_ALPHA)` |
| 都没有 | 正常 | `glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)` |

---

## 完整 lupa 集成示例

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

        # 缓存常用 Lua 函数
        self._update_meshes = self.lua.eval(
            b"function(rt) return rt:update_meshes() end"
        )
        self._apply_pose = self.lua.eval(
            b"function(rt,dt) return rt:apply_pose(dt) end"
        )

        self.runtime = self._build_runtime()
        self.textures = self._load_textures()
        self.motion_players = self._load_motions()

        self.timer = QTimer()
        self.timer.timeout.connect(self.update)
        self.timer.start(16)

    def paintGL(self):
        import OpenGL.GL as gl
        gl.glClear(GL_COLOR_BUFFER_BIT)

        if self.active_motion:
            self.active_motion:tick(16/1000)
            self.active_motion:apply(self.runtime)

        self._apply_pose(self.runtime, 16/1000)
        self._update_meshes(self.runtime)

        meshes = self.runtime.meshes
        for i in range(1, len(meshes) + 1):
            mesh = meshes[i]
            if mesh.opacity > 0.001:
                self._draw_mesh(mesh)
```

---

## 与 Cubism 2.1 的主要区别

| 方面 | Cubism 2.1 | Cubism 3 |
|------|-----------|----------|
| 模型格式 | `.moc` (二进制 v2) | `.moc3` (二进制 v3/v4/v5) |
| 配置文件 | `.model.json` (v1) | `.model3.json` (v3) |
| 动作 | `.mtn` (二进制) | `.motion3.json` (JSON) |
| Art mesh | ~80 | 134 (Hiyori) |
| 变形器 | 仅旋转 | 弯曲 + 旋转 |
| Keyform | 每 part | 每 art mesh，带颜色混合 |
| 渲染器 | 固定管线 GL | GLSL 着色器 (#version 120) |
| 嵌入模块 | `live2d_embed.lua` | 直接 `live2d.cubism3.*` API |
| 纹理数量 | 1 | 2+ |

---

## 常见问题

### `require("ffi")` 在 lupa 中失败
lupa 基于标准 Lua 而非 LuaJIT 编译。重装：`pip install lupa --force-reinstall`（确保环境中有 LuaJIT 开发头文件）。

### 找不到模块
确保设置了 `package.path` 且工作目录是 repo 根目录。lupa 默认不会继承 Lua 的搜索路径。

### 顶点看起来扭曲/翻转
渲染器会做 Y 轴翻转 (`-vertex.y`)，将 Live2D 坐标系 (Y 向上) 转换为 OpenGL 屏幕坐标。请确保投影矩阵设置正确。

### 参数变化没有视觉效果
部分参数（如 `ParamAngleX`）影响变形器位置而非不透明度。视觉变化取决于变形器影响哪些 mesh。参数变更后请确保调用了 `runtime:update_meshes()`。
