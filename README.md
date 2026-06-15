# DEVOPS-UTRAINS

A Terraform + GitHub Actions setup that provisions a small AWS "tools" server for a CI/CD pipeline: build code, scan it with SonarCloud, publish artifacts to JFrog, and manage secrets with HashiCorp Vault and AWS Secrets Manager.

All active code lives in [GITHUB_ACTION_DEVOPS/](GITHUB_ACTION_DEVOPS/). Everything else is in [legacy/](legacy/) (old Jenkins/SonarQube experiments, kept for reference only — not used by anything below).

## 1. What this code does

Running `terraform apply` in `GITHUB_ACTION_DEVOPS/` creates:

- A VPC + public subnet + Internet Gateway
- A security group opening `22` (SSH), `80` (HTTP), `8082` (JFrog), `4954` (Trivy), `8200` (Vault)
- One EC2 instance (Amazon Linux 2023, `t2.large`) that gets bootstrapped over SSH with:
  - **Docker**
  - **Java 17 + Maven** (required by Artifactory)
  - **JFrog Artifactory OSS** — artifact repository, served on port `8082`
  - **Trivy** — image/dependency vulnerability scanner
  - **HashiCorp Vault** — stores the JFrog credentials in its KV store and creates a `github-actions` AppRole so the pipeline can authenticate
- Two **AWS Secrets Manager** secrets ([secrets.tf](GITHUB_ACTION_DEVOPS/secrets.tf)):
  - `cicd/jfrog-credentials` — JFrog username/password/token
  - `cicd/sonarcloud-token` — SonarCloud token (see step 3 below)

The actual CI/CD work — build, **SonarCloud** scan, publish to JFrog — happens in **GitHub Actions** ([.github/workflows/jfrog-vault-ci.yml](.github/workflows/jfrog-vault-ci.yml)), not on the EC2 box. The box just hosts JFrog/Vault/Trivy and acts as the secret store backend.

There is **no Jenkins and no self-hosted SonarQube** in this active path — those only exist in `legacy/` from earlier iterations of this repo.

## 2. Deploy the infrastructure

```bash
cd GITHUB_ACTION_DEVOPS
cp terraform.tfvars.example terraform.tfvars   # fill in JFrog username/password/token
terraform init
terraform apply
```

After apply, note the outputs:
- `artifactory_url`, `vault_url`, `ssh_connection`
- `vault_key_file` → `vaultkey.txt` is copied locally; it contains the Vault root token/unseal key plus the AppRole **Role ID** and **Secret ID**
- `jfrog_credentials_secret_arn`, `sonarcloud_token_secret_arn`

## 3. Create a SonarCloud account and project

1. Go to [sonarcloud.io](https://sonarcloud.io) and click **Log in**.
2. Sign up / log in with your **GitHub** account — SonarCloud authenticates via your VCS provider.
3. Authorize SonarCloud to access your GitHub account/organization when prompted.
4. Create a new **Organization** in SonarCloud (it can mirror your GitHub org/username — free tier covers public repos).
5. Click **+ → Analyze new project**, select this repository, and import it.
6. Note the generated **Project Key** and **Organization Key**.
7. In your GitHub repo, go to **Settings → Secrets and variables → Actions → Variables** and add:
   - `SONAR_PROJECT_KEY`
   - `SONAR_ORGANIZATION`

### Generate the token
1. In SonarCloud: avatar (top right) → **My Account** → **Security**.
2. Under **Generate Tokens**, name it (e.g. `github-actions-token`), set an expiration, click **Generate**.
3. **Copy the token now** — it's shown only once.

## 4. Store the SonarCloud token in AWS Secrets Manager

The secret `cicd/sonarcloud-token` is already created by Terraform (empty until you populate it). Two ways to fill it in:

**Option A — Terraform** (edit `terraform.tfvars` then re-apply):
```hcl
sonarcloud_token = "<the token you copied>"
```
```bash
terraform apply
```

**Option B — AWS CLI** (no re-apply, good for rotation):
```bash
aws secretsmanager put-secret-value \
  --secret-id cicd/sonarcloud-token \
  --secret-string '{"SONAR_TOKEN":"<the token you copied>"}'
```

The JFrog credentials secret (`cicd/jfrog-credentials`) is filled in automatically from `terraform.tfvars` during `apply`.

## 5. Let GitHub Actions read the secrets (OIDC, no static AWS keys)

1. **Create the OIDC provider** (one-time per AWS account):
   ```bash
   aws iam create-open-id-connect-provider \
     --url https://token.actions.githubusercontent.com \
     --client-id-list sts.amazonaws.com \
     --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
   ```

2. **Create an IAM role** trusting GitHub Actions for this repo's `main` branch:
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [{
       "Effect": "Allow",
       "Principal": { "Federated": "arn:aws:iam::<account-id>:oidc-provider/token.actions.githubusercontent.com" },
       "Action": "sts:AssumeRoleWithWebIdentity",
       "Condition": {
         "StringEquals": { "token.actions.githubusercontent.com:aud": "sts.amazonaws.com" },
         "StringLike": { "token.actions.githubusercontent.com:sub": "repo:<github-org>/<repo-name>:ref:refs/heads/main" }
       }
     }]
   }
   ```

3. **Attach a least-privilege policy** scoped to just the two secrets:
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [{
       "Effect": "Allow",
       "Action": ["secretsmanager:GetSecretValue"],
       "Resource": [
         "arn:aws:secretsmanager:us-east-1:<account-id>:secret:cicd/jfrog-credentials-*",
         "arn:aws:secretsmanager:us-east-1:<account-id>:secret:cicd/sonarcloud-token-*"
       ]
     }]
   }
   ```

4. Add the role ARN as a GitHub repo secret: `AWS_OIDC_ROLE_ARN`.

5. Add the remaining repo secrets (connection info, not credentials):
   - `JFROG_URL` → from the `artifactory_url` output
   - `VAULT_ADDR` → from the `vault_url` output
   - `VAULT_ROLE_ID` / `VAULT_SECRET_ID` → from `vaultkey.txt`

## 6. Sample application

The repo root contains a minimal Maven project ([pom.xml](pom.xml), `src/main/java`, `src/test/java`) that gives the pipeline something real to build, scan, and publish:

- `com.devops.utrains:devops-utrains-app` — a single `App` class with one method and a JUnit 5 test
- `mvn clean verify` builds `target/devops-utrains-app-1.0.0.jar`, which is what step 5 of the pipeline below publishes to JFrog

## 7. Pipeline

[.github/workflows/jfrog-vault-ci.yml](.github/workflows/jfrog-vault-ci.yml) runs on every push to `main`:
1. Checkout + Java 17 setup
2. Assume the AWS role via OIDC
3. Fetch JFrog creds + SonarCloud token from Secrets Manager
4. `mvn clean verify sonar:sonar` against SonarCloud
5. Publish the built artifact to JFrog Artifactory
6. Sanity-check the Vault AppRole credentials

---

For full details and follow-up notes (e.g. scoping down the EC2 IAM role), see [GITHUB_ACTION_DEVOPS/README.md](GITHUB_ACTION_DEVOPS/README.md).
