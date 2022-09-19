resource "aws_cloudwatch_log_group" "this" {
  count             = length(var.cluster_enabled_log_types) > 0 && var.create_eks ? 1 : 0
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = var.cluster_log_retention_in_days
  kms_key_id        = var.cluster_log_kms_key_id
  tags              = var.tags
}

resource "aws_eks_cluster" "this" {
  count                     = var.create_eks ? 1 : 0
  name                      = var.cluster_name
  enabled_cluster_log_types = var.cluster_enabled_log_types
  role_arn                  = local.cluster_iam_role_arn
  version                   = var.cluster_version
  tags                      = var.tags

  vpc_config {
    security_group_ids      = compact([local.cluster_security_group_id])
    subnet_ids              = var.subnets
    endpoint_private_access = var.cluster_endpoint_private_access
    endpoint_public_access  = var.cluster_endpoint_public_access
    public_access_cidrs     = var.cluster_endpoint_public_access_cidrs
  }

  kubernetes_network_config {
    service_ipv4_cidr = var.cluster_service_ipv4_cidr
  }

  timeouts {
    create = var.cluster_create_timeout
    delete = var.cluster_delete_timeout
  }

  dynamic "encryption_config" {
    for_each = toset(var.cluster_encryption_config)

    content {
      provider {
        key_arn = encryption_config.value["provider_key_arn"]
      }
      resources = encryption_config.value["resources"]
    }
  }

  depends_on = [
    aws_security_group_rule.cluster_egress_internet,
    aws_security_group_rule.cluster_https_worker_ingress,
    aws_iam_role_policy_attachment.cluster_AmazonEKSClusterPolicy,
    aws_iam_role_policy_attachment.cluster_AmazonEKSServicePolicy,
    aws_iam_role_policy_attachment.cluster_AmazonEKSVPCResourceControllerPolicy,
    aws_cloudwatch_log_group.this
  ]
}

resource "aws_security_group_rule" "cluster_private_access" {
  count       = var.create_eks && var.cluster_create_endpoint_private_access_sg_rule && var.cluster_endpoint_private_access ? 1 : 0
  type        = "ingress"
  from_port   = 443
  to_port     = 443
  protocol    = "tcp"
  cidr_blocks = var.cluster_endpoint_private_access_cidrs

  security_group_id = aws_eks_cluster.this[0].vpc_config[0].cluster_security_group_id
}


resource "null_resource" "wait_for_cluster" {
  count = var.create_eks && var.manage_aws_auth ? 1 : 0

  depends_on = [
    aws_eks_cluster.this,
    aws_security_group_rule.cluster_private_access,
  ]

  provisioner "local-exec" {
    command     = var.wait_for_cluster_cmd
    interpreter = var.wait_for_cluster_interpreter
    environment = {
      ENDPOINT = aws_eks_cluster.this[0].endpoint
    }
  }
}

resource "aws_security_group" "cluster" {
  count       = var.cluster_create_security_group && var.create_eks ? 1 : 0
  name_prefix = var.cluster_name
  description = "EKS cluster security group."
  vpc_id      = var.vpc_id
  tags = merge(
    var.tags,
    {
      "Name" = "${var.cluster_name}-eks_cluster_sg"
    },
  )
}

resource "aws_security_group_rule" "cluster_egress_internet" {
  count             = var.cluster_create_security_group && var.create_eks ? 1 : 0
  description       = "Allow cluster egress access to the Internet."
  protocol          = "-1"
  security_group_id = local.cluster_security_group_id
  cidr_blocks       = ["0.0.0.0/0"]
  from_port         = 0
  to_port           = 0
  type              = "egress"
}

resource "aws_security_group_rule" "cluster_https_worker_ingress" {
  count                    = var.cluster_create_security_group && var.create_eks ? 1 : 0
  description              = "Allow pods to communicate with the EKS cluster API."
  protocol                 = "tcp"
  security_group_id        = local.cluster_security_group_id
  source_security_group_id = local.worker_security_group_id
  from_port                = 443
  to_port                  = 443
  type                     = "ingress"
}

