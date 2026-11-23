#!/bin/bash

set -Eeuo pipefail

# Minikube deployment automation for Yarrow-Mullein Bank
# Uses Minikube image build so it works with containerd runtime.

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILE="${MINIKUBE_PROFILE:-minikube}"
DRIVER="${MINIKUBE_DRIVER:-docker}"

cd "$PROJECT_DIR"

echo "=========================================="
echo " Yarrow-Mullein Bank Kubernetes Deployment"
echo "=========================================="

# Check required commands
for command in minikube kubectl; do
    if ! command -v "$command" >/dev/null 2>&1; then
        echo "ERROR: $command is not installed."
        exit 1
    fi
done

# Start Minikube if it is not running
if ! minikube -p "$PROFILE" status | grep -q "Running"; then
    echo "Starting Minikube..."
    minikube start -p "$PROFILE" --driver="$DRIVER"
else
    echo "Minikube is already running."
fi

# Update kubectl context
minikube -p "$PROFILE" update-context

# Enable CPU metrics for Horizontal Pod Autoscalers
echo "Enabling metrics-server..."
minikube -p "$PROFILE" addons enable metrics-server

# Build application images inside Minikube
echo "Building Backend image..."
minikube -p "$PROFILE" image build -t backend:latest ./backend

echo "Building Transactions image..."
minikube -p "$PROFILE" image build -t transactions:latest ./transactions

echo "Building Student Portfolio image..."
minikube -p "$PROFILE" image build -t studentportfolio:latest ./studentportfolio

# Pull required public images
echo "Pulling MongoDB image..."
minikube -p "$PROFILE" image pull mongo:4.4.18

echo "Pulling Nginx image..."
minikube -p "$PROFILE" image pull nginx:alpine

# Verify required images
echo "Checking images in Minikube..."
minikube -p "$PROFILE" image ls

# Deploy MongoDB first
echo "Deploying MongoDB..."
kubectl apply -f k8s/mongo-service.yaml
kubectl apply -f k8s/mongo-statefulset.yaml

echo "Waiting for MongoDB..."
kubectl rollout status statefulset/mongo --timeout=180s

# Apply all remaining Kubernetes resources
echo "Applying Kubernetes manifests..."
kubectl apply -f k8s/

# Create a runtime Secret without storing its key in the repository
echo "Creating runtime backend Secret..."
kubectl create secret generic backend-secret \
    --from-literal=secret-key="$(openssl rand -hex 32)" \
    --dry-run=client -o yaml | kubectl apply -f -

# Restart application deployments to use the built images
echo "Restarting application deployments..."
kubectl rollout restart deployment/backend
kubectl rollout restart deployment/transactions
kubectl rollout restart deployment/studentportfolio
kubectl rollout restart deployment/nginx

# Wait for deployments
echo "Waiting for application deployments..."
kubectl rollout status deployment/backend --timeout=180s
kubectl rollout status deployment/transactions --timeout=180s
kubectl rollout status deployment/studentportfolio --timeout=180s
kubectl rollout status deployment/nginx --timeout=180s

# Display final status
echo ""
echo "=========================================="
echo " Deployment completed successfully!"
echo "=========================================="

echo "Pods:"
kubectl get pods -o wide

echo ""
echo "Services:"
kubectl get services

echo ""
echo "Horizontal Pod Autoscalers:"
kubectl get hpa

echo ""
echo "To open the application, run:"
echo "minikube service nginx"
echo ""
