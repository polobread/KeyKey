#!/usr/bin/env python3
"""Compose the five-platform gallery image from unmodified product captures."""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont


STORE = Path(__file__).resolve().parent
WIDTH, HEIGHT = 1080, 1920
PURPLE = (128, 0, 128)
WHITE = (255, 255, 255)


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    names = (
        ["/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc",
         "/System/Library/Fonts/PingFang.ttc",
         "/System/Library/Fonts/Supplemental/PingFang.ttc"]
        if bold else
        ["/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
         "/System/Library/Fonts/PingFang.ttc",
         "/System/Library/Fonts/Supplemental/PingFang.ttc"]
    )
    for name in names:
        if Path(name).is_file():
            return ImageFont.truetype(name, size)
    raise FileNotFoundError("A Traditional Chinese Noto Sans or PingFang font is required")


def centered(draw: ImageDraw.ImageDraw, text: str, y: int, size: int,
             color: tuple[int, int, int] = WHITE, bold: bool = False) -> None:
    face = font(size, bold)
    bounds = draw.textbbox((0, 0), text, font=face)
    draw.text(((WIDTH - bounds[2] + bounds[0]) / 2, y), text,
              font=face, fill=color)


def backdrop() -> Image.Image:
    # Same dark-to-purple palette and soft circular accents as the existing 05.png.
    image = Image.new("RGB", (WIDTH, HEIGHT))
    pixels = image.load()
    for y in range(HEIGHT):
        t = y / (HEIGHT - 1)
        for x in range(WIDTH):
            glow = max(0, 1 - abs(x / WIDTH - 0.76) * 1.15) * (1 - t)
            pixels[x, y] = (
                int(39 + 78 * (1 - t) + 16 * glow),
                int(16 + 3 * (1 - t)),
                int(55 + 49 * (1 - t) + 11 * glow),
            )
    layer = Image.new("RGBA", image.size)
    draw = ImageDraw.Draw(layer)
    draw.ellipse((780, -240, 1390, 570), fill=(255, 255, 255, 20))
    draw.ellipse((-270, 1060, 480, 1810), fill=(255, 255, 255, 13))
    return Image.alpha_composite(image.convert("RGBA"), layer)


def card(canvas: Image.Image, name: str, source: str,
         box: tuple[int, int, int, int], development: bool = False) -> None:
    x, y, width, height = box
    shadow = Image.new("RGBA", canvas.size)
    ImageDraw.Draw(shadow).rounded_rectangle(
        (x + 3, y + 9, x + width + 3, y + height + 9),
        radius=28, fill=(0, 0, 0, 95))
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(17)))
    draw = ImageDraw.Draw(canvas)
    draw.rounded_rectangle((x, y, x + width, y + height), radius=28, fill=WHITE)

    title = name + (" · 開發中" if development else "")
    face = font(27 if development else 30, True)
    text_box = draw.textbbox((0, 0), title, font=face)
    draw.text((x + (width - text_box[2] + text_box[0]) / 2, y + 15),
              title, font=face, fill=PURPLE)

    screenshot = Image.open(STORE / "Sources" / source).convert("RGBA")
    available_w = width - 24
    available_h = height - 87
    screenshot.thumbnail((available_w, available_h), Image.Resampling.LANCZOS)
    px = x + (width - screenshot.width) // 2
    py = y + 64 + (available_h - screenshot.height) // 2
    canvas.alpha_composite(screenshot, (px, py))


def main() -> None:
    canvas = backdrop()
    draw = ImageDraw.Draw(canvas)
    centered(draw, "手機桌機，都用同一套手感", 59, 54, bold=True)
    centered(draw, "Android · iOS · macOS · Windows · Linux", 151, 28, bold=True)
    draw.rounded_rectangle((351, 224, 729, 286), radius=31,
                           fill=(151, 65, 153, 255))
    centered(draw, "琦琦注音", 231, 27, bold=True)

    card(canvas, "Android", "android-notes-floating-qi.png", (85, 331, 420, 567))
    card(canvas, "iOS", "ios-notes-qi.png", (575, 331, 420, 567))
    card(canvas, "macOS", "chichi-macos.png", (54, 955, 300, 460))
    card(canvas, "Windows", "chichi-windows.png", (390, 955, 300, 460))
    card(canvas, "Linux", "chichi-linux.png", (726, 955, 300, 460), True)

    draw = ImageDraw.Draw(canvas)
    centered(draw, "熟悉的注音，陪你切換不同裝置", 1472, 33, bold=True)
    centered(draw, "Linux 原生版正在開發中", 1532, 25)

    output = canvas.convert("RGB")
    for destination in (STORE / "GooglePlay/Phone/05.png",
                        STORE / "FivePlatforms/five-platforms.png"):
        destination.parent.mkdir(parents=True, exist_ok=True)
        output.save(destination, format="PNG", optimize=True)
        print(destination.relative_to(STORE))


if __name__ == "__main__":
    main()
