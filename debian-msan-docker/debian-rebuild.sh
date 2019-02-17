#!/usr/bin/bash

set -e

replace_gcc_with_clang() {
    # Even though we can set CC and CXX when calling dpkg-buildpackage,
    # in some cases these variables are not honoured and causing the rebuild
    # to fail (as gcc doesn't support -fsanitize=memory). The easiest way
    # is to temporary override all gcc symlinks to clang.
    GCC_BIN="$(readlink -f /usr/bin/gcc)"
    CPP_BIN="$(readlink -f /usr/bin/cpp)"
    GXX_BIN="$(readlink -f /usr/bin/g++)"

    echo "GCC: $GCC_BIN"
    echo "CPP: $CPP_BIN"
    echo "G++: $GXX_BIN"

    [[ $GCC_BIN =~ "clang" ]] || ( rm "$GCC_BIN" && ln -s /usr/bin/clang "$GCC_BIN" )
    [[ $CPP_BIN =~ "clang" ]] || ( rm "$CPP_BIN" && ln -s /usr/bin/clang "$CPP_BIN" )
    [[ $GXX_BIN =~ "clang" ]] || ( rm "$GXX_BIN" && ln -s /usr/bin/clang++ "$GXX_BIN" )
}
# Verified:
#  - util-linux (libmount1)
#  - libseccomp
#  - acl (libacl1)
#  - libcap2
PACKAGE_LIST=(util-linux libseccomp acl libcap2)

echo 'deb-src http://deb.debian.org/debian testing main' >> /etc/apt/sources.list
apt-get -y update
apt-get -y install clang

mkdir /built-packages
mkdir /rebuild
pushd /rebuild

for package in "${PACKAGE_LIST[@]}"; do
    rm -fr *
    apt-get -y build-dep $package
    apt-get source -y $package
    pushd ${package}-*
    replace_gcc_with_clang
    export DEB_CFLAGS_APPEND="-fsanitize=memory"
    export DEB_CXXFLAGS_APPEND="-fsanitize=memory"
    if [[ $package == "acl" ]]; then
        # This should be enabled only for packages which won't compile with
        # MSan otherwise, as it may break the detection process in configure
        # (like it does with crypt detection in util-linux)
        export DEB_LDFLAGS_APPEND="-z undefs"
    fi
    # Disable checks (like make check) as some test might (and actually do)
    # fail in the "default" docker environment
    export DEB_BUILD_OPTIONS=nocheck
    # Discovered during util-linux recompilation:
    # The memory sanitizer detects 'use of an uninitialized value' during the
    # scanf string alloc modifier check, thus marking is falsely as not supported.
    # This, in turn, casues libmount to be excluded from the compilation along
    # with several other dependencies. I guess a similar issue may appear in
    # other packages, so let's ignore MSan errors during compilation.
    export MSAN_OPTIONS=exit_code=0
    export CC="clang"
    export CXX="clang++"
    dpkg-buildpackage --no-sign

    popd
    mv -- *.deb /built-packages

    unset DEB_LDFLAGS_APPEND
done

popd

ls -la /built-packages
