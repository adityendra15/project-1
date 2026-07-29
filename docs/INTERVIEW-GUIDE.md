# Interview Guide

Do not memorize sentences. Run the project, break it, and explain what you observe.

## Explain the complete flow

1. A push starts GitHub Actions.
2. Python unit tests validate application behavior.
3. Docker builds baseline and candidate images.
4. Trivy records HIGH and CRITICAL findings.
5. A fixable CRITICAL finding blocks the workflow.
6. Trivy generates a CycloneDX SBOM.
7. kind creates a Kubernetes cluster inside the runner.
8. The baseline version is deployed and becomes ready.
9. A request monitor runs while the candidate version rolls out.
10. Kubernetes creates one surge Pod and removes old Pods only after replacements are ready.
11. The test deletes a Pod; the Deployment controller creates another.
12. A deliberately invalid image causes a rollout failure while old healthy Pods remain.
13. The exact tested image is transferred to a separate publishing job and pushed to GHCR.

## Liveness vs readiness vs startup

- **Startup probe:** gives a slow-starting process time to initialize. Until it succeeds,
  liveness and readiness checks do not control the container normally.
- **Readiness probe:** controls whether the Pod is included in Service endpoints. A failing
  readiness check does not restart the container.
- **Liveness probe:** asks whether Kubernetes should restart the container.

A database outage might make an application temporarily unready, but restarting it may not
fix the database. That is why readiness and liveness should not blindly perform the same
checks in every application.

## Why `maxUnavailable: 0` is not enough by itself

A rollout also needs working readiness checks, enough cluster capacity for the surge Pod,
multiple replicas, correct graceful shutdown behavior, and a healthy Service. The request
monitor tests the combined behavior.

## What “self-healing” means here

The Deployment maintains a desired state of three replicas. Deleting a managed Pod creates
a difference between desired and actual state. The ReplicaSet controller creates a
replacement. This does not mean Kubernetes can repair every application bug.

## Why scan before push

The workflow should avoid publishing an image that violates the security policy. The
publishing job depends on the verification job, so a failed gate prevents publication.

## Why save the image rather than rebuild it

A second build could differ because dependencies or base-image layers changed. Passing the
exact image artifact means the published bytes are the bytes that were scanned and tested.

## What an SBOM is

An SBOM is an inventory of software components and metadata. It supports vulnerability,
license and incident analysis. It does not prove that software is secure, that the build was
trustworthy, or that every component was detected.

## Important trade-offs

- Ephemeral kind provides reproducible Kubernetes evidence without cloud cost, but it does
  not model every cloud load balancer, CNI or storage behavior.
- Blocking only fixable CRITICAL vulnerabilities keeps the demonstration stable, but a real
  organization should define severity, exploitability, exception and remediation SLAs.
- Three replicas improve availability but use more resources.
- `maxUnavailable: 0` requires spare capacity for `maxSurge`.

## Questions to practice

1. Why does the readiness endpoint use a file switch?
2. What happens after a readiness probe fails?
3. What happens after a liveness probe fails three times?
4. Why is a startup probe useful?
5. Why are there three replicas?
6. What do `maxUnavailable` and `maxSurge` control?
7. How does the script detect failed requests during rollout?
8. What exact condition blocks registry publication?
9. Why is `continue-on-error` used for the scan step, and where is failure re-enforced?
10. Why does the publish job need `packages: write` while verify does not?
11. How does the project prove self-healing?
12. Why is an SBOM not the same as a vulnerability report?
13. What limitations does kind introduce?
14. How would you deploy to a real cluster securely?
15. How would image signing and provenance extend this project?
