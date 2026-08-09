//! operator-secrets-tui — thin fullscreen client for operator-secretsd.
//!
//! Runs in two places with the same code: as a console service on
//! /dev/console (`--console`), and as an ordinary command in an SSH
//! session. Every connected client renders the same daemon state and any
//! of them may answer the pending form — a headless box must be fillable
//! over SSH.
//!
//! Unlike var-disk-manager's TUI this is NOT a login shell: it runs in
//! the main system where the operator already has a real one, so there is
//! no `-c` passthrough and no exec-into-sh escape hatch.

use std::io::IsTerminal;
use std::path::PathBuf;
use std::time::Duration;

use anyhow::{Context, Result, bail};
use clap::Parser;
use crossterm::event::{Event, EventStream, KeyCode, KeyModifiers};
use crossterm::terminal::{EnterAlternateScreen, LeaveAlternateScreen};
use futures_util::StreamExt;
use ratatui::prelude::*;
use ratatui::widgets::{Block, Borders, Cell, Paragraph, Row, Table, Wrap};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::UnixStream;

use operator_secrets::{
    ClientMsg, EDIT_SOCKET_PATH, EDIT_UNIT, SOCKET_PATH, SecretState, Snapshot, state_file_for,
};

#[derive(Parser)]
#[command(
    about = "Answer the operator-provided secret prompts blocking this boot, or re-enter a stored secret with --edit"
)]
struct Cli {
    /// Control socket of the daemon. Defaults to the boot daemon's, or to
    /// the edit session's under `--edit`.
    #[arg(long)]
    socket: Option<PathBuf>,

    /// Console-service mode: exit as soon as the daemon goes away
    /// (releasing /dev/console back to systemd) instead of waiting for a
    /// keypress, and ignore the quit keys — the console prompt must not
    /// be closable into nothing.
    #[arg(long)]
    console: bool,

    /// Re-enter a secret on a running host. Starts an edit session and
    /// attaches to it; without SECRET, the session lists what this host
    /// declares and the secret is picked on screen.
    #[arg(long)]
    edit: bool,

    /// Secret to re-enter. Only meaningful with `--edit`.
    secret: Option<String>,
}

impl Cli {
    fn socket(&self) -> PathBuf {
        self.socket.clone().unwrap_or_else(|| {
            PathBuf::from(if self.edit {
                EDIT_SOCKET_PATH
            } else {
                SOCKET_PATH
            })
        })
    }
}

/// Start the edit session this client is about to attach to.
///
/// Run as a unit and not as a child of this process: the daemon's own log
/// lines belong in the journal, where a credential change stays on the
/// record, and not interleaved into the screen the operator is typing on.
fn start_edit_session() -> Result<()> {
    let status = std::process::Command::new("systemctl")
        .args(["start", "--no-block", EDIT_UNIT])
        .status()
        .with_context(|| format!("starting {EDIT_UNIT}"))?;
    if !status.success() {
        bail!(
            "could not start {EDIT_UNIT} ({status}); editing needs root, \
             and the unit exists only where operator-secrets is enabled"
        );
    }
    Ok(())
}

fn main() {
    let cli = Cli::parse();

    let rt = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .expect("tokio runtime");

    let result = if cli.edit {
        // Entering a secret means typing one, and there is no way to mask
        // what is typed without a terminal.
        if !std::io::stdout().is_terminal() {
            eprintln!("operator-secrets-tui: --edit needs a terminal");
            std::process::exit(1);
        }
        // --console disables the quit keys, which is right for a parked
        // boot and wrong for a picker nobody asked to be trapped in.
        if cli.console {
            eprintln!("operator-secrets-tui: --edit and --console are not compatible");
            std::process::exit(1);
        }
        match start_edit_session() {
            Ok(()) => rt.block_on(run_tui(&cli)),
            Err(e) => Err(e),
        }
    } else if cli.secret.is_some() {
        eprintln!("operator-secrets-tui: naming a secret only makes sense with --edit");
        std::process::exit(1);
    } else if std::io::stdout().is_terminal() {
        rt.block_on(run_tui(&cli))
    } else {
        // Not a TTY (`ssh` without -t, pipes): line mode. Read-only —
        // there is no sane way to mask a secret without a terminal.
        rt.block_on(run_lines(&cli))
    };
    if let Err(e) = result {
        eprintln!("operator-secrets-tui: {e:#}");
        std::process::exit(1);
    }
}

