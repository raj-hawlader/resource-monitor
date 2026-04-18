#!/usr/bin/env bash
# modules/disk.sh
# Disk helpers for htoppp
# Exposes:
#  - get_disk_overview [interval_ms]  -> prints "READ_KBPS|WRITE_KBPS"
#  - get_disk_bars [barlen] [max_kbps] -> prints two lines for read & write and a summary of top mounts

source "$(dirname "${BASH_SOURCE[0]}")/../utils/bars.sh" 2>/dev/null || true

# _read_diskstats: prints "major minor name sectors_read sectors_written" lines for block devices
_read_diskstats() {
  # /proc/diskstats format: major minor name reads completed ... sectors read ... writes completed ... sectors written ...
  # We'll print: name sectors_read sectors_written
  awk '{
    # ignore loop and ram devices and partitions (name containing digits), and ignore devices with name starting with "loop" or "ram"
    name=$3;
    if (name ~ /^(loop|ram|fd|sr)/) next;
    # skip partition entries like sda1 (we want whole device only)
    if (name ~ /[0-9]$/) next;
    # sectors_read is $6, sectors_written is $10 (kernel format)
    print name, $6+0, $10+0;
  }' /proc/diskstats 2>/dev/null || true
}

# _sum_disk: sums the 2nd and 3rd columns from _read_diskstats output
_sum_disk() {
  awk '{ rx += $2; wx += $3 } END { print rx+0, wx+0 }'
}

# convert sectors -> bytes (assume 512B sectors) then to KB (rounded)
_sectors_to_kbps() {
  local sectors=$1
  local interval_s=$2
  # bytes = sectors * 512 ; KB/s = bytes/1024 / interval_s = sectors * 0.5 / interval_s
  awk -v s="$sectors" -v t="$interval_s" 'BEGIN{ printf "%.0f", (s * 0.5) / t }'
}

# get_disk_overview [interval_ms]
get_disk_overview() {
  local interval_ms=${1:-500}
  local interval_s=$(awk -v ms="$interval_ms" 'BEGIN{ printf "%.3f", ms/1000 }')

  # snapshot 1
  local s1 s2 rx1 wx1 rx2 wx2
  s1=$(_read_diskstats)
  read -r rx1 wx1 <<<"$(printf "%s" "$s1" | _sum_disk)"

  sleep "$interval_s"

  s2=$(_read_diskstats)
  read -r rx2 wx2 <<<"$(printf "%s" "$s2" | _sum_disk)"

  # deltas
  local drx dwx
  drx=$((rx2 - rx1))
  dwx=$((wx2 - wx1))
  (( drx < 0 )) && drx=0
  (( dwx < 0 )) && dwx=0

  # convert to KB/s
  local read_kbps write_kbps
  read_kbps=$(_sectors_to_kbps "$drx" "$interval_s")
  write_kbps=$(_sectors_to_kbps "$dwx" "$interval_s")

  echo "${read_kbps}|${write_kbps}"
}

# helper: top mounted partitions (df -h), print up to N lines (default 3)
_top_mounts() {
  local n=${1:-3}
  # exclude tmpfs/devtmpfs and show source,pcent,target
  df -h --output=source,pcent,target 2>/dev/null \
    | grep -vE 'tmpfs|devtmpfs|udev' \
    | sed 1d \
    | head -n "$n" \
    | awk '{ printf "%s %s %s\n", $1, $2, $3 }'
}

# get_disk_bars [barlen] [max_kbps]
get_disk_bars() {
  local barlen=${1:-30}
  local max_kbps=${2:-10240}  # default 10 MB/s for scaling

  IFS="|" read -r rk wk < <(get_disk_overview 500)

  # percent relative to max_kbps
  local r_pct w_pct
  r_pct=$(awk -v v="$rk" -v m="$max_kbps" 'BEGIN{ p=(m>0? v/m*100:0); if(p<0)p=0; if(p>100)p=100; printf "%d", p }')
  w_pct=$(awk -v v="$wk" -v m="$max_kbps" 'BEGIN{ p=(m>0? v/m*100:0); if(p<0)p=0; if(p>100)p=100; printf "%d", p }')

  local r_bar w_bar
  r_bar=$(make_bar "$barlen" "$r_pct")
  w_bar=$(make_bar "$barlen" "$w_pct")

  printf "READ:  %s  %s KB/s\n" "$r_bar" "$rk"
  printf "WRITE: %s  %s KB/s\n" "$w_bar" "$wk"
  echo
  echo "Top mounts:"
  _top_mounts 5 | while read -r src pcent mount; do
    printf " %s %s on %s\n" "$src" "$pcent" "$mount"
  done
}
