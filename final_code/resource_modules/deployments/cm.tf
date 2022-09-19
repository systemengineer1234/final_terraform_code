# Resource: CloudWatch Agent ConfigMap
resource "kubernetes_config_map_v1" "cwagentconfig_configmap" {
  metadata {
    name = "cwagentconfig" 
    namespace = kubernetes_namespace_v1.amazon_cloudwatch.metadata[0].name 
  }
  data = {
    "cwagentconfig.json" = jsonencode({
      "logs": {
        "metrics_collected": {
          "kubernetes": {
            "metrics_collection_interval": 60
          }
        },
        "force_flush_interval": 5
      }
    })
  }
}

# Resource: FluentBit Agent ConfigMap
resource "kubernetes_config_map_v1" "fluentbit_configmap" {
  metadata {
    name = "fluent-bit-cluster-info"
    namespace = kubernetes_namespace_v1.amazon_cloudwatch.metadata[0].name 
  }
  data = {
    "cluster.name" = var.cluster_name
    "http.port"   = "2020"
    "http.server" = "On"
    "logs.region" = var.aws_region
    "read.head" = "Off"
    "read.tail" = "On"
  }
}

# Resource: Config Map
 resource "kubernetes_config_map_v1" "config_map" {
   metadata {
     name = "usermanagement-dbcreation-script"
   }
   data = {
    "webappdb.sql" = "${file("${path.module}/webappdb.sql")}"
   }
 } 