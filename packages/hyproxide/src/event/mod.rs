//! The events of Hyprland, read from its event socket.
//!
//! [`subscribe`] connects to the event socket and returns the [`Events`] that
//! Hyprland sends from the moment it accepts the connection. It accepts it in
//! its event loop after `subscribe` returned, so an event of that short time
//! in between does not arrive. Hyprland sends nothing to mark the start, and
//! replays nothing. Each line Hyprland writes arrives as one [`Event`] with
//! typed fields, also a line split across reads.
//!
//! Hyprland closes the connection of a program once 64 events wait for it
//! that its socket did not take, and [`Events::next`] then returns
//! [`Error::EventsClosed`](crate::Error::EventsClosed): keep calling it
//! (<https://github.com/hyprwm/Hyprland/blob/v0.57.1/src/ipc/s2/Unix.cpp>,
//! `MAX_QUEUED_EVENTS`, checked 2026-11-08).
//!
//! Hyprland sends most events twice, right after each other: first in an
//! older form, then in a newer one whose name ends in `v2`, and which often
//! carries more. Both arrive. The variants of the older forms end in `V1`.
//!
//! Hyprland joins the fields of an event with commas and escapes no comma
//! inside them. A field reads exactly when every other field of its event
//! cannot hold a comma, such as an address or a number. When a line has
//! more commas than separators and two of its fields can hold them, such as
//! the class and the title of a window, Hyprland gives no way to tell where
//! one ends: the line arrives as [`Event::Unknown`], except an opened window,
//! which keeps its address in [`Event::WindowOpenedUndivided`].
//!
//! Hyprland cuts the data of a line after [`DATA_LIMIT`] bytes, so a long
//! title or other text arrives cut, and a line cut inside a character is not
//! UTF-8 and arrives as [`Event::Unknown`].
//!
//! The stream ends only when the event socket closes or a read fails, never
//! because of a line it does not read.

mod line;
mod stream;

use crate::address::Address;
use crate::monitor::MonitorId;
use crate::workspace::{WorkspaceAddress, WorkspaceId, WorkspaceRef};

pub use line::DATA_LIMIT;
pub use stream::{Events, subscribe};

