import 'dart:async';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../widgets/glass.dart';
import 'login_page.dart';
class ForgotPasswordPage extends StatefulWidget {
const ForgotPasswordPage({super.key});
@override
State<ForgotPasswordPage> createState()=>_S();}
class _S extends State<ForgotPasswordPage>{
final _e=TextEditingController();
final _c=TextEditingController();
final _p1=TextEditingController();
final _p2=TextEditingController();
final _a=AuthService();
bool _sent=false;bool _busy=false;bool _o1=true;bool _o2=true;int _cd=0;Timer? _t;
@override
void dispose(){_e.dispose();_c.dispose();_p1.dispose();_p2.dispose();_t?.cancel();super.dispose();}
void _m(String m){if(!mounted)return;ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(m)));}
Future<void> _send({bool re=false})async{
final e=_e.text.trim();
if(!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(e)){_m('Please enter a valid email address');return;}
if(re&&_cd>0)return;
setState(()=>_busy=true);
try{await _a.sendResetCode(e);if(!mounted)return;
setState((){_sent=true;_cd=60;});
_t?.cancel();
_t=Timer.periodic(const Duration(seconds:1),(t){if(!mounted){t.cancel();return;}
if(_cd<=1){t.cancel();if(mounted)setState(()=>_cd=0);}else{if(mounted)setState(()=>_cd--);}});
_m('Code sent. Check your email.');}
catch(err){_m(AuthService.friendlyMessage(err));}
finally{if(mounted)setState(()=>_busy=false);}}
Future<void> _rst()async{
final e=_e.text.trim();final c=_c.text.trim();
if(c.length<6){_m('Please enter the 6-digit code');return;}
if(_p1.text.length<8){_m('New password must be at least 8 characters');return;}
if(_p1.text!=_p2.text){_m('Passwords do not match');return;}
setState(()=>_busy=true);
try{await _a.verifyResetCodeAndSetPassword(email:e,code:c,newPassword:_p1.text);
if(!mounted)return;
Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder:(_)=>const LoginPage(notice:'Password changed. Please log in.')),(_)=>false);}
catch(err){_m(AuthService.friendlyMessage(err));if(mounted)setState(()=>_busy=false);}}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reset password'),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
      ),
      extendBodyBehindAppBar: true,
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
                    'Forgot password',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _sent
                        ? 'Enter the code sent to ${_e.text.trim()} and a new password.'
                        : 'Enter your email to get a 6-digit code.',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 20),
                  GlassField(
                    controller: _e,
                    hint: 'Email',
                    icon: Icons.email,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.done,
                  ),
                  const SizedBox(height: 12),
                  if (!_sent)
                    GlassButton(
                      label: 'Send code',
                      isLoading: _busy,
                      onPressed: _busy ? null : _send,
                    )
                  else ...[
                    GlassField(
                      controller: _c,
                      hint: '6-digit code',
                      icon: Icons.pin,
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 12),
                    GlassField(
                      controller: _p1,
                      hint: 'New password (min 8)',
                      icon: Icons.lock,
                      obscure: _o1,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _o1 ? Icons.visibility : Icons.visibility_off,
                          color: Colors.white70,
                        ),
                        onPressed: () => setState(() => _o1 = !_o1),
                      ),
                    ),
                    const SizedBox(height: 12),
                    GlassField(
                      controller: _p2,
                      hint: 'Confirm new password',
                      icon: Icons.lock_outline,
                      obscure: _o2,
                      textInputAction: TextInputAction.done,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _o2 ? Icons.visibility : Icons.visibility_off,
                          color: Colors.white70,
                        ),
                        onPressed: () => setState(() => _o2 = !_o2),
                      ),
                    ),
                    const SizedBox(height: 16),
                    GlassButton(
                      label: 'Change password',
                      isLoading: _busy,
                      onPressed: _busy ? null : _rst,
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed:
                          (_busy || _cd > 0) ? null : () => _send(re: true),
                      child: Text(
                        _cd > 0 ? 'Resend code in $_cd s' : 'Resend code',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}