#!/bin/bash
set -e

echo "============================================================"
echo "🚮 Cleaning Up Kubernetes + ArgoCD + Namespaces"
echo "============================================================"

# Stop and delete any existing Minikube cluster
minikube stop || true
minikube delete || true

# Remove any leftover kube context
kubectl config delete-context minikube || true

echo
echo "============================================================"
echo "🧱 Restarting Fresh Minikube Cluster"
echo "============================================================"
minikube start --driver=docker

echo
echo "============================================================"
echo "🧰 Installing ArgoCD via Helm"
echo "============================================================"
# Install Helm if not installed
if ! command -v helm &> /dev/null; then
  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

# Add and update Argo repo
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

# Create ArgoCD namespace and install
kubectl create namespace argocd || true
helm install argocd argo/argo-cd -n argocd

echo
echo "============================================================"
echo "⏳ Waiting for ArgoCD to be Ready..."
echo "============================================================"
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd

echo
echo "============================================================"
echo "🔑 Getting ArgoCD Admin Password"
echo "============================================================"
ARGO_PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
echo "ArgoCD Admin Password: $ARGO_PASS"

echo
echo "============================================================"
echo "🌐 Starting ArgoCD Port Forward in Background"
echo "============================================================"
if ! lsof -i :8080 >/dev/null 2>&1; then
  kubectl port-forward svc/argocd-server -n argocd 8080:80 >/dev/null 2>&1 &
  sleep 5
fi

echo
echo "============================================================"
echo "🎯 ArgoCD Ready!"
echo "============================================================"
echo "➡️  Open: http://localhost:8080"
echo "👤 User: admin"
echo "🔑 Password: $ARGO_PASS"
echo "============================================================"

echo "✅ Cluster and ArgoCD setup completed successfully!"
