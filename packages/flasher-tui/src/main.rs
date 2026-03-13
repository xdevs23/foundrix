use anyhow::{Context, Result, bail};
use clap::Parser;
use crossterm::event::{self, Event, KeyCode, KeyModifiers};
use crossterm::terminal::{self, EnterAlternateScreen, LeaveAlternateScreen};
use ratatui::prelude::*;
use ratatui::widgets::{Block, Borders, Gauge, List, ListItem, ListState, Paragraph};
use std::fs::{self, File, OpenOptions};
use std::io::{self, Read, Write};
use std::os::unix::fs::OpenOptionsExt;
use std::process::Command;
use std::sync::mpsc;
use std::thread;

#[derive(Parser)]
#[command(about = "TUI for selecting a target disk and flashing a system image")]
struct Cli {
    /// Path to the system image to flash (supports .zst compressed)
    #[arg(long)]
    image: String,

    /// Display name for the image being flashed
    #[arg(long, default_value = "system image")]
    image_name: String,

    /// Uncompressed image size in bytes (required for compressed images)
    #[arg(long)]
    image_size: Option<u64>,
}

struct Disk {
    path: String,
    name: String,
    size_bytes: u64,
    model: String,
    transport: String,
}

impl Disk {
    fn display_size(&self) -> String {
        const GIB: u64 = 1024 * 1024 * 1024;
        const MIB: u64 = 1024 * 1024;
        if self.size_bytes >= GIB {
            format!("{:.1} GiB", self.size_bytes as f64 / GIB as f64)
        } else {
            format!("{:.1} MiB", self.size_bytes as f64 / MIB as f64)
        }
    }
}

fn format_size(bytes: u64) -> String {
    const GIB: u64 = 1024 * 1024 * 1024;
    const MIB: u64 = 1024 * 1024;
    if bytes >= GIB {
        format!("{:.1} GiB", bytes as f64 / GIB as f64)
    } else {
        format!("{:.1} MiB", bytes as f64 / MIB as f64)
    }
}

