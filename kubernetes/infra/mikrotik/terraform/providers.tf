terraform {
  required_version = ">= 1.8"

  required_providers {
    routeros = {
      source  = "terraform-routeros/routeros"
      version = "~> 1.98"
    }
  }

  # State stored in Kubernetes Secret "tfstate-default-mikrotik" in namespace infra
  # ServiceAccount tofu-mikrotik has RBAC permissions for this
  backend "kubernetes" {
    secret_suffix     = "mikrotik"
    namespace         = "infra"
    in_cluster_config = true
  }
}

provider "routeros" {
  hosturl  = "https://${var.mikrotik_host}"
  username = var.mikrotik_user
  password = var.mikrotik_password
  insecure = true # MikroTik self-signed cert
}
