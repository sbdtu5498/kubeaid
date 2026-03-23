# Prerequisites

This guide helps you prepare everything needed to deploy a KubeAid-managed Kubernetes cluster.
Whether you're setting up a production environment in the cloud or a local development cluster, start here.

---

## Choose Your Deployment

KubeAid supports two deployment paths. Choose based on your use case:

| Deployment Type | Best For | What You Need |
| ----------------- | ---------- | --------------- |
| **Cloud / Distributed** | Production workloads, multi-node clusters | Cloud provider account (AWS, Azure, Hetzner) or bare metal servers |
| **Local (K3D)** | Development, testing, learning KubeAid | Docker running on your local machine |

> **New to KubeAid?** Start with a **Local K3D** deployment to explore the platform without incurring any cloud costs.

---

## System Requirements

### Minimum Compute Requirements

| Component | Local (K3D) | Cloud / Bare Metal (per node) |
| ----------- | ------------- | ------------------------------- |
| **RAM** | 8GB (16GB recommended) | 16GB+ |
| **CPU** | 4 cores | 4+ cores |
| **Storage** | 50GB free disk space | 100GB+ |

---

## Supported Architectures

KubeAid runs on the following CPU architectures:

| Architecture | Also Known As | Examples |
| -------------- | --------------- | ---------- |
| **amd64** | x86_64 | Intel Core, AMD Ryzen, most cloud VMs |
| **arm64** | aarch64 | Apple Silicon (M1/M2/M3/M4), Raspberry Pi 4+ |

---

## Supported Operating Systems

### For Your Local Machine (running KubeAid CLI)

- **Linux** - Ubuntu, Debian, Fedora, RHEL, etc.
- **macOS** - Intel and Apple Silicon
- **Windows** - Via WSL2 (Windows Subsystem for Linux)

### For Cluster Nodes

- **Linux only** - Ubuntu 22.04+ recommended

---

## Common Dependencies  
  
Before setting up any KubeAid cluster, ensure you have the following tools and resources ready:  

### Required Software  
  
The following packages must be installed on your local machine:  
  
