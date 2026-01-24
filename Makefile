## ___________________Usage___________________
# Use deploy for you ci app to set image tag
# Use DRY_RUN='' to disable dry run during deploy , use DRY_RUN='-o yaml' to view yamls that are created
#
# --- Global settings --------------------------------------------------------
K8S_CTX ?= aks-qas-auto
AKS_CTX ?= $(K8S_CTX)
# Export these so sub-makefiles can see them
export K8S_CTX
export LOCAL_DOMAIN 	:= az-$${ENV}.local

# defaults
CFG_REPO_URL  		?= https://github.com/viaacode/playground_k8s-resources.git
REMOTE_CFG_DIR          := k8s-resources-remote
REPO_URL      		?= https://github.com/viaacode/cicd-helloworld-example.git
SVC_PORT      		?= 5000
IMAGE_NAME    		?= $(shell echo "$(FINAL_NAME)" | sed -E 's@[@].*$$@@; s@:[^/]*$$@@')
DRY_RUN       		?= --dry-run=client
APP_NAME ?= cicd-helloworld-example
ENV          		?= qas
NAMESPACE     		?= meemoo-infra
ENVS          		:= int qas prd
REGISTRY_HOST 		?= meeregistrymoo.azurecr.io

FINAL_NAME              ?= REGISTRY_HOST/$(NAMESPACE)/$(APP_NAME):$(ENV)-latest


export ENVS REGISTRY_HOST FINAL_NAME APP_NAME SVC_PORT
#if you have the platform
#CD
#ARGOPW        		:= $(shell $(MAKE) -C /opt/cloudmigration/meePlatFormoo/CiCd/ArgoCD/ get-pass |tail -n2|head -n1)

#PREFIX names

PREFIX        		?= $(NAMESPACE)
SUFFIX        		?= $(ENV)

## configuration list of NAMESAPCE apps
APPS          		?= $(APP_NAME)

# App Metadata: Port and Source Code Repo, make these for every app in APPS list
cicd-helloworld-example_PORT      	:= $(SVC_PORT)
cicd-helloworld-example_REPO      	:= $(REPO_URL)
cicd-helloworld-example_CFG_REPO       	:= $(CFG_REPO_URL)


.PHONY: all set-ns build-all deploy-all-envs redeploy-all-envs undeploy-all-apps clone_appcode buildi pushi clone_cfg image2acr
all: set-ns build-all push_cfg


# Use this to push the image to azure registry
image2acr: clone buildi pushi

set-ns:
	@kubectl config use-context $(K8S_CTX)
	@kubectl create namespace $(NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -
	@kubectl config set-context --current --namespace=$(NAMESPACE)



clone_appcode:
	@rm -rf $(APP_NAME) 2>/dev/null || true
	@git clone $(REPO_URL) $(APP_NAME) || true


clone_cfg: build-all
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
	$(MAKE) generate-argocd
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

.PHONY: generate-argocd argocd-deploy-root
# This target generates the ArgoCD manifests for each app/env
generate-argocd:
	@echo "__creating ArgoCD manifests__"
	@mkdir -p k8s-resources/argocd/int k8s-resources/argocd/qas k8s-resources/argocd/prd
	@$(foreach env, $(ENVS), \
		ENV=$(env) envsubst < argocd-root-tmpl.yaml > k8s-resources/argocd/$(env)/root-app.yaml; \
		$(foreach app, $(APPS), \
			APP_NAME=$(app) ENV=$(env) envsubst < argocd-child-tmpl.yaml > k8s-resources/argocd/$(env)/$(app)-$(env).yaml; \
		) \
	)

argocd-deploy-root-env: set-ns generate-argocd
	 kubectl apply -f k8s-resources/argocd/$(ENV)/root-app.yaml

create_structure:
	  @$(foreach app, $(APPS), \
                echo "Building $(app)..."; \
                mv $(app) k8s-resources/kustomize/$(app); \
        )


export APP_NAME ENV FINAL_NAME NAMESPACE PREFIX SUFFIX CFG_REPO_URL

.PHONY: default bootstrap clean deploy int qas prd

# "make APP_NAME=my-app" → bootstrap
default: bootstrap kustomize_image

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
int: set-ns build-all lint argocd-deploy-root-env

qas: ENV=qas
qas: K8S_CTX=aks-qas-auto
qas: set-ns build-all lint argocd-deploy-root-env


#qas: set-ns clean build-all lint argocd-deploy-root-env

prd: ENV=prd
int: K8S_CTX=aks-tst
prd: set-ns build-all lint argocd-deploy-root-env


argocd_login: set-ns
	kubectl config set-context --current --namespace argocd
	bash -c 'argocd login --core'

test_argocd: argocd_login
	@argocd app list


test: set-ns test_argocd
