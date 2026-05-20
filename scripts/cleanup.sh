#!/usr/bin/env bash
set -euo pipefail

# ─── Configuration ────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TF_DIR="$REPO_ROOT/terraform"
KEDA_TF_DIR="$REPO_ROOT/examples/pod-autoscaling/keda/terraform"

DRY_RUN=false
YES=false
KEEP_STORAGE=false
REGION=""
CLUSTER_NAME=""
SKIP_TERRAFORM=false
SKIP_KEDA=false

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

DELETED=0
KEPT=0
SKIPPED=0
ERRORS=0

# ─── Helpers ──────────────────────────────────────────────────────────────────

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Comprehensive cleanup for sample-aws-eks-auto-mode deployments.
Drains k8s-controller-managed AWS resources before terraform destroy,
then sweeps any orphans that survived.

OPTIONS:
  --dry-run          Show what would be deleted without deleting
  --yes              Skip all prompts (delete everything matching)
  --keep-storage     Keep all PVC/EBS/EFS resources (skip storage prompts)
  --region REGION    AWS region (auto-detected from terraform state if omitted)
  --cluster-name N   Cluster name (auto-detected from terraform state if omitted)
  --skip-terraform   Skip terraform destroy (only run pre-drain + post-sweep)
  --skip-keda        Skip KEDA terraform destroy
  -h, --help         Show this help

EXAMPLES:
  # Interactive cleanup (prompts for each decision)
  ./scripts/cleanup.sh

  # Full non-interactive delete
  ./scripts/cleanup.sh --yes

  # Dry run to see what would happen
  ./scripts/cleanup.sh --dry-run

  # Delete everything except storage
  ./scripts/cleanup.sh --yes --keep-storage

  # Orphan sweep only (terraform already destroyed)
  ./scripts/cleanup.sh --skip-terraform --yes
EOF
  exit 0
}

log()  { echo -e "${CYAN}[cleanup]${NC} $*"; }
warn() { echo -e "${YELLOW}[warn]${NC} $*"; }
err()  { echo -e "${RED}[error]${NC} $*"; }
ok()   { echo -e "${GREEN}[ok]${NC} $*"; }

confirm() {
  local msg="$1"
  if $YES; then return 0; fi
  if $DRY_RUN; then log "DRY-RUN: would $msg"; return 1; fi
  echo -ne "${YELLOW}$msg [y/N]: ${NC}"
  read -r ans
  [[ "$ans" =~ ^[Yy] ]]
}

prompt_resource() {
  local resource_type="$1" resource_id="$2" resource_name="${3:-}"
  if $DRY_RUN; then
    log "DRY-RUN: would delete $resource_type $resource_id ${resource_name:+($resource_name)}"
    return 1
  fi
  if $YES; then return 0; fi
  local display="$resource_type: $resource_id"
  [[ -n "$resource_name" ]] && display="$resource_type: $resource_name ($resource_id)"
  echo -ne "${YELLOW}Delete $display? [y/N/a(ll)]: ${NC}"
  read -r ans
  case "$ans" in
    [Yy]) return 0 ;;
    [Aa]) YES=true; return 0 ;;
    *) return 1 ;;
  esac
}

run_or_dry() {
  if $DRY_RUN; then
    log "DRY-RUN: $*"
    return 0
  fi
  "$@"
}

check_deps() {
  local missing=()
  for cmd in aws kubectl jq terraform; do
    command -v "$cmd" &>/dev/null || missing+=("$cmd")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    err "Missing required tools: ${missing[*]}"
    exit 1
  fi
}

# ─── Auto-detect cluster info ────────────────────────────────────────────────

detect_cluster_info() {
  if [[ -z "$CLUSTER_NAME" || -z "$REGION" ]]; then
    if [[ -f "$TF_DIR/terraform.tfstate" ]]; then
      local state_content
      state_content=$(cat "$TF_DIR/terraform.tfstate")
      local resource_count
      resource_count=$(echo "$state_content" | jq '.resources | length // 0')

      if [[ "$resource_count" -gt 0 ]]; then
        if [[ -z "$CLUSTER_NAME" ]]; then
          CLUSTER_NAME=$(cd "$TF_DIR" && terraform output -raw cluster_name 2>/dev/null || true)
        fi
        if [[ -z "$REGION" ]]; then
          REGION=$(cd "$TF_DIR" && terraform output -raw region 2>/dev/null || true)
        fi
      fi
    fi
  fi

  if [[ -z "$CLUSTER_NAME" ]]; then
    if kubectl config current-context &>/dev/null; then
      CLUSTER_NAME=$(kubectl config current-context | grep -oP '(?<=:cluster/)[^/]+' || true)
    fi
  fi

  if [[ -z "$REGION" ]]; then
    REGION=$(aws configure get region 2>/dev/null || echo "")
  fi

  if [[ -z "$CLUSTER_NAME" ]]; then
    err "Cannot detect cluster name. Use --cluster-name"
    exit 1
  fi
  if [[ -z "$REGION" ]]; then
    err "Cannot detect region. Use --region"
    exit 1
  fi

  log "Cluster: $CLUSTER_NAME"
  log "Region:  $REGION"
}

# ─── Phase 1: Pre-drain (requires live cluster) ──────────────────────────────

