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
    imageDigest = "sha256:c93ea0e057db350dbd20c6b58f7be53f79454c916f6226692c07ff2c215c1615";
    hash = "sha256-BrUmP2HTDkYsG0tbxgfEIFG/qSfBVqGTs9SxYkolo2k=";
    finalImageName = "supabase/studio";
    finalImageTag = "2026.07.07-sha-a6a04f2";
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
    imageDigest = "sha256:54000f24847d01a2c2302e0041cf0618b875c57fb48507d743cfa9aaa50bf43c";
    hash = "sha256-hk97XMB8aq4K2Cwpg3G0hzwRV1nghrESdWwtF1qxWPA=";
    finalImageName = "postgrest/postgrest";
    finalImageTag = "v14.12";
  };

  realtime = pullImage {
    imageName = "supabase/realtime";
    imageDigest = "sha256:aa1c92c0cf326007563641730ec9da9c60478caa6853887775365fa2c097a471";
    hash = "sha256-9M05h6YGYP4pexaiZ3mW8tybaC2AEFqeKMS+ixjaRtY=";
    finalImageName = "supabase/realtime";
    finalImageTag = "v2.102.3";
  };

  storage = pullImage {
    imageName = "supabase/storage-api";
    imageDigest = "sha256:c8eb9858eafec891a97c27125470aaad54703c3f4eb4d55ca7f1bf6c6411febf";
    hash = "sha256-on+NwynWVKUSGfw6aw0NTmYivrtqcfinPElgyzQ6C8s=";
    finalImageName = "supabase/storage-api";
    finalImageTag = "v1.60.4";
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
    imageDigest = "sha256:31c2f05b13b11069660fdfae2f6cfd37b509748d2710aca121cfee8b16cb8b07";
    hash = "sha256-S4ltdTXwS4nj3xnJdP/CERtzZf0Z3PAl5fxQIUta5XQ=";
    finalImageName = "supabase/supavisor";
    finalImageTag = "2.9.5";
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
