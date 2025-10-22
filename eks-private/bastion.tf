resource "aws_security_group" "bastion_sg" {
  name        = "bastion-sg"
  description = "Allow SSH access"
  vpc_id      = aws_vpc.eks_vpc.id

  ingress {
    description = "SSH from your IP"
    from_port   = 22
    to_port     = 22
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
    Name = "bastion-sg"
  }
}

resource "aws_instance" "bastion_host" {
  ami                         = "ami-04999cd8f2624f834"
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.public_subnets[0].id
  vpc_security_group_ids      = [aws_security_group.bastion_sg.id]
  associate_public_ip_address = true
  key_name                    = var.key_pair_name

  user_data = <<-EOF
              #!/bin/bash
              curl -O https://s3.us-west-2.amazonaws.com/amazon-eks/1.34.1/2025-09-19/bin/linux/amd64/kubectl
              chmod +x ./kubectl
              mkdir -p $HOME/bin && cp ./kubectl $HOME/bin/kubectl && export PATH=$HOME/bin:$PATH
              echo 'export PATH=$HOME/bin:$PATH' >> ~/.bashrc
              kubectl version --client
              ARCH=amd64
              PLATFORM=$(uname -s)_$ARCH
              curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$PLATFORM.tar.gz"
              tar -xzf eksctl_$PLATFORM.tar.gz -C /tmp && rm eksctl_$PLATFORM.tar.gz
              sudo mv /tmp/eksctl /usr/local/bin
              curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 > get_helm.sh
              chmod 700 get_helm.sh
              ./get_helm.sh
              helm version
              EOF

  tags = {
    Name = "bastion-host"
  }
}