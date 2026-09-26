import re

files_to_fix = [
    'lib/features/chat/presentation/chat_realtime_controller.dart',
    'lib/shared/widgets/desktop_workspace_sidebar.dart',
    'lib/features/chat/models/chat_models.dart'
]

# Mapping of corrupted text back to Arabic
replacements = {
    # chat_realtime_controller.dart
    r"'U\.O\xef\xbf\xbdO\xef\xbf\xbdU, O U,O\xef\xbf\xbdU\+'": "'متصل الآن'",
    r"'O\xef\xbf\xbdO O\xef\xbf\xbdUS O\xef\xbf\xbdO1O O_Oc O U,O O\xef\xbf\xbdO\xef\xbf\xbdO U,\.\.\.'": "'جاري إعادة الاتصال...'",
    r"'U\?O\'U, O U,O O\xef\xbf\xbdO\xef\xbf\xbdO U, O\"O U,O\'O O\xef\xbf\xbd'": "'فقد الاتصال بالسيرفر'",
    
    # workspace sidebar
    r"'U\.O\xef\xbf\xbdO\xef\xbf\xbdU, O\"O U,O3USO\xef\xbf\xbdU\?O\xef\xbf\xbd'": "'متصل بالسيرفر'",
    r"'O\xef\xbf\xbdO O\xef\xbf\xbdUS O U,O O\xef\xbf\xbdO\xef\xbf\xbdO U,\.\.\.'": "'جاري الاتصال بالسيرفر...'",
    r"'O\xef\xbf\xbdUSO\xef\xbf\xbd U\.O\xef\xbf\xbdO\xef\xbf\xbdU,'": "'غير متصل'",

    # models
    r"'U\.O\xef\xbf\xbdO\xef\xbf\xbdO\xef\xbf\xbdO U\?O\xef\xbf\xbdU\^U\? O\xef\xbf\xbdO3U\?'": "'محادثة بدون اسم'",
    r"'\?\?\?\?\?\? \?\?\?\? \?\?\?'": "'محادثة بدون اسم'"
}

for filepath in files_to_fix:
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    for corrupted, arabic in replacements.items():
        content = re.sub(corrupted, arabic, content)
        
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(content)

print('Done fixing Arabic')
