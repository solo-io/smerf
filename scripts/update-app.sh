#!/bin/bash

set -e

# The number of namespaces used to run the test app.
NUM_NS=${NUM_NS:-"1"}
# A time unit, e.g. 1s, 2m, 3h, to wait for a test app deployment rollout to complete.
ROLLOUT_TIMEOUT=${ROLLOUT_TIMEOUT:-"5m"}
# The number of deployment replicas to use for the test app.
REPLICAS=${REPLICAS:-1}

# Supported update types.
valid_updates=("l4" "l7" "waypoint")

# Source the utility functions
source ./scripts/utils.sh

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
MESH=${1:-"base"}

# Check the type of update
UPDATE=${2:-""}

# Validate update parameters
if [[ -n "$UPDATE" ]]; then
  IFS=',' read -ra UPDATES <<< "$UPDATE"
  for p in "${UPDATES[@]}"; do
    if [[ ! " ${valid_updates[*]} " =~ " $p " ]]; then
      echo "Invalid update: $p. Supported values are 'l4', 'l7', and 'waypoint'."
      exit 1
    fi
  done
fi

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

# Apply the sidecar label to the specified namespaces.
if [[ "$MESH" == "sidecar" && -z "$UPDATE" ]]; then
  for i in $(seq 1 $NUM_NS); do
    NAMESPACE="ns-$i"
    echo "Applying sidecar label to $NAMESPACE..."
    kubectl label namespace $NAMESPACE istio-injection=enabled --overwrite || {
      echo "Failed to apply sidecar labels to namespace $NAMESPACE"
      exit 1
    }
    echo "Applying sidecar annotations to test app deployments in $NAMESPACE..."
    kubectl get deployments -n $NAMESPACE -l kind=3-tier -o custom-columns=NAME:.metadata.name --no-headers | while read -r name; do
    kubectl patch -n $NAMESPACE deployment "$name" --patch '{
    "spec": {
      "template": {
        "metadata": {
          "annotations": {
            "proxy.istio.io/config": "{ \"holdApplicationUntilProxyStarts\": true }",
            "sidecar.istio.io/proxyMemoryLimit": "1Gi",
            "sidecar.istio.io/proxyCPULimit": "1",
            "sidecar.istio.io/proxyMemory": "128Mi",
            "sidecar.istio.io/proxyCPU": "100m"
          }
        }
      }
    }
  }'
    done || {
      echo "Failed to apply sidecar annotations to namespace $NAMESPACE"
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

# Sidecar uses the base app manifests.
if [[ "$MESH" == "sidecar" ]]; then
  MANIFEST_PATH="manifests/app/base"
fi

# Apply the manifest
echo "Applying $MANIFEST_PATH manifests."
for i in $(seq 1 $NUM_NS); do
  for manifest in "$MANIFEST_PATH"/*; do
    if [[ -f "$manifest" ]]; then
      # Update manifest variables
      sed -e "s/\$i/$i/g" \
        -e "s/\$REPLICAS/$REPLICAS/g" \
        "$manifest" | kubectl apply -f - || {
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
  # Wait for all app deployments to be ready
  all_app_rollout_status_and_rollback
elif [[ "$MESH" == "ambient" && "$UPDATE" == "waypoint" ]]; then
  # Wait for all waypoint deployments to be ready
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
