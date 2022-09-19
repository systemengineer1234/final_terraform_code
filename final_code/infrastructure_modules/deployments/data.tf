# Define Local Values in Terraform
locals {
  owners = var.business_divsion
  environment = var.environment
  name = "${var.business_divsion}-${var.environment}"
  common_tags = {
    owners = local.owners
    environment = local.environment
  }
#  eks_cluster_name = "${local.name}-${data.terraform_remote_state.eks.outputs.cluster_id}"  
} 

# Datasource: AWS Caller Identity
data "aws_caller_identity" "current" {}

# Datasource: EBS CSI IAM Policy get from EBS GIT Repo (latest)
data "http" "ebs_csi_iam_policy" {
  url = "https://raw.githubusercontent.com/kubernetes-sigs/aws-ebs-csi-driver/master/docs/example-iam-policy.json"

  # Optional request headers
  request_headers = {
    Accept = "application/json"
  }
}