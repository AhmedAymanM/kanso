# Destructive actions from the ask field are gated in code, not by the model

The ask field lets Foundation Models propose actions on files, and it reads contents of files downloaded from anywhere, so a file can carry instructions aimed at the model (indirect prompt injection). We allow Move to Trash from the ask field only behind deterministic checks: the trash tool accepts item IDs from a closed set Kanso put in context (the notice's files and the Duplicates shelf), never paths; Kanso renders the confirmation from the tool arguments and the journal, never from model text; it confirms with ⌘⌫, never Return; it is capped at 20 items; and it stays Move to Trash (journaled, Put Back). Most importantly, **if any file contents were read during a request, the trash tool is disabled for that request** (the taint rule), so content-derived reasoning can never lead to deletion; the user gets a normal Move to Trash button instead.

## Considered options

- **No destructive tool at all**: safest, but the user wants "trash the duplicates" to work from typed intent.
- **Rely on the model to refuse injected instructions, plus a confirmation dialog**: rejected. Refusal is probabilistic, and a model-worded confirmation can be disguised.
- **Taint rule plus closed ID set (chosen)**: a hostile file can at worst make Kanso propose a reversible move the user sees and declines.

## Consequences

"Read this and trash it if it's junk" takes two steps (an answer, then a button). Do not relax the taint rule, pass paths to tools, or let model text appear in a destructive confirmation without revisiting this ADR.
