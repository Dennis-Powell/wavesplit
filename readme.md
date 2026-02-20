# WAV Audio Channel Splitter

PowerShell-Script zum automatischen Aufteilen von Multi-Channel WAV-Dateien (wie sie z.B. vom Behringer X32 erstellt werden) in einzelne Mono-Kanäle mit konfigurierbaren Kanalnamen, paralleler Verarbeitung und optimierten ffmpeg-Parametern.

## 🚀 Features

- **Automatisches Multi-Channel Splitting**: Teilt WAV-Dateien mit bis zu 32 Kanälen in einzelne Mono-Dateien auf
- **Parallele Verarbeitung**: Verarbeitet mehrere Ordner gleichzeitig für maximale Performance
  - PowerShell 7+: Moderne `ForEach-Object -Parallel` Implementierung
  - PowerShell 5.1: Job-basierte Parallelverarbeitung
- **FFmpeg 7+ Optimierung**: Batch-Processing für bis zu 3x schnellere Verarbeitung
- **Konfigurierbare Kanalnamen**: Definiere eigene Namen für jeden Kanal
- **Channel Skipping**: Überspringe ungenutzte Kanäle
- **Flexible Präfixe**: Optional Ordnername als Präfix oder kein Präfix
- **Subfolder-Support**: Optional separate Unterordner für gesplittete Dateien
- **Bit-Depth Konvertierung**: Automatisch oder manuell (16/24/32 Bit)
- **Intelligente Erkennung**: Überspringt bereits verarbeitete Ordner

---

## 📦 Voraussetzungen

### Software

