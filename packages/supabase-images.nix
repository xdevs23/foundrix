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
    imageDigest = "sha256:94a2a9d2906e8b4109e55159a62e241c3044709a492913ea8edd34b14973d288";
    hash = "sha256-Ili46/FVDxV9ieb9Fpd/C8TAIM3u9SIHeEFUgRgwpE4=";
    finalImageName = "supabase/studio";
    finalImageTag = "2026.09.07-sha-7996410";
  };

  envoy = pullImage {
    imageName = "envoyproxy/envoy";
    imageDigest = "sha256:57e14a549d7bd43c8d3f6d03e8cfa653e037d4b38e133acd9b54f38c524401b4";
    hash = "sha256-UtWyTcbJxMjdlVlDG6WlT6Q6dxKYwXCfB7igRUgefBk=";
    finalImageName = "envoyproxy/envoy";
    finalImageTag = "v1.39.1";
  };

  auth = pullImage {
    imageName = "supabase/gotrue";
    imageDigest = "sha256:c0c25187a6b835e65a6f6e6c6b39d090e832d40e6de5186f2c038e0411944232";
    hash = "sha256-TQSzyp/RQkaxJGyh+wb7KOm2E90pXu/d8mZnlHUkwU0=";
    finalImageName = "supabase/gotrue";
    finalImageTag = "v2.196.0";
  };

  rest = pullImage {
    imageName = "postgrest/postgrest";
    imageDigest = "sha256:c9dc201e555f5d8e37e7f39cdd4df0229774996e213bfd7de8d10ac609030f2c";
    hash = "sha256-MW3AZf77GhkOXlegcWrcmaJ1wtReq5lPazadseatSwQ=";
    finalImageName = "postgrest/postgrest";
    finalImageTag = "v14.17";
  };

  realtime = pullImage {
    imageName = "supabase/realtime";
    imageDigest = "sha256:cbcc6a7986fc28b6dcffa798b077d5fb9c69cd25500371ab49147a86d7edbb03";
    hash = "sha256-x36nPqH3xDTUW/NqHuKpiJd7pnaxQ7rnktzp4ND3/5g=";
    finalImageName = "supabase/realtime";
    finalImageTag = "v2.134.10";
  };

  storage = pullImage {
    imageName = "supabase/storage-api";
    imageDigest = "sha256:f1546fac6d1c7e345428ac904bfaa7be7cecd50a1f549fe1cf38c628a7b15c85";
    hash = "sha256-W0IJ5E+QvieRKKtlFNxTWAzOIA6A5pGUwip0vFDZ8AU=";
    finalImageName = "supabase/storage-api";
    finalImageTag = "v1.74.0";
  };

  imgproxy = pullImage {
    imageName = "darthsim/imgproxy";
    imageDigest = "sha256:73c5dda13199745b0d2d00e4149d4a589c5b2e205dbf335ca05eca8276b54712";
    hash = "sha256-a4Huqvd5dVW00BSBKyMmQE7UcZnCgJdKJF0gHjk9k5M=";
    finalImageName = "darthsim/imgproxy";
    finalImageTag = "v3.31.4";
  };

  meta = pullImage {
    imageName = "supabase/postgres-meta";
    imageDigest = "sha256:9a079ac1c94d89629262822a4bd1902d5b1be4adb464e5a0a8fd078aaed72158";
    hash = "sha256-NL9ihkj/Eo/PUXWD8qDUIJPSyNV+Ipfm6rCkFsogVuw=";
    finalImageName = "supabase/postgres-meta";
    finalImageTag = "v0.99.0";
  };

  functions = pullImage {
    imageName = "supabase/edge-runtime";
    imageDigest = "sha256:edd22bef4477b900d5c300e287ce9b18bff9b81a0291bee14ee0b7c7b71a2899";
    hash = "sha256-Ea4HfmaoQPOs6K8ZUCoTD2RSraqEQVr0fqcGPk05zN8=";
    finalImageName = "supabase/edge-runtime";
    finalImageTag = "v1.76.2";
  };

  supavisor = pullImage {
    imageName = "supabase/supavisor";
    imageDigest = "sha256:464b93a60ba8c96bc06dad7f241562d6613b2a994922307717b05f432ae415c2";
    hash = "sha256-UbNZJGyFR3St/d52EWOx1lt4nnQH5U07eKL6+ANkB40=";
    finalImageName = "supabase/supavisor";
    finalImageTag = "2.9.12";
  };

  postgres =
    (pullImage {
      imageName = "supabase/postgres";
      imageDigest = "sha256:f371b5f3f2ac0a05703f33d6e6134515fb2498cab708fb948a0aeb7481467c00";
      hash = "sha256-dncZuKZ8FYrmxa8kv/hbK+HGaYQ6qpcQ/tXViNuW14c=";
      finalImageName = "supabase/postgres";
      finalImageTag = "17.6.1.136";
    }).overrideAttrs
      {
        __structuredAttrs = true;
        unsafeDiscardReferences.out = true;
      };
}
