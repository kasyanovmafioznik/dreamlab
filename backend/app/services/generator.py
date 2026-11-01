"""Procedural art generator (Pillow only, no network, deterministic).

Not a real diffusion model — but a layered fBm-noise painter that composes
a proper picture per style: gradient sky, clouds, sun glow, mountain ridges,
water reflections, city skylines, watercolor washes, etc. Seeded by the
prompt, so the same input always yields the same artwork.
"""

from __future__ import annotations

import hashlib
import math
import random
import textwrap
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

from app.models import ASPECT_SHAPES, QUALITIES, AspectRatio, Quality, Style

# ---------------------------------------------------------------------------
# Palettes
# ---------------------------------------------------------------------------

# General purpose: (bg_top, bg_bottom, accent, ink) — used by the text panel.
_STYLE_PALETTES: dict[Style, tuple[str, str, str, str]] = {
    Style.photorealistic: ("#1b2a41", "#4a6fa5", "#8ab4f8", "#ffffff"),
    Style.illustration: ("#ff9a3c", "#ff3f6c", "#ffe66d", "#2b2118"),
    Style.minimal: ("#f4f4f5", "#d9d9de", "#6366f1", "#18181b"),
    Style.cinematic: ("#0f0f1a", "#3b1d4f", "#f5a623", "#f5f5f5"),
    Style.cyberpunk: ("#0d0221", "#ff2a6d", "#05d9e8", "#d1f7ff"),
    Style.watercolor: ("#e8f4f8", "#f9d5e5", "#98d4bb", "#3d3d3d"),
}

_STYLE_TAGS: dict[Style, str] = {
    Style.photorealistic: "CAMERA RAW",
    Style.illustration: "HAND DRAWN",
    Style.minimal: "LESS IS MORE",
    Style.cinematic: "ANAMORPHIC",
    Style.cyberpunk: "NEON NIGHT",
    Style.watercolor: "WET ON WET",
}


def _hash_seed(*parts: str) -> int:
    return int(hashlib.sha256("|".join(parts).encode()).hexdigest()[:8], 16)


# ---------------------------------------------------------------------------
# Color / geometry helpers
# ---------------------------------------------------------------------------


def _rgb(hex_color: str) -> tuple[int, int, int]:
    h = hex_color.lstrip("#")
    return tuple(int(h[i : i + 2], 16) for i in (0, 2, 4))  # type: ignore[return-value]


def _as_rgb(c: str | tuple[int, int, int]) -> tuple[int, int, int]:
    return _rgb(c) if isinstance(c, str) else c


def _mix(c1: tuple[int, int, int], c2: tuple[int, int, int], t: float) -> tuple[int, int, int]:
    return tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3))  # type: ignore[return-value]


def _lerp_color(
    c1: str | tuple[int, int, int], c2: str | tuple[int, int, int], t: float
) -> tuple[int, int, int]:
    return _mix(_as_rgb(c1), _as_rgb(c2), t)


def _shade(c: tuple[int, int, int], f: float) -> tuple[int, int, int]:
    return tuple(max(0, min(255, int(v * f))) for v in c)  # type: ignore[return-value]


def _vgrad(size: tuple[int, int], stops: list[tuple[float, str]]) -> Image.Image:
    """Vertical multi-stop gradient."""
    w, h = size
    strip = Image.new("RGB", (1, h))
    px = strip.load()
    stops = sorted(stops, key=lambda s: s[0])
    for y in range(h):
        t = y / max(h - 1, 1)
        for (p0, c0), (p1, c1) in zip(stops, stops[1:]):
            if p0 <= t <= p1:
                k = (t - p0) / max(p1 - p0, 1e-6)
                px[0, y] = _lerp_color(c0, c1, k)
                break
        else:
            px[0, y] = _as_rgb(stops[-1][1])
    return strip.resize((w, h))


def _fbm(w: int, h: int, rng: random.Random, octaves: int = 5, base: int = 4) -> Image.Image:
    """Fractal value noise in L mode (smooth, tileable-ish clouds)."""
    acc = Image.new("L", (w, h), 0)
    weight_sum = 0.0
    for o in range(octaves):
        gw = max(base * (2**o), 2)
        gh = max(int(gw * h / w), 2)
        cell = Image.new("L", (gw, gh))
        cell.putdata([rng.randrange(256) for _ in range(gw * gh)])
        cell = cell.resize((w, h), Image.Resampling.BICUBIC)
        weight = 0.5**o
        weight_sum += weight
        acc = ImageChops.add(acc, cell.point(lambda v, wt=weight: int(v * wt)))
    if weight_sum > 0:
        acc = acc.point(lambda v: min(255, int(v / weight_sum)))
    return acc


