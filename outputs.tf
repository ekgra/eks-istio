output "vpc_id" {
  value = aws_vpc.this.id
}

output "public_subnet_ids" {
  value = [for s in aws_subnet.public : s.id]
}

output "public_subnet_cidrs" {
  value = { for k, s in aws_subnet.public : k => s.cidr_block }
}

output "public_route_table_id" {
  value = aws_route_table.public.id
}

output "nodes_additional_sg_id" {
  value       = aws_security_group.nodes_extra.id
  description = "Attach this SG to your EKS node group (vpc_security_group_ids) so NLB -> NodePort works."
}


# ========== EKS outputs ==========
output "cluster_name" {
  value = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority" {
  value = aws_eks_cluster.this.certificate_authority[0].data
}

output "nodegroup_name" {
  value = aws_eks_node_group.spot_ng.node_group_name
}
