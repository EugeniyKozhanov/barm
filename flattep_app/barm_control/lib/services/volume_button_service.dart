import 'package:flutter/services.dart';
import 'dart:async';

class VolumeButtonService {
  static const MethodChannel _channel = MethodChannel('com.barm.control/volume');
  static const EventChannel _eventChannel = EventChannel('com.barm.control/volume_events');
  
  StreamSubscription? _subscription;
  Function(String)? _onVolumeButtonPressed;
  
  /// Start listening to volume button events
  /// onVolumeButtonPressed callback receives 'up' or 'down'
  void startListening(Function(String) onVolumeButtonPressed) {
    _onVolumeButtonPressed = onVolumeButtonPressed;
    
    _subscription = _eventChannel.receiveBroadcastStream().listen(
      (event) {
        if (event is String) {
          _onVolumeButtonPressed?.call(event);
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
    _onVolumeButtonPressed = null;
    
    // Disable volume button interception
    _channel.invokeMethod('disableVolumeButtons');
  }
  
  void dispose() {
    stopListening();
  }
}
