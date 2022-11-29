# Deploy Kueue with Cohorts and Resource Sharing

This tutorial further showcases features of Kueue with cohorts, and how ClusterQueues under the same cohort can share quotas and maximize utilization. 

## Objective

This tutorial is for application operators and other users that want to implement a Job queueing system on Kubernetes using Kueue, and also use multiple resource types or have a flexible quota system for Job queueing. 

This tutorial covers the following steps:

1. Create a GKE cluster
1. Create the ResourceFlavor
1. Create the ClusterQueue and LocalQueue
1. Deploy Prometheus to monitor Kueue
1. Observe and Generate Jobs to Kueue
1. Cohort Sharing
1. Clean up
1. Next steps

This tutorial uses Google Cloud Platform (GCP) and Google Kubernetes Engine (GKE).

## Before you begin

### Set up your project

1. In the Google Cloud console, on the project selector page, click Create project to begin creating a new Google Cloud project.

1. Make sure that billing is enabled for your Cloud project. Learn how to check if billing is enabled on a project.

1. Enable the GKE API.

1. The Kubernetes cluster version is 1.21 or newer.

## Create a GKE Cluster

1. Create a GKE Standard cluster named `kueue-standard`:

    ```sh
    gcloud container clusters create kueue-standard --region us-central1 \
    --machine-type e2-standard-4 --release-channel rapid --cluster-version 1.24 \
    --num-nodes 1 --node-labels spot=false --enable-autoscaling --max-nodes=10 \
    --autoscaling-profile optimize-utilization
    ```

    Note: Cluster creation can take up to 5 minutes.

1. Create a node pool named `spot` where it will be used as a spot VM:

    ```
    gcloud container node-pools create spot --cluster=kueue-standard --region us-central1 \
    --node-labels spot=true --spot --enable-autoscaling --max-nodes=20 --num-nodes=0 \
    --machine-type e2-standard-4
    ```

    Note: The node label is set to spot=true to configure matching node labels in ResourceFlavor

