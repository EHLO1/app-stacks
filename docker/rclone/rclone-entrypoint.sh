#!/bin/sh

set -eu

MARKER="/state/initialized"
READY="/tmp/rclone-ready"
REMOTE="s3:${RCLONE_S3_BUCKET}"

log() {
  printf '%s %s\n' \
    "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    "$*"
}

local_data_exists() {
  # Application volumes are mounted in /data.
  # The mounted directories don't count for rclone, so go 1 level deeper, and ignore empty directories.
  [ -n "$(find /data -mindepth 2 ! -type d -print -quit)" ]
}

get_remote_listing() {
  REMOTE_LISTING_FILE="$(mktemp)"

  if ! rclone lsf \
    "${REMOTE}" \
    --recursive \
    --config /dev/null \
    > "${REMOTE_LISTING_FILE}"
  then
    rm -f "${REMOTE_LISTING_FILE}"
    log "ERROR: Unable to inspect ${REMOTE}."
    exit 1
  fi
}

remote_data_exists() {
  [ -s "${REMOTE_LISTING_FILE}" ]
}

write_marker() {
  printf '%s\n' "${RCLONE_S3_BUCKET}" > "${MARKER}"
}

initialize() {
  if [ -f "${MARKER}" ]; then
    if [ "$(cat "${MARKER}")" != "${RCLONE_S3_BUCKET}" ]; then
      log "ERROR: State marker belongs to a different S3 bucket."
      exit 1
    fi

    log "Local volumes are already initialized."
    return
  fi

  get_remote_listing

  if local_data_exists; then
    if remote_data_exists; then
      rm -f "${REMOTE_LISTING_FILE}"

      log "ERROR: Initialization marker is missing."
      log "ERROR: Both local data and remote data exist."
      log "Refusing to choose an authoritative source automatically."
      exit 1
    fi
  
    rm -f "${REMOTE_LISTING_FILE}"

    log "Local data exists and the S3 bucket is empty."
    log "Adopting the existing local volumes."

    write_marker
    return
  fi

  if remote_data_exists; then
    rm -f "${REMOTE_LISTING_FILE}"

    log "Local volumes are empty."
    log "Restoring data from ${REMOTE}..."

    rclone sync \
      "${REMOTE}" \
      /data \
      --config /dev/null \
      --metadata \
      --links \
      --create-empty-src-dirs \
      --local-metadata-restore-special-bits \
      --verbose \
      --stats 30s

    write_marker
    log "Initial restore completed successfully."
    return
  fi

  rm -f "${REMOTE_LISTING_FILE}"

  log "Local volumes and the S3 bucket are empty."
  log "Initializing a new empty stack."

  write_marker
}

sync_to_s3() {
  log "Synchronizing local volumes to ${REMOTE}..."

  rclone sync \
    /data \
    "${REMOTE}" \
    --config /dev/null \
    --metadata \
    --links \
    --create-empty-src-dirs \
    --verbose \
    --stats 30s
}

initialize

# Populate or confirm the bucket before dependent services start.
sync_to_s3

touch "${READY}"
log "Rclone initialization and initial synchronization complete."

while true; do
  sleep "${RCLONE_SYNC_INTERVAL}"

  if sync_to_s3; then
    log "Synchronization completed successfully."
  else
    status=$?
    log "WARNING: Synchronization failed with status ${status}."
    log "Synchronization will be retried on the next interval."
  fi
done