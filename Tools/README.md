# Tools

## App icon

`AppIcon-source.png` is the master artwork for the Top Drawer app icon — a
photorealistic wooden chest with the top drawer pulled open, revealing glowing
app tiles (1024×1024, full-bleed, square corners).

The shipped `AppIcon.appiconset` slots are derived from it: the artwork is
scaled to an 824×824 rounded-corner squircle (corner radius 22.37%), centered
on a transparent 1024×1024 canvas per the Big Sur+ icon grid, then downsampled
to every slot size. To regenerate, e.g. with Python/Pillow:

```python
from PIL import Image, ImageDraw
src = Image.open("Tools/AppIcon-source.png").convert("RGBA")
CANVAS, ART = 1024, 824
art = src.resize((ART, ART), Image.LANCZOS)
SS = 4
mask = Image.new("L", (ART*SS, ART*SS), 0)
ImageDraw.Draw(mask).rounded_rectangle([0, 0, ART*SS-1, ART*SS-1], radius=round(ART*0.2237)*SS, fill=255)
art.putalpha(mask.resize((ART, ART), Image.LANCZOS))
master = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
master.paste(art, ((CANVAS-ART)//2, (CANVAS-ART)//2), art)
for px, name in [(16, "icon_16x16"), (32, "icon_16x16@2x"), (32, "icon_32x32"),
                 (64, "icon_32x32@2x"), (128, "icon_128x128"), (256, "icon_128x128@2x"),
                 (256, "icon_256x256"), (512, "icon_256x256@2x"), (512, "icon_512x512"),
                 (1024, "icon_512x512@2x")]:
    out = master if px == CANVAS else master.resize((px, px), Image.LANCZOS)
    out.save(f"MacDring/Resources/Assets.xcassets/AppIcon.appiconset/{name}.png")
```

The previous programmatic generator (`GenerateAppIcon.swift`, which drew the
old gradient-squircle MacDring icon) was removed when the artwork-based icon
landed — regenerating with it would overwrite this icon.