resource "aws_iam_role" "cluster" {
  count                 = var.manage_cluster_iam_resources && var.create_eks ? 1 : 0
  name_prefix           = substr(var.cluster_name, 0,31)
  assume_role_policy    = data.aws_iam_policy_document.cluster_assume_role_policy.json
  permissions_boundary  = var.permissions_boundary
  path                  = var.iam_path
  force_detach_policies = true
  tags                  = var.tags
}

resource "aws_iam_role_policy_attachment" "cluster_AmazonEKSClusterPolicy" {
  count      = var.manage_cluster_iam_resources && var.create_eks ? 1 : 0
  policy_arn = "${local.policy_arn_prefix}/AmazonEKSClusterPolicy"
  role       = local.cluster_iam_role_name
}

resource "aws_iam_role_policy_attachment" "cluster_AmazonEKSServicePolicy" {
  count      = var.manage_cluster_iam_resources && var.create_eks ? 1 : 0
  policy_arn = "${local.policy_arn_prefix}/AmazonEKSServicePolicy"
  role       = local.cluster_iam_role_name
}

resource "aws_iam_role_policy_attachment" "cluster_AmazonEKSVPCResourceControllerPolicy" {
  count      = var.manage_cluster_iam_resources && var.create_eks ? 1 : 0
  policy_arn = "${local.policy_arn_prefix}/AmazonEKSVPCResourceController"
  role       = local.cluster_iam_role_name
}

/*
 Adding a policy to cluster IAM role that allow permissions
 required to create AWSServiceRoleForElasticLoadBalancing service-linked role by EKS during ELB provisioning
*/

data "aws_iam_policy_document" "cluster_elb_sl_role_creation" {
  count = var.manage_cluster_iam_resources && var.create_eks ? 1 : 0

  statement {
    effect = "Allow"
    actions = [
      "ec2:DescribeAccountAttributes",
      "ec2:DescribeInternetGateways"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "cluster_elb_sl_role_creation" {
  count       = var.manage_cluster_iam_resources && var.create_eks ? 1 : 0
  name_prefix = "${var.cluster_name}-elb-sl-role-creation"
  description = "Permissions for EKS to create AWSServiceRoleForElasticLoadBalancing service-linked role"
  policy      = data.aws_iam_policy_document.cluster_elb_sl_role_creation[0].json
  path        = var.iam_path
}

resource "aws_iam_role_policy_attachment" "cluster_elb_sl_role_creation" {
  count      = var.manage_cluster_iam_resources && var.create_eks ? 1 : 0
  policy_arn = aws_iam_policy.cluster_elb_sl_role_creation[0].arn
  role       = local.cluster_iam_role_name
}

#data.terraform_remote_state.eks.outputs.aws_iam_openid_connect_provider_arn
#data.terraform_remote_state.eks.outputs.aws_iam_openid_connect_provider_extract_from_arn

# Resource: Create EBS CSI IAM Policy 
resource "aws_iam_policy" "ebs_csi_iam_policy" {
  name        = "${local.name}-AmazonEKS_EBS_CSI_Driver_Policy"
  path        = "/"
  description = "EBS CSI IAM Policy"
  policy = data.http.ebs_csi_iam_policy.body
}

locals {
    aws_iam_oidc_connect_provider_extract_from_arn = element(split("oidc-provider/", var.enable_irsa ? concat(aws_iam_openid_connect_provider.oidc_provider[*].arn, [""])[0] : null), 1)
}

# Resource: Create IAM Role and associate the EBS IAM Policy to it
resource "aws_iam_role" "ebs_csi_iam_role" {
  name = "${local.name}-ebs-csi-iam-role"

  # Terraform's "jsonencode" function converts a Terraform expression result to valid JSON syntax.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Federated = var.enable_irsa ? concat(aws_iam_openid_connect_provider.oidc_provider[*].arn, [""])[0] : null
        }
        Condition = {
          StringEquals = {            
           "${local.aws_iam_oidc_connect_provider_extract_from_arn}:sub": "system:serviceaccount:kube-system:ebs-csi-controller-sa"
          }
        }        

      },
    ]
  })

  tags = {
    tag-key = "${local.name}-ebs-csi-iam-role"
  }
}

