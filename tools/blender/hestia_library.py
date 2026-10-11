# Builds Hestia's asset library: the finished materials, models, and sky that the live 3D view places, made
# once ahead of time so the app never models or converts anything while you work. Run with Blender:
#
#   blender -b --factory-startup --python-exit-code 1 --python tools/blender/hestia_library.py -- --out DIR
#
# It reads the same tables as the photo renderer (hestia_render.py: TEXTURES, MODELS, PAINT, TINTS, HDRI), so the
# live view and the photos use the same assets, and fetches them through the renderer's checked downloader into
# the same cache. Into DIR it writes:
#
#   library.json         what is in the library and how to use it (format below)
#   surfaces/<asset>/    diffuse.jpg, normal.jpg (OpenGL), rough.jpg for each surface material
#   models/<asset>.usdz  each model, y up, its footprint centered on the origin, standing on y = 0, in meters,
#                        its front toward +z (the same as Hestia's view space, where plan south is +z)
#   sky/sky.png          the sky photo, tone-mapped to 8 bits, laid out as SceneKit reads an equirectangular image
#                        and turned so its sun stands at SUN_AZIMUTH (see build_sky)
#   CREDITS.txt          where everything came from: Poly Haven, CC0
#
# Every asset is CC0 (https://polyhaven.com/license), so the library can ship inside the app.

import argparse
import json
import math
import os
import shutil
import sys
import tempfile

import bpy
import mathutils

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
SOURCE = open(os.path.join(HERE, "hestia_render.py")).read().replace("\nmain()\n", "\n")
shared = {"__name__": "hestia_render"}
exec(compile(SOURCE, "hestia_render.py", "exec"), shared)

LIBRARY_VERSION = 1
# Where the sky's sun stands, clockwise from north, after the sky is turned: the south-south-east, so the front
# of a house facing south is in sunlight.
SUN_AZIMUTH = 150.0
SKY_SIZE = (2048, 1024)


def arguments():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", required=True)
    parser.add_argument("--cache", default=os.path.expanduser("~/Library/Caches/Hestia/assets"))
    parser.add_argument("--only", nargs="*", help="build only these Poly Haven assets (for checking)")
    return parser.parse_args(argv)


def wanted(asset, args):
    return not args.only or asset in args.only


# MARK: - Surfaces


def build_surfaces(args, out):
    """Each surface look's texture maps, copied once per Poly Haven asset, with its tile size, paint, and
    tint."""
    surfaces = {}
    copied = {}
    for look, (asset, tile) in sorted(shared["TEXTURES"].items()):
        if not wanted(asset, args):
            continue
        if asset not in copied:
            maps = shared["texture_maps"](asset, args.cache)
            folder = os.path.join(out, "surfaces", asset)
            os.makedirs(folder, exist_ok=True)
            names = {}
            for kind, path in sorted(maps.items()):
                name = {"diffuse": "diffuse", "normal": "normal", "rough": "rough"}[kind] + ".jpg"
                shutil.copyfile(path, os.path.join(folder, name))
                names[kind] = "surfaces/%s/%s" % (asset, name)
            copied[asset] = names
        entry = {"asset": asset, "tile": tile, "maps": copied[asset]}
        paint = shared["PAINT"].get(look)
        if paint:
            entry["paint"] = list(paint)
        tint = shared["TINTS"].get(asset)
        if tint:
            entry["tint"] = list(tint)
        surfaces[look] = entry
    return surfaces


# MARK: - Models


def empty_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


# Triangle budgets for the live view, per model: one for leaves and one for everything else. Both are reached by
# decimating, which keeps every leaf (a Poly Haven tree has tens of thousands, each a small curved mesh) but
# with fewer triangles, so the canopy stays as full as the original's.
LEAF_BUDGET = 130_000
SOLID_BUDGET = 60_000


