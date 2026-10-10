# Offline checks of hestia_render.py's download boundary. Run with Blender, which provides bpy:
#
#   blender -b --factory-startup --python-exit-code 1 --python tools/blender/test_hestia_render.py
#
# Exits non-zero when any check fails. Needs no network: downloads are served by a stand-in opener.

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
    if os.path.exists(os.path.join(root, "..", "evil.bin")):
        failures.append("wrote outside the cache")
        print("FAIL: wrote outside the cache")
    else:
        print("ok: nothing written outside the cache")

    # Downloads, offline: a stand-in opener serves bytes as Poly Haven would.
    import hashlib
    import io
    import urllib.request

    class Response(io.BytesIO):
        def __init__(self, data, url):
            super().__init__(data)
            self.url = url

        def geturl(self):
            return self.url

    class Opener:
        def __init__(self, data, final_url=None):
            self.data, self.final_url = data, final_url

        def open(self, request, timeout=None):
            return Response(self.data, self.final_url or request.full_url)

    def check(label, condition):
        if condition:
            print("ok:", label)
        else:
            failures.append(label)
            print("FAIL:", label)

    def partials(directory):
        return [name for name in os.listdir(directory) if name.endswith(".part")] if os.path.isdir(directory) else []

    fetch, download = namespace["fetch"], namespace["download"]
    body = b"hestia test bytes" * 100
    entry = {"url": "https://dl.polyhaven.org/file/a.jpg", "size": len(body), "md5": hashlib.md5(body).hexdigest()}
    folder = os.path.join(root, "textures", "A")

    redirects = namespace["CheckedRedirects"]()
    request = urllib.request.Request("https://dl.polyhaven.org/a.jpg")
    refused("a redirect to another host, before it is followed",
            lambda: redirects.redirect_request(request, None, 302, "Found", {}, "https://example.com/a.jpg"))
    check("a redirect within Poly Haven is followed",
          redirects.redirect_request(request, None, 302, "Found", {}, "https://dl.polyhaven.org/b.jpg") is not None)
    refused("a final URL on another host",
            lambda: fetch(entry, root, "textures", "A", "a.jpg", opener=Opener(body, "https://example.com/a.jpg")))
    check("no partial left after a refused final URL", partials(folder) == [])

    outside = os.path.join(tempfile.mkdtemp(), "victim.txt")
    with open(outside, "w") as handle:
        handle.write("untouched")
    os.makedirs(folder, exist_ok=True)
    os.symlink(outside, os.path.join(folder, "a.jpg.part"))
    os.symlink(outside, os.path.join(folder, "b.jpg"))
    path = fetch(entry, root, "textures", "A", "a.jpg", opener=Opener(body))
    check("a planted symlink at the old fixed partial name is never written through",
          open(outside).read() == "untouched")
    check("the download landed as a regular file", os.path.isfile(path) and not os.path.islink(path)
          and open(path, "rb").read() == body)
    os.remove(os.path.join(folder, "a.jpg.part"))  # The planted link, so later checks see only what renders leave.
    refused("a destination that is a symlink out of the cache",
            lambda: fetch(entry, root, "textures", "A", "b.jpg", opener=Opener(body)))
    check("the symlink's target was not written", open(outside).read() == "untouched")
    shutil.rmtree(os.path.dirname(outside))

    first, second = namespace["partial_file"](folder), namespace["partial_file"](folder)
    check("two renders get different partial files", first[1] != second[1])
    for descriptor, name in (first, second):
        os.close(descriptor)
        os.remove(name)

    refused("a streamed response over the ceiling",
            lambda: download("https://dl.polyhaven.org/big.bin", os.path.join(folder, "big.bin"), 1000,
                             opener=Opener(b"x" * 5000)))
    check("no partial or file left after an over-ceiling stream",
          partials(folder) == [] and not os.path.exists(os.path.join(folder, "big.bin")))
    refused("a size mismatch", lambda: fetch(dict(entry, size=len(body) + 1), root, "textures", "A", "c.jpg",
                                             opener=Opener(body)))
    refused("an MD5 mismatch", lambda: fetch(dict(entry, md5="0" * 32), root, "textures", "A", "d.jpg",
                                             opener=Opener(body)))
    check("no partial or file left after a size or MD5 mismatch",
          partials(folder) == [] and not os.path.exists(os.path.join(folder, "c.jpg"))
          and not os.path.exists(os.path.join(folder, "d.jpg")))
    for missing in ("size", "md5", "url"):
        partial_entry = {key: value for key, value in entry.items() if key != missing}
        refused("an asset entry without a declared " + missing,
                lambda partial_entry=partial_entry: fetch(partial_entry, root, "textures", "A", "e.jpg",
                                                          opener=Opener(body)))
except Exception as error:  # An unexpected exception is a failed check, not a crash that exits zero.
    failures.append("unexpected %r" % error)
    print("FAIL: unexpected", repr(error))
finally:
    shutil.rmtree(root)

print("ALL OK" if not failures else "FAILURES: %d" % len(failures))
sys.exit(1 if failures else 0)
