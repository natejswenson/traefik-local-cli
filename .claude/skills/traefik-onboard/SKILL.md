---
name: traefik-onboard
description: Onboard a local app to a tk-managed Traefik stack at <app>.internal — hardened container, mandatory token gate for PII/api, optional agent isolation, deterministic pass/fail gates. Use when the user says "add my X app to traefik", "expose my app at <name>.internal", or wants a local app served with production hardening.
---

# traefik-onboard

Onboard a local app to a `tk`-managed home-lab Traefik stack at `https://<app>.internal`, **hardened
the way a production reference app is** (non-root, token-gated, data kept out of the image). This is
a deterministic procedure with hard gates — follow it in order, do not skip a gate, do not improvise.
It complements `tk connect --harden` (which hardens the container) by adding the app-side controls a
generator can't: the bearer-token gate, the bind-refusal, and agent isolation.

`*.internal` already has a wildcard cert (mkcert) and wildcard DNS (dnsmasq), so a new single-label
`<app>.internal` is resolvable and cert-trusted the moment Traefik routes it — no cert reissue, no
dnsmasq edit. Onboarding is just: containerize (hardened) → wire into compose → deploy → verify.

## Configure (per-stack — set once)
The skill reads these. Defaults suit a typical `tk` setup; store any non-default value in your
stack's **gitignored** `.env`. **Load them at the start of every run:**
```bash
TRAEFIK_DIR="${TRAEFIK_DIR:-$HOME/localrepo/traefik}"                  # the tk/traefik stack repo
[ -f "$TRAEFIK_DIR/.env" ] && set -a && . "$TRAEFIK_DIR/.env" && set +a # picks up STACK_DNS_IP + tokens
STACK_DNS_IP="${STACK_DNS_IP:-$(ipconfig getifaddr en0)}"              # dnsmasq/host LAN IP
MKCERT_ROOT="$(mkcert -CAROOT)/rootCA.pem"                            # local CA for the cert gates
TK="$TRAEFIK_DIR/scripts/tk"                                          # the tk CLI
```
- Compose: `$TRAEFIK_DIR/docker-compose.yml` — append the new service before `networks:`.
- Secrets/tokens: `$TRAEFIK_DIR/.env` (**gitignored** — the only place tokens go).

## tk's role (narrow)
Use `tk` for: **detection** (`service-detector.sh` — language/framework/port/existing Dockerfile),
**lifecycle** (`$TK start|stop|logs|status <app>`), and optionally **container hardening**
(`$TK connect <path> --harden` — non-root, data-excluded, cap-dropped — but it can't add the
app-side token gate/bind-refusal/agent isolation; you still owe Phase 1.5 if you use it).

**Never run plain `tk connect` (no `--harden`) for a PII/api app** — it's root, `--reload`,
whole-source-mounted, ships data into the image, and executes build/up/hosts-write immediately.
This skill writes the hardened Dockerfile + compose block itself from `templates/`.

---

## Phase 0 — Detect, then ask only the two policy questions

