//! `cdc:CSN`

pub const service = "cdc:CSN";

pub const Line = zitrus.hardware.i2s.Line;
pub const Gain = zitrus.hardware.codec.i2s.Gain;

session: ClientSession,

pub const open = horizon.services.Methods(@This()).openService;
pub const openWithResult = horizon.services.Methods(@This()).openServiceWithResult;
pub const close = horizon.services.Methods(@This()).close;
pub const send = horizon.services.Methods(@This()).send;
pub const sendWithResult = horizon.services.Methods(@This()).sendWithResult;

// NOTE: Some are provisional names

pub const command = struct {
    /// May return 0xc9403800 (sleeping, nothing changed)
    pub const IgnoreVolumeSliderForceSpeakerOutput = ipc.Command(Id, .ignore_volume_slider_forcing_speaker_output, void, void);
    pub const StopIgnoreVolumeSliderForceSpeakerOutput = ipc.Command(Id, .stop_ignore_volume_slider_force_speaker_output, void, void);
    pub const SetI2sVolume = ipc.Command(Id, .set_i2s_volume, struct {
        line: Line,
        gain: Gain,
    }, void);
    pub const GetI2sVolume = ipc.Command(Id, .get_i2s_volume, Line, Gain);
    pub const SetForceSpeakerOutput = ipc.Command(Id, .set_force_speaker_output, bool, void);
    pub const IsForcingSpeakerOutput = ipc.Command(Id, .is_forcing_speaker_output, bool, bool);
    pub const SetIgnoreVolumeSlider = ipc.Command(Id, .set_ignore_volume_slider, bool, void);
    pub const IsIgnoringVolumeSlider = ipc.Command(Id, .is_ignoring_volume_slider, void, bool);
    pub const GetWakeupCompletedEvent = ipc.Command(Id, .get_wakeup_completed_event, void, horizon.Event);

    pub const Id = enum(u16) {
        ignore_volume_slider_forcing_speaker_output = 0x0001,
        stop_ignore_volume_slider_force_speaker_output,
        set_i2s_volume,
        get_i2s_volume,
        set_force_speaker_output,
        is_forcing_speaker_output,
        set_ignore_volume_slider,
        is_ignoring_volume_slider,
        get_wakeup_completed_event,
    };
};

const CSnd = @This();

const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
const tls = horizon.tls;
const ipc = horizon.ipc;

const ClientSession = horizon.Session.Client;
const ServiceManager = horizon.ServiceManager;
