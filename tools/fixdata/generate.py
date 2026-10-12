#!/usr/bin/env python3
"""Builds Resources/Fixes/members.json: the real members of common Python modules
(from every Python on this Mac) and JavaScript globals (from Node, plus the DOM),
so Halo can tell time.slep from time.sleep without guessing.

    python3 tools/fixdata/generate.py
"""
import json, os, re, subprocess

PYTHONS = ["/Library/Frameworks/Python.framework/Versions/3.10/bin/python3",
           "/Library/Frameworks/Python.framework/Versions/3.14/bin/python3",
           "/opt/homebrew/bin/python3", "/usr/bin/python3"]
MODULES = """time os os.path sys json random math re datetime string collections itertools functools subprocess
pathlib shutil glob csv statistics typing copy socket threading asyncio logging argparse uuid hashlib base64
platform decimal fractions heapq bisect operator textwrap timeit turtle tkinter sqlite3 pickle io tempfile zipfile
unittest pprint secrets calendar enum dataclasses contextlib getpass webbrowser signal traceback inspect struct
array queue urllib urllib.request urllib.parse http.client http.server email smtplib ssl select multiprocessing
concurrent.futures cmath numbers abc warnings locale gc weakref atexit codecs unicodedata difflib fnmatch
configparser xml.etree.ElementTree html shlex zlib gzip tarfile sched curses""".split()

PROBE = r'''
import json, importlib, sys
out = {}
for name in sys.argv[1:]:
    try:
        m = importlib.import_module(name)
        out[name] = sorted(set(dir(m)))
    except Exception:
        pass
for name, obj in [("str", str), ("list", list), ("dict", dict), ("set", set), ("tuple", tuple), ("int", int), ("float", float), ("bytes", bytes)]:
    out["@" + name] = sorted(n for n in dir(obj) if not n.startswith("__"))
# Attributes of the objects people actually hold: files, matches, dates, paths…
attrs = set()
import types as _t
samples = []
for spec in ["io.TextIOWrapper", "io.BufferedReader", "io.BufferedWriter", "io.BytesIO", "io.StringIO", "re.Match", "re.Pattern",
             "datetime.datetime", "datetime.date", "datetime.timedelta", "datetime.time", "pathlib.Path", "socket.socket",
             "threading.Thread", "threading.Event", "threading.Lock", "collections.Counter", "collections.deque", "collections.OrderedDict",
             "collections.defaultdict", "subprocess.CompletedProcess", "subprocess.Popen", "logging.Logger", "logging.Handler",
             "argparse.ArgumentParser", "argparse.Namespace", "sqlite3.Connection", "sqlite3.Cursor", "decimal.Decimal", "fractions.Fraction",
             "zipfile.ZipFile", "tarfile.TarFile", "email.message.Message", "http.client.HTTPResponse", "urllib.request.Request",
             "queue.Queue", "asyncio.Task", "asyncio.Future", "asyncio.Queue", "asyncio.Event", "asyncio.AbstractEventLoop",
             "concurrent.futures.Future", "concurrent.futures.ThreadPoolExecutor", "enum.Enum", "unittest.TestCase", "csv.DictReader",
             "csv.DictWriter", "string.Template", "random.Random", "array.array", "memoryview", "range", "slice", "property", "staticmethod",
             "classmethod", "BaseException", "Exception", "OSError", "type", "object", "complex", "frozenset", "bytearray", "tkinter.Tk",
             "tkinter.Canvas", "tkinter.Label", "tkinter.Button", "tkinter.Entry", "tkinter.Frame", "turtle.Turtle", "turtle.Screen"]:
    module, _, name = spec.rpartition(".")
    try:
        obj = getattr(importlib.import_module(module), name) if module else getattr(__import__("builtins"), name)
        attrs.update(dir(obj))
    except Exception:
        pass
# Every class in the probed modules, so their attributes are known too.
for name in sys.argv[1:]:
    try:
        m = importlib.import_module(name)
    except Exception:
        continue
    for attr in dir(m):
        try:
            obj = getattr(m, attr)
        except Exception:
            continue
        if isinstance(obj, type):
            try: attrs.update(dir(obj))
            except Exception: pass
try:
    raise ValueError
except ValueError as error:
    attrs.update(dir(error.__traceback__)); attrs.update(dir(error.__traceback__.tb_frame)); attrs.update(dir(error.__traceback__.tb_frame.f_code))
# Linux- and Windows-only names that a Mac's Python doesn't have.
attrs.update("""epoll EPOLLIN EPOLLOUT EPOLLERR EPOLLHUP EPOLLET EPOLLONESHOT EPOLLRDHUP EPOLLPRI EPOLLEXCLUSIVE devpoll
    sched_setaffinity sched_getaffinity memfd_create pipe2 posix_fadvise getxattr setxattr listxattr removexattr startfile
    O_BINARY O_TEXT O_DIRECT O_PATH SIGRTMIN SIGRTMAX SIGPWR SIGPOLL SIGCLD splice eventfd pidfd_open getrandom""".split())
def _gen(): yield 1
async def _coro(): pass
async def _agen(): yield 1
for sample in [_gen(), _coro(), _agen(), (lambda: 0), _t.SimpleNamespace(), _t.ModuleType("m")]:
    attrs.update(dir(sample))
    try: sample.close()
    except Exception: pass
out["@attrs"] = sorted(attrs)
import builtins, keyword
out["@builtins"] = sorted(n for n in dir(builtins) if not n.startswith("_"))
out["@keywords"] = sorted(keyword.kwlist + getattr(keyword, "softkwlist", []))
print(json.dumps(out))
'''

