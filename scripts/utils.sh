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
parallel_step() {
  STEP_NAME=$1
  shift
  STEP_START=$(date +%s)
  log "$STEP_NAME... (running in background)"
  "$@" &
  PID=$!
  echo "$PID $STEP_NAME $STEP_START" >> /tmp/parallel_steps.log
}

wait_parallel_steps() {
  if [ -f /tmp/parallel_steps.log ]; then
    while read PID STEP_NAME STEP_START; do
      if wait "$PID"; then
        STEP_END=$(date +%s)
        STEP_DUR=$((STEP_END - STEP_START))
        log "$STEP_NAME done (${STEP_DUR}s)"
      else
        warn "$STEP_NAME failed"
      fi
    done < /tmp/parallel_steps.log
    rm -f /tmp/parallel_steps.log
  fi
}
