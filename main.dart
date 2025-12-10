import React, { useState, useEffect, useCallback } from 'react';
import { initializeApp } from 'firebase/app';
import { 
  getAuth, 
  signInAnonymously, 
  signInWithCustomToken, 
  onAuthStateChanged 
} from 'firebase/auth';
import { 
  getFirestore, 
  doc, 
  setDoc, 
  onSnapshot, 
  collection,
  getDoc,
  setLogLevel
} from 'firebase/firestore';
import { FileDown, Upload, Download, Loader2, RefreshCw } from 'lucide-react';

// --- Global Variable Initialization ---
// These variables are provided by the canvas environment for Firebase access.
const appId = typeof __app_id !== 'undefined' ? __app_id : 'default-app-id';
const firebaseConfig = typeof __firebase_config !== 'undefined' 
  ? JSON.parse(__firebase_config) 
  : { /* Mock Config for Local Development */ };

// Set Firestore log level for debugging
setLogLevel('debug');

const INITIAL_SETTINGS = {
  timerDuration: 60, // seconds
  volume: 0.8,
  // Add another setting to make the data more realistic
  theme: 'blue', 
  lastBackupDate: null,
};

// Utility function to convert milliseconds to readable time format
const formatTime = (seconds) => {
  const minutes = Math.floor(seconds / 60);
  const remainingSeconds = seconds % 60;
  return `${minutes}:${remainingSeconds.toString().padStart(2, '0')}`;
};

