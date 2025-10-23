resource "aws_eks_cluster" "eks_demo" {
  name     = "EKS-Lab"
  role_arn = aws_iam_role.eks_role.arn
  version  = "1.34"

  vpc_config {
    subnet_ids              = aws_subnet.public_subnets[*].id
    endpoint_private_access = false
    endpoint_public_access  = true
  }

  access_config {
    authentication_mode = "API_AND_CONFIG_MAP"
  }

  upgrade_policy {
    support_type = "STANDARD"
  }

  tags = {
    Name = "eks-cluster-public"
  }
}

resource "aws_eks_node_group" "eks_node_group" {
  cluster_name    = aws_eks_cluster.eks_demo.name
  node_group_name = "eks-public-nodes"
  node_role_arn   = aws_iam_role.node_role.arn
  subnet_ids      = aws_subnet.public_subnets[*].id
  ami_type        = "AL2023_x86_64_STANDARD"
  capacity_type   = "ON_DEMAND"
  instance_types  = ["t3.medium"]
  disk_size       = 20

  scaling_config {
    desired_size = 1
    min_size     = 1
    max_size     = 1
  }

  update_config {
    max_unavailable = 1
  }

  tags = {
    Name = "eks-node-group-public"
  }
}