#!/bin/bash

set -e

VERSION="v3.14.1"

usage() { echo "Usage: $0 -a <arm|aarch64> [-v]" 1>&2; exit 1; }

while getopts ":a:v" opt; do
	case ${opt} in
		a)
			arch=${OPTARG}
			if  [ "$arch" == "arm" ]; then
				export GOARCH=arm
			elif [ "$arch" == "aarch64" ]; then
				export GOARCH=arm64
			else
				usage
			fi
			;;
		v)
			set -x
			;;
		*) usage
		;;
	esac
done
[ -z "$arch" ] && usage

base="$PWD"
workdir="$base/workdir-$arch"

build_resource_type() {
	name=$1

	mkdir -p "$workdir/resources"

	[ -d "$name-resource" ] || git clone "https://github.com/concourse/$name-resource"

	pushd "$name-resource"
		git reset --hard
		git clean -ffxd

		for patch in "$base/patches/$arch/$name-resource/"*; do
			[[ -e $patch ]] || break
			git apply < "$patch"
		done

		cp "$base/qemu-$arch-static-3.0.0" .

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
		for patch in "$base/patches/$arch/baggageclaim/"*; do
			[[ -e $patch ]] || break
			git apply < "$patch"
		done
	popd

	# get garden-runc
	garden_tag="v1.16.2"
	[ -d "garden-runc-release" ] || git clone --branch "$garden_tag" --recursive 'https://github.com/cloudfoundry/garden-runc-release'
	find garden-runc-release -path '*/vendor/golang.org/x/net/trace' -print0 | xargs -0 --no-run-if-empty -n1 rm -r
	pushd ./garden-runc-release/src/code.cloudfoundry.org/guardian
		git reset --hard
		for patch in "$base/patches/$arch/guardian/"*; do
			[[ -e $patch ]] || break
			git apply < "$patch"
		done
	popd
	pushd ./garden-runc-release/src/code.cloudfoundry.org/idmapper
		git reset --hard
		for patch in "$base/patches/$arch/idmapper/"*; do
			[[ -e $patch ]] || break
			git apply < "$patch"
		done
	popd

	# get final-version
	mkdir -p final-version
	echo -n "$VERSION" > final-version/version

	# build fly-rc
	mkdir linux-binary
	./concourse/ci/scripts/fly-build
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
		cp "$base/qemu-$arch-static-3.0.0" .
		git reset --hard
		for patch in "$base/patches/$arch/concourse-bin/"*; do
			[[ -e $patch ]] || break
			git apply < "$patch"
		done
		docker build -t concourse-bin .
	popd

	mkdir -p binary
	docker run \
		-v "$PWD:$PWD" \
		-w "$PWD" \
		--rm \
		--entrypoint="qemu-$arch-static" \
		-e QEMU_EXECVE=1 \
		concourse-bin /bin/bash -c 'rm -rf cli-artifacts; ./concourse/src/github.com/concourse/bin/ci/build-linux'
	rm -rf "$base/output"
	mv binary "$base/output"
popd
