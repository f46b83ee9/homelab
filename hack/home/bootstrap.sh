#!/bin/bash

for item in 'cilium' 'coredns'; do
    echo -e "\n› Installing ${item} helm release"

    manifest=$(kubectl kustomize infrastructure/envs/home/${item})

    version=$(this=$manifest yq --null-input 'env(this) | select(.kind == "Application") | .spec.source.targetRevision')
    repo_url=$(this=$manifest yq --null-input 'env(this) | select(.kind == "Application") | .spec.source.repoURL')
    chart=$(this=$manifest yq --null-input 'env(this) | select(.kind == "Application") | .spec.source.chart')
    name=$(this=$manifest yq --null-input 'env(this) | select(.kind == "Application") | .metadata.name')
    namespace=$(this=$manifest yq --null-input 'env(this) | select(.kind == "Application") | .spec.destination.namespace')
    values=$(this=$manifest yq --null-input 'env(this) | select(.kind == "Application") |.spec.source.helm.valuesObject')

    helm repo add ${item} ${repo_url}

    printf "${values}" | helm upgrade --install ${name} ${item}/${chart} \
        --values - \
        --version==${version} \
        --namespace=${namespace}
done

echo -e "\n› Waiting for cilium to be ready"
kubectl rollout -n kube-system status ds/cilium --timeout=120s

echo -e "\n› Waiting for coredns to be ready"
kubectl rollout -n kube-system status deploy/coredns --timeout=120s

echo -e "\n› Applying argocd manifest"
kubectl apply -k bootstrap/clusters/home/argo-cd

echo -e "\n› Waiting for argo-server to be ready"
kubectl wait -n argocd --for=condition=ready pod --selector=app.kubernetes.io/name=argocd-server --timeout=120s
kubectl wait -n argocd --for=condition=ready pod --selector=app.kubernetes.io/name=argocd-application-controller --timeout=120s
kubectl wait -n argocd --for=condition=ready pod --selector=app.kubernetes.io/name=argocd-repo-server --timeout=120s

echo -e "\n› Waiting for crds to be ready"
kubectl wait -n argocd --for condition=established --timeout=60s crd/applications.argoproj.io
kubectl wait -n argocd --for condition=established --timeout=60s crd/applicationsets.argoproj.io
kubectl wait -n argocd --for condition=established --timeout=60s crd/appprojects.argoproj.io

echo -e "\n› Apply argocd custom resources (Apps & AppSets)"
kubectl apply -f bootstrap/clusters/home/argo-cd.yaml
kubectl apply -f bootstrap/clusters/home/root.yaml

echo -e "\n› Done!"