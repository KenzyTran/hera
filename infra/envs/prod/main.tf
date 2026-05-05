provider "aws" {
  region = var.region
}

module "knowledge_base" {
  source = "../../modules/knowledge_base"

  name_prefix = var.name_prefix
  env         = var.env
  region      = var.region
}
