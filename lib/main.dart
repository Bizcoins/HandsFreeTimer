
import 'dart:async';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:just_audio/just_audio.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'firebase_options.dart';

// --- Entry Point & Foreground Task Setup ---
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  
  // Initialize and configure the foreground task
  // Note: The 'init' method returns a Future<bool>, so we handle it.
  await _initForegroundTask();

  runApp(const HandsFreeTimerApp());
}

Future<void> _initForegroundTask() async {
    // Defines configurations for the foreground service.
    await FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'hands_free_timer',
        channelName: 'Timer Service',
        channelDescription: 'Allows the timer to run in the background.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        iconData: const NotificationIconData(
          resType: ResourceType.mipmap,
          resPrefix: ResourcePrefix.ic,
          name: 'launcher',
        ),
      ),
      // Corrected: Removed the 'allowsAlert' parameter which is not in this version.
      iosNotificationOptions: const IOSNotificationOptions(
        allowsBadge: true,
        allowsSound: true,
      ),
      foregroundTaskOptions: const ForegroundTaskOptions(
        interval: 5000,
        autoRunOnBoot: true,
        allowWifiLock: true,
      ),
    );
}

// --- The Background Task Entry Point ---
@pragma('vm:entry-point')
void startCallback() {
  // The callback function for starting the foreground task.
  FlutterForegroundTask.setTaskHandler(TimerTaskHandler());
}

// The root widget of the application.
class HandsFreeTimerApp extends StatelessWidget {
  const HandsFreeTimerApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Provides the foreground task context to the rest of the app.
    return const WithForegroundTask(
      child: MaterialApp(
        title: 'Hands-Free Timer',
        theme: ThemeData(primarySwatch: Colors.indigo, useMaterial3: true),
        home: TimerHomePage(),
      ),
    );
  }
}


// --- Main UI Widget ---
class TimerHomePage extends StatefulWidget {
  const TimerHomePage({super.key});

  @override
  State<TimerHomePage> createState() => _TimerHomePageState();
}

class _TimerHomePageState extends State<TimerHomePage> {
  // --- State & Listeners ---
  StreamSubscription? _settingsListener;
  ReceivePort? _receivePort;
  User? _user;

  // Settings
  int _timerDuration = 60;
  double _volume = 0.8;

  // App & Timer State
  bool _loading = true;
  String _message = "Initializing...";
  bool _isNear = false;
  int _remainingTime = 60;
  bool _isTimerRunning = false;

  @override
  void initState() {
    super.initState();
    _signInAndLoadData();
    _requestPermissions();
    _setupTimerStateListener();
  }

  @override
  void dispose() {
    _settingsListener?.cancel();
    _receivePort?.close();
    super.dispose();
  }

  // --- Permissions & Service Control ---
  Future<void> _requestPermissions() async {
    // This is required on Android 13+ to show notifications.
    await FlutterForegroundTask.requestNotificationPermission();
  }

  Future<void> _startForegroundService() async {
    // Corrected: 'isRunningService' is a Future<bool> and must be awaited.
    if (await FlutterForegroundTask.isRunningService) return;
    
    _receivePort = FlutterForegroundTask.receivePort;
    _setupTimerStateListener(); // Re-setup listener after getting the port.

    FlutterForegroundTask.startService(
      notificationTitle: 'Timer is Ready',
      notificationText: 'Wave to start',
      callback: startCallback,
    );
  }

  void _stopForegroundService() {
    FlutterForegroundTask.stopService();
  }

  // --- UI State Synchronization ---
  void _setupTimerStateListener() {
    // Corrected: Check if the receivePort is available.
    _receivePort?.listen((message) {
      if (message is Map<String, dynamic>) {
        setState(() {
          _remainingTime = message['remainingTime'] ?? _remainingTime;
          _isTimerRunning = message['isTimerRunning'] ?? _isTimerRunning;
          _isNear = message['isNear'] ?? _isNear;
        });
      }
    });
  }

  // --- Firebase Logic ---
  Future<void> _signInAndLoadData() async {
      setState(() { _message = "Signing in..."; });
      try {
        UserCredential userCredential = await FirebaseAuth.instance.signInAnonymously();
        _user = userCredential.user;
        setState(() { _message = "Loading settings..."; });
        if (_user != null) {
          DocumentSnapshot settings = await FirebaseFirestore.instance.collection('settings').doc(_user!.uid).get();
          if (settings.exists) {
            final data = settings.data() as Map<String, dynamic>;
            _timerDuration = data['timerDuration'] ?? 60;
            _volume = (data['volume'] ?? 0.8).toDouble();
            _remainingTime = _timerDuration;
          }
        }
      } catch (e) {
        setState(() { _message = "Error: ${e.toString()}"; });
      }
      setState(() { _loading = false; });
  }
  
  Future<void> _updateSetting(String key, dynamic value) async {
    if (_user == null) return;
    await FirebaseFirestore.instance.collection('settings').doc(_user!.uid).set({key: value}, SetOptions(merge: true));
    // Corrected: The method is 'sendData', not 'sendDataToTask'.
    FlutterForegroundTask.sendData({key: value});
  }