def foliage_materials(gltf_path):
    """Leaf materials (glTF alphaMode MASK or BLEND), with whether their color texture can carry the alpha that
    cuts out their shape, and its cutoff. Poly Haven's 1k models use JPEG, which has no alpha: their leaves are
    modeled in shape, so they are drawn solid. A PNG leaf texture is drawn cut out, never blended, so leaves
    sort correctly in the live view."""
    with open(gltf_path) as handle:
        document = json.load(handle)
    images, textures = document.get("images", []), document.get("textures", [])
    found = {}
    for material in document.get("materials", []):
        if material.get("alphaMode") not in ("MASK", "BLEND"):
            continue
        texture = material.get("pbrMetallicRoughness", {}).get("baseColorTexture", {}).get("index")
        uri = ""
        if isinstance(texture, int) and 0 <= texture < len(textures):
            source = textures[texture].get("source")
            if isinstance(source, int) and 0 <= source < len(images):
                uri = images[source].get("uri", "")
        cutout = uri.lower().endswith(".png")
        found[material.get("name", "")] = material.get("alphaCutoff", 0.5) if cutout else None
    return found


def split_by_material(obj):
    """One object per material, so leaves and solid parts can be lightened differently."""
    import bmesh

    used = sorted({polygon.material_index for polygon in obj.data.polygons})
    if len(used) < 2:
        return [obj]
    parts = []
    for index in used:
        part = obj.copy()
        part.data = obj.data.copy()
        bpy.context.scene.collection.objects.link(part)
        mesh = bmesh.new()
        mesh.from_mesh(part.data)
        bmesh.ops.delete(mesh, geom=[face for face in mesh.faces if face.material_index != index], context="FACES")
        for face in mesh.faces:
            face.material_index = 0
        mesh.to_mesh(part.data)
        mesh.free()
        # One slot holding the part's own material: the USD exporter binds a mesh with one material to its first
        # slot, whichever slot its faces name.
        material = part.data.materials[index]
        part.data.materials.clear()
        part.data.materials.append(material)
        parts.append(part)
    bpy.data.objects.remove(obj)
    return parts


def decimate(obj, budget):
    """Collapses a solid part's triangles down to its budget."""
    triangles = len(obj.data.polygons)
    if triangles <= budget:
        return
    modifier = obj.modifiers.new("Live", "DECIMATE")
    modifier.ratio = budget / triangles
    depsgraph = bpy.context.evaluated_depsgraph_get()
    lighter = bpy.data.meshes.new_from_object(obj.evaluated_get(depsgraph))
    obj.modifiers.remove(modifier)
    old = obj.data
    obj.data = lighter
    bpy.data.meshes.remove(old)


def lighten(foliage):
    """Brings the open scene within the live view's triangle budgets, sharing each budget across the parts it
    covers by their size."""
    parts = []
    for obj in [obj for obj in bpy.data.objects if obj.type == "MESH"]:
        parts += split_by_material(obj)
    def material(part):
        slots = part.data.materials
        return slots[0].name if len(slots) and slots[0] else ""

    leaves = [part for part in parts if material(part) in foliage]
    solids = [part for part in parts if part not in leaves]
    for group, budget in ((leaves, LEAF_BUDGET), (solids, SOLID_BUDGET)):
        total = sum(len(part.data.polygons) for part in group)
        for part in group:
            decimate(part, max(int(budget * len(part.data.polygons) / max(total, 1)), 200))
    return sum(len(obj.data.polygons) for obj in bpy.data.objects if obj.type == "MESH")


