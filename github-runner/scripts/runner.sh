#!/bin/bash
# Installs the GitHub Actions runner, registers it with GitHub and runs it as
# a service under the unprivileged "runner" user.
#
#   1. download the runner release and check its SHA-256
#   2. wait for the GitHub token in Secrets Manager (you put it there)
#   3. trade it for a 1-hour registration token, register, start the service
#
# After this the runner has its own credentials (.runner, .credentials) and
# polls GitHub for jobs over outbound HTTPS. It updates itself.
source /opt/github-runner-bootstrap/lib.sh

RUNNER_HOME=/home/runner
DIR=$RUNNER_HOME/actions-runner

# The user jobs run as. In the docker group, so jobs can build images and use
# containers (that's root-equivalent on this machine, which is why it's a
# dedicated runner server).
if ! id runner >/dev/null 2>&1; then
  useradd --create-home --home-dir "$RUNNER_HOME" --shell /bin/bash runner
fi
usermod -aG docker runner

log "Downloading the GitHub Actions runner $RUNNER_VERSION"
TARBALL=actions-runner-linux-x64-$RUNNER_VERSION.tar.gz
# The release notes list each file's SHA-256 between these markers.
EXPECTED_SHA=$(curl -fsSL --retry 5 "https://api.github.com/repos/actions/runner/releases/tags/v$RUNNER_VERSION" |
  jq -r .body | sed -n 's/.*<!-- BEGIN SHA linux-x64 -->\([0-9a-f]\{64\}\)<!-- END SHA linux-x64 -->.*/\1/p')
[[ -n $EXPECTED_SHA ]] || die "no SHA-256 for linux-x64 in the v$RUNNER_VERSION release notes"
curl -fsSL --retry 5 -o "/tmp/$TARBALL" \
  "https://github.com/actions/runner/releases/download/v$RUNNER_VERSION/$TARBALL"
echo "$EXPECTED_SHA  /tmp/$TARBALL" | sha256sum -c - || die "checksum mismatch for $TARBALL"

mkdir -p "$DIR"
tar -xzf "/tmp/$TARBALL" -C "$DIR"
rm -f "/tmp/$TARBALL"
chown -R runner:runner "$DIR"
"$DIR/bin/installdependencies.sh" >/dev/null # .NET runtime libraries (libicu...)

# Organization ("my-org") or one repository ("my-org/my-repo").
if [[ $GITHUB_SCOPE == */* ]]; then
  API="https://api.github.com/repos/$GITHUB_SCOPE/actions/runners/registration-token"
  GROUP_ARGS=()
else
  API="https://api.github.com/orgs/$GITHUB_SCOPE/actions/runners/registration-token"
  GROUP_ARGS=(--runnergroup "$RUNNER_GROUP")
fi

log "Waiting for the GitHub token in Secrets Manager ($SECRET_ARN)"
GITHUB_TOKEN=""
for _ in {1..240}; do
  if GITHUB_TOKEN=$(aws secretsmanager get-secret-value --secret-id "$SECRET_ARN" \
    --query SecretString --output text 2>/dev/null | jq -er .token 2>/dev/null); then
    break
  fi
  sleep 30
done
[[ -n $GITHUB_TOKEN ]] || die "no token in $SECRET_ARN after 2 hours; put it there, then: sudo $SCRIPT_DIR/bootstrap.sh"

log "Requesting a registration token for $GITHUB_SCOPE"
REG_TOKEN=$(curl -fsS --retry 3 -X POST \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "$API" | jq -er .token) ||
  die "GitHub refused the registration token request: check the token's permissions and github_scope ($GITHUB_SCOPE)"
unset GITHUB_TOKEN

log "Registering as $RUNNER_NAME (labels: self-hosted, linux, x64, $RUNNER_LABELS)"
cd "$DIR"
runuser -u runner -- ./config.sh --unattended \
  --url "https://github.com/$GITHUB_SCOPE" \
  --token "$REG_TOKEN" \
  --name "$RUNNER_NAME" \
  --labels "$RUNNER_LABELS" \
  --work _work \
  --replace \
  "${GROUP_ARGS[@]}"

log "Installing the runner service"
./svc.sh install runner
./svc.sh start
log "Runner $RUNNER_NAME is online"
