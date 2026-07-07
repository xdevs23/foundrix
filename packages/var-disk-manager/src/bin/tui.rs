//! var-disk-manager-tui — thin fullscreen client for var-disk-managerd.
//!
//! Runs in two places with the same code: as a console service on
//! /dev/console, and as root's initrd SSH login shell. All connected
//! clients render the same daemon state and any of them may answer a
//! pending passphrase prompt.
//!
//! Login-shell contract: sshd invokes the shell as `shell -c <command>`
//! for non-interactive commands — passed through to /bin/sh so
//! `ssh -p 2222 host <cmd>` keeps working for debugging. On TUI exit
//! (Esc/Ctrl-C, daemon gone) it execs /bin/sh: the escape hatch to a real
//! shell must never be more than one keypress away.

use std::io::IsTerminal;
use std::os::unix::process::CommandExt;
use std::time::Duration;

use anyhow::{Context, Result};
use crossterm::event::{Event, EventStream, KeyCode, KeyModifiers};
use crossterm::terminal::{EnterAlternateScreen, LeaveAlternateScreen};
use futures_util::StreamExt;
use ratatui::prelude::*;
use ratatui::widgets::{Block, Borders, Cell, Gauge, Paragraph, Row, Table, Wrap};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::UnixStream;

use var_disk_manager::{ClientMsg, DiskClass, PromptKind, SOCKET_PATH, STATE_FILE, Snapshot};

fn exec_shell() -> ! {
    let err = std::process::Command::new("/bin/sh").exec();
    eprintln!("exec /bin/sh failed: {err}");
    std::process::exit(1);
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    // Login-shell command passthrough: `shell -c <command>`.
    if args.get(1).map(String::as_str) == Some("-c") {
        let err = std::process::Command::new("/bin/sh").args(&args[1..]).exec();
        eprintln!("exec /bin/sh failed: {err}");
        std::process::exit(1);
    }
    // Console service mode: exit when the daemon goes away (releasing
    // /dev/console for systemd) instead of waiting for a keypress.
    let console_mode = args.iter().any(|a| a == "--console");

    let rt = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .expect("tokio runtime");

    if std::io::stdout().is_terminal() {
        match rt.block_on(run_tui(console_mode)) {
            Ok(AfterTui::Shell) => exec_shell(),
            Ok(AfterTui::Exit) => {}
            Err(e) => {
                eprintln!("var-disk-manager-tui: {e:#}");
                exec_shell()
            }
        }
    } else {
        // Not a TTY (`ssh` without -t, pipes): line mode.
        if let Err(e) = rt.block_on(run_lines()) {
            eprintln!("var-disk-manager-tui: {e:#}");
            std::process::exit(1);
        }
    }
}

/// Connect with retries; the daemon may not be up yet early in boot.
async fn connect() -> Option<UnixStream> {
    for _ in 0..60 {
        if let Ok(s) = UnixStream::connect(SOCKET_PATH).await {
            return Some(s);
        }
        tokio::time::sleep(Duration::from_millis(500)).await;
    }
    None
}

/// Line mode: print the message line on every change until the daemon exits.
async fn run_lines() -> Result<()> {
    let Some(stream) = connect().await else {
        // Daemon gone or never started; the state file is the breadcrumb.
        let state = std::fs::read_to_string(STATE_FILE).unwrap_or_default();
        println!("no var-disk-manager daemon; last state: {}", state.trim());
        return Ok(());
    };
    let (read_half, _write_half) = stream.into_split();
    let mut lines = BufReader::new(read_half).lines();
    let mut last = String::new();
    while let Some(line) = lines.next_line().await? {
        let snap: Snapshot = serde_json::from_str(&line).context("parsing snapshot")?;
        if snap.message != last {
            println!("{}", snap.message);
            last = snap.message;
        }
    }
    println!("daemon exited (boot continuing or failed)");
    Ok(())
}

enum AfterTui {
    /// Drop the user into /bin/sh.
    Shell,
    /// Just exit (boot is continuing).
    Exit,
}

struct App {
    snap: Snapshot,
    input: String,
    /// Daemon connection closed: boot continuing (clean) or daemon died.
    daemon_gone: bool,
}

/// Restores the terminal unconditionally — on clean exit, on any `?`
/// error path, and on panic unwind. The escape-hatch shell must never
/// inherit raw mode or the alternate screen.
struct TermGuard;

