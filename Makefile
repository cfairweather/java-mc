# Common operations. `make help` lists them.
SHELL := /bin/bash
.DEFAULT_GOAL := help

COMPOSE   ?= docker compose
TF_DIR    ?= infra/terraform
TF        ?= terraform -chdir=$(TF_DIR)
AWS_REGION ?= $(shell $(TF) output -raw region 2>/dev/null)
CLUSTER    ?= $(shell $(TF) output -raw ecs_cluster 2>/dev/null)
SERVICE    ?= $(shell $(TF) output -raw ecs_service 2>/dev/null)
IMAGE     ?= ghcr.io/cfairweather/java-mc
TAG       ?= $(shell git rev-parse --short HEAD)

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | sed 's/:.*## /\t/' | column -t -s $$'\t'

# ---------------------------------------------------------------- mods -------
.PHONY: resolve check-lock mrpack
resolve: ## Re-resolve mods/mods.txt against Modrinth (updates lock + listings)
	python3 scripts/resolve_mods.py

check-lock: ## Fail if mods/lock.json is out of date with mods/mods.txt
	python3 scripts/resolve_mods.py --check

mrpack: ## Build the client packs into dist/ (core and full)
	python3 scripts/build_mrpack.py --profile core
	python3 scripts/build_mrpack.py --profile full

# ---------------------------------------------------------------- local ------
.PHONY: up down restart logs ps rcon console whitelist-add whitelist-remove backup-now snapshots restore
up: .env ## Build and start the local server + backup sidecar
	$(COMPOSE) up -d --build

down: ## Stop the local stack (world data is kept in the mc-data volume)
	$(COMPOSE) down

restart: ## Restart the local server container
	$(COMPOSE) restart mc

logs: ## Tail local server logs
	$(COMPOSE) logs -f --tail=200 mc

ps: ## Show local container status
	$(COMPOSE) ps

rcon: ## Open an RCON shell on the local server
	$(COMPOSE) exec mc rcon-cli

console: ## Run one RCON command locally: make console CMD="list"
	$(COMPOSE) exec mc rcon-cli $(CMD)

whitelist-add: ## Whitelist a player locally now: make whitelist-add NAME=Steve
	scripts/whitelist.sh add $(NAME)

whitelist-remove: ## Remove a player locally now: make whitelist-remove NAME=Steve
	scripts/whitelist.sh remove $(NAME)

backup-now: ## Take a backup immediately (local stack)
	$(COMPOSE) exec backup backup now

snapshots: ## List restic snapshots (local stack)
	$(COMPOSE) exec backup restic snapshots

restore: ## Restore a snapshot into the local data volume: make restore SNAPSHOT=latest
	scripts/restore.sh $(SNAPSHOT)

.env:
	@echo "Copy .env.example to .env and set the passwords first." && exit 1

# ---------------------------------------------------------------- image ------
.PHONY: image push
image: ## Build the server image tagged $(IMAGE):$(TAG)
	docker build -t $(IMAGE):$(TAG) -t $(IMAGE):latest .

push: image ## Push the server image to GHCR
	docker push $(IMAGE):$(TAG)
	docker push $(IMAGE):latest

# ---------------------------------------------------------------- aws --------
.PHONY: tf-init tf-plan tf-apply tf-destroy deploy aws-status aws-logs aws-rcon aws-console aws-backup-now aws-snapshots aws-ssm
tf-init: ## terraform init
	$(TF) init

tf-plan: ## terraform plan
	$(TF) plan

tf-apply: ## terraform apply (creates or updates the AWS stack)
	$(TF) apply

tf-destroy: ## terraform destroy (backups in S3 are retained)
	$(TF) destroy

deploy: ## Roll the ECS service to the latest task definition / image
	aws ecs update-service --region $(AWS_REGION) --cluster $(CLUSTER) --service $(SERVICE) --force-new-deployment --no-cli-pager >/dev/null
	aws ecs wait services-stable --region $(AWS_REGION) --cluster $(CLUSTER) --services $(SERVICE)
	@echo "Deployed. Server address: $$($(TF) output -raw server_address)"

aws-status: ## Show ECS service / task status
	aws ecs describe-services --region $(AWS_REGION) --cluster $(CLUSTER) --services $(SERVICE) \
	  --query 'services[0].{status:status,running:runningCount,desired:desiredCount,taskDef:taskDefinition}' --output table

aws-logs: ## Tail server logs from CloudWatch
	aws logs tail --region $(AWS_REGION) $$($(TF) output -raw log_group) --follow --since 10m

aws-rcon: ## Open an RCON shell on the AWS server (ECS Exec)
	scripts/aws-exec.sh mc rcon-cli

aws-console: ## Run one RCON command on AWS: make aws-console CMD="whitelist add Steve"
	scripts/aws-exec.sh mc rcon-cli $(CMD)

aws-backup-now: ## Take a backup on AWS immediately
	scripts/aws-exec.sh backup backup now

aws-snapshots: ## List restic snapshots in S3
	scripts/aws-exec.sh backup restic snapshots

aws-ssm: ## Shell on the Bottlerocket host (SSM session)
	aws ssm start-session --region $(AWS_REGION) --target $$($(TF) output -raw instance_id)
