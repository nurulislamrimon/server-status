#!/usr/bin/env bash
# =============================================================================
# Server Status – Grafana-style Terminal Dashboard
# Author: Nurul Islam Rimon (nurulislamrimon)
# GitHub: https://github.com/nurulislamrimon/server-status
# Version: 1.0.1 (CPU FIX ONLY)
# License: MIT
# =============================================================================

# Default settings
REFRESH=1.5
NET_DEV=""
SERVICES=("nginx" "apache2" "mysql" "redis" "docker" "pm2" "cron" "ssh" "ufw" "fail2ban")

show_help() {
    echo "Usage: server-status [OPTIONS]"
    echo ""
    echo "Options:"
    echo " --help                Show this help message"
    echo " --interface <name>    Override network interface"
    echo " --refresh <seconds>   Refresh interval (default: 1.5)"
    echo " --services \"svc1,svc2,...\"  Custom services"
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

if [[ -z "$NET_DEV" ]]; then
    NET_DEV=$(ip -4 route show default | awk '{print $5}' | head -1)
    [[ -z "$NET_DEV" ]] && NET_DEV="eth0"
fi

trap 'echo -e "\e[?25h\e[0m\e[?1049l"; tput cnorm 2>/dev/null; clear; exit' INT TERM EXIT
echo -e "\e[?25l\e[?1049h"

RESET="\e[0m"
BOLD="\e[1m"
GRAY="\e[90m"
WHITE="\e[97m"
GREEN="\e[32m"
YELLOW="\e[33m"
RED="\e[31m"
CYAN="\e[36m"
BLUE="\e[34m"
DOT="●"

LEFT_COL=2
RIGHT_COL=44
PANEL_WIDTH=40

prev_rx=0
prev_tx=0

# CPU delta globals (FIX)
prev_idle=0
prev_total=0

draw_static_box() {
    local r=$1 c=$2 w=$3 h=$4 title="$5"
    local i
    echo -ne "\e[${r};${c}H${GRAY}┌$(printf '─%.0s' $(seq 1 $((w-2))))┐${RESET}"
    ((r++))
    echo -ne "\e[${r};${c}H${GRAY}│${RESET} ${BOLD}${WHITE}${title}${RESET}"
    local len=${#title}
    printf ' %.0s' $(seq 1 $((w - len - 3)))
    echo -ne "${GRAY}│${RESET}"
    ((r++))
    echo -ne "\e[${r};${c}H${GRAY}├$(printf '─%.0s' $(seq 1 $((w-2))))┤${RESET}"
    for ((i=1; i<=h-4; i++)); do
        ((r++))
        echo -ne "\e[${r};${c}H${GRAY}│${RESET}"
        printf ' %.0s' $(seq 1 $((w-2)))
        echo -ne "${GRAY}│${RESET}"
    done
    ((r++))
    echo -ne "\e[${r};${c}H${GRAY}└$(printf '─%.0s' $(seq 1 $((w-2))))┘${RESET}"
}

update_line() {
    local row=$1 col=$2 text="$3" color="${4:-$WHITE}"
    echo -ne "\e[${row};${col}H${color}${text}${RESET}\e[K"
}

# ──────────────────────────────────────────────────────────────────────────────
# PANEL POSITIONS - FIXED LAYOUT
# ──────────────────────────────────────────────────────────────────────────────
draw_cpu_panel_static()     { draw_static_box  2 $LEFT_COL  $PANEL_WIDTH 18 "CPU";      }
draw_memory_panel_static()  { draw_static_box 20 $LEFT_COL  $PANEL_WIDTH 10 "MEMORY";  }
draw_disk_panel_static()    { draw_static_box 30 $LEFT_COL  $PANEL_WIDTH 10 "DISK";    }
draw_network_panel_static() { draw_static_box  2 $RIGHT_COL $PANEL_WIDTH  9 "NETWORK (${NET_DEV})"; }
draw_services_panel_static(){ draw_static_box 11 $RIGHT_COL $PANEL_WIDTH 19 "SERVICES"; }

# ──────────────────────────────────────────────────────────────────────────────
# UPDATE FUNCTIONS
# ──────────────────────────────────────────────────────────────────────────────
update_cpu_panel() {
    local top=$(top -bn1 | head -17)

    # ---- FIXED CPU USAGE (ONLY CHANGE) ----
    read cpu user nice system idle iowait irq softirq steal _ < /proc/stat

    local idle_now=$((idle + iowait))
    local total_now=$((user + nice + system + idle + iowait + irq + softirq + steal))

    local diff_idle=$((idle_now - prev_idle))
    local diff_total=$((total_now - prev_total))

    local usage=0
    if (( diff_total > 0 )); then
        usage=$(awk "BEGIN {printf \"%.1f\", 100 * (1 - $diff_idle / $diff_total)}")
    fi

    prev_idle=$idle_now
    prev_total=$total_now
    # ---- END FIX ----

    local total_procs=$(ps -e --no-headers | wc -l)
    local active_procs=$(echo "$top" | awk 'NR>7 && $9>0 {count++} END {print count+0}')

    local load=$(uptime | awk -F'load average: ' '{print $2}' | cut -d, -f1-3 | xargs || echo "N/A")

    local temp=$(cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null | sort -nr | head -1)
    [[ -n "$temp" ]] && temp=$((temp/1000)) || temp="N/A"

    local usage_int=$(awk "BEGIN {print int($usage * 10)}")

    local usage_color="$WHITE"
    if (( usage_int >= 900 )); then usage_color="$RED"
    elif (( usage_int >= 700 )); then usage_color="$YELLOW"
    else usage_color="$GREEN"; fi

    local procs_color="$WHITE"
    if (( total_procs >= 600 )); then procs_color="$RED"
    elif (( total_procs >= 400 )); then procs_color="$YELLOW"
    else procs_color="$GREEN"; fi

    update_line 5 $((LEFT_COL+2)) "Total Usage     : ${usage_color}${usage}%${RESET} "
    update_line 6 $((LEFT_COL+2)) "Total Processes : ${procs_color}${total_procs}${RESET} "
    update_line 7 $((LEFT_COL+2)) "Active Processes: ${active_procs} "
    update_line 8 $((LEFT_COL+2)) "Load Average    : ${load} "
    update_line 9 $((LEFT_COL+2)) "Temperature     : ${temp}°C "

    local cores=$(echo "$top" | tail -n +3 | head -4 | awk '{printf "%s%% ", 100-$NF}' || echo "N/A")
    update_line 11 $((LEFT_COL+2)) "Per Core        : ${cores} "

    local top_consumers=$(echo "$top" | awk 'NR>7 && $9>0 {print $1 " " $9 "% " substr($12,1,20)}' | head -3 || echo "None")
    update_line 13 $((LEFT_COL+2)) "Top Consumers:"
    local row=14
    while IFS= read -r line; do
        [[ -n "$line" ]] && update_line $row $((LEFT_COL+2)) "  ${line}"
        ((row++))
    done <<< "$top_consumers"
}

update_memory_panel() {
    local m=($(free -m | awk '/Mem:/ {print $2,$3,$4,$6,$7} /Swap:/ {print $3,$2}'))
    local total_mem=${m[0]} used_mem=${m[1]} free_mem=${m[2]} cached=${m[3]} avail=${m[4]}
    local swap_used=${m[5]} swap_total=${m[6]}

    local mem_pct=0
    [[ $total_mem -gt 0 ]] && mem_pct=$(awk "BEGIN {print int(100 * $used_mem / $total_mem)}")

    local swap_pct=0
    [[ $swap_total -gt 0 ]] && swap_pct=$(awk "BEGIN {print int(100 * $swap_used / $swap_total)}")

    local mem_color="$WHITE"
    if (( mem_pct >= 90 )); then mem_color="$RED"
    elif (( mem_pct >= 75 )); then mem_color="$YELLOW"
    else mem_color="$GREEN"; fi

    update_line 22 $((LEFT_COL+2)) "Total Usage  : ${mem_color}${mem_pct}%${RESET} (${used_mem}/${total_mem} MB) "
    update_line 23 $((LEFT_COL+2)) "Available    : ${avail} MB "
    update_line 24 $((LEFT_COL+2)) "Cached       : ${cached} MB "
    update_line 25 $((LEFT_COL+2)) "Swap Used    : ${swap_pct}% (${swap_used}/${swap_total} MB) "
}

update_disk_panel() {
    local df_out=$(df -h / | tail -1)
    local root_used_pct=$(echo "$df_out" | awk '{print $5}' | tr -d '%')
    local root_total=$(echo "$df_out" | awk '{print $2}')
    local root_used=$(echo "$df_out" | awk '{print $3}')

    local iowait=$(top -bn1 | grep -oP '%Cpu.*wa,\s*\K[0-9.]+' || echo "N/A")
    local rd wr="N/A"
    if command -v iostat >/dev/null 2>&1; then
        read rd wr <<< $(iostat -d -k 1 2 | tail -1 | awk '{print $3,$4}')
    fi

    local disk_color="$WHITE"
    if (( root_used_pct >= 90 )); then disk_color="$RED"
    elif (( root_used_pct >= 80 )); then disk_color="$YELLOW"
    else disk_color="$GREEN"; fi

    update_line 32 $((LEFT_COL+2)) "Total Usage  : ${disk_color}${root_used_pct}%${RESET} (${root_used}/${root_total}) "
    update_line 33 $((LEFT_COL+2)) "IO Wait      : ${iowait}% "
    update_line 34 $((LEFT_COL+2)) "Read Speed   : ${rd} KB/s "
    update_line 35 $((LEFT_COL+2)) "Write Speed  : ${wr} KB/s "
}

update_network_panel() {
    local stats=($(grep -w "${NET_DEV}:" /proc/net/dev | awk '{print $2,$10}'))
    local rx=${stats[0]} tx=${stats[1]}
    local rx_speed=$(((rx - prev_rx) / 1024))
    local tx_speed=$(((tx - prev_tx) / 1024))
    prev_rx=$rx
    prev_tx=$tx

    local conns="N/A"
    command -v ss >/dev/null && conns=$(ss -s | grep -oP 'TCP:\s*\K\d+(?=\s*\()')

    update_line 5 $((RIGHT_COL+2)) "RX : ${rx_speed} KB/s "
    update_line 6 $((RIGHT_COL+2)) "TX : ${tx_speed} KB/s "
    update_line 7 $((RIGHT_COL+2)) "Connections : ${conns} "
}

update_services_panel() {
    local row=13
    for svc in "${SERVICES[@]}"; do
        local state="unknown"
        if systemctl is-active --quiet "$svc"; then state="active"
        elif systemctl is-failed --quiet "$svc"; then state="failed"; fi

        local color=$GRAY dot="○"
        case $state in
            active) color=$GREEN; dot="$DOT" ;;
            failed) color=$RED; dot="$DOT" ;;
        esac

        update_line $row $((RIGHT_COL+2)) "${svc^}: "
        update_line $row $((RIGHT_COL+14)) "${color}${dot} ${state^}${RESET} "
        ((row++))
    done
}

# ──────────────────────────────────────────────────────────────────────────────
# MAIN
# ──────────────────────────────────────────────────────────────────────────────
clear
draw_cpu_panel_static
draw_memory_panel_static
draw_disk_panel_static
draw_network_panel_static
draw_services_panel_static

while true; do
    update_cpu_panel
    update_memory_panel
    update_disk_panel
    update_network_panel
    update_services_panel
    sleep "$REFRESH"
done
