#!/usr/bin/env bash

set -e

# The number of namespaces used to run the test app.
NUM_NS=${NUM_NS:-"1"}
# A time unit, e.g. 1s, 2m, 3h, to wait for a test app deployment rollout to complete.
ROLLOUT_TIMEOUT=${ROLLOUT_TIMEOUT:-"5m"}
# The number of requests per second to send from each load generator.
RPS=${RPS:-"150"}
# The duration in time to generate traffic load.
DURATION=${DURATION:-"10m"}
# The number of deployment replicas to use for the load generator deployment.
REPLICAS=${REPLICAS:-1}

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
loadgen_rollout_status_and_rollback() {
  local namespace=$1
  for deploy in vegeta1 vegeta2; do
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
all_loadgen_rollout_status_and_rollback() {
  # Wait for the tiered app rollout to complete
  for i in $(seq 1 $NUM_NS); do
    loadgen_rollout_status_and_rollback "ns-$i"
  done
}

# Update and apply the loadgen manifest
MANIFEST="manifests/loadgen/base/loadgen.yaml"
echo "Applying $MANIFEST manifest with updates: rps=$RPS, duration=$DURATION"
for i in $(seq 1 $NUM_NS); do
    # Update manifest variables
    sed -e "s/\$i/$i/g" \
        -e "s/\$REPLICAS/$REPLICAS/g" \
        -e "s/\$DURATION/$DURATION/g" \
        -e "s/\$RPS/$RPS/g" \
        manifests/loadgen/base/loadgen.yaml | kubectl apply -f - || {
      echo "Failed to apply Kubernetes resources for namespace ns-$i: ${PIPESTATUS[0]}"
      exit 1
    }
done

# Wait for all loadgen deployments to be ready
all_loadgen_rollout_status_and_rollback

if [ "$NUM_NS" -eq 1 ]; then
  echo "Updated load generators in $NUM_NS namespace."
else
  echo "Updated load generators in $NUM_NS namespaces."
fi
