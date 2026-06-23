# Embedding Live2D Cubism 3 (MOC3) in Python

[English](Embedded2PythonCubism3.md) | [中文](Embedded2PythonCubism3_cn.md)

## アーキテクチャ概要

```
Python GUI (PySide6 / PyQt6 / wxPython など)
  └─ QOpenGLWidget / GL canvas          ← OpenGL コンテキストを作成・保持
       ├─ 初期化フェーズ
       │    ├─ Hiyori.model3.json を読み込み              ← Python が読み Lua に渡す
       │    ├─ Hiyori.moc3 バイナリを読み込み              ← Python が読み Lua に渡す
       │    ├─ テクスチャデコード (PNG → RGBA via QImage)  ← Python 側
       │    ├─ モーション / ポーズ JSON を読み込み         ← Python が読み Lua に渡す
       │    └─ Lua 内で ModelRuntime を構築                ← lupa LuaRuntime
       │
       ├─ フレーム更新
       │    ├─ モーションプレイヤーを駆動 (デルタ時間)
       │    ├─ モーション適用 → ランタイムパラメータ
       │    ├─ ポーズ適用 → パート透明度
       │    └─ runtime:update_meshes()
       │
       ├─ レンダリング
       │    ├─ メッシュリスト + テクスチャ ID + 投影行列を渡す
       │    └─ OpenGL シェーダーが全 134 メッシュを描画
       │
       └─ QTimer(16ms)           ← リフレッシュループを駆動
```

**核心理念**：Python 側がファイル I/O とテクスチャデコードを管理し、Lua 側がすべての Cubism 3 データ処理——MOC3 バイナリ解析、パラメータ評価、デフォーマー合成、メッシュ生成を担当します。OpenGL レンダラーが描画を処理します。

## 前提条件

### 1. LuaJIT ランタイム

このプロジェクトは LuaJIT の `ffi` モジュールに依存しています。**標準 Lua インタプリタでは動作しません**。

| 方法 | ライブラリ | 原理 | 推奨度 |
|------|-----------|------|--------|
| lupa (LuaJIT 版) | `pip install lupa` | `import lupa.luajit21` | ★★★ 推奨 |
| ctypes + luajit.dll | システムの `luajit-2.1.dll` | ctypes で DLL ロード、Lua C API 呼出 | ★★☆ 代替案 |

### 2. OpenGL ウィジェット

Python GUI は OpenGL 対応ウィジェットを提供する必要があります：
- **PySide6** / **PyQt6**：`QOpenGLWidget`（本ガイドで使用）
- **wxPython**：`wx.GLCanvas`

> ⚠️ Cubism 3 レンダラーは GLSL シェーダー (GL `#version 120`) を使用します。GL 2.1+ コンテキストが必要です。

### 3. 依存関係のインストール

```bash
pip install PySide6 lupa
```

> **重要**：lupa は LuaJIT に基づいてコンパイルされている必要があります。確認方法：

```python
lua = LuaRuntime()
assert lua.execute(b'return require("ffi")'), "lupa は LuaJIT FFI でビルドされている必要があります"
```

---

## Cubism 3 API リファレンス

Lua モジュール構造：

```
live2d.cubism3.
  init.lua                    # モジュールエントリ
  core/                       # 数学、補間、デフォーマー、物理演算
  json/                       # model3, motion3, physics3, pose3, cdi3
  moc3/                       # MOC3 バイナリ解析 (14 セクション)
  runtime.lua                 # ModelRuntime
  motion.lua                  # MotionPlayer
  opengl_renderer.lua         # OpenGLRenderer
```

### モデルの読み込み

```python
import os
from pathlib import Path
from lupa.luajit21 import LuaRuntime

lua = LuaRuntime(unpack_returned_tuples=True, encoding=None)
lua.execute(b'package.path = package.path .. ";./?.lua;./?/init.lua"')

# モジュールの読み込み
ModelRuntime = lua.execute(b'return require("live2d.cubism3.runtime")')
model3       = lua.execute(b'return require("live2d.cubism3.json.model3")')
pose3        = lua.execute(b'return require("live2d.cubism3.json.pose3")')
motion3      = lua.execute(b'return require("live2d.cubism3.json.motion3")')
MotionPlayer = lua.execute(b'return require("live2d.cubism3.motion")')
moc3         = lua.execute(b'return require("live2d.cubism3.moc3")')

# モデルファイルの読み込み
base = Path("resources/Hiyori")
model_json = (base / "Hiyori.model3.json").read_text()
moc_bytes  = (base / "Hiyori.moc3").read_bytes()
pose_json  = (base / "Hiyori.pose3.json").read_text()

# JSON の解析
model_data = model3.parse(model_json)
pose_data  = pose3.parse(pose_json)

# MOC3 バイナリの解析
canvas     = moc3.canvas.parse(moc_bytes)
ids        = moc3.ids.parse(moc_bytes)
bindings   = moc3.keyform_bindings.parse(moc_bytes)
parts      = moc3.parts.parse(moc_bytes)
deformers  = moc3.deformers.parse(moc_bytes)
art_meshes = moc3.art_meshes.parse(moc_bytes)
keyforms   = moc3.keyforms.parse(moc_bytes)
offscreen  = moc3.offscreen.parse(moc_bytes)

# ランタイムの構築
runtime = ModelRuntime.new(
    model_data, canvas, art_meshes, keyforms,
    deformers, bindings, ids, offscreen, parts, pose_data
)
```

