## Concourse bootstrap build for arm and aarch64

See [concourse/concourse#1379](https://github.com/concourse/concourse/issues/1379) for more information

### Building

Make sure you have a working Go and Docker installation on a linux x86\_64
machine. The build process has been tested on linux 4.17.12 running Go 1.10.3
and Docker 18.05.0-ce.

To make an arm build run:

```sh
./build.sh -a arm
```

To make an aarch64 build run:

```sh
./build.sh -a aarch64
```

You can also add the `-v` flag if you want debug output.

### Missing features

The following resource types need to be added in the build process:

* bosh-deployment
* bosh-io-release
* bosh-io-stemcell
* cf
* github-release
* hg
* pool
* semver
* tracker
