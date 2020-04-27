variable "tf_region" {}
variable "tf_cidr" {}

locals {
  family = "terraform-task-definition"
}

provider "aws" {
  region = var.tf_region
}

resource "aws_iam_role" "test_exec_role" {
  name = "ecsTaskExecutionRole"
  force_detach_policies  = true
  assume_role_policy = jsonencode({
    Version   = "2008-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
      Sid = ""
    }]
  })
}

resource "aws_iam_policy_attachment" "test-attach" {
  name = "tf-ECSTaskExecutionRolePolicy"
  roles      = [aws_iam_role.test_exec_role.name]
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_vpc" "test_vpc" {
  cidr_block = "${var.tf_cidr}/16"
  enable_dns_hostnames = true
}

resource "aws_internet_gateway" "test_gateway" {
  vpc_id = aws_vpc.test_vpc.id
}

resource "aws_default_route_table" "test_route_table" {
  # vpc_id = aws_vpc.test_vpc.id
  default_route_table_id = aws_vpc.test_vpc.default_route_table_id
  route  {
    cidr_block                = "0.0.0.0/0"
    gateway_id                = aws_internet_gateway.test_gateway.id
  }
}

resource "aws_subnet" "test_subnet" {
  vpc_id = aws_vpc.test_vpc.id
  cidr_block = "${var.tf_cidr}/24"
}

resource "aws_security_group" "test_security_group" {
  vpc_id = aws_vpc.test_vpc.id
  name = "terraform-security-group"
  revoke_rules_on_delete = true
  egress {
    cidr_blocks      = [ "0.0.0.0/0"]
    protocol         = "-1"
    from_port        = 0
    to_port          = 0
  }
  ingress {
    cidr_blocks      = [ "0.0.0.0/0"]
    protocol = "tcp"
    from_port        = 80
    to_port          = 80
  }
  ingress {
    cidr_blocks      = [ "0.0.0.0/0"]
    protocol = "tcp"
    from_port        = 2049
    to_port          = 2049
  }
}

resource "aws_default_security_group" "test_security_group" {
  vpc_id = aws_vpc.test_vpc.id
  ingress {
    security_groups = [ aws_security_group.test_security_group.id ]
    protocol = "-1"
    from_port        = 0
    to_port          = 0
  }
}

resource "aws_cloudwatch_log_group" "test_log_group" {
  name =  "/ecs/${local.family}"
}

resource "aws_efs_file_system" "test_efs_file_system" {
  creation_token = "test_efs"
  depends_on = [ aws_subnet.test_subnet, aws_security_group.test_security_group ]
}

resource "aws_efs_mount_target" "test_mount_target" {
    file_system_id = aws_efs_file_system.test_efs_file_system.id
    subnet_id = aws_subnet.test_subnet.id
    security_groups = [ aws_security_group.test_security_group.id ]
}

resource "aws_ecs_task_definition" "test_ecs_task_definition" {
  family = local.family
  cpu = "256"
  memory = "512"
  network_mode  = "awsvpc"
  requires_compatibilities = [ "FARGATE" ]
  execution_role_arn = aws_iam_role.test_exec_role.arn
  container_definitions = jsonencode([{
    essential = true
    name = "terraform-app-container"
    image = "httpd:2.4"
    entryPoint = [ "sh", "-c"]
    command = [
      "/bin/sh -c \"df -h /mnt/efs > /usr/local/apache2/htdocs/index.html && httpd-foreground\""
    ]
    portMappings = [{
      containerPort = 80
      hostPort      = 80
      protocol      = "tcp"
    }]
    environment       = [{
      name = "VAR1"
      value = "VALUE1"
    }]
    mountPoints       = [
      {
        containerpath = "/mnt/efs"
        sourceVolume = "service-storage"
      }
    ]
    logConfiguration  = {
      logDriver = "awslogs"
      options   = {
          awslogs-group         = aws_cloudwatch_log_group.test_log_group.id
          awslogs-region        = var.tf_region
          awslogs-stream-prefix = "ecs"
        }
    }
  }])
  volume {
    name = "service-storage"
    efs_volume_configuration {
      file_system_id = aws_efs_file_system.test_efs_file_system.id
    }
  }
  depends_on = [
    aws_efs_mount_target.test_mount_target
  ]
}

resource "aws_ecs_cluster" "test_cluster" {
  name = "terraform-cluster"
  setting {
      name  = "containerInsights"
      value = "enabled"
  }
 }

resource "aws_ecs_service" "test_ecs_service" {
  name = "terraform-app-service"
  platform_version = "1.4.0"
  launch_type = "FARGATE"
  cluster = aws_ecs_cluster.test_cluster.id
  task_definition = aws_ecs_task_definition.test_ecs_task_definition.arn
  desired_count = 1
  network_configuration {
      assign_public_ip = true
      security_groups = [ aws_security_group.test_security_group.id ]
      subnets = [ aws_subnet.test_subnet.id ]
  }
}