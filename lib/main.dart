import 'package:flutter/material.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:provider/provider.dart';
import 'models/image_state.dart';
import 'models/crop_state.dart';
import 'screens/editor_screen.dart';
import 'services/raw_processor.dart';
import 'services/preferences_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize services
  await PreferencesService.initialize();
  RawProcessor.initialize();
  
  runApp(const AksApp());
  
  doWhenWindowReady(() {
    const initialSize = Size(1200, 800);
    appWindow.minSize = const Size(800, 600);
    appWindow.size = initialSize;
    appWindow.alignment = Alignment.center;
    appWindow.show();
  });
}

class AksApp extends StatelessWidget {
  const AksApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ImageState()),
        ChangeNotifierProvider(create: (_) => CropState()),
      ],
      child: MaterialApp(
        title: 'AKS',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          primaryColor: const Color(0xFF1E1E1E),
          scaffoldBackgroundColor: const Color(0xFF121212),
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF1E1E1E),
            secondary: Color(0xFF3D3D3D),
            surface: Color(0xFF2D2D2D),
            background: Color(0xFF121212),
          ),
          useMaterial3: true,
        ),
        home: const EditorScreen(),
      ),
    );
  }
}