import 'package:flutter/material.dart';

import '../controllers/univault_controller.dart';
import '../models/document_model.dart';
import '../models/pdf_text_chunk.dart';
import '../services/ai_service.dart';
import '../services/pdf_text_service.dart';

class AiAssistantScreen extends StatefulWidget {
  const AiAssistantScreen({
    required this.controller,
    this.document,
    this.onNavigateToPage,
    this.onClose,
    this.aiService,
    this.pdfTextService,
    super.key,
  });

  final UnivaultController controller;
  final DocumentModel? document;
  final ValueChanged<int>? onNavigateToPage;
  final VoidCallback? onClose;
  final AiService? aiService;
  final PdfTextService? pdfTextService;

  @override
  State<AiAssistantScreen> createState() => _AiAssistantScreenState();
}

class _AiAssistantScreenState extends State<AiAssistantScreen> {
  late final AiService _aiService;
  late final PdfTextService _pdfTextService;
  late final bool _ownsAiService;
  final TextEditingController _questionController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();
  final List<_ChatMessage> _messages = [];
  final Set<int> _consentedDocuments = {};

  List<DocumentModel> _documents = [];
  List<PdfTextChunk>? _extractedChunks;
  DocumentModel? _selectedDocument;
  bool _loadingDocuments = true;
  bool _busy = false;
  bool _requestStarting = false;
  String? _documentError;
  String? _loadingMessage;
  String? _failedQuestion;
  int _questionCount = 5;