impl TermGuard {
    fn new() -> Result<Self> {
        crossterm::terminal::enable_raw_mode().context("enabling raw mode")?;
        crossterm::execute!(std::io::stdout(), EnterAlternateScreen)?;
        Ok(Self)
    }
}

impl Drop for TermGuard {
    fn drop(&mut self) {
        let _ = crossterm::terminal::disable_raw_mode();
        let _ = crossterm::execute!(std::io::stdout(), LeaveAlternateScreen);
    }
}

async fn run_tui(console_mode: bool) -> Result<AfterTui> {
    let stream = match connect().await {
        Some(s) => s,
        None => {
            let state = std::fs::read_to_string(STATE_FILE).unwrap_or_default();
            eprintln!("no var-disk-manager daemon; last state: {}", state.trim());
            return Ok(AfterTui::Shell);
        }
    };
    let (read_half, mut write_half) = stream.into_split();
    let mut snapshots = BufReader::new(read_half).lines();

    let _guard = TermGuard::new()?;
    let backend = CrosstermBackend::new(std::io::stdout());
    let mut terminal = Terminal::new(backend).context("creating terminal")?;

    let mut app = App { snap: Snapshot::default(), input: String::new(), daemon_gone: false };
    let mut events = EventStream::new();
    // Terminal state is restored by TermGuard's Drop on every exit path.
    loop {
        terminal.draw(|f| ui(f, &app))?;

        tokio::select! {
            line = snapshots.next_line(), if !app.daemon_gone => {
                match line {
                    Ok(Some(l)) => {
                        if let Ok(snap) = serde_json::from_str::<Snapshot>(&l) {
                            // A new prompt invalidates half-typed input for
                            // an old one.
                            let new_id = snap.prompt.as_ref().map(|p| p.id);
                            let old_id = app.snap.prompt.as_ref().map(|p| p.id);
                            if new_id != old_id {
                                app.input.clear();
                            }
                            app.snap = snap;
                        }
                    }
                    _ => {
                        app.daemon_gone = true;
                        if console_mode {
                            // Release /dev/console; systemd resets the tty
                            // (TTYReset) and boot messages take over.
                            break Ok(AfterTui::Exit);
                        }
                    }
                }
            }
            ev = events.next() => {
                let Some(Ok(Event::Key(key))) = ev else { continue };
                if !key.is_press() {
                    continue;
                }
                match key.code {
                    KeyCode::Char('c') if key.modifiers.contains(KeyModifiers::CONTROL) => {
                        break Ok(AfterTui::Shell);
                    }
                    KeyCode::Esc => break Ok(AfterTui::Shell),
                    KeyCode::Enter => {
                        if let Some(prompt) = &app.snap.prompt {
                            let msg = ClientMsg::Submit {
                                prompt_id: prompt.id,
                                value: std::mem::take(&mut app.input),
                            };
                            let mut json = serde_json::to_string(&msg)?;
                            json.push('\n');
                            if write_half.write_all(json.as_bytes()).await.is_err() {
                                app.daemon_gone = true;
                            }
                        } else if app.daemon_gone {
                            break Ok(AfterTui::Exit);
                        }
                    }
                    KeyCode::Backspace => {
                        app.input.pop();
                    }
                    KeyCode::Char('u') if key.modifiers.contains(KeyModifiers::CONTROL) => {
                        app.input.clear();
                    }
                    KeyCode::Char(c) => {
                        app.input.push(c);
                    }
                    _ => {}
                }
            }
        }
    }
}

fn hostname() -> String {
    std::fs::read_to_string("/proc/sys/kernel/hostname")
        .map(|h| h.trim().to_string())
        .ok()
        .filter(|h| !h.is_empty() && h != "(none)" && h != "localhost")
        .unwrap_or_else(|| "initrd".into())
}

fn class_style(class: DiskClass) -> (&'static str, Style) {
    match class {
        DiskClass::Luks => ("LUKS", Style::default().fg(Color::Green)),
        DiskClass::Legacy => ("legacy", Style::default().fg(Color::Yellow)),
        DiskClass::Blank => ("blank", Style::default().fg(Color::Cyan)),
        DiskClass::Foreign => ("foreign", Style::default().fg(Color::DarkGray)),
    }
}

