# Bootstrap: the bucket that holds the Terraform state of every stack in this
# repository, this one included. First run uses local state (see README,
# "Bootstrap"), then the state moves into the bucket it created.

module "state_bucket" {
  source = "../../modules/state-bucket"

  bucket_name = var.state_bucket_name
}
