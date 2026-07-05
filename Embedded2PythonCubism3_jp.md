# Python で Live2D Cubism 3 (MOC3) を埋め込む

[English](Embedded2PythonCubism3.md) | [中文](Embedded2PythonCubism3_cn.md)

## アーキテクチャ概要

```
Python GUI (PySide6 / PyQt6 / wxPython など)
  └─ QOpenGLWidget / GL canvas          ← OpenGL コンテキストを作成・保持
       ├─ 初期化フェーズ
       │    ├─ live2d_moc3_embed.load_model() で Renderer を作成
       │    │    ├─ Python が model3.json / moc3 / テクスチャを読み込み
       │    │    ├─ resource_streams でメモリ内ファイル解決を設定
       │    │    └─ Lua が内部で MOC3 を解析、ModelRuntime を構築
       │    ├─ テクスチャデコード (PNG → RGBA via QImage)  ← Python 側
       │    └─ renderer:set_gl(gl) で OpenGL バインディングテーブルを渡す
       │
       ├─ フレーム更新
       │    ├─ renderer:start_motion(group, no)              ← モーションをキュー
       │    ├─ renderer:set_expression(name)                 ← エクスプレッションをキュー
       │    ├─ renderer:set_parameter(id, value)             ← パラメータ駆動
       │    └─ renderer:update(delta_seconds)                ← 全駆動 + メッシュ再構築
       │
       ├─ レンダリング
       │    └─ renderer:render(projection, texture_paths)    ← OpenGL 描画呼出
       │
       └─ QTimer(16ms)           ← リフレッシュループを駆動
```

**核心理念**：`live2d_moc3_embed.lua` モジュールは Cubism 3 のパイプライン全体を単一の `Renderer` オブジェクトにカプセル化します。Python 側はファイル I/O、テクスチャデコード、OpenGL コンテキストのみを管理します。MOC3 解析、パラメータ評価、デフォーマー合成、モーション/エクスプレッション再生、ポーズ適用、メッシュ生成、OpenGL 描画といった Cubism ロジックはすべて Lua レンダラーが内部で処理します。

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

## Embed API リファレンス

単一のエントリポイントは `live2d_moc3_embed.lua` です。`Renderer` クラス（`require` から返されるテーブル）と、グローバルな「カレント」レンダラーを操作するモジュールレベルの便利関数を提供します。

```
live2d_moc3_embed.lua
  Renderer                        ← embed.new() / embed.load_model() が返すインスタンス
  embed.new(opts)                 ← モデル未ロードの Renderer を作成
  embed.load_model(path, opts)    ← 作成 + ロードを一度に（「カレント」として設定）
  embed.current()                 ← 「カレント」レンダラーを取得
  embed.update(dt)                ← カレントを更新
  embed.get_meshes()              ← カレントからメッシュを取得
  embed.set_parameter(id, val)    ← カレントにパラメータを設定
  embed.start_motion(g, n, w)     ← カレントでモーションを開始
  embed.clear_motions()           ← カレントのモーションをクリア
  embed.set_expression(name, w)   ← カレントにエクスプレッションを設定
  embed.clear_expressions()       ← カレントのエクスプレッションをクリア
  embed.render(proj, tex_paths)   ← カレントをレンダリング
  embed.dispose()                 ← カレントを破棄
```

### Renderer の作成

```python
from lupa.luajit21 import LuaRuntime

lua = LuaRuntime(unpack_returned_tuples=True, encoding=None)
lua.execute(b'package.path = package.path .. ";./?.lua;./?/init.lua"')

embed = lua.execute(b'return require("live2d_moc3_embed")')

# 方法 A: 一度に作成してロード
renderer = embed.load_model("resources/Hiyori/Hiyori.model3.json")

# 方法 B: 先に作成、後からロード
renderer = embed.new()
renderer:load_model("resources/Hiyori/Hiyori.model3.json")
```

`load_model()` メソッドの動作：
- `model3.json` を読み込み → `FileReferences` を抽出
- `.moc3` バイナリを読み込み → 全 14 MOC3 セクションを解析
- 存在すれば `.pose3.json` を読み込み
- 内部で `ModelRuntime` を構築
- `FileReferences.Textures` からテクスチャパスを保持

