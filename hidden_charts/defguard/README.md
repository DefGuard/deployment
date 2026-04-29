 <p align="center">
    <img src="docs/header.png" alt="defguard">
 </p>

# Defguard Helm chart

This Helm chart can be used to deploy the whole [Defguard](https://defguard.net/) stack:

- Defguard Core service
- Postgres database
- Defguard Gateway service 
- public Defguard Proxy service

Check our [documentation](https://docs.defguard.net/deployment-strategies/kubernetes) for deployment
instructions.

## ⚠️ Important: Postgres image tags 

Due to changes in Bitnami policy the Postgres subchart now uses the `latest` tag by default.
Remember to set a specific tag in your `values.yaml` to avoid issues with major version upgrades in production environments.
