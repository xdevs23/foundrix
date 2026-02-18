mod client;
mod daemon;
mod error;
mod ipc;
mod window;
mod workspace;

use clap::{Parser, Subcommand};
use tracing_subscriber::layer::SubscriberExt;
use tracing_subscriber::util::SubscriberInitExt;
use tracing_subscriber::{reload, EnvFilter};

use crate::error::Result;
use crate::ipc::{parse_bool_arg, CollapseMode, Command, Direction};

#[derive(Parser)]
#[command(name = "hypr-workspaced")]
#[command(about = "Daemon for synchronized virtual workspaces across Hyprland monitors")]
#[command(version)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Start the daemon (foreground)
    Daemon {
        /// Restart a systemd user service when Hyprland IPC reconnects after disconnection
        #[arg(long)]
        on_hypr_ipc_reconnect_restart: Option<String>,
    },
    /// Switch all monitors to a virtual workspace (1-9)
    Switch {
        /// Virtual workspace number (1-9)
        workspace: u8,
    },
    /// Move active window to virtual workspace and switch
    Move {
        /// Virtual workspace number (1-9)
        workspace: u8,
    },
    /// Switch to next virtual workspace
    Next,
    /// Switch to previous virtual workspace
    Prev,
    /// Swap windows with neighboring monitor (next/prev by physical position)
    Swap {
        /// Direction: 'next' (right) or 'prev' (left)
        direction: String,
    },
    /// Collapse windows to current monitor
    Collapse {
        /// Mode: 'all' (same virtual workspace) or 'invisible' (orphan workspaces only)
        mode: String,
    },
    /// Reassign workspaces to monitors (useful after hotplug)
    Assign,
    /// Pin a window pattern to follow virtual workspace switches
    Pin {
        /// Window pattern (e.g., class:Firefox, title:YouTube)
        pattern: Vec<String>,
    },
    /// Unpin a window pattern
    Unpin {
        /// Window pattern to unpin
        pattern: Vec<String>,
    },
    /// List all pinned window patterns
    Pins,
    /// Toggle debug logging
    Debug {
        /// Enable or disable debug logging (on/off, true/false, 1/0)
        enabled: String,
    },
}


#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();

    match cli.command {
        Commands::Daemon { on_hypr_ipc_reconnect_restart } => {
            let filter = EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| EnvFilter::new("info"));
            let (filter_layer, reload_handle) = reload::Layer::new(filter);

            tracing_subscriber::registry()
                .with(filter_layer)
                .with(tracing_subscriber::fmt::layer())
                .init();

            daemon::run(reload_handle, on_hypr_ipc_reconnect_restart).await
        }
        Commands::Switch { workspace } => {
            let cmd = Command::Switch(Command::validate_workspace(workspace)?);
            client::send_command(cmd).await
        }
        Commands::Move { workspace } => {
            let cmd = Command::MoveTo(Command::validate_workspace(workspace)?);
            client::send_command(cmd).await
        }
        Commands::Next => {
            client::send_command(Command::Navigate(Direction::Next)).await
        }
        Commands::Prev => {
            client::send_command(Command::Navigate(Direction::Prev)).await
        }
        Commands::Swap { direction } => {
            let dir = match direction.as_str() {
                "next" => Direction::Next,
                "prev" => Direction::Prev,
                _ => {
                    eprintln!("Invalid swap direction: {direction}. Use 'next' or 'prev'.");
                    std::process::exit(1);
                }
            };
            client::send_command(Command::Swap(dir)).await
        }
        Commands::Collapse { mode } => {
            let mode = match mode.as_str() {
                "all" => CollapseMode::All,
                "invisible" => CollapseMode::Invisible,
                _ => {
                    eprintln!("Invalid collapse mode: {mode}. Use 'all' or 'invisible'.");
                    std::process::exit(1);
                }
            };
            client::send_command(Command::Collapse(mode)).await
        }
        Commands::Assign => {
            client::send_command(Command::Assign).await
        }
        Commands::Pin { pattern } => {
            let pattern = pattern.join(" ");
            client::send_command(Command::Pin(pattern)).await
        }
        Commands::Unpin { pattern } => {
            let pattern = pattern.join(" ");
            client::send_command(Command::Unpin(pattern)).await
        }
        Commands::Pins => client::send_command_with_output(Command::Pins).await,
        Commands::Debug { enabled } => {
            let enabled = match parse_bool_arg(&enabled) {
                Ok(b) => b,
                Err(e) => {
                    eprintln!("{e}");
                    std::process::exit(1);
                }
            };
            client::send_command(Command::Debug(enabled)).await
        }
    }
}
