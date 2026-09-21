"""Removal contracts: scope, validation, retained data and partial failures."""

import copy
import importlib.util
import json
from pathlib import Path
import unittest

import test_inspect as fixtures

SPEC = importlib.util.spec_from_file_location("tk_remove", fixtures.SCRIPTS / "lib/tk-remove.py")
remove = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(remove)


class RemoveTests(unittest.TestCase):
    def setUp(self):
        fixtures.InspectTests.setUp(self)
        self.source = self.root / "docker-compose.yml"
        self.raw = ("services:\n  # API description\n  api:\n    image: fixture\n"
                    "    environment:\n      SECRET: never-print-this-secret\n\n"
                    "  # Preserve database comment\n  database:\n    image: fixture\n"
                    "volumes:\n  api:\n  database:\n").encode()
        self.source.write_bytes(self.raw)
        self.candidate = copy.deepcopy(self.config)
        del self.candidate["services"]["api"]
        self.env["SOURCE"] = str(self.source)
        self.env["STATE_FILE"] = str(self.root / "removed")
        for key in ("COMPOSE_FILE", "DOCKER_COMPOSE_FILE", "COMPOSE_PATH_SEPARATOR"):
            self.env.pop(key, None)
        (self.root / "docker").write_text('''#!/usr/bin/env python3
import json,os,sys
from pathlib import Path
args=sys.argv[1:]
with Path(os.environ['CALLS']).open('a') as handle: handle.write(json.dumps(args)+'\\n')
source=Path(os.environ['SOURCE']).resolve()
state=Path(os.environ['STATE_FILE'])
if 'config' in args:
    if '--environment' in args:
        print(os.environ.get('COMPOSE_ENV','SECRET=never-print-this-secret'))
    elif '-f' in args and Path(args[args.index('-f')+1]).resolve() != source:
        if os.environ.get('CANDIDATE_FAIL'):
            print('never-print-this-secret',file=sys.stderr);sys.exit(1)
        print(os.environ['CANDIDATE'])
    elif '-f' in args and os.environ.get('SOURCE_MISMATCH'): print('{}')
    elif state.exists() and os.environ.get('CONFIG_RACE'):
        config=json.loads(os.environ['CONFIG']);config['name']='changed';print(json.dumps(config))
    else: print(os.environ['CONFIG'])
elif 'ps' in args:
    if os.environ.get('DAEMON_FAIL'): sys.exit(1)
    rows=json.loads(os.environ['CONTAINERS'])
    if state.exists() and not os.environ.get('REMAINS'): rows=[r for r in rows if r['Service']!='api']
    print(json.dumps(rows))
elif 'rm' in args:
    if os.environ.get('ACTION_FAIL'):
        print('never-print-this-secret',file=sys.stderr);sys.exit(1)
    state.touch()
    if os.environ.get('SOURCE_RACE'): source.write_text('concurrent user edit\\n')
else: sys.exit(9)
''')

    def cli(self, *args, extra=None):
        extra = dict(extra or {}, CANDIDATE=json.dumps(self.candidate))
        return fixtures.InspectTests.cli(self, *args, extra=extra)

    def calls(self):
        path = self.root / "calls"
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def mutations(self):
        return [args for args in self.calls() if any(op in args for op in ("rm", "down", "up", "stop", "restart"))]

    def test_default_preview_does_not_touch_daemon_source_or_tkrc(self):
        (self.root / ".tkrc").write_text("touch unexpected-side-effect\n")
        result = self.cli("remove", "api", "--json", extra={"DAEMON_FAIL": "1"})
        data = json.loads(result.stdout)
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(data["state"], "planned")
        self.assertFalse(data["changed"])
        self.assertTrue(data["plan"]["preserve_volumes"])
        self.assertTrue(data["plan"]["container_writable_layer_removed"])
        self.assertEqual(self.source.read_bytes(), self.raw)
        self.assertFalse((self.root / "unexpected-side-effect").exists())
        self.assertFalse((self.root / ".tk").exists())
        self.assertFalse(any("ps" in args for args in self.calls()))
        self.assertNotIn("never-print-this-secret", result.stdout + result.stderr)

    def test_apply_only_removes_target_and_preserves_original_in_private_backup(self):
        self.source.chmod(0o640)
        result = self.cli("remove", "api", "--apply", "--json")
        data = json.loads(result.stdout)
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(data["state"], "removed")
        self.assertTrue(data["config_changed"])
        self.assertEqual(len(self.mutations()), 1)
        self.assertEqual(self.mutations()[0][-4:], ["rm", "--stop", "--force", "api"])
        self.assertNotIn("--volumes", self.mutations()[0])
        self.assertEqual(Path(data["backup"]).read_bytes(), self.raw)
        self.assertEqual(Path(data["backup"]).stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.source.stat().st_mode & 0o777, 0o640)
        self.assertIn("# Preserve database comment\n  database:\n    image: fixture", self.source.read_text())
        self.assertIn("volumes:\n  api:\n  database:", self.source.read_text())
        self.assertNotIn("SECRET", self.source.read_text())

    def test_missing_extra_and_all_targets_fail_before_docker(self):
        for args in [("remove",), ("remove", "--all"), ("remove", "api", "database"),
                     ("remove", "api", "--apply", "--dry-run")]:
            result = self.cli(*args, "--json")
            self.assertEqual(result.returncode, 2)
            self.assertEqual(json.loads(result.stdout)["error"]["code"], "invalid_arguments")
        self.assertEqual(self.calls(), [])

    def test_dependents_block_before_source_edit_or_mutation(self):
        for dependency in [{"depends_on": {"api": {"condition": "service_started"}}},
                           {"network_mode": "service:api"}, {"volumes_from": ["api:ro"]}, {"links": ["api:alias"]}]:
            self.config["services"]["database"] = dependency
            result = self.cli("remove", "api", "--apply", "--json")
            data = json.loads(result.stdout)
            self.assertEqual(data["error"]["code"], "dependent_services")
            self.assertEqual(data["dependent_services"], ["database"])
        self.assertEqual(self.source.read_bytes(), self.raw)
        self.assertEqual(self.mutations(), [])

    def test_semantic_change_to_neighbor_is_rejected(self):
        self.candidate["services"]["database"]["image"] = "changed"
        result = self.cli("remove", "api", "--apply", "--json")
        self.assertEqual(json.loads(result.stdout)["error"]["code"], "unexpected_config_change")
        self.assertEqual(self.mutations(), [])
        self.assertEqual(self.source.read_bytes(), self.raw)

    def test_invalid_candidate_suppresses_compose_secret_output(self):
        result = self.cli("remove", "api", "--apply", "--json", extra={"CANDIDATE_FAIL": "1"})
        self.assertEqual(result.returncode, 1)
        self.assertNotIn("never-print-this-secret", result.stdout + result.stderr)
        self.assertEqual(self.mutations(), [])

    def test_merged_source_is_rejected(self):
        for extra in ({"COMPOSE_ENV": "COMPOSE_FILE=one.yml:two.yml"}, {"SOURCE_MISMATCH": "1"}):
            result = self.cli("remove", "api", "--apply", "--json", extra=extra)
            self.assertEqual(json.loads(result.stdout)["error"]["code"], "unsupported_compose_source")
        (self.root / "compose.override.yaml").touch()
        result = self.cli("remove", "api", "--apply", "--json")
        self.assertEqual(json.loads(result.stdout)["error"]["code"], "unsupported_compose_source")
        self.assertEqual(self.mutations(), [])

    def test_symlink_source_is_not_replaced(self):
        target = self.root / "actual.yaml"
        self.source.rename(target)
        self.source.symlink_to(target)
        result = self.cli("remove", "api", "--apply", "--json")
        self.assertEqual(json.loads(result.stdout)["error"]["code"], "unsupported_compose_source")
        self.assertTrue(self.source.is_symlink())
        self.assertEqual(self.mutations(), [])

    def test_daemon_failure_keeps_source_and_creates_no_backup(self):
        result = self.cli("remove", "api", "--apply", "--json", extra={"DAEMON_FAIL": "1"})
        self.assertEqual(result.returncode, 1)
        self.assertEqual(self.source.read_bytes(), self.raw)
        self.assertFalse((self.root / ".tk/backups").exists())
        self.assertEqual(self.mutations(), [])

    def test_failed_removal_retains_source_and_releases_lock_for_retry(self):
        result = self.cli("remove", "api", "--apply", "--json", extra={"ACTION_FAIL": "1"})
        data = json.loads(result.stdout)
        self.assertEqual(result.returncode, 1)
        self.assertIsNone(data["changed"])
        self.assertFalse(data["config_changed"])
        self.assertEqual(self.source.read_bytes(), self.raw)
        self.assertNotIn("never-print-this-secret", result.stdout + result.stderr)
        self.assertEqual(self.cli("remove", "api", "--apply", "--json").returncode, 0)

    def test_remaining_container_prevents_source_edit(self):
        result = self.cli("remove", "api", "--apply", "--json", extra={"REMAINS": "1"})
        self.assertEqual(json.loads(result.stdout)["error"]["code"], "removal_incomplete")
        self.assertEqual(self.source.read_bytes(), self.raw)

    def test_concurrent_source_edit_is_preserved_after_container_removal(self):
        result = self.cli("remove", "api", "--apply", "--json", extra={"SOURCE_RACE": "1"})
        data = json.loads(result.stdout)
        self.assertEqual(data["error"]["code"], "config_changed")
        self.assertEqual(data["state"], "containers_removed")
        self.assertFalse(data["config_changed"])
        self.assertEqual(self.source.read_text(), "concurrent user edit\n")
        self.assertEqual(Path(data["backup"]).read_bytes(), self.raw)

    def test_changed_resolved_configuration_is_preserved(self):
        result = self.cli("remove", "api", "--apply", "--json", extra={"CONFIG_RACE": "1"})
        self.assertEqual(json.loads(result.stdout)["error"]["code"], "config_changed")
        self.assertEqual(self.source.read_bytes(), self.raw)

    def test_concurrent_mutation_blocks_removal_and_restart_but_allows_preview(self):
        with fixtures.inspect.acquire_project_lock(self.root):
            for command in [("remove", "api", "--apply"), ("restart", "api")]:
                result = self.cli(*command, "--json")
                self.assertEqual(json.loads(result.stdout)["error"]["code"], "operation_in_progress")
            self.assertEqual(self.cli("remove", "api", "--json").returncode, 0)
            self.assertEqual(self.cli("status", "api", "--json").returncode, 0)
        self.assertEqual(self.mutations(), [])

    def test_block_edit_handles_quotes_crlf_and_same_named_top_level_resource(self):
        raw = b'services:\r\n    "api":\r\n        image: one\r\n    peer:\r\n        image: two\r\nvolumes:\r\n    api:\r\n'
        candidate = remove.remove_block(raw, "api")
        self.assertEqual(candidate, b'services:\r\n    peer:\r\n        image: two\r\nvolumes:\r\n    api:\r\n')

    def test_flow_style_and_implicit_service_blocks_are_refused(self):
        for raw in (b'services: {api: {image: one}, peer: {image: two}}\n',
                    b'services:\n  <<: *shared-services\n'):
            with self.assertRaises(remove.Error):
                remove.remove_block(raw, "api")


if __name__ == "__main__":
    unittest.main()
