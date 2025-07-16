# Exit on error
$ErrorActionPreference = "Stop"

# Load environment variables
Get-Content .env | ForEach-Object {
    if ($_ -match '^([^=]+)=(.*)$') {
        $name = $matches[1]
        $value = $matches[2]
        Set-Item -Path "env:$name" -Value $value
    }
}

# Create ECR repository if it doesn't exist
try {
    aws ecr describe-repositories --repository-names trino-api
} catch {
    aws ecr create-repository --repository-name trino-api
}

# Get ECR login token and login
aws ecr get-login-password --region $env:AWS_REGION | docker login --username AWS --password-stdin "$env:AWS_ACCOUNT_ID.dkr.ecr.$env:AWS_REGION.amazonaws.com"

# Build and push Docker image
docker build -t trino-api .
docker tag trino-api:latest "$env:AWS_ACCOUNT_ID.dkr.ecr.$env:AWS_REGION.amazonaws.com/trino-api:latest"
docker push "$env:AWS_ACCOUNT_ID.dkr.ecr.$env:AWS_REGION.amazonaws.com/trino-api:latest"

# Create EKS cluster if it doesn't exist
try {
    eksctl get cluster --name trino-poc-cluster
} catch {
    eksctl create cluster -f cluster-config.yaml
}

# Update kubeconfig
aws eks update-kubeconfig --name trino-poc-cluster --region $env:AWS_REGION

# Add Trino Helm repository
helm repo add trino https://trinodb.github.io/charts
helm repo update

# Install Trino using Helm
helm upgrade --install trino trino/trino `
    --namespace trino `
    --create-namespace `
    -f helm/trino-values.yaml

# Deploy the API
$deploymentYaml = Get-Content k8s/deployment.yaml -Raw
$deploymentYaml = $deploymentYaml -replace '\${ECR_REGISTRY}', "$env:AWS_ACCOUNT_ID.dkr.ecr.$env:AWS_REGION.amazonaws.com"
$deploymentYaml | kubectl apply -f -

Write-Host "Deployment completed successfully!" 