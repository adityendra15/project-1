# Testing and Demonstrations

## Unit tests

```bash
make install
make test
```

The tests cover the page, health endpoints, readiness/liveness separation, version metadata,
security headers and JSON 404 responses.

## Readiness demonstration without Kubernetes

```bash
make run
curl -i http://127.0.0.1:8080/health/ready
touch /tmp/not-ready
curl -i http://127.0.0.1:8080/health/ready
curl -i http://127.0.0.1:8080/health/live
rm /tmp/not-ready
```

Expected result: readiness becomes HTTP 503 while liveness remains HTTP 200.

## Container security checks

```bash
docker build -t secure-web:local .
docker inspect secure-web:local --format '{{.Config.User}}'
docker run --rm secure-web:local id
```

Expected UID and GID: `10001`.

The Kubernetes manifest additionally disables privilege escalation, drops Linux capabilities,
uses the runtime-default seccomp profile, and makes the root filesystem read-only.

## Complete Kubernetes test

```bash
./scripts/local-test.sh
```

Evidence appears in `build/` and `artifacts/`.

## Observe rolling updates manually

Run the full test with `KEEP_CLUSTER=true`, then in another terminal:

```bash
kubectl -n secure-web get pods --watch
```

Look for a new Pod becoming ready before an old Pod terminates.

## Observe self-healing manually

```bash
kubectl -n secure-web get pods
kubectl -n secure-web delete pod <one-pod-name>
kubectl -n secure-web get pods --watch
```

The ReplicaSet should create a replacement because the Deployment still declares three replicas.

## Demonstrate readiness routing

```bash
pod=$(kubectl -n secure-web get pods -l app.kubernetes.io/name=secure-web \
  -o jsonpath='{.items[0].metadata.name}')
kubectl -n secure-web exec "$pod" -- touch /tmp/not-ready
kubectl -n secure-web get pods --watch
kubectl -n secure-web exec "$pod" -- rm /tmp/not-ready
```

The Pod should remain running but change between Ready and NotReady.
