# Defguard deployment

We prepared a [git repository](https://github.com/DefGuard/deployment) with deployment configuration, clone it:

```
git clone git@github.com:DefGuard/deployment.git
```
The repository contains configuration files for:

- [Defguard deployment](#defguard-deployment)
- [Docker Compose deployment](#docker-compose-deployment)
- [Kubernetes deployment](#kubernetes-deployment)

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

[Helm](https://helm.sh) must be installed to use the charts.  Please refer to
Helm's [documentation](https://helm.sh/docs) to get started.

Once Helm has been set up correctly, add the repo as follows:

```
helm repo add <alias> https://defguard.github.io/helm-charts
```

If you had already added this repo earlier, run `helm repo update` to retrieve
the latest versions of the packages.  You can then run `helm search repo
<alias>` to see the charts.

To install the defguard chart:

```
helm install my-defguard defguard/defguard
```

To uninstall the chart:

```
helm delete my-defguard
```
