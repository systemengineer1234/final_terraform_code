terraform {
  required_version = "> 1.1"
 
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