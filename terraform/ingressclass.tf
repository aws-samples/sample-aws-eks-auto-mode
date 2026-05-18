# IngressClassParams carries var.tags onto ALBs created by the EKS Auto Mode
# ALB controller. Without this, ALBs/TGs would only get the controller's
# default tags. Paired with the LoadBalancer statement in
# aws_iam_role_policy.eks_cluster_allow_custom_tags so the cluster role is
# permitted to set custom tags on elasticloadbalancing:CreateLoadBalancer.
resource "kubectl_manifest" "ingressclassparams_internet_facing_alb" {
  yaml_body = yamlencode({
    apiVersion = "eks.amazonaws.com/v1"
    kind       = "IngressClassParams"
    metadata = {
      name = "internet-facing-alb"
    }
    spec = {
      scheme = "internet-facing"
      tags   = [for k, v in local.tags : { key = k, value = v }]
    }
  })

  depends_on = [
    module.eks,
    aws_iam_role_policy.eks_cluster_allow_custom_tags,
  ]
}

resource "kubectl_manifest" "ingressclass_internet_facing_alb" {
  yaml_body = yamlencode({
    apiVersion = "networking.k8s.io/v1"
    kind       = "IngressClass"
    metadata = {
      name = "internet-facing-alb"
      annotations = {
        "ingressclass.kubernetes.io/is-default-class" = "true"
      }
    }
    spec = {
      controller = "eks.amazonaws.com/alb"
      parameters = {
        apiGroup = "eks.amazonaws.com"
        kind     = "IngressClassParams"
        name     = "internet-facing-alb"
      }
    }
  })

  depends_on = [kubectl_manifest.ingressclassparams_internet_facing_alb]
}
