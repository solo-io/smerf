#!/bin/bash

set -e

# Environment Variables
CREATE_CLUSTER=${CREATE_CLUSTER:-false}
CLUSTER_TYPE=${CLUSTER_TYPE:-"eks"}
# Get the first cluster name returned by `eksctl get clusters`
DEFAULT_CLUSTER_NAME=$(eksctl get clusters --output json | jq -r '.[0].Name')
# Set the CLUSTER_NAME variable, defaulting to the name returned by eksctl if not provided
CLUSTER_NAME=${CLUSTER_NAME:-$DEFAULT_CLUSTER_NAME}
# Get the first cluster name returned by `eksctl get clusters`
DEFAULT_REGION=$(eksctl get clusters --output json | jq -r '.[0].Region')
# Set the REGION variable, defaulting to the region returned by eksctl if not provided
REGION=${REGION:-$DEFAULT_REGION}
NUM_NS=${NUM_NS:-"1"}
# Set the default number of nodes based on the number of ready nodes
DEFAULT_NUM_NODES=$(kubectl get nodes | grep -c 'Ready')
NUM_NODES=${NUM_NODES:-$DEFAULT_NUM_NODES}
REPLICAS=${REPLICAS:-1}
RPS=${RPS:-"150"}
DURATION=${DURATION:-"10m"}
DELETE_CLUSTER=${DELETE_CLUSTER:-false}

# Create an EKS cluster
if [ "$CREATE_CLUSTER" = true ]; then
  echo "Creating Kubernetes cluster..."
  ./scripts/create-perf-cluster.sh
fi

# Run the test app
echo "Running the test app..."
REPLICAS=$REPLICAS ./scripts/create.sh app

# Run the load generators
echo "Running the load generators..."
DURATION=$DURATION RPS=$RPS ./scripts/create.sh loadgen

# Create performance baseline reports
echo "Creating performance baseline reports..."
./scripts/run-all-reports.sh "$CLUSTER_TYPE-$NUM_NODES-node-$NUM_NS-ns-$REPLICAS-replica-$RPS-rps-$DURATION-duration-baseline"

# Scale down the load generators
echo "Scaling down the load generators..."
./scripts/scale.sh loadgen 0

# Install Istio using ambient mode
echo "Installing Istio in ambient mode..."
./scripts/install-istio.sh ambient

# Add the test app to the Istio ambient mesh
echo "Adding the test app to the Istio ambient mesh..."
REPLICAS=$REPLICAS ./scripts/update-app.sh ambient

# Scale up the load generators
echo "Scaling up the load generators..."
./scripts/scale.sh loadgen 1

# Create ambient mTLS performance reports
echo "Creating ambient mTLS performance reports..."
./scripts/run-all-reports.sh "$CLUSTER_TYPE-$NUM_NODES-node-$NUM_NS-ns-$REPLICAS-replica-$RPS-rps-$DURATION-duration-ambient"

# Scale down the load generators
echo "Scaling down the load generators..."
./scripts/scale.sh loadgen 0

# Apply Istio L4 auth policies
echo "Applying Istio L4 auth policies..."
REPLICAS=$REPLICAS ./scripts/update-app.sh ambient l4

# Scale up the load generators
echo "Scaling up the load generators..."
./scripts/scale.sh loadgen 1

# Create ambient mTLS+L4 Auth performance reports
echo "Creating ambient mTLS+L4 Auth performance reports..."
./scripts/run-all-reports.sh "$CLUSTER_TYPE-$NUM_NODES-node-$NUM_NS-ns-$REPLICAS-replica-$RPS-rps-$DURATION-duration-ambient-l4-auth"

# Scale down the load generators
echo "Scaling down the load generators..."
./scripts/scale.sh loadgen 0

# Create an ambient waypoint per namespace
echo "Creating an ambient waypoint per namespace..."
./scripts/update-app.sh ambient waypoint

# Apply Istio L7 auth policies
echo "Applying Istio L7 auth policies..."
./scripts/update-app.sh ambient l7

# Scale up the load generators
echo "Scaling up the load generators..."
./scripts/scale.sh loadgen 1

# Create ambient waypoint+L7 Auth performance reports
echo "Creating ambient waypoint+L7 Auth performance reports..."
./scripts/run-all-reports.sh "$CLUSTER_TYPE-$NUM_NODES-node-$NUM_NS-ns-$REPLICAS-replica-$RPS-rps-$DURATION-duration-ambient-l7-auth"

# Delete the load generators
./scripts/delete.sh loadgen

# Delete the test app
echo "Deleteing test app..."
./scripts/delete.sh app

# Uninstall Istio using ambient mode
echo "Uninstalling Istio in ambient mode..."
./scripts/uninstall-istio.sh ambient

# Delete the cluster if DELETE_CLUSTER is set to true and CLUSTER_TYPE is "eks"
if [ "$DELETE_CLUSTER" = true ] && [ "$CLUSTER_TYPE" = "eks" ]; then
  echo "Deleting the Kubernetes cluster..."
  eksctl delete cluster --region="$REGION" --name="$CLUSTER_NAME"
fi