const App = () => {
  const [db, setDb] = useState(null);
  const [auth, setAuth] = useState(null);
  const [userId, setUserId] = useState(null);
  const [isAuthReady, setIsAuthReady] = useState(false);
  
  const [settings, setSettings] = useState(INITIAL_SETTINGS);
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState('');
  
  const settingsDocPath = `artifacts/${appId}/users/${userId}/settings/user_settings`;

  // --- 1. FIREBASE INITIALIZATION AND AUTHENTICATION ---
  useEffect(() => {
    try {
      const app = initializeApp(firebaseConfig);
      const firestore = getFirestore(app);
      const authentication = getAuth(app);
      
      setDb(firestore);
      setAuth(authentication);

      const unsubscribe = onAuthStateChanged(authentication, async (user) => {
        if (user) {
          setUserId(user.uid);
          console.log("Authenticated user ID:", user.uid);
        } else {
          // If the custom token is not present, sign in anonymously
          console.log("No user found, signing in anonymously.");
          await signInAnonymously(authentication);
          setUserId(authentication.currentUser?.uid || crypto.randomUUID());
        }
        setIsAuthReady(true);
      });

      // Use custom token if provided
      const initialAuthToken = typeof __initial_auth_token !== 'undefined' ? __initial_auth_token : null;
      if (initialAuthToken) {
        signInWithCustomToken(authentication, initialAuthToken)
          .catch(error => {
            console.error("Error signing in with custom token:", error);
          });
      }

      return () => unsubscribe();
    } catch (error) {
      console.error("Firebase Initialization Error:", error);
      setMessage(`Initialization failed: ${error.message}`);
    }
  }, []);

  // --- 2. FIRESTORE REAL-TIME DATA LISTENER (READ) ---
  useEffect(() => {
    if (!isAuthReady || !db || !userId) return;

    const docRef = doc(db, settingsDocPath);
    
    console.log("Setting up snapshot listener for:", settingsDocPath);

    const unsubscribe = onSnapshot(docRef, (docSnap) => {
      if (docSnap.exists()) {
        const loadedSettings = docSnap.data();
        console.log("Settings loaded from Firestore:", loadedSettings);
        setSettings({ ...INITIAL_SETTINGS, ...loadedSettings });
      } else {
        console.log("No settings found, initializing new document.");
        // Initialize if the document doesn't exist
        setDoc(docRef, INITIAL_SETTINGS, { merge: true })
          .then(() => setSettings(INITIAL_SETTINGS))
          .catch(e => console.error("Error initializing settings:", e));
      }
    }, (error) => {
      console.error("Firestore snapshot error:", error);
      setMessage(`Error fetching data: ${error.message}`);
    });

    return () => unsubscribe();
  }, [isAuthReady, db, userId]);


  // --- 3. FIRESTORE DATA WRITER (UPDATE) ---
  const updateSetting = useCallback((key, value) => {
    if (!db || !userId) {
      setMessage("App is not ready. Please wait for authentication.");
      return;
    }
    
    const newSettings = { ...settings, [key]: value };
    setSettings(newSettings);

    const docRef = doc(db, settingsDocPath);
    setDoc(docRef, { [key]: value }, { merge: true })
      .catch(error => {
        console.error("Error updating setting:", error);
        setMessage(`Failed to save setting: ${error.message}`);
      });
  }, [db, userId, settings]);


  // --- 4. EXPORT FUNCTION (BACKUP) ---
  const exportDataToJSON = async () => {
    if (!db || !userId) {
      setMessage("Authentication not complete. Cannot export data.");
      return;
    }
    setLoading(true);
    setMessage('Preparing to export...');
    
    try {
      const docRef = doc(db, settingsDocPath);
      const docSnap = await getDoc(docRef);

      if (!docSnap.exists()) {
        setMessage('No user settings found to export.');
        setLoading(false);
        return;
      }

      const dataToExport = {
        ...docSnap.data(),
        // Add metadata to the backup file
        backupTimestamp: new Date().toISOString(),
        appIdentifier: appId,
        dataType: 'HandsFreeTimerSettings',
      };

      const json = JSON.stringify(dataToExport, null, 2);
      const blob = new Blob([json], { type: 'application/json' });
      const url = URL.createObjectURL(blob);
      const filename = `timer_backup_${new Date().toISOString().slice(0, 10)}.json`;

      // Create a temporary link element to trigger the download
      const a = document.createElement('a');
      a.href = url;
      a.download = filename;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);

      setSettings(prev => ({ ...prev, lastBackupDate: dataToExport.backupTimestamp }));
      updateSetting('lastBackupDate', dataToExport.backupTimestamp);
      setMessage(`Successfully exported settings to ${filename}`);

    } catch (error) {
      console.error("Error during export:", error);
      setMessage(`Export failed: ${error.message}`);
    } finally {
      setLoading(false);
    }
  };

  // --- 5. IMPORT FUNCTION (RESTORE) ---
  const importDataFromJSON = async (event) => {
    if (!db || !userId) {
      setMessage("Authentication not complete. Cannot import data.");
      return;
    }
    setLoading(true);
    setMessage('Reading backup file...');
    
    const file = event.target.files[0];
    if (!file) {
      setLoading(false);
      return;
    }

    try {
      const reader = new FileReader();
      reader.onload = async (e) => {
        try {
          const content = e.target.result;
          const importedData = JSON.parse(content);

          // Basic validation (optional but recommended)
          if (importedData.appIdentifier !== appId || importedData.dataType !== 'HandsFreeTimerSettings') {
            setMessage("Error: This file does not appear to be a valid backup for this application.");
            setLoading(false);
            return;
          }

          // Clean up metadata before writing to Firestore
          delete importedData.backupTimestamp;
          delete importedData.appIdentifier;
          delete importedData.dataType;
          
          const restoreData = {
            ...INITIAL_SETTINGS,
            ...importedData,
            // Update lastRestoreDate metadata
            lastRestoreDate: new Date().toISOString()
          };
          
          const docRef = doc(db, settingsDocPath);
          await setDoc(docRef, restoreData, { merge: true });
          
          setSettings(restoreData); // onSnapshot will also trigger an update, but this makes it instant
          setMessage(`Successfully restored settings from backup! New duration: ${formatTime(restoreData.timerDuration)}`);

        } catch (parseError) {
          console.error("Error parsing JSON:", parseError);
          setMessage("Error: Failed to parse the file content. Ensure it is a valid JSON backup file.");
        } finally {
          setLoading(false);
          event.target.value = null; // Reset file input
        }
      };
      reader.readAsText(file);

    } catch (error) {
      console.error("Error during import process:", error);
      setMessage(`Import failed: ${error.message}`);
      setLoading(false);
    }
  };


  if (!isAuthReady) {
    return (
      <div className="flex items-center justify-center min-h-screen bg-gray-50">
        <Loader2 className="w-8 h-8 animate-spin text-indigo-600" />
        <p className="ml-3 text-lg font-medium text-indigo-600">Connecting to Timer Service...</p>
      </div>
    );
  }

  return (
    <div className={`min-h-screen p-4 sm:p-8 bg-${settings.theme}-50 transition-colors duration-500`}>
      <script src="https://cdn.tailwindcss.com"></script>
      <div className="max-w-xl mx-auto space-y-8 p-6 bg-white shadow-xl rounded-xl">
        
        {/* Header */}
        <header className="text-center">
          <h1 className="text-3xl font-extrabold text-gray-900">Hands-Free Timer</h1>
          <p className="text-sm text-gray-500">User ID: <span className="font-mono text-xs break-all">{userId}</span></p>
        </header>

        {/* Message Alert */}
        {message && (
          <div className="p-3 text-sm font-medium rounded-lg text-indigo-700 bg-indigo-100" role="alert">
            {message}
          </div>
        )}

        {/* Timer Settings Card */}
        <section className="p-5 border border-indigo-200 rounded-lg space-y-4 shadow-md">
          <h2 className="text-xl font-semibold text-indigo-600 flex items-center">
            <RefreshCw className="w-5 h-5 mr-2"/> Current Settings
          </h2>
          
          {/* Duration Slider */}
          <div>
            <label htmlFor="duration" className="block text-sm font-medium text-gray-700 mb-2">
              Timer Duration: <span className="font-bold text-indigo-600">{formatTime(settings.timerDuration)}</span>
            </label>
            <input
              id="duration"
              type="range"
              min="30"
              max="600"
              step="30"
              value={settings.timerDuration}
              onChange={(e) => updateSetting('timerDuration', parseInt(e.target.value))}
              className={`w-full h-2 bg-indigo-100 rounded-lg appearance-none cursor-pointer range-lg accent-indigo-600`}
            />
          </div>

          {/* Volume Slider */}
          <div>
            <label htmlFor="volume" className="block text-sm font-medium text-gray-700 mb-2">
              Volume: <span className="font-bold text-indigo-600">{(settings.volume * 100).toFixed(0)}%</span>
            </label>
            <input
              id="volume"
              type="range"
              min="0"
              max="1"
              step="0.1"
              value={settings.volume}
              onChange={(e) => updateSetting('volume', parseFloat(e.target.value))}
              className={`w-full h-2 bg-indigo-100 rounded-lg appearance-none cursor-pointer range-lg accent-indigo-600`}
            />
          </div>
          
          {/* Theme Selector */}
          <div>
            <label htmlFor="theme" className="block text-sm font-medium text-gray-700 mb-2">
              App Theme:
            </label>
            <select
              id="theme"
              value={settings.theme}
              onChange={(e) => updateSetting('theme', e.target.value)}
              className="mt-1 block w-full pl-3 pr-10 py-2 text-base border-gray-300 focus:outline-none focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm rounded-md"
            >
              <option value="blue">Blue (Default)</option>
              <option value="emerald">Emerald</option>
              <option value="purple">Purple</option>
              <option value="slate">Slate</option>
            </select>
          </div>
          
        </section>


        {/* Backup and Restore Section */}
        <section className="p-5 border border-gray-300 rounded-lg space-y-4 shadow-md bg-gray-50">
          <h2 className="text-xl font-semibold text-gray-800 flex items-center">
            <FileDown className="w-5 h-5 mr-2"/> Data Backup & Restore
          </h2>

          {/* Export/Backup Button */}
          <button
            onClick={exportDataToJSON}
            disabled={loading}
            className="w-full flex items-center justify-center px-4 py-2 border border-transparent text-sm font-medium rounded-lg text-white bg-green-600 hover:bg-green-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-green-500 disabled:opacity-50 transition duration-150"
          >
            {loading ? <Loader2 className="w-5 h-5 mr-2 animate-spin" /> : <Download className="w-5 h-5 mr-2" />}
            Export Settings to JSON
          </button>
          <p className="text-xs text-gray-500 text-center">
            {settings.lastBackupDate 
              ? `Last successful backup: ${new Date(settings.lastBackupDate).toLocaleDateString()} at ${new Date(settings.lastBackupDate).toLocaleTimeString()}`
              : 'No backup recorded yet.'}
          </p>

          <div className="relative border-t pt-4 border-gray-200">
            {/* Import/Restore Input */}
            <label 
              htmlFor="file-upload" 
              className="w-full flex items-center justify-center px-4 py-2 border border-gray-400 text-sm font-medium rounded-lg text-gray-700 bg-white hover:bg-gray-100 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 cursor-pointer disabled:opacity-50 transition duration-150"
            >
              {loading ? <Loader2 className="w-5 h-5 mr-2 animate-spin" /> : <Upload className="w-5 h-5 mr-2" />}
              Restore Settings from JSON
            </label>
            <input
              id="file-upload"
              type="file"
              accept=".json"
              onChange={importDataFromJSON}
              disabled={loading}
              className="sr-only"
            />
            <p className="text-xs text-gray-500 mt-1 text-center">
              Uploading a file will overwrite your current settings.
            </p>
          </div>
        </section>
        
      </div>
    </div>
  );
};

export default App;