### リソースストリーム（メモリ内ロード）

Python がデータをメモリに事前ロードし、リソースストリームとして登録することで、Lua 側はディスクアクセスなしで Python 側のバイトバッファからファイルを解決できます。

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

レンダラーはファイルパスをまず `resource_streams` で解決し、未ヒットの場合はディスクにフォールバックします。ストリーム値には以下が使用可能です：
- 生の string/bytes
- データを返す引数なし関数
- `.data` / `.bytes` / `[1]` フィールドを持つテーブル

### パラメータ制御

```python
# 文字列 ID で設定
renderer:set_parameter("ParamAngleX", 30.0)                # 生の値
renderer:set_parameter_normalized("ParamEyeLOpen", 0.8)     # 正規化値 0-1

# インデックスで設定
renderer:set_parameter_by_index(0, 15.0)

# 現在値を読み取り
value = renderer:get_parameter("ParamAngleX")               # 生の値
value = renderer:get_parameter_normalized("ParamAngleX")     # 0-1
value = renderer:get_parameter_by_index(0)

# パラメータのメタデータ
info = renderer:get_parameter_info("ParamAngleX")
print(info.id, info.minimum, info.maximum, info.default)

# デフォルト値にリセット
renderer:reset_parameters()
```

**パラメータオーバーライド** — モーションやエクスプレッションの*後*に適用され、ブレンドや加算オフセットに便利：

```python
renderer:set_parameter_override("ParamEyeLOpen", 1.0)
renderer:set_parameter_override_normalized("ParamMouthOpenY", 0.5)
renderer:clear_parameter_override("ParamEyeLOpen")
renderer:clear_parameter_overrides()  # すべてクリア
```

### パート透明度制御

```python
renderer:set_part_opacity("PartArmL", 0.5)
renderer:set_part_opacity_by_index(0, 1.0)
renderer:reset_part_opacities()
```

### モーション再生

モーションはグループ（例: `"Idle"`、`"TapBody"`）で整理され、グループ内で 0 から始まるインデックスで参照します。`model3.json` の `FileReferences.Motions` 構造と一致します。

```python
# モーションを開始（グループ名、モーションインデックス、オプションの重み 0-1）
renderer:start_motion("Idle", 0, 1.0)

# 複数モーションを同時に開始
renderer:start_motion("Idle", 0)
renderer:start_motion("TapBody", 2, 0.5)

# すべての再生中モーションをクリア
renderer:clear_motions()
```

モーションは初回使用時に自動的に解析・キャッシュされます。完了したモーションは `update()` 中に自動的に削除されます。

### エクスプレッション再生

```python
# 名前で指定（FileReferences.Expressions から）
renderer:set_expression("f01", 1.0)

# インデックスで指定
renderer:set_expression(0)

# すべてのエクスプレッションをクリア（ベースパラメータ値を復元）
renderer:clear_expressions()
```

エクスプレッションは内部的に `ExpressionManager` を使用し、`.exp3.json` ファイルで定義された Add/Multiply/Overwrite ブレンドモードをサポートします。`FadeInTime`/`FadeOutTime` のフェード時間が反映され、負の値は「モデルデフォルトを継承」を意味します。

### フレーム更新

```python
def on_frame(delta_seconds: float):
    # この単一呼出で以下を実行：
    #   1. すべてのアクティブなモーションプレイヤーを駆動
    #   2. モーションパラメータ変更をランタイムに適用
    #   3. エクスプレッションマネージャーを駆動
    #   4. エクスプレッションブレンドをランタイムに適用
    #   5. パラメータオーバーライドを適用
    #   6. ポーズフェードを適用（パート透明度）
    #   7. 全メッシュを再構築（デフォーマー合成 + 頂点生成）
    renderer:update(delta_seconds)
```

### メッシュデータへのアクセス

```python
meshes = renderer:get_meshes()  # Lua テーブル、1 インデックス
for i in range(1, len(meshes) + 1):
    mesh = meshes[i]
    print(f"mesh[{i}]: tex={mesh.texture_index}, opacity={mesh.opacity}, "
          f"verts={len(mesh.vertices)}, indices={len(mesh.indices)}")
```

