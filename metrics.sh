#!/bin/bash

mypgid=$(ps -o pgid= -p $$ | tr -d ' ')
tmp1=$(mktemp)
tmp2=$(mktemp)
trap 'rm -f "$tmp1" "$tmp2"' EXIT

# Snapshot: "CPU total idle" and "P pid jiffies" for each process, plus "NET iface rx tx" bytes
# Matches btop's /proc/stat formula: total=user+nice+sys+idle+iowait+irq+softirq+steal, idle=idle+iowait
take_snapshot() {
  awk '/^cpu /{print "CPU", $2+$3+$4+$5+$6+$7+$8+$9, $5+$6}' /proc/stat
  awk 'FNR==1{
    pid=$1; line=$0
    sub(/^[0-9]+ \(.*\) /, "", line)
    split(line, f, " ")
    if (length(f) >= 13) print "P", pid, f[12]+f[13]
  }' /proc/[0-9]*/stat 2>/dev/null
  awk 'NR>2{
    sub(/^ +/, "")
    n = split($0, a, "[: ]+")
    iface = a[1]
    if (n >= 10 && iface !~ /^(lo|veth|docker|br-|virbr)/) print "NET", iface, a[2], a[10]
  }' /proc/net/dev
}

# CPU package power via RAPL (/sys/class/powercap). Root-only file, fine since this
# script runs as root under update-metrics.service. Not available on all hardware.
rapl_dir=""
for d in /sys/class/powercap/intel-rapl:[0-9]*; do
  [ -d "$d" ] || continue
  if [ "$(cat "$d/name" 2>/dev/null)" = "package-0" ] && [ -r "$d/energy_uj" ]; then
    rapl_dir="$d"
    break
  fi
done
rapl_max=0
[ -n "$rapl_dir" ] && rapl_max=$(cat "$rapl_dir/max_energy_range_uj" 2>/dev/null || echo 0)

# Samples RAPL energy every 200ms across ~2s (instead of a plain sleep) so short wraparound
# windows (some AMD parts wrap their counter in ~1s under load) can't be missed between reads.
# Prints average watts over the window, or nothing if RAPL isn't available.
sample_power() {
  if [ -z "$rapl_dir" ] || [ "$rapl_max" -le 0 ]; then
    sleep 2
    return
  fi
  local steps=10 interval=0.2
  local prev cur d total_uj=0 t_start t_end
  prev=$(cat "$rapl_dir/energy_uj" 2>/dev/null)
  if [ -z "$prev" ]; then
    sleep 2
    return
  fi
  t_start=$(date +%s.%N)
  for i in $(seq 1 $steps); do
    sleep "$interval"
    cur=$(cat "$rapl_dir/energy_uj" 2>/dev/null)
    [ -z "$cur" ] && cur=$prev
    d=$(( cur - prev ))
    [ "$d" -lt 0 ] && d=$(( d + rapl_max ))
    total_uj=$(( total_uj + d ))
    prev=$cur
  done
  t_end=$(date +%s.%N)
  awk -v uj="$total_uj" -v a="$t_start" -v b="$t_end" 'BEGIN{ dt=b-a; if (dt>0) printf "%.2f", uj/1000000/dt }'
}

cpu_usage() {
  local state="${CPU_STATE_FILE:-/home/alex/.cache/metrics_cpu_prev}"
  mkdir -p "$(dirname "$state")"
  # btop fields: 0=user 1=nice 2=sys 3=idle 4=iowait 5=irq 6=softirq 7=steal 8=guest 9=guest_nice
  read -r totals idles < <(awk '/^cpu / {
    sum=0; for (i=2;i<=NF;i++) sum+=$i
    g=0; if (NF>=10) g+=$10; if (NF>=11) g+=$11   # subtract guest + guest_nice
    idle=$5; if (NF>=6) idle+=$6                   # idle + iowait
    print sum-g, idle; exit
  }' /proc/stat)

  local prev_total=0 prev_idle=0
  [[ -r "$state" ]] && read -r prev_total prev_idle < "$state"
  printf '%s %s\n' "$totals" "$idles" > "$state"

  awk -v t="$totals" -v i="$idles" -v pt="$prev_total" -v pi="$prev_idle" 'BEGIN {
    dt = t - pt; di = i - pi
    if (dt < 1) dt = 1; if (di < 0) di = 0
    p = (dt - di) * 100 / dt
    if (p < 0) p = 0; if (p > 100) p = 100
    printf "%d", p + 0.5     # round + clamp, exactly like btop
  }'
}

