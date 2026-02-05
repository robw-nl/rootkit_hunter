#!/bin/bash
#
# rkhunter wrapper script
# - Checks daily (prevents double runs)
# - Filters false positives and 'grep' noise
# - Logs ONLY 'Clean' status or full report if infected
#
# Verion 1.02 January 4, 2026
#

set -u

# --- Configuration ---
CONFIG_FILE="/home/rob/Files/Scripts/rkhunter.conf"
TEMP_LOG="/tmp/rkhunter_raw_output.txt"

if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    notify-send "Error: rkhunter config missing"
    exit 1
fi

# --- Functions ---

check_run_file() {
    # Check if run file exists and was modified today (YYYYMMDD format)
    if [[ -f "${RUN_FILE}" ]]; then
        TODAY=$(date +%Y%m%d)
        LAST_RUN=$(date -r "${RUN_FILE}" +%Y%m%d)

        if [[ "$TODAY" == "$LAST_RUN" ]]; then
            # Already ran today, exit silently
            exit 0
        fi
    fi

    # Update timestamp for this run
    touch "${RUN_FILE}"
}

check_commands() {
    if ! command -v rkhunter &> /dev/null; then
        notify-send "Error: rkhunter is not installed"
        exit 1
    fi
}

run_scan() {
    notify-send "🛡️ Starting Rootkit Scan..."

    # 1. Run Scan to temporary file & Filter noise
    # We pipe stderr (2>&1) to stdout to catch the grep warnings
    # sed removes the specific Manjaro/grep noise
    sudo rkhunter --check --sk --nocolors 2>&1 \
        | sed -E '/(egrep is obsolescent|grep: warning: stray)/d' \
        > "$TEMP_LOG"

    # 2. Analyze the output for ACTUAL rootkits
    # We look for the summary line "Possible rootkits: 0"
    if grep -q "Possible rootkits: 0" "$TEMP_LOG"; then

        # --- SCENARIO: CLEAN ---
        # Overwrite log with just a timestamp and status
        echo "$(date '+%Y-%m-%d %H:%M:%S') - System Clean. No rootkits found." > "$LOGFILE"
        notify-send "✅ RKHunter: System Clean"

    else
        # --- SCENARIO: INFECTED (or critical error) ---
        # Copy the FULL report to the logfile so you can investigate
        cat "$TEMP_LOG" > "$LOGFILE"

        # Check if it was just a warning (file change) or a rootkit
        # rkhunter returns exit code 1 for warnings too, so we double check the text
        if grep -q "Possible rootkits: [1-9]" "$TEMP_LOG"; then
            notify-send -u critical "⚠️ RKHunter: ROOTKIT FOUND!" "Check log: $LOGFILE"
            $EDITOR_CMD "$LOGFILE"
        else
            # Warnings found (files changed), but no rootkits.
            # We log it, but notification is mild.
            notify-send "ℹ️ RKHunter: Warnings (files changed)"
        fi
    fi

    # Cleanup temp file
    rm -f "$TEMP_LOG"
}

# --- Execution Flow ---

# 1. Check if we already ran today (First thing we do!)
check_run_file

# 2. Wait for desktop to settle
sleep 10

# 3. Check requirements
check_commands

# 4. Silent update (ignoring errors)
sudo rkhunter --update --nocolors > /dev/null 2>&1

# 5. Run the filtered scan
run_scan