phase_predrain() {
  log "━━━ Phase 1: Pre-drain (k8s controller-managed resources) ━━━"

  local cluster_status
  cluster_status=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" \
    --query 'cluster.status' --output text 2>/dev/null || echo "NOT_FOUND")

  if [[ "$cluster_status" != "ACTIVE" ]]; then
    warn "Cluster not active (status: $cluster_status). Skipping pre-drain."
    return 0
  fi

  aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION" --quiet 2>/dev/null || true

  drain_ingresses
  drain_lb_services
  drain_pvcs
  drain_keda
  drain_helm_releases
  drain_nodepools
  drain_external_dns_records
  wait_for_lb_cleanup
}

drain_ingresses() {
  log "Deleting all Ingress resources (triggers ALB controller cleanup)..."
  local ingresses
  ingresses=$(kubectl get ingress -A -o json 2>/dev/null | jq -r '.items[] | "\(.metadata.namespace)/\(.metadata.name)"' || true)
  if [[ -z "$ingresses" ]]; then
    ok "No Ingresses found"
    return
  fi
  echo "$ingresses" | while read -r ing; do
    log "  Deleting Ingress $ing"
    run_or_dry kubectl delete ingress -n "${ing%%/*}" "${ing##*/}" --wait=true --timeout=120s 2>/dev/null || true
    ((DELETED++)) || true
  done
  log "Waiting 30s for ALB controller to clean up load balancers..."
  $DRY_RUN || sleep 30
}

drain_lb_services() {
  log "Deleting LoadBalancer-type Services..."
  local services
  services=$(kubectl get svc -A -o json 2>/dev/null | \
    jq -r '.items[] | select(.spec.type == "LoadBalancer") | "\(.metadata.namespace)/\(.metadata.name)"' || true)
  if [[ -z "$services" ]]; then
    ok "No LoadBalancer Services found"
    return
  fi
  echo "$services" | while read -r svc; do
    log "  Deleting Service $svc"
    run_or_dry kubectl delete svc -n "${svc%%/*}" "${svc##*/}" --wait=true --timeout=120s 2>/dev/null || true
    ((DELETED++)) || true
  done
}

drain_pvcs() {
  if $KEEP_STORAGE; then
    warn "Skipping PVC deletion (--keep-storage)"
    return
  fi
  log "Deleting PersistentVolumeClaims (triggers EBS CSI volume release)..."
  local pvcs
  pvcs=$(kubectl get pvc -A -o json 2>/dev/null | \
    jq -r '.items[] | "\(.metadata.namespace)/\(.metadata.name) [\(.spec.storageClassName // "default")]"' || true)
  if [[ -z "$pvcs" ]]; then
    ok "No PVCs found"
    return
  fi
  echo "$pvcs" | while read -r pvc_line; do
    local pvc_ref="${pvc_line%% *}"
    if prompt_resource "PVC" "$pvc_ref"; then
      run_or_dry kubectl delete pvc -n "${pvc_ref%%/*}" "${pvc_ref##*/}" --wait=true --timeout=60s 2>/dev/null || true
      ((DELETED++)) || true
    else
      ((KEPT++)) || true
    fi
  done
}

drain_keda() {
  log "Removing KEDA ScaledObjects (prevents rescaling during drain)..."
  if kubectl api-resources 2>/dev/null | grep -q scaledobjects; then
    run_or_dry kubectl delete scaledobjects -A --all --wait=true --timeout=60s 2>/dev/null || true
    run_or_dry kubectl delete triggerauthentications -A --all --wait=true --timeout=30s 2>/dev/null || true
  else
    ok "No KEDA CRDs found"
  fi
}

drain_helm_releases() {
  log "Uninstalling Helm releases in cluster..."
  local releases
  releases=$(helm list -A -o json 2>/dev/null | jq -r '.[] | "\(.namespace)/\(.name)"' || true)
  if [[ -z "$releases" ]]; then
    ok "No Helm releases found"
    return
  fi
  echo "$releases" | while read -r rel; do
    local ns="${rel%%/*}" name="${rel##*/}"
    log "  Uninstalling Helm release $rel"
    run_or_dry helm uninstall "$name" -n "$ns" --wait --timeout 120s 2>/dev/null || true
    ((DELETED++)) || true
  done
}

drain_nodepools() {
  log "Deleting custom NodePools + NodeClaims (triggers node termination)..."
  if kubectl api-resources 2>/dev/null | grep -q nodepools.karpenter; then
    local pools
    pools=$(kubectl get nodepools.karpenter.sh -o name 2>/dev/null | grep -v "general-purpose" || true)
    if [[ -n "$pools" ]]; then
      echo "$pools" | while read -r pool; do
        log "  Deleting $pool"
        run_or_dry kubectl delete "$pool" --wait=true --timeout=300s 2>/dev/null || true
        ((DELETED++)) || true
      done
    fi
    local claims
    claims=$(kubectl get nodeclaims.karpenter.sh -o name 2>/dev/null || true)
    if [[ -n "$claims" ]]; then
      log "  Deleting remaining NodeClaims..."
      run_or_dry kubectl delete nodeclaims.karpenter.sh --all --wait=true --timeout=300s 2>/dev/null || true
    fi
  fi
  if kubectl api-resources 2>/dev/null | grep -q nodeclasses.eks.amazonaws.com; then
    local classes
    classes=$(kubectl get nodeclasses.eks.amazonaws.com -o name 2>/dev/null | grep -v "default" || true)
    if [[ -n "$classes" ]]; then
      echo "$classes" | while read -r cls; do
        log "  Deleting $cls"
        run_or_dry kubectl delete "$cls" --wait=true --timeout=60s 2>/dev/null || true
      done
    fi
  fi
  ok "NodePool drain complete"
}

