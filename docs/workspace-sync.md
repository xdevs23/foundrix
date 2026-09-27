# Workspace sync under a full Hyprland request queue, and one lock screen at a time

hypr-workspaced stops dropping workspace switches when Hyprland's request queue is briefly full: every request it sends waits up to 5 s for room in the queue. hypridle's lock command in the foundrix Hyprland module starts no second lock screen while one runs, so lock screens no longer pile up over a long session and fill that queue.

## Requirements

**sync-in-long-sessions**: Workspaces stay in sync across the monitors in a session that has run for a long time: when the main monitor switches workspace, the other monitors switch with it, without restarting hypr-workspaced.

**fixes-approved**: The fixes are built on top of foundrix commit 8cd99d8, the main branch after the Lua migration, and only those the investigation shows to be needed and correct, among these candidates: the daemon waits for room in Hyprland's queue instead of giving up; the topbar asks for the window list once per burst; only one lock screen can run at a time.

**two-foundrix-fixes**: The unit builds exactly two fixes, both in foundrix: the daemon waits for room in Hyprland's request queue, and one lock screen runs at a time. The topbar change is not built.

**waiting-connect**: Every request hypr-workspaced sends to Hyprland's request socket connects in a way that waits in the kernel for room in the socket's queue: a blocking connect with a send timeout, run off the async runtime, after which the request and its answer go over the connected socket as today. The simpler route, the non-blocking connect used now, fails with EAGAIN whenever the queue is full and so drops the switch.

**five-second-bound**: The wait for room is bounded by 5 s, the time Hyprland itself waits for an accepted client's request. When the bound runs out, the kernel reports the same EAGAIN a connect that does not wait gets at once, so the request path turns it into its own error, a separate variant of the daemon's error type whose message says that Hyprland's request queue stayed full for the whole wait. That error reaches the same handling a failed request reaches today.

**one-request-path**: hypr-workspaced has one request path to Hyprland's request socket, used by the Lua commands and by every state query. The queries send the JSON forms of the requests the crate sends today and deserialize the answers with serde_json into the crate's data types: monitors with "monitors all" (disabled monitors included), windows with "clients", workspaces with "workspaces", the active workspace with "activeworkspace" and the cursor position with "cursorpos". The active monitor is the focused entry of the monitors answer, and an answer without a focused entry is an error, as with the crate today. The crate stays in use for the event listener and the data types only.

**dependencies**: hypr-workspaced declares socket2 and serde_json as direct dependencies at the versions its Cargo.lock already holds, so no new crate enters the build. socket2 creates the socket, sets its send timeout and then connects; the standard library's UnixStream::connect cannot set a send timeout before it waits, and raw libc calls would need unsafe code for the same three steps. serde_json deserializes the query answers, as the crate does internally.

**lock-guard**: hypridle's lock command in the foundrix Hyprland module starts the configured lock screen through util-linux's flock with --nonblock and --close on a lock file in $XDG_RUNTIME_DIR. It starts nothing while a lock screen it started still runs, and starts one again once that lock screen has exited, also after a crash. With --close the lock stays with the flock process that waits for the lock screen, so nothing the lock screen leaves running can keep it. The simpler route, the lock screen's executable alone as today, starts a new lock screen on every lock request, which takes the lock over and leaves the old one running.

**readme-current**: The hypr-workspaced read-me describes the request path as built: commands and state queries go through the daemon's own request module, which waits for room in Hyprland's queue, and the crate provides events and data types. Every part that describes the crate's query functions as the way to read state is brought in line: the architecture diagram, the dependency table (which also lists the new direct dependencies) and the examples that call the crate's query functions.

## Boundaries

**long-session-only**: The failure appears only in a session that has run for a long time; a fresh session does not show it.

**foundrix-first**: Changes to foundrix are tested with foundrix overridden to the tree under test; foundrix is published once the change is confirmed, and the nixos-desktop lock moves to it afterwards. Publishing and the lock update are not part of the unit.

**host-error**: In a session that had run for about two days, hypr-workspaced, which had run without an error since the session started, logged "Monitor sync failed: Hyprland IPC error: Resource temporarily unavailable (os error 11)" 38 times within 35 minutes, and kept logging it after each of two restarts.

