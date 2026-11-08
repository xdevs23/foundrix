//! Answers of Hyprland 0.57.1, recorded in a NixOS VM with two outputs:
//! Virtual-1 at x 0 showing workspace 3 with the focus, and
//! HYPR-WORKSPACED-1 at x 512 showing workspace 13. The windows are tiled,
//! floating, fullscreen, of another class, on the orphan workspace 10, on
//! workspace 23 of no output, on the hidden workspace 5 and on a special
//! workspace, each with a title that says so.

use hyproxide::query::{Client, Monitor};

pub fn clients() -> Vec<Client> {
    serde_json::from_str(include_str!(
        "../testdata/hyprland-answers/clients-two-outputs.json"
    ))
    .unwrap()
}

pub fn monitors() -> Vec<Monitor> {
    serde_json::from_str(include_str!(
        "../testdata/hyprland-answers/monitors-all-two-outputs.json"
    ))
    .unwrap()
}
