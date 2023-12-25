#!/bin/bash
sudo yum update -y
sudo yum install -y yum-utils
sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
sudo amazon-linux-extras install java-openjdk11 -y

# then install git
sudo yum install git -y

#then install terraform
sudo yum -y install terraform



# Install Docker
sudo yum install -y docker 
# Start and enable the Docker service
sudo systemctl start docker
sudo systemctl enable docker

# Add the current user to the docker group to run Docker without sudo
sudo usermod -aG docker $USER

#install docker-compose
# Download the latest version of Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
# Apply executable permissions to the downloaded binary
sudo chmod +x /usr/local/bin/docker-compose
# Create a symbolic link to the binary to make it available in your system path
sudo ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose

# 启动程序
cd ~
git clone https://github.com/Arvingrep/atlassian.git \
    && cd atlassian \
    && sudo  docker-compose up


