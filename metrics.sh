#!/bin/bash
cpu=$(top -bn1 | grep "Cpu(s)" | awk '{print 100-$8}')
mem=$(free | awk '/Mem/{printf "%.1f", $3/$2*100}')
mem_used=$(free -m | awk '/Mem/{print $3}')
mem_total=$(free -m | awk '/Mem/{print $2}')
uptime_s=$(cat /proc/uptime | awk '{print int($1)}')
echo "{\"cpu\":$cpu,\"ram\":$mem,\"ram_used_mb\":$mem_used,\"ram_total_mb\":$mem_total,\"uptime_s\":$uptime_s}" \
  > metrics.json
