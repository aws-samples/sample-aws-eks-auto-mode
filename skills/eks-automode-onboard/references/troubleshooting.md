# EKS Auto Mode -- Troubleshooting

Common issues encountered when first deploying and operating an EKS Auto Mode cluster.

## Pods stuck Pending

### Symptoms

Pod stays in `Pending` state. `kubectl describe pod` shows:
```
Events:
  Warning  FailedScheduling  ... 0/0 nodes are available: ...
```

No NodeClaim is created, or a NodeClaim is created but no node appears.

### Diagnosis

```bash
# Check if any NodePool matches the pod's requirements
kubectl get nodepools -o yaml | grep -A 20 'requirements:'

# Check pod's nodeSelector and affinity
kubectl get pod <name> -n <ns> -o jsonpath='{.spec.nodeSelector}'
kubectl get pod <name> -n <ns> -o jsonpath='{.spec.affinity}'

# Look for NodeClaims (Karpenter's intent to launch)
kubectl get nodeclaims
```

### Common causes

1. **Missing `eks.amazonaws.com/compute-type: auto` label match** -- if your NodePool
   has this requirement but the pod doesn't select it (or vice versa).

2. **Architecture mismatch** -- pod image is amd64-only but NodePool only allows
   arm64 (or vice versa). Check `kubernetes.io/arch` in requirements.

3. **No NodePool allows the requested instance type** -- if your pod uses
   `node.kubernetes.io/instance-type` in nodeSelector, a NodePool must include that
   family in its requirements.

4. **Resource requests exceed largest allowed instance** -- a pod requesting 512Gi
   memory with a NodePool limited to M5 family (max 384 GiB) can never schedule.

5. **Taint without toleration** -- NodePool applies taints that the pod doesn't
   tolerate.

### Fix

Ensure at least one NodePool's requirements are a superset of the pod's scheduling
constraints. If you are unsure, remove the nodeSelector temporarily and see if the
pod schedules.

## Node not joining the cluster

### Symptoms

A NodeClaim exists and shows `Launched` but never transitions to `Registered`.
No corresponding Node appears in `kubectl get nodes`.

### Diagnosis

```bash
# Check NodeClaim status
kubectl describe nodeclaim <name>

# Look for the EC2 instance
aws ec2 describe-instances --filters "Name=tag:karpenter.sh/nodeclaim,Values=<name>" --query 'Reservations[].Instances[].{ID:InstanceId,State:State.Name}'

# Check CloudTrail for IAM errors
aws cloudtrail lookup-events --lookup-attributes AttributeKey=EventName,AttributeValue=RunInstances --max-results 5
```

### Common causes

1. **IAM role issues** -- the node role is missing required managed policies
   (`AmazonEKSWorkerNodeMinimalPolicy`, `AmazonEKSAutoNodePolicy`). Check CloudTrail
   for `AccessDenied` or `UnauthorizedOperation` on RunInstances.

2. **Security group blocks kubelet** -- the node security group must allow egress to
   the EKS API server endpoint (port 443). In private clusters, VPC endpoints are
   required.

3. **Subnet has no available IPs** -- the subnet selected by the NodeClass is
   exhausted. Check `aws ec2 describe-subnets` for available IP count.

4. **Instance launch failed** -- InsufficientInstanceCapacity in the selected AZ.
   Karpenter retries with other instance types/AZs if the NodePool allows diversity.

### Fix

For IAM issues, verify the node role in the EKS console under "Access" tab. The
module in this repo configures IAM correctly by default; if you modified roles
manually, compare against the module's output.

## Tags not landing on resources

### Symptoms

EC2 instances, EBS volumes, or ALBs appear without your custom tags. CloudTrail may
show `UnauthorizedOperation` errors.

### Diagnosis

```bash
# Check CloudTrail for tag-related denials
aws cloudtrail lookup-events --lookup-attributes AttributeKey=EventName,AttributeValue=RunInstances --query 'Events[?contains(CloudTrailEvent, `UnauthorizedOperation`)].CloudTrailEvent' --max-results 3

# Verify IAM policy exists on cluster role
aws iam list-attached-role-policies --role-name <cluster-node-role-name>
```

### 5 common reasons

1. **Missing IAM custom-tags policy** -- the managed policies only allow `eks:*`,
   `kubernetes.io/*`, and `karpenter.sh/*` tag keys. Custom keys require
   `enable_auto_mode_custom_tags=true` in the EKS module (this repo sets it by default).