def _radial_glow(size: int, color: tuple[int, int, int], alpha: int) -> Image.Image:
    """Soft radial sprite (RGBA) for sun/moon/neon glows.

    The alpha mask is multiplied by a border fade that reaches 0 at the
    sprite edges — otherwise Gaussian blur clamps at the borders and leaves
    a hard rectangular edge when pasted.
    """
    n = 64
    ramp = Image.new("L", (n, 1))
    ramp.putdata(
        [int(255 * (1 - abs(2 * i / (n - 1) - 1)) ** 1.2) for i in range(n)]
    )
    fade = ImageChops.multiply(
        ramp.resize((n, n), Image.Resampling.BILINEAR),
        ramp.transpose(Image.Transpose.ROTATE_90).resize((n, n), Image.Resampling.BILINEAR),
    )
    mask = Image.new("L", (n, n), 0)
    d = ImageDraw.Draw(mask)
    d.ellipse([0, 0, n - 1, n - 1], fill=alpha)
    mask = ImageChops.multiply(mask, fade)
    mask = mask.resize((size, size), Image.Resampling.BICUBIC).filter(
        ImageFilter.GaussianBlur(radius=size / 7)
    )
    solid = Image.new("RGBA", (size, size), (*color, 255))
    solid.putalpha(mask)
    return solid


