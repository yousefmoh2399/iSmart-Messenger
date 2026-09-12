import 'dart:io';

const String notoPngUrlBase = "https://raw.githubusercontent.com/googlefonts/noto-emoji/main/png/72/";
const String animatedLottieUrlBase = "https://raw.githubusercontent.com/googlefonts/noto-emoji/main/third_party/lottie/wave1/";

const List<String> popularAnimated = [
    "1f600", "1f602", "1f60d", "1f62d", "1f618", "1f621", "1f44d", "1f44e",
    "2764", "1f525", "1f389", "1f44f", "1f64f", "1f923", "1f60a", "1f60e",
    "1f970", "1f609", "1f614", "1f631"
];

const List<String> popularEmojisUnicode = [
    // Faces
    "1f600", "1f603", "1f604", "1f601", "1f606", "1f605", "1f923", "1f602", "1f642", "1f643",
    "1f609", "1f60a", "1f607", "1f970", "1f60d", "1f929", "1f618", "1f617", "1f61a", "1f619",
    "1f60b", "1f61b", "1f61c", "1f92a", "1f61d", "1f911", "1f917", "1f92d", "1f92b", "1f914",
    "1f910", "1f928", "1f610", "1f611", "1f636", "1f60f", "1f612", "1f644", "1f62c", "1f925",
    "1f60c", "1f614", "1f62a", "1f924", "1f634", "1f637", "1f912", "1f915", "1f922", "1f92e",
    "1f927", "1f975", "1f976", "1f974", "1f635", "1f92f", "1f920", "1f973", "1f60e", "1f913",
    "1f9d0", "1f615", "1f61f", "1f641", "2639", "1f62e", "1f62f", "1f632", "1f633", "1f97a",
    "1f626", "1f627", "1f628", "1f630", "1f625", "1f622", "1f62d", "1f631", "1f616", "1f623",
    "1f61e", "1f613", "1f629", "1f62b", "1f971", "1f624", "1f621", "1f620", "1f92c", "1f608",
    "1f47f", "1f480", "1f4a9", "1f47b", "1f47d",
    // Hands
    "1f44d", "1f44e", "1f44c", "270c", "1f91e", "1f91f", "1f918", "1f919", "1f448", "1f449",
    "1f446", "1f447", "261d", "270b", "1f91a", "1f590", "1f596", "1f44b", "1f91b", "1f91c",
    "1f44a", "270a", "1f44f", "1f64c", "1f450", "1f932", "1f64f",
    // Hearts & Symbols
    "2764", "1f9e1", "1f49b", "1f49a", "1f499", "1f49c", "1f5a4", "1f90d", "1f494", "2763",
    "1f495", "1f49e", "1f493", "1f497", "1f496", "1f498", "1f49d", "1f49f", "262e", "271d",
    "1f525", "2728", "1f31f", "1f4ab",
    // Objects & Activities
    "1f389", "1f388", "1f381", "1f382", "1f4a5", "1f38a", "1f3c6", "1f3c5", "1f947", "1f948", "1f949",
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
  final pngDir = Directory('${assetsDir.path}/noto_emojis_png');
  final lottieDir = Directory('${assetsDir.path}/animated_emoji_lottie');

  if (!pngDir.existsSync()) pngDir.createSync(recursive: true);
  if (!lottieDir.existsSync()) lottieDir.createSync(recursive: true);

  print("Downloading PNG emojis...");
  for (final code in popularEmojisUnicode) {
    final url = "${notoPngUrlBase}emoji_u$code.png";
    final dest = "${pngDir.path}/emoji_u$code.png";
    await downloadFile(url, dest);
  }

  print("Downloading Lottie emojis...");
  for (final code in popularAnimated) {
    final url = "${animatedLottieUrlBase}emoji_u$code.json";
    final dest = "${lottieDir.path}/emoji_u$code.json";
    await downloadFile(url, dest);
  }

  print("Done!");
}
