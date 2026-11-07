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
    imageDigest = "sha256:727a7f37b15f4c76c44e0d765e6be231d8d71c67f2933b2df8c6cbcc9b04c5d0";
    hash = "sha256-QKbHnln7UAFY/0aPjpY1hOB0FNOxJwBn5Bu7lfys0VE=";
    finalImageName = "supabase/studio";
    finalImageTag = "2026.11.02-sha-a05e7ec";
  };

  envoy = pullImage {
    imageName = "envoyproxy/envoy";
    imageDigest = "sha256:1fde8efee875e4e4f6a39a90fe49d9338e1caacce5762034ef9fb4bbb9ad6aed";
    hash = "sha256-75kg8CeORO2pgoh+S92HQAqTkAKL4KLuWuZd6W/lrFg=";
    finalImageName = "envoyproxy/envoy";
    finalImageTag = "v1.39.6";
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
    imageDigest = "sha256:25cf375b9b7cb71d90cdf6e04a1a30996e39a8df866ebd0525bba1d959edc8d6";
    hash = "sha256-10fzp2HyHtLKOmPZtq9pkg/oIy57+q1seZvGdUMWmIw=";
    finalImageName = "supabase/realtime";
    finalImageTag = "v2.148.3";
  };

  storage = pullImage {
    imageName = "supabase/storage-api";
    imageDigest = "sha256:8526956cb462e9f7d392e9848ec77133b2769982ed614e9753cc687e8e4339a6";
    hash = "sha256-cmJh6oof/rZOEY/9M2o2sMppyhju+UyEAQKTD9XtKRw=";
    finalImageName = "supabase/storage-api";
    finalImageTag = "v1.89.12";
  };

  imgproxy = pullImage {
    imageName = "darthsim/imgproxy";
    imageDigest = "sha256:69ae09dbc3349944564cb2f66cf35f80a4a9a78fda73d06061a337849520ab1f";
    hash = "sha256-BjjUOTzc/HIuMWBjvxOh6SCwk3DtD4n8Sj6FbSnGeBg=";
    finalImageName = "darthsim/imgproxy";
    finalImageTag = "v4.0.21";
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
    imageDigest = "sha256:6b850a2ccf0bf50ecac9accff8098095cd191c389c2a53c59b857aa0f53a8343";
    hash = "sha256-u1uKwDW5mj6HHjUIkVL+/j2xWlV08EmquAJk7G8lymM=";
    finalImageName = "supabase/edge-runtime";
    finalImageTag = "v1.77.9";
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
