# Rendering and other 3D tools

Hestia draws the house live in its own 3D view, finished from an asset library built ahead of time. For still pictures it renders with Blender, and for other 3D programs it hands the house over as OpenUSD.

## The live 3D view and the asset library

The live view is finished from an **asset library**: materials, furniture and planting models, and a sky, prepared once with Blender. While you draw, orbit, and walk, the view only places copies of what the library already holds, so nothing is modeled or converted while you work.

- **Building the library.** `tools/blender/hestia_library.py` reads the same tables as the photo renderer (textures, models, sky). It fetches the assets through the renderer's checked downloader, then writes the library folder:
  - `library.json`: what the library holds and how to use it.
  - `surfaces/`: diffuse, normal (OpenGL), and roughness maps for each surface material.
  - `models/`: one USDZ per model, y up, in meters, footprint centered on the origin, standing on y = 0, with its front toward +z.
  - `sky/sky.png`: the sky photo, tone-mapped and laid out as SceneKit reads an equirectangular image (north three quarters across, measured on Metal). The sun is found as the brightest point of the HDR photo, where it stands far above any cloud (a photo without such a peak is refused), and the sky is turned so the sun stands at a known bearing for the view's sun lamp.
  - `CREDITS.txt`: every asset comes from Poly Haven and is CC0, so the library can ship inside the app.
- **Ready for the live view.** Models are lightened to live-view triangle budgets: leaves and other parts are decimated separately, so a tree keeps every leaf at about an eighth of its triangles. Leaf textures with alpha are marked to draw cut out, never blended.
- **In the app.** `Apps/Hestia/build-app.sh` builds the library with Blender (`/Applications/Blender.app`, or `BLENDER`) when it is missing or its builder has changed, keeps it in `Apps/Hestia/build/Library`, and copies it into the app. `HESTIA_LIBRARY_SOURCE` names a library built elsewhere. The default library is about 80 MB. The build fails closed: with no Blender, no built library, and no `HESTIA_LIBRARY_SOURCE` it stops, and a named or cached library that fails its check stops it too. `HESTIA_ALLOW_FLAT=1` asks for a development build without a library, which draws in flat colors with simple shapes. `sh Apps/Hestia/test-build-app.sh` checks these rules without building.
- **What the view does with it** (`LiveLook.swift`):
  - **Materials:** every surface with a library material wears its photographed maps at their real size. Texture coordinates follow each face, so roof courses run along the eaves and tiles stay level (`SurfaceMapping.swift`).
  - **Models:** each placed item with a library model is drawn by that model, fitted to the item's footprint or height.
  - **Light:** the sky photo is the background and the image-based light, and the sun lamp stands where the photo's sun is.
  - **Camera:** high dynamic range, ambient occlusion, and a light vignette.
  - **Walking inside:** the sky light is turned down and each room gets a warm ceiling light, since image-based light reaches through walls. The camera then meters its exposure as a photographer would: it draws a small picture of what it sees and moves the exposure until the picture's mean brightness is near the middle. Starting a walk resets the exposure to the same start and meters fully, so nothing is carried in from an earlier walk; walking on meters a gentle step every half second, so the exposure eases from room to room. No fixed exposure suits every house and every Mac's GPU.
- **Your own libraries.** The format is open: a folder with `library.json` and USDZ models, which Blender writes directly and Maya and 3ds Max write through their USD exporters. Loading a person's own library beside the default one is planned. Paths in a library must stay inside its folder, and links that lead out are refused.
- **Checking a library.** `python3 tools/blender/check_library.py <folder>` fails unless:
  - `library.json` is a regular file, and the library is complete, not a partial build;
  - every look and catalog item maps to the very asset, tile, fit, turn, and file the renderer's tables name for it, maps carry their canonical names, and every model's size is one a real piece could be (1 cm to 50 m);
  - the sky is the renderer's photo, laid out for SceneKit, its sun at the builder's bearing and above the horizon;
  - its provenance is whole: Poly Haven as source, CC0 as license, the builder's version, every asset it uses credited with its download URL, size, and SHA-256, and every file it holds (CREDITS.txt included) recorded with its size and SHA-256, matching what is on disk. `build-app.sh` runs it on whatever library it is about to package.
