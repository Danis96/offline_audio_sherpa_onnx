import 'dart:typed_data';

import 'soniox_socket_stub.dart' if (dart.library.io) 'soniox_socket_io.dart';

abstract class SonioxSocket {
  Stream<Object> get messages;

  Future<void> sendText(String message);

  Future<void> sendBinary(Uint8List bytes);

  Future<void> close();
}

Future<SonioxSocket> connectSonioxSocket(String url) =>
    connectSonioxSocketImpl(url);
