#!/bin/bash
# Simple network throughput report using sar
# Crontab: */10 * * * * /path/to/network_throughput_email.sh user@email.com

EMAIL="${1:-root}"
HOST=$(hostname)

# Get network stats - average over last 10 minutes worth of sar data
# sar -n DEV: network device stats
REPORT=$(sar -n DEV 60 10 2>/dev/null | grep -E "Average|IFACE")

echo -e "Network Throughput - $HOST\n$(date)\n\n$REPORT" | mail -s "Network Stats: $HOST" "$EMAIL"
