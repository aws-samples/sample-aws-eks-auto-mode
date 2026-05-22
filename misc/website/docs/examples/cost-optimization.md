---
sidebar_position: 5
title: "Cost Optimization Patterns for EKS Auto Mode"
---

# Cost Optimization Patterns for EKS Auto Mode

This example demonstrates two key cost optimization patterns: **OD/Spot mixed capacity** and **overprovision headroom via pause pods**.

---

## Why OD/Spot Split Matters

EC2 Spot instances are 60-90% cheaper than On-Demand, but AWS can reclaim them with 2 minutes notice. For production workloads you need a mix:

- **On-Demand** provides a stable baseline that won't disappear mid-request.
- **Spot** provides cheap burst capacity for stateless, fault-tolerant work.

EKS Auto Mode (via Karpenter) labels nodes with `karpenter.sh/capacity-type: on-demand` or `karpenter.sh/capacity-type: spot`. You use topology spread constraints to distribute pods across both capacity types evenly.

---

## How Topology Spread Constraints Work

```yaml
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: karpenter.sh/capacity-type
    whenUnsatisfiable: DoNotSchedule
    labelSelector:
      matchLabels:
        app: web-mixed-capacity
```

| Field | Meaning |
|-------|---------|
| `maxSkew` | Maximum allowed difference in pod count between any two topology domains. A skew of 1 means "at most 1 pod difference between OD and Spot." |
| `topologyKey` | The node label that defines topology domains. Using `karpenter.sh/capacity-type` creates two domains: `on-demand` and `spot`. |
| `whenUnsatisfiable` | `DoNotSchedule` blocks new pods if they'd violate the skew (hard constraint). `ScheduleAnyway` is a soft preference. |
| `labelSelector` | Which pods count toward the spread calculation. Must match the pod's own labels. |

With 6 replicas and maxSkew 1, you get 3 pods on OD nodes and 3 on Spot nodes. If a Spot node is reclaimed, you still have 3 OD pods serving traffic while replacements schedule.

---

## What Overprovision / Headroom Is

When a new pod arrives and no node has capacity, EKS Auto Mode launches a new node. That takes 1-2 minutes. For latency-sensitive scale-out, that delay is unacceptable.

**Overprovision** solves this by keeping spare capacity pre-warmed. You run low-priority "pause" pods that reserve CPU and memory on nodes but do nothing. When a real workload arrives, the scheduler **preempts** the pause pods instantly, giving the real pod immediate access to already-running node capacity.

The pause pods use the `registry.k8s.io/pause:3.9` image — a 500KB container that literally does nothing except hold a resource reservation.

---

## How PriorityClasses and Preemption Work Together

```
PriorityClass "pause-pods"  → value: -1  (lowest)
Default priority            → value:  0  (all normal workloads)
```

The scheduler always prefers higher-priority pods. When a real pod (priority 0) cannot be scheduled due to lack of resources, the scheduler looks for lower-priority pods it can evict. The pause pods at priority -1 are always the first victims.

The flow:
1. Pause pods hold 3 x (1 CPU + 1Gi memory) of headroom on nodes.
2. A real deployment scales up and needs resources.
3. Scheduler evicts pause pods (instant — `terminationGracePeriodSeconds: 0`).
4. Real pods land immediately on the freed capacity.
5. The now-pending pause pods trigger new node creation in the background, restoring headroom.

---

## When to Use Each Pattern

| Pattern | Use case |
|---------|----------|
| **OD/Spot split** | Stateless HTTP services, batch processors, queue workers — anything that tolerates pod replacement gracefully. |
| **Overprovision headroom** | Latency-sensitive scale-out where waiting 1-2 min for a node is unacceptable: real-time APIs, gaming backends, autoscaled inference endpoints. |

You can combine both — run pause pods on Spot capacity so your headroom is cheap, while real workloads spread across OD and Spot.

---

## Deploy

```bash
kubectl apply -f examples/cost-optimization/mixed-od-spot-deployment.yaml
kubectl apply -f examples/cost-optimization/overprovision-pause-pods.yaml
```

---

## What to Observe

**For the OD/Spot split deployment:**

```bash
# Check that pods spread across capacity types
kubectl get pods -n cost-optimization -l app=web-mixed-capacity -o wide

# Verify nodes have different capacity types
kubectl get nodes -L karpenter.sh/capacity-type

# Count pods per capacity type
kubectl get pods -n cost-optimization -l app=web-mixed-capacity -o json | \
  jq -r '.items[].spec.nodeName' | \
  xargs -I{} kubectl get node {} -o jsonpath='{.metadata.labels.karpenter\.sh/capacity-type}' | \
  sort | uniq -c
```

**For overprovision/headroom:**

```bash
# Verify pause pods are running and holding resources
kubectl get pods -n cost-optimization -l app=overprovision

# Check their priority class
kubectl get pods -n cost-optimization -l app=overprovision -o jsonpath='{.items[0].spec.priorityClassName}'

# Watch preemption in action — scale a real workload and observe events
kubectl get events -n cost-optimization --field-selector reason=Preempted -w

# Measure scheduling latency (time from creation to running)
kubectl get pods -n cost-optimization -o json | \
  jq '.items[] | select(.status.phase=="Running") | .metadata.name + ": " + (.status.conditions[] | select(.type=="PodScheduled") | .lastTransitionTime)'
```
