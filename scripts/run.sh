#!/bin/bash

set -e

# The number of namespaces used to run the test app or load generators.
NUM_NS=${NUM_NS:-"1"}
# A time unit, e.g. 1s, 2m, 3h, to wait for a deployment rollout to complete.
ROLLOUT_TIMEOUT=${ROLLOUT_TIMEOUT:-"5m"}

# Supported values for the number of namespaces.
valid_num_ns=(1 25)
# Supported types for the script.
valid_types=("app" "loadgen")

# Check if type argument is provided
if [ -z "$1" ]; then
  echo "Usage: $0 <type>"
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

# Function to handle rollout status and rollback for the app
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
      kubectl delete -k manifests/loadgen/$NUM_NS/base || {
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

# Apply the appropriate manifests based on the type
if [[ "$TYPE" == "app" ]]; then
  # Deploy the test app
  kubectl apply -k manifests/app/$NUM_NS/base || {
    echo "Failed to apply Kubernetes resources: ${PIPESTATUS[0]}"
    kubectl delete -k manifests/app/$NUM_NS/base || {
      echo "Failed to delete Kubernetes resources: ${PIPESTATUS[0]}"
    }
    exit 1
  }
  # Check rollout status and rollback for all namespaces
  all_app_rollout_status_and_rollback
  if [ "$NUM_NS" -eq 1 ]; then
    echo "Test app is running in $NUM_NS namespace."
  else
    echo "Test app is running in $NUM_NS namespaces."
  fi
elif [[ "$TYPE" == "loadgen" ]]; then
  # Deploy the load generators
  kubectl apply -k manifests/loadgen/$NUM_NS/base || {
    echo "Failed to apply Kubernetes resources: ${PIPESTATUS[0]}"
    kubectl delete -k manifests/loadgen/$NUM_NS/base || {
      echo "Failed to delete Kubernetes resources: ${PIPESTATUS[0]}"
    }
    exit 1
  }
  # Check rollout status and rollback for all namespaces
  all_loadgen_rollout_status_and_rollback
  if [ "$NUM_NS" -eq 1 ]; then
    echo "Load generators are running in $NUM_NS namespace."
  else
    echo "Load generators are running in $NUM_NS namespaces."
  fi
fi
