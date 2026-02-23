# Maintaining this module

This doc is for the person or team that **maintains** the terraform-aws-confluent-platform repo and releases it for others to provision Kafka clusters.

## What you maintain

- **Terraform modules** – `modules/network`, `modules/eks`, `modules/cfk` (provider versions, EKS/addon wiring, CFK operator install).
- **Example environment** – `envs/dev` (reference for variables and provider config).
- **Reference manifests** – `manifests/base/` (Zookeeper + Kafka) and `manifests/overlays/dev` and `overlays/staging` (Kustomize; teams add overlays or patch for their env).
- **Docs** – README (consumer flow), MAINTAINING.md (this file), and `manifests/README.md`.

## What consumers do

- Use an existing env (e.g. `envs/dev`) or add a new one under `envs/`.
- Set variables via tfvars; use a Kustomize overlay (e.g. `manifests/overlays/dev`) or add a new overlay and patch replicas, StorageClass, domain, etc.
- Pin to a **git tag** so they get a fixed version until they choose to upgrade.

## Versioning and releases

- Use **semantic version tags** (e.g. `v1.0.0`, `v1.1.0`).
- **Breaking changes** (e.g. module renames, required variable changes, manifest schema changes) → bump major.
- **New features or new optional behavior** → bump minor.
- **Bug fixes and doc updates** → bump patch.

## Release process (suggested)

1. Update version references in docs if you keep a single “current version” line (optional).
2. Commit and push, then create a tag:
   ```bash
   git tag -a v1.0.0 -m "Release v1.0.0"
   git push origin v1.0.0
   ```
3. Tell consumers to pin to that tag (e.g. `git checkout v1.0.0` or clone with `--branch v1.0.0`).

If this repo is consumed as a **Terraform module** from another repo (e.g. `source = "git::https://...?ref=v1.0.0"`), consumers pin via the `ref` parameter.

## Changelog

Keep a short **CHANGELOG.md** in the repo root (or in MAINTAINING.md) listing:

- Version and date.
- Added/changed/fixed items that affect consumers (e.g. “Added internal NLB for Kafka”, “Bumped CFK Helm default to 2.x”, “New variable `ebs_csi_addon_version`”).

## Upgrading dependencies

- **EKS module** – Bump `modules/eks` version and run `terraform plan` in `envs/dev`; fix any breaking changes and update docs.
- **CFK Helm** – Update default or example in `envs/dev` / README; document any CR or image changes in manifests.
- **Confluent images** – When you bump Zookeeper/Kafka image versions in `manifests/base/`, note it in the changelog and call out any required CR or config changes.

## Accepting changes from the team

- Prefer **env-specific config** (new envs, new tfvars, or new Kustomize overlays/patches) over changing the shared modules or `manifests/base/` in ways that break existing consumers.
- For shared behavior (e.g. new variable, new addon), change the relevant module or example env and document it; bump version and changelog as above.
