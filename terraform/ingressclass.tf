# --------------------------------------------------------------------------
# Cluster-wide IngressClassParams + IngressClass for the shared ALB.
#
# Two mutually-exclusive branches, gated on local.enable_domain:
#
#   enable_domain = false (default, safe-by-default)
#     scheme: internal -> ALB attaches to private subnets only.
#     Reachable via kubectl port-forward, not from the public internet.
#
#   enable_domain = true
#     scheme: internet-facing + spec.group.name: shared-internet-facing-alb
#     so multiple Ingresses share one ALB. Depends on ACM validation so the
#     wildcard cert exists before any Ingress can attach to the shared ALB.
#
# Both branches preserve spec.tags from local.tags so the ALB / TG /
# Listener carry cluster tags.
#
# spec.certificateArn is intentionally NOT set: the ALB controller picks the
# right cert via SNI from each Ingress's host: header against ACM SANs.
# --------------------------------------------------------------------------

locals {
  # YAML-formatted spec.tags entries indented to fit under spec.tags:
  ingressclass_tags_yaml = "    ${indent(4, yamlencode([for k, v in local.tags : { key = k, value = v }]))}"
}

# ---- Default branch: internal scheme, single class "alb" ----
resource "kubectl_manifest" "ingressclassparams_internal" {
  count = local.enable_domain ? 0 : 1

  yaml_body = <<-YAML
apiVersion: eks.amazonaws.com/v1
kind: IngressClassParams
metadata:
  name: alb
spec:
  scheme: internal
  tags:
${local.ingressclass_tags_yaml}
  YAML

  depends_on = [module.eks]
}

resource "kubectl_manifest" "ingressclass_internal" {
  count = local.enable_domain ? 0 : 1

  yaml_body = <<-YAML
apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata:
  name: alb
  annotations:
    ingressclass.kubernetes.io/is-default-class: "true"
spec:
  controller: eks.amazonaws.com/alb
  parameters:
    apiGroup: eks.amazonaws.com
    kind: IngressClassParams
    name: alb
  YAML

  depends_on = [kubectl_manifest.ingressclassparams_internal]
}

# ---- Opt-in branch: internet-facing, shared-group ALB ----
resource "kubectl_manifest" "ingressclassparams_shared_internet_facing_alb" {
  count = local.enable_domain ? 1 : 0

  yaml_body = <<-YAML
apiVersion: eks.amazonaws.com/v1
kind: IngressClassParams
metadata:
  name: alb
spec:
  scheme: internet-facing
  group:
    name: shared-internet-facing-alb
  tags:
${local.ingressclass_tags_yaml}
  YAML

  depends_on = [
    module.eks,
    aws_acm_certificate_validation.wildcard,
  ]
}

resource "kubectl_manifest" "ingressclass_shared_internet_facing_alb" {
  count = local.enable_domain ? 1 : 0

  yaml_body = <<-YAML
apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata:
  name: alb
  annotations:
    ingressclass.kubernetes.io/is-default-class: "true"
spec:
  controller: eks.amazonaws.com/alb
  parameters:
    apiGroup: eks.amazonaws.com
    kind: IngressClassParams
    name: alb
  YAML

  depends_on = [kubectl_manifest.ingressclassparams_shared_internet_facing_alb]
}
