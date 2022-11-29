`# Deploy a simple Kueue deployment

This tutorial shows how to set up Kueue to perform Job queueing in Kubernetes. Follow this tutorial to learn the basics on what Kueue aims to achieve. 

## Background

Kueue is a new set of APIs that handle Job queueing and elastic quota management. It is a Job level manager that decides when a job should be admitted to start, and when to stop. Kueue does not re-implement existing functionality like autoscaling, pod scheduling and job lifecycle management. It supports native batch/v1.job API and integrates custom workloads. Kueue is a slim implementation that reuses the maximum of the K8S core, and has full compatibility with the ecosystem. 

As an application operator or an application developer, Kueue manages Jobs and properly queues them. Kueue can facilitate workloads that use machine learning, training, and rendering. 

## Objective

This tutorial is for application operators and other users that want to implement a Job queueing system on Kubernetes using Kueue.

This tutorial covers the following steps:

1. Create a GKE cluster
1. Create a ResourceFlavor
1. Create a ClusterQueue
1. Create a LocalQueue
1. Observe the Job
1. Observe the admitted workloads 

This tutorial uses Google Cloud Platform (GCP) and Google Kubernetes Engine (GKE).

## Before you begin

### Set up your project

1. In the Google Cloud console, on the project selector page, click Create project to begin creating a new Google Cloud project.

1. Make sure that billing is enabled for your Cloud project. Learn how to check if billing is enabled on a project.

1. Enable the GKE API.

1. The Kubernetes cluster version is 1.21 or newer.

### Create a GKE Cluster

1. Create a GKE Autopilot cluster named `kueue-autopilot`:

    ```sh
    gcloud container clusters create-auto kueue-autopilot --region us-central1
    ```

    Note: Cluster creation can take up to 10 minutes.

    GKE Autopilot allows node pool autoscaling where node pools get created on demand, and will provision the necessary resources for the node pool. 

1. Install the release version of Kueue to the cluster:

    ```sh
    VERSION=v0.2.1
    kubectl apply -f https://github.com/kubernetes-sigs/kueue/releases/download/$VERSION/manifests.yaml
    ```

    Stay up to date on the version of Kueue [here](https://github.com/kubernetes-sigs/kueue/releases).

1. Create two new namespaces called `team-a` and `team-b`:

    ```sh
    kubectl create namespace team-a
    kubectl create namespace team-b
    ```

    Jobs will be generated on each namespace.

## Create the ResourceFlavor

```yaml
apiVersion: kueue.x-k8s.io/v1alpha2
kind: ResourceFlavor
metadata:
  name: default # This ResourceFlavor will be used for the memory resource
---
apiVersion: kueue.x-k8s.io/v1alpha2
kind: ResourceFlavor
metadata:
  name: render # This ResourceFlavor will be used for the GPU resource
---
apiVersion: kueue.x-k8s.io/v1alpha2
kind: ResourceFlavor
metadata:
  name: on-demand # This ResourceFlavor will be used for the CPU resource
---
apiVersion: kueue.x-k8s.io/v1alpha2
kind: ResourceFlavor
metadata:
  name: storage # This ResourceFlavor will be used for the ephemeral-storage resource
```

A ResourceFlavor is an object that represents the resource variations and allows you to associate them with node labels and taints. Use ResourceFlavors to differentiate between different VMs (e.g. spot vs on-demand), architectures (e.g. x86 vs ARM CPUs), brands and models (e.g. Nvidia A100 vs T4 GPUs). 

We will create ResourceFlavors for memory, GPU, CPU, and ephemeral-storage. 

Deploy the ResourceFlavor:

```sh
kubectl apply -f flavors.yaml
```

## Create the ClusterQueue

```yaml
apiVersion: kueue.x-k8s.io/v1alpha2
kind: ClusterQueue
metadata:
  name: cq
spec:
  namespaceSelector: {}
  queueingStrategy: BestEffortFIFO # Default queueing strategy
  resources:
  - name: "cpu"
    flavors:
    - name: on-demand
      quota:
        min: 10
  - name: "memory"
    flavors:
    - name: default
      quota:
        min: 10Gi
  - name: "nvidia.com/gpu"
    flavors:
    - name: render
      quota:
        min: 10
  - name: "ephemeral-storage"
    flavors:
    - name: storage
      quota:
        min: 5Gi
