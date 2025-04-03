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
  default     = "1.32"
  type        = string
}

# VPC with 65536 IPs (10.0.0.0/16) for 3 AZs
variable "vpc_cidr" {
  description = "VPC CIDR. This should be a valid private (RFC 1918) CIDR range"
  default     = "10.0.0.0/16"
  type        = string
}
