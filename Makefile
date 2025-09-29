# -----------------------------
# Globals / variables
# -----------------------------

SHELL           := /bin/bash
GIT_SHA         := $(shell git rev-parse --short HEAD)

AWS_PROFILE     			?= default         					#Overwrite this in console when using makefile
BUCKET_OUTPUT   			?= bucket_name    					#defined in outputs.tf
COGNITO_ID      			?= cognito_id  						#defined in outputs.tf
COGNITO_DOMAIN_NAME         ?= cognito_domain_name  			#defined in outputs.tf
CLOUDFRONT_CALLBACK         ?= cloudfront_callback				#defined in outputs.tf

# Paths
FRONTEND_DIR    := frontend/src
ISSUER_DIR      := services/cookie-issuer
STACK_DIR       := infra
TFVARS          := env/prod.tfvars
RESTRICTED  := restricted
FRONTEND_ENV_FILE  := .env.production


# -----------------------------
# Frontend
# -----------------------------
.PHONY: install-frontend gen-frontend-env build-frontend publish-frontend
install-frontend:
	cd $(FRONTEND_DIR) && npm ci

gen-frontend-env: tf-init
	@set -euo pipefail; \
	cd $(FRONTEND_DIR); \
	cognito_id=$$(terraform -chdir=../../$(STACK_DIR) output -raw $(COGNITO_ID)); \
	cognito_domain_name=$$(terraform -chdir=../../$(STACK_DIR) output -raw $(COGNITO_DOMAIN_NAME)); \
	cloudfront_callback=$$(terraform -chdir=../../$(STACK_DIR) output -raw $(CLOUDFRONT_CALLBACK)); \
	test -n "$$cognito_id"; \
	test -n "$$cognito_domain_name"; \
	test -n "$$cloudfront_callback"; \
	{ \
	  echo "NEXT_PUBLIC_COGNITO_CLIENT_ID=$$cognito_id"; \
	  echo "NEXT_PUBLIC_COGNITO_DOMAIN=https://$$cognito_domain_name"; \
	  echo "NEXT_PUBLIC_REDIRECT_URI=$$cloudfront_callback"; \
	} > $(FRONTEND_ENV_FILE); \
	echo "Wrote $(FRONTEND_ENV_FILE)"

build-frontend: install-frontend gen-frontend-env
	cd $(FRONTEND_DIR) && npm run build

publish-frontend: build-frontend 
	@set -euo pipefail; \
	bucket=$$(terraform -chdir=$(STACK_DIR) output -raw $(BUCKET_OUTPUT)); \
	test -n "$$bucket" || { echo "Bucket output empty"; exit 1; }; \
	echo "Deploying to s3://$$bucket ..."; \
	cd $(FRONTEND_DIR) && \
	aws s3 sync ./out/ s3://$$bucket/ \
	  --delete --exclude "restricted/*" --exclude "*.html" \
	  --cache-control "public,max-age=31536000,immutable" \
	  --profile $(AWS_PROFILE) --only-show-errors; \
	aws s3 sync ./out/ s3://$$bucket/ \
	  --delete --exclude "restricted/*" --exclude "*" --include "*.html" \
	  --cache-control "public,max-age=60" \
	  --profile $(AWS_PROFILE) --only-show-errors; \
	aws s3 cp ../$(RESTRICTED)/index.html s3://$$bucket/restricted/index.html \
	  --cache-control "public,max-age=60" \
	  --content-type "text/html" \
	  --profile $(AWS_PROFILE) --only-show-errors

# -----------------------------
# Lambda (cookie issuer)
# -----------------------------
.PHONY: install-issuer build-issuer
install-issuer:
	cd $(ISSUER_DIR) && npm ci

build-issuer: install-issuer
	cd $(ISSUER_DIR) && npm run build

# -----------------------------
# Terraform (plan/apply uses artifact produced above)
# -----------------------------
.PHONY: tf-init tf-plan tf-apply tf-destroy
tf-init:
	terraform -chdir=$(STACK_DIR) init -upgrade=false

tf-plan: tf-init
	terraform -chdir=$(STACK_DIR) plan \
	  -var-file=$(TFVARS)

tf-apply: tf-init build-issuer
	terraform -chdir=$(STACK_DIR) apply -auto-approve \
	  -var-file=$(TFVARS)

tf-destroy: tf-init
	terraform -chdir=$(STACK_DIR) destroy -auto-approve \
	  -var-file=$(TFVARS)

# -----------------------------
# Convenience
# -----------------------------
.PHONY: release help destroy bootstrap
release: publish-frontend

bootstrap: tf-apply

help:
	@echo "Usage: make release"
	@echo "Runs infra + builds + deploys (all or nothing)."

destroy:
	@test "$(CONFIRM)" = "YES" || { \
	  echo "Refusing to destroy. Run: CONFIRM=YES make destroy"; exit 2; }
	$(MAKE) tf-destroy


ifeq ($(MAKELEVEL),0)
  ifneq ($(filter release help bootstrap destroy clean,$(MAKECMDGOALS)),)
    # ok
  else ifneq ($(MAKECMDGOALS),)
    $(error Use `make release`, `make bootstrap` (or `make help`))
  endif
endif

