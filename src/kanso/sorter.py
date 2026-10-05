"""Scan roots, decide where each item goes, move it, tag it, journal it."""

import fnmatch
import json
import os
import plistlib
import re
import shutil
import subprocess
import time
import tomllib
import uuid
from dataclasses import dataclass, field
from pathlib import Path

HOME = Path.home()
CONFIG_DIR = HOME / ".config" / "kanso"
CONFIG = CONFIG_DIR / "config.toml"
JOURNAL = CONFIG_DIR / "journal.jsonl"
STATE = CONFIG_DIR / "state.json"
LEARNED = CONFIG_DIR / "learned.json"  # types Apple Intelligence created for unknown extensions
DEFAULT_CONFIG = Path(__file__).with_name("default_config.toml")

UNSORTED = "Unsorted"
SCREENSHOTS = "Screenshots"
PARTIAL = (".crdownload", ".download", ".part", ".partial", ".opdownload", ".tmp")
TAGS_XATTR = "com.apple.metadata:_kMDItemUserTags"


@dataclass
class Item:
    path: Path
    root: Path
    where_from: list = field(default_factory=list)
    screenshot: bool = False

    @property
    def ext(self):
        return self.path.suffix.lower().lstrip(".")


@dataclass
class Move:
    item: Item
    dest: Path  # directory
    tags: list
    why: str
    link: Path | None = None  # Recents folder to leave a symlink in (recents = "links")


# --- config & state ---------------------------------------------------------

def load_config(path=CONFIG):
    if not path.exists():
        path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy(DEFAULT_CONFIG, path)
    cfg = tomllib.loads(path.read_text())
    cfg["roots"] = [Path(os.path.expanduser(r)) for r in cfg["roots"]]
    cfg.setdefault("rules", [])
    for ext, t in learned().items():
        cfg["categories"].setdefault(t["type"], {"emoji": t["emoji"], "description": t["description"], "match": []})
        cfg["categories"][t["type"]].setdefault("match", []).append(ext)
    return cfg


def learned(path=None):
    try:
        return json.loads((path or LEARNED).read_text())
    except (OSError, ValueError):
        return {}


def learn(cfg, ext, name, emoji, description, path=None):
    """Remember a type the model chose or created for an extension, so it's decided without a model next time."""
    c = cfg["categories"].setdefault(name, {"emoji": emoji, "description": description, "match": []})
    c.setdefault("match", []).append(ext)
    path = path or LEARNED
    data = learned(path)
    data[ext] = {"type": name, "emoji": c.get("emoji", emoji), "description": c.get("description", description)}
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=1, ensure_ascii=False))


def set_roots(paths, path=CONFIG):
    """Rewrite the `roots = [...]` line, keeping the rest of the user's config (and comments) intact."""
    home = str(HOME)
    roots = [("~" + p[len(home):]) if p.startswith(home + "/") else p for p in map(str, paths)]
    text = path.read_text()
    # a JSON array of strings is also a valid TOML array
    new, n = re.subn(r"^roots\s*=\s*\[[^\]]*\]", lambda _: "roots = " + json.dumps(roots), text, count=1, flags=re.M)
    path.write_text(new if n else f"roots = {json.dumps(roots)}\n{text}")


def since(state=STATE):
    """Auto mode only touches items that arrived after Kanso was first set up."""
    try:
        return json.loads(state.read_text())["since"]
    except (OSError, ValueError, KeyError):
        state.parent.mkdir(parents=True, exist_ok=True)
        state.write_text(json.dumps({"since": time.time()}))
        return time.time()


# --- file metadata (xattrs, not Spotlight: mdls is unavailable to sandboxed/background processes) ---

def read_plist_xattr(path, name):
    r = subprocess.run(["/usr/bin/xattr", "-px", name, str(path)], capture_output=True, text=True)
    if r.returncode:
        return None
    try:
        return plistlib.loads(bytes.fromhex("".join(r.stdout.split())))
    except Exception:
        return None


def read_tags(path):
    return read_plist_xattr(path, TAGS_XATTR) or []


def write_tags(path, tags):
    """Merge Finder tags. Stored as a binary plist of 'Name' or 'Name\\n<color>' strings."""
    old = read_tags(path)
    names = {t.split("\n")[0] for t in old}
    merged = old + [t for t in dict.fromkeys(tags) if t and t not in names]
    data = plistlib.dumps(merged, fmt=plistlib.FMT_BINARY).hex()
    subprocess.run(["/usr/bin/xattr", "-wx", TAGS_XATTR, data, str(path)], check=True)


def inspect(path, root):
    """Metadata only; file contents are never opened (so iCloud placeholders never download)."""
    item = Item(path, root)
    item.where_from = read_plist_xattr(path, "com.apple.metadata:kMDItemWhereFroms") or []
    item.screenshot = read_plist_xattr(path, "com.apple.metadata:kMDItemIsScreenCapture") is not None
    return item