def _ridge(w: int, base_y: float, amp: float, rng: random.Random) -> list[float]:
    """Smooth 1-D mountain skyline (cosine-interpolated control points)."""
    n = max(w // 90, 6) + 3
    ctrl = [rng.uniform(-amp, amp) for _ in range(n)]
    ys: list[float] = []
    for x in range(w):
        t = x / w * (n - 1)
        i = int(t)
        i = min(i, n - 2)
        k = t - i
        s = (1 - math.cos(k * math.pi)) / 2
        ys.append(base_y + ctrl[i] * (1 - s) + ctrl[i + 1] * s)
    return ys


def _fill_below(img: Image.Image, xs: list[int], ys: list[float], color, offset: float = 0) -> None:
    pts = [(x, y + offset) for x, y in zip(xs, ys)]
    pts += [(xs[-1], img.height), (xs[0], img.height)]
    ImageDraw.Draw(img, "RGBA").polygon(pts, fill=color)


# ---------------------------------------------------------------------------
# Scenes
# ---------------------------------------------------------------------------


def _detect_features(prompt: str) -> set[str]:
    p = prompt.lower()
    feats: set[str] = set()
    for word, feat in {
        "night": "night",
        "dark": "night",
        "moon": "moon",
        "star": "stars",
        "sunset": "sunset",
        "dawn": "sunset",
        "sunrise": "sunset",
        "sun": "sun",
        "forest": "trees",
        "tree": "trees",
        "wood": "trees",
        "city": "city",
        "street": "city",
        "building": "city",
        "town": "city",
        "sea": "water",
        "ocean": "water",
        "water": "water",
        "lake": "water",
        "river": "water",
        "beach": "water",
        "island": "water",
        "snow": "snow",
        "cloud": "clouds",
        "fog": "fog",
        "mist": "fog",
    }.items():
        if word in p:
            feats.add(feat)
    return feats


def _draw_stars(img: Image.Image, rng: random.Random, n: int = 90) -> None:
    w, h = img.size
    d = ImageDraw.Draw(img, "RGBA")
    for _ in range(n):
        x, y = rng.randrange(w), rng.randrange(int(h * 0.55))
        r = rng.choice([1, 1, 1, 2])
        a = rng.randrange(120, 255)
        d.ellipse([x - r, y - r, x + r, y + r], fill=(255, 255, 255, a))


def _draw_tree(d: ImageDraw.ImageDraw, x: int, ground: int, scale: float, color) -> None:
    trunk_w = max(2, int(6 * scale))
    trunk_h = int(30 * scale)
    d.rectangle([x - trunk_w // 2, ground - trunk_h, x + trunk_w // 2, ground], fill=color)
    for i, s in enumerate((1.0, 0.75, 0.5)):
        cy = ground - trunk_h - int(i * 22 * scale)
        rw, rh = int(34 * scale * s), int(26 * scale * s)
        d.polygon(
            [(x, cy - rh), (x - rw, cy + rh * 0.6), (x + rw, cy + rh * 0.6)],
            fill=color,
        )


def _scene_landscape(
    img: Image.Image,
    rng: random.Random,
    feats: set[str],
    style: Style,
    pal: dict[str, str],
) -> None:
    """Sky + clouds + sun/moon + ridges (+ water or city)."""
    w, h = img.size
    horizon = int(h * rng.uniform(0.55, 0.68))

    night = "night" in feats or style == Style.cyberpunk
    sky = _vgrad(
        (w, horizon),
        [(0.0, pal["sky_top"]), (0.55, pal["sky_mid"]), (1.0, pal["sky_low"])],
    )
    img.paste(sky, (0, 0))

    # clouds (fbm lifted into the sky)
    if "clouds" in feats or ("fog" not in feats and not night):
        noise = _fbm(w, horizon, rng, octaves=5, base=3)
        noise = noise.point(lambda v: max(0, min(255, int((v - 96) * 2.1))))
        cloud_tint = Image.new("L", (w, horizon), 0)
        cloud_tint.paste(noise)
        tint_color = (255, 244, 230) if not night else (96, 110, 150)
        clouds = Image.new("RGB", (w, horizon), tint_color)
        img.paste(clouds, (0, 0), cloud_tint.point(lambda v: int(v * 0.75)))

    # sun / moon
    cx = int(w * rng.uniform(0.2, 0.8))
    cy = int(horizon * rng.uniform(0.35, 0.75))
    if "moon" in feats or (night and "sun" not in feats):
        disc_color = (232, 236, 245)
        disc_r = max(w // 40, 12)
    else:
        disc_color = pal.get("sun", "#ffd9a0")  # type: ignore[assignment]
        disc_color = _rgb(disc_color) if isinstance(disc_color, str) else disc_color
        disc_r = max(w // 26, 14)
    glow_r = disc_r * 6
    glow = _radial_glow(glow_r * 2, disc_color, 210)
    img.paste(glow, (cx - glow_r, cy - glow_r), glow)
    d = ImageDraw.Draw(img, "RGBA")
    d.ellipse([cx - disc_r, cy - disc_r, cx + disc_r, cy + disc_r], fill=(*disc_color, 245))
    if style == Style.cinematic:  # anamorphic flare
        flare = _radial_glow(int(glow_r * 2.6), _rgb(pal.get("sun", "#ffb066") if isinstance(pal.get("sun"), str) else "#ffb066"), 120)
        fw, fh = flare.size
        img.paste(flare.resize((fw, max(fh // 5, 8))), (cx - fw // 2, cy - fh // 10), flare.resize((fw, max(fh // 5, 8))))

    if "stars" in feats or night:
        _draw_stars(img, rng, n=140 if night else 60)

    # mountains: 3 ridge layers, far → near
    xs = list(range(w))
    far_c = _mix(_rgb(pal["mountain"]), (255, 255, 255), 0.35 if not night else 0.1)
    mid_c = _mix(_rgb(pal["mountain"]), (0, 0, 0), 0.25)
    near_c = _mix(_rgb(pal["mountain"]), (0, 0, 0), 0.55)
    for (layer_h, color, alpha) in (
        (h * 0.10, far_c, 200),
        (h * 0.14, mid_c, 230),
        (h * 0.18, near_c, 255),
    ):
        ys = _ridge(w, horizon - layer_h * 0.3, layer_h, rng)
        _fill_below(img, xs, ys, (*color, alpha))
        # ridge highlight
        dd = ImageDraw.Draw(img, "RGBA")
        dd.line(list(zip(xs, [int(y) for y in ys])), fill=(*_mix(color, (255, 255, 255), 0.3), 120), width=2)

    if "trees" in feats:
        ground = horizon + int(h * 0.02)
        tree_c = (14, 24, 18, 255) if not night else (6, 8, 16, 255)
        for _ in range(rng.randint(7, 12)):
            x = rng.randrange(w)
            _draw_tree(d, x, ground + rng.randint(0, int(h * 0.05)), rng.uniform(0.7, 1.6), tree_c)

    if "city" in feats:
        _city_skyline(img, rng, horizon, pal, night)

    if "water" in feats:
        _water_reflection(img, rng, horizon, pal, night)


def _city_skyline(img: Image.Image, rng: random.Random, horizon: int, pal: dict, night: bool) -> None:
    w, h = img.size
    d = ImageDraw.Draw(img, "RGBA")
    building = _rgb(pal["city"])
    neon_a = _rgb(pal["neon_a"])
    neon_b = _rgb(pal["neon_b"])
    x = -rng.randint(0, 40)
    while x < w:
        bw = rng.randint(max(w // 40, 18), max(w // 14, 46))
        bh = rng.randint(int(h * 0.10), int(h * 0.34))
        top = horizon - bh
        d.rectangle([x, top, x + bw, horizon + 4], fill=(*_shade(building, rng.uniform(0.7, 1.15)), 255))
        # windows
        win_c = neon_a if rng.random() < 0.6 else neon_b
        for wy in range(int(top + 8), horizon - 6, max(bh // 9, 10)):
            for wx in range(int(x + 5), x + bw - 5, max(bw // 5, 8)):
                if rng.random() < 0.45:
                    d.rectangle([wx, wy, wx + 4, wy + 5], fill=(*win_c, rng.randrange(140, 255)))
        x += bw + rng.randint(2, max(w // 60, 6))
    # neon horizon glow
    glow = _radial_glow(int(h * 0.5), neon_a, 130)
    img.paste(glow, (int(w / 2 - glow.width / 2), horizon - glow.height // 2), glow)


def _water_reflection(
    img: Image.Image, rng: random.Random, horizon: int, pal: dict, night: bool
) -> None:
    w, h = img.size
    depth = h - horizon
    if depth <= 8:
        return
    sky_part = img.crop((0, 0, w, horizon)).transpose(Image.Transpose.FLIP_TOP_BOTTOM)
    sky_part = sky_part.filter(ImageFilter.GaussianBlur(radius=max(w // 300, 1)))
    water = Image.new("RGBA", (w, depth), (0, 0, 0, 0))
    water.paste(sky_part.crop((0, 0, w, depth)), (0, 0))
    # darken with depth (gentle — keep the reflection readable)
    shade = Image.new("RGBA", (w, depth), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shade)
    for y in range(depth):
        a = int(35 + 120 * (y / max(depth - 1, 1)))
        sd.line([(0, y), (w, y)], fill=(0, 0, 0, a))
    water.alpha_composite(shade)
    water_tint = Image.new("RGBA", (w, depth), (*_rgb(pal["water"]), 55))
    water.alpha_composite(water_tint)
    img.paste(water, (0, horizon))
    # horizontal glints
    d = ImageDraw.Draw(img, "RGBA")
    glint = (255, 255, 255, 110) if not night else (200, 220, 255, 85)
    for _ in range(rng.randint(14, 22)):
        y = rng.randrange(horizon + 4, h)
        x0 = rng.randrange(0, w)
        ln = rng.randint(w // 30, w // 8)
        d.line([(x0, y), (min(x0 + ln, w), y)], fill=glint, width=rng.choice([1, 1, 2]))


def _scene_illustration(
    img: Image.Image, rng: random.Random, feats: set[str], pal: dict
) -> None:
    w, h = img.size
    noise = _fbm(w, h, rng, octaves=4, base=3).point(lambda v: int(v * 0.35))
    wash = Image.new("RGB", (w, h), pal["wash"])
    img.paste(wash, (0, 0), noise)
    d = ImageDraw.Draw(img, "RGBA")
    ink = _rgb(pal["ink"])
    accents = [_rgb(pal["a"]), _rgb(pal["b"]), _rgb(pal["c"])]
    # bold confetti shapes with outlines (kept above the text panel zone)
    for i in range(rng.randint(6, 9)):
        color = accents[i % len(accents)]
        cx = rng.randint(w // 8, w * 7 // 8)
        cy = rng.randint(h // 10, int(h * 0.66))
        r = rng.randint(min(w, h) // 18, min(w, h) // 7)
        alpha = rng.randrange(200, 245)
        kind = rng.random()
        if kind < 0.4:
            d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(*color, alpha), outline=(*ink, 255), width=max(3, w // 300))
        elif kind < 0.7:
            d.rounded_rectangle(
                [cx - r, cy - r * 7 // 10, cx + r, cy + r * 7 // 10],
                radius=r // 4,
                fill=(*color, alpha),
                outline=(*ink, 255),
                width=max(3, w // 300),
            )
        else:
            pts = [
                (cx, cy - r),
                (cx - r * 9 // 10, cy + r * 7 // 10),
                (cx + r * 9 // 10, cy + r * 7 // 10),
            ]
            d.polygon(pts, fill=(*color, alpha), outline=(*ink, 255))
    # doodle dots & arcs
    for _ in range(18):
        x, y = rng.randrange(w), rng.randrange(h)
        r = rng.randint(3, max(w // 120, 5))
        d.ellipse([x - r, y - r, x + r, y + r], fill=(*ink, rng.randrange(120, 220)))
    for _ in range(3):
        x, y = rng.randrange(w), rng.randrange(h // 3, h)
        rr = rng.randint(w // 10, w // 5)
        d.arc([x - rr, y - rr, x + rr, y + rr], start=rng.randrange(180), end=rng.randrange(190, 360), fill=(*ink, 180), width=max(3, w // 320))


def _scene_minimal(
    img: Image.Image, rng: random.Random, feats: set[str], pal: dict
) -> None:
    w, h = img.size
    # gentle paper noise
    noise = _fbm(w, h, rng, octaves=3, base=2).point(lambda v: int(v * 0.10))
    img.paste(Image.new("RGB", (w, h), pal["paper"]), (0, 0), noise)
    d = ImageDraw.Draw(img, "RGBA")
    accent = _rgb(pal["a"])
    ink = _rgb(pal["ink"])
    cx = int(w * rng.uniform(0.42, 0.58))
    cy = int(h * rng.uniform(0.36, 0.46))
    r = int(min(w, h) * rng.uniform(0.15, 0.21))
    # off-center focal: filled circle + thin ring + baseline
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(*accent, 255))
    ring = int(r * 1.45)
    d.ellipse([cx - ring, cy - ring, cx + ring, cy + ring], outline=(*ink, 90), width=max(2, w // 400))
    base_y = int(h * 0.84)
    d.line([(int(w * 0.12), base_y), (int(w * 0.88), base_y)], fill=(*ink, 60), width=max(2, w // 500))
    for i in range(3):
        bx = int(w * (0.16 + i * 0.05))
        d.rectangle([bx, base_y - rng.randint(10, 34), bx + max(w // 120, 6), base_y], fill=(*ink, 120))
    # small accent dot
    d.ellipse(
        [cx + ring + r // 3, cy - r, cx + ring + r // 3 + max(r // 6, 8), cy - r + max(r // 6, 8)],
        fill=(*_rgb(pal["b"]), 255),
    )


def _scene_cyberpunk(img: Image.Image, rng: random.Random, feats: set[str], pal: dict) -> None:
    w, h = img.size
    horizon = int(h * 0.60)
    sky = _vgrad((w, horizon), [(0.0, pal["sky_top"]), (0.7, pal["sky_mid"]), (1.0, pal["sky_low"])])
    img.paste(sky, (0, 0))
    _draw_stars(img, rng, n=60)
    # purple haze
    haze = _fbm(w, horizon, rng, octaves=4, base=3).point(lambda v: int(v * 0.4))
    img.paste(Image.new("RGB", (w, horizon), pal["haze"]), (0, 0), haze)
    _city_skyline(img, rng, horizon, pal, night=True)
    _water_reflection(img, rng, horizon, pal, night=True)

    # perspective neon grid on the bottom
    d = ImageDraw.Draw(img, "RGBA")
    neon = _rgb(pal["neon_a"])
    grid_top = horizon + (h - horizon) // 3
    for i in range(1, 9):
        y = grid_top + int((h - grid_top) * (i / 8) ** 1.6)
        d.line([(0, y), (w, y)], fill=(*neon, 90 + i * 12), width=max(1, h // 700))
    vx = w // 2
    for i in range(-7, 8):
        d.line([(vx + i * w // 7, h), (vx + i * w // 18, grid_top)], fill=(*neon, 70), width=max(1, h // 900))
    # neon beams
    for _ in range(rng.randint(2, 4)):
        x = rng.randrange(w)
        col = _rgb(pal["neon_b"]) if rng.random() < 0.5 else _rgb(pal["neon_a"])
        d.line([(x, horizon), (x, 0)], fill=(*col, 60), width=max(2, w // 250))
        glow = _radial_glow(max(w // 12, 24), col, 150)
        img.paste(glow, (x - glow.width // 2, int(horizon * 0.4) - glow.height // 2), glow)


def _scene_watercolor(
    img: Image.Image, rng: random.Random, feats: set[str], pal: dict
) -> None:
    w, h = img.size
    # paper with a soft top-to-bottom wash (no hard-edged overlay rects)
    paper_c = _rgb(pal["paper"])
    top_c = _mix(_rgb(pal["a"]), paper_c, 0.40)
    bottom_c = _mix(_rgb(pal["d"]), paper_c, 0.75)
    paper = _vgrad(
        (w, h), [(0.0, top_c), (0.45, paper_c), (1.0, bottom_c)]
    )
    grain = _fbm(w, h, rng, octaves=3, base=2).point(lambda v: int(v * 0.14))
    img.paste(paper, (0, 0), grain)
    d = ImageDraw.Draw(img, "RGBA")
    washes = [_rgb(pal["a"]), _rgb(pal["b"]), _rgb(pal["c"]), _rgb(pal["d"])]
    blur_r = max(min(w, h) // 70, 6)
    for i in range(rng.randint(6, 8)):
        color = washes[i % len(washes)]
        layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        ld = ImageDraw.Draw(layer)
        cx, cy = rng.randint(0, w), rng.randint(int(h * 0.15), h)
        rx, ry = rng.randint(w // 8, w // 3), rng.randint(h // 10, h // 4)
        # irregular blob from overlapping ellipses
        for _ in range(rng.randint(3, 5)):
            ox, oy = rng.randint(-rx // 2, rx // 2), rng.randint(-ry // 2, ry // 2)
            sx, sy = rng.randint(rx // 2, rx), rng.randint(ry // 2, ry)
            ld.ellipse(
                [cx + ox - sx, cy + oy - sy, cx + ox + sx, cy + oy + sy],
                fill=(*color, rng.randrange(80, 130)),
            )
        # darker pigment rim
        ld.ellipse(
            [cx - rx, cy - ry, cx + rx, cy + ry],
            outline=(*_shade(color, 0.72), 95),
            width=max(3, w // 220),
        )
        layer = layer.filter(ImageFilter.GaussianBlur(radius=blur_r))
        img.alpha_composite(layer)
    # occasional drips
    for _ in range(rng.randint(2, 4)):
        x = rng.randrange(w)
        y0 = rng.randrange(int(h * 0.3), int(h * 0.7))
        d = ImageDraw.Draw(img, "RGBA")
        d.line(
            [(x, y0), (x, y0 + rng.randint(int(h * 0.05), int(h * 0.15)))],
            fill=(*washes[rng.randrange(len(washes))], 110),
            width=max(3, w // 240),
        )
    # sparse pigment splatter dots
    for _ in range(rng.randint(8, 14)):
        x, y = rng.randrange(w), rng.randrange(h)
        r = rng.randint(max(w // 300, 3), max(w // 90, 6))
        d = ImageDraw.Draw(img, "RGBA")
        d.ellipse(
            [x - r, y - r, x + r, y + r],
            fill=(*washes[rng.randrange(len(washes))], rng.randrange(90, 150)),
        )


# ---------------------------------------------------------------------------
# Style palettes (scene parameters)
# ---------------------------------------------------------------------------

_SCENE_PAL: dict[Style, dict[str, str]] = {
    Style.photorealistic: {
        "sky_top": "#20304f", "sky_mid": "#e0764b", "sky_low": "#ffc978",
        "sun": "#ffd9a0", "mountain": "#233046", "water": "#2c4a63",
        "city": "#1a2136", "neon_a": "#ffb347", "neon_b": "#7fbfff",
    },
    Style.cinematic: {
        "sky_top": "#0b1c26", "sky_mid": "#d96c3f", "sky_low": "#f7b267",
        "sun": "#ffb066", "mountain": "#0a161d", "water": "#10313b",
        "city": "#0a1218", "neon_a": "#ff9a3c", "neon_b": "#39c0ba",
    },
    Style.illustration: {
        "wash": "#fff3dd", "ink": "#2b2118", "a": "#ff3f6c", "b": "#3b5bdb", "c": "#ffd93d",
        "sky_top": "#ffd9a0", "sky_mid": "#ff9a76", "sky_low": "#ffe9c9",
        "sun": "#ff8c42", "mountain": "#7c5cbf", "water": "#74c0fc",
        "city": "#3b3b98", "neon_a": "#ff3f6c", "neon_b": "#3b5bdb",
    },
    Style.minimal: {
        "paper": "#f6f6f8", "ink": "#18181b", "a": "#6366f1", "b": "#f59e0b",
        "sky_top": "#dfe3ff", "sky_mid": "#eef0ff", "sky_low": "#f6f6f8",
        "sun": "#c7d2fe", "mountain": "#cbd5e1", "water": "#e2e8f0",
        "city": "#94a3b8", "neon_a": "#6366f1", "neon_b": "#a5b4fc",
    },
    Style.cyberpunk: {
        "sky_top": "#07021a", "sky_mid": "#2a0a45", "sky_low": "#ff2a6d",
        "haze": "#3b0a5e", "sun": "#ff2a6d", "mountain": "#12051f",
        "water": "#0d0221", "city": "#07030f", "neon_a": "#ff2a6d", "neon_b": "#05d9e8",
    },
    Style.watercolor: {
        "paper": "#fbf7f0", "a": "#93c5fd", "b": "#f9a8d4", "c": "#98d4bb", "d": "#fde68a",
        "sky_top": "#cfe8f7", "sky_mid": "#f8e3ea", "sky_low": "#fbf7f0",
        "sun": "#fbcfe8", "mountain": "#a5b4c8", "water": "#bfdbfe",
        "city": "#94a3b8", "neon_a": "#93c5fd", "neon_b": "#f9a8d4",
    },
}


# ---------------------------------------------------------------------------
# Post-processing
# ---------------------------------------------------------------------------


def _vignette(img: Image.Image, strength: float = 0.35) -> Image.Image:
    w, h = img.size
    mask = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(mask)
    pad = int(min(w, h) * 0.06)
    d.ellipse([-pad, -pad, w + pad, h + pad], fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(radius=min(w, h) / 6))
    mask = mask.point(lambda v: int(255 - (255 - v) * strength))
    dark = Image.new("RGB", (w, h), (0, 0, 0))
    img.paste(Image.composite(img, dark, mask), (0, 0))
    return img


def _bloom(img: Image.Image, radius: float, amount: float) -> Image.Image:
    gray = img.convert("L").point(lambda v: max(0, (v - 165)) * 2)
    hi = Image.composite(img, Image.new("RGB", img.size, (0, 0, 0)), gray)
    hi = hi.filter(ImageFilter.GaussianBlur(radius=radius))
    return Image.blend(img, ImageChops.screen(img, hi), amount)


def _grain(img: Image.Image, rng: random.Random, amount: int = 10) -> Image.Image:
    noise = Image.effect_noise(img.size, amount).convert("L")
    noise = noise.point(lambda v: v - 128)
    overlay = Image.merge("RGB", (noise, noise, noise))
    return Image.blend(img, ImageChops.overlay(img, overlay), 0.35)


def _font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    """Best available font; falls back to Pillow's bundled default."""
    candidates = [
        "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
        "/Library/Fonts/Arial.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    ]
    for path in candidates:
        if Path(path).exists():
            try:
                return ImageFont.truetype(path, size)
            except OSError:
                continue
    try:
        return ImageFont.load_default(size=size)  # Pillow >= 10
    except TypeError:
        return ImageFont.load_default()


def _text_panel(
    img: Image.Image, prompt: str, style: Style, aspect: AspectRatio, quality: Quality
) -> None:
    w, h = img.size
    _, _, _, ink_hex = _STYLE_PALETTES[style]
    ink = _rgb(ink_hex)

    pad = max(w // 20, 24)
    title_size = max(w // 16, 18)
    body_size = max(w // 26, 14)
    meta_size = max(w // 40, 11)

    wrap_width = max(int(w / (body_size * 0.55)), 12)
    lines = textwrap.wrap(prompt, width=wrap_width)[:6]
    body_h = int(body_size * 1.35) * len(lines)
    panel_h = pad + meta_size + 14 + body_h + 18 + meta_size + pad
    panel_w = w - 2 * pad

    top = h - panel_h - pad

    # glass panel: blurred crop behind rounded rect
    region = img.crop((pad, top, pad + panel_w, top + panel_h)).filter(
        ImageFilter.GaussianBlur(radius=max(w // 200, 4))
    ).convert("RGBA")
    scrim = Image.new("RGBA", region.size, (0, 0, 0, 0))
    sc = ImageDraw.Draw(scrim)
    ink_dark = sum(ink) < 380  # dark text → light glass, light text → dark glass
    sc.rounded_rectangle(
        [0, 0, panel_w, panel_h],
        radius=max(w // 60, 12),
        fill=(255, 255, 255, 150) if ink_dark else (12, 12, 18, 140),
    )
    region.alpha_composite(scrim)
    img.paste(region, (pad, top))

    draw = ImageDraw.Draw(img, "RGBA")
    y = top + pad
    tag = _STYLE_TAGS[style]
    tag_font = _font(meta_size)
    tag_w = draw.textlength(tag, font=tag_font)
    pill_color = _lerp_color(*_STYLE_PALETTES[style][:2], 0.5)
    draw.rounded_rectangle(
        [pad, y - 2, pad + tag_w + meta_size, y + meta_size + 4],
        radius=meta_size // 2 + 2,
        fill=(*pill_color, 225),
    )
    draw.text((pad + meta_size // 2, y), tag, font=tag_font, fill=(255, 255, 255, 240))
    y += meta_size + 14

    body_font = _font(body_size)
    body_color = ink if ink_dark else (255, 255, 255, 235)
    for line in lines:
        draw.text((pad, y), line, font=body_font, fill=body_color)
        y += int(body_size * 1.35)

    y += 10
    meta = f"{aspect.value}  ·  {quality.value.upper()}  ·  style: {style.value}"
    meta_font = _font(meta_size)
    meta_color = (*ink, 200) if ink_dark else (255, 255, 255, 190)
    draw.text((pad, y), meta, font=meta_font, fill=meta_color)

    # top-left watermark
    logo_font = _font(max(w // 44, 12))
    logo = "MOCKDIFFUSION"
    logo_y = pad // 2
    d_size = max(meta_size, 10)
    cx, cy = pad + d_size // 2, logo_y + d_size // 2
    wm = (*ink, 220) if ink_dark else (255, 255, 255, 220)
    draw.polygon(
        [(cx, cy - d_size // 2), (cx + d_size // 2, cy), (cx, cy + d_size // 2), (cx - d_size // 2, cy)],
        fill=wm,
    )
    draw.text((pad + d_size + 6, logo_y), logo, font=logo_font, fill=(*wm[:3], 190))


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------


def render_image(
    prompt: str,
    style: Style,
    aspect_ratio: AspectRatio,
    quality: Quality,
    out_path: Path,
    nonce: str | None = None,
) -> Path:
    """Render an artwork PNG and write it to out_path.

    Scene and palette follow (prompt, style); `nonce` (job id) guarantees a
    fresh variation on every request instead of the same picture forever.
    """
    shape_w, shape_h = ASPECT_SHAPES[aspect_ratio]
    long_side = QUALITIES[quality]["long_side"]
    if shape_w >= shape_h:
        w = long_side
        h = max(1, round(long_side * shape_h / shape_w))
    else:
        h = long_side
        w = max(1, round(long_side * shape_w / shape_h))

    seed = _hash_seed(
        prompt, style.value, aspect_ratio.value, quality.value, nonce or ""
    )
    rng = random.Random(seed)
    feats = _detect_features(prompt)
    pal = dict(_SCENE_PAL[style])

    # Night shift for dark prompts (except styles that are already dark).
    if "night" in feats and style not in (Style.cyberpunk, Style.cinematic):
        pal["sky_top"] = "#0a1026"
        pal["sky_mid"] = "#1b2a55"
        pal["sky_low"] = "#3b4a7a"

    img = _vgrad((w, h), [(0.0, pal["sky_low"]), (1.0, pal["sky_low"])]).convert("RGBA")

    if style in (Style.photorealistic, Style.cinematic):
        _scene_landscape(img, rng, feats, style, pal)
    elif style == Style.cyberpunk:
        _scene_cyberpunk(img, rng, feats, pal)
    elif style == Style.illustration:
        _scene_illustration(img, rng, feats, pal)
    elif style == Style.minimal:
        _scene_minimal(img, rng, feats, pal)
    else:  # watercolor
        _scene_watercolor(img, rng, feats, pal)

    # global light sweep (keeps a bit of the old mock DNA)
    sweep = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    sd = ImageDraw.Draw(sweep)
    for i in range(-h, w, max(w // 12, 40)):
        sd.line([(i, h), (i + h, 0)], fill=(255, 255, 255, 7), width=max(w // 60, 6))
    sweep = sweep.filter(ImageFilter.GaussianBlur(radius=max(w // 150, 2)))
    img.alpha_composite(sweep)

    rgb = img.convert("RGB")
    light_style = style in (Style.minimal, Style.watercolor, Style.illustration)
    rgb = _bloom(rgb, radius=max(w // 180, 2), amount=0.12 if light_style else 0.30)
    if style in (Style.cinematic, Style.cyberpunk):
        vig = 0.40
    elif light_style:
        vig = 0.15
    else:
        vig = 0.26
    rgb = _vignette(rgb, strength=vig)
    rgb = _grain(rgb, rng, amount=6 if light_style else 9)

    final = rgb.convert("RGBA")
    _text_panel(final, prompt, style, aspect_ratio, quality)

    out_path.parent.mkdir(parents=True, exist_ok=True)
    final.convert("RGB").save(out_path, format="PNG", optimize=True)
    return out_path
