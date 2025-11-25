import 'package:flutter/services.dart';
import 'dart:async';

class VolumeButtonService {
  static const MethodChannel _channel = MethodChannel('com.barm.control/volume');
  static const EventChannel _eventChannel = EventChannel('com.barm.control/volume_events');
  
  StreamSubscription? _subscription;
  Function(String, bool)? _onVolumeButtonEvent;
  
  /// Start listening to volume button events
  /// onVolumeButtonEvent callback receives button ('up' or 'down') and isPressed (true=down, false=up)
  void startListening(Function(String, bool) onVolumeButtonEvent) {
    _onVolumeButtonEvent = onVolumeButtonEvent;
    
    _subscription = _eventChannel.receiveBroadcastStream().listen(
      (event) {
        if (event is Map) {
          final button = event['button'] as String?;
          final isPressed = event['pressed'] as bool?;
          if (button != null && isPressed != null) {
            _onVolumeButtonEvent?.call(button, isPressed);
          }
        }
      },
      onError: (error) {
        print('Volume button error: $error');
      },
    );
    
    // Enable volume button interception
    _channel.invokeMethod('enableVolumeButtons');
  }
  
  /// Stop listening to volume button events
  void stopListening() {
    _subscription?.cancel();
    _subscription = null;
    _onVolumeButtonEvent = null;
    
    // Disable volume button interception
    _channel.invokeMethod('disableVolumeButtons');
  }
  
  void dispose() {
    stopListening();
  }
}
