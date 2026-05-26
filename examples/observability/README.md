# Observability with CloudWatch Container Insights

This guide explains how EKS Auto Mode integrates with Amazon CloudWatch Container Insights to provide full-stack observability for your cluster without managing any monitoring infrastructure yourself.

## Prerequisites

- Cluster deployed and `kubectl` configured per [Quick Start](../../README.md#quick-start).
- Terraform installed and AWS credentials configured.

## Deploy

Enable the observability addon:

```bash
terraform -chdir=../../terraform apply -var="enable_observability=true"
```

## What Container Insights Provides

CloudWatch Container Insights delivers observability across three pillars:

**Metrics** — CPU, memory, network, and disk utilization at every level of the hierarchy: cluster, node, pod, and individual container. These metrics are collected at 1-minute intervals and stored in the `ContainerInsights` CloudWatch metrics namespace.

**Logs** — Pod stdout/stderr logs are shipped to CloudWatch Logs automatically. This gives you a centralized, searchable log store without deploying a separate logging stack.

**Application Signals (Distributed Tracing)** — Auto-instrumentation for Java, Python, Node.js, and .NET applications. When enabled, traces flow to CloudWatch Application Signals, giving you service maps, latency percentiles, and error rates across microservices.

## How It Works in Auto Mode

EKS Auto Mode manages the node lifecycle (provisioning, scaling, patching, termination). The `amazon-cloudwatch-observability` EKS addon handles the observability plane:

1. The addon deploys a **CloudWatch agent DaemonSet** on every node. This agent collects container-level metrics and forwards them to CloudWatch Metrics.
2. A **Fluent Bit sidecar** captures pod logs and streams them to CloudWatch Logs.
3. An **OpenTelemetry collector** (optional, via Application Signals) collects traces and sends them to X-Ray/Application Signals.

Because Auto Mode manages nodes and the addon manages observability, you get a fully hands-off monitoring stack. No Helm charts to maintain, no Prometheus to scale, no Fluentd config files to debug.

## What You Get Out of the Box

Once enabled, the following are created automatically:

### CloudWatch Log Groups

| Log Group | Contents |
|-----------|----------|
| `/aws/containerinsights/<cluster>/application` | Pod stdout/stderr logs |
| `/aws/containerinsights/<cluster>/performance` | Cadvisor and kubelet metrics in structured JSON |
| `/aws/containerinsights/<cluster>/dataplane` | Kubelet, kube-proxy, and container runtime logs |
| `/aws/containerinsights/<cluster>/host` | Node-level system logs |

### CloudWatch Metrics Namespace

All metrics land in `ContainerInsights` with dimensions for ClusterName, Namespace, PodName, and ContainerName. Key metrics include:

- `pod_cpu_utilization`, `pod_memory_utilization`
- `node_cpu_utilization`, `node_memory_utilization`
- `pod_network_rx_bytes`, `pod_network_tx_bytes`
- `cluster_node_count`, `cluster_failed_node_count`

### Container Insights Dashboard

The CloudWatch console provides a pre-built Container Insights dashboard at:

```
CloudWatch > Container Insights > Performance monitoring
```

This shows top resource consumers, pod restart trends, and node capacity in a single pane.

## Cost Awareness

CloudWatch Container Insights is metered. Key cost drivers:

| Dimension | Cost Driver | Mitigation |
|-----------|-------------|------------|
| **Metrics** | Custom metrics at $0.30/metric/month (first 10k) | Metrics are per pod/container; large clusters generate many |
| **Logs** | Ingestion at $0.50/GB + storage at $0.03/GB/month | Set log retention policies (default is never-expire) |
| **Traces** | $1.00 per million traces sampled | Use sampling rules to reduce volume |

**Recommendations by environment:**

- **Dev/Staging** — Enable with defaults. Cost is minimal for small clusters. Good learning environment.
- **Production** — Set CloudWatch Logs retention to 30 days. Use metric filters to drop noisy metrics. Configure trace sampling at 5-10% for high-throughput services.
- **Cost-sensitive** — Consider enabling metrics only (disable logs/traces) or use the Enhanced Observability tier selectively.

Set log retention via AWS CLI after deployment:

```bash
CLUSTER=$(terraform -chdir=../../terraform output -raw cluster_name)
REGION=$(terraform -chdir=../../terraform output -raw region)
aws logs put-retention-policy --log-group-name /aws/containerinsights/$CLUSTER/application --retention-in-days 30 --region $REGION
```

## Application Signals (Distributed Tracing)

Application Signals provides auto-instrumentation without code changes. To enable tracing for a workload, add an annotation to your pod spec:

**Java:**
```yaml
metadata:
  annotations:
    instrumentation.opentelemetry.io/inject-java: "true"
```

**Python:**
```yaml
metadata:
  annotations:
    instrumentation.opentelemetry.io/inject-python: "true"
```

**Node.js:**
```yaml
metadata:
  annotations:
    instrumentation.opentelemetry.io/inject-nodejs: "true"
```

**.NET:**
```yaml
metadata:
  annotations:
    instrumentation.opentelemetry.io/inject-dotnet: "true"
```

Once annotated, pods are automatically instrumented on next restart. Traces appear in:

```
CloudWatch > Application Signals > Services
```

You get service maps, latency histograms, error rates, and dependency graphs with zero code changes.

---

## What to Observe

Verify the CloudWatch agent pods are running:

```bash
kubectl get pods -n amazon-cloudwatch
```

Expected output shows `amazon-cloudwatch-observability-controller-manager` and `cloudwatch-agent` DaemonSet pods (one per node).

Confirm metrics are flowing:

```bash
CLUSTER=$(terraform -chdir=../../terraform output -raw cluster_name)
REGION=$(terraform -chdir=../../terraform output -raw region)
aws cloudwatch list-metrics --namespace ContainerInsights --dimensions Name=ClusterName,Value=$CLUSTER --region $REGION
```

Check log groups were created:

```bash
REGION=$(terraform -chdir=../../terraform output -raw region)
aws logs describe-log-groups --log-group-name-prefix /aws/containerinsights/ --region $REGION
```

Once deployed, explore these CloudWatch console paths:

- **Container Insights dashboard:** `CloudWatch > Container Insights > Performance monitoring`
- **Pod logs:** `CloudWatch > Logs > Log groups > /aws/containerinsights/<cluster>/application`
- **Application Signals:** `CloudWatch > Application Signals > Services`
- **Metrics explorer:** `CloudWatch > Metrics > ContainerInsights`

Get the direct console URL:

```bash
terraform -chdir=../../terraform output cloudwatch_dashboard_url
```

## Clean Up

Disable the observability addon:

```bash
terraform -chdir=../../terraform apply -var="enable_observability=false"
```

This removes the CloudWatch agent DaemonSet and controller but does not delete existing log groups or metrics already stored in CloudWatch.
