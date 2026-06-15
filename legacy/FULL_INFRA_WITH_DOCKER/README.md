# FULL_INFRA_WITH_DOCKER

Terraform project that provisions a single **CI/CD "tools" EC2 instance** on AWS, bootstrapped with **JFrog Artifactory**, **HashiCorp Vault** and **Trivy**. Builds, code scanning (SonarCloud) and artifact publishing are handled by **GitHub Actions**, which talk to this infrastructure.

> Jenkins and the self-hosted SonarQube container have been removed. Static analysis is now done via **SonarCloud** (SaaS), and the pipeline runs on **GitHub Actions** instead of Jenkins.

## 1. What gets created

### Infrastructure ([main.tf](main.tf), [roles.tf](roles.tf), [generate-key.tf](generate-key.tf))
- A VPC (`10.0.0.0/16`) with a public subnet, Internet Gateway and route table
- A security group (`cicd-security-group`) opening:
  - `22` – SSH
  - `80` – HTTP
  - `8082` – JFrog Artifactory
  - `4954` – Trivy
  - `8200` – HashiCorp Vault
- An SSH key pair generated locally (`server_key.pem`) and attached to the instance
- An EC2 instance (`t2.large`, latest Amazon Linux 2023 AMI) with an IAM instance profile (`cicd_tools_admin_role`)

### Bootstrap scripts (`installations_scripts/`)
The instance is provisioned over SSH and runs these scripts in order:

| Order | Script | What it installs |
|---|---|---|
| 1 | `install_docker.sh` | Docker, adds `ec2-user` to the `docker` group |
| 2 | `install_java.sh` | Java 17 (Amazon Corretto) + Maven 3.9.11 — required by JFrog Artifactory |
| 3 | `install_jfrog.sh` | JFrog Artifactory OSS as a systemd service (port `8082`) |
| 4 | `install_trivy.sh` | Trivy (container/image vulnerability scanner) |
| 5 | `install_vault.sh` | HashiCorp Vault, configured with an AppRole + `tools` policy that stores the JFrog username/password/token as secrets |

### Outputs ([output.tf](output.tf))
- `ssh_connexion` – ready-to-use SSH command for the instance
- `JFROG_URL` – `http://<public-ip>:8082`
- `HASHICORP_VAULT_URL` – `http://<public-ip>:8200`
- `vault_key_file` – path to the local file containing the Vault unseal key / root token / AppRole credentials (fetched via `scp` by `null_resource.fetch_remote_file`)

## 2. Deploying

```bash
cd FULL_INFRA_WITH_DOCKER
terraform init
terraform plan
terraform apply
```

⚠️ **Security note:** [terraform.tfvars](terraform.tfvars) currently stores `jfrog_secret_username_and_password` and `jfrog_secret_token` in **plain text**. These end up in Vault on the instance, but the source values are committed to the repo. For anything beyond a training lab, move these into AWS Secrets Manager / SSM Parameter Store (or a `.tfvars` file excluded via `.gitignore`) and have Terraform read them with `data "aws_secretsmanager_secret_version"`.

---

## 3. CI/CD pipeline (GitHub Actions)

The pipeline lives in [.github/workflows/full-infra-jfrog-vault-sonarcloud-ci.yml](../.github/workflows/full-infra-jfrog-vault-sonarcloud-ci.yml) and, on every push to `main`:

1. Checks out the repo and sets up Java 17
2. Assumes an AWS IAM role via OIDC (no long-lived AWS keys stored in GitHub)
3. Fetches the **SonarCloud token** from **AWS Secrets Manager**
4. Builds with Maven and runs the **SonarCloud** analysis
5. Publishes the built artifact to **JFrog Artifactory**
6. Validates connectivity to **HashiCorp Vault**

The sections below explain how to set up SonarCloud and wire AWS Secrets Manager into this workflow.

---

## 4. SonarCloud setup

### Step 1 — Create a SonarCloud account

1. Go to [sonarcloud.io](https://sonarcloud.io) and click **Log in**.
2. Sign up using your **GitHub** account — SonarCloud authenticates via your VCS provider.
3. Authorize SonarCloud to access your GitHub account/organization when prompted.
4. Create a new **Organization** in SonarCloud (it can mirror your GitHub org/username). The free tier covers public repos.
5. Click **+ → Analyze new project**, select this repository, and import it.
6. Note the generated **Project Key** and **Organization Key** — these map to `vars.SONAR_PROJECT_KEY` and `vars.SONAR_ORGANIZATION` in the workflow (set them under **Settings → Secrets and variables → Actions → Variables** in your GitHub repo).

### Step 2 — Generate a SonarCloud token

1. In SonarCloud, click your avatar (top right) → **My Account** → **Security** tab.
2. Under **Generate Tokens**, give it a name (e.g. `github-actions-token`), choose an expiration, and click **Generate**.
3. **Copy the token immediately** — it's shown only once.

---

## 5. Storing the SonarCloud token in AWS Secrets Manager

**Option A — AWS Console**
1. Go to **AWS Console → Secrets Manager → Store a new secret**.
2. Choose **Other type of secret**.
3. Add a key/value pair:
   - Key: `SONAR_TOKEN`
   - Value: `<the token you copied>`
4. Name the secret `cicd/sonarcloud-token` and click **Store**.

**Option B — AWS CLI**
```bash
aws secretsmanager create-secret \
  --name cicd/sonarcloud-token \
  --description "SonarCloud token used by the GitHub Actions pipeline" \
  --secret-string '{"SONAR_TOKEN":"<the token you copied>"}' \
  --region us-east-1
```

To rotate it later:
```bash
aws secretsmanager put-secret-value \
  --secret-id cicd/sonarcloud-token \
  --secret-string '{"SONAR_TOKEN":"<new token>"}'
```

---

## 6. Letting GitHub Actions read the secret (OIDC, no static AWS keys)

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

3. **Attach a least-privilege policy** that only allows reading this one secret:
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Action": ["secretsmanager:GetSecretValue"],
         "Resource": "arn:aws:secretsmanager:us-east-1:<account-id>:secret:cicd/sonarcloud-token-*"
       }
     ]
   }
   ```

4. **Store the role ARN as a GitHub secret**: `Settings → Secrets and variables → Actions → New repository secret` → `AWS_OIDC_ROLE_ARN` = the role's ARN. The workflow's `aws-actions/configure-aws-credentials` step assumes this role at runtime to fetch `cicd/sonarcloud-token`.

5. Also add the remaining secrets used by the workflow: `JFROG_URL`, `JFROG_USERNAME`, `JFROG_PASSWORD`, `VAULT_ADDR`, `VAULT_TOKEN` (values come from the Terraform outputs and `vaultkey.txt`).

---

## 7. Migrating the existing JFrog/Vault secrets

The same Secrets Manager + OIDC pattern used for the SonarCloud token can replace the plaintext values in [terraform.tfvars](terraform.tfvars) and the Vault-based secret storage in `install_vault.sh`, giving a single, consistent secrets-management story across JFrog, Vault and SonarCloud.
