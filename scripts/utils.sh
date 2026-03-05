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
step() {
  STEP_NAME=$1
  STEP_START=$(date +%s)
  log "$STEP_NAME..."
}

step_done() {
  STEP_END=$(date +%s)
  STEP_DUR=$((STEP_END - STEP_START))
  log "$STEP_NAME done (${STEP_DUR}s)"
}

# ——— Total runtime ———
total_start() { TOTAL_START=$(date +%s); }
total_done() {
  TOTAL_END=$(date +%s)
  TOTAL_DUR=$((TOTAL_END - TOTAL_START))
  log "Total runtime: ${TOTAL_DUR}s"
}

# ——— Parallelisation helpers ———
# Usage: parallel_step "Step name" command
PARALLEL_PIDS=""
PARALLEL_NAMES=""
PARALLEL_STARTS=""

parallel_step() {
  _name=$1
  shift
  _start=$(date +%s)
  log "$_name... (running in background)"
  "$@" &
  _pid=$!
  PARALLEL_PIDS="$PARALLEL_PIDS $_pid"
  PARALLEL_NAMES="$PARALLEL_NAMES|$_name"
  PARALLEL_STARTS="$PARALLEL_STARTS $_start"
}

wait_parallel_steps() {
  _i=1
  for _pid in $PARALLEL_PIDS; do
    _i=$((_i + 1))
    _name=$(echo "$PARALLEL_NAMES" | cut -d'|' -f"$_i")
    _start=$(echo "$PARALLEL_STARTS" | cut -d' ' -f"$_i")
    if wait "$_pid"; then
      _end=$(date +%s)
      _dur=$((_end - _start))
      log "$_name done (${_dur}s)"
    else
      warn "$_name failed"
    fi
  done
  PARALLEL_PIDS=""
  PARALLEL_NAMES=""
  PARALLEL_STARTS=""
}