# Associate EBS CSI IAM Policy to EBS CSI IAM Role
resource "aws_iam_role_policy_attachment" "ebs_csi_iam_role_policy_attach" {
  policy_arn = aws_iam_policy.ebs_csi_iam_policy.arn 
  role       = aws_iam_role.ebs_csi_iam_role.name
}

# Install EBS CSI Driver using HELM
# Resource: Helm Release 
resource "helm_release" "ebs_csi_driver" {
  depends_on = [
    #aws_eks_node_group.eks_ng_1,
    #aws_iam_openid_connect_provider.oidc_provider,
    aws_iam_role.ebs_csi_iam_role
  ]
  name       = "aws-ebs-csi-driver"

  repository = "https://kubernetes-sigs.github.io/aws-ebs-csi-driver"
  chart      = "aws-ebs-csi-driver"

  namespace = "kube-system"     

  set {
    name = "image.repository"
    value = "602401143452.dkr.ecr.us-east-1.amazonaws.com/eks/aws-ebs-csi-driver" # Changes based on Region - This is for us-east-1 Additional Reference: https://docs.aws.amazon.com/eks/latest/userguide/add-ons-images.html
  }       

  set {
    name  = "controller.serviceAccount.create"
    value = "true"
  }

  set {
    name  = "controller.serviceAccount.name"
    value = "ebs-csi-controller-sa"
  }

  set {
    name  = "controller.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = "${aws_iam_role.ebs_csi_iam_role.arn}"
  }
    
}
/*
# Resource: EBS CSI Driver AddOn
# Install EBS CSI Driver using EKS Add-Ons (aws_eks_addon)
resource "aws_eks_addon" "ebs_eks_addon" {
  depends_on = [ aws_iam_role_policy_attachment.ebs_csi_iam_role_policy_attach]
  cluster_name = element(concat(aws_eks_cluster.this.*.id, tolist([""])), 0) 
  addon_name   = "aws-ebs-csi-driver"
  service_account_role_arn = aws_iam_role.ebs_csi_iam_role.arn 
}
*/
# Resource: Create AWS Load Balancer Controller IAM Policy 
resource "aws_iam_policy" "lbc_iam_policy" {
  name        = "AWSLoadBalancerControllerIAMPolicy"
  path        = "/"
  description = "AWS Load Balancer Controller IAM Policy"
  policy = data.http.lbc_iam_policy.body
}

resource "aws_iam_role" "lbc_iam_role" {
  name = "${local.name}-lbc-iam-role"

  # Terraform's "jsonencode" function converts a Terraform expression result to valid JSON syntax.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Federated = var.enable_irsa ? concat(aws_iam_openid_connect_provider.oidc_provider[*].arn, [""])[0] : null
        }
        Condition = {
          StringEquals = {
            "${local.aws_iam_oidc_connect_provider_extract_from_arn}:aud": "sts.amazonaws.com",            
            "${local.aws_iam_oidc_connect_provider_extract_from_arn}:sub": "system:serviceaccount:kube-system:aws-load-balancer-controller"
          }
        }        
      },
    ]
  })

  tags = {
    tag-key = "AWSLoadBalancerControllerIAMPolicy"
  }
}

# Associate Load Balanacer Controller IAM Policy to  IAM Role
resource "aws_iam_role_policy_attachment" "lbc_iam_role_policy_attach" {
  policy_arn = aws_iam_policy.lbc_iam_policy.arn 
  role       = aws_iam_role.lbc_iam_role.name
}

