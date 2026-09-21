"""Exercise action scope, failures and readiness without touching the real stack."""

import json
from pathlib import Path
import time
import unittest

import test_inspect as fixtures


class OperationsTests(unittest.TestCase):
    cli = fixtures.InspectTests.cli

    def setUp(self):
        fixtures.InspectTests.setUp(self)
        self.config["services"]["api"]["build"] = {"context": str(self.root)}
        self.config["services"]["api"]["container_name"] = "api-container"
        self.env["STATE_FILE"] = str(self.root / "state")
        self.env["COUNT_FILE"] = str(self.root / "count")
        (self.root / "docker").write_text('''#!/usr/bin/env python3
import json,os,sys,time
from pathlib import Path
args=sys.argv[1:]
with Path(os.environ['CALLS']).open('a') as f: f.write(json.dumps(args)+'\\n')
if 'config' in args:
    print(os.environ['CONFIG'])
elif 'ps' in args:
    if os.environ.get('DAEMON_FAIL'): sys.exit(1)
    state=Path(os.environ['STATE_FILE'])
    steps=json.loads(os.environ.get('STEPS','[]'))
    if steps:
        count=Path(os.environ['COUNT_FILE'])
        i=int(count.read_text()) if count.exists() else 0
        count.write_text(str(i+1))
        print(json.dumps(steps[min(i,len(steps)-1)]))
    else: print(state.read_text() if state.exists() else os.environ['CONTAINERS'])
elif any(op in args for op in ('up','stop','restart')):
    if os.environ.get('ACTION_FAIL'):
        print('never-print-this-secret',file=sys.stderr);sys.exit(1)
    if os.environ.get('ACTION_SLEEP'): time.sleep(3)
    Path(os.environ['STATE_FILE']).write_text(os.environ.get('AFTER',os.environ['CONTAINERS']))
else: sys.exit(9)
''')

    def calls(self):
        path = self.root / "calls"
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def mutations(self):
        return [call for call in self.calls() if any(op in call for op in ("up", "stop", "restart"))]

    def test_missing_or_ambiguous_target_is_json_usage_error_without_docker(self):
        for arguments in [("stop",), ("restart", "api", "--all"), ("start", "api", "extra"), ("wait", "api", "--timeout", "0")]:
            result = self.cli(*arguments, "--json")
            self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
            self.assertFalse(json.loads(result.stdout)["ok"])
            self.assertEqual(result.stderr, "")
        self.assertEqual(self.calls(), [])

    def test_container_alias_is_suggested_but_not_automatically_selected(self):
        result = self.cli("restart", "api-container", "--json")
        data = json.loads(result.stdout)
        self.assertEqual(data["error"]["code"], "unknown_service")
        self.assertIn("api", data["error"]["message"])
        self.assertEqual(self.mutations(), [])

    def test_inspect_reports_paths_dependencies_without_daemon_or_secrets(self):
        self.config["services"]["api"]["depends_on"] = {"database": {"condition": "service_healthy"}}
        result = self.cli("inspect", "api", "--json", extra={"DAEMON_FAIL": "1"})
        self.assertEqual(result.returncode, 0, result.stdout)
        row = json.loads(result.stdout)["services"][0]
        self.assertEqual(row["build_context"], str(self.root))
        self.assertEqual(row["depends_on"][0]["service"], "database")
        self.assertNotIn("SECRET", result.stdout)
        self.assertFalse(any("ps" in call for call in self.calls()))

    def test_dry_run_does_not_contact_daemon_or_mutate(self):
        result = self.cli("rebuild", "api", "--dry-run", "--json", extra={"DAEMON_FAIL": "1"})
        data = json.loads(result.stdout)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(data["state"], "planned")
        self.assertFalse(data["changed"])
        self.assertEqual(data["targets"], ["api"])
        self.assertIn("--build", data["plan"]["argv"])
        self.assertIn("--no-deps", data["plan"]["argv"])
        self.assertFalse(any("ps" in call for call in self.calls()))
        self.assertEqual(self.mutations(), [])

    def test_rebuild_is_one_targeted_up_and_waits_for_health(self):
        result = self.cli("rebuild", "api", "--json")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(len(self.mutations()), 1)
        action = self.mutations()[0]
        self.assertEqual(action[-5:], ["up", "--detach", "--build", "--no-deps", "api"])
        data = json.loads(result.stdout)
        self.assertEqual(data["state"], "ready")
        self.assertTrue(data["changed"])
        self.assertTrue(data["services"][0]["ready"])

    def test_missing_required_dependency_blocks_before_mutation(self):
        self.config["services"]["api"]["depends_on"] = {"database": {"condition": "service_healthy"}}
        result = self.cli("rebuild", "api", "--json")
        self.assertEqual(json.loads(result.stdout)["error"]["code"], "dependency_not_ready")
        self.assertEqual(self.mutations(), [])

    def test_with_deps_is_explicit_and_reports_dependency_closure(self):
        self.config["services"]["api"]["depends_on"] = {"database": {"condition": "service_healthy"}}
        result = self.cli("start", "api", "--with-deps", "--json")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(json.loads(result.stdout)["affected_services"], ["api", "database"])
        self.assertNotIn("--no-deps", self.mutations()[0])

    def test_completed_one_shot_dependency_can_satisfy_start(self):
        self.config["services"]["api"]["depends_on"] = {"database": {"condition": "service_completed_successfully"}}
        self.containers[1].update(State="exited", ExitCode=0)
        self.assertEqual(self.cli("start", "api", "--json").returncode, 0)

    def test_restart_never_restarts_dependencies(self):
        result = self.cli("restart", "api", "--json")
        self.assertEqual(result.returncode, 0)
        self.assertEqual(self.mutations()[0][-3:], ["restart", "--no-deps", "api"])

    def test_wait_follows_starting_to_healthy_without_mutations(self):
        starting = [dict(self.containers[0], Health="starting")]
        result = self.cli("wait", "api", "--timeout", "4", "--json", extra={"STEPS": json.dumps([starting, self.containers])})
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(json.loads(result.stdout)["state"], "ready")
        self.assertEqual(self.mutations(), [])

    def test_wait_timeout_has_nonzero_exit_and_last_state(self):
        self.containers[0]["Health"] = "starting"
        start = time.monotonic()
        result = self.cli("wait", "api", "--timeout", "1", "--json")
        self.assertLess(time.monotonic() - start, 3)
        data = json.loads(result.stdout)
        self.assertEqual(result.returncode, 3)
        self.assertEqual(data["error"]["code"], "readiness_timeout")
        self.assertEqual(data["services"][0]["containers"][0]["health"], "starting")

    def test_unhealthy_replica_prevents_readiness(self):
        self.containers.append(dict(self.containers[0], Name="api-2", Health="unhealthy"))
        result = self.cli("wait", "api", "--timeout", "1", "--json")
        self.assertEqual(result.returncode, 3)

    def test_missing_configured_replica_prevents_readiness(self):
        self.config["services"]["api"]["deploy"] = {"replicas": 2}
        result = self.cli("wait", "api", "--timeout", "1", "--json")
        self.assertEqual(result.returncode, 3)
        row = json.loads(result.stdout)["services"][0]
        self.assertEqual(row["expected_replicas"], 2)
        self.assertFalse(row["ready"])

    def test_stop_is_scoped_and_reports_stopped(self):
        after = [dict(self.containers[0], State="exited", Health=""), self.containers[1]]
        result = self.cli("stop", "api", "--json", extra={"AFTER": json.dumps(after)})
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(json.loads(result.stdout)["state"], "stopped")
        self.assertEqual(self.mutations()[0][-2:], ["stop", "api"])

    def test_all_only_targets_configured_services_not_orphans(self):
        self.containers.append({"Service": "unmanaged", "State": "running"})
        result = self.cli("restart", "--all", "--json")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(json.loads(result.stdout)["targets"], ["api", "database"])
        self.assertNotIn("unmanaged", self.mutations()[0])

    def test_failed_action_suppresses_secrets_and_warns_of_partial_effects(self):
        result = self.cli("rebuild", "api", "--json", extra={"ACTION_FAIL": "1"})
        data = json.loads(result.stdout)
        self.assertEqual(result.returncode, 1)
        self.assertIsNone(data["changed"])
        self.assertEqual(data["state"], "unknown")
        self.assertIn("before retrying", data["error"]["next_action"])
        self.assertNotIn("never-print-this-secret", result.stdout + result.stderr)
        self.assertEqual(len(self.mutations()), 1)

    def test_timed_out_action_is_never_retried(self):
        result = self.cli("restart", "api", "--timeout", "1", "--json", extra={"ACTION_SLEEP": "1"})
        data = json.loads(result.stdout)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(data["error"]["code"], "command_timeout")
        self.assertIsNone(data["changed"])
        self.assertEqual(len(self.mutations()), 1)

    def test_inspection_can_target_one_service_without_false_orphan_warnings(self):
        result = self.cli("doctor", "api", "--json")
        data = json.loads(result.stdout)
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual([row["service"] for row in data["services"]], ["api"])
        self.assertEqual(data["orphans"], [])

    def test_rebuild_rejects_image_only_service(self):
        result = self.cli("rebuild", "database", "--json")
        self.assertEqual(json.loads(result.stdout)["error"]["code"], "no_build_context")
        self.assertEqual(self.mutations(), [])


if __name__ == "__main__":
    unittest.main()
