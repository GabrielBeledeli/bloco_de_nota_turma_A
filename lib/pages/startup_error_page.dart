import 'package:flutter/material.dart';

class StartupErrorPage extends StatelessWidget {
  const StartupErrorPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Não foi possível conectar ao Firebase. '
            'Verifique a configuração do projeto e reinicie o app.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