```

A ClusterQueue is a cluster-scoped object that governs a pool of resources such as CPU, memory, GPU. It manages the ResourceFlavors, and limits the usage and order of consumption. 

The order of consumption is determined by `.spec.queueingStrategy`, where the default is set to `BestEffortFIFO`, where it follows the first in first out (FIFO) rule, but older workloads that can't be admitted will not block newer workloads. Where `StrictFIFO` follows priority, then `.metadata.creationTimestamp`.

In `cluster-queue.yaml`, we create a new ClusterQueue called `cq`. This ClusterQueue will use 4 resources, `cpu`, `memory`, `nvidia.com/gpu` and `ephemeral-storage` with flavors created in `flavors.yaml` which also matches the request in the Pod spec. 

Each flavor includes usage limits represented as `.spec.resources.flavors.quota.min`. In this case, the ClusterQueue admits workloads if and only if 

* the sum of the CPU requests is less than or equal to 10
* the sum of the memory requests is less than or equal to 10Gi
* the sum of GPU requests is less than or equal to 10
* the sum of the storage used is less than or equal to 5Gi

Deploy the ClusterQueue:

```sh
kubectl apply -f cluster-queue.yaml
```

## Create the LocalQueue

```yaml
apiVersion: kueue.x-k8s.io/v1alpha2
kind: LocalQueue
metadata:
  namespace: team-a # LocalQueue under team-a namespace
  name: team-a-lq
spec:
  clusterQueue: cq # Point to the ClusterQueue cq
---
apiVersion: kueue.x-k8s.io/v1alpha2
kind: LocalQueue
metadata:
  namespace: team-b # LocalQueue under team-b namespace
  name: team-b-lq
spec:
  clusterQueue: cq # Point to the ClusterQueue cq
```

A LocalQueue is a namespaced object that groups closely related workloads belonging to a single tenant. LocalQueues from different namespaces can point to the same ClusterQueue, in this case, LocalQueue from namespace `team-a` and `team-b` points to the same ClusterQueue `cq` under `.spec.clusterQueue`. 

Jobs are sent to the LocalQueue instead of the ClusterQueue, which are then allocated resources by the ClusterQueue. 

Deploy the LocalQueue:

```sh
kubectl apply -f local-queue.yaml
```

## Observe the Job

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  namespace: team-a # Job under team-a namespace
  generateName: sample-job-
  annotations:
    kueue.x-k8s.io/queue-name: team-a-lq # Point to the LocalQueue
spec:
  ttlSecondsAfterFinished: 60 # Job will be deleted after 60 seconds
  parallelism: 3 # This Job will have 3 replicas running at the same time
  completions: 3 # This Job requires 3 completions
  suspend: true
  template:
    spec:
      nodeSelector:
        cloud.google.com/gke-accelerator: "nvidia-tesla-t4" # Specify the GPU hardware
      containers:
      - name: dummy-job
        image: gcr.io/k8s-staging-perf-tests/sleep:latest
        args: ["10s"] # Sleep for 10 seconds
        resources:
          requests:
            cpu: "1"
            memory: "100Mi"
            ephemeral-storage: "100Mi"
            nvidia.com/gpu: "1"
          limits:
            nvidia.com/gpu: "1"
      restartPolicy: Never
```

This [Job](https://kubernetes.io/docs/concepts/workloads/controllers/job/) will be created under the namespace `team-a`. This Job points to the LocalQueue `team-a-lq`, and in order to request GPU resources, `nodeSelector` is set to `nvidia-tesla-t4`. 

The Job will sleep for 10 seconds, with 3 paralleled Jobs and will be completed with 3 completions. It will then be cleaned up after 60 seconds indicated by `ttlSecondsAfterFinished`.

This Job will require 1 CPU request, 100Mi of memory, 100Mi of ephemeral storage, and 1 GPU request. 

We will also create another Job named `team-b-job.yaml` where it's namespace will be in `team-b`, with slightly different requests to represent different teams with different needs. 

Note: Learn more information on [deploying GPU workloads in Autopilot](https://cloud.google.com/kubernetes-engine/docs/how-to/autopilot-gpus)


## Observe the admitted workloads

1. Start a new terminal and observe the status of the ClusterQueue 

    ```sh
    watch -n 2 kubectl get clusterqueue cq -o wide
    ```

1. Start a new terminal and observe the status of the nodes

    ```sh
    watch -n 2 kubectl get nodes -o wide
    ```

1. Start another terminal, create Jobs to LocalQueue from namespace `team-a` and `team-b` every 10 seconds

    ```sh
    ./create_jobs.sh team-a-job.yaml team-b-job.yaml 10s
    ```

1. Observe the Jobs being queued up and nodes being brought up with GKE Autopilot 

    Note: It is normal to see the error message `Unschedulable` on the Workload while pods are scaling up.

1. When the pending workloads start increasing from the ClusterQueue, end the script by pressing `CTRL + C` on the running script.

1. Once all Jobs are completed, notice the nodes being scaled down

## Clean up

1. Uninstall Kueue from the cluster

    ```sh
    VERSION=v0.2.0
    kubectl delete -f https://github.com/kubernetes-sigs/kueue/releases/download/$VERSION/manifests.yaml
    ```

1. Uninstall Prometheus from the cluster

    ```sh
    kubectl delete -f Prometheus/setup
    kubectl delete -f Prometheus
    ```

1. Or delete the GKE cluster

    ```sh
    gcloud container clusters delete kueue-cluster
    ```

## Next Steps

* [Multiple resource-type ClusterQueues using Kueue]()
* Contribute to the [Kueue Github repo](kueue.sh)

`