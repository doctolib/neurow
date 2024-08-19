data "aws_ami" "ami-x86" {
  filter {
    name   = "name"
    values = ["amzn2-ami-kernel-*-hvm-*x86*"]
  }

  most_recent = true
  owners      = ["137112412989"]
}


data "aws_subnet" "first_public" {
  id = var.public_subnet_ids[0]
}
