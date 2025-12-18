#!/bin/bash

# ==============================================================================
# Script Name: ghost_mode.sh
# Description: Privacy "Ghost Mode" for YouTube on Android (Termux + Shizuku)
# Author: Antigravity
# Version: 1.0.0
# ==============================================================================

# ------------------------------------------------------------------------------
# Colors & Formatting
# ------------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_err() { echo -e "${RED}[ERROR]${NC} $1"; }

# ------------------------------------------------------------------------------
# 1. Environment & Dependency Checks
# ------------------------------------------------------------------------------
check_dependencies() {
    log_info "Checking dependencies..."

    # Check for rish (Shizuku)
    if ! command -v rish &> /dev/null; then
        log_err "'rish' (Shizuku shell) not found."
        echo "Please open the Shizuku app -> 'Use Shizuku in terminal apps' -> 'Export files' and follow instructions."
        exit 1
    fi

    # Check for jq
    if ! command -v jq &> /dev/null; then
        log_warn "'jq' not found. Installing..."
        pkg install jq -y || { log_err "Failed to install jq."; exit 1; }
    fi

    # Check for curl
    if ! command -v curl &> /dev/null; then
        log_warn "'curl' not found. Installing..."
        pkg install curl -y || { log_err "Failed to install curl."; exit 1; }
    fi

    # Check if Shizuku server is running
    # We look for the Shizuku process in the process list
    if ! ps -ef | grep -q "moh.shizuku"; then
        log_err "Shizuku server is NOT running."
        echo -e "${YELLOW}Please start Shizuku via Wireless Debugging (or Root) in the Shizuku app.${NC}"
        exit 1
    fi

    log_success "All dependencies met and Shizuku is running."
}

