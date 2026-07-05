# 在 Python 中嵌入 Live2D Cubism 3 (MOC3)

[English](Embedded2PythonCubism3.md) | [日本語](Embedded2PythonCubism3_jp.md)

## 架构概览

```
Python GUI (PySide6 / PyQt6 / wxPython 等)
  └─ QOpenGLWidget / GL canvas          ← 创建并持有 OpenGL context
       ├─ 初始化阶段
       │    ├─ 通过 live2d_moc3_embed.load_model() 创建 Renderer
       │    │    ├─ Python 读取 model3.json / moc3 / 纹理
       │    │    ├─ 设置 resource_streams 实现内存文件解析
       │    │    └─ Lua 内部解析 MOC3、构建 ModelRuntime
       │    ├─ 纹理解码 (PNG → RGBA via QImage)           ← Python 侧
       │    └─ 通过 renderer:set_gl(gl) 传入 OpenGL 绑定表
       │
       ├─ 逐帧更新
       │    ├─ renderer:start_motion(group, no)            ← 排队动作
       │    ├─ renderer:set_expression(name)               ← 排队表情
       │    ├─ renderer:set_parameter(id, value)           ← 驱动参数
       │    └─ renderer:update(delta_seconds)              ← 全部驱动 + 重建 mesh
       │
       ├─ 渲染
       │    └─ renderer:render(projection, texture_paths)  ← OpenGL 绘制调用
       │
       └─ QTimer(16ms)           ← 驱动刷新循环
```

**核心理念**：`live2d_moc3_embed.lua` 模块将整个 Cubism 3 管线封装成一个 `Renderer` 对象。Python 仅管理文件 I/O、纹理解码和 OpenGL 上下文。所有 Cubism 逻辑——MOC3 解析、参数求值、变形器组合、动作/表情播放、Pose 应用、mesh 生成和 OpenGL 绘制——全部由 Lua 渲染器内部处理。

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

## Embed API 参考

统一入口为 `live2d_moc3_embed.lua`。它提供了 `Renderer` 类（由 `require` 返回的表）和操作全局"当前"渲染器的模块级便捷函数。

```
live2d_moc3_embed.lua
  Renderer                        ← embed.new() / embed.load_model() 返回的实例
  embed.new(opts)                 ← 创建 Renderer（不加载模型）
  embed.load_model(path, opts)    ← 创建 + 加载，同时设为"当前"
  embed.current()                 ← 获取"当前"渲染器
  embed.update(dt)                ← 更新当前渲染器
  embed.get_meshes()              ← 从当前渲染器获取 mesh
  embed.set_parameter(id, val)    ← 在当前渲染器中设置参数
  embed.start_motion(g, n, w)     ← 在当前渲染器启动动作
  embed.clear_motions()           ← 清除当前渲染器的动作
  embed.set_expression(name, w)   ← 在当前渲染器设置表情
  embed.clear_expressions()       ← 清除当前渲染器的表情
  embed.render(proj, tex_paths)   ← 渲染当前渲染器
  embed.dispose()                 ← 释放当前渲染器
```

### 创建 Renderer

```python
from lupa.luajit21 import LuaRuntime

lua = LuaRuntime(unpack_returned_tuples=True, encoding=None)
lua.execute(b'package.path = package.path .. ";./?.lua;./?/init.lua"')

embed = lua.execute(b'return require("live2d_moc3_embed")')

# 方式 A：一步创建并加载
renderer = embed.load_model("resources/Hiyori/Hiyori.model3.json")

# 方式 B：先创建再加载
renderer = embed.new()
renderer:load_model("resources/Hiyori/Hiyori.model3.json")
```

`load_model()` 方法执行：
- 读取 `model3.json` → 提取 `FileReferences`
- 读取 `.moc3` 二进制 → 解析全部 14 个 MOC3 段
- 如有 `pose3.json` 则读取
- 内部构建 `ModelRuntime`
- 存储 `FileReferences.Textures` 中的纹理路径

### 资源流（内存加载）

Python 可预加载数据到内存并注册为资源流，Lua 侧可直接从 Python 侧的字节缓冲区解析文件，无需磁盘访问。

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

渲染器优先从 `resource_streams` 解析文件路径，未命中则回退到磁盘读取。流值支持：
- 原始 string/bytes
- 返回数据的零参数函数
- 带有 `.data` / `.bytes` / `[1]` 字段的表

### 参数控制

```python
# 按字符串 ID 设置
renderer:set_parameter("ParamAngleX", 30.0)               # 原始值
renderer:set_parameter_normalized("ParamEyeLOpen", 0.8)    # 归一化值 0-1

# 按索引设置
renderer:set_parameter_by_index(0, 15.0)

# 读取当前值
value = renderer:get_parameter("ParamAngleX")              # 原始值
value = renderer:get_parameter_normalized("ParamAngleX")    # 0-1
value = renderer:get_parameter_by_index(0)

# 参数元数据
info = renderer:get_parameter_info("ParamAngleX")
print(info.id, info.minimum, info.maximum, info.default)

# 恢复默认值
renderer:reset_parameters()
```

