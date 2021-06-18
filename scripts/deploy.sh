#!/bin/bash

set -euo pipefail
set -x

BUILDPACK_ID=org.cloudfoundry.buildpacks.legacy
BUILDPACK_IMAGE=eirini/legacy-buildpack

patch-cluster-store() {
  local patch_spec
  current_buildpack=$(kubectl get clusterstore tinypaas-cluster-store -o jsonpath='{.spec.sources[-1:].image}')
  if [[ "$current_buildpack" =~ "$BUILDPACK_IMAGE" ]]; then
    sources_len=$(kubectl get clusterstore tinypaas-cluster-store -o json | jq '.spec.sources | length')
    buildpack_index=$((sources_len - 1))
    patch_spec=$(printf '[{"op":"remove","path":"/spec/sources/%d"}]' "$buildpack_index")
    kubectl patch clusterstore tinypaas-cluster-store --type "json" -p "$patch_spec"
  fi
  patch_spec=$(printf '[{"op":"add","path":"/spec/sources/-","value":{image: "%s@%s"}}]' "$BUILDPACK_IMAGE" "$buildpack_image_sha")
  kubectl patch clusterstore tinypaas-cluster-store --type "json" -p "$patch_spec"
}

publish-buildpack() {
  pack package-buildpack "$BUILDPACK_IMAGE" --config ./package.toml
  buildpack_image_sha=$(docker push "$BUILDPACK_IMAGE" | grep "latest: digest" | awk '{ print $3 }')
}

main() {
  local buildpack_image_sha
  publish-buildpack
  patch-cluster-store "$buildpack_image_sha"
}

main
