
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ══════════════════════════════════════════════════════════════
// ENTRY POINT
// ══════════════════════════════════════════════════════════════

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PrimeYardBootstrapApp());
}

class PrimeYardBootstrapApp extends StatefulWidget {
  const PrimeYardBootstrapApp({super.key});
  @override State<PrimeYardBootstrapApp> createState() => _BootAppState();
}
class _BootAppState extends State<PrimeYardBootstrapApp> {
  late final Future<_BP> _f = _init();
  Future<_BP> _init() async {
    String? e;
    try { await BS.init().timeout(const Duration(seconds: 12)); } catch (x) { e = 'Firebase init failed: $x'; }
    return _BP(s: await AppSession.load(), e: e);
  }
  @override
  Widget build(BuildContext ctx) => FutureBuilder<_BP>(
    future: _f,
    builder: (ctx, snap) {
      if (!snap.hasData) return MaterialApp(debugShowCheckedModeBanner: false,
        home: Scaffold(backgroundColor: P.deep, body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Image.asset('assets/logo-mark.png', width: 90),
          const SizedBox(height: 20),
          const CircularProgressIndicator(color: Colors.white),
          const SizedBox(height: 14),
          const Text('Starting PrimeYard…', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        ]))));
      return PrimeYardApp(session: snap.data!.s, startupErr: snap.data!.e);
    },
  );
}
class _BP { final AppSession s; final String? e; _BP({required this.s, this.e}); }

// ══════════════════════════════════════════════════════════════
// CONFIG & PALETTE
// ══════════════════════════════════════════════════════════════

class Cfg {
  static const opts = FirebaseOptions(
    apiKey: 'AIzaSyAf0ziL9na5z7CPodC33T1SjQVBOCXUFCg',
    appId: '1:1063126418476:android:d42f77528438d22ac7bd89',
    messagingSenderId: '1063126418476',
    projectId: 'primeyard-521ea',
    storageBucket: 'primeyard-521ea.firebasestorage.app',
  );
}

class P {
  static const green  = Color(0xFF1A6B30);
  static const deep   = Color(0xFF0D3B1A);
  static const soft   = Color(0xFF2F8A4B);
  static const gold   = Color(0xFFF2B632);
  static const cream  = Color(0xFFF5F1E8);
  static const text   = Color(0xFF171717);
  static const muted  = Color(0xFF6D665D);
  static const border = Color(0xFFE6DED0);
  static const danger = Color(0xFFC62828);
  static const infoBg = Color(0xFFE3F2FD);
  static const infoFg = Color(0xFF1565C0);
}

// ══════════════════════════════════════════════════════════════
// SESSION
// ══════════════════════════════════════════════════════════════

class AppSession {
  final bool loggedIn;
  final String id, username, displayName, role;
  const AppSession({this.loggedIn=false,this.id='',this.username='',this.displayName='',this.role=''});
  bool get isAdmin => role=='admin'||role=='master_admin';
  bool get isMaster => role=='master_admin';
  bool get isSupervisor => role=='supervisor';
  bool get isWorker => role=='worker';
  static Future<AppSession> load() async {
    final p = await SharedPreferences.getInstance();
    return AppSession(loggedIn:p.getBool('li')??false,id:p.getString('uid')??'',username:p.getString('un')??'',displayName:p.getString('dn')??'',role:p.getString('role')??'');
  }
  Future<void> persist() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('li',loggedIn); await p.setString('uid',id);
    await p.setString('un',username); await p.setString('dn',displayName); await p.setString('role',role);
  }
  static Future<void> clear() async => (await SharedPreferences.getInstance()).clear();
}

// ══════════════════════════════════════════════════════════════
// PRICING CONSTANTS
// ══════════════════════════════════════════════════════════════

// Package base prices per visit [launch, full] indexed by size tier (0=0-300m², 1=301-600, 2=601-1000, 3=1000+)
const kPackagePrices = {
  'PrimeBasic':  [[350.0,450.0],[500.0,650.0],[700.0,900.0],[950.0,1200.0]],
  'PrimeCare':   [[500.0,650.0],[700.0,900.0],[950.0,1200.0],[1300.0,1600.0]],
  'PrimeElite':  [[700.0,900.0],[950.0,1200.0],[1300.0,1650.0],[1750.0,2200.0]],
};
const kPackageIncludes = {
  'PrimeBasic':  'Lawn mowing, leaf blowing, basic edge trimming',
  'PrimeCare':   'Lawn mowing, full edging & trimming, cleanup & blow, bed tidying',
  'PrimeElite':  'Full PrimeCare + hedge trimming, weed removal, fertilization, detailed cleanup',
};
const kSizeTiers = [300.0, 600.0, 1000.0];
const kAddOns = {
  'Hedge trimming':       200.0,
  'Extra leaf cleanup':   150.0,
  'Fertilization':        300.0,
  'Weed treatment':       250.0,
  'Irrigation check':     350.0,
  'Paving/path clean':    200.0,
  'Tree trimming (small)':450.0,
  'Gutter cleaning':      380.0,
  'Pool surround':        280.0,
};

int _sizeTier(double sqm) {
  if (sqm <= kSizeTiers[0]) return 0;
  if (sqm <= kSizeTiers[1]) return 1;
  if (sqm <= kSizeTiers[2]) return 2;
  return 3;
}

// ══════════════════════════════════════════════════════════════
// WORKSPACE STATE
// ══════════════════════════════════════════════════════════════

class WS {
  final List<dynamic> clients,invoices,jobs,emps,quotes,equipment,checkLogs,clockEntries,users;
  final String schedDate;
  final DateTime? updatedAt;
  const WS({required this.clients,required this.invoices,required this.jobs,required this.emps,required this.quotes,required this.equipment,required this.checkLogs,required this.clockEntries,required this.users,required this.schedDate,this.updatedAt});
  factory WS.empty() => WS(clients:[],invoices:[],jobs:[],emps:[],quotes:[],equipment:[],checkLogs:[],clockEntries:[],users:[],schedDate:_today());
  factory WS.fromMap(Map<String,dynamic>? m) {
    final d = m??{};
    return WS(clients:List.from(d['clients']??[]),invoices:List.from(d['invoices']??[]),jobs:List.from(d['jobs']??[]),emps:List.from(d['emps']??[]),quotes:List.from(d['quotes']??[]),equipment:List.from(d['equipment']??[]),checkLogs:List.from(d['checkLogs']??[]),clockEntries:List.from(d['clockEntries']??[]),users:List.from(d['users']??[]),schedDate:(d['schedDate']??_today()).toString(),updatedAt:d['updatedAt'] is Timestamp?(d['updatedAt'] as Timestamp).toDate():d['updatedAt'] is String?DateTime.tryParse(d['updatedAt']):null);
  }
  Map<String,dynamic> toMap() => {'clients':clients,'invoices':invoices,'jobs':jobs,'emps':emps,'quotes':quotes,'equipment':equipment,'checkLogs':checkLogs,'clockEntries':clockEntries,'users':users,'schedDate':schedDate};
  WS copyWith({List<dynamic>? clients,List<dynamic>? invoices,List<dynamic>? jobs,List<dynamic>? emps,List<dynamic>? quotes,List<dynamic>? equipment,List<dynamic>? checkLogs,List<dynamic>? clockEntries,List<dynamic>? users,String? schedDate}) =>
    WS(clients:clients??this.clients,invoices:invoices??this.invoices,jobs:jobs??this.jobs,emps:emps??this.emps,quotes:quotes??this.quotes,equipment:equipment??this.equipment,checkLogs:checkLogs??this.checkLogs,clockEntries:clockEntries??this.clockEntries,users:users??this.users,schedDate:schedDate??this.schedDate,updatedAt:updatedAt);
}

// ══════════════════════════════════════════════════════════════
// BACKEND SERVICE
// ══════════════════════════════════════════════════════════════

class BBoot { final WS st; final String? err; final bool live; const BBoot({required this.st,this.err,required this.live}); }

class BS {
  static final _auth = fb.FirebaseAuth.instance;
  static final _doc  = FirebaseFirestore.instance.collection('primeyard').doc('sharedState');
  static final _photos = FirebaseFirestore.instance.collection('py_photos');
  static Future<void> init() async { if (Firebase.apps.isEmpty) await Firebase.initializeApp(options: Cfg.opts); }
  static Future<void> _auth2() async { await init(); if (_auth.currentUser==null) { await _auth.signInAnonymously(); if (_auth.currentUser==null) await _auth.authStateChanges().firstWhere((u)=>u!=null); } }
  static Future<void> _cache(Map<String,dynamic> d) async => (await SharedPreferences.getInstance()).setString('wsc',jsonEncode(_safe(d)));
  static Future<void> _cacheU(List u) async => (await SharedPreferences.getInstance()).setString('usc',jsonEncode(_safe(u)));
  static Future<WS> _cached() async { final r=(await SharedPreferences.getInstance()).getString('wsc'); if(r==null||r.isEmpty)return WS.empty(); try{return WS.fromMap(jsonDecode(r));}catch(_){return WS.empty();} }
  static Future<List<Map<String,dynamic>>> _cachedU() async { final r=(await SharedPreferences.getInstance()).getString('usc'); if(r==null||r.isEmpty)return[]; try{return(jsonDecode(r) as List).whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();}catch(_){return[];} }

  static Future<BBoot> bootstrap() async {
    try {
      await _auth2();
      final s = await _doc.get(const GetOptions(source: Source.serverAndCache));
      if (!s.exists) { final c=await _cached(); return BBoot(st:c,live:false,err:'No Firestore document found.'); }
      final d = Map<String,dynamic>.from(s.data()??{});
      await _cache(d); await _cacheU(List.from(d['users']??[]));
      final st = WS.fromMap(d);
      return BBoot(st:st,live:st.users.isNotEmpty||st.clients.isNotEmpty||st.jobs.isNotEmpty);
    } on fb.FirebaseAuthException catch(e){final c=await _cached();return BBoot(st:c,live:false,err:'[auth/${e.code}] ${e.message}');}
      on FirebaseException catch(e){final c=await _cached();return BBoot(st:c,live:false,err:'[fb/${e.code}] ${e.message}');}
      catch(e){final c=await _cached();return BBoot(st:c,live:false,err:e.toString());}
  }

  static Stream<WS> stream() async* {
    try { await _auth2(); yield* _doc.snapshots().asyncMap((s) async { if(!s.exists)return await _cached(); final d=Map<String,dynamic>.from(s.data()??{}); await _cache(d); await _cacheU(List.from(d['users']??[])); return WS.fromMap(d); }); }
    catch(_) { yield await _cached(); }
  }

  static Future<WS> get() async {
    try { await _auth2(); final s=await _doc.get(const GetOptions(source:Source.serverAndCache)); if(!s.exists)return await _cached(); final d=Map<String,dynamic>.from(s.data()??{}); await _cache(d); await _cacheU(List.from(d['users']??[])); return WS.fromMap(d); }
    catch(_) { return await _cached(); }
  }

  static Future<void> save(WS st, {String by='app'}) async {
    await _auth2();
    await _doc.set({...st.toMap(),'updatedAt':FieldValue.serverTimestamp(),'updatedBy':by},SetOptions(merge:true));
    await _cache(st.toMap()); await _cacheU(st.users);
  }

  static Future<Map<String,dynamic>?> login(String u, String pw) async {
    final uh=u.toLowerCase(); final h=_hash(pw);
    Future<Map<String,dynamic>?> chk(List list) async { for(final e in list){if(e is Map){final r=Map<String,dynamic>.from(e);if((r['username']??'').toString().toLowerCase()==uh&&(r['passwordHash']??'')==h)return r;}}return null; }
    final st=await get(); return await chk(st.users)??await chk(await _cachedU());
  }

  static Future<String?> savePhoto(String jobId, String type, File file) async {
    try {
      await _auth2();
      final bytes=await file.readAsBytes();
      // Compress: store only if under 800KB, else just metadata
      if (bytes.length > 800000) return null;
      final ref=_photos.doc();
      await ref.set({'jid':jobId,'t':type,'d':base64Encode(bytes),'by':_auth.currentUser?.uid??'','ts':FieldValue.serverTimestamp()});
      return ref.id;
    } catch(_) { return null; }
  }

  static Future<Uint8List?> loadPhoto(String id) async {
    try { final doc=await _photos.doc(id).get(); if(!doc.exists)return null; final b64=doc.data()?['d'] as String?; return b64!=null?base64Decode(b64):null; } catch(_){return null;}
  }
}

// ══════════════════════════════════════════════════════════════
// APP ROOT
// ══════════════════════════════════════════════════════════════

