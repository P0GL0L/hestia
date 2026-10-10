# Hestia photoreal render, run by Blender in the background:
#
#   blender -b --factory-startup --python hestia_render.py -- \
#       --usd house.usda --out render.png [--view exterior|interior] [--samples 128] [--size 1920x1080] \
#       [--cache ~/Library/Caches/Hestia/assets] [--device auto|cpu|gpu] [--no-assets]
#
# It opens the house Hestia exported as OpenUSD, swaps each surface's flat color for a CC0 PBR material from
# Poly Haven (wood floors, tile, plaster, roof tiles, lawn, paving, ...), swaps the simple stand-in furniture
# and trees for CC0 Poly Haven models of the same size where one fits, lights it with a real sky (HDRI) and a
# sun, and renders it with Cycles. Downloads are cached, so later renders run offline.
#
# Downloads come only over HTTPS from Poly Haven's API and download hosts, stream to a temporary file under a
# byte ceiling, and must match Poly Haven's declared size and MD5 before they replace anything in the cache;
# every cache path is checked to stay inside the cache. A manifest beside the picture lists each asset file
# with its source, license, declared size and MD5, and computed SHA-256. Assets: Poly Haven, CC0.
#
# Blender is a separate program the user installs; Hestia only runs it. Output is a schematic visualization,
# not a construction document.

import argparse
import hashlib
import json
import math
import os
import sys
import urllib.parse
import urllib.request

import bpy
import mathutils

API = "https://api.polyhaven.com/files/"
SCRIPT_VERSION = "hestia_render 2"

# Surface look -> (Poly Haven texture, real size of one tile in meters). Looks not listed keep the USD color.
TEXTURES = {
    "wall": ("painted_plaster_wall", 2.0),
    "woodFloor": ("laminate_floor_02", 2.0),
    "tileFloor": ("floor_tiles_06", 1.5),
    "carpet": ("poly_wool_herringbone", 1.0),
    "roof": ("grey_roof_tiles_02", 2.5),
    "grass": ("leafy_grass", 4.0),
    "lawn": ("leafy_grass", 3.0),
    "concrete": ("concrete_floor_01", 3.0),
    "slab": ("concrete_floor_01", 3.0),
    "paving": ("rectangular_paving", 2.0),
    "gravel": ("gravel_floor", 2.0),
    "deck": ("wood_floor_deck", 2.0),
    "stone": ("marble_01", 1.0),
    "wood": ("oak_veneer_01", 1.0),
    "woodDark": ("dark_wooden_planks", 1.5),
    "stair": ("oak_veneer_01", 1.0),
    "door": ("oak_veneer_01", 1.0),
    "fabric": ("fabric_pattern_07", 0.6),
}

# Catalog item -> (Poly Haven model, how to fit it: "footprint" or "height", extra turn in degrees).
MODELS = {
    "hestia.loveseat": ("Sofa_01", "footprint", 0),
    "hestia.sofa": ("Sofa_01", "footprint", 0),
    "hestia.armchair": ("ArmChair_01", "footprint", 0),
    "hestia.coffee-table": ("modern_coffee_table_01", "footprint", 0),
    "hestia.nightstand": ("ClassicNightstand_01", "footprint", 0),
    "hestia.dresser": ("modern_wooden_cabinet", "footprint", 0),
    "hestia.bookcase": ("Shelf_01", "footprint", 0),
    "hestia.desk": ("metal_office_desk", "footprint", 0),
    "hestia.office-chair": ("modern_arm_chair_01", "footprint", 0),
    "hestia.bar-stool": ("bar_chair_round_01", "footprint", 0),
    "hestia.range": ("electric_stove", "footprint", 0),
    "hestia.dining-chair": ("dining_chair_02", "footprint", 0),
    "hestia.dining-table": ("dining_table", "footprint", 0),
    "hestia.round-table": ("round_wooden_table_02", "footprint", 0),
    "hestia.patio-table": ("outdoor_table_chair_set_01", "footprint", 0),
    "hestia.car": ("covered_car", "footprint", 0),
    "hestia.tree-shade": ("island_tree_01", "height", 0),
    "hestia.tree-ornamental": ("island_tree_01", "height", 240),
    "hestia.tree-pine": ("island_tree_01", "height", 120),
    "hestia.shrub": ("fern_02", "height", 0),
}

