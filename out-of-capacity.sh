#!/usr/bin/env bash
# in zsh run with `bash ./out-of-capacity.sh &!`

TERMINATE=0
DELAY=5  # Delay in seconds between retries
MAX_RETRIES=10  # Number of retries per availability domain before moving to the next
ARCHIVE_THRESHOLD=15000  # Archive log after this many retries
LOG_FILE="tf_apply.log"  # Log file name
RETRY_COUNT_FILE="retry_count"  # File to store retry count
ATTEMPT_COUNT=0  # Local counter for total terraform apply attempts

function abort {
  TERMINATE=1
}

trap abort 0 1 2 3 6 9 15

# Function to load retry count from the file
function load_retry_count {
  if [[ -f "$RETRY_COUNT_FILE" ]]; then
    ATTEMPT_COUNT=$(cat "$RETRY_COUNT_FILE")
  else
    ATTEMPT_COUNT=0
  fi
}

# Function to save retry count to the file
function save_retry_count {
  echo "$ATTEMPT_COUNT" > "$RETRY_COUNT_FILE"
}

# Function to archive and compress the log file after reaching retry threshold
function archive_log {
  TIMESTAMP=$(date +%Y%m%d%H%M)  # Unique timestamp for the archive
  ARCHIVE_NAME="tf_apply_${TIMESTAMP}.log.gz"

  echo "Archiving and compressing log file as $ARCHIVE_NAME" | tee -a "$LOG_FILE"
  gzip -c "$LOG_FILE" > "$ARCHIVE_NAME"  # Compress the log file
  > "$LOG_FILE"  # Truncate the original log file
  echo "Retry count reset after archiving." | tee -a "$LOG_FILE"

  ATTEMPT_COUNT=0  # Reset retry count after archiving
  save_retry_count
}

# Load the retry count at the start
load_retry_count

# Infinite loop until terraform apply succeeds
while true; do
  # Check if we reached the retry threshold and archive the log if needed
  if [[ $ATTEMPT_COUNT -ge $ARCHIVE_THRESHOLD ]]; then
    archive_log
  fi

  # Separator at the start of the big Availability Domain loop
  echo "########################################" | tee -a "$LOG_FILE"
  echo "Starting Availability Domain Loop..." | tee -a "$LOG_FILE"
  echo "########################################" | tee -a "$LOG_FILE"

  # Loop through availability domains 1 to 3
  for AD in {1..3}; do
    echo "Trying Terraform apply for availability_domain = ${AD}" | tee -a "$LOG_FILE"

    # Retry loop for the current availability domain
    for ((i=1; i<=MAX_RETRIES; i++)); do
      ((ATTEMPT_COUNT++))  # Increment the attempt counter
      save_retry_count  # Save the updated retry count to the file

      echo "Attempt $i of $MAX_RETRIES for availability_domain = ${AD} (Total attempts: $ATTEMPT_COUNT)" | tee -a "$LOG_FILE"

      # Separator line for better output readability
      echo "========================================" | tee -a "$LOG_FILE"

      terraform apply -var="availability_domain=${AD}" -no-color -auto-approve >> "$LOG_FILE" 2>&1

      # Check the return status of terraform apply
      if [[ $? -eq 0 ]]; then
        echo "========================================" | tee -a "$LOG_FILE"
        echo "Terraform apply succeeded for availability_domain = ${AD} on attempt $i (Total attempts: $ATTEMPT_COUNT)" | tee -a "$LOG_FILE"
        save_retry_count  # Ensure the final retry count is saved
        exit 0  # Exit the script on success
      fi

      if [[ $TERMINATE -eq 1 ]]; then
        echo "Script terminated. Exiting..." | tee -a "$LOG_FILE"
        save_retry_count
        exit 1
      fi

      echo "========================================" | tee -a "$LOG_FILE"
      echo "Terraform apply failed for availability_domain = ${AD}. Retrying after ${DELAY} seconds..." | tee -a "$LOG_FILE"
      sleep $DELAY
    done

    echo "Terraform apply failed after $MAX_RETRIES attempts for availability_domain = ${AD}. Moving to the next one..." | tee -a "$LOG_FILE"
  done

  echo "All availability domains exhausted. Restarting the loop..." | tee -a "$LOG_FILE"
done
