# SonarCloud + AWS Secrets Manager Lab

A small, self-contained lab for beginners. It shows you how to:

1. Create a **SonarCloud** account and get a token that lets a tool scan your code for bugs/security issues.
2. Store that token safely in **AWS Secrets Manager** (instead of pasting it into files or chat).
3. Let a **GitHub Actions** workflow pick up the token automatically and run a SonarCloud scan every time you push code — **without ever putting an AWS password in GitHub** (it uses something called "OIDC", explained below).

You don't need to know Terraform or AWS well to follow this — every step is explained.

---

## How it all fits together

```
You push code to GitHub
        |
        v
GitHub Actions workflow starts
        |
        v
Workflow asks AWS: "let me log in, here is a one-time GitHub-signed token" (OIDC)
        |
        v
AWS checks: "is this request coming from the right repo?" -> yes -> gives temporary access
        |
        v
Workflow reads the SonarCloud token from AWS Secrets Manager
        |
        v
Workflow runs the SonarCloud scanner using that token
        |
        v
Results show up on sonarcloud.io
```

The Terraform code in [terraform/](terraform/) creates two things in your AWS account:

- An **AWS Secrets Manager secret** named `sonarcloud/token` — a locked box that holds your SonarCloud token.
- An **IAM role** that GitHub Actions is allowed to "become", but only when the workflow runs in *your* repo. That role can only read that one secret — nothing else in your AWS account.

---

## Prerequisites

