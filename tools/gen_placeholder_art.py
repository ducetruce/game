#!/usr/bin/env python3
"""Generate placeholder art for Hollowmere.

Writes a 16x16 tile atlas and a 4-facing character sprite sheet as PNGs, with
no third-party dependencies. Everything here is deliberately crude and exists
only so gameplay is never blocked waiting on art -- delete this script and its
output once real tilesets and creature art land.

    python3 tools/gen_placeholder_art.py

Output is deterministic: re-running produces byte-identical files, so this
never shows up as noise in a diff.
"""

from __future__ import annotations

import json
import os
import struct
import zlib

TILE = 16
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


# --- tiny PNG writer -------------------------------------------------------

class Canvas:
    """An RGBA pixel buffer. Origin is top-left, y grows downward."""

    def __init__(self, width: int, height: int) -> None:
        self.width = width
        self.height = height
        self.px = bytearray(width * height * 4)

    def set(self, x: int, y: int, rgba: tuple[int, int, int, int]) -> None:
        if not (0 <= x < self.width and 0 <= y < self.height):
            return
        i = (y * self.width + x) * 4
        self.px[i:i + 4] = bytes(rgba)

    def rect(self, x: int, y: int, w: int, h: int, rgba) -> None:
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                self.set(xx, yy, rgba)

    def blob(self, cx: float, cy: float, rx: float, ry: float, rgba) -> None:
        """Filled ellipse. Crude, but it reads as a body at 32x32."""
        for yy in range(int(cy - ry), int(cy + ry) + 1):
            for xx in range(int(cx - rx), int(cx + rx) + 1):
                dx = (xx + 0.5 - cx) / max(rx, 0.001)
                dy = (yy + 0.5 - cy) / max(ry, 0.001)
                if dx * dx + dy * dy <= 1.0:
                    self.set(xx, yy, rgba)

    def save(self, path: str) -> None:
        rows = bytearray()
        stride = self.width * 4
        for y in range(self.height):
            rows.append(0)  # filter type 0 (None) -- keeps output deterministic
            rows.extend(self.px[y * stride:(y + 1) * stride])

        def chunk(tag: bytes, data: bytes) -> bytes:
            body = tag + data
            return struct.pack(">I", len(data)) + body + struct.pack(
                ">I", zlib.crc32(body) & 0xFFFFFFFF
            )

        header = struct.pack(">IIBBBBB", self.width, self.height, 8, 6, 0, 0, 0)
        png = (
            b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", header)
            + chunk(b"IDAT", zlib.compress(bytes(rows), 9))
            + chunk(b"IEND", b"")
        )
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as fh:
            fh.write(png)
        print("wrote %s (%dx%d)" % (os.path.relpath(path, ROOT), self.width, self.height))


def noise(x: int, y: int, seed: int) -> int:
    """Stable per-pixel hash. Stands in for hand-placed dither until real art."""
    h = (x * 73856093) ^ (y * 19349663) ^ (seed * 83492791)
    h = (h ^ (h >> 13)) * 1274126177
    return (h ^ (h >> 16)) & 0xFF


# --- palette ---------------------------------------------------------------

A = 255
GRASS = (64, 102, 66, A)
GRASS_HI = (80, 122, 78, A)
GRASS_LO = (52, 86, 56, A)
TUFT = (104, 142, 92, A)

PATH = (124, 104, 80, A)
PATH_HI = (142, 122, 96, A)
PATH_LO = (104, 86, 66, A)

WATER = (46, 78, 110, A)
WATER_HI = (68, 106, 140, A)
WATER_LO = (34, 60, 88, A)

ROCK = (96, 98, 106, A)
ROCK_HI = (126, 128, 136, A)
ROCK_LO = (66, 68, 76, A)

TRUNK = (72, 54, 44, A)
LEAF = (46, 84, 56, A)
LEAF_HI = (64, 108, 70, A)
LEAF_LO = (32, 62, 42, A)

WOOD = (110, 84, 58, A)
WOOD_HI = (138, 108, 76, A)
WOOD_LO = (78, 58, 40, A)


def speckle(c: Canvas, ox: int, oy: int, base, hi, lo, seed: int, density: int = 90) -> None:
    """Fill one tile with base colour plus stable two-tone dither."""
    c.rect(ox, oy, TILE, TILE, base)
    for y in range(TILE):
        for x in range(TILE):
            n = noise(ox + x, oy + y, seed)
            if n > 255 - density // 2:
                c.set(ox + x, oy + y, hi)
            elif n < density // 2:
                c.set(ox + x, oy + y, lo)


# --- tile atlas ------------------------------------------------------------
# Layout is 4 columns x 2 rows. Row 0 is walkable, row 1 is solid. The tileset
# resource and src/overworld/tile_legend.gd both depend on these coordinates.

