# Offline checks of hestia_render.py's download boundary. Run with Blender, which provides bpy:
#
#   blender -b --factory-startup --python tools/blender/test_hestia_render.py
#
# Exits non-zero on the first failure. Needs no network: every case is refused before anything is fetched.

import json
import os
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SOURCE = open(os.path.join(HERE, "hestia_render.py")).read().replace("\nmain()\n", "\n")
namespace = {"__name__": "hestia_render"}
exec(compile(SOURCE, "hestia_render.py", "exec"), namespace)
DownloadError = namespace["DownloadError"]
failures = []


def refused(label, action):
    try:
        action()
    except DownloadError:
        print("ok: refused", label)
        return
    failures.append(label)
    print("FAIL: accepted", label)


root = tempfile.mkdtemp()
try:
    inside, checked_url, asset_name = namespace["inside"], namespace["checked_url"], namespace["asset_name"]
    refused("an absolute cache path", lambda: inside(root, "/etc/passwd"))
    refused("a cache path that climbs out", lambda: inside(root, "models", "x", "..", "..", "evil"))
    refused("plain HTTP", lambda: checked_url("http://dl.polyhaven.org/a.jpg"))
    refused("another host", lambda: checked_url("https://example.com/a.jpg"))
    refused("a host suffix trick", lambda: checked_url("https://dl.polyhaven.org.example.com/a.jpg"))
    refused("credentials in the URL", lambda: checked_url("https://u:p@dl.polyhaven.org/a.jpg"))
    refused("an asset name with a path", lambda: asset_name("../evil"))
    os.makedirs(os.path.join(root, "index"))
    for name, include in (("Climb", "../../../evil.bin"), ("Absolute", "/tmp/evil.bin"), ("Dot", "./x/../../e")):
        with open(os.path.join(root, "index", name + ".json"), "w") as handle:
            json.dump({"gltf": {"1k": {"gltf": {"url": "https://dl.polyhaven.org/a.gltf", "size": 1, "md5": "0",
                                                "include": {include: {"url": "https://dl.polyhaven.org/e.bin",
                                                                      "size": 1, "md5": "0"}}}}}}, handle)
        refused("a model include path " + include, lambda name=name: namespace["model_file"](name, root))
    refused("a file declared over the ceiling",
            lambda: namespace["fetch"]({"url": "https://dl.polyhaven.org/big.hdr",
                                        "size": namespace["FILE_LIMIT"] + 1, "md5": "0"}, root, "hdri", "big.hdr"))
    print("ok: nothing written outside the cache" if not os.path.exists(os.path.join(root, "..", "evil.bin"))
          else "FAIL: wrote outside the cache")
finally:
    shutil.rmtree(root)

print("ALL OK" if not failures else "FAILURES: %d" % len(failures))
sys.exit(1 if failures else 0)