- An AWS account (the [AWS Free Tier](https://aws.amazon.com/free/) is enough — Secrets Manager and IAM resources used here cost a few cents at most).
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) installed and configured (`aws configure`) with credentials that can create IAM roles and Secrets Manager secrets.
- [Terraform](https://developer.hashicorp.com/terraform/install) installed (version 1.0 or newer).
- A GitHub account and a repository where you want the scan to run.
- A free [SonarCloud](https://sonarcloud.io) account (we'll create this in Step 1).

---

## Step 1 — Create a SonarCloud account, organization, project, and token

1. Go to [https://sonarcloud.io](https://sonarcloud.io) and click **Log in**, then choose **"Log in with GitHub"** (recommended — it's the fastest way and lets SonarCloud see your repos).
2. Authorize SonarCloud to access your GitHub account when prompted.
3. **Create an organization**:
   - SonarCloud will prompt you to import an organization from GitHub, or you can create a free one manually.
   - Pick the **Free plan**.
   - Note down your **organization key** (shown in the URL and in Administration -> Organization settings) — you'll need it later. Example: `your-org-key`.
4. **Create a project**:
   - Click **"+"** -> **"Analyze new project"**.
   - Select the GitHub repository you want to analyze (or create one) and follow the prompts to set it up.
   - Note down the **project key** (e.g. `your-org_your-repo`) — shown on the project's main page.
5. **Generate a token**:
   - Click your profile picture (top right) -> **My Account** -> **Security**.
   - Under "Generate Tokens", give it a name (e.g. `aws-secrets-lab`), choose type **"Global Analysis Token"** (or "Project Analysis Token" scoped to your project), and click **Generate**.
   - **Copy the token immediately** — SonarCloud only shows it once. It looks something like `1a2b3c4d5e6f7g8h9i0j...`.

Keep this token handy — you'll paste it into AWS in Step 3.

---

## Step 2 — Create the AWS resources with Terraform

This step creates the Secrets Manager secret and the IAM role that GitHub will use.

```bash
cd sonarcloud-aws-secrets-lab/terraform

# Copy the example variables file and edit it
cp terraform.tfvars.example terraform.tfvars
```

Open `terraform.tfvars` and fill in:

```hcl
github_org  = "your-github-username-or-org"
github_repo = "your-repo-name"
```

These tell AWS which GitHub repository is allowed to use the IAM role. Leave `sonarcloud_token` commented out for now — we'll add it in Step 3.

Then run:

```bash
terraform init
terraform apply
```

Type `yes` when prompted. After a minute or two, Terraform will print two outputs:

- `github_actions_role_arn` — an ARN (a long AWS resource ID) that looks like `arn:aws:iam::123456789012:role/github-actions-sonarcloud-role`. You'll need this in Step 4.
- `secret_name` — should be `sonarcloud/token`.

> **Note on "OIDC"**: OIDC (OpenID Connect) is just a standard way for GitHub to prove its identity to AWS using a short-lived, auto-generated token — no AWS access keys are stored in GitHub at all.
>
> AWS allows only **one** GitHub OIDC provider per account. [terraform/oidc.tf](terraform/oidc.tf) assumes one **already exists** (a `data` lookup, not a new resource) and just reuses it. Check with:
>
> ```bash
> aws iam list-open-id-connect-providers
> ```
>
> - If it returns a `token.actions.githubusercontent.com` provider, you're good — `terraform apply` will find and reuse it automatically.
> - If the list is **empty**, open [terraform/oidc.tf](terraform/oidc.tf) and replace the `data "aws_iam_openid_connect_provider" "github"` block with:
>   ```hcl
>   resource "aws_iam_openid_connect_provider" "github" {
>     url             = "https://token.actions.githubusercontent.com"
>     client_id_list  = ["sts.amazonaws.com"]
>     thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
>   }
>   ```
>   and change every `data.aws_iam_openid_connect_provider.github.arn` to `aws_iam_openid_connect_provider.github.arn`.

---

## Step 3 — Put your SonarCloud token into the secret

You have two options. Pick whichever feels easier.

### Option A — Using the AWS CLI (recommended, no re-apply needed)

```bash
aws secretsmanager put-secret-value \
  --secret-id sonarcloud/token \
  --secret-string '{"SONAR_TOKEN":"PASTE-YOUR-SONARCLOUD-TOKEN-HERE"}'
```

Replace `PASTE-YOUR-SONARCLOUD-TOKEN-HERE` with the token you copied in Step 1.

### Option B — Using Terraform

Open `terraform/terraform.tfvars` and uncomment/add this line:

```hcl
sonarcloud_token = "PASTE-YOUR-SONARCLOUD-TOKEN-HERE"
```

Then run `terraform apply` again. (Be careful: this writes the token into Terraform's state file, which is a plain-text file on your disk — Option A avoids that.)

---

## Step 4 — Configure your GitHub repository

1. Go to your GitHub repository -> **Settings** -> **Secrets and variables** -> **Actions**.
2. Click **New repository secret**:
   - Name: `AWS_ROLE_ARN`
   - Value: the `github_actions_role_arn` output from Step 2 (e.g. `arn:aws:iam::123456789012:role/github-actions-sonarcloud-role`)
3. At the **root of your GitHub repository** (not inside this lab folder — GitHub only runs workflows that live in a top-level `.github/workflows/` directory), create a `sonar-project.properties` file with your real values from Step 1:

```properties
sonar.projectKey=your-org_your-repo
sonar.organization=your-sonarcloud-org
```

4. Copy [.github/workflows/sonarcloud.yml](#) from this lab (or the version already placed at your repo root, if you're using this lab as a reference) into your repo's root `.github/workflows/` directory.

---

## Step 5 — Push and watch it run

1. Commit and push your repo's root `.github/workflows/sonarcloud.yml` and `sonar-project.properties` (these must be at the repo root, not inside `sonarcloud-aws-secrets-lab/`).
2. Go to the **Actions** tab in your GitHub repository — you should see the **"SonarCloud Scan"** workflow running.
3. Once it finishes, go to [sonarcloud.io](https://sonarcloud.io) and open your project — you should see your scan results (bugs, code smells, security hotspots, etc.).

Here's what the workflow does, step by step:

1. Checks out your code.
2. Logs in to AWS using OIDC (the `AWS_ROLE_ARN` secret you set in Step 4) — no AWS password involved.
3. Fetches the SonarCloud token from the `sonarcloud/token` secret in AWS Secrets Manager and masks it in the logs so it never appears in plain text.
4. Runs the SonarCloud scanner using that token.

---

## Troubleshooting

- **"Error: An error occurred (AccessDenied)" in the GitHub Actions log** — double check that `AWS_ROLE_ARN` in your repo secrets exactly matches the `github_actions_role_arn` Terraform output, and that `github_org`/`github_repo` in `terraform.tfvars` exactly match your GitHub username/org and repository name.
- **"ResourceNotFoundException: Secrets Manager can't find the specified secret"** — make sure `terraform apply` completed successfully and that you completed Step 3 (the secret exists, but may have no value yet if you skipped it).
- **OIDC provider already exists error** — see the note at the end of Step 2.
- **SonarCloud shows "no analysis yet"** — check the `sonar.projectKey` and `sonar.organization` values in your repo root's `sonar-project.properties` match exactly what's shown on your SonarCloud project page.

---

## Cleaning up

To remove everything this lab created in AWS:

```bash
cd terraform
terraform destroy
```

This deletes the Secrets Manager secret, the IAM role, and (if no other project uses it) the GitHub OIDC provider. Your SonarCloud account and project are not affected — delete those manually from sonarcloud.io if you no longer need them.