drain_external_dns_records() {
  log "Checking for external-dns managed Route53 records..."
  if kubectl get deploy -n external-dns external-dns &>/dev/null 2>&1; then
    log "  external-dns is present; its records will be cleaned when the deployment is removed"
    log "  (Helm uninstall above should trigger external-dns cleanup via finalizers)"
    $DRY_RUN || sleep 10
  fi
}

wait_for_lb_cleanup() {
  log "Verifying load balancers are cleaned up..."
  local max_wait=180
  local waited=0
  while [[ $waited -lt $max_wait ]]; do
    local lbs
    lbs=$(aws elbv2 describe-load-balancers --region "$REGION" \
      --query "LoadBalancers[].LoadBalancerArn" --output json 2>/dev/null | jq -r '.[]' || true)
    if [[ -z "$lbs" ]]; then
      ok "All load balancers cleaned up"
      return
    fi
    local cluster_lbs=0
    for lb_arn in $lbs; do
      local tags
      tags=$(aws elbv2 describe-tags --region "$REGION" --resource-arns "$lb_arn" \
        --query "TagDescriptions[0].Tags" --output json 2>/dev/null || echo "[]")
      if echo "$tags" | jq -e ".[] | select(.Key == \"elbv2.k8s.aws/cluster\" and .Value == \"$CLUSTER_NAME\")" &>/dev/null; then
        ((cluster_lbs++)) || true
      fi
    done
    if [[ $cluster_lbs -eq 0 ]]; then
      ok "No cluster-owned load balancers remaining"
      return
    fi
    if $DRY_RUN; then return; fi
    log "  Still waiting for $cluster_lbs LB(s) to drain... (${waited}s/${max_wait}s)"
    sleep 15
    ((waited+=15))
  done
  warn "Timed out waiting for LB cleanup. Continuing (post-sweep will catch orphans)."
}

# ─── Phase 2: Terraform Destroy ──────────────────────────────────────────────

phase_terraform_destroy() {
  if $SKIP_TERRAFORM; then
    warn "Skipping terraform destroy (--skip-terraform)"
    return
  fi
  log "━━━ Phase 2: Terraform Destroy ━━━"

  if ! $SKIP_KEDA; then
    phase_keda_destroy
  fi
  phase_main_destroy
}

phase_keda_destroy() {
  if [[ ! -d "$KEDA_TF_DIR" ]]; then
    ok "No KEDA terraform directory found"
    return
  fi
  local resource_count
  resource_count=$(cd "$KEDA_TF_DIR" && terraform state list 2>/dev/null | wc -l || echo "0")
  if [[ "$resource_count" -eq 0 ]]; then
    ok "KEDA terraform state is empty (already destroyed)"
    return
  fi
  log "Destroying KEDA resources ($resource_count in state)..."
  if confirm "Run terraform destroy in $KEDA_TF_DIR?"; then
    run_or_dry bash -c "cd '$KEDA_TF_DIR' && terraform destroy -auto-approve"
  else
    warn "Skipped KEDA terraform destroy"
    ((SKIPPED++)) || true
  fi
}

phase_main_destroy() {
  local resource_count
  resource_count=$(cd "$TF_DIR" && terraform state list 2>/dev/null | wc -l || echo "0")
  if [[ "$resource_count" -eq 0 ]]; then
    ok "Main terraform state is empty (already destroyed)"
    return
  fi
  log "Destroying main infrastructure ($resource_count resources in state)..."
  if confirm "Run terraform destroy in $TF_DIR?"; then
    run_or_dry bash -c "cd '$TF_DIR' && terraform destroy -auto-approve"
  else
    warn "Skipped main terraform destroy"
    ((SKIPPED++)) || true
  fi
}

# ─── Phase 3: Post-destroy orphan sweep ──────────────────────────────────────

phase_orphan_sweep() {
  log "━━━ Phase 3: Post-destroy orphan sweep ━━━"
  log "Scanning for resources tagged with cluster '$CLUSTER_NAME' or in cluster VPC..."

  sweep_load_balancers
  sweep_target_groups
  sweep_ec2_instances
  sweep_ebs_volumes
  sweep_enis
  sweep_security_groups
  sweep_iam_roles
  sweep_oidc_providers
  sweep_cloudwatch_logs
  sweep_kms_keys
  sweep_route53_records
  sweep_sqs_queues
  sweep_launch_templates
  sweep_eips
}

