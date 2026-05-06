#!/usr/bin/env bash

set -euo pipefail

STATE_FILE="${STATE_FILE:-versions/upstream.env}"
TMP_DIR="$(mktemp -d)"
CHANGE_DETECTED="false"
ENV_WECHAT_AMD64_URL="${WECHAT_AMD64_URL-__UNSET__}"
ENV_WECHAT_ARM64_URL="${WECHAT_ARM64_URL-__UNSET__}"

cleanup() {
  rm -rf "$TMP_DIR"
}

trap cleanup EXIT

if [[ -f "$STATE_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$STATE_FILE"
fi

if [[ "$ENV_WECHAT_AMD64_URL" != "__UNSET__" ]]; then
  WECHAT_AMD64_URL="$ENV_WECHAT_AMD64_URL"
fi

if [[ "$ENV_WECHAT_ARM64_URL" != "__UNSET__" ]]; then
  WECHAT_ARM64_URL="$ENV_WECHAT_ARM64_URL"
fi

WECHAT_AMD64_URL="${WECHAT_AMD64_URL:-https://dldir1v6.qq.com/weixin/Universal/Linux/WeChatLinux_x86_64.deb}"
WECHAT_ARM64_URL="${WECHAT_ARM64_URL:-https://dldir1v6.qq.com/weixin/Universal/Linux/WeChatLinux_arm64.deb}"

download_package() {
  local source_path="$1"
  local destination="$2"

  case "$source_path" in
    http://*|https://*)
      curl --fail --silent --show-error --location \
        --retry 3 --retry-delay 5 --retry-all-errors \
        -o "$destination" "$source_path"
      ;;
    *)
      cp "$source_path" "$destination"
      ;;
  esac
}

read_metadata() {
  local package_name="$1"
  local arch="$2"
  local source_path="$3"
  local package_path="$TMP_DIR/${package_name}-${arch}.deb"
  local version_var="${package_name}_${arch}_VERSION"
  local sha_var="${package_name}_${arch}_SHA256"
  local current_version="${!version_var:-}"
  local current_sha="${!sha_var:-}"
  local detected_version
  local detected_sha

  echo "Checking ${package_name} ${arch} from ${source_path}"
  download_package "$source_path" "$package_path"

  detected_version="$(dpkg-deb -f "$package_path" Version)"
  detected_sha="$(sha256sum "$package_path" | awk '{print $1}')"

  printf -v "$version_var" '%s' "$detected_version"
  printf -v "$sha_var" '%s' "$detected_sha"

  if [[ "$current_version" != "$detected_version" || "$current_sha" != "$detected_sha" ]]; then
    CHANGE_DETECTED="true"
  fi
}

read_metadata "WECHAT" "AMD64" "$WECHAT_AMD64_URL"
read_metadata "WECHAT" "ARM64" "$WECHAT_ARM64_URL"

if [[ "$CHANGE_DETECTED" == "true" || ! -f "$STATE_FILE" ]]; then
  WECHAT_LAST_CHECKED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
fi

NEW_STATE_FILE="$TMP_DIR/upstream.env"
cat > "$NEW_STATE_FILE" <<EOF
# Upstream package state tracked by automation.

WECHAT_AMD64_URL="$WECHAT_AMD64_URL"
WECHAT_ARM64_URL="$WECHAT_ARM64_URL"

WECHAT_AMD64_VERSION="$WECHAT_AMD64_VERSION"
WECHAT_ARM64_VERSION="$WECHAT_ARM64_VERSION"

WECHAT_AMD64_SHA256="$WECHAT_AMD64_SHA256"
WECHAT_ARM64_SHA256="$WECHAT_ARM64_SHA256"

WECHAT_LAST_CHECKED_AT="$WECHAT_LAST_CHECKED_AT"
EOF

mkdir -p "$(dirname "$STATE_FILE")"
if [[ ! -f "$STATE_FILE" ]] || ! cmp -s "$NEW_STATE_FILE" "$STATE_FILE"; then
  cp "$NEW_STATE_FILE" "$STATE_FILE"
fi

echo "Change detected: $CHANGE_DETECTED"
echo "WECHAT_AMD64_VERSION=$WECHAT_AMD64_VERSION"
echo "WECHAT_ARM64_VERSION=$WECHAT_ARM64_VERSION"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "changed=$CHANGE_DETECTED"
    echo "wechat_amd64_version=$WECHAT_AMD64_VERSION"
    echo "wechat_arm64_version=$WECHAT_ARM64_VERSION"
    echo "state_file=$STATE_FILE"
  } >> "$GITHUB_OUTPUT"
fi

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    echo "## Upstream Detection"
    echo ""
    echo "- Changed: \`$CHANGE_DETECTED\`"
    echo "- WeChat amd64: \`$WECHAT_AMD64_VERSION\`"
    echo "- WeChat arm64: \`$WECHAT_ARM64_VERSION\`"
    echo "- State file: \`$STATE_FILE\`"
  } >> "$GITHUB_STEP_SUMMARY"
fi
