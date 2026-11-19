#!/usr/bin/env sh
set -eu

GRADLE_VERSION="${GRADLE_VERSION:-latest}"
FALLBACK_GRADLE_VERSION="9.9.1"
FORCE="false"
TARGET_DIR="${TARGET_DIR:-.}"
TMP_DIR=""

usage() {
  cat <<'EOF'
Usage: init-gradle.sh [OPTIONS]

Initialize the Gradle wrapper in the current directory without requiring a
system-wide Gradle installation.

Options:
      --gradle-version <ver>   Gradle version for wrapper/download (default: latest)
      --force                  Regenerate wrapper even if ./gradlew exists
  -h, --help                   Show this help message
EOF
}

cleanup() {
  if [ -n "${TMP_DIR}" ] && [ -d "${TMP_DIR}" ]; then
    rm -rf "${TMP_DIR}"
  fi
}

log_info() {
  printf '%s\n' "[init-gradle] $*"
}

log_err() {
  printf '%s\n' "[init-gradle] ERROR: $*" >&2
}

require_arg() {
  if [ "$#" -lt 2 ] || [ -z "$2" ]; then
    log_err "Option $1 requires a value."
    usage >&2
    exit 1
  fi
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --gradle-version)
        require_arg "$1" "${2:-}"
        GRADLE_VERSION="$2"
        shift 2
        ;;
      --force)
        FORCE="true"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        log_err "Unknown option: $1"
        usage >&2
        exit 1
        ;;
    esac
  done
}

resolve_gradle_version() {
  if [ "${GRADLE_VERSION}" != "latest" ]; then
    printf '%s\n' "${GRADLE_VERSION}"
    return 0
  fi
  if command -v curl >/dev/null 2>&1; then
    resolved="$(curl -sSLf "https://services.gradle.org/versions/current" 2>/dev/null | sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1 || true)"
    if [ -n "${resolved}" ]; then
      printf '%s\n' "${resolved}"
      return 0
    fi
  fi
  printf '%s\n' "${FALLBACK_GRADLE_VERSION}"
}

resolve_gradle_bin() {
  if command -v gradle >/dev/null 2>&1; then
    command -v gradle
    return 0
  fi

  if ! command -v java >/dev/null 2>&1; then
    log_err "Java is required to run Gradle but was not found on PATH."
    exit 1
  fi

  dl_version="$(resolve_gradle_version)"
  dl_dir="${TMP_DIR:-$(mktemp -d)}"
  temp_gradle="${dl_dir}/gradle-${dl_version}/bin/gradle"
  if [ -x "${temp_gradle}" ]; then
    printf '%s\n' "${temp_gradle}"
    return 0
  fi

  if ! command -v curl >/dev/null 2>&1; then
    log_err "'curl' is required to download Gradle ${dl_version} when gradle is not installed."
    exit 1
  fi

  zip_path="${dl_dir}/gradle-${dl_version}-bin.zip"
  dist_url="https://services.gradle.org/distributions/gradle-${dl_version}-bin.zip"
  printf '%s\n' "[init-gradle] Downloading Gradle ${dl_version}..." >&2
  curl -sSLf "${dist_url}" -o "${zip_path}"
  if command -v unzip >/dev/null 2>&1; then
    unzip -q -o "${zip_path}" -d "${dl_dir}"
  elif command -v python3 >/dev/null 2>&1; then
    python3 -m zipfile -e "${zip_path}" "${dl_dir}"
  elif command -v jar >/dev/null 2>&1; then
    (cd "${dl_dir}" && jar xf "${zip_path}")
  else
    rm -f "${zip_path}"
    log_err "'unzip', 'python3', or 'jar' is required to extract Gradle ${dl_version}."
    exit 1
  fi
  rm -f "${zip_path}"
  if [ -f "${temp_gradle}" ]; then
    chmod +x "${temp_gradle}"
  fi

  if [ ! -x "${temp_gradle}" ]; then
    log_err "Failed to install Gradle ${dl_version} into ${dl_dir}."
    exit 1
  fi

  printf '%s\n' "${temp_gradle}"
}

main() {
  parse_args "$@"

  if [ -x "${TARGET_DIR}/gradlew" ] && [ "${FORCE}" != "true" ]; then
    log_info "Gradle wrapper already exists at ${TARGET_DIR}/gradlew (use --force to regenerate)."
    return 0
  fi

  TMP_DIR="$(mktemp -d)"
  trap cleanup EXIT HUP INT TERM

  gradle_bin="$(resolve_gradle_bin)"
  log_info "Initializing Gradle wrapper ${GRADLE_VERSION} using ${gradle_bin}..."
  "${gradle_bin}" --no-daemon --project-dir "${TARGET_DIR}" wrapper --gradle-version "${GRADLE_VERSION}" --distribution-type bin
  log_info "Gradle wrapper initialized successfully."
}

if [ "${INIT_GRADLE_SOURCE_ONLY:-0}" != "1" ]; then
  main "$@"
fi
