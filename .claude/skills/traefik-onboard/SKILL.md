---
name: traefik-onboard
description: Onboard a local app to a tk-managed Traefik stack at <app>.internal — hardened container, mandatory token gate for PII/api, optional agent isolation, deterministic pass/fail gates. Use when the user says "add my X app to traefik", "expose my app at <name>.internal", or wants a local app served with production hardening.
---

# traefik-onboard

Onboard a local app to a `tk`-managed home-lab Traefik stack at `https://<app>.internal`, **hardened
the way a production reference app is** (non-root, token-gated, data kept out of the image). This is
a deterministic procedure with hard gates — follow it in order, do not skip a gate, do not improvise.
Distilled from real by-hand onboardings and hardened by a red-team + siege pass. It complements
`tk connect --harden` (which hardens the container) by adding the app-side controls a generator
can't: the bearer-token gate, the bind-refusal, and agent isolation.

## The one insight that makes this small

The stack already has a **`*.internal` wildcard** at both TLS (mkcert leaf SANs `*.internal`) and
DNS (dnsmasq `address=/internal/<mac-ip>`). So a new **single-label** `<app>.internal` is already
resolvable and cert-trusted the moment Traefik routes it — **no cert re-issue, no dnsmasq edit.**
Per-app onboarding is just: containerize (hardened) → wire into compose → deploy → verify.

## Configure (per-stack — set once)
The skill reads these. Defaults suit a typical `tk` setup; store any non-default value in your
stack's **gitignored** `.env` (never a tracked file). **Load them at the start of every run:**
```bash
TRAEFIK_DIR="${TRAEFIK_DIR:-$HOME/localrepo/traefik}"                  # the tk/traefik stack repo
[ -f "$TRAEFIK_DIR/.env" ] && set -a && . "$TRAEFIK_DIR/.env" && set +a # picks up STACK_DNS_IP + tokens
STACK_DNS_IP="${STACK_DNS_IP:-$(ipconfig getifaddr en0)}"              # dnsmasq/host LAN IP (set in .env if not en0)
MKCERT_ROOT="$(mkcert -CAROOT)/rootCA.pem"                            # local CA for the cert gates
TK="$TRAEFIK_DIR/scripts/tk"                                          # the tk CLI
```
- Compose: `$TRAEFIK_DIR/docker-compose.yml` — append the new service before `networks:`.
- Secrets/tokens: `$TRAEFIK_DIR/.env` (**gitignored** — the only place tokens go).

## tk's role (READ THIS — it is narrow)
Use `tk` for:
- **Detection:** `$TRAEFIK_DIR/scripts/lib/service-detector.sh` — language / framework / port / existing Dockerfile.
- **Lifecycle:** `$TK start <app>` / `stop` / `logs` / `status`.
- **Container hardening (optional):** `$TK connect <path> --harden` emits a non-root, data-excluded,
  cap-dropped, prod compose block — but it **cannot** add the app-side bearer gate, bind-refusal, or
  agent isolation. If you use it, you still owe the app-side controls this skill installs (Phase 1.5).

**NEVER run plain `tk connect` (no `--harden`) for a PII/api app.** It emits a *root, `--reload`,
whole-source-mounted* container, ships `data/`/`*.db` into the image, and *executes*
`docker build` + `up` + `sudo tee -a /etc/hosts` at connect time. This skill writes the hardened
Dockerfile + compose block itself from `templates/` (equivalent to `--harden` plus the app-side gate).

---

## Phase 0 — Detect, then ask only the two policy questions

**Infer from the repo (do NOT ask) — then CONFIRM the two security-relevant ones with the user:**
- language/framework + port + existing Dockerfile → `tk`'s `service-detector.sh` (or read the repo).
- serves HTTP? (a web framework / served routes present)
- **exposes `/api/*` (or any data route)?** — `grep -rE '/api|@app\.(get|post)|router\.(get|post)' <app-path>`.
  This is HALF the I8 trigger, so state it back: "I see routes X, Y — these will require the token gate."
  If inference might miss a route prefix, ask. A missed `/api` route = the mandatory-token rule silently
  doesn't fire.
