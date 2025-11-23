import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:dio/dio.dart';

void main() {
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    home: ImagePumperApp(),
    theme: ThemeData(primarySwatch: Colors.blue),
  ));
}

class ImagePumperApp extends StatefulWidget {
  @override
  _ImagePumperAppState createState() => _ImagePumperAppState();
}

class _ImagePumperAppState extends State<ImagePumperApp> {
  InAppWebViewController? _webViewController;
  String status = "הכנס לקישור ולחץ על 'התחל שאיבה'";
  bool isWorking = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("הפומפה - מוריד התמונות")),
      body: Column(
        children: [
          Container(
            padding: EdgeInsets.all(12),
            color: Colors.grey[200],
            child: Column(
              children: [
                Text(status, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16), textAlign: TextAlign.center),
                SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton.icon(
                      onPressed: isWorking ? null : startPumping,
                      icon: Icon(Icons.download),
                      label: Text("התחל שאיבה"),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                    ),
                    ElevatedButton.icon(
                      onPressed: stopPumping,
                      icon: Icon(Icons.stop),
                      label: Text("עצור"),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: InAppWebView(
                  initialUrlRequest: URLRequest(url: WebUri("https://www.google.com")),
                  onWebViewCreated: (controller) {
                    _webViewController = controller;
                  },
                  onLoadStop: (controller, url) async {
                    await Permission.storage.request();
                    await Permission.manageExternalStorage.request();
                  },
                ),
              ),
            ],
          ),
        );
  }

  void stopPumping() {
    setState(() {
      isWorking = false;
      status = "עצרת את הפעולה.";
    });
  }

  Future<void> startPumping() async {
    if (await Permission.storage.request().isDenied) {
       await Permission.manageExternalStorage.request();
    }

    setState(() {
      isWorking = true;
      status = "מתחיל לעבוד... נא לא לגעת במסך";
    });

    Directory dir = Directory('/storage/emulated/0/Download/PumperApp');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    int noChangeCount = 0;
    int lastHeight = 0;

    while (isWorking) {
      await downloadVisibleImages(dir);
      await _webViewController?.evaluateJavascript(source: "window.scrollBy(0, document.body.scrollHeight);");
      
      setState(() => status = "גולל וממתין לטעינה...");
      await Future.delayed(Duration(seconds: 4));

      var heightResult = await _webViewController?.evaluateJavascript(source: "document.body.scrollHeight");
      int currentHeight = int.tryParse(heightResult.toString()) ?? 0;

      if (currentHeight == lastHeight) {
        noChangeCount++;
        if (noChangeCount >= 3) {
          setState(() {
            isWorking = false;
            status = "סיימנו! כל התמונות ירדו לתיקיית Downloads/PumperApp";
          });
          break;
        }
      } else {
        noChangeCount = 0;
        lastHeight = currentHeight;
      }
    }
  }

  Future<void> downloadVisibleImages(Directory dir) async {
    var result = await _webViewController?.evaluateJavascript(source: """
      Array.from(document.querySelectorAll('img')).map(img => img.src);
    """);

    List<dynamic> urls = result ?? [];
    
    for (var urlObj in urls) {
      if (!isWorking) return;
      String url = urlObj.toString();

      if (url.startsWith("http") && (url.contains(".jpg") || url.contains(".png") || url.contains(".jpeg"))) {
        try {
          String filename = url.split('/').last.split('?').first;
          String uniqueFilename = DateTime.now().millisecondsSinceEpoch.toString() + "_" + filename;
          File file = File("${dir.path}/$uniqueFilename");
          
          if (!file.existsSync()) {
             await Dio().download(url, file.path);
          }
          
        } catch (e) {
          print("שגיאה בהורדה נקודתית: $e");
        }
      }
    }
  }
}
