K8S_CTX            ?= kind-kind
absPathMakefile    = "$(abspath $(lastword $(MAKEFILE_LIST)))"
wd                 = `dirname $(absPathMakefile)`
WD                 := $(wd)/
BIN_DIR            ?= ../bin
REPO               ?= https://github.com/openbao/openbao.git
CLONE_DIR          := ./openbao-src
NAMESPACE          ?= external-secrets
VAULT_PATH         ?= kv-$(ENV)

VAULT_TOKEN        = $(MAKE) -C ../Vault ENV=$${ENV} env_token

.PHONY: all add_secret_store

all: setctx add_secret_store

default: all

setctx:
	@kubectl config use-context $(K8S_CTX) || exit 1
	@kubectl create namespace $(NAMESPACE) 2>/dev/null || true
	@kubectl create namespace $(BUILDKIT_NS) 2>/dev/null || true
	@kubectl config set-context --current --namespace $(NAMESPACE) >/dev/null



install:
	@helm repo add external-secrets https://charts.external-secrets.io
	@helm repo update
	helm install external-secrets \
   external-secrets/external-secrets \
    -n external-secrets \
    --create-namespace \
    --set installCRDs=false
	@kubectl apply -f "https://raw.githubusercontent.com/external-secrets/external-secrets/v1.1.0/deploy/crds/bundle.yaml" --server-side


add_secret_store: setctx
	#cat secretstore-tmpl.yaml | envsubst | tee  external-secret-store-$(NAMESPACE).yaml
	envsubst < secretstore-hashicloud-tmpl.yaml > external-secret-store-$(NAMESPACE).yaml
	kubectl replace -f external-secret-store-$(NAMESPACE).yaml || kubectl apply -f external-secret-store-$(NAMESPACE).yaml


test:
	echo > /dev/tcp/$${VAULT_HOSTNAME}/$${VAULT_PORT}
	make -c ../OpenBao/ test
