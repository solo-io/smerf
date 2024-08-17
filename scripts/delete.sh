#!/bin/bash

set -e

# The number of namespaces to remove the test app or load generators from. 
NUM_NS=${NUM_NS:-"1"}

# Supported values for the number of namespaces.
valid_num_ns=(1 25)
# Supported types for the script.
valid_types=("app" "loadgen")
# Supported policies for app deletion
valid_policies=("l4" "l7" "waypoint")

# Check if type argument is provided
if [ -z "$1" ]; then
  echo "Usage: $0 <type> [<mesh> <policy>]"
  echo "Supported types are: app, loadgen"
  exit 1
fi

# Set the type
TYPE=$1

# Validate type
if [[ ! " ${valid_types[*]} " =~ " $TYPE " ]]; then
  echo "Invalid type: $TYPE. Supported values are 'app' and 'loadgen'."
  exit 1
fi

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

if [[ "$TYPE" == "app" ]]; then
  # Check if mesh argument is provided, default to "base" if not
  MESH=${2:-"base"}

  # Check if policy argument is provided
  UPDATE=${3:-""}

  # Validate policy
  if [[ -n "$UPDATE" ]]; then
    IFS=',' read -ra UPDATES <<< "$UPDATE"
    for p in "${UPDATES[@]}"; do
      if [[ ! " ${valid_policies[*]} " =~ " $p " ]]; then
        echo "Invalid policy: $p. Supported values are 'l4', 'l7', and 'waypoint'."
        exit 1
      fi
    done
  fi

  # Construct the correct manifest path based on mesh and policy
  MANIFEST_PATH="manifests/app/$NUM_NS/$MESH"
  if [[ "$MESH" == "ambient" ]]; then
    if [[ " ${UPDATES[*]} " =~ "l4" || " ${UPDATES[*]} " =~ "l7" ]]; then
      MANIFEST_PATH="$MANIFEST_PATH/l4-policy"
    elif [[ " ${UPDATES[*]} " =~ "waypoint" ]]; then
      MANIFEST_PATH="$MANIFEST_PATH/waypoints"
    fi
  fi

  # Delete the manifest
  kubectl delete -k $MANIFEST_PATH || {
    echo "Failed to delete Kubernetes resources for $MESH mesh with policy $UPDATE: ${PIPESTATUS[0]}"
    exit 1
  }

  # Determine what to echo based on whether a policy was provided
  if [ -z "$UPDATE" ]; then
    if [ "$NUM_NS" -eq 1 ]; then
      echo "Test app removed from $NUM_NS namespace."
    else
      echo "Test app removed from $NUM_NS namespaces."
    fi
  else
    if [ "$NUM_NS" -eq 1 ]; then
      echo "$UPDATE removed from $NUM_NS namespace."
    else
      echo "$UPDATE removed from $NUM_NS namespaces."
    fi
  fi

elif [[ "$TYPE" == "loadgen" ]]; then
  # Delete the load generators
  kubectl delete -k manifests/loadgen/$NUM_NS/base || {
    echo "Failed to delete Kubernetes resources: ${PIPESTATUS[0]}"
    exit 1
  }

  if [ "$NUM_NS" -eq 1 ]; then
    echo "Load generators removed from $NUM_NS namespace."
  else
    echo "Load generators removed from $NUM_NS namespaces."
  fi
fi
