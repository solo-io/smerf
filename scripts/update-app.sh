#!/bin/bash

set -e

# The number of namespaces used to run the test app.
NUM_NS=${NUM_NS:-"1"}
# A time unit, e.g. 1s, 2m, 3h, to wait for a test app deployment rollout to complete.
ROLLOUT_TIMEOUT=${ROLLOUT_TIMEOUT:-"5m"}

# Supported values for the number of namespaces to run the app.
valid_num_ns=(1 25)
# Supported update types.
valid_updates=("l4" "l7" "waypoint")


# Source the utility functions
source ./scripts/utils.sh

# Check if NUM_NS is valid
if [[ ! " ${valid_num_ns[*]} " =~ " $NUM_NS " ]]; then
  echo "Invalid value for NUM_NS. Supported values are 1 and 25."
  exit 1
fi

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check if kubectl is installed
if ! command_exists kubectl; then
    echo "kubectl is not installed. Please install kubectl before running this script."
    exit 1
fi

# Function to handle tiered app rollout status and rollback
app_rollout_status_and_rollback() {
  local namespace=$1
  for deploy in tier-1-app-a tier-1-app-b tier-2-app-a tier-2-app-b tier-2-app-c tier-2-app-d tier-3-app-a tier-3-app-b; do
    kubectl rollout status deploy/$deploy -n $namespace --timeout=$ROLLOUT_TIMEOUT || {
      echo "Rollout status check failed for deployment $deploy in namespace $namespace: ${PIPESTATUS[0]}"
      kubectl delete -k manifests/app/$NUM_NS/base || {
        echo "Failed to delete Kubernetes resources: ${PIPESTATUS[0]}"
      }
      exit 1
    }
  done
}

# Function to handle tiered app rollout status and rollback for all namespaces
all_app_rollout_status_and_rollback() {
  # Wait for the tiered app rollout to complete
  for i in $(seq 1 $NUM_NS); do
    app_rollout_status_and_rollback "ns-$i"
  done
}

# Function to handle waypoint rollout status and rollback
waypoint_rollout_status_and_rollback() {
  local namespace=$1
  kubectl rollout status deploy/waypoint -n $namespace --timeout=$ROLLOUT_TIMEOUT || {
    echo "Rollout status check failed for waypoint in namespace $namespace: ${PIPESTATUS[0]}"
    kubectl delete -k manifests/app/$NUM_NS/ambient/waypoints || {
      echo "Failed to delete Kubernetes resources: ${PIPESTATUS[0]}"
    }
    exit 1
  }
}

# Function to handle waypoint rollout status and rollback for all namespaces
all_waypoint_rollout_status_and_rollback() {
  # Wait for the waypoint rollout to complete
  for i in $(seq 1 $NUM_NS); do
    waypoint_rollout_status_and_rollback "ns-$i"
  done
}

# Check if mesh argument is provided, default to "base" if not
MESH=${1:-"base"}

# Check if update argument is provided
UPDATE=${2:-""}

# Validate update
if [[ -n "$UPDATE" ]]; then
  IFS=',' read -ra UPDATES <<< "$UPDATE"
  for p in "${UPDATES[@]}"; do
    if [[ ! " ${valid_updates[*]} " =~ " $p " ]]; then
      echo "Invalid update: $p. Supported values are 'l4', 'l7', and 'waypoint'."
      exit 1
    fi
  done
fi

# Construct the correct manifest path based on mesh and policy
MANIFEST_PATH="manifests/app/$NUM_NS/$MESH"
if [[ "$MESH" == "ambient" ]]; then
  if [[ " ${UPDATE[*]} " =~ "l4" || " ${UPDATE[*]} " =~ "l7" ]]; then
    MANIFEST_PATH="$MANIFEST_PATH/l4-policy"
  elif [[ " ${UPDATE[*]} " =~ "waypoint" ]]; then
    MANIFEST_PATH="$MANIFEST_PATH/waypoints"
  fi
fi

# Apply the manifest
echo "Applying $MANIFEST_PATH manifests."
kubectl apply -k $MANIFEST_PATH || {
  echo "Failed to apply Kubernetes resources for $MESH mesh with update $UPDATE: ${PIPESTATUS[0]}"
  kubectl delete -k $MANIFEST_PATH || {
    echo "Failed to delete Kubernetes resources for $MESH mesh with update $UPDATE: ${PIPESTATUS[0]}"
  }
  exit 1
}

# Function to handle waypoint rollout status and rollback for all namespaces
if [ -z "$UPDATE" ]; then
  all_app_rollout_status_and_rollback
elif [[ "$MESH" == "ambient" && "$UPDATE" == "waypoint" ]]; then
  all_waypoint_rollout_status_and_rollback
fi

# Determine what to echo based on whether a policy was provided
if [ -z "$UPDATE" ]; then
  if [ "$NUM_NS" -eq 1 ]; then
    echo "Test app is running in $NUM_NS namespace."
  else
    echo "Test app is running in $NUM_NS namespaces."
  fi
else
  if [ "$NUM_NS" -eq 1 ]; then
    echo "$UPDATE is running in $NUM_NS namespace."
  else
    echo "$UPDATE is running in $NUM_NS namespaces."
  fi
fi