**参数覆盖**——在动作和表情*之后*应用，适用于叠加或附加偏移：

```python
renderer:set_parameter_override("ParamEyeLOpen", 1.0)
renderer:set_parameter_override_normalized("ParamMouthOpenY", 0.5)
renderer:clear_parameter_override("ParamEyeLOpen")
renderer:clear_parameter_overrides()  # 清除全部
```

### Part 透明度控制

```python
renderer:set_part_opacity("PartArmL", 0.5)
renderer:set_part_opacity_by_index(0, 1.0)
renderer:reset_part_opacities()
```

### 动作播放

动作按组（如 `"Idle"`、`"TapBody"`）组织，组内从 0 索引，与 `model3.json` 的 `FileReferences.Motions` 结构一致。

```python
# 启动动作（组名、动作索引、可选权重 0-1）
renderer:start_motion("Idle", 0, 1.0)

# 同时启动多个动作
renderer:start_motion("Idle", 0)
renderer:start_motion("TapBody", 2, 0.5)

# 清除所有播放中的动作
renderer:clear_motions()
```

动作首次使用时自动解析并缓存。已完成的动作在 `update()` 期间自动移除。

### 表情播放

```python
# 按名称（来自 FileReferences.Expressions）
renderer:set_expression("f01", 1.0)

# 按索引
renderer:set_expression(0)

# 清除所有表情（恢复基础参数值）
renderer:clear_expressions()
```

表情内部使用 `ExpressionManager`，支持 `.exp3.json` 文件中定义的 Add/Multiply/Overwrite 混合模式。`FadeInTime`/`FadeOutTime` 中的淡入淡出时间被遵循；负值表示"继承模型默认值"。

### 逐帧更新

```python
def on_frame(delta_seconds: float):
    # 这一调用将依次执行：
    #   1. 驱动所有活动动作播放器
    #   2. 将动作参数变化应用到运行时
    #   3. 驱动表情管理器
    #   4. 将表情混合应用到运行时
    #   5. 应用参数覆盖
    #   6. 应用 Pose 淡入（Part 透明度）
    #   7. 重建所有 mesh（变形器组合 + 顶点生成）
    renderer:update(delta_seconds)
```

### 访问 Mesh 数据

```python
meshes = renderer:get_meshes()  # Lua 表，1 索引
for i in range(1, len(meshes) + 1):
    mesh = meshes[i]
    print(f"mesh[{i}]: tex={mesh.texture_index}, opacity={mesh.opacity}, "
          f"verts={len(mesh.vertices)}, indices={len(mesh.indices)}")
```

### Mesh 数据结构

每个 `Moc3DrawableMesh` 包含：

| 字段 | 类型 | 说明 |
|------|------|------|
| `texture_index` | int | 纹理数组索引 |
| `drawable_flags` | int | 混合模式 + mask 反转标志 |
| `opacity` | float | 最终计算的不透明度 (0.0–1.0) |
| `draw_order` | float | 从 Keyform 插值的绘制顺序 |
| `render_order` | int | MOC3 指定的渲染顺序 (slot 87) |
| `multiply_color` | `{r,g,b,a}` | 正片叠底颜色 (预乘 alpha) |
| `screen_color` | `{r,g,b,a}` | 滤色颜色 (预乘 alpha) |
| `vertices` | table | `{position={x,y}, uv={u,v}}` 数组 |
| `indices` | table | uint16 三角形索引数组 |
| `masks` | table | 裁剪 mask drawable ID 数组 |

### 渲染

```python
# GL 初始化时执行一次：
renderer:set_gl(gl_table)  # 传入 PyOpenGL 模块或等效 GL 绑定

# 上传纹理到 OpenGL (Python 侧):
texture_paths = renderer:get_texture_paths()  # 返回解析后的绝对路径
for i, path in enumerate(texture_paths):
    rgba = decode_png_to_rgba(path)
    gl.glBindTexture(GL_TEXTURE_2D, texture_ids[i])
    gl.glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, w, h, 0, GL_RGBA, GL_UNSIGNED_BYTE, rgba)

# 逐帧渲染:
projection = compute_ortho_matrix(w, h)
renderer:render(projection, texture_paths)
```

`render()` 内部处理：
- 按 `render_order`（主键）和 `draw_order`（次键）排序绘制调用
- 裁剪 mask 设置（模板缓冲区）
- 混合模式选择（正常 / 加法 / 正片叠底）
- Shader uniform 上传（投影矩阵、基础色、正片叠底色、滤色）

### 混合模式

| 标志位 | 混合模式 | GL 混合设置 |
|--------|---------|------------|
| bit 0 | 加法 | `glBlendFunc(GL_ONE, GL_ONE)` |
| bit 1 | 正片叠底 | `glBlendFunc(GL_DST_COLOR, GL_ONE_MINUS_SRC_ALPHA)` |
| 都没有 | 正常 | `glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA)` |

> 渲染器使用预乘 alpha 管线：片元输出为 `vec4(rgb * alpha, alpha)`，混合方程已适配。

### 资源释放

```python
renderer:dispose()    # 清除运行时、缓存、纹理引用，触发 GC
```

