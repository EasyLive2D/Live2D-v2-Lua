# Live2D v2 in LuaJIT

[中文](README_cn.md) | [日本語](README_jp.md)

<p align="center">
  <a href="https://github.com/HELPMEEADICE/Live2D-v2-Lua"><img alt="GitHub Repo" src="https://img.shields.io/badge/GitHub-Live2D--v2--Lua-ff69b4?logo=github"></a>
  <a href="https://github.com/HELPMEEADICE/Live2D-v2-Lua/blob/main/LICENSE"><img alt="License" src="https://img.shields.io/github/license/HELPMEEADICE/Live2D-v2-Lua?color=blue"></a>
  <a href="https://github.com/HELPMEEADICE/Live2D-v2-Lua/stargazers"><img alt="Stars" src="https://img.shields.io/github/stars/HELPMEEADICE/Live2D-v2-Lua?color=yellow"></a>
  <a href="https://github.com/HELPMEEADICE/Live2D-v2-Lua/network/members"><img alt="Forks" src="https://img.shields.io/github/forks/HELPMEEADICE/Live2D-v2-Lua?color=orange"></a>
  <a href="https://luajit.org/"><img alt="LuaJIT" src="https://img.shields.io/badge/LuaJIT-2.1+-000080?logo=lua&logoColor=white"></a>
  <a href="https://www.live2d.com/"><img alt="Live2D" src="https://img.shields.io/badge/Live2D-Cubism%20v2-EE82EE?logo=data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAyNCAyNCI+PHBhdGggZmlsbD0id2hpdGUiIGQ9Ik0xMiAyQzYuNDggMiAyIDYuNDggMiAxMnM0LjQ4IDEwIDEwIDEwIDEwLTQuNDggMTAtMTBTMTcuNTIgMiAxMiAyem0tMSAxNy45M2MtMy45NS0uNDktNy0zLjg1LTctNy45M3MzLjA1LTcuNDQgNy03LjkzdjE1Ljg2em0yLTE1Ljg2YzMuOTUuNDkgNyAzLjg1IDcgNy45M3MtMy4wNSA3LjQ0LTcgNy45M1Y0LjA3eiIvPjwvc3ZnPg=="></a>
  <a href="https://github.com/HELPMEEADICE/Live2D-v2-Lua"><img alt="Last Commit" src="https://img.shields.io/github/last-commit/HELPMEEADICE/Live2D-v2-Lua?color=green"></a>
</p>

> Kirakira dokidoki! Live2D Cubism 2.1 SDK, pure LuaJIT edition.

A complete Lua rewrite of [EasyLive2D/live2d-v2](https://github.com/EasyLive2D/live2d-v2) from Python — **zero C compilation, pure FFI**. As long as you have LuaJIT + SDL2 + a heart burning with anime passion, it just runs.

If you ask me why Lua — it's probably like when Kasumi found the Random Star in the warehouse. Some things need no reason. (Actually, it's because Python performance is awful.)

> ⚠️ `main.lua` is just a demo. The real purpose of this Lua implementation is: this high-performance (way beyond Python) Live2D v2 rendering core can be embedded into any language like glue — whether it's C++ via `lua_pcall` or Python via `lupa`, whatever you like.
>
> 🔌 **See [Embedded2Python.md](Embedded2Python.md) for Python integration**, with lupa / ctypes / subprocess approaches, full PySide6 example, and troubleshooting FAQ.

> 🌸 This is a fan-made port. This repository originates from [EasyLive2D/live2d-v2](https://github.com/EasyLive2D/live2d-v2) (MIT), rewritten from Python to Lua.
>
> 🤖 Special thanks to **DeepSeek V4 Pro** (primary rewrite) and **GPT 5.5** (troubleshooting & bug fixes) — without these two silent accomplices, this tiny project would still be stuck in import hell. Total AI cost: about **$5**, roughly two bottles of ramune.

![screenshot](example.png)

---

## Prerequisites

- **LuaJIT 2.1+** (FFI required)
- **SDL2** runtime library
- **OpenGL** driver (Windows: `opengl32.dll`, Linux: `libGL.so`)
- **zlib** (needed for PNG decoding on Linux)

### Windows

```bash
# SDL2.dll in PATH or current directory
luajit main.lua
```

### Linux

```bash
# Debian/Ubuntu
sudo apt install luajit libsdl2-2.0-0 libgl1 zlib1g

# Run
luajit main.lua
```

## Quick Start

```bash
luajit main.lua
```

A 400×650 window opens. Click the character to switch motions, press Esc to quit.

```bash
luajit render_frames.lua
```

## Entry Scripts

| Script | Function |
|--------|----------|
| `main.lua` | Interactive viewer with mouse tracking + click motion switching + auto breathing/blinking |
| `render_frames.lua` | Offline render 20 frames as BMP to `frames_output/` |
| `live2d_embed.lua` | Headless rendering core module for host language embedding |
| `examples/pyside6_lupa_kasumi2.py` | Complete Python integration example (PySide6 + lupa) |
| `simple.lua` | ~~Work in progress~~ Don't use |

## Default Character

`kasumi2` — yes, that Kasumi, the vocalist and guitarist of Poppin'Party from BanG Dream! The model files are in `resources/kasumi2/kasumi2.model.json`.

> Douse nara, hoshi no kodou de ikou! 🎸✨

## Project Structure

```
live2d/
  init.lua                 # facade
  core/                    # Cubism Core 2.1 port
  framework/               # Cubism Framework port
  sdl2.lua                 # SDL2 FFI bindings (pure Lua declarations + loader)
  gl_loader.lua            # OpenGL extension loader (wglGetProcAddress / glXGetProcAddress)
  platform_manager.lua     # File I/O abstraction layer
  lapp_model.lua           # High-level model interface (JSON / motions / physics)
```

Module naming follows the original C++ class hierarchy (e.g. `live2d.core.live2d`), making it easy to cross-reference with the official SDK docs.

## Known Issues

- **GC Step is essential**: Every `model:Draw()` call allocates temporary FFI vertex buffers. Without `collectgarbage("step", 200)`, memory will explode on drivers without vsync.
- **OpenGL extension loading is cross-platform**: `gl_loader.lua` supports Windows (`wglGetProcAddress`) and Linux (`glXGetProcAddress`), auto-detecting the platform.
- **Scripts must run from repo root**: Every entry script inlines `package.path` extensions. Running outside the root means modules won't be found.
- **No tests, no CI, no build system**: This is a pure Lua project. No `make`, `cmake`, `npm`, stuff like that. Just run it.

## Credits

- [EasyLive2D/live2d-v2](https://github.com/EasyLive2D/live2d-v2)
- [DeepSeek V4 Pro](https://www.deepseek.com)
- [GPT 5.5](https://chatgpt.com/codex/cloud)
- [OpenCode](https://opencode.ai)
