# Kubernetes deployment

1. Install Helm binary from https://github.com/helm/helm/releases/latest
2. Create namespace, e.g.: `kubectl create namespace defguard`
3. Install Helm chart, e.g.: `helm install --wait=true --namespace defguard defguard defguard`
