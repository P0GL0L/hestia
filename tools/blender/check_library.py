# Checks a built Hestia asset library before it is packaged into the app. Plain Python, no Blender:
#
#   python3 tools/blender/check_library.py LIBRARY_FOLDER
#
# Exits non-zero, listing every problem, unless the library is complete and holds every file it names: the
# library.json, itself a regular file, at the version the app reads, not a partial (--only) build; a surface for
# every textured look with all three maps and a model for every catalog item, each the very asset, tile, fit,
# turn, and file hestia_render.py's tables name for it, at a size a real piece could be, its maps at their
# canonical names; the sky the renderer's photo, laid out for SceneKit with its sun where the builder turns it;
# and its provenance whole: Poly Haven as source, CC0 as license, the builder's version, every asset it uses
# credited with its download URL, size, and SHA-256, and every file it holds (CREDITS.txt included) recorded with
# its size and SHA-256, which must match. Every named file must be a regular, non-empty file inside the folder,
# reached through no link. hestia_library.py runs the same check before it writes library.json, and build-app.sh
# runs it on whatever library it is about to copy.

import ast
import hashlib
import json
import math
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
LIBRARY_VERSION = 1


SOURCE = "Poly Haven (https://polyhaven.com), CC0"


def constants(path, names):
    """Top-level constants from a script's source, read without running it."""
    tree = ast.parse(open(path).read())
    found = {}
    for node in tree.body:
        if isinstance(node, ast.Assign) and len(node.targets) == 1 and isinstance(node.targets[0], ast.Name):
            if node.targets[0].id in names:
                found[node.targets[0].id] = ast.literal_eval(node.value)
    return found


def renderer_tables(path=os.path.join(HERE, "hestia_render.py")):
    """TEXTURES and MODELS from the photo renderer's source, read without running it."""
    tables = constants(path, ("TEXTURES", "MODELS"))
    return tables["TEXTURES"], tables["MODELS"]


def expected():
    """What a library's provenance and sky must say: the renderer's photo, license, and version, and the bearing
    the builder turns the sun to."""
    found = constants(os.path.join(HERE, "hestia_render.py"), ("HDRI", "LICENSE_URL", "SCRIPT_VERSION"))
    found.update(constants(os.path.join(HERE, "hestia_library.py"), ("SUN_AZIMUTH",)))
    return found


def digest(path):
    """A file's size and SHA-256."""
    hasher = hashlib.sha256()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            hasher.update(block)
    return os.path.getsize(path), hasher.hexdigest()


