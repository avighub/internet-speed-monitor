# Internet Speed Monitor (Raspberry Pi)

Monitors internet download speed on a schedule, logs trends for downtime evidence, and sends Gmail alerts when speed is below threshold.

## Features
- Configurable interval (default 15 minutes via cron)
- Download threshold check (default: 30 Mbps)
- Gmail SMTP alert on below-threshold episode start
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

## Gmail App Password
Use a Google App Password (not your account password):
- Enable 2-Step Verification on your Google account
- Generate App Password from Google Account security settings
- Put it in `.env` as `SMTP_PASS`

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
