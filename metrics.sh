#!/bin/bash

cpu_usage() {
  read_cpu() { awk '/^cpu / {print $2+$3+$4+$5+$6+$7+$8, $5}' /proc/stat; }
  read1=$(read_cpu); sleep 1; read2=$(read_cpu)
  awk -v r1="$read1" -v r2="$read2" 'BEGIN {
    split(r1,a," "); split(r2,b," ")
    total=b[1]-a[1]; idle=b[2]-a[2]
    printf "%.1f", 100*(total-idle)/total
  }'
}

cpu=$(cpu_usage)
mem=$(free | awk '/Mem/{printf "%.1f", $3/$2*100}')
mem_used=$(free -m | awk '/Mem/{print $3}')
mem_total=$(free -m | awk '/Mem/{print $2}')
uptime_s=$(awk '{print int($1)}' /proc/uptime)
disks=$(df -x tmpfs -x devtmpfs -x squashfs -x efivarfs -x overlay \
  --output=source,used,size,pcent \
  | awk 'NR>1 && /^\/dev\// && $3 > 2097152 && !seen[$1]++ {gsub(/%/,"",$4); printf "%s{\"dev\":\"%s\",\"used\":%s,\"total\":%s,\"pct\":%s}", \
    (count++>0?",":""), $1,$2,$3,$4}')
disks="[$disks]"
proc_count=$(ps aux | wc -l)
timestamp=$(date +%s)

top_procs=$(ps aux --no-headers | awk '{
    cmd = $11
    if (cmd ~ /\/proc\/self\/exe/) {
        "readlink /proc/" $2 "/exe 2>/dev/null" | getline cmd
        close("readlink /proc/" $2 "/exe 2>/dev/null")
    }
    n = split(cmd, p, "/"); name = p[n]
    split(name, np, " "); name = np[1]
    if (name == "") name = "unknown"
    if (length(name) > 24) name = substr(name, 1, 24)
    cpu_t[name] += $3; mem_t[name] += $6; cnt[name]++
} END {
    for (n in cpu_t) printf "%.1f\t%.0f\t%d\t%s\n", cpu_t[n], mem_t[n]/1024, cnt[n], n
}')

top_cpu=$(echo "$top_procs" | sort -t$'\t' -rn -k1 | head -5 | awk -F'\t' '{
    printf "%s{\"name\":\"%s\",\"cpu\":%s,\"mem_mb\":%s,\"procs\":%s}",
        (NR>1?",":""), $4, $1, $2, $3
}')

top_mem=$(echo "$top_procs" | sort -t$'\t' -rn -k2 | head -5 | awk -F'\t' '{
    printf "%s{\"name\":\"%s\",\"cpu\":%s,\"mem_mb\":%s,\"procs\":%s}",
        (NR>1?",":""), $4, $1, $2, $3
}')

echo "{\"cpu\":$cpu,\"ram\":$mem,\"ram_used_mb\":$mem_used,\"ram_total_mb\":$mem_total,\"uptime_s\":$uptime_s,\"disks\":$disks,\"proc_count\":$proc_count,\"timestamp\":$timestamp,\"top_cpu\":[$top_cpu],\"top_mem\":[$top_mem]}" \
  > metrics.json