# ------------------------------------------------------------------------------
# 2. Network Identity Analysis & Kill Switch
# ------------------------------------------------------------------------------
check_network_identity() {
    log_info "Analyzing network identity..."

    # Fetch IP info
    RESPONSE=$(curl -s http://ip-api.com/json)
    
    if [ -z "$RESPONSE" ]; then
        log_err "Failed to fetch network info. Check internet connection."
        exit 1
    fi

    IP=$(echo "$RESPONSE" | jq -r '.query')
    COUNTRY=$(echo "$RESPONSE" | jq -r '.country')
    TIMEZONE=$(echo "$RESPONSE" | jq -r '.timezone')

    echo -e "----------------------------------------"
    echo -e "${BOLD}Current Identity:${NC}"
    echo -e "  IP:       ${CYAN}$IP${NC}"
    echo -e "  Country:  ${CYAN}$COUNTRY${NC}"
    echo -e "  Timezone: ${CYAN}$TIMEZONE${NC}"
    echo -e "----------------------------------------"

    # Kill Switch
    if [[ "$COUNTRY" == "Iran" ]]; then
        echo -e "${RED}${BOLD}!!! SECURITY ALERT !!!${NC}"
        echo -e "${RED}YOU ARE CONNECTED FROM IRAN (OR VPN OFF).${NC}"
        echo -e "${RED}GHOST MODE ABORTED TO PROTECT YOUR SAFETY.${NC}"
        read -p "Do you want to proceed regardless? (y/N): " FORCE
        if [[ "$FORCE" != "y" && "$FORCE" != "Y" ]]; then
            log_info "Exiting..."
            exit 1
        fi
        log_warn "Proceeding with CAUTION..."
    else
        log_success "Location safe ($COUNTRY)."
        export DETECTED_TIMEZONE="$TIMEZONE"
    fi
}

# ------------------------------------------------------------------------------
# 3. System Hardening (Ghost Logic)
# ------------------------------------------------------------------------------

# Store initial states or defaults for cleanup
trap cleanup EXIT INT TERM

cleanup() {
    echo ""
    log_info "Restoring system state..."
    
    # Re-enable Sensors (Code 0 usually resets/unmutes)
    # The '1' enables privacy (disables sensors), '0' disables privacy (enables sensors)
    # Actually, for 'setSensorPrivacy', 'true' (1) means privacy ON (sensors OFF).
    # 'false' (0) means privacy OFF (sensors ON).
    
    # We need to redetect or reuse the trans code from the main logic, but for simplicity:
    # We'll just run the restore commands.
    
    # NOTE: We are running detection again inside or just reusing variables if we could.
    # To be safe, let's re-eval strict SDK logic or assume variable is set.
    if [ -n "$SENSOR_TRANS_CODE" ]; then
        log_info "Re-enabling sensors..."
        rish -c "service call sensor_privacy $SENSOR_TRANS_CODE i32 0" > /dev/null
    fi

    # Restore Location for YouTube
    log_info "Restoring location permissions..."
    rish -c "cmd appops set com.google.android.youtube COARSE_LOCATION allow"
    rish -c "cmd appops set com.google.android.youtube FINE_LOCATION allow"

    # Reset Timezone (Optional, default to Tehran as requested)
    log_info "Resetting specific timezone (Asia/Tehran)..."
    rish -c "service call alarm 3 s16 'Asia/Tehran'" > /dev/null

    log_success "System restored. Stay safe."
    exit
}

activate_ghost_mode() {
    log_info "Activating Ghost Mode..."

    # --- Sensor Privacy ---
    SDK_VER=$(getprop ro.build.version.sdk)
    log_info "Android SDK Version: $SDK_VER"

    # Determine Transaction Code for IToggleSensorPrivacy (or equivalent interface)
    # Codes based on AOSP source inspection for different versions
    if [ "$SDK_VER" -eq 29 ] || [ "$SDK_VER" -eq 30 ]; then
        # Android 10, 11
        SENSOR_TRANS_CODE=4
    elif [ "$SDK_VER" -eq 31 ] || [ "$SDK_VER" -eq 32 ]; then
        # Android 12, 12L
        SENSOR_TRANS_CODE=8
    elif [ "$SDK_VER" -ge 33 ]; then
        # Android 13, 14+
        SENSOR_TRANS_CODE=9
    else
        log_warn "Unknown SDK version for Sensor Privacy. Trying code 8 (common fallback)."
        SENSOR_TRANS_CODE=8
    fi

    export SENSOR_TRANS_CODE # Export for cleanup trap

    log_info "Disabling Sensors (Mic/Cam/etc) [TransCode: $SENSOR_TRANS_CODE]..."
    # i32 1 = enable privacy mode (sensors OFF)
    rish -c "service call sensor_privacy $SENSOR_TRANS_CODE i32 1" > /dev/null

    # --- Location Blocking (AppOps) ---
    log_info "Blocking Location for YouTube..."
    rish -c "cmd appops set com.google.android.youtube COARSE_LOCATION ignore"
    rish -c "cmd appops set com.google.android.youtube FINE_LOCATION ignore"

    # --- Timezone Sync ---
    if [ -n "$DETECTED_TIMEZONE" ]; then
        log_info "Syncing System Timezone to: $DETECTED_TIMEZONE"
        # 'alarm' service, transaction 3 is setTimezone usually
        rish -c "service call alarm 3 s16 '$DETECTED_TIMEZONE'" > /dev/null
    else
        log_warn "No detected timezone to sync."
    fi

    log_success "Ghost Mode ACTIVE."
}

# ------------------------------------------------------------------------------
# 4. YouTube Launch Menu
# ------------------------------------------------------------------------------
launch_youtube() {
    echo ""
    echo "----------------------------------------"
    echo "       GHOST MODE: YOUTUBE LAUNCHER     "
    echo "----------------------------------------"
    echo "1) Open YouTube Home"
    echo "2) Open Specific Video ID"
    echo "3) Exit (Restore & Quit)"
    echo "----------------------------------------"
    read -p "Select option: " CHOICE

    case $CHOICE in
        1)
            log_info "Launching YouTube Home..."
            rish -c "am start -a android.intent.action.VIEW -d 'vnd.youtube:'" > /dev/null
            ;;
        2)
            read -p "Enter Video ID (e.g., dQw4w9WgXcQ): " VID_ID
            if [ -n "$VID_ID" ]; then
                log_info "Launching Video..."
                # Use standard https link with intent flag, or straight vnd.youtube scheme
                # vnd.youtube:<id> usually works for intents
                rish -c "am start -a android.intent.action.VIEW -d 'vnd.youtube:$VID_ID'" > /dev/null
            else
                log_err "Invalid ID."
            fi
            ;;
        3)
            # Cleanup happens automatically via trap
            exit 0
            ;;
        *)
            echo "Invalid option."
            ;;
    esac

    echo ""
    echo -e "${YELLOW}Press [ENTER] to restore settings and exit script...${NC}"
    read
}

# ------------------------------------------------------------------------------
# Main Execution Flow
# ------------------------------------------------------------------------------
main() {
    clear
    echo -e "${CYAN}${BOLD}:: Android Privacy Shield (Ghost Mode) ::${NC}"
    
    check_dependencies
    check_network_identity
    activate_ghost_mode
    launch_youtube
}

main
