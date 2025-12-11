
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// This function will be updated with your actual Firebase config
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // TODO: Add your Firebase project's configuration options here.
  // You can get these from the Firebase console.
  await Firebase.initializeApp(
      // options: DefaultFirebaseOptions.currentPlatform, // Uncomment this line after setting up firebase_cli
      );
  runApp(const HandsFreeTimerApp());
}

class HandsFreeTimerApp extends StatelessWidget {
  const HandsFreeTimerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hands-Free Timer',
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        scaffoldBackgroundColor: Colors.grey[50],
        useMaterial3: true,
      ),
      home: const TimerHomePage(),
    );
  }
}

class TimerHomePage extends StatefulWidget {
  const TimerHomePage({super.key});

  @override
  State<TimerHomePage> createState() => _TimerHomePageState();
}

class _TimerHomePageState extends State<TimerHomePage> {
  // --- Firebase & State Variables ---
  User? _user;
  StreamSubscription<DocumentSnapshot>? _settingsListener;

  // Default settings
  int _timerDuration = 60;
  double _volume = 0.8;
  String _theme = 'Blue';
  String? _lastBackupDate;

  bool _loading = true;
  String _message = "Connecting to Firebase...";

  @override
  void initState() {
    super.initState();
    _signInAndLoadData();
  }

  @override
  void dispose() {
    // Cancel the Firestore listener to prevent memory leaks
    _settingsListener?.cancel();
    super.dispose();
  }

  // --- Firebase Authentication & Data Loading ---
  Future<void> _signInAndLoadData() async {
    try {
      // 1. Authenticate Anonymously
      final userCredential = await FirebaseAuth.instance.signInAnonymously();
      _user = userCredential.user;

      if (_user == null) {
        throw Exception("Anonymous sign-in failed.");
      }
      
      setState(() {
        _message = "Authenticated. Loading settings...";
      });

      // 2. Set up Firestore Listener
      final docRef = FirebaseFirestore.instance.collection('users').doc(_user!.uid);
      _settingsListener = docRef.snapshots().listen((snapshot) {
        if (snapshot.exists) {
          final data = snapshot.data()!;
          // Load data from Firestore, use defaults if not present
          setState(() {
            _timerDuration = data['timerDuration'] ?? 60;
            _volume = (data['volume'] ?? 0.8).toDouble();
            _theme = data['theme'] ?? 'Blue';
            _lastBackupDate = data['lastBackupDate'];
            _loading = false;
            _message = "Settings loaded.";
          });
        } else {
          // If no settings exist, create the document with default values
          _initializeSettings(docRef);
        }
      });

    } catch (e) {
      setState(() {
        _message = "Error: ${e.toString()}";
        _loading = false;
      });
    }
  }
  
  Future<void> _initializeSettings(DocumentReference docRef) async {
      await docRef.set({
        'timerDuration': _timerDuration,
        'volume': _volume,
        'theme': _theme,
        'lastBackupDate': null,
      });
      setState(() { _loading = false; _message = "Initial settings created."; });
  }

  // --- Update Setting in Firestore ---
  Future<void> _updateSetting(String key, dynamic value) async {
    if (_user == null) return;
    final docRef = FirebaseFirestore.instance.collection('users').doc(_user!.uid);
    try {
      await docRef.set({key: value}, SetOptions(merge: true));
    } catch (e) {
      // Show a snackbar or message if update fails
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to save setting: $e"))
      );
    }
  }

  // --- UI Build ---
  String _formatTime(int seconds) {
    final minutes = (seconds / 60).floor().toString().padLeft(2, '0');
    final remainingSeconds = (seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$remainingSeconds';
  }

  void _exportData() {
    // TODO: Implement JSON export logic
    setState(() {
      _message = "Export functionality coming soon!";
    });
  }

  void _importData() {
    // TODO: Implement JSON import logic
    setState(() {
      _message = "Import functionality coming soon!";
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hands-Free Timer'),
        elevation: 4,
        shadowColor: Theme.of(context).shadowColor,
      ),
      body: _loading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(_message),
                ],
              ),
            )
          : _buildSettingsPage(),
    );
  }

  // --- Main Settings UI ---
  Widget _buildSettingsPage() {
     return SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                elevation: 2,
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Current Settings',
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.indigo),
                      ),
                      const SizedBox(height: 24),
                      
                      Text('Timer Duration: ${_formatTime(_timerDuration)}'),
                      Slider(
                        value: _timerDuration.toDouble(),
                        min: 30,
                        max: 600,
                        divisions: (600 - 30) ~/ 30,
                        onChanged: (value) => setState(() => _timerDuration = value.toInt()),
                        onChangeEnd: (value) => _updateSetting('timerDuration', value.toInt()),
                      ),

                      Text('Volume: ${(_volume * 100).toInt()}%'),
                      Slider(
                        value: _volume,
                        min: 0,
                        max: 1,
                        divisions: 10,
                        onChanged: (value) => setState(() => _volume = value),
                        onChangeEnd: (value) => _updateSetting('volume', value),
                      ),

                       const SizedBox(height: 16),
                       Text('App Theme: $_theme'),
                       DropdownButton<String>(
                        value: _theme,
                        isExpanded: true,
                        items: ['Blue', 'Emerald', 'Purple', 'Slate']
                            .map((label) => DropdownMenuItem(child: Text(label), value: label))
                            .toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _theme = value);
                            _updateSetting('theme', value);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              Card(
                 elevation: 2,
                 clipBehavior: Clip.antiAlias,
                 child: Padding(
                  padding: const EdgeInsets.all(16.0),
                   child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Data Backup & Restore',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.download),
                        label: const Text('Export Settings'),
                        onPressed: _exportData,
                      ),
                      const SizedBox(height: 16),
                       ElevatedButton.icon(
                        icon: const Icon(Icons.upload),
                        label: const Text('Restore Settings'),
                        onPressed: _importData,
                      ),
                    ],
                   ),
                 ),
              )
            ],
          ),
        ),
      );
  }
}
