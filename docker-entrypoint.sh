#!/bin/sh
set -eu

TARGET_HOME="${HERMES_HOME:-/opt/data}"
BOOTSTRAP_HOME="${HERMES_BOOTSTRAP_HOME:-}"
FORCE_BOOTSTRAP="${HERMES_BOOTSTRAP_FORCE:-false}"
TARGET_UID="${HERMES_UID:-10000}"
TARGET_GID="${HERMES_GID:-10000}"
AUTO_UPDATE="${HERMES_AUTO_UPDATE:-true}"
AUTO_UPDATE_ARGS="${HERMES_AUTO_UPDATE_ARGS:---yes --gateway}"
AUTO_UPDATE_REQUIRED="${HERMES_AUTO_UPDATE_REQUIRED:-false}"

ensure_hermes_update_permissions() {
  chown hermes:hermes /opt/hermes /opt/hermes/package.json /opt/hermes/README.md 2>/dev/null || true
  chown -R hermes:hermes /opt/hermes/.venv /opt/hermes/hermes_agent.egg-info /opt/hermes/hermes_cli/web_dist 2>/dev/null || true
}

copy_if_needed() {
  source_path="$1"
  target_path="$2"

  if [ ! -f "$source_path" ]; then
    return 0
  fi

  if [ "$FORCE_BOOTSTRAP" = "true" ] || [ ! -f "$target_path" ]; then
    mkdir -p "$(dirname "$target_path")"
    cp "$source_path" "$target_path"
  fi
}

copy_dir_if_needed() {
  source_path="$1"
  target_path="$2"

  if [ ! -d "$source_path" ]; then
    return 0
  fi

  if [ "$FORCE_BOOTSTRAP" = "true" ] || [ ! -d "$target_path" ]; then
    mkdir -p "$target_path"
    cp -R "$source_path"/. "$target_path"/
  fi
}

copy_bootstrap_home() {
  source_home="$1"
  target_home="$2"

  mkdir -p "$target_home/cron" "$target_home/hooks" "$target_home/logs" \
    "$target_home/memories" "$target_home/sessions" "$target_home/skills" \
    "$target_home/skins"

  copy_if_needed "$source_home/config.yaml" "$target_home/config.yaml"
  copy_if_needed "$source_home/.env" "$target_home/.env"
  copy_if_needed "$source_home/SOUL.md" "$target_home/SOUL.md"
  copy_dir_if_needed "$source_home/skills" "$target_home/skills"
  copy_dir_if_needed "$source_home/profiles" "$target_home/profiles"
}

run_hermes_update() {
  cd /opt/hermes
  export VIRTUAL_ENV=/opt/hermes/.venv
  export PATH="$VIRTUAL_ENV/bin:$PATH"
  export UV_LINK_MODE="${UV_LINK_MODE:-copy}"
  gosu hermes /opt/hermes/hermes update $AUTO_UPDATE_ARGS
}

mkdir -p "$TARGET_HOME"

if [ -n "$BOOTSTRAP_HOME" ] && [ -d "$BOOTSTRAP_HOME" ]; then
  copy_bootstrap_home "$BOOTSTRAP_HOME" "$TARGET_HOME"

  # Some Hermes Desktop/TUI and legacy resume paths still inspect a nested
  # .hermes home. Keep it aligned with the managed Docker home so stale custom
  # provider metadata cannot shadow the current bootstrap config.
  copy_bootstrap_home "$BOOTSTRAP_HOME" "$TARGET_HOME/.hermes"
fi

chown -R "$TARGET_UID:$TARGET_GID" "$TARGET_HOME"

case "$AUTO_UPDATE" in
  true|TRUE|1|yes|YES)
    if [ "${1:-}" != "update" ]; then
      echo "Updating Hermes Agent before container start..."
      ensure_hermes_update_permissions
      if ! run_hermes_update; then
        if [ "$AUTO_UPDATE_REQUIRED" = "true" ]; then
          echo "Hermes auto-update failed and HERMES_AUTO_UPDATE_REQUIRED=true." >&2
          exit 1
        fi
        echo "Warning: Hermes auto-update failed; continuing with installed version." >&2
      fi
      chown -R hermes:hermes /opt/hermes/.venv 2>/dev/null || true
    fi
    ;;
esac

if [ -x /opt/hermes/docker/main-wrapper.sh ]; then
  if [ "$(readlink /usr/bin/tini 2>/dev/null || true)" = "/init" ]; then
    exec /usr/bin/tini /opt/hermes/docker/main-wrapper.sh "$@"
  fi

  exec /usr/bin/tini -g -- /opt/hermes/docker/main-wrapper.sh "$@"
fi

exec /usr/bin/tini -g -- /opt/hermes/docker/entrypoint.sh "$@"
