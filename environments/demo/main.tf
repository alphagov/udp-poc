terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}


provider "aws" {
  region = "eu-west-2"
  default_tags {
    tags = {
      POC = "UDP"
    }
  }
}

module "core" {
  source                = "../../modules/core"
  region                = "eu-west-2"
  bucket_name_prefix    = "udp-data-lake"
  athena_workgroup_name = "udp-demo-workgroup"
}

module "app_settings" {
  source                = "../../modules/data_product"
  product_name          = "app_settings"
  bucket_name           = module.core.s3_bucket_name
  lf_tag_domain_key     = module.core.lf_tag_domain_key
  lf_tag_pii_key        = module.core.lf_tag_pii_key
  glue_crawler_role_arn = module.core.glue_crawler_role_arn
}

module "notifications" {
  source                = "../../modules/data_product"
  product_name          = "notifications"
  bucket_name           = module.core.s3_bucket_name
  lf_tag_domain_key     = module.core.lf_tag_domain_key
  lf_tag_pii_key        = module.core.lf_tag_pii_key
  glue_crawler_role_arn = module.core.glue_crawler_role_arn
}

module "companion" {
  source               = "../../modules/consumer_access"
  consumer_role_arn    = module.core.data_consumer_role_arn
  lf_tag_domain_key    = module.core.lf_tag_domain_key
  lf_tag_pii_key       = module.core.lf_tag_pii_key
  allowed_domains      = ["app_settings", "notifications"]
  allow_non_pii_tables = true
}

module "app_layer" {
  source       = "../../modules/app_layer"
  bucket_name  = module.core.s3_bucket_name
  product_name = "app_settings"
}

module "companion_reader" {
  source         = "../../modules/companion"
  bucket_name    = module.core.s3_bucket_name
  product_name   = "app_settings"
  database_name  = "app_settings_dp"
  workgroup_name = module.core.athena_workgroup_name
}

module "companion_lf_access" {
  source               = "../../modules/consumer_access"
  consumer_role_arn    = module.companion_reader.companion_role_arn
  lf_tag_domain_key    = module.core.lf_tag_domain_key
  lf_tag_pii_key       = module.core.lf_tag_pii_key
  allowed_domains      = ["app_settings"]
  allow_non_pii_tables = true
}

# Grant DATA_LOCATION_ACCESS to Companion on the data lake bucket so Athena can read S3 through LF
resource "aws_lakeformation_permissions" "companion_location" {
  principal   = module.companion_reader.companion_role_arn
  permissions = ["DATA_LOCATION_ACCESS"]

  data_location {
    arn = module.core.s3_bucket_arn
  }
}
