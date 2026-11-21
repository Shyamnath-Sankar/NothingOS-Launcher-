# Doto

Doto is the display and numeric accent typeface for the NothingUI design layer. It is used only for
display-sized text and numeric accents. Body, title and label text stays in the platform sans-serif
for legibility.

## Source

- Official catalogue: <https://fonts.google.com/specimen/Doto>
- Official repository path:
  <https://github.com/google/fonts/tree/7380f7cebbf2250460c23fd301b51bcbab162edf/ofl/doto>
- Source commit: `7380f7cebbf2250460c23fd301b51bcbab162edf` (2026-03-03)
- Upstream project: <https://github.com/oliverlalan/Doto>
- Upstream source commit from `METADATA.pb`: `1c587f2eed62cb257055540ac2a15f356070414f`
- Font version: `Version 1.000`
- Copyright: Copyright 2024-2024 The Doto Project Authors
  (<https://github.com/oliverlalan/Doto>)
- License: SIL Open Font License, Version 1.1. The verbatim license is in
  [`OFL-Doto.txt`](OFL-Doto.txt).

The downloaded file was the official variable font
`ofl/doto/Doto[ROND,wght].ttf` (SHA-256
`6f4fe7d37853b91df3698daa84cde2dbe1c9695d88c986e6510134910337d426`).

## Bundled instances

Android resources use two static instances generated from the official variable font with
`fontTools.varLib.instancer` (fontTools 4.68.0). The `ROND` axis is pinned at its default `0`; the
`wght` axis is pinned at `400` and `700`. Glyph outlines and the cmap are unchanged; only the
variable axes are removed and the name table is updated to the static names.

| Android resource | Axis instance | SHA-256 |
|---|---|---|
| `lawnchair/res/font/doto_regular.ttf` | `wght=400`, `ROND=0` | `45470421ac47f0e79c0f363c1229e864bffe7a09c8a1081806fbd47811afeb4a` |
| `lawnchair/res/font/doto_bold.ttf` | `wght=700`, `ROND=0` | `568e557c5916184d110e6f9394cb27fd2607b6bf6de7a1770a6fd6fe666f92f3` |

Both files are TrueType fonts (`00010000` sfnt header), not HTML or WOFF. No glyphs were added,
removed or redrawn, and no Nothing font or asset is included.
