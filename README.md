# Kubernetes deployment

```
cd k8s
```

Create database password secret:

```
kubectl create secret generic db-password --from-literal=DEFGUARD_DB_PASSWORD=<YOUR_DB_PASSWORD>
```

Apply configuration:

```
kubectl apply
```
