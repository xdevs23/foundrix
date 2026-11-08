use tokio::net::UnixDatagram;

/// Wait until a program reports to be ready, through the `READY=1` message
/// of the systemd notify protocol on `notifications`, the socket named to it
/// in `NOTIFY_SOCKET`. Hyprland and the libraries it uses also send other
/// messages, such as `ERRNO=2`.
///
/// # Panics
///
/// When receiving from the socket fails.
pub async fn wait_for_ready(notifications: &UnixDatagram) {
    loop {
        let mut message = Vec::new();
        let _length: usize = notifications.recv_buf(&mut message).await.unwrap();
        if message
            .split(|&byte| byte == b'\n')
            .any(|line| line == b"READY=1")
        {
            return;
        }
    }
}