- [`kubectl`](https://kubernetes.io/docs/tasks/tools/) - Kubernetes command-line tool  
- [`jq`](https://jqlang.org/download/) - JSON processor  
- [`terragrunt`](https://terragrunt.gruntwork.io/docs/getting-started/install/) - Terraform wrapper  
- [`terraform`](https://developer.hashicorp.com/terraform/install) - Infrastructure as Code tool  
- [`bcrypt`](https://www.npmjs.com/package/bcrypt) - Password hashing utility  
- [`wireguard`](https://www.wireguard.com/install/) - VPN software (optional, for private cluster access)  
- [`yq`](https://github.com/mikefarah/yq) - YAML processor
  
### Docker  
  
Ensure [Docker](https://docs.docker.com/get-docker/) is installed and running locally on your machine.
Docker Desktop is recommended for Linux, macOS, and Windows users for ease of use.
  
### Git Repositories  
  
You need to set up two Git repositories:  
  
1. **KubeAid Repository**: Fork or mirror the [KubeAid repository](https://github.com/Obmondo/KubeAid) from Obmondo.

  **Important**: Never make changes on the master/main branch of your mirror of the KubeAid repository,
  as this branch is used to deliver updates. All customizations should happen in your `kubeaid-config` repository.
  
1. **KubeAid Config Repository**: Fork the [KubeAid Config repository](https://github.com/Obmondo/kubeaid-config),
   which will contain your cluster-specific configurations.

#### Repository Structure Overview

```mermaid
---
title: KubeAid repository structure
---
flowchart LR
    subgraph KubeAid["KubeAid Repository"]
        direction TB
        HelmCharts["argocd-helm-charts/"]
        CertManager["cert-manager/"]
        Templates["templates/"]
        Traefik["traefik/ + more..."]
        KubePrometheus["kube-prometheus/"]
        
        HelmCharts --> CertManager
        HelmCharts --> Traefik
        CertManager --> Templates
    end
    
    subgraph KubeAidConfig["KubeAid Config Repository"]
        direction TB
        K8s["k8s/"]
        Cluster1["cluster-name/"]
        ArgoApps["argocd-apps/"]
        Values["*.values.yaml"]
        SealedSecrets["sealed-secrets/"]
        Cluster2["another-cluster/"]
        
        K8s --> Cluster1
        K8s --> Cluster2
        Cluster1 --> ArgoApps
        Cluster1 --> Values
        Cluster1 --> SealedSecrets
    end
    
    ArgoApps -.->|references charts| HelmCharts
```

> **Key Concept:** The KubeAid repo contains Helm charts and templates.
> Your KubeAid Config repo contains values files and ArgoCD Application manifests that reference those charts.
  
### Git Provider Credentials  
  
Keep your Git provider credentials ready. These will be used by ArgoCD for GitOps operations.  
  
#### GitHub  
  
Create a [Personal Access Token (PAT)](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens#creating-a-fine-grained-personal-access-token)
with permission to write to your KubeAid Config fork. This PAT will be used as the password.
  
**Best Practice**: Create a separate user called `obmondo-<service>-user`
and use its Personal Access Token instead of your personal account token.
  
#### GitLab  
  
For GitLab, you can create a Project Access Token (available in self-hosted and enterprise GitLab)
or create a separate user called `obmondo-<service>-user` and provide its Personal Access Token.
  
## Provider-Specific Prerequisites  
  
### AWS  
  
- **AWS SSH KeyPair**: Create an AWS SSH KeyPair in the region where you'll be bootstrapping the cluster.
  
### Azure  
  
- **System Requirements**: A Linux or MacOS computer with at least 16GB of RAM
  (8GB might work but may encounter Out of memory (OOM) issues).
  
- **Service Principal**: [Register an application (Service Principal) in Microsoft Entra ID](https://learn.microsoft.com/en-us/entra/identity-platform/quickstart-register-app).
  
- **SSH Keypairs**:
  - An OpenSSH type SSH keypair (private key for SSH access to VMs). You can generate this using:

    ```bash
    ssh-keygen -t ed25519 -f azure-ssh-key -C "azure-cluster-key"
    ```

  - A key pair in PEM format (required for [Azure Workload Identity setup](https://learn.microsoft.com/en-us/azure/aks/workload-identity-deploy-cluster)).
    You can generate this using:

    ```bash
    openssl genpkey -algorithm ed25519 -out jwt-signing-key.pem
    openssl pkey -in jwt-signing-key.pem -pubout -out jwt-signing-pub.pem
    ```

  > **Note:** ed25519 keys are shorter and more secure than RSA keys, though not quantum-safe.
  > If RSA is preferred by you or your organization, use `ssh-keygen -t rsa -b 4096`
  > and `openssl genrsa -out jwt-signing-key.pem 4096` instead.
  
### Bare Metal  
  
For general bare metal setups (non-Hetzner), only the common dependencies are required.
The bare metal provider uses [Kubermatic KubeOne](https://github.com/kubermatic/kubeone) under the hood for SSH-only access
platforms without API host management support.
  
### Hetzner  
  
#### Hetzner HCloud  
  
- **HCloud SSH KeyPair**: Create an HCloud SSH KeyPair.
  Note that no two HCloud SSH KeyPairs can have the same SSH public key.
  
#### Hetzner Bare Metal  
  
- **Hetzner Bare Metal SSH KeyPair**: Create a Hetzner Bare Metal SSH KeyPair at
  https://robot.hetzner.com/key/index. Note that no two Hetzner Bare Metal SSH KeyPairs can have the same SSH public key.
  
- **RAID Cleanup** (if applicable): If you plan to set `cloud.hetzner.bareMetal.wipeDisks: True` in your configuration,
  remove any pre-existing RAID setup from your Hetzner Bare Metal servers by executing
  `wipefs -fa <partition-name>` for each partition.
  
#### Hetzner Hybrid  
  
Requires both HCloud and Hetzner Bare Metal prerequisites listed above.
  
### Local K3D  
  
For local testing with K3D, only the common dependencies are required.
Note that this setup does not support cluster upgrades and disaster recovery.
  
## Notes  
  
- The cluster setup follows GitOps principles using ArgoCD, ensuring all changes are version-controlled through Git.
- KubeAid clusters are designed to be private by default, with optional Wireguard gateway for secure access.
- All providers use Cilium CNI running in kube-proxyless mode for networking.
