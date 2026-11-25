import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';

import '../controllers/univault_controller.dart';
import '../models/document_model.dart';
import 'ai_assistant_screen.dart';

class PdfReaderScreen extends StatefulWidget {
  const PdfReaderScreen({
    required this.controller,
    required this.document,
    super.key,
  });

  final UnivaultController controller;
  final DocumentModel document;

  @override
  State<PdfReaderScreen> createState() => _PdfReaderScreenState();
}

class _PdfReaderScreenState extends State<PdfReaderScreen> {
  static const double _wideLayoutBreakpoint = 760;
  static const double _dividerWidth = 14;

  PdfControllerPinch? _pdfController;
  PdfDocument? _loadedDocument;
  Future<PdfDocument>? _documentFuture;
  final GlobalKey _pdfViewerKey = GlobalKey();
  final GlobalKey _assistantPanelKey = GlobalKey();
  int _currentPage = 1;
  int _pageCount = 0;
  double _pdfPanelFraction = 0.58;
  bool _aiPanelVisible = false;
  String? _pdfLoadError;
  int _loadGeneration = 0;
  bool? _wideLayout;

  @override
  void initState() {
    super.initState();
    _startDocumentLoad();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final wide = MediaQuery.sizeOf(context).width >= _wideLayoutBreakpoint;
    if (_wideLayout != wide) {
      _wideLayout = wide;
      _aiPanelVisible = wide;
    }
  }

  @override
  void didUpdateWidget(PdfReaderScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.document.id == widget.document.id &&
        oldWidget.document.localFilePath == widget.document.localFilePath) {
      return;
    }

