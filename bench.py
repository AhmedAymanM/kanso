"""Benchmark classification approaches side by side on real folders. Dry run: nothing moves.

    uv run python bench.py [ROOT ...] >> BENCHMARKS.md      # default roots: Downloads, Desktop, Documents

Uses the shipped default config (not ~/.config/tidy), with recent_days=0 so every file gets classified.
Accuracy is scored against bench_labels.json ({"Downloads/file.pdf": "Documents/Finance"}) when present.
To benchmark a new approach, add it to APPROACHES.
"""

import contextlib
import gc
import json
import platform
import sys
import tempfile
import time
import tomllib
from datetime import datetime
from pathlib import Path

from tidy import sorter
from tidy.brain import Brain, state_for

LABELS = Path(__file__).with_name("bench_labels.json")

class ExtensionOnly(Brain):
    """No model: type from the extension table, unknowns go to Unsorted."""

    def classify(self, item, category):
        return category or sorter.UNSORTED, [], "extension"


class Typed(Brain):
    """von's replacement: any typed-decision model behind ask(state, question, {option: desc}) -> {option: p}."""

    def __init__(self, cfg, ask):
        super().__init__(cfg)
        self.ask = ask

    def _von_classify(self, item, category, options, nl_rules):  # bench sets rules=[], so only the folder choice
        if not options:
            return category, [], "extension"
        q = f"Which {category} folder does this file belong in?" if category else "Which folder does this file belong in?"
        probs = self.ask(state_for(item), q, options)
        (top, p1), (_, p2) = sorted(probs.items(), key=lambda kv: -kv[1])[:2]
        if p1 - p2 >= self.cfg["min_confidence"]:  # von's confidence definition, so the threshold means the same
            return top, [], f"{top} conf={p1 - p2:.2f}"
        return category or sorter.UNSORTED, [], f"unsure ({top} conf={p1 - p2:.2f})"


def config(roots, **over):
    cfg = tomllib.loads(sorter.DEFAULT_CONFIG.read_text())
    cfg.update({"roots": roots, "recent_days": 0, "settle_seconds": 0, "rules": [], **over})
    return cfg


def extension_only(roots):
    cfg = config(roots)
    return cfg, ExtensionOnly(cfg)


def von(roots):
    cfg = config(roots, apple_intelligence=False)
    return cfg, Brain(cfg)


def apple_intelligence(roots):
    cfg = config(roots)
    brain = Brain(cfg)
    return (cfg, brain) if brain.fm() else None  # needs macOS 26 + AI on + `uv sync --extra apple`


def typed(make_ask):
    def approach(roots):
        cfg = config(roots, apple_intelligence=False)
        try:
            return cfg, Typed(cfg, make_ask())
        except ImportError:  # needs `uv sync --group bench`
            return None
    return approach


def laya(model):
    def make():
        from laya import Router
        router = Router()
        return lambda state, q, opts: router.predict(
            json.dumps(state), {"f": {"type": "choice", "instructions": q, "criteria": opts}}, model=model
        )["answers"]["f"]["probabilities"]
    return make


def decider(repo):
    def make():
        from decider.infer import Decider
        d = Decider(repo)
        return lambda state, q, opts: d.system_one(
            state, {"f": {"type": "choice", "instructions": q, "criteria": opts}})["answers"]["f"]["probabilities"]
    return make


def verdict():
    # ponytail: gliclass breaks on transformers 5, so run Verdict's own ONNX export on CPU instead of the torch model
    import onnxruntime as ort
    from core.calibration import TemperatureCalibrator
    from huggingface_hub import hf_hub_download
    from rlcd import Choice, DecisionEngine, Option
    from transformers import AutoTokenizer

    repo = "heman10x/rlcd-modernbert-151m"
    engine = DecisionEngine(repo, model=True, tokenizer=AutoTokenizer.from_pretrained(repo),
                            calibrator=TemperatureCalibrator.load(hf_hub_download(repo, "calibrator.json")))
    engine.ort_session = ort.InferenceSession(hf_hub_download(repo, "model.onnx"), providers=["CPUExecutionProvider"])

    def ask(state, q, opts):
        choice = Choice(id="f", question=q, options=[Option(id=k, description=v) for k, v in opts.items()])
        probs = dict(engine.evaluate(json.dumps(state), [choice]).results[0].probabilities)
        probs.pop("__insufficient_evidence__")  # drop the abstain slot and renormalize, as openjev does
        total = sum(probs.values())
        return {k: p / total for k, p in probs.items()}
    return ask