def normalized_model(asset, cache):
    """Imports a model into an empty scene and moves it so its footprint is centered on the origin and it
    stands on z = 0. Returns its size in meters (x, y, z, Blender's z up) and its cut-out materials."""
    empty_scene()
    path = shared["model_file"](asset, cache)
    bpy.ops.import_scene.gltf(filepath=path)
    meshes = [obj for obj in bpy.data.objects if obj.type == "MESH"]
    if not meshes:
        raise RuntimeError("no meshes in %s" % asset)
    bpy.context.view_layer.update()
    low = mathutils.Vector((1e9, 1e9, 1e9))
    high = -low
    for obj in meshes:
        for corner in obj.bound_box:
            point = obj.matrix_world @ mathutils.Vector(corner)
            low = mathutils.Vector(map(min, low, point))
            high = mathutils.Vector(map(max, high, point))
    shift = mathutils.Matrix.Translation((-(low.x + high.x) / 2, -(low.y + high.y) / 2, -low.z))
    for obj in [obj for obj in bpy.data.objects if obj.parent is None]:
        obj.matrix_world = shift @ obj.matrix_world
    bpy.context.view_layer.update()
    foliage = foliage_materials(path)
    triangles = lighten(foliage)
    print("Hestia library:", asset, triangles, "triangles")
    return high - low, {name: cutoff for name, cutoff in foliage.items() if cutoff is not None}


def export_usdz(path):
    """The open scene as USDZ: y up with the front toward +z, UsdPreviewSurface materials, and its textures
    packed in at no more than 1024 pixels."""
    bpy.ops.wm.usd_export(
        filepath=path,
        selected_objects_only=False,
        export_animation=False,
        export_materials=True,
        generate_preview_surface=True,
        export_lights=False,
        export_cameras=False,
        convert_orientation=True,
        export_global_forward_selection="NEGATIVE_Z",
        export_global_up_selection="Y",
        usdz_downscale_size="1024",
        root_prim_path="/model",
        triangulate_meshes=True,
    )


def mark_cutouts(usd_path, masks):
    """Gives each cut-out material its threshold and wires its opacity to its color texture's alpha, so leaves
    show their shape and not their card. Returns how many materials it marked."""
    from pxr import Sdf, Usd, UsdShade

    stage = Usd.Stage.Open(usd_path)
    marked = 0
    for prim in stage.Traverse():
        if not prim.IsA(UsdShade.Material):
            continue
        cutoff = next((value for name, value in masks.items()
                       if name and (prim.GetName() == name or prim.GetName() == shared["asset_name"](name)
                                    or prim.GetName().replace("_", "") == name.replace(" ", "").replace("_", ""))),
                      None)
        if cutoff is None:
            continue
        for child in Usd.PrimRange(prim):
            shader = UsdShade.Shader(child)
            if not shader or shader.GetIdAttr().Get() != "UsdPreviewSurface":
                continue
            shader.CreateInput("opacityThreshold", Sdf.ValueTypeNames.Float).Set(float(cutoff))
            color = shader.GetInput("diffuseColor")
            sources = color.GetConnectedSources()[0] if color else []
            if sources:
                texture = UsdShade.Shader(sources[0].source.GetPrim())
                alpha = texture.CreateOutput("a", Sdf.ValueTypeNames.Float)
                shader.CreateInput("opacity", Sdf.ValueTypeNames.Float).ConnectToSource(alpha)
            marked += 1
    stage.Save()
    return marked


