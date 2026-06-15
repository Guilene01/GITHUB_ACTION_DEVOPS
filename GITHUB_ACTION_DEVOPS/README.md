# GITHUB_ACTION_DEVOPS

This is the **canonical** infrastructure module for the repo: a Terraform-provisioned AWS "tools" server running **JFrog Artifactory**, **HashiCorp Vault**, and **Trivy**, paired with a **GitHub Actions** pipeline that builds, scans with **SonarCloud**, and publishes artifacts. Secrets (JFrog credentials, SonarCloud token) are stored in **AWS Secrets Manager** and retrieved at pipeline runtime via GitHub OIDC — nothing sensitive needs to live in GitHub repo secrets or plaintext tfvars.

> Jenkins and self-hosted SonarQube are not part of this module. See [../legacy/](../legacy/) for retired modules.

## 1. What gets created

### Infrastructure ([main.tf](main.tf), [roles.tf](roles.tf), [secrets.tf](secrets.tf), [generate-key.tf](generate-key.tf))
- A VPC (`10.0.0.0/16`) with a public subnet, Internet Gateway and route table
- A security group (`cicd-security-group`) opening:
  - `22` – SSH
  - `80` – HTTP
  - `8082` – JFrog Artifactory
  - `4954` – Trivy
  - `8200` – HashiCorp Vault