sweep_load_balancers() {
  log "Checking for orphaned Load Balancers..."
  local lbs
  lbs=$(aws elbv2 describe-load-balancers --region "$REGION" \
    --query "LoadBalancers[].LoadBalancerArn" --output json 2>/dev/null | jq -r '.[]' || true)
  [[ -z "$lbs" ]] && { ok "No load balancers found"; return; }

  for lb_arn in $lbs; do
    local tags lb_name
    tags=$(aws elbv2 describe-tags --region "$REGION" --resource-arns "$lb_arn" \
      --query "TagDescriptions[0].Tags" --output json 2>/dev/null || echo "[]")
    lb_name=$(aws elbv2 describe-load-balancers --region "$REGION" \
      --load-balancer-arns "$lb_arn" --query "LoadBalancers[0].LoadBalancerName" --output text 2>/dev/null || echo "unknown")

    local is_cluster=false
    if echo "$tags" | jq -e ".[] | select(.Key == \"elbv2.k8s.aws/cluster\" and .Value == \"$CLUSTER_NAME\")" &>/dev/null; then
      is_cluster=true
    elif echo "$tags" | jq -e ".[] | select(.Key == \"kubernetes.io/cluster/$CLUSTER_NAME\")" &>/dev/null; then
      is_cluster=true
    fi

    if $is_cluster; then
      if prompt_resource "LoadBalancer" "$lb_arn" "$lb_name"; then
        local listeners
        listeners=$(aws elbv2 describe-listeners --region "$REGION" --load-balancer-arn "$lb_arn" \
          --query "Listeners[].ListenerArn" --output json 2>/dev/null | jq -r '.[]' || true)
        for listener_arn in $listeners; do
          run_or_dry aws elbv2 delete-listener --region "$REGION" --listener-arn "$listener_arn"
        done
        run_or_dry aws elbv2 delete-load-balancer --region "$REGION" --load-balancer-arn "$lb_arn"
        ((DELETED++)) || true
      else
        ((KEPT++)) || true
      fi
    fi
  done
}

sweep_target_groups() {
  log "Checking for orphaned Target Groups..."
  local tgs
  tgs=$(aws elbv2 describe-target-groups --region "$REGION" \
    --query "TargetGroups[].TargetGroupArn" --output json 2>/dev/null | jq -r '.[]' || true)
  [[ -z "$tgs" ]] && { ok "No target groups found"; return; }

  for tg_arn in $tgs; do
    local tags tg_name
    tags=$(aws elbv2 describe-tags --region "$REGION" --resource-arns "$tg_arn" \
      --query "TagDescriptions[0].Tags" --output json 2>/dev/null || echo "[]")
    tg_name=$(echo "$tg_arn" | grep -oP 'targetgroup/\K[^/]+' || echo "unknown")

    local is_cluster=false
    if echo "$tags" | jq -e ".[] | select(.Key == \"elbv2.k8s.aws/cluster\" and .Value == \"$CLUSTER_NAME\")" &>/dev/null; then
      is_cluster=true
    fi

    if $is_cluster; then
      if prompt_resource "TargetGroup" "$tg_arn" "$tg_name"; then
        run_or_dry aws elbv2 delete-target-group --region "$REGION" --target-group-arn "$tg_arn"
        ((DELETED++)) || true
      else
        ((KEPT++)) || true
      fi
    fi
  done
}

sweep_ec2_instances() {
  log "Checking for orphaned EC2 instances..."
  local instances
  instances=$(aws ec2 describe-instances --region "$REGION" \
    --filters "Name=instance-state-name,Values=running,pending,stopping,stopped" \
    --query "Reservations[].Instances[].[InstanceId,Tags[?Key=='Name'].Value|[0]]" \
    --output json 2>/dev/null | jq -r '.[] | "\(.[0]) \(.[1] // "unnamed")"' || true)
  [[ -z "$instances" ]] && { ok "No running instances found"; return; }

  while read -r instance_id instance_name; do
    local tags
    tags=$(aws ec2 describe-tags --region "$REGION" \
      --filters "Name=resource-id,Values=$instance_id" --output json 2>/dev/null || echo '{"Tags":[]}')

    local is_cluster=false
    if echo "$tags" | jq -e ".Tags[] | select(.Key == \"karpenter.sh/discovery\" and .Value == \"$CLUSTER_NAME\")" &>/dev/null; then
      is_cluster=true
    elif echo "$tags" | jq -e ".Tags[] | select(.Key == \"aws:eks:cluster-name\" and .Value == \"$CLUSTER_NAME\")" &>/dev/null; then
      is_cluster=true
    elif echo "$tags" | jq -e ".Tags[] | select(.Key == \"kubernetes.io/cluster/$CLUSTER_NAME\")" &>/dev/null; then
      is_cluster=true
    fi

    if $is_cluster; then
      if prompt_resource "EC2 Instance" "$instance_id" "$instance_name"; then
        run_or_dry aws ec2 terminate-instances --region "$REGION" --instance-ids "$instance_id"
        ((DELETED++)) || true
      else
        ((KEPT++)) || true
      fi
    fi
  done <<< "$instances"
}

