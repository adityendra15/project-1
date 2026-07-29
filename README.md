# Automated Secure Website Deployment Pipeline

A reproducible CI/CD project that tests a Python website, builds a hardened container,
scans it before registry publication, generates a CycloneDX SBOM, deploys it to a real
Kubernetes cluster created inside CI, validates rolling-update availability, and proves
that Kubernetes replaces a failed Pod.

This repository is intentionally designed so its claims can be demonstrated rather than
only described.

## What the pipeline proves

| Resume claim | Executable evidence |
|---|---|
| Build on every push | `.github/workflows/secure-ci-cd.yml` triggers on pushes and pull requests. |
| Create a Docker image | The `verify` job builds baseline and candidate images. |
| Scan before registry push | Trivy runs in `verify`; `publish` cannot run unless `verify` succeeds. |
| Generate an SBOM | Trivy produces `artifacts/sbom.cdx.json`, uploaded from every run. |
| Deploy to Kubernetes automatically | CI creates a kind cluster and applies the manifests without manual commands. |
| Validate each rollout | `kubectl rollout status` and replica checks fail the job on a stalled rollout. |
| Reduce rollout downtime | Three replicas, readiness probes, `maxUnavailable: 0`, and continuous HTTP requests are tested. |
| Self-healing | The test deletes a Pod and verifies that the Deployment returns to three ready replicas. |
| Safe failed rollout | CI attempts a deliberately broken image update and verifies that requests continue before rollback. |

## Architecture

```text
Git push / pull request
        |
        v
Unit tests -> Docker build -> Trivy reports -> Critical-CVE gate -> CycloneDX SBOM
                                                        |
                                                        v
                                             Temporary kind cluster
                                                        |
                baseline deploy -> continuous requests -> rolling update
                                                        |
                              Pod deletion -> replacement verification
                                                        |
                     broken rollout -> availability check -> rollback
                                                        |
                                                        v
                         exact tested image artifact -> GHCR on the default branch
```

## Application endpoints

| Endpoint | Purpose |
|---|---|
| `/` | Human-readable deployment page. |
| `/health/live` | Tells Kubernetes whether the process should be restarted. |
| `/health/ready` | Tells Kubernetes whether the Pod should receive traffic. |
| `/version` | Shows version, commit, build time and Pod hostname. |

## Local prerequisites

- Python 3.13
- Docker
- kubectl
- kind
- curl
- Trivy

The GitHub workflow installs checksum-verified kind and Trivy releases automatically.
For local use, install those tools first or run `scripts/install-kind.sh` and
`scripts/install-trivy.sh` on Linux.

## Fast local test

After installing the prerequisites listed above, run:

```bash
./scripts/local-test.sh
```

The two installer scripts are used by the Linux GitHub Actions runner. On macOS, install
`kind` and Trivy with Homebrew before running the local test.

The script runs unit tests, builds two images, performs the blocking vulnerability scan,
generates the SBOM, deploys to kind, monitors a rollout, deletes a Pod to show
self-healing, and verifies that an intentionally broken rollout does not interrupt the
healthy Service.

To inspect the cluster after the script finishes:

```bash
KEEP_CLUSTER=true ./scripts/local-test.sh
kubectl -n secure-web get deployment,pods,service,pdb -o wide
kind delete cluster --name secure-pipeline-ci
```

## Run only the application

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --requirement requirements-dev.txt
APP_VERSION=local flask --app app.main run --host 0.0.0.0 --port 8080
```

In a second terminal:

```bash
curl http://127.0.0.1:8080/version
```

Or with Docker:

```bash
docker build -t secure-web:local .
docker run --rm -p 8080:8080 secure-web:local
```

## Vulnerability policy

The pipeline always records HIGH and CRITICAL findings in JSON. It blocks publication
when Trivy reports a **fixable CRITICAL** vulnerability. `--ignore-unfixed` is used so the
policy does not fail on an issue for which no patched package exists. This is a project
policy decision, not a claim that unfixed vulnerabilities are harmless.

## Why the image is saved between jobs

The `verify` job saves the exact Docker image it scanned and deployed. The `publish` job
loads that artifact and pushes it to GHCR. It does not rebuild the image after scanning,
which prevents a gap where one image is tested and a different image is published.

## Kubernetes availability design

- Three replicas keep capacity during updates.
- The rolling strategy uses `maxUnavailable: 0` and `maxSurge: 1`.
- Readiness removes a Pod from Service endpoints before it is safe to receive traffic.
- Liveness restarts a process that becomes unhealthy.
- A startup probe prevents premature liveness failures during startup.
- `preStop` plus a termination grace period gives traffic time to drain.
- A PodDisruptionBudget requests that two replicas remain available during voluntary disruption.

These controls reduce the risk of downtime. The automated request monitor is the evidence
for the tested scenario; no finite test can guarantee zero downtime in every possible
infrastructure failure.

## Evidence produced by GitHub Actions

Every workflow run uploads:

- Trivy JSON report
- Trivy gate output
- CycloneDX SBOM
- rolling-update availability report
- failed-rollout availability report
- self-healing report
- final Kubernetes state

## Repository guide

- `app/` — website and health endpoints
- `tests/` — unit tests
- `Dockerfile` — multi-stage, non-root container
- `k8s/` — Deployment, Service, ServiceAccount and PodDisruptionBudget
- `scripts/` — rendering and executable verification
- `.github/workflows/` — complete automated pipeline
- `README.md` — architecture, operation, evidence and limitations
- `SECURITY.md` — security policy and responsible reporting guidance

## Known limitations

- CI deploys to an ephemeral kind cluster, not a long-lived production cloud cluster.
- The example publishes only the immutable commit tag; production systems normally add
  promotion environments, approvals, signatures, provenance and registry retention rules.
- kind's default networking does not enforce Kubernetes NetworkPolicy, so this repository
  does not claim network-policy enforcement.
- A successful availability test demonstrates the tested rollout conditions; it is not a
  universal mathematical guarantee.
