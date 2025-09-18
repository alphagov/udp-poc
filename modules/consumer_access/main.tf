resource "aws_lakeformation_permissions" "describe_databases_by_domain" {
  count       = length(var.allowed_domains) > 0 ? 1 : 0
  principal   = var.consumer_role_arn
  permissions = ["DESCRIBE"]

  lf_tag_policy {
    resource_type = "DATABASE"
    expression {
      key    = var.lf_tag_domain_key
      values = var.allowed_domains
    }
  }
}

resource "aws_lakeformation_permissions" "select_non_pii_tables" {
  count       = var.allow_non_pii_tables ? 1 : 0
  principal   = var.consumer_role_arn
  permissions = ["SELECT", "DESCRIBE"]

  lf_tag_policy {
    resource_type = "TABLE"
    expression {
      key    = var.lf_tag_pii_key
      values = ["false"]
    }
  }
}

# Optional: grant DESCRIBE on app_settings DB to companion (reuse module for companion by passing its role)


