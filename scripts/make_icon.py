#!/usr/bin/env python3
"""Generates Resources/Assets.xcassets/AppIcon.appiconset (an hourglass on a teal gradient).

    pip install pillow
    python3 scripts/make_icon.py
"""
import json
import os

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = os.path.join(os.path.dirname(__file__), "..", "Resources", "Assets.xcassets", "AppIcon.appiconset")
SS = 2          # supersampling factor
SIZE = 1024
S = SIZE * SS

# Palette from the web timer.
TEAL_LIGHT = (84, 191, 200)    # #54bfc8
TEAL = (65, 184, 194)          # #41b8c2
TEAL_MID = (42, 124, 131)      # #2A7C83
TEAL_DEEP = (29, 85, 89)       # #1D5559
GLASS = (244, 251, 251)        # #f4fbfb


def px(v):
    return int(round(v * SS))


def gradient(size, c0, c1, c2):
    """Diagonal gradient c0 -> c1 -> c2, top-left to bottom-right."""
    w, h = size
    img = Image.new("RGB", size)
    data = []
    for y in range(h):
        for x in range(w):
            t = (x / (w - 1) + y / (h - 1)) / 2
            a, b, u = (c0, c1, t * 2) if t < 0.5 else (c1, c2, (t - 0.5) * 2)
            data.append(tuple(int(a[i] + (b[i] - a[i]) * u) for i in range(3)))
    img.putdata(data)
    return img


def rounded_mask(box, radius):
    m = Image.new("L", (S, S), 0)
    ImageDraw.Draw(m).rounded_rectangle([px(v) for v in box], radius=px(radius), fill=255)
    return m


def render():
    # macOS icon grid: an 824pt rounded square centred in the 1024pt canvas.
    margin, body = 100, 824
    box = (margin, margin, margin + body, margin + body)
    tile_mask = rounded_mask(box, 185)

    bg = gradient((S, S), TEAL_LIGHT, TEAL_MID, TEAL_DEEP)
    canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    canvas.paste(bg, (0, 0), tile_mask)

    # Soft top highlight.
    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([px(150), px(40), px(874), px(520)], fill=(255, 255, 255, 46))
    glow = glow.filter(ImageFilter.GaussianBlur(px(60)))
    glow.putalpha(ImageChops.multiply(glow.getchannel("A"), tile_mask))
    canvas = Image.alpha_composite(canvas, glow)

    # Hourglass silhouette, centred on x=512.
    cx = 512
    top, bottom = 292, 732
    neck_y = (top + bottom) / 2
    half_w, neck_half = 150, 22
    bulb_top, bulb_bottom = top + 36, bottom - 36

    def glass_poly(inset=0):
        return [
            (cx - half_w + inset, bulb_top + inset * 0.6),
            (cx + half_w - inset, bulb_top + inset * 0.6),
            (cx + neck_half + inset * 0.4, neck_y - 18),
            (cx + neck_half + inset * 0.4, neck_y + 18),
            (cx + half_w - inset, bulb_bottom - inset * 0.6),
            (cx - half_w + inset, bulb_bottom - inset * 0.6),
            (cx - neck_half - inset * 0.4, neck_y + 18),
            (cx - neck_half - inset * 0.4, neck_y - 18),
        ]

    def scaled(points):
        return [(px(x), px(y)) for x, y in points]

    # Drop shadow under the glass.
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.polygon(scaled([(x, y + 14) for x, y in glass_poly()]), fill=(8, 40, 44, 120))
    for y0 in (top, bottom - 30):
        sd.rounded_rectangle([px(cx - 186), px(y0 + 14), px(cx + 186), px(y0 + 44)], radius=px(15), fill=(8, 40, 44, 120))
    shadow = shadow.filter(ImageFilter.GaussianBlur(px(18)))
    canvas = Image.alpha_composite(canvas, shadow)

    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.polygon(scaled(glass_poly()), fill=GLASS + (255,))

    # Sand: a pile in the lower bulb and a shrinking mass in the upper bulb, clipped to the glass.
    sand = Image.new("L", (S, S), 0)
    sd = ImageDraw.Draw(sand)
    inner = glass_poly(inset=18)
    sd.polygon(scaled([  # upper sand, funnel shape
        (inner[0][0] + 26, bulb_top + 78), (inner[1][0] - 26, bulb_top + 78),
        (cx + 8, neck_y - 14), (cx - 8, neck_y - 14),
    ]), fill=255)
    sd.polygon(scaled([  # lower pile
        (cx - 8, neck_y + 4), (cx + 8, neck_y + 4),
        (cx + 112, bulb_bottom - 20), (cx - 112, bulb_bottom - 20),
    ]), fill=255)
    sd.rectangle([px(cx - 3), px(neck_y - 14), px(cx + 3), px(neck_y + 40)], fill=255)  # falling stream
    clip = Image.new("L", (S, S), 0)
    ImageDraw.Draw(clip).polygon(scaled(inner), fill=255)
    sand = ImageChops.multiply(sand, clip)
    sand_fill = gradient((S, S), TEAL, TEAL_MID, TEAL_DEEP)
    layer.paste(sand_fill, (0, 0), sand)

    # Caps.
    for y0 in (top, bottom - 30):
        d.rounded_rectangle([px(cx - 186), px(y0), px(cx + 186), px(y0 + 30)], radius=px(15), fill=GLASS + (255,))
    canvas = Image.alpha_composite(canvas, layer)

    return canvas.resize((SIZE, SIZE), Image.LANCZOS)


def main():
    os.makedirs(ROOT, exist_ok=True)
    master = render()
    images = []
    for points in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            name = f"icon_{points}x{points}" + ("@2x" if scale == 2 else "") + ".png"
            master.resize((points * scale, points * scale), Image.LANCZOS).save(os.path.join(ROOT, name))
            images.append({"filename": name, "idiom": "mac", "scale": f"{scale}x", "size": f"{points}x{points}"})
    with open(os.path.join(ROOT, "Contents.json"), "w") as f:
        json.dump({"images": images, "info": {"author": "xcode", "version": 1}}, f, indent=2)
        f.write("\n")
    print("wrote", len(images), "icons to", os.path.normpath(ROOT))


if __name__ == "__main__":
    main()
