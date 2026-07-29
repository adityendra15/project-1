# Learning Plan

Study this project in the following order.

## Module 1: Application

Read `app/main.py` and run the unit tests. Explain every endpoint and why readiness can
fail while liveness still succeeds.

## Module 2: Container

Read the Dockerfile from top to bottom. Explain multi-stage builds, the non-root user,
OCI labels, Gunicorn, and why `/tmp` must be writable in Kubernetes.

## Module 3: Kubernetes

Read the manifests in this order:

1. Namespace
2. ServiceAccount
3. Deployment
4. Service
5. PodDisruptionBudget

Draw the relationship among Deployment, ReplicaSet, Pods, Service, probes and endpoints.

## Module 4: Deployment behavior

Run `scripts/kubernetes-e2e.sh` and follow it line by line. Observe:

- baseline deployment,
- candidate rollout,
- continuous requests,
- Pod deletion and replacement,
- failed image rollout,
- rollback.

## Module 5: Security evidence

Explain the difference among:

- a vulnerability report,
- a blocking vulnerability policy,
- an SBOM,
- a tested image,
- a published image.

## Module 6: GitHub Actions

Read `.github/workflows/secure-ci-cd.yml`. For every step, answer:

- What is its input?
- What artifact or state does it produce?
- What makes it fail?
- Which later step depends on it?
- What permission does it need?

## Final exercise

Rebuild the project in an empty folder without copying files. Looking up syntax is allowed,
but you should be able to explain the architecture and the reason for every control.
