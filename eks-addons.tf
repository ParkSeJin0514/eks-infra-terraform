# ============================================================================
# eks-addons.tf - EKS Add-ons 설치 (ALB Controller, EFS CSI Driver)
# ============================================================================
# Helm으로 ALB Controller와 EFS CSI Driver를 설치합니다.
# OIDC Provider는 포함하지만, EFS 파일시스템 등은 포함하지 않습니다.
# ============================================================================

# ============================================================================
# OIDC Provider (IRSA 사용을 위해 필요)
# ============================================================================
# IAM Roles for Service Accounts (IRSA)를 사용하기 위한 OIDC Provider
# EKS 클러스터 생성 시 OIDC가 자동 활성화되지만,
# Terraform에서 IAM Role을 생성하려면 명시적으로 등록해야 합니다.
# ============================================================================

data "tls_certificate" "cluster" {
  url = module.eks.cluster_oidc_issuer_url
}

resource "aws_iam_openid_connect_provider" "cluster" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.cluster.certificates[0].sha1_fingerprint]
  url             = module.eks.cluster_oidc_issuer_url

  tags = {
    Name        = "${var.project_name}-eks-oidc"
    Project     = var.project_name
    Environment = "production"
    ManagedBy   = "terraform"
  }
}

# ============================================================================
# 1. AWS Load Balancer Controller
# ============================================================================

# ----------------------------------------------------------------------------
# 1-1. IAM Role for ALB Controller (IRSA)
# ----------------------------------------------------------------------------
module "alb_controller_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.48"

  role_name                              = "${var.project_name}-alb-controller"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = aws_iam_openid_connect_provider.cluster.arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }

  tags = {
    Project     = var.project_name
    Environment = "production"
    ManagedBy   = "terraform"
  }
}

# ----------------------------------------------------------------------------
# 1-2. Kubernetes Service Account for ALB Controller
# ----------------------------------------------------------------------------
resource "kubernetes_service_account" "alb_controller" {
  metadata {
    name      = "aws-load-balancer-controller"
    namespace = "kube-system"

    labels = {
      "app.kubernetes.io/name"      = "aws-load-balancer-controller"
      "app.kubernetes.io/component" = "controller"
    }

    annotations = {
      "eks.amazonaws.com/role-arn"               = module.alb_controller_irsa.iam_role_arn
      "eks.amazonaws.com/sts-regional-endpoints" = "true"
    }
  }

  depends_on = [module.eks]
}

# ----------------------------------------------------------------------------
# 1-3. Helm Release for ALB Controller
# ----------------------------------------------------------------------------
resource "helm_release" "alb_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "1.8.1"

  set {
    name  = "clusterName"
    value = module.eks.cluster_id
  }

  set {
    name  = "serviceAccount.create"
    value = "false"
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  set {
    name  = "region"
    value = "ap-northeast-2"
  }

  set {
    name  = "vpcId"
    value = module.network.vpc_id
  }

  set {
    name  = "image.repository"
    value = "602401143452.dkr.ecr.ap-northeast-2.amazonaws.com/amazon/aws-load-balancer-controller"
  }

  depends_on = [
    kubernetes_service_account.alb_controller
  ]
}

# ============================================================================
# 2. AWS EFS CSI Driver
# ============================================================================

# ----------------------------------------------------------------------------
# 2-1. IAM Role for EFS CSI Driver (IRSA)
# ----------------------------------------------------------------------------
module "efs_csi_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.48"

  role_name             = "${var.project_name}-efs-csi-driver"
  attach_efs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = aws_iam_openid_connect_provider.cluster.arn
      namespace_service_accounts = ["kube-system:efs-csi-controller-sa"]
    }
  }

  tags = {
    Project     = var.project_name
    Environment = "production"
    ManagedBy   = "terraform"
  }
}

# ----------------------------------------------------------------------------
# 2-2. Kubernetes Service Account for EFS CSI Driver
# ----------------------------------------------------------------------------
resource "kubernetes_service_account" "efs_csi_controller" {
  metadata {
    name      = "efs-csi-controller-sa"
    namespace = "kube-system"

    labels = {
      "app.kubernetes.io/name" = "aws-efs-csi-driver"
    }

    annotations = {
      "eks.amazonaws.com/role-arn" = module.efs_csi_irsa.iam_role_arn
    }
  }

  depends_on = [module.eks]
}

# ----------------------------------------------------------------------------
# 2-3. Helm Release for EFS CSI Driver
# ----------------------------------------------------------------------------
resource "helm_release" "efs_csi_driver" {
  name       = "aws-efs-csi-driver"
  repository = "https://kubernetes-sigs.github.io/aws-efs-csi-driver/"
  chart      = "aws-efs-csi-driver"
  namespace  = "kube-system"
  version    = "3.0.8"

  set {
    name  = "controller.serviceAccount.create"
    value = "false"
  }

  set {
    name  = "controller.serviceAccount.name"
    value = "efs-csi-controller-sa"
  }

  set {
    name  = "node.serviceAccount.create"
    value = "false"
  }

  set {
    name  = "node.serviceAccount.name"
    value = "efs-csi-controller-sa"
  }

  depends_on = [
    kubernetes_service_account.efs_csi_controller
  ]
}