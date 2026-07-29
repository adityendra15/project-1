# Resume Claim Mapping

This document connects every project claim to code and executable evidence.

## “On every code push … builds the application”

- Trigger: `.github/workflows/secure-ci-cd.yml`
- Unit tests: `tests/test_app.py`
- Candidate build: `Build baseline and candidate images` workflow step

The workflow also runs for pull requests so problems are detected before merging.

## “Creates a Docker image”

- Build definition: `Dockerfile`
- Non-root UID: 10001
- Build-time metadata: `APP_VERSION`, `VCS_REF`, `BUILD_TIME`
- Runtime server: Gunicorn

## “Deploys it to Kubernetes with zero manual intervention”

- Cluster creation: `scripts/install-kind.sh` and `scripts/kubernetes-e2e.sh`
- Manifests: `k8s/`
- Deployment command: workflow step `Verify rolling deployment and self-healing`

The target is an ephemeral kind cluster inside GitHub Actions. No human command is needed
after a push starts the workflow.

## “Automated vulnerability scanning and SBOM generation before push”

- Trivy installation: `scripts/install-trivy.sh`
- JSON report: `artifacts/trivy-image.json`
- Blocking policy: CRITICAL findings with fixes available
- SBOM: CycloneDX JSON
- Job dependency: `publish` has `needs: verify`

The exact scanned image is saved as an artifact and loaded by the publishing job, avoiding
a rebuild between verification and publication.

## “Liveness/readiness probes”

- Application logic: `app/main.py`
- Probe configuration: `k8s/deployment.yaml`
- Readiness can fail independently by creating `/tmp/not-ready`.

## “Validate each rollout”

- `kubectl rollout status` checks progress.
- `scripts/wait-for-replicas.sh` requires all three replicas to be ready, available and updated.
- `/version` proves that the candidate version is actually serving traffic.

## “Zero-downtime, self-healing deployments”

The repository implements and tests the mechanisms behind the claim:

- `replicas: 3`
- `maxUnavailable: 0`
- readiness and liveness probes
- graceful termination settings
- continuous request monitoring during replacement
- Pod deletion followed by replacement verification
- intentionally broken rollout while old replicas continue serving

Accurate interview wording: the tested rollout completed with zero failed requests, and the
Deployment controller restored the declared replica count after a Pod was deleted.
