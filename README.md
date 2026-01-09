## ColourSwift Secure Files

<img src="https://github.com/phsycologicalFudge/CS-Secure-Files/blob/main/assets/icons/logo.png" width="140" alt="ColourSwift logo">

ColourSwift Secure Files is a lightweight, open source android file manager.

<p>
<img src="https://img.shields.io/github/downloads/phsycologicalFudge/CS-Secure-File/total?label=App%20downloads">
<img src="https://img.shields.io/github/v/release/phsycologicalFudge/CS-Secure-File?label=App%20release">
<img src="https://img.shields.io/github/license/phsycologicalFudge/CS-Secure-File">
</p>

<p>
  <a href="https://play.google.com/store/apps/details?id=com.colourswift.securefiles">
    <img src="https://play.google.com/intl/en_gb/badges/static/images/badges/en_badge_web_generic.png"
         height="80"
         alt="Get it on Google Play">
  </a>
</p>

---

## Overview

ColourSwift Secure Files provides a clean interface for browsing, managing, and transferring files stored on your device.

The app is intentionally simple and avoids bundling unnecessary features.

- Browse internal and external storage
- Install APK files locally
- View storage usage
- Optional local network access via FTP / HTTP
- No accounts required
- No ads

All functionality is local to the device.

---

## Network access

ColourSwift Secure Files includes optional local network features:

- FTP server for local file transfer
- HTTP file access for browser-based downloads

These services:
- Run only when explicitly enabled
- Are restricted to local storage roots
- Do not perform scanning or inspection of files

The server runtime is a small native component and does not include antivirus logic.

---

## Relationship to ColourSwift Security

This app does not scan files and does not include malware detection.

If you are looking for malware scanning or security features, see:

https://github.com/phsycologicalFudge/ColourSwift_AV

ColourSwift Secure Files is maintained separately and can be used independently.

---

## Download

Get the latest APK from GitHub Releases:

https://github.com/phsycologicalFudge/ColourSwift_SecureFiles/releases

---

## Privacy

- No personal data collection
- No analytics or tracking
- No cloud uploads
- No user accounts

All file operations are performed locally on the device.

---

## Open source status

This repository contains the full source code for the Android application.

The bundled native server runtime (FTP / HTTP) is provided as source and can be compiled independently.  
It does not include any proprietary antivirus components.

Developers are free to inspect, modify, and build the server runtime for their own use.
