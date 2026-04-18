#!/usr/bin/env bash
# utils/bars.sh
# Functions to render ASCII bars and tiny sparklines
# Usage: source utils/bars.sh

# make_bar length percent
# prints a bar like: [█████-----] 50%
make_bar() {
  local len=${1:-20}
  local pct=${2:-0}
  # clamp pct to 0-100
  if (( $(echo "$pct < 0" | bc -l) )); then pct=0; fi
  if (( $(echo "$pct > 100" | bc -l) )); then pct=100; fi

  # integer math for filled chars
  local filled=$(( (pct * len) / 100 ))
  local i
  local bar=""
  for ((i=0;i<filled;i++)); do bar+="█"; done
  for ((i=filled;i<len;i++)); do bar+="-"; done
  printf "[%s] %3s%%" "$bar" "$pct"
}

# make_sparkline values...
# prints small sparkline using ▁▂▃▄▅▆▇█ characters
make_sparkline() {
  local values=("$@")
  local -a chars=( ▁ ▂ ▃ ▄ ▅ ▆ ▇ █ )
  local min=999999999
  local max=-999999999
  local v
  for v in "${values[@]}"; do
    # treat non-numeric as 0
    if ! [[ $v =~ ^-?[0-9]+([.][0-9]+)?$ ]]; then v=0; fi
    # use bc for comparisons if floats
    if (( $(echo "$v < $min" | bc -l) )); then min=$v; fi
    if (( $(echo "$v > $max" | bc -l) )); then max=$v; fi
  done
  # avoid div by zero
  local range=$(echo "$max - $min" | bc -l)
  local out=""
  for v in "${values[@]}"; do
    local idx=0
    if (( $(echo "$range > 0" | bc -l) )); then
      # normalize to 0-1 then to 0-7
      idx=$(printf "%.0f" "$(echo "($v - $min) / $range * 7" | bc -l)")
    fi
    # clamp
    if (( idx < 0 )); then idx=0; fi
    if (( idx > 7 )); then idx=7; fi
    out+="${chars[$idx]}"
  done
  printf "%s" "$out"
}
