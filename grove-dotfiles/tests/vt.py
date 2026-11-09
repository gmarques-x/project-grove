# vt.py FILE [COLS]: replay a terminal recording (from `script`) and print the
# screen as plain text. Handles cursor moves (CSI C/D/G/A/B/H), ESC 7/8, CR/LF;
# colors and APC/OSC/DCS (images, titles) are skipped. For the fastfetch box test.
import re, sys, unicodedata
data = open(sys.argv[1], encoding="utf-8", errors="replace").read()
W = int(sys.argv[2]) if len(sys.argv) > 2 else 140
g = {}; r = c = 0; saved = (0, 0); i = 0
def wid(ch): return 2 if unicodedata.east_asian_width(ch) in "WF" else 1
while i < len(data):
    ch = data[i]
    if ch == "\x1b":
        n = data[i+1:i+2]
        if n == "[":
            m = re.match(r"\x1b\[([?0-9;]*)([A-Za-z@])", data[i:])
            if not m: i += 1; continue
            args, cmd = m.group(1), m.group(2); i += len(m.group(0))
            v = int(args.split(";")[0]) if args and args.split(";")[0].lstrip("?").isdigit() and not args.startswith("?") else 1
            if cmd == "C": c += v
            elif cmd == "D": c = max(0, c - v)
            elif cmd == "G": c = v - 1
            elif cmd == "A": r = max(0, r - v)
            elif cmd == "B": r += v
            elif cmd == "H":
                p = (args or "1;1").split(";"); r, c = int(p[0] or 1) - 1, int((p+["1"])[1] or 1) - 1
            continue
        if n in ("_", "]", "P"):
            e = data.find("\x1b\\", i); b = data.find("\x07", i)
            ends = [x for x in (e if e >= 0 else None, b if b >= 0 and n == "]" else None) if x is not None]
            i = (min(ends) + (2 if min(ends) == e else 1)) if ends else len(data); continue
        if n == "7": saved = (r, c); i += 2; continue
        if n == "8": r, c = saved; i += 2; continue
        i += 2; continue
    if ch == "\r": c = 0
    elif ch == "\n": r += 1; c = 0
    elif ch >= " ":
        g[(r, c)] = ch; c += wid(ch)
    i += 1
R = max(k[0] for k in g) + 1
for y in range(R):
    print("".join(g.get((y, x), " ") for x in range(W)).rstrip())
