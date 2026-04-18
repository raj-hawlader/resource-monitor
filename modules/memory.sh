#!/usr/bin/env bash
# modules/memory.sh
# Provides:
#   - get_memory_overview
#   - get_memory_bars

source "$(dirname "${BASH_SOURCE[0]}")/../utils/bars.sh" 2>/dev/null || true

# Parse /proc/meminfo and compute memory stats
# Returns: used_percent used_mb total_mb swap_used_mb swap_total_mb
get_memory_overview() {
    local mem_total mem_avail mem_free buffers cached
    local swap_total swap_free

    # Read meminfo
    while IFS=":" read -r key value; do
        val=$(echo "$value" | awk '{print $1}')
        case "$key" in
            "MemTotal")   mem_total=$val ;;
            "MemAvailable") mem_avail=$val ;;
            "SwapTotal")  swap_total=$val ;;
            "SwapFree")   swap_free=$val ;;
        esac
    done < /proc/meminfo

    # Convert kB → MB
    local mem_total_mb=$((mem_total / 1024))
    local mem_avail_mb=$((mem_avail / 1024))
    local mem_used_mb=$((mem_total_mb - mem_avail_mb))

    local swap_total_mb=$((swap_total / 1024))
    local swap_free_mb=$((swap_free / 1024))
    local swap_used_mb=$((swap_total_mb - swap_free_mb))

    # Percentage
    local used_percent=0
    if (( mem_total_mb > 0 )); then
        used_percent=$(( (mem_used_mb * 100) / mem_total_mb ))
    fi

    echo "${used_percent}|${mem_used_mb}|${mem_total_mb}|${swap_used_mb}|${swap_total_mb}"
}

# Pretty printed bars
get_memory_bars() {
    local barlen=${1:-30}

    IFS="|" read -r pct used total swap_used swap_total < <(get_memory_overview)

    # RAM bar
    local ram_bar
    ram_bar=$(make_bar "$barlen" "$pct")

    # Swap percent
    local swap_pct=0
    if (( swap_total > 0 )); then
        swap_pct=$(( (swap_used * 100) / swap_total ))
    fi

    local swap_bar
    swap_bar=$(make_bar "$barlen" "$swap_pct")

    printf "RAM : %s  (%s/%s MB)\n" "$ram_bar" "$used" "$total"
    printf "SWAP: %s  (%s/%s MB)\n" "$swap_bar" "$swap_used" "$swap_total"
}
