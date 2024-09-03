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
# The number of namespaces to run the 3-tier test app.
NUM_NS=${NUM_NS:-"1"}
# Set the default number of nodes based on the number of ready nodes
DEFAULT_NUM_NODES=$(kubectl get nodes | grep -c 'Ready' || true)
NUM_NODES=${NUM_NODES:-$DEFAULT_NUM_NODES}
# Profile is the service mesh profile to use. Supported options are 'ambient' and 'sidecar'
PROFILE=${PROFILE:-"ambient"}
# The number of replicas to use for the 3-tier test app
REPLICAS=${REPLICAS:-1}
# The number of requests per second to generate
RPS=${RPS:-"150"}
# The length of time to generate traffic
DURATION=${DURATION:-"10m"}
DELETE_CLUSTER=${DELETE_CLUSTER:-false}
# Run the baseline performance testing
RUN_BASELINE=${RUN_BASELINE:-true}
# Whether to install Istio. If true, Istio will be installed based on the configured $PROFILE
INSTALL_MESH=${INSTALL_MESH:-true}

# Supported install profile values.
valid_profiles=("ambient" "sidecar")

# Check if NUM_NS is valid
if [[ ! " ${valid_profiles[*]} " =~ " $PROFILE " ]]; then
  echo "Invalid value for profile. Supported values are 'ambient' and 'sidecar'"
  exit 1
fi

# Create an EKS cluster
if [ "$CREATE_CLUSTER" = true ]; then
  echo "Creating Kubernetes cluster..."
  ./scripts/create-cluster.sh
fi

# Run the test app
echo "Running the test app..."
REPLICAS=$REPLICAS ./scripts/create.sh app

# Run the load generators
echo "Running the load generators..."
REPLICAS=1 DURATION=$DURATION RPS=$RPS ./scripts/create.sh loadgen

if [ "$RUN_BASELINE" = true ]; then
  # Create performance baseline reports
  echo "Creating performance baseline reports..."
  ./scripts/run-all-reports.sh "$CLUSTER_TYPE-$NUM_NODES-node-$NUM_NS-ns-$REPLICAS-replica-$RPS-rps-$DURATION-duration-baseline"
fi

# Scale down the load generators
echo "Scaling down the load generators..."
./scripts/scale.sh loadgen 0

# Install Istio using the configured profile
if [ "$INSTALL_MESH" = true ]; then
  echo "Installing Istio in $PROFILE mode..."
  ./scripts/install-istio.sh $PROFILE
fi

# Add the test app to the Istio service mesh
echo "Adding the test app to the Istio $PROFILE mesh..."
REPLICAS=$REPLICAS ./scripts/update-app.sh $PROFILE

# Scale up the load generators
echo "Scaling up the load generators..."
./scripts/scale.sh loadgen 1

# Create performance reports based on the configured $PROFILE
echo "Creating $PROFILE performance reports..."
./scripts/run-all-reports.sh "$CLUSTER_TYPE-$NUM_NODES-node-$NUM_NS-ns-$REPLICAS-replica-$RPS-rps-$DURATION-duration-$PROFILE"

# Scale down the load generators
echo "Scaling down the load generators..."
./scripts/scale.sh loadgen 0

if [[ "$PROFILE" == "ambient" ]]; then
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
fi

# Delete the load generators
echo "Deleteing load generators..."
./scripts/delete.sh loadgen

# Delete the test app
echo "Deleteing test app..."
./scripts/delete.sh app

# Uninstall Istio based on the configured $PROFILE
if [ "$INSTALL_MESH" = true ]; then
  echo "Uninstalling Istio in $PROFILE mode..."
  ./scripts/uninstall-istio.sh $PROFILE
fi

# Delete the cluster if DELETE_CLUSTER is set to true and CLUSTER_TYPE is "eks"
if [ "$DELETE_CLUSTER" = true ] && [ "$CLUSTER_TYPE" = "eks" ]; then
  echo "Deleting the Kubernetes cluster..."
  eksctl delete cluster --region="$REGION" --name="$CLUSTER_NAME"
fi