HDRI = "kloofendal_48d_partly_cloudy_puresky"

# Color multipliers for textures that read too dry or too dark at house scale.
TINTS = {"leafy_grass": (0.75, 1.05, 0.55)}


def arguments():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--usd", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--view", default="exterior", choices=["exterior", "interior"])
    parser.add_argument("--samples", type=int, default=128)
    parser.add_argument("--size", default="1920x1080")
    parser.add_argument("--cache", default=os.path.expanduser("~/Library/Caches/Hestia/assets"))
    parser.add_argument("--device", default="auto", choices=["auto", "cpu", "gpu"])
    parser.add_argument("--no-assets", action="store_true")
    parser.add_argument("--grass", type=float, default=0.0, help="grass clumps per square meter of lawn; 0 for none")

    return parser.parse_args(argv)


# MARK: - Downloads


class DownloadError(Exception):
    pass


ALLOWED_HOSTS = {"api.polyhaven.com", "dl.polyhaven.org"}
METADATA_LIMIT = 4 * 1024 * 1024
FILE_LIMIT = 96 * 1024 * 1024
LICENSE_URL = "https://polyhaven.com/license"

# Every asset file this render used, for the manifest written beside the picture.
MANIFEST = []


def checked_url(url):
    """The URL, when it is HTTPS on a Poly Haven host; otherwise refused."""
    parts = urllib.parse.urlsplit(url)
    if parts.scheme != "https" or parts.hostname not in ALLOWED_HOSTS or parts.username or parts.password:
        raise DownloadError("refused a download from outside Poly Haven: %r" % url)
    return url


def inside(root, *relative):
    """A path under `root`, refusing absolute paths and any that climb out of it."""
    base = os.path.realpath(root)
    for piece in relative:
        steps = piece.replace("\\", "/").split("/")
        if not piece or os.path.isabs(piece) or piece.startswith(("/", "\\")) or "\x00" in piece or ".." in steps:
            raise DownloadError("refused an unsafe cache path: %r" % (relative,))
    path = os.path.realpath(os.path.join(base, *relative))
    if os.path.commonpath([base, path]) != base or path == base:
        raise DownloadError("refused a cache path outside the cache: %r" % (relative,))
    return path


def asset_name(asset):
    if not asset or not all(char.isascii() and (char.isalnum() or char == "_") for char in asset):
        raise DownloadError("refused an unexpected asset name: %r" % asset)
    return asset


def digests(path):
    md5, sha = hashlib.md5(), hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            md5.update(chunk)
            sha.update(chunk)
    return md5.hexdigest(), sha.hexdigest()


def download(url, path, limit, size=None, md5=None):
    """Streams an allowlisted HTTPS file to `path`, checking the host after redirects, the byte ceiling, and the
    declared size and MD5. A cached file is reused only when it still matches. Returns the path."""
    checked_url(url)
    if size is not None and size > limit:
        raise DownloadError("%s declares %d bytes, over the %d-byte ceiling" % (url, size, limit))
    if os.path.exists(path):
        if size is None or (os.path.getsize(path) == size and (md5 is None or digests(path)[0] == md5)):
            return path
        os.remove(path)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    partial = path + ".part"
    try:
        request = urllib.request.Request(url, headers={"User-Agent": "Hestia/0.1 (+https://github.com/P0GL0L/hestia)"})
        with urllib.request.urlopen(request, timeout=120) as response, open(partial, "wb") as out:
            checked_url(response.geturl())
            written = 0
            for chunk in iter(lambda: response.read(1 << 16), b""):
                written += len(chunk)
                if written > limit:
                    raise DownloadError("%s is larger than %d bytes" % (url, limit))
                out.write(chunk)
        if size is not None and os.path.getsize(partial) != size:
            raise DownloadError("%s arrived with %d bytes, not the declared %d" % (url, os.path.getsize(partial), size))
        if md5 is not None and digests(partial)[0] != md5:
            raise DownloadError("%s failed its MD5 check" % url)
        os.replace(partial, path)
        return path
    finally:
        if os.path.exists(partial):
            os.remove(partial)


