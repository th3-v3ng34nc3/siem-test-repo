provider "aws" {
  region = var.region
  default_tags {
    tags = {
      "Owner" : "Accuknox CDR collector"
    }
  }
}