fn discover_disks() -> Result<Vec<Disk>> {
    let output = Command::new("lsblk")
        .args(["-b", "-dn", "-o", "NAME,SIZE,TYPE,TRAN,MODEL"])
        .output()
        .context("running lsblk")?;

    if !output.status.success() {
        bail!(
            "lsblk failed: {}",
            String::from_utf8_lossy(&output.stderr)
        );
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    let mut disks = Vec::new();

    for line in stdout.lines() {
        let fields: Vec<&str> = line.splitn(5, char::is_whitespace)
            .map(str::trim)
            .filter(|s| !s.is_empty())
            .collect();

        if fields.len() < 3 {
            continue;
        }

        let name = fields[0];
        let size_bytes: u64 = match fields[1].parse() {
            Ok(s) => s,
            Err(_) => continue,
        };
        let disk_type = fields[2];

        if disk_type != "disk" {
            continue;
        }

        let transport = fields.get(3).unwrap_or(&"").to_string();
        let model = fields.get(4).unwrap_or(&"").to_string();

        if transport == "usb" {
            continue;
        }

        let dev_path = format!("/dev/{name}");

        if is_mounted(&dev_path) {
            continue;
        }

        disks.push(Disk {
            path: dev_path,
            name: name.to_string(),
            size_bytes,
            model,
            transport,
        });
    }

    disks.sort_by(|a, b| b.size_bytes.cmp(&a.size_bytes));
    Ok(disks)
}

fn is_mounted(dev_path: &str) -> bool {
    if Command::new("findmnt")
        .args(["-rn", "-S", dev_path])
        .output()
        .map(|o| o.status.success())
        .unwrap_or(false)
    {
        return true;
    }

    let Ok(output) = Command::new("lsblk")
        .args(["-ln", "-o", "NAME", dev_path])
        .output()
    else {
        return false;
    };

    let stdout = String::from_utf8_lossy(&output.stdout);
    for line in stdout.lines().skip(1) {
        let part = line.trim();
        if !part.is_empty()
            && Command::new("findmnt")
                .args(["-rn", "-S", &format!("/dev/{part}")])
                .output()
                .map(|o| o.status.success())
                .unwrap_or(false)
        {
            return true;
        }
    }

    false
}

enum FlashProgress {
    Writing { written: u64, total: u64 },
    Done,
    Error(String),
}

fn flash_image(image_path: &str, disk_path: &str, total: u64, tx: mpsc::Sender<FlashProgress>) {
    let result = (|| -> Result<()> {
        let file = File::open(image_path).context("opening image file")?;
        let mut src: Box<dyn Read> = if image_path.ends_with(".zst") {
            Box::new(zstd::Decoder::new(file).context("initializing zstd decoder")?)
        } else {
            Box::new(file)
        };

        let mut dst = OpenOptions::new()
            .write(true)
            .custom_flags(libc::O_DSYNC)
            .open(disk_path)
            .context("opening target disk")?;

        let mut buf = vec![0u8; 4 * 1024 * 1024]; // 4 MiB buffer
        let mut written: u64 = 0;

        loop {
            let n = src.read(&mut buf).context("reading image")?;
            if n == 0 {
                break;
            }
            dst.write_all(&buf[..n]).context("writing to disk")?;
            written += n as u64;
            tx.send(FlashProgress::Writing { written, total }).ok();
        }

        Command::new("blockdev")
            .args(["--rereadpt", disk_path])
            .status()
            .context("re-reading partition table")?;

        Ok(())
    })();

    match result {
        Ok(()) => { tx.send(FlashProgress::Done).ok(); }
        Err(e) => { tx.send(FlashProgress::Error(format!("{e:#}"))).ok(); }
    }
}

enum Screen {
    Select,
    Confirm(usize),
    Flashing { disk_idx: usize, written: u64, total: u64 },
    Done,
    Error(String),
}

struct App {
    disks: Vec<Disk>,
    list_state: ListState,
    screen: Screen,
    image: String,
    image_name: String,
    image_size: Option<u64>,
}

impl App {
    fn new(cli: Cli, disks: Vec<Disk>) -> Self {
        let mut list_state = ListState::default();
        if !disks.is_empty() {
            list_state.select(Some(0));
        }
        Self {
            disks,
            list_state,
            screen: Screen::Select,
            image: cli.image,
            image_name: cli.image_name,
            image_size: cli.image_size,
        }
    }

    fn selected_disk(&self) -> Option<&Disk> {
        self.list_state.selected().and_then(|i| self.disks.get(i))
    }

    fn select_next(&mut self) {
        if self.disks.is_empty() {
            return;
        }
        let i = self.list_state.selected().map_or(0, |i| {
            if i >= self.disks.len() - 1 { 0 } else { i + 1 }
        });
        self.list_state.select(Some(i));
    }

    fn select_prev(&mut self) {
        if self.disks.is_empty() {
            return;
        }
        let i = self.list_state.selected().map_or(0, |i| {
            if i == 0 { self.disks.len() - 1 } else { i - 1 }
        });
        self.list_state.select(Some(i));
    }
}

fn ui(frame: &mut Frame, app: &mut App) {
    let area = frame.area();

    match &app.screen {
        Screen::Select => {
            let chunks = Layout::vertical([
                Constraint::Length(4),
                Constraint::Min(6),
                Constraint::Length(3),
            ])
            .split(area);

            let header = Paragraph::new(vec![
                Line::from(""),
                Line::from(format!("  Flashing: {}", app.image_name))
                    .style(Style::default().fg(Color::Cyan).bold()),
                Line::from("  Select the target disk:"),
            ]);
            frame.render_widget(header, chunks[0]);

            if app.disks.is_empty() {
                let msg = Paragraph::new(vec![
                    Line::from(""),
                    Line::from("  No available disks found.")
                        .style(Style::default().fg(Color::Red)),
                    Line::from("  Connect a non-USB disk and restart."),
                ]);
                frame.render_widget(msg, chunks[1]);
            } else {
                let items: Vec<ListItem> = app
                    .disks
                    .iter()
                    .map(|d| {
                        let model = if d.model.is_empty() {
                            d.transport.clone()
                        } else {
                            d.model.clone()
                        };
                        ListItem::new(format!(
                            "  {}  {:>10}  {}",
                            d.path,
                            d.display_size(),
                            model,
                        ))
                    })
                    .collect();

                let list = List::new(items)
                    .block(
                        Block::default()
                            .borders(Borders::ALL)
                            .border_style(Style::default().fg(Color::Cyan))
                            .title(" Disks "),
                    )
                    .highlight_style(
                        Style::default()
                            .fg(Color::Black)
                            .bg(Color::Cyan)
                            .bold(),
                    )
                    .highlight_symbol("▸ ");

                frame.render_stateful_widget(list, chunks[1], &mut app.list_state);
            }

            let help = if app.disks.is_empty() {
                "  s: shell  |  Ctrl-C: exit"
            } else {
                "  ↑/↓: navigate  |  Enter: select  |  s: shell  |  Ctrl-C: exit"
            };
            let footer =
                Paragraph::new(help).style(Style::default().fg(Color::DarkGray));
            frame.render_widget(footer, chunks[2]);
        }

        Screen::Confirm(idx) => {
            let disk = &app.disks[*idx];
            let text = vec![
                Line::from(""),
                Line::from("  ⚠ WARNING ⚠")
                    .style(Style::default().fg(Color::Yellow).bold()),
                Line::from(""),
                Line::from(format!(
                    "  This will ERASE ALL DATA on {}",
                    disk.path
                ))
                .style(Style::default().fg(Color::Red).bold()),
                Line::from(""),
                Line::from(format!("  Disk:   {} ({})", disk.path, disk.display_size())),
                Line::from(format!(
                    "  Model:  {}",
                    if disk.model.is_empty() {
                        "unknown"
                    } else {
                        &disk.model
                    }
                )),
                Line::from(format!("  Image:  {}", app.image_name)),
                Line::from(""),
                Line::from("  Press 'y' to confirm, any other key to go back."),
            ];
            frame.render_widget(Paragraph::new(text), area);
        }

        Screen::Flashing { disk_idx, written, total } => {
            let disk = &app.disks[*disk_idx];
            let chunks = Layout::vertical([
                Constraint::Length(5),
                Constraint::Length(3),
                Constraint::Min(0),
            ])
            .split(area);

            let header = Paragraph::new(vec![
                Line::from(""),
                Line::from(format!("  {} → {}", app.image_name, disk.path))
                    .style(Style::default().fg(Color::Cyan).bold()),
                Line::from(format!("  Writing...  ({} / {})",
                    format_size(*written),
                    format_size(*total),
                )),
                Line::from(""),
            ]);
            frame.render_widget(header, chunks[0]);

            let ratio = if *total > 0 {
                (*written as f64 / *total as f64).min(1.0)
            } else {
                0.0
            };
            let pct = (ratio * 100.0) as u16;

            let gauge = Gauge::default()
                .block(Block::default().borders(Borders::ALL).title(" Progress "))
                .gauge_style(Style::default().fg(Color::Cyan).bg(Color::DarkGray))
                .percent(pct);
            frame.render_widget(gauge, chunks[1]);
        }

        Screen::Done => {
            let text = vec![
                Line::from(""),
                Line::from("  Flash complete!")
                    .style(Style::default().fg(Color::Green).bold()),
                Line::from(""),
                Line::from("  Press Enter to reboot."),
            ];
            frame.render_widget(Paragraph::new(text), area);
        }

        Screen::Error(msg) => {
            let mut lines = vec![
                Line::from(""),
                Line::from("  Error:")
                    .style(Style::default().fg(Color::Red).bold()),
            ];
            for line in msg.lines() {
                lines.push(Line::from(format!("  {line}")));
            }
            lines.push(Line::from(""));
            lines.push(Line::from("  Press Enter to reboot, or Escape to go back."));
            frame.render_widget(Paragraph::new(lines), area);
        }
    }
}

fn drop_to_shell(terminal: &mut Terminal<CrosstermBackend<std::io::Stdout>>) -> Result<()> {
    terminal::disable_raw_mode()?;
    crossterm::execute!(std::io::stdout(), LeaveAlternateScreen)?;

    let shell = std::env::var("SHELL").unwrap_or_else(|_| "/bin/sh".to_string());
    let status = Command::new(&shell)
        .status()
        .context("spawning shell")?;

    if !status.success() {
        eprintln!("shell exited with {status}");
    }

    crossterm::execute!(std::io::stdout(), EnterAlternateScreen)?;
    terminal::enable_raw_mode()?;
    terminal.clear()?;
    Ok(())
}

fn run(terminal: &mut Terminal<CrosstermBackend<std::io::Stdout>>, app: &mut App) -> Result<()> {
    let mut flash_rx: Option<mpsc::Receiver<FlashProgress>> = None;

    loop {
        terminal.draw(|f| ui(f, app))?;

        // During flashing, poll for progress updates
        if let Some(rx) = &flash_rx {
            while let Ok(progress) = rx.try_recv() {
                match progress {
                    FlashProgress::Writing { written, total } => {
                        app.screen = Screen::Flashing {
                            disk_idx: match app.screen {
                                Screen::Flashing { disk_idx, .. } => disk_idx,
                                _ => unreachable!(),
                            },
                            written, total,
                        };
                    }
                    FlashProgress::Done => {
                        app.screen = Screen::Done;
                        flash_rx = None;
                        break;
                    }
                    FlashProgress::Error(msg) => {
                        app.screen = Screen::Error(msg);
                        flash_rx = None;
                        break;
                    }
                }
            }

            if flash_rx.is_some() {
                if event::poll(std::time::Duration::from_millis(50))? {
                    if let Event::Key(key) = event::read()? {
                        if key.code == KeyCode::Char('c')
                            && key.modifiers.contains(KeyModifiers::CONTROL)
                        {
                            return Ok(());
                        }
                    }
                }
            }
            continue;
        }

        if let Event::Key(key) = event::read().context("reading event")? {
            match &app.screen {
                Screen::Select => match key.code {
                    KeyCode::Char('c') if key.modifiers.contains(KeyModifiers::CONTROL) => {
                        return Ok(());
                    }
                    KeyCode::Char('s') => {
                        drop_to_shell(terminal)?;
                        app.disks = discover_disks()?;
                        if !app.disks.is_empty() && app.list_state.selected().is_none() {
                            app.list_state.select(Some(0));
                        }
                    }
                    KeyCode::Down | KeyCode::Char('j') => app.select_next(),
                    KeyCode::Up | KeyCode::Char('k') => app.select_prev(),
                    KeyCode::Enter if app.selected_disk().is_some() => {
                        let idx = app.list_state.selected().unwrap();
                        app.screen = Screen::Confirm(idx);
                    }
                    _ => {}
                },

                Screen::Confirm(idx) => match key.code {
                    KeyCode::Char('y') | KeyCode::Char('Y') => {
                        let idx = *idx;
                        let image = app.image.clone();
                        let disk_path = app.disks[idx].path.clone();
                        let total = app.image_size.unwrap_or_else(|| {
                            fs::metadata(&image).map(|m| m.len()).unwrap_or(0)
                        });

                        app.screen = Screen::Flashing {
                            disk_idx: idx, written: 0, total,
                        };

                        let (tx, rx) = mpsc::channel();
                        flash_rx = Some(rx);
                        thread::spawn(move || flash_image(&image, &disk_path, total, tx));
                    }
                    _ => {
                        app.screen = Screen::Select;
                    }
                },

                Screen::Done => match key.code {
                    KeyCode::Enter => {
                        Command::new("systemctl").arg("reboot").status().ok();
                        return Ok(());
                    }
                    _ => {}
                },

                Screen::Error(_) => match key.code {
                    KeyCode::Enter => {
                        Command::new("systemctl").arg("reboot").status().ok();
                        return Ok(());
                    }
                    KeyCode::Esc => {
                        app.screen = Screen::Select;
                    }
                    _ => {}
                },

                Screen::Flashing { .. } => {}
            }
        }
    }
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    let disks = discover_disks()?;

    terminal::enable_raw_mode().context("enabling raw mode")?;
    crossterm::execute!(std::io::stdout(), EnterAlternateScreen)?;

    let backend = CrosstermBackend::new(std::io::stdout());
    let mut terminal = Terminal::new(backend).context("creating terminal")?;
    let mut app = App::new(cli, disks);

    let result = run(&mut terminal, &mut app);

    terminal::disable_raw_mode()?;
    crossterm::execute!(std::io::stdout(), LeaveAlternateScreen)?;

    result
}