### メッシュデータ構造

各 `Moc3DrawableMesh` に含まれるフィールド：

| フィールド | 型 | 説明 |
|-----------|-----|------|
| `texture_index` | int | テクスチャ配列のインデックス |
| `drawable_flags` | int | ブレンドモード + マスク反転フラグ |
| `opacity` | float | 最終計算透明度 (0.0–1.0) |
| `draw_order` | float | キーフォームから補間された描画順序 |
| `render_order` | int | MOC3 指定のレンダリング順序 (slot 87) |
| `multiply_color` | `{r,g,b,a}` | 乗算ブレンド色 (プリマルチプライド) |
| `screen_color` | `{r,g,b,a}` | スクリーンブレンド色 (プリマルチプライド) |
| `vertices` | table | `{position={x,y}, uv={u,v}}` の配列 |
| `indices` | table | uint16 三角形インデックスの配列 |
| `masks` | table | クリッピングマスク drawable ID の配列 |

### レンダリング

```python
# GL 初期化時に一度だけ実行：
renderer:set_gl(gl_table)  # PyOpenGL モジュールまたは同等の GL バインディングを渡す

# テクスチャを OpenGL にアップロード（Python 側）:
texture_paths = renderer:get_texture_paths()  # 解決済みの絶対パスを返す
for i, path in enumerate(texture_paths):
    rgba = decode_png_to_rgba(path)
    gl.glBindTexture(GL_TEXTURE_2D, texture_ids[i])
    gl.glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, w, h, 0, GL_RGBA, GL_UNSIGNED_BYTE, rgba)

# 毎フレームの描画:
projection = compute_ortho_matrix(w, h)
renderer:render(projection, texture_paths)
```

`render()` の内部処理：
- `render_order`（主キー）と `draw_order`（タイブレーカー）で描画呼出をソート
- クリッピングマスク設定（ステンシルバッファ）
- ブレンドモード選択（通常 / 加算 / 乗算）
- シェーダー uniform アップロード（投影行列、ベース色、乗算色、スクリーン色）

### ブレンドモード

| フラグビット | ブレンドモード | GL ブレンド設定 |
|-------------|--------------|----------------|
| bit 0 | 加算 | `glBlendFunc(GL_ONE, GL_ONE)` |
| bit 1 | 乗算 | `glBlendFunc(GL_DST_COLOR, GL_ONE_MINUS_SRC_ALPHA)` |
| どちらもなし | 通常 | `glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA)` |

> レンダラーはプリマルチプライドアルファパイプラインを使用します：フラグメント出力は `vec4(rgb * alpha, alpha)` で、ブレンド方程式がこれに対応しています。

### クリーンアップ

```python
renderer:dispose()    # ランタイム、キャッシュ、テクスチャ参照をクリアし、GC をトリガー
```

---

## 完全な PySide6 統合例

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

        # モデルファイルをリソースストリームとして事前ロード（Lua 実行中のディスク I/O 不要）
        self.renderer = self.embed.new({"resourceStreams": {
            "Hiyori.model3.json": (MODEL_BASE / "Hiyori.model3.json").read_text(),
            "Hiyori.moc3":        (MODEL_BASE / "Hiyori.moc3").read_bytes(),
            "Hiyori.pose3.json":  (MODEL_BASE / "Hiyori.pose3.json").read_text(),
        }})
        self.renderer:load_model("Hiyori.model3.json")

        # GL を設定
        import OpenGL.GL as gl
        self.renderer:set_gl(gl)  # PyOpenGL モジュールを GL バインディングとして渡す

        # テクスチャをロード
        self.texture_ids = {}
        for i, tex_path in enumerate(self.renderer:get_texture_paths()):
            img = QImage(tex_path).convertToFormat(QImage.Format_RGBA8888)
            self.texture_ids[i] = gl.glGenTextures(1)
            gl.glBindTexture(gl.GL_TEXTURE_2D, self.texture_ids[i])
            gl.glTexImage2D(gl.GL_TEXTURE_2D, 0, gl.GL_RGBA8,
                            img.width(), img.height(), 0,
                            gl.GL_RGBA, gl.GL_UNSIGNED_BYTE,
                            img.constBits().tobytes())

        # デフォルト待機モーションを開始
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

