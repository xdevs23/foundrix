# A build of a Rust package with its vendored dependencies that runs one
# cargo command, with `tool` at hand, in place of building, testing and
# installing.
package: name: tool: command:
package.overrideAttrs (previous: {
  pname = "${previous.pname}-${name}";
  nativeBuildInputs = previous.nativeBuildInputs ++ [ tool ];
  buildPhase = ''
    runHook preBuild
    ${command}
    runHook postBuild
  '';
  doCheck = false;
  installPhase = "touch $out";
})
