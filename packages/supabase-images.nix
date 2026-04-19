# Docker images for Supabase services
# All images are prefetched by Nix for reproducibility
#
# chore: update supabase docker images
# check https://github.com/supabase/supabase/blob/master/docker/docker-compose.yml for latest tags
# for each image, prefetch with:
#   nix run nixpkgs#nix-prefetch-docker -- --image-name <name> --image-tag <tag>
{ pkgs, ... }:
let
  pullImage = pkgs.dockerTools.pullImage;
in
{
  studio = pullImage {
    imageName = "supabase/studio";
    imageDigest = "sha256:6df01717260781224d6e5fc24532511a184d43b705be39ba592b4958ccf4109d";
    hash = "sha256-0rfaiO78AubxCe8DUUyXI6ZfEOMwwyz/bk69hxUvuD0=";
    finalImageName = "supabase/studio";
    finalImageTag = "2026.04.08-sha-205cbe7";
  };

  kong = pullImage {
    imageName = "kong/kong";
    imageDigest = "sha256:6addf50e6bd8d578314cb9ce4f2d2d1e3781d2edecef59f707e00c6e05d384f5";
    hash = "sha256-MxxBOpl82TL4ZmReAJdsw3JWqh9pQPZ6RfLQ1wWFaGw=";
    finalImageName = "kong/kong";
    finalImageTag = "3.9.1";
  };

  auth = pullImage {
    imageName = "supabase/gotrue";
    imageDigest = "sha256:f2112b9289422f205df4ea15b8b550d425ae42528ea54521faa32cc7b62490de";
    hash = "sha256-t91cYLhvwDVgL3lOWZAnu5FJlcrZN47r7l1RTcmO5LQ=";
    finalImageName = "supabase/gotrue";
    finalImageTag = "v2.186.0";
  };

  rest = pullImage {
    imageName = "postgrest/postgrest";
    imageDigest = "sha256:4173b72e0be29cf15349dc827798c3e464c5f2cc7f9c1697022f9cd1874b4c36";
    hash = "sha256-r8NCu5MKkRiXnWyphw1xLrW19uB2PO0HCmvME92EevM=";
    finalImageName = "postgrest/postgrest";
    finalImageTag = "v14.8";
  };

  realtime = pullImage {
    imageName = "supabase/realtime";
    imageDigest = "sha256:ec6607368a2b41f54fb6edffbb821984522d0ba47399937aeeba75673c36a6f8";
    hash = "sha256-IFiEivCHmTw9kpKfmvI8Pw82gmsRbnfmiESkfwQTCLM=";
    finalImageName = "supabase/realtime";
    finalImageTag = "v2.76.5";
  };

  storage = pullImage {
    imageName = "supabase/storage-api";
    imageDigest = "sha256:86487b496499561225c1f79c546645421890125539a8d9e00da45dee0a834314";
    hash = "sha256-EPU8QS55Zp35T/Gsbmv7YhWgttWnW/UKXHE3H/GUssM=";
    finalImageName = "supabase/storage-api";
    finalImageTag = "v1.48.26";
  };

  imgproxy = pullImage {
    imageName = "darthsim/imgproxy";
    imageDigest = "sha256:3b709e4a0e5e8e0e959b556b7031229202b4b8e7e7d955c517ea7abed68ee34d";
    hash = "sha256-rVVdeh3V25TLwzgFUZCfEMl7II8D0WlFnWzWeFlw6UA=";
    finalImageName = "darthsim/imgproxy";
    finalImageTag = "v3.30.1";
  };

  meta = pullImage {
    imageName = "supabase/postgres-meta";
    imageDigest = "sha256:f0f98965679534a62897b6c007b1daaad5a3a81ba97a8c418d4477684e847f0e";
    hash = "sha256-eWhslH/RSXiHebCVwaZK2Y7cZBH2hYuC+MasgR6U+a0=";
    finalImageName = "supabase/postgres-meta";
    finalImageTag = "v0.96.3";
  };

  functions = pullImage {
    imageName = "supabase/edge-runtime";
    imageDigest = "sha256:2c0994891f47466d8791b714bac9a05842dec637feba050fc736e4fdedae0a43";
    hash = "sha256-LVKS4QGU0b/2zrej7JF/7kbmCvJPxmfosAZU0/tQlfc=";
    finalImageName = "supabase/edge-runtime";
    finalImageTag = "v1.71.2";
  };

  supavisor = pullImage {
    imageName = "supabase/supavisor";
    imageDigest = "sha256:466297ba00956e2d1cbd56a4362fbd5dbc9c2a47ad83e8ca9bdb877f743315ee";
    hash = "sha256-MWDURMUy5nS4gEYDLtD2kEWrt/b6XCuZ7Z2r8umb/Jo=";
    finalImageName = "supabase/supavisor";
    finalImageTag = "2.7.4";
  };

  postgres =
    (pullImage {
      imageName = "supabase/postgres";
      imageDigest = "sha256:0d16f6b3441ecf21318b0b45fce78ffb6a469dd141119ebfd4810088f417a857";
      hash = "sha256-bCybMECtInSjnDTL16iMcNmRD7z1VFQZLoq8b2a7S50=";
      finalImageName = "supabase/postgres";
      finalImageTag = "17.6.1.066";
    }).overrideAttrs
      {
        __structuredAttrs = true;
        unsafeDiscardReferences.out = true;
      };
}
