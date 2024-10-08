#!/usr/bin/env bash

set -e

# The number of namespaces used to run the test app or load generators.
NUM_NS=${NUM_NS:-"1"}
# A time unit, e.g. 1s, 2m, 3h, to wait for a deployment rollout to complete.
ROLLOUT_TIMEOUT=${ROLLOUT_TIMEOUT:-"5m"}

# Supported types for the script.
valid_types=("app" "loadgen")

# Check if type argument is provided
if [ -z "$1" ]; then
  echo "Usage: $0 <workload_type> <replicas>"
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

# Check if replicas argument is provided
if [ -z "$2" ]; then
  echo "Usage: $0 $TYPE <replicas>"
  exit 1
fi

replicas=$2

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

# Function to handle rollout status for the app
app_rollout_status() {
  local namespace=$1
  for deploy in tier-1-app-a tier-1-app-b tier-2-app-a tier-2-app-b tier-2-app-c tier-2-app-d tier-3-app-a tier-3-app-b; do
    kubectl rollout status deploy/$deploy -n $namespace --timeout=$ROLLOUT_TIMEOUT || {
      echo "Rollout status check failed for deployment $deploy in namespace $namespace: ${PIPESTATUS[0]}"
      exit 1
    }
  done
  if [ "$replicas" -eq 0 ]; then
      # Wait until all pods to no longer exist
      echo "Waiting for all pods with label 'kind=3-tier' to be terminated..."
      while kubectl get pods -n $namespace -l kind=3-tier --no-headers | grep -q .; do
          echo "Pods with in namespace $namespace with label 'kind=3-tier' are still terminating..."
          sleep 2
      done
      echo "All pods in namespace $namespace with label 'kind=3-tier' have been terminated."
  else
      # Wait for all pods to be ready
      kubectl wait --for=condition=ready -n $namespace pod -l kind=3-tier --timeout=300s
      # Ensure all pods are ready before proceeding
      if kubectl get pods -n $namespace -l kind=3-tier --field-selector=status.phase!=Running | grep -q 'Pending\|Failed'; then
          echo "Some pods in namespace $namespace are not ready. Exiting."
          exit 1
      fi
      echo "All pods are ready."
  fi
}

# Function to handle rollout status for the load generators
loadgen_rollout_status() {
  local namespace=$1
  for deploy in vegeta1 vegeta2; do
    kubectl rollout status deploy/$deploy -n $namespace --timeout=$ROLLOUT_TIMEOUT || {
      echo "Rollout status check failed for deployment $deploy in namespace $namespace: ${PIPESTATUS[0]}"
      exit 1
    }
  done
  if [ "$replicas" -eq 0 ]; then
      # Wait until all pods to no longer exist
      echo "Waiting for all pods with label 'kind=vegeta' to be terminated..."
      while kubectl get pods -n $namespace -l kind=vegeta --no-headers | grep -q .; do
          echo "Pods with label 'kind=vegeta' are still terminating..."
          sleep 2
      done
      echo "All pods with label 'kind=vegeta' have been terminated."
  else
      # Wait for all pods to be ready
      kubectl wait --for=condition=ready pod -n $namespace -l kind=vegeta  --timeout=300s
      # Ensure all pods are ready before proceeding
      if kubectl get pods -n $namespace -l kind=vegeta --field-selector=status.phase!=Running | grep -q 'Pending\|Failed'; then
          echo "Some pods are not ready. Exiting."
          exit 1
      fi
      echo "All pods are ready."
  fi
}

# Scale deployments based on the type
if [[ "$TYPE" == "app" ]]; then
  for i in $(seq 1 $NUM_NS); do
    kubectl scale deploy/tier-1-app-a -n ns-$i --replicas=$replicas --timeout=$ROLLOUT_TIMEOUT
    kubectl scale deploy/tier-1-app-b -n ns-$i --replicas=$replicas --timeout=$ROLLOUT_TIMEOUT
    kubectl scale deploy/tier-2-app-a -n ns-$i --replicas=$replicas --timeout=$ROLLOUT_TIMEOUT
    kubectl scale deploy/tier-2-app-b -n ns-$i --replicas=$replicas --timeout=$ROLLOUT_TIMEOUT
    kubectl scale deploy/tier-2-app-c -n ns-$i --replicas=$replicas --timeout=$ROLLOUT_TIMEOUT
    kubectl scale deploy/tier-2-app-d -n ns-$i --replicas=$replicas --timeout=$ROLLOUT_TIMEOUT
    kubectl scale deploy/tier-3-app-a -n ns-$i --replicas=$replicas --timeout=$ROLLOUT_TIMEOUT
    kubectl scale deploy/tier-3-app-b -n ns-$i --replicas=$replicas --timeout=$ROLLOUT_TIMEOUT
    app_rollout_status "ns-$i"
  done
  if [ "$NUM_NS" -eq 1 ]; then
    echo "Test app has been scaled to $replicas in $NUM_NS namespace."
  else
    echo "Test app has been scaled to $replicas in $NUM_NS namespaces."
  fi
elif [[ "$TYPE" == "loadgen" ]]; then
  for i in $(seq 1 $NUM_NS); do
    kubectl scale deploy/vegeta1 -n ns-$i --replicas=$replicas --timeout=$ROLLOUT_TIMEOUT
    kubectl scale deploy/vegeta2 -n ns-$i --replicas=$replicas --timeout=$ROLLOUT_TIMEOUT
    loadgen_rollout_status "ns-$i"
  done
  if [ "$NUM_NS" -eq 1 ]; then
    echo "Load generators have been scaled to $replicas in $NUM_NS namespace."
  else
    echo "Load generators have been scaled to $replicas in $NUM_NS namespaces."
  fi
fi
