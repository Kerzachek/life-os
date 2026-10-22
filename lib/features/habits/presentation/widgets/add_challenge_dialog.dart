import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/widgets/responsive.dart';
import '../providers/habits_provider.dart';

class AddChallengeDialog extends ConsumerStatefulWidget {
  const AddChallengeDialog({super.key});

  @override
  ConsumerState<AddChallengeDialog> createState() => _AddChallengeDialogState();
}

class _AddChallengeDialogState extends ConsumerState<AddChallengeDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now().add(const Duration(days: 30));

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() ?? false) {
      ref.read(habitsControllerProvider).createChallenge(
            title: _titleController.text.trim(),
            description: _descriptionController.text.trim().isEmpty
                ? null
                : _descriptionController.text.trim(),
            startDate: _startDate,
            endDate: _endDate,
          );
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd.MM.yyyy');

    return AdaptiveFormDialog(
      title: const Text('Новый челлендж'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Название челленджа *',
                  hintText: '30 дней без сахара, Марафон чтения...',
                  border: OutlineInputBorder(),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Введите название челленджа';
                  }
                  return null;
                },
                autofocus: true,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Правила и цель',
                  hintText: 'Каждый день читать по 20 страниц...',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.play_arrow, size: 18),
                      label: Text('Старт: ${dateFormat.format(_startDate)}'),
                      onPressed: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: _startDate,
                          firstDate: DateTime.now().subtract(const Duration(days: 30)),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                        );
                        if (date != null) {
                          setState(() => _startDate = date);
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.flag, size: 18),
                      label: Text('Финиш: ${dateFormat.format(_endDate)}'),
                      onPressed: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: _endDate,
                          firstDate: _startDate,
                          lastDate: _startDate.add(const Duration(days: 365)),
                        );
                        if (date != null) {
                          setState(() => _endDate = date);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Запустить'),
        ),
      ],
    );
  }
}
