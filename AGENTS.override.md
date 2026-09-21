# CLI development

This directory is its own Git repository, used as the parent Traefik stack's
`scripts/` submodule. Preserve current changes and branch. Do not commit/publish
unless requested; a parent commit alone does not save submodule file edits.

Use macOS-compatible Bash 3.2 and Python 3 standard-library helpers. Run
`./run-tests.sh` after code changes; distinguish Docker-dependent skips from passes.
Document CLI behavior in README.md and QUICKSTART.md. The older `agents.md` is
background reference; inspect current implementations before trusting examples.

Use `./tk list --json`, `./tk status --json` and `./tk doctor --probe --json`
for read-only inspection. `./tk logs SERVICE --tail 100` is a finite snapshot.
Keep JSON stdout clean, never print environments/secrets, and retain subprocess
timeouts. Structured inspection and lifecycle commands do not source executable `.tkrc`.
Lifecycle commands require a service or explicit `--all`. Prefer `tk rebuild SERVICE
--dry-run --json` before an authorized rebuild; use `--with-deps` only when intended.
Use bounded `tk wait SERVICE --timeout 30 --json` and inspect state before retrying failures.
`tk remove SERVICE --json` previews; `--apply` executes only an authorized removal.
It validates the remaining Compose configuration, retains volumes and backs up the
source under `.tk/backups/`. Structured mutations share a per-checkout lock;
never unlink a lock file to bypass an active operation.
Do not use the running shared stack as a mutating test fixture.

For local-memory, follow the installed skill and host activity policy: doctor
before personal recall/capture, resolve registered repository scope, recall
relevant outcomes, then record a concise source-backed result with artifact links.
No raw transcripts or secrets; do not create fallback stores when unavailable.
