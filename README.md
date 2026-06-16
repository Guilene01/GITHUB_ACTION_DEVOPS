# DEVOPS-UTRAINS

A Terraform + GitHub Actions project that provisions an AWS "tools" server and demonstrates two CI/CD pipeline approaches: a **practice pipeline** that ties together SonarCloud, Vault, and JFrog, and an **enterprise-grade template** covering the full lifecycle from build to Kubernetes deploy.

---

## 1. What this repo contains

| Path | Purpose |
|---|---|
| [GITHUB_ACTION_DEVOPS/](GITHUB_ACTION_DEVOPS/) | Terraform — provisions the AWS infrastructure |
| [.github/workflows/jfrog-vault-ci.yml](.github/workflows/jfrog-vault-ci.yml) | Practice pipeline — build, SonarCloud scan, publish to JFrog via Vault |
| [.github/workflows/enterprise-pipeline-template.yml](.github/workflows/enterprise-pipeline-template.yml) | Enterprise template — full pipeline reference (Maven → SonarCloud → Trivy → JFrog → Docker → ECR → Helm → K8s) |
| [pom.xml](pom.xml), [src/](src/) | Minimal Java app used by the practice pipeline |

---

## 2. Infrastructure (Terraform)

Running `terraform apply` in `GITHUB_ACTION_DEVOPS/` creates:

- A VPC (`10.0.0.0/16`) with a public subnet, Internet Gateway, and route table
- A security group opening: `22` (SSH), `80` (HTTP), `8082` (JFrog), `4954` (Trivy), `8200` (Vault)
- An SSH key pair generated locally (`server_key.pem`)
- An EC2 instance (`t2.large`, Amazon Linux 2023) bootstrapped over SSH with:

| Script | What it installs |
|---|---|
| `install_docker.sh` | Docker |
| `install_java.sh` | Java 17 + Maven 3.9.11 |
| `install_jfrog.sh` | JFrog Artifactory OSS (port `8082`) |
| `install_trivy.sh` | Trivy vulnerability scanner |
| `install_vault.sh` | HashiCorp Vault with an AppRole (`github-actions-role`) and JFrog credentials seeded at `secrets/creds/jfrog` |

- A GitHub Actions **OIDC IAM role** (`github-actions-cicd-role`) scoped to this repo's `main` branch — available for future pipeline steps that need AWS access

**Secret storage strategy:**

| Secret | Where it lives |
|---|---|
| JFrog username / password | HashiCorp Vault (`secrets/creds/jfrog`) |
| SonarCloud token | GitHub Actions repository secret (`SONAR_TOKEN`) |

### Deploy

```bash
cd GITHUB_ACTION_DEVOPS
cp terraform.tfvars.example terraform.tfvars   # fill in JFrog username/password/token
terraform init
terraform apply
```

Key outputs after apply:

| Output | Description |
|---|---|
| `artifactory_url` | JFrog UI — `http://<ip>:8082` |
| `vault_url` | Vault UI — `http://<ip>:8200` |
| `ssh_connection` | Ready-to-use SSH command |
| `vault_key_file` | `vaultkey.txt` — contains Vault unseal key, root token, AppRole Role ID / Secret ID |
| `jfrog_default_credentials` | Default login for JFrog (`admin` / `password`) — change on first login |
| `github_actions_role_arn` | IAM role ARN for OIDC (future use) |

> ⚠️ `terraform.tfvars` contains real credentials and is gitignored. Never commit it.

---

## 3. SonarCloud setup

