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
use crate::ipc::{Command, Direction};

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
    /// Collapse windows from same virtual workspace to current monitor
    Collapse,
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
        /// Enable or disable debug logging
        #[arg(value_parser = parse_bool_arg)]
        enabled: bool,
    },
}

fn parse_bool_arg(s: &str) -> std::result::Result<bool, String> {
    match s.to_lowercase().as_str() {
        "on" | "true" | "1" => Ok(true),
        "off" | "false" | "0" => Ok(false),
        _ => Err(format!("expected on/off, true/false, or 1/0, got '{s}'")),
    }
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
        Commands::Collapse => {
            client::send_command(Command::Collapse).await
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
        Commands::Debug { enabled } => client::send_command(Command::Debug(enabled)).await,
    }
}
