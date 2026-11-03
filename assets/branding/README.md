# Brand assets

| File | Description |
|---|---|
| `original/EazyClinic Caring Healthcare Logo.png` | **Approved logo, untouched** (1536×1024 PNG, white background). Never edit or overwrite. |
| `eazyclinic_logo.png` | App-ready full logo: the original scaled uniformly to 960×640 (`sips -Z 960`). Aspect ratio preserved. |
| `eazyclinic_icon.png` | Icon-only variant: a 640×560 crop of the original's symbol (`sips -c 560 640 --cropOffset 40 430`). No redrawing. |

Derived from the original with macOS `sips` only (resize and crop). No
recolouring, redrawing or re-vectorizing was done.

Used for: in-app logo (`EcBrandLogo`), web favicons/PWA icons (icon variant
centred on a white square), Android launcher icons (same square, resized to
48/72/96/144/192 px).

Limitations (see docs/TECHNICAL_DEBT.md): the original has an opaque white
background and is raster-only. A transparent or vector master is needed for
dark backgrounds, adaptive Android icons and print.

`packages/design_system/assets/` holds copies bundled with the Flutter package;
run `scripts/sync_brand_assets.sh` after changes.
