#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.env"
MONITOR_SCRIPT="${SCRIPT_DIR}/monitor.sh"

if [[ -f "${CONFIG_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${CONFIG_FILE}"
fi

CHECK_INTERVAL_MINUTES="${CHECK_INTERVAL_MINUTES:-15}"

if ! [[ "${CHECK_INTERVAL_MINUTES}" =~ ^[0-9]+$ ]]; then
  echo "CHECK_INTERVAL_MINUTES must be a positive integer"
  exit 1
fi

if (( CHECK_INTERVAL_MINUTES < 1 || CHECK_INTERVAL_MINUTES > 59 )); then
  echo "CHECK_INTERVAL_MINUTES should be between 1 and 59 for cron step format"
  exit 1
fi

CRON_LINE="*/${CHECK_INTERVAL_MINUTES} * * * * ${MONITOR_SCRIPT} >> ${SCRIPT_DIR}/logs/cron.log 2>&1"

TMP_FILE="$(mktemp)"
crontab -l 2>/dev/null | grep -v "${MONITOR_SCRIPT}" > "${TMP_FILE}" || true
echo "${CRON_LINE}" >> "${TMP_FILE}"
crontab "${TMP_FILE}"
rm -f "${TMP_FILE}"

echo "Cron updated: ${CRON_LINE}"
