import 'dart:io';

const String animatedLottieUrlBase =
    "https://raw.githubusercontent.com/googlefonts/noto-emoji/main/third_party/lottie/wave1/";

const List<String> popularAnimated = [
  "1f600",
  "1f602",
  "1f60d",
  "1f62d",
  "1f618",
  "1f621",
  "1f44d",
  "1f44e",
  "2764",
  "1f525",
  "1f389",
  "1f44f",
  "1f64f",
  "1f923",
  "1f60a",
  "1f60e",
  "1f970",
  "1f609",
  "1f614",
  "1f631",
];

Future<void> downloadFile(String url, String dest) async {
  final file = File(dest);
  if (file.existsSync()) return;
  try {
    final client = HttpClient();
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close();
    if (response.statusCode == 200) {
      await response.pipe(file.openWrite());
      print("Downloaded: $dest");
    } else {
      print("Failed to download $url - Status: ${response.statusCode}");
    }
    client.close();
  } catch (e) {
    print("Error downloading $url: $e");
  }
}

void main() async {
  final assetsDir = Directory('assets');
  final lottieDir = Directory('${assetsDir.path}/animated_emoji_lottie');

  if (!lottieDir.existsSync()) lottieDir.createSync(recursive: true);

  print("Downloading Lottie emojis...");
  for (final code in popularAnimated) {
    final url = "${animatedLottieUrlBase}emoji_u$code.json";
    final dest = "${lottieDir.path}/emoji_u$code.json";
    await downloadFile(url, dest);
  }

  print("Done!");
}
