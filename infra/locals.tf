resource "random_id" "suffix" {
  byte_length = 2
}

locals {
  bucket_name = lower(replace("${var.project_name}-${random_id.suffix.hex}", "_", "-"))
}