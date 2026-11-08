//! Requests against a fake Hyprland: a listener on the command socket in a
//! directory made for each test, which reads a request in one read and
//! writes an answer.

mod support;

use std::future::{Future, poll_fn};
use std::io;
use std::os::fd::OwnedFd;
use std::path::{Path, PathBuf};
use std::pin::{Pin, pin};
use std::task::Poll;

use hyproxide::{Error, Instance, dispatch, query};
use socket2::{Domain, SockAddr, Socket, Type};
use tokio::io::{AsyncReadExt as _, AsyncWriteExt as _};
use tokio::net::{UnixListener, UnixStream};

use support::TempDirectory;

struct FakeHyprland {
    directory: TempDirectory,
    listener: UnixListener,
}

impl FakeHyprland {
    /// A Hyprland whose socket queues 10 connections, as Hyprland 0.57.1 does.
    fn new() -> Self {
        Self::with_queue_length(10)
    }

    /// A Hyprland whose socket queues `length` connections that wait to be
    /// accepted.
    fn with_queue_length(length: i32) -> Self {
        let directory = TempDirectory::new();
        let socket = Socket::new(Domain::UNIX, Type::STREAM, None).unwrap();
        socket
            .bind(&SockAddr::unix(socket_path(directory.path())).unwrap())
            .unwrap();
        socket.listen(length).unwrap();
        socket.set_nonblocking(true).unwrap();
        let listener = std::os::unix::net::UnixListener::from(OwnedFd::from(socket));
        Self {
            directory,
            listener: UnixListener::from_std(listener).unwrap(),
        }
    }

    fn instance(&self) -> Instance {
        Instance::at(self.directory.path())
    }

    /// Accept one connection, read its request in one read, write the answer
    /// in the given pieces and close the connection. Returns the request.
    async fn answer(&self, pieces: &[&[u8]]) -> String {
        let (mut stream, _) = self.listener.accept().await.unwrap();
        let mut request = Vec::new();
        let _request_length: usize = stream.read_buf(&mut request).await.unwrap();
        for piece in pieces {
            stream.write_all(piece).await.unwrap();
            stream.flush().await.unwrap();
        }
        String::from_utf8(request).unwrap()
    }
}

fn socket_path(directory: &Path) -> PathBuf {
    directory.join(".socket.sock")
}

/// Poll a future once, so it starts its work.
async fn poll_once<F: Future>(mut future: Pin<&mut F>) -> Poll<F::Output> {
    poll_fn(|context| Poll::Ready(future.as_mut().poll(context))).await
}

#[tokio::test]
async fn a_json_request_goes_out_in_one_write_and_its_answer_is_read_to_the_end() {
    let hyprland = FakeHyprland::new();
    let instance = hyprland.instance();
    let (submap, request) = tokio::join!(
        query::submap(&instance),
        hyprland.answer(&[b"\"def", b"au", b"lt\"\n"]),
    );
    assert_eq!(request, "j/submap");
    assert_eq!(submap.unwrap(), "default");
}

#[tokio::test]
async fn a_text_request_with_the_answer_ok_succeeds() {
    let hyprland = FakeHyprland::new();
    let instance = hyprland.instance();
    let (ran, request) = tokio::join!(
        dispatch::eval(&instance, "hl.version()"),
        hyprland.answer(&[b"ok"]),
    );
    assert_eq!(request, "/eval hl.version()");
    assert!(ran.is_ok(), "{ran:?}");
}

#[tokio::test]
async fn any_other_answer_is_a_refusal() {
    let hyprland = FakeHyprland::new();
    let instance = hyprland.instance();
    for answer in [
        "warning: Nothing to focus to in direction l",
        "error: boom",
        "",
    ] {
        let pieces = [answer.as_bytes()];
        let (ran, _) = tokio::join!(dispatch::eval(&instance, "x"), hyprland.answer(&pieces));
        assert!(
            matches!(&ran, Err(Error::Refused { request, answer: returned }) if request == "eval x" && returned == answer),
            "{ran:?}"
        );
    }
}

#[tokio::test]
async fn an_answer_that_is_not_utf8_fails() {
    let hyprland = FakeHyprland::new();
    let instance = hyprland.instance();
    let (submap, _) = tokio::join!(query::submap(&instance), hyprland.answer(&[b"\"\xff\""]));
    assert!(
        matches!(&submap, Err(Error::NotUtf8 { request, .. }) if request == "submap"),
        "{submap:?}"
    );
}

#[tokio::test]
async fn a_request_waits_while_the_queue_of_the_socket_is_full() {
    let hyprland = FakeHyprland::with_queue_length(0);
    let mut queued = Vec::new();
    let full = loop {
        match UnixStream::connect(socket_path(hyprland.directory.path())).await {
            Ok(stream) => queued.push(stream),
            Err(error) => break error,
        }
    };
    assert_eq!(full.kind(), io::ErrorKind::WouldBlock, "{full}");

    let instance = hyprland.instance();
    let mut submap = pin!(query::submap(&instance));
    assert!(poll_once(submap.as_mut()).await.is_pending());

    for _ in &queued {
        let _accepted = hyprland.listener.accept().await.unwrap();
    }
    let (submap, request) = tokio::join!(submap, hyprland.answer(&[b"\"default\""]));
    assert_eq!(request, "j/submap");
    assert_eq!(submap.unwrap(), "default");
}

#[tokio::test]
async fn an_instance_without_a_socket_fails_to_connect() {
    let directory = TempDirectory::new();
    let submap = query::submap(&Instance::at(directory.path())).await;
    assert!(
        matches!(&submap, Err(Error::Connect { path, .. }) if *path == socket_path(directory.path())),
        "{submap:?}"
    );
}
