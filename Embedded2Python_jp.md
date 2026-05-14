# Embedding Live2D in Python

[English](Embedded2Python.md) | [中文](Embedded2Python_cn.md)

## アーキテクチャ概要

```
Python GUI (PySide6 / PyQt6 / wxPython など)
  └─ QOpenGLWidget / GL canvas          ← OpenGL コンテキストを作成・保持
       ├─ 初期化フェーズ
       │    ├─ モデルディレクトリの全ファイルを再帰的に読み取り   ← Python 側
       │    ├─ QImage でテクスチャを RGBA8888 にデコード        ← Python 側
       │    ├─ resource_streams テーブルを構築                  ← lupa Lua テーブル
       │    ├─ texture_streams テーブルを構築                    ← lupa Lua テーブル
       │    └─ opts = { resource_streams, texture_streams }
       │
       ├─ ロード & レンダリング
       │    ├─ embed.load_model(path, w, h, opts) ← 全リソースがストリーム経由、ファイルシステム読み取りゼロ
       │    ├─ resizeGL(w, h)    → embed.resize(w, h)
       │    └─ paintGL()         → embed.draw()
       │
       └─ QTimer(16ms)           ← リフレッシュループを駆動
```

**核心理念**：Python 側がファイルの読み取りとデコードを完全に管理します。Lua 側はメモリバイトストリームのみを受け取り、ファイルシステムや `image_loader.lua` に依存しません。

## 前提条件

### 1. LuaJIT ランタイム

このプロジェクトは LuaJIT の `ffi` モジュールに依存しています。**標準 Lua インタプリタでは動作しません**。

| 方法 | ライブラリ | 原理 | 推奨度 |
|------|-----------|------|--------|
| lupa (LuaJIT 版) | `pip install lupa` | `import lupa.luajit21` | ★★★ 推奨 |
| ctypes + luajit.dll | システムの `luajit-2.1.dll` | ctypes で DLL をロード、Lua C API を呼出 | ★★☆ 代替案 |
| サブプロセス + IPC | `subprocess` + 共有メモリ/Socket | 独立プロセスでレンダリング、ピクセルを Python に転送 | ★☆☆ 最も安定だが遅い |

### 2. OpenGL ウィジェット

Python GUI は OpenGL 対応のウィジェットを提供する必要があります。推奨：

- **PySide6** / **PyQt6**: `QOpenGLWidget`（本ガイドで使用）
- **wxPython**: `wx.GLCanvas`

### 3. オペレーティングシステム

このリポジトリの `live2d/gl_loader.lua` は **Windows と Linux をサポート**しています。macOS の互換性は未検証です。

### 4. 依存関係のインストール

```bash
pip install PySide6 lupa
```

> **重要**: lupa の wheel は LuaJIT ベースでコンパイルされている必要があります。lupa 内で `require("ffi")` がエラーになる場合、その lupa は標準 Lua にバンドルされています。

---

## ストリームベースのロード（推奨方式）

Python からバイトストリームを直接 Lua に渡し、ファイルシステムの読み取りとテクスチャデコードを完全にバイパスします。これが推奨方式である理由：

- **ファイルシステム非依存**：モデルを zip/ネットワーク/メモリからロード可能
- **ゼロ I/O 結合**：Python 側がデータソースを決定し、Lua 側はバイトを消費するのみ
- **GDI+ 制限を回避**：`image_loader.lua` を使用せず、Windows GDI+ デコードの問題を回避
- **クロスプラットフォームテクスチャデコード**：Qt の `QImage` でテクスチャをデコード、`wincodec` 非依存

### ストリーム API リファレンス

#### リソースストリーム（resource_streams）—— すべてのファイル読み取りを置換

```lua
-- Lua 側
embed.set_resource_stream(path, bytes)        -- 単一エントリ
embed.set_resource_streams(resource_streams)  -- 一括
embed.clear_resource_streams()                -- 全消去
```

`load_model` 時に opts 経由で渡すことも可能：

```lua
embed.load_model("resources/kasumi2/kasumi2.model.json", 400, 650, {
    resource_streams = {
        ["resources/kasumi2/kasumi2.model.json"] = json_bytes,
        ["resources/kasumi2/live2d/kasumi_school_winter_t03.moc"] = moc_bytes,
        ["resources/kasumi2/live2d/001_live_event_47_ssr_idle01.mtn"] = mtn_bytes,
        -- ... 物理演算、ポーズ、表情などすべてこのテーブル経由
    },
})
```