def build_models(args, out):
    """Each Poly Haven model the catalog uses, once, as USDZ; and each catalog item's entry pointing at it."""
    from pxr import UsdUtils

    folder = os.path.join(out, "models")
    os.makedirs(folder, exist_ok=True)
    built = {}
    failed = []
    for asset in sorted({choice[0] for choice in shared["MODELS"].values()}):
        if not wanted(asset, args):
            continue
        try:
            size, masks = normalized_model(asset, args.cache)
            work = tempfile.mkdtemp()
            try:
                plain = os.path.join(work, asset + ".usdc")
                export_usdz(plain)
                cutouts = mark_cutouts(plain, masks) if masks else 0
                target = os.path.join(folder, asset + ".usdz")
                if os.path.exists(target):
                    os.remove(target)
                if not UsdUtils.CreateNewUsdzPackage(plain, target):
                    raise RuntimeError("could not package %s" % asset)
            finally:
                shutil.rmtree(work, ignore_errors=True)
            # Blender's z up becomes y up and its -y (the model's front) becomes +z.
            built[asset] = {"file": "models/%s.usdz" % asset, "size": [round(size.x, 4), round(size.z, 4),
                                                                          round(size.y, 4)],
                            "cutout": cutouts > 0}
            print("Hestia library: model", asset, built[asset])
        except Exception as error:
            print("Hestia library: could not build model", asset, error)
            failed.append("%s (%s)" % (asset, error))
    if failed:
        raise LibraryError(["models that did not build: " + ", ".join(failed)])
    items = {}
    for item, (asset, fit, turn) in sorted(shared["MODELS"].items()):
        if asset in built:
            items[item] = dict(built[asset], asset=asset, fit=fit, turn=turn)
    return items


# MARK: - Sky


