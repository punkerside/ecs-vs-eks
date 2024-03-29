export NAME               = container-benchmark
export DOCKER_UID         = $(shell id -u)
export DOCKER_GID         = $(shell id -g)
export DOCKER_USER        = $(shell whoami)
export AWS_DEFAULT_REGION = us-east-1
export AWS_DOMAIN         = punkerside.io

export DOCKER_BUILDKIT    = 0
export KUBECONFIG         = /tmp/${NAME}

# creating base container images
base:
	@docker build -t ${NAME}:base -f docker/Dockerfile.base .
	@docker build -t ${NAME}:packer --build-arg IMG=${NAME}:base -f docker/Dockerfile.packer .
	@docker build -t ${NAME}:npm --build-arg IMG=${NAME}:base -f docker/Dockerfile.npm .
	@docker build -t $(shell aws sts get-caller-identity --query "Account" --output text).dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${NAME}:psql --build-arg IMG=${NAME}:base -f docker/Dockerfile.psql .

# customize test script
jmeter-gui:
	@xhost +
	@docker build -t ${NAME}:jmeter -f docker/Dockerfile.jmeter .
	@docker run -ti --rm -e DISPLAY=${DISPLAY} -v /tmp/.X11-unix:/tmp/.X11-unix -v ${PWD}:/app ${NAME}:jmeter bash

# creating vpc and container registry
vpc:
	@cd terraform/vpc/ && terraform init
	@cd terraform/vpc/ && terraform apply -var="name=${NAME}" -auto-approve

# creating psql server in rds
psql:
	@aws ecr get-login-password --region ${AWS_DEFAULT_REGION} | docker login --username AWS --password-stdin $(shell aws sts get-caller-identity --query "Account" --output text).dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com
	@docker push $(shell aws sts get-caller-identity --query "Account" --output text).dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${NAME}:psql
	@echo "${DOCKER_USER}:x:${DOCKER_UID}:${DOCKER_GID}::/app:/sbin/nologin" > passwd
	@cd terraform/psql/ && terraform init
	@cd terraform/psql/ && terraform apply -var="name=${NAME}" -auto-approve
	@make run-task

# provisioning database
run-task:
	aws ecs run-task --cluster ${NAME}-psql --task-definition ${NAME}-psql:$(shell aws ecs describe-task-definition --task-definition ${NAME}-psql --region ${AWS_DEFAULT_REGION} | jq -r .taskDefinition.revision) --launch-type="FARGATE" --network-configuration '{ "awsvpcConfiguration": { "securityGroups": ["$(shell aws ec2 describe-security-groups --region ${AWS_DEFAULT_REGION} --filter Name=group-name,Values=${NAME}-psql | jq -r .SecurityGroups[0].GroupId)"], "subnets": ["$(shell aws ec2 describe-subnets --filters "Name=tag:Name,Values=${NAME}-private-${AWS_DEFAULT_REGION}c" --query "Subnets[*].SubnetId" --region ${AWS_DEFAULT_REGION} | jq -r .[0])"]}}' --region ${AWS_DEFAULT_REGION}

# deploying demo application
deploy:
	@echo "${DOCKER_USER}:x:${DOCKER_UID}:${DOCKER_GID}::/app:/sbin/nologin" > passwd
	@docker run --rm -u ${DOCKER_UID}:${DOCKER_GID} -v ${PWD}/passwd:/etc/passwd:ro -v ${PWD}/app:/app ${NAME}:npm
	@docker build -t $(shell aws sts get-caller-identity --query "Account" --output text).dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${NAME}:latest --build-arg IMG=${NAME}:base -f docker/Dockerfile.latest .
	@aws ecr get-login-password --region ${AWS_DEFAULT_REGION} | docker login --username AWS --password-stdin $(shell aws sts get-caller-identity --query "Account" --output text).dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com
	@docker push $(shell aws sts get-caller-identity --query "Account" --output text).dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${NAME}:latest

# creating ecs cluster
ecs:
	@cd terraform/ecs/ && terraform init
	@cd terraform/ecs/ && terraform apply -var="name=${NAME}" -var="domain=${AWS_DOMAIN}" -auto-approve

# creating infrastructure for jmeter testing
jmeter:
	@cd terraform/jmeter/ && terraform init
	@cd terraform/jmeter/ && terraform apply -var="name=${NAME}" -auto-approve
	aws s3 sync docker/jmeter/ s3://container-benchmark-jmeter/







































