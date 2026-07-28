#!/usr/bin/env python3
"""Portable CI checks for Joi's Codex plugin package."""

from __future__ import annotations

import json
from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[1]
PLUGIN = ROOT / "plugins" / "joi-assistant"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(message)


manifest = json.loads((PLUGIN / ".codex-plugin" / "plugin.json").read_text())
require(manifest["name"] == "joi-assistant", "Unexpected plugin name")
require(manifest["mcpServers"] == "./.mcp.json", "MCP manifest path is missing")
require((PLUGIN / "assets" / "pet" / "spritesheet.webp").is_file(), "Pet atlas is missing")
require((PLUGIN / "assets" / "pet" / "pet.json").is_file(), "Pet manifest is missing")

mcp = json.loads((PLUGIN / ".mcp.json").read_text())
require("joi" in mcp.get("mcpServers", {}), "Joi MCP server is missing")

skill_roots = sorted((PLUGIN / "skills").glob("*/SKILL.md"))
require(len(skill_roots) == 10, "Expected ten Joi skills")
for skill_path in skill_roots:
    contents = skill_path.read_text()
    require("[TODO:" not in contents, f"TODO remains in {skill_path}")
    _, frontmatter, _ = contents.split("---", 2)
    skill = yaml.safe_load(frontmatter)
    require(skill.get("name") == skill_path.parent.name, f"Skill name mismatch in {skill_path}")
    require(bool(skill.get("description")), f"Skill description is missing in {skill_path}")
    agent = yaml.safe_load((skill_path.parent / "agents" / "openai.yaml").read_text())
    default_prompt = agent.get("interface", {}).get("default_prompt", "")
    require(f"${skill_path.parent.name}" in default_prompt, f"Default prompt must invoke {skill_path.parent.name}")

print(f"Validated {len(skill_roots)} skills and plugin {manifest['version']}")