    final previousController = _pdfController;
    final previousDocument = _loadedDocument;
    final previousDocumentFuture = _documentFuture;
    _pdfController = null;
    _loadedDocument = null;
    _documentFuture = null;
    _currentPage = 1;
    _pageCount = 0;
    _pdfLoadError = null;
    _loadGeneration++;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      previousController?.dispose();
      if (previousDocument != null) {
        unawaited(_closeDocument(previousDocument));
      } else if (previousDocumentFuture != null) {
        unawaited(_closeDocumentWhenLoaded(previousDocumentFuture));
      }
    });
    _startDocumentLoad();
  }

  Future<void> _startDocumentLoad() async {
    final generation = ++_loadGeneration;
    try {
      final file = File(widget.document.localFilePath);
      if (!await file.exists()) {
        throw const FileSystemException(
          'This PDF is no longer available in local storage.',
        );
      }
      if (await file.length() == 0) {
        throw const FileSystemException('This PDF is empty or damaged.');
      }
      if (!mounted || generation != _loadGeneration) {
        return;
      }

      final documentFuture = PdfDocument.openFile(file.path);
      final controller = PdfControllerPinch(document: documentFuture);
      setState(() {
        _documentFuture = documentFuture;
        _pdfController = controller;
        _pdfLoadError = null;
      });
    } catch (error) {
      if (!mounted || generation != _loadGeneration) {
        return;
      }
      setState(() {
        _pdfLoadError = _readableError(error);
      });
    }
  }

  void _handleDocumentLoaded(PdfDocument document) {
    if (!mounted) {
      unawaited(_closeDocument(document));
      return;
    }
    if (document.pagesCount < 1) {
      setState(() {
        _pdfLoadError = 'The PDF opened but contains no pages.';
      });
      return;
    }
    setState(() {
      _loadedDocument = document;
      _pageCount = document.pagesCount;
      _currentPage = _currentPage.clamp(1, _pageCount).toInt();
      _pdfLoadError = null;
    });
  }

  void _handleDocumentError(Object error) {
    if (!mounted) {
      return;
    }
    setState(() {
      _pdfLoadError = _readableError(error);
    });
  }

  String _readableError(Object error) {
    if (error is FileSystemException && error.message.isNotEmpty) {
      return error.message;
    }
    final details = error.toString().trim();
    return details.isEmpty
        ? 'The PDF could not be opened. It may be damaged or encrypted.'
        : 'Could not open this PDF: $details';
  }

  Future<void> _closeDocument(PdfDocument document) async {
    try {
      await document.close();
    } catch (error, stackTrace) {
      debugPrint(
        '[PDF_READER] Failed to close PDF document: $error\n$stackTrace',
      );
    }
  }

  Future<void> _closeDocumentWhenLoaded(
    Future<PdfDocument> documentFuture,
  ) async {
    try {
      await (await documentFuture).close();
    } catch (error, stackTrace) {
      debugPrint(
        '[PDF_READER] Failed to close pending PDF document: $error\n$stackTrace',
      );
    }
  }

  @override
  void dispose() {
    _loadGeneration++;
    _pdfController?.dispose();
    final document = _loadedDocument;
    final documentFuture = _documentFuture;
    if (document != null) {
      unawaited(_closeDocument(document));
    } else if (documentFuture != null) {
      unawaited(_closeDocumentWhenLoaded(documentFuture));
    }
    super.dispose();
  }

  void _toggleAiPanel() {
    setState(() => _aiPanelVisible = !_aiPanelVisible);
  }

  void _closeAiPanel() {
    if (_aiPanelVisible) {
      setState(() => _aiPanelVisible = false);
    }
  }

  void _navigateToPage(int pageNumber) {
    final controller = _pdfController;
    if (controller == null || pageNumber < 1 || pageNumber > _pageCount) {
      return;
    }
    unawaited(
      controller.animateToPage(
        pageNumber: pageNumber,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
      ),
    );
    setState(() => _currentPage = pageNumber);
  }

  Widget _buildPdfLoadingIndicator() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 12),
          Text('Opening PDF...', style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }

  Widget _buildPdfError(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 40,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(
              'Unable to display this PDF',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildPdfView() {
    final error = _pdfLoadError;
    if (error != null) {
      return _buildPdfError(error);
    }
    final controller = _pdfController;
    if (controller == null) {
      return _buildPdfLoadingIndicator();
    }

    return SizedBox.expand(
      child: PdfViewPinch(
        key: _pdfViewerKey,
        controller: controller,
        padding: 8,
        backgroundDecoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
        ),
        onDocumentLoaded: _handleDocumentLoaded,
        onDocumentError: _handleDocumentError,
        onPageChanged: (pageNumber) {
          if (!mounted || pageNumber == _currentPage) {
            return;
          }
          setState(() => _currentPage = pageNumber);
        },
        builders: PdfViewPinchBuilders<DefaultBuilderOptions>(
          options: const DefaultBuilderOptions(),
          documentLoaderBuilder: (_) => _buildPdfLoadingIndicator(),
          pageLoaderBuilder: (_) =>
              const Center(child: CircularProgressIndicator()),
          errorBuilder: (context, error) =>
              _buildPdfError(_readableError(error)),
        ),
      ),
    );
  }

  Widget _buildAiPanel() {
    return AiAssistantScreen(
      key: _assistantPanelKey,
      controller: widget.controller,
      document: widget.document,
      onNavigateToPage: _navigateToPage,
      onClose: _closeAiPanel,
    );
  }

  Widget _buildWideLayout(double width) {
    if (!_aiPanelVisible) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _buildPdfView()),
          SizedBox(
            width: 56,
            child: Center(
              child: IconButton.filledTonal(
                tooltip: 'Show AI Assistant',
                onPressed: _toggleAiPanel,
                icon: const Icon(Icons.auto_awesome),
              ),
            ),
          ),
          Offstage(
            offstage: true,
            child: SizedBox(width: 0, height: 0, child: _buildAiPanel()),
          ),
        ],
      );
    }

    final usableWidth = math.max(0, width - _dividerWidth);
    final minimumPdfFraction = math.max(0.25, 280 / usableWidth);
    final maximumPdfFraction = math.min(
      0.72,
      1 - math.min(320 / usableWidth, 0.68),
    );
    final pdfFraction = _pdfPanelFraction
        .clamp(minimumPdfFraction, maximumPdfFraction)
        .toDouble();
    final pdfWidth = usableWidth * pdfFraction;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: pdfWidth, child: _buildPdfView()),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: (details) {
            setState(() {
              _pdfPanelFraction = (pdfFraction + details.delta.dx / usableWidth)
                  .clamp(minimumPdfFraction, maximumPdfFraction)
                  .toDouble();
            });
          },
          child: SizedBox(
            width: _dividerWidth,
            child: Center(
              child: Container(
                width: 4,
                height: 48,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        ),
        Expanded(child: _buildAiPanel()),
      ],
    );
  }

  Widget _buildPhoneLayout() {
    if (_aiPanelVisible) {
      return Column(
        children: [
          Expanded(flex: 5, child: _buildPdfView()),
          Divider(
            height: 1,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          Expanded(
            flex: 6,
            child: Material(
              color: Theme.of(context).colorScheme.surface,
              child: ClipRect(child: _buildAiPanel()),
            ),
          ),
        ],
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        _buildPdfView(),
        Offstage(
          offstage: true,
          child: SizedBox(width: 0, height: 0, child: _buildAiPanel()),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_aiPanelVisible,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _closeAiPanel();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.document.name),
          actions: [
            IconButton(
              tooltip: _aiPanelVisible
                  ? 'Hide AI Assistant'
                  : 'Show AI Assistant',
              onPressed: _toggleAiPanel,
              icon: Icon(
                _aiPanelVisible
                    ? Icons.auto_awesome
                    : Icons.auto_awesome_outlined,
              ),
            ),
          ],
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= _wideLayoutBreakpoint) {
              return _buildWideLayout(constraints.maxWidth);
            }
            return _buildPhoneLayout();
          },
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                const Spacer(),
                FilledButton.icon(
                  onPressed: _toggleAiPanel,
                  icon: Icon(
                    _aiPanelVisible ? Icons.close : Icons.auto_awesome,
                  ),
                  label: Text(_aiPanelVisible ? 'Hide AI' : 'Ask AI'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