class PrimeYardApp extends StatefulWidget {
  final AppSession session; final String? startupErr;
  const PrimeYardApp({super.key,required this.session,this.startupErr});
  @override State<PrimeYardApp> createState() => _AppState();
}
class _AppState extends State<PrimeYardApp> {
  late AppSession _s = widget.session;
  void _onIn(AppSession s) => setState(()=>_s=s);
  Future<void> _onOut() async { await AppSession.clear(); setState(()=>_s=const AppSession()); }
  @override
  Widget build(BuildContext ctx) {
    final cs = ColorScheme.fromSeed(seedColor:P.green,primary:P.green,secondary:P.gold,brightness:Brightness.light);
    return MaterialApp(
      debugShowCheckedModeBanner:false, title:'PrimeYard Workspace',
      theme: ThemeData(
        useMaterial3:true, colorScheme:cs, scaffoldBackgroundColor:P.cream,
        textTheme:Theme.of(ctx).textTheme.apply(bodyColor:P.text,displayColor:P.text),
        appBarTheme:const AppBarTheme(backgroundColor:Colors.transparent,elevation:0,foregroundColor:P.text),
        cardTheme:CardTheme(color:Colors.white,elevation:0,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(20),side:const BorderSide(color:P.border))),
        inputDecorationTheme:InputDecorationTheme(filled:true,fillColor:Colors.white,contentPadding:const EdgeInsets.symmetric(horizontal:14,vertical:13),border:OutlineInputBorder(borderRadius:BorderRadius.circular(14),borderSide:const BorderSide(color:P.border)),enabledBorder:OutlineInputBorder(borderRadius:BorderRadius.circular(14),borderSide:const BorderSide(color:P.border)),focusedBorder:OutlineInputBorder(borderRadius:BorderRadius.circular(14),borderSide:const BorderSide(color:P.green,width:1.5))),
        chipTheme:ChipThemeData(shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(99))),
      ),
      home: _s.loggedIn ? Shell(s:_s,onOut:_onOut,onUpd:_onIn) : LoginScreen(onIn:_onIn,bootErr:widget.startupErr),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// LOGIN
// ══════════════════════════════════════════════════════════════

class LoginScreen extends StatefulWidget {
  final ValueChanged<AppSession> onIn; final String? bootErr;
  const LoginScreen({super.key,required this.onIn,this.bootErr});
  @override State<LoginScreen> createState() => _LoginState();
}
class _LoginState extends State<LoginScreen> {
  final _u=TextEditingController(),_p=TextEditingController();
  bool _loading=true; String? _err; BBoot? _boot;
  @override void initState(){super.initState();_doBoot();}
  Future<void> _doBoot() async { final b=await BS.bootstrap(); if(!mounted)return; setState((){_boot=b;_loading=false;if(b.err!=null&&b.st.users.isEmpty)_err=b.err;}); }
  Future<void> _login() async {
    FocusScope.of(context).unfocus(); setState((){_loading=true;_err=null;});
    final u=await BS.login(_u.text.trim(),_p.text);
    if(u==null){setState((){_err='Incorrect username or password.';_loading=false;});return;}
    final s=AppSession(loggedIn:true,id:(u['id']??'').toString(),username:(u['username']??'').toString(),displayName:(u['displayName']??u['username']??'User').toString(),role:(u['role']??'worker').toString());
    await s.persist(); widget.onIn(s);
  }
  @override
  Widget build(BuildContext ctx)=>Scaffold(body:Container(
    decoration:const BoxDecoration(gradient:LinearGradient(colors:[P.deep,P.green,P.soft],begin:Alignment.topLeft,end:Alignment.bottomRight)),
    child:SafeArea(child:Center(child:SingleChildScrollView(padding:const EdgeInsets.all(20),child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:480),child:Card(child:Padding(padding:const EdgeInsets.fromLTRB(22,22,22,26),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Center(child:Image.asset('assets/logo-full.png',height:56)),
      const SizedBox(height:6),
      Text('Business Manager',textAlign:TextAlign.center,style:Theme.of(ctx).textTheme.titleMedium?.copyWith(color:P.muted,fontWeight:FontWeight.w600)),
      const SizedBox(height:6),
      Text('Your property, our pride.',textAlign:TextAlign.center,style:Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight:FontWeight.w800)),
      const SizedBox(height:12),
      Image.asset('assets/mascot.png',height:130,fit:BoxFit.contain),
      const SizedBox(height:12),
      if(_boot!=null)Container(padding:const EdgeInsets.all(10),decoration:BoxDecoration(color:const Color(0xFFF7F4EC),borderRadius:BorderRadius.circular(12),border:Border.all(color:P.border)),child:Row(children:[Icon(_boot!.live?Icons.cloud_done_rounded:Icons.cloud_off_rounded,color:_boot!.live?P.green:P.danger,size:15),const SizedBox(width:6),Expanded(child:Text(_boot!.live?'Live workspace connected':'Using cached data',style:const TextStyle(fontWeight:FontWeight.w700,fontSize:12)))])),
      const SizedBox(height:12),
      TextField(controller:_u,textInputAction:TextInputAction.next,decoration:const InputDecoration(labelText:'Username',prefixIcon:Icon(Icons.person_outline_rounded))),
      const SizedBox(height:8),
      TextField(controller:_p,obscureText:true,onSubmitted:(_)=>_login(),decoration:const InputDecoration(labelText:'Password',prefixIcon:Icon(Icons.lock_outline_rounded))),
      if(_err!=null)...[const SizedBox(height:8),Container(padding:const EdgeInsets.all(10),decoration:BoxDecoration(color:const Color(0xFFFFEBEE),borderRadius:BorderRadius.circular(10)),child:Text(_err!,style:const TextStyle(color:P.danger,fontWeight:FontWeight.w700,fontSize:12)))],
      const SizedBox(height:14),
      FilledButton.icon(
        onPressed:_loading?null:_login,
        icon:_loading?const SizedBox(width:16,height:16,child:CircularProgressIndicator(strokeWidth:2,color:Colors.white)):const Icon(Icons.login_rounded),
        label:Padding(padding:const EdgeInsets.symmetric(vertical:11),child:Text(_loading?'Signing in…':'Sign in',style:const TextStyle(fontSize:15,fontWeight:FontWeight.w700))),
        style:FilledButton.styleFrom(backgroundColor:P.green,foregroundColor:Colors.white,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(14))),
      ),
    ])))))))
  ));
}

// ══════════════════════════════════════════════════════════════
// SHELL
// ══════════════════════════════════════════════════════════════

class Shell extends StatefulWidget {
  final AppSession s; final Future<void> Function() onOut; final ValueChanged<AppSession> onUpd;
  const Shell({super.key,required this.s,required this.onOut,required this.onUpd});
  @override State<Shell> createState() => _ShellState();
}
class _ShellState extends State<Shell> {
  int _i=0;
  @override
  Widget build(BuildContext ctx)=>StreamBuilder<WS>(
    stream:BS.stream(),
    builder:(ctx,snap){
      if(snap.connectionState==ConnectionState.waiting&&!snap.hasData)return const Scaffold(body:Center(child:CircularProgressIndicator()));
      final st=snap.data??WS.empty();
      final pages=_pages(widget.s,st);
      if(_i>=pages.length)_i=0;
      final cur=pages[_i];
      return Scaffold(
        appBar:AppBar(titleSpacing:14,title:Row(children:[Image.asset('assets/logo-mark.png',width:24,height:24),const SizedBox(width:8),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(cur.lbl,style:const TextStyle(fontWeight:FontWeight.w800,fontSize:16)),Text(widget.s.displayName,style:const TextStyle(fontSize:10,color:P.muted))]))]),
          actions:[IconButton(onPressed:()=>_profile(ctx,st),icon:CircleAvatar(backgroundColor:P.green,radius:14,child:Text(_ini(widget.s.displayName),style:const TextStyle(color:Colors.white,fontSize:10,fontWeight:FontWeight.w800))))]),
        body:AnimatedSwitcher(duration:const Duration(milliseconds:180),child:cur.build(ctx,st)),
        bottomNavigationBar:NavigationBar(height:64,selectedIndex:_i,destinations:[for(final p in pages) NavigationDestination(icon:Icon(p.ico),label:p.short)],onDestinationSelected:(v)=>setState(()=>_i=v)),
      );
    },
  );

  void _profile(BuildContext ctx,WS st){
    showModalBottomSheet(context:ctx,shape:const RoundedRectangleBorder(borderRadius:BorderRadius.vertical(top:Radius.circular(22))),builder:(_)=>SafeArea(child:Padding(padding:const EdgeInsets.all(20),child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Row(children:[CircleAvatar(backgroundColor:P.green,radius:20,child:Text(_ini(widget.s.displayName),style:const TextStyle(color:Colors.white,fontWeight:FontWeight.w800))),const SizedBox(width:10),Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(widget.s.displayName,style:const TextStyle(fontWeight:FontWeight.w900,fontSize:16)),Text('@${widget.s.username} · ${widget.s.role}',style:const TextStyle(color:P.muted,fontSize:11))])]),
      const SizedBox(height:14),
      _mTile(ctx,Icons.lock_outline_rounded,'Change password',null,(){Navigator.pop(ctx);_changePw(ctx,st);}),
      _mTile(ctx,Icons.logout_rounded,'Sign out',P.danger,(){Navigator.pop(ctx);widget.onOut();}),
    ]))));
  }
  ListTile _mTile(BuildContext ctx,IconData ico,String t,Color? col,VoidCallback fn)=>ListTile(leading:Icon(ico,color:col),title:Text(t,style:TextStyle(color:col)),shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(12)),onTap:fn);

  void _changePw(BuildContext ctx,WS st){
    final o=TextEditingController(),n=TextEditingController(),c2=TextEditingController();
    String? err;
    showDialog(context:ctx,builder:(dx)=>StatefulBuilder(builder:(dx,ss)=>AlertDialog(shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(20)),title:const Text('Change Password',style:TextStyle(fontWeight:FontWeight.w900)),content:Column(mainAxisSize:MainAxisSize.min,children:[_pwf(o,'Current password'),const SizedBox(height:8),_pwf(n,'New password'),const SizedBox(height:8),_pwf(c2,'Confirm new password'),if(err!=null)...[const SizedBox(height:8),Text(err!,style:const TextStyle(color:P.danger,fontWeight:FontWeight.w700,fontSize:12))]]),
      actions:[TextButton(onPressed:()=>Navigator.pop(dx),child:const Text('Cancel')),FilledButton(onPressed:() async {
        if(o.text.isEmpty||n.text.isEmpty||c2.text.isEmpty){ss(()=>err='All fields required.');return;}
        if(n.text!=c2.text){ss(()=>err='Passwords do not match.');return;}
        if(n.text.length<6){ss(()=>err='Min 6 chars.');return;}
        final cu=st.users.whereType<Map>().firstWhere((u)=>(u['username']??'').toString().toLowerCase()==widget.s.username.toLowerCase(),orElse:()=>{});
        if(cu.isEmpty){ss(()=>err='User not found.');return;}
        if(_hash(o.text)!=(cu['passwordHash']??'')){ss(()=>err='Current password incorrect.');return;}
        final up=st.users.whereType<Map>().map((u){final r=Map<String,dynamic>.from(u);if((r['username']??'').toString().toLowerCase()==widget.s.username.toLowerCase())r['passwordHash']=_hash(n.text);return r;}).toList();
        await BS.save(st.copyWith(users:up),by:widget.s.username);
        if(dx.mounted)Navigator.pop(dx);
        if(ctx.mounted)_snack(ctx,'Password changed!');
      },child:const Text('Change'))])));
  }

  TextField _pwf(TextEditingController c,String l)=>TextField(controller:c,obscureText:true,decoration:InputDecoration(labelText:l));

  List<_PD> _pages(AppSession s,WS st){
    if(s.isWorker)return[_PD('My Route','Route',Icons.route_rounded,(c,st)=>WorkerRoute(s:s,st:st)),_PD('Clock','Clock',Icons.access_time_rounded,(c,st)=>ClockPage(s:s,st:st)),_PD('Equipment','Equip',Icons.handyman_rounded,(c,st)=>EquipPage(st:st,s:s))];
    if(s.isSupervisor)return[_PD('Dashboard','Home',Icons.dashboard_rounded,(c,st)=>DashPage(st:st)),_PD('Schedule','Jobs',Icons.calendar_month_rounded,(c,st)=>SchedulePage(st:st,s:s)),_PD('Equipment','Equip',Icons.handyman_rounded,(c,st)=>EquipPage(st:st,s:s)),_PD('Jobs Log','Log',Icons.task_alt_rounded,(c,st)=>JobsLogPage(st:st)),_PD('Clock','Clock',Icons.punch_clock_rounded,(c,st)=>ClockEntPage(st:st))];
    return[_PD('Dashboard','Home',Icons.dashboard_rounded,(c,st)=>DashPage(st:st)),_PD('Clients','Clients',Icons.people_alt_rounded,(c,st)=>ClientsPage(st:st,s:s)),_PD('Invoices','Bills',Icons.receipt_long_rounded,(c,st)=>InvoicesPage(st:st,s:s)),_PD('Schedule','Jobs',Icons.calendar_month_rounded,(c,st)=>SchedulePage(st:st,s:s)),_PD('Staff','Staff',Icons.badge_rounded,(c,st)=>EmpsPage(st:st,s:s)),_PD('More','More',Icons.tune_rounded,(c,st)=>MorePage(st:st,s:s))];
  }
}
class _PD{final String lbl,short;final IconData ico;final Widget Function(BuildContext,WS) build;_PD(this.lbl,this.short,this.ico,this.build);}

// ══════════════════════════════════════════════════════════════
// WORKER — ROUTE
// ══════════════════════════════════════════════════════════════

class WorkerRoute extends StatelessWidget {
  final AppSession s; final WS st;
  const WorkerRoute({super.key,required this.s,required this.st});
  @override
  Widget build(BuildContext ctx){
    final jobs=st.jobs.whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).where((j){final w=(j['workerName']??'').toString().toLowerCase();return(w==s.displayName.toLowerCase()||w==s.username.toLowerCase()||w.isEmpty)&&(j['date']??'')==st.schedDate;}).toList();
    final done=jobs.where((j)=>j['done']==true).length;
    return ListView(padding:const EdgeInsets.fromLTRB(14,8,14,100),children:[
      _SH(title:'My Route',sub:'${st.schedDate} · $done/${jobs.length} done'),
      for(final j in jobs) _JCard(job:j,onTap:()=>_go(ctx,JobDetail(job:j,s:s,st:st))),
      if(jobs.isEmpty)const _Emp(ico:Icons.route_rounded,t:'No route today',s:'No jobs assigned to you yet.'),
    ]);
  }
}

class _JCard extends StatelessWidget {
  final Map<String,dynamic> job; final VoidCallback onTap;
  const _JCard({required this.job,required this.onTap});
  @override
  Widget build(BuildContext ctx){
    final done=job['done']==true; final ip=job['status']=='in_progress';
    return Padding(padding:const EdgeInsets.only(bottom:10),child:Card(child:InkWell(borderRadius:BorderRadius.circular(20),onTap:onTap,child:Padding(padding:const EdgeInsets.all(14),child:Row(children:[
      Icon(done?Icons.check_circle_rounded:ip?Icons.play_circle_rounded:Icons.radio_button_unchecked_rounded,color:done?P.green:ip?P.gold:P.muted,size:26),
      const SizedBox(width:10),
      Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text((job['name']??'Client').toString(),style:const TextStyle(fontWeight:FontWeight.w800,fontSize:15)),
        if((job['address']??'').toString().isNotEmpty)Text(job['address'].toString(),style:const TextStyle(color:P.muted,fontSize:12)),
        if(ip&&(job['startedAt']??'').isNotEmpty)_Timer(ts:job['startedAt'].toString()),
        if((job['notes']??'').toString().isNotEmpty)Text('📝 ${job['notes']}',style:const TextStyle(color:P.green,fontSize:11)),
      ])),
      if(done)Container(margin:const EdgeInsets.only(left:4),padding:const EdgeInsets.symmetric(horizontal:7,vertical:3),decoration:BoxDecoration(color:P.green.withOpacity(.1),borderRadius:BorderRadius.circular(99)),child:const Text('Done',style:TextStyle(color:P.green,fontWeight:FontWeight.w800,fontSize:11))),
      const Icon(Icons.chevron_right_rounded,color:P.muted,size:18),
    ])))));
  }
}

class _Timer extends StatefulWidget {
  final String ts; const _Timer({required this.ts});
  @override State<_Timer> createState()=>_TimerState();
}
class _TimerState extends State<_Timer>{
  Timer? _t; Duration _el=Duration.zero;
  @override void initState(){super.initState();_tick();_t=Timer.periodic(const Duration(seconds:1),(_)=>_tick());}
  @override void dispose(){_t?.cancel();super.dispose();}
  void _tick(){try{final st=DateTime.parse(widget.ts).toLocal();if(mounted)setState(()=>_el=DateTime.now().difference(st));}catch(_){}}
  String _fmt(Duration d)=>'${d.inHours.toString().padLeft(2,'0')}:${(d.inMinutes%60).toString().padLeft(2,'0')}:${(d.inSeconds%60).toString().padLeft(2,'0')}';
  @override Widget build(BuildContext ctx)=>Text('⏱ ${_fmt(_el)}',style:const TextStyle(color:P.gold,fontWeight:FontWeight.w700,fontSize:11));
}

// ══════════════════════════════════════════════════════════════
// JOB DETAIL
// ══════════════════════════════════════════════════════════════