def build_atlas() -> Canvas:
    c = Canvas(TILE * 4, TILE * 2)

    # (0,0) grass
    speckle(c, 0, 0, GRASS, GRASS_HI, GRASS_LO, 11)

    # (1,0) grass with tufts
    speckle(c, TILE, 0, GRASS, GRASS_HI, GRASS_LO, 11)
    for tx, ty in ((3, 4), (9, 3), (6, 10), (12, 11), (2, 12)):
        c.set(TILE + tx, ty, TUFT)
        c.set(TILE + tx, ty + 1, TUFT)
        c.set(TILE + tx - 1, ty + 1, TUFT)
        c.set(TILE + tx + 1, ty + 1, TUFT)

    # (2,0) packed dirt path
    speckle(c, TILE * 2, 0, PATH, PATH_HI, PATH_LO, 23)

    # (3,0) worn path, coarser grit
    speckle(c, TILE * 3, 0, PATH, PATH_HI, PATH_LO, 29, density=150)

    # (0,1) water -- solid
    speckle(c, 0, TILE, WATER, WATER_HI, WATER_LO, 37, density=60)
    for y in (3, 8, 13):
        for x in range(2, 14, 4):
            c.set(x, TILE + y, WATER_HI)
            c.set(x + 1, TILE + y, WATER_HI)

    # (1,1) rock -- solid
    speckle(c, TILE, TILE, ROCK, ROCK_HI, ROCK_LO, 41, density=120)
    c.rect(TILE + 1, TILE + 1, 14, 2, ROCK_HI)
    c.rect(TILE + 1, TILE + 13, 14, 2, ROCK_LO)

    # (2,1) tree canopy -- solid
    speckle(c, TILE * 2, TILE, LEAF, LEAF_HI, LEAF_LO, 53, density=140)
    c.rect(TILE * 2 + 7, TILE + 11, 3, 5, TRUNK)
    c.rect(TILE * 2 + 4, TILE + 1, 8, 2, LEAF_HI)

    # (3,1) fence -- solid
    speckle(c, TILE * 3, TILE, GRASS, GRASS_HI, GRASS_LO, 11)
    c.rect(TILE * 3 + 0, TILE + 5, TILE, 2, WOOD)
    c.rect(TILE * 3 + 0, TILE + 9, TILE, 2, WOOD_LO)
    c.rect(TILE * 3 + 3, TILE + 3, 2, 11, WOOD_HI)
    c.rect(TILE * 3 + 11, TILE + 3, 2, 11, WOOD_HI)

    return c


# --- character sprite sheet ------------------------------------------------
# 4 frames of 16x24, in facing order: down, up, left, right. That order is
# mirrored by Player.Facing, so frame index == facing index.

SHADOW = (0, 0, 0, 70)
CLOAK = (74, 66, 96, A)
CLOAK_HI = (98, 88, 124, A)
CLOAK_LO = (52, 46, 70, A)
SKIN = (198, 158, 126, A)
HOOD = (58, 52, 78, A)
BOOT = (44, 38, 46, A)
EYE = (26, 24, 34, A)

CW, CH = 16, 24


def build_character() -> Canvas:
    c = Canvas(CW * 4, CH)
    for i in range(4):
        ox = i * CW
        c.rect(ox + 4, CH - 3, 8, 2, SHADOW)          # ground shadow
        c.rect(ox + 5, CH - 8, 2, 6, BOOT)            # legs
        c.rect(ox + 9, CH - 8, 2, 6, BOOT)
        c.rect(ox + 4, 9, 8, 9, CLOAK)                # body
        c.rect(ox + 3, 11, 1, 6, CLOAK_LO)
        c.rect(ox + 12, 11, 1, 6, CLOAK_LO)
        c.rect(ox + 5, 9, 6, 2, CLOAK_HI)
        c.rect(ox + 5, 4, 6, 6, SKIN)                 # head
        c.rect(ox + 4, 2, 8, 3, HOOD)                 # hood brim

    # down: face forward, both eyes
    c.set(6, 7, EYE)
    c.set(9, 7, EYE)

    # up: hood covers the face entirely
    c.rect(CW + 5, 4, 6, 6, HOOD)

    # left: profile, hood pulled to the trailing side
    c.rect(CW * 2 + 9, 2, 3, 7, HOOD)
    c.set(CW * 2 + 6, 7, EYE)

    # right: mirrored profile
    c.rect(CW * 3 + 4, 2, 3, 7, HOOD)
    c.set(CW * 3 + 9, 7, EYE)

    return c


# --- creature sprites ------------------------------------------------------
# One 32x32 frame per species, written to assets/sprites/creatures/<id>.png and
# loaded by id at runtime. Shapes are rough silhouettes chosen per species so
# the seven read as different animals on a battle screen; colours come from the
# creature's type. Real creature art drops into the same paths.

CREATURE = 32

