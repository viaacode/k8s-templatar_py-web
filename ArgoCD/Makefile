# defaults
CFG_REPO_URL  		?= CFG_GIT_REPO=https://github.com/viaacode/tkn-demo.git
REMOTE_CFG_DIR          := k8s-resources-remote
REPO_URL      		?= CFG_GIT_REPO=https://github.com/viaacode/tkn-demo.git
SVC_PORT      		?= 5000
IMAGE_NAME    		?= $(shell echo "$(FINAL_NAME)" | sed -E 's@[@].*$$@@; s@:[^/]*$$@@')
DRY_RUN       		?= --dry-run=client
APP_NAME                ?= cicd-helloworld-example
ENV          		?= qas
NAMESPACE     		?= meemoo-infra
ENVS          		:= int qas prd
REGISTRY_HOST 		?= meeregistrymoo.azurecr.io

#--- ArgoCD / config repo bootstrap -----------------------------------------
ARGOCD_NS            ?= argocd

# Choose auth mode: https or ssh
CFG_AUTH             := https

# HTTPS auth vars (CFG_AUTH=https)
CFG_GIT_USERNAME     ?= $${GIT_USER}
CFG_GIT_TOKEN        ?= $${GIT_PASSWORD}

# SSH auth vars (CFG_AUTH=ssh)
CFG_REPO_SSH_URL     ?=   # e.g. git@github.com:org/repo.git
CFG_GIT_SSH_KEY_FILE ?=   # path to deploy key file
NAMESPACE            ?= $(ARGOCD_NS)


.PHONY: generate-argocd argocd-deploy-root argocd-bootstrap argocd-apply-projects argocd-apply-repo-creds set-ns


# --- ArgoCD bootstrap: create repo creds + projects + (optionally) apply root-app
argocd-bootstrap: set-ns generate-argocd argocd-apply-repo-creds argocd-apply-projects argocd-deploy-root-env
all: set-ns login
default: generate-argocd argocd-deploy-root-env
# This target generates the ArgoCD manifests for each app/env
generate-argocd:

	@echo "__creating ArgoCD manifests__"
	@mkdir -p ../k8s-resources/argocd/applications/{int,qas,prd}
	@$(foreach env, $(ENVS), \
		ENV=$(env) envsubst < argocd-root-tmpl.yaml > ../k8s-resources/argocd/applications/$(env)/root-app.yaml; \
		$(foreach app, $(APPS), \
			APP_NAME=$(app) ENV=$(env) envsubst < argocd-child-tmpl.yaml > ../k8s-resources/argocd/applications/$(env)/$(app)-$(env).yaml; \
		) \
	)

argocd-deploy-root-env: set-ns
	 kubectl apply -f ../k8s-resources/argocd/applications/$(ENV)/root-app.yaml



deploy_app: set-ns argocd-apply-repo-creds
	#envsubst < argocd-child-tmpl.yaml | kubectl apply -f -
	kubectl apply -f ../k8s-resources/argocd/applications/qas/$(APP_NAME)-$(ENV).yaml

set-ns:
	@kubectl config use-context $(K8S_CTX)
	@kubectl create namespace $(NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -
	@kubectl config set-context --current --namespace=$(NAMESPACE)



argocd_password: set-ns
	NAMESPACE=argocd kubectl -n $(NAMESPACE) get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo ""



argocd_login: set-ns
	kubectl config set-context --current --namespace argocd
	bash -c 'argocd login --core'

test_argocd: argocd_login
	@argocd app list


test: set-ns test_argocd




argocd-apply-projects: argocd-apply-repo-creds
	@echo "__applying ArgoCD projects__"
	@for e in $(ENVS); do \
	  ENV=$$e ARGOCD_NS=$(ARGOCD_NS) envsubst < argocd-project-tmpl.yaml | kubectl apply -f - ; \
	done

argocd-apply-repo-creds:
	@echo "__applying ArgoCD config-repo credentials (CFG_AUTH=$(CFG_AUTH))__"
ifeq ($(CFG_AUTH),https)
	@ARGOCD_NS=$(ARGOCD_NS) CFG_GIT_USERNAME=$(CFG_GIT_USERNAME) CFG_GIT_TOKEN=$(CFG_GIT_TOKEN) envsubst < argocd-repo-https-secret-tmpl.yaml | kubectl apply -f -
else ifeq ($(CFG_AUTH),ssh)
	@if [ -z "$(CFG_GIT_SSH_KEY_FILE)" ]; then echo "CFG_GIT_SSH_KEY_FILE is required for CFG_AUTH=ssh"; exit 2; fi
	@export CFG_GIT_SSH_KEY_INDENTED="$$(sed 's/^/    /' $(CFG_GIT_SSH_KEY_FILE))" ; \
	ARGOCD_NS=$(ARGOCD_NS) CFG_GIT_SSH_KEY_INDENTED="$$CFG_GIT_SSH_KEY_INDENTED" envsubst < argocd-repo-ssh-secret-tmpl.yaml | kubectl apply -f -
else
	@echo "Unknown CFG_AUTH: $(CFG_AUTH) (use https or ssh)"; exit 2
endif