- An SSH key pair generated locally (`server_key.pem`) and attached to the instance
- An EC2 instance (`t2.large`, latest Amazon Linux 2023 AMI) with an IAM instance profile (`cicd_tools_admin_role`)
- Two AWS Secrets Manager secrets:
  - `cicd/jfrog-credentials` – JFrog username/password/token
  - `cicd/sonarcloud-token` – SonarCloud token (populated once you've generated one, see below)

### Bootstrap scripts (`installations_scripts/`)
The instance is provisioned over SSH and runs these scripts in order:

| Order | Script | What it installs |
|---|---|---|
| 1 | `install_docker.sh` | Docker, adds `ec2-user` to the `docker` group |
| 2 | `install_java.sh` | Java 17 (Amazon Corretto) + Maven 3.9.11 — required by JFrog Artifactory |
| 3 | `install_jfrog.sh` | JFrog Artifactory OSS as a systemd service (port `8082`) |
| 4 | `install_trivy.sh` | Trivy (container/image vulnerability scanner) |
| 5 | `install_vault.sh` | HashiCorp Vault, an AppRole (`github-actions-role`) + `github-actions-policy`, and seeds the JFrog creds into Vault's KV store |

### Outputs ([output.tf](output.tf))
- `ssh_connection` – ready-to-use SSH command for the instance
- `artifactory_url` – `http://<public-ip>:8082`
- `vault_url` – `http://<public-ip>:8200`
- `vault_key_file` – local file (`vaultkey.txt`, fetched via `scp`) containing the Vault unseal key, root token, and the AppRole Role ID / Secret ID
- `jfrog_credentials_secret_arn` / `sonarcloud_token_secret_arn` – ARNs of the Secrets Manager secrets

## 2. Deploying

```bash
cd GITHUB_ACTION_DEVOPS
cp terraform.tfvars.example terraform.tfvars   # then edit with real values
terraform init
terraform plan
terraform apply
```

After apply, `vaultkey.txt` is copied to this directory — it contains the Vault root token/unseal key plus the `github-actions-role` Role ID and Secret ID needed by the pipeline.

⚠️ `terraform.tfvars` contains real JFrog credentials and is excluded from version control (see root `.gitignore`). Use `terraform.tfvars.example` as the template.

---

## 3. CI/CD pipeline (GitHub Actions)

The pipeline lives in [.github/workflows/jfrog-vault-ci.yml](../.github/workflows/jfrog-vault-ci.yml) and, on every push to `main`:

1. Checks out the repo and sets up Java 17
2. Assumes an AWS IAM role via OIDC (no long-lived AWS keys stored in GitHub)
3. Fetches the **JFrog credentials** and **SonarCloud token** from **AWS Secrets Manager**
4. Builds with Maven and runs the **SonarCloud** analysis
5. Publishes the built artifact to **JFrog Artifactory**
6. Validates the Vault AppRole credentials are present

---

## 4. SonarCloud setup

### Step 1 — Create a SonarCloud account
1. Go to [sonarcloud.io](https://sonarcloud.io) and click **Log in**.
2. Sign up using your **GitHub** account — SonarCloud authenticates via your VCS provider.
3. Authorize SonarCloud to access your GitHub account/organization when prompted.
4. Create a new **Organization** in SonarCloud (it can mirror your GitHub org/username). The free tier covers public repos.
5. Click **+ → Analyze new project**, select this repository, and import it.
6. Note the generated **Project Key** and **Organization Key** — set these as repository **variables** (not secrets) in GitHub: `Settings → Secrets and variables → Actions → Variables` → `SONAR_PROJECT_KEY`, `SONAR_ORGANIZATION`.

### Step 2 — Generate a SonarCloud token
1. In SonarCloud, click your avatar (top right) → **My Account** → **Security** tab.
2. Under **Generate Tokens**, give it a name (e.g. `github-actions-token`), choose an expiration, and click **Generate**.
3. **Copy the token immediately** — it's shown only once.

---

## 5. Storing the SonarCloud token in AWS Secrets Manager

The secret container `cicd/sonarcloud-token` is created by Terraform ([secrets.tf](secrets.tf)). Two ways to populate it with the token from Step 2:

**Option A — via Terraform** (before first `apply`, or with a follow-up `apply`):
```bash
# in terraform.tfvars
sonarcloud_token = "<the token you copied>"
```
```bash
terraform apply
```

**Option B — via AWS CLI** (no re-apply needed, e.g. when rotating the token):
```bash
aws secretsmanager put-secret-value \
  --secret-id cicd/sonarcloud-token \
  --secret-string '{"SONAR_TOKEN":"<the token you copied>"}'
```

The JFrog credentials secret (`cicd/jfrog-credentials`) is populated automatically from `jfrog_secret_username_and_password` / `jfrog_secret_token` in `terraform.tfvars`.

---

## 6. Letting GitHub Actions read the secrets (OIDC, no static AWS keys)

1. **Create an OIDC identity provider** in IAM for GitHub Actions (one-time per AWS account):
   ```bash
   aws iam create-open-id-connect-provider \
     --url https://token.actions.githubusercontent.com \
     --client-id-list sts.amazonaws.com \
     --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
   ```

2. **Create an IAM role** that trusts GitHub Actions for this repo:
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Principal": {
           "Federated": "arn:aws:iam::<account-id>:oidc-provider/token.actions.githubusercontent.com"
         },
         "Action": "sts:AssumeRoleWithWebIdentity",
         "Condition": {
           "StringEquals": {
             "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
           },
           "StringLike": {
             "token.actions.githubusercontent.com:sub": "repo:<github-org>/<repo-name>:ref:refs/heads/main"
           }
         }
       }
     ]
   }
   ```

3. **Attach a least-privilege policy** that only allows reading these two secrets:
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Action": ["secretsmanager:GetSecretValue"],
         "Resource": [
           "arn:aws:secretsmanager:us-east-1:<account-id>:secret:cicd/jfrog-credentials-*",
           "arn:aws:secretsmanager:us-east-1:<account-id>:secret:cicd/sonarcloud-token-*"
         ]
       }
     ]
   }
   ```

4. **Store the role ARN as a GitHub secret**: `Settings → Secrets and variables → Actions → New repository secret` → `AWS_OIDC_ROLE_ARN` = the role's ARN.

5. **Remaining repository secrets** used by the workflow (not stored in AWS Secrets Manager, since they're connection details rather than credentials):
   - `JFROG_URL` – from the `artifactory_url` Terraform output
   - `VAULT_ADDR` – from the `vault_url` Terraform output
   - `VAULT_ROLE_ID` / `VAULT_SECRET_ID` – from `vaultkey.txt`

---

## 7. Notes / future improvements

- The instance role `cicd_tools_admin_role` ([roles.tf](roles.tf)) currently has `AdministratorAccess`. For production use, scope this down to exactly what the bootstrap scripts need (EC2 description, Secrets Manager read/write for `cicd/*`).
- `terraform.tfvars` still contains the JFrog admin password and token in plaintext locally. They're seeded into both Vault and Secrets Manager — consider generating them at deploy time (e.g. `random_password`) instead of hand-picking values.
