# Start Here

This repository is Project 1 from the resume: **Automated Secure Website Deployment Pipeline**.

## Recommended first test: GitHub Actions

1. Back up the current `project-1` repository.
2. Replace its files with the contents of this folder. Keep the `.github` directory.
3. Commit and push to the repository's default branch.
4. Open the repository's **Actions** tab and select **Secure CI/CD Pipeline**.
5. Open the `verify` job and watch each stage.
6. After success, download the security and Kubernetes evidence artifacts.
7. Open the repository's **Packages** section and confirm the immutable `sha-...` image exists.

No additional registry password is required. The workflow uses the repository-scoped
`GITHUB_TOKEN` and grants package write permission only to the publishing job.

## Full local test

A Linux machine or WSL2 environment with Docker is recommended.

```bash
./scripts/install-kind.sh
./scripts/install-trivy.sh
./scripts/local-test.sh
```

The complete run deliberately takes time because it performs a real Kubernetes rolling
update, continuously checks availability, deletes a Pod to prove replacement, and attempts
a broken rollout before rolling back.

## Evidence to save for the interview

- Screenshot of the successful GitHub Actions workflow
- Trivy JSON report
- CycloneDX SBOM
- Rolling-update availability JSON showing zero failures
- Failed-rollout availability JSON showing zero failures
- Self-healing JSON showing the deleted and replacement Pod names
- GHCR package page with the immutable commit tag

## When something fails

Do not randomly change files. Save:

- the failed workflow step name,
- the complete error output,
- the relevant generated artifact,
- your operating system and Docker version for local failures.

Then diagnose the reason before applying a fix. Understanding each failure is part of
turning the repository into work you can explain confidently.
