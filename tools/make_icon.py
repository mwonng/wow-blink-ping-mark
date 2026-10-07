"""Addon list icon: a blue "On my way" style arrow pointing down onto a glowing ring.

    pip install pillow
    python tools/make_icon.py          -> icon.tga (64x64 RGBA, uncompressed)

Drawn at 4x and downscaled for smooth edges.
"""
import os
from PIL import Image, ImageChops, ImageDraw, ImageFilter

S = 4                      # supersampling
W = 64 * S
OUT = os.path.join(os.path.dirname(__file__), "..", "icon.tga")


def px(v):
    return int(round(v * S))


img = Image.new("RGBA", (W, W), (0, 0, 0, 0))

# --- ground ring: a soft glow ellipse with a brighter rim
ring = Image.new("RGBA", (W, W), (0, 0, 0, 0))
d = ImageDraw.Draw(ring)
d.ellipse([px(8), px(42), px(56), px(60)], fill=(80, 180, 255, 110))
ring = ring.filter(ImageFilter.GaussianBlur(px(2.5)))
img.alpha_composite(ring)
d = ImageDraw.Draw(img)
d.ellipse([px(12), px(45), px(52), px(57)], outline=(190, 235, 255, 230), width=px(1.6))

# --- arrow: shaft + head, dark outline, blue body, white gloss on the left
shaft_l, shaft_r = px(24), px(40)
head_l, head_r = px(10), px(54)
top, neck, tip = px(4), px(30), px(50)
arrow = [
    (shaft_l, top), (shaft_r, top), (shaft_r, neck), (head_r, neck),
    (px(32), tip), (head_l, neck), (shaft_l, neck),
]

outline = Image.new("RGBA", (W, W), (0, 0, 0, 0))
ImageDraw.Draw(outline).polygon(arrow, fill=(8, 30, 70, 255))
outline = outline.filter(ImageFilter.MaxFilter(px(2.2) | 1))  # grow the shape for the outline
img.alpha_composite(outline)

# vertical gradient body, clipped by the arrow shape
body = Image.new("RGBA", (W, W), (0, 0, 0, 0))
bd = ImageDraw.Draw(body)
for y in range(top, tip + 1):
    t = (y - top) / max(1, tip - top)
    r = int(70 + (10 - 70) * t)
    g = int(190 + (110 - 190) * t)
    b = int(255 + (225 - 255) * t)
    bd.line([(0, y), (W, y)], fill=(r, g, b, 255))
mask = Image.new("L", (W, W), 0)
ImageDraw.Draw(mask).polygon(arrow, fill=255)
img.paste(body, (0, 0), mask)

# gloss: a lighter band on the left side of the shaft and head
gloss = Image.new("RGBA", (W, W), (0, 0, 0, 0))
gd = ImageDraw.Draw(gloss)
gd.polygon([(shaft_l + px(2), top + px(2)), (shaft_l + px(7), top + px(2)),
            (shaft_l + px(7), neck), (head_l + px(9), neck + px(2)), (px(30), tip - px(4)),
            (px(27), tip - px(4)), (head_l + px(5), neck + px(1)), (shaft_l + px(2), neck)],
           fill=(255, 255, 255, 95))
gloss = gloss.filter(ImageFilter.GaussianBlur(px(0.6)))
gloss.putalpha(ImageChops.multiply(gloss.getchannel("A"), mask))  # keep it inside the arrow
img.alpha_composite(gloss)

img = img.resize((64, 64), Image.LANCZOS)
img.save(OUT, format="TGA")
print("wrote", os.path.normpath(OUT))
