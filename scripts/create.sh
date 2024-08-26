#!/bin/bash

set -e

# The number of namespaces used to run the test app or load generators.
NUM_NS=${NUM_NS:-"1"}
# A time unit, e.g. 1s, 2m, 3h, to wait for a deployment rollout to complete.
ROLLOUT_TIMEOUT=${ROLLOUT_TIMEOUT:-"5m"}
# The number of deployment replicas to use for the specified workload_type.
REPLICAS=${REPLICAS:-1}
# The number of requests per second to send when workload_type is loadgen.
RPS=${RPS:-"150"}
# The duration in time to generate traffic load when workload_type is loadgen.
DURATION=${DURATION:-"10m"}

# Supported workload types for the script.
valid_types=("app" "loadgen")

# Check if workload type argument is provided
if [ -z "$1" ]; then
  echo "Usage: $0 <type>"
  echo "Supported workload types are: app, loadgen"
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

# Function to handle rollout status and rollback for the app
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

# Function to handle rollout status and rollback for all app namespaces
all_app_rollout_status_and_rollback() {
  for i in $(seq 1 $NUM_NS); do
    app_rollout_status_and_rollback "ns-$i"
  done
}

# Function to handle rollout status and rollback for the load generators
load_rollout_status_and_rollback() {
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

# Function to handle rollout status and rollback for all loadgen namespaces
all_loadgen_rollout_status_and_rollback() {
  for i in $(seq 1 $NUM_NS); do
    load_rollout_status_and_rollback "ns-$i"
  done
}

# Apply the appropriate manifests based on the workload type
if [[ "$TYPE" == "app" ]]; then
  # Update and apply the loadgen manifest
  MANIFEST="manifests/app/base/app.yaml"
  echo "Applying $MANIFEST manifest with: replicas=$REPLICAS"
  for i in $(seq 1 $NUM_NS); do
      # Update manifest variables
      sed -e "s/\$i/$i/g" \
          -e "s/\$REPLICAS/$REPLICAS/g" \
          $MANIFEST | kubectl apply -f - || {
        echo "Failed to apply Kubernetes resources for namespace ns-$i: ${PIPESTATUS[0]}"
        sed "s/\$i/$i/g" manifests/app/base/app.yaml | kubectl delete -f - || {
        echo "Failed to delete Kubernetes resources for namespace ns-$i: ${PIPESTATUS[0]}"
      }
        exit 1
      }
  done
  # Check rollout status and rollback for all namespaces
  all_app_rollout_status_and_rollback
  if [ "$NUM_NS" -eq 1 ]; then
    echo "Test app is running in $NUM_NS namespace."
  else
    echo "Test app is running in $NUM_NS namespaces."
  fi
elif [[ "$TYPE" == "loadgen" ]]; then
  # Update and apply the loadgen manifest
  MANIFEST="manifests/loadgen/base/loadgen.yaml"
  echo "Applying $MANIFEST manifest with: replicas=$REPLICAS, rps=$RPS, duration=$DURATION"
  for i in $(seq 1 $NUM_NS); do
      # Update manifest variables
      sed -e "s/\$i/$i/g" \
          -e "s/\$DURATION/$DURATION/g" \
          -e "s/\$RPS/$RPS/g" \
          -e "s/\$REPLICAS/$REPLICAS/g" \
          manifests/loadgen/base/loadgen.yaml | kubectl apply -f - || {
        echo "Failed to apply Kubernetes resources for namespace ns-$i: ${PIPESTATUS[0]}"
        sed "s/\$i/$i/g" manifests/loadgen/base/loadgen.yaml | kubectl delete -f - || {
        echo "Failed to delete Kubernetes resources for namespace ns-$i: ${PIPESTATUS[0]}"
      }
        exit 1
      }
  done
  # Check rollout status and rollback for all namespaces
  all_loadgen_rollout_status_and_rollback
  if [ "$NUM_NS" -eq 1 ]; then
    echo "Load generators are running in $NUM_NS namespace."
  else
    echo "Load generators are running in $NUM_NS namespaces."
  fi
fi