def fetch(entry, cache, *relative, asset=""):
    """A Poly Haven file entry (url, size, md5) downloaded into the cache at `relative`, recorded for the
    manifest."""
    url, size, md5 = entry["url"], entry.get("size"), entry.get("md5")
    path = download(url, inside(cache, *relative), FILE_LIMIT, size, md5)
    MANIFEST.append({"asset": asset, "url": url, "declaredSize": size, "declaredMD5": md5,
                     "sha256": digests(path)[1], "license": LICENSE_URL})
    return path


def files(asset, cache):
    """Poly Haven's file list for an asset, cached. It carries each file's URL, size, and MD5."""
    asset = asset_name(asset)
    path = inside(cache, "index", asset + ".json")
    if not os.path.exists(path):
        download(API + asset, path, METADATA_LIMIT)
    try:
        with open(path) as handle:
            return json.load(handle)
    except ValueError:
        os.remove(path)
        raise DownloadError("Poly Haven's file list for %s was not valid JSON" % asset)


def texture_maps(asset, cache):
    """Diffuse, OpenGL normal, and roughness maps at 1k, as local paths."""
    info = files(asset, cache)
    maps = {}
    for key, name in (("Diffuse", "diffuse"), ("nor_gl", "normal"), ("Rough", "rough")):
        if key in info and "1k" in info[key]:
            entry = info[key]["1k"].get("jpg") or info[key]["1k"].get("png")
            leaf = os.path.basename(urllib.parse.urlsplit(entry["url"]).path)
            maps[name] = fetch(entry, cache, "textures", asset, leaf, asset=asset)
    return maps


def model_file(asset, cache):
    """The model's glTF at 1k with its buffers and textures, as a local path."""
    entry = files(asset, cache)["gltf"]["1k"]["gltf"]
    for relative, include in entry.get("include", {}).items():
        pieces = relative.replace("\\", "/").split("/")
        if any(piece in ("", ".", "..") for piece in pieces):
            raise DownloadError("refused an unsafe model path: %r" % relative)
        fetch(include, cache, "models", asset, *pieces, asset=asset)
    leaf = os.path.basename(urllib.parse.urlsplit(entry["url"]).path)
    return fetch(entry, cache, "models", asset, leaf, asset=asset)


def write_manifest(args):
    """What the picture was made from, beside it: every asset file, its source and license, and the versions."""
    unique = {item["url"]: item for item in MANIFEST}
    record = {
        "picture": os.path.basename(args.out),
        "script": SCRIPT_VERSION,
        "blender": bpy.app.version_string,
        "source": "Poly Haven (https://polyhaven.com), CC0",
        "license": LICENSE_URL,
        "assets": sorted(unique.values(), key=lambda item: item["url"]),
    }
    with open(os.path.splitext(args.out)[0] + ".manifest.json", "w") as handle:
        json.dump(record, handle, indent=2)


# MARK: - Scene


def flatten(objects):
    """Bakes each mesh's world transform into its vertices, so object space is world meters."""
    for obj in objects:
        world = obj.matrix_world.copy()
        obj.parent = None
        obj.data.transform(world)
        obj.matrix_world = mathutils.Matrix.Identity(4)


def principled(material):
    material.use_nodes = True
    nodes = material.node_tree.nodes
    return next((node for node in nodes if node.type == "BSDF_PRINCIPLED"), None)