- **PowerShell**: Version 5.1 oder höher
  - Windows: Integriert in Windows 10/11
  - Für optimale Performance: [PowerShell 7+](https://github.com/PowerShell/PowerShell/releases)
  
- **FFmpeg**: Version 6 oder höher (Version 7+ empfohlen)
  - Download: [ffmpeg.org](https://ffmpeg.org/download.html)
  - FFmpeg muss in `PATH` verfügbar sein

### Verifikation

Prüfe ob FFmpeg installiert ist:
```powershell
ffmpeg -version
ffprobe -version
```

Prüfe PowerShell Version:
```powershell
$PSVersionTable.PSVersion
```

---

## 🔧 Installation

### Dateien herunterladen

Lade `Split.ps1` und `split.cfg`. Platziere die Dateien im gleichen Verzeichnis.

---

## 🎯 Verwendung

### Grundlegende Verwendung

```powershell
.\Split.ps1
```

Das Script:
1. Lädt die Config-Datei `split.cfg`
2. Durchsucht alle Unterordner im konfigurierten `BasePath`
3. Findet Ordner mit genau **einer** WAV-Datei
4. Splittet die WAV-Datei in 32 Kanäle (oder weniger, je nach Config)
5. Speichert die Kanäle mit den konfigurierten Namen

### Ordnerstruktur

**Vorher:**
```
h:\X_LIVE\
  ├── 5C53A647\
  │   └── 00000001.wav (32 Kanäle)
  ├── 5C53AB5D\
  │   └── 00000001.wav (32 Kanäle)
```

**Nachher (mit `CreateSubfolderForChannels = true`):**
```
h:\X_LIVE\
  ├── 5C53AB5D\
  │   ├── 00000001.wav (Original)
  │   └── channels\
  │       ├── 5C53AB5D-01 Kick.wav
  │       ├── 5C53AB5D-02 Snare.wav
  │       ├── 5C53AB5D-03 HiHat.wav
  │       └── ...
```

**Nachher (mit `UseFolderNameAsPrefix = false`):**
```
h:\X_LIVE\
  ├── 5C53AB5D\
  │   ├── 00000001.wav (Original)
  │   └── channels\
  │       ├── 01 Kick.wav
  │       ├── 02 Snare.wav
  │       ├── 03 HiHat.wav
  │       └── ...
```

---

## ⚙️ Konfiguration

### Config-Datei: `split.cfg`

Die Config-Datei verwendet INI-Format mit zwei Sections: `[Options]` und `[Channels]`.

### Options Section

| Option | Typ | Standard | Beschreibung |
|--------|-----|----------|--------------|
| `BasePath` | String | - | **Pflicht**: Haupt-Verzeichnis mit den zu verarbeitenden Ordnern |
| `BitDepth` | String | `auto` | Ziel Bit-Tiefe: `auto`, `16`, `24`, `32` |
| `VerboseOutput` | Boolean | `false` | Detaillierte Ausgaben während der Verarbeitung |
| `CreateSubfolderForChannels` | Boolean | `true` | Erstellt `channels\` Unterordner für gesplittete Dateien |
| `ParallelProcessing` | Boolean | `true` | Aktiviert parallele Verarbeitung mehrerer Ordner |
| `MaxParallelJobs` | Integer | CPU-Kerne | Maximale Anzahl gleichzeitiger Jobs |
| `UseFolderNameAsPrefix` | Boolean | `true` | Nutzt Ordnernamen als Datei-Präfix |

#### Option Details

**BasePath**
- Absoluter oder relativer Pfad
- Beispiele:
  - `h:\X_LIVE` (absolut)
  - `Recordings` (relativ zum Script-Ordner)

**BitDepth**
- `auto`: Behält Original Bit-Tiefe bei
- `16`: Konvertiert zu 16-bit PCM
- `24`: Konvertiert zu 24-bit PCM
- `32`: Konvertiert zu 32-bit PCM

**ParallelProcessing**
- `true`: Mehrere Ordner werden gleichzeitig verarbeitet
- `false`: Sequentielle Verarbeitung (langsamer, aber weniger Ressourcen)

**MaxParallelJobs**
- Empfehlung: 50-75% der CPU-Kerne
- Beispiel: 8-Kern CPU → `MaxParallelJobs = 4-6`

**UseFolderNameAsPrefix**
- `true`: Dateiname = `Ordnername-01 Kick.wav`
- `false`: Dateiname = `01 Kick.wav` (ohne Präfix)

### Channels Section

Definiert Namen für jeden Kanal (1-32).

**Format:**
```ini
[Channels]
KanalNummer = KanalName
```

**Spezielle Werte:**
- `(Skip)`: Kanal wird nicht exportiert
- Leerer Wert: Kanal wird nicht exportiert
- Beliebiger Text: Wird als Kanalname verwendet

**Beispiel:**
```ini
[Channels]
1 = Kick
2 = Snare
3 = (Skip)     # Wird übersprungen
4 =            # Wird übersprungen
5 = Tom
```

---

## 📚 Beispiele

### Beispiel 1: Standard Studio Recording

**Config:**
```ini
[Options]
BasePath = D:\Recordings
BitDepth = 24
CreateSubfolderForChannels = true
ParallelProcessing = true
MaxParallelJobs = 4
UseFolderNameAsPrefix = true

[Channels]
1 = Kick
2 = Snare
3 = HiHat
4 = Tom1
5 = Tom2
6 = Floor Tom
7 = OH L
8 = OH R
9 = Bass DI
10 = Bass Amp
11 = (Skip)
12 = (Skip)
13 = (Skip)
14 = (Skip)
15 = (Skip)
16 = (Skip)
17 = (Skip)
18 = (Skip)
19 = (Skip)
20 = (Skip)
21 = (Skip)
22 = (Skip)
23 = Vocal
24-32 = (Skip)
```

**Ergebnis:**
- Ordner: `2024-SessionXYZ`
- Output: `2024-SessionXYZ-01 Kick.wav`, `2024-SessionXYZ-02 Snare.wav`, etc.
- Kanäle 11-22 und 24-32 werden übersprungen

### Beispiel 2: Live Recording ohne Präfix

**Config:**
```ini
[Options]
BasePath = E:\LiveShows
BitDepth = auto
CreateSubfolderForChannels = false
UseFolderNameAsPrefix = false

[Channels]
1 = Kick
2 = Snare
3 = Bass
4 = Guitar L
5 = Guitar R
6 = Vocal
7-32 = (Skip)
```

**Ergebnis:**
- Ordner: `LiveShow-2024-12-25`
- Output direkt im Ordner: `01 Kick.wav`, `02 Snare.wav`, `03 Bass.wav`, etc.
- Nur 6 Dateien werden erstellt

### Beispiel 3: Maximale Performance

**Config:**
```ini
[Options]
BasePath = F:\BigProject
BitDepth = 32
ParallelProcessing = true
MaxParallelJobs = 12        # Für 16-Kern CPU
CreateSubfolderForChannels = true
UseFolderNameAsPrefix = true
VerboseOutput = false       # Weniger Konsolen-Output = schneller
```

---

## ⚡ Performance

### Geschwindigkeitsvergleich

**Testsystem**: AMD Ryzen 9 5950X (16 Kerne), SSD, FFmpeg 7.0

| Szenario | Sequentiell | Parallel (PS 5.1) | Parallel (PS 7+) |
|----------|-------------|-------------------|------------------|
| 1 Datei (2GB, 32 Kanäle) | ~60s | ~60s | ~20s* |
| 10 Dateien | ~600s | ~75s | ~80s |
| 50 Dateien | ~3000s | ~375s | ~400s |

\* FFmpeg 7+ Batch-Processing Vorteil

### Performance-Tipps

1. **Nutze PowerShell 7+** für beste Performance
2. **FFmpeg 7+** für Batch-Processing (3x schneller pro Datei)
3. **SSD statt HDD** für Output-Verzeichnis
4. **MaxParallelJobs optimieren:**
   - Zu wenig: Verschenkte Performance
   - Zu viel: Ressourcen-Überlastung
   - Sweet Spot: 50-75% der CPU-Kerne

5. **VerboseOutput = false** für schnellere Verarbeitung
6. **BitDepth = auto** vermeidet unnötige Konvertierung

---

## 🖥️ Kompatibilität

### Betriebssysteme

| OS | PowerShell 5.1 | PowerShell 7+ | Status |
|----|----------------|---------------|--------|
| Windows 10/11 | ✅ Integriert | ✅ Optional | Vollständig |
| Windows Server 2016+ | ✅ Integriert | ✅ Optional | Vollständig |
| macOS | ❌ | ✅ | Experimentell* |
| Linux | ❌ | ✅ | Experimentell* |

\* Pfade müssen angepasst werden (Unix-Style: `/home/user/audio` statt `h:\audio`)

### PowerShell Versionen

| Version | Parallel-Modus | FFmpeg Batch | Status |
|---------|----------------|--------------|--------|
| 5.1 | Job-basiert | ✅ | Unterstützt |
| 7.0+ | ForEach-Parallel | ✅ | Empfohlen |

### FFmpeg Versionen

| Version | map_channel | Batch (pan) | Performance |
|---------|-------------|-------------|-------------|
| 6.x | ✅ | ❌ | Normal |
| 7.0+ | ✅ | ✅ | 3x schneller |

---

## 🔍 Troubleshooting

### Problem: "ffmpeg nicht gefunden"

**Fehler:**
```
ffmpeg : Die Benennung "ffmpeg" wurde nicht als Name eines Cmdlet erkannt
```

**Lösung:**
1. Installiere FFmpeg: [ffmpeg.org](https://ffmpeg.org)
2. Füge FFmpeg zu PATH hinzu:
   ```powershell
   # Windows
   $env:Path += ";C:\ffmpeg\bin"
   ```
3. Verifiziere:
   ```powershell
   ffmpeg -version
   ```

### Problem: "BasePath nicht definiert"

**Fehler:**
```
BasePath wurde in der Config-Datei nicht definiert.
```

**Lösung:**
- Stelle sicher dass `split.cfg` im gleichen Ordner wie `Split.ps1` liegt
- Prüfe dass `[Options]` Section vorhanden ist
- Prüfe dass `BasePath = ...` korrekt geschrieben ist

### Problem: Keine Dateien werden verarbeitet

**Mögliche Ursachen:**

1. **Ordner enthält mehrere WAV-Dateien:**
   - Script verarbeitet nur Ordner mit **genau 1** WAV-Datei
   - Output: `Ueberspringe: Ordner - 3 WAV-Dateien (bereits gesplittet?)`

2. **Ordner enthält keine WAV-Dateien:**
   - Output: `Ueberspringe: Ordner - Keine WAV-Dateien`

3. **BasePath falsch:**
   - Prüfe ob Pfad existiert
   - Prüfe Schreibweise

### Problem: Parallele Verarbeitung funktioniert nicht (PS 5.1)

**Symptom:**
```
Starte parallele Verarbeitung (PS5.1) mit max. X gleichzeitigen Jobs...
```

**Hinweis:**
- Das ist normal bei PowerShell 5.1
- Script nutzt automatisch Job-basierte Parallelverarbeitung
- Funktioniert vollständig, nur anders implementiert als PS 7+

**Für optimale Performance:**
- Installiere [PowerShell 7+](https://github.com/PowerShell/PowerShell/releases)

### Problem: Langsame Verarbeitung

**Checks:**

1. **FFmpeg Version prüfen:**
   ```powershell
   ffmpeg -version
   # Sollte 7.0 oder höher sein für beste Performance
   ```

2. **Parallele Verarbeitung aktiviert?**
   ```ini
   ParallelProcessing = true
   ```

3. **MaxParallelJobs zu niedrig?**
   ```ini
   MaxParallelJobs = 8  # Erhöhen auf 50-75% deiner CPU-Kerne
   ```

4. **VerboseOutput deaktivieren:**
   ```ini
   VerboseOutput = false
   ```

### Problem: "Sample Rate konnte nicht ermittelt werden"

**Fehler:**
```
Sample Rate konnte nicht ermittelt werden
```

**Lösung:**
- Datei ist möglicherweise korrupt
- Prüfe mit: `ffprobe DATEI.wav`
- Versuche Datei mit anderem Tool zu öffnen/reparieren

---

## 📄 Lizenz

MIT License

---

## 🤝 Contribution

Contributions sind willkommen! Bei Fragen oder Problemen gerne Issues erstellen.

---

## 🙏 Credits

- https://github.com/Topslakr/x32Live-CleanUp/tree/master
- **FFmpeg**: [ffmpeg.org](https://ffmpeg.org)
- **PowerShell**: [Microsoft](https://github.com/PowerShell/PowerShell)

---

## 📝 Changelog

### Version 2.0.0 (2024-12)
- ✨ PowerShell 5.1 Kompatibilität mit Job-basierter Parallelverarbeitung
- ✨ FFmpeg 7+ Batch-Processing Support
- ✨ Optionaler Ordnername als Präfix
- ✨ Performance-Optimierungen
- 📚 Ausführliche Dokumentation

### Version 1.0.0 (Initial)
- 🎉 Erste Version
- ✨ Basis WAV-Splitting Funktionalität
- ⚙️ Config-basierte Kanal-Namen