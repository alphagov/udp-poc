# Data Mesh - Demo


Lake formation controls access to app settings using the following LF-tags:
* `domain` - app_settings, notifications
* `pii` - true|false

LF permissions (SELECT/DESCRIBE) decide “who can read which tables.”

S3 bucket policy grants LFs service-linked role list/get so Athena can read governed data

Data products (`modules/data_product`)
* Glue databases per product `*_dp`
* S3 prefix in data lake `products/app_settings`

App Layer (`modules/app_layer`)
* Dynamo `udp_app_settings` with streams
* Stream ingest lambda writes change events to s3
  * producer-to-lake pipeline; producers never get direct s3 access

Consumer Access (`modules/consumer_access`)
* LF tag-based permissions:
  * DESCRIBE on DATABASE 

Companion service (`modules/companion`)
* API + lambda that reads app settings through Athena
* Runs athena query in workgroup
* IAM limited to Athena + Glue catalog read + LF GetDataAccess + S3 only for Athena results
  * No direct s3 data permissions; access through Lake Formation + Athena

Athena still fetches files from S3. With LF enabled, Athena uses the LF service-linked role to access S3.

Next improvements (if you want)
- Add a small compaction job to write curated Parquet with stable schema and better performance.
- Use Lake Formation Governed Tables (Iceberg) for ACID upserts and faster freshness.
- Add row/column-level controls or masked views for PII handling.
- Add SSO group-based principals for human access, and per-team workgroups.