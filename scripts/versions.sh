#!/usr/bin/env bash
# Check, upgrade, back up, and roll back the Floci pins in versions.env.
# Run it through mise: `mise run outdated | upgrade | backup | rollback`.
#
# Functions that can run inside `if` or `||` return explicitly on failure,
# because bash ignores `set -e` in those contexts.
set -euo pipefail

cd "$(dirname "$0")/.."

readonly VERSIONS_FILE=versions.env
readonly COMPOSE_FILE=floci-lab/docker-compose.yml
readonly DATA_PARENT=floci-lab
readonly BACKUP_DIR=floci-lab/backups
readonly RESTORE_TMP=floci-lab/.data-restore
readonly KEEP_BACKUPS=5
readonly HEALTH_TIMEOUT_SECONDS=90

readonly EMULATOR_REPO=floci-io/floci
readonly CONSOLE_REPO=floci-io/floci-ui

BACKUP_PATH=""

die() {
  echo "ERROR: $*" >&2
  exit 1
}

# ─── Pins ─────────────────────────────────────────────────────────────────────

pin() { sed -n "s/^$1=//p" "$VERSIONS_FILE"; }

pin_in() { sed -n "s/^$2=//p" "$1/versions.env"; }

set_pin() {
  sed "s/^$1=.*/$1=$2/" "$VERSIONS_FILE" >"$VERSIONS_FILE.tmp"
  mv "$VERSIONS_FILE.tmp" "$VERSIONS_FILE"
}

