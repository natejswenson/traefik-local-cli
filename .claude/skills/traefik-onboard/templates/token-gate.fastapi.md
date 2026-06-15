# Token gate (FastAPI) — app-side middleware the skill MUST install

I8/T6 require a **server-side** bearer-token gate + a non-loopback bind-refusal. This lives in the
**app's** code, not the container config — so for any app that didn't already copy budget's
`server.py`, the skill must ADD it. Verifying the gate (Phase 4) without installing it is hollow:
the app returns 200 on `/api/*` with no token and T6 fails with nothing to fix.

This is the exact, working shape from budget (`src/local_budget/web/server.py`). Substitute `<APP>`
(uppercase env prefix) and set the protected prefix(es) to the app's real PII routes (NOT assumed to
be `/api/` — enumerate them).

```python
import hmac, os
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

_API_TOKEN = os.environ.get("<APP>_API_TOKEN")
_MIN_TOKEN_LEN = 32                       # I3 — reject weak tokens on a LAN bind
_PROTECTED = ("/api/",)                   # EVERY PII route prefix — verify against the real routes
_OPEN = ("/health", "/")                  # unauthenticated by design

def install_token_gate(app: FastAPI) -> None:
    @app.middleware("http")
    async def _auth(request: Request, call_next):
        path = request.url.path
        if _API_TOKEN and any(path.startswith(p) for p in _PROTECTED):
            header = request.headers.get("authorization", "")
            token = header[7:] if header.lower().startswith("bearer ") else ""
            if not hmac.compare_digest(token, _API_TOKEN):   # constant-time
                return JSONResponse({"error": "unauthorized"}, status_code=401)
        return await call_next(request)

    @app.get("/health")                   # cheap, unauthenticated, touches NO DB (I3) —
    def health() -> dict:                 # the gate above already exempts it (not under a _PROTECTED prefix)
        return {"status": "ok"}

def serve(host: str = "127.0.0.1", port: int = 8000) -> None:
    import uvicorn
    if host != "127.0.0.1":               # bind-refusal — fail CLOSED on a non-loopback bind
        if not _API_TOKEN:
            raise SystemExit("Refusing to bind a non-loopback host without <APP>_API_TOKEN (PII).")
        if len(_API_TOKEN) < _MIN_TOKEN_LEN:
            raise SystemExit(f"Refusing to bind non-loopback with a weak <APP>_API_TOKEN (<{_MIN_TOKEN_LEN}).")
    uvicorn.run(_app, host=host, port=port, log_level="warning")
```

**Wire it:** call `install_token_gate(app)` when building the app, and make the container entrypoint
call `serve(host="0.0.0.0", port=<PORT>)` (the bind-refusal is what makes the "token-in-.env-before-up"
ordering fail-closed — without it a new app comes up open on 0.0.0.0).

**If there is NO `/health` yet** and you're not installing this whole gate (a no-PII no-api app),
still add the one-liner `@app.get("/health")` returning `{"status":"ok"}` — every gate depends on it,
and it must NOT sit behind any auth.

**Node equivalent:** the same three pieces — a middleware that 401s on the protected prefix unless
`Authorization: Bearer` matches `process.env.<APP>_API_TOKEN` via a constant-time compare
(`crypto.timingSafeEqual`), an open `/health`, and a startup check that refuses `0.0.0.0` without a
≥32-char token.