sweep_ebs_volumes() {
  if $KEEP_STORAGE; then
    warn "Skipping EBS volume sweep (--keep-storage)"
    return
  fi
  log "Checking for orphaned EBS volumes..."
  local volumes
  volumes=$(aws ec2 describe-volumes --region "$REGION" \
    --filters "Name=status,Values=available" \
    --query "Volumes[].[VolumeId,Tags[?Key=='Name'].Value|[0],Tags[?Key=='kubernetes.io/created-for/pvc/name'].Value|[0]]" \
    --output json 2>/dev/null | jq -r '.[] | "\(.[0]) \(.[1] // "unnamed") \(.[2] // "")"' || true)
  [[ -z "$volumes" ]] && { ok "No available (detached) volumes found"; return; }

  while read -r vol_id vol_name pvc_name; do
    local tags
    tags=$(aws ec2 describe-tags --region "$REGION" \
      --filters "Name=resource-id,Values=$vol_id" --output json 2>/dev/null || echo '{"Tags":[]}')

    local is_cluster=false
    if echo "$tags" | jq -e ".Tags[] | select(.Key == \"kubernetes.io/cluster/$CLUSTER_NAME\")" &>/dev/null; then
      is_cluster=true
    elif echo "$tags" | jq -e ".Tags[] | select(.Key == \"ebs.csi.aws.com/cluster\" and .Value == \"$CLUSTER_NAME\")" &>/dev/null; then
      is_cluster=true
    elif echo "$tags" | jq -e ".Tags[] | select(.Key == \"KubernetesCluster\" and .Value == \"$CLUSTER_NAME\")" &>/dev/null; then
      is_cluster=true
    elif [[ "$vol_name" == *"$CLUSTER_NAME"* ]]; then
      is_cluster=true
    elif [[ "$vol_name" == *"automode"*"dynamic-pvc"* ]]; then
      is_cluster=true
    fi

    if $is_cluster; then
      local display="${vol_name}"
      [[ -n "$pvc_name" ]] && display="${display} (PVC: $pvc_name)"
      if prompt_resource "EBS Volume" "$vol_id" "$display"; then
        run_or_dry aws ec2 delete-volume --region "$REGION" --volume-id "$vol_id"
        ((DELETED++)) || true
      else
        ((KEPT++)) || true
      fi
    fi
  done <<< "$volumes"
}

sweep_enis() {
  log "Checking for orphaned ENIs..."
  local enis
  enis=$(aws ec2 describe-network-interfaces --region "$REGION" \
    --filters "Name=status,Values=available" \
    --query "NetworkInterfaces[].[NetworkInterfaceId,Description,Groups[0].GroupName]" \
    --output json 2>/dev/null | jq -r '.[] | "\(.[0]) \(.[1] // "") \(.[2] // "")"' || true)
  [[ -z "$enis" ]] && { ok "No orphaned ENIs found"; return; }

  while read -r eni_id description sg_name; do
    local is_cluster=false
    if [[ "$description" == *"$CLUSTER_NAME"* ]] || [[ "$sg_name" == *"$CLUSTER_NAME"* ]]; then
      is_cluster=true
    fi
    local tags
    tags=$(aws ec2 describe-tags --region "$REGION" \
      --filters "Name=resource-id,Values=$eni_id" --output json 2>/dev/null || echo '{"Tags":[]}')
    if echo "$tags" | jq -e ".Tags[] | select(.Key == \"kubernetes.io/cluster/$CLUSTER_NAME\" or .Key == \"aws:eks:cluster-name\" and .Value == \"$CLUSTER_NAME\")" &>/dev/null; then
      is_cluster=true
    fi
    if echo "$tags" | jq -e ".Tags[] | select(.Key == \"elbv2.k8s.aws/cluster\" and .Value == \"$CLUSTER_NAME\")" &>/dev/null; then
      is_cluster=true
    fi

    if $is_cluster; then
      if prompt_resource "ENI" "$eni_id" "$description"; then
        run_or_dry aws ec2 delete-network-interface --region "$REGION" --network-interface-id "$eni_id"
        ((DELETED++)) || true
      else
        ((KEPT++)) || true
      fi
    fi
  done <<< "$enis"
}