パスは自動的に正規化され（`\` → `/`、先頭の `./` を除去）、`.model.json` 内の相対参照と一致します。

上書きされるロードエントリポイント：
- `.model.json` 自体（`loadBytes` が JSON を読み取り）
- `.moc` モデルファイル（`loadLive2DModel` → `loadBytes`）
- `.mtn` モーションファイル（`loadMotion` → `loadBytes`）
- `.json` 表情 / ポーズ / 物理演算ファイル（各 `loadExpression`、`loadPose`、`loadPhysics` → `loadBytes`）
- `PlatformManager:loadBytes()` 経由で読み取られるその他すべてのファイル

#### テクスチャストリーム（texture_streams）—— PNG デコードと GL アップロードを置換

```lua
-- Lua 側
embed.set_texture_stream(no, width, height, rgba_bytes)   -- 単一テクスチャ
embed.set_texture_streams(texture_streams)                 -- 一括
embed.clear_texture_streams()                              -- 全消去
```

テクスチャ番号は **0 ベース**で、モデル JSON の `textures` 配列の順序に対応します。

```lua
embed.load_model("resources/kasumi2/kasumi2.model.json", 400, 650, {
    texture_streams = {
        [0] = {
            width  = 1024,
            height = 1024,
            data   = rgba_bytes,  -- Lua 文字列 / FFI ポインタ
        },
    },
})
```

パイプライン：Python 側で任意の画像ライブラリで PNG をデコード → RGBA8888 バイト → lupa 経由で Lua に渡す → `platform_manager.lua` が `glTexImage2D` で直接 OpenGL テクスチャをアップロード、`image_loader.lua` を完全にスキップ。

### lupa 統合の完全な例

`examples/pyside6_lupa_kasumi2.py`

コアフロー：

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

        # 1. LuaJIT ランタイムを作成（encoding=None で lupa が Python bytes を直接渡せるように）
        self.lua = LuaRuntime(unpack_returned_tuples=True, encoding=None)
        self.lua.execute(b'assert(require("ffi"), "lupa must be built with LuaJIT FFI")')

        # 2. live2d_embed をロード
        self.embed = self.lua.execute(b'return require("live2d_embed")')

        # 3. 高頻度関数をプリコンパイル
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

        # 4. ストリームテーブルを構築
        opts = self.lua.table()
        opts[b"resource_streams"] = load_resource_streams(self.lua, ROOT / "resources" / "kasumi2")
        opts[b"texture_streams"]  = load_texture_streams(self.lua, ROOT / MODEL_PATH)

        # 5. モデルをロード（すべてストリーム経由）
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


# ---- ストリーム構築ヘルパー関数 -----------------------------------------------

def load_resource_streams(lua, model_dir):
    """モデルディレクトリ内の全ファイルを再帰的に読み取り、Lua テーブルを構築。
    Key はリポジトリ相対パス（例: "resources/kasumi2/live2d/xxx.mtn"）、Value は bytes。"""
    streams = lua.table()
    for path in model_dir.rglob("*"):
        if path.is_file():
            key = path.relative_to(ROOT).as_posix().encode()
            streams[key] = path.read_bytes()
    return streams


def load_texture_streams(lua, model_json_path):
    """モデル JSON を読み取り、テクスチャを RGBA8888 にデコードし、Lua テーブルを構築。
    Key はテクスチャ番号（0 ベース）、Value は { width, height, data }。"""
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
    """QImage を使用して画像を RGBA8888 bytes にデコード。"""
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

実行：

```bash
python examples/pyside6_lupa_kasumi2.py
```

---

## lupa の重要な注意点

### 1. encoding=None

```python
self.lua = LuaRuntime(unpack_returned_tuples=True, encoding=None)
```

`encoding=None` により `lua.execute()` と `lua.eval()` が Python の `bytes` を受け付け、直接 Lua に Lua 文字列として渡せるようになります——これはリソースバイトストリームにとって必須で、そうしないとエンコード変換がバイナリデータを破壊します。

### 2. グローバル関数のキャッシュ

`lua.eval("...")` は毎回新しい Lua クロージャをパース・コンパイルします。`paintGL()` 内で使用しないでください。`initializeGL()` で一度だけプリキャッシュします：

```python
# 良い: プリコンパイル
self._draw = self.lua.eval(b"function(e) return e.draw() end")
self._draw(self.embed)

