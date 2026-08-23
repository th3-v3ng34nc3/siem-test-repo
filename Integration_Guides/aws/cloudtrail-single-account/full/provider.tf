provider "aws" {
  region = "us-west-1"
  default_tags {
    tags = {
      "Owner": "Accuknox CDR collector"
    }
  }
}