class JobDetail extends StatefulWidget {
  final Map<String,dynamic> job; final AppSession s; final WS st;
  const JobDetail({super.key,required this.job,required this.s,required this.st});
  @override State<JobDetail> createState()=>_JDState();
}
class _JDState extends State<JobDetail>{
  late Map<String,dynamic> _j;
  final _nc=TextEditingController();
  bool _saving=false; String? _pErr;
  final _pk=ImagePicker();
  @override void initState(){super.initState();_j=Map<String,dynamic>.from(widget.job);_nc.text=(_j['notes']??'').toString();}
  bool get _done=>_j['done']==true; bool get _ip=>_j['status']=='in_progress';
  Future<void> _start()async{final now=DateTime.now();setState((){_j['status']='in_progress';_j['startedAt']=now.toIso8601String();_j['startedBy']=widget.s.username;});await _save();}
  Future<void> _done2()async{final now=DateTime.now();setState((){_j['done']=true;_j['status']='done';_j['completedAt']=now.toIso8601String();_j['completedBy']=widget.s.username;});await _save();}
  Future<void> _pend()async{setState((){_j['done']=false;_j['status']='pending';_j.remove('completedAt');_j.remove('completedBy');});await _save();}
  Future<void> _saveNotes()async{setState((){_j['notes']=_nc.text.trim();_saving=true;});await _save();setState(()=>_saving=false);if(mounted)_snack(context,'Notes saved');}
  Future<void> _photo(String type)async{
    setState(()=>_pErr=null);
    try{
      final pk=await _pk.pickImage(source:ImageSource.camera,imageQuality:35,maxWidth:800,maxHeight:800);
      if(pk==null)return;
      setState(()=>_saving=true);
      final id=await BS.savePhoto(_j['id'].toString(),type,File(pk.path));
      if(id!=null){final k=type=='before'?'beforePhotos':'afterPhotos';final l=List<String>.from(_j[k]??[]);l.add(id);setState((){_j[k]=l;});await _save();if(mounted)_snack(context,'Photo saved ✓');}
      else setState(()=>_pErr='Upload failed — check your connection. Photos must be under 800KB.');
    }catch(e){setState(()=>_pErr='Camera error: $e');}
    setState(()=>_saving=false);
  }
  Future<void> _save()async{final u=widget.st.jobs.whereType<Map>().map((e){final r=Map<String,dynamic>.from(e);if(r['id']==_j['id'])return Map<String,dynamic>.from(_j);return r;}).toList();await BS.save(widget.st.copyWith(jobs:u),by:widget.s.username);}
  @override
  Widget build(BuildContext ctx){
    final before=List<String>.from(_j['beforePhotos']??[]);
    final after=List<String>.from(_j['afterPhotos']??[]);
    return Scaffold(
      appBar:AppBar(title:Text((_j['name']??'Job').toString(),style:const TextStyle(fontWeight:FontWeight.w900))),
      body:ListView(padding:const EdgeInsets.fromLTRB(14,8,14,100),children:[
        // Status + actions
        Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          Row(children:[Icon(_done?Icons.check_circle_rounded:_ip?Icons.play_circle_rounded:Icons.circle_outlined,color:_done?P.green:_ip?P.gold:P.muted,size:20),const SizedBox(width:7),Text(_done?'Completed':_ip?'In Progress':'Pending',style:TextStyle(fontWeight:FontWeight.w800,color:_done?P.green:_ip?P.gold:P.muted,fontSize:14))]),
          if((_j['address']??'').toString().isNotEmpty)...[const SizedBox(height:5),Row(children:[const Icon(Icons.location_on_rounded,color:P.muted,size:14),const SizedBox(width:4),Expanded(child:Text(_j['address'].toString(),style:const TextStyle(color:P.muted,fontSize:12)))])],
          if(_ip&&(_j['startedAt']??'').isNotEmpty)...[const SizedBox(height:8),_Timer(ts:_j['startedAt'].toString())],
          if(_done&&(_j['completedAt']??'').isNotEmpty)...[const SizedBox(height:5),Text('✓ Completed ${_fmtDT(_j['completedAt'].toString())}',style:const TextStyle(color:P.green,fontSize:11))],
          const SizedBox(height:14),
          if(!_done&&!_ip)FilledButton.icon(onPressed:_saving?null:_start,icon:const Icon(Icons.play_arrow_rounded),label:const Padding(padding:EdgeInsets.symmetric(vertical:10),child:Text('Start Job',style:TextStyle(fontSize:15,fontWeight:FontWeight.w700))),style:FilledButton.styleFrom(backgroundColor:P.gold,foregroundColor:Colors.white,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(12)))),
          if(_ip)FilledButton.icon(onPressed:_saving?null:_done2,icon:const Icon(Icons.check_rounded),label:const Padding(padding:EdgeInsets.symmetric(vertical:10),child:Text('Mark as Done',style:TextStyle(fontSize:15,fontWeight:FontWeight.w700))),style:FilledButton.styleFrom(backgroundColor:P.green,foregroundColor:Colors.white,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(12)))),
          if(!_done&&!_ip)...[const SizedBox(height:6),OutlinedButton.icon(onPressed:_saving?null:_done2,icon:const Icon(Icons.check_rounded,size:15),label:const Text('Skip to Done'),style:OutlinedButton.styleFrom(shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(12))))],
          if(_done)...[FilledButton.icon(onPressed:_saving?null:_pend,icon:const Icon(Icons.undo_rounded),label:const Text('Mark as Pending'),style:FilledButton.styleFrom(backgroundColor:P.muted,foregroundColor:Colors.white,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(12))))],
        ]))),
        const SizedBox(height:10),
        // Notes
        Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[const Text('Job Notes',style:TextStyle(fontWeight:FontWeight.w800,fontSize:14)),const SizedBox(height:8),TextField(controller:_nc,maxLines:3,decoration:const InputDecoration(hintText:'Site notes, observations, instructions…')),const SizedBox(height:8),OutlinedButton.icon(onPressed:_saving?null:_saveNotes,icon:_saving?const SizedBox(width:14,height:14,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.save_rounded,size:15),label:const Text('Save Notes'),style:OutlinedButton.styleFrom(shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(12))))]))),
        const SizedBox(height:10),
        if(_pErr!=null)Container(margin:const EdgeInsets.only(bottom:10),padding:const EdgeInsets.all(10),decoration:BoxDecoration(color:const Color(0xFFFFEBEE),borderRadius:BorderRadius.circular(10)),child:Text(_pErr!,style:const TextStyle(color:P.danger,fontSize:12))),
        _PhotoSec(title:'Before Photos',ids:before,onAdd:_saving?null:()=>_photo('before')),
        const SizedBox(height:10),
        _PhotoSec(title:'After Photos',ids:after,onAdd:_saving?null:()=>_photo('after')),
      ]),
    );
  }
}

class _PhotoSec extends StatelessWidget {
  final String title; final List<String> ids; final VoidCallback? onAdd;
  const _PhotoSec({required this.title,required this.ids,this.onAdd});
  @override Widget build(BuildContext ctx)=>Card(child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[Text(title,style:const TextStyle(fontWeight:FontWeight.w800,fontSize:14)),if(onAdd!=null)FilledButton.icon(onPressed:onAdd,icon:const Icon(Icons.camera_alt_rounded,size:13),label:const Text('Take Photo'),style:FilledButton.styleFrom(backgroundColor:P.green,foregroundColor:Colors.white,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(10)),padding:const EdgeInsets.symmetric(horizontal:10,vertical:7),textStyle:const TextStyle(fontSize:12,fontWeight:FontWeight.w700)))]),
    if(ids.isNotEmpty)...[const SizedBox(height:10),SizedBox(height:100,child:ListView.separated(scrollDirection:Axis.horizontal,itemCount:ids.length,separatorBuilder:(_,__)=>const SizedBox(width:7),itemBuilder:(_,i)=>_FSPic(id:ids[i])))]
    else...[const SizedBox(height:6),const Text('No photos yet',style:TextStyle(color:P.muted,fontSize:12))],
  ])));
}

class _FSPic extends StatefulWidget {
  final String id; const _FSPic({required this.id});
  @override State<_FSPic> createState()=>_FSPicState();
}
class _FSPicState extends State<_FSPic>{
  Uint8List? _b; bool _loading=true;
  @override void initState(){super.initState();BS.loadPhoto(widget.id).then((b){if(mounted)setState((){_b=b;_loading=false;});});}
  @override Widget build(BuildContext ctx){
    if(_loading)return ClipRRect(borderRadius:BorderRadius.circular(8),child:Container(width:100,height:100,color:P.border,child:const Center(child:CircularProgressIndicator(strokeWidth:2))));
    if(_b==null)return ClipRRect(borderRadius:BorderRadius.circular(8),child:Container(width:100,height:100,color:P.border,child:const Icon(Icons.broken_image_rounded,color:P.muted)));
    return GestureDetector(onTap:()=>showDialog(context:ctx,builder:(_)=>Dialog(child:InteractiveViewer(child:Image.memory(_b!)))),child:ClipRRect(borderRadius:BorderRadius.circular(8),child:Image.memory(_b!,width:100,height:100,fit:BoxFit.cover)));
  }
}

// ══════════════════════════════════════════════════════════════
// CLOCK
// ══════════════════════════════════════════════════════════════

class ClockPage extends StatefulWidget {
  final AppSession s; final WS st;
  const ClockPage({super.key,required this.s,required this.st});
  @override State<ClockPage> createState()=>_ClockState();
}
class _ClockState extends State<ClockPage>{
  bool _saving=false; Timer? _t; Duration _el=Duration.zero;
  @override void initState(){super.initState();_tick();_t=Timer.periodic(const Duration(seconds:1),(_)=>_tick());}
  @override void dispose(){_t?.cancel();super.dispose();}
  void _tick(){final ci=_lastIn;if(ci!=null){try{final st=DateTime.parse(ci['timestamp'].toString()).toLocal();if(mounted)setState(()=>_el=DateTime.now().difference(st));}catch(_){}}else{if(mounted)setState(()=>_el=Duration.zero);}}
  List<Map<String,dynamic>> get _mine=>widget.st.clockEntries.whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).where((e)=>(e['username']??'').toString().toLowerCase()==widget.s.username.toLowerCase()).toList()..sort((a,b)=>(b['timestamp']??'').toString().compareTo((a['timestamp']??'').toString()));
  Map<String,dynamic>? get _lastIn{final td=_mine.where((e)=>(e['date']??'')==_today()).toList();return td.isNotEmpty&&td.first['type']=='in'?td.first:null;}
  bool get _in=>_lastIn!=null;
  Future<void> _clock(String type)async{setState(()=>_saving=true);final now=DateTime.now();final e={'id':now.millisecondsSinceEpoch.toString(),'userId':widget.s.id,'username':widget.s.username,'displayName':widget.s.displayName,'type':type,'timestamp':now.toIso8601String(),'date':_today()};await BS.save(widget.st.copyWith(clockEntries:[...widget.st.clockEntries,e]),by:widget.s.username);setState(()=>_saving=false);}
  String _fmtEl(Duration d)=>'${d.inHours.toString().padLeft(2,'0')}:${(d.inMinutes%60).toString().padLeft(2,'0')}:${(d.inSeconds%60).toString().padLeft(2,'0')}';
  @override
  Widget build(BuildContext ctx){
    final today=_mine.where((e)=>(e['date']??'')==_today()).toList();
    return ListView(padding:const EdgeInsets.fromLTRB(14,8,14,100),children:[
      _SH(title:'My Clock',sub:_today()),
      Card(child:Padding(padding:const EdgeInsets.all(22),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        Container(padding:const EdgeInsets.all(18),decoration:BoxDecoration(color:_in?const Color(0xFFE8F5E9):const Color(0xFFFFF8E1),borderRadius:BorderRadius.circular(16)),child:Column(children:[
          Icon(_in?Icons.login_rounded:Icons.logout_rounded,size:42,color:_in?P.green:P.gold),
          const SizedBox(height:6),
          Text(_in?'CLOCKED IN':'CLOCKED OUT',style:TextStyle(fontWeight:FontWeight.w900,fontSize:16,color:_in?P.green:const Color(0xFFE65100))),
          const SizedBox(height:3),
          Text(DateFormat('HH:mm · EEEE d MMM').format(DateTime.now()),style:const TextStyle(color:P.muted,fontSize:12)),
          if(_in&&_el.inSeconds>0)...[const SizedBox(height:10),Container(padding:const EdgeInsets.symmetric(horizontal:16,vertical:7),decoration:BoxDecoration(color:P.green.withOpacity(.12),borderRadius:BorderRadius.circular(99)),child:Text(_fmtEl(_el),style:const TextStyle(fontWeight:FontWeight.w900,fontSize:28,color:P.green))),const SizedBox(height:2),const Text('time clocked in',style:TextStyle(color:P.muted,fontSize:11))],
        ])),
        const SizedBox(height:16),
        FilledButton.icon(
          onPressed:_saving?null:()=>_clock(_in?'out':'in'),
          icon:_saving?const SizedBox(width:16,height:16,child:CircularProgressIndicator(strokeWidth:2,color:Colors.white)):Icon(_in?Icons.logout_rounded:Icons.login_rounded),
          label:Padding(padding:const EdgeInsets.symmetric(vertical:13),child:Text(_in?'Clock Out':'Clock In',style:const TextStyle(fontSize:16,fontWeight:FontWeight.w800))),
          style:FilledButton.styleFrom(backgroundColor:_in?P.danger:P.green,foregroundColor:Colors.white,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(12))),
        ),
      ]))),
      const SizedBox(height:12),
      _SH(title:"Today's Activity",sub:'${today.length} entries'),
      for(final e in today)Padding(padding:const EdgeInsets.only(bottom:6),child:Card(child:ListTile(leading:CircleAvatar(backgroundColor:e['type']=='in'?const Color(0xFFE8F5E9):const Color(0xFFFFEBEE),child:Icon(e['type']=='in'?Icons.login_rounded:Icons.logout_rounded,color:e['type']=='in'?P.green:P.danger,size:15)),title:Text(e['type']=='in'?'Clocked In':'Clocked Out',style:const TextStyle(fontWeight:FontWeight.w800)),trailing:Text(_fmtDT(e['timestamp']??''),style:const TextStyle(color:P.muted,fontSize:11))))),
      if(today.isEmpty)const _Emp(ico:Icons.access_time_rounded,t:'No entries today',s:'Tap above to clock in.'),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════
// EQUIPMENT
// ══════════════════════════════════════════════════════════════

