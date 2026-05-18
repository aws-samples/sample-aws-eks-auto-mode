# --------------------------------------------------------------------------
# Five-layer tag propagation for EKS Auto Mode.
#
# Layers 1 and 2 (provider default_tags, EKS cluster_tags) live in main.tf
# and eks.tf respectively. Layer 3 (NodeClass spec.tags) lives in setup.tf
# and the nodepool-templates/. This file carries the remaining pieces:
#
#   - IAM policy permitting the cluster role to set var.tags on the AWS
#     resources that EKS Auto Mode creates (load-bearing for L3 / L4 / L5).
#   - StorageClass (Layer 4) so PVCs default to a class that tags the EBS
#     volume at create time.
#   - IngressClass + IngressClassParams (Layer 5) so Ingresses default to a
#     class that tags the resulting ALB / TG / Listener.
#
# See claude-md/TAGGING.md for the full pattern explanation, including the
# explicit-override gaps these defaults do not cover (e.g. PVCs with
# storageClassName: gp3, Ingresses with an ingressClassName override).
# --------------------------------------------------------------------------


# --------------------------------------------------------------------------
# IAM: cluster role permission to set custom tags
#
# EKS Auto Mode's managed AmazonEKS*Policies gate ec2:RunInstances /
# CreateFleet / CreateVolume / CreateNetworkInterface / CreateLoadBalancer
# with a ForAllValues tag-key allowlist (eks:*, kubernetes.io/*, karpenter.*).
# Custom tags from var.tags fall outside that allowlist so the managed Allow
# does not match and the call is denied.
#
# This inline policy unions in the AWS-prescribed "Custom AWS tags for EKS
# Auto resources" statements so the cluster role can create Auto-Mode
# resources carrying var.tags.
#
# Source: https://docs.aws.amazon.com/eks/latest/userguide/auto-cluster-iam-role.html
# --------------------------------------------------------------------------
resource "aws_iam_role_policy" "eks_cluster_allow_custom_tags" {
  name = "${module.eks.cluster_name}-allow-custom-tags"
  role = module.eks.cluster_iam_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Compute"
        Effect = "Allow"
        Action = [
          "ec2:CreateFleet",
          "ec2:RunInstances",
          "ec2:CreateLaunchTemplate",
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestTag/eks:eks-cluster-name" = "$${aws:PrincipalTag/eks:eks-cluster-name}"
          }
          StringLike = {
            "aws:RequestTag/eks:kubernetes-node-class-name" = "*"
            "aws:RequestTag/eks:kubernetes-node-pool-name"  = "*"
          }
        }
      },
      {
        Sid    = "Storage"
        Effect = "Allow"
        Action = [
          "ec2:CreateVolume",
          "ec2:CreateSnapshot",
        ]
        Resource = [
          "arn:aws:ec2:*:*:volume/*",
          "arn:aws:ec2:*:*:snapshot/*",
        ]
        Condition = {
          StringEquals = {
            "aws:RequestTag/eks:eks-cluster-name" = "$${aws:PrincipalTag/eks:eks-cluster-name}"
          }
        }
      },
      {
        Sid      = "Networking"
        Effect   = "Allow"
        Action   = "ec2:CreateNetworkInterface"
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestTag/eks:eks-cluster-name" = "$${aws:PrincipalTag/eks:eks-cluster-name}"
          }
          StringLike = {
            "aws:RequestTag/eks:kubernetes-cni-node-name" = "*"
          }
        }
      },
      {
        Sid    = "LoadBalancer"
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:CreateLoadBalancer",
          "elasticloadbalancing:CreateTargetGroup",
          "elasticloadbalancing:CreateListener",
          "elasticloadbalancing:CreateRule",
          "ec2:CreateSecurityGroup",
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestTag/eks:eks-cluster-name" = "$${aws:PrincipalTag/eks:eks-cluster-name}"
          }
        }
      },
      {
        Sid    = "ShieldProtection"
        Effect = "Allow"
        Action = [
          "shield:CreateProtection",
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestTag/eks:eks-cluster-name" = "$${aws:PrincipalTag/eks:eks-cluster-name}"
          }
        }
      },
      {
        Sid    = "ShieldTagResource"
        Effect = "Allow"
        Action = [
          "shield:TagResource",
        ]
        Resource = "arn:aws:shield::*:protection/*"
        Condition = {
          StringEquals = {
            "aws:RequestTag/eks:eks-cluster-name" = "$${aws:PrincipalTag/eks:eks-cluster-name}"
          }
        }
      },
    ]
  })
}


# --------------------------------------------------------------------------
# Layer 4: StorageClass for tagged EBS volumes
#
# PVCs without storageClassName land on the default StorageClass. We make
# that default a custom "ebs" class with tagSpecification_N parameters, so
# the EBS-CSI driver tags volumes at create time. The legacy in-tree gp2
# StorageClass is removed so "ebs" is the sole default. PVCs that explicitly
# request the EKS-Auto-managed gp3 class bypass this and produce untagged
# volumes (managed StorageClass cannot be mutated).
# --------------------------------------------------------------------------
resource "kubectl_manifest" "storageclass_ebs" {
  yaml_body = yamlencode({
    apiVersion = "storage.k8s.io/v1"
    kind       = "StorageClass"
    metadata = {
      name = "ebs"
      annotations = {
        "storageclass.kubernetes.io/is-default-class" = "true"
      }
    }
    provisioner       = "ebs.csi.eks.amazonaws.com"
    volumeBindingMode = "WaitForFirstConsumer"
    parameters = merge(
      { type = "gp3" },
      { for i, k in keys(local.tags) : "tagSpecification_${i + 1}" => "${k}=${local.tags[k]}" },
    )
  })

  depends_on = [module.eks]
}

resource "null_resource" "delete_gp2_storageclass" {
  provisioner "local-exec" {
    command = <<-EOT
      aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.region} && \
      kubectl delete storageclass gp2 --ignore-not-found
    EOT
  }

  depends_on = [
    module.eks,
    kubectl_manifest.storageclass_ebs,
  ]
}


# Layer 5 (ALB tagging) is handled per-example: each Ingress YAML in examples/
# is templated and rendered with var.tags injected into its IngressClassParams.
# This keeps the example self-documenting (the user sees IngressClassParams in
# the YAML they apply) and avoids the cluster-default-class footgun where an
# Ingress with an explicit ingressClassName bypasses a global default.
# See terraform/setup.tf and examples/{graviton,spot}/2048-ingress.yaml.tpl.
