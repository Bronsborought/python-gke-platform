#!/usr/bin/env bash
set -euo pipefail

# Load protected local environment file if present on the CM5 host (mode 0600)
if [[ -f /etc/cm5-backup/backup.env ]]; then
  # shellcheck disable=SC1091
  source /etc/cm5-backup/backup.env
fi

DATASET="${DATASET:-datapool/annotation-data}"
GCS_BUCKET="${GCS_BUCKET:-gs://python-gke-dt-20261027-onprem-backups/cm5}"
RETENTION_LOCAL_DAYS="${RETENTION_LOCAL_DAYS:-7}"
: "${BACKUP_PASSPHRASE:?ERROR: BACKUP_PASSPHRASE must be set in environment or /etc/cm5-backup/backup.env}"

TIMESTAMP="$(date -u +"%Y%m%d-%H%M%S")"
SNAP_NAME="${DATASET}@backup-${TIMESTAMP}"
ARCHIVE_NAME="annotation-data-${TIMESTAMP}.zfs.zst.enc"
TMP_ARCHIVE="/tmp/${ARCHIVE_NAME}"

echo "[1/4] Creating atomic ZFS snapshot: ${SNAP_NAME}"
sudo zfs snapshot "${SNAP_NAME}"

echo "[2/4] Streaming ZFS send -> zstd compression -> AES-256-CBC encryption: ${TMP_ARCHIVE}"
sudo zfs send "${SNAP_NAME}" \
  | zstd -T0 -3 -c \
  | openssl enc -aes-256-cbc -salt -pbkdf2 -iter 100000 -pass env:BACKUP_PASSPHRASE -out "${TMP_ARCHIVE}"

SHA256_SUM="$(sha256sum "${TMP_ARCHIVE}" | awk '{print $1}')"
echo "Archive SHA-256: ${SHA256_SUM}"

echo "[3/4] Uploading encrypted archive to ${GCS_BUCKET}/${ARCHIVE_NAME}"
gcloud storage cp "${TMP_ARCHIVE}" "${GCS_BUCKET}/${ARCHIVE_NAME}"
rm -f "${TMP_ARCHIVE}"

echo "[4/4] Pruning local backup snapshots older than ${RETENTION_LOCAL_DAYS} days"
cutoff_epoch="$(date -u -d "${RETENTION_LOCAL_DAYS} days ago" +%s)"
while IFS=$'\t' read -r snap creation_epoch; do
  [[ -z "${snap}" ]] && continue
  if (( creation_epoch < cutoff_epoch )); then
    echo "Destroying expired local snapshot: ${snap}"
    sudo zfs destroy "${snap}"
  fi
done < <(zfs list -H -p -t snapshot -o name,creation | grep "^${DATASET}@backup-" || true)

echo "Backup completed successfully: ${GCS_BUCKET}/${ARCHIVE_NAME} (sha256=${SHA256_SUM})"
