# Intel GPU compute

foundrix's Intel GPU module installs the Intel compute stack: Level Zero for
oneAPI and SYCL programs, and OpenCL. This document states how the Level Zero
driver is installed so that it finds the libraries it opens at run time, on both
supported NixOS releases. A program that renders on the GPU through oneAPI, such
as Blender's Cycles with Embree on the GPU for hardware ray tracing, needs all
of them.

## The Level Zero driver

A oneAPI program reaches the GPU through the Level Zero loader, which loads the
Intel Level Zero driver `libze_intel_gpu.so.1` from the system graphics driver
directory. The driver in turn opens two kinds of library with dlopen:
`libigc.so.2` and `libigdfcl.so.2` of the Intel graphics compiler, and
`libze_intel_gpu_raytracing.so`, which builds the ray tracing acceleration
structures that Embree on the GPU asks for. Three things stood in the way.

- On NixOS 26.05 the driver sits in the compute runtime's `drivers` output. The
  graphics module of NixOS links only the default output, `out`, into the system
  graphics driver directory, so the driver was missing there. On nixos-unstable
  the driver sits in `out`.
- On both releases nixpkgs builds the driver without the graphics compiler's
  library directory in its RUNPATH, so the dlopen of the compiler libraries
  fails.
- nixpkgs has no package with `libze_intel_gpu_raytracing.so` on either release.
  Without it the driver still advertises the experimental ray tracing builder
  extension, but it answers every attempt to create a builder with
  `ZE_RESULT_ERROR_DEPENDENCY_UNAVAILABLE`, and Embree reports that Level Zero
  ray tracing support is missing.

The module's default list of XPU packages, which feeds
`hardware.graphics.extraPackages`, holds an adapted compute runtime in place of
the plain one. It is a symlinkJoin of every output of the compute runtime from
the same package set as the rest of the list, so it covers both releases. In it
the driver is a copy of the original with two directories added to its RUNPATH:
the library directory of that package set's `intel-graphics-compiler`, and the
library directory of the ray tracing support library. The OpenCL driver and its
ICD file stay links to the original runtime. The system graphics driver
directory therefore holds exactly one `libze_intel_gpu.so.1`, and it finds both
the compiler and the ray tracing library.

The ray tracing support library is Intel's level-zero-raytracing-support 1.3.0,
built from source with the package set's CMake and compiler. It links oneTBB
statically, the upstream default, from the source of the package set's own
oneTBB, so it depends only on the C and C++ runtime libraries and works inside a
program that brings its own oneTBB, as Blender does.

The driver looks up two sets of entry points in the library: one for the
experimental builder extension, whose names end in `ExpImpl`, and one for the
newer builder extension, whose names end in `ExtImpl`. Embree 4.4, as the
official Blender build bundles it, uses the experimental extension, so the
driver serves it from the `ExpImpl` set. Version 1.3.0 of the library defines
both sets.

The build of the adapted runtime checks the pairing of driver and library. It
fails when the driver no longer names `libze_intel_gpu_raytracing.so`, when the
driver names no ray tracing entry point, or when the library lacks an entry
point whose name the driver carries. A newer driver that expects entry points an
older library lacks therefore stops the system build, and does not leave ray
tracing silently unavailable.

Both directories go into the driver's RUNPATH because that is where a dlopen
from the driver looks. Putting the libraries into the system graphics driver
directory would not help that dlopen, and a library path set only in one
program's launcher would leave every other Level Zero program without them. The
copy costs one file copy and a patchelf call, where changing the compute
runtime's own build would rebuild the whole runtime.

## How the module and the package expressions fit together

The adapted runtime and the ray tracing library are two package expressions
beside the Intel GPU module, each in a directory of its own whose only Nix file
is the directory's default expression. foundrix turns every other Nix file under
its module directories into a module, and exports its packages directory as
flake packages, so this placement keeps both expressions private to the module.
The runtime expression takes the compute runtime, the graphics compiler, the ray
tracing library, patchelf and binutils as arguments.

The module holds the options, picks the package set and wires the result in. It
instantiates the ray tracing library and then the adapted runtime with
`callPackage` of the selected package set. With `useUnstablePackages` set, that
is nixpkgs-unstable for the runtime, its compiler and the ray tracing library,
the same as for the other XPU packages.

## Alternatives set aside

- Fixing the Level Zero driver in the configuration of a single device was set
  aside. The fix belongs in the Intel GPU module, so every device with an Intel
  GPU gets it.