1. Install the release version of Kueue to the cluster:

    ```sh
    VERSION=v0.2.1
    kubectl apply -f https://github.com/kubernetes-sigs/kueue/releases/download/$VERSION/manifests.yaml
    ```

    Stay up to date on the version of Kueue [here](https://github.com/kubernetes-sigs/kueue/releases).

1. Allow prometheus-operator to scrape metrics from Kueue components:

    ```sh
    kubectl apply -f https://github.com/kubernetes-sigs/kueue/releases/download/$VERSION/prometheus.yaml
    ```

1. Create two new namespaces called `team-a` and `team-b`, and `monitoring` for Prometheus monitoring:

    ```sh
    kubectl create namespace team-a
    kubectl create namespace team-b
    kubectl create namespace monitoring
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
  name: on-demand # This ResourceFlavor will be used for the CPU resource
  labels:
    spot: "false"
---
apiVersion: kueue.x-k8s.io/v1alpha2
kind: ResourceFlavor
metadata:
  name: spot # This ResourceFlavor will be used as added resource for the CPU resource
  labels:
    spot: "true"
```

The ResourceFlavor `on-demand` has its label set to `spot=false` so it will not use the node pool `spot`. Where the ResourceFlavor `spot` has its label set to `spot=true` so Kueue will configure the labels with matching node labels. 

A ResourceFlavor can use node labels and taints to differentiate between different VMs (e.g. spot vs on-demand), architectures (e.g. x86 vs ARM CPUs), brands and models (e.g. Nvidia A100 vs T4 GPUs). 

Deploy the ResourceFlavor:

```sh
kubectl apply -f flavors.yaml
```

## Create the ClusterQueue and LocalQueue

Create 2 ClusterQueues `team-a-cq` and `team-b-cq`, and its corresponding LocalQueues `team-a-lq` and `team-b-lq`. 

```yaml
apiVersion: kueue.x-k8s.io/v1alpha2
kind: ClusterQueue
metadata:
  name: team-a-cq
spec:
  cohort: all # team-a-cq and team-b-cq share the same cohort
  namespaceSelector: {}
  resources:
  - name: "cpu"
    flavors:
    - name: on-demand
      quota:
        max: 15
        min: 10
    - name: spot # The spot resource is not used for now
      quota:
        min: 0
  - name: "memory"
    flavors:
    - name: on-demand
      quota:
        min: 36Gi
---
apiVersion: kueue.x-k8s.io/v1alpha2
kind: LocalQueue
metadata:
  namespace: team-a
  name: team-a-lq
spec:
  clusterQueue: team-a-cq
```

ClusterQueues allows resources to have multiple flavors, in this case both ClusterQueues have a resource called `cpu` which has 2 flavors: `on-demand` and `spot`. The ResourceFlavor `spot`'s quota is set to 0, and will not be used for now.

Both ClusterQueues share the same cohort `all` shown in `.spec.cohort`. When a ClusterQueues share the same cohort, they can borrow unused quota from each other. 

To restrict the amount of quota a ClusterQueue can share, set the max quota for a resource flavor to equal or greater than `min`. We currently set the `.spec.resources.flavors.quota.max` to 15, which means the ClusterQueue can only borrow up to 15. 

Deploy the ClusterQueues:

```sh
kubectl apply -f team-a-cq.yaml
kubectl apply -f team-b-cq.yaml
```


## Deploy Prometheus to monitor Kueue

Use Prometheus to monitor Kueue pending workloads and active workloads.

1. Create the CRDs for Prometheus

    ```sh
    kubectl create -f Prometheus/setup
    ```

1. Create the remaining resources

    ```sh
    kubectl create -f Prometheus
    ```

1. Access Prometheus by port forwarding the service onto [localhost:9090](localhost:9090)

    ```sh
    kubectl --namespace monitoring port-forward svc/prometheus-k8s 9090
    ```

1. Open Prometheus on [localhost:9090](localhost:9090) in the browser

1. Enter the query for the first panel that monitors the active ClusterQueue `team-a-cq`

    ```sh
    kueue_pending_workloads{cluster_queue="team-a-cq", status="active"} or kueue_admitted_active_workloads{cluster_queue="team-a-cq"}
    ```

1. Add another panel and enter the query that monitors the active ClusterQueue `team-b-cq`

    ```sh
    kueue_pending_workloads{cluster_queue="team-b-cq", status="active"} or kueue_admitted_active_workloads{cluster_queue="team-b-cq"}
    ```

## Observe and Generate Jobs to Kueue

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  namespace: team-a
  generateName: sample-job-
  annotations:
    kueue.x-k8s.io/queue-name: team-a-lq
spec:
  ttlSecondsAfterFinished: 60
  parallelism: 3
  completions: 3
  suspend: true
  template:
    spec:
      containers:
      - name: dummy-job
        image: gcr.io/k8s-staging-perf-tests/sleep:latest
        args: ["10s"] # Sleep for 10 seconds
        resources:
          requests:
            cpu: "1"
            memory: "1Gi"
      restartPolicy: Never
```

Generate Jobs to both ClusterQueues that will sleep for 10 seconds, with 3 paralleled Jobs and will be completed with 3 completions. It will then be cleaned up after 60 seconds.

`team-a-job.yaml` will create Jobs under the namespace `team-a` and points to the LocalQueue `team-a-lq` and the ClusterQueue `team-a-cq`. 

Similarly, `team-b-job.yaml` creates Jobs under `team-b` namespace, and points to the LocalQueue `team-b-lq` and the ClusterQueue `team-b-cq`.

1. Start a new terminal, this script will generate a Job every 3 seconds:

    ```sh
    ./create_jobs.sh team-a-job.yaml 3
    ```

1. Start another terminal and create Jobs for the beta namespace:

    ```sh
    ./create_jobs.sh team-b-job.yaml 3
    ```

1. Observe the Jobs being queued up in Prometheus

## Cohort Sharing

1. Once there are some Jobs queued up for both ClusterQueues where the admitted workloads , stop the script for the `team-b` namespace by pressing `CTRL+c`. Once all the pending Jobs from the namespace `team-b` are processed, observe how more Jobs from the namespace `team-a` are admitted.

    Since `team-a-cq` and `team-b-cq` share the same cohort called `all`, these ClusterQueues are able to share resources that are not shared. 

1. Resume the script for the `team-b` namespace

    ```sh
    ./create_jobs.sh team-b-job.yaml 3s
    ```

1. Create a new ClusterQueue called `spot-cq` with cohort set to `all`

    ```yaml
    apiVersion: kueue.x-k8s.io/v1alpha2
    kind: ClusterQueue
    metadata:
    name: spot-cq
    spec:
    cohort: all
    namespaceSelector: {}
    resources:
    - name: "cpu"
        flavors:
        - name: spot
        quota:
            min: 40
    - name: "memory"
        flavors:
        - name: default
        quota:
            min: 144Gi
    ```

    ```sh
    kubectl apply -f spot-cq.yaml
    ```

1. Observe in Prometheus how the admitted workloads spike for both `team-a-cq` and `team-b-cq` thanks to the added quota by `spot-cq` who shares the same cohort.

1. Stop both scripts by pressing `CTRL+c` for `team-a` and `team-b` namespace. 


## Clean Up

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
* To get started on Kueue, see [Deploy a simple Kueue deployment]().