**leftover-lock-screens**: In that session, ten lock screen processes had accumulated next to the topbar over the two days.

**relock-while-locked**: hypridle ran its lock command each time the session was asked to lock, also while it was already locked: one lock was followed by further lock screens 5 and 55 minutes later, all before the session was unlocked.

**lock-command-now**: The foundrix Hyprland module sets hypridle's lock command to the lock screen package's executable and sets misc:allow_session_lock_restore.

**restore-lets-new-lock-take-over**: With misc:allow_session_lock_restore, Hyprland lets a new lock client take the lock while the session is locked; without it, the new lock client is denied.

**takeover-current-setup**: On the setup before the Lua migration (Hyprland 0.55.2 with the Quickshell lock screen of that time) and with the restore option set, starting the lock screen a second time while locked leaves both lock screens running.

**takeover-migrated-setup**: The same happens on the migrated setup (Hyprland 0.56.2, Quickshell 41651d7, the migrated lock screen).

**module-lock-command-fails**: The lock command the foundrix module renders at the base commit for a consumer that keeps the default lock screen (hyprlock), run twice the way hypridle runs it in a session with the module's restore option, leaves two lock screens running.

**hypridle-runs-sh**: hypridle 0.1.7 runs its commands through /bin/sh -c.

**flock-guard-works**: Run through /bin/sh -c as flock --nonblock "$XDG_RUNTIME_DIR/lockscreen.lock" <lock screen>, a second start while the first lock screen runs exits and leaves one lock screen holding the lock.

**process-names**: The topbar and the lock screens run under the same process name.

**queue-of-ten**: Hyprland 0.56.2 queues at most 10 connections on its request socket and, after accepting one, waits up to 5 s for its request.

**crate-connects-without-waiting**: The hyprland crate's async requests connect with tokio's UnixStream::connect, which does not wait for room in the queue.

**request-module-connects-without-waiting**: hypr-workspaced's own Lua request module connects the same way.

**crate-queries-in-use**: hypr-workspaced reads monitors, workspaces, windows, the active monitor, the active workspace and the cursor position through the crate's query functions.

**crate-has-no-newer-release**: The hyprland crate has no release newer than the locked 0.4.0-beta.3.

**crate-types-deserialize**: The crate's data types derive serde's Deserialize.

**new-dependencies-locked**: socket2 and serde_json are already in hypr-workspaced's Cargo.lock, pulled in by tokio and the hyprland crate. crates.io lists newer releases; RustSec has no serde_json advisory, and its one socket2 advisory is patched from 0.3.16 on.

**waiting-connect-gets-through**: Against Hyprland 0.56.2, with bursts of 30 clients filling the queue, a connect that does not wait failed with EAGAIN in 19 of 50 rounds, and a connect that waits in the kernel with a 5 s send timeout failed in none.

**unfixed-daemon-under-load**: The hypr-workspaced of the base commit, against a headless Hyprland whose request queue was kept full by rounds of 30 window-list requests, failed 12 of 60 switch commands and logged the same error 8 times.

**leftovers-fill-the-queue**: With a focused terminal changing its title every 50 ms, eleven Quickshell clients that refresh the window list on the lock screen's caffeine events made the unfixed daemon log the same error 7 times in 60 switches; one such client made it log none.

**one-window-list-request-per-process**: Quickshell starts a new window-list request only when none is in flight in the same process.

**topbar-requests-serial**: The migrated topbar sent 50 window-list requests during a 4.7 s burst of 100 title changes and 20 during 20 workspace switches, one after another.

**refused-without-restore**: Without misc:allow_session_lock_restore, a second lock screen started while the session is locked is refused and exits at once, on both the setup before the Lua migration and the migrated one.

**crash-recovery-needs-restore**: After the running lock screen is killed, a new lock screen takes the lock over with misc:allow_session_lock_restore set; without it the new lock screen is refused and the session stays locked with no lock screen (Hyprland 0.56.2, the migrated lock screen).