/// Connect with retries; the daemon may not be up yet.
async fn connect(socket: &PathBuf) -> Option<UnixStream> {
    for _ in 0..60 {
        if let Ok(s) = UnixStream::connect(socket).await {
            return Some(s);
        }
        tokio::time::sleep(Duration::from_millis(500)).await;
    }
    None
}

fn last_state(socket: &std::path::Path) -> String {
    std::fs::read_to_string(state_file_for(socket))
        .unwrap_or_default()
        .trim()
        .to_string()
}

/// Line mode: print the message line on every change until the daemon exits.
async fn run_lines(cli: &Cli) -> Result<()> {
    let socket = cli.socket();
    let Some(stream) = connect(&socket).await else {
        println!(
            "no operator-secrets daemon; last state: {}",
            last_state(&socket)
        );
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
        if snap.prompt.is_some() {
            println!("  (run `operator-secrets-tui` on a terminal to answer)");
        }
    }
    println!("daemon exited (boot continuing or failed)");
    Ok(())
}

struct App {
    snap: Snapshot,
    /// One editable buffer per prompt field, in prompt order.
    inputs: Vec<String>,
    focus: usize,
    /// Row highlighted in the secret list while an edit session waits for
    /// a choice. Meaningless outside that state.
    selected: usize,
    /// A choice has been sent for the secret named on the command line, so
    /// it is not sent again on every later snapshot.
    choice_sent: bool,
    /// Attached to an edit session and not to a boot, which changes what
    /// the daemon going away means.
    editing: bool,
    /// Daemon connection closed: boot continuing, or daemon died.
    daemon_gone: bool,
    /// Non-fatal note for the operator (submitted, send failed...).
    note: String,
}

impl App {
    /// Adopt a new snapshot, keeping half-typed input when the prompt is
    /// the same one and discarding it when it is not.
    fn adopt(&mut self, snap: Snapshot) {
        let new_id = snap.prompt.as_ref().map(|p| p.id);
        let old_id = self.snap.prompt.as_ref().map(|p| p.id);
        if new_id != old_id {
            self.inputs = snap
                .prompt
                .as_ref()
                .map(|p| p.fields.iter().map(|f| f.value.clone()).collect())
                .unwrap_or_default();
            self.focus = 0;
            self.note.clear();
        }
        self.snap = snap;
        self.selected = self.selected.min(self.snap.secrets.len().saturating_sub(1));
    }

    fn field_count(&self) -> usize {
        self.snap.prompt.as_ref().map_or(0, |p| p.fields.len())
    }

    /// An edit session is waiting for a secret to be picked, and no form
    /// has taken its place yet.
    fn choosing(&self) -> bool {
        self.snap.choosing && self.snap.prompt.is_none()
    }
}

/// Restores the terminal unconditionally — on clean exit, on any `?`
/// error path, and on panic unwind (the crate deliberately does not set
/// panic = "abort"). A console or SSH session must never be left in raw
/// mode on the alternate screen.
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

