import 'package:flutter/material.dart';

import 'app.dart';
import 'data/repository_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repositories = await ForumRepositories.create();
  runApp(LuntanApp(repositories: repositories));
}
