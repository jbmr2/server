#!/usr/bin/env python3
"""Remove alpha channel from PNG screenshots for App Store Connect."""
from PIL import Image
import os
import sys

folder = sys.argv[1] if len(sys.argv) > 1 else "AppStoreScreenshots"
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
src_dir = os.path.join(root, folder)
out_dir = os.path.join(src_dir, "opaque")
os.makedirs(out_dir, exist_ok=True)

for name in sorted(f for f in os.listdir(src_dir) if f.endswith(".png")):
    path = os.path.join(src_dir, name)
    img = Image.open(path)
    if img.mode in ("RGBA", "LA", "P"):
        bg = Image.new("RGB", img.size, (0, 0, 0))
        if img.mode == "P":
            img = img.convert("RGBA")
        if img.mode in ("RGBA", "LA"):
            bg.paste(img, mask=img.split()[-1])
        else:
            bg.paste(img)
        img = bg
    elif img.mode != "RGB":
        img = img.convert("RGB")
    out_path = os.path.join(out_dir, name)
    img.save(out_path, "PNG")
    print(f"Fixed: {name} -> opaque/{name}")
