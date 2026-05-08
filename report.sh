#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/logs"
SAMPLES_LOG="${LOG_DIR}/samples.csv"
EPISODES_LOG="${LOG_DIR}/episodes.csv"
DAILY_SUMMARY_LOG="${LOG_DIR}/summary_daily.csv"

if [[ ! -f "${SAMPLES_LOG}" ]]; then
  echo "No samples log found yet at ${SAMPLES_LOG}"
  exit 0
fi

echo "Internet Speed Monitoring Report"
echo "Generated: $(date -Iseconds)"
echo

echo "Recent samples (last 10):"
tail -n 10 "${SAMPLES_LOG}"
echo

if [[ -f "${EPISODES_LOG}" ]]; then
  echo "Recent downtime episodes (last 10):"
  tail -n 10 "${EPISODES_LOG}"
  echo
fi

if [[ -f "${DAILY_SUMMARY_LOG}" ]]; then
  echo "Daily summary:"
  cat "${DAILY_SUMMARY_LOG}"
  echo
fi

echo "Complaint-ready summary (all recorded days):"
if [[ -f "${DAILY_SUMMARY_LOG}" ]]; then
  awk -F, '
    NR==1 {next}
    {
      episodes += $2
      minutes += $3
      if (worst == "" || $4+0 < worst+0) {
        worst = $4
      }
    }
    END {
      if (episodes == 0) {
        print "No below-threshold downtime episodes recorded yet."
      } else {
        printf "Total episodes: %d\nTotal below-threshold minutes: %d\nWorst recorded speed: %s Mbps\n", episodes, minutes, worst
      }
    }
  ' "${DAILY_SUMMARY_LOG}"
else
  echo "No daily summary available yet."
fi