def build_sky(args, out):
    """The sky photo turned so its sun stands at SUN_AZIMUTH and tone-mapped to an 8-bit PNG.

    The PNG is laid out as SceneKit reads an equirectangular image, measured on Metal: column u (0 at the left
    edge, 1 at the right) looks toward compass bearing (u - 0.75) * 360 degrees, clockwise from north, so the
    column three quarters across looks north (view -z); row v (0 at the top) looks up at (0.5 - v) * 180
    degrees. The sun is found in the photo's HDR data, where it stands far brighter than any cloud; a photo with
    no such peak is refused."""
    import numpy

    entry = shared["files"](shared["HDRI"], args.cache)["hdri"]["2k"]["hdr"]
    leaf = os.path.basename(shared["urllib"].parse.urlsplit(entry["url"]).path)
    path = shared["fetch"](entry, args.cache, "hdri", leaf, asset=shared["HDRI"])
    image = bpy.data.images.load(path)
    width, height = image.size
    pixels = numpy.empty(width * height * 4, dtype=numpy.float32)
    image.pixels.foreach_get(pixels)
    # Blender's pixel rows run bottom to top; the PNG's run top to bottom.
    rgb = pixels.reshape(height, width, 4)[::-1, :, :3].astype(numpy.float64)
    brightness = rgb.sum(axis=2)
    row, column = numpy.unravel_index(int(numpy.argmax(brightness)), brightness.shape)
    # The sun, not a bright cloud: far brighter than nearly all of the sky.
    if brightness[row, column] < 20 * float(numpy.percentile(brightness, 99.5)):
        raise LibraryError(["the sky photo has no distinct sun to align the sun lamp with"])
    # Blender's equirectangular photos: column u looks toward atan2(y, -x), which is bearing (u - 0.5) * 360 + 270.
    photo_bearing = (((column + 0.5) / width - 0.5) * 360 + 270) % 360
    elevation = (0.5 - (row + 0.5) / height) * 180
    # Roll the photo so the sun lands in the column that, in the library's convention, looks toward SUN_AZIMUTH.
    sun_column = int(round(((SUN_AZIMUTH / 360 + 0.75) % 1) * width)) % width
    rgb = numpy.roll(rgb, sun_column - column, axis=1)
    # Tone map: expose so the sky's middle brightness sits at about middle gray, then a soft shoulder.
    luminance = rgb @ numpy.array([0.2126, 0.7152, 0.0722])
    upper = luminance[: height // 2]
    exposure = 0.45 / max(float(numpy.median(upper)), 1e-6)
    mapped = 1 - numpy.exp(-rgb * exposure)
    srgb = numpy.where(mapped <= 0.0031308, mapped * 12.92, 1.055 * numpy.power(mapped, 1 / 2.4) - 0.055)
    srgb = numpy.clip(srgb, 0, 1)
    sky = bpy.data.images.new("Hestia sky", width=width, height=height, alpha=False)
    sky.colorspace_settings.name = "Non-Color"
    flat = numpy.ones((height, width, 4), dtype=numpy.float32)
    flat[:, :, :3] = srgb[::-1]
    sky.pixels.foreach_set(flat.ravel())
    if (width, height) != SKY_SIZE:
        sky.scale(*SKY_SIZE)
    folder = os.path.join(out, "sky")
    os.makedirs(folder, exist_ok=True)
    sky.filepath_raw = os.path.join(folder, "sky.png")
    sky.file_format = "PNG"
    sky.save()
    print("Hestia library: sky sun at bearing", round(photo_bearing, 1), "turned to", SUN_AZIMUTH, "elevation",
          round(elevation, 1))
    return {"file": "sky/sky.png", "asset": shared["HDRI"], "layout": "scenekit", "sunAzimuth": SUN_AZIMUTH,
            "sunElevation": round(max(elevation, 8.0), 2), "exposure": round(exposure, 5)}


# MARK: - Library


class LibraryError(Exception):
    """The library is incomplete or names a file it does not hold; nothing is written as finished."""

    def __init__(self, problems):
        super().__init__("; ".join(problems))
        self.problems = problems


def validate(library, out, complete):
    """Every problem with a library before it is written; see check_library.validate, the same rule
    build-app.sh applies to whatever library it packages."""
    import check_library

    want = {"HDRI": shared["HDRI"], "LICENSE_URL": shared["LICENSE_URL"], "SCRIPT_VERSION": shared["SCRIPT_VERSION"],
            "SUN_AZIMUTH": SUN_AZIMUTH}
    return check_library.validate(library, out, complete, shared["TEXTURES"], shared["MODELS"], want)


def record_files(library, out):
    """Each file the library names, and its credits, with its size and SHA-256, so the packaging check can tell
    the library holds exactly what was built."""
    import check_library

    named = [path for entry in library["surfaces"].values() for path in entry["maps"].values()]
    named += [entry["file"] for entry in library["models"].values()]
    if "sky" in library:
        named.append(library["sky"]["file"])
    files = {}
    for relative in sorted(set(named) | {"CREDITS.txt"}):
        path = os.path.join(out, relative)
        if os.path.isfile(path):
            size, sha256 = check_library.digest(path)
            files[relative] = {"bytes": size, "sha256": sha256}
    return files


def write_credits(out):
    assets = sorted({item["asset"] for item in shared["MANIFEST"] if item.get("asset")})
    with open(os.path.join(out, "CREDITS.txt"), "w") as handle:
        handle.write("Hestia asset library\n\nMaterials, models, and sky: Poly Haven (https://polyhaven.com), CC0 "
                     "(https://polyhaven.com/license).\n\n")
        for asset in assets:
            handle.write("- %s\n" % asset)


def main():
    args = arguments()
    out = os.path.abspath(args.out)
    os.makedirs(out, exist_ok=True)
    library = {
        "version": LIBRARY_VERSION,
        "script": shared["SCRIPT_VERSION"],
        "blender": bpy.app.version_string,
        "source": "Poly Haven (https://polyhaven.com), CC0",
        "license": shared["LICENSE_URL"],
        "surfaces": build_surfaces(args, out),
        "models": build_models(args, out),
    }
    if wanted(shared["HDRI"], args):
        library["sky"] = build_sky(args, out)
    unique = {item["url"]: item for item in shared["MANIFEST"]}
    library["assets"] = sorted(unique.values(), key=lambda item: item["url"])
    complete = not args.only
    if not complete:
        library["partial"] = True
    write_credits(out)
    library["files"] = record_files(library, out)
    problems = validate(library, out, complete)
    if problems:
        raise LibraryError(problems)
    with open(os.path.join(out, "library.json"), "w") as handle:
        json.dump(library, handle, indent=2, sort_keys=True)
    print("Hestia library: wrote", out, len(library["surfaces"]), "surfaces,", len(library["models"]), "items")


main()
