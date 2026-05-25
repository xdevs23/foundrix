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
    imageDigest = "sha256:c18b922ab1afdc4f25600f5c5bba701c302823013df5388927205a472ea95a10";
    hash = "sha256-6V81llIZvuqV7euM0ugzVwH9cuKkhb9nyccxTAGzUlE=";
    finalImageName = "supabase/studio";
    finalImageTag = "2026.05.25-sha-65c570e";
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
    imageDigest = "sha256:385184459f57569c54c25209f51f3b2be99ddd7c4ce9e3555b5d3eea8447b7cf";
    hash = "sha256-6cGjhpumJIX3HpMOVC87ihLIOeP+ibQ65tDjM4R/wVU=";
    finalImageName = "supabase/gotrue";
    finalImageTag = "v2.189.0";
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
    imageDigest = "sha256:11d32f9d8a31b00e848de7eccf992cc3ebbb5a17ebd55429d4cf37b4b252491f";
    hash = "sha256-Yn+6p/PPVFFBL74GEIWGST1SEYJHEHEfjk3HCAYEYZw=";
    finalImageName = "supabase/realtime";
    finalImageTag = "v2.98.1";
  };

  storage = pullImage {
    imageName = "supabase/storage-api";
    imageDigest = "sha256:dadc9367b30bcad218ffe4a2cab99b61389aa84e7b930f180d12815572dae5c1";
    hash = "sha256-Nj7CXkBYmKXOt7JGDu15BD9wnJ/DWpo83sb9n6KT+jU=";
    finalImageName = "supabase/storage-api";
    finalImageTag = "v1.58.27";
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
    imageDigest = "sha256:a84cc713585eea7b401e4a2561ec4a1e48c87083d1c7ecb4502f204bb4391300";
    hash = "sha256-d454M4jmHz9RjUjjp3FpQCdx+ZVDcjQh/U/1nGLNWsM=";
    finalImageName = "supabase/postgres-meta";
    finalImageTag = "v0.96.6";
  };

  functions = pullImage {
    imageName = "supabase/edge-runtime";
    imageDigest = "sha256:2781daf92394db91f7e94129cc3d04ec474ad16a8fe64b3fbeef6e7d557ab120";
    hash = "sha256-wM8m7oVsRzXTsi/lyxaLuUqxOMj8Xr5ihxYnj4rszhg=";
    finalImageName = "supabase/edge-runtime";
    finalImageTag = "v1.74.0";
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
      imageDigest = "sha256:ae8582f7e09ee1c039a1ac77e16169d6ce73f8518e89c4ddd2844bbddd4d4a7c";
      hash = "sha256-ICx/uiTEhDhOWMwOa41kbjKG5G+0DkwWfZB2R6lQZ5U=";
      finalImageName = "supabase/postgres";
      finalImageTag = "17.6.1.129";
    }).overrideAttrs
      {
        __structuredAttrs = true;
        unsafeDiscardReferences.out = true;
      };
}
