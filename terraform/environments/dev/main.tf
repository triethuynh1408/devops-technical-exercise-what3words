terraform {
  required_version = ">= 1.5"

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
  }

  # Local state. One state file per environment directory, so a mistake in dev
  # can never touch prod. A real deployment would use a remote backend
  # (S3+DynamoDB, GCS, TFC) with locking — see DECISIONS.md.
}

provider "helm" {
  kubernetes = {
    config_path    = var.kubeconfig
    config_context = var.kube_context
  }
}

module "greeter" {
  source = "../../modules/greeter"

  release_name  = "greeter-dev"
  namespace     = "greeter-dev"
  greeting_name = var.greeting_name
  replica_count = var.replica_count
  image_tag     = var.image_tag
  node_port     = var.node_port
}
