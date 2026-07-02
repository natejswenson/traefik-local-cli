#!/usr/bin/env bats
# Mechanical regression checks for the highest-stakes textual invariants in
# scripts/.claude/skills/tk/SKILL.md (docs/plans/2026-07-01-tk-cli-skill-design.md,
# Testing Strategy). These do NOT validate behavior — only that the load-bearing
# prose rules haven't been silently deleted or edited out of the skill file.

load '../test_helper'

SKILL_FILE="${SCRIPTS_DIR}/.claude/skills/tk/SKILL.md"

@test "tk skill package contains only SKILL.md (no bundled code files)" {
    assert_file_exists "$SKILL_FILE"
    local extra
    extra=$(find "${SCRIPTS_DIR}/.claude/skills/tk" -type f ! -name "SKILL.md")
    [ -z "$extra" ]
}

@test "tk skill still gates 'add' behind the PII/API question with a traefik-onboard redirect" {
    assert_file_contains "$SKILL_FILE" "PII"
    assert_file_contains "$SKILL_FILE" "traefik-onboard"
}

@test "tk skill's remove dispatch still bypasses tk's internal confirm prompt" {
    assert_file_contains "$SKILL_FILE" "CONFIRM_DESTRUCTIVE=false"
}

@test "tk skill's cleanup dispatch still uses the no-newline-separator printf fix" {
    # The actual dispatch command must use the fixed 'printf %s%s' form. The
    # surrounding prose legitimately mentions the broken '%s\n%s' form when
    # explaining the bug, so this only checks the dispatch line itself.
    assert_file_contains "$SKILL_FILE" "printf '%s%s'"
}

@test "tk skill still warns against --port/--domain/--harden on the rebuild dispatch" {
    assert_file_contains "$SKILL_FILE" "\-\-port"
    assert_file_contains "$SKILL_FILE" "\-\-domain"
    assert_file_contains "$SKILL_FILE" "\-\-harden"
}

@test "tk skill's rebuild-vs-name-conflict check still compares build.context, not name alone" {
    assert_file_contains "$SKILL_FILE" "build.context"
    assert_file_contains "$SKILL_FILE" "name match alone"
}
