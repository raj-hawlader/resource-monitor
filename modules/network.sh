#!/usr/bin/env bash
# modules/network.sh
# Network helpers for htoppp
# Exposes:
#  - get_net_overview [interval_ms]    -> prints "RX_KBPS|TX_KBPS|RX_TOTAL_MB|TX_TOTAL_MB"
#  - get_net_bars [barlen] [max_kbps]  -> prints 2 lines: "DL : [bar] X KB/s" "UL : [bar] Y KB/s"
# Notes:
#  - interval_ms defaults to 500 ms
#  - max_kbps is used to scale bars; default 10240 (10 MB/s)

source "$(dirname "${BASH_SOURCE[0]}")/../utils/bars.sh" 2>/dev/null || true

# read_net: prints lines "iface rx_bytes tx_bytes" for non-loopback interfaces
_read_net() {
  awk 'NR>2 {
    gsub(":", "", $1);
    iface=$1; rx=$2; tx=$10;
    if (iface != "lo") print iface, rx, tx;
  }' /proc/net/dev 2>/dev/null || true
}

# sum_net: given _read_net output, sums rx and tx bytes
_sum_net() {
  awk '{
    rx += $2; tx += $3;
  } END { print rx+0, tx+0 }'
}

# format_bytes_to_mb: integer MB with no decimals
_format_mb() {
  awk -v b="$1" 'BEGIN{ printf "%d", (b/1024/1024) }'
}

# get_net_overview [interval_ms]
get_net_overview() {
  local interval_ms=${1:-500}
  local interval_s=$(awk -v ms="$interval_ms" 'BEGIN{ printf "%.3f", ms/1000 }')

  # snapshot 1
  local s1 s2 rx1 tx1 rx2 tx2
  s1=$(_read_net)
  read -r rx1 tx1 <<<"$(printf "%s" "$s1" | _sum_net)"

  # sleep
  sleep "$interval_s"

  # snapshot 2
  s2=$(_read_net)
  read -r rx2 tx2 <<<"$(printf "%s" "$s2" | _sum_net)"

  # compute delta bytes
  local drx dtx
  drx=$((rx2 - rx1))
  dtx=$((tx2 - tx1))
  # avoid negative
  (( drx < 0 )) && drx=0
  (( dtx < 0 )) && dtx=0

  # speeds in KB/s (use floating then round)
  local rx_kbps tx_kbps
  rx_kbps=$(awk -v b="$drx" -v t="$interval_s" 'BEGIN{ printf "%.0f", (b/1024) / t }')
  tx_kbps=$(awk -v b="$dtx" -v t="$interval_s" 'BEGIN{ printf "%.0f", (b/1024) / t }')

  # totals (MB) from snapshot2
  local rx_total_mb tx_total_mb
  rx_total_mb=$(_format_mb "$rx2")
  tx_total_mb=$(_format_mb "$tx2")

  echo "${rx_kbps}|${tx_kbps}|${rx_total_mb}|${tx_total_mb}"
}

# get_net_bars [barlen] [max_kbps]
get_net_bars() {
  local barlen=${1:-30}
  local max_kbps=${2:-10240}   # default 10 MB/s
  IFS="|" read -r rx_kbps tx_kbps rx_total tx_total < <(get_net_overview 500)

  # percent calculation (clamp at 100)
  local rx_pct tx_pct
  rx_pct=$(awk -v v="$rx_kbps" -v m="$max_kbps" 'BEGIN{ p=(m>0? v/m*100:0); if(p<0)p=0; if(p>100)p=100; printf "%d", p }')
  tx_pct=$(awk -v v="$tx_kbps" -v m="$max_kbps" 'BEGIN{ p=(m>0? v/m*100:0); if(p<0)p=0; if(p>100)p=100; printf "%d", p }')

  local rx_bar tx_bar
  rx_bar=$(make_bar "$barlen" "$rx_pct")
  tx_bar=$(make_bar "$barlen" "$tx_pct")

  printf "DL : %s  %s KB/s (Total: %s MB)\n" "$rx_bar" "$rx_kbps" "$rx_total"
  printf "UL : %s  %s KB/s (Total: %s MB)\n" "$tx_bar" "$tx_kbps" "$tx_total"
}
