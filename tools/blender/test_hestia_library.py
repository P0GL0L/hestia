# Offline checks of hestia_library.py: which materials count as leaves, and that lightening a model keeps each
# material on its own part and stays within the live view's budgets. Run with Blender, which provides bpy:
#
#   blender -b --factory-startup --python-exit-code 1 --python tools/blender/test_hestia_library.py
#
# Exits non-zero when any check fails. Needs no network.

import json
import os
import sys
import tempfile

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
SOURCE = open(os.path.join(HERE, "hestia_library.py")).read().replace("\nmain()\n", "\n")
library = {"__name__": "hestia_library", "__file__": os.path.join(HERE, "hestia_library.py")}
exec(compile(SOURCE, "hestia_library.py", "exec"), library)
failures = []


def check(label, condition):
    print(("ok: " if condition else "FAIL: ") + label)
    if not condition:
        failures.append(label)


def gltf(materials, images, textures):
    handle, path = tempfile.mkstemp(suffix=".gltf")
    with os.fdopen(handle, "w") as out:
        json.dump({"materials": materials, "images": images, "textures": textures}, out)
    return path


# Leaves: MASK and BLEND materials; cut out only when their color texture can carry alpha.
path = gltf(
    [{"name": "bark"},
     {"name": "leaves_png", "alphaMode": "MASK", "alphaCutoff": 0.3,
      "pbrMetallicRoughness": {"baseColorTexture": {"index": 0}}},
     {"name": "leaves_jpg", "alphaMode": "BLEND", "pbrMetallicRoughness": {"baseColorTexture": {"index": 1}}},
     {"name": "leaves_bad", "alphaMode": "MASK", "pbrMetallicRoughness": {"baseColorTexture": {"index": 9}}}],
    [{"uri": "textures/leaf.png"}, {"uri": "textures/leaf.jpg"}],
    [{"source": 0}, {"source": 1}])
found = library["foliage_materials"](path)
check("bark is not a leaf", "bark" not in found)
check("a PNG leaf is cut out at its cutoff", found.get("leaves_png") == 0.3)
check("a JPEG leaf is a leaf drawn solid", "leaves_jpg" in found and found["leaves_jpg"] is None)
check("a leaf naming a missing texture is drawn solid", "leaves_bad" in found and found["leaves_bad"] is None)