TYPE_PALETTE = {
    "bloom":  ((70, 112, 68, A), (98, 146, 88, A), (46, 78, 50, A)),
    "stone":  ((104, 106, 114, A), (140, 142, 150, A), (68, 70, 78, A)),
    "gale":   ((150, 170, 186, A), (196, 212, 224, A), (104, 124, 144, A)),
    "mire":   ((88, 96, 66, A), (118, 128, 88, A), (56, 62, 44, A)),
    "cinder": ((178, 92, 54, A), (226, 150, 76, A), (118, 54, 38, A)),
    "wane":   ((98, 86, 118, A), (136, 122, 158, A), (62, 54, 80, A)),
    "beast":  ((122, 96, 70, A), (156, 128, 96, A), (82, 62, 46, A)),
}
DEFAULT_PALETTE = ((110, 110, 118, A), (150, 150, 158, A), (72, 72, 80, A))


def draw_creature(c: Canvas, shape: str, base, hi, lo) -> None:
    c.rect(8, CREATURE - 3, 16, 2, SHADOW)

    if shape == "quadruped":                      # thistlecalf
        c.blob(16, 19, 9, 6, base)
        c.blob(23, 13, 5, 4.5, hi)                # head
        for lx in (10, 14, 18, 21):
            c.rect(lx, 24, 2, 5, lo)
        c.rect(8, 16, 3, 2, lo)                   # tail
        for bx, by in ((12, 15), (16, 18), (19, 14)):
            c.rect(bx, by, 2, 2, lo)              # burrs
    elif shape == "stack":                        # cairnling
        c.blob(16, 26, 9, 4, lo)
        c.blob(16, 19, 7, 4, base)
        c.blob(16, 13, 5, 3.5, hi)
        c.blob(16, 8, 3, 2.5, base)
        c.set(14, 13, lo)
        c.set(18, 13, lo)
    elif shape == "flier":                        # skirling
        c.blob(16, 17, 4, 6, base)
        c.blob(7, 13, 6, 3, hi)                   # wings
        c.blob(25, 13, 6, 3, hi)
        c.blob(16, 9, 3, 3, hi)
        c.rect(15, 23, 1, 4, lo)
        c.rect(18, 23, 1, 4, lo)
    elif shape == "lump":                         # sloughback
        c.blob(16, 22, 12, 7, base)
        c.blob(16, 17, 9, 4, hi)                  # ridge
        c.blob(24, 21, 4, 3.5, hi)                # head
        for bx in (9, 13, 17, 21):
            c.rect(bx, 14, 2, 2, lo)
    elif shape == "wick":                         # emberwick
        c.rect(15, 12, 3, 16, lo)                 # wick
        c.blob(16, 10, 5, 6, base)                # flame
        c.blob(16, 8, 3, 4, hi)
        c.blob(11, 20, 3, 2, base)                # wings
        c.blob(21, 20, 3, 2, base)
    elif shape == "wisp":                         # gloamkin
        c.blob(16, 14, 6, 8, base)
        c.blob(16, 11, 4, 5, hi)
        for yy in range(21, 29):                  # dissolving lower half
            width = 9 - (yy - 21)
            if (yy % 2) == 0:
                c.rect(16 - width // 2, yy, width, 1, lo)
        c.set(14, 11, lo)
        c.set(18, 11, lo)
    else:                                          # moorhound
        c.blob(15, 18, 10, 5, base)
        c.blob(24, 14, 5, 4, hi)                  # head
        c.rect(26, 10, 2, 3, lo)                  # ear
        for lx in (9, 12, 18, 21):
            c.rect(lx, 22, 2, 6, lo)
        c.rect(4, 14, 4, 2, lo)                   # tail
        c.set(25, 13, lo)


SHAPES = {
    "thistlecalf": "quadruped",
    "cairnling": "stack",
    "skirling": "flier",
    "sloughback": "lump",
    "emberwick": "wick",
    "gloamkin": "wisp",
    "moorhound": "hound",
}


def build_creature_sprites() -> None:
    """Reads data/creatures.json so the sprite set always matches the roster."""
    path = os.path.join(ROOT, "data", "creatures.json")
    with open(path) as fh:
        roster = json.load(fh)["creatures"]
    for species in roster:
        species_id = species["id"]
        first_type = (species.get("types") or ["beast"])[0]
        base, hi, lo = TYPE_PALETTE.get(first_type, DEFAULT_PALETTE)
        canvas = Canvas(CREATURE, CREATURE)
        draw_creature(canvas, SHAPES.get(species_id, "hound"), base, hi, lo)
        canvas.save(os.path.join(ROOT, "assets", "sprites", "creatures", species_id + ".png"))


def main() -> None:
    build_atlas().save(os.path.join(ROOT, "assets", "tilesets", "placeholder_atlas.png"))
    build_character().save(
        os.path.join(ROOT, "assets", "sprites", "placeholder_character.png")
    )
    build_creature_sprites()


if __name__ == "__main__":
    main()
