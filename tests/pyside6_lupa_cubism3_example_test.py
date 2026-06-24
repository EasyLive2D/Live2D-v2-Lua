"""Smoke checks for the PySide6 + lupa Cubism3 example."""

from __future__ import annotations

import ast
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
EXAMPLE = ROOT / "examples" / "pyside6_lupa_cubism3.py"


def test_example_exists_and_parses() -> None:
    source = EXAMPLE.read_text(encoding="utf-8")
    ast.parse(source, filename=str(EXAMPLE))


def test_example_uses_hiyori_moc3_embed() -> None:
    source = EXAMPLE.read_text(encoding="utf-8")

    assert "live2d_moc3_embed" in source
    assert "resources/Hiyori/Hiyori.model3.json" in source
    assert "Hiyori - PySide6 + lupa" in source


def test_example_drives_cubism3_renderer() -> None:
    source = EXAMPLE.read_text(encoding="utf-8")

    assert "ensureExtensions" in source
    assert "embed.update" in source
    assert "embed.render" in source
    assert "make_projection" in source
    assert "start_motion" in source
