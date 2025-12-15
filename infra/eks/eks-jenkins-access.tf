# Give Jenkins EC2 IAM Role access to the EKS cluster (no manual aws-auth edits).
# This uses EKS "Access Entries" + "Cluster Access Policies".

resource "aws_eks_access_entry" "jenkins" {
  cluster_name  = aws_eks_cluster.eks.name
  principal_arn = aws_iam_role.jenkins_role.arn
  type          = "STANDARD"

  depends_on = [aws_eks_cluster.eks]
}

resource "aws_eks_access_policy_association" "jenkins_admin" {
  cluster_name  = aws_eks_cluster.eks.name
  principal_arn = aws_iam_role.jenkins_role.arn

  # AWS-managed cluster access policy (cluster-admin equivalent)
  policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.jenkins]
}
    