### パラメータ制御

```python
# 名前でパラメータインデックスを取得
idx = runtime:parameter_index_of("ParamAngleX")
if idx is not None:
    runtime:set_parameter_by_index(idx, 0.5)

# 文字列 ID で設定
runtime:set_parameter("ParamEyeLOpen", 0.8)

# 現在の値を取得
params = runtime.parameter_values  # Lua テーブル、Python から走査可能

# デフォルトにリセット
runtime:reset_parameters()
```

### モーション再生

```python
# モーションを読み込み
motion_json = (base / "motions/Hiyori_m01.motion3.json").read_text()
motion_data = motion3.parse(motion_json)
player = MotionPlayer.new(motion_data)

# 毎フレーム:
player:tick(delta_seconds)
player:apply(runtime)
runtime:update_meshes()

# 状態を確認
if player:is_finished():
    player:restart()
```

### レンダリング

```python
# OpenGL コンテキストをセットアップ後:

# テクスチャの読み込み
for i, tex_rel in enumerate(model_data.file_references.textures):
    tex_path = base / tex_rel
    # QImage / PIL などで PNG を RGBA にデコード
    rgba = decode_png_to_rgba(tex_path)
    gl.glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, w, h, 0, GL_RGBA, GL_UNSIGNED_BYTE, rgba)

# 毎フレームの描画:
meshes = runtime.meshes  # 134 個の Moc3DrawableMesh を含む Lua テーブル
for mesh_idx in range(len(meshes)):
    mesh = meshes[mesh_idx + 1]  # Lua は 1 インデックス
    if mesh.opacity > 0.001:
        draw_mesh(mesh, projection_matrix)
```

### メッシュデータ構造

各 `Moc3DrawableMesh` に含まれるフィールド：

| フィールド | 型 | 説明 |
|-----------|-----|------|
| `texture_index` | int | テクスチャ配列のインデックス (Hiyori は 0 か 1) |
| `drawable_flags` | int | ブレンドモード + マスク反転フラグ |
| `opacity` | float | 最終計算透明度 (0.0–1.0) |
| `draw_order` | float | モデルの生の描画順序 |
| `render_order` | int | 解決済みのレンダリング順序 |
| `multiply_color` | `{r,g,b}` | 乗算ブレンド色 |
| `screen_color` | `{r,g,b}` | スクリーンブレンド色 |
| `vertices` | table | `{position={x,y}, uv={u,v}}` の配列 |
| `indices` | table | uint16 三角形インデックスの配列 |
| `masks` | table | クリッピングマスク ID の配列 |

### ブレンドモード

| フラグビット | ブレンドモード | GL ブレンド設定 |
|-------------|--------------|----------------|
| bit 0 | 加算 | `glBlendFunc(GL_SRC_ALPHA, GL_ONE)` |
| bit 1 | 乗算 | `glBlendFunc(GL_DST_COLOR, GL_ONE_MINUS_SRC_ALPHA)` |
| どちらもなし | 通常 | `glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)` |

---

## 完全な lupa 統合例

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

        # よく呼ばれる Lua 関数をキャッシュ
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

## Cubism 2.1 との主な違い

| 項目 | Cubism 2.1 | Cubism 3 |
|------|-----------|----------|
| モデル形式 | `.moc` (バイナリ v2) | `.moc3` (バイナリ v3/v4/v5) |
| 設定ファイル | `.model.json` (v1) | `.model3.json` (v3) |
| モーション | `.mtn` (バイナリ) | `.motion3.json` (JSON) |
| アートメッシュ | ~80 | 134 (Hiyori) |
| デフォーマー | 回転のみ | ワープ + 回転 |
| キーフォーム | パート単位 | アートメッシュ単位、色ブレンド付き |
| レンダラー | 固定機能 GL | GLSL シェーダー (#version 120) |
| 埋め込みモジュール | `live2d_embed.lua` | `live2d.cubism3.*` API 直接 |
| テクスチャ数 | 1 | 2+ |

---

## トラブルシューティング

### `require("ffi")` が lupa で失敗する
お使いの lupa は標準 Lua でコンパイルされています。LuaJIT ではありません。再インストール：`pip install lupa --force-reinstall`（環境に LuaJIT 開発ヘッダーが必要です）。

### モジュールが見つからない
`package.path` が設定されており、作業ディレクトリがリポジトリルートであることを確認してください。lupa はデフォルトで Lua の検索パスを継承しません。

### 頂点が歪んで見える（引き伸ばし / 反転）
レンダラーは Y 軸反転 (`-vertex.y`) を行い、Live2D 座標系 (Y 上向き) から OpenGL 画面座標に変換します。投影行列が正しく設定されていることを確認してください。

### パラメータ変更が視覚効果を持たない
一部のパラメータ（例: `ParamAngleX`）は不透明度ではなくデフォーマーの位置に影響します。視覚的変化はデフォーマーがどのメッシュに影響するかに依存します。パラメータ変更後に `runtime:update_meshes()` が呼ばれていることを確認してください。
