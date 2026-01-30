# --- ArgoCD / config repo bootstrap -----------------------------------------
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

FINAL_NAME              ?= $(REGISTRY_HOST)/$(NAMESPACE)/$(APP_NAME):$(ENV)-latest


export ENVS REGISTRY_HOST FINAL_NAME APP_NAME SVC_PORT

.PHONY: cfg-bootstrap cfg-sync cfg-push argocd-setup

.PHONY: all set-ns build-all deploy-all-envs redeploy-all-envs undeploy-all-apps clone_appcode buildi pushi clone_cfg image2acr

all: set-ns clean build-all deploy argocd-setup
#build-all push_cfg


cfg-bootstrap: clone_cfg cfg-sync cfg-push

.PHONY: default bootstrap clean deploy int qas prd
default: all

# "make APP_NAME=my-app" → bootstrap

# Sync local generated output into the config repo working tree
cfg-sync:
	@echo "__syncing generated manifests into config repo__"
	@mkdir -p $(REMOTE_CFG_DIR)/kustomize
	@mkdir -p $(REMOTE_CFG_DIR)/argocd/applications
	@mkdir -p $(REMOTE_CFG_DIR)/argocd/projects
	@mkdir -p $(REMOTE_CFG_DIR)/apps

	# kustomize overlays/bases
	@rsync -va --delete k8s-resources/kustomize/ $(REMOTE_CFG_DIR)/kustomize/

	# argo applications (your generated root/child apps)
	@rsync -va --delete k8s-resources/argocd/applications/ $(REMOTE_CFG_DIR)/argocd/applications/

	@echo "__done syncing__"

cfg-push:
	@echo "__pushing config repo__"
	@cd $(REMOTE_CFG_DIR) && \
	  git add . && \
	  (git diff --cached --quiet || git commit -m "Auto commit templatar") && \
	  git push


# --- Global settings --------------------------------------------------------
K8S_CTX ?= aks-qas-auto
AKS_CTX ?= $(K8S_CTX)
# Export these so sub-makefiles can see them
export K8S_CTX
export LOCAL_DOMAIN 	:= az-$${ENV}.local


#if you have the platform
#CD
#ARGOPW        		:= $(shell $(MAKE) -C /opt/cloudmigration/meePlatFormoo/CiCd/ArgoCD/ get-pass |tail -n2|head -n1)

#PREFIX names

PREFIX        		?= $(NAMESPACE)
SUFFIX        		?= $(ENV)

## configuration list of NAMESAPCE apps
APPS          		?= $(APP_NAME)

# App Metadata: Port and Source Code Repo, make these for every app in APPS list
tkn-demo_PORT      	:= $(SVC_PORT)
tkn-demo_REPO      	:= $(REPO_URL)
tkn-demo_CFG_REPO      	:= $(CFG_REPO_URL)



# Use this to push the image to azure registry
image2acr: clone_appcode buildi pushi

