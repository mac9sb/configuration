#!/bin/sh
set -eu

# ——— Logging ———
log() {
  level="${2:-INFO}"
  printf "%s [%s] %s\n" "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$level" "$1"
}

warn() { log "$*" "WARN"; }
die() { log "$*" "ERROR"; exit 1; }

# ——— Step timing ———
# step/step_done use a local-friendly pattern: step prints and records
# the start time, step_done computes the duration. When called inside
# a subshell (e.g. parallel_step), the global writes are intentionally
# scoped to the subshell, and timing is handled by wait_parallel_steps.
step() {
  STEP_NAME=$1
  STEP_START=$(date +%s)
  log "$STEP_NAME..."
}

step_done() {
  _step_end=$(date +%s)
  _step_dur=$((_step_end - STEP_START))
  log "$STEP_NAME done (${_step_dur}s)"
}

# ——— Total runtime ———
total_start() { TOTAL_START=$(date +%s); }
total_done() {
  TOTAL_END=$(date +%s)
  TOTAL_DUR=$((TOTAL_END - TOTAL_START))
  log "Total runtime: ${TOTAL_DUR}s"
}

# ——— Parallelisation helpers ———
# Uses indexed temp files instead of fragile string-delimited lists.
# Each parallel step writes its metadata to a numbered temp file.
_PARALLEL_DIR=""
_PARALLEL_COUNT=0

parallel_step() {
  _name=$1
  shift
  _start=$(date +%s)
  log "$_name... (running in background)"

  # Create temp directory on first use
  if [ -z "$_PARALLEL_DIR" ]; then
    _PARALLEL_DIR=$(mktemp -d)
  fi

  "$@" &
  _pid=$!
  printf '%s\n%s\n%s\n' "$_pid" "$_name" "$_start" > "$_PARALLEL_DIR/$_PARALLEL_COUNT"
  _PARALLEL_COUNT=$((_PARALLEL_COUNT + 1))
}

wait_parallel_steps() {
  if [ -z "$_PARALLEL_DIR" ] || [ "$_PARALLEL_COUNT" -eq 0 ]; then
    return 0
  fi

  _i=0
  while [ "$_i" -lt "$_PARALLEL_COUNT" ]; do
    _file="$_PARALLEL_DIR/$_i"
    _pid=$(sed -n '1p' "$_file")
    _name=$(sed -n '2p' "$_file")
    _start=$(sed -n '3p' "$_file")

    if wait "$_pid"; then
      _end=$(date +%s)
      _dur=$((_end - _start))
      log "$_name done (${_dur}s)"
    else
      warn "$_name failed"
    fi
    _i=$((_i + 1))
  done

  rm -rf "$_PARALLEL_DIR"
  _PARALLEL_DIR=""
  _PARALLEL_COUNT=0
}