class EquipPage extends StatelessWidget {
  final WS st; final AppSession s;
  const EquipPage({super.key,required this.st,required this.s});
  Future<void> _seed()async{if(st.equipment.isNotEmpty)return;const seed=[{'id':'eq1','name':'Brush cutter','status':'ok'},{'id':'eq2','name':'Lawn mower','status':'ok'},{'id':'eq3','name':'Blower','status':'ok'},{'id':'eq4','name':'Hedge trimmer','status':'ok'},{'id':'eq5','name':'Compactor','status':'ok'}];await BS.save(st.copyWith(equipment:seed),by:s.username);}
  void _check(BuildContext ctx,Map<String,dynamic> item){
    String sel=(item['status']??'ok').toString();
    final nc=TextEditingController();
    showDialog(context:ctx,builder:(dx)=>StatefulBuilder(builder:(dx,ss)=>AlertDialog(
      shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(20)),
      title:Text('Check: ${item['name']}',style:const TextStyle(fontWeight:FontWeight.w900,fontSize:16)),
      content:Column(mainAxisSize:MainAxisSize.min,children:[
        const Text('Select condition:',style:TextStyle(color:P.muted,fontSize:12)),const SizedBox(height:10),
        Row(mainAxisAlignment:MainAxisAlignment.center,children:[for(final st in ['ok','issue','missing'])Padding(padding:const EdgeInsets.symmetric(horizontal:3),child:ChoiceChip(label:Text(st.toUpperCase(),style:TextStyle(fontWeight:FontWeight.w800,fontSize:12,color:sel==st?Colors.white:P.text)),selected:sel==st,selectedColor:st=='ok'?P.green:st=='issue'?P.gold:P.danger,onSelected:(_)=>ss(()=>sel=st)))]),
        const SizedBox(height:12),
        TextField(controller:nc,maxLines:2,decoration:const InputDecoration(labelText:'Notes (optional)',hintText:'Describe any issues…')),
      ]),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(dx),child:const Text('Cancel')),
        FilledButton.icon(
          onPressed:()async{
            Navigator.pop(dx);
            final ue=this.st.equipment.whereType<Map>().map((e){final r=Map<String,dynamic>.from(e);if(r['id']==item['id'])r['status']=sel;return r;}).toList();
            final now=DateTime.now();
            final log={'id':now.millisecondsSinceEpoch.toString(),'equipmentId':item['id'],'equipmentName':item['name'],'status':sel,'notes':nc.text.trim(),'submittedBy':s.username,'submittedByName':s.displayName,'date':_today(),'timestamp':now.toIso8601String()};
            await BS.save(this.st.copyWith(equipment:ue,checkLogs:[...this.st.checkLogs,log]),by:s.username);
            if(ctx.mounted)_snack(ctx,'Check submitted for ${item['name']}');
          },
          icon:const Icon(Icons.check_rounded),label:const Text('Submit Check'),
          style:FilledButton.styleFrom(backgroundColor:P.green,foregroundColor:Colors.white,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(10))),
        ),
      ],
    )));
  }
  @override
  Widget build(BuildContext ctx){
    final items=st.equipment.whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();
    if(items.isEmpty)_seed();
    return ListView(padding:const EdgeInsets.fromLTRB(14,8,14,100),children:[
      _SH(title:'Equipment Checks',sub:'${items.length} items · ${_today()}'),
      Container(margin:const EdgeInsets.only(bottom:12),padding:const EdgeInsets.all(10),decoration:BoxDecoration(color:P.infoBg,borderRadius:BorderRadius.circular(12)),child:const Text('Tap an item → select condition → Submit Check to log it.',style:TextStyle(color:P.infoFg,fontSize:12))),
      for(final item in items)Padding(padding:const EdgeInsets.only(bottom:10),child:Card(child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Row(children:[const Icon(Icons.handyman_rounded,color:P.green,size:20),const SizedBox(width:8),Expanded(child:Text((item['name']??'').toString(),style:const TextStyle(fontWeight:FontWeight.w800,fontSize:14))),_Pill(text:(item['status']??'ok').toString())]),
        const SizedBox(height:10),
        SizedBox(width:double.infinity,child:OutlinedButton.icon(onPressed:()=>_check(ctx,item),icon:const Icon(Icons.fact_check_outlined,size:15),label:const Text('Submit Check'),style:OutlinedButton.styleFrom(shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(10)),side:const BorderSide(color:P.green),foregroundColor:P.green))),
      ])))),
      if(items.isEmpty)const _Emp(ico:Icons.handyman_rounded,t:'No equipment',s:'Seeding default list…'),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════
// DASHBOARD
// ══════════════════════════════════════════════════════════════

class DashPage extends StatelessWidget {
  final WS st; const DashPage({super.key,required this.st});
  @override
  Widget build(BuildContext ctx){
    final ac=st.clients.whereType<Map>().where((e)=>(e['active']??true)==true).length;
    final rec=st.clients.whereType<Map>().fold<double>(0,(s,e)=>s+_n(e['rate']));
    final out=st.invoices.whereType<Map>().where((e)=>(e['status']??'')=='unpaid').fold<double>(0,(s,e)=>s+_n(e['amount']));
    final tj=st.jobs.whereType<Map>().where((e)=>(e['date']??'')==st.schedDate).toList();
    final dn=tj.where((e)=>(e['done']??false)==true).length;
    return ListView(padding:const EdgeInsets.fromLTRB(14,8,14,100),children:[
      _HeroCard(st:st),const SizedBox(height:12),
      GridView.count(physics:const NeverScrollableScrollPhysics(),crossAxisCount:2,mainAxisSpacing:10,crossAxisSpacing:10,childAspectRatio:1.15,shrinkWrap:true,children:[
        _Stat(t:'Active Clients',v:'$ac',s:'Recurring',ico:Icons.people_alt_rounded,c:P.green),
        _Stat(t:'Monthly Revenue',v:_m(rec),s:'Expected',ico:Icons.payments_rounded,c:const Color(0xFF1565C0)),
        _Stat(t:'Outstanding',v:_m(out),s:'Unpaid invoices',ico:Icons.receipt_long_rounded,c:P.danger),
        _Stat(t:'Jobs Today',v:'$dn/${tj.length}',s:'Completed',ico:Icons.task_alt_rounded,c:const Color(0xFF6A1B9A)),
      ]),
      const SizedBox(height:12),
      _SC(t:'Mission',child:const Text('Deliver dependable lawn and property care with professional standards, honest communication, and visible pride in every finished result.',style:TextStyle(height:1.6))),
      const SizedBox(height:10),
      _SC(t:'Core Values',child:Wrap(spacing:8,runSpacing:7,children:[for(final v in ['Reliability','Professional presentation','Respect for property','Clear communication','Consistent quality'])_Ch(v)])),
    ]);
  }
}
class _HeroCard extends StatelessWidget{final WS st;const _HeroCard({required this.st});@override Widget build(BuildContext ctx)=>Container(decoration:BoxDecoration(borderRadius:BorderRadius.circular(22),gradient:const LinearGradient(colors:[P.deep,P.green],begin:Alignment.topLeft,end:Alignment.bottomRight),boxShadow:[BoxShadow(color:Colors.black.withOpacity(.14),blurRadius:14,offset:const Offset(0,7))]),padding:const EdgeInsets.all(18),child:Row(children:[Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('PrimeYard Workspace',style:TextStyle(color:Colors.white,fontSize:19,fontWeight:FontWeight.w900)),const SizedBox(height:5),const Text('Jobs, invoices, staff, equipment — one app.',style:TextStyle(color:Color(0xE6FFFFFF),height:1.5,fontSize:12)),const SizedBox(height:10),Container(padding:const EdgeInsets.symmetric(horizontal:9,vertical:5),decoration:BoxDecoration(color:Colors.white.withOpacity(.14),borderRadius:BorderRadius.circular(99)),child:Text(st.updatedAt==null?'Waiting for sync…':'Synced ${DateFormat('HH:mm').format(st.updatedAt!)}',style:const TextStyle(color:Colors.white,fontWeight:FontWeight.w700,fontSize:11)))])),const SizedBox(width:8),Image.asset('assets/mascot.png',height:90)]));}

// ══════════════════════════════════════════════════════════════
// CLIENTS
// ══════════════════════════════════════════════════════════════

