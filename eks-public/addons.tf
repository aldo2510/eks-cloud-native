resource "aws_eks_addon" "coredns" {
  cluster_name      = aws_eks_cluster.eks_demo.name
  addon_name        = "coredns"
  addon_version     = "v1.13.2-eksbuild.4"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name      = aws_eks_cluster.eks_demo.name
  addon_name        = "vpc-cni"
  addon_version     = "v1.21.1-eksbuild.5"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name      = aws_eks_cluster.eks_demo.name
  addon_name        = "kube-proxy"
  addon_version     = "v1.35.2-eksbuild.4"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}

resource "aws_eks_addon" "pod_identity_agent" {
  cluster_name      = aws_eks_cluster.eks_demo.name
  addon_name        = "eks-pod-identity-agent"
  addon_version     = "v1.3.10-eksbuild.2"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}