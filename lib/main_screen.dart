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
              injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
              source: r'''
                (function () {
                  // Bridge Flutter
                  window.appInterface = {
                    postMessage: function(message) {
                      if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
                        window.flutter_inappwebview.callHandler('appInterface', message);
                      } else {
                        window.__traccarMessageQueue = window.__traccarMessageQueue || [];
                        window.__traccarMessageQueue.push(message);
                      }
                    }
                  };

                  // Vacia cola cuando el handler esté listo
                  window.addEventListener('flutterInAppWebViewPlatformReady', function() {
                    if (window.__traccarMessageQueue &&
                        window.flutter_inappwebview &&
                        window.flutter_inappwebview.callHandler) {
                      window.__traccarMessageQueue.forEach(function(message) {
                        window.flutter_inappwebview.callHandler('appInterface', message);
                      });
                      window.__traccarMessageQueue = [];
                    }
                  });

                  // Intercepta XLSX generados como Blob
                  const excelType = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
                  const originalCreateObjectURL = URL.createObjectURL;

                  URL.createObjectURL = function(object) {
                    try {
                      if (object instanceof Blob && object.type === excelType) {
                        const reader = new FileReader();
                        reader.onload = () => {
                          // envia base64 al lado nativo
                          window.appInterface.postMessage('download|' + reader.result.split(',')[1]);
                        };
                        reader.readAsDataURL(object);
                      }
                    } catch (e) {}
                    return originalCreateObjectURL.apply(this, arguments);
                  };
                })();
              ''',
            ),

            // 2) 🔒 SOLO oculta el botón QR (IconButton de MUI) por CLASES + SVG
            //    Esto es más robusto que matchear el "d" completo.
            UserScript(
              injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END,
              source: r'''
                (function () {
                  // Botón QR en tu captura:
                  // <button class="MuiButtonBase-root MuiIconButton-root ... muiltr-9sn16m">
                  //   <svg ...><path d="..."></path></svg>
                  // </button>

                  function hideQrButton(root) {
                    root = root || document;

                    // 1) Intenta por clases estables de MUI (ignora las muiltr-xxxxx)
                    const btns = root.querySelectorAll('button.MuiIconButton-root');

                    for (const btn of btns) {
                      // tiene SVG adentro
                      const hasSvg = !!btn.querySelector('svg');
                      if (!hasSvg) continue;

                      // Para no esconder otros IconButtons (ej: ojo password),
                      // filtramos por tamaño típico del QR (40x40 en tu inspector),
                      // pero tolerando variaciones.
                      const r = btn.getBoundingClientRect();
                      const looksLikeQr =
                        (r.width >= 34 && r.width <= 48 && r.height >= 34 && r.height <= 48);

                      if (looksLikeQr) {
                        btn.style.display = 'none';
                        btn.setAttribute('data-hidden-by-app', '1');
                      }
                    }
                  }

                  // Ejecuta una vez
                  hideQrButton(document);

                  // Observa re-renders (MUI / React)
                  const obs = new MutationObserver((mutations) => {
                    for (const m of mutations) {
                      for (const n of m.addedNodes) {
                        if (n && n.nodeType === 1) hideQrButton(n);
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
