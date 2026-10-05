import json
import plistlib
import subprocess
import tempfile
import time
import tomllib
import unittest
from pathlib import Path
from types import SimpleNamespace as NS

from kanso import sorter
from kanso.brain import Brain


def config(root, **over):
    cfg = tomllib.loads(sorter.DEFAULT_CONFIG.read_text())
    cfg.update({"roots": [root], "recent_days": 0, "apple_intelligence": False, "rules": [], **over})
    return cfg


class FakeVon:
    """Stands in for the von module: returns canned answers, records the questions."""

    def __init__(self, choice="Finance", confidence=0.6, noul=0.1):
        self.a = NS(choice=choice, confidence=confidence, noul=noul)
        self.questions = None

    def choice(self, instructions, criteria):
        return ("choice", criteria)

    def noul(self, instructions):
        return ("noul", instructions)

    def system_one(self, state, questions):
        self.questions = questions
        return NS(answers={k: self.a for k in questions})


class NoVon:
    def system_one(self, **_):
        raise AssertionError("von must not run when Apple Intelligence answered")


class FakeAI(Brain):
    """Apple Intelligence 'available' and answering `pick` (None = model failed); `new` = (name, emoji, description)."""

    def __init__(self, cfg, pick, von=None, new=("", "", "")):
        super().__init__(cfg)
        self._fm, self._von, self.pick, self.new, self.options, self.calls = True, von or NoVon(), pick, new, None, 0

    def _fm_choose(self, item, options, creating):
        self.options, self.creating = options, creating
        self.calls += 1
        return self.pick and NS(folder=self.pick, name=self.new[0], emoji=self.new[1], description=self.new[2])


class KansoTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name) / "Downloads"
        self.root.mkdir()
        self.journal = Path(self.tmp.name) / "journal.jsonl"
        self.later = time.time() + 3600  # everything is settled an hour from now
        self.lib = self.root / "My Shelves"
        self.icons = []
        self._patch = sorter.set_folder_icon, sorter.LEARNED
        sorter.set_folder_icon = lambda path, emoji: self.icons.append((path.name, emoji))
        sorter.LEARNED = Path(self.tmp.name) / "learned.json"

    def tearDown(self):
        sorter.set_folder_icon, sorter.LEARNED = self._patch
        self.tmp.cleanup()

    def touch(self, name, text="x"):
        p = self.root / name
        p.write_text(text)
        return p

    def plan(self, cfg, von=None):
        brain = Brain(cfg)
        brain._von = von or FakeVon()
        return sorter.plan(cfg, brain, after=0, now=self.later)

    def test_skips_hidden_partial_office_lock_and_unsettled(self):
        for n in [".DS_Store", "movie.mp4.crdownload", "~$report.docx", "big.zip"]:
            self.touch(n)
        moves, _ = self.plan(config(self.root))
        self.assertEqual([m.item.path.name for m in moves], ["big.zip"])
        _, young = sorter.plan(config(self.root), Brain(config(self.root)), after=0, now=time.time())
        self.assertEqual(young, 1)

    def test_items_older_than_install_are_left_alone(self):
        self.touch("old.zip")
        found, _ = sorter.candidates(config(self.root), after=time.time() + 60, now=self.later)
        self.assertEqual(found, [])

    def test_hold_mode_parks_new_files_in_recents_then_sorts(self):
        self.touch("a.zip")
        cfg = config(self.root, recents="hold", recent_days=1)
        (m,), _ = sorter.plan(cfg, Brain(cfg), after=0, now=time.time() + 60)
        self.assertEqual(m.dest, self.root / "Recents")
        sorter.apply([m], self.journal)
        (m,), _ = sorter.plan(cfg, Brain(cfg), after=0, now=time.time() + 2 * 86400)
        self.assertEqual(m.dest, self.lib / "Archives")

    def test_links_mode_sorts_now_links_in_recents_expires_and_undoes(self):
        self.touch("a.zip")
        cfg = config(self.root, recent_days=7)
        moves, _ = sorter.plan(cfg, Brain(cfg), after=0, now=time.time() + 60)
        (_, dst, _), = sorter.apply(moves, self.journal, icons=sorter.icons(cfg))
        link = self.root / "Recents" / "a.zip"
        self.assertEqual((dst, link.resolve()), (self.lib / "Archives" / "a.zip", dst.resolve()))
        self.assertEqual(self.icons, [("My Shelves", "✨"), ("Archives", "📦"), ("Recents", "🆕")])
        self.assertEqual(self.plan(cfg)[0], [])  # Recents and My Shelves are never re-sorted
        sorter.clean_recents(cfg, now=time.time() + 86400)
        self.assertTrue(link.is_symlink())
        sorter.undo("Keep", self.journal)
        self.assertFalse(link.is_symlink())
        self.assertEqual((self.root / "a.zip").read_text(), "x")

    def test_expired_and_broken_recents_links_are_cleaned(self):
        recents = self.root / "Recents"
        recents.mkdir()
        (recents / "gone.pdf").symlink_to(self.root / "missing.pdf")
        (recents / "real.pdf").write_text("kept")  # a real file someone put there
        target = self.touch("b.txt")
        (recents / "old.txt").symlink_to(target)
        cfg = config(self.root, recent_days=7)
        sorter.clean_recents(cfg, now=time.time() + 8 * 86400)
        self.assertEqual(sorted(p.name for p in recents.iterdir()), ["real.pdf"])

    def test_off_mode_and_backlog_get_no_links(self):
        self.touch("a.zip")
        (m,), _ = self.plan(config(self.root, recents="off", recent_days=7))
        self.assertIsNone(m.link)
        (m,), _ = self.plan(config(self.root, recent_days=0))  # older than recent_days: no link
        self.assertIsNone(m.link)

    def test_manual_library_is_never_touched(self):
        (self.root / "Manual Shelves").mkdir()
        (self.root / "Manual Shelves" / "mine.pdf").write_text("x")
        self.assertEqual(self.plan(config(self.root))[0], [])

    def test_known_types_never_load_a_model(self):
        for n in ["setup.dmg", "report.xlsx", "flow.mermaid", "data.json", "scan.pdf", "app.sqlite", "key.pem", "arm.stl", "Rename.shortcut"]:
            self.touch(n)
        cfg = config(self.root)
        moves, _ = sorter.plan(cfg, Brain(cfg), after=0, now=self.later)  # Brain._von stays None; import would be real
        self.assertEqual({m.item.path.name: m.dest.name for m in moves},
                         {"setup.dmg": "Apps", "report.xlsx": "Reports", "flow.mermaid": "Diagrams",
                          "data.json": "JSON", "scan.pdf": "Documents", "app.sqlite": "Databases",
                          "key.pem": "Keys", "arm.stl": "3D Models", "Rename.shortcut": "Automations"})

    def test_screenshot_flag_wins_over_extension(self):
        p = self.touch("Screen Recording.mov")
        flag = plistlib.dumps(True, fmt=plistlib.FMT_BINARY).hex()  # stored like macOS does: a binary plist
        subprocess.run(["/usr/bin/xattr", "-wx", "com.apple.metadata:kMDItemIsScreenCapture", flag, str(p)], check=True)
        (m,), _ = self.plan(config(self.root))
        self.assertEqual((m.dest, m.why), (self.lib / "Screenshots", "screenshot"))

    def test_default_rules_send_automation_exports_to_automations(self):
        url = plistlib.dumps(["https://eu1.make.com/scenario/42"], fmt=plistlib.FMT_BINARY).hex()
        p = self.touch("My Scenario.json")
        subprocess.run(["/usr/bin/xattr", "-wx", "com.apple.metadata:kMDItemWhereFroms", url, str(p)], check=True)
        self.touch("blueprint (3).json")
        self.touch("data.json")
        rules = tomllib.loads(sorter.DEFAULT_CONFIG.read_text())["rules"]
        moves, _ = self.plan(config(self.root, rules=rules))
        self.assertEqual({m.item.path.name: m.dest.name for m in moves},
                         {"My Scenario.json": "Automations", "blueprint (3).json": "Automations", "data.json": "JSON"})

    def test_folders_stay_unless_opted_in_and_git_repos_never_move(self):
        (self.root / "Some Folder").mkdir()
        (self.root / "repo" / ".git").mkdir(parents=True)
        (self.root / "Figma.app").mkdir()  # bundles sort like files
        (self.root / "Resize.workflow").mkdir()  # Automator workflows are bundles too
        moves, _ = self.plan(config(self.root))
        self.assertEqual(sorted(m.item.path.name for m in moves), ["Figma.app", "Resize.workflow"])
        moves, _ = self.plan(config(self.root, sort_folders=True))
        self.assertEqual(sorted(m.item.path.name for m in moves), ["Figma.app", "Resize.workflow", "Some Folder"])

    def test_von_picks_a_type_for_unknowns_and_low_confidence_is_unsorted(self):
        self.touch("blob.xyz")
        von = FakeVon("Code", 0.5)
        (m,), _ = self.plan(config(self.root), von)
        self.assertEqual(m.dest, self.lib / "Code")
        self.assertIn("Diagrams", von.questions["folder"][1])
        self.assertNotIn("Unsorted", von.questions["folder"][1])
        (m,), _ = self.plan(config(self.root), FakeVon("Code", 0.01))
        self.assertEqual(m.dest, self.lib / "Unsorted")

    def test_glob_rule_wins_and_tags_are_written(self):
        self.touch("Rechnung-42.pdf")
        cfg = config(self.root, rules=[{"glob": "*nomatch*", "dest": "~/nowhere"},
                                       {"glob": "*.pdf", "dest": "Documents/Invoices", "tags": ["Invoice"]}])
        (m,), _ = self.plan(cfg)
        self.assertEqual((m.dest, m.why), (self.lib / "Documents" / "Invoices", "rule *.pdf"))
        (src, dst, _), = sorter.apply([m], self.journal)
        self.assertEqual(sorter.read_tags(dst), ["Invoice"])

    def test_natural_language_rule_fires_above_threshold(self):
        self.touch("lecture3.pdf")
        cfg = config(self.root, rules=[{"when": "university course material", "dest": "Documents/Uni"}])
        (m,), _ = self.plan(cfg, FakeVon("Work", 0.6, noul=0.9))
        self.assertEqual(m.dest, self.lib / "Documents" / "Uni")
        (m,), _ = self.plan(cfg, FakeVon("Work", 0.6, noul=0.3))
        self.assertEqual(m.dest, self.lib / "Documents")

    def ai_plan(self, cfg, pick, von=None, new=("", "", "")):
        brain = FakeAI(cfg, pick, von, new)
        moves, _ = sorter.plan(cfg, brain, after=0, now=self.later)
        return moves, brain

    def test_apple_intelligence_picks_a_type_for_unknowns_and_learns_it(self):
        self.touch("scene.qwe")
        cfg = config(self.root)
        (m,), brain = self.ai_plan(cfg, "Design")
        self.assertEqual((m.dest, m.why), (self.lib / "Design", "apple-intelligence Design"))
        self.assertTrue(brain.creating)
        self.assertEqual(sorter.learned()["qwe"]["type"], "Design")
        self.assertEqual(sorter.ext_category(cfg, "qwe"), "Design")  # next .qwe skips the model

    def test_apple_intelligence_creates_a_new_type_with_emoji(self):
        self.touch("server.zzz")
        cfg = config(self.root)
        (m,), _ = self.ai_plan(cfg, "new", new=("keys/certs", "🔐 lock", "Security keys and certificates"))
        self.assertEqual(m.dest, self.lib / "Keys certs")
        self.assertEqual(sorter.learned()["zzz"], {"type": "Keys certs", "emoji": "🔐",
                                                   "description": "Security keys and certificates"})
        self.assertEqual(sorter.icons(cfg)["Keys certs"], "🔐")
        self.touch("other.zzz")
        moves, brain = self.ai_plan(cfg, "new")
        self.assertEqual(({m.dest for m in moves}, brain.calls), ({self.lib / "Keys certs"}, 0))

    def test_learned_types_load_with_the_config(self):
        path = Path(self.tmp.name) / "config.toml"
        path.write_text(sorter.DEFAULT_CONFIG.read_text())
        sorter.learn(config(self.root), "zzz", "Vaults", "🔐", "Vaults")
        self.assertEqual(sorter.ext_category(sorter.load_config(path), "zzz"), "Vaults")

    def test_apple_intelligence_unsure_goes_to_unsorted(self):
        self.touch("mystery")
        (m,), brain = self.ai_plan(config(self.root), "unsure")
        self.assertEqual(m.dest, self.lib / "Unsorted")
        self.assertFalse(brain.creating)  # no extension: nothing to name a type after
        self.assertEqual(sorter.learned(), {})

    def test_catch_all_new_type_names_go_to_unsorted(self):
        self.touch("blob.xyz")
        (m,), _ = self.ai_plan(config(self.root), "new", new=("Unknown Files", "❔", "Files of unknown type"))
        self.assertEqual(m.dest, self.lib / "Unsorted")
        self.assertEqual(sorter.learned(), {})

    def test_apple_intelligence_failure_falls_back_to_von(self):
        self.touch("blob.xyz")
        (m,), _ = self.ai_plan(config(self.root), None, FakeVon("Code", 0.6))
        self.assertEqual((m.dest, m.why), (self.lib / "Code", "von Code conf=0.60"))

    def test_apple_intelligence_can_pick_a_natural_language_rule(self):
        self.touch("lecture3.pdf")
        cfg = config(self.root, rules=[{"when": "university course material", "dest": "Documents/Uni", "tags": ["Uni"]}])
        (m,), brain = self.ai_plan(cfg, "rule:0")
        self.assertEqual((m.dest, m.tags), (self.lib / "Documents" / "Uni", ["Uni"]))
        self.assertEqual(brain.options["rule:0"], "university course material")
        self.assertFalse(brain.creating)  # a known type never gets a new folder

    def test_models_see_metadata_never_contents(self):
        self.touch("notes", "SECRET CONTENT")
        seen = []
        von = FakeVon("Documents", 0.6)
        von.system_one = lambda state, questions: seen.append(state) or FakeVon.system_one(von, state, questions)
        self.ai_plan(config(self.root), None, von)
        self.assertNotIn("SECRET", json.dumps(seen))
        self.assertEqual(seen[0]["file name"], "notes")

    def test_set_roots_keeps_rest_of_config(self):
        path = Path(self.tmp.name) / "config.toml"
        path.write_text(sorter.DEFAULT_CONFIG.read_text())
        sorter.set_roots([sorter.HOME / "Downloads", "/Volumes/Ext/Inbox"], path)
        cfg = tomllib.loads(path.read_text())
        self.assertEqual(cfg["roots"], ["~/Downloads", "/Volumes/Ext/Inbox"])
        self.assertIn("# roots = [", path.read_text())  # commented example untouched
        self.assertEqual(cfg["recent_days"], 7)

    def test_collision_then_undo_restores_and_pins(self):
        (self.lib / "Archives").mkdir(parents=True)
        (self.lib / "Archives" / "a.zip").write_text("existing")
        self.touch("a.zip", "new")
        moves, _ = self.plan(config(self.root))
        (_, dst, _), = sorter.apply(moves, self.journal)
        self.assertEqual(dst.name, "a 2.zip")
        sorter.undo("Keep", self.journal)
        self.assertEqual((self.root / "a.zip").read_text(), "new")
        self.assertEqual(sorter.read_tags(self.root / "a.zip"), ["Keep"])
        self.assertEqual(self.plan(config(self.root))[0], [])  # pinned: never moved again


if __name__ == "__main__":
    unittest.main()
