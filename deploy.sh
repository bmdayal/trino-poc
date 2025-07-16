#!/bin/bash

# Exit on error
set -e

# Load environment variables
source .env

# Create ECR repository if it doesn't exist
aws ecr describe-repositories --repository-names trino-api || \
    aws ecr create-repository --repository-name trino-api

# Get ECR login token and login
aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

# Build and push Docker image
docker build -t trino-api .
docker tag trino-api:latest ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/trino-api:latest
docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/trino-api:latest

# Create EKS cluster if it doesn't exist
eksctl get cluster --name trino-poc-cluster || \
    eksctl create cluster -f cluster-config.yaml

# Update kubeconfig
aws eks update-kubeconfig --name trino-poc-cluster --region ${AWS_REGION}

# Add Trino Helm repository
helm repo add trino https://trinodb.github.io/charts
helm repo update

# Install Trino using Helm
helm upgrade --install trino trino/trino \
    --namespace trino \
    --create-namespace \
    -f helm/trino-values.yaml

# Deploy the API
envsubst < k8s/deployment.yaml | kubectl apply -f -

echo "Deployment completed successfully!" 