# # creating and provisioning eks cluster
# eks:
# 	@echo "${DOCKER_USER}:x:${DOCKER_UID}:${DOCKER_GID}::/app:/sbin/nologin" > passwd
# 	@docker run --rm -u ${DOCKER_UID}:${DOCKER_GID} -v ${PWD}/passwd:/etc/passwd:ro -v ${PWD}/terraform/eks:/app ${NAME}:terraform init
# 	@docker run --rm -u ${DOCKER_UID}:${DOCKER_GID} -v ${PWD}/passwd:/etc/passwd:ro -v ${PWD}/terraform/eks:/app -e AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION} -e AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} -e AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} ${NAME}:terraform apply -var="name=${NAME}" -auto-approve
# 	@rm -rf ${KUBECONFIG}
# 	@aws eks update-kubeconfig --name ${NAME} --region ${AWS_DEFAULT_REGION}
# 	@kubectl rollout restart -n kube-system deployment coredns
# 	@kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
# 	@export NAME=${NAME} ACCOUNT_ID=$(shell aws sts get-caller-identity --query "Account" --output text) && envsubst < k8s/sa.yaml | kubectl apply -f -
# 	@helm repo add eks https://aws.github.io/eks-charts
# 	@helm repo update eks
# 	@helm install aws-load-balancer-controller eks/aws-load-balancer-controller -n kube-system --set clusterName=${NAME} --set serviceAccount.create=false --set serviceAccount.name=aws-load-balancer-controller --set region=${AWS_DEFAULT_REGION} --set vpcId=$(shell aws ec2 describe-vpcs --filters Name=tag:Name,Values=${NAME} --region ${AWS_DEFAULT_REGION} | jq -r .Vpcs[0].VpcId)
# 	@export NAME=${NAME} AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION} CERTIFICATE_ARN=$(shell aws acm list-certificates --query "CertificateSummaryList[?DomainName=='eks.punkerside.io'].CertificateArn" --output text --region ${AWS_DEFAULT_REGION}) DB_HOSTNAME=$(shell aws rds describe-db-instances --db-instance-identifier ${NAME} --region ${AWS_DEFAULT_REGION} | jq -r .DBInstances[0].Endpoint.Address) NAME=${NAME} ACCOUNT_ID=$(shell aws sts get-caller-identity --query "Account" --output text) && envsubst < k8s/app.yaml | kubectl apply -f -





# # destroy all infrastructure
# destroy:
# #	@export NAME=${NAME} AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION} CERTIFICATE_ARN=$(shell aws acm list-certificates --query "CertificateSummaryList[?DomainName=='eks.punkerside.io'].CertificateArn" --output text --region ${AWS_DEFAULT_REGION}) DB_HOSTNAME=$(shell aws rds describe-db-instances --db-instance-identifier ${NAME} --region ${AWS_DEFAULT_REGION} | jq -r .DBInstances[0].Endpoint.Address) NAME=${NAME} ACCOUNT_ID=$(shell aws sts get-caller-identity --query "Account" --output text) && envsubst < k8s/app.yaml | kubectl delete -f -
# 	@echo "${DOCKER_USER}:x:${DOCKER_UID}:${DOCKER_GID}::/app:/sbin/nologin" > passwd
# 	@docker run --rm -u ${DOCKER_UID}:${DOCKER_GID} -v ${PWD}/passwd:/etc/passwd:ro -v ${PWD}/terraform/jmeter:/app -e AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION} -e AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} -e AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} ${NAME}:terraform destroy -var="name=${NAME}" -auto-approve
# 	@docker run --rm -u ${DOCKER_UID}:${DOCKER_GID} -v ${PWD}/passwd:/etc/passwd:ro -v ${PWD}/terraform/ecs:/app -e AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION} -e AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} -e AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} ${NAME}:terraform destroy -var="name=${NAME}" -auto-approve
# 	@docker run --rm -u ${DOCKER_UID}:${DOCKER_GID} -v ${PWD}/passwd:/etc/passwd:ro -v ${PWD}/terraform/eks:/app -e AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION} -e AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} -e AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} ${NAME}:terraform destroy -var="name=${NAME}" -auto-approve
# 	@docker run --rm -u ${DOCKER_UID}:${DOCKER_GID} -v ${PWD}/passwd:/etc/passwd:ro -v ${PWD}/terraform/psql:/app -e AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION} -e AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} -e AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} ${NAME}:terraform destroy -var="name=${NAME}" -auto-approve
# 	@docker run --rm -u ${DOCKER_UID}:${DOCKER_GID} -v ${PWD}/passwd:/etc/passwd:ro -v ${PWD}/terraform/vpc:/app -e AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION} -e AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} -e AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} ${NAME}:terraform destroy -var="name=${NAME}" -auto-approve

# init:
# 	./quickstart.sh