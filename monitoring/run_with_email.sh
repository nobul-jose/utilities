#!/bin/bash

# Configuration - customize these values
COMMAND="echo 'This is a test command output' && echo 'Second line of output' && sleep 2"
EMAIL_TO="test@example.com"
EMAIL_FROM="$(whoami)@$(hostname)"
OUTPUT_DIR="${HOME}/command_outputs"

# Create output directory if it doesn't exist
mkdir -p "${OUTPUT_DIR}"

# Generate timestamped filenames (using same timestamp for both files)
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
STDOUT_FILE="${OUTPUT_DIR}/${TIMESTAMP}_stdout.log"
STDERR_FILE="${OUTPUT_DIR}/${TIMESTAMP}_stderr.log"

# Function to send email
send_email() {
    local subject="$1"
    local body="$2"
    shift 2
    local attachments=("$@")
    
    if command -v mail &> /dev/null; then
        # Use mailx syntax (mail is typically mailx on Linux)
        # mailx -s subject -r from-addr -a attachment to-addr
        local mail_args=(-s "${subject}" -r "${EMAIL_FROM}")
        for attachment in "${attachments[@]}"; do
            if [ -f "${attachment}" ]; then
                mail_args+=(-a "${attachment}")
            fi
        done
        mail_args+=("${EMAIL_TO}")
        echo "${body}" | mail "${mail_args[@]}"
        echo "Email sent to ${EMAIL_TO}"
    elif command -v sendmail &> /dev/null; then
        # Use sendmail (without attachments - sendmail attachment support is complex)
        {
            echo "From: ${EMAIL_FROM}"
            echo "To: ${EMAIL_TO}"
            echo "Subject: ${subject}"
            echo ""
            echo "${body}"
            if [ ${#attachments[@]} -gt 0 ]; then
                echo ""
                echo "Note: Attachments not supported with sendmail. Files:"
                for attachment in "${attachments[@]}"; do
                    echo "  - ${attachment}"
                done
            fi
        } | sendmail "${EMAIL_TO}"
        echo "Email sent to ${EMAIL_TO} (attachments listed in body)"
    else
        echo "Warning: Neither 'mail' nor 'sendmail' command found. Email not sent."
        echo "Subject: ${subject}"
        echo "Body:"
        echo "${body}"
    fi
}

# Send start notification email
START_TIME_STR=$(date '+%Y-%m-%d %H:%M:%S')
START_TIME=$(date +%s)
TIMESTAMP_STR=$(date '+%Y-%m-%d %H:%M:%S')

# Create subject with command, truncating if necessary to stay under 78 chars (email best practice)
# Format: "Command Starting: <command> - <timestamp>"
# Reserve ~40 chars for prefix/suffix, so command can use ~38 chars
MAX_CMD_LEN=38
if [ ${#COMMAND} -gt ${MAX_CMD_LEN} ]; then
    CMD_DISPLAY="${COMMAND:0:$((MAX_CMD_LEN-3))}..."
else
    CMD_DISPLAY="${COMMAND}"
fi
START_SUBJECT="Command Starting: ${CMD_DISPLAY} - ${TIMESTAMP_STR}"
START_BODY=$(cat <<EOF
Command Execution Started
=========================

Command: ${COMMAND}
Start Time: ${START_TIME_STR}
Output Directory: ${OUTPUT_DIR}
Timestamp: ${TIMESTAMP}

The command is now running. You will receive a completion email when it finishes.

EOF
)

send_email "${START_SUBJECT}" "${START_BODY}"

# Run the command and capture output
echo "Starting command: ${COMMAND}"
echo "Start time: ${START_TIME_STR}"

# Execute command, capturing both stdout and stderr
# Use eval to properly execute command strings that may contain multiple commands
if eval "${COMMAND}" > "${STDOUT_FILE}" 2> "${STDERR_FILE}"; then
    EXIT_CODE=0
    STATUS="SUCCESS"
else
    EXIT_CODE=$?
    STATUS="FAILED"
fi

END_TIME=$(date +%s)
END_TIME_STR=$(date '+%Y-%m-%d %H:%M:%S')
DURATION=$((END_TIME - START_TIME))

echo "Command completed with exit code: ${EXIT_CODE}"
echo "End time: ${END_TIME_STR}"
echo "Duration: ${DURATION} seconds"

# Compress output files
STDOUT_GZ="${STDOUT_FILE}.gz"
STDERR_GZ="${STDERR_FILE}.gz"

if [ -f "${STDOUT_FILE}" ]; then
    gzip -c "${STDOUT_FILE}" > "${STDOUT_GZ}"
    echo "Compressed stdout to ${STDOUT_GZ}"
fi

if [ -f "${STDERR_FILE}" ]; then
    gzip -c "${STDERR_FILE}" > "${STDERR_GZ}"
    echo "Compressed stderr to ${STDERR_GZ}"
fi

# Prepare completion email body
# Create completion subject with command (matching start email format)
# Reuse CMD_DISPLAY from start email, but may need to truncate further due to status/exit code
# Format: "Command Complete: <command> - <status> (<exit_code>) - <timestamp>"
COMPLETION_TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
# Calculate available space: 78 total - "Command Complete: " (19) - " - " (3) - " (" (2) - ") - " (4) - timestamp (19) = 31
# Status can be "SUCCESS" (7) or "FAILED" (6), exit code typically 1-3 digits (3)
# So we need: 31 - 7 - 3 = 21 chars for command in worst case
# But we'll use a shorter format to give more room to command
# "Complete: " (10) + " - " (3) + " (" (2) + ") - " (4) + timestamp (19) = 38 fixed
# Status (7) + exit (3) = 10, so 78 - 38 - 10 = 30 chars for command
COMPLETION_MAX_CMD_LEN=30
if [ ${#COMMAND} -gt ${COMPLETION_MAX_CMD_LEN} ]; then
    COMPLETION_CMD_DISPLAY="${COMMAND:0:$((COMPLETION_MAX_CMD_LEN-3))}..."
else
    COMPLETION_CMD_DISPLAY="${COMMAND}"
fi
COMPLETION_SUBJECT="Complete: ${COMPLETION_CMD_DISPLAY} - ${STATUS} (${EXIT_CODE}) - ${COMPLETION_TIMESTAMP}"
COMPLETION_BODY=$(cat <<EOF
Command Execution Report
========================

Command: ${COMMAND}
Status: ${STATUS}
Exit Code: ${EXIT_CODE}
Start Time: ${START_TIME_STR}
End Time: ${END_TIME_STR}
Duration: ${DURATION} seconds

Compressed Output Files (attached):
- stdout: ${STDOUT_GZ}
- stderr: ${STDERR_GZ}

Original Files:
- stdout: ${STDOUT_FILE}
- stderr: ${STDERR_FILE}

EOF
)

# Prepare attachments array
ATTACHMENTS=()
if [ -f "${STDOUT_GZ}" ]; then
    ATTACHMENTS+=("${STDOUT_GZ}")
fi
if [ -f "${STDERR_GZ}" ]; then
    ATTACHMENTS+=("${STDERR_GZ}")
fi

# Send completion email with attachments
send_email "${COMPLETION_SUBJECT}" "${COMPLETION_BODY}" "${ATTACHMENTS[@]}"

exit ${EXIT_CODE}

