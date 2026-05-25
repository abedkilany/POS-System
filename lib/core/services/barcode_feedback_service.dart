import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

import 'local_database_service.dart';

class BarcodeFeedbackSettings {
  const BarcodeFeedbackSettings({
    required this.soundEnabled,
    required this.vibrationEnabled,
    required this.volume,
  });

  static const BarcodeFeedbackSettings defaults = BarcodeFeedbackSettings(
    soundEnabled: true,
    vibrationEnabled: true,
    volume: 0.85,
  );

  final bool soundEnabled;
  final bool vibrationEnabled;
  final double volume;

  BarcodeFeedbackSettings copyWith({
    bool? soundEnabled,
    bool? vibrationEnabled,
    double? volume,
  }) {
    return BarcodeFeedbackSettings(
      soundEnabled: soundEnabled ?? this.soundEnabled,
      vibrationEnabled: vibrationEnabled ?? this.vibrationEnabled,
      volume: (volume ?? this.volume).clamp(0.0, 1.0).toDouble(),
    );
  }
}

class BarcodeFeedbackService {
  BarcodeFeedbackService._();

  static const String _soundEnabledKey = 'barcode_feedback_sound_enabled_v1';
  static const String _vibrationEnabledKey = 'barcode_feedback_vibration_enabled_v1';
  static const String _volumeKey = 'barcode_feedback_volume_v1';
  static const Duration cooldown = Duration(milliseconds: 650);
  static const String _soundAsset = 'sounds/beep.wav';

  static final AudioPlayer _player = AudioPlayer(playerId: 'ventio_barcode_feedback');
  static DateTime? _lastFeedbackAt;
  static Future<void>? _activePlayback;

  static BarcodeFeedbackSettings loadSettings() {
    final soundRaw = LocalDatabaseService.getString(_soundEnabledKey);
    final vibrationRaw = LocalDatabaseService.getString(_vibrationEnabledKey);
    final volumeRaw = LocalDatabaseService.getString(_volumeKey);

    return BarcodeFeedbackSettings(
      soundEnabled: soundRaw == null ? BarcodeFeedbackSettings.defaults.soundEnabled : soundRaw == 'true',
      vibrationEnabled: vibrationRaw == null ? BarcodeFeedbackSettings.defaults.vibrationEnabled : vibrationRaw == 'true',
      volume: double.tryParse(volumeRaw ?? '')?.clamp(0.0, 1.0).toDouble() ?? BarcodeFeedbackSettings.defaults.volume,
    );
  }

  static Future<void> saveSettings(BarcodeFeedbackSettings settings) async {
    await LocalDatabaseService.setString(_soundEnabledKey, settings.soundEnabled.toString());
    await LocalDatabaseService.setString(_vibrationEnabledKey, settings.vibrationEnabled.toString());
    await LocalDatabaseService.setString(_volumeKey, settings.volume.toStringAsFixed(2));
  }

  static bool get canPlayNow {
    final last = _lastFeedbackAt;
    return last == null || DateTime.now().difference(last) >= cooldown;
  }

  static Future<bool> play({bool force = false}) async {
    if (!force && !canPlayNow) return false;
    _lastFeedbackAt = DateTime.now();

    final settings = loadSettings();
    var soundPlayed = false;

    if (settings.soundEnabled) {
      try {
        await _activePlayback;
        await _player.stop();
        await _player.setVolume(settings.volume);
        _activePlayback = _player.play(AssetSource(_soundAsset));
        await _activePlayback;
        soundPlayed = true;
      } catch (_) {
        soundPlayed = false;
      }
    }

    if (settings.vibrationEnabled || !soundPlayed) {
      await _vibrateFallback();
    }

    return soundPlayed;
  }

  static Future<void> _vibrateFallback() async {
    try {
      await HapticFeedback.mediumImpact();
    } catch (_) {
      try {
        await HapticFeedback.vibrate();
      } catch (_) {
        // Some desktop/web targets do not support haptic feedback.
      }
    }
  }
}
