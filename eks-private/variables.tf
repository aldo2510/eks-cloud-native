variable "aws_region" {
  description = "AWS region"
  default     = "us-west-2"
}

variable "vpc_cidr" {
  default = "10.0.0.0/16"
}

variable "public_subnets" {
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnets" {
  default = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "availability_zones" {
  default = ["us-west-2a", "us-west-2b"]
}

variable "eks_version" {
  type        = string
  description = "Versión de Kubernetes para el clúster EKS"
  default     = "1.34"
}

variable "key_pair_name" {
  default = "Key-Bastion"
}