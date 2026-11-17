#!/usr/bin/env bats

setup() {
  TEST_TEMP_DIR="$(mktemp -d)"
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  INIT_SH="${REPO_ROOT}/gradle-plugin-bootstrap/init-gradle.sh"
}

teardown() {
  rm -rf "${TEST_TEMP_DIR}"
}

@test "prints usage on --help" {
  run sh "${INIT_SH}" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: init-gradle.sh [OPTIONS]"* ]]
  [[ "$output" == *"--gradle-version"* ]]
  [[ "$output" == *"--force"* ]]
}

@test "fails on unknown option" {
  run sh "${INIT_SH}" --bogus
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unknown option: --bogus"* ]]
}

@test "fails when --gradle-version value is missing" {
  run sh "${INIT_SH}" --gradle-version
  [ "$status" -ne 0 ]
  [[ "$output" == *"Option --gradle-version requires a value."* ]]
}

@test "skips when gradlew already exists without --force" {
  local target="${TEST_TEMP_DIR}/repo"
  mkdir -p "${target}"
  cat >"${target}/gradlew" <<'EOF'
#!/usr/bin/env sh
exit 0
EOF
  chmod +x "${target}/gradlew"

  run env TARGET_DIR="${target}" sh "${INIT_SH}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Gradle wrapper already exists"* ]]
}

@test "regenerates wrapper when gradlew exists and --force is passed" {
  local target="${TEST_TEMP_DIR}/repo"
  local fake_bin="${TEST_TEMP_DIR}/fake-bin"
  local args_log="${TEST_TEMP_DIR}/gradle-args.log"
  mkdir -p "${target}" "${fake_bin}"

  cat >"${target}/gradlew" <<'EOF'
#!/usr/bin/env sh
exit 0
EOF
  chmod +x "${target}/gradlew"

  cat >"${fake_bin}/gradle" <<EOF
#!/usr/bin/env sh
printf '%s\n' "\$@" > "${args_log}"
EOF
  chmod +x "${fake_bin}/gradle"

  run env TARGET_DIR="${target}" PATH="${fake_bin}:${PATH}" sh "${INIT_SH}" --force --gradle-version 9.0.0
  [ "$status" -eq 0 ]
  [[ "$output" == *"Gradle wrapper initialized successfully."* ]]
  run cat "${args_log}"
  [[ "$output" == *"--no-daemon"* ]]
  [[ "$output" == *"--project-dir"* ]]
  [[ "$output" == *"${target}"* ]]
  [[ "$output" == *"wrapper"* ]]
  [[ "$output" == *"--gradle-version"* ]]
  [[ "$output" == *"9.0.0"* ]]
  [[ "$output" == *"--distribution-type"* ]]
  [[ "$output" == *"bin"* ]]
}

@test "uses cached gradle when gradle is not on PATH" {
  local cache="${TEST_TEMP_DIR}/cache"
  local fake_bin="${TEST_TEMP_DIR}/fake-bin"
  mkdir -p "${cache}/gradle-8.14/bin" "${fake_bin}"

  cat >"${cache}/gradle-8.14/bin/gradle" <<'EOF'
#!/usr/bin/env sh
exit 0
EOF
  chmod +x "${cache}/gradle-8.14/bin/gradle"

  cat >"${fake_bin}/java" <<'EOF'
#!/usr/bin/env sh
exit 0
EOF
  chmod +x "${fake_bin}/java"

  run env INIT_GRADLE_SOURCE_ONLY=1 sh -c "PATH='${fake_bin}'; export PATH; . '${INIT_SH}'; CACHE_DIR='${cache}'; GRADLE_VERSION='8.14'; resolve_gradle_bin"
  [ "$status" -eq 0 ]
  [ "$output" = "${cache}/gradle-8.14/bin/gradle" ]
}

@test "resolve_gradle_version resolves latest from Gradle versions endpoint" {
  local fake_bin="${TEST_TEMP_DIR}/fake-bin"
  mkdir -p "${fake_bin}"
  cat >"${fake_bin}/curl" <<'EOF'
#!/usr/bin/env sh
printf '{\n  "version" : "9.9.2",\n  "current" : true\n}\n'
EOF
  chmod +x "${fake_bin}/curl"

  run env INIT_GRADLE_SOURCE_ONLY=1 sh -c "PATH='${fake_bin}:/bin:/usr/bin'; export PATH; . '${INIT_SH}'; GRADLE_VERSION='latest'; resolve_gradle_version"
  [ "$status" -eq 0 ]
  [ "$output" = "9.9.2" ]
}

@test "resolve_gradle_version falls back when endpoint is unavailable" {
  local fake_bin="${TEST_TEMP_DIR}/fake-bin"
  mkdir -p "${fake_bin}"
  cat >"${fake_bin}/curl" <<'EOF'
#!/usr/bin/env sh
exit 1
EOF
  chmod +x "${fake_bin}/curl"

  run env INIT_GRADLE_SOURCE_ONLY=1 sh -c "PATH='${fake_bin}:/bin:/usr/bin'; export PATH; . '${INIT_SH}'; GRADLE_VERSION='latest'; resolve_gradle_version"
  [ "$status" -eq 0 ]
  [ "$output" = "9.9.1" ]
}

@test "fails when neither gradle nor java is available" {
  local empty_bin="${TEST_TEMP_DIR}/empty-bin"
  mkdir -p "${empty_bin}"

  run env INIT_GRADLE_SOURCE_ONLY=1 sh -c "PATH='${empty_bin}'; export PATH; . '${INIT_SH}'; resolve_gradle_bin"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Java is required to run Gradle but was not found on PATH."* ]]
}

@test "fails when java is present without gradle or curl" {
  local fake_bin="${TEST_TEMP_DIR}/fake-bin"
  local cache="${TEST_TEMP_DIR}/empty-cache"
  mkdir -p "${fake_bin}" "${cache}"

  cat >"${fake_bin}/java" <<'EOF'
#!/usr/bin/env sh
exit 0
EOF
  chmod +x "${fake_bin}/java"

  run env INIT_GRADLE_SOURCE_ONLY=1 sh -c "PATH='${fake_bin}'; export PATH; . '${INIT_SH}'; CACHE_DIR='${cache}'; resolve_gradle_bin"
  [ "$status" -ne 0 ]
  [[ "$output" == *"'curl' is required to download Gradle"* ]]
}
