"""Kanso: keeps Downloads, Desktop and Documents sorted, automatically.

Items are sorted by file type into <root>/My Shelves/<Type>; new arrivals also show
up in <root>/Recents for a while, and <root>/Manual Shelves is never touched. A launchd
agent wakes kanso whenever a watched folder changes (and hourly, to expire Recents).
Models only run for unknown types. Every move is journaled so `kanso undo` can put it back.
"""

import argparse
import json
import os
import plistlib
import subprocess
import sys
import time

from . import sorter

LABEL = "com.kanso.agent"
PLIST = sorter.HOME / "Library" / "LaunchAgents" / f"{LABEL}.plist"
LOG = sorter.HOME / "Library" / "Logs" / "kanso.log"


def cmd_run(args, cfg):
    from .brain import Brain

    brain = Brain(cfg)
    after = 0 if args.all else sorter.since()
    if not args.dry_run:
        sorter.clean_recents(cfg)
        sorter.prepare_roots(cfg)
    moved, planned = [], 0
    for _ in range(6):  # items still downloading get a few more chances before the run ends
        moves, young = sorter.plan(cfg, brain, after)
        planned += len(moves)
        for m in moves:
            print(f"{m.item.path}  ->  {m.dest}/  [{m.why}]" + (f"  tags={m.tags}" if m.tags else ""))
        if not args.dry_run:
            moved += sorter.apply(moves, icons=sorter.icons(cfg))
        if args.dry_run or not young:
            break
        time.sleep(cfg["settle_seconds"])
    sorted_n = sum(1 for _, dst, _ in moved if dst.parent.name != cfg["recents_dir"])
    if moved and cfg["notify"] and not sys.stdout.isatty():
        sorter.notify(f"Sorted {sorted_n} item(s)" if sorted_n else f"{len(moved)} new item(s) in {cfg['recents_dir']}")
    print(f"planned {planned}" if args.dry_run else f"moved {len(moved)}")


def cmd_undo(args, cfg):
    for dst, src in sorter.undo(cfg["keep_tag"], recents_dir=cfg["recents_dir"]):
        print(f"{dst}  ->  {src}")


def cmd_install(args, cfg):
    sorter.since()  # everything already there is left alone; `kanso run --all` sorts it
    PLIST.parent.mkdir(parents=True, exist_ok=True)
    LOG.parent.mkdir(parents=True, exist_ok=True)
    with PLIST.open("wb") as f:
        plistlib.dump({
            "Label": LABEL,
            "ProgramArguments": [sys.executable, "-m", "kanso", "run"],
            "WatchPaths": [str(r) for r in cfg["roots"]] + [str(r / cfg["recents_dir"]) for r in cfg["roots"]],
            "StartInterval": 3600,
            "ThrottleInterval": 15,
            "RunAtLoad": True,
            "ProcessType": "Background",
            "StandardOutPath": str(LOG),
            "StandardErrorPath": str(LOG),
        }, f)
    domain = f"gui/{os.getuid()}"
    subprocess.run(["launchctl", "bootout", domain, str(PLIST)], capture_output=True)
    subprocess.run(["launchctl", "bootstrap", domain, str(PLIST)], check=True)
    print(f"Kanso is watching {', '.join(map(str, cfg['roots']))}\n"
          f"Grant Full Disk Access to {os.path.realpath(sys.executable)} in System Settings > "
          f"Privacy & Security, or macOS will block the background agent.\nLog: {LOG}")


def cmd_uninstall(args, cfg):
    subprocess.run(["launchctl", "bootout", f"gui/{os.getuid()}", str(PLIST)], capture_output=True)
    PLIST.unlink(missing_ok=True)
    print("agent removed (config and journal kept in ~/.config/tidy)")


def enabled():
    return subprocess.run(["launchctl", "print", f"gui/{os.getuid()}/{LABEL}"], capture_output=True).returncode == 0


def cmd_roots(args, cfg):
    """Replace the watched folders; re-register the agent so launchd watches the new set."""
    sorter.set_roots([os.path.abspath(os.path.expanduser(p)) for p in args.paths])
    if enabled():
        with open(os.devnull, "w") as quiet:
            sys.stdout, out = quiet, sys.stdout
            try:
                cmd_install(args, sorter.load_config())
            finally:
                sys.stdout = out


def cmd_status(args, cfg):
    from .brain import Brain

    if args.json:
        print(json.dumps({"enabled": enabled(), "roots": [str(r) for r in cfg["roots"]],
                          "apple_intelligence": bool(Brain(cfg).fm()), "python": os.path.realpath(sys.executable),
                          "keep_tag": cfg["keep_tag"]}))
        return
    loaded = enabled()
    print(f"agent: {'running' if loaded else 'not installed'}\nconfig: {sorter.CONFIG}")
    print(f"roots: {', '.join(str(r) for r in cfg['roots'])}")
    print(f"apple intelligence: {'on' if Brain(cfg).fm() else 'off'}")


def cmd_config(args, cfg):
    subprocess.run(["open", "-t", str(sorter.CONFIG)])


def main():
    p = argparse.ArgumentParser(prog="kanso", description=__doc__.splitlines()[0])
    sub = p.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("run", help="sort new items now")
    r.add_argument("--all", action="store_true", help="also sort items that were there before install")
    r.add_argument("--dry-run", action="store_true", help="print the plan, move nothing")
    for name in ("undo", "install", "uninstall", "config"):
        sub.add_parser(name)
    sub.add_parser("status").add_argument("--json", action="store_true")
    sub.add_parser("roots", help="set the folders to sort").add_argument("paths", nargs="+")
    args = p.parse_args()
    cfg = sorter.load_config()
    globals()[f"cmd_{args.cmd}"](args, cfg)
