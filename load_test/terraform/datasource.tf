data "aws_ami" "ami-x86" {
  filter {
    name   = "name"
    values = ["*/ubuntu-noble-24.04-amd64-server*"]
  }

  most_recent = true
  owners      = ["099720109477"]
}

data "aws_subnet" "first_public" {
  id = var.public_subnet_ids[0]
}