/// Something that happened in Hyprland, by the name of the line it arrived
/// in
/// (<https://github.com/hyprwm/Hyprland/blob/v0.57.1/src/ipc/s2/S2.cpp> and
/// its callers, checked 2026-11-08).
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Event {
    /// `openwindow`: a window was mapped.
    WindowOpened {
        window: Address,
        workspace: WorkspaceAddress,
        class: String,
        title: String,
    },
    /// `openwindow` whose workspace, class and title cannot be told apart,
    /// because its data has more commas than separate them: a comma in the
    /// title, the class or the name of the workspace.
    WindowOpenedUndivided {
        window: Address,
        /// Everything after the address and its comma, as Hyprland sent it.
        fields: String,
    },
    /// `closewindow`: a window was unmapped.
    WindowClosed(Address),
    /// `movewindow`, the older form of [`Event::WindowMoved`].
    WindowMovedV1 {
        window: Address,
        workspace: WorkspaceAddress,
    },
    /// `movewindowv2`: a window moved to another workspace.
    WindowMoved {
        window: Address,
        workspace: WorkspaceRef,
    },
    /// `windowtitle`, the older form of [`Event::WindowTitleChanged`].
    WindowTitleChangedV1(Address),
    /// `windowtitlev2`: a window changed its title.
    WindowTitleChanged { window: Address, title: String },
    /// `activewindow`, the older form of [`Event::ActiveWindowChanged`]. Both
    /// fields are empty when no window has focus, as they are for a focused
    /// window without class and title.
    ActiveWindowChangedV1 { class: String, title: String },
    /// `activewindowv2`: another window has focus, or none. Hyprland also
    /// sends it when the focused window changes its title or class.
    ActiveWindowChanged(Option<Address>),
    /// `urgent`: a window asks for attention.
    WindowUrgent(Address),
    /// `fullscreen`: the focused window entered or left fullscreen or
    /// maximized state.
    FullscreenChanged(bool),
    /// `changefloatingmode`: a window started or stopped floating.
    FloatingChanged { window: Address, floating: bool },
    /// `pin`: a window was pinned to all workspaces, or no longer is.
    PinnedChanged { window: Address, pinned: bool },
    /// `minimized`: a window asked to be minimized or restored.
    MinimizedChanged { window: Address, minimized: bool },
    /// `bell`: a window rang the bell, or a surface that is no window.
    Bell(Option<Address>),
    /// `kill`: a window was killed in kill mode.
    WindowKilled(Address),
    /// `togglegroup`: a group was formed, with `window` as its first member,
    /// or dissolved, with `window` as its head.
    GroupToggled { window: Address, formed: bool },
    /// `moveintogroup`: a window moved into a group.
    WindowMovedIntoGroup(Address),
    /// `moveoutofgroup`: a window moved out of a group.
    WindowMovedOutOfGroup(Address),
    /// `lockgroups`: the groups were locked or unlocked.
    GroupsLockChanged(bool),
    /// `workspace`, the older form of [`Event::WorkspaceChanged`].
    WorkspaceChangedV1(WorkspaceAddress),
    /// `workspacev2`: a monitor shows another workspace, and the focus went
    /// along. Hyprland sends nothing for a change without focus, nor for
    /// special workspaces.
    WorkspaceChanged(WorkspaceRef),
    /// `createworkspace`, the older form of [`Event::WorkspaceCreated`].
    WorkspaceCreatedV1(WorkspaceAddress),
    /// `createworkspacev2`
    WorkspaceCreated(WorkspaceRef),
    /// `destroyworkspace`, the older form of [`Event::WorkspaceDestroyed`].
    WorkspaceDestroyedV1(WorkspaceAddress),
    /// `destroyworkspacev2`
    WorkspaceDestroyed(WorkspaceRef),
    /// `renameworkspace`: a workspace got another name to show. Hyprland
    /// does not rename special workspaces.
    WorkspaceRenamed(WorkspaceRef),
    /// `changeworkspaceid`: a numbered workspace got another number, which
    /// is now also its address.
    WorkspaceIdChanged {
        previous: WorkspaceId,
        current: WorkspaceId,
    },
    /// `moveworkspace`, the older form of [`Event::WorkspaceMoved`].
    WorkspaceMovedV1 {
        workspace: WorkspaceAddress,
        monitor: String,
    },
    /// `moveworkspacev2`: a workspace moved to another monitor.
    WorkspaceMoved {
        workspace: WorkspaceRef,
        monitor: String,
    },
    /// `activespecial`, the older form of
    /// [`Event::SpecialWorkspaceChanged`].
    SpecialWorkspaceChangedV1 {
        workspace: WorkspaceAddress,
        monitor: String,
    },
    /// `activespecialv2`: a monitor shows another special workspace, or
    /// none.
    SpecialWorkspaceChanged {
        workspace: WorkspaceRef,
        monitor: String,
    },
    /// `focusedmon`, the older form of [`Event::MonitorFocused`]. Hyprland
    /// writes `?` both for a monitor without workspace and for the workspace
    /// named `?`, so such a line arrives as [`Event::Unknown`].
    MonitorFocusedV1 {
        monitor: String,
        workspace: WorkspaceAddress,
    },
    /// `focusedmonv2`: another monitor has focus, with its active
    /// workspace, if it has one.
    MonitorFocused {
        monitor: String,
        workspace: WorkspaceAddress,
    },
    /// `monitoradded`, the older form of [`Event::MonitorAdded`].
    MonitorAddedV1(String),
    /// `monitoraddedv2`: a monitor was added, also one without hardware.
    MonitorAdded {
        id: MonitorId,
        name: String,
        /// Make, model and serial, as far as known, without commas.
        description: String,
    },
    /// `monitorremoved`, the older form of [`Event::MonitorRemoved`].
    MonitorRemovedV1(String),
    /// `monitorremovedv2`: a monitor was removed. Hyprland sends nothing
    /// while it shuts down.
    MonitorRemoved {
        id: MonitorId,
        name: String,
        /// See [`Event::MonitorAdded`].
        description: String,
    },
    /// `openlayer`: a layer surface was mapped, by its namespace.
    LayerOpened(String),
    /// `closelayer`: a layer surface was unmapped, by its namespace.
    LayerClosed(String),
    /// `activelayout`: a keyboard switched its layout.
    KeyboardLayoutChanged {
        /// The name of the keyboard, lowercase, with `-` for spaces and
        /// commas.
        keyboard: String,
        layout: String,
    },
    /// `submap`: another submap is active, or none.
    SubmapChanged(Option<String>),
    /// `screencast`, the older form of [`Event::ScreencastChanged`].
    ScreencastChangedV1 {
        active: bool,
        source: ScreencastSource,
    },
    /// `screencastv2`: a screencast started or stopped.
    ScreencastChanged {
        active: bool,
        target: ScreencastTarget,
    },
    /// `configreloaded`
    ConfigReloaded,
    /// `custom`: the text a configuration or a program passed to the
    /// dispatcher `hl.dsp.event`.
    Custom(String),
    /// A line this library does not read into one of the events above, as
    /// Hyprland sent it: an event newer than this library, or one whose
    /// data does not have the form Hyprland 0.57.1 writes, cannot be split
    /// exactly, or is not UTF-8. The name is the text before the first
    /// `>>`, the whole line when it has none.
    Unknown { name: Vec<u8>, data: Vec<u8> },
}

/// What a screencast shows, as [`Event::ScreencastChangedV1`] tells it.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ScreencastSource {
    Monitor,
    Window,
    Region,
    Workspace,
}

/// What a screencast shows, as [`Event::ScreencastChanged`] tells it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ScreencastTarget {
    /// A whole monitor, by its name.
    Monitor(String),
    /// A region of a monitor, by the name of the monitor.
    Region(String),
    /// A window, by its title, the only thing Hyprland tells of it.
    Window {
        title: String,
    },
    Workspace(WorkspaceAddress),
}

#[cfg(test)]
mod tests;