def python_members():
    merged = {}
    for exe in PYTHONS:
        if not os.path.exists(exe):
            continue
        try:
            raw = subprocess.run([exe, "-c", PROBE, *MODULES], capture_output=True, text=True, timeout=120).stdout
            data = json.loads(raw)
        except Exception as error:
            print("skipped", exe, error)
            continue
        for key, names in data.items():
            merged.setdefault(key, set()).update(names)
        print("probed", exe, len(data), "modules")
    return {k: sorted(v) for k, v in sorted(merged.items())}

NODE_PROBE = r'''
const names = ["Math", "JSON", "Object", "Array", "Number", "String", "Promise", "Date", "Reflect", "Symbol", "Intl", "BigInt", "Boolean", "RegExp", "Error", "Map", "Set", "Proxy"];
const out = {};
for (const n of names) out[n] = Object.getOwnPropertyNames(globalThis[n]).filter(k => !/^\d/.test(k)).sort();
out["@array"] = Object.getOwnPropertyNames(Array.prototype).sort();
out["@string"] = Object.getOwnPropertyNames(String.prototype).sort();
out["@object"] = Object.getOwnPropertyNames(Object.prototype).sort();
out["@map"] = Object.getOwnPropertyNames(Map.prototype).sort();
out["@set"] = Object.getOwnPropertyNames(Set.prototype).sort();
out["@number"] = Object.getOwnPropertyNames(Number.prototype).sort();
out["@promise"] = Object.getOwnPropertyNames(Promise.prototype).sort();
out["@globals"] = Object.getOwnPropertyNames(globalThis).sort();
(typeof print === "function" ? print : console.log)(JSON.stringify(out));
'''
JSC = "/System/Library/Frameworks/JavaScriptCore.framework/Versions/A/Helpers/jsc"