def upgrade_material(material, asset, size, cache, tint=None):
    """Box-projected PBR textures in world meters on the material's Principled BSDF."""
    bsdf = principled(material)
    if bsdf is None:
        return
    maps = texture_maps(asset, cache)
    tree = material.node_tree
    nodes, links = tree.nodes, tree.links
    coords = nodes.new("ShaderNodeTexCoord")
    mapping = nodes.new("ShaderNodeMapping")
    mapping.inputs["Scale"].default_value = (1 / size, 1 / size, 1 / size)
    links.new(coords.outputs["Object"], mapping.inputs["Vector"])

    def image(path, color):
        node = nodes.new("ShaderNodeTexImage")
        node.image = bpy.data.images.load(path, check_existing=True)
        node.image.colorspace_settings.name = "sRGB" if color else "Non-Color"
        node.projection = "BOX"
        node.projection_blend = 0.25
        links.new(mapping.outputs["Vector"], node.inputs["Vector"])
        return node

    if "diffuse" in maps:
        color = image(maps["diffuse"], True).outputs["Color"]
        if tint:
            mix = nodes.new("ShaderNodeMix")
            mix.data_type = "RGBA"
            mix.blend_type = "MULTIPLY"
            mix.inputs["Factor"].default_value = 1.0
            links.new(color, mix.inputs["A"])
            mix.inputs["B"].default_value = (*tint, 1.0)
            color = mix.outputs["Result"]
        links.new(color, bsdf.inputs["Base Color"])
    if "rough" in maps:
        links.new(image(maps["rough"], False).outputs["Color"], bsdf.inputs["Roughness"])
    if "normal" in maps:
        normal = nodes.new("ShaderNodeNormalMap")
        normal.inputs["Strength"].default_value = 0.8
        links.new(image(maps["normal"], False).outputs["Color"], normal.inputs["Color"])
        links.new(normal.outputs["Normal"], bsdf.inputs["Normal"])


def tune_plain_materials():
    """Glass and water that refract, metal that reflects, and soft fabric for the looks left untextured."""
    for material in bpy.data.materials:
        bsdf = principled(material)
        if bsdf is None:
            continue
        name = material.name.split(".")[0]
        if name in ("glass", "water"):
            if name == "glass":
                bsdf.inputs["Base Color"].default_value = (0.95, 0.97, 0.98, 1)
            bsdf.inputs["Transmission Weight"].default_value = 1.0
            bsdf.inputs["Roughness"].default_value = 0.02
            bsdf.inputs["IOR"].default_value = 1.45 if name == "glass" else 1.33
            bsdf.inputs["Alpha"].default_value = 1.0
        elif name == "trim":
            bsdf.inputs["Roughness"].default_value = 0.35
        elif name == "metal":
            bsdf.inputs["Metallic"].default_value = 1.0
            bsdf.inputs["Roughness"].default_value = 0.3
        elif name in ("fabricDark", "leather", "linen", "white", "porcelain"):
            bsdf.inputs["Roughness"].default_value = 0.2 if name == "porcelain" else 0.7
            bsdf.inputs["Sheen Weight"].default_value = 0.3 if name in ("fabricDark", "linen") else 0.0


def item_frame(empty, children):
    """Where a placed item stands: floor middle, turn about z, and its width, depth, and height in meters."""
    axis = empty.matrix_world.to_3x3() @ mathutils.Vector((1, 0, 0))
    turn = math.atan2(axis.y, axis.x)
    origin = empty.matrix_world.translation
    undo = mathutils.Matrix.Rotation(-turn, 4, "Z")
    low = mathutils.Vector((1e9, 1e9, 1e9))
    high = -low
    for child in children:
        for corner in child.bound_box:
            point = undo @ (child.matrix_world @ mathutils.Vector(corner) - origin)
            low = mathutils.Vector(map(min, low, point))
            high = mathutils.Vector(map(max, high, point))
    size = high - low
    middle = mathutils.Matrix.Rotation(turn, 4, "Z") @ ((low + high) / 2)
    return origin + mathutils.Vector((middle.x, middle.y, 0)), turn, size, origin.z + low.z


def load_model(asset, cache, loaded):
    """Imports a model once into its own hidden collection, and returns that collection and its bounds."""
    if asset in loaded:
        return loaded[asset]
    path = model_file(asset, cache)
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    imported = [obj for obj in bpy.data.objects if obj not in before]
    collection = bpy.data.collections.new("Model " + asset)
    bpy.context.scene.collection.children.link(collection)
    for obj in imported:
        for owner in obj.users_collection:
            owner.objects.unlink(obj)
        collection.objects.link(obj)
    bpy.context.view_layer.layer_collection.children[collection.name].exclude = True
    bpy.context.view_layer.update()
    low = mathutils.Vector((1e9, 1e9, 1e9))
    high = -low
    for obj in imported:
        if obj.type == "MESH":
            for corner in obj.bound_box:
                point = obj.matrix_world @ mathutils.Vector(corner)
                low = mathutils.Vector(map(min, low, point))
                high = mathutils.Vector(map(max, high, point))
    loaded[asset] = (collection, low, high)
    return loaded[asset]


