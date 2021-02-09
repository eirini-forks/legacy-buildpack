# Legacy Buildpack

## What is this?

This is a simple wrapper buildpack for kpack, which runs all legacy cloudfoundry buildpacks.

## How to use the buildpack

To build it and install it in a cf-for-k8s cluster run `./scripts/deploy.sh` in that repository. The script builds the buildpack, pushes the image and patches the ClusterStore on the cluster. The only manual step is to edit the Kpack Builder in the `cf-workloads-staging` namespace and replace all of the buildpacks there with our buildpack. It should look something like:

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

The buildpack is configured by two environment variables - BUILDPACK_ORDER and SKIP_DETECT. Since the `cf buildpacks` family of commands now configure kpack instead of actually putting them in the blobstore, to override the default buildpacks, you need to either set them in staging-environment-variable-group or in the app manifest. For example:

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

The default values are currently in the build script [here](https://github.com/eirini-forks/legacy-buildpack/blob/dec5649ba5442a62b0312536a2a37dc5fd788823/bin/build#L4-L5)

## How it works

The buildpack implements the [cloud native buildpack spec](https://github.com/buildpacks/spec) by supplying the `bin/build` and `bin/detect` scripts. The detect scripts always returns 0, because our buildpack contains all legacy buildpacks and detection is delegated to them.

The build script creates 2 layers - the buildcache layer and the droplet layer. The droplet layer contains the untarred droplet generated from the [buildpackapplifecycle builder](https://github.com/cloudfoundry/buildpackapplifecycle/tree/d53c18d48ba95bb923220f64d82032d62a01f02b/builder). The builder is given the buildpack order via the `BUILDPACK_ORDER` env var and wheter to skip detection with the `SKIP_DETECT` env var. The later is useful if you want to use a specific buildpack to build your app, that doesn't implement the detect script (for example the binary_buildpack).

Once the two layers are built a [.profile](https://github.com/buildpacks/spec/blob/6aa243e04c29912a79be0b9dda28a0e6b167592d/buildpack.md#app-interface) script is created which sources all the scripts in `profile.d`, created by the build step and also exports environment variables like HOME, DEPS_DIR and PATH and changes the working dir to `/workspace`. Doing this is important, since it was previously handled by the [buildpackapplifecycle launcher](https://github.com/cloudfoundry/buildpackapplifecycle/tree/d53c18d48ba95bb923220f64d82032d62a01f02b/launcher), but is not done by the CNB launcher.

Finally the start command is parsed from `staging_info.yml` and set in the [launch.toml](https://github.com/buildpacks/spec/blob/6aa243e04c29912a79be0b9dda28a0e6b167592d/buildpack.md#launchtoml-toml).
