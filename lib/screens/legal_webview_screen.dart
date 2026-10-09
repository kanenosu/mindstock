import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// プライバシーポリシーとサポートをアプリ内で確認するための画面。
/// App Review中もログインや外部ブラウザなしで内容へ到達できる。
class LegalWebViewScreen extends StatefulWidget {
  final String title;
  final Uri uri;

  const LegalWebViewScreen({super.key, required this.title, required this.uri});

  @override
  State<LegalWebViewScreen> createState() => _LegalWebViewScreenState();
}

class _LegalWebViewScreenState extends State<LegalWebViewScreen> {
  late final WebViewController _controller;
  var _loading = true;
  String? _error;

  String get _assetPath => widget.uri.path.endsWith('/support')
      ? 'backend/public/support.html'
      : 'backend/public/privacy.html';

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.disabled)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame != true) return;
            if (mounted) {
              setState(() {
                _loading = false;
                _error = error.description;
              });
            }
          },
        ),
      )
      // The public Render URL can briefly show a cold-start holding page.
      // Bundle the same reviewed text so it is always available immediately,
      // including offline and during App Review.
      ..loadFlutterAsset(_assetPath);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Stack(
        children: [
          if (_error == null)
            WebViewWidget(controller: _controller)
          else
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off_outlined, size: 36),
                    const SizedBox(height: 12),
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () {
                        setState(() {
                          _loading = true;
                          _error = null;
                        });
                        _controller.loadFlutterAsset(_assetPath);
                      },
                      child: const Text('Retry / 再試行'),
                    ),
                  ],
                ),
              ),
            ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
        ],
      ),
    );
  }
}
