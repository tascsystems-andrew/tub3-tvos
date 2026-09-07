"""Build the tvOS brand assets from the project mark.

tvOS icons are not flat images: they are *layered* stacks that the system parallaxes as the
icon takes focus. So the mark is split across layers rather than flattened — the ink ground
behind, the purple shell in the middle, the gold conductor in front — which is what makes it
move like a tvOS icon instead of a sticker.
"""
import json
import os
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(HERE, "Apps/TV/Assets.xcassets")
BRAND = os.path.join(ASSETS, "App Icon & Top Shelf Image.brandassets")
MARK = "/path/to/BoobTube/8008tub3/packaging/assets/splash.png"

INK = (12, 11, 10, 255)
GOLD = (255, 200, 60, 255)
PURPLE = (168, 92, 246, 255)

def write(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        json.dump(data, f, indent=2)

def imageset(path, image, name, scales=("1x", "2x")):
    """An imageset holding one PNG. tvOS wants 1x and 2x; 2x is the real one."""
    os.makedirs(path, exist_ok=True)
    images = []
    for scale in scales:
        if scale == "2x":
            image.save(os.path.join(path, name))
            images.append({"idiom": "tv", "filename": name, "scale": scale})
        else:
            images.append({"idiom": "tv", "scale": scale})
    write(os.path.join(path, "Contents.json"),
          {"images": images, "info": {"author": "xcode", "version": 1}})

def layer(stack_dir, layer_name, image, order):
    d = os.path.join(stack_dir, f"{layer_name}.imagestacklayer")
    os.makedirs(d, exist_ok=True)
    write(os.path.join(d, "Contents.json"), {"info": {"author": "xcode", "version": 1}})
    imageset(os.path.join(d, "Content.imageset"), image, f"{layer_name.lower()}.png")

def mark(size, scale=1.0, with_shell=True, with_core=True):
    """The mark, split so each layer carries only its own part."""
    w, h = size
    canvas = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    src = Image.open(MARK).convert("RGBA")
    side = int(min(w, h) * 0.62 * scale)
    art = src.resize((side, side), Image.LANCZOS)

    pixels = art.load()
    for y in range(side):
        for x in range(side):
            r, g, b, a = pixels[x, y]
            if a < 20:
                continue
            gold = r > 200 and g > 150 and b < 120
            if gold and not with_core:
                pixels[x, y] = (0, 0, 0, 0)
            elif not gold and not with_shell:
                pixels[x, y] = (0, 0, 0, 0)
    canvas.paste(art, ((w - side) // 2, (h - side) // 2), art)
    return canvas

def ground(size):
    w, h = size
    img = Image.new("RGBA", (w, h), INK)
    draw = ImageDraw.Draw(img)
    # A soft vignette so the flat ink does not read as a hole behind the parallax.
    for i in range(40):
        k = i / 40
        draw.rectangle([int(w * k * 0.5), int(h * k * 0.5),
                        int(w - w * k * 0.5), int(h - h * k * 0.5)],
                       outline=(int(12 + 22 * (1 - k)), int(11 + 18 * (1 - k)),
                                int(10 + 30 * (1 - k)), 255))
    return img

def build_stack(name, size):
    # The declared size is the 1x size; the PNG we ship is the 2x one, so it has to be
    # rendered at twice the nominal dimensions or the back layer resolves to half the stack
    # and the asset compiler rejects it — "the last image stack layer must exactly fill".
    size = (size[0] * 2, size[1] * 2)
    stack = os.path.join(BRAND, f"{name}.imagestack")
    os.makedirs(stack, exist_ok=True)
    write(os.path.join(stack, "Contents.json"),
          {"layers": [{"filename": "Front.imagestacklayer"},
                      {"filename": "Middle.imagestacklayer"},
                      {"filename": "Back.imagestacklayer"}],
           "info": {"author": "xcode", "version": 1}})
    layer(stack, "Back", ground(size), 2)
    layer(stack, "Middle", mark(size, 1.0, with_shell=True, with_core=False), 1)
    layer(stack, "Front", mark(size, 1.0, with_shell=False, with_core=True), 0)

def build_top_shelf(name, size):
    size = (size[0] * 2, size[1] * 2)
    w, h = size
    img = ground(size)
    art = mark((int(h * 0.8), int(h * 0.8)), 1.0)
    img.paste(art, (int(w * 0.06), (h - art.height) // 2), art)
    imageset(os.path.join(BRAND, f"{name}.imageset"), img, f"{name.lower().replace(' ', '-')}.png")

os.makedirs(BRAND, exist_ok=True)
write(os.path.join(ASSETS, "Contents.json"), {"info": {"author": "xcode", "version": 1}})
write(os.path.join(BRAND, "Contents.json"),
      {"assets": [
          {"filename": "App Icon.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "400x240"},
          {"filename": "App Icon - App Store.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "1280x768"},
          {"filename": "Top Shelf Image.imageset", "idiom": "tv", "role": "top-shelf-image", "size": "1920x720"},
          {"filename": "Top Shelf Image Wide.imageset", "idiom": "tv", "role": "top-shelf-image-wide", "size": "2320x720"},
      ],
       "info": {"author": "xcode", "version": 1}})

build_stack("App Icon", (400, 240))
build_stack("App Icon - App Store", (1280, 768))
build_top_shelf("Top Shelf Image", (1920, 720))
build_top_shelf("Top Shelf Image Wide", (2320, 720))
print("brand assets written to", BRAND)
