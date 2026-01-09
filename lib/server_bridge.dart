import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

typedef FtpStartWithRootNative = Void Function(
    Int32,
    Pointer<Utf8>,
    Pointer<Utf8>,
    Pointer<Utf8>,
    );
typedef FtpStopNative = Void Function();
typedef FtpStatusNative = Int32 Function();

typedef HttpStartWithRootNative = Void Function(
    Int32,
    Pointer<Utf8>,
    Pointer<Utf8>,
    );
typedef HttpStopNative = Void Function();
typedef HttpStatusNative = Int32 Function();

typedef FtpStartWithRootDart = void Function(
    int,
    Pointer<Utf8>,
    Pointer<Utf8>,
    Pointer<Utf8>,
    );
typedef FtpStopDart = void Function();
typedef FtpStatusDart = int Function();

typedef HttpStartWithRootDart = void Function(
    int,
    Pointer<Utf8>,
    Pointer<Utf8>,
    );
typedef HttpStopDart = void Function();
typedef HttpStatusDart = int Function();

class ServerBridge {
  late final DynamicLibrary _lib;

  late final FtpStartWithRootDart _ftpStartWithRoot;
  late final FtpStopDart _ftpStop;
  late final FtpStatusDart _ftpStatus;

  late final HttpStartWithRootDart _httpStartWithRoot;
  late final HttpStopDart _httpStop;
  late final HttpStatusDart _httpStatus;

  ServerBridge() {
    if (Platform.isAndroid) {
      _lib = DynamicLibrary.open("libcolourswift_av.so");
    } else if (Platform.isWindows) {
      _lib = DynamicLibrary.open("colourswift_av.dll");
    } else {
      throw UnsupportedError("Unsupported platform");
    }

    _ftpStartWithRoot = _lib.lookupFunction<FtpStartWithRootNative, FtpStartWithRootDart>(
      'ftp_start_with_root',
    );
    _ftpStop = _lib.lookupFunction<FtpStopNative, FtpStopDart>('ftp_stop');
    _ftpStatus = _lib.lookupFunction<FtpStatusNative, FtpStatusDart>('ftp_status');

    _httpStartWithRoot = _lib.lookupFunction<HttpStartWithRootNative, HttpStartWithRootDart>(
      'http_start_with_root',
    );
    _httpStop = _lib.lookupFunction<HttpStopNative, HttpStopDart>('http_stop');
    _httpStatus = _lib.lookupFunction<HttpStatusNative, HttpStatusDart>('http_status');
  }

  void ftpStartWithRoot(int port, String root, String user, String pass) {
    final r = root.toNativeUtf8();
    final u = user.toNativeUtf8();
    final p = pass.toNativeUtf8();
    try {
      _ftpStartWithRoot(port, r, u, p);
    } finally {
      malloc.free(r);
      malloc.free(u);
      malloc.free(p);
    }
  }

  void ftpStop() {
    _ftpStop();
  }

  bool ftpIsRunning() {
    return _ftpStatus() == 1;
  }

  void httpStartWithRoot(int port, String root, String password) {
    final r = root.toNativeUtf8();
    final p = password.toNativeUtf8();
    try {
      _httpStartWithRoot(port, r, p);
    } finally {
      malloc.free(r);
      malloc.free(p);
    }
  }

  void httpStop() {
    _httpStop();
  }

  bool httpIsRunning() {
    return _httpStatus() == 1;
  }
}
