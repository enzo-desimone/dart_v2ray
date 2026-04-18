import 'package:dart_v2ray/dart_v2ray.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('parseShareLink returns a parser object', (
    WidgetTester tester,
  ) async {
    final parsed = DartV2ray.parseShareLink(
      'vmess://eyJhZGQiOiJleGFtcGxlLmNvbSIsImFpZCI6IjAiLCJob3N0IjoiIiwiaWQiOiIxMjNlNDU2Ny1lODliLTEyZDMtYTQ1Ni00MjY2MTQxNzQwMDAiLCJuZXQiOiJ0Y3AiLCJwYXRoIjoiIiwicG9ydCI6IjQ0MyIsInBzIjoiZGVtbyIsInNjeSI6ImF1dG8iLCJ0bHMiOiIiLCJ0eXBlIjoibm9uZSIsInYiOiIyIn0=',
    );

    expect(parsed, isA<VmessUrl>());
    expect(parsed.getFullConfiguration(), contains('"outbounds"'));
  });
}