- **Checking the look.** With a built library on a Mac:

  ```sh
  HESTIA_LIBRARY=Apps/Hestia/build/Library HESTIA_SNAPSHOT_DIR=/tmp/hestia-snapshots \
    swift test --filter LiveViewSnapshotTests
  ```

  This writes stills of the sample house from outside, at the street, in the garden, toward the sun, and inside.

## Photo renders with Blender

**Render Photo** makes a still of the house from outside or from the largest room.

1. Hestia exports the house as OpenUSD (`HouseUSD.swift`).
2. It runs Blender in the background with `tools/blender/hestia_render.py`.
3. The script replaces each flat color with a CC0 PBR material from Poly Haven, such as laminate, tile, plaster, roof tiles, lawn, paving, or marble.
4. It replaces the simple stand-in furniture and trees with CC0 Poly Haven models of the same size and place, and lights the scene with a real sky (HDRI), a sun, and a ceiling light in each room.
5. The pictures are composed as an architectural photographer would. The camera is held level, so walls stay vertical, and it is set at eye height.
   - **Outside:** it tries three front viewpoints (south-east, south-west, and south) and takes the one with the fewest tall placed items, such as cars and trees, between it and the house. It does not search for the clearest view overall.
   - **Inside:** it stands in a corner of the largest room and looks toward that room's windows.
   - **Light:** when the sky photo (HDRI) loads, the renderer estimates its sun from the brightest point and turns the sky so that estimate matches the sun lamp. If it cannot be loaded, the scene falls back to a plain blue sky.
   - **Building detail:** the roof gets thickness at the eaves and the walls and roof get bevelled edges. Framing uses the house's size after this detail is added.
   - **Trees:** a seeded ring of trees stands around the building, 32 to 70 m from its middle. On a large lot they can stand inside it.
6. Cycles renders it on the GPU through Metal when Blender finds a Metal device, and on the CPU otherwise.

The picture is saved in `~/Hestia-exports` and opened.

- **Blender is a separate, free program.** Hestia does not include it or link to its code. It only starts Blender as a separate program, the way a terminal would.
- **Credit.** Materials, models, and sky come from [Poly Haven](https://polyhaven.com), CC0, through its public API. The app credits it beside Render Photo ("Powered by Poly Haven").
- **First-run download.** Before the first photo, the app says what it will fetch: about 120 MB from Poly Haven, kept in `~/Library/Caches/Hestia/assets`. Later photos reuse the cache and work offline.
- **Download safety.**
  - **Hosts:** the script fetches only over HTTPS from `api.polyhaven.com` and `dl.polyhaven.org`. Each redirect is checked before it is followed, and the final address is checked again.
  - **Partial files:** each file streams under a byte ceiling into a new, uniquely named partial file, created exclusively, so a planted link or a second render is never written through.
  - **Verification:** a file is moved into place in one step only if it matches the size and MD5 that Poly Haven declares. Asset entries without a declared size and MD5 are refused, and partial files are always removed.
  - **Cache paths:** every cache path must stay inside the cache, so absolute paths, `../` and symlinks that lead out are refused. A cached file is checked again before reuse.
  - **Tests:** `blender -b --factory-startup --python-exit-code 1 --python tools/blender/test_hestia_render.py` runs these checks offline.
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

The live view uses SceneKit, which Apple now keeps in maintenance; RealityKit is its successor. Planned:

- **Doors and windows from the library:** door and window styles (panel and glass doors, casement and double-hung windows) as library pieces that stretch to each opening.
- **Your own libraries:** load a person's library beside the default one, and add a model (USDZ, glTF, FBX) to it from the app.
- **Photos from the library:** have Render Photo place the same library models, so photos and the live view match exactly.
- **RealityKit:** move the view to RealityKit when SceneKit's maintenance status starts to cost features.
- **More architectural detail:** baseboards, fascia and soffit, gutters, and a visible foundation.
