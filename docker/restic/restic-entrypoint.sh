#!/bin/sh

set -eu

MARKER="/state/initialized"
READY="/tmp/restic-ready"
CONFIG_JSON="/tmp/restic-config.json"
SNAPSHOTS_JSON="/tmp/restic-snapshots.json"
ERROR_LOG="/tmp/restic-error.log"

BACKUP_INTERVAL="${RESTIC_BACKUP_INTERVAL:-300}"
LOCK_RETRY="${RESTIC_LOCK_RETRY:-2m}"

LAST_RETENTION_RUN="/state/last-retention"

RETENTION_INTERVAL="${RESTIC_RETENTION_INTERVAL:-86400}"

KEEP_HOURLY="${RESTIC_RETENTION_KEEP_HOURLY:-24}"
KEEP_DAILY="${RESTIC_RETENTION_KEEP_DAILY:-7}"
KEEP_WEEKLY="${RESTIC_RETENTION_KEEP_WEEKLY:-4}"
KEEP_MONTHLY="${RESTIC_RETENTION_KEEP_MONTHLY:-6}"

log() {
  printf '%s %s\n' \
    "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    "$*"
}

restic_cmd() {
  restic \
    --retry-lock "${LOCK_RETRY}" \
    -o s3.bucket-lookup=path \
    "$@"
}

local_data_exists() {
  # Application volumes must be mounted one level beneath /data.
  # Empty mount-point directories do not count as application data.
  find /data \
    -mindepth 2 \
    ! -type d \
    -print -quit |
    grep -q .
}

probe_repository() {
  if restic_cmd --json cat config \
    >"${CONFIG_JSON}" \
    2>"${ERROR_LOG}"
  then
    REPOSITORY_EXISTS=true
    REPOSITORY_ID="$(jq -er '.id' "${CONFIG_JSON}")"
    return
  else
    status=$?
  fi

  # Restic returns status 10 when repository does not exist.
  if [ "${status}" -eq 10 ]; then
    REPOSITORY_EXISTS=false
    REPOSITORY_ID=""
    return
  fi

  cat "${ERROR_LOG}" >&2
  log "ERROR: Unable to inspect the Restic repository (status ${status})."
  exit "${status}"
}

probe_snapshots() {
  if ! restic_cmd --json snapshots >"${SNAPSHOTS_JSON}"; then
    log "ERROR: Unable to inspect repository snapshots."
    exit 1
  fi

  if jq -e 'length > 0' "${SNAPSHOTS_JSON}" >/dev/null; then
    SNAPSHOTS_EXIST=true
  else
    SNAPSHOTS_EXIST=false
  fi
}

initialize_repository() {
  log "Initializing Restic repository ${RESTIC_REPOSITORY}..."

  if ! restic_cmd --json init >"${CONFIG_JSON}"; then
    log "ERROR: Restic repository initialization failed."
    exit 1
  fi

  REPOSITORY_ID="$(jq -er '.id' "${CONFIG_JSON}")"
  REPOSITORY_EXISTS=true
  SNAPSHOTS_EXIST=false
}

validate_marker() {
  marker_repository_id="$(cat "${MARKER}")"

  if [ "${marker_repository_id}" != "${REPOSITORY_ID}" ]; then
    log "ERROR: State marker belongs to a different Restic repository."
    exit 1
  fi
}

write_marker() {
  printf '%s\n' "${REPOSITORY_ID}" >"${MARKER}"
}

backup_data() {
  log "Creating Restic snapshot of /data..."

  (
    cd /data

    restic_cmd backup \
      --group-by paths \
      --skip-if-unchanged \
      .
  )
}

restore_data() {
  log "Restoring the latest Restic snapshot into /data..."

  restic_cmd restore \
    latest \
    --target /data

  log "Restore completed successfully."
}

retention_run_is_due() {
  current_time="$(date +%s)"

  if [ ! -f "${LAST_RETENTION_RUN}" ]; then
    # Start the retention interval from the first successful backup.
    printf '%s\n' "${current_time}" > "${LAST_RETENTION_RUN}"
    return 1
  fi

  last_time="$(cat "${LAST_RETENTION_RUN}")"

  case "${last_time}" in
    ''|*[!0-9]*)
      log "WARNING: Invalid timestamp; retention will run."
      return 0
      ;;
  esac

  elapsed=$((current_time - last_time))

  [ "${elapsed}" -ge "${RETENTION_INTERVAL}" ]
}