---

## 完整 PySide6 集成示例

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

        # 预加载模型文件为资源流（Lua 执行期间无磁盘 I/O）
        self.renderer = self.embed.new({"resourceStreams": {
            "Hiyori.model3.json": (MODEL_BASE / "Hiyori.model3.json").read_text(),
            "Hiyori.moc3":        (MODEL_BASE / "Hiyori.moc3").read_bytes(),
            "Hiyori.pose3.json":  (MODEL_BASE / "Hiyori.pose3.json").read_text(),
        }})
        self.renderer:load_model("Hiyori.model3.json")

        # 设置 GL
        import OpenGL.GL as gl
        self.renderer:set_gl(gl)  # PyOpenGL 模块作为 GL 绑定

        # 加载纹理
        self.texture_ids = {}
        for i, tex_path in enumerate(self.renderer:get_texture_paths()):
            img = QImage(tex_path).convertToFormat(QImage.Format_RGBA8888)
            self.texture_ids[i] = gl.glGenTextures(1)
            gl.glBindTexture(gl.GL_TEXTURE_2D, self.texture_ids[i])
            gl.glTexImage2D(gl.GL_TEXTURE_2D, 0, gl.GL_RGBA8,
                            img.width(), img.height(), 0,
                            gl.GL_RGBA, gl.GL_UNSIGNED_BYTE,
                            img.constBits().tobytes())

        # 启动默认待机动作
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

## 模块级便捷 API

对于快速脚本或单模型使用场景，embed 模块维护一个"当前"渲染器：

```python
embed = lua.execute(b'return require("live2d_moc3_embed")')

# 一行加载（设为当前）
r = embed.load_model("resources/Hiyori/Hiyori.model3.json")

# 模块级辅助函数操作当前渲染器
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

## 访问底层模块

embed 表暴露了底层模块引用，供高级场景使用：

```python
moc3        = embed.moc3           # live2d.cubism3.moc3
model3      = embed.model3         # live2d.cubism3.json.model3
motion3     = embed.motion3        # live2d.cubism3.json.motion3
expression3 = embed.expression3     # live2d.cubism3.json.expression3
pose3       = embed.pose3          # live2d.cubism3.json.pose3
Renderer    = embed.Renderer       # Renderer 类（Lua 侧子类化用）
ModelRuntime = embed.ModelRuntime  # ModelRuntime 类
MotionPlayer = embed.MotionPlayer  # MotionPlayer 类
```

```python
# 访问底层运行时进行直接控制
runtime = renderer:get_runtime()
model_data = renderer:get_model_data()
```

---

## 与 Cubism 2.1 的区别

| 方面 | Cubism 2.1 | Cubism 3 |
|------|-----------|----------|
| 模型格式 | `.moc` (二进制 v2) | `.moc3` (二进制 v3/v4/v5) |
| 配置文件 | `.model.json` (v1) | `.model3.json` (v3) |
| 动作 | `.mtn` (二进制) | `.motion3.json` (JSON) |
| 表情 | `.json` (旧格式) | `.exp3.json` (Cubism 3) |
| Art mesh | ~80 | 134 (Hiyori), 311 (Rana v5) |
| 变形器 | 仅旋转 | 弯曲 + 旋转 |
| Keyform | 每 Part | 每 Art mesh，带颜色混合 |
| 渲染器 | 固定管线 GL | GLSL 着色器 (#version 120)，模板裁剪 |
| 嵌入模块 | `live2d_embed.lua` | `live2d_moc3_embed.lua` |
| 纹理数量 | 1 | 2+ |
| Pose | — | `pose3.json` (Part 透明度 + Art mesh 淡入) |
| Draw order group | — | Cubism 5 绘制顺序组扩展 |

---

## 常见问题

### `require("ffi")` 在 lupa 中失败
lupa 基于标准 Lua 而非 LuaJIT 编译。重装：`pip install lupa --force-reinstall`（确保环境中有 LuaJIT 开发头文件）。

### 找不到模块
确保设置了 `package.path` 且工作目录是 repo 根目录。lupa 默认不会继承 Lua 的搜索路径。

### 资源流无法解析
资源流键值按规范化路径匹配（反斜杠 → 正斜杠，去除尾部斜杠）。检查键值是否与 `model3.json` 引用产生的路径一致。

### 顶点扭曲/翻转
渲染器做 Y 轴翻转 (`-vertex.y`) 将 Live2D 坐标系 (Y 向上) 转换为 OpenGL 屏幕坐标。确保投影矩阵正确。

### 裁剪/透明度异常
裁剪 mask 需要模板缓冲区（8-bit）。在 `glClear` 中包含 `GL_STENCIL_BUFFER_BIT`，并请求支持模板的帧缓冲。渲染器在模板写入时将 mask mesh 透明度强制设为 1.0——Pose 中透明度为 0 的 mask mesh 不会丢失裁剪能力。

### 参数改变后没有视觉效果
`ParamAngleX` 等参数影响变形器位置而非不透明度。视觉效果取决于变形器控制哪些 mesh。参数变更后确保调用了 `renderer:update()`。