sweep_security_groups() {
  log "Checking for orphaned Security Groups..."
  local sgs
  sgs=$(aws ec2 describe-security-groups --region "$REGION" \
    --query "SecurityGroups[?GroupName != 'default'].[GroupId,GroupName,Description]" \
    --output json 2>/dev/null | jq -r '.[] | "\(.[0]) \(.[1]) \(.[2])"' || true)
  [[ -z "$sgs" ]] && { ok "No non-default security groups found"; return; }

  while read -r sg_id sg_name sg_desc; do
    local is_cluster=false
    if [[ "$sg_name" == *"$CLUSTER_NAME"* ]] || [[ "$sg_desc" == *"$CLUSTER_NAME"* ]]; then
      is_cluster=true
    fi
    local tags
    tags=$(aws ec2 describe-tags --region "$REGION" \
      --filters "Name=resource-id,Values=$sg_id" --output json 2>/dev/null || echo '{"Tags":[]}')
    if echo "$tags" | jq -e ".Tags[] | select(.Key == \"aws:eks:cluster-name\" and .Value == \"$CLUSTER_NAME\")" &>/dev/null; then
      is_cluster=true
    elif echo "$tags" | jq -e ".Tags[] | select(.Key == \"elbv2.k8s.aws/cluster\" and .Value == \"$CLUSTER_NAME\")" &>/dev/null; then
      is_cluster=true
    elif echo "$tags" | jq -e ".Tags[] | select(.Key == \"kubernetes.io/cluster/$CLUSTER_NAME\")" &>/dev/null; then
      is_cluster=true
    fi

    if $is_cluster; then
      if prompt_resource "SecurityGroup" "$sg_id" "$sg_name"; then
        local ingress_rules
        ingress_rules=$(aws ec2 describe-security-group-rules --region "$REGION" \
          --filters "Name=group-id,Values=$sg_id" \
          --query "SecurityGroupRules[?!IsEgress].SecurityGroupRuleId" --output json 2>/dev/null | jq -r '.[]' || true)
        if [[ -n "$ingress_rules" ]]; then
          run_or_dry aws ec2 revoke-security-group-ingress --region "$REGION" \
            --group-id "$sg_id" --security-group-rule-ids $ingress_rules 2>/dev/null || true
        fi
        local egress_rules
        egress_rules=$(aws ec2 describe-security-group-rules --region "$REGION" \
          --filters "Name=group-id,Values=$sg_id" \
          --query "SecurityGroupRules[?IsEgress].SecurityGroupRuleId" --output json 2>/dev/null | jq -r '.[]' || true)
        if [[ -n "$egress_rules" ]]; then
          run_or_dry aws ec2 revoke-security-group-egress --region "$REGION" \
            --group-id "$sg_id" --security-group-rule-ids $egress_rules 2>/dev/null || true
        fi
        run_or_dry aws ec2 delete-security-group --region "$REGION" --group-id "$sg_id" 2>/dev/null || {
          warn "  Failed to delete SG $sg_id (may have dependencies). Will retry after other resources."
          ((ERRORS++)) || true
        }
        ((DELETED++)) || true
      else
        ((KEPT++)) || true
      fi
    fi
  done <<< "$sgs"
}

sweep_iam_roles() {
  log "Checking for orphaned IAM roles..."
  local roles
  roles=$(aws iam list-roles --query "Roles[].RoleName" --output json 2>/dev/null | jq -r '.[]' || true)
  [[ -z "$roles" ]] && return

  local cluster_patterns=(
    "$CLUSTER_NAME"
  )

  for role_name in $roles; do
    local is_cluster=false
    for pattern in "${cluster_patterns[@]}"; do
      if [[ "$role_name" == *"$pattern"* ]]; then
        is_cluster=true
        break
      fi
    done
    [[ "$role_name" == "aws-service-role"* ]] && is_cluster=false
    [[ "$role_name" == "AWSServiceRole"* ]] && is_cluster=false

    if $is_cluster; then
      if prompt_resource "IAM Role" "$role_name"; then
        local policies
        policies=$(aws iam list-attached-role-policies --role-name "$role_name" \
          --query "AttachedPolicies[].PolicyArn" --output json 2>/dev/null | jq -r '.[]' || true)
        for policy_arn in $policies; do
          run_or_dry aws iam detach-role-policy --role-name "$role_name" --policy-arn "$policy_arn"
        done
        local inline_policies
        inline_policies=$(aws iam list-role-policies --role-name "$role_name" \
          --query "PolicyNames[]" --output json 2>/dev/null | jq -r '.[]' || true)
        for policy_name in $inline_policies; do
          run_or_dry aws iam delete-role-policy --role-name "$role_name" --policy-name "$policy_name"
        done
        local instance_profiles
        instance_profiles=$(aws iam list-instance-profiles-for-role --role-name "$role_name" \
          --query "InstanceProfiles[].InstanceProfileName" --output json 2>/dev/null | jq -r '.[]' || true)
        for ip_name in $instance_profiles; do
          run_or_dry aws iam remove-role-from-instance-profile --role-name "$role_name" --instance-profile-name "$ip_name"
          run_or_dry aws iam delete-instance-profile --instance-profile-name "$ip_name"
        done
        run_or_dry aws iam delete-role --role-name "$role_name"
        ((DELETED++)) || true
      else
        ((KEPT++)) || true
      fi
    fi
  done
}