run_retention() {
  log "Applying Restic snapshot retention and pruning..."

  if restic_cmd forget \
    --group-by paths \
    --keep-hourly "${KEEP_HOURLY}" \
    --keep-daily "${KEEP_DAILY}" \
    --keep-weekly "${KEEP_WEEKLY}" \
    --keep-monthly "${KEEP_MONTHLY}" \
    --prune
  then
    date +%s > "${LAST_RETENTION_RUN}"
    log "Restic retention run completed successfully."
    return 0
  else
    status=$?
    log "WARNING: Restic retention run failed with status ${status}."
    log "Retention run will be retried after the next successful backup."
    return "${status}"
  fi
}

initialize() {
  NEEDS_MARKER=false

  probe_repository

  # S3 bucket is empty or the repository is uninitialized
  if [ "${REPOSITORY_EXISTS}" = false ]; then
    initialize_repository
    NEEDS_MARKER=true

    # This block is for logging purposes only
    if local_data_exists; then
      log "Existing local data found; adopting it as the initial snapshot."
    else
      log "Local volumes are empty; creating a new empty backup set."
    fi

    return
  fi

  probe_snapshots

  # State marker exists.
  if [ -f "${MARKER}" ]; then
    validate_marker

    # Scenario: Marker = true, snapshots = true, local data = true
    # Action:   Normal startup of an already initialized stack.
    if local_data_exists; then
      if [ "${SNAPSHOTS_EXIST}" = true ]; then
        log "Local volumes and Restic repository are initialized."
      
      # Scenario: Marker = true, snapshots = false, local data = true
      # Action:   Create a new snapshot, then proceed with normal startup of an
      #           already initialized stack.
      else
        log "WARNING: State marker exists, but the repository has no snapshots."
        log "Existing local data will be used to create a new snapshot."
      fi

      return
    fi

    # Scenario: Marker = true, snapshots = true, local data = false
    # Action:   Restore data from repository to local volumes.
    if [ "${SNAPSHOTS_EXIST}" = true ]; then
      log "Local volumes are empty, but Restic snapshots exist."
      restore_data
      return
    fi

    # Scenario: Marker = true, snapshots = false, local data = false
    # Action:   Panic.
    log "ERROR: State marker exists, but local volumes are empty."
    log "ERROR: The Restic repository also contains no snapshots."
    log "There is no available source from which to recover."
    exit 1
  fi

  NEEDS_MARKER=true

  # Scenario: Marker = false, snapshots = true, local data = true
  # Action:   Panic.
  if [ "${SNAPSHOTS_EXIST}" = true ]; then
    if local_data_exists; then
      log "ERROR: Initialization marker is missing."
      log "ERROR: Both local data and Restic snapshots exist."
      log "Refusing to choose an authoritative source automatically."
      exit 1
    fi

    restore_data
    return
  fi

  # Add restic to an existing docker stack
  # Scenario: Marker = false, snapshots = false, local data = true
  # Action:   Accept existing local volume for initial snapshot.
  if local_data_exists; then
    log "Local data exists and the repository has no snapshots."
    log "Adopting the existing local volumes."
  
  # Scenario: Marker = false, snapshots = false, local data = false
  # Action:   New everything. Initialize everything as new.
  else
    log "Local volumes and the repository are empty."
    log "Initializing a new empty backup set."
  fi
}

initialize

# Take a snapshot before other services start.
backup_data

if [ "${NEEDS_MARKER}" = true ]; then
  write_marker
fi

touch "${READY}"
log "Restic initialization and initial snapshot completed."

while true; do
  sleep "${BACKUP_INTERVAL}"

  if backup_data; then
    log "Snapshot cycle completed successfully."

    if retention_run_is_due; then
      run_retention || true
    fi
  else
    status=$?
    log "WARNING: Snapshot cycle failed with status ${status}."
    log "The next scheduled cycle will retry."
  fi
done