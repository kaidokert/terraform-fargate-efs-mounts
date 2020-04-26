variable "aws_region" {}
variable "cidr1" {}
variable "cidr2" {}

locals {
  family = "tf-run"
}

provider "aws" {
  region = var.aws_region
}
resource "aws_vpc" "test_vpc" {
  cidr_block = "${var.cidr1}/16"
}
resource "aws_subnet" "sub1" {
  vpc_id = aws_vpc.test_vpc.id
  cidr_block = "${var.cidr1}/24"
}
resource "aws_subnet" "sub2" {
  vpc_id = aws_vpc.test_vpc.id
  cidr_block = "${var.cidr2}/24"
}

resource "aws_security_group" "elb_sg" {
  vpc_id = aws_vpc.test_vpc.id
  name = "terraform-fargate-sg"
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
}

resource "aws_ecs_task_definition" "example" {
  family = local.family
  memory = "512"
  network_mode  = "awsvpc"
  cpu = "256"
  container_definitions = jsonencode([
    {
      essential = true
      name = "sample-app"
      image = "httpd:2.4"
      command = [
        "/bin/sh -c \"echo '<html><body><h1>Hello</h1></body></html>' > /usr/local/apache2/htdocs/index.html && httpd-foreground\"",
      ]
      portMappings = [{
        containerPort = 80
        hostPort      = 80
        protocol      = "tcp"
      }]
      environment       = []
      mountPoints       = []
      volumesFrom       = []
      logConfiguration  = {
        logDriver = "awslogs"
        options   = {
            awslogs-group         = "/ecs/${local.family}"
            awslogs-region        = var.aws_region
          }
      }
    }
  ])
}

resource "aws_ecs_service" "imported" {
  name = "sample-app-service"
  launch_type = "FARGATE"
  task_definition = aws_ecs_task_definition.example.arn
  desired_count = 1
  network_configuration {
      assign_public_ip = true
      security_groups = [ aws_security_group.elb_sg.id ]
      subnets = [
        aws_subnet.sub1.id, aws_subnet.sub2.id
      ]
  }
}