  // --- UI Build ---
   String _formatTime(int seconds) => '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(title: const Text('Hands-Free Timer')),
        body: _loading ? _buildLoading() : _buildTimerPage(),
    );
  }
  
  Widget _buildLoading() => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const CircularProgressIndicator(), const SizedBox(height: 16), Text(_message)]));

  Widget _buildTimerPage() {
     return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
            // Timer Display Card
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  children: [
                    Text(_isTimerRunning ? "Timer Running" : "Timer Paused", style: Theme.of(context).textTheme.headlineSmall),
                    Text(_formatTime(_remainingTime), style: Theme.of(context).textTheme.displayLarge),
                    const SizedBox(height: 10),
                    Chip(
                      label: Text(_isNear ? "Sensor: Near" : "Sensor: Far"),
                      backgroundColor: _isNear ? Colors.red.shade100 : Colors.green.shade100,
                    ),
                  ],
                ),
              ),
            ),
            
            // Action Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: _startForegroundService,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('START SERVICE'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                ),
                ElevatedButton.icon(
                  onPressed: _stopForegroundService,
                  icon: const Icon(Icons.stop),
                  label: const Text('STOP SERVICE'),
                   style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                ),
              ],
            ),

            // Settings Expander
            ExpansionTile(
              title: const Text('Settings'),
              children: [
                  ListTile(
                    title: Text("Timer Duration: ${_formatTime(_timerDuration)}"),
                    subtitle: Slider(
                      value: _timerDuration.toDouble(),
                      min: 10,
                      max: 3600,
                      divisions: 359,
                      label: _formatTime(_timerDuration),
                      onChanged: (value) => setState(() => _timerDuration = value.toInt()),
                      onChangeEnd: (value) => _updateSetting('timerDuration', value.toInt()),
                    ),
                  ),
                  ListTile(
                    title: Text("Alarm Volume: ${(_volume * 100).toInt()}%"),
                    subtitle: Slider(
                      value: _volume,
                      min: 0.0,
                      max: 1.0,
                      onChanged: (value) => setState(() => _volume = value),
                      onChangeEnd: (value) => _updateSetting('volume', value),
                    ),
                  ),
              ],
            )
        ],
      ),
    );
  }
}


// --- Background Task Handler Logic ---
class TimerTaskHandler extends TaskHandler {
  // --- State ---
  StreamSubscription? _proximitySubscription;
  Timer? _timer;
  final AudioPlayer _audioPlayer = AudioPlayer();
  SendPort? _sendPort;

  // Settings from UI
  int _timerDuration = 60;
  double _volume = 0.8;

  // Internal Timer State
  int _remainingTime = 60;
  bool _isTimerRunning = false;
  bool _isNear = false;

  @override
  Future<void> onStart(DateTime timestamp, SendPort? sendPort) async {
    _sendPort = sendPort;
    await _audioPlayer.setAsset('assets/alarm.mp3');
    
    // Listen to proximity sensor events
    _proximitySubscription = proximityEvents.listen((ProximityEvent event) {
      final wasNear = _isNear;
      _isNear = event.isNear;
      _updateUI();

      // A "wave" is when the sensor goes from near to far.
      if (wasNear && !_isNear) {
        _resetTimer();
      }
    });
  }

  @override
  Future<void> onEvent(DateTime timestamp, dynamic data) async {
    // Listen for settings changes from the UI
    if (data is Map<String, dynamic>) {
      if (data.containsKey('timerDuration')) {
        _timerDuration = data['timerDuration'];
        if (!_isTimerRunning) {
          _remainingTime = _timerDuration;
          _updateUI(); // Update UI if timer is not running
        }
      }
      if (data.containsKey('volume')) {
        _volume = data['volume'];
      }
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, SendPort? sendPort) async {
    _proximitySubscription?.cancel();
    _timer?.cancel();
    _audioPlayer.dispose();
    await WakelockPlus.disable(); // Use await for async operations
    await FlutterForegroundTask.clearAllData();
  }

  // Corrected: Added the missing onRepeatEvent method to satisfy the abstract class.
  @override
  void onRepeatEvent(DateTime timestamp, SendPort? sendPort) {
    // This event is triggered by the 'interval' in ForegroundTaskOptions.
    // We can use it for periodic updates if needed, but our timer handles that.
  }

  // --- Timer Control (runs in background) ---
  void _startTimer() {
    if (_isTimerRunning) return;
    WakelockPlus.enable();
    _isTimerRunning = true;
    _remainingTime = _timerDuration; // Start from the full duration
    _updateUI();

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_remainingTime > 0) {
        _remainingTime--;
        _updateUI();
      } else {
        _handleTimerCompletion();
      }
    });
  }

  void _resetTimer() {
    if (!_isTimerRunning) {
      _startTimer(); // If timer wasn't running, the wave starts it.
    } else {
      _remainingTime = _timerDuration; // If it was running, the wave just resets it.
      _updateUI();
    }
  }

  void _handleTimerCompletion() {
    _isTimerRunning = false;
    _timer?.cancel();
    WakelockPlus.disable();
    
    _audioPlayer.setVolume(_volume);
    _audioPlayer.seek(Duration.zero);
    _audioPlayer.play();

    _updateUI();

    // After the sound plays, reset the timer display for the next cycle.
    Future.delayed(const Duration(seconds: 3), () {
        _remainingTime = _timerDuration;
        _updateUI();
    });
  }

  // --- UI Communication ---
  void _updateUI() {
    // Send data back to the main UI.
    _sendPort?.send({
      'remainingTime': _remainingTime,
      'isTimerRunning': _isTimerRunning,
      'isNear': _isNear,
    });

    // Also update the persistent notification.
    if (_isTimerRunning) {
      FlutterForegroundTask.updateService(
        notificationTitle: 'Timer Running: ${_formatTime(_remainingTime)}',
        notificationText: 'Wave to reset',
      );
    } else {
       FlutterForegroundTask.updateService(
        notificationTitle: 'Timer Ready',
        notificationText: 'Wave to start. Duration: ${_formatTime(_timerDuration)}',
      );
    }
  }

  // Helper to format time in MM:SS
  String _formatTime(int seconds) => '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
}
