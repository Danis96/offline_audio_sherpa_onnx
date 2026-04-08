import 'dart:typed_data';

import 'soniox_socket.dart';

Future<SonioxSocket> connectSonioxSocketImpl(String url) {
  throw UnsupportedError('Soniox streaming is not supported on this platform.');
}

class UnsupportedSonioxSocket implements SonioxSocket {
  @override
  Stream<Object> get messages => const Stream<Object>.empty();

  @override
  Future<void> close() async {}

  @override
  Future<void> sendBinary(Uint8List bytes) async {}

  @override
  Future<void> sendText(String message) async {}
}
