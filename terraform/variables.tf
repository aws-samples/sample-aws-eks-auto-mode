variable "name" {
  description = "Name of the VPC and EKS Cluster"
  default     = "automode-cluster"
  type        = string
}

variable "region" {
  description = "region"
  default     = "us-west-2"
  type        = string
}

variable "eks_cluster_version" {
  description = "EKS Cluster version"
  default     = "1.33"
  type        = string
}

# VPC with 65536 IPs (10.0.0.0/16) for 3 AZs
variable "vpc_cidr" {
  description = "VPC CIDR. This should be a valid private (RFC 1918) CIDR range"
  default     = "10.0.0.0/16"
  type        = string
}

variable "tags" {
  description = "Tags applied to every taggable AWS resource (provider default_tags, EKS primary SG, NodeClass-launched EC2/EBS/ENI, EBS volumes via StorageClass, ALB via IngressClassParams). Override to integrate with your tagging policy."
  type        = map(string)
  default = {
    "auto-delete" = "never"
  }
}

variable "base_domain" {
  description = "Public Route53 hosted zone you already own (e.g. \"example.com\"). Leave empty (default) for safe-by-default: all example workloads expose internal-scheme load balancers reachable only via kubectl port-forward. When set, an ACM wildcard cert is created, external-dns is installed, and example Ingresses are exposed publicly at <name>.<full_domain> over HTTPS. The hosted zone must already exist; this stack does not create it."
  type        = string
  default     = ""
}

variable "subdomain" {
  description = "Optional subdomain prefix under var.base_domain (e.g. \"automode\" -> automode.example.com). Ignored when var.base_domain is empty."
  type        = string
  default     = ""
}