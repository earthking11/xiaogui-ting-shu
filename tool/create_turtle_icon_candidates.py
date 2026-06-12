#!/usr/bin/env python3
"""Create cute turtle-reading app icon candidates for review."""

from __future__ import annotations

import shutil
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

PROJECT_ROOT = Path(__file__).resolve().parents[1]
CANDIDATE_DIR = PROJECT_ROOT / "assets/branding/icon_candidates"
AI_SOURCE = Path(
    "/Users/lidazuo/.codex/generated_images/019eb0e9-a6a2-7d42-a3df-b6047db58b33/"
    "ig_0865b6cefecf5f30016a2a6b27c8348194a99ca8fd75e4f185.png"
)

SIZE = 1024


def rounded_rect(draw: ImageDraw.ImageDraw, box: tuple[int, int, int, int], radius: int, fill, outline=None, width=1) -> None:
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


def ellipse(draw: ImageDraw.ImageDraw, box: tuple[int, int, int, int], fill, outline=None, width=1) -> None:
    draw.ellipse(box, fill=fill, outline=outline, width=width)


def polygon(draw: ImageDraw.ImageDraw, points: list[tuple[int, int]], fill, outline=None) -> None:
    draw.polygon(points, fill=fill, outline=outline)


def add_shadow(base: Image.Image, mask: Image.Image, offset: tuple[int, int], blur: int, color: tuple[int, int, int, int]) -> None:
    layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
    color_layer = Image.new("RGBA", base.size, color)
    layer.paste(color_layer, offset, mask)
    base.alpha_composite(layer.filter(ImageFilter.GaussianBlur(blur)))


