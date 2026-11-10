#!/usr/bin/env python3
"""Remake Grove Icons from VS Code's Seti icons: same font and icons, Everforest colors.

Usage: build.py [SETI_DIR]   (default: the installed VS Code's theme-seti/icons)
Writes grove-icon-theme.json, seti.woff, package.json and NOTICE next to this file
and prints the color mapping. Dev-only: grove install uses the committed output.
Standard library only.
"""
import colorsys
import json
import re
import shutil
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
THEME = HERE.parents[2] / "theme" / "everforest-dark-medium"
SETI = Path("/Applications/Visual Studio Code.app/Contents/Resources/app/extensions/theme-seti/icons")
ACCENTS = ["red", "orange", "yellow", "green", "aqua", "blue", "purple"]


def palette():
    pal = {}
    for line in THEME.read_text().splitlines():
        m = re.match(r"^([a-z_0-9]+)\s*=\s*(#[0-9A-Fa-f]{6})\b", line)
        if m:
            pal[m.group(1)] = m.group(2).upper()
    return pal


def rgb01(hex6):
    return tuple(int(hex6[i:i + 2], 16) / 255 for i in (1, 3, 5))


def recolor(hex6, pal):
    """Greys go to grey0, grey1 or fg by lightness; colors to the nearest accent by hue."""
    h, l, s = colorsys.rgb_to_hls(*rgb01(hex6))
    if s < 0.25:
        return pal["grey0"] if l < 0.40 else pal["grey1"] if l < 0.65 else pal["fg"]

    def dist(name):
        d = abs(h - colorsys.rgb_to_hls(*rgb01(pal[name]))[0])
        return min(d, 1 - d)

    return pal[min(ACCENTS, key=dist)]


def bump(version):
    major, minor, patch = (int(x) for x in version.split("."))
    return f"{major}.{minor}.{patch + 1}"


NOTICE = """Grove Icons is VS Code's Seti file icon theme with its colors changed to
Everforest Dark Medium (theme/everforest-dark-medium). The font and the icon
associations are unchanged. Both sources are under the MIT License:

Seti UI (font and icon set): https://github.com/jesseweed/seti-ui
Copyright (c) 2014 Jesse Weed

VS Code theme-seti (icon theme file): https://github.com/microsoft/vscode
Copyright (c) Microsoft Corporation

MIT License

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
"""


def main():
    seti = Path(sys.argv[1]) if len(sys.argv) > 1 else SETI
    pal = palette()
    theme = json.loads((seti / "vs-seti-icon-theme.json").read_text())
    theme.pop("light", None)
    theme["fonts"][0]["src"][0]["path"] = "./seti.woff"

    mapping = {}
    for d in theme["iconDefinitions"].values():
        old = d.get("fontColor")
        # No color means VS Code's text color; fg looks the same and stays in the palette.
        new = recolor(old, pal) if old else pal["fg"]
        mapping[(old or "(none)").lower()] = new
        d["fontColor"] = new

    out = HERE / "grove-icon-theme.json"
    text = json.dumps(theme, indent=2, ensure_ascii=False) + "\n"
    pkg_path = HERE / "package.json"
    version = "1.0.0"
    if pkg_path.exists():
        version = json.loads(pkg_path.read_text())["version"]
        if not out.exists() or out.read_text() != text:
            version = bump(version)
    out.write_text(text)
    shutil.copyfile(seti / "seti.woff", HERE / "seti.woff")
    pkg = {
        "name": "grove-icons",
        "displayName": "Grove Icons",
        "description": "VS Code's Seti icons in Everforest colors",
        "publisher": "grove",
        "version": version,
        "license": "MIT",
        "engines": {"vscode": "^1.80.0"},
        "categories": ["Themes"],
        "contributes": {"iconThemes": [{"id": "grove-icons", "label": "Grove Icons", "path": "./grove-icon-theme.json"}]},
    }
    pkg_path.write_text(json.dumps(pkg, indent=2) + "\n")
    (HERE / "NOTICE").write_text(NOTICE)

    names = {v: k for k, v in pal.items() if k in ACCENTS + ["grey0", "grey1", "fg"]}
    for old, new in sorted(mapping.items()):
        print(f"{old} -> {names[new]} {new}")
    print(f"{len(theme['iconDefinitions'])} icons, version {version}")


if __name__ == "__main__":
    main()
