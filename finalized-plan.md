# Finalized Plan: Raspberry Pi Internet Speed Monitoring + Evidence Logs

## Objective
Create a Bash + cron monitor on Raspberry Pi that runs at configurable intervals, measures download speed, logs every sample, tracks downtime episodes below threshold, and sends email alerts via Gmail SMTP.

## Confirmed Decisions
- Twilio/WhatsApp removed from scope.
- Email delivery in phase 1 uses Gmail SMTP (smtp.gmail.com with App Password).
- Core metric is download Mbps threshold breach (< 30 Mbps by default).
- Speed check backend is speedtest-cli.
- Logs are designed as evidence artifacts for ISP complaints.

## Implementation Plan

### Phase 1: Configuration and Secrets
1. Create configuration values for:
   - CHECK_INTERVAL_MINUTES (default: 15)
   - SPEED_THRESHOLD_MBPS (default: 30)
   - ALERT_COOLDOWN_MINUTES (default: 60)
   - Gmail SMTP settings (host, port, username, app password, from, to)
2. Keep secrets in an env file with restrictive permissions.
3. Keep non-secret defaults in a config file.

### Phase 2: Speed Check Flow
1. Use speedtest-cli in script mode and parse download speed in Mbps.
2. Normalize parsed speed to numeric value.
3. Record status for every run (success/failure/error reason).

### Phase 3: Downtime Trend and Evidence Tracking
1. Log every sample to a CSV file:
   - timestamp
   - measured download Mbps
   - threshold
   - status
2. Define an episode as consecutive samples below threshold.
3. Maintain episode log fields:
   - episode_start
   - episode_end
   - duration_minutes
   - min_speed_mbps
   - avg_speed_mbps
4. Maintain daily summary log fields:
   - date
   - episode_count
   - total_below_threshold_minutes
   - worst_speed_mbps

### Phase 4: Alerting Policy
1. Send Gmail alert when entering a below-threshold episode.
2. Enforce cooldown so repeated failing checks do not spam alerts.
3. Optionally send one recovery email when episode closes.

### Phase 5: Scheduling and Operations
1. Use cron for execution every N minutes (default 15).
2. Provide setup helper to install/update cron entry safely.
3. Keep logs append-only and predictable for auditing.
4. Add basic rotation/retention guidance.

## Proposed Project Files
- monitor.sh: main check + decision + alert logic
- config.env: interval, threshold, cooldown, non-secret SMTP defaults
- .env.example: required secrets template
- logs/samples.csv: per-run speed measurements
- logs/episodes.csv: below-threshold episode history
- logs/summary_daily.csv: daily aggregated evidence
- report.sh: human-readable summary for ISP complaint
- setup-cron.sh: cron installer/updater
- README.md: setup, Gmail app-password steps, troubleshooting

## Verification Checklist
1. Confirm speedtest-cli works on Raspberry Pi and output parsing is correct.
2. Run manual checks and verify sample logs are generated.
3. Simulate low-speed condition and verify episode start + first alert.
4. Re-run during cooldown and verify no duplicate alert.
5. Simulate recovery and verify episode closure (and optional recovery alert).
6. Verify daily summary calculations match raw samples.
7. Verify cron runs at configured interval and logs keep growing correctly.

## Operational Recommendations
- Use ISO 8601 timestamps with timezone for evidence quality.
- Retain raw samples at least 30 days and summaries at least 90 days.
- Keep Gmail app password private and rotate if exposed.
