import 'dart:async';

import 'package:flutter/services.dart';

/// Service to receive hardware button events from native Android code.
///
/// Wear OS watches have hardware buttons (stem buttons) that can be intercepted.
/// This service provides a stream of button press events.
class HardwareButtonService {
  static const _channel = MethodChannel('com.jellywear.jellyfin_wear_os/hardware_buttons');

  static final _stemButtonController = StreamController<int>.broadcast();

  /// Stream of stem button press events.
  ///
  /// Button numbers:
  /// - 1: STEM_1 (secondary button, most common)
  /// - 2: STEM_2 (tertiary button, some watches)
  /// - 3: STEM_3 (quaternary button, rare)
  static Stream<int> get stemButtonEvents => _stemButtonController.stream;

  /// Initialize the service. Call once at app startup.
  static void initialize() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onStemButton') {
        final button = call.arguments['button'] as int?;
        if (button != null) {
          _stemButtonController.add(button);
        }
      }
    });
  }

  /// Dispose resources. Call on app shutdown if needed.
  static void dispose() {
    _stemButtonController.close();
  }
}
