//! Fixtures shared by the integration tests.

use std::env;
use std::fs;
use std::io;
use std::path::{Path, PathBuf};
use std::process;
use std::sync::atomic::{AtomicU32, Ordering};

/// A new directory under the temporary directory, removed with its contents
/// when dropped.
pub struct TempDirectory(PathBuf);

impl TempDirectory {
    pub fn new() -> Self {
        static CREATED: AtomicU32 = AtomicU32::new(0);
        loop {
            let number = CREATED.fetch_add(1, Ordering::Relaxed);
            let path = env::temp_dir().join(format!("hyproxide-{}-{number}", process::id()));
            match fs::create_dir(&path) {
                Ok(()) => return Self(path),
                // Left by an earlier run whose process had the same id.
                Err(error) if error.kind() == io::ErrorKind::AlreadyExists => {}
                Err(error) => panic!("creating {} failed: {error}", path.display()),
            }
        }
    }

    pub fn path(&self) -> &Path {
        &self.0
    }
}

impl Drop for TempDirectory {
    fn drop(&mut self) {
        let _left_to_the_system_when_removal_fails = fs::remove_dir_all(&self.0);
    }
}
