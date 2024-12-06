.PHONY: help
.DEFAULT_GOAL := help

help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

init: ## init terraform
	tofu init

plan: ## plan terraform and create plan file
	tofu plan -out=terraform.plan

apply: plan ## apply terraform based on the plan file
	tofu apply -auto-approve terraform.plan

