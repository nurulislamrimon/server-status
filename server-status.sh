#!/usr/bin/env bash
# =============================================================================
# Server Status – Grafana-style Terminal Dashboard
# Author: Nurul Islam Rimon (nurulislamrimon)
# Version: 1.0.7 (CPU FIX)
# License: MIT
# =============================================================================

REFRESH=1.5
NET_DEV=""
SERVICES=("nginx" "apache2" "mysql" "redis" "docker" "pm2" "cron" "ssh" "ufw" "fail2ban")

# ───── CPU GLOBALS (FIX) ─────
prev_idle=0
prev_total=0

show_help() {
    echo "Usage: server-status [OPTIONS]"
    echo " --help"
    echo " --interface <name>"
    echo " --refresh <seconds>"
    echo " --services \"svc1,svc2\""
    exit 0
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --help) show_help ;;
        --interface) NET_DEV="$2"; shift 2 ;;
        --refresh) REFRESH="$2"; shift 2 ;;
        --services) IFS=',' read -r -a SERVICES <<< "$2"; shift 2 ;;
        *) echo "Unknown option: $1"; show_help ;;
    esac
done

[[ -z "$NET_DEV" ]] && NET_DEV=$(ip route show default | awk '{print $5}' | head -1)
[[ -z "$NET_DEV" ]] && NET_DEV="eth0"

trap 'echo -e "\e[?25h\e[0m\e[?1049l"; tput cnorm; clear; exit' INT TERM EXIT
echo -e "\e[?25l\e[?1049h"

RESET="\e[0m"; BOLD="\e[1m"; GRAY="\e[90m"
WHITE="\e[97m"; GREEN="\e[32m"; YELLOW="\e[33m"
RED="\e[31m"; CYAN="\e[36m"; BLUE="\e[34m"
DOT="●"

LEFT_COL=2
RIGHT_COL=44
PANEL_WIDTH=40

prev_rx=0
prev_tx=0

draw_static_box() {
    local r=$1 c=$2 w=$3 h=$4 title="$5"
    echo -ne "\e[${r};${c}H${GRAY}┌$(printf '─%.0s' $(seq 1 $((w-2))))┐${RESET}"
    ((r++))
    echo -ne "\e[${r};${c}H${GRAY}│${RESET} ${BOLD}${WHITE}${title}${RESET}"
    printf ' %.0s' $(seq 1 $((w-${#title}-3)))
    echo -ne "${GRAY}│${RESET}"
    ((r++))
    echo -ne "\e[${r};${c}H${GRAY}├$(printf '─%.0s' $(seq 1 $((w-2))))┤${RESET}"
    for ((i=1;i<=h-4;i++)); do
        ((r++))
        echo -ne "\e[${r};${c}H${GRAY}│${RESET}$(printf ' %.0s' $(seq 1 $((w-2))))${GRAY}│${RESET}"
    done
    ((r++))
    echo -ne "\e[${r};${c}H${GRAY}└$(printf '─%.0s' $(seq 1 $((w-2))))┘${RESET}"
}

update_line() {
    echo -ne "\e[$1;$2H$3$RESET\e[K"
}

# ───────────────── CPU PANEL (FIXED) ─────────────────
update_cpu_panel() {

    # Kernel-trusted CPU usage (delta based)
    read cpu user nice system idle iowait irq softirq steal _ < /proc/stat

    local idle_now=$((idle + iowait))
    local total_now=$((user + nice + system + idle + iowait + irq + softirq + steal))

    local diff_idle=$((idle_now - prev_idle))
    local diff_total=$((total_now - prev_total))

    local usage=0
    (( diff_total > 0 )) && usage=$(awk "BEGIN {printf \"%.1f\", 100*(1-$diff_idle/$diff_total)}")

    prev_idle=$idle_now
    prev_total=$total_now

    local usage_int=$(awk "BEGIN {print int($usage * 10)}")

    local usage_color=$GREEN
    (( usage_int >= 900 )) && usage_color=$RED
    (( usage_int >= 700 && usage_int < 900 )) && usage_color=$YELLOW

    local total_procs=$(ps -e --no-headers | wc -l)
    local active_procs=$(ps -eo pcpu | awk '$1>0{c++} END{print c+0}')
    local load=$(cut -d' ' -f1-3 /proc/loadavg)

    local temp=$(cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null | sort -nr | head -1)
    [[ -n "$temp" ]] && temp=$((temp/1000)) || temp="N/A"

    update_line 5  $((LEFT_COL+2)) "Total Usage     : ${usage_color}${usage}%"
    update_line 6  $((LEFT_COL+2)) "Total Processes : ${total_procs}"
    update_line 7  $((LEFT_COL+2)) "Active Processes: ${active_procs}"
    update_line 8  $((LEFT_COL+2)) "Load Average    : ${load}"
    update_line 9  $((LEFT_COL+2)) "Temperature     : ${temp}°C"
}

# ───────── MEMORY ─────────
update_memory_panel() {
    read total used free shared buff avail < <(free -m | awk '/Mem:/ {print $2,$3,$4,$5,$6,$7}')
    local pct=$((100*used/total))
    local color=$GREEN
    (( pct >= 90 )) && color=$RED
    (( pct >= 75 && pct < 90 )) && color=$YELLOW

    update_line 22 $((LEFT_COL+2)) "Total Usage  : ${color}${pct}% (${used}/${total} MB)"
    update_line 23 $((LEFT_COL+2)) "Available    : ${avail} MB"
}

# ───────── DISK ─────────
update_disk_panel() {
    read size used avail pct <<< $(df -h / | awk 'NR==2{print $2,$3,$4,$5}')
    update_line 32 $((LEFT_COL+2)) "Total Usage  : ${pct} (${used}/${size})"
}

# ───────── NETWORK ─────────
update_network_panel() {
    read rx tx <<< $(awk -v d="$NET_DEV" '$1~d":"{print $2,$10}' /proc/net/dev)
    update_line 5 $((RIGHT_COL+2)) "RX : $(((rx-prev_rx)/1024)) KB/s"
    update_line 6 $((RIGHT_COL+2)) "TX : $(((tx-prev_tx)/1024)) KB/s"
    prev_rx=$rx; prev_tx=$tx
}

# ───────── SERVICES ─────────
update_services_panel() {
    local row=13
    for svc in "${SERVICES[@]}"; do
        systemctl is-active --quiet "$svc" && state="active" || state="inactive"
        color=$([[ $state == active ]] && echo "$GREEN" || echo "$GRAY")
        update_line $row $((RIGHT_COL+2)) "${svc^}: ${color}${state}"
        ((row++))
    done
}

# ───────── UI ─────────
clear
draw_static_box 2  $LEFT_COL  $PANEL_WIDTH 18 "CPU"
draw_static_box 20 $LEFT_COL  $PANEL_WIDTH 10 "MEMORY"
draw_static_box 30 $LEFT_COL  $PANEL_WIDTH 10 "DISK"
draw_static_box 2  $RIGHT_COL $PANEL_WIDTH 9  "NETWORK ($NET_DEV)"
draw_static_box 11 $RIGHT_COL $PANEL_WIDTH 19 "SERVICES"

while true; do
    update_cpu_panel
    update_memory_panel
    update_disk_panel
    update_network_panel
    update_services_panel
    sleep "$REFRESH"
done