# --- scanning ---------------------------------------------------------------

def managed_names(cfg):
    return {cfg["library"], cfg["manual_library"], cfg["recents_dir"]}


def ignored(path, keep_tag):
    n = path.name
    return (n.startswith((".", "~$")) or n.lower().endswith(PARTIAL) or n == "Icon\r"
            or any(t.split("\n")[0] == keep_tag for t in read_tags(path)))


def candidates(cfg, after, now):
    """Return ([(path, root, stage, fresh)], young). stage is 'recent' (park in Recents, hold mode) or 'sort';
    fresh = arrived within recent_days. young counts items skipped because they are still changing."""
    recent_s = cfg["recent_days"] * 86400
    hold = cfg["recents"] == "hold"
    managed = managed_names(cfg)
    young = 0
    out = []
    for root in cfg["roots"]:
        if not root.is_dir():
            continue
        entries = [(p, False) for p in root.iterdir() if p.name not in managed]
        if hold and (root / cfg["recents_dir"]).is_dir():
            entries += [(p, True) for p in (root / cfg["recents_dir"]).iterdir() if not p.is_symlink()]
        for p, in_recent in entries:
            try:
                st = p.lstat()
            except OSError:
                continue
            if not in_recent and st.st_ctime < after:  # ctime changes when an item is moved/renamed in
                continue
            if p.is_dir() and not ext_category(cfg, p.suffix.lower().lstrip(".")):  # bundles like .app count as files
                if not cfg.get("sort_folders") or (p / ".git").exists():
                    continue
            if ignored(p, cfg["keep_tag"]):
                continue
            if now - max(st.st_mtime, st.st_ctime) < cfg["settle_seconds"]:
                young += 1
                continue
            fresh = now - st.st_ctime < recent_s
            if hold and fresh:
                if not in_recent:
                    out.append((p, root, "recent", fresh))
            else:
                out.append((p, root, "sort", fresh))
    return out, young


# --- deciding ---------------------------------------------------------------

def ext_category(cfg, ext):
    for name, c in cfg["categories"].items():
        if ext and ext in c.get("match", []):
            return name
    return None


def rule_matches(rule, item):
    if "when" in rule:
        return False  # natural-language rules are judged by the brain
    if "glob" in rule and not fnmatch.fnmatch(item.path.name.lower(), rule["glob"].lower()):
        return False
    if "ext" in rule and item.ext not in [e.lower().lstrip(".") for e in rule["ext"]]:
        return False
    if "from" in rule and not any(rule["from"].lower() in u.lower() for u in item.where_from):
        return False
    return any(k in rule for k in ("glob", "ext", "from"))


def resolve(cfg, root, dest):
    """'Images' -> <root>/My Shelves/Images. Absolute or ~ paths are used as-is."""
    if dest.startswith(("~", "/")):
        return Path(os.path.expanduser(dest))
    return root.joinpath(cfg["library"], *[p for p in dest.split("/") if p])


def decide(cfg, item, brain):
    """Return (dest, tags, why). dest is a type ('Images'), a path inside the library, or an absolute path."""
    for rule in cfg["rules"]:
        if rule_matches(rule, item):
            return rule["dest"], list(rule.get("tags", [])), f"rule {rule.get('glob') or rule.get('from') or rule.get('ext')}"
    if item.screenshot and SCREENSHOTS in cfg["categories"]:
        return SCREENSHOTS, [], "screenshot"
    return brain.classify(item, ext_category(cfg, item.ext))


def plan(cfg, brain, after, now=None):
    now = now or time.time()
    found, young = candidates(cfg, after, now)
    moves = []
    for path, root, stage, fresh in found:
        if stage == "recent":
            moves.append(Move(Item(path, root), root / cfg["recents_dir"], [], "new"))
            continue
        try:
            item = inspect(path, root)
            dest, tags, why = decide(cfg, item, brain)
        except Exception as e:  # one bad file must not stop the run
            print(f"skip {path}: {e}")
            continue
        link = root / cfg["recents_dir"] if cfg["recents"] == "links" and fresh else None
        moves.append(Move(item, resolve(cfg, root, dest), tags if cfg["tag"] else [], why, link))
    return moves, young


# --- acting -----------------------------------------------------------------

def unique(path):
    n, stem, suffix = 2, path.stem, path.suffix
    while path.exists() or path.is_symlink():
        path = path.with_name(f"{stem} {n}{suffix}")
        n += 1
    return path


def icons(cfg):
    """{folder name: emoji} for every folder Kanso creates, or {} when folder_icons is off."""
    if not cfg["folder_icons"]:
        return {}
    out = {n: c["emoji"] for n, c in cfg["categories"].items() if c.get("emoji")}
    return out | {cfg["library"]: "✨", cfg["manual_library"]: "🏠", cfg["recents_dir"]: "🆕"}