2. **Editing the managed `default` NodeClass** -- adding `spec.tags` to the default
   NodeClass reverts silently. Create a custom NodeClass instead.

3. **StorageClass parameters are immutable** -- changing `tagSpecification` on an
   existing StorageClass requires delete + recreate. `kubectl apply` on changed
   params silently fails or errors.

4. **Tags only apply to future resources** -- existing EC2/EBS/ALB resources keep
   their original tags. Retag imperatively with `aws ec2 create-tags` or
   `aws elbv2 add-tags`.

5. **NodePool doesn't reference the custom NodeClass** -- if `nodeClassRef.name`
   still points to `default`, your custom NodeClass tags are ignored.

### Fix

Verify `enable_auto_mode_custom_tags=true` in `terraform/eks.tf`, ensure your
NodePool references the correct custom NodeClass, and run `terraform apply` to
reconcile. See `claude-md/TAGGING.md` for the full 5-layer tagging guide.

## Load balancer not provisioning

### Symptoms

Ingress or Service of type LoadBalancer stays without an ADDRESS. Events show
errors about subnet discovery or permissions.

### Diagnosis

```bash
# Check Ingress events
kubectl describe ingress <name> -n <ns>

# Check Service events (for NLB)
kubectl describe svc <name> -n <ns>

# Verify subnet tags
aws ec2 describe-subnets --filters "Name=vpc-id,Values=<vpc-id>" --query 'Subnets[].[SubnetId,Tags[?Key==`kubernetes.io/role/elb`]]'
```

### Common causes

1. **Missing subnet tags** -- ALB controller discovers subnets by tags:
   - Public subnets: `kubernetes.io/role/elb: "1"`
   - Private subnets: `kubernetes.io/role/internal-elb: "1"`
   
   This repo adds these automatically. Custom VPCs must add them manually.

2. **IngressClass not found** -- the Ingress must specify
   `spec.ingressClassName: alb` (or use the `kubernetes.io/ingress.class` annotation).

3. **NLB missing loadBalancerClass** -- for Auto Mode NLBs, the Service must set
   `spec.loadBalancerClass: eks.amazonaws.com/nlb`.

4. **IngressClassParams misconfigured** -- if you created custom IngressClassParams,
   verify the scheme (internet-facing vs internal) and subnet selection.

5. **Security group limits** -- VPC has a default limit of 2500 security group rules.
   Many ALBs + many target groups can exhaust this.

### Fix

For this repo specifically, ensure you ran `terraform apply` successfully (it
creates IngressClass + IngressClassParams). If using `base_domain`, the ALB scheme
switches to internet-facing automatically.

## Storage class issues

### Symptoms

PVCs stay `Pending`. Events reference the wrong provisioner or show binding errors.

### Diagnosis

```bash
# Check PVC events
kubectl describe pvc <name> -n <ns>

# Verify StorageClass provisioner
kubectl get sc -o custom-columns='NAME:.metadata.name,PROVISIONER:.provisioner'
```

### Common causes

1. **Wrong provisioner name** -- Auto Mode uses `ebs.csi.eks.amazonaws.com`, NOT
   `ebs.csi.aws.com`. The latter is the self-managed driver. If your StorageClass
   references the wrong provisioner, PVCs will never bind.

2. **Volume type not supported** -- Auto Mode EBS supports gp3, gp2, io1, io2, st1,
   sc1. Verify your StorageClass `parameters.type`.

3. **AZ mismatch** -- EBS volumes are AZ-local. If the pod is constrained to AZ-a
   but the PV was created in AZ-b, it cannot attach. Use
   `volumeBindingMode: WaitForFirstConsumer` (this repo sets it by default).

4. **KMS key permissions** -- if using encrypted volumes with a customer-managed key,
   the node role must have `kms:CreateGrant` and `kms:Decrypt` on that key.

### Fix

Check `kubectl get sc ebs-csi -o yaml` and confirm:
```yaml
provisioner: ebs.csi.eks.amazonaws.com
volumeBindingMode: WaitForFirstConsumer
```

## SELinux volume sharing

### Symptoms

Multiple pods mounting the same PVC get permission denied errors, or one pod succeeds
and another fails with `Operation not permitted` on the mounted path.

### Cause

Auto Mode nodes run Bottlerocket with SELinux enabled. When two pods mount the same
volume, they must share the same SELinux context. If they have different (or no)
`seLinuxOptions.level`, the kernel blocks cross-context access.

### Fix

Set matching `seLinuxOptions.level` in both pod security contexts:

