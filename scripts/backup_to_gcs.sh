#!/usr/bin/env bash
set -euo pipefail

DATASET="${DATASET:-datapool/annotation-data}"
GCS_BUCKET="${GCS_BUCKET:-gs://python-gke-dt-20261027-onprem-backups}"
RPI_HOST="${RPI_HOST:-bronsborought@192.168.88.59}"
RPI_SSH_KEY="${RPI_SSH_KEY:-$HOME/.ssh/cm5_ed25519}"
BACKUP_PASSPHRASE="${BACKUP_PASSPHRASE:-cm5-hybrid-edge-aes256-backup-key}"
LOG_FILE="${LOG_FILE:-/tmp/cm5-zfs-backup.log}"
ALERT_WEBHOOK_URL="${ALERT_WEBHOOK_URL:-}"

log() {
  local level="$1"
  shift
  printf '[%s] [%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$level" "$*" | tee -a "$LOG_FILE"
}

alert_on_failure() {
  local line_no="$1"
  log "ALERT" "Backup pipeline failed at line ${line_no} for dataset ${DATASET}"
  if [[ -n "$ALERT_WEBHOOK_URL" ]]; then
    curl -fsS -X POST "$ALERT_WEBHOOK_URL" \
      -H "Content-Type: application/json" \
      -d "{\"status\":\"error\",\"dataset\":\"${DATASET}\",\"line\":${line_no}}" || true
  fi
}
trap 'alert_on_failure $LINENO' ERR

TS="$(date -u +%Y%m%d-%H%M%S)"
SNAP_NAME="${DATASET}@backup-${TS}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

log "INFO" "Starting atomic ZFS snapshot ${SNAP_NAME} on ${RPI_HOST}"
PREV_SNAP="$(ssh -i "$RPI_SSH_KEY" "$RPI_HOST" "sudo zfs list -H -t snapshot -o name -s creation -r '${DATASET}' | grep '@backup-' | tail -n 1 || true")"
ssh -i "$RPI_SSH_KEY" "$RPI_HOST" "sudo zfs snapshot '${SNAP_NAME}'"

if [[ -n "$PREV_SNAP" ]]; then
  BACKUP_MODE="incremental"
  ARCHIVE_NAME="annotation-data-${TS}-incr.zfs.zst.enc"
  log "INFO" "Exporting incremental ZFS stream (${PREV_SNAP} -> ${SNAP_NAME}) with zstd + AES-256 encryption"
  ssh -i "$RPI_SSH_KEY" "$RPI_HOST" "sudo zfs send -i '${PREV_SNAP}' '${SNAP_NAME}' | zstd -c" \
    | openssl enc -aes-256-cbc -pbkdf2 -salt -pass "pass:${BACKUP_PASSPHRASE}" -out "${TMP_DIR}/${ARCHIVE_NAME}"
else
  BACKUP_MODE="full"
  ARCHIVE_NAME="annotation-data-${TS}-full.zfs.zst.enc"
  log "INFO" "Exporting full ZFS stream (${SNAP_NAME}) with zstd + AES-256 encryption"
  ssh -i "$RPI_SSH_KEY" "$RPI_HOST" "sudo zfs send '${SNAP_NAME}' | zstd -c" \
    | openssl enc -aes-256-cbc -pbkdf2 -salt -pass "pass:${BACKUP_PASSPHRASE}" -out "${TMP_DIR}/${ARCHIVE_NAME}"
fi

SHA256_SUM="$(sha256sum "${TMP_DIR}/${ARCHIVE_NAME}" | awk '{print $1}')"
DEST_URI="${GCS_BUCKET}/zfs-backups/${ARCHIVE_NAME}"

log "INFO" "Uploading encrypted ${BACKUP_MODE} backup (sha256=${SHA256_SUM}) to ${DEST_URI}"
gcloud storage cp "${TMP_DIR}/${ARCHIVE_NAME}" "${DEST_URI}" --quiet
log "INFO" "Backup completed successfully: ${DEST_URI}"