sweep_oidc_providers() {
  log "Checking for orphaned OIDC providers..."
  local providers
  providers=$(aws iam list-open-id-connect-providers --query "OpenIDConnectProviderList[].Arn" \
    --output json 2>/dev/null | jq -r '.[]' || true)
  [[ -z "$providers" ]] && { ok "No OIDC providers found"; return; }

  for provider_arn in $providers; do
    local url
    url=$(aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$provider_arn" \
      --query "Url" --output text 2>/dev/null || true)
    if [[ "$url" == *"$CLUSTER_NAME"* ]] || [[ "$url" == *"eks"*"$REGION"* ]]; then
      local cluster_match=false
      local eks_cluster_id
      eks_cluster_id=$(echo "$url" | grep -oP '[A-F0-9]{32}' || true)
      if [[ -n "$eks_cluster_id" ]]; then
        cluster_match=true
      fi
      if $cluster_match || [[ "$url" == *"$CLUSTER_NAME"* ]]; then
        if prompt_resource "OIDC Provider" "$provider_arn" "$url"; then
          run_or_dry aws iam delete-open-id-connect-provider --open-id-connect-provider-arn "$provider_arn"
          ((DELETED++)) || true
        else
          ((KEPT++)) || true
        fi
      fi
    fi
  done
}

sweep_cloudwatch_logs() {
  log "Checking for orphaned CloudWatch log groups..."
  local log_groups
  log_groups=$(aws logs describe-log-groups --region "$REGION" \
    --log-group-name-prefix "/aws/eks/$CLUSTER_NAME" \
    --query "logGroups[].logGroupName" --output json 2>/dev/null | jq -r '.[]' || true)

  local ci_logs
  ci_logs=$(aws logs describe-log-groups --region "$REGION" \
    --log-group-name-prefix "/aws/containerinsights/$CLUSTER_NAME" \
    --query "logGroups[].logGroupName" --output json 2>/dev/null | jq -r '.[]' || true)

  local all_logs="$log_groups"$'\n'"$ci_logs"
  all_logs=$(echo "$all_logs" | sed '/^$/d')

  if [[ -z "$all_logs" ]]; then
    ok "No cluster log groups found"
    return
  fi

  echo "$all_logs" | while read -r lg; do
    if prompt_resource "CloudWatch LogGroup" "$lg"; then
      run_or_dry aws logs delete-log-group --region "$REGION" --log-group-name "$lg"
      ((DELETED++)) || true
    else
      ((KEPT++)) || true
    fi
  done
}

sweep_kms_keys() {
  log "Checking for orphaned KMS keys..."
  local keys
  keys=$(aws kms list-aliases --region "$REGION" \
    --query "Aliases[?contains(AliasName, '$CLUSTER_NAME')].[TargetKeyId,AliasName]" \
    --output json 2>/dev/null | jq -r '.[] | "\(.[0]) \(.[1])"' || true)
  [[ -z "$keys" ]] && { ok "No cluster KMS aliases found"; return; }

  while read -r key_id alias_name; do
    [[ -z "$key_id" ]] && continue
    local key_state
    key_state=$(aws kms describe-key --region "$REGION" --key-id "$key_id" \
      --query "KeyMetadata.KeyState" --output text 2>/dev/null || true)
    if [[ "$key_state" == "Enabled" ]]; then
      if prompt_resource "KMS Key" "$key_id" "$alias_name"; then
        run_or_dry aws kms delete-alias --region "$REGION" --alias-name "$alias_name"
        run_or_dry aws kms schedule-key-deletion --region "$REGION" --key-id "$key_id" --pending-window-in-days 7
        log "  Scheduled key $key_id for deletion in 7 days"
        ((DELETED++)) || true
      else
        ((KEPT++)) || true
      fi
    fi
  done <<< "$keys"
}

sweep_route53_records() {
  log "Checking for orphaned Route53 records..."
  local hosted_zones
  hosted_zones=$(aws route53 list-hosted-zones --query "HostedZones[].Id" --output json 2>/dev/null | jq -r '.[]' || true)
  [[ -z "$hosted_zones" ]] && { ok "No hosted zones found"; return; }

  for zone_id in $hosted_zones; do
    local zone_name
    zone_name=$(aws route53 get-hosted-zone --id "$zone_id" --query "HostedZone.Name" --output text 2>/dev/null || true)

    local records
    records=$(aws route53 list-resource-record-sets --hosted-zone-id "$zone_id" \
      --query "ResourceRecordSets[?Type == 'A' || Type == 'CNAME' || Type == 'TXT']" \
      --output json 2>/dev/null || echo "[]")

    echo "$records" | jq -c '.[]' | while read -r record; do
      local record_name record_type
      record_name=$(echo "$record" | jq -r '.Name')
      record_type=$(echo "$record" | jq -r '.Type')

      local is_cluster=false
      if [[ "$record_name" == *"$CLUSTER_NAME"* ]]; then
        is_cluster=true
      fi
      if echo "$record" | jq -e '.ResourceRecords[]? | select(.Value | contains("Heritage=external-dns"))' &>/dev/null; then
        is_cluster=true
      fi
      if echo "$record" | jq -e '.AliasTarget.DNSName? // "" | contains("elb.amazonaws.com")' &>/dev/null 2>&1; then
        if echo "$record" | jq -e '.AliasTarget.DNSName' &>/dev/null; then
          local alias_dns
          alias_dns=$(echo "$record" | jq -r '.AliasTarget.DNSName // ""')
          if [[ "$alias_dns" == *"elb"*"amazonaws.com"* ]]; then
            is_cluster=true
          fi
        fi
      fi

      if $is_cluster; then
        if prompt_resource "Route53 Record" "$record_name" "$record_type in $zone_name"; then
          local change_batch
          change_batch=$(jq -n --argjson record "$record" '{
            Changes: [{Action: "DELETE", ResourceRecordSet: $record}]
          }')
          run_or_dry aws route53 change-resource-record-sets --hosted-zone-id "$zone_id" \
            --change-batch "$change_batch" 2>/dev/null || {
              warn "  Failed to delete $record_name (may be alias to deleted LB)"
              ((ERRORS++)) || true
            }
          ((DELETED++)) || true
        else
          ((KEPT++)) || true
        fi
      fi
    done
  done
}

sweep_sqs_queues() {
  log "Checking for orphaned SQS queues..."
  local queues
  queues=$(aws sqs list-queues --region "$REGION" \
    --queue-name-prefix "$CLUSTER_NAME" \
    --query "QueueUrls[]" --output json 2>/dev/null | jq -r '.[]' || true)
  [[ -z "$queues" ]] && { ok "No cluster SQS queues found"; return; }

  for queue_url in $queues; do
    local queue_name
    queue_name=$(echo "$queue_url" | awk -F/ '{print $NF}')
    if prompt_resource "SQS Queue" "$queue_url" "$queue_name"; then
      run_or_dry aws sqs delete-queue --region "$REGION" --queue-url "$queue_url"
      ((DELETED++)) || true
    else
      ((KEPT++)) || true
    fi
  done
}

sweep_launch_templates() {
  log "Checking for orphaned Launch Templates..."
  local templates
  templates=$(aws ec2 describe-launch-templates --region "$REGION" \
    --query "LaunchTemplates[].[LaunchTemplateId,LaunchTemplateName]" \
    --output json 2>/dev/null | jq -r '.[] | "\(.[0]) \(.[1])"' || true)
  [[ -z "$templates" ]] && { ok "No launch templates found"; return; }

  while read -r lt_id lt_name; do
    local is_cluster=false
    if [[ "$lt_name" == *"$CLUSTER_NAME"* ]]; then
      is_cluster=true
    fi
    local tags
    tags=$(aws ec2 describe-launch-templates --region "$REGION" \
      --launch-template-ids "$lt_id" --query "LaunchTemplates[0].Tags" --output json 2>/dev/null || echo "[]")
    if echo "$tags" | jq -e ".[] | select(.Key == \"aws:eks:cluster-name\" and .Value == \"$CLUSTER_NAME\")" &>/dev/null; then
      is_cluster=true
    fi

    if $is_cluster; then
      if prompt_resource "Launch Template" "$lt_id" "$lt_name"; then
        run_or_dry aws ec2 delete-launch-template --region "$REGION" --launch-template-id "$lt_id"
        ((DELETED++)) || true
      else
        ((KEPT++)) || true
      fi
    fi
  done <<< "$templates"
}

sweep_eips() {
  log "Checking for orphaned Elastic IPs..."
  local eips
  eips=$(aws ec2 describe-addresses --region "$REGION" \
    --query "Addresses[?AssociationId==null].[AllocationId,Tags[?Key=='Name'].Value|[0]]" \
    --output json 2>/dev/null | jq -r '.[] | "\(.[0]) \(.[1] // "unnamed")"' || true)
  [[ -z "$eips" ]] && { ok "No unassociated EIPs found"; return; }

  while read -r alloc_id eip_name; do
    local is_cluster=false
    if [[ "$eip_name" == *"$CLUSTER_NAME"* ]]; then
      is_cluster=true
    fi
    local tags
    tags=$(aws ec2 describe-tags --region "$REGION" \
      --filters "Name=resource-id,Values=$alloc_id" --output json 2>/dev/null || echo '{"Tags":[]}')
    if echo "$tags" | jq -e ".Tags[] | select(.Key == \"kubernetes.io/cluster/$CLUSTER_NAME\")" &>/dev/null; then
      is_cluster=true
    fi
    if echo "$tags" | jq -e ".Tags[] | select(.Value == \"$CLUSTER_NAME\")" &>/dev/null; then
      is_cluster=true
    fi

    if $is_cluster; then
      if prompt_resource "Elastic IP" "$alloc_id" "$eip_name"; then
        run_or_dry aws ec2 release-address --region "$REGION" --allocation-id "$alloc_id"
        ((DELETED++)) || true
      else
        ((KEPT++)) || true
      fi
    fi
  done <<< "$eips"
}

# ─── Summary ─────────────────────────────────────────────────────────────────

print_summary() {
  echo ""
  log "━━━ Summary ━━━"
  ok "  Deleted: $DELETED"
  [[ $KEPT -gt 0 ]] && warn "  Kept:    $KEPT"
  [[ $SKIPPED -gt 0 ]] && warn "  Skipped: $SKIPPED"
  [[ $ERRORS -gt 0 ]] && err "  Errors:  $ERRORS"
  echo ""
  if [[ $KEPT -gt 0 || $ERRORS -gt 0 ]]; then
    warn "Some resources were kept or had errors. Re-run to retry."
    exit 1
  fi
  ok "Cleanup complete."
}

# ─── Main ────────────────────────────────────────────────────────────────────

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run) DRY_RUN=true; shift ;;
      --yes) YES=true; shift ;;
      --keep-storage) KEEP_STORAGE=true; shift ;;
      --region) REGION="$2"; shift 2 ;;
      --cluster-name) CLUSTER_NAME="$2"; shift 2 ;;
      --skip-terraform) SKIP_TERRAFORM=true; shift ;;
      --skip-keda) SKIP_KEDA=true; shift ;;
      -h|--help) usage ;;
      *) err "Unknown option: $1"; usage ;;
    esac
  done

  check_deps
  detect_cluster_info

  echo ""
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log "  EKS Auto Mode Cleanup"
  log "  Cluster: $CLUSTER_NAME"
  log "  Region:  $REGION"
  log "  Dry-run: $DRY_RUN"
  log "  Auto-yes: $YES"
  log "  Keep storage: $KEEP_STORAGE"
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  if ! $YES && ! $DRY_RUN; then
    confirm "Proceed with cleanup?" || { log "Aborted."; exit 0; }
  fi

  phase_predrain
  phase_terraform_destroy
  phase_orphan_sweep
  print_summary
}

main "$@"
