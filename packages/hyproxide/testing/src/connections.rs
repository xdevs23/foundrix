//! The connections that a program accepted on a Unix socket, as the kernel
//! lists them in `/proc/net/unix`
//! (<https://github.com/torvalds/linux/blob/v6.18/net/unix/af_unix.c>,
//! `unix_seq_show` and `unix_stream_connect`, checked on Linux 6.18 on
//! 2026-11-08). A connection accepted on a socket has the path of that
//! socket, and is listed until the program that accepted it closes it.

use std::collections::BTreeSet;
use std::fs;
use std::path::Path;

/// The flag `__SO_ACCEPTCON` of a socket that listens, in the `Flags` column.
const LISTENING: &str = "00010000";

/// The inodes of the connections open on the listening socket at `socket`.
///
/// # Panics
///
/// When `/proc/net/unix` cannot be read.
#[must_use]
pub fn open_connections_to(socket: &Path) -> BTreeSet<u64> {
    let sockets = fs::read_to_string("/proc/net/unix").unwrap();
    sockets
        .lines()
        .skip(1)
        .filter_map(|line| {
            // The columns Num, RefCount, Protocol, Flags, Type, St, Inode and
            // Path. The sockets of the tests have paths without spaces.
            let fields: Vec<&str> = line.split_whitespace().collect();
            let [_, _, _, flags, _, _, inode, path] = fields.as_slice() else {
                return None;
            };
            (*flags != LISTENING && Path::new(path) == socket).then(|| inode.parse().unwrap())
        })
        .collect()
}
