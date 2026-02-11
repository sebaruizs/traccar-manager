import 'dart:async';
import 'dart:convert';
import 'dart:collection';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:traccar_manager/error_screen.dart';
import 'package:traccar_manager/main.dart';
import 'package:traccar_manager/token_store.dart';
import 'package:url_launcher/url_launcher.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  /// 🔒 HARD LOCK DEL SERVER
  static const String _lockedUrl = 'https://gps.ridder.com.py';

  String get _baseUrl => _lockedUrl;

  final _initialized = Completer<void>();
  final _authenticated = Completer<void>();

  late final AppLinks _appLinks;
  StreamSubscription<Uri>? _appLinksSubscription;

  final _loginTokenStore = TokenStore();
  final _messaging = FirebaseMessaging.instance;

  InAppWebViewController? _controller;
  String? _loadingError;

  late String _initialUrl;
  bool _settingsReady = false;
  bool _controllerReady = false;

  // --------------------------------------------------

  @override
  void initState() {
    super.initState();
    _initWebView();
    _initAppLinks();
    _initNotifications();
  }

  @override
  void dispose() {
    _appLinksSubscription?.cancel();
    super.dispose();
  }

  // --------------------------------------------------
  // INIT
  // --------------------------------------------------

  Future<void> _initWebView() async {
    var url = _baseUrl;

    final initialMessage = await _messaging.getInitialMessage();

    if (initialMessage != null) {
      final eventId = initialMessage.data['eventId'];
      if (eventId != null) {
        url = '$url/event/$eventId';
      }
    }

    setState(() {
      _initialUrl = url;
      _settingsReady = true;
    });

    _maybeCompleteInitialized();
  }

  Future<void> _initAppLinks() async {
    await _initialized.future;

    _appLinks = AppLinks();

    _appLinksSubscription = _appLinks.uriLinkStream.listen((uri) {
      if (uri.scheme == 'org.traccar.manager') {
        final baseUri = Uri.parse(_baseUrl);

        final updatedUri = uri.replace(
          scheme: baseUri.scheme,
          host: baseUri.host,
          port: baseUri.port,
        );

        _loadUrl(updatedUri);
      } else {
        _loadUrl(uri);
      }
    });
  }

  Future<void> _initNotifications() async {
    await _initialized.future;

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      final eventId = message.data['eventId'];

      if (eventId != null) {
        _loadUrl(Uri.parse('$_baseUrl/event/$eventId'));
      }
    });

    await _messaging.requestPermission();

    await _authenticated.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {},
    );

    _messaging.onTokenRefresh.listen((token) {
      _controller?.evaluateJavascript(
        source: "updateNotificationToken?.('$token')",
      );
    });

    FirebaseMessaging.onMessage.listen((message) {
      final notification = message.notification;

      if (notification != null) {
        _controller?.evaluateJavascript(
          source:
              "handleNativeNotification?.(${jsonEncode(message.toMap())})",
        );

        messengerKey.currentState?.showSnackBar(
          SnackBar(content: Text(notification.body ?? 'Unknown')),
        );
      }
    });
  }

  void _maybeCompleteInitialized() {
    if (!_initialized.isCompleted &&
        _settingsReady &&
        _controllerReady) {
      _initialized.complete();
    }
  }

  // --------------------------------------------------
  // DOWNLOAD
  // --------------------------------------------------

  bool _isDownloadable(Uri uri) {
    final last =
        uri.pathSegments.isNotEmpty ? uri.pathSegments.last.toLowerCase() : '';

    return ['xlsx', 'kml', 'csv', 'gpx'].contains(last);
  }

  Future<void> _shareFile(String fileName, Uint8List bytes) async {
    final directory = Platform.isAndroid
        ? await getExternalStorageDirectory()
        : await getApplicationDocumentsDirectory();

    final file = File('${directory!.path}/$fileName');

    await file.writeAsBytes(bytes);

    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)]),
    );
  }

  Future<void> _downloadFile(Uri uri) async {
    try {
      final token = await _loginTokenStore.read(false);
      if (token == null) return;

      final response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final extension = uri.pathSegments.last;

        _shareFile('$timestamp.$extension', response.bodyBytes);
      }
    } catch (e) {
      developer.log('Failed to download file', error: e);
    }
  }

  // --------------------------------------------------
  // WEB MESSAGE
  // --------------------------------------------------

  void _handleWebMessage(String message) async {
    final parts = message.split('|');

    switch (parts[0]) {
      case 'login':
        if (parts.length > 1) {
          await _loginTokenStore.save(parts[1]);
        }

        try {
          final token = await _messaging.getToken();

          if (token != null) {
            _controller?.evaluateJavascript(
              source: "updateNotificationToken?.('$token')",
            );
          }
        } catch (e) {
          developer.log('Failed to get notification token', error: e);
        }
        break;

      case 'authentication':
        final loginToken = await _loginTokenStore.read(true);

        if (loginToken != null) {
          _controller?.evaluateJavascript(
            source: "handleLoginToken?.('$loginToken')",
          );
        }
        break;

      case 'authenticated':
        if (!_authenticated.isCompleted) {
          _authenticated.complete();
        }
        break;

      case 'logout':
        await _loginTokenStore.delete();
        break;

      case 'download':
        try {
          _shareFile('report.xlsx', base64Decode(parts[1]));
        } catch (e) {
          developer.log('Failed to save downloaded file', error: e);
        }
        break;

      /// 🔒 SERVER CHANGE BLOCKED
      case 'server':
        await _loginTokenStore.delete();
        await _loadUrl(Uri.parse(_baseUrl));
        break;
    }
  }

  // --------------------------------------------------

  Future<void> _loadUrl(Uri uri) async {
    await _controller?.loadUrl(
      urlRequest: URLRequest(url: WebUri(uri.toString())),
    );
  }

  bool _isRootOrLogin(String baseUrl, String? currentUrl) {
    if (currentUrl == null) return false;

    final baseUri = Uri.parse(baseUrl);
    final currentUri = Uri.parse(currentUrl);

    if (baseUri.origin != currentUri.origin) return false;

    return currentUri.path == '/' || currentUri.path == '/login';
  }

  // --------------------------------------------------
  // UI
  // --------------------------------------------------

