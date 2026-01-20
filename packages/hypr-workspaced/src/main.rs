mod client;
mod daemon;
mod error;
mod ipc;
mod workspace;

use clap::{Parser, Subcommand};
use tracing_subscriber::EnvFilter;

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
    Daemon,
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
}

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();

    match cli.command {
        Commands::Daemon => {
            tracing_subscriber::fmt()
                .with_env_filter(
                    EnvFilter::try_from_default_env()
                        .unwrap_or_else(|_| EnvFilter::new("info")),
                )
                .init();

            daemon::run().await
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
    }
}
