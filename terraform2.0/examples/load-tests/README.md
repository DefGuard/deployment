# Defguard load-testing stack

This Terraform example creates an isolated AWS environment for reproducing the load tests described in [Performance and deployment sizing](https://docs.defguard.net/2.2/in-depth/performance-and-deployment-sizing). It is for load testing, not production. The linked page contains the benchmark results, tested hardware, and methodology; this guide covers deploying and removing the test environment.

## What it creates

The stack creates a dedicated VPC with public and private subnets, a NAT gateway, and instances for Defguard Core, Edge, Gateway, PostgreSQL, OpenLDAP, a load generator, and Prometheus/Grafana. Core and the databases are private. Edge, Gateway, and the load generator have public addresses; security groups control access.

## Requirements

- Terraform 1.5 or later.
- An AWS account and credentials with permission to create the resources in this stack. Use the standard AWS credential chain, such as an AWS profile or SSO. Do not put AWS keys in Terraform files.
- An AWS key pair only if you need SSH access.

The stack creates billable AWS resources, including EC2 instances, storage, public IPs, and a NAT gateway. Review expected costs and clean up the stack after testing.

## Configure and deploy

1. Copy `main.tf.example` to `main.tf`.
2. Review the region, instance types, image tags, and network settings in `main.tf`.
3. Replace the example database, LDAP, and Grafana passwords with private values. Do not commit `main.tf`, Terraform state, plans, or files containing secrets.
4. SSH is disabled by default. To enable it, set `ssh_admin_cidr` to your public IP as a `/32` and `key_name` to an existing EC2 key pair in the selected region. Do not use `0.0.0.0/0`.
5. Initialize and inspect the plan:

   ```sh
   terraform init
   terraform validate
   terraform plan
   ```

6. Check the plan for unexpected replacements, deletions, or networking changes. Apply it manually only after review:

   ```sh
   terraform apply
   ```

The example uses self-managed PostgreSQL on a private EC2 instance. The load-testing network module disables its optional RDS resources.

## First access and running tests

After deployment, Terraform prints the component addresses. Core is private. Follow the first-access notes at the bottom of `main.tf.example` to reach its web UI, complete setup, set the WireGuard location endpoint to the Gateway public address, and configure the enrollment URL to use Edge.

Use the load-generator instance to run scenarios. The commands below assume the repository is cloned at `/home/ubuntu/defguard`, as configured by cloud-init. Replace the example values with the PostgreSQL private address and location ID from Terraform/Core, plus the credentials configured in your private `main.tf`:

```sh
export DEFGUARD_DB_HOST="POSTGRES_PRIVATE_IP" DEFGUARD_DB_NAME=defguard DEFGUARD_DB_USER=defguard DEFGUARD_DB_PASSWORD="REPLACE_WITH_DB_PASSWORD"
export NETWORK_ID="LOCATION_ID" EDGE_URL="https://EDGE_PUBLIC_IP"
```

Seed users and devices for polling once, then run a five-minute polling test at 100 requests per second. The auto-created WireGuard location uses a small default subnet, so keep the seed count within its available address space:

```sh
cd /home/ubuntu/defguard && cargo run --release --manifest-path tools/defguard_load_generator/Cargo.toml -- seed --users 100 --network-id "$NETWORK_ID"
cd /home/ubuntu/defguard && cargo run --release --manifest-path tools/defguard_load_generator/Cargo.toml -- test config-polling --proxy-url "$EDGE_URL" --network-id "$NETWORK_ID" --requests-per-second 100 --duration 5m
```

The seed command creates users with TOTP enabled and devices assigned to the selected location. For a separate MFA authorization test, use a location with internal MFA enabled:

```sh
cd /home/ubuntu/defguard && cargo run --release --manifest-path tools/defguard_load_generator/Cargo.toml -- test client-mfa --proxy-url "$EDGE_URL" --network-id "$NETWORK_ID" --requests-per-second 20 --duration 5m
```

Start with conservative rates, confirm the scenario works, then increase load while watching the results. Run `cargo run --release --manifest-path tools/defguard_load_generator/Cargo.toml -- test --help` for current options. Open Grafana through an approved path into the VPC, such as an SSH tunnel when SSH is enabled. The monitoring host is private.

For comparable results, record the tested image versions, instance types, generator options, and run duration. Use the performance and sizing page for the benchmark methodology and interpretation of results.

## Remove the environment

When testing is complete, inspect the destruction plan and then run it manually:

```sh
terraform plan -destroy
terraform destroy
```

Confirm that the plan targets only this load-testing environment. Destroying the stack removes its AWS resources and data; back up anything you need first. Terraform state may contain sensitive values, so keep it private and remove it securely when no longer needed.

## Security notes

- Keep Core, PostgreSQL, OpenLDAP, and monitoring private.
- Enable SSH only when required, and restrict it to a trusted `/32` CIDR.
- Replace all example passwords before deployment.
- Do not commit `main.tf`, `terraform.tfstate*`, saved plans, credentials, or generated secret files.
