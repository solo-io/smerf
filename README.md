# Table of Contents

- [Table of Contents](#table-of-contents)
  - [Introduction](#introduction)
  - [Prerequisites](#prerequisites)
  - [Create a Cluster](#create-a-cluster)
  - [Run the Test App or Load Generators](#run-the-test-app-or-load-generators)
  - [Scale the Test App or Load Generators](#scale-the-test-app-or-load-generators)
  - [Install Istio](#install-istio)
  - [Update the Test App](#update-the-test-app)
  - [Cleanup](#cleanup)
    - [Delete the Test App or Load Generators](#delete-the-test-app-or-load-generators)

## Introduction

Mesh-perf provides tools for performance benchmark testing of service mesh implementations.

## Prerequisites

Ensure the following tools are installed:

- [kubectl](https://kubernetes.io/docs/tasks/tools/): The Kubernetes command-line tool.
- [eksctl](https://eksctl.io/): Required for managing EKS clusters.
- [helm](https://helm.sh/docs/intro/install/): A package manager for Kubernetes.

## Create a Cluster

The `scripts/create-perf-cluster.sh` script automates the creation of a Kubernetes cluster,
defaulting to Amazon EKS if `CLUSTER_TYPE` is unspecified. It also handles node labeling/tainting,
and optional add-on installations, e.g. Kubernetes metrics-server.

__Environment Variables:__

- `AWS_ACCESS_KEY_ID`: Required for EKS.
- `AWS_SECRET_ACCESS_KEY`: Required for EKS.
- `AWS_SESSION_TOKEN`: Required for EKS.
- `CLUSTER_NAME`: Default is ${USER}-$RANDOM.
- `REGION`: AWS region, default is us-west-2.
- `NUM_NODES`: Number of nodes, default is 3.
- `INSTANCE`: Instance type, defaults to AWS EC2 m5.2xlarge.
- `CILIUM_NODE_TAINT`: Taints nodes to ensure application pods are not scheduled until Cilium is deployed, defaults to false.
- `NUM_LOAD_NODES`: Number of nodes to label as load generators, default is 1.
- `ADDONS`: A comma-separated list of add-ons, defaults to metrics-server.
- `DELETE_CLUSTER_ON_FAIL`: Deletes the cluster on failure, default is true.

## Run the Test App or Load Generators

The `scripts/create.sh <workload_type>` automates the creation of the 3-tier app used as a target or the vegeta
load generators used to generate traffic for performance benchmark testing.

__Arguments:__

- `workload_type`: The type of workload to run, supported options are `app` for the 3-tier test app and `loadgen`
  for the vegeta load generators.

__Environment Variables:__

- `NUM_NS`: The number of namespaced app instances, defaults to 1.
- `ROLLOUT_TIMEOUT`: The amount of time to wait for each app deployment to rollout, defaults to 5m for 5-minutes.

## Scale the Test App or Load Generators

The `scripts/scale.sh <workload_type> <replicas>` script scales the 3-tier test app or vegeta load generators up or down.

__Arguments:__

- `workload_type`: The type of workload to scale, supported options are `app` for the 3-tier test app
and `loadgen` for the vegeta load generators.
- `replicas`: The number of replicas to scale the `workload_type` to.

__Environment Variables:__

- `NUM_NS`: The number of namespaced app instances, defaults to 1.
- `ROLLOUT_TIMEOUT`: The amount of time to wait for each app deployment to report status, defaults to 5m for 5-minutes.

## Install Istio

The `scripts/install-istio.sh <profile>` script automates the installation of Istio.

__Arguments:__

- `profile`: The installation profile to use, supported options are `ambient` and `sidecar`.

__Environment Variables:__

- `NUM_NS`: The number of namespaced vegeta instances, defaults to 1.
- `ROLLOUT_TIMEOUT`: The amount of time to wait for each vegeta deployment to rollout, defaults to 5m for 5-minutes.

- `ISTIO_VERSION`: The version of Istio to install. Supported options are "1.22.1" (default) and "1.22.1-patch0-solo".
- `ISTIO_REPO`: The repo to use for pulling Istio container images. Supported options are "docker.io/istio" (default)
and "us-docker.pkg.dev/gloo-mesh/istio-a9ee4fe9f69a".
- `ROLLOUT_TIMEOUT`: A time unit, e.g. 1s, 2m, 3h, to wait for Istio deployment roll-outs to complete. Defaults to "5m".

## Update the Test App

The `scripts/update.sh <workload_type> [<mesh_type> <update_type>]` script updates the 3-tier test app for the specified `<mesh_type>`.

Examples:

- `scripts/update.sh app ambient` to run the 3-tier test app on ambient mesh. __Note:__ Requires a running Istio control plane
  configured for ambient, e.g . `scripts/install-istio.sh ambient`.
- `scripts/update.sh app ambient l4` to apply L4 authn policies to the 3-tier test app running on ambient mesh.

__Arguments:__

- `workload_type`: The type of workload to scale, supported options are `app` for the 3-tier test app.
- `mesh_type`: The type of mesh to associate with the workload.
- `update_type`: The type of update to apply for the specified `<mesh_type>`. Supported options for `mesh_type=ambient` are `l4`
to apply Istio L4 authorization policies, `l7` to apply Istio L7 authorization policies, and `waypoint` to apply waypoint proxies
to the 3-tier test app instances.

__Environment Variables:__

- `NUM_NS`: The number of namespaced 3-tier test app or vegeta load generators instances, defaults to 1.

## Cleanup

### Delete the Test App or Load Generators

The `scripts/delete.sh <workload_type>` script deletes the 3-tier test app or vegeta load generators and all of
the app's dependencies.

__Arguments:__

- `workload_type`: The type of workload to delete, supported options are `app` for the 3-tier test app and
  `loadgen` for the vegeta load generators.

__Environment Variables:__

`NUM_NS`: The number of namespaced 3-tier test app or vegeta load generators instances, defaults to 1.
