#!/bin/bash

set -e

# The number of namespaces used to run the test app.
NUM_NS=${NUM_NS:-"1"}
# A time unit, e.g. 1s, 2m, 3h, to wait for a test app deployment rollout to complete.
ROLLOUT_TIMEOUT=${ROLLOUT_TIMEOUT:-"5m"}

# Supported workload types for the script.
valid_types=("app")
# Supported update types.
valid_updates=("l4" "l7" "waypoint")
# Supported parameters for loadgen workloads.
valid_loadgen_updates=("rps" "duration" "url")

# Source the utility functions
source ./scripts/utils.sh

# Check if workload type argument is provided
if [ -z "$1" ]; then
  echo "Usage: $0 <type>"
  echo "Supported workload types are: app"
  exit 1
fi

# Set the type
TYPE=$1

# Validate workload types
if [[ ! " ${valid_types[*]} " =~ " $TYPE " ]]; then
  echo "Invalid workload type: $TYPE. Supported workload values are 'app' and 'loadgen'."
  exit 1
fi

# Validate NUM_NS to ensure it's between 1 and 25
if [[ "$NUM_NS" -lt 1 || "$NUM_NS" -gt 25 ]]; then
  echo "Invalid value for NUM_NS. Supported values are between 1 and 25."
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
      kubectl delete deploy/$deploy -n $namespace || {
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
    kubectl delete -f deploy/waypoint -n $namespace || {
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

# Check if mesh argument is provided
MESH=${2:-""}

# Validate update parameters based on workload type
if [[ "$TYPE" == "app" ]]; then
  UPDATE=${3:-""}
  if [[ -n "$UPDATE" ]]; then
    IFS=',' read -ra UPDATES <<< "$UPDATE"
    for p in "${UPDATES[@]}"; do
      if [[ ! " ${valid_updates[*]} " =~ " $p " ]]; then
        echo "Invalid update: $p. Supported values are 'l4', 'l7', and 'waypoint'."
        exit 1
      fi
    done
  fi
elif [[ "$TYPE" == "loadgen" ]]; then
  RPS=${3:-""}
  DURATION=${4:-""}
  URL=${5:-""}
  if [[ -n "$RPS" ]]; then
    if [[ ! " ${valid_loadgen_updates[*]} " =~ "rps" ]]; then
      echo "Invalid loadgen update: rps"
      exit 1
    fi
  fi
  if [[ -n "$DURATION" ]]; then
    if [[ ! " ${valid_loadgen_updates[*]} " =~ "duration" ]]; then
      echo "Invalid loadgen update: duration"
      exit 1
    fi
  fi
  if [[ -n "$URL" ]]; then
    if [[ ! " ${valid_loadgen_updates[*]} " =~ "url" ]]; then
      echo "Invalid loadgen update: url"
      exit 1
    fi
  fi
fi

# Apply the appropriate manifests based on the workload type
if [[ "$TYPE" == "app" ]]; then
  # Apply the ambient labels to the specified namespaces.
  if [[ "$MESH" == "ambient" && -z "$UPDATE" ]]; then
    for i in $(seq 1 $NUM_NS); do
      NAMESPACE="ns-$i"
      echo "Applying ambient labels to $NAMESPACE..."
      kubectl label namespace $NAMESPACE istio.io/dataplane-mode=ambient istio.io/use-waypoint=waypoint --overwrite || {
        echo "Failed to apply labels to namespace $NAMESPACE"
        exit 1
      }
    done
    exit 0
  fi

  # Construct the correct manifest path based on mesh and policy
  MANIFEST_PATH="manifests/app/$MESH"
  if [[ "$MESH" == "ambient" ]]; then
    if [[ " ${UPDATE[*]} " =~ "l4" ]]; then
      MANIFEST_PATH="$MANIFEST_PATH/l4-policy"
    elif [[ " ${UPDATE[*]} " =~ "l7" ]]; then
      MANIFEST_PATH="$MANIFEST_PATH/l7-policy"
    elif [[ " ${UPDATE[*]} " =~ "waypoint" ]]; then
      MANIFEST_PATH="$MANIFEST_PATH/waypoints"
    fi
  fi

  # Apply the manifest
  echo "Applying $MANIFEST_PATH manifests."
  for i in $(seq 1 $NUM_NS); do
    for manifest in "$MANIFEST_PATH"/*; do
      if [[ -f "$manifest" ]]; then
        sed "s/\$i/$i/g" "$manifest" | kubectl apply -f - || {
          echo "Failed to apply Kubernetes resources for $MESH mesh with update $UPDATE in namespace ns-$i: ${PIPESTATUS[0]}"
          # Attempt to delete the resources applied so far
          kubectl delete -f "$manifest" || {
            echo "Failed to delete Kubernetes resources for $MESH mesh with update $UPDATE in namespace ns-$i: ${PIPESTATUS[0]}"
          }
          exit 1
        }
      fi
    done
  done

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

elif [[ "$TYPE" == "loadgen" ]]; then
  MANIFEST_PATH="manifests/loadgen/base"
  echo "Applying $MANIFEST_PATH manifest with updates: rps=$RPS, duration=$DURATION, URL=$URL."
  for i in $(seq 1 $NUM_NS); do
    for manifest in "$MANIFEST_PATH"/*; do
      if [[ -f "$manifest" ]]; then
        sed -e "s/\$i/$i/g" \
            -e "s/REQUESTS_PER_SECOND:.*/REQUESTS_PER_SECOND: \"$RPS\"/" \
            -e "s/DURATION:.*/DURATION: \"$DURATION\"/" \
            -e "s#APP_URL:.*#APP_URL: \"$URL\"#" \
            "$manifest" | kubectl apply -f - || {
          echo "Failed to apply load generator resources with updates in namespace ns-$i: ${PIPESTATUS[0]}"
          # Attempt to delete the resources applied so far
          kubectl delete -f "$manifest" || {
            echo "Failed to delete load generator resources with updates in namespace ns-$i: ${PIPESTATUS[0]}"
          }
          exit 1
        }
      fi
    done
  done

  if [ "$NUM_NS" -eq 1 ]; then
    echo "Load generators are running in $NUM_NS namespace."
  else
    echo "Load generators are running in $NUM_NS namespaces."
  fi
fi
