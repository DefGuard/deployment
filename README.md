# Defguard deployment

We prepared a [git repository](https://github.com/DefGuard/deployment) with deployment configuration, clone it:

```
git clone git@github.com:DefGuard/deployment.git
```
The repository contains configuration files for:

* [docker-compose](#docker-compose-deployment)
* [kubernetes](#kubernetes-deployment) (helm)

# Docker Compose deployment

In docker-compose directory you'll find a template env file called `.env.template`. Copy it:

```
cd docker-compose
cp .env.template .env
```

And then edit the values in `.env` file to setup your secrets. Those should be kept... well, secret.

Once that's done you can start the stack with:

```
docker-compose up
```

> Make sure you have [Docker](https://www.docker.com/get-started/) and [Docker Compose](https://docs.docker.com/compose/install/) installed.

That's it, Defguard should be running on port 80 of your server ([http://localhost](http://localhost) if you're running locally).

# Kubernetes deployment

1. Install Helm binary from https://github.com/helm/helm/releases/latest
2. Create namespace, e.g.: `kubectl create namespace defguard`
3. Install Helm chart, e.g.: `helm install --wait=true --namespace defguard defguard defguard`
