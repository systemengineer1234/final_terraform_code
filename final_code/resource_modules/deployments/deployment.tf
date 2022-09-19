## Resource: Namespace
resource "kubernetes_namespace_v1" "amazon_cloudwatch" {
  metadata {
    name = "amazon-cloudwatch"
  }
}

# Resource: kubectl_manifest which will create k8s Resources from the URL specified in above datasource
resource "kubectl_manifest" "fluentbit_resources" {
  depends_on = [
    kubernetes_namespace_v1.amazon_cloudwatch,
    kubernetes_config_map_v1.fluentbit_configmap,
    kubectl_manifest.cwagent_daemonset
    ]
  for_each = data.kubectl_file_documents.fluentbit_docs.manifests    
  yaml_body = each.value
}

# Resource: MySQL Kubernetes Deployment
resource "kubernetes_deployment_v1" "mysql_deployment" {
  metadata {
    name = "mysql"
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "mysql"
      }          
    }
    strategy {
      type = "Recreate"
    }  
    template {
      metadata {
        labels = {
          app = "mysql"
        }
      }
      spec {
        volume {
          name = "mysql-persistent-storage"
          persistent_volume_claim {
            #claim_name = kubernetes_persistent_volume_claim_v1.pvc.metadata.0.name # THIS IS NOT GOING WORK, WE NEED TO GIVE PVC NAME DIRECTLY OR VIA VARIABLE, direct resource name reference will fail.
            claim_name = "ebs-mysql-pv-claim"
          }
        }
        volume {
          name = "usermanagement-dbcreation-script"
          config_map {
            name = kubernetes_config_map_v1.config_map.metadata.0.name 
          }
        }
        container {
          name = "mysql"
          image = "mysql:5.6"
          port {
            container_port = 3306
            name = "mysql"
          }
          env {
            name = "MYSQL_ROOT_PASSWORD"
            value = "dbpassword11"
          }
          volume_mount {
            name = "mysql-persistent-storage"
            mount_path = "/var/lib/mysql"
          }
          volume_mount {
            name = "usermanagement-dbcreation-script"
            mount_path = "/docker-entrypoint-initdb.d" #https://hub.docker.com/_/mysql Refer Initializing a fresh instance                                            
          }
        }
      }
    }      
  }
  
}

# Resource: UserMgmt WebApp Kubernetes Deployment
resource "kubernetes_deployment_v1" "usermgmt_webapp" {
  depends_on = [kubernetes_deployment_v1.mysql_deployment]
  metadata {
    name = "usermgmt-webapp"
    labels = {
      app = "usermgmt-webapp"
    }
  }
 
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "usermgmt-webapp"
      }
    }
    template {
      metadata {
        labels = {
          app = "usermgmt-webapp"
        }
      }
      spec {
        container {
          image = "stacksimplify/kube-usermgmt-webapp:1.0.0-MySQLDB"
          name  = "usermgmt-webapp"
          #image_pull_policy = "always"  # Defaults to Always so we can comment this
          port {
            container_port = 8080
          }
          env {
            name = "DB_HOSTNAME"
            #value = "mysql"
            value = kubernetes_service_v1.mysql_clusterip_service.metadata.0.name 
          }
          env {
            name = "DB_PORT"
            #value = "3306"
            value = kubernetes_service_v1.mysql_clusterip_service.spec.0.port.0.port
          }
          env {
            name = "DB_NAME"
            value = "webappdb"
          }
          env {
            name = "DB_USERNAME"
            value = "root"
          }
          env {
            name = "DB_PASSWORD"
            #value = "dbpassword11"
            value = kubernetes_deployment_v1.mysql_deployment.spec.0.template.0.spec.0.container.0.env.0.value
          }          
        }
      }
    }
  }
}