APPROACHES = {
    "extension only": extension_only,
    "von": von,
    "apple intelligence": apple_intelligence,
    "verdict-151m": typed(verdict),
    "laya-421m": typed(laya("english")),
    "laya-multilingual-322m": typed(laya("multilingual")),
    "decider-0.8b": typed(decider("Mapika/decider-0.8b")),
}


def where(m):
    try:
        rel = m.dest.relative_to(m.item.root)
    except ValueError:
        return str(m.dest)
    return "(stays)" if str(rel) == "." else str(rel)


def main(roots):
    with contextlib.redirect_stdout(sys.stderr):  # models and the sorter print progress; keep stdout pure markdown
        results, stats, skipped, labels = run(roots)
    report(roots, results, stats, skipped, labels)


def run(roots):
    sorter.LEARNED = Path(tempfile.mkdtemp()) / "learned.json"  # never teach the user's real config
    labels = json.loads(LABELS.read_text()) if LABELS.exists() else {}
    results, stats, skipped = {}, {}, []
    for name, make in APPROACHES.items():
        made = make(roots)
        if not made:
            skipped.append(name)
            continue
        cfg, brain = made
        sorter.plan(cfg, brain, after=0, now=time.time() + 3600)  # warm-up pass: model load stays out of timings
        t = time.perf_counter()
        moves, _ = sorter.plan(cfg, brain, after=0, now=time.time() + 3600)
        dt = time.perf_counter() - t
        results[name] = {f"{m.item.root.name}/{m.item.path.name}": where(m) for m in moves}
        stats[name] = (len(moves), dt)
        del made, cfg, brain, moves  # one model in 8 GB of RAM at a time
        gc.collect()
    files = set().union(*results.values())
    labels = {k: v for k, v in labels.items() if k in files}  # score only what this run saw
    stats = {n: (*s, sum(results[n].get(k) == v for k, v in labels.items())) for n, s in stats.items()}
    return results, stats, skipped, labels


def report(roots, results, stats, skipped, labels):
    names = list(results)
    files = sorted(set().union(*results.values()))
    split = [f for f in files if len({results[n].get(f) for n in names if n != "extension only"}) > 1]

    out = [f"\n## Run {datetime.now():%Y-%m-%d %H:%M}\n",
           f"Roots: {', '.join('~/' + r.name for r in roots)}. {len(files)} files, "
           f"{len(labels)} labeled. {platform.machine()}, macOS {platform.mac_ver()[0]}."
           + (f" Skipped (unavailable): {', '.join(skipped)}." if skipped else "") + "\n",
           "| approach | files | ms/file | accuracy |", "|---|---|---|---|"]
    for n, (count, dt, hits) in stats.items():
        acc = f"{hits}/{len(labels)} ({hits / len(labels):.0%})" if labels else "no labels"
        out.append(f"| {n} | {count} | {dt / max(count, 1) * 1000:.0f} | {acc} |")

    def table(rows):
        head = ["file", *names] + (["label"] if labels else [])
        lines = ["| " + " | ".join(head) + " |", "|" + "---|" * len(head)]
        for f in rows:
            cells = [f"`{f}`", *(results[n].get(f, "-") for n in names)] + ([labels.get(f, "")] if labels else [])
            lines.append("| " + " | ".join(cells) + " |")
        return lines

    out += [f"\n### Where the models disagree ({len(split)})\n", *table(split)]
    out += ["\n<details><summary>All files</summary>\n", *table(files), "\n</details>\n"]
    print("\n".join(out))


if __name__ == "__main__":
    args = sys.argv[1:] or ["~/Downloads", "~/Desktop", "~/Documents"]
    main([Path(a).expanduser() for a in args])