# Node has no DOM: the parts of it people actually type.
DOM = {
    "document": """getElementById getElementsByClassName getElementsByTagName getElementsByName querySelector querySelectorAll
        createElement createElementNS createTextNode createDocumentFragment createComment createEvent addEventListener
        removeEventListener dispatchEvent body head title documentElement cookie forms images links scripts readyState
        activeElement location URL domain referrer write writeln open close hasFocus execCommand getSelection
        elementFromPoint elementsFromPoint importNode adoptNode visibilityState hidden fonts fullscreenElement
        exitFullscreen pointerLockElement exitPointerLock defaultView currentScript characterSet contentType
        lastModified styleSheets onclick onkeydown onkeyup onload onreadystatechange append prepend replaceChildren
        contains firstElementChild lastElementChild children childElementCount""",
    "window": """alert confirm prompt open close print setTimeout clearTimeout setInterval clearInterval requestAnimationFrame
        cancelAnimationFrame addEventListener removeEventListener dispatchEvent location history navigator document
        localStorage sessionStorage innerWidth innerHeight outerWidth outerHeight scrollX scrollY pageXOffset pageYOffset
        scrollTo scrollBy scroll getComputedStyle matchMedia fetch console performance crypto screen devicePixelRatio
        onload onresize onscroll onkeydown onkeyup onclick onerror onbeforeunload onpopstate onhashchange postMessage
        atob btoa structuredClone queueMicrotask indexedDB caches self top parent frames opener name origin isSecureContext
        customElements visualViewport getSelection focus blur stop find""",
    "console": """log error warn info debug table time timeEnd timeLog group groupCollapsed groupEnd trace assert dir
        dirxml count countReset clear profile profileEnd""",
    "localStorage": "getItem setItem removeItem clear key length",
    "sessionStorage": "getItem setItem removeItem clear key length",
    "navigator": """userAgent language languages platform onLine clipboard geolocation mediaDevices serviceWorker
        cookieEnabled hardwareConcurrency maxTouchPoints vendor share canShare vibrate sendBeacon permissions storage""",
    "location": "href protocol host hostname port pathname search hash origin assign reload replace toString ancestorOrigins",
    "history": "back forward go pushState replaceState length state scrollRestoration",
}

def js_members():
    out = {}
    try:
        raw = subprocess.run(["node", "-e", NODE_PROBE], capture_output=True, text=True, timeout=60).stdout
        out = json.loads(raw)
        print("probed node", len(out), "globals")
    except Exception:
        # Node may be missing or broken; macOS always has JavaScriptCore.
        import tempfile
        with tempfile.NamedTemporaryFile("w", suffix=".js", delete=False) as f:
            f.write(NODE_PROBE)
        raw = subprocess.run([JSC, f.name], capture_output=True, text=True, timeout=60).stdout
        out = json.loads(raw)
        print("probed JavaScriptCore", len(out), "globals")
    for name, names in DOM.items():
        out[name] = sorted(set(names.split()))
    return out

def c_known():
    """Every identifier the macOS SDK's C and C++ headers declare, so real libc
    names (strnlen, memchr…) are never mistaken for typos."""
    sdk = subprocess.run(["xcrun", "--show-sdk-path"], capture_output=True, text=True).stdout.strip()
    inc = os.path.join(sdk, "usr", "include")
    names_c, names_cpp = set(), set()
    ident = re.compile(r"\b([A-Za-z_][A-Za-z0-9_]{2,})\b")
    for folder, target in [(inc, names_c), (os.path.join(inc, "sys"), names_c), (os.path.join(inc, "c++", "v1"), names_cpp)]:
        if not os.path.isdir(folder):
            continue
        for name in os.listdir(folder):
            path = os.path.join(folder, name)
            if not os.path.isfile(path) or (folder.endswith("v1") and "." in name and not name.endswith(".h")):
                pass
            if not os.path.isfile(path):
                continue
            try:
                text = open(path, errors="ignore").read()
            except Exception:
                continue
            for m in ident.finditer(text):
                word = m.group(1)
                if not word.startswith("__") and not word.startswith("_LIBCPP") and not word.startswith("_ABI"):
                    target.add(word)
    print("SDK names:", len(names_c), "C,", len(names_cpp), "C++")
    return {"@known": sorted(names_c)}, {"@known": sorted(names_cpp - names_c)}

if __name__ == "__main__":
    c, cpp = c_known()
    data = {"python": python_members(), "javascript": js_members(), "c": c, "cpp": cpp}
    path = os.path.join(os.path.dirname(__file__), "..", "..", "Resources", "Fixes", "members.json")
    with open(path, "w") as f:
        json.dump(data, f, separators=(",", ":"), sort_keys=True)
    print("wrote", os.path.normpath(path), os.path.getsize(path) // 1024, "KB")
