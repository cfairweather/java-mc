terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
  # Recommended: keep state in S3. Uncomment and fill in, then `make tf-init`.
  # backend "s3" {
  #   bucket = "my-terraform-state"
  #   key    = "java-mc/terraform.tfstate"
  #   region = "us-west-2"
  # }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = merge({ Project = var.name, ManagedBy = "terraform" }, var.tags)
  }
}
