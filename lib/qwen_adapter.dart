import 'package:llamadart/llamadart.dart';

/// Adapter wrapper for Qwen3-VL chat session using llamadart.
class Qwen3VLAdapter {
  final ChatSession session;
  bool _degraded = false;

  Qwen3VLAdapter(this.session);

  String get modelId => 'qwen3-vl-2b-instruct';

  bool get isDegraded => _degraded;

  Future<String> runInference(String text) async {
    final buffer = StringBuffer();
    final stream = session.create([LlamaTextContent(text)]);
    await for (final chunk in stream) {
      final token = chunk.choices.first.delta.content;
      if (token != null) buffer.write(token);
    }
    return buffer.toString();
  }

  void simulateMemoryPressure(int mb) {
    if (mb > 200) _degraded = true;
  }

  void reset() {
    _degraded = false;
  }

  bool isHealthy() => !_degraded;
}
