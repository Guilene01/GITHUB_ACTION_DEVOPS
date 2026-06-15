# Create a VPC
resource "aws_vpc" "my-vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "devops VPC"
  }
}

# Create Web Public Subnet
resource "aws_subnet" "web-subnet" {
  vpc_id                  = aws_vpc.my-vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
 // availability_zone       = "$a"

  tags = {
    Name = "devops-subnet"
  }
}

# Create Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.my-vpc.id

  tags = {
    Name = "devops IGW"
  }
}

# Create Web layber route table
resource "aws_route_table" "web-rt" {
  vpc_id = aws_vpc.my-vpc.id


  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "WebRT"
  }
}

# Create Web Subnet association with Web route table
resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.web-subnet.id
  route_table_id = aws_route_table.web-rt.id
}


# Create Web Security Group
resource "aws_security_group" "web-sg" {
  name        = "cicd-security-group"
  description = "Allow ssh inbound traffic"
  vpc_id      = aws_vpc.my-vpc.id

  ingress {
    description = "ssh from VPC"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "http port"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "JFrog Artifactory port"
    from_port   = 8082
    to_port     = 8082
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Trivy port"
    from_port   = 4954
    to_port     = 4954
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Vault port"
    from_port   = 8200
    to_port     = 8200
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "tools-server-sg"
    Owner = "Hermann90"
  }
}


# Latest Amazon Linux 2023 AMI
data "aws_ssm_parameter" "amzn2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# create ec2 instance
resource "aws_instance" "main-server" {
  ami                    = data.aws_ssm_parameter.amzn2023.value
 // instance_type          = var.aws_instance_type_server
  subnet_id              = aws_subnet.web-subnet.id
  vpc_security_group_ids = [aws_security_group.web-sg.id]
  key_name               = aws_key_pair.ec2-key.key_name
  

  # Attach role to Ec2 instance
  iam_instance_profile = aws_iam_instance_profile.tools_instance_profile.name

  # Set the instance's root volume to 50 GB
  root_block_device {
    volume_size = 50
  }


  tags = {
    Name        = "CICD-Server"
    owner       = "utrains"
    Environment = "dev"
  }

    provisioner "file" {
    source      = "${path.module}/installations_scripts"
    destination = "/home/ec2-user/"

    connection {
      type = "ssh"
      user = "ec2-user"
      private_key = file(local_file.ssh_key.filename)
      host        = self.public_ip
      timeout     = "1m"
    }
  }
}

# This Null Resource can install dos2unix and Docker
resource "null_resource" "install_docker" {

  # ssh into the ec2 instance 
  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = file(local_file.ssh_key.filename)
    host        = aws_instance.main-server.public_ip
  }
  # set permissions and run the  file
  provisioner "remote-exec" {
    
    inline = [
      "sudo yum update -y ",
      "sudo yum install dos2unix -y",
      
      "dos2unix /home/ec2-user/installations_scripts/*.sh",
      
      # Install docker
      "sh installations_scripts/install_docker.sh",
    ] 
  }
  # wait the main-server end his installation
  depends_on = [aws_instance.main-server, local_file.ssh_key]
}


# Wait for Docker to be installed before installing the rest of the toolchain.
resource "null_resource" "install_tools" {

  # ssh into the ec2 instance
  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = file(local_file.ssh_key.filename)
    host        = aws_instance.main-server.public_ip
  }
  # set permissions and run the  file
  provisioner "remote-exec" {

    inline = [
      "ls",
      "pwd",

      # Java/Maven runtime, required by JFrog Artifactory
      "sh installations_scripts/install_java.sh",

      # JFrog Artifactory (artifact repository for GitHub Actions to publish to)
      "sh installations_scripts/install_jfrog.sh",

      # Trivy (image/dependency vulnerability scanner)
      "sudo sh installations_scripts/install_trivy.sh",

      # HashiCorp Vault, then create a policy and an AppRole so GitHub Actions can read the secrets stored in Vault
     //"sudo sh installations_scripts/install_vault.sh ${var.jfrog_secret_username_and_password[0]} ${var.jfrog_secret_username_and_password[1]} ${var.jfrog_secret_token} ",
    ]

  }

  depends_on = [null_resource.install_docker, local_file.ssh_key]
}


resource "null_resource" "fetch_remote_file" {
   provisioner "local-exec" {
     command = "scp -o StrictHostKeyChecking=no -i ${local_file.ssh_key.filename} ec2-user@${aws_instance.main-server.public_ip}:/home/ec2-user/*.txt ."
   }

   depends_on = [null_resource.install_tools]
 }

