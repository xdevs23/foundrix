{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  ninja,
  onetbb,
}:
# libze_intel_gpu_raytracing.so, the library the Intel Level Zero driver opens to build ray
# tracing acceleration structures. Without it the driver answers every RTAS builder call, which
# Embree on the GPU makes, with ZE_RESULT_ERROR_DEPENDENCY_UNAVAILABLE.
stdenv.mkDerivation (finalAttrs: {
  pname = "level-zero-raytracing-support";
  version = "1.3.0";

  src = fetchFromGitHub {
    owner = "intel";
    repo = "level-zero-raytracing-support";
    tag = "v${finalAttrs.version}";
    hash = "sha256-s8fTYq7mzs13FWRQeeoSqxsCbSYpzhpK+MnZyXM2krs=";
  };

  nativeBuildInputs = [
    cmake
    ninja
  ];

  # The library links oneTBB statically, the upstream default, so it works inside a program that
  # ships its own oneTBB, such as Blender. The build takes the sources from a tbb directory in the
  # source tree in place of downloading them.
  postUnpack = ''
    cp -r --no-preserve=mode ${onetbb.src} $sourceRoot/tbb
  '';

  cmakeFlags = [
    (lib.cmakeFeature "ZE_RAYTRACING_TBB" "build_static")
    (lib.cmakeBool "TBB_STRICT" false)
    # The project still declares CMake 3.1 as its minimum, which CMake 4 no longer accepts.
    (lib.cmakeFeature "CMAKE_POLICY_VERSION_MINIMUM" "3.5")
  ];

  meta = {
    description = "Ray tracing acceleration structure builder for the Intel Level Zero GPU driver";
    homepage = "https://github.com/intel/level-zero-raytracing-support";
    license = lib.licenses.asl20;
    platforms = [ "x86_64-linux" ];
  };
})
