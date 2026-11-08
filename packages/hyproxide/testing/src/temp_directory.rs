use std::env;
use std::fs;
use std::io;
use std::path::{Path, PathBuf};
use std::process;
use std::sync::atomic::{AtomicU32, Ordering};

/// A new directory under the temporary directory, removed with its contents
/// when dropped.
#[derive(Debug)]
pub struct TempDirectory(PathBuf);

impl TempDirectory {
    /// # Panics
    ///
    /// When the directory cannot be created.
    #[must_use]
    pub fn create() -> Self {
        static CREATED: AtomicU32 = AtomicU32::new(0);
        loop {
            let number = CREATED.fetch_add(1, Ordering::Relaxed);
            // Short, as the sockets of a Hyprland started in it lie three
            // levels deeper, and a socket path has at most 107 bytes.
            let path = env::temp_dir().join(format!("hyproxide-{}-{number}", process::id()));
            match fs::create_dir(&path) {
                Ok(()) => return Self(path),
                // Left by an earlier run whose process had the same id.
                Err(error) if error.kind() == io::ErrorKind::AlreadyExists => {}
                Err(error) => panic!("creating {} failed: {error}", path.display()),
            }
        }
    }

    #[must_use]
    pub fn path(&self) -> &Path {
        &self.0
    }
}

impl Drop for TempDirectory {
    fn drop(&mut self) {
        let _left_to_the_system_when_removal_fails = fs::remove_dir_all(&self.0);
    }
}
