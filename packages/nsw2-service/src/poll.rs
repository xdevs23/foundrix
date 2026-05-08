//! Thin wrappers around `eventfd(2)` and `poll(2)` for bridging
//! `mpsc` channels into a pollable fd set.
//!
//! [`PollableSender`] / [`PollableReceiver`] wrap an `mpsc` channel
//! with an [`EventFd`]: the sender bumps the eventfd after every
//! `send`, and the receiver, after waking on `POLLIN`, drains the
//! channel via `try_recv` and resets the eventfd counter.

use std::io;
use std::os::fd::{AsRawFd, FromRawFd, OwnedFd, RawFd};
use std::sync::mpsc;

pub struct EventFd(OwnedFd);

impl EventFd {
    pub fn new() -> io::Result<Self> {
        let fd = unsafe { libc::eventfd(0, libc::EFD_CLOEXEC | libc::EFD_NONBLOCK) };
        if fd < 0 {
            return Err(io::Error::last_os_error());
        }
        Ok(Self(unsafe { OwnedFd::from_raw_fd(fd) }))
    }

    pub fn try_clone(&self) -> io::Result<Self> {
        let dup = unsafe { libc::dup(self.0.as_raw_fd()) };
        if dup < 0 {
            return Err(io::Error::last_os_error());
        }
        Ok(Self(unsafe { OwnedFd::from_raw_fd(dup) }))
    }

    pub fn notify(&self) -> io::Result<()> {
        let val: u64 = 1;
        let r = unsafe {
            libc::write(
                self.0.as_raw_fd(),
                &val as *const u64 as *const libc::c_void,
                8,
            )
        };
        if r < 0 {
            Err(io::Error::last_os_error())
        } else {
            Ok(())
        }
    }

    pub fn drain(&self) -> io::Result<u64> {
        let mut val: u64 = 0;
        let r = unsafe {
            libc::read(
                self.0.as_raw_fd(),
                &mut val as *mut u64 as *mut libc::c_void,
                8,
            )
        };
        if r < 0 {
            Err(io::Error::last_os_error())
        } else {
            Ok(val)
        }
    }

    pub fn raw_fd(&self) -> RawFd {
        self.0.as_raw_fd()
    }
}

pub struct PollableSender<T> {
    tx: mpsc::Sender<T>,
    efd: EventFd,
}

impl<T> PollableSender<T> {
    pub fn send(&self, value: T) -> Result<(), mpsc::SendError<T>> {
        self.tx.send(value)?;
        let _ = self.efd.notify();
        Ok(())
    }
}

pub struct PollableReceiver<T> {
    rx: mpsc::Receiver<T>,
    efd: EventFd,
}

impl<T> PollableReceiver<T> {
    pub fn raw_fd(&self) -> RawFd {
        self.efd.raw_fd()
    }

    /// Drain all pending items from the channel, calling `f` for each.
    /// Returns `true` if the sender side has been dropped (channel
    /// disconnected) and no more items will ever arrive.
    pub fn drain<F>(&self, mut f: F) -> bool
    where
        F: FnMut(T),
    {
        let mut disconnected = false;
        loop {
            match self.rx.try_recv() {
                Ok(item) => f(item),
                Err(mpsc::TryRecvError::Empty) => break,
                Err(mpsc::TryRecvError::Disconnected) => {
                    disconnected = true;
                    break;
                }
            }
        }
        let _ = self.efd.drain();
        disconnected
    }
}

pub fn pollable_channel<T>() -> io::Result<(PollableSender<T>, PollableReceiver<T>)> {
    let (tx, rx) = mpsc::channel();
    let efd = EventFd::new()?;
    let dup_fd = unsafe { libc::dup(efd.raw_fd()) };
    if dup_fd < 0 {
        return Err(io::Error::last_os_error());
    }
    let efd_dup = EventFd(unsafe { OwnedFd::from_raw_fd(dup_fd) });

    Ok((
        PollableSender { tx, efd: efd_dup },
        PollableReceiver { rx, efd },
    ))
}

pub struct PollSet<'a> {
    fds: &'a mut [libc::pollfd],
}

impl<'a> PollSet<'a> {
    pub fn new(fds: &'a mut [libc::pollfd]) -> Self {
        Self { fds }
    }

    pub fn wait(&mut self) -> io::Result<()> {
        let r = unsafe { libc::poll(self.fds.as_mut_ptr(), self.fds.len() as libc::nfds_t, -1) };
        if r < 0 {
            let err = io::Error::last_os_error();
            if err.kind() == io::ErrorKind::Interrupted {
                return Ok(());
            }
            return Err(err);
        }
        Ok(())
    }

    pub fn readable(&self, idx: usize) -> bool {
        self.fds[idx].revents & libc::POLLIN != 0
    }

    pub fn has_error(&self, idx: usize) -> bool {
        self.fds[idx].revents & (libc::POLLERR | libc::POLLHUP | libc::POLLNVAL) != 0
    }
}

pub fn pollfd(fd: RawFd) -> libc::pollfd {
    libc::pollfd {
        fd,
        events: libc::POLLIN,
        revents: 0,
    }
}
