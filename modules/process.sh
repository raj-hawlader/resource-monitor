#!/usr/bin/env bash
# modules/process.sh  (safer, root-owner protection)
: "${PS:=ps}"
: "${AWK:=awk}"
: "${SORT:=sort}"
: "${HEAD:=head}"

get_top_cpu() {
  local n=${1:-5}
  ${PS} -eo pid,user,%cpu,%mem,comm --no-headers \
    | ${AWK} '{ printf "%6s|%8s|%5s|%5s|%s\n", $1, $2, $3, $4, $5 }' \
    | ${SORT} -t'|' -k3 -nr \
    | ${HEAD} -n "$n"
}

get_top_mem() {
  local n=${1:-5}
  ${PS} -eo pid,user,%cpu,%mem,comm --no-headers \
    | ${AWK} '{ printf "%6s|%8s|%5s|%5s|%s\n", $1, $2, $3, $4, $5 }' \
    | ${SORT} -t'|' -k4 -nr \
    | ${HEAD} -n "$n"
}

# kill_process: SAFE version
kill_process() {
  local pid="$1"

  # basic validation
  if ! [[ "$pid" =~ ^[0-9]+$ ]]; then
    echo "ERROR: invalid pid: $pid" >&2
    return 1
  fi

  # protect monitor and parent and init
  local mypid="$$"
  local myppid="$PPID"
  if [[ "$pid" -eq "$mypid" ]]; then
    echo "Refusing to kill the monitor (PID $pid)."
    return 1
  fi
  if [[ "$pid" -eq "$myppid" ]]; then
    echo "Refusing to kill the parent shell (PID $pid)."
    return 1
  fi
  if [[ "$pid" -eq 1 ]]; then
    echo "Refusing to kill PID 1 (init/system)."
    return 1
  fi

  # get owner uid and command name
  local owner_uid
  owner_uid=$(awk -v p="$pid" 'BEGIN{ uid=0 } $1==p { print $5 }' /proc/"$pid"/status 2>/dev/null || true)
  # fallback: if /proc not accessible, check ps
  if [[ -z "$owner_uid" ]]; then
    owner_uid=$(ps -o uid= -p "$pid" 2>/dev/null || echo "")
    owner_uid="${owner_uid// /}"
  fi

  local cmdname
  cmdname=$(ps -o comm= -p "$pid" 2>/dev/null || echo "")

  # refuse to kill internal pipeline processes
  case "$cmdname" in
    ps|awk|sort|head|bash|sh)
      echo "Refusing to kill internal/critical process: $cmdname (PID $pid)"
      return 1
      ;;
  esac

  # refuse to kill root-owned processes unless we are root
  if [[ -n "$owner_uid" ]] && [[ "$owner_uid" -eq 0 ]]; then
    if [[ "$(id -u)" -ne 0 ]]; then
      echo "Refusing to kill process owned by root (PID $pid, UID 0). Run as root to override."
      return 1
    fi
  fi

  # verify process exists
  if ! kill -0 "$pid" 2>/dev/null; then
    echo "No such process: $pid"
    return 1
  fi

  # attempt graceful termination
  if ! kill -15 "$pid" 2>/dev/null; then
    echo "Failed to send SIGTERM to $pid"
    return 1
  fi

  # wait briefly (up to 3s)
  local i=0
  while kill -0 "$pid" 2>/dev/null && (( i < 30 )); do
    sleep 0.1
    ((i++))
  done

  if kill -0 "$pid" 2>/dev/null; then
    # still alive -> escalate
    if kill -9 "$pid" 2>/dev/null; then
      sleep 0.1
      if ! kill -0 "$pid" 2>/dev/null; then
        echo "Process $pid force killed"
        return 0
      else
        echo "Failed to kill $pid after SIGKILL"
        return 1
      fi
    else
      echo "Failed to send SIGKILL to $pid"
      return 1
    fi
  else
    echo "Process $pid terminated"
    return 0
  fi
}
