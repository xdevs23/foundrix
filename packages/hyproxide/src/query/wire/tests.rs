use serde_json::de::StrRead;

use super::*;

fn json(text: &str) -> serde_json::Deserializer<StrRead<'_>> {
    serde_json::Deserializer::from_str(text)
}

#[test]
fn minus_one_is_none() {
    assert_eq!(minus_one_as_none::<_, u32>(&mut json("-1")).unwrap(), None);
    assert_eq!(
        minus_one_as_none::<_, u32>(&mut json("3")).unwrap(),
        Some(3)
    );
    assert!(minus_one_as_none::<_, u32>(&mut json("-2")).is_err());
    assert_eq!(minus_one_as_no_monitor(&mut json("-1")).unwrap(), None);
    assert_eq!(
        minus_one_as_no_monitor(&mut json("1")).unwrap(),
        Some(MonitorId::new(1))
    );
}

#[test]
fn null_is_an_empty_list() {
    assert_eq!(
        null_as_empty::<_, u8>(&mut json("null")).unwrap(),
        Vec::<u8>::new()
    );
    assert_eq!(
        null_as_empty::<_, u8>(&mut json("[]")).unwrap(),
        Vec::<u8>::new()
    );
    assert_eq!(null_as_empty::<_, u8>(&mut json("[4]")).unwrap(), [4]);
}

