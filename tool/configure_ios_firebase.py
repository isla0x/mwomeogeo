#!/usr/bin/env python3
"""Prepare iOS FirebaseOptions from the Firebase console's public app plist."""
import json
import plistlib
import sys
from pathlib import Path

root=Path(__file__).resolve().parents[1]
source=Path(sys.argv[1]).expanduser().resolve() if len(sys.argv)>1 else root/'GoogleService-Info.plist'
if not source.is_file():
    raise SystemExit('Firebase에서 iOS 앱(com.chaen.mwomeogeo)의 GoogleService-Info.plist를 내려받아 경로를 지정해 주세요.')
with source.open('rb') as stream:
    data=plistlib.load(stream)
required=['API_KEY','GOOGLE_APP_ID','GCM_SENDER_ID','PROJECT_ID','BUNDLE_ID','STORAGE_BUCKET']
missing=[key for key in required if not isinstance(data.get(key),str) or not data[key].strip()]
if missing:
    raise SystemExit('설정 파일에서 필요한 항목을 찾지 못했어요: '+', '.join(missing))
if data['BUNDLE_ID']!='com.chaen.mwomeogeo':
    raise SystemExit('현재 앱의 Bundle ID는 com.chaen.mwomeogeo예요. 이 ID로 등록한 Firebase iOS 앱 설정 파일을 사용해 주세요.')
def dart_string(value):
    return json.dumps(value,ensure_ascii=False).replace('$',r'\$')
pairs={'apiKey':data['API_KEY'],'appId':data['GOOGLE_APP_ID'],'messagingSenderId':data['GCM_SENDER_ID'],
       'projectId':data['PROJECT_ID'],'storageBucket':data['STORAGE_BUCKET'],'iosBundleId':data['BUNDLE_ID']}
fields='\n'.join('    '+key+': '+dart_string(value)+',' for key,value in pairs.items())
dart="""// Firebase iOS app configuration. These are public app identifiers.
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) return ios;
    throw UnsupportedError('이 설정은 iOS용이에요. 다른 플랫폼은 FlutterFire CLI로 설정해 주세요.');
  }
  static const FirebaseOptions ios = FirebaseOptions(
"""+fields+"""
  );
}
"""
(root/'lib/firebase_options.dart').write_text(dart,encoding='utf-8')
print('Firebase iOS 앱 설정을 반영했어요. 다음 설치 빌드에 적용됩니다.')
print('프로젝트: '+data['PROJECT_ID'])
