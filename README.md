# Table of Contents

- [Table of Contents](#table-of-contents)
  - [Introduction](#introduction)
  - [Prerequisites](#prerequisites)
  - [Typical Workflow](#typical-workflow)
  - [Create a Cluster](#create-a-cluster)
  - [Run the Test App or Load Generators](#run-the-test-app-or-load-generators)
  - [Scale the Test App or Load Generators](#scale-the-test-app-or-load-generators)
  - [Install Istio](#install-istio)
  - [Update the Test App](#update-the-test-app)
  - [Manual Operations](#manual-operations)
    - [Cluster Node Pool Resizing](#cluster-node-pool-resizing)
    - [Manual Testing](#manual-testing)
    - [Istio](#istio)
  - [Cleanup](#cleanup)
    - [Delete the Test App or Load Generators](#delete-the-test-app-or-load-generators)

## Introduction

Mesh-perf provides tools for performance benchmark testing of service mesh implementations.

## Prerequisites

Ensure the following tools are installed:

- [kubectl](https://kubernetes.io/docs/tasks/tools/): The Kubernetes command-line tool.
- [eksctl](https://eksctl.io/): Required for managing EKS clusters.
- [helm](https://helm.sh/docs/intro/install/): A package manager for Kubernetes.

## Typical Workflow

A typical workflow is:

1. Create a Kubernetes cluster:

   ```scripts/create-perf-cluster.sh```

2. Run the test app:

   ```./scripts/create.sh app```

3. Run the load generators:

   ```./scripts/create.sh loadgen```

4. Create performance baseline reports:

   ```./scripts/run-all-reports.sh <unique_report_name>```

5. Scale down the load generators:

   ```./scripts/scale.sh loadgen 0```

6. Install Istio using ambient mode:

   ```./scripts/install-istio.sh ambient```

7. Add the test app to the Istio ambient mesh:

   ```./scripts/update.sh app ambient```

8. Scale up the load generators:

   ```./scripts/scale.sh loadgen 1```

9. Create ambient mTLS performance reports:

   ```./scripts/run-all-reports.sh <unique_report_name>```

10. Scale down the load generators:

    ```./scripts/scale.sh loadgen 0```

11. Apply Istio L4 auth policies:

    ```./scripts/update.sh app ambient l4```

12. Scale up the load generators:

    ```./scripts/scale.sh loadgen 1```

13. Create ambient mTLS+L4 Auth performance reports:

    ```./scripts/run-all-reports.sh <unique_report_name>```

14. Scale down the load generators:

    ```./scripts/scale.sh loadgen 0```

15. Create an ambient waypoint per namespace:

    ```./scripts/update.sh app ambient waypoint```

16. Apply Istio L7 auth policies:

    ```./scripts/update.sh app ambient l7```

17. Create ambient waypoint+L7 Auth performance reports:

    ```./scripts/run-all-reports.sh <unique_report_name>```

18. Scale down the load generators, uninstall Istio, or delete the cluster.

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

- `profile`: The installation profile to use. The only supported option is `ambient`.

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

## Manual Operations

The following are optional manual operations for inspecting the test environment.

### Cluster Node Pool Resizing

If you want to scale up/down the `ng-1` node group:

```bash
eksctl scale nodegroup --cluster ${CLUSTER_NAME} --nodes ${NUM_NODES} --name ng-1
```

Check the status of the scaling:

```bash
eksctl get nodegroup --cluster ${CLUSTER_NAME} --name ng-1
```

### Manual Testing

Exec into a vegeta load generator to run your own test:

```bash
kubectl exec -it deploy/vegeta1 --namespace ns-1 -c vegeta -- /bin/sh
```

Example test run:

```bash
echo "GET http://tier-1-app-a.ns-1.svc.cluster.local:8080" | vegeta attack -dns-ttl=0 -rate 500/1s -duration=2s | tee results.bin | vegeta report -type=text
```

### Istio

Port-forward the waypoint (Envoy) admin endpoint to review configuration, stats, etc. This is useful to confirm traffic
from the load generators is going through waypoints.

```bash
kubectl port-forward deploy/waypoint 15000:15000 -n <namespace>
```

Port-forward the ztunnel admin endpoint to review configuration, stats, etc.

```bash
kubectl port-forward -n istio-system ds/ztunnel 15020:15020
```

## Cleanup

### Delete the Test App or Load Generators

The `scripts/delete.sh <workload_type>` script deletes the 3-tier test app or vegeta load generators and all of
the app's dependencies.

__Arguments:__

- `workload_type`: The type of workload to delete, supported options are `app` for the 3-tier test app and
  `loadgen` for the vegeta load generators.

__Environment Variables:__

`NUM_NS`: The number of namespaced 3-tier test app or vegeta load generators instances, defaults to 1.
