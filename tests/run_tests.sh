#!/usr/bin/env sh
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "=== Running ShellCheck ==="
shellcheck "${REPO_ROOT}/gradle-plugin-bootstrap/init-gradle.sh" "${SCRIPT_DIR}/run_tests.sh"

echo "=== Running Bats Unit Tests ==="
bats "${SCRIPT_DIR}/init-gradle.bats"

echo "=== All shell script checks passed! ==="