#[test]
fn placeholder_texts_are_none() {
    assert_eq!(empty_as_none(&mut json(r#""""#)).unwrap(), None);
    assert_eq!(
        empty_as_none(&mut json(r#""web""#)).unwrap().as_deref(),
        Some("web")
    );
    assert_eq!(unknown_as_none(&mut json(r#""unknown""#)).unwrap(), None);
    assert_eq!(
        unknown_as_none(&mut json(r#""dwindle""#))
            .unwrap()
            .as_deref(),
        Some("dwindle")
    );
    assert_eq!(question_mark_as_none(&mut json(r#""?""#)).unwrap(), None);
    assert_eq!(
        question_mark_as_none(&mut json(r#""DP-1""#))
            .unwrap()
            .as_deref(),
        Some("DP-1")
    );
}

#[test]
fn quoted_values() {
    assert!(quoted_bool(&mut json(r#""true""#)).unwrap());
    assert!(!quoted_bool(&mut json(r#""false""#)).unwrap());
    assert!(quoted_bool(&mut json("true")).is_err());
    assert!(quoted_bool(&mut json(r#""yes""#)).is_err());
    assert_eq!(
        quoted_minus_one_as_none(&mut json(r#""6512""#)).unwrap(),
        Some(6512)
    );
    assert_eq!(
        quoted_minus_one_as_none(&mut json(r#""-1""#)).unwrap(),
        None
    );
    assert!(quoted_minus_one_as_none(&mut json(r#""-2""#)).is_err());
    assert!(quoted_minus_one_as_none(&mut json(r#""many""#)).is_err());
}

#[test]
fn negative_scroll_factor_is_none() {
    assert_eq!(scroll_factor(&mut json("-1.00")).unwrap(), None);
    assert_eq!(scroll_factor(&mut json("1.50")).unwrap(), Some(1.5));
}

#[test]
fn addresses_after_0x() {
    let read = address(&mut json(r#""0x573106b0db30""#)).unwrap();
    assert_eq!(read.get().get(), 0x5731_06b0_db30);
    assert!(address(&mut json(r#""0x0""#)).is_err());
    assert!(address(&mut json(r#""573106b0db30""#)).is_err());
    assert!(address(&mut json(r#""0x573106B0DB30""#)).is_err());
    assert!(optional_bare_address(&mut json(r#""+1a""#)).is_err());
    assert_eq!(optional_address(&mut json(r#""0x0""#)).unwrap(), None);
    assert_eq!(
        optional_address(&mut json(r#""0x1a""#))
            .unwrap()
            .map(|a| a.get().get()),
        Some(0x1a)
    );
    assert_eq!(optional_bare_address(&mut json(r#""0""#)).unwrap(), None);
    assert_eq!(
        optional_bare_address(&mut json(r#""1a""#))
            .unwrap()
            .map(|a| a.get().get()),
        Some(0x1a)
    );
    let grouped = addresses(&mut json(r#"["0x1", "0x2"]"#)).unwrap();
    assert_eq!(
        grouped.iter().map(|a| a.get().get()).collect::<Vec<_>>(),
        [1, 2]
    );
    assert!(addresses(&mut json(r#"["0x0"]"#)).is_err());
}

#[test]
fn stable_ids_are_bare_hex() {
    assert_eq!(
        stable_id(&mut json(r#""18000001""#)).unwrap(),
        StableId(0x1800_0001)
    );
    assert!(stable_id(&mut json(r#""0x18000001""#)).is_err());
}

#[test]
fn numbers_of_identities() {
    assert_eq!(
        fullscreen_state(&mut json("1")).unwrap(),
        FullscreenState::Maximized
    );
    assert_eq!(
        fullscreen_state(&mut json("9")).unwrap(),
        FullscreenState::Unknown(9)
    );
    assert_eq!(
        modifiers(&mut json("65")).unwrap(),
        Modifiers::from_mask(65)
    );
    assert_eq!(monitor_id(&mut json("2")).unwrap(), MonitorId::new(2));
    assert_eq!(null_as_no_monitor(&mut json("null")).unwrap(), None);
    assert_eq!(
        null_as_no_monitor(&mut json("0")).unwrap(),
        Some(MonitorId::new(0))
    );
}

#[test]
fn mirrored_monitor_is_none_or_an_id() {
    assert_eq!(
        quoted_monitor_or_none(&mut json(r#""none""#)).unwrap(),
        None
    );
    assert_eq!(
        quoted_monitor_or_none(&mut json(r#""1""#)).unwrap(),
        Some(MonitorId::new(1))
    );
    assert!(quoted_monitor_or_none(&mut json(r#""DP-1""#)).is_err());
}

#[test]
fn geometry() {
    assert_eq!(
        position_pair(&mut json("[10, -20]")).unwrap(),
        Position { x: 10, y: -20 }
    );
    assert_eq!(
        position_object(&mut json(r#"{"x": 256, "y": 192}"#)).unwrap(),
        Position { x: 256, y: 192 }
    );
    assert_eq!(
        size(&mut json("[2048, 1080]")).unwrap(),
        Size {
            width: 2048,
            height: 1080
        }
    );
}

#[test]
fn modes_have_a_size_and_a_refresh_rate() {
    assert_eq!(
        modes(&mut json(r#"["1920x1080@59.94Hz"]"#)).unwrap(),
        [Mode {
            width: 1920,
            height: 1080,
            refresh_rate_hz: 59.94
        }]
    );
    for malformed in ["1920x1080", "1920@60.00Hz", "1920x@60.00Hz", "axb@60Hz"] {
        let text = format!("[{malformed:?}]");
        assert!(modes(&mut json(&text)).is_err(), "{malformed}");
    }
}

#[test]
fn workspaces_by_kind() {
    let read = |text| workspace(&mut json(text)).unwrap().address;
    assert_eq!(
        read(r#"{"address": "6", "id": 6, "type": "normal", "name": "6"}"#),
        WorkspaceAddress::Numbered(WorkspaceId::try_from(6).unwrap())
    );
    assert_eq!(
        read(r#"{"address": "web", "type": "normal", "name": "Web"}"#),
        WorkspaceAddress::Named(WorkspaceName::try_from("web").unwrap())
    );
    assert_eq!(
        read(r#"{"address": "special:scratch", "type": "special", "name": "special:scratch"}"#),
        WorkspaceAddress::Special("scratch".into())
    );
    assert_eq!(
        read(r#"{"address": "", "type": "", "name": ""}"#),
        WorkspaceAddress::None
    );
    assert_eq!(
        read(r#"{"address": "6", "type": "", "name": ""}"#),
        WorkspaceAddress::None
    );
}

#[test]
fn workspaces_whose_fields_do_not_fit_together_fail() {
    for text in [
        r#"{"address": "0", "id": 0, "type": "normal", "name": "0"}"#,
        r#"{"address": "7", "id": 6, "type": "normal", "name": "6"}"#,
        r#"{"address": "7", "type": "normal", "name": "7"}"#,
        r#"{"address": "", "type": "normal", "name": ""}"#,
        r#"{"address": "scratch", "type": "special", "name": "scratch"}"#,
        r#"{"address": "special:a", "id": 6, "type": "special", "name": "a"}"#,
        r#"{"address": "", "id": 6, "type": "", "name": ""}"#,
    ] {
        assert!(workspace(&mut json(text)).is_err(), "{text}");
    }
}