- uses the Claude Agent SDK? → `grep -rl claude-agent-sdk pyproject.toml 2>/dev/null` (Python) or
  `grep -l '@anthropic-ai/claude-code' package.json 2>/dev/null` (Node — note the package is
  `@anthropic-ai/claude-code`, the same string the overlay pins).

**Ask the human ONLY these two (a repo can't reveal them):**
1. **Does it hold PII / sensitive data?** (drives: data dir stays a host bind-mount, never `COPY`-d;
   `.dockerignore` excludes it; **and forces the token gate — I8**.)
2. **Any mutating / raw-intake routes you do NOT want reachable from the LAN?** (drives a
   `NO_INTAKE`-style server-side 403 gate on the closed set of those routes — I5.)

Record the answers for the gates below: `pii=yes|no` (answer 1) and `has_api=yes|no` (from the
detected `/api` checkpoint). These drive the fail-closed token gates in Phase 2 and Phase 4.

**Name rule (GATE — stop if violated):** the subdomain must be a **single label**
`^[a-z0-9-]+$`, and must NOT be an existing service or the reserved `traefik`/`dashboard`.
Reject `a.b.internal` (the wildcard cert doesn't cover multi-label) and any non-`.internal` TLD.
```bash
name="<app>"
[[ "$name" =~ ^[a-z0-9-]+$ ]] || { echo "FAIL: name must be a single lowercase label"; }
grep -q "^  ${name}:" $TRAEFIK_DIR/docker-compose.yml && echo "FAIL: service '${name}' already exists"
[[ "$name" == traefik || "$name" == dashboard ]] && echo "FAIL: reserved name"
```

**GATE 0 — prereqs (refuse to proceed if the stack isn't set up):**
```bash
openssl x509 -in $TRAEFIK_DIR/certs/cert.pem -noout -ext subjectAltName | grep -q '\*.internal' \
  && echo "PASS cert wildcard" || echo "FAIL: no *.internal wildcard cert — run the stack migration first"
dig +short probe.internal @$STACK_DNS_IP | grep -q "$STACK_DNS_IP" \
  && echo "PASS dnsmasq wildcard" || echo "FAIL: dnsmasq not answering *.internal"
docker ps --filter name=traefik --filter health=healthy -q | grep -q . \
  && echo "PASS traefik healthy" || echo "FAIL: traefik not running/healthy"
```
Any FAIL → stop. The stack one-time setup (the `*.internal` wildcard cert + dnsmasq + per-device
DNS/CA trust) is a prerequisite, not part of per-app onboarding — set it up first.

**Branch on what was detected:**
- static site → use `tk`'s static generator (don't write a Dockerfile); skip token unless it has `/api`.
- python service → `templates/Dockerfile.python`; node service → `templates/Dockerfile.node`.
- **Agent-SDK** → ALSO apply `templates/agent-sdk.overlay.md` (node + pinned claude CLI, OAuth env,
  claude-config volume, the 4-mechanism isolation checklist).
- **existing Dockerfile** → ask "replace with the hardened template, or harden in place?" Never
  silently keep an unhardened one.

---

## Phase 1 — Containerize (hardened — the skill writes these)

1. Copy the right `templates/Dockerfile.{python,node}` into the app repo, substituting `<app>`,
   `<APP>` (uppercase env prefix), `<PORT>`. **Note `<app>` has THREE meanings that may differ:**
   service name, repo dir, and the venv console-script binary. The python template's
   `CMD ["/app/.venv/bin/<app>", "serve", ...]` assumes a `[project.scripts] <app> = ...` entry AND a
   `serve` subcommand. **Most apps have neither** — if so, either add a `[project.scripts]` console
   script + a `serve` verb, OR swap the CMD to `["uvicorn", "<module>:app", "--host", "0.0.0.0",
   "--port", "<PORT>"]`. Confirm the entrypoint against `pyproject.toml` before building.
2. Write `.dockerignore` (inline below) — substitute the data dir name(s). For a **node** app
   (`COPY . .`), this is the ONLY thing keeping data out of the image — the Phase-1 image scan (below)
   is the proof it worked.
3. **Repoint any write dir that defaults outside `/data`** via an env override (the `BRIEFINGS_DIR`
   lesson — else a runtime 500 no `/health` gate catches).
4. If Agent-SDK: apply `templates/agent-sdk.overlay.md`.

### Phase 1.5 — Install the token gate + /health (app-side code — REQUIRED for PII / any /api)
I8/T6 are server-side controls that live in the **app**, not the container config. If the app holds
PII or exposes any data route and does NOT already have a bearer-token middleware + a non-loopback
bind-refusal, **you must add them** — see `templates/token-gate.fastapi.md` (the exact working shape
from budget). Set the protected prefix(es) to the app's REAL data routes (don't assume `/api/`).
Always ensure a `GET /health` exists that is **unauthenticated and touches no DB** — the gate must
exempt it, or every health/routing gate flips red. Skipping this makes Phase 4's T6 unfixable: the
app returns 200 on its data routes with no token and there's nothing to roll back to.

> **Substitute every `<...>` in the GATE commands too, not just in files.** A gate left with a literal
> `<app>`/`<APP>`/`<data-dir>`/`<pii-db>` silently matches nothing and FALSE-PASSES.

**`.dockerignore` (the load-bearing data-exclusion control — `docker build` tars the WHOLE context):**
```gitignore
.git
.gitignore
# Sensitive data + generated artifacts — NEVER in an image
<data-dir>
logs
backups
# Local secrets / host config
.env
.env.local
# tooling cruft (rebuilt in the container)
.venv
__pycache__
**/__pycache__
*.pyc
.pytest_cache
.ruff_cache
.coverage
node_modules
# editor / OS / scratch / non-runtime
.idea
.vscode
.DS_Store
.claude
docs
tests
spikes
```

**GATE 1** — scan the REAL built image, never simulate `.dockerignore` with tar (BSD tar's
exclude syntax ≠ docker's `.dockerignore`, and a name-literal grep misses `.sqlite`/`.ofx`/`.pem`):
```bash
grep -q '<data-dir>' <app-path>/.dockerignore && { echo "FAIL: <data-dir> placeholder not substituted"; }
docker build -t <app>:onboard ./<app-path>            # must succeed
# Scan the actual image filesystem for ANY data/secret (broad, case-insensitive):
docker create --name <app>-scan <app>:onboard >/dev/null
docker export <app>-scan | tar -t 2>/dev/null | \
  grep -Ei '\.(db|sqlite3?|env|env\..+|pem|key|ofx|qfx|qbo|csv)$|/(data|storage|instance|secrets|backups|briefings)/' \
  && echo "FAIL: data/secret in IMAGE" || echo "PASS image clean"
docker rm <app>-scan >/dev/null
# Smoke: valid port map, the app's real <PORT>, and the token env (a PII server bind-refuses without it):
docker run --rm -d --name <app>-smoke -p 127.0.0.1:9000:<PORT> -e <APP>_API_TOKEN="$tok" <app>:onboard
for i in $(seq 1 10); do curl -fsS http://127.0.0.1:9000/health && break || sleep 2; done \
  && echo "PASS /health" || echo "FAIL: /health never came up (entrypoint? crash? missing route?)"
docker rm -f <app>-smoke
```
(`$tok` is generated in Phase 2 — generate it before the smoke, or bind `127.0.0.1` for the smoke.)
Plus a **functional write-path check** if the app writes outside `/data` (exercise one such route).

---

## Phase 2 — Wire into Traefik (write the hardened service block)

**Token first (ORDERING IS LOAD-BEARING).** If the app holds PII or exposes any `/api`, generate
the token and write it to `.env` **BEFORE** the first `up` (a tokened server refuses to start —
crash-loops — without it):
```bash
env=$TRAEFIK_DIR/.env
tok=$(python3 -c "import secrets; print(secrets.token_urlsafe(32))")   # 43 chars, ≥32 (I3)
# Idempotent: replace in place if present, else append. NEVER blind-append — compose interpolates
# the LAST duplicate, so a second run + a top-down hand-edit rotates the WRONG (dead) line.
if grep -q '^<APP>_API_TOKEN=' "$env"; then
  python3 - "$env" "$tok" <<'PY'
import re,sys
p,t=sys.argv[1],sys.argv[2]
s=open(p).read()                       # READ FIRST — open(p,'w') truncates before the arg evaluates
s=re.sub(r'(?m)^<APP>_API_TOKEN=.*$', f'<APP>_API_TOKEN={t}', s, count=1)
open(p,'w').write(s)
PY
else
  printf '<APP>_API_TOKEN=%s\n' "$tok" >> "$env"   # gitignored — NEVER the app repo / compose / README
fi
[ "$(grep -c '^<APP>_API_TOKEN=' "$env")" = 1 ] || echo "FAIL: duplicate <APP>_API_TOKEN — compose uses the LAST; dedupe"
# Agent-SDK app also needs an OAuth token (same idempotent treatment):
# printf 'CLAUDE_CODE_OAUTH_TOKEN=%s\n' "$(claude setup-token)" >> "$env"
```

**Append this service block** before `networks:` in `$TRAEFIK_DIR/docker-compose.yml`
(substitute `<app>`/`<APP>`/`<PORT>`. The token line is MANDATORY for PII/`api` — drop it ONLY for a
genuinely no-PII no-`api` app. `NO_INTAKE`/`CLAUDE_CODE_OAUTH_TOKEN`/the claude-config volume are the
only truly optional parts; add the volume + OAuth env only for Agent-SDK apps):
```yaml
  <app>:
    <<: *common-config
    build:
      context: ./../<app>
    container_name: ${<APP>_SERVICE_NAME:-<app>}
    security_opt:
      - no-new-privileges:true        # I1/I9 — DO NOT add read_only rootfs if the agent overlay is present
    cap_drop:
      - ALL
    environment:
      - <APP>_HOST=0.0.0.0
      - <APP>_DATA_DIR=/data
      # ▼▼▼ MANDATORY for PII / any /api (I8) — this is NOT one of the optional commented lines below.
      #     Server bind-refuses without it. Only remove for a genuinely no-PII, no-/api app.
      - <APP>_API_TOKEN=${<APP>_API_TOKEN}
      # ▲▲▲
      # --- optional (uncomment as needed) ---
      # - <APP>_NO_INTAKE=1            # if there are LAN-blocked mutating routes (I5)
      # - CLAUDE_CODE_OAUTH_TOKEN=${CLAUDE_CODE_OAUTH_TOKEN}   # Agent-SDK only
    volumes:
      - ${HOME}/localrepo/<app>/data:/data         # data-only bind — NEVER the whole repo, NEVER docker.sock
      # - <app>-claude-config:/home/app/.claude    # Agent-SDK only; first run: docker exec -it <app> claude
    labels:
      <<: *traefik-base-labels
      traefik.http.routers.<app>.rule: Host(`${<APP>_SERVICE_DOMAIN:-<app>.internal}`) || Host(`<app>.home.local`)
      traefik.http.routers.<app>.entrypoints: websecure
      traefik.http.routers.<app>.tls: "true"
      traefik.http.services.<app>.loadbalancer.server.port: <PORT>
    healthcheck:
      <<: *healthcheck-defaults
      test: ["CMD", "curl", "-fsS", "http://127.0.0.1:<PORT>/health"]
      start_period: 20s
    depends_on:
      traefik:
        condition: service_healthy
```
For Agent-SDK apps, also add `<app>-claude-config:` under a top-level `volumes:` key.

**GATE 2:**
```bash
cd $TRAEFIK_DIR && docker compose config >/dev/null && echo "PASS compose parses"
# Extract just the new block (terminator stops at the next top-level service OR networks:/volumes:):
blk=$(awk '/^  <app>:/{f=1;print;next} f&&/^  [a-z]|^[a-z]/{f=0} f' docker-compose.yml)
echo "$blk" | grep -q 'no-new-privileges:true' && echo "$blk" | grep -q 'cap_drop' \
  && echo "PASS hardened" || echo "FAIL: block missing no-new-privileges/cap_drop"
echo "$blk" | grep -Eq '(^\s*ports:|/var/run/docker\.sock)' && echo "FAIL: ports/docker.sock present (I9)" || echo "PASS no ports/sock"
# Token is FAIL-CLOSED when PII/api: a missing token is NOT acceptable, not a NOTE (I8).
if [ "$pii" = yes ] || [ "$has_api" = yes ]; then
  grep -q '^<APP>_API_TOKEN=.\{32,\}$' .env && echo "PASS token ≥32 in .env" \
    || echo "FAIL: PII/api app without a ≥32-char <APP>_API_TOKEN — I8 violation, do not deploy"
fi
```

---

## Phase 3 — Verify infra (no change — wildcard covers it)
```bash
dig +short <app>.internal @$STACK_DNS_IP | grep -q "$STACK_DNS_IP" && echo "PASS resolves"
```

## Phase 4 — Deploy & verify (default-deny; roll back on insecure)
```bash
cd $TRAEFIK_DIR && docker compose up -d <app>      # NO sudo; scoped to one service
R="--resolve <app>.internal:443:127.0.0.1" ; tok=$(grep '^<APP>_API_TOKEN=' .env | cut -d= -f2)
# routing:
curl -k $R https://<app>.internal/health && echo "PASS routing"
# TOKEN GATE / DEFAULT-DENY (T6) — enumerate the app's REAL data routes; the literal /api/... is vacuous.
# Source the routes from OpenAPI, a router grep, or ask. REQUIRE at least one for a PII/api app.
routes=$(curl -ks $R https://<app>.internal/openapi.json | python3 -c 'import sys,json;print("\n".join(k for k in json.load(sys.stdin).get("paths",{}) if k not in ("/","/health")))' 2>/dev/null)
if { [ "$pii" = yes ] || [ "$has_api" = yes ]; } && [ -z "$routes" ]; then
  echo "FAIL: cannot enumerate data routes — cannot certify default-deny. Roll back."
fi
for r in $routes; do
  no=$(curl -k -o /dev/null -s -w '%{http_code}' $R "https://<app>.internal$r")
  yes=$(curl -k -o /dev/null -s -w '%{http_code}' -H "Authorization: Bearer $tok" $R "https://<app>.internal$r")
  [ "$no" = 401 ] && echo "PASS 401-without on $r" || echo "FAIL: $r returned $no without token → ROLL BACK"
  echo "  with-token $r → $yes"   # expect 200/4xx-app-level, NOT 401
done
# read-only gate (if any): each NO_INTAKE route → 403 (enumerate, don't spot-check)
# cert smoke:
echo | openssl s_client -connect 127.0.0.1:443 -servername <app>.internal \
  -CAfile "$MKCERT_ROOT" 2>/dev/null | grep -q "Verify return code: 0" && echo "PASS cert"
```
**If ANY real data route answers non-401 without a token (or routes can't be enumerated) on a
PII/`api` app → `docker compose stop <app>`, remove the service block, and stop.** Do not leave it
exposed. A vacuous probe of a non-existent path is NOT a pass.

## Phase 5 — Human handoff (give the user exactly these)
- **Token to paste** in the browser on first open of `https://<app>.internal` (per-origin localStorage).
- **Agent-SDK app:** run once: `docker exec -it <app> claude` to log in (chat is broken until this runs).
- **Brand-new device only** (already-onboarded devices need nothing): set Wi-Fi DNS → `$STACK_DNS_IP`;
  install + **fully-trust** the mkcert rootCA; on iOS turn **"Limit IP Address Tracking" OFF** for the network.
- **Security note + rotation:** the app is now LAN-discoverable; the token is the only control. Rotate:
  edit `<APP>_API_TOKEN` in `$TRAEFIK_DIR/.env` → `docker compose up -d <app>` → re-paste.

---

## Honest scope
Claude-side work is minutes. **Device-side** work (a new phone/laptop: DNS + CA trust + the iOS
Limit-IP-Tracking toggle) is NOT automatable and was the bulk of the real human time — hand the user
the exact steps but they run them. "Minutes, not hours" holds for Claude's part and for any
already-trusted device; it is not a claim about onboarding a brand-new device.

See `invariants.md` for the full I1–I9 + anti-invariants + T1–T6 gate checklist, and
`templates/agent-sdk.overlay.md` for the agent-isolation requirements.
