import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:llamadart/llamadart.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'On-Device Multimodal Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.deepOrange,
      ),
      home: const DemoPage(),
    );
  }
}

enum MessageSender { user, assistant }

class ChatMessage {
  final MessageSender sender;
  String text;
  final File? image;
  final DateTime timestamp;
  bool isError;

  ChatMessage({
    required this.sender,
    required this.text,
    this.image,
    required this.timestamp,
    this.isError = false,
  });
}

class DemoPage extends StatefulWidget {
  const DemoPage({super.key});

  @override
  State<DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<DemoPage> {
  LlamaEngine? _engine;
  ChatSession? _session;
  File? _pickedImage;
  final TextEditingController _promptController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final List<ChatMessage> _messages = [];
  StreamSubscription<dynamic>? _generationSubscription;

  String _status = 'Initializing llamadart engine...';
  bool _isLoading = false;
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    _loadModel();
  }

  Future<void> _loadModel() async {
    setState(() {
      _isLoading = true;
      _status = 'Loading Qwen3-VL on-device with llamadart...';
    });

    try {
      final dir = await getExternalStorageDirectory();
      if (dir == null) {
        setState(() {
          _status = 'Error: App storage directory unavailable.';
          _isLoading = false;
        });
        return;
      }

      final modelPath = '${dir.path}/model.gguf';
      final mmprojPath = '${dir.path}/mmproj.gguf';

      debugPrint('[LLAMADART] Model path: $modelPath');
      debugPrint('[LLAMADART] MMProj path: $mmprojPath');

      if (!File(modelPath).existsSync() || !File(mmprojPath).existsSync()) {
        setState(() {
          _status =
              'Model files not found.\nPush them via adb first:\nmodel.gguf & mmproj.gguf';
          _isLoading = false;
        });
        return;
      }

      final backend = LlamaBackend();
      final engine = LlamaEngine(backend);

      debugPrint('[LLAMADART] Loading GGUF model...');
      await engine.loadModel(modelPath);

      debugPrint('[LLAMADART] Loading Multimodal Projector...');
      await engine.loadMultimodalProjector(mmprojPath);

      final session = ChatSession(engine);

      setState(() {
        _engine = engine;
        _session = session;
        _status = 'Qwen3-VL Loaded Successfully with llamadart (Vision: ACTIVE)';
        _isLoading = false;
      });

      debugPrint('[LLAMADART] Engine initialization completed successfully!');
    } catch (e, stack) {
      debugPrint('[LLAMADART ERROR] Engine load failed: $e\n$stack');
      setState(() {
        _status = 'Failed to load engine: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery);
      if (picked != null) {
        setState(() => _pickedImage = File(picked.path));
        debugPrint('[LLAMADART] Picked image file: ${picked.path}');
      }
    } catch (e, stack) {
      debugPrint('[LLAMADART ERROR] Pick image failed: $e\n$stack');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick image: $e')),
        );
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _runInference() async {
    final promptText = _promptController.text.trim();

    if (_engine == null || _session == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('llamadart engine is not loaded yet.')),
      );
      return;
    }

    if (promptText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a prompt.')),
      );
      return;
    }

    final currentImage = _pickedImage;

    setState(() {
      _isGenerating = true;
      _messages.add(ChatMessage(
        sender: MessageSender.user,
        text: promptText,
        image: currentImage,
        timestamp: DateTime.now(),
      ));

      _messages.add(ChatMessage(
        sender: MessageSender.assistant,
        text: '',
        timestamp: DateTime.now(),
      ));

      _promptController.clear();
      _pickedImage = null;
    });

    _scrollToBottom();

    final assistantMsg = _messages.last;

    try {
      final List<LlamaContentPart> contents = [];

      if (currentImage != null) {
        debugPrint('[LLAMADART INFERENCE] Attaching image: ${currentImage.path}');
        contents.add(LlamaImageContent(path: currentImage.path));
      }

      contents.add(LlamaTextContent(promptText));

      debugPrint('[LLAMADART INFERENCE] Streaming session creation...');
      final stream = _session!.create(contents);

      _generationSubscription = stream.listen(
        (chunk) {
          final token = chunk.choices.first.delta.content;
          if (token != null && token.isNotEmpty) {
            debugPrint('[LLAMADART TOKEN] $token');
            setState(() {
              assistantMsg.text += token;
            });
            _scrollToBottom();
          }
        },
        onError: (error, stack) {
          debugPrint('[LLAMADART ERROR] Stream Error: $error\n$stack');
          setState(() {
            assistantMsg.text = '[Error: $error]';
            assistantMsg.isError = true;
            _isGenerating = false;
          });
        },
        onDone: () {
          debugPrint('[LLAMADART] Stream generation completed.');
          if (_isGenerating) {
            setState(() => _isGenerating = false);
          }
        },
      );
    } catch (e, stack) {
      debugPrint('[LLAMADART CATCH] Inference Launch Error: $e\n$stack');
      setState(() {
        assistantMsg.text = 'Error launching inference: $e';
        assistantMsg.isError = true;
        _isGenerating = false;
      });
    }
  }