set-ns:
	@kubectl config use-context $(K8S_CTX)
	@kubectl create namespace $(NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -
	@kubectl config set-context --current --namespace=$(NAMESPACE)



clone_appcode:
	@rm -rf $(APP_NAME) 2>/dev/null || true
	@git clone $(REPO_URL) $(APP_NAME) || true


clone_cfg:
	@rm -rf $(REMOTE_CFG_DIR) 2>/dev/null || true
	@git clone $(CFG_REPO_URL) $(REMOTE_CFG_DIR) || true


build_cfg: clean clone_cfg
	@rsync -va --progress k8s-resources/kustomize/$(APP_NAME) $(REMOTE_CFG_DIR)/
	@rsync -va --progress k8s-resources/argocd $(REMOTE_CFG_DIR)/

buildi:
	FINAL_NAME=$(FINAL_NAME) APP_NAME=$(APP_NAME) docker build ./$(APP_NAME) -t $(FINAL_NAME)

pushi:
	FINAL_NAME=$(FINAL_NAME) docker push $(FINAL_NAME)

push_cfg: build_cfg
	cd $(REMOTE_CFG_DIR) && \
   git add .  && \
   git commit -m 'Auto commit templatar' && \
   git push



argocd-setup: set-ns
	$(MAKE) -C ArgoCD argocd-bootstrap argocd-apply-projects argocd-apply-repo-creds



# Example: Run templator and kustomize build for every app
build-all: set-ns
	@$(foreach app, $(APPS), \
		echo "--- Processing $(app) ---"; \
		APP_NAME=$(app) \
		SVC_PORT=$($(app)_PORT) \
		REPO_URL=$($(app)_REPO) \
		SUFFIX=$${ENV} \
		$(MAKE) bootstrap; \
		$(MAKE) deploy-all-envs APP_NAME=$(app) SVC_PORT=$($(app)_PORT) REPO_URL=$($(app)_CFG_REPO); \
	)
	$(MAKE) create_structure
	@echo "All resources generated in k8s-resources/"
	tree k8s-resources

# Helper to run deploy for all envs this sets the tag to $ENV
deploy-all-envs: set-ns
	@for e in $(ENVS); do \
		ENV=$$e $(MAKE) deploy; \
	done

redeploy-all-envs: set-ns
	@for e in $(ENVS); do \
                ENV=$$e $(MAKE) deploy; \
        done

undeploy-all-apps: set-ns
	@for e in $(APPS); do \
                APP_NAME=$$e $(MAKE) undeploy; \
        done

create_structure:
	  @$(foreach app, $(APPS), \
                echo "Building $(app)..."; \
                mv $(app) k8s-resources/kustomize/$(app); \
        )


export APP_NAME ENV FINAL_NAME NAMESPACE PREFIX SUFFIX CFG_REPO_URL



debug:
	echo $(IMAGE_NAME)
lint:
	kustomize build "k8s-resources/kustomize/$(APP_NAME)/overlays/$(ENV)" >/dev/null

bootstrap:
	@echo "Bootstrapping app '$(APP_NAME)' with image '$(FINAL_NAME)' in namespace '$(NAMESPACE)'..."
	@mkdir -p "./$(APP_NAME)/base"
	@for e in $(ENVS); do \
		mkdir -p "./$(APP_NAME)/overlays/$$e"; \
	done

	@echo "__running generator.sh__"
	@./generator.sh

	@echo "__creating base kustomization__"
	@envsubst < kustomization-tmpl.yaml > "./$(APP_NAME)/base/kustomization.yaml"

	@echo "__creating overlay kustomizations (int/qas/prd)__"
	@for e in $(ENVS); do \
		SUFFIX=$$e ENV=$$e envsubst < kustomization-overlay-env-tmpl.yaml > "./$(APP_NAME)/overlays/$$e/kustomization.yaml"; \
	done

	@echo "__adding ExternalSecret manifests__"
	@for e in $(ENVS); do \
		ENV=$$e envsubst < externalsecret-tmpl.yaml > "./$(APP_NAME)/overlays/$$e/$(APP_NAME)-$$e-externalsecret.yaml"; \
	done

	@echo "__adding app config env files__"
	@for e in $(ENVS); do \
		ENV=$$e envsubst < app_envfile-tmpl > "./$(APP_NAME)/overlays/$$e/$(APP_NAME)-config-$$e.env"; \
	done
	# Edit this to set limits and replicas
	@for e in $(ENVS); do \
		case $$e in \
		  int) REPLICAS=0 CPU_REQUEST=50m  MEM_REQUEST=64Mi  CPU_LIMIT=200m MEM_LIMIT=256Mi ;; \
		  qas) REPLICAS=1 CPU_REQUEST=100m MEM_REQUEST=128Mi CPU_LIMIT=250m MEM_LIMIT=384Mi ;; \
		  prd) REPLICAS=2 CPU_REQUEST=200m MEM_REQUEST=256Mi CPU_LIMIT=200m MEM_LIMIT=512Mi ;; \
		esac; \
		ENV=$$e REPLICAS=$$REPLICAS envsubst < patch-replicas-tmpl.yaml  > "./$(APP_NAME)/overlays/$$e/patch-replicas.yaml"; \
		ENV=$$e CPU_REQUEST=$$CPU_REQUEST MEM_REQUEST=$$MEM_REQUEST CPU_LIMIT=$$CPU_LIMIT MEM_LIMIT=$$MEM_LIMIT \
		  envsubst < patch-resources-tmpl.yaml > "./$(APP_NAME)/overlays/$$e/patch-resources.yaml"; \
	done

	@echo "__✅ created kustomize structure for $(APP_NAME)__"
	@echo "  - ./$(APP_NAME)/base"
	@echo "  - ./$(APP_NAME)/overlays/{int,qas,prd}"

clean:
	@echo "__🤟 removing $(APPS) dir __"
	rm -rf $(APPS)
	@echo "__✅ removed $(APPS) dir __"
	@$(foreach app, $(APPS), \
                echo "__🤟 Deletinging $(app)..."; \
                rm -rf k8s-resources/kustomize/$(app); \
        )

	@$(foreach e, $(ENVS), \
		rm -rf k8s-resources/argocd/$$e/*; \
	)
	@echo "__✅ removed $(APPS) dirs from k8s-resources/kustomize __"
	rm -rf $(REMOTE_CFG_DIR)

# Generic deploy uses ENV (int/qas/prd)
kustomize_image: bootstrap
	@echo "Deploying '$(APP_NAME)' to env '$(ENV)' with image '$(FINAL_NAME)'..."
	cd "./$(APP_NAME)/overlays/$(ENV)" &&  kustomize edit set image "$(FINAL_NAME)=$(REGISTRY_HOST)/$(NAMESPACE)/$(APP_NAME):$(ENV)" && \
  kubectl apply $(DRY_RUN) -k .

deploy: set-ns kustomize_image
	@echo "Deploying '$(APP_NAME)' to env '$(ENV)' with image '$(FINAL_NAME)'..."
	cd "./$(APP_NAME)/overlays/$(ENV)" && \
  kustomize edit set image "$(FINAL_NAME)=$(REGISTRY_HOST)/$(NAMESPACE)/$(APP_NAME):$(ENV)" && \
  kubectl apply $(DRY_RUN) -k .

undeploy: set-ns
	kubectl delete -l app=$(APP_NAME)  svc,deploy,ing

# Convenience targets; ENV is set here and used in deploy + templates
## K8S_CTX is important each env is in other cluster so set context !
int: ENV=int
int: K8S_CTX=aks-tst
int: set-ns
	$(MAKE) -C ArgoCD generate-argocd argocd-deploy-root-env deploy_app



#######################
qas: ENV=qas
qas: K8S_CTX=aks-qas-auto
qas: set-ns build-all kustomize_image lint

#############

prd: ENV=prd
int: K8S_CTX=aks-tst
prd: set-ns build-all lint -env




