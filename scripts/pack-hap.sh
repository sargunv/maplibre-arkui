#!/usr/bin/env bash
# Packs a compiled OpenHarmony module into a HAP and signs it for local development.
#
#   scripts/pack-hap.sh <resources-dir> <modules.abc> <libs-dir> <hap>
#
# <resources-dir> holds the module.json, resources, and resources.index that
# restool compiled, and <libs-dir> a directory of native libraries for each
# ABI. app_packing_tool packs them with <modules.abc> and the libraries, and
# hap-sign-tool signs the HAP with the OpenHarmony SDK's release signing material,
# for the bundle that module.json names. The signed HAP is <hap>.
#
# DevEco Studio does these steps through hvigor. Its packages are on the
# OpenHarmony npm registry, but their license is unknown: their package.json
# names a LICENSE.txt that they don't include. So this script calls the SDK's
# tools itself. It comes from MapLibre Native FFI's tools/ohos/pack-hap.
set -euo pipefail

usage="usage: scripts/pack-hap.sh <resources-dir> <modules.abc> <libs-dir> <hap>"
compiled="$(cd "${1:?$usage}" && pwd)"
# The packing tool runs in a directory of its own, so it takes absolute paths.
abc="$(cd "$(dirname "${2:?$usage}")" && pwd)/$(basename "$2")"
libs="$(cd "${3:?$usage}" && pwd)"
hap=${4:?$usage}
sdk="$(dirname "${OHOS_SDK_NATIVE:?OHOS_SDK_NATIVE must name the OpenHarmony native SDK}")"
tools="$sdk/toolchains"
signing="$tools/lib"
for tool in "$signing/app_packing_tool.jar" "$signing/hap-sign-tool.jar"; do
  if [[ ! -e "$tool" ]]; then
    echo "error: the OpenHarmony SDK has no $tool; reinstall it with mise -E ohos install --force ohos-sdk" >&2
    exit 1
  fi
done
bundle=$(jq -er .app.bundleName "$compiled/module.json")
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/pack"

# The packing tool empties its working directory when it exits, so it runs in
# a directory of its own.
(
  cd "$work/pack"
  java -jar "$signing/app_packing_tool.jar" --mode hap --force true \
    --json-path "$compiled/module.json" \
    --ets-path "$abc" \
    --lib-path "$libs" \
    --resources-path "$compiled/resources" \
    --index-path "$compiled/resources.index" \
    --out-path "$work/unsigned.hap" >/dev/null
)

# The SDK ships signing keys and an unsigned profile template but no
# application certificate. The SDK's application CA issues one for the
# release key, the template becomes this bundle's release profile, and the
# profile key signs it.
password=123456
keystore="$signing/OpenHarmony.p12"
for alias in root:"openharmony application root ca" sub:"openharmony application ca"; do
  keytool -exportcert -rfc -alias "${alias#*:}" -keystore "$keystore" \
    -storetype PKCS12 -storepass "$password" >"$work/${alias%%:*}-ca.cer"
done
sign_tool=(java -jar "$signing/hap-sign-tool.jar")
"${sign_tool[@]}" generate-app-cert -keyAlias "openharmony application release" \
  -issuer "C=CN, O=OpenHarmony, OU=OpenHarmony Team, CN=OpenHarmony Application CA" \
  -issuerKeyAlias "openharmony application ca" \
  -subject "C=CN, O=OpenHarmony, OU=MapLibre, CN=MapLibre ArkUI" \
  -signAlg SHA256withECDSA -keystoreFile "$keystore" -keystorePwd "$password" \
  -keyPwd "$password" -issuerKeyPwd "$password" -outForm certChain \
  -rootCaCertFile "$work/root-ca.cer" -subCaCertFile "$work/sub-ca.cer" \
  -outFile "$work/app.cer" >/dev/null
# A debug profile must list the device's UDID on OpenHarmony 7.0, and the
# emulator reports none, so the HAP carries a release profile, which lists no
# devices. Its distribution certificate is the leaf of the chain, which comes
# first. The template's validity has expired, so it gets a new one.
jq --arg bundle "$bundle" --rawfile chain "$work/app.cer" '
  ($chain | split("-----BEGIN CERTIFICATE-----"))[1] as $leaf
  | .["bundle-info"]["bundle-name"] = $bundle
  | .["bundle-info"]["distribution-certificate"] = ("-----BEGIN CERTIFICATE-----" + $leaf)
  | .validity = {"not-before": 1600000000, "not-after": 2500000000}' "$signing/UnsgnedReleasedProfileTemplate.json" >"$work/profile.json"
"${sign_tool[@]}" sign-profile -keyAlias "openharmony application profile release" \
  -signAlg SHA256withECDSA -mode localSign \
  -profileCertFile "$signing/OpenHarmonyProfileRelease.pem" \
  -inFile "$work/profile.json" -outFile "$work/profile.p7b" \
  -keystoreFile "$keystore" -keystorePwd "$password" -keyPwd "$password" >/dev/null
"${sign_tool[@]}" sign-app -keyAlias "openharmony application release" \
  -signAlg SHA256withECDSA -mode localSign -appCertFile "$work/app.cer" \
  -profileFile "$work/profile.p7b" -inFile "$work/unsigned.hap" \
  -outFile "$hap" \
  -keystoreFile "$keystore" -keystorePwd "$password" -keyPwd "$password" >/dev/null