def swap_items(cache):
    """Replaces stand-in furniture and trees with finished models of the same size and place. Each model is
    loaded once and placed as an instance, so five trees cost the memory of one."""
    loaded = {}
    # An item made of one part comes in as a single mesh object rather than an empty holding meshes.
    for empty in [obj for obj in bpy.data.objects if "hestia:catalogItem" in obj]:
        choice = MODELS.get(empty["hestia:catalogItem"])
        children = [child for child in empty.children_recursive if child.type == "MESH"]
        if empty.type == "MESH":
            children.append(empty)
        if choice is None or not children:
            continue
        asset, fit, extra = choice
        try:
            collection, low, high = load_model(asset, cache, loaded)
        except Exception as error:  # A failed download keeps the stand-in.
            print("Hestia: kept the stand-in for", asset, error)
            continue
        position, turn, size, floor = item_frame(empty, children)
        model = high - low
        if fit == "height":
            scale = size.z / max(model.z, 1e-6)
        else:
            scale = min(size.x / max(model.x, 1e-6), size.y / max(model.y, 1e-6))
        middle = (low + high) / 2
        root = bpy.data.objects.new(empty.name + "_model", None)
        root.instance_type = "COLLECTION"
        root.instance_collection = collection
        bpy.context.scene.collection.objects.link(root)
        root.matrix_world = (mathutils.Matrix.Translation((position.x, position.y, floor))
                             @ mathutils.Matrix.Rotation(turn + math.radians(extra), 4, "Z")
                             @ mathutils.Matrix.Scale(scale, 4)
                             @ mathutils.Matrix.Translation((-middle.x, -middle.y, -low.z)))
        for child in children:
            child.hide_render = True
            child.hide_viewport = True


def scatter_grass(cache, density):
    """Real grass on the lawn and the lot: a CC0 grass clump scattered over them with geometry nodes."""
    try:
        path = model_file("grass_bermuda_01", cache)
    except Exception as error:
        print("Hestia: no grass model", error)
        return
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    clump = bpy.data.collections.new("Grass clump")
    for obj in [obj for obj in bpy.data.objects if obj not in before]:
        for collection in obj.users_collection:
            collection.objects.unlink(obj)
        clump.objects.link(obj)
    # The clump itself stays out of the picture; only its scattered copies render.
    bpy.context.scene.collection.children.link(clump)
    bpy.context.view_layer.layer_collection.children[clump.name].exclude = True
    print("Hestia: grass clump size", [tuple(round(v, 2) for v in obj.dimensions) for obj in clump.objects][:3])
    targets = [obj for obj in bpy.data.objects
               if obj.type == "MESH" and obj.get("hestia_part") == "site" and obj.name.split(".")[0] == "lawn"]
    for target in targets:
        group = bpy.data.node_groups.new("Hestia grass", "GeometryNodeTree")
        group.interface.new_socket("Geometry", in_out="INPUT", socket_type="NodeSocketGeometry")
        group.interface.new_socket("Geometry", in_out="OUTPUT", socket_type="NodeSocketGeometry")
        nodes, links = group.nodes, group.links
        start, end = nodes.new("NodeGroupInput"), nodes.new("NodeGroupOutput")
        scatter = nodes.new("GeometryNodeDistributePointsOnFaces")
        scatter.inputs["Density"].default_value = density if target.name.startswith("lawn") else density * 0.6
        info = nodes.new("GeometryNodeCollectionInfo")
        info.inputs["Collection"].default_value = clump
        info.inputs["Separate Children"].default_value = True
        info.inputs["Reset Children"].default_value = True
        info.transform_space = "RELATIVE"
        place = nodes.new("GeometryNodeInstanceOnPoints")
        place.inputs["Pick Instance"].default_value = True
        turn = nodes.new("FunctionNodeRandomValue")
        turn.data_type = "FLOAT_VECTOR"
        turn.inputs["Min"].default_value = (0, 0, 0)
        turn.inputs["Max"].default_value = (0, 0, 6.283)
        size = nodes.new("FunctionNodeRandomValue")
        size.inputs["Min"].default_value = 1.2
        size.inputs["Max"].default_value = 2.0
        join = nodes.new("GeometryNodeJoinGeometry")
        # No grass under the house, the paving, or the water: drop points close to those surfaces.
        blockers = nodes.new("GeometryNodeJoinGeometry")
        for other in bpy.data.objects:
            if other.type != "MESH" or other is target:
                continue
            part, look = other.get("hestia_part"), other.name.split(".")[0]
            if part == "building" or (part == "site" and look not in ("lawn", "grass")):
                source = nodes.new("GeometryNodeObjectInfo")
                source.inputs["Object"].default_value = other
                source.transform_space = "RELATIVE"
                links.new(source.outputs["Geometry"], blockers.inputs["Geometry"])
        near = nodes.new("GeometryNodeProximity")
        near.target_element = "FACES"
        links.new(blockers.outputs["Geometry"], near.inputs["Target"])
        close = nodes.new("FunctionNodeCompare")
        close.data_type = "FLOAT"
        close.operation = "LESS_THAN"
        close.inputs["B"].default_value = 0.08
        links.new(near.outputs["Distance"], close.inputs["A"])
        drop = nodes.new("GeometryNodeDeleteGeometry")
        drop.domain = "POINT"
        links.new(start.outputs["Geometry"], scatter.inputs["Mesh"])
        links.new(scatter.outputs["Points"], drop.inputs["Geometry"])
        links.new(close.outputs["Result"], drop.inputs["Selection"])
        links.new(drop.outputs["Geometry"], place.inputs["Points"])
        links.new(info.outputs["Instances"], place.inputs["Instance"])
        links.new(turn.outputs["Value"], place.inputs["Rotation"])
        links.new(size.outputs["Value"], place.inputs["Scale"])
        links.new(start.outputs["Geometry"], join.inputs["Geometry"])
        links.new(place.outputs["Instances"], join.inputs["Geometry"])
        links.new(join.outputs["Geometry"], end.inputs["Geometry"])
        modifier = target.modifiers.new("Grass", "NODES")
        modifier.node_group = group
        print("Hestia: grass on", target.name)


