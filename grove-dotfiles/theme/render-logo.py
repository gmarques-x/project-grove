"""Render theme/grove-logo.txt as 24-bit ANSI half-block art.

Usage: python3 -I theme/render-logo.py > config/macchina/grove.ascii
Run from grove-dotfiles/. Colors come from theme/everforest-dark-medium.
"""
import os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
LEGEND = {"A": "aqua", "G": "green", "Y": "yellow", "T": "grey0", "D": "bg_green", "E": "bg3", "S": "grey1", "W": "fg"}

palette = {}
for line in open(os.path.join(HERE, "everforest-dark-medium")):
    m = re.match(r"\s*(\w+)\s*=\s*#([0-9A-Fa-f]{6})", line)
    if m:
        palette[m.group(1)] = tuple(int(m.group(2)[i:i + 2], 16) for i in (0, 2, 4))

lines = open(os.path.join(HERE, "grove-logo.txt")).read().splitlines()
scale = 1
for l in lines:
    m = re.match(r"#\s*scale:\s*(\d+)", l)
    if m:
        scale = int(m.group(1))
rows = [l for l in lines if l.strip() and not l.startswith("#")]
rows = ["".join(c * scale for c in r) for r in rows for _ in range(scale)]
width = max(len(r) for r in rows)
rows = [r.ljust(width, ".") for r in rows]
if len(rows) % 2:
    rows.append("." * width)

def rgb(letter):
    return palette[LEGEND[letter]]

out = []
for top, bottom in zip(rows[0::2], rows[1::2]):
    cells = []
    for t, b in zip(top, bottom):
        if t == "." and b == ".":
            cells.append("\033[0m ")
        elif b == ".":
            cells.append("\033[0;38;2;%d;%d;%dm▀" % rgb(t))
        elif t == ".":
            cells.append("\033[0;38;2;%d;%d;%dm▄" % rgb(b))
        elif t == b:
            cells.append("\033[0;38;2;%d;%d;%dm█" % rgb(t))
        else:
            cells.append("\033[0;38;2;%d;%d;%d;48;2;%d;%d;%dm▀" % (rgb(t) + rgb(b)))
    out.append("".join(cells) + "\033[0m")
sys.stdout.write("\n".join(out) + "\n")