class ClientsPage extends StatelessWidget{
  final WS st;final AppSession s;const ClientsPage({super.key,required this.st,required this.s});
  Future<void> _edit(BuildContext ctx,[Map<String,dynamic>? ex])async{
    final nm=TextEditingController(text:ex?['name']?.toString()??'');
    final addr=TextEditingController(text:ex?['address']?.toString()??'');
    final rt=TextEditingController(text:ex!=null?_n(ex['rate']).toStringAsFixed(0):'');
    final sqm=TextEditingController(text:ex!=null?_n(ex['sqm']).toStringAsFixed(0):'');
    final act=ValueNotifier<bool>((ex?['active']??true)==true);
    final ok=await showDialog<bool>(context:ctx,builder:(_)=>ValueListenableBuilder(valueListenable:act,builder:(_,av,__)=>_Dlg(title:ex==null?'New Client':'Edit Client',child:Column(mainAxisSize:MainAxisSize.min,children:[
      _tf(nm,'Client name *'),const SizedBox(height:8),_tf(addr,'Property address'),const SizedBox(height:8),
      Row(children:[Expanded(child:_tf(sqm,'Size (m²)',num:true)),const SizedBox(width:8),Expanded(child:_tf(rt,'Rate (R/mo)',num:true))]),
      const SizedBox(height:8),Container(padding:const EdgeInsets.all(9),decoration:BoxDecoration(color:P.infoBg,borderRadius:BorderRadius.circular(10)),child:const Text('💡 Leave rate blank — it calculates from m² using your pricing.',style:TextStyle(color:P.infoFg,fontSize:11))),
      const SizedBox(height:6),SwitchListTile(value:av,onChanged:(v)=>act.value=v,title:const Text('Active'),contentPadding:EdgeInsets.zero,dense:true),
    ]))));
    if(ok!=true||nm.text.trim().isEmpty)return;
    double cr=double.tryParse(rt.text.trim())??0;
    if(cr==0&&sqm.text.trim().isNotEmpty){final sv=double.tryParse(sqm.text.trim())??0;cr=sv*0.15;}
    final items=List<dynamic>.from(st.clients);
    if(ex==null)items.insert(0,{'id':DateTime.now().millisecondsSinceEpoch.toString(),'name':nm.text.trim(),'address':addr.text.trim(),'sqm':double.tryParse(sqm.text.trim())??0,'rate':cr,'active':act.value,'createdAt':_today()});
    else{final i=items.indexWhere((e)=>e is Map&&e['id']==ex['id']);if(i>=0)items[i]={...ex,'name':nm.text.trim(),'address':addr.text.trim(),'sqm':double.tryParse(sqm.text.trim())??0,'rate':cr,'active':act.value};}
    await BS.save(st.copyWith(clients:items),by:s.username);
  }
  @override
  Widget build(BuildContext ctx){
    final c=st.clients.whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();
    return ListView(padding:const EdgeInsets.fromLTRB(14,8,14,100),children:[
      _SH(title:'Clients',sub:'${c.length} total',action:_fab(()=>_edit(ctx),'Add')),
      for(final cl in c)Padding(padding:const EdgeInsets.only(bottom:10),child:Card(child:ListTile(contentPadding:const EdgeInsets.fromLTRB(14,10,6,10),leading:CircleAvatar(backgroundColor:const Color(0xFFE8F3EA),child:Text(_ini(cl['name']))),title:Text((cl['name']??'').toString(),style:const TextStyle(fontWeight:FontWeight.w800)),
        subtitle:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text((cl['address']??'').toString(),style:const TextStyle(fontSize:12)),Row(children:[Text(_m(_n(cl['rate']))+'/mo',style:const TextStyle(fontSize:12,fontWeight:FontWeight.w700,color:P.green)),if(_n(cl['sqm'])>0)...[const Text(' · ',style:TextStyle(color:P.muted,fontSize:12)),Text('${_n(cl['sqm']).toStringAsFixed(0)}m²',style:const TextStyle(fontSize:12,color:P.muted))]])]),
        trailing:Row(mainAxisSize:MainAxisSize.min,children:[_Pill(text:(cl['active']??true)?'Active':'Paused'),PopupMenuButton<String>(onSelected:(v)async{if(v=='edit')_edit(ctx,cl);else if(await _conf(ctx,'Delete "${cl['name']}"?')==true)await BS.save(st.copyWith(clients:st.clients.where((e)=>e is Map&&e['id']!=cl['id']).toList()),by:s.username);},itemBuilder:(_)=>[const PopupMenuItem(value:'edit',child:Text('Edit')),const PopupMenuItem(value:'del',child:Text('Delete',style:TextStyle(color:P.danger)))])])))),
      if(c.isEmpty)const _Emp(ico:Icons.people_alt_rounded,t:'No clients yet',s:'Add your first client.'),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════
// INVOICES
// ══════════════════════════════════════════════════════════════

class InvoicesPage extends StatelessWidget{
  final WS st;final AppSession s;const InvoicesPage({super.key,required this.st,required this.s});
  Future<void> _edit(BuildContext ctx,[Map<String,dynamic>? ex])async{
    final cl=TextEditingController(text:ex?['client']?.toString()??'');
    final am=TextEditingController(text:ex!=null?_n(ex['amount']).toStringAsFixed(2):'');
    final no=TextEditingController(text:ex?['notes']?.toString()??'');
    final sv=ValueNotifier<String>((ex?['status']??'unpaid').toString());
    final ok=await showDialog<bool>(context:ctx,builder:(_)=>ValueListenableBuilder(valueListenable:sv,builder:(_,v,__)=>_Dlg(title:ex==null?'New Invoice':'Edit Invoice',child:Column(mainAxisSize:MainAxisSize.min,children:[
      _tf(cl,'Client name *'),const SizedBox(height:8),_tf(am,'Amount (R) *',num:true),const SizedBox(height:8),
      DropdownButtonFormField<String>(value:v,items:const[DropdownMenuItem(value:'unpaid',child:Text('Unpaid')),DropdownMenuItem(value:'paid',child:Text('Paid'))],onChanged:(v2)=>sv.value=v2??'unpaid',decoration:const InputDecoration(labelText:'Status')),
      const SizedBox(height:8),TextField(controller:no,maxLines:2,decoration:const InputDecoration(labelText:'Description / notes')),
    ]))));
    if(ok!=true||cl.text.trim().isEmpty)return;
    final items=List<dynamic>.from(st.invoices);
    if(ex==null)items.insert(0,{'id':DateTime.now().millisecondsSinceEpoch.toString(),'client':cl.text.trim(),'amount':double.tryParse(am.text.trim())??0,'status':sv.value,'notes':no.text.trim(),'createdAt':_today(),'invoiceNo':'INV-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}'});
    else{final i=items.indexWhere((e)=>e is Map&&e['id']==ex['id']);if(i>=0)items[i]={...ex,'client':cl.text.trim(),'amount':double.tryParse(am.text.trim())??0,'status':sv.value,'notes':no.text.trim()};}
    await BS.save(st.copyWith(invoices:items),by:s.username);
  }
  Future<void> _pdf(BuildContext ctx,Map<String,dynamic> inv)async{
    final doc=pw.Document();
    doc.addPage(pw.Page(pageFormat:PdfPageFormat.a4,build:(pctx){
      final gn=PdfColor.fromHex('1A6B30');final gr=PdfColor.fromHex('6D665D');
      return pw.Column(crossAxisAlignment:pw.CrossAxisAlignment.start,children:[
        pw.Row(mainAxisAlignment:pw.MainAxisAlignment.spaceBetween,children:[
          pw.Column(crossAxisAlignment:pw.CrossAxisAlignment.start,children:[pw.Text('PRIMEYARD',style:pw.TextStyle(fontSize:26,fontWeight:pw.FontWeight.bold,color:gn)),pw.Text('Lawn & Property Maintenance',style:pw.TextStyle(fontSize:11,color:gr)),pw.Text('Your property, our pride.',style:pw.TextStyle(fontSize:10,color:gr))]),
          pw.Column(crossAxisAlignment:pw.CrossAxisAlignment.end,children:[pw.Text('INVOICE',style:pw.TextStyle(fontSize:20,fontWeight:pw.FontWeight.bold)),pw.Text((inv['invoiceNo']??'INV-${(inv['id']??'').toString().substring(0,min(8,(inv['id']??'').toString().length))}').toString(),style:pw.TextStyle(fontSize:11,color:gr)),pw.Text('Date: ${inv['createdAt']??_today()}',style:pw.TextStyle(fontSize:10))]),
        ]),
        pw.SizedBox(height:18),pw.Divider(color:PdfColor.fromHex('E6DED0')),pw.SizedBox(height:14),
        pw.Text('BILL TO',style:pw.TextStyle(fontSize:9,color:gr,fontWeight:pw.FontWeight.bold)),
        pw.SizedBox(height:3),pw.Text((inv['client']??'Client').toString(),style:pw.TextStyle(fontSize:15,fontWeight:pw.FontWeight.bold)),
        pw.SizedBox(height:24),
        pw.Table(border:pw.TableBorder.all(color:PdfColor.fromHex('E6DED0'),width:.5),children:[
          pw.TableRow(decoration:pw.BoxDecoration(color:PdfColor.fromHex('E8F3EA')),children:[pw.Padding(padding:const pw.EdgeInsets.all(8),child:pw.Text('Description',style:pw.TextStyle(fontWeight:pw.FontWeight.bold,fontSize:11))),pw.Padding(padding:const pw.EdgeInsets.all(8),child:pw.Text('Amount',style:pw.TextStyle(fontWeight:pw.FontWeight.bold,fontSize:11)))]),
          pw.TableRow(children:[pw.Padding(padding:const pw.EdgeInsets.all(8),child:pw.Text((inv['notes']?.toString().isNotEmpty==true?inv['notes'].toString():'Lawn & property maintenance services'),style:pw.TextStyle(fontSize:11))),pw.Padding(padding:const pw.EdgeInsets.all(8),child:pw.Text(_m(_n(inv['amount'])),style:pw.TextStyle(fontSize:11)))]),
        ]),
        pw.SizedBox(height:8),
        pw.Align(alignment:pw.Alignment.centerRight,child:pw.Column(crossAxisAlignment:pw.CrossAxisAlignment.end,children:[
          pw.Divider(color:gn,thickness:1.5),
          pw.Row(mainAxisAlignment:pw.MainAxisAlignment.end,children:[pw.Text('TOTAL DUE: ',style:pw.TextStyle(fontWeight:pw.FontWeight.bold,fontSize:13)),pw.Text(_m(_n(inv['amount'])),style:pw.TextStyle(fontWeight:pw.FontWeight.bold,fontSize:17,color:gn))]),
          pw.Text('Status: ${(inv['status']??'unpaid').toString().toUpperCase()}',style:pw.TextStyle(fontSize:11,color:inv['status']=='paid'?gn:PdfColor.fromHex('C62828'),fontWeight:pw.FontWeight.bold)),
        ])),
        pw.Spacer(),
        pw.Divider(color:PdfColor.fromHex('E6DED0')),pw.SizedBox(height:6),
        pw.Text('Thank you for choosing PrimeYard! Payment is due within 30 days.',style:pw.TextStyle(fontSize:9,color:gr,fontStyle:pw.FontStyle.italic)),
      ]);
    }));
    final bytes=await doc.save();
    await Printing.sharePdf(bytes:bytes,filename:'PrimeYard_Invoice_${(inv['client']??'Client').toString().replaceAll(' ','_')}.pdf');
  }
  @override
  Widget build(BuildContext ctx){
    final invs=st.invoices.whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();
    final out=invs.where((e)=>e['status']=='unpaid').fold<double>(0,(s,e)=>s+_n(e['amount']));
    return ListView(padding:const EdgeInsets.fromLTRB(14,8,14,100),children:[
      _SH(title:'Invoices',sub:'${invs.length} records · ${_m(out)} outstanding',action:_fab(()=>_edit(ctx),'Add')),
      for(final inv in invs)Padding(padding:const EdgeInsets.only(bottom:10),child:Card(child:Padding(padding:const EdgeInsets.fromLTRB(14,12,6,12),child:Row(children:[
        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text((inv['client']??'').toString(),style:const TextStyle(fontWeight:FontWeight.w800,fontSize:14)),
          Text('${inv['createdAt']??'-'}  ${inv['invoiceNo']??''}',style:const TextStyle(color:P.muted,fontSize:11)),
          if((inv['notes']??'').toString().isNotEmpty)Text(inv['notes'].toString(),style:const TextStyle(fontSize:12,color:P.muted)),
          const SizedBox(height:4),
          Row(children:[Text(_m(_n(inv['amount'])),style:const TextStyle(fontSize:16,fontWeight:FontWeight.w900,color:P.green)),const SizedBox(width:7),_Pill(text:(inv['status']??'unpaid').toString())]),
        ])),
        Column(mainAxisSize:MainAxisSize.min,children:[
          IconButton(icon:const Icon(Icons.picture_as_pdf_rounded,color:P.danger,size:22),tooltip:'PDF / Share',onPressed:()=>_pdf(ctx,inv)),
          PopupMenuButton<String>(
            onSelected:(v)async{
              if(v=='toggle'){final up=st.invoices.whereType<Map>().map((e){final r=Map<String,dynamic>.from(e);if(r['id']==inv['id'])r['status']=r['status']=='paid'?'unpaid':'paid';return r;}).toList();await BS.save(st.copyWith(invoices:up),by:s.username);}
              else if(v=='edit')_edit(ctx,inv);
              else if(await _conf(ctx,'Delete invoice for "${inv['client']}"?')==true)await BS.save(st.copyWith(invoices:st.invoices.where((e)=>e is Map&&e['id']!=inv['id']).toList()),by:s.username);
            },
            itemBuilder:(_)=>[PopupMenuItem(value:'toggle',child:Text(inv['status']=='paid'?'Mark unpaid':'Mark as paid')),const PopupMenuItem(value:'edit',child:Text('Edit')),const PopupMenuItem(value:'del',child:Text('Delete',style:TextStyle(color:P.danger)))],
          ),
        ]),
      ])))),
      if(invs.isEmpty)const _Emp(ico:Icons.receipt_long_rounded,t:'No invoices yet',s:'Add your first invoice.'),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════
// SCHEDULE
// ══════════════════════════════════════════════════════════════

class SchedulePage extends StatefulWidget{
  final WS st;final AppSession s;const SchedulePage({super.key,required this.st,required this.s});
  @override State<SchedulePage> createState()=>_SchedState();
}
class _SchedState extends State<SchedulePage>{
  late DateTime _dt;
  @override void initState(){super.initState();_dt=DateTime.tryParse(widget.st.schedDate)??DateTime.now();}
  String get _ds=>DateFormat('yyyy-MM-dd').format(_dt);
  Future<void> _add(BuildContext ctx)async{
    final cl=TextEditingController();final addr=TextEditingController();final wk=TextEditingController();
    final wkrs=widget.st.emps.whereType<Map>().map((e)=>(e['name']??'').toString()).where((e)=>e.isNotEmpty).toList();
    final ok=await showDialog<bool>(context:ctx,builder:(_)=>_Dlg(title:'Schedule Job',child:Column(mainAxisSize:MainAxisSize.min,children:[_tf(cl,'Client name *'),const SizedBox(height:8),_tf(addr,'Address'),const SizedBox(height:8),if(wkrs.isNotEmpty)DropdownButtonFormField<String>(value:null,items:[const DropdownMenuItem(value:'',child:Text('— Select worker —')),...wkrs.map((w)=>DropdownMenuItem(value:w,child:Text(w)))],onChanged:(v)=>wk.text=v??'',decoration:const InputDecoration(labelText:'Assign worker'))else _tf(wk,'Worker name')])));
    if(ok!=true||cl.text.trim().isEmpty)return;
    final j=List<dynamic>.from(widget.st.jobs);j.insert(0,{'id':DateTime.now().millisecondsSinceEpoch.toString(),'name':cl.text.trim(),'address':addr.text.trim(),'workerName':wk.text.trim(),'date':_ds,'done':false,'status':'pending','notes':'','beforePhotos':[],'afterPhotos':[]});
    await BS.save(widget.st.copyWith(jobs:j),by:widget.s.username);
  }
  @override
  Widget build(BuildContext ctx){
    final jobs=widget.st.jobs.whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).where((j)=>(j['date']??'')==_ds).toList();
    final dn=jobs.where((j)=>j['done']==true).length;
    return ListView(padding:const EdgeInsets.fromLTRB(14,8,14,100),children:[
      Card(child:Padding(padding:const EdgeInsets.symmetric(horizontal:4,vertical:2),child:Row(children:[
        IconButton(icon:const Icon(Icons.chevron_left_rounded),onPressed:()=>setState(()=>_dt=_dt.subtract(const Duration(days:1)))),
        Expanded(child:InkWell(onTap:()async{final p=await showDatePicker(context:ctx,initialDate:_dt,firstDate:DateTime(2020),lastDate:DateTime(2030));if(p!=null)setState(()=>_dt=p);},borderRadius:BorderRadius.circular(10),child:Padding(padding:const EdgeInsets.symmetric(vertical:8),child:Column(children:[Text(DateFormat('EEEE').format(_dt),style:const TextStyle(fontWeight:FontWeight.w800,fontSize:14)),Text(DateFormat('d MMMM yyyy').format(_dt),style:const TextStyle(color:P.muted,fontSize:11))])))),
        IconButton(icon:const Icon(Icons.chevron_right_rounded),onPressed:()=>setState(()=>_dt=_dt.add(const Duration(days:1)))),
        TextButton(onPressed:()=>setState(()=>_dt=DateTime.now()),child:const Text('Today')),
      ]))),
      const SizedBox(height:8),
      _SH(title:'Jobs',sub:'$dn/${jobs.length} done',action:_fab(()=>_add(ctx),'Add')),
      for(final j in jobs)Padding(padding:const EdgeInsets.only(bottom:10),child:Card(child:CheckboxListTile(
        controlAffinity:ListTileControlAffinity.leading,
        shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(18)),
        value:j['done']==true,
        title:Text((j['name']??'').toString(),style:const TextStyle(fontWeight:FontWeight.w800)),
        subtitle:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          if((j['address']??'').toString().isNotEmpty)Text(j['address'].toString(),style:const TextStyle(fontSize:12)),
          Text((j['workerName']??'Unassigned').toString(),style:const TextStyle(color:P.muted,fontSize:11)),
          if(j['status']=='in_progress')Text('⏱ Started ${_fmtDT((j['startedAt']??'').toString())}',style:const TextStyle(color:P.gold,fontSize:11,fontWeight:FontWeight.w700)),
        ]),
        secondary:PopupMenuButton<String>(
          onSelected:(v)async{
            if(v=='edit'){final cl=TextEditingController(text:(j['name']??'').toString());final addr=TextEditingController(text:(j['address']??'').toString());final wk=TextEditingController(text:(j['workerName']??'').toString());final ok=await showDialog<bool>(context:ctx,builder:(_)=>_Dlg(title:'Edit Job',child:Column(mainAxisSize:MainAxisSize.min,children:[_tf(cl,'Client name'),const SizedBox(height:8),_tf(addr,'Address'),const SizedBox(height:8),_tf(wk,'Worker')])));if(ok!=true)return;final up=widget.st.jobs.whereType<Map>().map((e){final r=Map<String,dynamic>.from(e);if(r['id']==j['id']){r['name']=cl.text.trim();r['address']=addr.text.trim();r['workerName']=wk.text.trim();}return r;}).toList();await BS.save(widget.st.copyWith(jobs:up),by:widget.s.username);}
            else if(await _conf(ctx,'Delete job for "${j['name']}"?')==true)await BS.save(widget.st.copyWith(jobs:widget.st.jobs.where((e)=>e is Map&&e['id']!=j['id']).toList()),by:widget.s.username);
          },
          itemBuilder:(_)=>[const PopupMenuItem(value:'edit',child:Text('Edit')),const PopupMenuItem(value:'del',child:Text('Delete',style:TextStyle(color:P.danger)))],
        ),
        onChanged:(_)async{final nd=!(j['done']==true);final up=widget.st.jobs.whereType<Map>().map((e){final r=Map<String,dynamic>.from(e);if(r['id']==j['id']){r['done']=nd;r['status']=nd?'done':'pending';}return r;}).toList();await BS.save(widget.st.copyWith(jobs:up),by:widget.s.username);},
      ))),
      if(jobs.isEmpty)const _Emp(ico:Icons.calendar_month_rounded,t:'No jobs this day',s:'Add jobs to build the route.'),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════
// EMPLOYEES
// ══════════════════════════════════════════════════════════════

class EmpsPage extends StatelessWidget{
  final WS st;final AppSession s;const EmpsPage({super.key,required this.st,required this.s});
  Future<void> _edit(BuildContext ctx,[Map<String,dynamic>? ex])async{
    final nm=TextEditingController(text:ex?['name']?.toString()??'');
    final rt=TextEditingController(text:ex!=null?_n(ex['dailyRate']).toStringAsFixed(0):'');
    final ok=await showDialog<bool>(context:ctx,builder:(_)=>_Dlg(title:ex==null?'New Employee':'Edit Employee',child:Column(mainAxisSize:MainAxisSize.min,children:[_tf(nm,'Full name *'),const SizedBox(height:8),_tf(rt,'Daily rate (R)',num:true)])));
    if(ok!=true||nm.text.trim().isEmpty)return;
    final items=List<dynamic>.from(st.emps);
    if(ex==null)items.insert(0,{'id':DateTime.now().millisecondsSinceEpoch.toString(),'name':nm.text.trim(),'dailyRate':double.tryParse(rt.text.trim())??0,'startDate':_today()});
    else{final i=items.indexWhere((e)=>e is Map&&e['id']==ex['id']);if(i>=0)items[i]={...ex,'name':nm.text.trim(),'dailyRate':double.tryParse(rt.text.trim())??0};}
    await BS.save(st.copyWith(emps:items),by:s.username);
  }
  void _payroll(BuildContext ctx,Map<String,dynamic> emp){
    final en=emp['name'].toString().toLowerCase().split(' ').first;
    final entries=st.clockEntries.whereType<Map>().where((e)=>(e['displayName']??e['username']??'').toString().toLowerCase().contains(en)).toList();
    final days=entries.where((e)=>e['type']=='in').length;
    final total=days*_n(emp['dailyRate']);
    showModalBottomSheet(context:ctx,shape:const RoundedRectangleBorder(borderRadius:BorderRadius.vertical(top:Radius.circular(20))),builder:(_)=>Padding(padding:const EdgeInsets.all(20),child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Text(emp['name'].toString(),style:const TextStyle(fontWeight:FontWeight.w900,fontSize:19)),
      Text('${_m(_n(emp['dailyRate']))}/day · Since ${emp['startDate']??'-'}',style:const TextStyle(color:P.muted,fontSize:12)),
      const Divider(height:22),
      Row(children:[Expanded(child:_PBx(l:'Days Worked',v:'$days')),const SizedBox(width:10),Expanded(child:_PBx(l:'Total Wages',v:_m(total)))]),
      const SizedBox(height:12),const Text('Based on clock-in records.',style:TextStyle(color:P.muted,fontSize:11),textAlign:TextAlign.center),
    ])));
  }
  @override
  Widget build(BuildContext ctx){
    final emps=st.emps.whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();
    return ListView(padding:const EdgeInsets.fromLTRB(14,8,14,100),children:[
      _SH(title:'Employees',sub:'${emps.length} on record',action:_fab(()=>_edit(ctx),'Add')),
      for(final e in emps)Padding(padding:const EdgeInsets.only(bottom:10),child:Card(child:ListTile(contentPadding:const EdgeInsets.fromLTRB(14,10,6,10),leading:CircleAvatar(backgroundColor:const Color(0xFFE8F3EA),child:Text(_ini(e['name']))),title:Text((e['name']??'').toString(),style:const TextStyle(fontWeight:FontWeight.w800)),subtitle:Text('${_m(_n(e['dailyRate']))}/day · Since ${e['startDate']??'-'}'),
        trailing:Row(mainAxisSize:MainAxisSize.min,children:[IconButton(icon:const Icon(Icons.payments_rounded,color:P.green,size:20),onPressed:()=>_payroll(ctx,e)),
        PopupMenuButton<String>(onSelected:(v)async{if(v=='edit')_edit(ctx,e);else if(await _conf(ctx,'Remove "${e['name']}"?')==true)await BS.save(st.copyWith(emps:st.emps.where((x)=>x is Map&&x['id']!=e['id']).toList()),by:s.username);},itemBuilder:(_)=>[const PopupMenuItem(value:'edit',child:Text('Edit')),const PopupMenuItem(value:'del',child:Text('Remove',style:TextStyle(color:P.danger)))])])))),
      if(emps.isEmpty)const _Emp(ico:Icons.badge_rounded,t:'No employees yet',s:'Add your team.'),
    ]);
  }
}
class _PBx extends StatelessWidget{final String l,v;const _PBx({required this.l,required this.v});@override Widget build(BuildContext ctx)=>Container(padding:const EdgeInsets.all(14),decoration:BoxDecoration(color:const Color(0xFFE8F3EA),borderRadius:BorderRadius.circular(12)),child:Column(children:[Text(v,style:const TextStyle(fontWeight:FontWeight.w900,fontSize:20,color:P.green)),const SizedBox(height:3),Text(l,style:const TextStyle(color:P.muted,fontSize:11))]));}

// ══════════════════════════════════════════════════════════════
// MORE
// ══════════════════════════════════════════════════════════════

class MorePage extends StatelessWidget{
  final WS st;final AppSession s;const MorePage({super.key,required this.st,required this.s});
  void _go(BuildContext ctx,Widget w)=>_push(ctx,w);
  @override
  Widget build(BuildContext ctx)=>ListView(padding:const EdgeInsets.fromLTRB(14,8,14,100),children:[
    _SH(title:'More Tools',sub:'Extra workspace controls'),
    _AT(ico:Icons.calculate_rounded,t:'Quotes & Estimates',s:'PrimeBasic / PrimeCare / PrimeElite calculator',f:()=>_go(ctx,QuotesPage(st:st,s:s))),
    _AT(ico:Icons.handyman_rounded,t:'Equipment',s:'Daily checks and status log',f:()=>_go(ctx,EquipPage(st:st,s:s))),
    _AT(ico:Icons.task_alt_rounded,t:'Jobs Log',s:'All jobs with date filter',f:()=>_go(ctx,JobsLogPage(st:st))),
    _AT(ico:Icons.punch_clock_rounded,t:'Clock Entries',s:'All staff clock-in/out records',f:()=>_go(ctx,ClockEntPage(st:st))),
    _AT(ico:Icons.checklist_rounded,t:'Equipment Logs',s:'Submitted check history',f:()=>_go(ctx,CheckLogsPage(st:st))),
    if(s.isMaster)_AT(ico:Icons.manage_accounts_rounded,t:'User Management',s:'Add, edit, delete staff accounts',f:()=>_go(ctx,UsersPage(st:st,s:s))),
  ]);
}

// ══════════════════════════════════════════════════════════════
// QUOTES — FULL PRICING LOGIC
// ══════════════════════════════════════════════════════════════

class QuotesPage extends StatelessWidget{
  final WS st;final AppSession s;const QuotesPage({super.key,required this.st,required this.s});
  @override
  Widget build(BuildContext ctx){
    final qs=st.quotes.whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();
    return ListView(padding:const EdgeInsets.fromLTRB(14,8,14,100),children:[
      _SH(title:'Quotes',sub:'${qs.length} total',action:Row(mainAxisSize:MainAxisSize.min,children:[
        OutlinedButton.icon(onPressed:()=>_calc(ctx),icon:const Icon(Icons.calculate_rounded,size:14),label:const Text('Calculator'),style:OutlinedButton.styleFrom(shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(10)),foregroundColor:P.green,side:const BorderSide(color:P.green),padding:const EdgeInsets.symmetric(horizontal:10,vertical:8))),
        const SizedBox(width:6),
        _fab(()=>_manual(ctx),'Add'),
      ])),
      for(final q in qs)_QuoteCard(q:q,onEdit:()=>_manual(ctx,q),onDel:()async{if(await _conf(ctx,'Delete quote for "${q['client']}"?')==true)await BS.save(st.copyWith(quotes:st.quotes.where((e)=>e is Map&&e['id']!=q['id']).toList()),by:s.username);}),
      if(qs.isEmpty)const _Emp(ico:Icons.calculate_rounded,t:'No quotes yet',s:'Tap Calculator to create an auto-priced quote.'),
    ]);
  }
  void _calc(BuildContext ctx){
    showModalBottomSheet(context:ctx,isScrollControlled:true,useSafeArea:true,shape:const RoundedRectangleBorder(borderRadius:BorderRadius.vertical(top:Radius.circular(22))),builder:(_)=>QuoteCalcSheet(onSave:(q)async{final items=List<dynamic>.from(st.quotes);items.insert(0,q);await BS.save(st.copyWith(quotes:items),by:s.username);}));
  }
  Future<void> _manual(BuildContext ctx,[Map<String,dynamic>? ex])async{
    final cl=TextEditingController(text:ex?['client']?.toString()??'');
    final addr=TextEditingController(text:ex?['address']?.toString()??'');
    final desc=TextEditingController(text:ex?['description']?.toString()??'');
    final am=TextEditingController(text:ex!=null?_n(ex['amount']).toStringAsFixed(0):'');
    final sv=ValueNotifier<String>((ex?['status']??'pending').toString());
    final ok=await showDialog<bool>(context:ctx,builder:(_)=>ValueListenableBuilder(valueListenable:sv,builder:(_,v,__)=>_Dlg(title:ex==null?'Manual Quote':'Edit Quote',child:Column(mainAxisSize:MainAxisSize.min,children:[
      _tf(cl,'Client name *'),const SizedBox(height:8),_tf(addr,'Property address'),const SizedBox(height:8),
      TextField(controller:desc,maxLines:2,decoration:const InputDecoration(labelText:'Description')),const SizedBox(height:8),
      _tf(am,'Amount (R)',num:true),const SizedBox(height:8),
      DropdownButtonFormField<String>(value:v,items:const[DropdownMenuItem(value:'pending',child:Text('Pending')),DropdownMenuItem(value:'accepted',child:Text('Accepted')),DropdownMenuItem(value:'declined',child:Text('Declined'))],onChanged:(v2)=>sv.value=v2??'pending',decoration:const InputDecoration(labelText:'Status')),
    ]))));
    if(ok!=true||cl.text.trim().isEmpty)return;
    final items=List<dynamic>.from(st.quotes);
    if(ex==null)items.insert(0,{'id':DateTime.now().millisecondsSinceEpoch.toString(),'client':cl.text.trim(),'address':addr.text.trim(),'description':desc.text.trim(),'amount':double.tryParse(am.text.trim())??0,'status':sv.value,'createdAt':_today(),'createdBy':s.username});
    else{final i=items.indexWhere((e)=>e is Map&&e['id']==ex['id']);if(i>=0)items[i]={...ex,'client':cl.text.trim(),'address':addr.text.trim(),'description':desc.text.trim(),'amount':double.tryParse(am.text.trim())??0,'status':sv.value};}
    await BS.save(st.copyWith(quotes:items),by:s.username);
  }
}