**Infer from the repo (do NOT ask), then confirm the security-relevant ones with the user:**
- language/framework + port + existing Dockerfile → `service-detector.sh` (or read the repo).
- serves HTTP? exposes `/api/*` or any data route? (`grep -rE '/api|@app\.(get|post)|router\.(get|post)' <app-path>`; if inference might miss a route prefix, ask — a missed route means the mandatory token gate silently doesn't fire).
- uses the Claude Agent SDK? → `grep -rl claude-agent-sdk pyproject.toml 2>/dev/null` (Python) or
  `grep -l '@anthropic-ai/claude-code' package.json 2>/dev/null` (Node).

**Ask the human only these two (a repo can't reveal them):**
1. Does it hold PII / sensitive data? (drives: data dir stays a bind-mount not `COPY`-d,
   `.dockerignore` excludes it, and forces the token gate below.)
2. Any mutating / raw-intake routes that should stay off the LAN? (drives a `NO_INTAKE`-style
   server-side 403 gate on that closed set of routes.)

Record `pii=yes|no` and `has_api=yes|no` — these drive the fail-closed token gates in Phase 2 and 4.

**Name rule (GATE — stop if violated):** single label `^[a-z0-9-]+$`, not an existing service, not
`traefik`/`dashboard`. Reject multi-label (`a.b.internal`) or non-`.internal` names.
```bash
name="<app>"
[[ "$name" =~ ^[a-z0-9-]+$ ]] || { echo "FAIL: name must be a single lowercase label"; }
grep -q "^  ${name}:" $TRAEFIK_DIR/docker-compose.yml && echo "FAIL: service '${name}' already exists"
[[ "$name" == traefik || "$name" == dashboard ]] && echo "FAIL: reserved name"
```

**GATE 0 — prereqs (stop on any FAIL):**
```bash
openssl x509 -in $TRAEFIK_DIR/certs/cert.pem -noout -ext subjectAltName | grep -q '\*.internal' \
  && echo "PASS cert wildcard" || echo "FAIL: no *.internal wildcard cert — run the stack migration first"
dig +short probe.internal @$STACK_DNS_IP | grep -q "$STACK_DNS_IP" \
  && echo "PASS dnsmasq wildcard" || echo "FAIL: dnsmasq not answering *.internal"
docker ps --filter name=traefik --filter health=healthy -q | grep -q . \
  && echo "PASS traefik healthy" || echo "FAIL: traefik not running/healthy"
```

**Branch on what was detected:**
- static site → `tk`'s static generator, no Dockerfile; skip token unless it has `/api`.
- python → `templates/Dockerfile.python`; node → `templates/Dockerfile.node`.
- Agent-SDK → also apply `templates/agent-sdk.overlay.md` (pinned claude CLI, OAuth env,
  claude-config volume, isolation checklist).
- existing Dockerfile → ask "replace with the hardened template, or harden in place?" — never
  silently keep an unhardened one.

---

## Phase 1 — Containerize (hardened — the skill writes these)

1. Copy `templates/Dockerfile.{python,node}` into the app repo, substituting `<app>` (service name),
   `<APP>` (uppercase env prefix), `<PORT>`. The python template's
   `CMD ["/app/.venv/bin/<app>", "serve", ...]` assumes a `[project.scripts] <app> = ...` entry and a
   `serve` subcommand — most apps have neither, so either add both or swap the CMD to
   `["uvicorn", "<module>:app", "--host", "0.0.0.0", "--port", "<PORT>"]`. Confirm against
   `pyproject.toml` before building.
2. Write `.dockerignore` (below), substituting the data dir name(s) — for a node app (`COPY . .`)
   this is the only thing keeping data out of the image; GATE 1 is the proof it worked.
3. Repoint any write dir that defaults outside `/data` via an env override.
4. If Agent-SDK: apply `templates/agent-sdk.overlay.md`.

### Phase 1.5 — Install the token gate + /health (REQUIRED for PII / any /api)
If the app holds PII or exposes any data route and doesn't already have a bearer-token middleware +
non-loopback bind-refusal, add them — see `templates/token-gate.fastapi.md`. Set the protected
prefix(es) to the app's real data routes (don't assume `/api/`). Ensure `GET /health` exists,
unauthenticated, touching no DB — the gate must exempt it.

> Substitute every `<...>` in the GATE commands too, not just in files — a literal
> `<app>`/`<APP>`/`<data-dir>` silently matches nothing and false-passes.

**`.dockerignore`** (`docker build` tars the whole context — this is load-bearing):
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

**GATE 1** — scan the real built image (never simulate with tar; a name-literal grep misses
`.sqlite`/`.ofx`/`.pem`):
```bash
grep -q '<data-dir>' <app-path>/.dockerignore && { echo "FAIL: <data-dir> placeholder not substituted"; }
docker build -t <app>:onboard ./<app-path>            # must succeed
docker create --name <app>-scan <app>:onboard >/dev/null
docker export <app>-scan | tar -t 2>/dev/null | \
  grep -Ei '\.(db|sqlite3?|env|env\..+|pem|key|ofx|qfx|qbo|csv)$|/(data|storage|instance|secrets|backups|briefings)/' \
  && echo "FAIL: data/secret in IMAGE" || echo "PASS image clean"
docker rm <app>-scan >/dev/null
docker run --rm -d --name <app>-smoke -p 127.0.0.1:9000:<PORT> -e <APP>_API_TOKEN="$tok" <app>:onboard
for i in $(seq 1 10); do curl -fsS http://127.0.0.1:9000/health && break || sleep 2; done \
  && echo "PASS /health" || echo "FAIL: /health never came up (entrypoint? crash? missing route?)"
docker rm -f <app>-smoke
```
(`$tok` is generated in Phase 2 — generate it first, or bind `127.0.0.1` for the smoke.) Also run a
functional write-path check if the app writes outside `/data`.

---

## Phase 2 — Wire into Traefik (write the hardened service block)

**Token first — a tokened server crash-loops without it, so generate + write before the first `up`:**
```bash
env=$TRAEFIK_DIR/.env
tok=$(python3 -c "import secrets; print(secrets.token_urlsafe(32))")   # ≥32 chars
# Idempotent: replace in place if present (compose uses the LAST duplicate on blind append).
if grep -q '^<APP>_API_TOKEN=' "$env"; then
  python3 - "$env" "$tok" <<'PY'
import re,sys
p,t=sys.argv[1],sys.argv[2]
s=open(p).read()                       # read before write — open(p,'w') truncates first
s=re.sub(r'(?m)^<APP>_API_TOKEN=.*$', f'<APP>_API_TOKEN={t}', s, count=1)
open(p,'w').write(s)
PY
else
  printf '<APP>_API_TOKEN=%s\n' "$tok" >> "$env"   # gitignored — never the app repo/compose/README
fi
[ "$(grep -c '^<APP>_API_TOKEN=' "$env")" = 1 ] || echo "FAIL: duplicate <APP>_API_TOKEN — dedupe"
# Agent-SDK app also needs an OAuth token (same idempotent treatment):
# printf 'CLAUDE_CODE_OAUTH_TOKEN=%s\n' "$(claude setup-token)" >> "$env"
```

**Append this service block** before `networks:` in `$TRAEFIK_DIR/docker-compose.yml`, substituting
`<app>`/`<APP>`/`<PORT>`. The token line is mandatory for PII/`api` (drop only for a genuinely
no-PII, no-`api` app); `NO_INTAKE`/`CLAUDE_CODE_OAUTH_TOKEN`/the claude-config volume are optional
(the latter two: Agent-SDK only):
```yaml
  <app>:
    <<: *common-config
    build:
      context: ./../<app>
    container_name: ${<APP>_SERVICE_NAME:-<app>}
    security_opt:
      - no-new-privileges:true        # don't add read_only rootfs if the agent overlay is present
    cap_drop:
      - ALL
    environment:
      - <APP>_HOST=0.0.0.0
      - <APP>_DATA_DIR=/data
      - <APP>_API_TOKEN=${<APP>_API_TOKEN}   # mandatory for PII/api — server bind-refuses without it
      # --- optional (uncomment as needed) ---
      # - <APP>_NO_INTAKE=1            # LAN-blocked mutating routes
      # - CLAUDE_CODE_OAUTH_TOKEN=${CLAUDE_CODE_OAUTH_TOKEN}   # Agent-SDK only
    volumes:
      - ${HOME}/localrepo/<app>/data:/data         # data-only bind — never the whole repo or docker.sock
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
blk=$(awk '/^  <app>:/{f=1;print;next} f&&/^  [a-z]|^[a-z]/{f=0} f' docker-compose.yml)
echo "$blk" | grep -q 'no-new-privileges:true' && echo "$blk" | grep -q 'cap_drop' \
  && echo "PASS hardened" || echo "FAIL: block missing no-new-privileges/cap_drop"
echo "$blk" | grep -Eq '(^\s*ports:|/var/run/docker\.sock)' && echo "FAIL: ports/docker.sock present" || echo "PASS no ports/sock"
if [ "$pii" = yes ] || [ "$has_api" = yes ]; then
  grep -q '^<APP>_API_TOKEN=.\{32,\}$' .env && echo "PASS token ≥32 in .env" \
    || echo "FAIL: PII/api app without a ≥32-char <APP>_API_TOKEN — do not deploy"
fi
```

---

## Phase 3 — Verify infra (no change — wildcard covers it)
```bash
dig +short <app>.internal @$STACK_DNS_IP | grep -q "$STACK_DNS_IP" && echo "PASS resolves"
```

## Phase 4 — Deploy & verify (default-deny; roll back on insecure)
```bash
cd $TRAEFIK_DIR && docker compose up -d <app>      # no sudo; scoped to one service
R="--resolve <app>.internal:443:127.0.0.1" ; tok=$(grep '^<APP>_API_TOKEN=' .env | cut -d= -f2)
curl -k $R https://<app>.internal/health && echo "PASS routing"
# Enumerate the app's REAL data routes (OpenAPI, router grep, or ask) — a literal /api/... probe is vacuous.
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
# read-only gate (if any): each NO_INTAKE route → 403, enumerate don't spot-check
echo | openssl s_client -connect 127.0.0.1:443 -servername <app>.internal \
  -CAfile "$MKCERT_ROOT" 2>/dev/null | grep -q "Verify return code: 0" && echo "PASS cert"
```
**If any real data route answers non-401 without a token (or routes can't be enumerated) on a
PII/`api` app → `docker compose stop <app>`, remove the service block, and stop.** A vacuous probe
of a non-existent path is not a pass.

## Phase 5 — Human handoff
- Token to paste in the browser on first open of `https://<app>.internal` (per-origin localStorage).
- Agent-SDK app: run once `docker exec -it <app> claude` to log in (chat is broken until then).
- Brand-new device only: set Wi-Fi DNS → `$STACK_DNS_IP`, install + fully-trust the mkcert rootCA,
  and on iOS turn "Limit IP Address Tracking" off for the network.
- Rotation: edit `<APP>_API_TOKEN` in `.env` → `docker compose up -d <app>` → re-paste. The token is
  the only control on this LAN-discoverable app.

---

See `invariants.md` for the full I1–I9 + anti-invariants + T1–T6 gate checklist, and
`templates/agent-sdk.overlay.md` for the agent-isolation requirements.
