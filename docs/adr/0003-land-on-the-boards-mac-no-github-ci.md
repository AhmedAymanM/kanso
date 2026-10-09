# Code lands only through scripts/land on the Board's Mac; no GitHub CI

Status: proposed (Forge, 2026-10-09). The Board accepts or rejects.

Agents write Kanso on a Linux server, and Kanso is macOS-only: KansoCore imports AppKit, FoundationModels, PDFKit and Vision, and the Python tests call `/usr/bin/xattr`. So nothing can be built or tested where the code is written. We make one machine responsible for that: **`scripts/land KAN-<n>` on the Board's Mac is the only path to `main`.** It rebases the PR branch on `main`, runs `swift test` and the Python tests, merges and pushes. A paired `pre-push` hook refuses any other push to `main`. Before that, cheap checks with no tests run earlier: a `pre-commit` hook (territory and `Architecture-Ref`) and a `pre-receive` hook on the gate repo (branch name, merge-base, territory, `Architecture-Ref`). GitHub is a mirror and a PR UI. Releases (sign, DMG, notarize) also run by hand on the Board's Mac, separate from land, which never touches Apple secrets.

## Considered options

- **GitHub Actions on `macos-latest`** (`.github/workflows/swift.yml`, extended by PR #11): it tests every PR without the Board. Rejected as the merge gate: macOS minutes are metered on a private repo, the runner's Xcode and macOS lag the Board's (Liquid Glass and FoundationModels need macOS 26+ and Xcode 27), Apple signing secrets would live in GitHub, and a green check that nobody merges on doesn't decide anything. The release scripts from PR #11 are still useful when run locally.
- **Self-hosted runner on the Board's Mac**: the same machine with more moving parts (a resident agent, the runner token, the network exposure). It may come back if landing by hand becomes the bottleneck.
- **Land on the Board's Mac (chosen)**: one place where tests run and one merge path, on the machine that matches users' setups.

## Consequences

- Swift changes are verified only when they land. Tasks must be shaped so that is acceptable: small PRs, engine logic covered by `swift test`, UI checked with `--snapshot` on the Mac.
- A red land sends the PR back to its seat. Nothing reaches `main` untested.
- `.github/workflows/swift.yml` is removed once `scripts/land` exists (KAN-25). PR #11 has to be reworked into local release scripts with no workflow before it merges.
- Revisit this ADR before adding any CI that gates merges or holds Apple credentials.