```yaml
spec:
  securityContext:
    seLinuxOptions:
      level: "s0:c123,c456"   # Same value in all pods sharing the volume
```

Or use `seLinuxChangePolicy: Recursive` (K8s 1.27+) if only one pod mounts at a time
and you want relabeling on attach.

## Off-cluster controller issues

### Symptoms

Managed components (Karpenter, ALB controller, EBS CSI) behave unexpectedly:
- Nodes not consolidating despite underutilization
- ALBs not updating target groups
- Volumes not detaching after pod deletion

### Diagnosis

These components run in the AWS control plane. You cannot view their logs directly.

```bash
# Check NodePool status conditions
kubectl get nodepool <name> -o jsonpath='{.status.conditions}'

# Check for NodeClaim status
kubectl get nodeclaims -o wide

# Look for EKS platform events in CloudTrail
aws cloudtrail lookup-events --lookup-attributes AttributeKey=EventSource,AttributeValue=eks.amazonaws.com --max-results 10
```

### Fix

If a managed component is misbehaving and you have verified your manifests are
correct, open an AWS Support ticket. Include:
- Cluster name and region
- Timestamp of the issue
- Relevant resource names (NodePool, NodeClaim, Ingress, PVC)
- Expected vs actual behavior

AWS Support can access the control-plane component logs that you cannot see.

## CloudWatch Logs Insights query for Karpenter events

Auto Mode emits Kubernetes events from Karpenter into the cluster event stream.
Query them with:

```bash
# Recent Karpenter-related events
kubectl get events --field-selector reason!=Scheduled,reason!=Pulling,reason!=Pulled,reason!=Created,reason!=Started -A | grep -i 'karpenter\|nodepool\|nodeclaim\|consolidat'

# If Container Insights is enabled, query CloudWatch
aws logs start-query --log-group-name "/aws/containerinsights/<cluster-name>/performance" --start-time $(date -d '1 hour ago' +%s) --end-time $(date +%s) --query-string 'fields @timestamp, @message | filter @message like /karpenter/ | sort @timestamp desc | limit 50'
```

For broader event history (events expire from etcd after 1 hour):

```bash
# CloudWatch Logs Insights (if observability enabled)
# Log group: /aws/eks/<cluster-name>/cluster
# Query:
fields @timestamp, @message
| filter @logStream like /kube-apiserver-audit/
| filter @message like /nodeclaims|nodepools/
| sort @timestamp desc
| limit 100
```

## NodeDiagnostic resource for node logs

When you need logs from a specific node (kubelet, containerd, kernel), use the
NodeDiagnostic custom resource:

```yaml
apiVersion: eks.amazonaws.com/v1
kind: NodeDiagnostic
metadata:
  name: <node-name>    # Must match the Node name exactly
```

```bash
# Create the diagnostic
kubectl apply -f - <<EOF
apiVersion: eks.amazonaws.com/v1
kind: NodeDiagnostic
metadata:
  name: $(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
EOF

# Check status (contains S3 presigned URL for log bundle)
kubectl get nodediagnostic <node-name> -o yaml
```

The status includes a presigned S3 URL where you can download the log bundle.
NodeDiagnostic resources auto-delete after 30 minutes.

This replaces SSH/SSM for node-level debugging on Auto Mode.

## Sources

- [Troubleshooting Auto Mode](https://docs.aws.amazon.com/eks/latest/userguide/auto-troubleshoot.html)
- [Get node logs (NodeDiagnostic)](https://docs.aws.amazon.com/eks/latest/userguide/auto-get-logs.html)
- [Auto Mode IAM](https://docs.aws.amazon.com/eks/latest/userguide/auto-learn-iam.html)
- [Tag subnets for Auto Mode](https://docs.aws.amazon.com/eks/latest/userguide/tag-subnets-auto.html)
- [Configure ALB](https://docs.aws.amazon.com/eks/latest/userguide/auto-configure-alb.html)
- [Configure NLB](https://docs.aws.amazon.com/eks/latest/userguide/auto-configure-nlb.html)
- [Create StorageClass](https://docs.aws.amazon.com/eks/latest/userguide/create-storage-class.html)
- [Auto Mode reference](https://docs.aws.amazon.com/eks/latest/userguide/auto-reference.html)
- [Best practices for Auto Mode](https://docs.aws.amazon.com/eks/latest/best-practices/automode.html)
- [This repository](https://github.com/aws-samples/sample-aws-eks-auto-mode)
