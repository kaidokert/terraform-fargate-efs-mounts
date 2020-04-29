### Terraform code to set up a Fargate container with EFS mount

Terrform based on https://github.com/mantalus/fargate-efs 

This is hackish TF attempt first setting up network resources in a minimally workable config,
and then second half actually creating the EFS and Fargate / ECS blocks

To deploy, change the `"region"` and `"cidr"` variables in .tfvars, and run 

`terraform plan`

To tear it down

`terraform destroy`

Note: Destroy tends to get stuck on the very last item, deleting a security group, due to
some weird invisible resource sticking to it. Manually deleting the VPC works around it.