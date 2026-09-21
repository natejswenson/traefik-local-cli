#!/usr/bin/env python3
"""Opt-in live Docker check; uses only disposable resources in a unique project.

Requires the locally cached traefik:3.6.5 image. No published ports or host mounts.
Run directly; intentionally excluded from ordinary offline test discovery.
"""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import uuid

TK = Path(__file__).resolve().parents[1] / "tk"
IMAGE = "traefik:3.6.5"


def run(argv, env, cwd=None, timeout=90):
    result = subprocess.run(argv, env=env, cwd=cwd, capture_output=True, text=True, timeout=timeout)
    if result.returncode:
        raise RuntimeError(f"Fixture command failed ({Path(argv[0]).name}, exit {result.returncode})")
    return result.stdout


def main():
    project = "tk-agent-smoke-" + uuid.uuid4().hex[:12]
    env = {key: value for key, value in os.environ.items()
           if not key.startswith("COMPOSE_") and key not in ("DOCKER_COMPOSE_FILE", "DOCKER_DEFAULT_PLATFORM")}
    run(["docker", "image", "inspect", IMAGE], env, timeout=15)  # Refuse instead of pulling.
    with tempfile.TemporaryDirectory(prefix=project + "-") as directory:
        root = Path(directory)
        source = root / "compose.yaml"
        (root / "Dockerfile").write_text(f'FROM {IMAGE}\nCMD ["sh", "-c", "sleep 3600"]\n')
        original = f'''name: {project}
services:
  app:
    build:
      context: {json.dumps(str(root))}
      network: none
    image: {project}:test
    pull_policy: never
    network_mode: none
    volumes:
      - app-data:/data
    healthcheck:
      test: ["CMD", "traefik", "version"]
      interval: 1s
      timeout: 2s
      retries: 3
  peer:
    image: {IMAGE}
    pull_policy: never
    command: ["sh", "-c", "sleep 3600"]
    network_mode: none
    healthcheck:
      test: ["CMD", "traefik", "version"]
      interval: 1s
      timeout: 2s
      retries: 3
volumes:
  app-data: {{}}
'''
        source.write_text(original)
        env.update(TK_TEST_MODE="true", COMPOSE_PROJECT_NAME=project, COMPOSE_FILE=str(source))
        compose = ["docker", "compose", "--project-directory", str(root), "-f", str(source), "-p", project]

        def cli(*arguments):
            result = subprocess.run([str(TK), *arguments, "--json"], cwd=root, env=env,
                                    capture_output=True, text=True, timeout=90)
            data = json.loads(result.stdout)
            if result.returncode or not data["ok"]:
                raise RuntimeError(json.dumps(data))
            print(json.dumps({"command": arguments[0], "state": data["state"], "ok": data["ok"]}), flush=True)
            return data

        def peer_state():
            container = run(compose + ["ps", "--quiet", "peer"], env).strip()
            state = json.loads(run(["docker", "inspect", container, "--format", "{{json .State}}"], env))
            return state["StartedAt"], state["Running"]

        try:
            cli("start", "--all", "--timeout", "60")
            before = peer_state()
            run(compose + ["exec", "-T", "app", "sh", "-c", "echo keep-me > /data/sentinel"], env)
            cli("rebuild", "app", "--timeout", "60")
            cli("stop", "app", "--timeout", "30")
            cli("restart", "app", "--timeout", "30")
            cli("wait", "app", "--timeout", "10")
            preview = cli("remove", "app")
            assert preview["state"] == "planned" and source.read_text() == original
            removed = cli("remove", "app", "--apply", "--timeout", "30")
            assert removed["state"] == "removed" and removed["config_changed"]
            assert Path(removed["backup"]).read_text() == original
            config = json.loads(run(compose + ["config", "--format", "json"], env))
            assert set(config["services"]) == {"peer"}
            assert peer_state() == before and before[1], "Untargeted peer was interrupted"
            contents = run(["docker", "run", "--rm", "--name", project + "-volume-check", "--network", "none",
                            "--pull=never", "--mount", f"type=volume,source={project}_app-data,target=/data,readonly",
                            "--entrypoint", "cat", IMAGE, "/data/sentinel"], env)
            assert contents.strip() == "keep-me", "Fixture volume data was not preserved"
            print("Peer start time unchanged; removed app's volume data and Compose backup preserved.", flush=True)
        finally:
            # Restore only the fixture so Compose can clean its own retained volume.
            source.write_text(original)
            run(compose + ["down", "--volumes", "--remove-orphans"], env, timeout=30)
            subprocess.run(["docker", "rm", "--force", project + "-volume-check"], env=env,
                           capture_output=True, timeout=15)
            subprocess.run(["docker", "image", "rm", project + ":test"], env=env,
                           capture_output=True, timeout=15)
            print("Disposable fixture cleaned up.", flush=True)


if __name__ == "__main__":
    main()