net_t0=$(date +%s.%N)
take_snapshot > "$tmp1"
power_w=$(sample_power)
take_snapshot > "$tmp2"
net_t1=$(date +%s.%N)
dt_wall=$(awk -v a="$net_t0" -v b="$net_t1" 'BEGIN{printf "%.3f", b-a}')

# Compute overall cpu%, per-pid cpu% from jiffie deltas (same method as btop), and per-iface net rates
cpu_result=$(awk -v dt_wall="$dt_wall" '
FNR == NR {
  if ($1 == "CPU") { t1=$2; i1=$3 }
  else if ($1 == "P") { j1[$2] = $3+0 }
  else if ($1 == "NET") { rx1[$2] = $3+0; tx1[$2] = $4+0 }
  next
}
{
  if ($1 == "CPU") { t2=$2; i2=$3 }
  else if ($1 == "P") { j2[$2] = $3+0 }
  else if ($1 == "NET") { rx2[$2] = $3+0; tx2[$2] = $4+0 }
}
END {
  dt = t2-t1; di = i2-i1
  printf "CPU %.1f\n", (dt > 0 ? 100*(dt-di)/dt : 0)
  for (p in j2) {
    dj = j2[p] - (p in j1 ? j1[p] : j2[p])
    printf "PCPU %s %.2f\n", p, (dt > 0 && dj > 0) ? 100*dj/dt : 0
  }
  for (n in rx2) {
    drx = rx2[n] - (n in rx1 ? rx1[n] : rx2[n])
    dtx = tx2[n] - (n in tx1 ? tx1[n] : tx2[n])
    if (drx < 0) drx = 0
    if (dtx < 0) dtx = 0
    rx_rate = (dt_wall+0 > 0) ? drx/dt_wall : 0
    tx_rate = (dt_wall+0 > 0) ? dtx/dt_wall : 0
    printf "NETRATE %s %.0f %.0f %.0f %.0f\n", n, rx_rate, tx_rate, rx2[n], tx2[n]
  }
}
' "$tmp1" "$tmp2")

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

# Container-id -> name map, so generic binaries running inside a container (ffmpeg,
# python, java, ...) can be labeled with the container instead of just the binary.
docker_map=""
if command -v docker >/dev/null 2>&1; then
  docker_map=$(timeout 2 docker ps --no-trunc --format '{{.ID}} {{.Names}}' 2>/dev/null)
fi

top_procs=$(ps -eo pgid=,pid=,rss=,args= | awk -v mypgid="$mypgid" -v cpu_data="$cpu_result" -v docker_map="$docker_map" '
BEGIN {
  n = split(cpu_data, lines, "\n")
  for (i = 1; i <= n; i++) {
    split(lines[i], f, " ")
    if (f[1] == "PCPU") pid_cpu[f[2]] = f[3]+0
  }
  m = split(docker_map, dlines, "\n")
  for (i = 1; i <= m; i++) {
    if (dlines[i] == "") continue
    split(dlines[i], df, " ")
    cname[df[1]] = df[2]
  }
}
{
  pgid=$1+0; pid=$2+0; rss_kb=$3+0
  if (pgid == mypgid+0) next
  cmd = $4
  if (cmd ~ /\/proc\/self\/exe/) {
    "readlink /proc/" pid "/exe 2>/dev/null" | getline cmd
    close("readlink /proc/" pid "/exe 2>/dev/null")
  }
  n_parts = split(cmd, parts, "/"); base = parts[n_parts]
  if (base == "") base = "unknown"

  # Resolve an owner from the cgroup leaf: the docker container name, or the
  # innermost systemd unit. Generic names like ffmpeg/python/java get prefixed
  # with it so processes spawned by different services don'\''t get lumped together.
  label = ""
  cgfile = "/proc/" pid "/cgroup"
  if ((getline cgline < cgfile) > 0) {
    nseg = split(cgline, segs, "/")
    leaf = segs[nseg]
    if (leaf ~ /^docker-[0-9a-f]+\.scope$/) {
      id = leaf
      sub(/^docker-/, "", id); sub(/\.scope$/, "", id)
      if (id in cname) label = cname[id]
    } else if (leaf ~ /\.service$/) {
      label = leaf
      sub(/\.service$/, "", label)
    }
  }
  close(cgfile)

  if (label == "" || index(label, base) > 0 || index(base, label) > 0) name = (label != "" ? label : base)
  else name = label ":" base
  if (length(name) > 36) name = substr(name, 1, 36)
  gsub(/["\\]/, "_", name)
  cpu_t[name] += (pid in pid_cpu) ? pid_cpu[pid] : 0
  mem_t[name] += rss_kb / 1024
  cnt[name]++
}
END {
  for (n in cpu_t) printf "%.1f\t%.0f\t%d\t%s\n", cpu_t[n], mem_t[n], cnt[n], n
}')

top_cpu=$(echo "$top_procs" | sort -t$'\t' -rn -k1 | head -5 | awk -F'\t' '{
  printf "%s{\"name\":\"%s\",\"cpu\":%s,\"mem_mb\":%s,\"procs\":%s}",
    (NR>1?",":""), $4, $1, $2, $3
}')

top_mem=$(echo "$top_procs" | sort -t$'\t' -rn -k2 | head -5 | awk -F'\t' '{
  printf "%s{\"name\":\"%s\",\"cpu\":%s,\"mem_mb\":%s,\"procs\":%s}",
    (NR>1?",":""), $4, $1, $2, $3
}')

net_interfaces=$(echo "$cpu_result" | awk -F' ' '$1=="NETRATE"{
  printf "%s{\"iface\":\"%s\",\"rx_bps\":%s,\"tx_bps\":%s,\"rx_bytes_total\":%s,\"tx_bytes_total\":%s}",
    (n++>0?",":""), $2, $3, $4, $5, $6
}')
# Headline rx/tx should reflect real wire traffic only. Interfaces with no /sys .../device
# symlink are virtual (tailscale0, wg*, etc); tailscale traffic is re-encapsulated and already
# counted on the physical NIC, so summing it in too would double-count those bytes.
phys_ifaces=""
for d in /sys/class/net/*/; do
  n=$(basename "$d")
  [ -e "$d/device" ] && phys_ifaces="$phys_ifaces $n"
done
read -r net_rx_bps net_tx_bps < <(echo "$cpu_result" | awk -v phys="$phys_ifaces" '
  BEGIN { m = split(phys, arr, " "); for (i = 1; i <= m; i++) isphys[arr[i]] = 1 }
  $1=="NETRATE" && ($2 in isphys) {rx+=$3; tx+=$4}
  END{printf "%.0f %.0f", rx, tx}')
net="{\"rx_bps\":${net_rx_bps:-0},\"tx_bps\":${net_tx_bps:-0},\"interfaces\":[$net_interfaces]}"
power_json="${power_w:-null}"

echo "{\"cpu\":$cpu,\"ram\":$mem,\"ram_used_mb\":$mem_used,\"ram_total_mb\":$mem_total,\"uptime_s\":$uptime_s,\"disks\":$disks,\"proc_count\":$proc_count,\"timestamp\":$timestamp,\"net\":$net,\"power_w\":$power_json,\"top_cpu\":[$top_cpu],\"top_mem\":[$top_mem]}" \
  > /home/alex/metrics.json
