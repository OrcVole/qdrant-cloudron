# Releasing

The repeatable release runbook. The package version and the upstream Qdrant version move
independently: the package version is plain semver in `CloudronManifest.json`; the upstream version
is the `QDRANT_VERSION` build argument in the `Dockerfile`, which is the single source of truth for
the binary that ships.

## Identity (every release)

All published artifacts use the neutral OrcVole identity and nothing else:

- Repository (public): `github.com/OrcVole/qdrant-cloudron`
- Image (public): `ghcr.io/orcvole/qdrant-cloudron`
- Commit author and committer: `OrcVole <OrcVole@users.noreply.github.com>`, unsigned

Run the anonymity sweep before every push (step 9). No personal host, email, username, internal URL,
path, or token may appear in any tracked file. A private personal mirror is a convenience only; its
URL must never appear in a tracked file.

## Prerequisites

- A container builder. Rootless `podman` is enough (no Docker daemon required). `cloudron build` can
  drive podman over its socket by exporting `DOCKER_HOST=unix:///run/user/$(id -u)/podman/podman.sock`.
- `skopeo` (to read the registry digest), `curl`, `jq`, and ImageMagick (only if the icon changes).
- A GitHub Personal Access Token for OrcVole with `repo`, `write:packages`, and `read:packages`,
  kept in a gitignored and dockerignored file, deleted after the release.

## Release sequence

### 1. Bump versions

Change `QDRANT_VERSION` in the `Dockerfile`, and the pinned `@sha256` digest on the same upstream
`FROM` line (both move together), to the new upstream tag. Update `upstreamVersion` and bump
`version` in `CloudronManifest.json`. Add a `[x.y.z]` entry to `CHANGELOG.md` (the bracket form is
required by `cloudron versions add`).

### 2. Gate 1: linkage and base re-pin (mandatory)

The qdrant binary is dynamically linked. A future upstream build on a newer toolchain can require a
glibc newer than the base provides, and that fails at runtime, not at build time. The Dockerfile
runs the gate as a build step, so build and confirm:

```
podman build -t ghcr.io/orcvole/qdrant-cloudron:<ver> -f Dockerfile .
podman run --rm ghcr.io/orcvole/qdrant-cloudron:<ver> ldd /app/code/qdrant
podman run --rm ghcr.io/orcvole/qdrant-cloudron:<ver> /app/code/qdrant --version
```

No `not found` and no `GLIBC_x not found`, and the version must print. If either fails, raise the
`cloudron/base` pin to a newer digest that provides the required glibc, re-run, and only then
continue. Re-pinning the base digest is part of this gate, not optional.

### 3. Gates 2 and 4: data safety on a throwaway

On a throwaway test app: `test/upgrade.sh` (data and operator config survive `cloudron update`),
then `test/backup-restore.sh` (data, config, and the API key survive a backup then a clone into a
fresh app). For a real minor jump, also confirm the storage migration (docs/UPGRADING.md).

### 4. Push the image

```
printf '%s' "$TOKEN" | podman login ghcr.io -u OrcVole --password-stdin
podman push ghcr.io/orcvole/qdrant-cloudron:<ver>
```

### 5. Capture the registry digest (not the local one)

A local podman build reports a different manifest digest than the registry stores, so always read
the registry:

```
skopeo inspect --format '{{.Digest}}' docker://ghcr.io/orcvole/qdrant-cloudron:<ver>
```

### 6. Generate the versions entry and pin the digest

`cloudron versions add --state published` writes the new version into `CloudronVersions.json` (a
`version -> manifest-with-dockerImage` map). It enforces a stricter schema than install: a valid
`contactEmail`, a non-empty `iconUrl`, at least one `mediaLinks` entry, and a changelog in the
literal `[x.y.z]` bracket form. Then replace the recorded `dockerImage` tag with the `@sha256:`
digest in BOTH `CloudronManifest.json` (`dockerImage`) and `CloudronVersions.json`
(`versions["<ver>"].manifest.dockerImage`).

### 7. GHCR visibility

GHCR packages are private by default. The first publish needs a one-time manual flip to public
(profile, then Packages, then the package, then Package settings, then Danger Zone, then Change
visibility, then Public). There is no REST API for this. A normal version bump to the existing
package stays public.

### 8. Anonymous-pull-by-digest gate

Prove a stranger can pull the published image with no credentials, before pushing the repository:

```
podman rmi -f ghcr.io/orcvole/qdrant-cloudron@sha256:<digest>
podman logout ghcr.io
printf '{"auths":{}}' > /tmp/empty.json
podman pull --authfile /tmp/empty.json ghcr.io/orcvole/qdrant-cloudron@sha256:<digest>
```

An `unauthorized` result means the package is still private (fix step 7). Do not push the repository
until this passes.

### 9. Secret-scan and anonymity sweep (before any push)

Run `test/secret-scan.sh`. Confirm no token, key, personal host, email, internal URL, or path is in
any tracked file, and confirm it on the built image filesystem too (a gitignore does not protect the
Docker build context; only the dockerignore does).

### 10. Commit and push token-free

Commit as OrcVole, unsigned. Push with `GIT_ASKPASS` so no credential is written into git config or
the process arguments. Leave the named remote URL token-free.

### 11. Token cleanup

Delete the token file after the release and revoke the PAT if no near-term updates are planned.

### 12. The real community path

Install a throwaway from the public versions URL on a spare subdomain
(`cloudron install --versions-url <raw CloudronVersions.json URL> --location ...`), confirm the app
log shows the image pulled by its digest, run `test/sso-topology.sh`, then uninstall. This is the
only test that exercises what a stranger does.

## The gates, in one place

1. Linkage (Gate 1): the binary runs on the pinned base (`ldd` plus `--version`), including
   re-pinning the base digest if the glibc floor rose. Mandatory on every bump; the failure is
   silent at build time otherwise.
2. Update survival (Gate 2): data and operator config survive `cloudron update`.
3. Storage migration (Gate 3): for a real minor jump, the migration is exercised on a throwaway.
4. Backup and restore (Gate 4): data, config, and the API key survive a backup then a clone into a
   clean app.
5. Anonymous pull: the published digest is pullable with no credentials.
6. Anonymity and secret sweep: no personal identifier or secret in any tracked file.
