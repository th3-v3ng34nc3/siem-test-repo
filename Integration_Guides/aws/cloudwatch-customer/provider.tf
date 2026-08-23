provider "aws" {
  region = "us-west-2"
  alias  = "us_west_2"

  default_tags {
    tags = {
      "Owner" : "Accuknox CDR collector"
    }
  }
}