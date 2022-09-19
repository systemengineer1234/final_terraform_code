module "deployments" {
  source = "../../resource_modules/deployments"
#  name_app = var.name_app
  storage_size = var.storage_size
  cluster_name = var.cluster_name
}