1. Go to [sonarcloud.io](https://sonarcloud.io) → log in with GitHub
2. Create an **Organization** (free tier, public repos)
3. **+ → Analyze new project** → import this repository
4. Note the **Organization Key** (lowercase, shown under org name) and **Project Key**
5. GitHub repo → **Settings → Secrets and variables → Actions → Variables** → add:
   - `SONAR_PROJECT_KEY`
   - `SONAR_ORGANIZATION`

**Generate a token:**
1. SonarCloud → avatar → **My Account** → **Security**
2. Generate a token → copy it (shown once)
3. GitHub repo → **Settings → Secrets → New repository secret** → `SONAR_TOKEN`

---

## 4. GitHub Actions secrets required

**Settings → Secrets and variables → Actions → Secrets:**

| Secret | Value |
|---|---|
| `SONAR_TOKEN` | SonarCloud token from step 3 |
| `JFROG_URL` | `artifactory_url` Terraform output |
| `VAULT_ADDR` | `vault_url` Terraform output |
| `VAULT_ROLE_ID` | Role ID from `vaultkey.txt` |
| `VAULT_SECRET_ID` | Secret ID from `vaultkey.txt` |

**Settings → Secrets and variables → Actions → Variables:**

| Variable | Value |
|---|---|
| `SONAR_PROJECT_KEY` | From SonarCloud project settings |
| `SONAR_ORGANIZATION` | From SonarCloud org settings (lowercase) |

---

## 5. Practice pipeline — jfrog-vault-ci.yml

[.github/workflows/jfrog-vault-ci.yml](.github/workflows/jfrog-vault-ci.yml) runs on every push to `main`. It was built as a hands-on exercise to wire together SonarCloud, Vault, and JFrog in GitHub Actions.

Three jobs run after each push:

**`build-and-scan`**
- Checkout + Java 17
- `mvn clean verify` — builds and runs tests
- SonarCloud analysis using `SONAR_TOKEN` secret
- Uploads the built jar as a workflow artifact

**`publish-to-jfrog`** _(after build-and-scan)_
- Authenticates to Vault via AppRole (`VAULT_ROLE_ID` / `VAULT_SECRET_ID`)
- Reads JFrog credentials from `secrets/creds/jfrog`
- Publishes the jar to `libs-release-local` in JFrog Artifactory

**`validate-vault`** _(parallel with publish-to-jfrog)_
- Authenticates to Vault via AppRole
- Confirms `secrets/creds/jfrog` path returns HTTP 200 — fails if not

**Viewing the artifact in JFrog:**
1. Open `artifactory_url` → log in (`admin` / your password)
2. **Artifactory → Artifacts → libs-release-local** → expand folders
3. If `libs-release-local` doesn't exist: **Administration → Repositories → Local → New → Maven** → key: `libs-release-local`

---

## 6. Enterprise pipeline template — enterprise-pipeline-template.yml

[.github/workflows/enterprise-pipeline-template.yml](.github/workflows/enterprise-pipeline-template.yml) is triggered manually only (`workflow_dispatch`) — it is a reference template, not wired to this repo's app. Use it as a starting point for a full production pipeline.

**`build-and-test`**
- Checkout + Java 17
- Unit tests (`mvn clean compile test`)
- SonarCloud scan + quality gate check
- Trivy filesystem scan (dependency vulnerabilities → `maven_dependency.html`)
- `mvn package` → uploads jar artifact

**`publish-to-jfrog`** _(after build-and-test)_
- Downloads jar artifact
- Publishes to JFrog Artifactory via credentials in GitHub secrets

**`docker-build-and-scan`** _(after build-and-test)_
- Builds Docker image (tagged `latest` + run ID)
- Trivy image scan → `docker_image_report.html`
- Authenticates to AWS ECR via OIDC
- Pushes image to ECR

**`deploy-to-k8s`** _(after docker-build-and-scan)_
- Updates Helm chart image tag to the current run ID
- Packages Helm chart
- Uploads Helm package to JFrog
- Deploys to Kubernetes with `helm upgrade --install`

**To adapt this template for a real project:**
- Update `env:` values (`APP_NAME`, `ECR_REPO_URL`, `HELM_CHART_DIR`, etc.)
- Add secrets: `JFROG_USERNAME`, `JFROG_PASSWORD`, `SONAR_TOKEN`, `KUBE_CONFIG`, `AWS_OIDC_ROLE_ARN`
- Add vars: `SONAR_PROJECT_KEY`, `SONAR_ORGANIZATION`
- Change trigger from `workflow_dispatch` to `push: branches: [main]`

---

## 7. Notes

- The EC2 instance role (`cicd_tools_admin_role`) has `AdministratorAccess` — scope this down for production use
- `terraform.tfvars` holds the JFrog password in plaintext locally; consider using `random_password` to generate it at deploy time
- The OIDC IAM role (`github-actions-cicd-role`) is provisioned but not currently used by either pipeline — available if a future step needs direct AWS access
