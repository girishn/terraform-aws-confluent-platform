terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws        = { source = "hashicorp/aws" }
    kubernetes = { source = "hashicorp/kubernetes" }
    helm       = { source = "hashicorp/helm" }
    null       = { source = "hashicorp/null" }
    local      = { source = "hashicorp/local" }
  }
}

provider "aws" {
  region = var.region
}

provider "null" {}
provider "local" {}

