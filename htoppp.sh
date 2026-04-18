#!/usr/bin/env bash
# htoppp.sh - Main controller for HTop++ (Resource Monitor)
# Usage: ./htoppp.sh
# Requires: sourceable modules in ./modules and utils in ./utils

set -euo pipefail
shopt -s expand_aliases

# ---- Config ----
REFRESH_INTERVAL=10          # seconds for main refresh
BAR_LEN=30                  # default bar length for small panels
NET_MAX_KBPS=10240          # 10 MB/s scale for network bars
DISK_MAX_KBPS=10240         # 10 MB/s scale for disk bars
TOP_N=5                     # top N processes

# ---- Locate & source utilities and modules ----
project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# utils
source "$project_root/utils/colors.sh" 2>/dev/null || true
source "$project_root/utils/bars.sh"   2>/dev/null || true

# modules (if missing, print friendly message)
for m in cpu memory process network disk; do
  if [ -f "$project_root/modules/${m}.sh" ]; then
    # shellcheck disable=SC1090
    source "$project_root/modules/${m}.sh"
  else
    printf "%s\n" "Warning: modules/${m}.sh not found — ${m} features will be unavailable." >&2
  fi
done

# ---- Terminal helpers ----
clear_screen() {
  # use tput if available else ANSI
  if command -v tput >/dev/null 2>&1; then
    tput reset
  else
    printf '\033c'
  fi
}

# move cursor to top-left
cursor_top() { printf '\033[H'; }

# print header line
print_header() {
  local title="$1"
  printf "%s\n" "$(colorize "$BOLD$CYAN" "========================================================")"
  printf " %s  |  %s\n" "$(colorize "$BOLD$MAGENTA" "Resource MONITOR")" "$(colorize "$BOLD$WHITE" "$title")"
  printf "%s\n\n" "$(colorize "$BOLD$CYAN" "========================================================")"
}

# Footer / key help
print_footer() {
  printf "\n"
  printf "%s\n" "$(colorize "$YELLOW" "[A] All") $(colorize "$WHITE" "|") $(colorize "$YELLOW" "[C] CPU") $(colorize "$WHITE" "|") $(colorize "$YELLOW" "[M] Mem") $(colorize "$WHITE" "|") $(colorize "$YELLOW" "[N] Net") $(colorize "$WHITE" "|") $(colorize "$YELLOW" "[D] Disk") $(colorize "$WHITE" "|") $(colorize "$YELLOW" "[P] Procs") $(colorize "$WHITE" "|") $(colorize "$YELLOW" "[K] Kill") $(colorize "$WHITE" "|") $(colorize "$YELLOW" "[R] Refresh") $(colorize "$WHITE" "|") $(colorize "$RED" "[Q] Quit")"
}

# helper: draw a labeled block with title and content (multi-line string)
draw_block() {
  local title="$1"
  local content="$2"
  printf "%s\n" "$(colorize "$BOLD$BLUE" "$title")"
  printf "%s\n" "$content"
}

# ---- View state ----
# allowed: all, cpu, mem, net, disk, proc
VIEW="all"

# ---- Input handling ----
handle_key() {
  local key=$1
  case "$key" in
    q|Q) cleanup_and_exit ;;
    r|R) return 0 ;;  # immediate refresh (handled by loop)
    c|C) VIEW="cpu" ;;
    m|M) VIEW="mem" ;;
    n|N) VIEW="net" ;;
    d|D) VIEW="disk" ;;
    p|P) VIEW="proc" ;;
    a|A) VIEW="all" ;;
    k|K) prompt_kill ;;
    *) ;; # ignore others
  esac
  return 0
}

prompt_kill() {
  # prompt for PID (read from stdin) — switch terminal mode to canonical temporarily
  stty sane
  printf "\nEnter PID to kill: "
  read -r pid_input
  # restore raw-ish behavior later (we keep default)
  if [[ -n "${pid_input//[0-9]/}" ]]; then
    printf "%s\n" "$(colorize "$RED" "Invalid PID. Aborting.")"
    sleep 1
    return 0
  fi
  # use module kill_process if available
  if declare -f kill_process >/dev/null 2>&1; then
    kill_output="$(kill_process "$pid_input" 2>&1)"
    printf "%s\n" "$kill_output"
  else
    printf "%s\n" "$(colorize "$YELLOW" "kill_process not available in modules/process.sh")"
  fi
  printf "%s\n" "$(colorize "$GREEN" "Press Enter to continue...")"
  read -r dummy
}

