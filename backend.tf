terraform {
  backend "s3" {
    bucket = "terraform-atlassian"
    region = "ap-northeast-2"
    key = "atlassian-server/terraform.tfstate"
  }
  required_providers {
  # We recommend pinning to the specific version of the Docker Provider you're using
  # since new versions are released frequently
  docker = {
    source  = "kreuzwerker/docker"
    version = "3.0.2"
  }
}
}
