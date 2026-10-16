# Loads CONFLUENT_CLOUD_API_KEY / CONFLUENT_CLOUD_API_SECRET from .env for Terraform.
include .env
export

.PHONY: help infra url status destroy

help:
	@echo "make infra      provision Confluent Cloud + AWS hosting, print the dashboard URL"
	@echo "make url        print the dashboard URL"
	@echo "make status     show Flink statement status"
	@echo "make destroy    tear everything down (Confluent + AWS)"

infra:
	cd terraform && terraform init -upgrade && terraform apply -auto-approve
	@$(MAKE) -s url

url:
	@cd terraform && terraform output -raw dashboard_url && echo

status:
	./scripts/flink-status.sh

destroy:
	cd terraform && terraform destroy -auto-approve