class _QuoteCard extends StatelessWidget{
  final Map<String,dynamic> q;final VoidCallback onEdit,onDel;
  const _QuoteCard({required this.q,required this.onEdit,required this.onDel});
  Color _sc(String s){switch(s){case'accepted':return P.green;case'declined':return P.danger;default:return P.gold;}}
  @override
  Widget build(BuildContext ctx)=>Padding(padding:const EdgeInsets.only(bottom:10),child:Card(child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Row(children:[
      Expanded(child:Text((q['client']??'').toString(),style:const TextStyle(fontWeight:FontWeight.w800,fontSize:14))),
      Container(padding:const EdgeInsets.symmetric(horizontal:8,vertical:3),decoration:BoxDecoration(color:_sc((q['status']??'pending').toString()).withOpacity(.12),borderRadius:BorderRadius.circular(99)),child:Text((q['status']??'pending').toString().toUpperCase(),style:TextStyle(color:_sc((q['status']??'pending').toString()),fontWeight:FontWeight.w800,fontSize:10))),
      PopupMenuButton<String>(onSelected:(v){if(v=='edit')onEdit();else onDel();},itemBuilder:(_)=>[const PopupMenuItem(value:'edit',child:Text('Edit')),const PopupMenuItem(value:'del',child:Text('Delete',style:TextStyle(color:P.danger)))]),
    ]),
    if((q['address']??'').toString().isNotEmpty)Text(q['address'].toString(),style:const TextStyle(color:P.muted,fontSize:12)),
    if((q['description']??'').toString().isNotEmpty)Text(q['description'].toString(),style:const TextStyle(fontSize:12)),
    const SizedBox(height:6),
    Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[Text(_m(_n(q['amount'])),style:const TextStyle(fontWeight:FontWeight.w900,fontSize:18,color:P.green)),Text(q['createdAt']?.toString()??'-',style:const TextStyle(color:P.muted,fontSize:11))]),
    if(q['package']!=null)...[const SizedBox(height:4),Text('📦 ${q['package']} · ${q['serviceType']??''} · ${q['pricingMode']??''}',style:const TextStyle(color:P.muted,fontSize:11))],
    if(q['frequency']!=null&&q['serviceType']=='Recurring')Text('🔄 ${q['frequency']}',style:const TextStyle(color:P.muted,fontSize:11)),
    if(q['monthlyTotal']!=null)Text('📅 Monthly total: ${_m(_n(q['monthlyTotal']))}',style:const TextStyle(color:P.green,fontWeight:FontWeight.w700,fontSize:12)),
    if(q['breakdown'] is List&&(q['breakdown'] as List).isNotEmpty)...[
      const SizedBox(height:6),const Divider(height:10),
      for(final b in (q['breakdown'] as List).whereType<Map>())Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[Expanded(child:Text((b['label']??'').toString(),style:const TextStyle(fontSize:11,color:P.muted))),Text(_m(_n(b['amount'])),style:const TextStyle(fontSize:11,fontWeight:FontWeight.w700))]),
    ],
  ]))));
}

// ── Quote Calculator Sheet ────────────────────────────────────

class QuoteCalcSheet extends StatefulWidget{
  final Function(Map<String,dynamic>) onSave;
  const QuoteCalcSheet({super.key,required this.onSave});
  @override State<QuoteCalcSheet> createState()=>_QCSState();
}
class _QCSState extends State<QuoteCalcSheet>{
  final _cl=TextEditingController();
  final _addr=TextEditingController();
  final _sqm=TextEditingController();
  final _custom=TextEditingController();

  String _pkg='PrimeBasic';
  String _pricingMode='Full Operational'; // 'Launch' or 'Full Operational'
  String _svcType='Recurring';            // 'Recurring' or 'Once-Off'
  String _freq='2x per month';           // '2x per month' or '4x per month'
  bool _surchargeOvergrowth=false;
  bool _surchargeSteep=false;
  Map<String,bool> _addOns={for(final k in kAddOns.keys) k:false};
  double _customAmt=0;

  double get _sqmVal=>double.tryParse(_sqm.text)??0;
  int get _tier=>_sizeTier(_sqmVal);
  int get _modeIdx=>_pricingMode=='Launch'?0:1;
  double get _basePerVisit{final pp=kPackagePrices[_pkg]!;return pp[_tier][_modeIdx];}
  double get _surcharge{double s=0;if(_surchargeOvergrowth)s+=0.25;if(_surchargeSteep)s+=0.15;return s;}
  double get _addOnsTotal=>_addOns.entries.where((e)=>e.value).fold(0,(s,e)=>s+kAddOns[e.key]!);
  double get _customTotal=>_customAmt;
  double get _perVisit=>_basePerVisit*(1+_surcharge)+_addOnsTotal+_customTotal;
  int get _visitsPerMonth=>_freq=='2x per month'?2:4;
  double get _monthlyTotal=>_svcType=='Recurring'?_perVisit*_visitsPerMonth:_perVisit;

  List<Map<String,dynamic>> get _breakdown{
    final list=<Map<String,dynamic>>[];
    list.add({'label':'${_pkg} base (${_tier==0?'≤300m²':_tier==1?'301-600m²':_tier==2?'601-1000m²':'>1000m²'})','amount':_basePerVisit});
    if(_surchargeOvergrowth)list.add({'label':'Overgrowth surcharge (+25%)','amount':_basePerVisit*0.25});
    if(_surchargeSteep)list.add({'label':'Steep slope surcharge (+15%)','amount':_basePerVisit*0.15});
    for(final e in _addOns.entries.where((e)=>e.value))list.add({'label':e.key,'amount':kAddOns[e.key]!});
    if(_customTotal>0)list.add({'label':_custom.text.trim().isEmpty?'Custom task':'Custom: ${_custom.text.trim()}','amount':_customTotal});
    return list;
  }

