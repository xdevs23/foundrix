{
  boot.kernel.sysctl = {
    "kernel.yama.ptrace_scope" = 2;
    "kernel.unprivileged_bpf_disabled" = 1;
    "kernel.ftrace_enabled" = false;
    "kernel.randomize_va_space" = 2;
    "vm.unprivileged_userfaultfd" = 0;
  };
}