  Future<void> _stopGenerating() async {
    if (_generationSubscription != null) {
      await _generationSubscription!.cancel();
      _generationSubscription = null;
    }
    debugPrint('[LLAMADART] Generation stopped by user.');
    setState(() {
      _isGenerating = false;
      if (_messages.isNotEmpty &&
          _messages.last.sender == MessageSender.assistant) {
        if (_messages.last.text.isEmpty) {
          _messages.last.text = '[Generation stopped by user.]';
        } else {
          _messages.last.text += ' [Stopped]';
        }
      }
    });
  }

  @override
  void dispose() {
    _generationSubscription?.cancel();
    _engine?.dispose();
    _promptController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('On-Device Multimodal Demo (llamadart)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading || _isGenerating ? null : _loadModel,
            tooltip: 'Reload Model Engine',
          )
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.deepOrange.shade50,
              child: Row(
                children: [
                  Icon(
                    _engine != null ? Icons.check_circle : Icons.info,
                    color: _engine != null ? Colors.green : Colors.deepOrange,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _status,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.deepOrange.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_isLoading) const LinearProgressIndicator(),
            Expanded(
              child: _messages.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.chat_bubble_outline,
                              size: 48, color: Colors.grey.shade400),
                          const SizedBox(height: 12),
                          Text(
                            'Pick an image and ask a question to start!',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final msg = _messages[index];
                        final isUser = msg.sender == MessageSender.user;

                        return Align(
                          alignment: isUser
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            constraints: BoxConstraints(
                              maxWidth: MediaQuery.of(context).size.width * 0.82,
                            ),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isUser
                                  ? Colors.deepOrange.shade600
                                  : msg.isError
                                      ? Colors.red.shade100
                                      : Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(16).copyWith(
                                bottomRight: isUser
                                    ? const Radius.circular(0)
                                    : const Radius.circular(16),
                                bottomLeft: isUser
                                    ? const Radius.circular(16)
                                    : const Radius.circular(0),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (msg.image != null) ...[
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.file(
                                      msg.image!,
                                      height: 180,
                                      width: double.infinity,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                ],
                                Text(
                                  msg.text.isEmpty &&
                                          _isGenerating &&
                                          index == _messages.length - 1
                                      ? 'Thinking...'
                                      : msg.text,
                                  style: TextStyle(
                                    color: isUser
                                        ? Colors.white
                                        : msg.isError
                                            ? Colors.red.shade900
                                            : Colors.black87,
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            if (_pickedImage != null)
              Container(
                padding: const EdgeInsets.all(8),
                color: Colors.grey.shade100,
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.file(
                        _pickedImage!,
                        height: 50,
                        width: 50,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Image attached',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.red),
                      onPressed: () => setState(() => _pickedImage = null),
                    ),
                  ],
                ),
              ),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 4,
                    offset: const Offset(0, -2),
                  )
                ],
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.add_a_photo),
                    onPressed: _isLoading || _isGenerating ? null : _pickImage,
                    tooltip: 'Attach Image',
                  ),
                  Expanded(
                    child: TextField(
                      controller: _promptController,
                      enabled: !_isLoading && !_isGenerating,
                      decoration: const InputDecoration(
                        hintText: 'Ask a question about the image...',
                        border: OutlineInputBorder(),
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      onSubmitted: (_) =>
                          _isGenerating ? null : _runInference(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (_isGenerating)
                    ElevatedButton.icon(
                      onPressed: _stopGenerating,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                      ),
                      icon: const Icon(Icons.stop, size: 18),
                      label: const Text('Stop'),
                    )
                  else
                    FilledButton(
                      onPressed:
                          (_isLoading || _engine == null) ? null : _runInference,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                      ),
                      child: const Text('Send'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
