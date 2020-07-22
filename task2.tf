# Variables

variable "vpc_cidr" {
    description = "CIDR for the whole VPC"
    default = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
    description = "CIDR for the Public Subnet"
    default = "10.0.1.0/24"
}

# VPC Creation 
resource "aws_vpc" "terravpc" {
    cidr_block = "${var.vpc_cidr}"
    enable_dns_hostnames = true
    tags = {
        Name = "terravpc"
    }
}

# Subnet Creation
resource "aws_subnet" "public" {
    vpc_id = "${aws_vpc.terravpc.id}"

    cidr_block = "${var.public_subnet_cidr}"
    availability_zone = "ap-south-1a"

    tags = {
        Name = "Public Subnet"
    }
}

# Internet Gateway
resource "aws_internet_gateway" "terraig" {
    vpc_id = "${aws_vpc.terravpc.id}"
	tags = {
	Name = "terraig"
	}
}

# Route Table
resource "aws_route_table" "ap-south-1a-public" {
    vpc_id = "${aws_vpc.terravpc.id}"

    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = "${aws_internet_gateway.terraig.id}"
    }

    tags = {
        Name = "Route"
    }
}

# Route Table Association
resource "aws_route_table_association" "a" {
    subnet_id = "${aws_subnet.public.id}"
    route_table_id = "${aws_route_table.ap-south-1a-public.id}"
}

# Security Group
resource "aws_security_group" "efs-ssh-http" {
  name        = "efs-ssh-http"
  description = "inbound and outbound traffic"
vpc_id = "${aws_vpc.terravpc.id}"

  ingress {
  description = "ssh"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

ingress {
  description = "efs"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  ingress {
  description = "http"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }


  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }
  tags = {
  Name = "efs-ssh-http"
  }
}

# Key Pair
resource "tls_private_key" "terrakey" {
    algorithm = "RSA"
}

module "key_pair" {

  source = "terraform-aws-modules/key-pair/aws"
  key_name   = "terrakey"
  public_key = tls_private_key.terrakey.public_key_openssh

}

resource "local_file" "privet_key" {
    content     =tls_private_key.terrakey.private_key_pem
    filename = "terrakey.pem"
}

# EFS File System
resource "aws_efs_file_system" "efs" {
  creation_token = "my-product"

  tags = {
    Name = "Myefs"
  }
}

# Mounting EFS 

resource "aws_efs_mount_target" "mountefs" {
  file_system_id = "${aws_efs_file_system.efs.id}"
  subnet_id      = "${aws_subnet.public.id}"
security_groups = ["${aws_security_group.efs-ssh-http.id}"]
}

# EC2 Creation

resource "aws_instance" "ec2os" {
  ami               = "ami-052c08d70def0ac62"
  instance_type     = "t2.micro"
  key_name = "terrakey"
  security_groups   = ["${aws_security_group.efs-ssh-http.id}"]
  availability_zone = "ap-south-1a"
  subnet_id = "${aws_subnet.public.id}"
  associate_public_ip_address = true
  tags = {
        Name = "MAINOS"
  }

# connecting to EC2 Instance
	connection {

	type = "ssh"
	user = "ec2-user"
	private_key = tls_private_key.terrakey.private_key_pem
	host = aws_instance.ec2os.public_ip

        }

# Remote Execution
	provisioner "remote-exec" {
		
		inline = [
		"sudo yum install httpd git -y",
        "sudo systemctl start httpd",
        "sudo systemctl enable httpd",
		    "sudo yum install -y amazon-efs-utils",
		    "sudo mount ${aws_efs_file_system.efs.id}: /var/www/html/",
        "sudo rm -rf /var/www/html/*",
		    "sudo git clone https://github.com/samiramazon/AWSwithTerraform.git   /var/www/html"
                
		]
	}
}

# S3 Bucket Creation

resource "aws_s3_bucket" "main2bucket" {
bucket = "bucket2main"
  acl    = "public-read"

  tags = {
	Name = "main2bucket"
  }
}

# S3 object

resource "aws_s3_bucket_object" "image" {
bucket = aws_s3_bucket.main2bucket.bucket
key = "image.png"
acl = "public-read"
source = "D:/New/image.png"
}

locals {
  s3_origin_id = "myterraS30riginn"
}

# CloudFront Distribution 
resource "aws_cloudfront_distribution" "terras3_distribution" {
  origin {
    domain_name = "${aws_s3_bucket.main2bucket.bucket_regional_domain_name}"
    origin_id   = "${local.s3_origin_id}"
  }
  
enabled             = true

default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "${local.s3_origin_id}"

    forwarded_values {
      query_string = true

      cookies {
        forward = "none"
      }
    }

viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }
  
ordered_cache_behavior {
    path_pattern     = "/content/immutable/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = "${local.s3_origin_id}"

    forwarded_values {
      query_string = false
      headers      = ["Origin"]

      cookies {
        forward = "none"
      }
    }

    min_ttl                = 0
    default_ttl            = 86400
    max_ttl                = 31536000
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
  }
  
restrictions {
    geo_restriction {
      restriction_type = "none"
          }
  }

  tags = {
    Environment = "production"
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}


