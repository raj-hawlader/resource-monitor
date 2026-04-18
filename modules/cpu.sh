#!/usr/bin/env bash
# modules/cpu.sh  (robust, drop-in replacement)
# Exposes:
#  - get_cpu_overview    -> prints "TOTAL_PERCENT|LOAD1|LOAD5|LOAD15"
#  - get_cpu_percore_bars -> prints multi-line "CoreN: [bar] XX%"

# locate bars util (try relative path first, then PATH)
if [ -f "$(dirname "${BASH_SOURCE[0]}")/../utils/bars.sh" ]; then
  source "$(dirname "${BASH_SOURCE[0]}")/../utils/bars.sh"
else
  # fallback: try to source from cwd utils
  [ -f "utils/bars.sh" ] && source "utils/bars.sh"
fi

# Helper: read cpu lines into arrays of totals and idles
_read_all_cpu() {
  # prints lines: total idle (one per CPU line: cpu, cpu0, cpu1, ...)
  awk '/^cpu/ {
    idle = $5 + $6; total=0; for(i=2;i<=NF;i++) total+= $i;
    print total " " idle
  }' /proc/stat
}

# compute percent from two snapshots (total1 idle1 ; total2 idle2)
_compute_pct_from_snapshot_lines() {
  # expects two lines per CPU in order; called internally
  local t1 idle1 t2 idle2
  t1=$1; idle1=$2; t2=$3; idle2=$4
  local dt=$((t2 - t1))
  local di=$((idle2 - idle1))
  if (( dt <= 0 )); then
    echo 0
    return
  fi
  local used=$((dt - di))
  echo $(( (used * 100) / dt ))
}

# get_cpu_overview: prints "TOTAL_PERCENT|LOAD1|LOAD5|LOAD15"
get_cpu_overview() {
  # snapshot 1 (first line is aggregate)
  mapfile -t snap1 < <(_read_all_cpu)
  # small sleep (tunable)
  sleep 0.20
  mapfile -t snap2 < <(_read_all_cpu)

  if [ ${#snap1[@]} -lt 1 ] || [ ${#snap2[@]} -lt 1 ]; then
    echo "0|0|0|0"
    return 0
  fi

  # parse first line
  read -r t1 idle1 <<<"${snap1[0]}"
  read -r t2 idle2 <<<"${snap2[0]}"
  pct=$(_compute_pct_from_snapshot_lines "$t1" "$idle1" "$t2" "$idle2" )

  # load averages
  if read -r la1 la5 la15 _ < /proc/loadavg 2>/dev/null; then
    :
  else
    la1=0; la5=0; la15=0
  fi

  echo "${pct}|${la1}|${la5}|${la15}"
}

# get_cpu_percore_bars: prints multiple lines "CoreN: [bar] XX%"
get_cpu_percore_bars() {
  local barlen=${1:-20}
  mapfile -t snap1 < <(_read_all_cpu)
  sleep 0.20
  mapfile -t snap2 < <(_read_all_cpu)

  # ensure equal length
  local n1=${#snap1[@]} n2=${#snap2[@]}
  local n=${n1}
  (( n2 < n1 )) && n=$n2

  for ((i=1; i<n; i++)); do   # start from 1 to skip aggregate (snap1[0])
    read -r t1 idle1 <<<"${snap1[i]}"
    read -r t2 idle2 <<<"${snap2[i]}"
    pct=$(_compute_pct_from_snapshot_lines "$t1" "$idle1" "$t2" "$idle2")
    # Core index is (i-1) because snap1[1] = cpu0
    core_idx=$((i-1))
    printf "Core%-2d: %s\n" "$core_idx" "$(make_bar "$barlen" "$pct")"
  done
}