def grid_object(name, cuts, material_names):
    """A subdivided plane whose faces alternate between the given materials, in rows."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    mesh = bpy.data.meshes.new(name)
    size = cuts + 1
    vertices = [(x, y, 0) for y in range(size) for x in range(size)]
    faces = []
    for y in range(cuts):
        for x in range(cuts):
            a = y * size + x
            faces += [(a, a + 1, a + size + 1), (a, a + size + 1, a + size)]
    mesh.from_pydata(vertices, [], faces)
    for material_name in material_names:
        mesh.materials.append(bpy.data.materials.new(material_name))
    for polygon in mesh.polygons:
        polygon.material_index = (polygon.index // (2 * cuts)) % len(material_names)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


grid_object("tree", 120, ["bark", "leaves"])
library["LEAF_BUDGET"], library["SOLID_BUDGET"] = 4000, 2000
total = library["lighten"]({"leaves": None})
parts = [obj for obj in bpy.data.objects if obj.type == "MESH"]
check("lightening splits a model into one part per material", len(parts) == 2)
check("each part keeps one material slot",
      all(len(part.data.materials) == 1 for part in parts))
names = sorted(part.data.materials[0].name for part in parts)
check("each part keeps its own material", names == ["bark", "leaves"])
leaves = next(part for part in parts if part.data.materials[0].name == "leaves")
bark = next(part for part in parts if part.data.materials[0].name == "bark")
check("leaves stay within their budget", len(leaves.data.polygons) <= 4000 * 1.05)
check("solid parts stay within their budget", len(bark.data.polygons) <= 2000 * 1.05)
check("lightening reports the triangles left", total == len(leaves.data.polygons) + len(bark.data.polygons))

grid_object("chair", 10, ["wood"])
library["lighten"]({})
chair = [obj for obj in bpy.data.objects if obj.type == "MESH"]
check("a model within budget is left alone", len(chair) == 1 and len(chair[0].data.polygons) == 200)

# A library is refused when it is incomplete or names a file it does not hold.
folder = tempfile.mkdtemp()
os.makedirs(os.path.join(folder, "models"))
with open(os.path.join(folder, "models", "Sofa.usdz"), "w") as out:
    out.write("x")
open(os.path.join(folder, "models", "Empty.usdz"), "w").close()
outside = tempfile.mkdtemp()
with open(os.path.join(outside, "secret.usdz"), "w") as out:
    out.write("x")
os.symlink(os.path.join(outside, "secret.usdz"), os.path.join(folder, "models", "Link.usdz"))
validate = library["validate"]
good = {"surfaces": {}, "models": {"hestia.sofa": {"file": "models/Sofa.usdz"}}}
check("a partial library naming only its own files passes", validate(good, folder, False) == [])
complete = validate(good, folder, True)
check("a complete build needs every surface", any("surface wall" in problem for problem in complete))
check("a complete build needs every catalog item's model", any("hestia.armchair" in p for p in complete))
check("a complete build needs the sky", any("sky" in problem for problem in complete))
for name, label in (("models/Missing.usdz", "a missing file"), ("models/Empty.usdz", "an empty file"),
                    ("models/Link.usdz", "a link out of the library"), ("../outside.usdz", "a path out")):
    bad = {"surfaces": {}, "models": {"x": {"file": name}}}
    check("refuses " + label, validate(bad, folder, False) != [])

# The packaging check: a complete library passes; a partial build, another version, or a damaged one does not.
sys.path.insert(0, HERE)
import check_library  # noqa: E402

textures, models = check_library.renderer_tables()
whole = tempfile.mkdtemp()
manifest = {"version": 1, "surfaces": {}, "models": {}, "sky": {"file": "sky/sky.png", "layout": "scenekit"}}
def touch(relative):
    path = os.path.join(whole, relative)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as out:
        out.write("x")
for look, (asset, tile) in textures.items():
    maps = {kind: "surfaces/%s/%s.jpg" % (asset, kind) for kind in ("diffuse", "normal", "rough")}
    for relative in maps.values():
        touch(relative)
    manifest["surfaces"][look] = {"asset": asset, "tile": tile, "maps": maps}
for item, (asset, fit, turn) in models.items():
    touch("models/%s.usdz" % asset)
    manifest["models"][item] = {"asset": asset, "file": "models/%s.usdz" % asset, "fit": fit, "turn": turn,
                                "size": [1, 1, 1]}
touch("sky/sky.png")
touch("CREDITS.txt")
want = check_library.expected()
manifest["sky"].update(asset=want["HDRI"], sunAzimuth=want["SUN_AZIMUTH"], sunElevation=40.0, exposure=1.3)
manifest.update(source=check_library.SOURCE, license=want["LICENSE_URL"], script=want["SCRIPT_VERSION"],
                blender="5.2.2")
used = sorted({entry["asset"] for part in ("surfaces", "models") for entry in manifest[part].values()}
              | {want["HDRI"]})
manifest["assets"] = [{"asset": name, "url": "https://dl.polyhaven.org/%s" % name, "declaredSize": 100,
                       "declaredMD5": "0" * 32, "sha256": "0" * 64, "license": want["LICENSE_URL"]} for name in used]


def recorded():
    """Every file in the test library with its size and digest, as the builder records them."""
    files = {}
    for folder, _, names in os.walk(whole):
        for name in names:
            relative = os.path.relpath(os.path.join(folder, name), whole)
            if relative != "library.json":
                size, sha256 = check_library.digest(os.path.join(folder, name))
                files[relative] = {"bytes": size, "sha256": sha256}
    return files


manifest["files"] = recorded()
def write(document):
    with open(os.path.join(whole, "library.json"), "w") as out:
        json.dump(document, out)
write(manifest)
check("the packaging check passes a complete library", check_library.check(whole) == [])
write(dict(manifest, partial=True))
check("the packaging check refuses a partial build", check_library.check(whole) != [])
write(dict(manifest, version=2))
check("the packaging check refuses another library version", check_library.check(whole) != [])
write(manifest)
os.remove(os.path.join(whole, "sky", "sky.png"))
check("the packaging check refuses a library missing a file", check_library.check(whole) != [])
touch("sky/sky.png")
os.remove(os.path.join(whole, "library.json"))
check("the packaging check refuses a folder with no library.json", check_library.check(whole) != [])

# A library.json reached through a link, even to a good manifest, is refused.
elsewhere = os.path.join(tempfile.mkdtemp(), "library.json")
with open(elsewhere, "w") as out:
    json.dump(manifest, out)
os.symlink(elsewhere, os.path.join(whole, "library.json"))
check("the packaging check refuses a linked library.json", check_library.check(whole) != [])
os.remove(os.path.join(whole, "library.json"))


def remapped(change):
    """The complete manifest with one change applied to a copy of it."""
    document = json.loads(json.dumps(manifest))
    change(document)
    return document


first_item, (first_asset, _, _) = sorted(models.items())[0]
other_asset = next(asset for _, (asset, _, _) in sorted(models.items()) if asset != first_asset)
first_look, (first_surface, _) = sorted(textures.items())[0]
other_surface = next(asset for _, (asset, _) in sorted(textures.items()) if asset != first_surface)
wrong = {
    "a catalog item mapped to another model's file":
        lambda d: d["models"][first_item].update(asset=other_asset, file="models/%s.usdz" % other_asset),
    "a catalog item with the wrong fit": lambda d: d["models"][first_item].update(fit="height-of-nothing"),
    "a catalog item with no size": lambda d: d["models"][first_item].pop("size"),
    "a catalog item with a negative size": lambda d: d["models"][first_item].update(size=[1, -1, 1]),
    "a look mapped to another surface": lambda d: d["surfaces"][first_look].update(asset=other_surface),
    "a look whose map is another surface's":
        lambda d: d["surfaces"][first_look]["maps"].update(diffuse="surfaces/%s/diffuse.jpg" % other_surface),
    "a look at the wrong tile size": lambda d: d["surfaces"][first_look].update(tile=99),
    "a sky not laid out for SceneKit": lambda d: d["sky"].pop("layout"),
    "a model 999 m across": lambda d: d["models"][first_item].update(size=[999, 999, 999]),
    "a map under another name": lambda d: d["surfaces"][first_look]["maps"].update(
        diffuse="surfaces/%s/Diffuse.jpg" % first_surface),
    "a sky from another photo": lambda d: d["sky"].update(asset="some_other_sky"),
    "a sky whose sun is not where the builder turned it": lambda d: d["sky"].update(sunAzimuth=90.0),
    "a sky with a sun below the horizon": lambda d: d["sky"].update(sunElevation=-5),
    "a sky with no exposure": lambda d: d["sky"].pop("exposure"),
    "an asset used but not credited": lambda d: d["assets"].pop(0),
    "a credit without its digest": lambda d: d["assets"][0].pop("sha256"),
    "a credit under another license": lambda d: d["assets"][0].update(license="https://example.com/license"),
    "another source": lambda d: d.update(source="somewhere"),
    "another license": lambda d: d.update(license="proprietary"),
    "another builder version": lambda d: d.update(script="hestia_render 0"),
    "no file digests": lambda d: d.pop("files"),
    "a file whose digest does not match": lambda d: d["files"]["sky/sky.png"].update(sha256="1" * 64),
    "credits without a digest": lambda d: d["files"].pop("CREDITS.txt"),
}
for surface in {other_surface}:
    for kind in ("diffuse", "normal", "rough"):
        touch("surfaces/%s/%s.jpg" % (surface, kind))
manifest["files"] = recorded()
for label, change in wrong.items():
    write(remapped(change))
    check("the packaging check refuses " + label, check_library.check(whole) != [])
write(manifest)
check("the packaging check still passes the complete library", check_library.check(whole) == [])
# A file changed after it was recorded is refused.
with open(os.path.join(whole, "sky", "sky.png"), "w") as out:
    out.write("tampered")
check("the packaging check refuses a file changed after it was recorded", check_library.check(whole) != [])

print("ALL OK" if not failures else "%d FAILED" % len(failures))
sys.exit(1 if failures else 0)
