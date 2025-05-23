# Criando a VPC, Subnets, Internet Gateway, Network ACL e Tabelas de Rotas
module "main" {
  source                = "./modules/vpc/vpc"
  vpc_name              = "${var.project}-${var.environment}-vpc"
  vpc_cidr              = "10.0.0.0/16"
  public_subnet_a_cidr  = "10.0.1.0/24"
  public_subnet_b_cidr  = "10.0.2.0/24"
  private_subnet_a_cidr = "10.0.101.0/24"
  private_subnet_b_cidr = "10.0.102.0/24"
  region                = var.region
  project               = var.project
  environment           = var.environment
}

# Criando um Grupo de Segurança para containers
module "containers_security_group" {
  source              = "./modules/vpc/security_groups"
  security_group_name = "${var.project}-${var.environment}-containers-sg"
  vpc_id              = module.main.vpc_id
  project             = var.project
  environment         = var.environment
}

# Criando o Application Load Balancer, associando as subnets e grupo de segurança
module "alb" {
  source            = "./modules/alb/alb"
  alb_name          = "${var.project}-${var.environment}-alb"
  subnets           = [module.main.public_subnet_a_id, module.main.public_subnet_b_id]
  security_groups   = [module.containers_security_group.containers_sg_id]
  vpc_id            = module.main.vpc_id
  target_group_name = "${var.project}-${var.environment}-tg"
  target_group_port = 80
  health_check_path = "/"
  project           = var.project
  environment       = var.environment
}

# Criando o cluster ECS Fargate
module "fargate_cluster" {
  source       = "./modules/ecs/fargate"
  fargate_name = "${var.project}-${var.environment}-cluster"
  project      = var.project
  environment  = var.environment
}

# Criando o bucket s3 para os artefatos do build
module "artifacts_bucket" {
  source      = "./modules/s3/artifacts"
  bucket_name = "${var.project}-${var.environment}-artifacts.${var.domain}"
  environment = var.environment
  project     = var.project
}

# Criando a conexão com o GitHub
module "github_connection" {
  source          = "./modules/dev_tools/github_connection"
  connection_name = "github-connection"
  github_provider = "GitHub"

}

# Criando um repositório ECR 
module "ecr_repository" {
  source          = "./modules/ecr/repository"
  repository_name = "${var.project}-${var.environment}-ecr-repository"
  project         = var.project
  environment     = var.environment
}

# Criando as Roles para o CodeBuild e CodePipeline
module "iam" {
  source                       = "./modules/iam"
  codebuild_role_name          = "${var.project}-${var.environment}-codebuild-service-role"
  codebuild_policy_name        = "${var.project}-${var.environment}-codebuild-base-policy"
  codedeploy_role_name         = "${var.project}-${var.environment}-codedeploy-service-role"
  codedeploy_policy_name       = "${var.project}-${var.environment}-codedeploy-base-policy"
  codepipeline_role_name       = "${var.project}-${var.environment}-codepipeline-service-role"
  codepipipeline_policy_name   = "${var.project}-${var.environment}-codepipeline-base-policy"
  ecs_task_execution_role_name = "${var.project}-${var.environment}-ecs-task-execution-role"
  codestar_connection_arn      = module.github_connection.codestar_connection_arn
  bucket_arn                   = module.artifacts_bucket.bucket_arn
}

# Criando o CodeBuild
module "codebuild" {
  source                  = "./modules/dev_tools/codebuild"
  codebuild_name          = "${var.project}-${var.environment}-codebuild"
  codebuild_role_arn      = module.iam.codebuild_role_arn
  github_owner            = var.github_owner
  github_repo             = var.github_repo
  artifact_bucket         = module.artifacts_bucket.bucket_name
  artifact_path           = ""
  codestar_connection_arn = module.github_connection.codestar_connection_arn
  environment_variables = [
    { name = "AWS_REGION", value = "${var.region}" },
    { name = "AWS_ACCOUNT_ID", value = "${var.account_id}" },
    { name = "IMAGE_REPO_NAME", value = "${module.ecr_repository.ecr_repository_name}" },
    { name = "IMAGE_TAG", value = "latest" },
    { name = "CONTAINER_NAME", value = "${var.project}-${var.environment}-container" },
    { name = "ASPNETCORE_ENVIRONMENT", value = "Production" },
  ]
  project     = var.project
  environment = var.environment
}