fn ui(frame: &mut Frame, app: &App) {
    let area = frame.area();
    let chunks = Layout::vertical([
        Constraint::Length(4),                                // header
        Constraint::Length(app.snap.disks.len() as u16 + 3),  // disk table
        Constraint::Length(4),                                // status / progress
        Constraint::Min(5),                                   // prompt / hints
    ])
    .split(area);

    // Header: title + host key fingerprint (visual MITM check vs console).
    let header = Paragraph::new(vec![
        Line::from(format!("  {} initrd — /var disk manager", hostname()))
            .style(Style::default().fg(Color::Cyan).bold()),
        Line::from(match &app.snap.fingerprint {
            Some(fp) => format!("  host key: {fp}"),
            None => "  host key: (not provisioned yet)".to_string(),
        })
        .style(Style::default().fg(Color::DarkGray)),
    ]);
    frame.render_widget(header, chunks[0]);

    // Disk table.
    let rows: Vec<Row> = app
        .snap
        .disks
        .iter()
        .map(|d| {
            let (name, style) = class_style(d.class);
            Row::new(vec![
                Cell::from(d.id.clone()),
                Cell::from(name).style(style.bold()),
                Cell::from(d.detail.clone()).style(Style::default().fg(Color::DarkGray)),
            ])
        })
        .collect();
    let table = Table::new(
        rows,
        [Constraint::Length(32), Constraint::Length(9), Constraint::Min(20)],
    )
    .header(Row::new(vec!["volume", "class", "detail"]).style(Style::default().bold()))
    .block(Block::default().title(" data volumes ").borders(Borders::ALL));
    frame.render_widget(table, chunks[1]);

    // Status / progress.
    if let Some(p) = app.snap.progress {
        let ratio = if p.total > 0 { (p.copied as f64 / p.total as f64).min(1.0) } else { 0.0 };
        let gauge = Gauge::default()
            .block(Block::default().title(" copying ").borders(Borders::ALL))
            .gauge_style(Style::default().fg(Color::Green))
            .ratio(ratio)
            .label(format!(
                "{:.1}% ({} / {} MiB)",
                ratio * 100.0,
                p.copied >> 20,
                p.total >> 20
            ));
        frame.render_widget(gauge, chunks[2]);
    } else {
        let style = if app.snap.blocked {
            Style::default().fg(Color::Red).bold()
        } else {
            Style::default().fg(Color::Yellow)
        };
        let status = Paragraph::new(format!("  {}", app.snap.message))
            .style(style)
            .wrap(Wrap { trim: false })
            .block(Block::default().title(" status ").borders(Borders::ALL));
        frame.render_widget(status, chunks[2]);
    }

    // Prompt / hints.
    let bottom = if app.daemon_gone {
        Paragraph::new(vec![
            Line::from(""),
            Line::from("  daemon exited — boot is continuing (or failed; check the journal)")
                .style(Style::default().fg(Color::Green)),
            Line::from("  Enter: close  |  Esc / Ctrl-C: shell")
                .style(Style::default().fg(Color::DarkGray)),
        ])
    } else if let Some(prompt) = &app.snap.prompt {
        let masked = "*".repeat(app.input.chars().count());
        let title = match prompt.kind {
            PromptKind::UnlockPassphrase => " passphrase ",
            PromptKind::NewPassphrase => " NEW passphrase ",
            PromptKind::RepeatPassphrase => " repeat passphrase ",
        };
        Paragraph::new(vec![
            Line::from(format!("  {}", prompt.text)).style(Style::default().bold()),
            Line::from(format!("  > {masked}")),
            Line::from(""),
            Line::from("  Enter: submit  |  Ctrl-U: clear  |  Esc / Ctrl-C: shell")
                .style(Style::default().fg(Color::DarkGray)),
        ])
        .block(Block::default().title(title).borders(Borders::ALL)
            .border_style(Style::default().fg(Color::Cyan)))
    } else {
        Paragraph::new(vec![
            Line::from(""),
            Line::from("  waiting...").style(Style::default().fg(Color::DarkGray)),
            Line::from("  Esc / Ctrl-C: shell").style(Style::default().fg(Color::DarkGray)),
        ])
    };
    frame.render_widget(bottom, chunks[3]);
}
