import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:quran_dub/main.dart';

void main() {
  testWidgets('Home screen shows app title', (WidgetTester tester) async {
    await tester.pumpWidget(const QuranDubApp());

    expect(find.text('تلاوة وتفسير'), findsWidgets);
  });
}
