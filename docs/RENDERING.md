# Rendering and other 3D tools

Hestia draws the house live in its own 3D view. For pictures that look like photographs, and for work in professional 3D tools, it hands the house to other programs through OpenUSD.

## Photo renders with Blender

**Render Photo** makes a still of the house from outside or from the living room.

1. Hestia exports the house as OpenUSD (`HouseUSD.swift`).
2. It runs Blender in the background with `tools/blender/hestia_render.py`.
3. The script replaces each flat color with a CC0 PBR material from Poly Haven, such as laminate, tile, plaster, roof tiles, lawn, paving, or marble.
4. It replaces the simple stand-in furniture and trees with CC0 Poly Haven models of the same size and place, and lights the scene with a real sky (HDRI), a sun, and a ceiling light in each room.
5. Cycles renders it, using the GPU through Metal on Apple silicon.

The picture is saved in `~/Hestia-exports` and opened.

- **Blender is a separate, free program.** Hestia does not include it or link to its code. It only starts Blender as a separate program, the way a terminal would.
- **Downloads are cached.** The first render downloads materials and models into `~/Library/Caches/Hestia/assets`; later renders work offline.
- **Optional grass.** `--grass N` scatters real grass clumps on the lawn. It is off by default until the lawn material is tuned.
- **Stand-ins stay in place.** Items with no matching model (beds, kitchen and bath fixtures) keep their stand-in shape, with real materials.

Run it by hand:

```sh
blender -b --factory-startup --python tools/blender/hestia_render.py -- \
  --usd house.usda --out house.png --view exterior --samples 128 --size 1920x1080
```

## Maya, 3ds Max, Houdini, Arnold, V-Ray

**Export USD** writes `<name>.usda`. All of these open USD: Maya through USD for Maya, 3ds Max through its USD plug-in, Houdini through Solaris, and Blender. Their renderers then render it: Arnold, V-Ray, RenderMan, or Karma.

The file is laid out for that work:

- **`/Hestia/Building`:** walls with trimmed doors and windows, stairs, roof, floors, and ceilings, one mesh per surface material.
- **`/Hestia/Site`:** the ground and the terrain patches (lot, lawn, driveway, paths, patio, deck, pond).
- **`/Hestia/Items`:** one transform per placed item. Each carries `hestia:catalogItem`, so a pipeline can swap the stand-in for its own finished asset. This is the same swap the Blender script makes.
- **`/Hestia/Rooms`:** one marker per room at the middle of its ceiling, with name, floor size, and floor finish.
- **`/Hestia/Materials`:** one `UsdPreviewSurface` per surface look, named so look-dev can replace it with MaterialX, OpenPBR, or Arnold and V-Ray shaders.
- **Sun and camera:** the stage also carries a sun and a camera.

The stage is in feet (`metersPerUnit` 0.3048), y up.

### Platforms and licenses

- **3ds Max** runs only on Windows.
- **Maya** runs on macOS 13 and later and on Windows and Linux.
- **Arnold and V-Ray** are commercial and need their own licenses.
- **Hestia needs none of these.** They are destinations for the USD file, not dependencies.

## Next steps for the live view

The live 3D view uses SceneKit with flat colors, sun shadows, and simple shapes. Apple now keeps SceneKit in maintenance and points new 3D work to RealityKit. Planned:

- **RealityKit:** move the view to RealityKit, with image-based lighting from the same HDRI sky, grounding shadows, and tone mapping.
- **Live materials:** use the same CC0 PBR texture sets as the photo renders, cached locally.
- **Real models:** load the same models live (USDZ or glTF) in place of stand-ins, and let people import their own glTF, OBJ, and USDZ (Stream G).
- **More architectural detail:** baseboards, fascia and soffit, gutters, and a visible foundation.