  @override
  void initState() {
    super.initState();
    _aiService = widget.aiService ?? AiService();
    _pdfTextService = widget.pdfTextService ?? PdfTextService();
    _ownsAiService = widget.aiService == null;
    _selectedDocument = widget.document;
    widget.controller.addListener(_loadDocuments);
    _loadDocuments();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_loadDocuments);
    if (_ownsAiService) {
      _aiService.close();
    }
    _questionController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadDocuments() async {
    try {
      final documents = (await widget.controller.loadAllDocuments())
          .where(
            (document) => document.localFilePath.toLowerCase().endsWith('.pdf'),
          )
          .toList();
      if (!mounted) {
        return;
      }

      final selectedId = widget.document?.id ?? _selectedDocument?.id;
      final updatedSelection = documents.where((doc) => doc.id == selectedId);
      setState(() {
        _documents = documents;
        _selectedDocument = updatedSelection.isEmpty
            ? widget.document
            : updatedSelection.first;
        _loadingDocuments = false;
        _documentError = null;
      });
    } on Exception {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingDocuments = false;
        _documentError = 'Could not load PDFs from your library. Try again.';
      });
    }
  }

  void _selectDocument(DocumentModel? document) {
    if (widget.document != null) {
      return;
    }
    setState(() {
      _selectedDocument = document;
      _extractedChunks = null;
      _messages.clear();
      _failedQuestion = null;
      _questionController.clear();
    });
  }

  Future<void> _clearConversation() async {
    if (_messages.isEmpty || _busy) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear conversation?'),
        content: const Text(
          'This clears the conversation for the current PDF.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      setState(() {
        _messages.clear();
        _failedQuestion = null;
        _questionController.clear();
      });
    }
  }

  Future<bool> _confirmExternalProcessing(DocumentModel document) async {
    if (_consentedDocuments.contains(document.id)) {
      return true;
    }

    final consented = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Send text to AI?'),
        content: Text(
          'UniVault will extract text from "${document.name}" on this device. '
          'Relevant text excerpts will be sent to your configured backend and Google Gemini '
          'to generate a response. The original PDF stays on this device, and UniVault '
          'does not save the extracted text. Google’s data-handling terms apply.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (consented == true) {
      _consentedDocuments.add(document.id);
      return true;
    }
    return false;
  }

  Future<List<PdfTextChunk>> _getChunks(DocumentModel document) async {
    final cached = _extractedChunks;
    if (cached != null) {
      return cached;
    }

    final chunks = await _pdfTextService.extractChunks(document.localFilePath);
    if (!mounted || _selectedDocument?.id != document.id) {
      throw const PdfTextException(
        'The selected PDF changed. Please select it again and retry.',
      );
    }
    _extractedChunks = chunks;
    return chunks;
  }

  Future<void> _askQuestion() async {
    final question = _questionController.text.trim();
    if (question.isEmpty || _busy || _requestStarting) {
      return;
    }
    final succeeded = await _runRequest(
      action: 'ask',
      prompt: question,
      displayPrompt: question,
    );
    if (succeeded && mounted && _questionController.text.trim() == question) {
      _questionController.clear();
    }
  }

  Future<void> _retryFailedQuestion() async {
    final question = _failedQuestion;
    if (question == null || _busy || _requestStarting) {
      return;
    }
    final succeeded = await _runRequest(
      action: 'ask',
      prompt: question,
      displayPrompt: question,
      retrying: true,
    );
    if (succeeded && mounted && _questionController.text.trim() == question) {
      _questionController.clear();
    }
  }

  Future<void> _generateSummary({required bool detailed}) async {
    final prompt = detailed
        ? 'Write a detailed summary of the document. Use clear headings and concise bullet points. Cover the main arguments, important supporting ideas, and conclusions.'
        : 'Write a concise summary of the document. Use a short heading and clear bullet points for the key ideas.';
    await _runRequest(
      action: 'summary',
      prompt: prompt,
      displayPrompt: detailed
          ? 'Generate detailed summary'
          : 'Generate summary',
      overview: true,
    );
  }

  Future<void> _generateStudyNotes() async {
    await _runRequest(
      action: 'study_notes',
      prompt: 'Create student-friendly study notes with clear headings and subheadings. Include the important concepts, definitions, explanations, examples where present, and key takeaways. Do not invent details missing from the source.',
      displayPrompt: 'Generate study notes',
      overview: true,
    );
  }

  Future<void> _generateMcqs() async {
    await _runRequest(
      action: 'mcq',
      prompt:
          'Create $_questionCount multiple-choice questions. Each must have exactly four options, clearly identify the correct answer, and include a short explanation. Test different important concepts and do not invent facts.',
      displayPrompt: 'Generate $_questionCount MCQs',
      overview: true,
      questionCount: _questionCount,
    );
  }

  Future<bool> _runRequest({
    required String action,
    required String prompt,
    required String displayPrompt,
    bool overview = false,
    int? questionCount,
    bool retrying = false,
  }) async {
    final document = _selectedDocument;
    if (document == null || _busy || _requestStarting) {
      return false;
    }
    _requestStarting = true;
    var requestStarted = false;
    var succeeded = false;
    try {
      if (!_aiService.isConfigured) {
        _appendError(
          'AI is not configured. Deploy the backend and set UNIVAULT_AI_ENDPOINT to its URL when building the app.',
        );
        return false;
      }
      if (!await _confirmExternalProcessing(document) || !mounted) {
        return false;
      }
      if (_selectedDocument?.id != document.id ||
          _selectedDocument?.localFilePath != document.localFilePath) {
        _appendError(
          'The selected PDF changed. Please select it again and retry.',
        );
        return false;
      }

      final historyMessages = _messages
          .where((message) => !message.isError)
          .toList()
          .reversed
          .take(8)
          .toList()
          .reversed
          .toList();
      if (retrying &&
          historyMessages.isNotEmpty &&
          historyMessages.last.isUser &&
          historyMessages.last.text == prompt) {
        historyMessages.removeLast();
      }
      final history = historyMessages
          .map(
            (message) => AiMessage(
              role: message.isUser ? 'user' : 'assistant',
              text: message.text,
            ),
          )
          .toList();
      setState(() {
        _busy = true;
        _loadingMessage = 'Reading PDF text…';
        _messages.add(_ChatMessage(isUser: true, text: displayPrompt));
        if (action == 'ask') {
          _failedQuestion = null;
        }
      });
      requestStarted = true;
      _scrollToLatest();

      final chunks = action == 'ask'
          ? await _pdfTextService.extractRelevantChunks(
              document.localFilePath,
              prompt,
            )
          : await _getChunks(document);
      if (!mounted) {
        return false;
      }
      if (chunks.isEmpty ||
          chunks.every((chunk) => chunk.text.trim().isEmpty)) {
        throw const PdfTextException(
          'No selectable text was found. This may be a scanned or image-only PDF; OCR is required before AI features can use it.',
        );
      }
      setState(() => _loadingMessage = 'Preparing relevant text…');
      final selectedChunks = action == 'ask'
          ? chunks
          : overview
          ? _pdfTextService.selectOverviewChunks(chunks)
          : _pdfTextService.selectRelevantChunks(chunks, prompt);
      final context = selectedChunks
          .map((chunk) => '[Page ${chunk.pageNumber}]\n${chunk.text}')
          .join('\n\n');
      if (context.trim().isEmpty) {
        throw const PdfTextException(
          'No selectable text was found. This may be a scanned or image-only PDF; OCR is required before AI features can use it.',
        );
      }

      setState(() => _loadingMessage = 'Generating response…');
      final answer = await _aiService.generate(
        action: action,
        documentName: document.name,
        context: context,
        prompt: prompt,
        history: action == 'ask' ? history : const [],
        questionCount: questionCount,
      );
      if (!mounted) {
        return false;
      }
      setState(() {
        _messages.add(_ChatMessage(isUser: false, text: answer));
        if (action == 'ask') {
          _failedQuestion = null;
        }
      });
      succeeded = true;
    } on PdfTextException catch (error) {
      if (action == 'ask') {
        _failedQuestion = null;
      }
      _appendError(error.message);
    } on AiServiceException catch (error) {
      if (action == 'ask' && _aiService.isConfigured) {
        _failedQuestion = prompt;
      }
      _appendError(error.message);
    } on Exception {
      if (action == 'ask' && _aiService.isConfigured) {
        _failedQuestion = prompt;
      }
      _appendError(
        'Something went wrong while processing this request. Please try again.',
      );
    } finally {
      _requestStarting = false;
      if (mounted && requestStarted) {
        setState(() {
          _busy = false;
          _loadingMessage = null;
        });
        _scrollToLatest();
      }
    }
    return succeeded;
  }

  void _appendError(String message) {
    if (!mounted) {
      return;
    }
    setState(() {
      _messages.add(_ChatMessage(isUser: false, isError: true, text: message));
    });
    _scrollToLatest();
  }

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final content = SafeArea(
      child: Column(
        children: [
          Expanded(
            child: ListView(
              controller: _chatScrollController,
              padding: const EdgeInsets.all(20),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.document == null
                            ? 'AI Assistant'
                            : 'Ask AI about this PDF',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (widget.document == null && _messages.isNotEmpty)
                      TextButton.icon(
                        onPressed: _busy ? null : _clearConversation,
                        icon: const Icon(Icons.delete_sweep_outlined),
                        label: const Text('Clear'),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  widget.document == null
                      ? 'Ask questions and create study materials from a PDF in your library.'
                      : 'Answers and study tools use only this PDF.',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
                _buildConfigurationNotice(context),
                const SizedBox(height: 16),
                if (widget.document == null)
                  _buildDocumentPicker(context)
                else
                  _buildSelectedDocument(context, widget.document!),
                const SizedBox(height: 16),
                _buildPrivacyNotice(context),
                const SizedBox(height: 20),
                if (_selectedDocument == null)
                  _buildEmptyState(context)
                else ...[
                  _buildActions(context),
                  const SizedBox(height: 16),
                  if (_messages.isEmpty && !_busy) _buildChatWelcome(context),
                  ..._messages.map(
                    (message) => _MessageBubble(
                      message: message,
                      onNavigateToPage: widget.onNavigateToPage,
                    ),
                  ),
                  if (_failedQuestion != null && !_busy)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        key: const ValueKey('ai-retry-question'),
                        onPressed: _retryFailedQuestion,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry question'),
                      ),
                    ),
                  if (_busy)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        children: [
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 12),
                          Text(_loadingMessage ?? 'Working…'),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
          if (_selectedDocument != null) _buildComposer(context),
        ],
      ),
    );
    if (widget.document == null) {
      return content;
    }
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: widget.onClose == null ? 'Back to PDF' : 'Close AI panel',
          onPressed: widget.onClose ?? () => Navigator.pop(context),
          icon: Icon(widget.onClose == null ? Icons.arrow_back : Icons.close),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Ask AI'),
            Text(
              widget.document!.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Clear conversation',
            onPressed: _messages.isEmpty || _busy ? null : _clearConversation,
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: content,
    );
  }

  Widget _buildSelectedDocument(BuildContext context, DocumentModel document) {
    return Card(
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.picture_as_pdf_rounded)),
        title: Text(
          document.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: const Text('All answers are limited to this PDF.'),
      ),
    );
  }

  Widget _buildConfigurationNotice(BuildContext context) {
    final configured = _aiService.isConfigured;
    return Card(
      color: configured
          ? Theme.of(context).colorScheme.primaryContainer
          : Theme.of(context).colorScheme.tertiaryContainer,
      child: ListTile(
        leading: Icon(
          configured ? Icons.cloud_done_outlined : Icons.settings_ethernet,
        ),
        title: Text(
          configured ? 'Backend configured' : 'Backend not configured',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          configured ? 'AI requests use your configured UniVault backend.' : 'Deploy the Cloudflare Worker and build with UNIVAULT_AI_ENDPOINT. AI requests are disabled until then.',
        ),
      ),
    );
  }

  Widget _buildDocumentPicker(BuildContext context) {
    if (_loadingDocuments) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_documentError != null) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.error_outline),
          title: Text(_documentError!),
          trailing: IconButton(
            tooltip: 'Retry',
            onPressed: _loadDocuments,
            icon: const Icon(Icons.refresh),
          ),
        ),
      );
    }

    return DropdownButtonFormField<DocumentModel>(
      key: const ValueKey('ai-pdf-picker'),
      initialValue: _selectedDocument,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Choose a PDF',
        prefixIcon: Icon(Icons.picture_as_pdf_outlined),
        border: OutlineInputBorder(),
      ),
      hint: const Text('Select from your library'),
      items: _documents
          .map(
            (document) => DropdownMenuItem(
              value: document,
              child: Text(document.name, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      onChanged: _busy ? null : _selectDocument,
    );
  }

  Widget _buildPrivacyNotice(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.privacy_tip_outlined, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Nothing is sent until you choose an AI action and consent. Only selected text excerpts are sent; the original PDF stays local.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final noLibraryPdfs =
        !_loadingDocuments && _documentError == null && _documents.isEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 12),
      child: Column(
        children: [
          Icon(
            noLibraryPdfs ? Icons.picture_as_pdf_outlined : Icons.auto_awesome,
            size: 44,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 12),
          Text(
            noLibraryPdfs
                ? 'No PDFs in your library yet'
                : 'Select a PDF to begin',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            noLibraryPdfs
                ? 'Import a PDF from Home or Library to use AI study tools.'
                : 'Choose a PDF above to ask questions, summarize, or make study materials.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Study tools',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _generateSummary(detailed: false),
                  icon: const Icon(Icons.summarize_outlined),
                  label: const Text('Summary'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _generateSummary(detailed: true),
                  icon: const Icon(Icons.subject_rounded),
                  label: const Text('Detailed summary'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _generateStudyNotes,
                  icon: const Icon(Icons.menu_book_outlined),
                  label: const Text('Study notes'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.quiz_outlined),
                    SizedBox(width: 8),
                    Text('MCQ questions'),
                  ],
                ),
                DropdownButton<int>(
                  value: _questionCount,
                  onChanged: _busy
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() => _questionCount = value);
                          }
                        },
                  items: [3, 5, 10, 15, 20]
                      .map(
                        (count) => DropdownMenuItem(
                          value: count,
                          child: Text('$count'),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _busy ? null : _generateMcqs,
                  child: const Text('Generate'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatWelcome(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        'Ask a question below, or choose a study tool. Your chat stays on this screen and is reset when you select another PDF.',
        style: Theme.of(context).textTheme.bodyMedium
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }

  Widget _buildComposer(BuildContext context) {
    return Material(
      elevation: 3,
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _questionController,
                  enabled: !_busy,
                  minLines: 1,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  maxLength: 2000,
                  decoration: const InputDecoration(
                    hintText: 'Ask about this PDF…',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _askQuestion(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: 'Send question',
                onPressed: _busy ? null : _askQuestion,
                icon: const Icon(Icons.send_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatMessage {
  const _ChatMessage({
    required this.isUser,
    required this.text,
    this.isError = false,
  });

  final bool isUser;
  final bool isError;
  final String text;
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.onNavigateToPage});

  final _ChatMessage message;
  final ValueChanged<int>? onNavigateToPage;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final background = message.isError
        ? colorScheme.errorContainer
        : message.isUser
        ? colorScheme.primaryContainer
        : colorScheme.surfaceContainerHighest;

    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(18),
        ),
        child: message.isUser || message.isError
            ? SelectableText(message.text)
            : _FormattedAnswer(
                text: message.text,
                onNavigateToPage: onNavigateToPage,
              ),
      ),
    );
  }
}

class _FormattedAnswer extends StatelessWidget {
  const _FormattedAnswer({required this.text, required this.onNavigateToPage});

  final String text;
  final ValueChanged<int>? onNavigateToPage;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: text.split('\n').expand<Widget>((line) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) {
          return [const SizedBox(height: 6)];
        }
        final pageReferences = RegExp(r'\[Page\s+(\d+)\]')
            .allMatches(trimmed)
            .map((match) => int.parse(match.group(1)!))
            .toList();
        final displayLine = onNavigateToPage == null
            ? trimmed
            : trimmed.replaceAll(RegExp(r'\[Page\s+\d+\]'), '').trim();
        final heading = RegExp(r'^#{1,4}\s+').hasMatch(displayLine);
        final bullet = RegExp(r'^[-*]\s+').hasMatch(displayLine);
        final content = displayLine
            .replaceFirst(RegExp(r'^#{1,4}\s+'), '')
            .replaceFirst(RegExp(r'^[-*]\s+'), '');
        final widgets = <Widget>[];
        if (bullet) {
          widgets.add(
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('•  '),
                  Expanded(child: SelectableText(content)),
                ],
              ),
            ),
          );
        } else if (content.isNotEmpty) {
          widgets.add(
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: SelectableText(
                content,
                style: heading
                    ? Theme.of(context).textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700)
                    : null,
              ),
            ),
          );
        }
        if (onNavigateToPage != null && pageReferences.isNotEmpty) {
          widgets.add(
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Wrap(
                spacing: 6,
                children: pageReferences
                    .toSet()
                    .map(
                      (page) => ActionChip(
                        avatar: const Icon(Icons.picture_as_pdf, size: 16),
                        label: Text('Page $page'),
                        onPressed: () => onNavigateToPage!(page),
                      ),
                    )
                    .toList(),
              ),
            ),
          );
        }
        return widgets;
      }).toList(),
    );
  }
}
