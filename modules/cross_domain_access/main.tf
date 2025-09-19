# Grant cross-domain access to specific table
resource "aws_lakeformation_permissions" "cross_domain_access" {
  principal   = var.consumer_role_arn
  permissions = ["SELECT", "DESCRIBE"]

  table {
    database_name = var.source_database_name
    name          = var.source_table_name
  }
}