  @override
  Widget build(BuildContext ctx){
    return DraggableScrollableSheet(
      initialChildSize:0.94,minChildSize:0.5,maxChildSize:1.0,expand:false,
      builder:(_,sc)=>Scaffold(
        appBar:AppBar(title:const Text('Quote Calculator',style:TextStyle(fontWeight:FontWeight.w900)),automaticallyImplyLeading:false,actions:[IconButton(icon:const Icon(Icons.close_rounded),onPressed:()=>Navigator.pop(ctx))]),
        body:SingleChildScrollView(controller:sc,padding:const EdgeInsets.fromLTRB(16,8,16,20),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[

          // Client info
          _sec('Client Details'),
          _tf(_cl,'Client name *'),const SizedBox(height:8),_tf(_addr,'Property address'),const SizedBox(height:8),
          _tf(_sqm,'Property size (m²) *',num:true,onCh:()=>setState((){})),
          if(_sqmVal>0)...[const SizedBox(height:4),Text('Size tier: ${_tier==0?'Small ≤300m²':_tier==1?'Medium 301-600m²':_tier==2?'Large 601-1000m²':'XL >1000m²'}',style:const TextStyle(color:P.muted,fontSize:11))],
          const SizedBox(height:16),

          // Package selection
          _sec('Package'),
          ...kPackagePrices.keys.map((pkg)=>_pkgTile(pkg)),
          const SizedBox(height:14),

          // Pricing mode
          _sec('Pricing Mode'),
          Row(children:[Expanded(child:_selBtn('Launch Price',_pricingMode=='Launch',()=>setState(()=>_pricingMode='Launch'))),const SizedBox(width:8),Expanded(child:_selBtn('Full Operational',_pricingMode=='Full Operational',()=>setState(()=>_pricingMode='Full Operational')))]),
          const SizedBox(height:14),

          // Service type
          _sec('Service Type'),
          Row(children:[Expanded(child:_selBtn('Recurring',_svcType=='Recurring',()=>setState(()=>_svcType='Recurring'))),const SizedBox(width:8),Expanded(child:_selBtn('Once-Off',_svcType=='Once-Off',()=>setState(()=>_svcType='Once-Off')))]),
          if(_svcType=='Recurring')...[
            const SizedBox(height:10),
            _sec('Frequency'),
            Row(children:[Expanded(child:_selBtn('2× per month',_freq=='2x per month',()=>setState(()=>_freq='2x per month'))),const SizedBox(width:8),Expanded(child:_selBtn('4× per month',_freq=='4x per month',()=>setState(()=>_freq='4x per month')))]),
          ],
          const SizedBox(height:14),

          // Surcharges
          _sec('Surcharges'),
          _surchRow('Overgrowth / neglected yard','+25%',_surchargeOvergrowth,(v)=>setState(()=>_surchargeOvergrowth=v),P.danger),
          const SizedBox(height:6),
          _surchRow('Difficult access / steep slope','+15%',_surchargeSteep,(v)=>setState(()=>_surchargeSteep=v),const Color(0xFFE65100)),
          const SizedBox(height:14),

          // Add-ons
          _sec('Add-On Services'),
          Wrap(spacing:8,runSpacing:6,children:[
            for(final e in kAddOns.entries)FilterChip(
              label:Text('${e.key}\n${_m(e.value)}',style:const TextStyle(fontSize:11)),
              selected:_addOns[e.key]==true,
              onSelected:(v)=>setState(()=>_addOns[e.key]=v),
              selectedColor:P.green.withOpacity(.14),checkmarkColor:P.green,
            ),
          ]),
          const SizedBox(height:14),

          // Custom task
          _sec('Custom Task'),
          Row(children:[
            Expanded(child:TextField(controller:_custom,decoration:const InputDecoration(labelText:'Task description'))),
            const SizedBox(width:8),
            SizedBox(width:110,child:TextField(keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Amount (R)',prefixText:'R '),onChanged:(v)=>setState(()=>_customAmt=double.tryParse(v)??0))),
          ]),
          const SizedBox(height:20),

          // Summary card
          if(_sqmVal>0)Container(padding:const EdgeInsets.all(16),decoration:BoxDecoration(color:const Color(0xFFE8F3EA),borderRadius:BorderRadius.circular(16)),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
            const Text('Price Summary',style:TextStyle(fontWeight:FontWeight.w900,fontSize:14,color:P.green)),
            const SizedBox(height:10),
            for(final b in _breakdown)Row(children:[Expanded(child:Text(b['label'].toString(),style:const TextStyle(fontSize:12))),Text(_m(_n(b['amount'])),style:const TextStyle(fontSize:12,fontWeight:FontWeight.w700))]),
            const Divider(height:16),
            Row(children:[const Expanded(child:Text('Per visit',style:TextStyle(fontWeight:FontWeight.w800))),Text(_m(_perVisit),style:const TextStyle(fontWeight:FontWeight.w900,fontSize:16,color:P.green))]),
            if(_svcType=='Recurring')Row(children:[Expanded(child:Text('Monthly ($_freq)',style:const TextStyle(fontWeight:FontWeight.w800))),Text(_m(_monthlyTotal),style:const TextStyle(fontWeight:FontWeight.w900,fontSize:18,color:P.green))]),
          ])),
          const SizedBox(height:16),

          FilledButton.icon(
            onPressed:_cl.text.trim().isEmpty||_sqmVal==0?null:()async{
              final now=DateTime.now();
              final q={
                'id':now.millisecondsSinceEpoch.toString(),
                'client':_cl.text.trim(),'address':_addr.text.trim(),
                'description':'${_pkg} · ${_svcType}${_svcType=='Recurring'?' (${_freq})':''} · ${_pricingMode}',
                'package':_pkg,'pricingMode':_pricingMode,'serviceType':_svcType,
                'frequency':_svcType=='Recurring'?_freq:null,
                'sqm':_sqmVal,'amount':_perVisit,'monthlyTotal':_svcType=='Recurring'?_monthlyTotal:null,
                'status':'pending','createdAt':_today(),'breakdown':_breakdown,
                'surcharges':{'overgrowth':_surchargeOvergrowth,'steep':_surchargeSteep},
                'addOns':_addOns.entries.where((e)=>e.value).map((e)=>e.key).toList(),
              };
              await widget.onSave(q);
              if(ctx.mounted)Navigator.pop(ctx);
            },
            icon:const Icon(Icons.check_rounded),
            label:Padding(padding:const EdgeInsets.symmetric(vertical:12),child:Text(_cl.text.trim().isEmpty||_sqmVal==0?'Enter client name and property size':'Save Quote — ${_m(_perVisit)}/visit${_svcType=='Recurring'?' · ${_m(_monthlyTotal)}/mo':''}',style:const TextStyle(fontSize:14,fontWeight:FontWeight.w700))),
            style:FilledButton.styleFrom(backgroundColor:P.green,foregroundColor:Colors.white,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(14))),
          ),
          const SizedBox(height:20),
        ])),
      ),
    );
  }

  Widget _sec(String t)=>Padding(padding:const EdgeInsets.only(bottom:8),child:Text(t,style:const TextStyle(fontWeight:FontWeight.w800,fontSize:13,color:P.text)));

  Widget _pkgTile(String pkg){
    final sel=_pkg==pkg;
    return Padding(padding:const EdgeInsets.only(bottom:8),child:InkWell(onTap:()=>setState(()=>_pkg=pkg),borderRadius:BorderRadius.circular(14),child:Container(padding:const EdgeInsets.all(12),decoration:BoxDecoration(borderRadius:BorderRadius.circular(14),border:Border.all(color:sel?P.green:P.border,width:sel?2:1),color:sel?P.green.withOpacity(.05):Colors.white),child:Row(children:[
      Icon(sel?Icons.radio_button_checked_rounded:Icons.radio_button_unchecked_rounded,color:sel?P.green:P.muted,size:18),const SizedBox(width:10),
      Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(pkg,style:TextStyle(fontWeight:FontWeight.w900,color:sel?P.green:P.text,fontSize:13)),
        Text(kPackageIncludes[pkg]??'',style:const TextStyle(fontSize:11,color:P.muted)),
      ])),
      if(_sqmVal>0)Column(crossAxisAlignment:CrossAxisAlignment.end,children:[
        Text(_m(kPackagePrices[pkg]![_tier][1]),style:const TextStyle(fontWeight:FontWeight.w900,fontSize:13)),
        Text('full · ${_m(kPackagePrices[pkg]![_tier][0])} launch',style:const TextStyle(fontSize:10,color:P.muted)),
      ]),
    ]))));
  }

  Widget _selBtn(String lbl,bool sel,VoidCallback fn)=>InkWell(onTap:fn,borderRadius:BorderRadius.circular(12),child:Container(padding:const EdgeInsets.symmetric(vertical:10),decoration:BoxDecoration(borderRadius:BorderRadius.circular(12),border:Border.all(color:sel?P.green:P.border,width:sel?2:1),color:sel?P.green.withOpacity(.07):Colors.white),child:Text(lbl,textAlign:TextAlign.center,style:TextStyle(fontWeight:sel?FontWeight.w800:FontWeight.w500,color:sel?P.green:P.muted,fontSize:12))));

  Widget _surchRow(String lbl,String pct,bool val,Function(bool) fn,Color c)=>InkWell(onTap:()=>fn(!val),borderRadius:BorderRadius.circular(12),child:Container(padding:const EdgeInsets.all(12),decoration:BoxDecoration(borderRadius:BorderRadius.circular(12),border:Border.all(color:val?c:P.border,width:val?2:1),color:val?c.withOpacity(.06):Colors.white),child:Row(children:[Checkbox(value:val,onChanged:(v)=>fn(v??false),activeColor:c),const SizedBox(width:4),Expanded(child:Text(lbl,style:TextStyle(fontWeight:FontWeight.w700,color:val?c:P.text,fontSize:12))),Container(padding:const EdgeInsets.symmetric(horizontal:8,vertical:3),decoration:BoxDecoration(color:c.withOpacity(.12),borderRadius:BorderRadius.circular(99)),child:Text(pct,style:TextStyle(color:c,fontWeight:FontWeight.w800,fontSize:12)))])));
}

// ══════════════════════════════════════════════════════════════
// JOBS LOG
// ══════════════════════════════════════════════════════════════

