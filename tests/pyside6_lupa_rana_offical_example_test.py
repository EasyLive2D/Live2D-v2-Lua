"""Smoke checks for the PySide6 + lupa Rana official Core example."""

from __future__ import annotations

import ast
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
EXAMPLE = ROOT / "examples" / "pyside6_lupa_rana_offical.py"


def test_example_exists_and_parses() -> None:
    source = EXAMPLE.read_text(encoding="utf-8")
    ast.parse(source, filename=str(EXAMPLE))


def test_example_uses_rana_official_embed() -> None:
    source = EXAMPLE.read_text(encoding="utf-8")

    assert "live2d_moc3_offical_embed" in source
    assert "resources/Rana/adv_live2d_rana_003_live_01.model3.json" in source
    assert "Rana - PySide6 + lupa - Official Core" in source


def test_example_drives_official_renderer() -> None:
    source = EXAMPLE.read_text(encoding="utf-8")

    assert "ensureExtensions" in source
    assert "embed.update" in source
    assert "embed.render" in source
    assert "make_projection" in source
    assert "start_motion" in source
