# Internet Speed Monitor (Raspberry Pi)

Monitors internet download speed on a schedule, logs trends for downtime evidence, and sends Resend email alerts when speed is below threshold.

## Features
- Configurable interval (default 15 minutes via cron)
- Download threshold check (default: 30 Mbps)
- Resend alert on below-threshold episode start
- Cooldown to prevent alert spam
- Optional recovery email
- CSV logs for samples, episodes, and daily summary
- Report script for ISP complaint evidence

## Prerequisites (Raspberry Pi)
Install required commands:

```bash
sudo apt update
sudo apt install -y speedtest-cli curl coreutils
```

## Setup
1. Copy secrets template and edit values:

```bash
cp .env.example .env
nano .env
chmod 600 .env
```

2. Optionally adjust non-secret settings in `config.env`.

3. Make scripts executable:

```bash
chmod +x monitor.sh report.sh setup-cron.sh
```

4. Test one manual run:

```bash
./monitor.sh
```

5. Install cron schedule:

```bash
./setup-cron.sh
```

## Configure and Test Runtime Values
Runtime config values live in `config.env`:
- `CHECK_INTERVAL_MINUTES`: how often cron runs (for example: `1`, `5`, `15`)
- `SPEED_THRESHOLD_MBPS`: alert threshold (alert when measured speed is lower)
- `ALERT_COOLDOWN_MINUTES`: minimum minutes between alert sends
- `REPEAT_ALERT_WHILE_LOW`: set `1` to send reminder alerts during an ongoing low-speed episode (respects cooldown), `0` for one alert per episode
- `SPEEDTEST_TIMEOUT_SECONDS`: timeout for each speed test call

After changing config:
1. Threshold/cooldown/timeout changes are picked up on the next script run.
2. Interval changes require cron to be regenerated:

```bash
./setup-cron.sh
crontab -l | grep monitor.sh
```

If behavior looks stale after major testing changes, clear runtime state once:

```bash
rm -f state/current_episode.state state/last_alert.state
```

### Manual Test Scenarios
Run one normal manual check:

```bash
./monitor.sh
tail -n 50 logs/monitor.log
```

Force a below-threshold test immediately (without waiting for actual low speed):

```bash
SPEED_THRESHOLD_MBPS=999 ALERT_COOLDOWN_MINUTES=0 ./monitor.sh
tail -n 80 logs/monitor.log
```

Expected success log line:

```text
INFO,email sent via Resend subject=...
```

If send fails, you should see:

```text
ERROR,resend API failed http_code=... response=...
```

### Cron and Path Validation
Confirm the cron job points to the same project path you are editing:

```bash
pwd
crontab -l | grep monitor.sh
```

If path is wrong, rerun:

```bash
./setup-cron.sh
```

## Resend API Setup
Email alerts are sent via [Resend](https://resend.com) — reliable transactional email with a free tier (3,000 emails/month).

1. Sign up at [resend.com](https://resend.com) (free, no credit card)
2. Verify a sending address or domain under **Domains**
3. Create an API key under **API Keys**
4. Set in `.env`:
   - `RESEND_API_KEY` — your API key (starts with `re_`)
   - `ALERT_FROM` — your verified sender address
   - `ALERT_TO` — recipient (your Gmail or any address)

## Logs
- `logs/samples.csv`: per-run speed checks
- `logs/episodes.csv`: below-threshold periods
- `logs/summary_daily.csv`: daily aggregate evidence
- `logs/monitor.log`: operational script logs
- `logs/cron.log`: cron execution output

## Report
Generate summary:

```bash
./report.sh
```

## Notes
- If `speedtest-cli` command fails, failures are logged in `samples.csv` and `monitor.log`.
- Daily summary is updated when a downtime episode ends.
- Keep `.env` private.
