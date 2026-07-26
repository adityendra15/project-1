# Understand every line — Project 1

## `index.html`

The browser displays one heading. The application is intentionally tiny because the project is about the pipeline, not application development.

## `Dockerfile`

1. `FROM busybox:1.36.1` starts from a tiny Linux image containing a basic web server.
2. `COPY ...` places the webpage inside the image.
3. `USER 1000` avoids running the web server as root.
4. `CMD ...` starts the web server on port 8080.

## `k8s.yaml`

- `Deployment` keeps the application running.
- `replicas: 2` requests two identical pods.
- `maxUnavailable: 0` tells Kubernetes not to intentionally remove an available pod during a rolling update.
- `maxSurge: 1` permits one extra pod during an update.
- `readinessProbe` decides when a pod may receive traffic.
- `livenessProbe` lets Kubernetes restart an unhealthy container.
- `Service` gives the pods one stable network name.

## Workflow

- `checkout` downloads the repository into the GitHub runner.
- `docker build` creates the image.
- The two Trivy commands create a vulnerability report and SBOM.
- `docker push` sends the image to GHCR.
- `kind-action` creates a temporary Kubernetes cluster.
- `kubectl apply` deploys the YAML.
- `rollout status` waits until the Deployment is healthy.
- `rollout restart` demonstrates the rolling-update configuration.
- The final step deletes one pod; the Deployment controller creates its replacement.
