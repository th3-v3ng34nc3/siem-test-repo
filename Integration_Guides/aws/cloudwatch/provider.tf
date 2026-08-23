provider "aws" {
  region = "us-west-1"
  alias  = "us_west_1"

  default_tags {
    tags = {
      "Owner" : "Accuknox CDR collector"
    }
  }
}