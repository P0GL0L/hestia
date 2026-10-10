# Rendering and other 3D tools

Hestia draws the house live in its own 3D view. For pictures that look like photographs, and for other 3D programs, it hands the house over as OpenUSD.

## Photo renders with Blender

**Render Photo** makes a still of the house from outside or from the living room.

1. Hestia exports the house as OpenUSD (`HouseUSD.swift`).
2. It runs Blender in the background with `tools/blender/hestia_render.py`.
3. The script replaces each flat color with a CC0 PBR material from Poly Haven, such as laminate, tile, plaster, roof tiles, lawn, paving, or marble.
4. It replaces the simple stand-in furniture and trees with CC0 Poly Haven models of the same size and place, and lights the scene with a real sky (HDRI), a sun, and a ceiling light in each room.
5. Cycles renders it, using the GPU through Metal on Apple silicon.

The picture is saved in `~/Hestia-exports` and opened.

- **Blender is a separate, free program.** Hestia does not include it or link to its code. It only starts Blender as a separate program, the way a terminal would.
- **Credit.** Materials, models, and sky come from [Poly Haven](https://polyhaven.com), CC0, through its public API. The app credits it beside Render Photo ("Powered by Poly Haven").
- **First-run download.** Before the first photo, the app says what it will fetch: about 120 MB from Poly Haven, kept in `~/Library/Caches/Hestia/assets`. Later photos reuse the cache and work offline.
- **Download safety.** The script fetches only over HTTPS from `api.polyhaven.com` and `dl.polyhaven.org`, and checks the host again after redirects. It streams each file under a byte ceiling, and keeps it only if it matches Poly Haven's declared size and MD5. A partial file is deleted, and a good one is moved into place in one step. Every cache path is checked to stay inside the cache, so absolute or `../` paths are refused. A cached file is checked again before it is reused. `tools/blender/test_hestia_render.py` covers the refusals.
- **Manifest.** Beside each picture, `<name>.manifest.json` records:
  - every asset file used, with its URL, declared size and MD5, and computed SHA-256;
  - the source and license;
  - the script version;
  - the Blender version.
- **Optional grass.** `--grass N` scatters real grass clumps on the lawn. It is off by default until the lawn material is tuned.
- **Stand-ins stay in place.** Items with no matching model (beds, kitchen and bath fixtures) keep their stand-in shape, with real materials.

Run it by hand:

```sh
blender -b --factory-startup --python tools/blender/hestia_render.py -- \
  --usd house.usda --out house.png --view exterior --samples 128 --size 1920x1080
```

## Other 3D programs

**Export USD** writes `<name>.usda`. It carries basic OpenUSD geometry and `UsdPreviewSurface` materials, which other OpenUSD programs can generally read.

What has been tested, and what has not:

- **Tested:** Blender 5.2 imports the export, including stages with hostile room names and catalog IDs. The render script above runs on it.
- **Not tested:** Maya, 3ds Max, Houdini, Arnold, and V-Ray. Nothing here claims their import works or that their renders match Blender's.

Each would need its own versioned check before Hestia claims support. Among them, 3ds Max runs only on Windows, and Arnold and V-Ray need their own licenses.

The file is laid out for that kind of work:

- **`/Hestia/Building`:** walls with trimmed doors and windows, stairs, roof, floors, and ceilings, one mesh per surface material.
- **`/Hestia/Site`:** the ground and the terrain patches.
- **`/Hestia/Items`:** one transform per placed item. Each carries `hestia:catalogItem`, so a pipeline can swap the stand-in for its own asset, as the Blender script does.
- **`/Hestia/Rooms`:** one marker per room at the middle of its ceiling, with name, floor size, and floor finish.
- **`/Hestia/Materials`:** one `UsdPreviewSurface` per surface look.
- **Sun and camera:** the stage also carries a sun and a camera.
- **Strings and names:** every string is escaped as a USDA literal. Prim names are ASCII identifiers made from the names in the model.

The stage is in feet (`metersPerUnit` 0.3048), y up.

## Next steps for the live view

The live 3D view uses SceneKit with flat colors, sun shadows, and simple shapes. Apple now keeps SceneKit in maintenance and points new 3D work to RealityKit. Planned:

- **RealityKit:** move the view to RealityKit, with image-based lighting from the same HDRI sky, grounding shadows, and tone mapping.
- **Live materials:** use the same CC0 PBR texture sets as the photo renders, cached locally.
- **Real models:** load the same models live (USDZ or glTF) in place of stand-ins, and let people import their own glTF, OBJ, and USDZ (Stream G).
- **More architectural detail:** baseboards, fascia and soffit, gutters, and a visible foundation.
