const service_name = "pm:app";

pub const LaunchFlags = packed struct(u32) {
    normal_application: bool = true,
    load_exheader_dependencies: bool = true,
    publish_termination_srv_notification: bool = false,
    queue_execution: bool = false,
    notification_offset: u4 = 0,
    _unused0: u8,
    use_update_title: bool = false,
    _unused1: u15 = 0,
};
