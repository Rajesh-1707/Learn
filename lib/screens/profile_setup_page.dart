import 'dart:math';

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../widgets/glass.dart';
import '../widgets/avatar_picker.dart';
import 'recovery_code_page.dart';

const _langs = [
  'Telugu',
  'Hindi',
  'Tamil',
  'Kannada',
  'Malayalam',
  'Bengali',
  'Marathi',
  'Gujarati',
  'Urdu',
  'Odia',
  'Punjabi',
  'English',
  'Other',
];
const _states = [
  'Andhra Pradesh',
  'Arunachal Pradesh',
  'Assam',
  'Bihar',
  'Chhattisgarh',
  'Goa',
  'Gujarat',
  'Haryana',
  'Himachal Pradesh',
  'Jharkhand',
  'Karnataka',
  'Kerala',
  'Madhya Pradesh',
  'Maharashtra',
  'Manipur',
  'Meghalaya',
  'Mizoram',
  'Nagaland',
  'Odisha',
  'Punjab',
  'Rajasthan',
  'Sikkim',
  'Tamil Nadu',
  'Telangana',
  'Tripura',
  'Uttar Pradesh',
  'Uttarakhand',
  'West Bengal',
];

class ProfileSetupPage extends StatefulWidget {
  final VoidCallback onSaved;
  const ProfileSetupPage({super.key, required this.onSaved});
  @override
  State<ProfileSetupPage> createState() => _P();
}

class _P extends State<ProfileSetupPage> {
  final _name = TextEditingController();
  final _city = TextEditingController();
  final _a = AuthService();
  static const _recoveryAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  String _newRecoveryCode() {
    final r = Random.secure();
    return List.generate(
      8,
      (_) => _recoveryAlphabet[r.nextInt(_recoveryAlphabet.length)],
    ).join();
  }

  String? _gender;
  String? _lang;
  String? _state;
  DateTime? _dob;
  bool _busy = false;
  String? _avatarUrl;
  @override
  void dispose() {
    _name.dispose();
    _city.dispose();
    super.dispose();
  }

  void _m(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      _m('Please enter your full name');
      return;
    }
    if (_gender == null) {
      _m('Please choose your gender');
      return;
    }
    if (_lang == null) {
      _m('Please choose your native language');
      return;
    }
    if (_dob == null) {
      _m('Please select your date of birth');
      return;
    }
    if (_city.text.trim().isEmpty) {
      _m('Please enter your city');
      return;
    }
    if (_state == null) {
      _m('Please choose your state');
      return;
    }
    setState(() => _busy = true);
    try {
      await _a.saveProfile(
        fullName: _name.text.trim(),
        gender: _gender!,
        nativeLanguage: _lang!,
        dob: _dob!,
        city: _city.text,
        state: _state!,
      );
      final code = _newRecoveryCode();
      await _a.saveRecoveryCode(code);
      if (!mounted) return;
      final saved = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => RecoveryCodePage(code: code)),
      );
      if (saved == true && mounted) {
        widget.onSaved();
      } else if (mounted) {
        setState(() => _busy = false);
      }
    } catch (e) {
      _m(AuthService.friendlyMessage(e));
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _chip(String v, String label) {
    final s = _gender == v;
    return GestureDetector(
      onTap: () => setState(() => _gender = v),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: s
              ? Colors.white.withValues(alpha: 0.45)
              : Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: s ? Colors.white : Colors.white.withValues(alpha: 0.3),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: s ? Colors.deepPurple : Colors.white,
            fontWeight: s ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GlassBackground(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: GlassCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Complete your profile',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'One quick step before you start.',
                    style: TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 20),
                  Center(
                    child: AvatarPicker(
                      avatarUrl: _avatarUrl,
                      fallbackName: _name.text,
                      onChanged: (u) => setState(() => _avatarUrl = u),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Center(
                    child: Text(
                      'Profile photo (optional)',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ),
                  const SizedBox(height: 16),
                  GlassField(
                    controller: _name,
                    hint: 'Full name',
                    icon: Icons.person,
                  ),
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: _busy
                        ? null
                        : () async {
                            final now = DateTime.now();
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: DateTime(
                                now.year - 18,
                                now.month,
                                now.day,
                              ),
                              firstDate: DateTime(1900),
                              lastDate: now,
                            );
                            if (picked != null) setState(() => _dob = picked);
                          },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 18,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.cake, color: Colors.white),
                          const SizedBox(width: 12),
                          Text(
                            _dob == null
                                ? 'Date of birth'
                                : '${_dob!.day.toString().padLeft(2, '0')}/${_dob!.month.toString().padLeft(2, '0')}/${_dob!.year}',
                            style: TextStyle(
                              color: _dob == null
                                  ? Colors.white70
                                  : Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  GlassField(
                    controller: _city,
                    hint: 'City',
                    icon: Icons.location_city,
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _state,
                        hint: const Text(
                          'Select state',
                          style: TextStyle(color: Colors.white70),
                        ),
                        dropdownColor: const Color(0xFF5B3BA8),
                        style: const TextStyle(color: Colors.white),
                        icon: const Icon(
                          Icons.arrow_drop_down,
                          color: Colors.white,
                        ),
                        isExpanded: true,
                        items: _states
                            .map(
                              (s) => DropdownMenuItem(value: s, child: Text(s)),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => _state = v),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Gender',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _chip('male', 'Male'),
                      const SizedBox(width: 8),
                      _chip('female', 'Female'),
                      const SizedBox(width: 8),
                      _chip('other', 'Other'),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Gender is used for call matching. Please choose honestly.',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Native language',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _lang,
                        hint: const Text(
                          'Select language',
                          style: TextStyle(color: Colors.white70),
                        ),
                        dropdownColor: const Color(0xFF5B3BA8),
                        style: const TextStyle(color: Colors.white),
                        icon: const Icon(
                          Icons.arrow_drop_down,
                          color: Colors.white,
                        ),
                        isExpanded: true,
                        items: _langs
                            .map(
                              (l) => DropdownMenuItem(value: l, child: Text(l)),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => _lang = v),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  GlassButton(
                    label: 'Save and continue',
                    isLoading: _busy,
                    onPressed: _busy ? null : _save,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
