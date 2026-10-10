# AWS ECS Deployment Strategies: Rolling, Blue/Green, Canary & Linear

> **A production-ready reference architecture demonstrating 4 AWS ECS Fargate deployment strategies on AWS Graviton (ARM64) with OpenTofu, GitHub Actions, and AWS CodeDeploy.**

[![OpenTofu](https://img.shields.io/badge/IaC-OpenTofu-blue.svg)](https://opentofu.org/)
[![Node.js](https://img.shields.io/badge/Node.js-20-green.svg)](https://nodejs.org/)
[![AWS Fargate Graviton](https://img.shields.io/badge/AWS%20Fargate-Graviton%20ARM64-orange.svg)](https://aws.amazon.com/ec2/graviton/)
[![GitHub Actions OIDC](https://img.shields.io/badge/Security-GitHub%20OIDC-purple.svg)](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect)

---

## 🎯 Architecture Overview & Key Highlights

This repository is designed for engineers seeking an enterprise-grade reference architecture for container deployments on Amazon ECS.

```
┌─────────────────────────────────────────────────────────────┐
│ 1. INFRASTRUCTURE PLANE (OpenTofu)                          │
│    • Infrequent executions (VPC, ALB, Cluster, IAM)         │
│    • Provisions initial baseline service & task definitions │
│    • Enforces lifecycle { ignore_changes = [task_def] }     │
└─────────────────────────────────────────────────────────────┘
                               ▲
                               │ Scaffolds baseline
                               ▼
┌─────────────────────────────────────────────────────────────┐
│ 2. APPLICATION DEPLOYMENT PLANE (GitHub Actions CI/CD)      │
│    • Frequent executions (on code commits / releases)       │
│    • Builds & pushes ARM64 Graviton Docker images to ECR    │
│    • Authenticates via GitHub OIDC (Zero long-lived keys)   │
│    • Updates Task Definitions and triggers rollouts         │
│    • Fast, zero Terraform state locks, scoped IAM perms     │
└─────────────────────────────────────────────────────────────┘
```

### Key Highlights
1. **Separation of Concerns:** Avoids the anti-pattern of running `terraform apply` on every code push. OpenTofu manages the cloud scaffolding; GitHub Actions directly orchestrates continuous application deployments.
2. **Zero Hardcoded Secrets in GitHub:** Uses AWS IAM OpenID Connect (OIDC) strictly scoped to `repo:<owner>/<repo>:ref:refs/heads/main` to eliminate static AWS Access Keys in public repositories.
3. **AWS Graviton (ARM64) Native:** Container images and Fargate task definitions are built and optimized for ARM64 for maximum price-performance.
4. **Visual Real-Time Traffic Monitor:** The included demo web app features a live dashboard showing container metadata, active version/color, real-time Blue/Green traffic split ratios, and a **Chaos Engineering** button to trigger automated CloudWatch alarm rollbacks.
5. **Cost-Optimized for Learning:** Default configurations run Fargate tasks in public subnets with public IPs, avoiding the continuous ~$32+/month cost of AWS NAT Gateways.

---

## 📊 Deployment Strategy Comparison

| Strategy | Mechanism | Traffic Shift Pattern | Rollback Mechanism | Best Used For |
| :--- | :--- | :--- | :--- | :--- |
| **1. Rolling Update** | Native ECS Controller | Batch replacement (`min 100%`, `max 200%`) behind a single Target Group | ECS Deployment Circuit Breaker | Routine internal microservices, non-breaking changes |
| **2. Blue/Green** | Native ECS / CodeDeploy | Instant 100% cutover between Blue and Green Target Groups | Immediate target group flip | Zero-downtime cutovers with instant rollback capability |
| **3. Canary** | AWS CodeDeploy | Shifts 10% traffic to Green for 5 mins; shifts remaining 90% if healthy | Automatic rollback on CloudWatch 5xx Alarm | Mission-critical production services requiring safe bake periods |
| **4. Linear** | AWS CodeDeploy | Incremental 10% shift every 1 minute until 100% is reached | Automatic rollback on CloudWatch 5xx Alarm | High-scale services needing progressive cache/resource warming |

---

## 📁 Repository Structure

```text
.
├── .github/workflows/
│   ├── ci-build-push.yml        # Builds & pushes Graviton Docker images to ECR
│   ├── deploy-rolling.yml       # Triggers ECS Native Rolling Update
│   ├── deploy-blue-green.yml    # Triggers Blue/Green Cutover
│   ├── deploy-canary.yml        # Triggers CodeDeploy Canary (10% for 5 min)
│   └── deploy-linear.yml        # Triggers CodeDeploy Linear (10% every 1 min)
├── app/                         # Node.js Demo Web Application
│   ├── src/                     # Express backend + Visual Traffic Inspector UI
│   ├── test/                    # Automated integration & health check tests
│   └── Dockerfile               # Multi-stage production build for linux/arm64
├── tofu/
│   ├── modules/                 # Reusable OpenTofu Modules
│   │   ├── oidc/                # GitHub Actions OIDC Provider & Scoped IAM Role
│   │   ├── vpc/                 # Cost-optimized 2-AZ VPC
│   │   ├── ecr/                 # ECR Repository with automated lifecycle cleanup
│   │   ├── ecs-cluster/         # Shared ECS Cluster on Fargate (ARM64)
│   │   └── alb/                 # ALB module supporting single/dual target groups
│   ├── foundation/              # Shared foundation (VPC, Cluster, ECR, OIDC)
│   └── strategies/              # Dedicated strategy environments
│       ├── 01-rolling-update/   # Strategy 1: Native ECS Rolling Update
│       ├── 02-native-blue-green/# Strategy 2: Blue/Green with Test Listener
│       ├── 03-canary/           # Strategy 3: CodeDeploy Canary (10% 5m) + Alarms
│       └── 04-linear/           # Strategy 4: CodeDeploy Linear (10% 1m) + Alarms
```

---

## 🚀 Step-by-Step Deployment Guide

### Prerequisites
- [OpenTofu](https://opentofu.org/) (`>= 1.6.0`)
- [AWS CLI v2](https://aws.amazon.com/cli/) configured with deployment permissions
- A public or private GitHub repository

---

### Step 1: Deploy Foundational Infrastructure

The foundation provisions the VPC, ECR repository, ECS Cluster, and the GitHub Actions OIDC role:

```bash
cd tofu/foundation

# Copy and edit variables
cp terraform.tfvars.example terraform.tfvars
```

Update `terraform.tfvars`:
```hcl
aws_region         = "us-east-1"
environment        = "demo"
github_repo        = "your-username/ecs-deployment-strategies" # Your GitHub repo
github_branch      = "main"
enable_nat_gateway = false                                     # Set to false to avoid NAT bills
```

Deploy:
```bash
tofu init
tofu apply
```

Note the output values:
- `github_actions_role_arn`
- `ecr_repository_url`

---

### Step 2: Configure GitHub Repository Secret

In your GitHub repository, navigate to **Settings > Secrets and variables > Actions** and add:

| Secret Name | Value | Description |
| :--- | :--- | :--- |
| `AWS_OIDC_ROLE_ARN` | `arn:aws:iam::<ACCOUNT_ID>:role/github-actions-ecs-deployer-demo` | Scoped OIDC IAM role created by OpenTofu |

> **Security Note:** In a public repository, anyone can see your workflow files. The Role ARN is safe because AWS STS validates the cryptographic GitHub OIDC token against your repository and branch before granting credentials.

---

### Step 3: Build & Push the Initial Image (v1.0.0)

1. Go to your GitHub repository's **Actions** tab.
2. Select **CI - Build and Push (Graviton ARM64)**.
3. Click **Run workflow** with default parameters:
   - `image_tag`: `latest`
   - `app_color`: `blue`
   - `app_release_title`: `Blue Stable (v1.0.0)`

This builds the ARM64 container and pushes it to your ECR repository.

---

### Step 4: Deploy Your Strategy of Choice

Each strategy is in its own directory and reads state from `tofu/foundation/terraform.tfstate`.

#### Example: Deploying Strategy 1 (Rolling Update)
```bash
cd tofu/strategies/01-rolling-update
tofu init
tofu apply
```

Open the printed `alb_dns_name` in your browser. You will see the **Blue Release (v1.0.0)** dashboard!

#### Example: Deploying Strategy 3 (Canary)
```bash
cd tofu/strategies/03-canary
tofu init
tofu apply
```

Open the printed `prod_url` in your browser.

---

### Step 5: Test Continuous Deployment via GitHub Actions

To test a deployment without running OpenTofu:

1. In GitHub Actions, select the corresponding deployment workflow (e.g., **Deploy - Canary (10% 5-Min Shift)**).
2. Click **Run workflow**:
   - `app_version`: `v2.0.0`
   - `app_color`: `green`
   - `app_release_title`: `Green Canary Release`
3. Watch the workflow execute:
   - It builds no infrastructure.
   - It creates a new Task Definition revision with the `green` color.
   - It triggers CodeDeploy to route **10% of traffic to the Green fleet for 5 minutes**.
4. Open the **Production URL**:
   - Watch the live **Traffic Distribution Monitor** bar shift to ~`Blue: 90% | Green: 10%`.
   - Incoming request stream pills will alternate between Blue and Green!

---

### Step 6: Test Automated Rollbacks (Chaos Engineering)

To see automated rollbacks in action:

1. During an active Canary or Linear deployment, click the **"Simulate 500 Failure"** button on the web UI.
2. The `/health` and `/api/ping` endpoints immediately begin returning `500 Internal Server Error`.
3. The CloudWatch `canary-demo-5xx-errors` alarm fires.
4. AWS CodeDeploy detects the alarm and **automatically rolls back traffic 100% to the Blue fleet**, terminating the faulty Green containers.

---

## 🧹 Teardown Instructions

To avoid ongoing AWS charges, destroy resources in reverse order:

```bash
# 1. Destroy active strategy environments
cd tofu/strategies/04-linear && tofu destroy -auto-approve
cd ../03-canary && tofu destroy -auto-approve
cd ../02-native-blue-green && tofu destroy -auto-approve
cd ../01-rolling-update && tofu destroy -auto-approve

# 2. Destroy foundation infrastructure
cd ../../foundation && tofu destroy -auto-approve
```

---

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
