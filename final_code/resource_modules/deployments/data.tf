locals {
  owners = var.business_divsion
  environment = var.environment
  name = "${var.business_divsion}-${var.environment}"
  common_tags = {
    owners = local.owners
    environment = local.environment
  }
  #eks_cluster_name = "${local.name}-${data.terraform_remote_state.eks.outputs.cluster_id}"  
} 

# Resource: Service Account, ClusteRole, ClusterRoleBinding

# Datasource
data "http" "get_cwagent_serviceaccount" {
  url = "https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/cwagent/cwagent-serviceaccount.yaml"
  # Optional request headers
  request_headers = {
    Accept = "text/*"
  }
}

# Datasource: kubectl_file_documents 
# This provider provides a data resource kubectl_file_documents to enable ease of splitting multi-document yaml content.
data "kubectl_file_documents" "cwagent_docs" {
    content = data.http.get_cwagent_serviceaccount.body
}

# Resource: kubectl_manifest which will create k8s Resources from the URL specified in above datasource
resource "kubectl_manifest" "cwagent_serviceaccount" {
    depends_on = [kubernetes_namespace_v1.amazon_cloudwatch]
    for_each = data.kubectl_file_documents.cwagent_docs.manifests
    yaml_body = each.value
}

# Resources: FluentBit 
## - ServiceAccount
## - ClusterRole
## - ClusterRoleBinding
## - ConfigMap: fluent-bit-config
## - DaemonSet

# Datasource
data "http" "get_fluentbit_resources" {
  url = "https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/fluent-bit/fluent-bit.yaml"
  # Optional request headers
  request_headers = {
    Accept = "text/*"
  }
}

# Datasource: kubectl_file_documents 
# This provider provides a data resource kubectl_file_documents to enable ease of splitting multi-document yaml content.
data "kubectl_file_documents" "fluentbit_docs" {
    content = data.http.get_fluentbit_resources.body
}
