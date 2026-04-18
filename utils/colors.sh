#!/usr/bin/env bash
# utils/colors.sh
# ANSI color helpers and simple wrappers
# Usage: source utils/colors.sh

# Basic colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'
BOLD='\033[1m'
RESET='\033[0m'

# Color helper: colorize text
# args: color_code text
colorize() {
  local color="$1"; shift
  printf "%b%s%b" "$color" "$*" "$RESET"
}

# Threshold-based color for percentages
# args: percent
# prints color code (not reset)
percent_color() {
  local p=${1%%.*}   # integer part
  if (( p >= 80 )); then
    printf "%b" "$RED"
  elif (( p >= 60 )); then
    printf "%b" "$YELLOW"
  else
    printf "%b" "$GREEN"
  fi
}