async fn run_tui(cli: &Cli) -> Result<()> {
    let socket = cli.socket();
    let Some(stream) = connect(&socket).await else {
        eprintln!(
            "no operator-secrets daemon; last state: {}",
            last_state(&socket)
        );
        return Ok(());
    };
    let (read_half, mut write_half) = stream.into_split();
    let mut snapshots = BufReader::new(read_half).lines();

    let _guard = TermGuard::new()?;
    let backend = CrosstermBackend::new(std::io::stdout());
    let mut terminal = Terminal::new(backend).context("creating terminal")?;

    let mut app = App {
        snap: Snapshot::default(),
        inputs: Vec::new(),
        focus: 0,
        selected: 0,
        choice_sent: false,
        editing: cli.edit,
        daemon_gone: false,
        note: String::new(),
    };
    let mut events = EventStream::new();

    loop {
        terminal.draw(|f| ui(f, &app))?;

        tokio::select! {
            line = snapshots.next_line(), if !app.daemon_gone => {
                match line {
                    Ok(Some(l)) => {
                        if let Ok(snap) = serde_json::from_str::<Snapshot>(&l) {
                            app.adopt(snap);
                        }
                        // A secret named on the command line skips the
                        // picker: the session is told once, as soon as it
                        // says it is waiting for a choice.
                        if let Some(name) = &cli.secret
                            && app.choosing()
                            && !app.choice_sent
                        {
                            app.choice_sent = true;
                            send_choice(&mut app, &mut write_half, name.clone()).await?;
                        }
                    }
                    _ => {
                        app.daemon_gone = true;
                        if cli.console {
                            // Release /dev/console; systemd resets the tty
                            // (TTYReset) and boot messages take over.
                            return Ok(());
                        }
                    }
                }
            }
            ev = events.next() => {
                let Some(Ok(Event::Key(key))) = ev else { continue };
                if !key.is_press() {
                    continue;
                }
                let ctrl = key.modifiers.contains(KeyModifiers::CONTROL);

                // Picking a secret is a different screen from filling a
                // form in, and shares none of its keys.
                if app.choosing() {
                    match key.code {
                        KeyCode::Esc => return Ok(()),
                        KeyCode::Char('c') if ctrl => return Ok(()),
                        KeyCode::Down | KeyCode::Tab => move_selection(&mut app, 1),
                        KeyCode::Up | KeyCode::BackTab => move_selection(&mut app, -1),
                        KeyCode::Enter => {
                            if let Some(s) = app.snap.secrets.get(app.selected) {
                                let name = s.name.clone();
                                send_choice(&mut app, &mut write_half, name).await?;
                            }
                        }
                        _ => {}
                    }
                    continue;
                }

                match key.code {
                    // Quit keys are disabled in console mode: closing the
                    // only visible prompt on a headless box, with the boot
                    // still parked, leaves nothing to come back to.
                    KeyCode::Esc if !cli.console => return Ok(()),
                    KeyCode::Char('c') if ctrl && !cli.console => return Ok(()),
                    KeyCode::Char('c') if ctrl => {
                        app.note = "Ctrl-C is disabled on the console UI".into();
                    }
                    KeyCode::Tab | KeyCode::Down => move_focus(&mut app, 1),
                    KeyCode::BackTab | KeyCode::Up => move_focus(&mut app, -1),
                    KeyCode::Enter => {
                        if app.field_count() == 0 {
                            if app.daemon_gone && !cli.console {
                                return Ok(());
                            }
                        } else if app.focus + 1 < app.field_count() {
                            move_focus(&mut app, 1);
                        } else {
                            submit(&mut app, &mut write_half).await?;
                        }
                    }
                    // Submit from anywhere in the form.
                    KeyCode::Char('s') if ctrl => submit(&mut app, &mut write_half).await?,
                    KeyCode::Char('u') if ctrl => {
                        if let Some(b) = app.inputs.get_mut(app.focus) {
                            b.clear();
                        }
                    }
                    KeyCode::Backspace => {
                        if let Some(b) = app.inputs.get_mut(app.focus) {
                            b.pop();
                        }
                    }
                    KeyCode::Char(c) => {
                        if let Some(b) = app.inputs.get_mut(app.focus) {
                            b.push(c);
                        }
                    }
                    _ => {}
                }
            }
        }
    }
}

fn move_focus(app: &mut App, delta: isize) {
    let n = app.field_count();
    if n == 0 {
        return;
    }
    let cur = app.focus.min(n - 1) as isize;
    app.focus = (cur + delta).rem_euclid(n as isize) as usize;
}

fn move_selection(app: &mut App, delta: isize) {
    let n = app.snap.secrets.len();
    if n == 0 {
        return;
    }
    let cur = app.selected.min(n - 1) as isize;
    app.selected = (cur + delta).rem_euclid(n as isize) as usize;
}

