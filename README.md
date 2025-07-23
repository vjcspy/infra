# Infra as Code Repository

This repository serves as the central hub for managing infrastructure as code (IaC), primarily leveraging **Harness** for CI/CD pipelines and **Kubernetes (K8s) with Helm** for application deployments. It encapsulates all configurations and scripts necessary to provision, manage, and deploy applications and their underlying infrastructure.

## Table of Contents
- [Project Overview](#project-overview)
- [Folder Structure](#folder-structure)
  - [harness/](#harness)
  - [k8s/](#k8s)
  - [misc/](#misc)
- [Getting Started](#getting-started)
- [Contribution Guidelines](#contribution-guidelines)

## Project Overview

This repository's core purpose is to define and manage infrastructure and deployment processes through code. Key technologies and their roles include:

-   **Harness**: Used for Continuous Integration (CI) and Continuous Delivery (CD) to automate the build, test, and deployment of applications. Harness configurations are synchronized with this Git repository, enabling GitOps practices.
-   **Kubernetes (K8s)**: The container orchestration platform where applications are deployed.
-   **Helm**: The package manager for Kubernetes, used to define, install, and upgrade complex Kubernetes applications. All application deployments are managed via Helm charts stored in this repository.
-   **AWS**: Utilized for underlying infrastructure, including EC2 instances for Kubernetes clusters and EBS volumes.

## Folder Structure

### `harness/`

This directory contains all the configuration files for **Harness CI/CD**. These files are designed to be synchronized with your Harness account, allowing for Git-driven management of your CI/CD pipelines, connectors, and environments.

-   **`harness/cd/`**: Contains definitions for Continuous Delivery (CD) pipelines for various applications. Each subdirectory represents a specific application's deployment pipeline.
    -   `jmeta/`: CD pipeline configurations for the `jmeta` application.
    -   `meta/`: CD pipeline configurations for the `meta` application.
    -   `whoami/`: CD pipeline configurations for the `whoami` application, often used as a starter or test application.
-   **`harness/connector/`**: Defines connectors used by Harness to integrate with external services.
    -   `github-connector.yaml`: Configuration for connecting Harness to GitHub repositories.
    -   `kubernetes-connector.yaml`: Configuration for connecting Harness to Kubernetes clusters, typically via a Kubernetes Delegate.
-   **`harness/environment/`**: Contains definitions for deployment environments within Harness.
    -   `dev-environment.yaml`: Development environment configuration.
    -   `dev-infra.yaml`: Infrastructure definition for development environments.
    -   `k8s-helm-chart-infra.yaml`: Infrastructure definition specifically for Kubernetes Helm chart deployments.
    -   `k8s-single-environment.yaml`: Configuration for a single Kubernetes environment.
-   **`harness/inputset/`**: Stores input sets, which are collections of runtime inputs for Harness pipelines.
    -   `stock.yaml`: An example input set, likely containing common parameters for pipeline execution.
-   **`harness/README.md`**: Provides setup instructions for Harness, including Kubernetes Delegate installation, GitHub Personal Access Token (PAT) setup, and commands to apply connectors.

### `k8s/`

This directory houses all **Helm charts** for applications deployed on Kubernetes. When CI/CD pipelines run on Harness, they refer to these charts to deploy and manage applications.

-   **`k8s/app/`**: Contains individual Helm charts for each application. Each subdirectory is a self-contained Helm chart.
    -   `db/`: Helm chart for database deployments.
    -   `fluent-bit/`: Helm chart for Fluent Bit, a log processor and forwarder.
    -   `ggg-api/`: Helm chart for the `ggg-api` application.
    -   `ggg-brand/`: Helm chart for the `ggg-brand` application.
    -   `ggg-temp-pod/`: Contains a simple `pod.yaml` for temporary pod deployments.
    -   `ggg-website/`: Helm chart for the `ggg-website` application.
    -   `jmeta/`: Helm chart for the `jmeta` application.
    -   `meta/`: Helm chart for the `meta` application.
    -   `notion-proxy/`: Helm chart for the `notion-proxy` application.
    -   `splunk-server/`: Helm chart for the `splunk-server` application.
    -   `whoami/`: Helm chart for the `whoami` application.
    Each application chart typically includes:
        -   `Chart.yaml`: Metadata about the Helm chart.
        -   `values.yaml`: Default configuration values for the chart, which can be overridden during deployment.
        -   `templates/`: Kubernetes manifest templates (e.g., `deployment.yaml`, `service.yaml`, `ingress.yaml`, `hpa.yaml`, `secret.yaml`, `serviceaccount.yaml`, `_helpers.tpl`).
-   **`k8s/init/`**: Contains initial Kubernetes configurations and setup scripts.
    -   `dashboard/`: Kubernetes manifests for deploying a Kubernetes Dashboard (e.g., `account.yaml`, `ingress.yaml`, `service.yaml`).
    -   `harness-cd/`: Kubernetes manifests specific to the Harness CD setup, such as `namespace.yaml`.
    -   `tls.crt`, `tls.key`: TLS certificates, likely for securing ingress or other services.
-   **`k8s/README.md`**: Basic README for the K8s directory.

### `misc/`

This directory holds various utility tools, scripts, and configurations that support the overall infrastructure.

-   **`misc/mount-ebs.sh`**: A shell script designed to manage and mount an AWS EBS volume to an EC2 instance. It handles checking volume status, detaching from other instances if necessary, attaching to the current instance, and mounting the volume.
-   **`misc/docker/`**: Contains Dockerfiles for building custom Docker images used across the infrastructure.
    -   `node16-yarn/`: Dockerfile for a Node.js 16 environment with Yarn.
    -   `node20-pnpm/`: Dockerfile for a Node.js 20 environment with pnpm.
    -   `quarkus-jvm-21/`: Dockerfile for a Quarkus application running on JVM 21.
    -   `quarkus-micro/`: Dockerfile for a Quarkus microservice.
    -   `splunk-license-server/`: Dockerfile for a Splunk license server.
    -   `splunk-server/`: Dockerfile for a Splunk server.
-   **`misc/manage-spot-request/`**: Contains configurations and scripts for managing AWS Spot Requests.
    -   `aws-python-spot-manager/`: A serverless application (AWS Lambda) likely used to manage EC2 Spot Instances, including assigning Elastic IPs. Contains Python scripts (`assign_eip.py`, `handler.py`) and a `serverless.yml` configuration.
    -   `infra/`: Terraform configurations (`main.tf`, `provider.tf`, `terraform.tf`) for provisioning AWS infrastructure components related to spot instance management.
-   **`misc/spot-request/`**:
    -   `spot_fleet_request.json`: A JSON file defining an AWS Spot Fleet Request, specifying desired instance types, AMIs, networking, and storage configurations for a fleet of spot instances.

## Getting Started

To effectively use and contribute to this repository, you will need:

1.  **Harness Account**: Access to a Harness platform account.
2.  **Harness CLI**: Installed and configured to interact with your Harness account.
3.  **Kubernetes Cluster**: A running Kubernetes cluster where applications will be deployed.
4.  **AWS Account**: An AWS account with appropriate permissions for managing EC2, EBS, and other related services.
5.  **Helm**: Installed locally for managing Kubernetes applications.
6.  **Terraform**: Installed locally if you plan to manage AWS infrastructure via Terraform.
7.  **Docker**: Installed locally if you plan to build custom Docker images.

Refer to the `harness/README.md` for initial Harness setup steps.

## Contribution Guidelines

When contributing to this repository, please adhere to the following guidelines:

-   **Follow Existing Patterns**: Maintain consistency with existing file structures, naming conventions, and configuration styles within each directory (`harness`, `k8s`, `misc`).
-   **Test Your Changes**: Before submitting, ensure your changes are thoroughly tested. For Helm charts, consider using `helm lint` and `helm template` to validate syntax and generated manifests. For Harness configurations, test pipeline execution.
-   **Documentation**: Update relevant `README.md` files or add new ones if you introduce new components or complex configurations.
-   **Pull Requests**: Submit your changes via pull requests, providing a clear description of the changes and their purpose.
-   **Security**: Ensure that no sensitive information (e.g., API keys, secrets) is hardcoded or committed directly into the repository. Utilize Harness Secrets Management or Kubernetes Secrets for sensitive data.
