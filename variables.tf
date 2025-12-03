variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "ap-southeast-2"
}

variable "cluster_name" {
  description = "EKS cluster name (used for subnet tags)"
  type        = string
  default     = "demo-eks-istio"
}

variable "vpc_cidr" {
  description = "VPC CIDR"
  type        = string
  default     = "10.10.0.0/16"
}

variable "allowed_cidr" {
  description = "CIDR allowed to hit NodePort range on nodes (for NLB instance targets). Tighten to your IP/32 for security."
  type        = string
  default     = "0.0.0.0/0"
}


# ========== EKS variables ==========
variable "eks_version" {
  description = "EKS Kubernetes version"
  type        = string
  default     = "1.31"
}


variable "node_min" {
  type    = number
  default = 2
}

variable "node_desired" {
  type    = number
  default = 2
}
variable "node_max" {
  type    = number
  default = 4
}

variable "instance_types" {
  description = "Instance types for node group"
  type        = list(string)
  default     = ["t3.small", "t3a.small", "t2.small", "t3.medium"]
}

# On-Demand fallback sizes — start at zero cost
variable "od_node_min" {
  type    = number
  default = 0
}

variable "od_node_desired" {
  type    = number
  default = 0
}

variable "od_node_max" {
  type    = number
  default = 2
}

# On-Demand instance types (can mirror Spot or be different)
variable "od_instance_types" {
  description = "Instance types for on-demand fallback"
  type        = list(string)
  default     = ["t3.small", "t3a.small", "t3.medium"]
}


