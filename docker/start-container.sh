#!/bin/bash
set -euo pipefail

TZ=${TZ:-UTC}
export TZ

SERVER_ROOT="/home/container"
echo "[Startup] Entrypoint reached as $(id -un 2>/dev/null || whoami) in $(pwd)"
echo "[Startup] Server root: ${SERVER_ROOT}"
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

bootstrap_app_if_needed() {
  if [ -f "${SERVER_ROOT}/main.py" ] || [ -f "${SERVER_ROOT}/app.py" ] || \
     [ -f "${SERVER_ROOT}/bot.py" ]; then
    return 0
  fi

  echo "[Startup] No Python entrypoint found. Creating minimal online application..."
  if [ ! -f "${SERVER_ROOT}/requirements.txt" ]; then
    cat > "${SERVER_ROOT}/requirements.txt" << 'REQEOF'
# Hello World bot template.
# No external Python packages are required.
REQEOF
  fi

  cat > "${SERVER_ROOT}/main.py" << 'PYEOF'
import http.server
import os
import socketserver
import threading
import time

bot_name = os.environ.get('BOT_NAME', 'HelloWorldBot')
port = int(os.environ.get('PORT', '8080'))

print(f'{bot_name} is online', flush=True)

class HealthHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = f'{bot_name} is online\n'.encode()
        self.send_response(200)
        self.send_header('Content-Type', 'text/plain; charset=utf-8')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        return

class ReusableTCPServer(socketserver.TCPServer):
    allow_reuse_address = True

def serve_health():
    with ReusableTCPServer(('0.0.0.0', port), HealthHandler) as httpd:
        print(f'{bot_name}: health server listening on 0.0.0.0:{port}', flush=True)
        httpd.serve_forever()

threading.Thread(target=serve_health, daemon=True).start()

while True:
    print(f'{bot_name}: hello world heartbeat', flush=True)
    time.sleep(60)
PYEOF
}

ensure_package_manager() {
  local pm="${1:-pip}"
  [ "${pm}" = "pip" ] && return 0
  command -v "${pm}" >/dev/null 2>&1 && return 0
  echo "[Startup] ${pm} not found. Installing via pip..."
  pip install --quiet --no-cache-dir "${pm}"
}

auto_install_if_needed() {
  local pm="${PACKAGE_MANAGER:-pip}"

  if [ -d "${SERVER_ROOT}/packages" ] || [ -d "${SERVER_ROOT}/.venv" ]; then
    return 0
  fi

  echo "[Startup] Packages not found. Running first-time install with ${pm}..."
  ensure_package_manager "${pm}"

  case "${pm}" in
    pip)
      if [ -f "${SERVER_ROOT}/requirements.txt" ]; then
        mkdir -p "${SERVER_ROOT}/packages"
        pip install --no-cache-dir --target="${SERVER_ROOT}/packages" -r "${SERVER_ROOT}/requirements.txt"
      elif [ -f "${SERVER_ROOT}/pyproject.toml" ]; then
        mkdir -p "${SERVER_ROOT}/packages"
        pip install --no-cache-dir --target="${SERVER_ROOT}/packages" "${SERVER_ROOT}"
      fi
      ;;
    uv)
      if [ -f "${SERVER_ROOT}/requirements.txt" ]; then
        mkdir -p "${SERVER_ROOT}/packages"
        uv pip install --no-cache --target="${SERVER_ROOT}/packages" -r "${SERVER_ROOT}/requirements.txt"
      elif [ -f "${SERVER_ROOT}/pyproject.toml" ]; then
        mkdir -p "${SERVER_ROOT}/packages"
        uv pip install --no-cache --target="${SERVER_ROOT}/packages" "${SERVER_ROOT}"
      fi
      ;;
    poetry)
      if [ -f "${SERVER_ROOT}/pyproject.toml" ]; then
        poetry config virtualenvs.in-project true
        poetry config cache-dir /tmp/poetry-cache
        poetry install --no-interaction
      fi
      ;;
    pipenv)
      export PIPENV_VENV_IN_PROJECT=1
      export PIPENV_CACHE_DIR=/tmp/pipenv-cache
      if [ -f "${SERVER_ROOT}/Pipfile" ]; then
        pipenv install --dev
      elif [ -f "${SERVER_ROOT}/requirements.txt" ]; then
        pipenv install --dev -r "${SERVER_ROOT}/requirements.txt"
      fi
      ;;
  esac

  echo "[Startup] First-time install complete."
}

setup_python_env() {
  if [ -d "${SERVER_ROOT}/packages" ]; then
    export PYTHONPATH="${SERVER_ROOT}/packages${PYTHONPATH:+:${PYTHONPATH}}"
    export PATH="${SERVER_ROOT}/packages/bin:${PATH}"
    echo "[Startup] Packages loaded from ${SERVER_ROOT}/packages"
  fi

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
bootstrap_app_if_needed
auto_install_if_needed
setup_python_env
resolve_start_command
run_build_on_start_if_enabled
run_python_app
