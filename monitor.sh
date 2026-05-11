#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.env"
SECRETS_FILE="${SCRIPT_DIR}/.env"

if [[ -f "${CONFIG_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${CONFIG_FILE}"
fi

if [[ ! -f "${SECRETS_FILE}" ]]; then
  echo "ERROR: .env file not found. Copy .env.example to .env and configure values." >&2
  exit 1
fi
# shellcheck disable=SC1090
source "${SECRETS_FILE}"

CHECK_INTERVAL_MINUTES="${CHECK_INTERVAL_MINUTES:-15}"
SPEED_THRESHOLD_MBPS="${SPEED_THRESHOLD_MBPS:-30}"
ALERT_COOLDOWN_MINUTES="${ALERT_COOLDOWN_MINUTES:-60}"
SPEEDTEST_TIMEOUT_SECONDS="${SPEEDTEST_TIMEOUT_SECONDS:-90}"
LOG_DIR="${LOG_DIR:-logs}"
STATE_DIR="${STATE_DIR:-state}"
SEND_RECOVERY_EMAIL="${SEND_RECOVERY_EMAIL:-1}"

LOG_DIR="${SCRIPT_DIR}/${LOG_DIR}"
STATE_DIR="${SCRIPT_DIR}/${STATE_DIR}"
mkdir -p "${LOG_DIR}" "${STATE_DIR}"

SAMPLES_LOG="${LOG_DIR}/samples.csv"
EPISODES_LOG="${LOG_DIR}/episodes.csv"
DAILY_SUMMARY_LOG="${LOG_DIR}/summary_daily.csv"
RUNTIME_LOG="${LOG_DIR}/monitor.log"
LAST_ALERT_FILE="${STATE_DIR}/last_alert.state"
CURRENT_EPISODE_FILE="${STATE_DIR}/current_episode.state"

log_msg() {
  local msg="$1"
  echo "$(date -Iseconds),${msg}" >> "${RUNTIME_LOG}"
}

ensure_csv_headers() {
  [[ -f "${SAMPLES_LOG}" ]] || echo "timestamp,speed_mbps,threshold_mbps,status,error" > "${SAMPLES_LOG}"
  [[ -f "${EPISODES_LOG}" ]] || echo "episode_start,episode_end,duration_minutes,min_speed_mbps,avg_speed_mbps,sample_count" > "${EPISODES_LOG}"
  [[ -f "${DAILY_SUMMARY_LOG}" ]] || echo "date,episode_count,total_below_threshold_minutes,worst_speed_mbps" > "${DAILY_SUMMARY_LOG}"
}

float_lt() {
  awk -v a="$1" -v b="$2" 'BEGIN {exit !(a < b)}'
}

float_gt() {
  awk -v a="$1" -v b="$2" 'BEGIN {exit !(a > b)}'
}

send_email() {
  local subject="$1"
  local body="$2"

  if ! command -v curl >/dev/null 2>&1; then
    log_msg "ERROR,curl is not installed; cannot send email"
    return 1
  fi

  local payload
  local msg_id date_header
  msg_id="<$(date +%s).$$@$(hostname)>"
  date_header="$(date -R)"

  payload="$(printf "Date: %s\r\nMessage-ID: %s\r\nFrom: %s\r\nTo: %s\r\nSubject: %s\r\nMIME-Version: 1.0\r\nContent-Type: text/plain; charset=UTF-8\r\n\r\n%s" \
    "${date_header}" "${msg_id}" "${ALERT_FROM}" "${ALERT_TO}" "${subject}" "${body}")"

  if ! curl --silent --show-error --fail \
    --url "smtp://${SMTP_HOST}:${SMTP_PORT}" \
    --ssl-reqd \
    --mail-from "${ALERT_FROM}" \
    --mail-rcpt "${ALERT_TO}" \
    --user "${SMTP_USER}:${SMTP_PASS}" \
    --upload-file - <<< "${payload}" >/dev/null; then
    log_msg "ERROR,failed to send email alert"
    return 1
  fi

  log_msg "INFO,email sent subject=${subject}"
  return 0
}

get_download_speed_mbps() {
  local output
  local speed

  if ! command -v speedtest-cli >/dev/null 2>&1; then
    echo "ERROR:speedtest-cli not installed"
    return 1
  fi

  if ! output="$(timeout "${SPEEDTEST_TIMEOUT_SECONDS}" speedtest-cli --simple 2>&1)"; then
    echo "ERROR:${output}"
    return 1
  fi

  speed="$(awk '
    /Download:/ {
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^[0-9]+(\.[0-9]+)?$/) {
          print $i
          exit
        }
      }
    }
  ' <<< "${output}")"

  if [[ -z "${speed}" ]]; then
    echo "ERROR:unable to parse download speed from speedtest-cli output"
    return 1
  fi

  if ! [[ "${speed}" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    echo "ERROR:parsed non-numeric speed value: ${speed}"
    return 1
  fi

  echo "${speed}"
  return 0
}

read_last_alert_ts() {
  [[ -f "${LAST_ALERT_FILE}" ]] && cat "${LAST_ALERT_FILE}" || echo "0"
}

write_last_alert_ts() {
  local ts="$1"
  echo "${ts}" > "${LAST_ALERT_FILE}"
}

can_send_alert() {
  local now_ts="$1"
  local last_ts
  local elapsed
  local cooldown_seconds

  last_ts="$(read_last_alert_ts)"
  elapsed=$(( now_ts - last_ts ))
  cooldown_seconds=$(( ALERT_COOLDOWN_MINUTES * 60 ))

  [[ "${elapsed}" -ge "${cooldown_seconds}" ]]
}

start_episode() {
  local ts_iso="$1"
  local speed="$2"
  cat > "${CURRENT_EPISODE_FILE}" <<EOF
start=${ts_iso}
min=${speed}
sum=${speed}
count=1
EOF
}

update_episode() {
  local speed="$1"
  if [[ ! -f "${CURRENT_EPISODE_FILE}" ]]; then
    return
  fi

  # shellcheck disable=SC1090
  source "${CURRENT_EPISODE_FILE}"

  if float_lt "${speed}" "${min}"; then
    min="${speed}"
  fi

  sum="$(awk -v a="${sum}" -v b="${speed}" 'BEGIN {printf "%.3f", a + b}')"
  count=$(( count + 1 ))

  cat > "${CURRENT_EPISODE_FILE}" <<EOF
start=${start}
min=${min}
sum=${sum}
count=${count}
EOF
}

close_episode() {
  local end_iso="$1"
  local duration_minutes="$2"

  if [[ ! -f "${CURRENT_EPISODE_FILE}" ]]; then
    return
  fi

  # shellcheck disable=SC1090
  source "${CURRENT_EPISODE_FILE}"
  local avg
  avg="$(awk -v s="${sum}" -v c="${count}" 'BEGIN {printf "%.3f", s / c}')"

  echo "${start},${end_iso},${duration_minutes},${min},${avg},${count}" >> "${EPISODES_LOG}"
  rm -f "${CURRENT_EPISODE_FILE}"
}

update_daily_summary() {
  local day="$1"
  local duration_minutes="$2"
  local min_speed="$3"

  local tmp
  local found=0
  tmp="$(mktemp)"

  awk -F, -v OFS="," -v day="${day}" -v dur="${duration_minutes}" -v min_speed="${min_speed}" '
    NR==1 {print; next}
    {
      if ($1 == day) {
        found=1
        episodes=$2 + 1
        total=$3 + dur
        worst=$4
        if (min_speed+0 < worst+0) {
          worst=min_speed
        }
        print $1, episodes, total, worst
      } else {
        print
      }
    }
    END {
      if (!found) {
        print day, 1, dur, min_speed
      }
    }
  ' "${DAILY_SUMMARY_LOG}" > "${tmp}"

  mv "${tmp}" "${DAILY_SUMMARY_LOG}"
}

main() {
  ensure_csv_headers

  local now_iso now_ts speed status error_msg
  now_iso="$(date -Iseconds)"
  now_ts="$(date +%s)"
  status="ok"
  error_msg=""

  if speed="$(get_download_speed_mbps)"; then
    echo "${now_iso},${speed},${SPEED_THRESHOLD_MBPS},${status}," >> "${SAMPLES_LOG}"
    log_msg "INFO,speed_mbps=${speed} threshold=${SPEED_THRESHOLD_MBPS}"

    if float_lt "${speed}" "${SPEED_THRESHOLD_MBPS}"; then
      if [[ ! -f "${CURRENT_EPISODE_FILE}" ]]; then
        start_episode "${now_iso}" "${speed}"
        if can_send_alert "${now_ts}"; then
          send_email \
            "[Internet Alert] Speed below ${SPEED_THRESHOLD_MBPS} Mbps" \
            "Time: ${now_iso}
Download speed: ${speed} Mbps
Threshold: ${SPEED_THRESHOLD_MBPS} Mbps
Host: $(hostname)"
          write_last_alert_ts "${now_ts}"
        else
          log_msg "INFO,below-threshold but cooldown active"
        fi
      else
        update_episode "${speed}"
      fi
    else
      if [[ -f "${CURRENT_EPISODE_FILE}" ]]; then
        # shellcheck disable=SC1090
        source "${CURRENT_EPISODE_FILE}"
        local start_ts duration_minutes day_for_summary
        start_ts="$(date -d "${start}" +%s 2>/dev/null || echo "${now_ts}")"
        duration_minutes=$(( (now_ts - start_ts) / 60 ))
        (( duration_minutes < 1 )) && duration_minutes=1

        close_episode "${now_iso}" "${duration_minutes}"
        day_for_summary="$(date +%F)"
        update_daily_summary "${day_for_summary}" "${duration_minutes}" "${min}"

        if [[ "${SEND_RECOVERY_EMAIL}" == "1" ]]; then
          send_email \
            "[Internet Recovery] Speed back above threshold" \
            "Time: ${now_iso}
Download speed: ${speed} Mbps
Threshold: ${SPEED_THRESHOLD_MBPS} Mbps
Host: $(hostname)
Episode duration: ${duration_minutes} minutes"
        fi
      fi
    fi
  else
    status="error"
    error_msg="${speed#ERROR:}"
    echo "${now_iso},,${SPEED_THRESHOLD_MBPS},${status},${error_msg}" >> "${SAMPLES_LOG}"
    log_msg "ERROR,speedtest failed error=${error_msg}"
    exit 1
  fi
}

main "$@"
