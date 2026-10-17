import 'package:flutter/material.dart';

import '../ui/theme.dart';

/// Uputstvo napisano za nekoga ko ne koristi često telefon — kratko i jasno.
void showHelpSheet(BuildContext context) {
  final t = Theme.of(context).textTheme;
  Widget q(String question, String answer) => Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(question, style: t.titleMedium),
          const SizedBox(height: 4),
          Text(answer, style: t.bodyLarge?.copyWith(color: AppColors.inkSoft)),
        ]),
      );

  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    builder: (context) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          children: [
            Text('Pomoć', style: t.headlineMedium),
            const SizedBox(height: 18),
            q('Kako da izaberem fotografiju?', 'Dodirnite krug u gornjem desnom uglu fotografije. Kada postane zelen sa kvačicom, fotografija je izabrana.'),
            q('Kako da vidim fotografiju u velikom?', 'Dodirnite samu fotografiju. Prstom prevucite levo ili desno za sledeću. Za povratak pritisnite „Zatvori”.'),
            q('Pogrešno sam izabrao/la. Šta sada?', 'Samo ponovo dodirnite zeleni krug — fotografija više nije izabrana.'),
            q('Da li moram nešto da sačuvam?', 'Ne. Sve se čuva samo od sebe. Možete zatvoriti stranicu i kasnije nastaviti na istom telefonu.'),
            q('Kako da pošaljem izbor?', 'Pritisnite zeleno dugme „Dalje” na dnu ekrana, upišite svoje ime i pritisnite „Pošalji izbor fotografu”.'),
            q('Mogu li da dobijem više primeraka iste fotografije?', 'Da. Kada izaberete fotografiju, pritisnite + kod „Primeraka”. Sve fotografije se štampaju u istoj veličini.'),
            const SizedBox(height: 4),
            FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Razumem')),
          ],
        ),
      ),
    ),
  );
}
