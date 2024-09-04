#!/usr/bin/env bash

set -e

# Default values
CLUSTER_TYPE=${CLUSTER_TYPE:-"eks"}
CLUSTER_NAME=${CLUSTER_NAME:-"$(whoami)-$RANDOM"}
REGION=${REGION:-"us-west-2"}
NUM_NODES=${NUM_NODES:-"3"}
MAX_NUM_NODES=${MAX_NUM_NODES:-"450"} # Max size of a managed node group
INSTANCE=${INSTANCE:-"m5.2xlarge"}
DELETE_CLUSTER_ON_FAIL=${DELETE_CLUSTER_ON_FAIL:-"false"}
NUM_LOAD_NODES=${NUM_LOAD_NODES:-"1"}
ADDONS=${ADDONS:-"metrics-server"}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check if kubectl is installed
if ! command_exists kubectl; then
    echo "kubectl is not installed. Please install kubectl before running this script."
    exit 1
fi

# Create the directory for the config file
mkdir -p ./out/config

# Check if the cluster type is EKS
if [[ "$CLUSTER_TYPE" == "eks" || -z "$CLUSTER_TYPE" ]]; then
    # Check for necessary environment variables
    if [[ -z "$AWS_ACCESS_KEY_ID" || -z "$AWS_SECRET_ACCESS_KEY" || -z "$AWS_SESSION_TOKEN" ]]; then
        echo "Required AWS environment variables (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_SESSION_TOKEN) are not set."
        exit 1
    fi

    # Check if eksctl is installed
    if ! command_exists eksctl; then
        echo "eksctl is not installed. Please install eksctl before running this script."
        exit 1
    fi

    # Create the EKS cluster configuration
    cat << EOF > ./out/config/clusterconfig.yaml
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata:
  name: ${CLUSTER_NAME}
  region: ${REGION}
availabilityZones:
- ${REGION}a
- ${REGION}b
- ${REGION}c
iam:
  withOIDC: true
managedNodeGroups:
- name: ng-1
  desiredCapacity: ${NUM_NODES}
  maxSize: ${MAX_NUM_NODES}
  instanceType: ${INSTANCE}
  availabilityZones:
  - ${REGION}a
  ssh:
    allow: true
addonsConfig:
  autoApplyPodIdentityAssociations: true
addons:
  - name: eks-pod-identity-agent
  - name: kube-proxy
  - name: coredns
  - name: vpc-cni
EOF

    # Add taints if CILIUM_NODE_TAINT is true
    if [[ "$CILIUM_NODE_TAINT" == "true" ]]; then
        cat << EOF >> ./out/config/clusterconfig.yaml
  taints:
   - key: "node.cilium.io/agent-not-ready"
     value: "true"
     effect: "NoExecute"
EOF
    fi

    # Echo the contents of the clusterconfig.yaml file
    echo "Generated cluster configuration:"
    cat ./out/config/clusterconfig.yaml

    # Create the EKS cluster
    eksctl create cluster -f ./out/config/clusterconfig.yaml &
    CLUSTER_CREATION_PID=$!

    # Wait for the cluster creation
    wait $CLUSTER_CREATION_PID || {
        echo "Cluster creation failed. Capturing eksctl logs."
        eksctl utils describe-stacks --cluster $CLUSTER_NAME
        if [[ "$DELETE_CLUSTER_ON_FAIL" == "true" ]]; then
            eksctl delete cluster --region=$REGION --name $CLUSTER_NAME
        fi
        exit 1
    }

    # Verify kubectl access
    if ! kubectl get nodes; then
        echo "Unable to access Kubernetes API server. Capturing kubectl error."
        
        # Capture and display the error to stdout
        kubectl get nodes 2>&1
        
        # Optionally delete the cluster if the DELETE_CLUSTER_ON_FAIL variable is set
        if [[ "$DELETE_CLUSTER_ON_FAIL" == "true" ]]; then
            eksctl delete cluster --name $CLUSTER_NAME
        fi
        exit 1
    fi
fi

# Label and taint load nodes
NODE_COUNT=$(kubectl get nodes --no-headers | wc -l)
if [[ "$NODE_COUNT" -le "$NUM_LOAD_NODES" ]]; then
    echo "Not enough nodes to assign load generator roles. Expected at least $((NUM_LOAD_NODES + 1))."
    if [[ "$DELETE_CLUSTER_ON_FAIL" == "true" ]]; then
        eksctl delete cluster --name $CLUSTER_NAME
    fi
    exit 1
fi

kubectl get nodes --no-headers | tail -n +2 | head -n $NUM_LOAD_NODES | while read -r node _; do
    kubectl label nodes $node node=loadgen
    kubectl taint nodes $node loadgen=true:NoSchedule
done

# Install addons
IFS=',' read -ra ADDON_ARRAY <<< "$ADDONS"
for addon in "${ADDON_ARRAY[@]}"; do
    if [[ "$addon" == "metrics-server" ]]; then
        kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
        
        # Rollout status check
        if ! kubectl rollout status deploy/metrics-server -n kube-system; then
            echo "Failed to rollout the metrics-server deployment."
            kubectl describe deploy/metrics-server -n kube-system
            
            if [[ "$DELETE_CLUSTER_ON_FAIL" == "true" ]]; then
                eksctl delete cluster --name $CLUSTER_NAME
            fi
            
            exit 1
        fi
    fi
done

echo "Cluster setup completed successfully."
