#!/bin/bash

set -exuo pipefail

unset host_alias
unset build_alias

export GHC_BUILD=$(echo $BUILD | sed "s/conda/unknown/g")
export GHC_HOST=$(echo $HOST | sed "s/conda/unknown/g")

if [[ "${target_platform}" == linux-* ]]; then
  # Make sure libraries for build are found without LDFLAGS
  cp $BUILD_PREFIX/lib/libgmp.so $BUILD_PREFIX/$BUILD/sysroot/usr/lib/
  cp $BUILD_PREFIX/lib/libncurses.so $BUILD_PREFIX/$BUILD/sysroot/usr/lib/
  cp $BUILD_PREFIX/lib/libtinfo.so $BUILD_PREFIX/$BUILD/sysroot/usr/lib/

  # Make sure libraries for host are found without LDFLAGS
  cp $PREFIX/lib/libgmp.so $BUILD_PREFIX/$HOST/sysroot/usr/lib/
  cp $PREFIX/lib/libncurses.so $BUILD_PREFIX/$HOST/sysroot/usr/lib/
  cp $PREFIX/lib/libtinfo.so $BUILD_PREFIX/$HOST/sysroot/usr/lib/

  # workaround some bugs in autoconf scripts
  cp $(which $AR) $BUILD_PREFIX/bin/$GHC_HOST-ar
  cp $(which $GCC) $BUILD_PREFIX/bin/$GHC_HOST-gcc
fi

pushd binary
  cp $BUILD_PREFIX/share/gnuconfig/config.* .
  # stage0 compiler: --build=$GHC_BUILD --host=$GHC_BUILD --target=$GHC_BUILD
  (
    unset CFLAGS
    LDFLAGS=${LDFLAGS//$PREFIX/$BUILD_PREFIX}
    CC=${CC_FOR_BUILD:-$CC}
    AR=($CC -print-prog-name=ar)
    NM=($CC -print-prog-name=nm)
    if [[ "${build_platform}" == linux-* ]]; then
      CPP=$BUILD-cpp
    fi
    LD=$BUILD-ld OBJDUMP=$BUILD-objdump RANLIB=$BUILD-ranlib STRIP=$BUILD-strip ./configure --prefix=$BUILD_PREFIX --with-gmp-includes=$BUILD_PREFIX/include --with-gmp-libraries=$BUILD_PREFIX/lib --build=$GHC_BUILD --host=$GHC_BUILD --target=$GHC_BUILD || (cat config.log; exit 1)
    make install -j${CPU_COUNT}
  )
popd

pushd source
  # stage1 compiler: --build=$GHC_BUILD --host=$GHC_BUILD --target=$GHC_HOST
  # stage2 compiler: --build=$GHC_BUILD --host=$GHC_HOST --target=$GHC_HOST
  if [[ "${target_platform}" == linux-* ]]; then
    export CC=$GCC
  fi
  cp $BUILD_PREFIX/share/gnuconfig/config.* .
  #./configure --prefix=$PREFIX --with-gmp-includes=$PREFIX/include --with-gmp-libraries=$PREFIX/lib --build=$GHC_BUILD --host=$GHC_BUILD --target=$GHC_HOST
  #./configure --prefix=$PREFIX --with-gmp-includes=$PREFIX/include --with-gmp-libraries=$PREFIX/lib --build=$GHC_BUILD --host=$GHC_HOST --target=$GHC_HOST
  ./configure --prefix=$PREFIX --with-gmp-includes=$PREFIX/include --with-gmp-libraries=$PREFIX/lib --with-ffi-includes=$PREFIX/include --with-ffi-libraries=$PREFIX/lib --target=$GHC_HOST
  make HADDOCK_DOCS=NO BUILD_SPHINX_HTML=NO BUILD_SPHINX_PDF=NO -j${CPU_COUNT}
  make HADDOCK_DOCS=NO BUILD_SPHINX_HTML=NO BUILD_SPHINX_PDF=NO install -j${CPU_COUNT}
  # Delete profile-enabled static libraries, other distributions don't seem to ship them either and they are very heavy.
  find $PREFIX -name '*_p.a' -delete
popd

#echo "main = putStr \"smalltest\"" > Main.hs
#ghc -v -O0 -threaded -L$PREFIX/lib -fasm -o smalltest Main.hs
#./smalltest
ghc-pkg recache