def make_background(colors: tuple[tuple[int, int, int], tuple[int, int, int]], radius: int = 210) -> Image.Image:
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    px = img.load()
    top, bottom = colors
    for y in range(SIZE):
        ratio = y / (SIZE - 1)
        color = tuple(int(top[i] + (bottom[i] - top[i]) * ratio) for i in range(3)) + (255,)
        for x in range(SIZE):
            px[x, y] = color
    mask = Image.new("L", (SIZE, SIZE), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle((44, 44, 980, 980), radius=radius, fill=255)
    out = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    out.paste(img, (0, 0), mask)
    return out


def draw_book(draw: ImageDraw.ImageDraw, variant: str = "open") -> None:
    if variant == "big":
        polygon(draw, [(258, 568), (512, 632), (512, 830), (244, 760)], fill=(134, 78, 38), outline=(94, 53, 27))
        polygon(draw, [(512, 632), (766, 568), (780, 760), (512, 830)], fill=(156, 88, 41), outline=(94, 53, 27))
        polygon(draw, [(282, 540), (512, 596), (512, 760), (276, 710)], fill=(255, 242, 198), outline=(214, 183, 126))
        polygon(draw, [(512, 596), (742, 540), (748, 710), (512, 760)], fill=(255, 247, 211), outline=(214, 183, 126))
    else:
        polygon(draw, [(296, 598), (512, 654), (512, 798), (286, 748)], fill=(255, 243, 202), outline=(214, 183, 126))
        polygon(draw, [(512, 654), (728, 598), (738, 748), (512, 798)], fill=(255, 248, 218), outline=(214, 183, 126))
        polygon(draw, [(286, 626), (512, 686), (512, 828), (270, 770)], fill=(143, 82, 41), outline=(96, 56, 31))
        polygon(draw, [(512, 686), (738, 626), (754, 770), (512, 828)], fill=(164, 94, 45), outline=(96, 56, 31))
        draw.line((512, 654, 512, 828), fill=(112, 70, 39), width=8)


def candidate_b() -> Image.Image:
    img = make_background(((255, 246, 223), (219, 241, 230)))
    draw = ImageDraw.Draw(img)
    shadow_mask = Image.new("L", (SIZE, SIZE), 0)
    smd = ImageDraw.Draw(shadow_mask)
    smd.ellipse((202, 240, 822, 900), fill=255)
    add_shadow(img, shadow_mask, (0, 28), 32, (88, 58, 34, 78))

    ellipse(draw, (254, 386, 770, 896), fill=(189, 139, 62), outline=(119, 83, 41), width=18)
    for x in (330, 452, 574):
        rounded_rect(draw, (x, 430, x + 110, 790), 44, fill=(202, 155, 76), outline=(139, 94, 45), width=8)
    ellipse(draw, (278, 208, 746, 574), fill=(154, 202, 105), outline=(88, 126, 62), width=18)
    ellipse(draw, (194, 522, 332, 706), fill=(143, 190, 97), outline=(88, 126, 62), width=14)
    ellipse(draw, (692, 522, 830, 706), fill=(143, 190, 97), outline=(88, 126, 62), width=14)
    ellipse(draw, (290, 792, 418, 904), fill=(143, 190, 97), outline=(88, 126, 62), width=12)
    ellipse(draw, (606, 792, 734, 904), fill=(143, 190, 97), outline=(88, 126, 62), width=12)

    ellipse(draw, (374, 350, 464, 448), fill=(255, 255, 246), outline=(71, 75, 53), width=7)
    ellipse(draw, (560, 350, 650, 448), fill=(255, 255, 246), outline=(71, 75, 53), width=7)
    ellipse(draw, (402, 380, 448, 432), fill=(80, 58, 43))
    ellipse(draw, (588, 380, 634, 432), fill=(80, 58, 43))
    ellipse(draw, (420, 386, 434, 402), fill=(255, 255, 255))
    ellipse(draw, (606, 386, 620, 402), fill=(255, 255, 255))
    draw.arc((422, 418, 602, 520), start=22, end=158, fill=(67, 91, 54), width=10)
    draw_book(draw, "open")
    return img


def candidate_c() -> Image.Image:
    img = make_background(((239, 249, 229), (255, 238, 210)), radius=260)
    draw = ImageDraw.Draw(img)
    ellipse(draw, (152, 242, 872, 920), fill=(108, 155, 91), outline=(55, 95, 66), width=22)
    ellipse(draw, (240, 296, 784, 858), fill=(186, 135, 63), outline=(98, 71, 42), width=18)
    ellipse(draw, (306, 168, 718, 540), fill=(135, 203, 123), outline=(58, 119, 74), width=20)
    ellipse(draw, (214, 526, 368, 730), fill=(123, 188, 111), outline=(58, 119, 74), width=16)
    ellipse(draw, (656, 526, 810, 730), fill=(123, 188, 111), outline=(58, 119, 74), width=16)
    ellipse(draw, (376, 322, 468, 424), fill=(255, 255, 251), outline=(45, 66, 44), width=7)
    ellipse(draw, (556, 322, 648, 424), fill=(255, 255, 251), outline=(45, 66, 44), width=7)
    ellipse(draw, (406, 352, 452, 404), fill=(65, 51, 42))
    ellipse(draw, (586, 352, 632, 404), fill=(65, 51, 42))
    ellipse(draw, (422, 360, 436, 376), fill=(255, 255, 255))
    ellipse(draw, (602, 360, 616, 376), fill=(255, 255, 255))
    draw.arc((430, 402, 594, 500), start=24, end=156, fill=(41, 92, 57), width=11)
    draw_book(draw, "big")
    return img


def candidate_d() -> Image.Image:
    img = make_background(((255, 241, 214), (230, 245, 244)), radius=190)
    draw = ImageDraw.Draw(img)
    ellipse(draw, (188, 218, 836, 912), fill=(97, 151, 103), outline=(43, 86, 60), width=20)
    rounded_rect(draw, (278, 360, 746, 850), 168, fill=(179, 127, 59), outline=(98, 67, 34), width=16)
    ellipse(draw, (308, 150, 716, 538), fill=(161, 219, 128), outline=(65, 128, 76), width=20)
    ellipse(draw, (246, 576, 374, 752), fill=(145, 206, 113), outline=(65, 128, 76), width=14)
    ellipse(draw, (650, 576, 778, 752), fill=(145, 206, 113), outline=(65, 128, 76), width=14)
    ellipse(draw, (380, 328, 474, 430), fill=(255, 255, 248), outline=(56, 77, 49), width=7)
    ellipse(draw, (550, 328, 644, 430), fill=(255, 255, 248), outline=(56, 77, 49), width=7)
    ellipse(draw, (410, 356, 458, 412), fill=(70, 49, 38))
    ellipse(draw, (580, 356, 628, 412), fill=(70, 49, 38))
    ellipse(draw, (426, 364, 442, 382), fill=(255, 255, 255))
    ellipse(draw, (596, 364, 612, 382), fill=(255, 255, 255))
    draw.arc((438, 410, 586, 502), start=28, end=152, fill=(53, 98, 58), width=10)
    draw_book(draw, "big")
    rounded_rect(draw, (398, 780, 626, 846), 30, fill=(255, 228, 158), outline=(179, 126, 58), width=8)
    return img


def prepare_ai_candidate() -> None:
    if AI_SOURCE.exists():
        shutil.copyfile(AI_SOURCE, CANDIDATE_DIR / "candidate-a-ai-soft-3d.png")


def create_contact_sheet(paths: list[Path]) -> None:
    thumb_size = 360
    label_h = 58
    gap = 32
    sheet = Image.new("RGBA", (gap + 2 * (thumb_size + gap), gap + 2 * (thumb_size + label_h + gap)), (248, 243, 232, 255))
    draw = ImageDraw.Draw(sheet)
    for index, path in enumerate(paths):
        image = Image.open(path).convert("RGBA")
        image.thumbnail((thumb_size, thumb_size), Image.Resampling.LANCZOS)
        col = index % 2
        row = index // 2
        x = gap + col * (thumb_size + gap)
        y = gap + row * (thumb_size + label_h + gap)
        tile = Image.new("RGBA", (thumb_size, thumb_size), (255, 255, 255, 255))
        tile.alpha_composite(image, ((thumb_size - image.width) // 2, (thumb_size - image.height) // 2))
        sheet.alpha_composite(tile, (x, y))
        draw.text((x + 8, y + thumb_size + 14), f"{chr(65 + index)}  {path.stem}", fill=(54, 48, 42))
    sheet.save(CANDIDATE_DIR / "contact-sheet.png")


def main() -> None:
    CANDIDATE_DIR.mkdir(parents=True, exist_ok=True)
    prepare_ai_candidate()
    variants = {
        "candidate-b-kawaii-plush.png": candidate_b(),
        "candidate-c-flat-badge.png": candidate_c(),
        "candidate-d-rounded-toy.png": candidate_d(),
    }
    for name, image in variants.items():
        image.save(CANDIDATE_DIR / name)
    paths = [
        CANDIDATE_DIR / "candidate-a-ai-soft-3d.png",
        CANDIDATE_DIR / "candidate-b-kawaii-plush.png",
        CANDIDATE_DIR / "candidate-c-flat-badge.png",
        CANDIDATE_DIR / "candidate-d-rounded-toy.png",
    ]
    create_contact_sheet([path for path in paths if path.exists()])
    print(f"Wrote candidates to {CANDIDATE_DIR}")


if __name__ == "__main__":
    main()
