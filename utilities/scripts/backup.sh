#!/bin/sh
# =============================================================================
#  Daily SQLite Backup — backs up all .db/.sqlite files to Cloudflare R2
#
#  Discovers SQLite databases across:
#    - ~/Library/Application Support/com.mac9sb/state.db (infra state)
#    - ~/Developer/sites/*/ (any .db or .sqlite files in server app dirs)
#
#  Backup strategy:
#    1. Per-project tarballs:  com.mac9sb.{project}-db-bak-{date}.tar.gz
#    2. Combined mega-tarball: com.mac9sb.server-backup-{date}.tar.gz
#    3. Upload mega-tarball to Cloudflare R2 object store
#    4. Clean up local staging (keep last 7 days of mega-tarballs)
#
#  R2 credentials are read from ~/Developer/.env.local (shell-sourceable):
#    R2_ACCOUNT_ID=<account-id>
#    R2_ACCESS_KEY_ID=<access-key>
#    R2_SECRET_ACCESS_KEY=<secret-key>
#    R2_BUCKET=<bucket-name>
#
#  Requires: curl, openssl, sqlite3 (all ship with macOS)
#  Triggered by: com.mac9sb.backup launchd agent (daily at 03:00)
#
#  Logs: ~/Library/Logs/com.mac9sb/backup.log
# =============================================================================

set -e

DEV_DIR="$HOME/Developer"
SITES_DIR="$DEV_DIR/sites"
STATE_DIR="$HOME/Library/Application Support/com.mac9sb"
LOG_DIR="$HOME/Library/Logs/com.mac9sb"
BACKUP_DIR="$HOME/Library/Application Support/com.mac9sb/backups"
BACKUP_LOG="$LOG_DIR/backup.log"
R2_CREDS="$DEV_DIR/.env.local"

DATE="$(date +%Y%m%d)"
TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"
RETENTION_DAYS=7

mkdir -p "$LOG_DIR" "$BACKUP_DIR"

# =============================================================================
#  Logging
# =============================================================================

log()  { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$BACKUP_LOG"; }
logn() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" | tee -a "$BACKUP_LOG"; }

log "========== Backup started =========="

# =============================================================================
#  S3v4 Signing Helpers (for Cloudflare R2 — no AWS CLI needed)
# =============================================================================
#  Implements AWS Signature Version 4 using only curl + openssl, both of
#  which ship with macOS. R2 is S3-compatible so this works directly.

# SHA-256 hash of a string (hex output)
_sha256() {
    printf '%s' "$1" | openssl dgst -sha256 2>/dev/null | sed 's/^.* //'
}

# SHA-256 hash of a file (hex output)
_sha256_file() {
    openssl dgst -sha256 "$1" 2>/dev/null | sed 's/^.* //'
}

# HMAC-SHA256 with a hex-encoded key, returns hex
_hmac_hex() {
    printf '%s' "$2" | openssl dgst -sha256 -mac HMAC -macopt "hexkey:$1" 2>/dev/null | sed 's/^.* //'
}

# Convert a plain string to hex encoding
_str_to_hex() {
    printf '%s' "$1" | od -A n -t x1 | tr -d ' \n'
}

# Upload a file to R2 using S3-compatible PUT with Signature V4.
# Usage: r2_upload <local-file> <object-key>
# Requires R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_BUCKET
# to be set in the environment.
r2_upload() {
    _file="$1"
    _object_key="$2"

    _host="${R2_ACCOUNT_ID}.r2.cloudflarestorage.com"
    _region="auto"
    _service="s3"
    _now_iso="$(date -u +%Y%m%dT%H%M%SZ)"
    _now_date="$(date -u +%Y%m%d)"
    _content_type="application/gzip"

    # Hash the file payload
    _payload_hash="$(_sha256_file "$_file")"

    # --- Canonical Request ---
    _canonical_uri="/${R2_BUCKET}/${_object_key}"
    _canonical_querystring=""
    _signed_headers="content-type;host;x-amz-content-sha256;x-amz-date"

    _canonical_request="$(printf 'PUT\n%s\n%s\ncontent-type:%s\nhost:%s\nx-amz-content-sha256:%s\nx-amz-date:%s\n\n%s\n%s' \
        "$_canonical_uri" \
        "$_canonical_querystring" \
        "$_content_type" \
        "$_host" \
        "$_payload_hash" \
        "$_now_iso" \
        "$_signed_headers" \
        "$_payload_hash")"

    # --- String to Sign ---
    _scope="${_now_date}/${_region}/${_service}/aws4_request"
    _canonical_hash="$(_sha256 "$_canonical_request")"

    _string_to_sign="$(printf 'AWS4-HMAC-SHA256\n%s\n%s\n%s' \
        "$_now_iso" \
        "$_scope" \
        "$_canonical_hash")"

    # --- Signing Key (HMAC chain) ---
    _key_hex="$(_str_to_hex "AWS4${R2_SECRET_ACCESS_KEY}")"
    _date_key="$(_hmac_hex "$_key_hex" "$_now_date")"
    _region_key="$(_hmac_hex "$_date_key" "$_region")"
    _service_key="$(_hmac_hex "$_region_key" "$_service")"
    _signing_key="$(_hmac_hex "$_service_key" "aws4_request")"

    # --- Signature ---
    _signature="$(_hmac_hex "$_signing_key" "$_string_to_sign")"

    # --- Authorization Header ---
    _authorization="AWS4-HMAC-SHA256 Credential=${R2_ACCESS_KEY_ID}/${_scope}, SignedHeaders=${_signed_headers}, Signature=${_signature}"

    # --- Upload ---
    _http_code="$(curl -s -o /dev/null -w '%{http_code}' -X PUT \
        -H "Content-Type: ${_content_type}" \
        -H "Host: ${_host}" \
        -H "X-Amz-Content-Sha256: ${_payload_hash}" \
        -H "X-Amz-Date: ${_now_iso}" \
        -H "Authorization: ${_authorization}" \
        --data-binary "@${_file}" \
        "https://${_host}${_canonical_uri}")"

    case "$_http_code" in
        2*) return 0 ;;
        *)
            log "  R2 upload returned HTTP ${_http_code}"
            return 1
            ;;
    esac
}

