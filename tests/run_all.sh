#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log_dir="$(mktemp -d "${TMPDIR:-/tmp}/polyrhythm-tests.XXXXXX")"
trap 'rm -rf "$log_dir"' EXIT

for test_file in "$project_dir"/tests/*_test.gd; do
	test_name="${test_file#"$project_dir"/}"
	printf '\n==> %s\n' "$test_name"
	godot --headless --path "$project_dir" --log-file "$log_dir/engine.log" --script "res://$test_name" 2>&1 | tee "$log_dir/output.log"
	# Godot can exit successfully even when a GDScript failed to parse or execute.
	if rg -q 'SCRIPT ERROR:|Failed to load script' "$log_dir/output.log"; then
		exit 1
	fi
done
