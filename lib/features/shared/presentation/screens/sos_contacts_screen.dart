import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/user_model.dart';
import '../../../../core/providers/app_providers.dart';
import '../../../../core/theme/app_colors.dart';

/// "Safety & SOS contacts" — lets the user maintain a short list of
/// emergency contacts who are notified (via SMS/push, server-side) when
/// the in-app SOS button is triggered (Safety & Reliability section).
class SosContactsScreen extends ConsumerStatefulWidget {
  const SosContactsScreen({super.key});

  @override
  ConsumerState<SosContactsScreen> createState() => _SosContactsScreenState();
}

class _SosContactsScreenState extends ConsumerState<SosContactsScreen> {
  bool _saving = false;

  Future<void> _saveContacts(String uid, List<SosContact> contacts) async {
    setState(() => _saving = true);
    try {
      await ref.read(authServiceProvider).updateUserFields(uid, {
        'sosContacts': contacts.map((c) => c.toMap()).toList(),
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _editContact(String uid, List<SosContact> contacts, {int? index}) async {
    final nameController = TextEditingController(text: index != null ? contacts[index].name : '');
    final phoneController = TextEditingController(text: index != null ? contacts[index].phone : '');

    final result = await showDialog<SosContact>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(index == null ? 'Add emergency contact' : 'Edit emergency contact'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Name'),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: phoneController,
              decoration: const InputDecoration(labelText: 'Phone number', hintText: '+213...'),
              keyboardType: TextInputType.phone,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final name = nameController.text.trim();
              final phone = phoneController.text.trim();
              if (name.isEmpty || phone.isEmpty) return;
              Navigator.pop(ctx, SosContact(name: name, phone: phone));
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result == null) return;

    final updated = List<SosContact>.from(contacts);
    if (index == null) {
      updated.add(result);
    } else {
      updated[index] = result;
    }
    await _saveContacts(uid, updated);
  }

  Future<void> _removeContact(String uid, List<SosContact> contacts, int index) async {
    final updated = List<SosContact>.from(contacts)..removeAt(index);
    await _saveContacts(uid, updated);
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(userProfileProvider);
    final uid = ref.watch(authStateProvider).value;

    return Scaffold(
      appBar: AppBar(title: const Text('Safety & SOS contacts')),
      body: profileAsync.when(
        data: (profile) {
          if (profile == null || uid == null) {
            return const Center(child: Text('Profile not found.'));
          }
          final contacts = profile.sosContacts;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.08), borderRadius: BorderRadius.circular(12)),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline_rounded, color: AppColors.primary, size: 20),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'These contacts are notified with your live location if you press the SOS button during a ride.',
                        style: TextStyle(fontSize: 12, color: AppColors.textPrimary),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (contacts.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: Text('No emergency contacts added yet.', style: TextStyle(color: AppColors.textSecondary)),
                  ),
                )
              else
                ...List.generate(contacts.length, (index) {
                  final contact = contacts[index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14)),
                    child: ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: AppColors.danger,
                        child: Icon(Icons.shield_rounded, color: Colors.white, size: 18),
                      ),
                      title: Text(contact.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(contact.phone),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 20),
                            onPressed: _saving ? null : () => _editContact(uid, contacts, index: index),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger, size: 20),
                            onPressed: _saving ? null : () => _removeContact(uid, contacts, index),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _saving || contacts.length >= 3 ? null : () => _editContact(uid, contacts),
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: Text(contacts.length >= 3 ? 'Maximum of 3 contacts reached' : 'Add emergency contact'),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}
