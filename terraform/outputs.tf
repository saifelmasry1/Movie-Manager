output "vpc_id" {
  value = aws_vpc.eks_vpc.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "eks_cluster_name" {
  value = aws_eks_cluster.eks.name
}

output "eks_nodegroup_name" {
  value = aws_eks_node_group.eks_nodes.node_group_name
}
