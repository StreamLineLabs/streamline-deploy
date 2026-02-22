# Changelog

All notable changes to this project will be documented in this file.
- fix: adjust resource limits in production manifest (2026-02-22)
- fix: correct volume mount paths in docker-compose (2026-02-22)

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.0] - 2026-02-18

### Added
- Docker Compose configuration for single-node deployment
- Dockerfile with multi-stage build
- Helm chart for Kubernetes deployment
- Raw Kubernetes manifests with kustomize support
- Health check and readiness probe configurations
- CI pipeline for validating deployment artifacts
