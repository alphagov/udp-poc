output "database_name" {
  value       = aws_glue_catalog_database.db.name
  description = "Glue database name for the product"
}

output "s3_prefix" {
  value       = "s3://${var.bucket_name}/products/${var.product_name}/"
  description = "S3 prefix for the product"
}

output "crawler_name" {
  value       = try(aws_glue_crawler.crawler[0].name, null)
  description = "Glue crawler name (if created)"
}


