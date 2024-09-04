#!/usr/bin/env bash

set -e

# The number of namespaces used to run the test app or load generators.
NUM_NS=${NUM_NS:-"1"}
# Maximum wait time in seconds (60 minutes)
MAX_TOTAL_WAIT=${MAX_TOTAL_WAIT:-"3600"}
# Maximum wait time per pod in seconds (15 minutes)
MAX_POD_WAIT=${MAX_POD_WAIT:-"900"}
# Interval between pod checks in seconds (5 seconds)
POD_CHECK_INTERVAL=${POD_CHECK_INTERVAL:-"5"}
# Label for pod selection
LABEL=${LABEL:-"kind=vegeta"}

# Check if file_name argument is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <file_name>"
    exit 1
fi

file_name=$1

# Validate NUM_NS to ensure it's between 1 and 25
if [[ "$NUM_NS" -lt 1 || "$NUM_NS" -gt 25 ]]; then
  echo "Invalid value for NUM_NS. Supported values are between 1 and 25."
  exit 1
fi

# Function to check if logs contain "Requests"
function check_logs() {
  local namespace=$1
  local logs=$(kubectl logs -l $LABEL -n $namespace 2>/dev/null | head -n 100)
  if [[ "$logs" =~ "Requests" ]]; then
    return 0  # Success
  else
    return 1  # No "Requests" found
  fi
}

# Function to wait for logs with retries
function wait_for_logs() {
  echo "Waiting up to $MAX_TOTAL_WAIT seconds for $LABEL/$1 to generate a test report..."
  local namespace=$1
  local elapsed_time=0
  while ! check_logs $namespace; do
    echo "No 'Requests' found in logs for namespace '$namespace'. Waiting..."
    sleep $POD_CHECK_INTERVAL
    elapsed_time=$((elapsed_time + POD_CHECK_INTERVAL))
    if [[ $elapsed_time -ge $MAX_POD_WAIT ]]; then
      echo "Timed out waiting for logs in namespace '$namespace'."
      exit 1
    fi
  done
  echo "Found 'Requests' in logs for namespace '$namespace'."
}

# Main script loop
total_elapsed_time=0
for i in $(seq 1 $NUM_NS); do
  wait_for_logs "ns-$i"
  total_elapsed_time=$((total_elapsed_time + MAX_POD_WAIT))
  if [[ $total_elapsed_time -ge $MAX_TOTAL_WAIT ]]; then
    echo "Timed out waiting for logs in all namespaces."
    exit 1
  fi
done

# Get the absolute path of the current script
script_dir=$(dirname "$(realpath "$0")")

# Run the latency report script
"$script_dir/latency-report.sh" "$file_name" "$NUM_NS"
if [ $? -ne 0 ]; then
    echo "Failed to generate latency report"
    exit 1
fi

# Run the load generator configuration report script
"$script_dir/loadgen-config-report.sh" "$file_name"
if [ $? -ne 0 ]; then
    echo "Failed to generate load generator configuration report"
    exit 1
fi

# Run the node and pod resource utilization script
"$script_dir/node-pod-resource-utilization.sh" "$file_name"
if [ $? -ne 0 ]; then
    echo "Failed to generate node and pod resource utilization report"
    exit 1
fi

# Run the waypoint stats report script (if waypoints present)
"$script_dir/waypoint-envoy-stats-report.sh" "$file_name"
if [ $? -ne 0 ]; then
    echo "Failed to generate waypoint envoy stats report"
    exit 1
fi

echo "All reports generated successfully with file name prefix: $file_name"
