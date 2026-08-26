
from PIL import Image, ImageDraw, ImageFilter
import pathlib

GRADIENT_START = (255, 176, 32)
GRADIENT_END   = (240, 109, 30)
ON_BRAND       = (26, 18, 6)
SIZE = 1024

def hero_gradient(size):
    img = Image.new("RGB", (size, size)); px = img.load()
    for y in range(size):
        for x in range(size):
            t = (x + y) / (2 * (size - 1))
            px[x, y] = tuple(round(a + (b - a) * t) for a, b in zip(GRADIENT_START, GRADIENT_END))
    return img

def lit(img):
    size = img.size[0]
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).ellipse([-size*0.30, -size*0.50, size*0.78, size*0.42], fill=54)
    mask = mask.filter(ImageFilter.GaussianBlur(size * 0.13))
    return Image.composite(Image.new("RGB", (size, size), (255, 246, 228)), img, mask)

# Bolt normalised so its bounding box is centred on 0.5 in both axes.
_RAW = [(0.545,0.020),(0.235,0.560),(0.450,0.560),(0.400,0.980),(0.735,0.420),(0.520,0.420)]
_minx = min(p[0] for p in _RAW); _maxx = max(p[0] for p in _RAW)
_miny = min(p[1] for p in _RAW); _maxy = max(p[1] for p in _RAW)
_cx = (_minx + _maxx) / 2; _cy = (_miny + _maxy) / 2
BOLT = [(x - _cx + 0.5, y - _cy + 0.5) for x, y in _RAW]

def bolt_polygon(box, origin):
    ox, oy = origin
    return [(ox + x * box, oy + y * box) for x, y in BOLT]

def draw_bolt(img, inset):
    size = img.size[0]
    box = size * inset
    origin = ((size - box) / 2, (size - box) / 2)
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(layer).polygon(
        [(x + size*0.005, y + size*0.009) for x, y in bolt_polygon(box, origin)],
        fill=(90, 40, 0, 75))
    layer = layer.filter(ImageFilter.GaussianBlur(size * 0.011))
    ImageDraw.Draw(layer).polygon(bolt_polygon(box, origin), fill=ON_BRAND + (255,))
    img = img.convert("RGBA"); img.alpha_composite(layer)
    return img.convert("RGB")

out = pathlib.Path("assets/icon"); out.mkdir(parents=True, exist_ok=True)
draw_bolt(lit(hero_gradient(SIZE)), inset=0.62).save(out / "icon.png")

fg = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
box = SIZE * 0.44
origin = ((SIZE - box) / 2, (SIZE - box) / 2)
ImageDraw.Draw(fg).polygon(bolt_polygon(box, origin), fill=ON_BRAND + (255,))
fg.save(out / "icon_foreground.png")
lit(hero_gradient(SIZE)).save(out / "icon_background.png")
print("icons regenerated, mark optically centred")