# Install AWS Load Balancer Controller using HELM

# Resource: Helm Release 
resource "helm_release" "loadbalancer_controller" {
  depends_on = [aws_iam_role.lbc_iam_role]            
  name       = "aws-load-balancer-controller"

  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"

  namespace = "kube-system"     

  # Value changes based on your Region (Below is for us-east-1)
  set {
    name = "image.repository"
    value = "602401143452.dkr.ecr.us-east-1.amazonaws.com/amazon/aws-load-balancer-controller" 
    # Changes based on Region - This is for us-east-1 Additional Reference: https://docs.aws.amazon.com/eks/latest/userguide/add-ons-images.html
  }       

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = "${aws_iam_role.lbc_iam_role.arn}"
  }

  set {
    name  = "vpcId"
    value = "${var.vpc_id}"
  }  

  set {
    name  = "region"
    value = "${var.aws_region}"
  }    

  set {
    name  = "clusterName"
    value = "${var.cluster_name}"
  }    
    
}

# Resource: Kubernetes Ingress Class
resource "kubernetes_ingress_class_v1" "ingress_class_default" {
  depends_on = [helm_release.loadbalancer_controller]
  metadata {
    name = "my-aws-ingress-class"
    annotations = {
      "ingressclass.kubernetes.io/is-default-class" = "true"
    }
  }  
  spec {
    controller = "ingress.k8s.aws/alb"
  }
}

## Additional Note
# 1. You can mark a particular IngressClass as the default for your cluster. 
# 2. Setting the ingressclass.kubernetes.io/is-default-class annotation to true on an IngressClass resource will ensure that new Ingresses without an ingressClassName field specified will be assigned this default IngressClass.  
# 3. Reference: https://kubernetes-sigs.github.io/aws-load-balancer-controller/v2.3/guide/ingress/ingress_class/

# Resource: Create External DNS IAM Policy 
resource "aws_iam_policy" "externaldns_iam_policy" {
  name        = "AllowExternalDNSUpdates"
  path        = "/"
  description = "External DNS IAM Policy"
  policy = jsonencode({
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "route53:ChangeResourceRecordSets"
      ],
      "Resource": [
        "arn:aws:route53:::hostedzone/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "route53:ListHostedZones",
        "route53:ListResourceRecordSets"
      ],
      "Resource": [
        "*"
      ]
    }
  ]
})
}

# Resource: Create IAM Role 
resource "aws_iam_role" "externaldns_iam_role" {
  name = "${local.name}-externaldns-iam-role"

  # Terraform's "jsonencode" function converts a Terraform expression result to valid JSON syntax.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Federated = var.enable_irsa ? concat(aws_iam_openid_connect_provider.oidc_provider[*].arn, [""])[0] : null
        }
        Condition = {
          StringEquals = {
            "${local.aws_iam_oidc_connect_provider_extract_from_arn}:aud": "sts.amazonaws.com",            
            "${local.aws_iam_oidc_connect_provider_extract_from_arn}:sub": "system:serviceaccount:default:external-dns"
          }
        }        
      },
    ]
  })

  tags = {
    tag-key = "AllowExternalDNSUpdates"
  }
}

# Associate External DNS IAM Policy to IAM Role
resource "aws_iam_role_policy_attachment" "externaldns_iam_role_policy_attach" {
  policy_arn = aws_iam_policy.externaldns_iam_policy.arn 
  role       = aws_iam_role.externaldns_iam_role.name
}

