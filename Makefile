SHELL := /usr/bin/env bash

.PHONY: install test run docker-build render local-test clean

install:
	python3 -m venv .venv
	. .venv/bin/activate && python -m pip install --requirement requirements-dev.txt

test:
	. .venv/bin/activate && pytest

run:
	. .venv/bin/activate && APP_VERSION=local flask --app app.main run --host 0.0.0.0 --port 8080

docker-build:
	docker build --build-arg APP_VERSION=local --build-arg VCS_REF=local --tag secure-web:local .

render:
	IMAGE=secure-web:local APP_VERSION=local COMMIT_SHA=local ./scripts/render-manifests.sh

local-test:
	./scripts/local-test.sh

clean:
	rm -rf .venv build artifacts candidate-image.tar