def number(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def provenance_problems(library, out, want, named):
    """A complete library's source, license, version, credits, sky, and file digests, against `want`."""
    problems = []
    if library.get("source") != SOURCE:
        problems.append("the library's source is %r, not %r" % (library.get("source"), SOURCE))
    if library.get("license") != want["LICENSE_URL"]:
        problems.append("the library's license is %r, not %s" % (library.get("license"), want["LICENSE_URL"]))
    if library.get("script") != want["SCRIPT_VERSION"]:
        problems.append("the library was built by %r, not %s" % (library.get("script"), want["SCRIPT_VERSION"]))
    if not isinstance(library.get("blender"), str) or not library.get("blender"):
        problems.append("the library does not say which Blender built it")
    # Every asset it uses credited, with where it came from and what was downloaded.
    credits = library.get("assets")
    credited = set()
    if not isinstance(credits, list):
        problems.append("the library credits no assets")
        credits = []
    for credit in credits:
        if not isinstance(credit, dict):
            problems.append("an asset credit is not a table")
            continue
        name = credit.get("asset")
        if not (isinstance(credit.get("url"), str) and credit["url"].startswith("https://")
                and credit.get("license") == want["LICENSE_URL"]
                and isinstance(credit.get("sha256"), str) and re.fullmatch(r"[0-9a-f]{64}", credit["sha256"])
                and isinstance(credit.get("declaredSize"), int) and credit["declaredSize"] > 0):
            problems.append("the credit for %r lacks its URL, CC0 license, SHA-256, or size" % (name,))
            continue
        credited.add(name)
    used = {entry.get("asset") for entry in library.get("surfaces", {}).values() if isinstance(entry, dict)}
    used |= {entry.get("asset") for entry in library.get("models", {}).values() if isinstance(entry, dict)}
    if isinstance(library.get("sky"), dict):
        used.add(library["sky"].get("asset"))
    for name in sorted(str(item) for item in used - credited):
        problems.append("asset %s is used but not credited" % name)
    # The sky: the renderer's photo, its sun turned to the builder's bearing, at a sane height and exposure.
    sky = library.get("sky")
    if isinstance(sky, dict):
        if sky.get("asset") != want["HDRI"]:
            problems.append("the sky is %r, not the renderer's %s" % (sky.get("asset"), want["HDRI"]))
        if sky.get("sunAzimuth") != want["SUN_AZIMUTH"]:
            problems.append("the sky's sun bearing is %r, not %r" % (sky.get("sunAzimuth"), want["SUN_AZIMUTH"]))
        if not (number(sky.get("sunElevation")) and 8 <= sky["sunElevation"] <= 90):
            problems.append("the sky's sun elevation %r is not between 8 and 90 degrees" % (sky.get("sunElevation"),))
        if not (number(sky.get("exposure")) and 0 < sky["exposure"] < 100):
            problems.append("the sky's exposure %r is not a positive number" % (sky.get("exposure"),))
    # Every file recorded with its size and digest, and each matching.
    files = library.get("files")
    if not isinstance(files, dict):
        return problems + ["the library records no file digests"]
    for relative in sorted(set(named) | {"CREDITS.txt"}):
        record = files.get(relative)
        path = os.path.join(out, relative)
        if not isinstance(record, dict):
            problems.append("%s has no recorded size and digest" % relative)
        elif os.path.islink(path) or not os.path.isfile(path):
            problems.append("%s is not a file in the library" % relative)
        elif (record.get("bytes"), record.get("sha256")) != digest(path):
            problems.append("%s does not match its recorded size and digest" % relative)
    return problems


def validate(library, out, complete, textures, models, want=None):
    """Every problem with a library: for a complete one, a surface for every textured look with all three maps,
    a model for every catalog item, and the sky; for any, every file it names present, a regular file inside
    the library folder reached through no link, and not empty."""
    problems = []
    root = os.path.realpath(out)
    surfaces, items = library.get("surfaces", {}), library.get("models", {})
    if not isinstance(surfaces, dict) or not isinstance(items, dict):
        return ["the library's surfaces and models are not tables"]
    if complete:
        for look in sorted(textures):
            entry = surfaces.get(look, {})
            maps = entry.get("maps", {}) if isinstance(entry, dict) else {}
            missing = [kind for kind in ("diffuse", "normal", "rough") if kind not in maps]
            if look not in surfaces or missing:
                problems.append("surface %s is missing %s" % (look, ", ".join(missing) or "entirely"))
                continue
            problems += mapping_problems_surface(look, entry, textures[look])
        for item in sorted(models):
            if item not in items:
                problems.append("catalog item %s has no model" % item)
                continue
            problems += mapping_problems_model(item, items[item], models[item])
        if "sky" not in library:
            problems.append("the sky is missing")
        elif library["sky"].get("file") != "sky/sky.png" or library["sky"].get("layout") != "scenekit":
            problems.append("the sky is not sky/sky.png laid out for SceneKit")
    named = [path for entry in surfaces.values() for path in entry.get("maps", {}).values()]
    named += [entry.get("file", "") for entry in items.values()]
    if "sky" in library:
        named.append(library["sky"].get("file", ""))
    for relative in sorted(set(named)):
        if not isinstance(relative, str) or not relative or relative.startswith("/") or ".." in relative.split("/"):
            problems.append("%r is not a path inside the library" % (relative,))
            continue
        path = os.path.join(out, relative)
        real = os.path.realpath(path)
        linked = any(os.path.islink(os.path.join(out, *relative.split("/")[:depth]))
                     for depth in range(1, len(relative.split("/")) + 1))
        if linked or not real.startswith(root + os.sep) or not os.path.isfile(path):
            problems.append("%s is not a file in the library" % relative)
        elif os.path.getsize(path) == 0:
            problems.append("%s is empty" % relative)
    if complete:
        safe = [relative for relative in set(named) if isinstance(relative, str) and relative
                and not relative.startswith("/") and ".." not in relative.split("/")]
        problems += provenance_problems(library, out, want or expected(), safe)
    return problems


def mapping_problems_surface(look, entry, expected):
    """A surface whose asset, tile, or map files are not the ones the renderer's table names for its look."""
    asset, tile = expected
    problems = []
    if entry.get("asset") != asset:
        problems.append("surface %s is %r, not %s" % (look, entry.get("asset"), asset))
    if entry.get("tile") != tile:
        problems.append("surface %s tiles every %r m, not %r" % (look, entry.get("tile"), tile))
    for kind, path in sorted(entry.get("maps", {}).items()):
        if path != "surfaces/%s/%s.jpg" % (asset, kind):
            problems.append("surface %s %s map %r is not surfaces/%s/%s.jpg" % (look, kind, path, asset, kind))
    return problems


def mapping_problems_model(item, entry, expected):
    """A model whose asset, fit, turn, file, or size is not what the renderer's table names for its item."""
    asset, fit, turn = expected
    problems = []
    if not isinstance(entry, dict):
        return ["catalog item %s's model is not a table" % item]
    if entry.get("asset") != asset or entry.get("file") != "models/%s.usdz" % asset:
        problems.append("catalog item %s maps to %r, not %s" % (item, entry.get("file"), "models/%s.usdz" % asset))
    if entry.get("fit") != fit or entry.get("turn") != turn:
        problems.append("catalog item %s fits %r turned %r, not %s turned %r"
                        % (item, entry.get("fit"), entry.get("turn"), fit, turn))
    size = entry.get("size")
    # Meters: from a 1 cm part to a 50 m tree.
    if not (isinstance(size, list) and len(size) == 3 and all(number(v) and 0.01 <= v <= 50 for v in size)):
        problems.append("catalog item %s has no size a real piece could be: %r" % (item, size))
    return problems


def check(folder):
    """Every problem with the library in `folder`, as packaged: complete, current, and whole."""
    manifest = os.path.join(folder, "library.json")
    if os.path.islink(manifest) or not os.path.isfile(manifest):
        return ["library.json is not a file in the library"]
    try:
        with open(manifest) as handle:
            library = json.load(handle)
    except (OSError, ValueError) as error:
        return ["library.json cannot be read: %s" % error]
    problems = []
    if library.get("version") != LIBRARY_VERSION:
        problems.append("library version %r is not %d" % (library.get("version"), LIBRARY_VERSION))
    if library.get("partial"):
        problems.append("the library is a partial (--only) build")
    textures, models = renderer_tables()
    return problems + validate(library, folder, True, textures, models)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: check_library.py LIBRARY_FOLDER")
    found = check(sys.argv[1])
    for problem in found:
        print("library problem:", problem, file=sys.stderr)
    sys.exit(1 if found else 0)