/// Tell the session which secret to re-enter.
async fn send_choice(
    app: &mut App,
    write_half: &mut (impl AsyncWriteExt + Unpin),
    secret: String,
) -> Result<()> {
    let mut json = serde_json::to_string(&ClientMsg::Edit { secret })?;
    json.push('\n');
    if write_half.write_all(json.as_bytes()).await.is_err() {
        app.daemon_gone = true;
        app.note = "daemon connection lost".into();
    }
    Ok(())
}

async fn submit(app: &mut App, write_half: &mut (impl AsyncWriteExt + Unpin)) -> Result<()> {
    let Some(prompt) = &app.snap.prompt else {
        return Ok(());
    };
    if let Some((i, f)) = prompt
        .fields
        .iter()
        .enumerate()
        .find(|(i, _)| app.inputs.get(*i).is_none_or(String::is_empty))
    {
        app.focus = i;
        app.note = format!("{} is empty", f.name);
        return Ok(());
    }
    let values: Vec<(String, String)> = prompt
        .fields
        .iter()
        .enumerate()
        .map(|(i, f)| (f.name.clone(), app.inputs[i].clone()))
        .collect();
    let mut json = serde_json::to_string(&ClientMsg::Submit {
        prompt_id: prompt.id,
        values,
    })?;
    json.push('\n');
    if write_half.write_all(json.as_bytes()).await.is_err() {
        app.daemon_gone = true;
        app.note = "daemon connection lost".into();
    } else {
        app.note = "submitted; validating...".into();
    }
    Ok(())
}

fn hostname() -> String {
    std::fs::read_to_string("/proc/sys/kernel/hostname")
        .map(|h| h.trim().to_string())
        .ok()
        .filter(|h| !h.is_empty() && h != "(none)")
        .unwrap_or_else(|| "this host".into())
}

fn state_style(state: SecretState) -> (&'static str, Style) {
    match state {
        SecretState::Pending => ("pending", Style::default().fg(Color::Gray)),
        SecretState::Checking => ("checking", Style::default().fg(Color::Cyan)),
        SecretState::NeedsInput => ("NEEDS INPUT", Style::default().fg(Color::Yellow)),
        SecretState::Validating => ("validating", Style::default().fg(Color::Cyan)),
        SecretState::Satisfied => ("ok", Style::default().fg(Color::Green)),
        SecretState::Undecided => ("UNDECIDED", Style::default().fg(Color::Red)),
    }
}

