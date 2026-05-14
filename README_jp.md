# Live2D v2 in LuaJIT

[English](README.md) | [中文](README_cn.md)

<p align="center">
  <a href="https://github.com/HELPMEEADICE/Live2D-v2-Lua"><img alt="GitHub Repo" src="https://img.shields.io/badge/GitHub-Live2D--v2--Lua-ff69b4?logo=github"></a>
  <a href="https://github.com/HELPMEEADICE/Live2D-v2-Lua/blob/main/LICENSE"><img alt="License" src="https://img.shields.io/github/license/HELPMEEADICE/Live2D-v2-Lua?color=blue"></a>
  <a href="https://github.com/HELPMEEADICE/Live2D-v2-Lua/stargazers"><img alt="Stars" src="https://img.shields.io/github/stars/HELPMEEADICE/Live2D-v2-Lua?color=yellow"></a>
  <a href="https://github.com/HELPMEEADICE/Live2D-v2-Lua/network/members"><img alt="Forks" src="https://img.shields.io/github/forks/HELPMEEADICE/Live2D-v2-Lua?color=orange"></a>
  <a href="https://luajit.org/"><img alt="LuaJIT" src="https://img.shields.io/badge/LuaJIT-2.1+-000080?logo=lua&logoColor=white"></a>
  <a href="https://www.live2d.com/"><img alt="Live2D" src="https://img.shields.io/badge/Live2D-Cubism%20v2-EE82EE?logo=data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAyNCAyNCI+PHBhdGggZmlsbD0id2hpdGUiIGQ9Ik0xMiAyQzYuNDggMiAyIDYuNDggMiAxMnM0LjQ4IDEwIDEwIDEwIDEwLTQuNDggMTAtMTBTMTcuNTIgMiAxMiAyem0tMSAxNy45M2MtMy45NS0uNDktNy0zLjg1LTctNy45M3MzLjA1LTcuNDQgNy03LjkzdjE1Ljg2em0yLTE1Ljg2YzMuOTUuNDkgNyAzLjg1IDcgNy45M3MtMy4wNSA3LjQ0LTcgNy45M1Y0LjA3eiIvPjwvc3ZnPg=="></a>
  <a href="https://github.com/HELPMEEADICE/Live2D-v2-Lua"><img alt="Last Commit" src="https://img.shields.io/github/last-commit/HELPMEEADICE/Live2D-v2-Lua?color=green"></a>
</p>

> キラキラドキドキ！Live2D Cubism 2.1 SDK、LuaJIT 純粋版。

