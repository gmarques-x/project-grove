"""Point every Desktop wallpaper in macOS's wallpaper store at one image.

usage: wallpaper_store.py STORE IMAGE_PATH
Run with /usr/bin/python3 -I (stdlib only). Prints the number of entries
changed; exits 1 with a message when the store is missing or unreadable.
"""
import os
import plistlib
import sys
import tempfile
from urllib.parse import quote


def desktop_holders(store):
    """Dicts that hold a "Desktop" key: all-spaces, displays, spaces."""
    found = []

    def add(node):
        if isinstance(node, dict) and isinstance(node.get("Desktop"), dict):
            found.append(node)

    add(store.get("AllSpacesAndDisplays"))
    for d in (store.get("Displays") or {}).values():
        add(d)
    for space in (store.get("Spaces") or {}).values():
        if not isinstance(space, dict):
            continue
        add(space.get("Default"))
        for d in (space.get("Displays") or {}).values():
            add(d)
    return found


def main(argv):
    if len(argv) != 3:
        print("usage: wallpaper_store.py STORE IMAGE_PATH")
        return 2
    path, image = argv[1], argv[2]
    try:
        with open(path, "rb") as f:
            store = plistlib.load(f)
        if not isinstance(store, dict):
            raise ValueError("not a dictionary")
    except (OSError, ValueError, plistlib.InvalidFileException) as e:
        print("cannot read %s: %s" % (path, e))
        return 1
    config = plistlib.dumps(
        {"type": "imageFile", "url": {"relative": "file://" + quote(image)}},
        fmt=plistlib.FMT_BINARY,
    )
    holders = desktop_holders(store)
    for h in holders:
        h["Desktop"].setdefault("Content", {})["Choices"] = [
            {
                "Provider": "com.apple.wallpaper.choice.image",
                "Configuration": config,
                "Files": [],
            }
        ]
    try:
        fd, tmp = tempfile.mkstemp(prefix=".wallpaper-", dir=os.path.dirname(os.path.abspath(path)))
        try:
            with os.fdopen(fd, "wb") as f:
                plistlib.dump(store, f, fmt=plistlib.FMT_BINARY)
            os.chmod(tmp, os.stat(path).st_mode & 0o777)
            os.replace(tmp, path)
        except BaseException:
            os.unlink(tmp)
            raise
    except OSError as e:
        print("cannot write %s: %s" % (path, e))
        return 1
    print(len(holders))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
