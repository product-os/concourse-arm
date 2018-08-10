#!/bin/bash

set -ex

VERSION="v3.14.1"

base="$PWD"
workdir="$base/workdir"

build_resource_type() {
	name=$1

	mkdir -p "$workdir/resources"

	[ -d "$name-resource" ] || git clone "https://github.com/concourse/$name-resource"

	pushd "$name-resource"
		git reset --hard
		git clean -ffxd
		git apply < "$base/patches/$name-resource/0001-build-for-arm.patch"
		cp "$base/qemu-arm-static-3.0.0" .

		docker build -t "$name-resource" .
		container_id=$(docker create "$name-resource")
		docker export "$container_id" | gzip > "$workdir/resources/$name-resource-deadbeef.tar.gz"
		docker rm "$container_id"
	popd
}

mkdir -p "$workdir"
pushd "$workdir"
	# get concourse
	[ -d "concourse" ] || git clone --branch="$VERSION" --recursive 'https://github.com/concourse/concourse'
	pushd ./concourse/src/github.com/concourse/baggageclaim
		git reset --hard
		git apply < "$base/patches/baggageclaim/0001-driver-fix-build-issues-on-32bit-platforms.patch"
	popd

	# get garden-runc
	garden_tag="v1.16.2"
	[ -d "garden-runc-release" ] || git clone --branch "$garden_tag" --recursive 'https://github.com/cloudfoundry/garden-runc-release'
	find garden-runc-release -path '*/vendor/golang.org/x/net/trace' -print0 | xargs -0 --no-run-if-empty -n1 rm -r
	pushd ./garden-runc-release/src/code.cloudfoundry.org/guardian
		git reset --hard
		git apply < "$base/patches/guardian/0001-guardiancmd-ensure-argument-is-an-int64.patch"
	popd

	# get final-version
	mkdir -p final-version
	echo -n "$VERSION" > final-version/version

	# build fly-rc
	mkdir linux-binary
	GOARCH=arm ./concourse/ci/scripts/fly-build
	rm -rf fly-rc
	mv linux-binary fly-rc

	# build resource types
	build_resource_type "docker-image"
	build_resource_type "git"
	build_resource_type "s3"
	build_resource_type "time"

	mkdir -p concourse/blobs
	rm -rf concourse/blobs/resources
	mv resources concourse/blobs

	# build concourse
	pushd ./concourse/src/github.com/concourse/bin
		cp "$base/qemu-arm-static-3.0.0" .
		git reset --hard
		git apply < "$base/patches/concourse-bin/0001-build-for-arm.patch"
		docker build -t concourse-bin .
	popd

	mkdir -p binary
	docker run \
		-v "$PWD:$PWD" \
		-w "$PWD" \
		--rm \
		--entrypoint=qemu-arm-static \
		-e QEMU_EXECVE=1 \
		concourse-bin /bin/bash ./concourse/src/github.com/concourse/bin/ci/build-linux
popd
