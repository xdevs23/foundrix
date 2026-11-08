#![forbid(unsafe_code)]

mod client;
mod daemon;
mod error;
mod events;
mod ipc;
mod layout;
mod monitor_registry;
mod plan;
#[cfg(test)]
mod recorded;
mod server;
mod virtual_workspace;
mod window;
mod workspace;

use std::env;
use std::process::ExitCode;

use clap::{Parser, Subcommand};
use tracing_subscriber::filter::LevelFilter;
use tracing_subscriber::layer::SubscriberExt;
use tracing_subscriber::util::SubscriberInitExt;
use tracing_subscriber::{EnvFilter, reload};

use crate::error::{Error, Result};
use crate::ipc::{CollapseMode, Command, DebugLogging, Direction};
use crate::virtual_workspace::VirtualWorkspace;

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
        workspace: VirtualWorkspace,
    },
    /// Move active window to virtual workspace and switch
    Move {
        /// Virtual workspace number (1-9)
        workspace: VirtualWorkspace,
    },
    /// Switch to next virtual workspace
    Next,
    /// Switch to previous virtual workspace
    Prev,
    /// Swap windows with neighboring monitor (next/prev by physical position)
    Swap {
        /// The monitor to swap with
        direction: Direction,
    },
    /// Collapse windows to current monitor
    Collapse {
        /// The windows to collapse
        mode: CollapseMode,
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
    /// Switch debug logging of the daemon on or off
    Debug { logging: DebugLogging },
}

#[tokio::main]
async fn main() -> ExitCode {
    match run(Cli::parse()).await {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("hypr-workspaced: {error}");
            ExitCode::FAILURE
        }
    }
}

async fn run(cli: Cli) -> Result<()> {
    match cli.command {
        Commands::Daemon {
            on_hypr_ipc_reconnect_restart,
        } => {
            let (filter_layer, reload_handle) = reload::Layer::new(log_filter()?);

            tracing_subscriber::registry()
                .with(filter_layer)
                .with(tracing_subscriber::fmt::layer())
                .init();

            daemon::run(reload_handle, on_hypr_ipc_reconnect_restart).await
        }
        Commands::Switch { workspace } => client::send_command(Command::Switch(workspace)).await,
        Commands::Move { workspace } => client::send_command(Command::MoveTo(workspace)).await,
        Commands::Next => client::send_command(Command::Navigate(Direction::Next)).await,
        Commands::Prev => client::send_command(Command::Navigate(Direction::Prev)).await,
        Commands::Swap { direction } => client::send_command(Command::Swap(direction)).await,
        Commands::Collapse { mode } => client::send_command(Command::Collapse(mode)).await,
        Commands::Assign => client::send_command(Command::Assign).await,
        Commands::Pin { pattern } => {
            let pattern = pattern.join(" ");
            client::send_command(Command::Pin(pattern)).await
        }
        Commands::Unpin { pattern } => {
            let pattern = pattern.join(" ");
            client::send_command(Command::Unpin(pattern)).await
        }
        Commands::Pins => client::send_command(Command::Pins).await,
        Commands::Debug { logging } => client::send_command(Command::Debug(logging)).await,
    }
}

/// The log filter of the daemon from `RUST_LOG`, the info level when the
/// variable is unset or empty.
fn log_filter() -> Result<EnvFilter> {
    let builder = EnvFilter::builder().with_default_directive(LevelFilter::INFO.into());
    let filter = if env::var_os(EnvFilter::DEFAULT_ENV).is_some() {
        builder.try_from_env()
    } else {
        builder.from_env()
    };
    filter.map_err(Error::LogFilter)
}
