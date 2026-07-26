# Project 1 — Minimal Automated Secure Deployment

## What it proves

On every GitHub push, the workflow:

1. Builds a Docker image.
2. Scans it with Trivy.
3. Generates a CycloneDX SBOM before pushing.
4. Pushes the image to GitHub Container Registry.
5. Creates a temporary Kubernetes cluster and deploys two replicas.
6. validates a rolling restart using readiness and liveness probes.
7. Deletes one pod and confirms Kubernetes returns to two running pods.

## Only four files matter

- `index.html`: the one-line website.
- `Dockerfile`: packages and starts the website.
- `k8s.yaml`: tells Kubernetes how to run it.
- `.github/workflows/pipeline.yml`: automates everything.

## Run locally on your Mac

Install Docker Desktop, open Terminal in this folder, then run:

```bash
docker build -t project1 .
docker run --rm -p 8080:8080 project1
```

Open `http://localhost:8080`. Stop it with `Control + C`.

## Run the full pipeline

1. Create a new public GitHub repository.
2. Upload every file, including the hidden `.github` folder.
3. Commit the files.
4. Open the repository's **Actions** tab.
5. Open **Build Scan Deploy** and watch each step.
6. Download the `security-reports` artifact to show `trivy.json` and `sbom.json`.

## What to say in the interview

> This is a small proof-of-concept CI/CD pipeline. A GitHub push triggers the workflow. It builds a BusyBox web-server image, scans the image with Trivy, generates a CycloneDX SBOM, pushes the scanned image to GHCR, and deploys it to a temporary kind Kubernetes cluster. The Deployment has two replicas, readiness and liveness probes, and a rolling-update strategy with maxUnavailable set to zero. The workflow restarts the Deployment and deletes a pod to demonstrate rollout validation and self-healing.

## Honest limitation

This demonstrates the mechanism in a temporary test cluster. It is not a production cloud deployment and it does not run a real load test. Say it is a **functional proof of concept designed for learning**.
