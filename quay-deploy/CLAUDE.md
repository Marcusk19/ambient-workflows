# Quay Deploy

## Execution Model

You are a state-machine executor. Your behavior is mechanical:

1. Read state from `.claude/deploy-state/<DEPLOY_ID>.json`
2. Execute the handler for the current state — do ONE thing
3. Advance to the next state via `deploy-state.sh advance`
4. If manual mode: pause and ask the user
5. Loop back to step 1

## Non-Negotiable Rules

- **NEVER stop between ticks.** The only valid exit is COMPLETE, user abort, or retry cap.
- **NEVER ask "should I continue?"** — the state machine decides, not the user.
- **NEVER skip a state.** Each state does one task. Execute it fully before advancing.
- **Always update deploy-state.sh** when recording cluster URL, operator version, QuayRegistry status, etc.
- **Always record video** when running Playwright smoke tests or feature tests.
- **Keep video rolling on bugs** — do NOT stop recording when you find unexpected behavior.

## Scripts

| Script | Purpose |
|--------|---------|
| `deploy-state.sh` | State management (init, read, advance, set) |
| `cluster-provision.sh` | Ephemeral OpenShift cluster via Gangway |
| `configure-cluster.sh` | ICSP/IDMS, pull secrets, storage, OLM, Quay |
| `remote-playwright.sh` | Remote Playwright browser on cluster |

## Environment Variables

| Variable | Purpose |
|----------|---------|
| `GANGWAY_TOKEN` | Auth token for OpenShift CI Gangway API |
| `KUBECONFIG_ENCRYPTION_KEY` | Passphrase to decrypt cluster kubeconfig |
| `KONFLUX_IMAGE_PULL_TOKEN` | Bearer token for image-rbac-proxy (Konflux pre-release image pulls) |

## Conventions

- All `oc` commands use `--kubeconfig=$KUBECONFIG_PATH` explicitly
- Manifests are generated dynamically (not static files) to support version parameterization
- The workflow detects OCP version and uses IDMS (4.14+) or ICSP (older) accordingly
- Mirror targets use `image-rbac-proxy.apps.stone-prd-rh01.pg1f.p1.openshiftapps.com` (not quay.io directly) for pulling Konflux pre-release builds
- Pull secret is generated on-the-fly from `KONFLUX_IMAGE_PULL_TOKEN` — username is arbitrary, proxy uses bearer token auth
- Playwright browser is deployed on the cluster as a pod, accessed via port-forward
- Feature testing uses `acli` for JIRA tickets or `Read` for file paths
- All artifacts (screenshots, videos) go to `/tmp/quay-validate/`
- Videos of bugs are the primary deliverable for human review
