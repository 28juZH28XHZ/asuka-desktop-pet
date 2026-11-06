"""Generate pet/assets PNGs and the tray icon from the delivery spritesheets.

Usage: python build-assets.py
Needs Pillow (pip install pillow).
"""
import os

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
DELIVERY = os.path.join(ROOT, "delivery", "asuka-v2_20261026")
ASSETS = os.path.join(HERE, "assets")


def main() -> None:
    os.makedirs(ASSETS, exist_ok=True)
    for form, name in (("asuka-school", "school"), ("asuka-work", "work")):
        src = os.path.join(DELIVERY, form, "spritesheet.webp")
        if not os.path.exists(src):
            raise SystemExit(f"missing spritesheet: {src}")
        image = Image.open(src).convert("RGBA")
        out = os.path.join(ASSETS, name + ".png")
        image.save(out, "PNG", optimize=True)
        print(f"{name}: {image.size[0]}x{image.size[1]} -> {out}")

    school = Image.open(os.path.join(ASSETS, "school.png")).convert("RGBA")
    icon = school.crop((0, 0, 192, 208)).resize((64, 64), Image.LANCZOS)
    icon.save(
        os.path.join(ASSETS, "app.ico"),
        sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64)],
    )
    print("icon: assets/app.ico")


if __name__ == "__main__":
    main()