fn ui(frame: &mut Frame, app: &App) {
    let area = frame.area();
    let chunks = Layout::vertical([
        Constraint::Length(2),                                 // header
        Constraint::Length(app.snap.secrets.len() as u16 + 3), // secret table
        Constraint::Length(4),                                 // status
        Constraint::Min(6),                                    // form / hints
    ])
    .split(area);

    let header = Paragraph::new(Line::from(format!(
        "  {} — operator-provided secrets",
        hostname()
    )))
    .style(Style::default().fg(Color::Cyan).bold());
    frame.render_widget(header, chunks[0]);

    let choosing = app.choosing();
    let rows: Vec<Row> = app
        .snap
        .secrets
        .iter()
        .enumerate()
        .map(|(i, s)| {
            let (name, style) = state_style(s.state);
            let picked = choosing && i == app.selected;
            let row = Row::new(vec![
                Cell::from(format!("{} {}", if picked { ">" } else { " " }, s.name)),
                Cell::from(name).style(style.bold()),
                Cell::from(if s.detail.is_empty() {
                    s.description.clone()
                } else {
                    s.detail.clone()
                })
                .style(Style::default().fg(Color::Gray)),
            ]);
            if picked {
                row.style(Style::default().fg(Color::Cyan).bold())
            } else {
                row
            }
        })
        .collect();
    let table = Table::new(
        rows,
        [
            Constraint::Length(24),
            Constraint::Length(12),
            Constraint::Min(20),
        ],
    )
    .header(Row::new(vec!["secret", "state", "detail"]).style(Style::default().bold()))
    .block(Block::default().title(" secrets ").borders(Borders::ALL));
    frame.render_widget(table, chunks[1]);

    let style = if app.snap.blocked {
        Style::default().fg(Color::Red).bold()
    } else if app.snap.done {
        Style::default().fg(Color::Green)
    } else {
        Style::default().fg(Color::Yellow)
    };
    let status = Paragraph::new(format!("  {}", app.snap.message))
        .style(style)
        .wrap(Wrap { trim: false })
        .block(Block::default().title(" status ").borders(Borders::ALL));
    frame.render_widget(status, chunks[2]);

    let bottom = if let Some(prompt) = &app.snap.prompt {
        let mut lines =
            vec![Line::from(format!("  {}", prompt.description)).style(Style::default().bold())];
        if !prompt.reason.is_empty() {
            lines.push(
                Line::from(format!("  {}", prompt.reason))
                    .style(Style::default().fg(Color::Yellow)),
            );
        }
        lines.push(Line::from(""));
        for (i, f) in prompt.fields.iter().enumerate() {
            let raw = app.inputs.get(i).cloned().unwrap_or_default();
            // Masking is the whole point of the `sensitive` flag: a
            // shoulder-surfable console must not show the secret.
            let shown = if f.sensitive {
                "*".repeat(raw.chars().count())
            } else {
                raw
            };
            let marker = if i == app.focus { ">" } else { " " };
            let style = if i == app.focus {
                Style::default().fg(Color::Cyan).bold()
            } else {
                Style::default()
            };
            lines.push(Line::from(format!("  {marker} {}: {shown}", f.name)).style(style));
            if i == app.focus && !f.description.is_empty() {
                lines.push(
                    Line::from(format!("      {}", f.description))
                        .style(Style::default().fg(Color::Gray)),
                );
            }
        }
        lines.push(Line::from(""));
        if !app.note.is_empty() {
            lines.push(
                Line::from(format!("  {}", app.note)).style(Style::default().fg(Color::Magenta)),
            );
        }
        lines.push(
            Line::from(
                "  Tab/↑↓: field  |  Enter: next / submit  |  Ctrl-S: submit  |  Ctrl-U: clear",
            )
            .style(Style::default().fg(Color::Gray)),
        );
        Paragraph::new(lines).block(
            Block::default()
                .title(format!(" {} ", prompt.secret))
                .borders(Borders::ALL)
                .border_style(Style::default().fg(Color::Cyan)),
        )
    } else if choosing {
        let mut lines = vec![
            Line::from("  Pick the secret to re-enter.").style(Style::default().bold()),
            Line::from(
                "  What is stored now stays untouched until a new answer has been accepted.",
            )
            .style(Style::default().fg(Color::Gray)),
            Line::from(""),
        ];
        if !app.note.is_empty() {
            lines
                .push(Line::from(format!("  {}", app.note)).style(Style::default().fg(Color::Magenta)));
        }
        lines.push(
            Line::from("  ↑↓: select  |  Enter: re-enter it  |  Esc: leave without changing anything")
                .style(Style::default().fg(Color::Gray)),
        );
        Paragraph::new(lines).block(
            Block::default()
                .title(" edit ")
                .borders(Borders::ALL)
                .border_style(Style::default().fg(Color::Cyan)),
        )
    } else if app.daemon_gone {
        let (text, colour) = if app.editing && app.snap.done {
            ("  done — the secret was written", Color::Green)
        } else if app.editing {
            (
                "  edit session ended without writing anything (check the journal)",
                Color::Yellow,
            )
        } else {
            (
                "  daemon exited — boot is continuing (or failed; check the journal)",
                Color::Green,
            )
        };
        Paragraph::new(vec![
            Line::from(""),
            Line::from(text).style(Style::default().fg(colour)),
        ])
    } else {
        Paragraph::new(vec![
            Line::from(""),
            Line::from("  waiting...").style(Style::default().fg(Color::Gray)),
        ])
    };
    frame.render_widget(bottom, chunks[3]);
}
