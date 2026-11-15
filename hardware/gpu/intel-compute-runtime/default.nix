{
  srcOnly,
  symlinkJoin,
  binutils,
  patchelf,
  intel-compute-runtime,
  intel-graphics-compiler,
  level-zero-raytracing-support,
}:
# The compute runtime with its Level Zero driver, libze_intel_gpu.so.1, next to the OpenCL driver.
# The Level Zero driver opens libraries with dlopen, which searches the driver's RUNPATH:
# libigc.so.2 and libigdfcl.so.2 of the graphics compiler, and libze_intel_gpu_raytracing.so,
# which builds the ray tracing acceleration structures. nixpkgs builds the driver with neither
# directory there. This package holds a copy of the driver with both directories added. On NixOS
# 26.05 the driver sits in the runtime's drivers output, which the graphics driver directory does
# not link, and on nixos-unstable in out; joining every output covers both.
symlinkJoin {
  name = "${intel-compute-runtime.name}-with-libraries";
  paths = map (output: intel-compute-runtime.${output}) intel-compute-runtime.outputs;
  nativeBuildInputs = [
    binutils
    patchelf
  ];
  postBuild = ''
    driver=$(readlink -f $out/lib/libze_intel_gpu.so.1)
    name=$(basename "$driver")
    rm $out/lib/$name
    cp "$driver" $out/lib/$name
    chmod u+w $out/lib/$name
    patchelf --add-rpath ${intel-graphics-compiler}/lib:${level-zero-raytracing-support}/lib $out/lib/$name
    ln -sfn $name $out/lib/libze_intel_gpu.so.1

    # The driver treats ray tracing as unavailable when it cannot open the library by this name or
    # cannot find one of the entry points it looks up there, so either fails the build. Both are
    # read from the patched source code of the driver, because the compiler may split string
    # literals in the binary.
    library=libze_intel_gpu_raytracing.so
    raytracing=${level-zero-raytracing-support}/lib/$library
    sources=${srcOnly intel-compute-runtime}/level_zero/core/source/rtas
    opened=$(grep -rhoE 'rtasLibraryName = "[^"]*"' $sources/linux | cut -d '"' -f 2) || [ $? -eq 1 ]
    if [ -z "$opened" ]; then
      echo "the Level Zero driver $name no longer defines rtasLibraryName in $sources/linux" >&2
      exit 1
    fi
    if [ "$opened" != "$library" ]; then
      echo "the Level Zero driver $name opens $opened instead of $library" >&2
      exit 1
    fi
    wanted=$(grep -rhoE '"ze[A-Za-z]*RTAS[A-Za-z]*Ex[pt]Impl"' $sources) || [ $? -eq 1 ]
    wanted=$(tr -d '"' <<< "$wanted" | sort -u)
    if [ -z "$wanted" ]; then
      echo "the Level Zero driver $name names no ray tracing entry points" >&2
      exit 1
    fi
    provided=$(nm -D --defined-only "$raytracing" | cut -d ' ' -f 3)
    for symbol in $wanted; do
      if ! grep -qx "$symbol" <<< "$provided"; then
        echo "$raytracing lacks $symbol, which the Level Zero driver $name looks up in it" >&2
        exit 1
      fi
    done
  '';
}