# Criando a Task Definition com imagem e role
module "ecs_task_definition" {
  source             = "./modules/ecs/task_definition"
  family_name        = "${var.project}-${var.environment}-fargate-task"
  cpu                = "256"
  memory             = "512"
  container_image    = module.ecr_repository.ecr_image_url
  execution_role_arn = module.iam.ecs_execution_role_arn
  project            = var.project
  environment        = var.environment
}

# Criando o ECS Service com ALB e cluster
module "ecs_service" {
  source              = "./modules/ecs/service"
  service_name        = "${var.project}-${var.environment}-ecs-service"
  container_name      = "${var.project}-${var.environment}-container"
  cluster_id          = module.fargate_cluster.cluster_id
  task_definition_arn = module.ecs_task_definition.task_definition_arn
  desired_count       = 1
  subnets             = [module.main.public_subnet_a_id, module.main.public_subnet_b_id]
  security_group_id   = module.containers_security_group.containers_sg_id
  target_group_arn    = module.alb.target_group_arn
  alb_listener_arn    = module.alb.listener_arn
  project             = var.project
}

# Criando o CodePipeline
module "codepipeline" {
  source                = "./modules/dev_tools/codepipeline"
  codepipeline_name     = "${var.project}-${var.environment}-codepipeline"
  codepipeline_role_arn = module.iam.codepipeline_role_arn

  artifact_bucket = module.artifacts_bucket.bucket_name

  codestar_connection_arn = module.github_connection.codestar_connection_arn
  github_owner            = var.github_owner
  github_repo             = var.github_repo
  github_branch           = var.github_branch

  codebuild_project_name = module.codebuild.codebuild_project_name

  ecs_cluster_name = module.fargate_cluster.cluster_name
  ecs_service_name = module.ecs_service.service_name

  region      = var.region
  project     = var.project
  environment = var.environment
}

# Criando o certificado SSL
module "meusite_cert" {
  source      = "./modules/certificate_manager/meusite_cert"
  domain_name = "${var.project}.${var.domain}"
  project     = var.project
  environment = var.environment
}

# Criando o listener HTTPS do ALB
module "alb_listener" {
  source              = "./modules/alb/listener_https"
  acm_certificate_arn = module.meusite_cert.acm_certificate_arn
  alb_arn             = module.alb.alb_arn
  target_group_arn    = module.alb.target_group_arn
}

# Criando um alarme de 5xx do ALB
module "alb_5xx_alarm" {
  source            = "./modules/cloud_watch/alb_5xx_alarm"
  alarm_name        = "Respostas HTTP 5xx no ALB"
  alarm_description = "Alarme para erros 5xx no ALB"
  alb_name       = module.alb.alb_name
}

# Criando um alarme de uso de CPU do ECS
module "ecs_cpu_alarm" {
  source            = "./modules/cloud_watch/cpu_alarm"
  alarm_name        = "Uso de CPU no ECS"
  alarm_description = "Uso de CPU acima de 80% no ECS"
  cluster_name      = module.fargate_cluster.cluster_name
  service_name      = module.ecs_service.service_name
}

# Criando um alarme de uso de memória do ECS 
module "ecs_memory_alarm" {
  source            = "./modules/cloud_watch/memory_alarm"
  alarm_name        = "Uso de memória no ECS"
  alarm_description = "Uso de memória acima de 80% no ECS"
  cluster_name      = module.fargate_cluster.cluster_name
  service_name      = module.ecs_service.service_name
}