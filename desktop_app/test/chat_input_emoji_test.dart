
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:desktop_app/features/chat/presentation/widgets/chat_input.dart';

void main() {
  test('ChatInput.insertTextAtSelection handles emoji insertion edge cases correctly', () {
    
    // Helper to simulate the state updates
    TextEditingValue apply(TextEditingValue value, String emoji) {
      return ChatInput.insertTextAtSelection(value, emoji);
    }

    // Case 1: Empty text
    var val = const TextEditingValue(text: '', selection: TextSelection.collapsed(offset: -1));
    val = apply(val, '??');
    expect(val.text, '??');
    expect(val.selection.baseOffset, '??'.length);

    // Case 2: Consecutive emojis
    val = apply(val, '??');
    expect(val.text, '????');
    expect(val.selection.baseOffset, '????'.length);

    // Case 3: Mid-word insertion
    val = const TextEditingValue(
      text: 'Hello world',
      selection: TextSelection.collapsed(offset: 5), // After 'Hello'
    );
    val = apply(val, '??');
    expect(val.text, 'Hello?? world');
    expect(val.selection.baseOffset, 'Hello??'.length);

    // Case 4: Compound emojis (ZWJ) like ????? and ????????
    val = const TextEditingValue(text: '', selection: TextSelection.collapsed(offset: -1));
    val = apply(val, '?????');
    expect(val.text, '?????');
    val = apply(val, '????????');
    expect(val.text, '?????????????');
    expect(val.text.contains('\uFFFD'), false);

    // Case 5: selection = -1 (unfocused or unselected text)
    val = const TextEditingValue(
      text: 'abc',
      selection: TextSelection.collapsed(offset: -1),
    );
    val = apply(val, '??');
    expect(val.text, 'abc??');
    expect(val.selection.baseOffset, 'abc??'.length);
  });
}