# Resource: Helm Release 
resource "helm_release" "external_dns" {
  depends_on = [aws_iam_role.externaldns_iam_role]            
  name       = "external-dns"

  repository = "https://kubernetes-sigs.github.io/external-dns/"
  chart      = "external-dns"

  namespace = "default"     

  set {
    name = "image.repository"
    value = "k8s.gcr.io/external-dns/external-dns" 
  }       

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = "external-dns"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = "${aws_iam_role.externaldns_iam_role.arn}"
  }

  set {
    name  = "provider" # Default is aws (https://github.com/kubernetes-sigs/external-dns/tree/master/charts/external-dns)
    value = "aws"
  }    

  set {
    name  = "policy" # Default is "upsert-only" which means DNS records will not get deleted even equivalent Ingress resources are deleted (https://github.com/kubernetes-sigs/external-dns/tree/master/charts/external-dns)
    value = "sync"   # "sync" will ensure that when ingress resource is deleted, equivalent DNS record in Route53 will get deleted
  }    
        
}# Resource: IAM Policy for Cluster Autoscaler
resource "aws_iam_policy" "cluster_autoscaler_iam_policy" {
  name        = "${local.name}-AmazonEKSClusterAutoscalerPolicy"
  path        = "/"
  description = "EKS Cluster Autoscaler Policy"

  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": [
                "autoscaling:DescribeAutoScalingGroups",
                "autoscaling:DescribeAutoScalingInstances",
                "autoscaling:DescribeInstances",
                "autoscaling:DescribeLaunchConfigurations",
                "autoscaling:DescribeTags",
                "autoscaling:SetDesiredCapacity",
                "autoscaling:TerminateInstanceInAutoScalingGroup",
                "ec2:DescribeLaunchTemplateVersions",
                "ec2:DescribeInstanceTypes"
            ],
            "Resource": "*",
            "Effect": "Allow"
        }
    ]
})
}

# Resource: IAM Role for Cluster Autoscaler
## Create IAM Role and associate it with Cluster Autoscaler IAM Policy
resource "aws_iam_role" "cluster_autoscaler_iam_role" {
  name = "${local.name}-cluster-autoscaler"

  # Terraform's "jsonencode" function converts a Terraform expression result to valid JSON syntax.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Federated = var.enable_irsa ? concat(aws_iam_openid_connect_provider.oidc_provider[*].arn, [""])[0] : null
        }
        Condition = {
          StringEquals = {
            "${local.aws_iam_oidc_connect_provider_extract_from_arn}:sub": "system:serviceaccount:kube-system:cluster-autoscaler"
          }
        }        
      },
    ]
  })

  tags = {
    tag-key = "cluster-autoscaler"
  }
}


# Associate IAM Policy to IAM Role
resource "aws_iam_role_policy_attachment" "cluster_autoscaler_iam_role_policy_attach" {
  policy_arn = aws_iam_policy.cluster_autoscaler_iam_policy.arn 
  role       = aws_iam_role.cluster_autoscaler_iam_role.name
}

# Install Cluster Autoscaler using HELM

# Resource: Helm Release 
resource "helm_release" "cluster_autoscaler_release" {
  depends_on = [aws_iam_role.cluster_autoscaler_iam_role ]            
  name       = "ca"

  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"

  namespace = "kube-system"   

  set {
    name  = "cloudProvider"
    value = "aws"
  }

  set {
    name  = "autoDiscovery.clusterName"
    value = element(concat(aws_eks_cluster.this.*.id, tolist([""])), 0)
  }

  set {
    name  = "awsRegion"
    value = var.aws_region
  }

  set {
    name  = "rbac.serviceAccount.create"
    value = "true"
  }

  set {
    name  = "rbac.serviceAccount.name"
    value = "cluster-autoscaler"
  }

  set {
    name  = "rbac.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = "${aws_iam_role.cluster_autoscaler_iam_role.arn}"
  }
  # Additional Arguments (Optional) - To Test How to pass Extra Args for Cluster Autoscaler
  #set {
  #  name = "extraArgs.scan-interval"
  #  value = "20s"
  #}    
   
}

# Install Kubernetes Metrics Server using HELM
# Resource: Helm Release 
resource "helm_release" "metrics_server_release" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  namespace = "kube-system"   
}