def make_dir(path, icons):
    """mkdir -p, giving each newly created folder its emoji icon."""
    missing = [p for p in [path, *path.parents] if not p.exists()][::-1]
    path.mkdir(parents=True, exist_ok=True)
    for p in missing:
        if p.name in icons:
            set_folder_icon(p, icons[p.name])


# Draws the emoji over the system folder icon and sets it as the folder's Finder icon (writes "Icon\r").
ICON_JXA = """
ObjC.import('AppKit');
function run(argv) {
  const [path, emoji] = argv, size = 512;
  const img = $.NSImage.alloc.initWithSize($.NSMakeSize(size, size));
  img.lockFocus;
  $.NSWorkspace.sharedWorkspace.iconForFileType('public.folder')
    .drawInRectFromRectOperationFraction($.NSMakeRect(0, 0, size, size), $.NSZeroRect, $.NSCompositingOperationSourceOver, 1);
  const text = $(emoji), attrs = $.NSDictionary.dictionaryWithObjectForKey($.NSFont.systemFontOfSize(size * 0.42), $.NSFontAttributeName);
  const s = text.sizeWithAttributes(attrs);
  text.drawAtPointWithAttributes($.NSMakePoint((size - s.width) / 2, size * 0.40 - s.height / 2), attrs);
  img.unlockFocus;
  return $.NSWorkspace.sharedWorkspace.setIconForFileOptions(img, path, 0);
}
"""


def set_folder_icon(path, emoji):
    subprocess.run(["/usr/bin/osascript", "-l", "JavaScript", "-e", ICON_JXA, str(path), emoji], capture_output=True)


def prepare_roots(cfg):
    """Create each root's My Shelves, Manual Shelves and Recents (with icons) so they're there from the start."""
    ic = icons(cfg)
    for root in cfg["roots"]:
        if root.is_dir():
            names = [cfg["library"], cfg["manual_library"]] + ([cfg["recents_dir"]] if cfg["recents"] != "off" else [])
            for n in names:
                make_dir(root / n, ic)


def clean_recents(cfg, now=None):
    """Drop Recents symlinks older than recent_days or whose file is gone. Real files there are left alone."""
    now = now or time.time()
    for root in cfg["roots"]:
        d = root / cfg["recents_dir"]
        if not d.is_dir():
            continue
        for p in d.iterdir():
            if p.is_symlink() and (not p.exists() or now - p.lstat().st_mtime >= cfg["recent_days"] * 86400):
                p.unlink()


def apply(moves, journal=JOURNAL, icons=None):
    icons = icons or {}
    run = uuid.uuid4().hex[:8]
    done = []
    journal.parent.mkdir(parents=True, exist_ok=True)
    for m in moves:
        src = m.item.path
        if m.dest == src.parent:
            continue
        try:
            make_dir(m.dest, icons)
            dst = unique(m.dest / src.name)
            shutil.move(src, dst)
        except (OSError, shutil.Error) as e:
            print(f"failed {src}: {e}")
            continue
        entry = {"run": run, "src": str(src), "dst": str(dst), "ts": time.time()}
        if m.link:
            try:
                make_dir(m.link, icons)
                link = unique(m.link / dst.name)
                link.symlink_to(dst)
                entry["link"] = str(link)
            except OSError as e:
                print(f"no Recents link for {dst}: {e}")
        with journal.open("a") as f:  # journal each move as it happens so undo survives a crash
            f.write(json.dumps(entry) + "\n")
        if m.tags:
            try:
                write_tags(dst, m.tags)
            except subprocess.CalledProcessError:
                pass
        done.append((src, dst, m))
    return done


def undo(keep_tag, journal=JOURNAL, recents_dir="Recents"):
    """Revert the most recent run. Restored items get the keep tag so Kanso leaves them alone."""
    if not journal.exists():
        return []
    entries = [json.loads(l) for l in journal.read_text().splitlines() if l.strip()]
    if not entries:
        return []
    run = entries[-1]["run"]
    restored = []
    for e in reversed([e for e in entries if e["run"] == run]):
        dst, src = Path(e["dst"]), Path(e["src"])
        if "link" in e and Path(e["link"]).is_symlink():
            Path(e["link"]).unlink()
        if dst.exists() and not src.exists():
            src.parent.mkdir(parents=True, exist_ok=True)
            shutil.move(dst, src)
            if src.parent.name != recents_dir:
                write_tags(src, [keep_tag])
            restored.append((dst, src))
    journal.write_text("".join(json.dumps(e) + "\n" for e in entries if e["run"] != run))
    return restored


def notify(text):
    script = f'display notification {json.dumps(text)} with title "Kanso"'
    subprocess.run(["/usr/bin/osascript", "-e", script], capture_output=True)