**timed-out-connect-errno**: On Linux, a blocking connect to a Unix socket whose queue stays full fails with EAGAIN when its send timeout runs out, the same error a connect that does not wait gets at once.

**std-connect-unbounded**: Rust's standard UnixStream::connect creates the socket and connects it in one call, so no send timeout can be set before it waits.

**flock-passes-the-lock-on**: Without --close, util-linux flock leaves the locked file open in the command it starts and in the children that command leaves running; with --close, neither holds it.

**crate-request-names**: The crate reads monitors with the "monitors all" request, which also lists disabled monitors, and finds the active monitor as the focused entry of that answer, returning an error when none is focused; windows, workspaces, the active workspace and the cursor position come from the "clients", "workspaces", "activeworkspace" and "cursorpos" requests.

**recorded-answers**: Answers of a headless Hyprland 0.56.2 session with one terminal window titled "terminal" are recorded for each of those requests, none of them empty and none naming the host or a local path.

**scope**: The unit changes hypr-workspaced (source, tests, Cargo files and read-me) and the hypridle lock command in the foundrix Hyprland desktop module. It does not change nixos-desktop, the Quickshell configurations, misc:allow_session_lock_restore, the daemon's workspace logic, or the crate's event listener.

## Rejected alternatives

**retry-loop**: Keep the non-blocking connect and retry it in a loop with sleeps when it fails with EAGAIN.
Reason: The kernel already waits for room itself when the connect blocks with a send timeout, and wakes the connect as soon as Hyprland accepts; a retry loop polls around the refusal instead.

**crate-queries-kept**: Keep reading state through the crate's query functions.
Reason: They connect inside the crate without waiting, the crate offers no way to change that, and no newer release exists.

**pidof-guard**: Guard the lock command with a process-name check, as in hypridle's example "pidof hyprlock || hyprlock".
Reason: A Quickshell lock screen runs under the same process name as the topbar, so a name check cannot tell whether a lock screen runs.

**restore-off**: Turn off misc:allow_session_lock_restore so a second lock screen is denied.
Reason: Without the option a second lock screen is refused, but a crashed lock screen can no longer be replaced either, and the session stays locked with no lock screen to unlock it. The option is also not among the candidate fixes.

**topbar-change**: Make the topbar ask for the window list once per burst of events.
Reason: Quickshell already keeps one window-list request in flight per process, and the measured topbar sends its requests one after another; the queue filled because of the leftover lock screens, one request each.

## Acceptance criteria

1. **daemon-under-load**: Against a headless Hyprland 0.56.2 whose request queue is kept full by rounds of 30 clients that each send a window-list request and retry refused connects, the hypr-workspaced built from the tree under test answers 60 switch commands without an error and logs no error, and the load was refused at least once during the run.
2. **wait-unit-tests**: Unit tests of the request path show both sides of the bound against a local listener whose queue is full: a connect started while the queue is full completes once the listener accepts, and a connect the listener never accepts fails with the request path's own timeout error after the bound (the tests may pass a shorter bound).
3. **query-unit-tests**: Unit tests deserialize, for each state query, the answer recorded from the headless Hyprland 0.56.2 session with one terminal window into the crate's data type the daemon uses for it; the recorded answers are stored in the package as test data. A further test shows that a monitors answer without a focused entry gives an error for the active monitor.
4. **no-crate-queries**: No call to the crate's query functions (get_async, get_active_async) remains in hypr-workspaced's source, and the crate's event listener is still used.
5. **existing-checks**: The existing checks still pass on the tree under test: the hypr-workspaced build with its unit tests, the check and headless load of the configuration rendered for a fixture consumer, the zoom keys, the daemon's end-to-end commands on a headless Hyprland, and the Lua request shapes.
6. **lock-command**: With the lock command and configuration the module renders for a fixture consumer, run the way hypridle runs it in a headless session: the first run locks the session, and the lock file is held by the lock screen's parent process and not by the lock screen; a second run exits within 5 s leaving one lock screen; and after the lock screen is killed the lock command starts a new one and the session is locked.
7. **clippy-clean**: cargo clippy --all-targets -- -D warnings reports nothing for hypr-workspaced.
