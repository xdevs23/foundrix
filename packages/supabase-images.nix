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
    imageDigest = "sha256:ad0c3b995d093e1799e1e4c68913f28d147da34fc6e70e76db8ba914a2749810";
    hash = "sha256-xg2SMR+pGFRcgLwQg86IZEGVPHmPjCAzsefFHRcexb8=";
    finalImageName = "supabase/studio";
    finalImageTag = "2025.12.17-sha-43f4f7f";
  };

  kong = pullImage {
    imageName = "kong";
    imageDigest = "sha256:1b53405d8680a09d6f44494b7990bf7da2ea43f84a258c59717d4539abf09f6d";
    hash = "sha256-HfNUlY882wyVMpICl6NfWzJ59jiE12J0P4u82YyAdCw=";
    finalImageName = "kong";
    finalImageTag = "2.8.1";
  };

  auth = pullImage {
    imageName = "supabase/gotrue";
    imageDigest = "sha256:c485010238ab429edf4ac8eb70b37b41aae0a0905277a935d4a0b64bb848e393";
    hash = "sha256-fekf63zbYzNdm5DhynxXgvC4nppos7BEihKKYQIqpSI=";
    finalImageName = "supabase/gotrue";
    finalImageTag = "v2.184.0";
  };

  rest = pullImage {
    imageName = "postgrest/postgrest";
    imageDigest = "sha256:e9490aa503a5fb07d8e8c80da46e5c0c193894e583b59ed9077e74c4101ffae2";
    hash = "sha256-y5CNvqn/xcydLR+p5Dn7gzeZmu+W9gurHT+nVfyWw6g=";
    finalImageName = "postgrest/postgrest";
    finalImageTag = "v14.1";
  };

  realtime = pullImage {
    imageName = "supabase/realtime";
    imageDigest = "sha256:5dd92da9b3b1e0d78de9b5484e786fbecba12a619a27041d1023e6cedb0edb81";
    hash = "sha256-I+K0NNNOwrnvxLZgwOvOox2yKjMmIveIarky8oX1l8M=";
    finalImageName = "supabase/realtime";
    finalImageTag = "v2.68.0";
  };

  storage = pullImage {
    imageName = "supabase/storage-api";
    imageDigest = "sha256:4f0eb90b935c676914ed0609c2c7d47cddb3f336155726bb2d5542617d4afdfa";
    hash = "sha256-cOoJxzBUex3MV4waTqkiDbZJ6rYpMyZFb/YCO0aYd9I=";
    finalImageName = "supabase/storage-api";
    finalImageTag = "v1.44.2";
  };

  imgproxy = pullImage {
    imageName = "darthsim/imgproxy";
    imageDigest = "sha256:0facd355d50f3be665ebe674486f2b2e9cdaebd3f74404acd9b7fece2f661435";
    hash = "sha256-be0IiNkdIy6h80vfRjD69harRGYWI1vQd0rq/UQXWcQ=";
    finalImageName = "darthsim/imgproxy";
    finalImageTag = "v3.8.0";
  };

  meta = pullImage {
    imageName = "supabase/postgres-meta";
    imageDigest = "sha256:91e967af7172a8209c5dcea05a874973f714aa3e8e8480ad0fa6a1ce0400d0cc";
    hash = "sha256-ggha6jjIGYESjm+i5MvlSyTB1osx6q8ixb7XWq7nljU=";
    finalImageName = "supabase/postgres-meta";
    finalImageTag = "v0.95.1";
  };

  functions = pullImage {
    imageName = "supabase/edge-runtime";
    imageDigest = "sha256:29d8fbebb409bd71a68e2efdca20fadcd52af343965a718f4f157b2dff7018ab";
    hash = "sha256-nLyZr5tzMKX2YDKZmsxEmvtT5oIPr6DxRG2x89RlZh0=";
    finalImageName = "supabase/edge-runtime";
    finalImageTag = "v1.69.28";
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
