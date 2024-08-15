# mesh-perf

Tools for testing the performance of service mesh implementations.

## Prerequisites

Ensure the following tools are installed:

[kubectl](https://kubernetes.io/docs/tasks/tools/): The Kubernetes command-line tool.
[eksctl](https://eksctl.io/): Required for managing EKS clusters.

## Create a Cluster

The `scripts/create-perf-cluster.sh` script automates the creation of a Kubernetes cluster,
defaulting to Amazon EKS if `CLUSTER_TYPE` is unspecified. It also handles node labeling,
tainting, and optional add-on installations like metrics-server.

### Environment Variables

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

### Environment Variables

`NUM_NS`: The number of namespaced app instances, defaults to 1.
`ROLLOUT_TIMEOUT`: The amount of time to wait for each app instance, defaults to 5m for 5-minutes.

## Run the Load Generator

The `scripts/run-loadgen.sh` script automates the creation of vegeta deployment used to generate load against the test app.

### Environment Variables

`NUM_NS`: The number of namespaced vegeta instances, defaults to 1.
`ROLLOUT_TIMEOUT`: The amount of time to wait for each vegeta instance, defaults to 5m for 5-minutes.