# 悪い: 毎フレーム eval
self.lua.eval(b"embed.draw()")
```

### 3. GC ステップ

`live2d_embed.lua` の `draw()` は内部で既に `collectgarbage("step", 200)` を実行しています。Python 側での追加処理は不要です。`draw()` を経由せずに直接 `model:Draw()` を呼び出す場合は、手動 GC が必要です：

```python
self.lua.execute(b"collectgarbage('step', 200)")
```

### 4. OpenGL コンテキストのスレッド親和性

QOpenGLWidget の `initializeGL` / `paintGL` は GL スレッド上で実行されます。Qt がコンテキストを既にバインド済みであることを保証します。**GL スレッド以外から `embed.draw()` を呼び出さないでください**。

### 5. バイトストリームのデータ型

Lua 側は `ffi.cast("const uint8_t*", data)` で受信データを処理します。`encoding=None` モードの Python `bytes` オブジェクトは lupa によって Lua 文字列として渡され、そのアドレスを FFI が安全にキャストできます。他の言語から生のポインタを渡すことも可能です。

---

## live2d_embed.lua 完全 API

### シングルトン API（グローバル単一モデル）

```lua
local embed = require("live2d_embed")

-- 初期化（遅延実行、OpenGL コンテキスト有効化後の初回呼出で自動トリガー）
embed.init()

-- モデルをロード（opts 経由でストリームを渡すことを推奨）
embed.load_model("resources/kasumi2/kasumi2.model.json", 400, 650, {
    resource_streams = { ... },
    texture_streams  = { ... },
    auto_breath = true,   -- 自動呼吸
    auto_blink  = true,   -- 自動まばたき
    center      = true,   -- モデル中央配置
    model_width = 2.0,    -- モデルスケーリング
    center_x    = 0,      -- X オフセット
    center_y    = 0,      -- Y オフセット
})

-- リソースストリーム管理
embed.set_resource_stream(path, bytes)        -- 単一リソースを注入
embed.set_resource_streams(resource_streams)  -- 一括注入
embed.clear_resource_streams()                -- 全リソースストリームを消去

-- テクスチャストリーム管理
embed.set_texture_stream(no, width, height, rgba_bytes)  -- 単一テクスチャを注入
embed.set_texture_streams(texture_streams)               -- 一括注入
embed.clear_texture_streams()                            -- 全テクスチャストリームを消去

-- 全ストリーム消去
embed.clear_streams()

-- 描画（clear + update + draw + GC step 内蔵）
embed.draw()               -- デフォルト clear
embed.draw({ clear = false, gc_step = 200 })

-- アニメーション更新のみ（レンダリングなし）
embed.update()

-- 手動画面クリア
embed.clear(r, g, b, a)

-- ビューポートサイズ
embed.resize(w, h)

-- マウス操作
embed.drag(x, y)           -- 視線 / 頭部追跡
embed.set_offset(x, y)     -- モデル平行移動
embed.set_scale(scale)     -- モデル拡大縮小

-- モーション
embed.start_motion(name, no, priority)  -- priority: embed.MotionPriority.FORCE (3)
embed.clear_motions()

-- パラメータ
embed.set_parameter("PARAM_ANGLE_X", 30)
embed.add_parameter("PARAM_BODY_ANGLE_X", 5)

-- 表情
embed.set_expression("SMILE")
embed.reset_expression()

-- ヒットテスト
local part = embed.hit_test(x, y)

-- 現在のレンダラー / モデルを取得
local r = embed.current()
local l2d_model = r:get_model():getLive2DModel()

-- クリーンアップ
embed.dispose()
```

### オブジェクト API（マルチモデルシナリオ）

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

-- すべてのシングルトン API メソッドが Renderer インスタンスで利用可能
r1:draw()
r1:resize(800, 600)
r1:drag(x, y)
```

---

## プラットフォーム互換性

