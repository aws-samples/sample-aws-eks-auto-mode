# Batch Jobs: Protecting Long-Running Workloads from Disruption

## The problem

Karpenter (and EKS Auto Mode) continuously consolidates underutilized nodes. This is great for cost optimization, but catastrophic for long-running batch jobs. A 6-hour ML training run evicted at hour 5 wastes 5 hours of GPU compute. An ETL pipeline disrupted mid-write can leave data in an inconsistent state.

Without protection, consolidation treats your 8-hour training job the same as a stateless web server -- just another pod to reschedule.

## Prerequisites

Cluster deployed and `kubectl` configured per [Quick Start](../../README.md#quick-start).

## How `karpenter.sh/do-not-disrupt` works

Adding this annotation to a pod's metadata tells Auto Mode: "do not voluntarily evict this pod for consolidation or drift remediation."

```yaml
metadata:
  annotations:
    karpenter.sh/do-not-disrupt: "true"
```

When this annotation is present on any pod running on a node, that entire node becomes protected from voluntary disruption. The node will not be consolidated, drifted, or removed for emptiness as long as the annotated pod is running.

## Scope of protection

| Disruption Type | Protected? | Example |
|----------------|-----------|---------|
| Consolidation (underutilized) | Yes | Karpenter wants to bin-pack pods onto fewer nodes |
| Drift remediation | Yes | AMI updated, Karpenter wants to roll nodes |
| Empty node removal | Yes | All other pods drained, but annotated pod remains |
| Spot interruption | **No** | AWS reclaims the instance with 2-min warning |
| Node health failure | **No** | EC2 status check fails |
| Manual `kubectl drain` | **No** | Human or automation explicitly drains |

**Key insight**: this protects against the scheduler's optimization decisions, not against infrastructure failures. For Spot protection, use on-demand instances. For health failures, implement checkpointing.

## Why annotation vs taint

These solve different problems:

- **Taints** control which pods CAN schedule onto a node (admission control)
- **do-not-disrupt** controls whether a node with this pod CAN be consolidated (eviction control)

A GPU taint prevents CPU pods from landing on GPU nodes. `do-not-disrupt` prevents Karpenter from evicting your training job to consolidate that GPU node.

## When to use

- ML training jobs (hours to days)
- ETL pipelines with expensive restart costs
- Video transcoding (long-running, stateful progress)
- Database migrations or backfills
- Any batch workload where: **restart cost > idle node cost**

## Deploy

Apply the GPU NodePool (required -- the training job tolerates `nvidia.com/gpu` and requests a GPU):

```bash
kubectl apply -f ../../nodepools/gpu-nodepool.yaml
```

Deploy the batch training job:

```bash
kubectl apply -f batch-training-job.yaml
```

Verify the job is running:

```bash
kubectl get jobs -n batch-jobs
kubectl get pods -n batch-jobs -o wide
```

## What to observe

Confirm the annotation is on the running pod:

```bash
kubectl get pod -n batch-jobs -l app=ml-training -o jsonpath='{.items[0].metadata.annotations}'
```

Watch Karpenter logs for "cannot disrupt" messages on the protected node:

```bash
kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter -f | grep "cannot disrupt\|do-not-disrupt"
```

Identify which node the job landed on:

```bash
NODE=$(kubectl get pod -n batch-jobs -l app=ml-training -o jsonpath='{.items[0].spec.nodeName}') && echo "Protected node: $NODE"
```

Verify that node is NOT being considered for consolidation:

```bash
kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter | grep "$NODE"
```

Once the job completes the annotation disappears with the pod and the node becomes eligible for consolidation again. Watch node lifecycle:

```bash
kubectl get nodes -w
```

## Clean up

```bash
kubectl delete -f batch-training-job.yaml
kubectl delete -f ../../nodepools/gpu-nodepool.yaml
```
