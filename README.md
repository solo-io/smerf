# Table of Contents

- [Table of Contents](#table-of-contents)
  - [Introduction](#introduction)
  - [Prerequisites](#prerequisites)
  - [Create a Cluster](#create-a-cluster)
  - [Run the Test App](#run-the-test-app)
  - [Run the Load Generators](#run-the-load-generators)
  - [Install Istio](#install-istio)
  - [Cleanup](#cleanup)
    - [Delete the Load Generators](#delete-the-load-generators)
    - [Delete the Test App](#delete-the-test-app)

## Introduction

Tools for testing the performance of service mesh implementations.

## Prerequisites

Ensure the following tools are installed:

- [kubectl](https://kubernetes.io/docs/tasks/tools/): The Kubernetes command-line tool.
- [eksctl](https://eksctl.io/): Required for managing EKS clusters.
- [helm](https://helm.sh/docs/intro/install/): A package manager for Kubernetes.

## Create a Cluster

The `scripts/create-perf-cluster.sh` script automates the creation of a Kubernetes cluster,
defaulting to Amazon EKS if `CLUSTER_TYPE` is unspecified. It also handles node labeling,
tainting, and optional add-on installations like metrics-server.

__Environment Variables:__

`AWS_ACCESS_KEY_ID`: Required for EKS.
`AWS_SECRET_ACCESS_KEY`: Required for EKS.
`AWS_SESSION_TOKEN`: Required for EKS.
`CLUSTER_NAME`: Default is ${USER}-$RANDOM.
`REGION`: AWS region, default is us-west-2.
`NUM_NODES`: Number of nodes, default is 2.
`INSTANCE`: Instance type, defaults to AWS EC2 m5.2xlarge.
`CILIUM_NODE_TAINT`: Taints nodes to ensure application pods are not scheduled until Cilium is deployed, defaults to false.
`NUM_LOAD_NODES`: Number of nodes to label as load generators.
`ADDONS`: A comma-separated list of add-ons, defaults to metrics-server.
`DELETE_CLUSTER_ON_FAIL`: Deletes the cluster on failure, default is true.

## Run the Test App

The `scripts/run-app.sh` script automates the creation of a 3-tier app used as a target for performance testing.

__Environment Variables:__

`NUM_NS`: The number of namespaced app instances, defaults to 1.
`ROLLOUT_TIMEOUT`: The amount of time to wait for each app deployment to rollout, defaults to 5m for 5-minutes.

## Run the Load Generators

The `scripts/run-loadgen.sh` script automates the creation of vegeta deployments used to generate load against the test app.

__Environment Variables:__

`NUM_NS`: The number of namespaced vegeta instances, defaults to 1.
`ROLLOUT_TIMEOUT`: The amount of time to wait for each vegeta deployment to rollout, defaults to 5m for 5-minutes.

## Install Istio

The `scripts/install-istio.sh <profile>` script automates the installation of Istio.

__Arguments:__

`profile`: The installation profile to use, supported options are `ambient` and `sidecar`.

__Environment Variables:__

`NUM_NS`: The number of namespaced vegeta instances, defaults to 1.
`ROLLOUT_TIMEOUT`: The amount of time to wait for each vegeta deployment to rollout, defaults to 5m for 5-minutes.

`ISTIO_VERSION`: The version of Istio to install. Supported options are "1.22.1" (default) and "1.22.1-patch0-solo".
`ISTIO_REPO`: The repo to use for pulling Istio container images. Supported options are "docker.io/istio" (default)
and "us-docker.pkg.dev/gloo-mesh/istio-a9ee4fe9f69a".
`ROLLOUT_TIMEOUT`: A time unit, e.g. 1s, 2m, 3h, to wait for Istio deployment roll-outs to complete. Defaults to "5m".

## Cleanup

### Delete the Load Generators

The `scripts/delete-loadgen.sh` script automates the deletion of vegeta deployments.

__Environment Variables:__

`NUM_NS`: The number of namespaced vegeta instances, defaults to 1.

### Delete the Test App

The `scripts/delete-app.sh` script automates the deletion of the test app deployments.

__Environment Variables:__

`NUM_NS`: The number of namespaced test app instances, defaults to 1.
