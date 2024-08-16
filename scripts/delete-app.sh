#!/bin/bash

set -e

# The number of namespaces to remove the test app from. 
NUM_NS=${NUM_NS:-"1"}

# Supported values for the number of namespaces.
valid_num_ns=(1 25)

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

# Deploy the test app with error handling and rollback
kubectl delete -k manifests/app/$NUM_NS/base || {
    echo "Failed to apply Kubernetes resources: ${PIPESTATUS[0]}"
    exit 1
}

if [ "$NUM_NS" -eq 1 ]; then
  echo "Test app removed from $NUM_NS namespace."
else
  echo "Test app removed from $NUM_NS namespaces."
fi
