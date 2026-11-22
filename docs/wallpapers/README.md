# Offline AMOLED wallpapers

These two resources are committed and used entirely offline. The app never
fetches wallpaper data at runtime.

## Pitch Black (PNG)

- Asset: `lawnchair/res/drawable-nodpi/dotwel_wallpaper_pitch_black.png`
- Original: `pitch-black-wallpaper-fhd-mobile-1080x1920-1bit.png`
- Source: https://github.com/tecdrop/pitch-black-wallpaper-images
  at commit `f3b0910b687bf01d6cd6c5f965b398508db05c04`
- Direct URL:
  https://raw.githubusercontent.com/tecdrop/pitch-black-wallpaper-images/f3b0910b687bf01d6cd6c5f965b398508db05c04/pitch-black-wallpaper-fhd-mobile-1080x1920-1bit.png
- Original size: 348 bytes, 1080 x 1920, 1-bit black.
- Original SHA-256:
  `d0e03819a6d71672180c5c15d2e3d09c7982ebee448f9599acb6a2ee0585181d`
- Copyright (c) 2024 Tecdrop. Licensed under CC BY 4.0:
  https://creativecommons.org/licenses/by/4.0/
- Change notice: the file was renamed to `dotwel_wallpaper_pitch_black.png`
  only. Its bytes and pixels are unchanged.

## Wireframe Torus (SVG -> Android vector)

- Editable source: `docs/wallpapers/wireframe-torus-source.svg`
- Recolored source: `docs/wallpapers/wireframe-torus-recolored.svg`
- Android resource:
  `lawnchair/res/drawable-nodpi/dotwel_wallpaper_wireframe_torus.xml`
- Source: https://walldye.com/t/db0311a07de8.svg
- Artwork page: https://walldye.com/torus-wireframe
- Metadata:
  https://github.com/nickolaj-jepsen/walldye/blob/main/wallpapers/torus-wireframe/meta.yaml
- Policy:
  https://github.com/nickolaj-jepsen/walldye/blob/main/docs/wallpapers.md
- Source size: 46,935 bytes, viewport 1080 x 2340.
- Source SHA-256:
  `db0311a07de8087eba6bfc7afc18d29fc5f239b265fb8f125a7b53058fd074f0`
- License: CC0 1.0 Universal:
  https://creativecommons.org/publicdomain/zero/1.0/
- Provenance: a model-made, non-recreation, non-franchise static output.
  No GPL generator, site or tool code was copied.

Inspected source structure: only `svg`, `rect` and `path` elements; three
plain paths using `M`/`L` commands; literal colours; no script, links,
transforms or external data.

Recolour mapping (literal source colours only):

| Source | Replacement |
| --- | --- |
| `#1C1B1A` | `#000000` |
| `#343331` | `#171717` |
| `#403E3C` | `#222222` |
| `#CF6A4C` | `#D7261E` |

Recolored SVG SHA-256 (bytes otherwise preserved):
`cd1c1671c5ad0b7923f70dbae020fb84697a7f2f469e2196576c69545f5612d1`

The Android vector keeps the same 1080 x 2340 viewport, the rectangle
geometry, every `pathData` string, the literal stroke widths (1.2, 1.6 and
3), the source round caps (the 1.6 and 3 width paths) and no fill on
stroked paths. This is a static output-format conversion, not generator
reuse.
