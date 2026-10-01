"""Deciding a file's type folder when its extension doesn't, from metadata only; contents are never read.

Known extensions never reach a model. For unknown types and folders, Apple Intelligence (on-device
Foundation Model) picks a type or creates a new one; von is the fallback and only picks existing types.
Both load lazily, so runs where every file has a known extension never touch them.
"""

import asyncio
import re

from . import sorter

UNSURE = "unsure"
NEW = "new"
CATCH_ALL = re.compile(r"(?i)((unknown|other|misc|miscellaneous|unsorted)( (files?|items?|types?))?|files?|items?)")


class Brain:
    def __init__(self, cfg):
        self.cfg = cfg
        self._von = None
        self._fm = None if cfg.get("apple_intelligence", True) else False

    def fm(self):
        """The apple_fm_sdk module if the on-device model is usable, else False."""
        if self._fm is None:
            try:
                import apple_fm_sdk as fm
                ok, reason = fm.SystemLanguageModel().is_available()
                if not ok:
                    print(f"Apple Intelligence unavailable: {reason}")
                self._fm = fm if ok else False
            except ImportError:
                self._fm = False
        return self._fm

    def von(self):
        if self._von is None:
            import von  # pulls in torch; ~1.5 GB of weights on first run
            self._von = von
        return self._von

    def classify(self, item, category):
        """Return (dest, tags, why). category is known from the extension, or None."""
        cats = self.cfg["categories"]
        nl_rules = [r for r in self.cfg["rules"] if "when" in r]
        options = folder_options(cats, category)
        if category and not nl_rules:
            return category, [], "extension"

        if self.fm():
            creating = not category and bool(item.ext) and not item.path.is_dir()  # only a real, unknown file type
            pick = self._fm_choose(item, {**options, **{f"rule:{i}": r["when"] for i, r in enumerate(nl_rules)}}, creating)
            if pick is not None:
                if pick.folder.startswith("rule:"):
                    rule = nl_rules[int(pick.folder[5:])]
                    return rule["dest"], list(rule.get("tags", [])), f"apple-intelligence rule '{rule['when']}'"
                if pick.folder in options:
                    self._remember(item, pick.folder)
                    return pick.folder, [], f"apple-intelligence {pick.folder}"
                if creating and pick.folder == NEW and (name := clean_name(pick.name)) and not CATCH_ALL.fullmatch(name):
                    name = next((t for t in self.cfg["categories"] if t.lower() == name.lower()), name)
                    self._remember(item, name, clean_emoji(pick.emoji), pick.description.strip()[:200])
                    return name, [], f"apple-intelligence new type {name}"
                return category or sorter.UNSORTED, [], "apple-intelligence unsure"
        return self._von_classify(item, category, options, nl_rules)

    def _remember(self, item, name, emoji="📁", description=""):
        """Learn the type for this extension, so the next file like it skips the model."""
        if item.ext and not item.path.is_dir():
            sorter.learn(self.cfg, item.ext, name, emoji, description)

    def _fm_choose(self, item, options, creating):
        """Guided generation constrained to the option keys (or NEW when creating, or UNSURE).
        Returns the Pick (folder, name, emoji, description), or None if the model fails."""
        fm = self.fm()
        keys = list(options) + ([NEW] if creating else []) + [UNSURE]

        @fm.generable("Folder choice")
        class Pick:
            folder: str = fm.guide("Key of the folder this file belongs in", anyOf=keys)
            name: str = fm.guide(f"If folder is '{NEW}': a short plural folder name for this file type, like 'Keys' or '3D Models'")
            emoji: str = fm.guide(f"If folder is '{NEW}': one emoji for that folder")
            description: str = fm.guide(f"If folder is '{NEW}': one sentence describing the files that belong there")

        facts = "\n".join(f"{k}: {v}" for k, v in state_for(item).items())
        menu = "\n".join(f"- {k}: {d}" for k, d in options.items())
        new = f"\n- {NEW}: a file type none of these folders covers; name a new folder for it" if creating else ""
        prompt = f"File:\n{facts}\n\nFolders:\n{menu}{new}\n- {UNSURE}: you can't tell what kind of file this is"

        async def ask():
            session = fm.LanguageModelSession(
                instructions="You sort files into folders by file type, using only their name, extension and source. "
                             "Pick an existing folder only if its description clearly covers this file type. "
                             + (f"If the type is recognizable but no folder covers it (calendar invites, contacts, "
                                f"certificates, torrents...), answer '{NEW}' and name a new folder. " if creating else "")
                             + f"Answer '{UNSURE}' when you can't tell what kind of file it is.")
            return await session.respond(prompt, generating=Pick)

        try:
            return asyncio.run(ask())
        except Exception as e:  # guardrail refusal, model not ready...
            print(f"apple intelligence: {item.path.name}: {e}")
            return None

    def _von_classify(self, item, category, options, nl_rules):
        von = self.von()
        questions = {}
        if options:
            q = f"Which {category} folder does this file belong in?" if category else "Which folder does this file belong in?"
            questions["folder"] = von.choice(q, options)
        for i, r in enumerate(nl_rules):
            questions[f"rule{i}"] = von.noul(f"Is this file {r['when']}?")

        answers = von.system_one(state=state_for(item), questions=questions).answers

        fired = [(answers[f"rule{i}"].noul, r) for i, r in enumerate(nl_rules)]
        p, rule = max(fired, key=lambda x: x[0], default=(0, None))
        if rule and p >= self.cfg["rule_threshold"]:
            return rule["dest"], list(rule.get("tags", [])), f"rule '{rule['when']}' p={p:.2f}"
        if "folder" not in questions:
            return category, [], "extension"
        a = answers["folder"]
        if a.confidence >= self.cfg["min_confidence"]:
            self._remember(item, a.choice)
            return a.choice, [], f"von {a.choice} conf={a.confidence:.2f}"
        return category or sorter.UNSORTED, [], f"von unsure ({a.choice} conf={a.confidence:.2f})"


def folder_options(cats, category):
    """{type: description} to choose from: none when the extension already decided, else every type."""
    if category:
        return {}
    return {n: c.get("description", n) for n, c in cats.items() if n not in (sorter.UNSORTED, sorter.SCREENSHOTS)}


def clean_name(name):
    name = " ".join(re.sub(r"[/:\\.]", " ", name or "").split())[:30].strip()
    return name[:1].upper() + name[1:]


def clean_emoji(e):
    e = (e or "").split()
    return e[0][:8] if e and not e[0][0].isalnum() else "📁"


def state_for(item):
    """What the models see: metadata only."""
    s = {"file name": item.path.name, "type": "folder" if item.path.is_dir() else (item.ext or "unknown")}
    if item.screenshot:
        s["screenshot"] = "yes, this is a screen capture"
    if item.where_from:
        s["downloaded from"] = item.where_from[0]
    if item.path.is_dir():
        try:
            s["contains"] = ", ".join(sorted(p.name for p in item.path.iterdir())[:20])
        except OSError:
            pass
    return s
