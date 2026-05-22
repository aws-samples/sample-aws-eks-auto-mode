---
sidebar_position: 7
title: "On-Demand Capacity Reservation (ODCR) Targeting in EKS Auto Mode"
---

# On-Demand Capacity Reservation (ODCR) Targeting in EKS Auto Mode

## What are ODCRs?

On-Demand Capacity Reservations (ODCRs) let you reserve compute capacity in a specific Availability Zone for a specific instance type. Once created, the capacity is held for you regardless of whether any instances are running against it. You pay the on-demand rate for the reserved capacity whether it is used or not, so the goal is to ensure your workloads actually land on the reservation rather than launching as regular on-demand instances beside it.

ODCRs are not the same as Reserved Instances or Savings Plans. Those are billing constructs that apply discounts retroactively. An ODCR is a physical capacity guarantee: the hosts are allocated and waiting for you.

## Why This Matters for ML/GPU Workloads

GPU instance families (p5, g6e, inf2, trn1) are frequently capacity-constrained in popular regions. You may submit a RunInstances call and receive an InsufficientInstanceCapacity error because the AZ is out of that type.

ODCRs solve this by pre-allocating the capacity. However, if your Karpenter/Auto Mode NodeClass does not explicitly target the reservation, launched instances will consume regular on-demand capacity and leave the ODCR idle (still costing you money). Correctly configuring `capacityReservationSelectorTerms` ensures nodes preferentially land on your reserved capacity.

Common scenarios:

- Multi-day distributed training jobs on p5.48xlarge
- Batch inference pipelines with predictable GPU demand
- Real-time inference with guaranteed baseline capacity
- Compliance requirements mandating dedicated or reserved tenancy

## How `capacityReservationSelectorTerms` Works

The NodeClass field `capacityReservationSelectorTerms` tells Auto Mode which ODCRs to target when launching nodes. There are three targeting strategies:

### 1. Target by Reservation ID (most specific)

```yaml
capacityReservationSelectorTerms:
  - id: cr-0a1b2c3d4e5f67890
```

Use this when you have a single known reservation and want deterministic placement.

### 2. Target by Tags (flexible, recommended)

```yaml
capacityReservationSelectorTerms:
  - tags:
      purpose: ml-training
      team: platform
```

Use this when you manage multiple reservations with a tagging convention. As you create or retire ODCRs, the NodeClass automatically picks up matching ones without manifest changes.

### 3. Target by Owner (for shared reservations)

```yaml
capacityReservationSelectorTerms:
  - owner: 123456789012
```

Use this when another account shares ODCRs with you via AWS Resource Access Manager (RAM).

You can combine multiple terms; Auto Mode evaluates them in order and uses the first reservation with available capacity.

## Fallback Behavior

If all matching ODCRs are fully utilized (every slot occupied by a running instance), Auto Mode falls back to launching regular on-demand instances. Your workloads still schedule and run; they simply do not benefit from the reservation guarantee.

This means:

- Pods are never stuck Pending solely because a reservation is full.
- You do not need separate "overflow" NodePools for the non-ODCR case.
- The same NodePool handles both reserved and unreserved launches transparently.

Monitor the `UsedInstanceCount` vs `TotalInstanceCount` in the EC2 Capacity Reservations console to see whether your ODCRs are being utilized.

## When to Use

| Scenario | Why ODCR helps |
|----------|---------------|
| GPU training jobs (multi-hour/day) | Guarantees capacity won't be reclaimed mid-job |
| Batch inference with known parallelism | Ensures all workers launch simultaneously |
| Real-time inference baseline | Baseline capacity is always available; burst goes on-demand |
| Compliance / dedicated tenancy | Some regulations require pre-allocated, non-shared capacity |
| Event-driven spikes (launches, demos) | Reserve ahead, release after the event |

## Prerequisites

1. **An existing ODCR** in the target AZ for the instance type you need.
   Create one via the EC2 console or CLI:
   ```
   aws ec2 create-capacity-reservation --instance-type g6e.xlarge --instance-platform Linux/UNIX --availability-zone us-west-2a --instance-count 4 --tag-specifications 'ResourceType=capacity-reservation,Tags=[{Key=purpose,Value=ml-training}]'
   ```
   See [AWS docs: Create a Capacity Reservation](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-capacity-reservations.html#capacity-reservations-create) for full options.

2. **Appropriate IAM permissions** on the node role to describe and use capacity reservations:
   - `ec2:DescribeCapacityReservations`
   - `ec2:RunInstances` with the reservation target

3. **Matching AZ and instance type** between the ODCR and the NodePool requirements. Auto Mode will not launch a g6e instance into a p5 reservation.

4. **Tags on the ODCR** if using tag-based selector terms (recommended for flexibility).

## Deploy

1. Render the template with your cluster values:
   ```
   terraform output -raw odcr_nodepool_manifest > odcr-nodepool.yaml
   ```
   Or substitute the variables manually in `odcr-nodepool.yaml.tpl`.

2. Apply to your cluster:
   ```
   kubectl apply -f odcr-nodepool.yaml
   ```

3. Launch a GPU workload that tolerates the `nvidia.com/gpu` taint:
   ```yaml
   tolerations:
     - key: "nvidia.com/gpu"
       operator: Equal
       value: "true"
       effect: NoSchedule
   resources:
     limits:
       nvidia.com/gpu: 1
   ```

## What to Observe

1. **EC2 Console > Capacity Reservations**: Watch `Used instance count` increase as Auto Mode launches nodes into the reservation.

2. **Node labels**: Nodes launched into an ODCR carry standard EC2 metadata. Check instance details:
   ```
   aws ec2 describe-instances --instance-ids <id> --query 'Reservations[].Instances[].CapacityReservationId'
   ```

3. **NodePool counters**: Verify the NodePool's resource usage is increasing:
   ```
   kubectl get nodepool odcr-gpu-nodepool -o yaml | grep -A5 status
   ```

4. **Fallback scenario**: If you scale beyond the reservation size, additional nodes will launch as regular on-demand. The `CapacityReservationId` field will be empty on those instances.

## Cleanup

To release ODCR capacity when no longer needed:

1. Scale down or delete workloads using the GPU taint.
2. Delete the NodePool and NodeClass: `kubectl delete nodepool odcr-gpu-nodepool && kubectl delete nodeclass odcr-gpu-nodeclass`
3. Cancel the capacity reservation: `aws ec2 cancel-capacity-reservation --capacity-reservation-id cr-0a1b2c3d4e5f67890`