@override
Widget build(BuildContext context) {
  if (!_settingsReady) {
    return const Center(child: CircularProgressIndicator());
  }

  if (_loadingError != null) {
    return ErrorScreen(
      error: _loadingError!,
      url: _baseUrl,
      onUrlSubmitted: (_) async {
        await _loginTokenStore.delete();

        setState(() {
          _initialUrl = _baseUrl;
          _loadingError = null;
          _controller = null;
          _controllerReady = false;
        });
      },
    );
  }

  return PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, result) {
      if (didPop) return;

      _controller?.getUrl().then((url) {
        _controller?.canGoBack().then((canGoBack) {
          if (canGoBack == true && !_isRootOrLogin(_baseUrl, url?.toString())) {
            _controller?.goBack();
          } else {
            SystemNavigator.pop();
          }
        });
      });
    },
    child: Scaffold(
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: InAppWebView(
          key: ValueKey(_initialUrl),
          initialUrlRequest: URLRequest(url: WebUri(_initialUrl)),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            useShouldOverrideUrlLoading: true,
          ),

          // ✅ Solo: Bridge + downloads + esconder botón QR (y nada más)
          // ⚠️ Importante: initialUserScripts espera UnmodifiableListView<UserScript>
          // y necesitas tener import 'dart:collection';
          initialUserScripts: UnmodifiableListView<UserScript>([
            // 1) Bridge + cola + intercept XLSX
            UserScript(
              injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END,
              source: r'''
                (function () {

                  // Icono que querés ocultar (QR/server)
                  const TARGET_D =
                    "M15 21h-2v-2h2zm-2-7h-2v5h2zm8-2h-2v4h2zm-2-2h-2v2h2zM7 12H5v2h2zm-2-2H3v2h2zm7-5h2V3h-2zm-7.5-.5v3h3v-3zM9 9H3V3h6zm-4.5 7.5v3h3v-3zM9 21H3v-6h6zm7.5-16.5v3h3v-3zM21 9h-6V3h6zm-2 10v-3h-4v2h2v3h4v-2zm-2-7h-4v2h4zm-4-2H7v2h2v2h2v-2h2zm1-1V7h-2V5h-2v4zM6.75 5.25h-1.5v1.5h1.5zm0 12h-1.5v1.5h1.5zm12-12h-1.5v1.5h1.5z";

                  function hideTarget(root) {
                    root = root || document;

                    // ✅ IMPORTANTÍSIMO: SOLO botones colorPrimary (tu botón a ocultar)
                    const btns = root.querySelectorAll(
                      'button.MuiIconButton-root.MuiIconButton-colorPrimary'
                    );

                    for (const btn of btns) {
                      if (btn.getAttribute('data-hidden-by-app') === '1') continue;

                      const p = btn.querySelector('svg path');
                      const d = p && p.getAttribute('d');

                      if (d === TARGET_D) {
                        btn.style.display = 'none';
                        btn.setAttribute('data-hidden-by-app', '1');
                      }
                    }
                  }

                  hideTarget(document);

                  const obs = new MutationObserver((mutations) => {
                    for (const m of mutations) {
                      for (const n of m.addedNodes) {
                        if (n && n.nodeType === 1) hideTarget(n);
                      }
                    }
                  });

                  obs.observe(document.documentElement, { childList: true, subtree: true });
                })();
              ''',
            ),
          ]),

          onWebViewCreated: (controller) {
            _controller = controller;

            controller.addJavaScriptHandler(
              handlerName: 'appInterface',
              callback: (args) {
                if (args.isEmpty) return null;
                _handleWebMessage(args.first.toString());
                return null;
              },
            );

            _controllerReady = true;
            _maybeCompleteInitialized();
          },

          onLoadStart: (controller, url) {
            setState(() => _loadingError = null);
          },

          shouldOverrideUrlLoading: (controller, navigationAction) async {
            final target = navigationAction.request.url;

            if (target == null) {
              return NavigationActionPolicy.ALLOW;
            }

            final uri = Uri.parse(target.toString());

            // OAuth
            if (['response_type', 'client_id', 'redirect_uri', 'scope']
                .every(uri.queryParameters.containsKey)) {
              _launchAuthorizeRequest(uri);
              return NavigationActionPolicy.CANCEL;
            }

            // Bloquea dominios externos
            if (uri.authority != Uri.parse(_baseUrl).authority) {
              try {
                launchUrl(uri, mode: LaunchMode.externalApplication);
              } catch (_) {}
              return NavigationActionPolicy.CANCEL;
            }

            // Downloads
            if (_isDownloadable(uri)) {
              _downloadFile(uri);
              return NavigationActionPolicy.CANCEL;
            }

            return NavigationActionPolicy.ALLOW;
          },
        ),
      ),
    ),
  );
}

  // --------------------------------------------------

  Future<void> _launchAuthorizeRequest(Uri uri) async {
    try {
      await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      developer.log('Failed to launch authorize request', error: e);
    }
  }
}
