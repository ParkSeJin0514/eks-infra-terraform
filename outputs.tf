# ============================================================================
# outputs.tf - 프로젝트 출력 값
# ============================================================================
# terraform apply 후 확인할 수 있는 주요 정보들
# ============================================================================

# ============================================================================
# Network Outputs
# ============================================================================

# ============================================================================
# EC2 Outputs
# ============================================================================

output "bastion_public_ip" {
  description = "Bastion Host Public IP (SSH 접속용)"
  value       = module.ec2.bastion_public_ip
}

output "mgmt_private_ip" {
  description = "Management Instance Private IP"
  value       = module.ec2.mgmt_private_ip
}

# ============================================================================
# EKS Outputs
# ============================================================================

output "eks_cluster_name" {
  description = "EKS 클러스터 이름"
  value       = module.eks.cluster_id
}

output "eks_cluster_version" {
  description = "EKS Kubernetes 버전"
  value       = module.eks.cluster_version
}

output "kubeconfig_command" {
  description = "kubeconfig 설정 명령어"
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_id} --region ap-northeast-2"
}

# ============================================================================
# RDS Outputs
# ============================================================================

output "rds_address" {
  description = "RDS 호스트명"
  value       = module.db.address
}

output "rds_database_name" {
  description = "생성된 데이터베이스 이름"
  value       = module.db.db_name
}

# ============================================================================
# 접속 가이드
# ============================================================================

output "connection_guide" {
  description = "접속 가이드"
  value       = <<-EOT

  ============================================
  📋 접속 가이드
  ============================================

  1️⃣  Bastion Host SSH 접속
      ssh -i test.pem ubuntu@${module.ec2.bastion_public_ip}

  2️⃣  Management Instance 접속 (Bastion 경유)
      ssh -i test.pem -J ubuntu@${module.ec2.bastion_public_ip} ubuntu@${module.ec2.mgmt_private_ip}

  3️⃣  kubeconfig 설정 (Management Instance에서)
      aws eks update-kubeconfig --name ${module.eks.cluster_id} --region ap-northeast-2

  4️⃣  RDS 접속 정보
      Host: ${module.db.address}
      Port: ${module.db.port}
      Database: ${module.db.db_name}
      
      MySQL 접속 (Management Instance에서)
      mysql -h ${module.db.address} -P ${module.db.port} -u admin -p
  EOT
}