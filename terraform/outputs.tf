output "configure_kubectl" {
  description = "Configure kubectl: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig"
  value       = "aws eks --region ${var.region} update-kubeconfig --name ${module.eks.cluster_name}"
}

output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "oidc_provider_arn" {
  description = "EKS OIDC provider ARN"
  value       = module.eks.oidc_provider_arn
}

output "region" {
  description = "AWS region"
  value       = var.region
}

output "name" {
  description = "Cluster name variable"
  value       = var.name
}

output "cloudwatch_dashboard_url" {
  description = "CloudWatch Container Insights URL (only when observability is enabled)"
  value       = var.enable_observability ? "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#container-insights:infrastructure" : null
}
