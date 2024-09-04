#!/usr/bin/env bash

set -e

# The number of namespaces to remove the test app or load generators from. 
NUM_NS=${NUM_NS:-"1"}

# Supported workload types for the script.
valid_types=("app" "loadgen")
# Supported policies for app deletion
valid_policies=("l4" "l7" "waypoint")

# Check if type argument is provided
if [ -z "$1" ]; then
  echo "Usage: $0 <workload_type> [<mesh_type> <update_type>]"
  echo "Supported workload types are: app, loadgen"
  exit 1
fi

# Set the workload type
TYPE=$1

# Validate type
if [[ ! " ${valid_types[*]} " =~ " $TYPE " ]]; then
  echo "Invalid workload type: $TYPE. Supported values are 'app' and 'loadgen'."
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

  # Remove the ambient labels from the specified namespaces.
  if [[ "$MESH" == "ambient" && -z "$UPDATE" ]]; then
    for i in $(seq 1 $NUM_NS); do
      NAMESPACE="ns-$i"
      echo "Removing ambient labels from $NAMESPACE..."
      kubectl label namespace $NAMESPACE istio.io/dataplane-mode- istio.io/use-waypoint- --overwrite || {
        echo "Failed to remove labels from namespace $NAMESPACE"
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

  # Delete the manifest
  for i in $(seq 1 $NUM_NS); do
    for manifest in "$MANIFEST_PATH"/*; do
      if [[ -f "$manifest" ]]; then
        sed "s/\$i/$i/g" "$manifest" | kubectl delete -f - || {
          echo "Failed to delete Kubernetes resources for manifest $manifest: ${PIPESTATUS[0]}"
          exit 1
        }
      fi
    done
  done


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
  for i in $(seq 1 $NUM_NS); do
    sed "s/\$i/$i/g" manifests/loadgen/base/loadgen.yaml | kubectl delete -f - 2>&1 | grep -v "not found" || {
      echo "Failed to delete load generator resources for namespace ns-$i: ${PIPESTATUS[0]}"
      # Continue to the next iteration even if there are "not found" errors
    }
  done

  if [ "$NUM_NS" -eq 1 ]; then
    echo "Load generators removed from $NUM_NS namespace."
  else
    echo "Load generators removed from $NUM_NS namespaces."
  fi
fi
