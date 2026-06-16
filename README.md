# DEVOPS-UTRAINS

A Terraform + GitHub Actions setup that provisions a small AWS "tools" server for a CI/CD pipeline: build code, scan it with SonarCloud, publish artifacts to JFrog, and manage secrets with HashiCorp Vault.

All active code lives in [GITHUB_ACTION_DEVOPS/](GITHUB_ACTION_DEVOPS/), plus the sample Java app at the repo root ([pom.xml](pom.xml), `src/`) and the GitHub Actions workflows in [.github/workflows/](.github/workflows/).

## 1. What this code does

Running `terraform apply` in `GITHUB_ACTION_DEVOPS/` creates:

- A VPC + public subnet + Internet Gateway
- A security group opening `22` (SSH), `80` (HTTP), `8082` (JFrog), `4954` (Trivy), `8200` (Vault)
- One EC2 instance (Amazon Linux 2023, `t2.large`) bootstrapped over SSH with:
  - **Docker**
  - **Java 17 + Maven** (required by Artifactory)
  - **JFrog Artifactory OSS** — artifact repository, served on port `8082`
  - **Trivy** — image/dependency vulnerability scanner
  - **HashiCorp Vault** — stores JFrog credentials at `secrets/creds/jfrog` and creates a `github-actions` AppRole so the pipeline can authenticate at runtime
- A GitHub Actions **OIDC IAM role** ([oidc.tf](GITHUB_ACTION_DEVOPS/oidc.tf)) scoped to this repo's `main` branch — available for future pipeline steps that need AWS access

**Secret storage strategy:**
| Secret | Where it lives |
|---|---|
| JFrog username / password | HashiCorp Vault (`secrets/creds/jfrog`) |
| SonarCloud token | GitHub Actions repository secret (`SONAR_TOKEN`) |

The actual CI/CD work — build, **SonarCloud** scan, publish to JFrog — happens in **GitHub Actions** ([.github/workflows/jfrog-vault-ci.yml](.github/workflows/jfrog-vault-ci.yml)), not on the EC2 box.

## 2. Deploy the infrastructure

```bash
cd GITHUB_ACTION_DEVOPS
cp terraform.tfvars.example terraform.tfvars   # fill in JFrog username/password/token
terraform init
terraform apply
```

After apply, note the outputs:
- `artifactory_url`, `vault_url`, `ssh_connection`
- `vault_key_file` → `vaultkey.txt` is written locally; contains the Vault unseal key, root token, AppRole **Role ID** and **Secret ID**
- `github_actions_role_arn` → put this in your GitHub repo secret `AWS_OIDC_ROLE_ARN` (for future use)

The `jfrog_default_credentials` output shows the default JFrog login (`admin` / `password`). Change the password on first login to match what you set in `terraform.tfvars`.

## 3. Create a SonarCloud account and project

1. Go to [sonarcloud.io](https://sonarcloud.io) and click **Log in** with your GitHub account.
2. Create a new **Organization** (free tier covers public repos).
3. Click **+ → Analyze new project**, select this repository, and import it.
4. Note the **Organization Key** (lowercase, shown under the org name) and **Project Key**.
5. In your GitHub repo: **Settings → Secrets and variables → Actions → Variables** and add:
   - `SONAR_PROJECT_KEY`
   - `SONAR_ORGANIZATION`

### Generate the SonarCloud token
1. SonarCloud: avatar → **My Account** → **Security**.
2. Under **Generate Tokens**, name it (e.g. `github-actions-token`), click **Generate**.
3. **Copy the token now** — it is shown only once.

## 4. Configure GitHub Actions secrets

Go to **Settings → Secrets and variables → Actions → Secrets** and add:

| Secret | Value |
|---|---|
| `SONAR_TOKEN` | SonarCloud token from step 3 |
| `JFROG_URL` | `artifactory_url` Terraform output |
| `VAULT_ADDR` | `vault_url` Terraform output |
| `VAULT_ROLE_ID` | Role ID from `vaultkey.txt` |
| `VAULT_SECRET_ID` | Secret ID from `vaultkey.txt` |

## 5. Sample application

The repo root contains a minimal Maven project ([pom.xml](pom.xml), `src/main/java`, `src/test/java`) that gives the pipeline something real to build, scan, and publish:

- `com.devops.utrains:devops-utrains-app` — a single `App` class with a JUnit 5 test
- `mvn clean verify` builds `target/devops-utrains-app-1.0.0.jar`, which the pipeline publishes to JFrog

## 6. Pipeline

[.github/workflows/jfrog-vault-ci.yml](.github/workflows/jfrog-vault-ci.yml) runs on every push to `main` with three parallel jobs after the build:

**`build-and-scan`**
1. Checkout + Java 17 setup
2. `mvn clean verify sonar:sonar` — builds, tests, and scans with SonarCloud (token from `SONAR_TOKEN` secret)
3. Uploads the built jar as a workflow artifact

**`publish-to-jfrog`** _(runs after build-and-scan)_
1. Downloads the jar artifact
2. Authenticates to Vault via AppRole, reads JFrog credentials from `secrets/creds/jfrog`
3. Publishes the jar to JFrog Artifactory

**`validate-vault`** _(runs in parallel with publish-to-jfrog)_
1. Authenticates to Vault via AppRole
2. Verifies `secrets/creds/jfrog` path is readable — fails the job if not

## 7. Enterprise pipeline template (reference)

[.github/workflows/enterprise-pipeline-template.yml](.github/workflows/enterprise-pipeline-template.yml) is a reference template (manually triggered via `workflow_dispatch`, not run on push) showing a fuller enterprise-style pipeline in GitHub Actions: Maven build/test, SonarCloud scan + quality gate, Trivy filesystem and image scans, JFrog artifact publish, Docker build/push to ECR, and Helm chart package/deploy to Kubernetes.

Use it as a starting point if you extend this project toward a containerized app with a Kubernetes deployment.

---

For infrastructure details see [GITHUB_ACTION_DEVOPS/README.md](GITHUB_ACTION_DEVOPS/README.md).
