# EKS Auto Mode's managed AmazonEKS*Policies gate ec2:RunInstances / CreateFleet /
# CreateVolume / CreateNetworkInterface / CreateLoadBalancer with a ForAllValues
# tag-key allowlist (eks:*, kubernetes.io/*, karpenter.*). Custom tags from
# var.tags fall outside that allowlist so the managed Allow does not match and
# the call is denied.
#
# This inline policy unions in the AWS-prescribed "Custom AWS tags for EKS Auto
# resources" statements so the cluster role can create Auto-Mode resources
# carrying var.tags.
#
# Source: https://docs.aws.amazon.com/eks/latest/userguide/auto-cluster-iam-role.html
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
