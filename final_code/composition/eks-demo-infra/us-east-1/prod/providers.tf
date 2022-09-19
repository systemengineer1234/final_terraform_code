########################################
# Provider to connect to AWS
# https://www.terraform.io/docs/providers/aws/
########################################

terraform {
  required_version = "> 1.1"
  backend "s3" {} # use backend.config for remote backend

  required_providers {
    aws        = "> 4.0"
    random     = "~> 3.3"
    kubernetes = "~> 2.0"
    local      = "~> 2.2"
    null       = "~> 3.1"
    template   = "~> 2.1"
    helm       = "~> 2.0"
    kubectl    =  {
      source = "gavinbunney/kubectl"
      version = "1.14.0"
    }
  }
}

provider "aws" {
  region  = var.region
  profile = var.profile_name
}

# In case of not creating the cluster, this will be an incompletely configured, unused provider, which poses no problem.
# ref: https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs
provider "kubernetes" {
  # if you use default value of "manage_aws_auth = true" then you need to configure the kubernetes provider as per the doc: https://github.com/terraform-aws-modules/terraform-aws-eks/blob/v12.1.0/README.md#conditional-creation, https://github.com/terraform-aws-modules/terraform-aws-eks/issues/911
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = element(concat(data.aws_eks_cluster_auth.cluster[*].token, tolist([""])), 0)
#  load_config_file       = false # set to false unless you want to import local kubeconfig to terraform
 exec {
      api_version = "client.authentication.k8s.io/v1"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_id]
      command     = "aws"
    }
}

provider "helm" {
   kubernetes {
       # if you use default value of "manage_aws_auth = true" then you need to configure the kubernetes provider as per the doc: https://github.com/terraform-aws-modules/terraform-aws-eks/blob/v12.1.0/README.md#conditional-creation, https://github.com/terraform-aws-modules/terraform-aws-eks/issues/911
      host                   = module.eks.cluster_endpoint
      cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
      token                  = element(concat(data.aws_eks_cluster_auth.cluster[*].token, tolist([""])), 0)
#  load_config_file       = false # set to false unless you want to import local kubeconfig to terraform
 exec {
      api_version = "client.authentication.k8s.io/v1"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_id]
      command     = "aws"
    }
   }
}

provider "kubectl" {
     host                   = module.eks.cluster_endpoint
     cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
     token                  = element(concat(data.aws_eks_cluster_auth.cluster[*].token, tolist([""])), 0)
}