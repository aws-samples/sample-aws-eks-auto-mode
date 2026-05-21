resource "aws_eks_addon" "cloudwatch_observability" {
  count        = var.enable_observability ? 1 : 0
  cluster_name = module.eks.cluster_name
  addon_name   = "amazon-cloudwatch-observability"

  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [module.eks]
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  count      = var.enable_observability ? 1 : 0
  role       = module.eks.node_iam_role_name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}