valid_version() { [[ $1 =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; }

major() { echo "${1%%.*}"; }

latest_release() {
  curl -fsSL "https://api.github.com/repos/$1/releases/latest" |
    grep -o '"tag_name": *"[^"]*"' | sed -n '1s/.*"\([^"]*\)"$/\1/p'
}

changelog_url() { echo "https://github.com/$1/blob/$2/CHANGELOG.md"; }

# ─── Lab ──────────────────────────────────────────────────────────────────────

# Read the pins from the file on every call. The task env still holds the old ones.
compose() {
  FLOCI_IMAGE_TAG="$(pin FLOCI_IMAGE_TAG)" FLOCI_UI_TAG="$(pin FLOCI_UI_TAG)" \
    docker compose -f "$COMPOSE_FILE" "$@"
}

lab_running() { [ -n "$(compose ps -q floci 2>/dev/null)" ]; }

start_lab() {
  docker network inspect floci-net >/dev/null 2>&1 ||
    docker network create floci-net >/dev/null || return 1
  compose up -d || return 1
}

wait_healthy() {
  local expected=$1 running
  local deadline=$((SECONDS + HEALTH_TIMEOUT_SECONDS))

  printf 'Waiting for the lab to become healthy'
  until mise run --quiet health >/dev/null 2>&1; do
    if ((SECONDS >= deadline)); then
      echo " timed out after ${HEALTH_TIMEOUT_SECONDS}s."
      return 1
    fi
    printf '.'
    sleep 3
  done
  echo

  running=$(curl -fsS http://localhost:4566/_floci/health |
    sed -n 's/.*"version":"\([^"]*\)".*/\1/p') || return 1
  if [ "$running" != "$expected" ]; then
    echo "The emulator reports version '$running'. Expected '$expected'." >&2
    return 1
  fi
  mise run --quiet health
}

# ─── Backups ──────────────────────────────────────────────────────────────────

list_backups() {
  mkdir -p "$BACKUP_DIR"
  find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d | sort -r
}

# Stops the lab so the WAL files are consistent. Sets BACKUP_PATH.
make_backup() {
  BACKUP_PATH="$BACKUP_DIR/$(date +%Y%m%d-%H%M%S)-floci-$(pin FLOCI_IMAGE_TAG)-ui-$(pin FLOCI_UI_TAG)"

  echo "Stopping the lab for a consistent backup..."
  compose down || return 1
  mkdir -p "$BACKUP_PATH" "$DATA_PARENT/data" || return 1
  tar -czf "$BACKUP_PATH/data.tar.gz" -C "$DATA_PARENT" data || return 1
  cp "$VERSIONS_FILE" "$BACKUP_PATH/versions.env" || return 1
  echo "Backup saved: $BACKUP_PATH"

  list_backups | tail -n +$((KEEP_BACKUPS + 1)) | while IFS= read -r old; do
    rm -rf "$old"
  done
}

restore_backup() {
  local dir=$1
  if [ ! -f "$dir/data.tar.gz" ] || [ ! -f "$dir/versions.env" ]; then
    echo "Incomplete backup: $dir" >&2
    return 1
  fi

  compose down || return 1

  # Extract first. The current data stays in place if the archive is bad.
  rm -rf "$RESTORE_TMP"
  mkdir -p "$RESTORE_TMP" || return 1
  tar -xzf "$dir/data.tar.gz" -C "$RESTORE_TMP" || return 1
  rm -rf "$DATA_PARENT/data"
  mv "$RESTORE_TMP/data" "$DATA_PARENT/data" || return 1
  rm -rf "$RESTORE_TMP"

  cp "$dir/versions.env" "$VERSIONS_FILE" || return 1
  start_lab || return 1
  wait_healthy "$(pin FLOCI_IMAGE_TAG)" || return 1
}

# ─── Output helpers ───────────────────────────────────────────────────────────

confirm() {
  local reply=""
  printf 'Type "yes" to continue: '
  read -r reply || true
  if [ "$reply" != "yes" ]; then
    echo "Cancelled. Nothing changed."
    exit 1
  fi
}

change_note() {
  local from=$1 to=$2 repo=$3 note
  note=$(changelog_url "$repo" "$to")
  if [ "$(major "$from")" != "$(major "$to")" ]; then
    note="MAJOR  $note"
  fi
  echo "$note"
}

# ─── Commands ─────────────────────────────────────────────────────────────────

cmd_outdated() {
  local latest_emulator latest_console tools
  latest_emulator=$(latest_release "$EMULATOR_REPO") || die "Cannot read the emulator releases from GitHub."
  latest_console=$(latest_release "$CONSOLE_REPO") || die "Cannot read the console releases from GitHub."

  printf '%-10s %-9s %-9s %s\n' COMPONENT PINNED LATEST NOTES
  outdated_row floci "$(pin FLOCI_IMAGE_TAG)" "$latest_emulator" "$EMULATOR_REPO"
  outdated_row floci-ui "$(pin FLOCI_UI_TAG)" "$latest_console" "$CONSOLE_REPO"

  echo
  echo "Tools in mise.toml:"
  tools=$(mise outdated --bump --local 2>/dev/null || true)
  echo "${tools:-  All up to date.}"
}

outdated_row() {
  local name=$1 pinned=$2 latest=$3 repo=$4 note="up to date"
  if [ "$pinned" != "$latest" ]; then
    note=$(change_note "$pinned" "$latest" "$repo")
  fi
  printf '%-10s %-9s %-9s %s\n' "$name" "$pinned" "$latest" "$note"
}

cmd_upgrade() {
  local cur_emulator cur_console new_emulator new_console
  cur_emulator=$(pin FLOCI_IMAGE_TAG)
  cur_console=$(pin FLOCI_UI_TAG)

  # No flags: both go to the latest release. With flags: only the named ones change.
  if [ -z "${usage_floci:-}" ] && [ -z "${usage_ui:-}" ]; then
    new_emulator=$(latest_release "$EMULATOR_REPO") || die "Cannot read the emulator releases from GitHub."
    new_console=$(latest_release "$CONSOLE_REPO") || die "Cannot read the console releases from GitHub."
  else
    new_emulator=${usage_floci:-$cur_emulator}
    new_console=${usage_ui:-$cur_console}
  fi
  valid_version "$new_emulator" || die "Emulator version must look like 1.2.3. Got: '$new_emulator'"
  valid_version "$new_console" || die "Console version must look like 1.2.3. Got: '$new_console'"

  if [ "$new_emulator" = "$cur_emulator" ] && [ "$new_console" = "$cur_console" ]; then
    echo "Already on floci $cur_emulator and floci-ui $cur_console. Nothing to do."
    return
  fi

  echo "Upgrade plan:"
  upgrade_row floci "$cur_emulator" "$new_emulator" "$EMULATOR_REPO"
  upgrade_row floci-ui "$cur_console" "$new_console" "$CONSOLE_REPO"
  echo
  echo "Read the changelogs before you continue."
  echo "The emulator can convert its data on upgrade. The backup is the only way back."
  confirm

  echo "Pulling the new images. The lab keeps running..."
  FLOCI_IMAGE_TAG=$new_emulator FLOCI_UI_TAG=$new_console \
    docker compose -f "$COMPOSE_FILE" pull || die "Pull failed. Nothing changed."

  make_backup || die "Backup failed. Pins not changed. Start the lab again with: mise run up"
  set_pin FLOCI_IMAGE_TAG "$new_emulator"
  set_pin FLOCI_UI_TAG "$new_console"

  if start_lab && wait_healthy "$new_emulator"; then
    echo
    echo "Upgrade complete: floci $new_emulator, floci-ui $new_console."
    echo "Commit versions.env to record it."
    return
  fi

  echo >&2
  echo "Health check failed. Last emulator log lines:" >&2
  compose logs --tail 20 floci >&2 || true
  echo "Restoring $BACKUP_PATH..." >&2
  restore_backup "$BACKUP_PATH" ||
    die "Restore failed. Backup kept at $BACKUP_PATH. Check: mise run logs"
  die "Upgrade rolled back. The lab runs floci $cur_emulator and floci-ui $cur_console again."
}

upgrade_row() {
  local name=$1 from=$2 to=$3 repo=$4
  if [ "$from" = "$to" ]; then
    printf '  %-10s %s (no change)\n' "$name" "$from"
  else
    printf '  %-10s %s → %s  %s\n' "$name" "$from" "$to" "$(change_note "$from" "$to" "$repo")"
  fi
}

cmd_backup() {
  local was_running=false
  if lab_running; then
    was_running=true
  fi

  make_backup || die "Backup failed."
  if $was_running && ! { start_lab && wait_healthy "$(pin FLOCI_IMAGE_TAG)"; }; then
    die "The lab did not start again. Check: mise run logs"
  fi
}

cmd_rollback() {
  local newest
  newest=$(list_backups | sed -n 1p)
  [ -n "$newest" ] || die "No backups in $BACKUP_DIR."

  echo "Newest backup: $newest"
  echo "  backup pins:  floci $(pin_in "$newest" FLOCI_IMAGE_TAG), floci-ui $(pin_in "$newest" FLOCI_UI_TAG)"
  echo "  current pins: floci $(pin FLOCI_IMAGE_TAG), floci-ui $(pin FLOCI_UI_TAG)"
  echo
  echo "WARNING: Emulator data written after this backup will be lost."
  confirm

  restore_backup "$newest" || die "Restore failed. Backup kept at $newest. Check: mise run logs"
  echo
  echo "Rollback complete. Commit versions.env if the pins changed."
}

case "${1:-}" in
  outdated) cmd_outdated ;;
  upgrade) cmd_upgrade ;;
  backup) cmd_backup ;;
  rollback) cmd_rollback ;;
  *) die "Usage: $0 outdated|upgrade|backup|rollback" ;;
esac
