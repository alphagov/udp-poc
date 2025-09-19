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
  source                = "../../modules/core_simple"
  athena_workgroup_name = "udp-demo-workgroup"
}

module "app_settings" {
  source                = "../../modules/domain"
  domain_name           = "app_settings"
  lf_tag_domain_key     = module.core.lf_tag_domain_key
  lf_tag_pii_key        = module.core.lf_tag_pii_key
  glue_crawler_role_arn = module.core.glue_crawler_role_arn
}

module "notifications" {
  source                = "../../modules/domain"
  domain_name           = "notifications"
  lf_tag_domain_key     = module.core.lf_tag_domain_key
  lf_tag_pii_key        = module.core.lf_tag_pii_key
  glue_crawler_role_arn = module.core.glue_crawler_role_arn
}

# module "companion" {
#   source               = "../../modules/consumer_access"
#   consumer_role_arn    = module.core.data_consumer_role_arn
#   lf_tag_domain_key    = module.core.lf_tag_domain_key
#   lf_tag_pii_key       = module.core.lf_tag_pii_key
#   allowed_domains      = ["app_settings", "notifications"]
#   allow_non_pii_tables = true
# }

module "companion" {
  source                = "../../modules/domain"
  domain_name           = "companion"
  lf_tag_domain_key     = module.core.lf_tag_domain_key
  lf_tag_pii_key        = module.core.lf_tag_pii_key
  glue_crawler_role_arn = module.core.glue_crawler_role_arn
}

# Grant Companion access to App Settings domain (authorized cross-domain access)
module "companion_to_app_settings" {
  source               = "../../modules/cross_domain_access"
  consumer_role_arn    = module.companion.domain_role_arn
  source_domain        = "app_settings"
  target_domain        = "companion"
  source_database_name = module.app_settings.database_name
  source_table_name    = module.app_settings.table_name
  lf_tag_domain_key    = module.core.lf_tag_domain_key
  lf_tag_pii_key       = module.core.lf_tag_pii_key
}

# Grant Companion access to Notifications domain (authorized cross-domain access)
module "companion_to_notifications" {
  source               = "../../modules/cross_domain_access"
  consumer_role_arn    = module.companion.domain_role_arn
  source_domain        = "notifications"
  target_domain        = "companion"
  source_database_name = module.notifications.database_name
  source_table_name    = module.notifications.table_name
  lf_tag_domain_key    = module.core.lf_tag_domain_key
  lf_tag_pii_key       = module.core.lf_tag_pii_key
}

# No S3 data lake - each domain owns their data store
