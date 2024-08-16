#!/bin/bash

set -e

# The version of Istio to install.
ISTIO_VERSION=${ISTIO_VERSION:-"1.22.1"}
# The repo to use for pulling Istio control-plane images.
ISTIO_REPO=${ISTIO_REPO:-"docker.io/istio"}
# A time unit, e.g. 1s, 2m, 3h, to wait for Istio control-plane component deployment rollout to complete.
ROLLOUT_TIMEOUT=${ROLLOUT_TIMEOUT:-"5m"}

# Check if the installation profile argument is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <installation_profile>"
    exit 1
fi

profile=$1

# Supportedinstall profile values.
valid_profiles=("ambient" "sidecar")

# Check if NUM_NS is valid
if [[ ! " ${valid_profiles[*]} " =~ " $profile " ]]; then
  echo "Invalid value for profile. Supported values are 'ambient' and 'sidecar'"
  exit 1
fi

# Supported Itio version values.
valid_istio_versions=("1.22.1" "1.22.1-patch0-solo")

# Check if ISTIO_VERSION is valid
if [[ ! " ${valid_istio_versions[*]} " =~ " $ISTIO_VERSION " ]]; then
  echo "Invalid value for ISTIO_VERSION. Supported values are '1.22.1' and '1.22.1-patch0-solo'."
  exit 1
fi

# Supported Itio repo values.
valid_istio_repos=("docker.io/istio" "us-docker.pkg.dev/gloo-mesh/istio-a9ee4fe9f69a")

# Check if ISTIO_REPO is valid
if [[ ! " ${valid_istio_repos[*]} " =~ " $ISTIO_REPO " ]]; then
  echo "Invalid value for ISTIO_REPO. Supported values are 'docker.io/istio' and 'us-docker.pkg.dev/gloo-mesh/istio-a9ee4fe9f69a'."
  exit 1
fi

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check if required CLI tools are installed
for cmd in kubectl helm; do
  if ! command_exists $cmd; then
    echo "$CMD is not installed. Please install $cmd before running this script."
    exit 1
  fi
done

# Function to handle rollout status of a daemonset
ds_rollout_status() {
  local ds=$1
  local ns=$2
  kubectl rollout status ds/$ds -n $ns --timeout=$ROLLOUT_TIMEOUT || {
    echo "Rollout status check failed for daemonset $ds/$ns: ${PIPESTATUS[0]}"
    exit 1
  }
}

# Function to handle rollout status of a deployment
deploy_rollout_status() {
  local deploy=$1
  local ns=$2
  kubectl rollout status deploy/$deploy -n $ns --timeout=$ROLLOUT_TIMEOUT || {
    echo "Rollout status check failed for deployment $deploy/$ns: ${PIPESTATUS[0]}"
    exit 1
  }
}

# Add Istio helm repo
helm repo add istio https://istio-release.storage.googleapis.com/charts
helm repo update

# Install istio-base
helm upgrade --install istio-base istio/base -n istio-system --version $ISTIO_VERSION --create-namespace

# Install Kubernetes Gateway CRDs
kubectl get crd gateways.gateway.networking.k8s.io &> /dev/null || \
  { kubectl kustomize "github.com/kubernetes-sigs/gateway-api/config/crd?ref=v1.0.0" | kubectl apply -f -; }

# Create the istio cni config file
if [[ "$profile" == "ambient" ]]; then
  cat << EOF > istio-cni-config.yaml
global:
  hub: $ISTIO_REPO
  tag: $ISTIO_VERSION
profile: ambient
EOF

  # Echo the contents of the config file
  echo "Generated istio-cni-node configuration:"
  cat istio-cni-config.yaml

  # Install istio cni
  helm upgrade --install istio-cni istio/cni \
  -n istio-system \
  --version=$ISTIO_VERSION \
  -f istio-cni-config.yaml

  # Wait for the istio cni daemonset rollout to complete
  ds_rollout_status "istio-cni-node" "istio-system"
fi

# Create the istiod config file
if [[ "$profile" == "ambient" ]]; then
  cat << EOF > istiod-config.yaml
global:
  hub: $ISTIO_REPO
  tag: $ISTIO_VERSION
profile: ambient
EOF
else
  cat << EOF > istiod-config.yaml
global:
  hub: $ISTIO_REPO
  tag: $ISTIO_IMAGE
meshConfig:
  accessLogFile: /dev/stdout
  enableAutoMtls: true
  defaultConfig:
    holdApplicationUntilProxyStarts: true
    proxyMetadata:
      ISTIO_META_DNS_CAPTURE: "true"
      ISTIO_META_DNS_AUTO_ALLOCATE: "true"
  outboundTrafficPolicy:
    mode: ALLOW_ANY
EOF
fi

# Echo the contents of the istiod config file
echo "Generated istiod configuration:"
cat istiod-config.yaml

# Install Istiod
helm upgrade --install istiod istio/istiod \
-n istio-system \
--version=$ISTIO_VERSION \
-f istiod-config.yaml

# Wait for the istiod deployment rollout to complete
deploy_rollout_status "istiod" "istio-system"

# TODO: Update the sidecar injector configmap for waypoint anti-affinity.

# Create the ztunnel config file
if [[ "$profile" == "ambient" ]]; then
  cat << EOF > istio-ztunnel-config.yaml
variant: distroless
hub: $ISTIO_REPO
tag: $ISTIO_VERSION
EOF

  # Echo the contents of the config file
  echo "Generated istio-ztunnel configuration:"
  cat istio-ztunnel-config.yaml

  # Install ztunnel
  helm upgrade --install ztunnel istio/ztunnel \
  -n istio-system \
  --version=$ISTIO_VERSION \
  -f istio-ztunnel-config.yaml

  # Wait for the ztunnel daemonset rollout to complete
  ds_rollout_status "ztunnel" "istio-system"
fi

echo "Istio successfully installed!"