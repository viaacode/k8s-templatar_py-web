# k8s-templator
## Kubernetes app bootstrap (go-template + kustomize + deploy with argocd)

This repo bootstraps a basic Kubernetes “web app” skeleton from a few templates:

- Generates **Deployment + Service + Ingress** using a `kubectl create deployment ... --dry-run=client` object rendered through a **Go template** (`app.gotmpl`)
- Creates a **kustomize** structure with:
  - `base/` (app manifests)
  - `overlays/{int,qas,prd}/` (env-specific config + ExternalSecret)
- Uses **External Secrets Operator** (`ExternalSecret`) to pull secrets from Vault.

The goal is to quickly scaffold a new app with sane defaults: health probes, resource limits, envFrom config, etc.

## USAGE
** Use make clean before building again !! **
the default image name is build like:
  - FINAL_NAME              ?= $(REGISTRY_HOST)/$(NAMESPACE)/$(APP_NAME):$(ENV)-latest
---
### Config
in Makefile:
 - For every app aad these mappings 
```
# App Metadata: Port and Source Code Repo, make these for every app in APPS list
app-1_PORT            := $(SVC_PORT)
app-1_REPO            := $(REPO_URL)
app-1_CFG_REPO        := $(CFG_REPO_URL)

app-n_PORT            := $(SVC_PORT)
app-n_REPO            := $(REPO_URL)
app-n_CFG_REPO        := $(CFG_REPO_URL)

```

### source env vars:
  - FINAL_NAME              <<< repo/ns/image:tag
  - APP_NAME
  - SVC_PORT
  - NAMESPACE
  - K8S_CTX <<<< this sets the cluster to talk too in multi cluster setup
  - REPO_URL
  - DRY_RUN << default: dry-run=client kubectl option
    - you can set other kubectl options here examples :
      - DRY_RUN='-o yaml' >> show the rendered yamls
      - DRY_RUN=''  >> this will remove dry run and deploy to cluster
  - CFG_REPO_URL  >> target namesapce config repo    
   
---
#### Examples
- ##### local build:
   - make clean build-all
- ##### remote push:
   - push_cfg   <<< this will run all steps:
     1. build the yamls and kustomize the images, configmaps etc
     2. clone the config repo
     3. rsync the APP dir and rsync the argocd dir to remote-dir
     4. pushes the code to the repo
---

## Requirements

- `kubectl`
- `kustomize` (optional; `kubectl apply -k` works with recent kubectl)
- `envsubst` (from `gettext`)
- External Secrets Operator installed in the cluster (for `ExternalSecret`)
- A configured `ClusterSecretStore` named `vault-backend`

---

## Repository layout

Templates and generator:

- `app.gotmpl` — Go template that outputs Deployment/Service/Ingress
- `generator.sh` — runs `kubectl create deployment ... --dry-run=client` and renders `app.gotmpl`
- `kustomization-tmpl.yaml` — base kustomization template
- `kustomization-overlay-env-tmpl.yaml` — overlay kustomization template
- `externalsecret-tmpl.yaml` — ExternalSecret template (Vault path per env)
- `app_envfile-tmpl` — env file template used by configMapGenerator
- `Makefile` — orchestration: bootstrap, deploy, clean

## Configuration and secrets

Config (ConfigMap):

- Each overlay uses configMapGenerator reading an env file:

- $APP_NAME/overlays/$ENV/client-config-$ENV.env etc.

The Deployment loads it via:

- ConfigMap name: ${APP_NAME}-${ENV}-config (matches the template output)

Secrets (Vault via ExternalSecret):

- Each overlay includes an ExternalSecret that creates a Secret consumed by the pod:
  - Secret name: ${APP_NAME}-${ENV}-vault

Vault key path convention:

/${NAMESPACE}/${APP_NAME}-${ENV}

Example:

namespace: hetarchief-v3

app: client

env: int

Vault key: /hetarchief-v3/client-int


## Usage

- edit the app_envfile-tmpl add all your envs

- make sure you have $APP_NAME $SVC_PORT $NAMESPACE $ENV set!

- run make bootsstrap to create the yamls

- run make int , to deploy int (dry run for now)


## List argocd apps in a given CONTEXT
use K8S_CTX=azure-aks-contextname to connect to the cluster 