## モジュールレベルの便利 API

クイックスクリプトや単一モデル利用向けに、embed モジュールは「カレント」レンダラーを管理します：

```python
embed = lua.execute(b'return require("live2d_moc3_embed")')

# ワンライナーロード（カレントとして設定）
r = embed.load_model("resources/Hiyori/Hiyori.model3.json")

# モジュールレベルのヘルパーがカレントレンダラーを操作
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

## 下位モジュールへのアクセス

embed テーブルは高度な利用のために下位モジュール参照を公開します：

```python
moc3        = embed.moc3           # live2d.cubism3.moc3
model3      = embed.model3         # live2d.cubism3.json.model3
motion3     = embed.motion3        # live2d.cubism3.json.motion3
expression3 = embed.expression3     # live2d.cubism3.json.expression3
pose3       = embed.pose3          # live2d.cubism3.json.pose3
Renderer    = embed.Renderer       # Renderer クラス（Lua でのサブクラス化用）
ModelRuntime = embed.ModelRuntime  # ModelRuntime クラス
MotionPlayer = embed.MotionPlayer  # MotionPlayer クラス
```

```python
# 下位ランタイムにアクセスして直接制御
runtime = renderer:get_runtime()
model_data = renderer:get_model_data()
```

---

## Cubism 2.1 との主な違い

| 項目 | Cubism 2.1 | Cubism 3 |
|------|-----------|----------|
| モデル形式 | `.moc` (バイナリ v2) | `.moc3` (バイナリ v3/v4/v5) |
| 設定ファイル | `.model.json` (v1) | `.model3.json` (v3) |
| モーション | `.mtn` (バイナリ) | `.motion3.json` (JSON) |
| エクスプレッション | `.json` (旧形式) | `.exp3.json` (Cubism 3) |
| アートメッシュ | ~80 | 134 (Hiyori), 311 (Rana v5) |
| デフォーマー | 回転のみ | ワープ + 回転 |
| キーフォーム | パート単位 | アートメッシュ単位、色ブレンド付き |
| レンダラー | 固定機能 GL | GLSL シェーダー (#version 120)、ステンシルクリッピング |
| 埋め込みモジュール | `live2d_embed.lua` | `live2d_moc3_embed.lua` |
| テクスチャ数 | 1 | 2+ |
| ポーズ | — | `pose3.json` (パート透明度 + アートメッシュフェード) |
| 描画順序グループ | — | Cubism 5 描画順序グループ拡張 |

---

## トラブルシューティング

### `require("ffi")` が lupa で失敗する
お使いの lupa は標準 Lua でコンパイルされています。LuaJIT ではありません。再インストール：`pip install lupa --force-reinstall`（環境に LuaJIT 開発ヘッダーが必要です）。

### モジュールが見つからない
`package.path` が設定されており、作業ディレクトリがリポジトリルートであることを確認してください。lupa はデフォルトで Lua の検索パスを継承しません。

### リソースストリームが解決されない
リソースストリームのキーは正規化パス（バックスラッシュ → スラッシュ、末尾スラッシュ除去）でマッチングされます。キーが `model3.json` の参照と一致しているか確認してください。

### 頂点が歪んで見える（引き伸ばし / 反転）
レンダラーは Y 軸反転 (`-vertex.y`) を行い、Live2D 座標系 (Y 上向き) から OpenGL 画面座標に変換します。投影行列が正しく設定されていることを確認してください。

### クリッピング / 透明度の異常
クリッピングマスクにはステンシルバッファ（8-bit）が必要です。`glClear` に `GL_STENCIL_BUFFER_BIT` を含め、ステンシル対応フレームバッファをリクエストしてください。レンダラーはステンシル書き込み時にマスクメッシュの透明度を 1.0 に強制します——ポーズで透明度 0 のマスクメッシュもクリッピング機能を失いません。

### パラメータ変更が視覚効果を持たない
`ParamAngleX` のようなパラメータは不透明度ではなくデフォーマーの位置に影響します。視覚的変化はデフォーマーがどのメッシュに影響するかに依存します。パラメータ変更後に `renderer:update()` が呼ばれていることを確認してください。
