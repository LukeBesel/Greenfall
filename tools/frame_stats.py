#!/usr/bin/env python3
"""Frame statistics for look work (art overhaul). Usage: tools/frame_stats.py IMG [IMG...]
Per image: mean luminance, share of crushed (<4/255) and clipped (>250/255) pixels, mean saturation,
and the mean luminance of three bands (sky = top fifth, far = the band round the horizon line,
ground = bottom third). Luminance is Rec.709 on the 8-bit values (display-referred)."""
import sys
import numpy as np
from PIL import Image


def stats(path):
    a = np.asarray(Image.open(path).convert("RGB"), dtype=np.float32)
    lum = a @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)
    mx, mn = a.max(axis=2), a.min(axis=2)
    sat = np.where(mx > 1, (mx - mn) / np.maximum(mx, 1), 0)
    h = lum.shape[0]
    return {
        "mean": lum.mean(), "crushed": (lum < 4).mean() * 100, "clipped": (mx > 250).mean() * 100,
        "sat": sat.mean(), "sky": lum[: h // 5].mean(), "far": lum[int(h * 0.3): int(h * 0.45)].mean(),
        "ground": lum[h * 2 // 3:].mean(), "p5": np.percentile(lum, 5), "p95": np.percentile(lum, 95),
    }


if __name__ == "__main__":
    print("%-44s %6s %6s %6s %8s %8s %5s %6s %6s %6s" % ("image", "mean", "p5", "p95", "crush%", "clip%", "sat", "sky", "far", "ground"))
    for p in sys.argv[1:]:
        s = stats(p)
        print("%-44s %6.1f %6.1f %6.1f %8.2f %8.2f %5.2f %6.1f %6.1f %6.1f" % (p[-44:], s["mean"], s["p5"], s["p95"], s["crushed"], s["clipped"], s["sat"], s["sky"], s["far"], s["ground"]))