def light_world(cache, strength):
    world = bpy.data.worlds.new("Sky")
    bpy.context.scene.world = world
    world.use_nodes = True
    nodes, links = world.node_tree.nodes, world.node_tree.links
    background = nodes.get("Background") or nodes.new("ShaderNodeBackground")
    background.inputs["Strength"].default_value = strength
    try:
        entry = files(HDRI, cache)["hdri"]["2k"]["hdr"]
        leaf = os.path.basename(urllib.parse.urlsplit(entry["url"]).path)
        environment = nodes.new("ShaderNodeTexEnvironment")
        environment.image = bpy.data.images.load(fetch(entry, cache, "hdri", leaf, asset=HDRI))
        links.new(environment.outputs["Color"], background.inputs["Color"])
    except Exception as error:
        print("Hestia: no sky image, using a plain sky", error)
        background.inputs["Color"].default_value = (0.55, 0.7, 0.95, 1)
    output = nodes.get("World Output") or nodes.new("ShaderNodeOutputWorld")
    links.new(background.outputs["Background"], output.inputs["Surface"])


def tune_sun():
    for obj in bpy.data.objects:
        if obj.type == "LIGHT" and obj.data.type == "SUN":
            obj.data.energy = 4.0
            obj.data.angle = math.radians(0.6)


def building_bounds():
    low = mathutils.Vector((1e9, 1e9, 1e9))
    high = -low
    for obj in bpy.data.objects:
        if obj.type == "MESH" and obj.get("hestia_part") == "building":
            for corner in obj.bound_box:
                point = obj.matrix_world @ mathutils.Vector(corner)
                low = mathutils.Vector(map(min, low, point))
                high = mathutils.Vector(map(max, high, point))
    return low, high


