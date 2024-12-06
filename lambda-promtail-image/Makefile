.PHONY: help
.DEFAULT_GOAL := help

REGION=us-east-1
AWS_ACCOUNT_ID=$(shell AWS_PAGER="" aws sts get-caller-identity --query Account --output text)
IMAGE_NAME=dnvriend-test-lambda-promtail-image
VERSION=dev

help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

build: ## build the docker image
	docker build -t $(AWS_ACCOUNT_ID).dkr.ecr.$(REGION).amazonaws.com/$(IMAGE_NAME):$(VERSION) .

shell: ## run a shell in the docker image
	docker run -it --entrypoint="" $(AWS_ACCOUNT_ID).dkr.ecr.$(REGION).amazonaws.com/$(IMAGE_NAME):$(VERSION) /bin/bash

login: ## login to ECR
	aws ecr get-login-password --region $(REGION) | docker login --username AWS --password-stdin $(AWS_ACCOUNT_ID).dkr.ecr.$(REGION).amazonaws.com

push: ## push the docker image to ECR
	docker push $(AWS_ACCOUNT_ID).dkr.ecr.$(REGION).amazonaws.com/$(IMAGE_NAME):$(VERSION)

sts: ## get STS credentials
	@AWS_PAGER="" aws sts get-caller-identity