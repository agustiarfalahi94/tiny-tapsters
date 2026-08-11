import 'dart:math' as math;

/// Decides, frame by frame, whether the microphone is hearing a voice.
///
/// **Why the app needs its own.** The recogniser has opinions about when
/// somebody stopped talking, but none of them are about silence. The package's
/// `pauseFor` stops the session N ms after the transcribed *text last changed*,
/// which is a different thing entirely: a child who is still speaking while the
/// recogniser's guess happens to be stable gets cut off mid-sentence, and the
/// words spoken during the restart are gone. Android's own endpointing is
/// tuned for adults dictating, not for a four-year-old thinking.
///
/// So the app listens to the sound level itself. That stream is raw `rmsdB`
/// from Android — roughly −2 dB in a quiet room up to about 10 dB for close
/// speech. (The screen used to `clamp(0, 1)` it for a UI pulse, which threw
/// away almost all of the range.)
///
/// Thresholds are **relative to a measured floor**, never absolute: what counts
/// as quiet depends on the room, the phone and how far away the child is
/// holding it, and an absolute dB number that works on one device is wrong on
/// the next.
class VadGate {
  VadGate({
    this.calibrationFrames = 4,
    this.onsetDb = 3.0,
    this.releaseDb = 1.5,
    this.onsetFrames = 2,
    this.floorAlpha = 0.05,
  });

  /// Frames used to seed the noise floor before any decision is made.
  final int calibrationFrames;

  /// How far above the floor a frame must sit to start counting as voice.
  ///
  /// Speech runs 6–12 dB over a room's floor at arm's length. Three is
  /// comfortably under that and comfortably over air-conditioning drift.
  final double onsetDb;

  /// How far above the floor a frame must stay to *keep* counting as voice.
  ///
  /// Lower than [onsetDb] on purpose. A single threshold chatters on every
  /// syllable boundary, and each flicker would reset the silence clock.
  final double releaseDb;

  /// Consecutive loud frames needed to declare voice. Rejects a finger tap or
  /// a door, both of which are one frame; no pair of syllables is that short.
  final int onsetFrames;

  /// How fast the floor follows a room that is getting noisier. Applied on
  /// silent frames only, so sustained speech cannot drag the floor up under
  /// itself and mute the speaker.
  final double floorAlpha;

  final List<double> _calibration = [];
  double _floor = 0;
  int _loudRun = 0;
  bool _voice = false;
  bool _everVoice = false;
  double _lastLevel = 0;

  /// True until enough frames have arrived to trust the floor.
  bool get isCalibrating => _calibration.length < calibrationFrames;

  /// True while the most recent frames read as somebody speaking.
  bool get isVoice => _voice;

  /// True if a voice has been heard at any point since the last [reset].
  ///
  /// This is what separates "nobody is there" from "somebody is talking but
  /// the recogniser cannot make it out" — two failures that deserve very
  /// different responses.
  bool get heardVoice => _everVoice;

  /// The current noise floor, in the same units as the fed levels.
  double get floor => _floor;

  /// The latest level as 0..1 above the floor, for a level meter.
  ///
  /// Ten dB of headroom over the floor covers the full range of a child
  /// speaking into a phone held in front of them.
  double get normalised =>
      ((_lastLevel - _floor) / 10.0).clamp(0.0, 1.0).toDouble();

  void reset() {
    _calibration.clear();
    _floor = 0;
    _loudRun = 0;
    _voice = false;
    _everVoice = false;
    _lastLevel = 0;
  }

  /// Feeds one level sample. Returns whether the gate now reads as voice.
  bool feed(double level) {
    _lastLevel = level;

    if (isCalibrating) {
      _calibration.add(level);
      if (isCalibrating) return false;
      // Median, not mean: one door slam during calibration would drag a mean
      // floor up far enough to make the child inaudible for the whole turn.
      final sorted = [..._calibration]..sort();
      _floor = sorted[sorted.length ~/ 2];
      return false;
    }

    final over = level - _floor;
    if (_voice) {
      // Hysteresis: it takes less to stay speaking than it took to start.
      if (over >= releaseDb) {
        return true;
      }
      _voice = false;
      _loudRun = 0;
    } else if (over >= onsetDb) {
      _loudRun++;
      if (_loudRun >= onsetFrames) {
        _voice = true;
        _everVoice = true;
        return true;
      }
      // Mid-onset: not yet voice, but do not let the floor chase the speech.
      return false;
    } else {
      _loudRun = 0;
    }

    // Quiet frame: let the floor drift toward the room.
    _floor = _floor * (1 - floorAlpha) + level * floorAlpha;
    return false;
  }

  /// Frames per second the caller should feed, matching Android's rms cadence.
  static const tick = Duration(milliseconds: 100);

  /// Clamps a raw level into something a meter can draw, without pretending
  /// the underlying value was ever 0..1.
  static double meterOf(double normalised) => math.max(0.02, normalised);
}
