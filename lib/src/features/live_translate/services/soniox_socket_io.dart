import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'soniox_socket.dart';

Future<SonioxSocket> connectSonioxSocketImpl(String url) async {
  final socket = await WebSocket.connect(url);
  return IoSonioxSocket(socket);
}

class IoSonioxSocket implements SonioxSocket {
  IoSonioxSocket(this._socket);

  final WebSocket _socket;

  @override
  Stream<Object> get messages => _socket.map<Object>((event) => event);

  @override
  Future<void> close() async {
    await _socket.close();
  }

  @override
  Future<void> sendBinary(Uint8List bytes) async {
    _socket.add(bytes);
  }

  @override
  Future<void> sendText(String message) async {
    _socket.add(message);
  }
}
