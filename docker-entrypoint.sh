#!/bin/sh
set -eu

TARGET_HOME="${HERMES_HOME:-/opt/data}"
BOOTSTRAP_HOME="${HERMES_BOOTSTRAP_HOME:-}"
FORCE_BOOTSTRAP="${HERMES_BOOTSTRAP_FORCE:-false}"
TARGET_UID="${HERMES_UID:-10000}"
TARGET_GID="${HERMES_GID:-10000}"

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

mkdir -p "$TARGET_HOME"

if [ -n "$BOOTSTRAP_HOME" ] && [ -d "$BOOTSTRAP_HOME" ]; then
  mkdir -p "$TARGET_HOME/cron" "$TARGET_HOME/hooks" "$TARGET_HOME/logs" \
    "$TARGET_HOME/memories" "$TARGET_HOME/sessions" "$TARGET_HOME/skills" \
    "$TARGET_HOME/skins"

  copy_if_needed "$BOOTSTRAP_HOME/config.yaml" "$TARGET_HOME/config.yaml"
  copy_if_needed "$BOOTSTRAP_HOME/.env" "$TARGET_HOME/.env"
  copy_if_needed "$BOOTSTRAP_HOME/SOUL.md" "$TARGET_HOME/SOUL.md"
fi

chown -R "$TARGET_UID:$TARGET_GID" "$TARGET_HOME"

exec /usr/bin/tini -g -- /opt/hermes/docker/entrypoint.sh "$@"