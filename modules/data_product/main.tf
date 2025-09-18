resource "aws_glue_catalog_database" "db" {
  name = "${var.product_name}_dp"
}

resource "aws_s3_object" "prefix" {
  bucket       = var.bucket_name
  key          = "products/${var.product_name}/"
  content      = ""
  content_type = "application/x-directory"
}

# Tag the database with domain LF-tag
resource "aws_lakeformation_resource_lf_tag" "db_domain_tag" {
  database { name = aws_glue_catalog_database.db.name }
  lf_tag {
    key   = var.lf_tag_domain_key
    value = var.product_name
  }
}

resource "aws_glue_crawler" "crawler" {
  count         = var.create_crawler ? 1 : 0
  name          = "${var.product_name}-crawler"
  role          = var.glue_crawler_role_arn
  database_name = aws_glue_catalog_database.db.name

  s3_target { path = "s3://${var.bucket_name}/products/${var.product_name}/" }

  configuration = jsonencode({
    Version       = 1.0,
    CrawlerOutput = { Partitions = { AddOrUpdateBehavior = "InheritFromTable" } }
  })
}

# Optional projected external table over raw stream events (for LF governance)
resource "aws_glue_catalog_table" "raw_projected" {
  name          = "${var.product_name}_raw"
  database_name = aws_glue_catalog_database.db.name

  table_type = "EXTERNAL_TABLE"
  parameters = {
    classification     = "json"
    EXTERNAL           = "TRUE"
    has_encrypted_data = "false"
  }

  storage_descriptor {
    location      = "s3://${var.bucket_name}/products/${var.product_name}/raw/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      name                  = "json"
      serialization_library = "org.openx.data.jsonserde.JsonSerDe"
    }

    columns {
      name = "op"
      type = "string"
    }
    columns {
      name = "keys"
      type = "struct<user_id:string,setting_key:string>"
    }
    columns {
      name = "new"
      type = "struct<user_id:string,setting_key:string,value:string,updated_at:string>"
    }
    columns {
      name = "old"
      type = "struct<user_id:string,setting_key:string,value:string,updated_at:string>"
    }
    columns {
      name = "ts"
      type = "string"
    }
  }
}

# Tag the raw table so LF grants apply (domain and pii=false for demo)
resource "aws_lakeformation_resource_lf_tag" "table_domain_tag" {
  table {
    database_name = aws_glue_catalog_database.db.name
    name          = aws_glue_catalog_table.raw_projected.name
  }
  lf_tag {
    key   = var.lf_tag_domain_key
    value = var.product_name
  }
}

resource "aws_lakeformation_resource_lf_tag" "table_pii_tag" {
  table {
    database_name = aws_glue_catalog_database.db.name
    name          = aws_glue_catalog_table.raw_projected.name
  }
  lf_tag {
    key   = var.lf_tag_pii_key
    value = "false"
  }
}