### lupa が利用不可の場合の代替案

#### ctypes + luajit.dll

lupa がインストールできない場合、ctypes を使用して LuaJIT の C API を直接呼び出すことができます：

```python
import ctypes

luajit = ctypes.CDLL("luajit-2.1.dll")

# Lua ステートを作成
L = luajit.luaL_newstate()
luajit.luaL_openlibs(L)

# live2d_embed をロード
luajit.luaL_dofile(L, b"live2d_embed.lua")

# embed.load_model を呼出（ストリームテーブルは lua_newtable + lua_pushstring + lua_settable で構築必要）
...
```

ctypes 方式の欠点：
- Lua スタックの手動管理が必要
- ストリームテーブルの構築が非常に煩雑（各キー・値ペアに複数回の push + settable が必要）
- エラーデバッグが困難

**それでも lupa のインストールを強く推奨します。**

---

## よくある質問

### Q: テクスチャが空白 / 白いモデル / モデルが表示されない

A: テクスチャストリームが正しい RGBA8888 データを渡しているか確認してください。`texture_streams` のキーが `0` ベース（`1` ではない）であることを確認してください。QImage でデコードする場合は、フォーマットが `Format_RGBA8888` であることを確認してください。

### Q: モーション / 物理演算 / 表情が動作しない

A: 対応する `.mtn` / `.json` ファイルが `resource_streams` に含まれていることを確認してください。パスキーはリポジトリルート相対パス（例: `resources/kasumi2/live2d/001_idle01.mtn`）で、パス区切り文字は `/` である必要があります。

### Q: モデル JSON のロードに失敗する

A: `.model.json` 自体も `resource_streams` に含まれている必要があります。`load_model` の第一引数（例: `"resources/kasumi2/kasumi2.model.json"`）はログ出力と json 内相対パスの解決にのみ使用され、実際の JSON 内容はストリームテーブルから読み取られます。

### Q: `gl.ensureExtensions()` が失敗する

A: `embed.init()` または最初の `load_model()` を呼び出す時点で OpenGL コンテキストが有効であることを確認してください。QOpenGLWidget は `initializeGL()` 内で自動的に `makeCurrent()` を呼び出します。

### Q: GC クラッシュ / メモリが継続的に増加する

A: `embed.draw()` は内部で既に `collectgarbage("step", 200)` を含んでいます。`draw()` の代わりに手動で `update()` + `Draw()` を使用する場合は、Python 側で GC をトリガーしてください：

```python
self.lua.execute(b"collectgarbage('step', 200)")
```

### Q: 複数モデルを同時にレンダリングする

A: オブジェクト API を使用します：

```python
self._draw_a = self.lua.eval(b"function(r) return r.draw() end")
self._draw_b = self.lua.eval(b"function(r) return r.draw() end")

def paintGL(self):
    self._draw_a(self.renderer_a)
    self._draw_b(self.renderer_b)
```

複数のモデルが同じ PlatformManager とストリームテーブルを共有することに注意してください。

### Q: 非ファイルソース（ネットワーク / zip / 暗号化パッケージ）をサポートするには？

A: これこそがストリームベースロードの強みです。Python 側でリモートデータをダウンロードまたは解凍して `bytes` にし、`resource_streams` と `texture_streams` を構築して Lua に注入するだけです：

```python
import zipfile, requests

zip_data = requests.get("https://example.com/model.zip").content
with zipfile.ZipFile(io.BytesIO(zip_data)) as zf:
    resource_streams[key.encode()] = zf.read(name)  # zip 内の各ファイルに対して
```

Lua 側はデータソースを完全に意識しません。

---

## ファイル一覧

```
live2d-v2/
├── live2d_embed.lua                       ← ヘッドレスレンダリングコアモジュール
├── Embedded2Python_jp.md                  ← 本文書
├── examples/
│   └── pyside6_lupa_kasumi2.py            ← Python 統合の完全な例（ストリーム方式）
├── live2d/
│   ├── platform_manager.lua               ← ファイル I/O + ストリームルーティング
│   ├── gl_loader.lua                      ← OpenGL 拡張ローダー (wglGetProcAddress)
│   ├── image_loader.lua                   ← GDI+ テクスチャロード（ストリームモードではトリガーされない）
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