def exterior_camera():
    """From the south-east at a person's height on a rise, the whole house in frame."""
    low, high = building_bounds()
    middle = (low + high) / 2
    reach = max(high.x - low.x, high.y - low.y) * 1.25
    camera = bpy.data.objects.new("Exterior", bpy.data.cameras.new("Exterior"))
    bpy.context.scene.collection.objects.link(camera)
    camera.data.lens = 32
    camera.location = (middle.x + reach * 0.85, middle.y - reach * 1.15, 5.5)
    target = mathutils.Vector((middle.x, middle.y, 1.6))
    camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
    return camera


def room_lights():
    """A warm ceiling panel in every room Hestia exported, sized and powered by the room's floor area."""
    for room in [obj for obj in bpy.data.objects if "hestia:room" in obj]:
        width, depth = (float(value) * 0.3048 for value in room.get("hestia:size", (10, 10)))
        lamp = bpy.data.lights.new("Ceiling " + room["hestia:room"], "AREA")
        lamp.shape = "RECTANGLE"
        lamp.size, lamp.size_y = max(width * 0.5, 0.3), max(depth * 0.5, 0.3)
        lamp.energy = 22 * width * depth
        lamp.color = (1.0, 0.9, 0.78)
        light = bpy.data.objects.new(lamp.name, lamp)
        light.location = room.matrix_world.translation - mathutils.Vector((0, 0, 0.06))
        bpy.context.scene.collection.objects.link(light)


def interior_camera():
    """At eye height in the south-west room, looking across the house toward the north-east."""
    low, high = building_bounds()
    camera = bpy.data.objects.new("Interior", bpy.data.cameras.new("Interior"))
    bpy.context.scene.collection.objects.link(camera)
    camera.data.lens = 20
    camera.location = (low.x + 0.9, low.y + 0.9, 1.6)
    target = mathutils.Vector((low.x + (high.x - low.x) * 0.45, low.y + (high.y - low.y) * 0.55, 1.2))
    camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
    room_lights()
    return camera


def configure(args, camera):
    scene = bpy.context.scene
    scene.camera = camera
    scene.render.engine = "CYCLES"
    width, height = (int(part) for part in args.size.lower().split("x"))
    scene.render.resolution_x, scene.render.resolution_y = width, height
    scene.render.resolution_percentage = 100
    scene.cycles.samples = args.samples
    scene.cycles.use_adaptive_sampling = True
    scene.cycles.use_denoising = True
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "AgX - Medium High Contrast"
    scene.view_settings.exposure = 0.3 if args.view == "interior" else 0.0
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = args.out
    if args.device != "cpu":
        prefs = bpy.context.preferences.addons["cycles"].preferences
        for backend in ("METAL", "OPTIX", "CUDA", "HIP", "ONEAPI"):
            try:
                prefs.compute_device_type = backend
                prefs.get_devices()
                if any(device.type != "CPU" for device in prefs.devices):
                    for device in prefs.devices:
                        device.use = True
                    scene.cycles.device = "GPU"
                    break
            except TypeError:
                continue


def main():
    args = arguments()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.wm.usd_import(filepath=args.usd)
    parts = {"Building": "building", "Site": "site"}
    for group, tag in parts.items():
        holder = bpy.data.objects.get(group)
        meshes = [obj for obj in (holder.children_recursive if holder else []) if obj.type == "MESH"]
        flatten(meshes)
        for obj in meshes:
            obj["hestia_part"] = tag
    if not args.no_assets:
        for material in list(bpy.data.materials):
            choice = TEXTURES.get(material.name.split(".")[0])
            if choice:
                try:
                    upgrade_material(material, choice[0], choice[1], args.cache, TINTS.get(choice[0]))
                except Exception as error:
                    print("Hestia: kept the plain color for", material.name, error)
        swap_items(args.cache)
        if args.grass > 0:
            scatter_grass(args.cache, args.grass)
    tune_plain_materials()
    tune_sun()
    light_world(args.cache, 1.0 if args.view == "exterior" else 1.6)
    if args.view == "interior":
        for obj in bpy.data.objects:
            if obj.type == "MESH" and obj.name.split(".")[0] == "roof":
                obj.visible_camera = False
        camera = interior_camera()
    else:
        camera = exterior_camera()
    configure(args, camera)
    bpy.ops.render.render(write_still=True)
    write_manifest(args)
    print("Hestia: wrote", args.out)


main()
