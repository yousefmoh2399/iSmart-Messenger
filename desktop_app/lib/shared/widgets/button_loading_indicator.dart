import 'package:flutter/cupertino.dart';

class ButtonLoadingIndicator extends StatelessWidget {
  const ButtonLoadingIndicator({super.key, this.radius = 9});

  final double radius;

  @override
  Widget build(BuildContext context) {
    return CupertinoActivityIndicator(radius: radius);
  }
}
