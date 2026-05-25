# Disruption Budgets

## What disruption budgets are

Disruption budgets limit how many nodes EKS Auto Mode can voluntarily disrupt at once. Without them, a consolidation decision can drain multiple nodes simultaneously, causing cascading failures as pods compete for remaining capacity.

They are defined in `spec.disruption.budgets[]` on a NodePool and act as a throttle on voluntary disruption velocity.

## Prerequisites

Cluster deployed and `kubectl` configured per [Quick Start](../../README.md#quick-start).

## Types of budgets

### Percentage-based

```yaml
budgets:
  - nodes: "10%"
```

At most 10% of nodes managed by this pool can be disrupting at any time. Scales with your fleet -- 100 nodes means max 10 disrupting simultaneously.

### Count-based

```yaml
budgets:
  - nodes: "3"
```

At most 3 nodes disrupting at once, regardless of fleet size. Use for small pools where percentages don't make sense.

### Zero budgets with schedules (maintenance windows)

```yaml
budgets:
  - nodes: "0"
    schedule: "0 9 * * 1-5"
    duration: 8h
```

Block ALL voluntary disruption during business hours (Mon-Fri 09:00-17:00 UTC). Disruption only happens outside this window. This gives you change-window discipline without manual intervention.

### Reason-specific budgets

```yaml
budgets:
  - nodes: "0"
    schedule: "0 9 * * 1-5"
    duration: 8h
    reasons:
      - Drifted
      - Underutilized
```

Scope the budget to specific disruption reasons. This example blocks drift remediation and consolidation during business hours, but still allows empty node removal (cost savings with zero risk).

Valid reasons: `Drifted`, `Underutilized`, `Empty`.

## How overlapping budgets work

When multiple budgets match the current time and disruption reason, the **most restrictive wins**. This lets you layer policies:

1. Baseline: `nodes: "10%"` (always active, caps total disruption)
2. Business hours: `nodes: "0"` for `Underutilized` and `Drifted` (blocks risky disruptions during peak)
3. Maintenance window: `nodes: "33%"` for `Drifted` (opens a wider window on weekends for drift remediation)

At 10am Monday, budgets 1 and 2 both apply. Budget 2 says "0" for Underutilized, so no consolidation happens even though budget 1 would allow 10%.

At 2am Saturday, budgets 1 and 3 apply. Budget 3 says "33%" for Drifted, but budget 1 says "10%" for everything. The 10% cap wins because it is more restrictive.

## Schedule format

Schedules use standard cron syntax (5 fields) with a `duration` that defines how long the budget is active after the cron trigger fires.

```
schedule: "0 9 * * 1-5"   # Fire at 09:00 UTC Monday-Friday
duration: 8h               # Active for 8 hours (until 17:00 UTC)
```

If no `schedule` and `duration` are set, the budget is always active.

## When to use

- **Production clusters** where uncontrolled consolidation causes request failures
- **Compliance environments** requiring change-window discipline
- **Mixed workloads** where some disruption reasons are safe (Empty) but others are risky (Underutilized)
- **Large fleets** where simultaneous node replacement would exhaust IP addresses or ENIs
- **Stateful workloads** where PV reattachment takes time and parallel disruption causes data unavailability

## Deploy

```bash
kubectl apply -f advanced-budgets-nodepool.yaml

# Verify the disruption policy
kubectl get nodepool production-nodepool -o yaml | grep -A 30 disruption
```

## What to observe

```bash
# Check current disruption budget state
kubectl get nodepool production-nodepool -o jsonpath='{.status.disruption}'

# Watch karpenter logs for budget enforcement
kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter -f | grep "budget\|disruption"

# During business hours, verify no consolidation occurs
kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter | grep "blocked by budget"

# During maintenance window, verify drift remediation proceeds
kubectl get nodes --sort-by=.metadata.creationTimestamp
```

## Clean up

```bash
kubectl delete -f .
```
