
import 'dart:async';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:just_audio/just_audio.dart';

// --- Global Variables for the Background Task ---
HAN SOLO
// These need to be top-level or static to be accessible by the background isolate.
final AudioPlayer _audioPlayer = AudioPlayer();
StreamSubscription? _proximityListener;
StreamSubscription? _timerSubscription;

int _timerDuration = 60; // Default, will be updated by the main app
int _remainingTime = 60;
double _volume = 0.8;

// --- The Main Background Task Handler ---
// This class will be instantiated by the flutter_foreground_task package.
class MyTaskHandler extends TaskHandler {

  @override
  Future<void> onStart(DateTime timestamp, SendPort? sendPort) async {
    // Initialize the audio player for the background task
    await _initAudioPlayer();

    // Start listening to the proximity sensor
    _initProximitySensor();
  }

  @override
  Future<void> onEvent(DateTime timestamp, SendPort? sendPort) async {
    // This method is called by the main app to update the background task.
    // We can receive data from the main app here.
    FlutterForegroundTask.getData<int>(key: 'timerDuration').then((duration) {
      if (duration != null) {
        _timerDuration = duration;
      }
    });

     FlutterForegroundTask.getData<double>(key: 'volume').then((vol) {
      if (vol != null) {
        _volume = vol;
      }
    });
  }

  @override
  Future<void> onDestroy(DateTime timestamp, SendPort? sendPort) async {
    // Clean up resources when the task is stopped.
    _proximityListener?.cancel();
    _timerSubscription?.cancel();
    await _audioPlayer.dispose();
  }

  @override
  void onRepeatEvent(DateTime timestamp, SendPort? sendPort) {
     // This method is called periodically. We can use it to send data back to the UI.
    FlutterForegroundTask.updateService(
      notificationText: 'Remaining Time: ${_formatTime(_remainingTime)}',
    );
    sendPort?.send(_remainingTime); // Send the remaining time to the UI
  }

  // --- Helper Methods for the Background Task ---

  Future<void> _initAudioPlayer() async {
    try {
      await _audioPlayer.setAsset('assets/alarm.mp3');
    } catch (e) {
      print("Error loading audio file in background: $e");
    }
  }

  void _initProximitySensor() {
    bool isNear = false; // Local state for the sensor
    _proximityListener = proximityEvents.listen((ProximityEvent event) {
      final wasNear = isNear;
      isNear = event.isNear;

      if (wasNear && !isNear) {
        print("BACKGROUND WAVE DETECTED! Resetting timer.");
        _resetTimer();
      }
    });
  }

  void _startTimer() {
    _remainingTime = _timerDuration;
    _timerSubscription?.cancel();
    _timerSubscription = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingTime > 0) {
        _remainingTime--;
      } else {
        _handleTimerCompletion();
      }
    });
  }

  void _resetTimer() {
    _timerSubscription?.cancel();
    _remainingTime = _timerDuration;
    _startTimer(); // Immediately restart after a wave
  }

  void _handleTimerCompletion() {
    _timerSubscription?.cancel();
    print("BACKGROUND TIMER FINISHED!");
    
    _audioPlayer.setVolume(_volume);
    _audioPlayer.seek(Duration.zero);
    _audioPlayer.play();

    // Stop the timer loop, wait for the next wave
     _timerSubscription?.cancel();
  }

  String _formatTime(int seconds) {
    final minutes = (seconds / 60).floor().toString().padLeft(2, '0');
    final remainingSeconds = (seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$remainingSeconds';
  }
}
