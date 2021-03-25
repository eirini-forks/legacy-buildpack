# Legacy Buildpack

## What is this?

This is a simple Cloud Native Buildpack wrapping the set of legacy Cloud Foundry buildpacks.
It allows kpack to use legacy Cloud Foundry buildpacks on apps that previously built and ran in Cloud Foundry for VMs, but might not yet build or run successfully with the new Paketo buildpacks.

## How to use the buildpack

To build and install it in a cf-for-k8s cluster, run `./scripts/deploy.sh` in this repository.
The script builds the buildpack, pushes the image and patches the ClusterStore on the cluster.
The only manual step is to edit the kpack Builder in the `cf-workloads-staging` namespace and replace all of the buildpacks there with this buildpack.
It should look something like:

```yaml
apiVersion: kpack.io/v1alpha1
kind: Builder
  name: cf-default-builder
  namespace: cf-workloads-staging
...
spec:
  order:
  - group:
    - id: org.cloudfoundry.buildpacks.legacy
...

```

The buildpack is configured by two environment variables - `BUILDPACK_ORDER` and `SKIP_DETECT`.
Since the `cf buildpacks` family of commands now configure kpack instead of actually putting them in the blobstore, to override the default buildpacks, you need to either set them in staging-environment-variable-group or in the app manifest.
For example:

```shell
cf set-staging-environment-variable-group '{"BUILDPACK_ORDER":"<buildpack1-url>,<buildpack2-url>,...", SKIP_DETECT: true}'
```

or using the manifest:

```yaml
---
applications:
  - name: my-app
    env:
      BUILDPACK_ORDER: "<buildpack1-url>,<buildpack2-url>,..."
      SKIP_DETECT: true
```

The default values are currently in the build script [here](https://github.com/eirini-forks/legacy-buildpack/blob/f8e40dc7073fb9cba48e36b751c28c43774b69e6/bin/build#L4-L5).
Note that this contains only the ruby, node, golang and static buildpacks used as a proof of concept.

## How it works

The buildpack implements the [cloud native buildpack spec](https://github.com/buildpacks/spec) by supplying the `bin/build` and `bin/detect` scripts.
The detect script always returns 0, because this buildpack contains all legacy buildpacks and overrides the new buildpacks.

The build script uses the legacy [buildpackapplifecycle builder](https://github.com/cloudfoundry/buildpackapplifecycle/tree/d53c18d48ba95bb923220f64d82032d62a01f02b/builder) to perform the build, exactly as in Cloud Foundry for VMs.
It translates the environment from and to the CNB structure before and after the build.
The builder is given the buildpack order via the `BUILDPACK_ORDER` env var and whether to skip detection with the `SKIP_DETECT` env var.
The later is useful if you want to use a specific buildpack to build your app, that doesn't implement the detect script (for example the binary-buildpack).

The build script uses the caching built into CNBs to provide the required cache directory to the legacy builder.
It copies the buildcache to a directory in `/tmp` prior to invoking the builder to overcome problems with hard links created by the buildpacks which might end up as cross-filesystem and erroring.
The buildcache layer is updated with the final cache state after the legacy build.

The legacy builder creates a droplet tarball which is extracted into a temporary layer, and then copied to the `/workspace` directory.
Permissions, in particular setgid bits, prevent extracting directly to `/workspace`.

The final step is to make the extracted droplet executable by the CNB launcher.
Rather than invoking the [launcher from buildpackapplifecycle](https://github.com/cloudfoundry/buildpackapplifecycle/tree/d53c18d48ba95bb923220f64d82032d62a01f02b/launcher), its functionality is reproduced in a [`.profile`](https://github.com/buildpacks/spec/blob/6aa243e04c29912a79be0b9dda28a0e6b167592d/buildpack.md#app-interface) file sourced by the CNB lifecycle.
This sources all the files that the legacy launcher would have sourced, setting PATH and all the required environment variables, and changes the working directory to `/workspace/app`.

Finally the start command is parsed from `staging_info.yml` and set in the [launch.toml](https://github.com/buildpacks/spec/blob/6aa243e04c29912a79be0b9dda28a0e6b167592d/buildpack.md#launchtoml-toml).

## Outstanding work

Reproducing the launcher's [CalcEnv](https://github.com/cloudfoundry/buildpackapplifecycle/blob/d53c18d48ba95bb923220f64d82032d62a01f02b/env/env.go#L15) in its entirety:

- Setting DATABASE_URL and VCAP\_\* env vars appropriately during launch
- Interpolating credhub secrets during launch
