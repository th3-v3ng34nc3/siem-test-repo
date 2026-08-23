
module "us_west_2" {
  source = "./accuknox-exporter"
  providers = {
    aws = aws.us_west_2
  }
  accuknox_suffix       = var.accuknox_suffix
  cloudwatch_target_url = var.cloudwatch_target_url
  chunk_size            = var.chunk_size
  insecure_tls          = var.insecure_tls
  line_limit            = var.line_limit
  log_groups            = var.log_groups
  username              = var.username
  password              = var.password
}