``` 
k8s-templatar_py-web $ kubectl config get-contexts 
CURRENT   NAME                                                                                CLUSTER                                               AUTHINFO                                                                      NAMESPACE
*         aks-qas-auto                                                                        aks-qas-auto                                          clusterUser_rg-qas-eunorth_aks-qas-auto                                       argocd
          aks-tst                                                                             aks-tst                                               clusterUser_rg-hetarchief-tst_aks-tst                                         argocd
          ci-cd/c113-e-private-eu-de-containers-cloud-ibm-com:30227/IAM#tina.cochet@viaa.be   c113-e-private-eu-de-containers-cloud-ibm-com:30227   IAM#tina.cochet@viaa.be/c113-e-private-eu-de-containers-cloud-ibm-com:30227   ci-cd
          int-admin                                                                           int-admin-cluster                                     int-admin-user                                                                meemoo-infra
          int-bot                                                                             int-bot-cluster                                       int-bot-user                                                                  meemoo-infra
          int-helm                                                                            int-helm-cluster                                      int-helm-user                                                                 meemoo-infra
          kind-dev                                                                            kind-dev                                              kind-dev                                                                      
          kind-kind                                                                           kind-kind                                             kind-kind                                                                     hetarchief-v3
          mig_source                                                                          mig_source                                            mig_source                                                                    ci-cd
          mig_target                                                                          mig_target                                            mig_target

_______________________________________________________________________________________________________________________________________________

k8s-templatar_py-web $ K8S_CTX=aks-tst make test
Switched to context "aks-tst".
namespace/playground unchanged
Context "aks-tst" modified.
kubectl config set-context --current --namespace argocd
Context "aks-tst" modified.
bash -c 'argocd login --core'
Context 'kubernetes' updated
NAME                             CLUSTER                         NAMESPACE      PROJECT  STATUS     HEALTH    SYNCPOLICY  CONDITIONS                                                 REPO                                                         PATH                           TARGET
argocd/demo1                     https://kubernetes.default.svc  meemoo-infra   default  OutOfSync  Degraded  Auto        OrphanedResourceWarning,RepeatedResourceWarning,SyncError  https://github.com/viaacode/argoCD-demo-app.git              k8s-kustomize/                 HEAD
argocd/hetarchief-v3-client-qas  https://kubernetes.default.svc  hetarchief-v3  default  Synced     Degraded  Auto-Prune  OrphanedResourceWarning                                    https://github.com/viaacode/hetarchief-v3_k8s-resources.git  kustomize/client/overlays/qas  main
argocd/hetarchief-v3-hasura-qas  https://kubernetes.default.svc  hetarchief-v3  default  Synced     Degraded  Auto-Prune  OrphanedResourceWarning                                    https://github.com/viaacode/hetarchief-v3_k8s-resources.git  kustomize/hasura/overlays/qas  main
argocd/hetarchief-v3-proxy-qas   https://kubernetes.default.svc  hetarchief-v3  default  Synced     Degraded  Auto-Prune  OrphanedResourceWarning                                    https://github.com/viaacode/hetarchief-v3_k8s-resources.git  kustomize/proxy/overlays/qas   main
argocd/hetarchief-v3-qas         https://kubernetes.default.svc  argocd         default  Synced     Healthy   Auto-Prune  OrphanedResourceWarning                                    https://github.com/viaacode/hetarchief-v3_k8s-resources.git  argocd/qas                     main
argocd/playground-int            https://kubernetes.default.svc  argocd         default  Unknown    Healthy   Auto-Prune  ComparisonError,OrphanedResourceWarning                    https://github.com/viaacode/playground_k8s-resources.git     argocd/int                     main
argocd/playground-qas            https://kubernetes.default.svc  argocd         default  Unknown    Healthy   Auto-Prune  ComparisonError,OrphanedResourceWarning                    https://github.com/viaacode/playground_k8s-resources.git     argocd/qas                     main
argocd/vault                     https://kubernetes.default.svc  meemoo-infra   default  OutOfSync  Healthy   Manual      OrphanedResourceWarning                                    https://openbao.github.io/openbao-helm                                                      0.18.4
tina  k8s-templatar_py-web $ K8S_CTX=aks-qas-auto make test
Switched to context "aks-qas-auto".
namespace/playground unchanged
Context "aks-qas-auto" modified.
kubectl config set-context --current --namespace argocd
Context "aks-qas-auto" modified.
bash -c 'argocd login --core'
Context 'kubernetes' updated
NAME                   CLUSTER                         NAMESPACE  PROJECT  STATUS   HEALTH   SYNCPOLICY  CONDITIONS       REPO                                                      PATH        TARGET
argocd/playground-int  https://kubernetes.default.svc  argocd     default  Unknown  Healthy  Auto-Prune  ComparisonError  https://github.com/viaacode/playground_k8s-resources.git  argocd/int  main
argocd/playground-qas  https://kubernetes.default.svc  argocd     default  Unknown  Healthy  Auto-Prune  ComparisonError  https://github.com/viaacode/playground_k8s-resources.git  argocd/qas  main
```

