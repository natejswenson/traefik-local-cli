# Invariants & gates — traefik-onboard

The hard constraints the skill must preserve. I1–I9 are inspectable; T1–T6 require a live gate.
Do not mark an onboarding done until every applicable item passes.

## Checkable by inspection (templates encode these)

- **I1 — non-root.** Every Dockerfile runs as uid 1001 (`USER app`).
- **I2 — no secrets/data in the build context or image.** `.dockerignore` excludes the data dir,
  `.env`, exports, `docs/tests/.claude`. Python: `COPY` explicit subdirs, never `COPY . .`. Node:
  `COPY . .` is allowed ONLY with a verified `.dockerignore` — the build-context gate (T4) is the
  proof. App data is a host bind-mount, never `COPY`-d into the image.
- **I3 — token strength.** If a token gate exists, the server **refuses a non-loopback bind without
  a token** AND **rejects tokens < 32 chars** (`secrets.token_urlsafe(32)` → 43). The gate covers
  `/api/*` only; `/health` and `/` stay open by design.
- **I4 — agent isolation (4 mechanisms).** (a) separate DB file, agent never references the PII
  store; (b) read-only + deny-ATTACH authorizer + table allow-list; (c) fail-closed `can_use_tool`
  default-deny + `disallowed_tools` + `setting_sources=[]` + `permission_mode != "bypassPermissions"`;
  (d) raw-SQL tool is SELECT/WITH-only and scrubs error text. See `templates/agent-sdk.overlay.md` §4.
- **I5 — LAN write-gate is real.** The read-only / `NO_INTAKE` gate is a **middleware** check against
  an **explicit closed route set**, returning 403 before the handler — not a hidden UI button.
- **I6 — dual-Host + wildcard.** Router matches `<app>.internal` (+ `.home.local`); the existing
  wildcard cert + dnsmasq cover it with no per-app edit. **Single-label names only.**
- **I7 — token never committed / never in the app repo.** `<APP>_API_TOKEN` lives ONLY in gitignored
  `$TRAEFIK_DIR/.env`. Never in the app repo, the compose file, a README value, or an image layer.
- **I8 — PII / `/api` ⇒ mandatory token.** No app that holds PII *or* exposes `/api/*` gets a Traefik
  router without a server-side ≥32-char token gate + the bind-refusal. **Not askable, not optional.**
  The gate is APP-SIDE code — if the app doesn't already have it, INSTALL it (Phase 1.5 /
  `templates/token-gate.fastapi.md`). Do not assume budget's bind-refusal exists in a new app: a new
  app with no bind-refusal comes up open on 0.0.0.0, and the "crash-loop = fail-closed" safety net
  does NOT apply to it.
- **I9 — no port-publish / no docker.sock.** An onboarded service never has a published `ports:`
  stanza (everything goes through Traefik) and never mounts `/var/run/docker.sock`.

## Operational anti-invariants (the scar tissue — DON'T re-break)

- **No `read_only` rootfs when the agent overlay is present** — claude/npm/uv caches need a writable
  HOME (budget tried it; crash-loop).
- **CMD is the venv console-script, never `uv run`** (uv needs a writable cache).
- **Repoint any write dir defaulting outside `/data`** (the `BRIEFINGS_DIR` → `/data/...` lesson) —
  else a runtime 500 no `/health` gate catches.
- **Token into `.env` BEFORE the first `docker compose up`** — a tokened server refuses to start
  (crash-loops) without it.

## Requires a live gate (Phase 1/2/4)

- **T1 — TLS.** `openssl s_client -servername <app>.internal -CAfile "$MKCERT_ROOT"`
  → `Verify return code: 0`.
- **T2 — token gate.** `/api/*` → 401 without / 200 with (if applicable); `/` + `/health` reachable
  unauthenticated.
- **T3 — read-only gate.** Every route in the closed `NO_INTAKE` set → 403 (enumerate, don't spot-check).
- **T4 — no data/secrets in the built IMAGE.** Scan the real image (`docker export | tar -t | grep -Ei
  '\.(db|sqlite3?|env|env\..+|pem|key|ofx|qfx|qbo|csv)$|/(data|storage|instance|secrets|backups)/'`) —
  do NOT simulate `.dockerignore` with `tar --exclude-from` (BSD tar's syntax ≠ docker's, and a
  name-literal grep misses `.sqlite`/`.ofx`/`.pem`). Also grep the image for the generated token value.
  Hard-stop if the `<data-dir>` placeholder is still literal in `.dockerignore`.
- **T5 — compose integrity.** `docker compose config` parses; a `config` diff adds ONLY the new
  service (the `traefik`/dashboard router labels are untouched).
- **T6 — default-deny (the most important gate).** Enumerate the app's REAL data routes (OpenAPI /
  router grep / ask) — probing a literal `/api/...` placeholder is vacuous. If a PII/`api` app
  returns non-401 on any real data route WITHOUT a token, **or its routes can't be enumerated**, the
  onboarding **fails — `docker compose stop`, remove the block, and stop.** A PII app reachable on
  the wildcard LAN without a token is unacceptable.

## Failure modes → action
- Stack not set up → Phase-0 prereq gate stops (pointer to the migration doc).
- PII=yes, auth=no → override to token-required (I8); never onboard a PII app open.
- Multi-label / non-`.internal` name → reject (breaks the wildcard cert/dns guarantee).
- Reserved/colliding name (`traefik`, an existing service) → stop and ask for another.
- App already has a Dockerfile → ask replace-vs-harden; never keep an unhardened one.
- Tokened server crash-loops on first `up` → token wasn't in `.env` first (ordering anti-invariant).
- App writes outside `/data` → writable-path override + functional gate.
- Agent-SDK chat 500s → the one-time `docker exec <app> claude` login wasn't run.
- App is not HTTP (worker/cron) → container only, no router; skip routing/token gates.