[EasyLive2D/live2d-v2](https://github.com/EasyLive2D/live2d-v2) を Python から Lua へ完全にリファクタリングしました。**C コンパイル不要、純粋 FFI**。LuaJIT + SDL2 + アニメへの熱い心があれば動きます。

なぜ Lua を選んだのか——それは多分、香澄が倉庫で Random Star を見つけた時と同じで、理由なんて要らないからです。（本当は Python のパフォーマンスが酷すぎるからですが。）

> ⚠️ `main.lua` はデモに過ぎません。この Lua 実装の本当の目的は：この高性能（Python より圧倒的に速い）Live2D v2 レンダリングコアが、接着剤のようにどんな言語にも簡単に埋め込めることです——C++ なら `lua_pcall`、Python なら `lupa`、お好みでどうぞ。
>
> 🔌 **Python からの呼び出し方法は [Embedded2Python_jp.md](Embedded2Python_jp.md) を参照**。lupa / ctypes / サブプロセス の3つの統合方法、PySide6 の完全な例、トラブルシューティング FAQ を含みます。

> 🌸 これはファンメイドの移植プロジェクトです。このリポジトリは [EasyLive2D/live2d-v2](https://github.com/EasyLive2D/live2d-v2)（MIT）に由来し、Python から Lua にリファクタリングされました。
>
> 🤖 特別な感謝を **DeepSeek V4 Pro**（メインのリファクタリングコーディング）と **GPT 5.5**（難易度の高いバグ修正）に——この二人の無言の共犯者がいなければ、この小さなプロジェクトは今でも import 地獄に閉じ込められていました。AI 利用の総費用は約 **5 ドル**、ラムネ2本分くらいです。

![screenshot](example.png)

---

## 前提条件

- **LuaJIT 2.1+**（FFI が必要です）
- **SDL2** ランタイムライブラリ
- **OpenGL** ドライバ（Windows: `opengl32.dll`, Linux: `libGL.so`）
- **zlib**（Linux で PNG デコードに必要）

### Windows

```bash
# SDL2.dll を PATH またはカレントディレクトリに配置
luajit main.lua
```

### Linux

```bash
# Debian/Ubuntu
sudo apt install luajit libsdl2-2.0-0 libgl1 zlib1g

# 実行
luajit main.lua
```

## クイックスタート

```bash
luajit main.lua
```

400×650 のウィンドウが開きます。キャラクターをクリックしてモーションを切り替え、Esc で終了します。

```bash
luajit render_frames.lua
```

## エントリースクリプト

| スクリプト | 機能 |
|-----------|------|
| `main.lua` | インタラクティブビューア、マウス追跡 + クリックでモーション切替 + 自動呼吸/まばたき |
| `render_frames.lua` | 20フレームを BMP として `frames_output/` にオフラインレンダリング |
| `live2d_embed.lua` | ヘッドレスレンダリングコアモジュール、ホスト言語への埋め込み用 |
| `examples/pyside6_lupa_kasumi2.py` | Python 統合の完全な例 (PySide6 + lupa) |
| `simple.lua` | ~~作業中~~ 使わないで |

## デフォルトキャラクター

`kasumi2`——そうです、あの香澄、BanG Dream! Poppin'Party のボーカル兼ギタリストです。モデルファイルは `resources/kasumi2/kasumi2.model.json` にあります。

> どうせなら、星の鼓動でいこう！ 🎸✨

## プロジェクト構成

```
live2d/
  init.lua                 # facade
  core/                    # Cubism Core 2.1 移植
  framework/               # Cubism Framework 移植
  sdl2.lua                 # SDL2 FFI バインディング（純粋 Lua 宣言 + ローダー）
  gl_loader.lua            # OpenGL 拡張ローダー（wglGetProcAddress / glXGetProcAddress）
  platform_manager.lua     # ファイル I/O 抽象レイヤー
  lapp_model.lua           # 高レベルモデルインターフェース（JSON / モーション / 物理演算）
```

モジュール命名は元の C++ クラス階層（例: `live2d.core.live2d`）に従っており、公式 SDK ドキュメントとの照合が容易です。

## 既知の問題

- **GC Step は必須**：`model:Draw()` を呼び出すたびに一時的な FFI 頂点バッファが割り当てられます。`collectgarbage("step", 200)` がない場合、垂直同期のないドライバではメモリが爆発します。
- **OpenGL 拡張のロードはクロスプラットフォーム対応**：`gl_loader.lua` は Windows（`wglGetProcAddress`）と Linux（`glXGetProcAddress`）をサポートし、プラットフォームを自動検出します。
- **スクリプトはリポジトリルートから実行する必要があります**：各エントリスクリプトは `package.path` の拡張をインラインで行っています。ルート以外から実行するとモジュールが見つかりません。
- **テストも CI もビルドシステムもありません**：これは純粋な Lua プロジェクトです。`make`、`cmake`、`npm` などはありません。ただ実行するだけです。

## 謝辞

- [EasyLive2D/live2d-v2](https://github.com/EasyLive2D/live2d-v2)
- [DeepSeek V4 Pro](https://www.deepseek.com)
- [GPT 5.5](https://chatgpt.com/codex/cloud)
- [OpenCode](https://opencode.ai)