# =============================================================================
#  1. Discover SQLite databases
# =============================================================================

# Staging directory for this run
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

# Track per-project tarballs for the mega-tar
PROJECT_TARBALLS=""
BACKUP_COUNT=0

# --- Infrastructure state database ---
_state_db="$STATE_DIR/state.db"
if [ -f "$_state_db" ]; then
    _project="infrastructure"
    _project_dir="$STAGING/$_project"
    mkdir -p "$_project_dir"

    # Use sqlite3 .backup for a consistent snapshot (handles WAL safely)
    sqlite3 "$_state_db" ".backup '$_project_dir/state.db'" 2>/dev/null
    if [ $? -eq 0 ]; then
        _tarname="com.mac9sb.${_project}-db-bak-${DATE}.tar.gz"
        (cd "$STAGING" && tar -czf "$_tarname" "$_project/")
        PROJECT_TARBALLS="${PROJECT_TARBALLS} ${_tarname}"
        BACKUP_COUNT=$((BACKUP_COUNT + 1))
        log "  Backed up: $_state_db → $_tarname"
    else
        log "  WARN: Failed to snapshot $_state_db"
    fi
fi

# --- Site databases ---
for _site_dir in "$SITES_DIR"/*/; do
    [ ! -d "$_site_dir" ] && continue
    _site_name="$(basename "$_site_dir")"

    _project_dir="$STAGING/$_site_name"
    mkdir -p "$_project_dir"

    # Find all .db and .sqlite files in the site directory
    # Exclude .build/ directory (build artifacts, not app data)
    # Use -maxdepth 5 to avoid traversing too deep
    find "$_site_dir" \
        -maxdepth 5 \
        -name '.build' -prune -o \
        -name '.swiftpm' -prune -o \
        \( -name '*.db' -o -name '*.sqlite' -o -name '*.sqlite3' \) \
        -type f -print 2>/dev/null | while IFS= read -r _db_file; do

        # Skip WAL and SHM files (they'll be captured by .backup)
        case "$_db_file" in
            *-wal|*-shm) continue ;;
        esac

        # Determine relative path within the site for the backup
        _rel_path="${_db_file#"$_site_dir"}"
        _backup_dest="$_project_dir/$_rel_path"
        mkdir -p "$(dirname "$_backup_dest")"

        # Use sqlite3 .backup for a consistent WAL-safe snapshot
        if sqlite3 "$_db_file" ".backup '$_backup_dest'" 2>/dev/null; then
            log "  Found DB: $_site_name/$_rel_path"
        else
            # Fallback to file copy for non-SQLite files matching the extension
            cp "$_db_file" "$_backup_dest" 2>/dev/null || true
            log "  Copied (non-WAL): $_site_name/$_rel_path"
        fi
    done

    # Check if any databases were found (the while loop runs in a subshell,
    # so _found_dbs won't propagate; check by directory contents instead)
    if [ -n "$(find "$_project_dir" -type f 2>/dev/null)" ]; then
        _tarname="com.mac9sb.${_site_name}-db-bak-${DATE}.tar.gz"
        (cd "$STAGING" && tar -czf "$_tarname" "$_site_name/")
        PROJECT_TARBALLS="${PROJECT_TARBALLS} ${_tarname}"
        BACKUP_COUNT=$((BACKUP_COUNT + 1))
        log "  Created: $_tarname"
    fi
done

# =============================================================================
#  2. Create mega-tarball of all per-project tarballs
# =============================================================================

if [ "$BACKUP_COUNT" -eq 0 ]; then
    log "No databases found to back up — exiting"
    log "========== Backup finished (nothing to do) =========="
    exit 0
fi

MEGA_TAR="com.mac9sb.server-backup-${DATE}.tar.gz"
MEGA_TAR_PATH="$BACKUP_DIR/$MEGA_TAR"

# Collect all per-project tarballs into the mega-tar
(cd "$STAGING" && tar -czf "$MEGA_TAR_PATH" $PROJECT_TARBALLS)
log "Created mega-tarball: $MEGA_TAR ($BACKUP_COUNT project(s))"

_size="$(stat -f '%z' "$MEGA_TAR_PATH" 2>/dev/null || echo "unknown")"
log "  Size: ${_size} bytes"

# =============================================================================
#  3. Upload to Cloudflare R2
# =============================================================================

_upload_success=false

if [ ! -f "$R2_CREDS" ]; then
    log "WARN: R2 credentials not found at $R2_CREDS — skipping upload"
    log "  Create $R2_CREDS with:"
    log "    R2_ACCOUNT_ID=<account-id>"
    log "    R2_ACCESS_KEY_ID=<access-key>"
    log "    R2_SECRET_ACCESS_KEY=<secret-key>"
    log "    R2_BUCKET=<bucket-name>"
else
    # Source credentials
    . "$R2_CREDS"

    # Validate required fields
    _missing=""
    [ -z "$R2_ACCOUNT_ID" ]        && _missing="${_missing} R2_ACCOUNT_ID"
    [ -z "$R2_ACCESS_KEY_ID" ]     && _missing="${_missing} R2_ACCESS_KEY_ID"
    [ -z "$R2_SECRET_ACCESS_KEY" ] && _missing="${_missing} R2_SECRET_ACCESS_KEY"
    [ -z "$R2_BUCKET" ]            && _missing="${_missing} R2_BUCKET"

    if [ -n "$_missing" ]; then
        log "WARN: Missing R2 credential fields:${_missing}"
        log "  Skipping upload"
    else
        R2_KEY="backups/${DATE}/${MEGA_TAR}"

        log "Uploading to R2: ${R2_BUCKET}/${R2_KEY}"

        if r2_upload "$MEGA_TAR_PATH" "$R2_KEY"; then
            log "Upload successful: ${R2_BUCKET}/${R2_KEY}"
            _upload_success=true
        else
            log "ERROR: R2 upload failed"
        fi
    fi
fi

# =============================================================================
#  4. Clean up old local backups (retain last N days)
# =============================================================================

_cleaned=0
_cleanup_list="$(mktemp)"
find "$BACKUP_DIR" -name 'com.mac9sb.server-backup-*.tar.gz' -type f -mtime +"$RETENTION_DAYS" 2>/dev/null > "$_cleanup_list"
while IFS= read -r _old; do
    [ -z "$_old" ] && continue
    rm -f "$_old"
    log "  Cleaned up old backup: $(basename "$_old")"
    _cleaned=$((_cleaned + 1))
done < "$_cleanup_list"
rm -f "$_cleanup_list"

if [ "$_cleaned" -gt 0 ]; then
    log "Cleaned up $_cleaned backup(s) older than $RETENTION_DAYS days"
fi

# =============================================================================
#  5. Summary
# =============================================================================

log "Backup summary:"
log "  Projects backed up: $BACKUP_COUNT"
log "  Mega-tarball: $MEGA_TAR_PATH"
if [ "$_upload_success" = true ]; then
    log "  R2 upload: success"
else
    log "  R2 upload: skipped or failed"
fi
log "========== Backup finished =========="