# cleanup and exit
cleanup_and_exit() {
  printf "\n"
  printf "%s\n" "$(colorize "$BOLD$GREEN" "Exiting Resource Monitor — bye!")"
  # restore terminal modes
  stty sane
  exit 0
}

# ---- Rendering functions ----

render_cpu() {
  if declare -f get_cpu_overview >/dev/null 2>&1; then
    IFS="|" read -r cpu_pct la1 la5 la15 < <(get_cpu_overview)
    local percore
    percore=$(get_cpu_percore_bars $BAR_LEN 2>/dev/null || true)
    printf "%s\n" "$(colorize "$BOLD$WHITE" "CPU USAGE:")"
    # bar for aggregate
    local agg_bar
    agg_bar=$(make_bar "$BAR_LEN" "${cpu_pct:-0}")
    printf "  Total: %s  %s%%\n" "$agg_bar" "${cpu_pct:-0}"
    printf "  Load Avg: %s %s %s\n" "$la1" "$la5" "$la15"
    printf "\n"
    # print per-core (limit to terminal height? we just print)
    printf "%s\n" "$percore"
  else
    printf "%s\n" "$(colorize "$YELLOW" "CPU module unavailable")"
  fi
}

render_memory() {
  if declare -f get_memory_overview >/dev/null 2>&1; then
    IFS="|" read -r used_pct used_mb total_mb swap_used swap_total < <(get_memory_overview)
    printf "%s\n" "$(colorize "$BOLD$WHITE" "MEMORY:")"
    local ram_bar
    ram_bar=$(make_bar "$BAR_LEN" "${used_pct:-0}")
    printf "  RAM : %s  %s%%  (%s/%s MB)\n" "$ram_bar" "${used_pct:-0}" "${used_mb:-0}" "${total_mb:-0}"
    local swap_bar
    local swap_pct=0
    if (( swap_total > 0 )); then swap_pct=$(( swap_used * 100 / swap_total )); fi
    swap_bar=$(make_bar "$BAR_LEN" "$swap_pct")
    printf "  SWAP: %s  %s%%  (%s/%s MB)\n" "$swap_bar" "$swap_pct" "$swap_used" "$swap_total"
  else
    printf "%s\n" "$(colorize "$YELLOW" "Memory module unavailable")"
  fi
}

render_network() {
  if declare -f get_net_overview >/dev/null 2>&1; then
    IFS="|" read -r rx_kbps tx_kbps rx_total tx_total < <(get_net_overview 400)
    printf "%s\n" "$(colorize "$BOLD$WHITE" "NETWORK:")"
    local dl_bar ul_bar
    local rx_pct tx_pct
    rx_pct=$(awk -v v="$rx_kbps" -v m="$NET_MAX_KBPS" 'BEGIN{ p=(m>0? v/m*100:0); if(p>100)p=100; printf "%d", p }')
    tx_pct=$(awk -v v="$tx_kbps" -v m="$NET_MAX_KBPS" 'BEGIN{ p=(m>0? v/m*100:0); if(p>100)p=100; printf "%d", p }')
    dl_bar=$(make_bar "$BAR_LEN" "$rx_pct")
    ul_bar=$(make_bar "$BAR_LEN" "$tx_pct")
    printf "  DL : %s  %s KB/s (Total: %s MB)\n" "$dl_bar" "$rx_kbps" "$rx_total"
    printf "  UL : %s  %s KB/s (Total: %s MB)\n" "$ul_bar" "$tx_kbps" "$tx_total"
  else
    printf "%s\n" "$(colorize "$YELLOW" "Network module unavailable")"
  fi
}

