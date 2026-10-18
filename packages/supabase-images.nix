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
    imageDigest = "sha256:948770ec467f00e6ae34c35018ef7cb23d7b30eb806b42c2cc0d7bcfdcf8a7a8";
    hash = "sha256-bA+YdlZmFG/KXYdIHx93xTLdvm1NPPV0BbOAmrUeZrc=";
    finalImageName = "supabase/studio";
    finalImageTag = "2026.10.12-sha-3699278";
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
    imageDigest = "sha256:1736a63078f5922b198c4cbe50f80ab9a2d3b54fe8b7b6cfb2e9dc5dbbc12c6b";
    hash = "sha256-lB1nkhLoqkt73NKGOnRaHi7tIWpX4K/0ppbUb8LPVDI=";
    finalImageName = "supabase/gotrue";
    finalImageTag = "v2.197.0";
  };

  rest = pullImage {
    imageName = "postgrest/postgrest";
    imageDigest = "sha256:c7cd7e265a85b05248abf53f4473fcec7e327c282d0bd0cf60f1551996d09fcf";
    hash = "sha256-4812EeB0eBT2PIR4S4+/uZ4e4HKzI9RzTDSB3xhBn+Q=";
    finalImageName = "postgrest/postgrest";
    finalImageTag = "v14.18";
  };

  realtime = pullImage {
    imageName = "supabase/realtime";
    imageDigest = "sha256:768b559241dd234c4e8852c5c0f504e598b80f1df2ad4dd78d5486fbed2f17a2";
    hash = "sha256-tQkfNIo1D7vOIed92B3c6GTJHrCb1hq03s/reh+sYiQ=";
    finalImageName = "supabase/realtime";
    finalImageTag = "v2.143.3";
  };

  storage = pullImage {
    imageName = "supabase/storage-api";
    imageDigest = "sha256:98ffec5d0678803783c30e404c27f4ec65e97efbe014088f2a86b4b8b54b9f54";
    hash = "sha256-OM9nUQz4YI4TQhO4iVeQ0Q8D+Tk3gKQy9vDrfA4CpxE=";
    finalImageName = "supabase/storage-api";
    finalImageTag = "v1.81.0";
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
    imageDigest = "sha256:145325b7e39f8ef4931d6e8cfd3f6f4d655de09d72a2ccc96d9513542c2202bd";
    hash = "sha256-b+rm/c9XS4JI4LvsPataeZI1+Q24LuZTwTNNcB8hAwA=";
    finalImageName = "supabase/postgres-meta";
    finalImageTag = "v0.100.0";
  };

  functions = pullImage {
    imageName = "supabase/edge-runtime";
    imageDigest = "sha256:ad45164b7548bf5820ed7be714789c17ac2865edce79a09cfb4c3756c3d365a8";
    hash = "sha256-hz2qcsWYengLJPw7SLaM/RCkoEIs3UW/ivzmpuxMiuc=";
    finalImageName = "supabase/edge-runtime";
    finalImageTag = "v1.77.4";
  };

  supavisor = pullImage {
    imageName = "supabase/supavisor";
    imageDigest = "sha256:07f1a6098ffc04b80263bca4eb5c3e7bd2e03dfd1fc465aa108d7329000a1a4e";
    hash = "sha256-hUwheRhSH5PgTmEiUGBMSJnxn3XVrFUWHMCq+Y0PKuw=";
    finalImageName = "supabase/supavisor";
    finalImageTag = "2.9.13";
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
