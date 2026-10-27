# Bundled LUTs

Files here are copied into the app. Name them after the preset id and slot:

| File | Used for |
|---|---|
| `preset-1.cube` / `preset-1.lut` | photos and the photo viewfinder |
| `preset-1.video.cube` / `.lut` | Rec.709 video (falls back to the photo LUT) |
| `preset-1.applelog.cube` / `.lut` | Apple Log video (no fallback) |

`preset-1` and `preset-2` are the JaneSu presets. Their photo LUT is the JaneSu 709 LUT with the neutral tone curve of the Helios photo LUT applied first (see `swift run luttool compose`). LUTs imported inside the app take priority over these.
