{ pkgs, opencodeMcp }:

pkgs.runCommand "opencode-mcp-package-test" {
  nativeBuildInputs = [ pkgs.python3 pkgs.procps ];
} ''
  export OPENCODE_AUTO_SERVE=false
  export OPENCODE_BASE_URL=http://127.0.0.1:1
  export OPENCODE_TASK_STORE=$TMPDIR/tasks
  timeout 5s env OPENCODE_AUTO_SERVE=false OPENCODE_BASE_URL=http://127.0.0.1:1 ${opencodeMcp}/bin/opencode-mcp </dev/null 2>stderr || test $? -eq 124
  grep -F 'opencode-mcp v3.0.0 started' stderr
  ! grep -F 'Launching OpenCode server' stderr
  touch $out
''