render_disk() {
  if declare -f get_disk_overview >/dev/null 2>&1; then
    IFS="|" read -r r_kbps w_kbps < <(get_disk_overview 400)
    printf "%s\n" "$(colorize "$BOLD$WHITE" "DISK I/O:")"
    local r_pct w_pct
    r_pct=$(awk -v v="$r_kbps" -v m="$DISK_MAX_KBPS" 'BEGIN{ p=(m>0? v/m*100:0); if(p>100)p=100; printf "%d", p }')
    w_pct=$(awk -v v="$w_kbps" -v m="$DISK_MAX_KBPS" 'BEGIN{ p=(m>0? v/m*100:0); if(p>100)p=100; printf "%d", p }')
    local r_bar w_bar
    r_bar=$(make_bar "$BAR_LEN" "$r_pct")
    w_bar=$(make_bar "$BAR_LEN" "$w_pct")
    printf "  READ : %s  %s KB/s\n" "$r_bar" "$r_kbps"
    printf "  WRITE: %s  %s KB/s\n" "$w_bar" "$w_kbps"
    printf "\n"
    # show top mounts
    if declare -f _top_mounts >/dev/null 2>&1; then
      printf "%s\n" "$(colorize "$BOLD$WHITE" "Top Mounts:")"
      _top_mounts 5 | while read -r src pcent mount; do
        printf "    %s %s on %s\n" "$src" "$pcent" "$mount"
      done
    fi
  else
    printf "%s\n" "$(colorize "$YELLOW" "Disk module unavailable")"
  fi
}

render_processes() {
  if declare -f get_top_cpu >/dev/null 2>&1; then
    printf "%s\n" "$(colorize "$BOLD$WHITE" "TOP PROCESSES (By CPU):")"
    get_top_cpu "$TOP_N" | while IFS='|' read -r pid user pcpu pmem cmd; do
      printf "  %6s %-10s %5s%% %5s%% %s\n" "$pid" "$user" "$pcpu" "$pmem" "$cmd"
    done
    printf "\n"
  fi
  if declare -f get_top_mem >/dev/null 2>&1; then
    printf "%s\n" "$(colorize "$BOLD$WHITE" "TOP PROCESSES (By MEM):")"
    get_top_mem "$TOP_N" | while IFS='|' read -r pid user pcpu pmem cmd; do
      printf "  %6s %-10s %5s%% %5s%% %s\n" "$pid" "$user" "$pcpu" "$pmem" "$cmd"
    done
  fi
}

render_system_info() {
  # small system info
  local up host kernel users
  up=$(awk '{print int($1/3600) "h " int(($1%3600)/60) "m"}' /proc/uptime 2>/dev/null || echo "N/A")
  host=$(hostname 2>/dev/null || echo "N/A")
  kernel=$(uname -r 2>/dev/null || echo "N/A")
  users=$(who | wc -l 2>/dev/null || echo "0")
  printf "%s\n" "$(colorize "$BOLD$WHITE" "SYSTEM:")"
  printf "  Host: %s  Kernel: %s  Uptime: %s  Users: %s\n\n" "$host" "$kernel" "$up" "$users"
}

# ---- Main loop ----
main_loop() {
  # trap Ctrl-C to cleanup
  trap cleanup_and_exit INT TERM

  while true; do
    clear_screen
    print_header "View: ${VIEW^^}   (Refresh ${REFRESH_INTERVAL}s)"

    # Render per current view
    case "$VIEW" in
      all)
        render_system_info
        render_cpu
        render_memory
        render_disk
        render_network
        render_processes
        ;;
      cpu) render_cpu ;;
      mem) render_memory ;;
      net) render_network ;;
      disk) render_disk ;;
      proc) render_processes ;;
      *) render_system_info ;;
    esac

    print_footer

    # Wait for key or timeout
    # read one char with timeout; if none, refresh
    # read -rsn1 -t "$REFRESH_INTERVAL" key 2>/dev/null || true
    read -rsn1 key 2>/dev/null || true
    if [ -n "${key:-}" ]; then
      handle_key "$key"
    fi
    # loop continues (immediate refresh if key was R or view changed)
  done
}

# ---- Start ----
# sanity: ensure required functions exist (not fatal)
echo "$(colorize "$BOLD$GREEN" "Starting Resource Monitor — press Q to quit")"
sleep 0.5
main_loop
