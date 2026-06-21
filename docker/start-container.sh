#!/bin/bash
set -euo pipefail

TZ=${TZ:-UTC}
export TZ

SERVER_ROOT="/home/container"
cd "${SERVER_ROOT}"

ensure_runtime_tools() {
  for cmd in python3 bash; do
    if ! command -v "${cmd}" >/dev/null 2>&1; then
      echo "[Startup] ${cmd} is not available in image." >&2
      exit 1
    fi
  done
}

bool_is_true() {
  case "${1:-false}" in
    true|TRUE|1|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

is_unsafe_user_command() {
  local cmd="${1:-}"
  case "${cmd}" in
    *";"*|*"&&"*|*"||"*|*"|"*|*'`'*|*'$('*|*">"*|*"<"*|*$'\n'*|*$'\r'*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

validate_user_command() {
  local cmd="${1:-}"
  local label="${2:-command}"

  if [ -z "${cmd}" ]; then
    echo "[Startup] ${label} is empty." >&2
    exit 1
  fi

  if is_unsafe_user_command "${cmd}"; then
    echo "[Startup] ${label} contains blocked shell operators. Use a simple command." >&2
    exit 1
  fi
}

setup_python_env() {
  # pip/uv --target packages directory
  if [ -d "${SERVER_ROOT}/packages" ]; then
    export PYTHONPATH="${SERVER_ROOT}/packages${PYTHONPATH:+:${PYTHONPATH}}"
    export PATH="${SERVER_ROOT}/packages/bin:${PATH}"
    echo "[Startup] Packages loaded from ${SERVER_ROOT}/packages"
  fi

  # poetry/pipenv in-project virtual environment
  if [ -d "${SERVER_ROOT}/.venv/bin" ]; then
    local sys_python
    sys_python="$(command -v python3 2>/dev/null || true)"

    if [ -n "${sys_python}" ]; then
      find "${SERVER_ROOT}/.venv/bin" -maxdepth 1 -type f 2>/dev/null | \
      while IFS= read -r f; do
        local first_line
        first_line="$(head -1 "${f}" 2>/dev/null)" || continue
        case "${first_line}" in
          "#!"*python*) sed -i "1s|^#!.*|#!${sys_python}|" "${f}" ;;
        esac
      done
    fi

    export VIRTUAL_ENV="${SERVER_ROOT}/.venv"
    export PATH="${VIRTUAL_ENV}/bin:${PATH}"
    unset PYTHONHOME
    echo "[Startup] Virtual environment activated at ${SERVER_ROOT}/.venv"
  fi
}

resolve_start_command() {
  START_COMMAND="${START_CMD:-python main.py}"
  validate_user_command "${START_COMMAND}" "START_CMD"
}

run_build_on_start_if_enabled() {
  if ! bool_is_true "${ENABLE_BUILD_ON_START:-false}"; then
    return 0
  fi

  local build_cmd="${BUILD_CMD:-}"
  validate_user_command "${build_cmd}" "BUILD_CMD"

  echo "[Startup] Running build command on start: ${build_cmd}"
  bash -lc "cd ${SERVER_ROOT} && ${build_cmd}"
}

run_python_app() {
  local port="${SERVER_PORT:-8080}"
  export PORT="${port}"
  echo "[Startup] Using PORT=${PORT}"
  echo "[Startup] Python application started"
  exec bash -lc "cd ${SERVER_ROOT} && ${START_COMMAND}"
}

ensure_runtime_tools
setup_python_env
resolve_start_command
run_build_on_start_if_enabled
run_python_app