class JobsLogPage extends StatefulWidget{final WS st;const JobsLogPage({super.key,required this.st});@override State<JobsLogPage> createState()=>_JLState();}
class _JLState extends State<JobsLogPage>{
  String _f='all'; DateTime? _from,_to;
  List<Map<String,dynamic>> get _jobs{
    var j=widget.st.jobs.whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList()..sort((a,b)=>(b['date']??'').toString().compareTo((a['date']??'').toString()));
    if(_f=='done')j=j.where((x)=>x['done']==true).toList();
    else if(_f=='pending')j=j.where((x)=>x['done']!=true&&x['status']!='in_progress').toList();
    else if(_f=='in_progress')j=j.where((x)=>x['status']=='in_progress').toList();
    else if(_f=='today')j=j.where((x)=>(x['date']??'')==_today()).toList();
    if(_from!=null){final fs=DateFormat('yyyy-MM-dd').format(_from!);j=j.where((x)=>(x['date']??'')>=fs).toList();}
    if(_to!=null){final ts=DateFormat('yyyy-MM-dd').format(_to!);j=j.where((x)=>(x['date']??'')<=ts).toList();}
    return j;
  }
  @override
  Widget build(BuildContext ctx){
    final jobs=_jobs;
    return ListView(padding:const EdgeInsets.fromLTRB(14,8,14,100),children:[
      _SH(title:'Jobs Log',sub:'${jobs.length} matching'),
      SingleChildScrollView(scrollDirection:Axis.horizontal,child:Row(children:[for(final f in [('all','All'),('today','Today'),('in_progress','In Progress'),('done','Done'),('pending','Pending')])Padding(padding:const EdgeInsets.only(right:7,bottom:8),child:FilterChip(label:Text(f.$2),selected:_f==f.$1,onSelected:(_)=>setState(()=>_f=f.$1),selectedColor:P.green.withOpacity(.13),checkmarkColor:P.green))])),
      Card(child:Padding(padding:const EdgeInsets.symmetric(horizontal:12,vertical:6),child:Row(children:[const Icon(Icons.date_range_rounded,color:P.muted,size:15),const SizedBox(width:6),Expanded(child:InkWell(onTap:()async{final d=await showDatePicker(context:ctx,initialDate:_from??DateTime.now(),firstDate:DateTime(2020),lastDate:DateTime(2030));if(d!=null)setState(()=>_from=d);},child:Text(_from==null?'From date':DateFormat('d MMM yy').format(_from!),style:TextStyle(color:_from==null?P.muted:P.text,fontSize:12)))),const Text(' → ',style:TextStyle(color:P.muted)),Expanded(child:InkWell(onTap:()async{final d=await showDatePicker(context:ctx,initialDate:_to??DateTime.now(),firstDate:DateTime(2020),lastDate:DateTime(2030));if(d!=null)setState(()=>_to=d);},child:Text(_to==null?'To date':DateFormat('d MMM yy').format(_to!),style:TextStyle(color:_to==null?P.muted:P.text,fontSize:12)))),if(_from!=null||_to!=null)IconButton(icon:const Icon(Icons.clear_rounded,size:14,color:P.muted),onPressed:()=>setState((){_from=null;_to=null;}))]))),
      const SizedBox(height:8),
      for(final j in jobs)Padding(padding:const EdgeInsets.only(bottom:8),child:Card(child:ListTile(contentPadding:const EdgeInsets.all(12),leading:Icon(j['done']==true?Icons.check_circle_rounded:j['status']=='in_progress'?Icons.play_circle_rounded:Icons.radio_button_unchecked_rounded,color:j['done']==true?P.green:j['status']=='in_progress'?P.gold:P.muted,size:24),title:Text((j['name']??'').toString(),style:const TextStyle(fontWeight:FontWeight.w800)),subtitle:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('${j['date']??'-'} · ${j['address']??''}',style:const TextStyle(fontSize:11)),Text((j['workerName']??'Unassigned').toString(),style:const TextStyle(color:P.muted,fontSize:10)),if((j['notes']??'').toString().isNotEmpty)Text('📝 ${j['notes']}',style:const TextStyle(color:P.green,fontSize:10)),if(j['done']==true&&(j['completedAt']??'').isNotEmpty)Text('✓ ${_fmtDT(j['completedAt'].toString())}',style:const TextStyle(color:P.green,fontSize:10))])))),
      if(jobs.isEmpty)const _Emp(ico:Icons.task_alt_rounded,t:'No jobs match',s:'Try a different filter.'),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════
// CLOCK ENTRIES (admin)
// ══════════════════════════════════════════════════════════════

class ClockEntPage extends StatefulWidget{final WS st;const ClockEntPage({super.key,required this.st});@override State<ClockEntPage> createState()=>_CEState();}
class _CEState extends State<ClockEntPage>{
  String _q='';
  @override Widget build(BuildContext ctx){
    final es=widget.st.clockEntries.whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).where((e)=>_q.isEmpty||(e['displayName']??e['username']??'').toString().toLowerCase().contains(_q.toLowerCase())).toList()..sort((a,b)=>(b['timestamp']??'').toString().compareTo((a['timestamp']??'').toString()));
    return ListView(padding:const EdgeInsets.fromLTRB(14,8,14,100),children:[
      _SH(title:'Clock Entries',sub:'${es.length} records'),
      TextField(decoration:const InputDecoration(hintText:'Search by name…',prefixIcon:Icon(Icons.search_rounded),isDense:true),onChanged:(v)=>setState(()=>_q=v)),
      const SizedBox(height:10),
      for(final e in es)Padding(padding:const EdgeInsets.only(bottom:6),child:Card(child:ListTile(leading:CircleAvatar(backgroundColor:e['type']=='in'?const Color(0xFFE8F5E9):const Color(0xFFFFEBEE),child:Icon(e['type']=='in'?Icons.login_rounded:Icons.logout_rounded,color:e['type']=='in'?P.green:P.danger,size:14)),title:Text((e['displayName']??e['username']??'?').toString(),style:const TextStyle(fontWeight:FontWeight.w800)),subtitle:Text('@${e['username']??''} · ${e['date']??''}'),trailing:Column(mainAxisAlignment:MainAxisAlignment.center,crossAxisAlignment:CrossAxisAlignment.end,children:[Text(e['type']=='in'?'Clock In':'Clock Out',style:TextStyle(fontWeight:FontWeight.w700,color:e['type']=='in'?P.green:P.danger,fontSize:11)),Text(_fmtDT(e['timestamp']??''),style:const TextStyle(color:P.muted,fontSize:10))])))),
      if(es.isEmpty)const _Emp(ico:Icons.punch_clock_rounded,t:'No entries',s:'Clock entries appear here.'),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════
// CHECK LOGS
// ══════════════════════════════════════════════════════════════

class CheckLogsPage extends StatelessWidget{final WS st;const CheckLogsPage({super.key,required this.st});
  @override Widget build(BuildContext ctx){
    final ls=st.checkLogs.whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList()..sort((a,b)=>(b['timestamp']??'').toString().compareTo((a['timestamp']??'').toString()));
    return ListView(padding:const EdgeInsets.fromLTRB(14,8,14,100),children:[
      _SH(title:'Equipment Logs',sub:'${ls.length} submissions'),
      for(final l in ls)Padding(padding:const EdgeInsets.only(bottom:8),child:Card(child:ListTile(contentPadding:const EdgeInsets.all(12),leading:const Icon(Icons.handyman_rounded,color:P.green),title:Text((l['equipmentName']??'').toString(),style:const TextStyle(fontWeight:FontWeight.w800)),subtitle:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('By ${l['submittedByName']??l['submittedBy']??'?'} · ${l['date']??''}'),if((l['notes']??'').toString().isNotEmpty)Text(l['notes'].toString(),style:const TextStyle(color:P.muted,fontSize:11))]),trailing:_Pill(text:(l['status']??'ok').toString())))),
      if(ls.isEmpty)const _Emp(ico:Icons.checklist_rounded,t:'No check logs',s:'Submitted checks appear here.'),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════
// USER MANAGEMENT
// ══════════════════════════════════════════════════════════════

class UsersPage extends StatelessWidget{final WS st;final AppSession s;const UsersPage({super.key,required this.st,required this.s});
  Future<void> _edit(BuildContext ctx,[Map<String,dynamic>? ex])async{
    final dn=TextEditingController(text:ex?['displayName']?.toString()??'');
    final un=TextEditingController(text:ex?['username']?.toString()??'');
    final pw=TextEditingController();final pw2=TextEditingController();
    final role=ValueNotifier<String>((ex?['role']??'worker').toString());
    String? err;
    final ok=await showDialog<bool>(context:ctx,builder:(dx)=>StatefulBuilder(builder:(dx,ss)=>AlertDialog(
      shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(20)),
      title:Text(ex==null?'Create User':'Edit User',style:const TextStyle(fontWeight:FontWeight.w900)),
      content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        _tf(dn,'Display name *'),const SizedBox(height:8),
        TextField(controller:un,enabled:ex==null,decoration:const InputDecoration(labelText:'Username *')),const SizedBox(height:8),
        ValueListenableBuilder(valueListenable:role,builder:(_,rv,__)=>DropdownButtonFormField<String>(value:rv,items:const[DropdownMenuItem(value:'master_admin',child:Text('Master Admin')),DropdownMenuItem(value:'admin',child:Text('Admin')),DropdownMenuItem(value:'supervisor',child:Text('Supervisor')),DropdownMenuItem(value:'worker',child:Text('Worker'))],onChanged:(v)=>role.value=v??'worker',decoration:const InputDecoration(labelText:'Role'))),
        const SizedBox(height:8),
        TextField(controller:pw,obscureText:true,decoration:InputDecoration(labelText:ex==null?'Password *':'New password (blank = keep)')),const SizedBox(height:8),
        TextField(controller:pw2,obscureText:true,decoration:const InputDecoration(labelText:'Confirm password')),
        if(err!=null)...[const SizedBox(height:8),Text(err!,style:const TextStyle(color:P.danger,fontWeight:FontWeight.w700,fontSize:12))],
      ])),
      actions:[TextButton(onPressed:()=>Navigator.pop(dx,false),child:const Text('Cancel')),FilledButton(onPressed:(){
        if(dn.text.trim().isEmpty||un.text.trim().isEmpty){ss(()=>err='Name and username required.');return;}
        if(ex==null&&pw.text.isEmpty){ss(()=>err='Password required.');return;}
        if(pw.text.isNotEmpty&&pw.text!=pw2.text){ss(()=>err='Passwords do not match.');return;}
        if(pw.text.isNotEmpty&&pw.text.length<6){ss(()=>err='Min 6 characters.');return;}
        Navigator.pop(dx,true);
      },child:Text(ex==null?'Create':'Save'))],
    )));
    if(ok!=true)return;
    if(ex==null&&st.users.whereType<Map>().any((u)=>(u['username']??'').toString().toLowerCase()==un.text.trim().toLowerCase())){if(ctx.mounted)_snack(ctx,'Username already taken');return;}
    final hash=pw.text.isNotEmpty?_hash(pw.text):(ex?['passwordHash']??'').toString();
    final items=List<dynamic>.from(st.users);
    if(ex==null)items.add({'id':DateTime.now().millisecondsSinceEpoch.toString(),'username':un.text.trim(),'displayName':dn.text.trim(),'role':role.value,'passwordHash':hash,'createdAt':_today()});
    else{final i=items.indexWhere((e)=>e is Map&&e['id']==ex['id']);if(i>=0)items[i]={...ex,'displayName':dn.text.trim(),'role':role.value,'passwordHash':hash};}
    await BS.save(st.copyWith(users:items),by:s.username);
    if(ctx.mounted)_snack(ctx,ex==null?'User created!':'Updated!');
  }
  @override
  Widget build(BuildContext ctx){
    final us=st.users.whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();
    return ListView(padding:const EdgeInsets.fromLTRB(14,8,14,100),children:[
      _SH(title:'Users',sub:'${us.length} accounts',action:FilledButton.icon(onPressed:()=>_edit(ctx),icon:const Icon(Icons.person_add_rounded,size:13),label:const Text('Add User'),style:FilledButton.styleFrom(backgroundColor:P.green,foregroundColor:Colors.white,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(10)),padding:const EdgeInsets.symmetric(horizontal:10,vertical:7)))),
      for(final u in us)Padding(padding:const EdgeInsets.only(bottom:8),child:Card(child:ListTile(contentPadding:const EdgeInsets.fromLTRB(14,10,6,10),leading:CircleAvatar(backgroundColor:const Color(0xFFE8F3EA),child:Text(_ini(u['displayName']))),title:Text((u['displayName']??'').toString(),style:const TextStyle(fontWeight:FontWeight.w800)),subtitle:Text('@${u['username']??''} · ${u['role']??'worker'}'),
        trailing:Row(mainAxisSize:MainAxisSize.min,children:[if((u['username']??'')==s.username)const _Pill(text:'You'),PopupMenuButton<String>(onSelected:(v)async{if(v=='edit')_edit(ctx,u);else{if((u['username']??'')==s.username){_snack(ctx,"Can't delete yourself");return;}if(await _conf(ctx,'Delete "${u['displayName']}"?')==true)await BS.save(st.copyWith(users:st.users.where((e)=>e is Map&&e['id']!=u['id']).toList()),by:s.username);}},itemBuilder:(_)=>[const PopupMenuItem(value:'edit',child:Text('Edit')),const PopupMenuItem(value:'del',child:Text('Delete',style:TextStyle(color:P.danger)))])])))),
      if(us.isEmpty)const _Emp(ico:Icons.manage_accounts_rounded,t:'No users',s:'Add the first account.'),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════
// SHARED WIDGETS
// ══════════════════════════════════════════════════════════════

class _SH extends StatelessWidget{final String title,sub;final Widget? action;const _SH({required this.title,required this.sub,this.action});@override Widget build(BuildContext ctx)=>Padding(padding:const EdgeInsets.only(bottom:10),child:Row(children:[Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(title,style:const TextStyle(fontSize:20,fontWeight:FontWeight.w900)),Text(sub,style:const TextStyle(color:P.muted,fontSize:11))])),if(action!=null)action!]));}
class _SC extends StatelessWidget{final String t;final Widget child;const _SC({required this.t,required this.child});@override Widget build(BuildContext ctx)=>Card(child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(t,style:const TextStyle(fontSize:15,fontWeight:FontWeight.w900)),const SizedBox(height:7),child])));}
class _Stat extends StatelessWidget{final String t,v,s;final IconData ico;final Color c;const _Stat({required this.t,required this.v,required this.s,required this.ico,required this.c});@override Widget build(BuildContext ctx)=>Card(child:Padding(padding:const EdgeInsets.all(13),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Icon(ico,color:c,size:20),const Spacer(),Text(t,style:const TextStyle(color:P.muted,fontWeight:FontWeight.w700,fontSize:11)),const SizedBox(height:3),Text(v,style:const TextStyle(fontSize:20,fontWeight:FontWeight.w900)),Text(s,style:const TextStyle(fontSize:10,color:P.muted))])));}
class _Ch extends StatelessWidget{final String t;const _Ch(this.t);@override Widget build(BuildContext ctx)=>Container(padding:const EdgeInsets.symmetric(horizontal:11,vertical:6),decoration:BoxDecoration(color:const Color(0xFFE8F3EA),borderRadius:BorderRadius.circular(99)),child:Text(t,style:const TextStyle(fontWeight:FontWeight.w700,fontSize:11)));}
class _Pill extends StatelessWidget{final String text;const _Pill({required this.text});@override Widget build(BuildContext ctx){final l=text.toLowerCase();Color bg,fg;switch(l){case'paid':case'ok':case'active':case'accepted':case'you':bg=const Color(0xFFE8F5E9);fg=P.green;break;case'issue':case'pending':bg=const Color(0xFFFFF8E1);fg=const Color(0xFFE65100);break;case'missing':case'unpaid':case'declined':bg=const Color(0xFFFFEBEE);fg=P.danger;break;default:bg=const Color(0xFFF1F1F1);fg=P.muted;}return Container(padding:const EdgeInsets.symmetric(horizontal:7,vertical:3),decoration:BoxDecoration(color:bg,borderRadius:BorderRadius.circular(99)),child:Text(text,style:TextStyle(color:fg,fontWeight:FontWeight.w800,fontSize:10)));}}
class _AT extends StatelessWidget{final IconData ico;final String t,s;final VoidCallback f;const _AT({required this.ico,required this.t,required this.s,required this.f});@override Widget build(BuildContext ctx)=>Padding(padding:const EdgeInsets.only(bottom:10),child:Card(child:ListTile(contentPadding:const EdgeInsets.all(12),leading:CircleAvatar(backgroundColor:const Color(0xFFE8F3EA),child:Icon(ico,color:P.green,size:18)),title:Text(t,style:const TextStyle(fontWeight:FontWeight.w900,fontSize:14)),subtitle:Text(s,style:const TextStyle(fontSize:11)),trailing:const Icon(Icons.chevron_right_rounded,size:18),onTap:f)));}
class _Emp extends StatelessWidget{final IconData ico;final String t,s;const _Emp({required this.ico,required this.t,required this.s});@override Widget build(BuildContext ctx)=>Card(child:Padding(padding:const EdgeInsets.all(26),child:Column(children:[Icon(ico,size:38,color:P.green),const SizedBox(height:10),Text(t,style:const TextStyle(fontWeight:FontWeight.w900,fontSize:16)),const SizedBox(height:5),Text(s,textAlign:TextAlign.center,style:const TextStyle(color:P.muted,fontSize:12))])));}
class _Dlg extends StatelessWidget{final String title;final Widget child;const _Dlg({required this.title,required this.child});@override Widget build(BuildContext ctx)=>AlertDialog(shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(20)),title:Text(title,style:const TextStyle(fontWeight:FontWeight.w900)),content:SingleChildScrollView(child:child),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Save'))]);}

// ══════════════════════════════════════════════════════════════
// UTILITIES
// ══════════════════════════════════════════════════════════════

TextField _tf(TextEditingController c,String l,{bool num=false,VoidCallback? onCh})=>TextField(controller:c,keyboardType:num?const TextInputType.numberWithOptions(decimal:true):TextInputType.text,decoration:InputDecoration(labelText:l),onChanged:onCh!=null?(_)=>onCh():null);
Widget _fab(VoidCallback fn,String lbl)=>FilledButton.icon(onPressed:fn,icon:const Icon(Icons.add_rounded,size:15),label:Text(lbl),style:FilledButton.styleFrom(backgroundColor:P.green,foregroundColor:Colors.white,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(10)),padding:const EdgeInsets.symmetric(horizontal:12,vertical:8)));
Future<bool?> _conf(BuildContext ctx,String msg)=>showDialog<bool>(context:ctx,builder:(_)=>AlertDialog(title:const Text('Confirm'),content:Text(msg),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),FilledButton(style:FilledButton.styleFrom(backgroundColor:P.danger),onPressed:()=>Navigator.pop(ctx,true),child:const Text('Delete'))]));
void _snack(BuildContext ctx,String msg)=>ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content:Text(msg),behavior:SnackBarBehavior.floating,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(10))));
void _go(BuildContext ctx,Widget w)=>Navigator.push(ctx,MaterialPageRoute(builder:(_)=>Scaffold(appBar:AppBar(),body:w)));
void _push(BuildContext ctx,Widget w)=>Navigator.push(ctx,MaterialPageRoute(builder:(_)=>Scaffold(appBar:AppBar(),body:w)));
String _today()=>DateFormat('yyyy-MM-dd').format(DateTime.now());
double _n(dynamic v)=>v is num?v.toDouble():double.tryParse('$v')??0;
String _m(double v)=>'R${v.toStringAsFixed(2)}';
String _ini(dynamic n){final p=(n??'').toString().trim().split(RegExp(r'\s+')).where((e)=>e.isNotEmpty).toList();if(p.isEmpty)return'P';return p.take(2).map((e)=>e[0].toUpperCase()).join();}
String _fmtDT(String iso){try{return DateFormat('HH:mm · d MMM yyyy').format(DateTime.parse(iso).toLocal());}catch(_){return iso;}}
int min(int a,int b)=>a<b?a:b;
dynamic _safe(dynamic v){if(v is Timestamp)return v.toDate().toIso8601String();if(v is DateTime)return v.toIso8601String();if(v is Map)return v.map((k,val)=>MapEntry(k.toString(),_safe(val)));if(v is Iterable)return v.map(_safe).toList();return v;}

// ── Hash (matches web app exactly) ───────────────────────────
String _hash(String msg){
  int n(int x)=>x&0xffffffff;
  const k=[0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2];
  var h0=0x6a09e667,h1=0xbb67ae85,h2=0x3c6ef372,h3=0xa54ff53a,h4=0x510e527f,h5=0x9b05688c,h6=0x1f83d9ab,h7=0x5be0cd19;
  final bytes=<int>[];
  for(var i=0;i<msg.length;i++){final c=msg.codeUnitAt(i);if(c<128){bytes.add(c);}else if(c<2048){bytes.add((c>>6)|192);bytes.add((c&63)|128);}else{bytes.add((c>>12)|224);bytes.add(((c>>6)&63)|128);bytes.add((c&63)|128);}}
  final bl=bytes.length;final bits=bl*8;
  bytes.add(0x80);while(bytes.length%64!=56)bytes.add(0);
  bytes.addAll([0,0,0,0,bits~/0x100000000,(bits>>24)&0xff,(bits>>16)&0xff,(bits>>8)&0xff,bits&0xff]);
  while(bytes.length%64!=0)bytes.add(0);
  for(var i=0;i<bytes.length;i+=64){
    final w=List<int>.filled(64,0);
    for(var j=0;j<16;j++)w[j]=(bytes[i+j*4]<<24)|(bytes[i+j*4+1]<<16)|(bytes[i+j*4+2]<<8)|bytes[i+j*4+3];
    for(var j=16;j<64;j++){final s0=n(((w[j-15]>>7)|(w[j-15]<<25))^((w[j-15]>>18)|(w[j-15]<<14))^(w[j-15]>>3));final s1=n(((w[j-2]>>17)|(w[j-2]<<15))^((w[j-2]>>19)|(w[j-2]<<13))^(w[j-2]>>10));w[j]=n(w[j-16]+s0+w[j-7]+s1);}
    var a=h0,b=h1,c=h2,d=h3,e=h4,f=h5,g=h6,hh=h7;
    for(var j=0;j<64;j++){final s1=n(((e>>6)|(e<<26))^((e>>11)|(e<<21))^((e>>25)|(e<<7)));final ch=(e&f)^((~e)&g);final t1=n(hh+s1+ch+k[j]+w[j]);final s0=n(((a>>2)|(a<<30))^((a>>13)|(a<<19))^((a>>22)|(a<<10)));final maj=(a&b)^(a&c)^(b&d);final t2=n(s0+maj);hh=g;g=f;f=e;e=n(d+t1);d=c;c=b;b=a;a=n(t1+t2);}
    h0=n(h0+a);h1=n(h1+b);h2=n(h2+c);h3=n(h3+d);h4=n(h4+e);h5=n(h5+f);h6=n(h6+g);h7=n(h7+hh);
  }
  return[h0,h1,h2,h3,h4,h5,h6,h7].map((x)=>x.toRadixString(16).padLeft(8,'0')).join();
}
