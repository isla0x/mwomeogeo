# 뭐먹어?

사진 한 장으로 나누는, 우리의 안부. Cherry Sky 목업을 Flutter로 옮긴 iOS 중심 앱입니다.

## 사용자 흐름

**앱 열기(식탁 0개) → 이름 정하기 → 식탁 만들기 또는 초대 코드로 참여 → 한 끼 남기기**

처음부터 만들어진 방이나 예시 사진은 표시하지 않습니다. 식탁을 만든 뒤에는 아침·점심·저녁을 누르며 전환하지 않고 한 피드에서 순서대로 확인합니다. 각 끼니의 '남기기'를 누르면 해당 끼니로 작성 화면이 열립니다. 이전 버전에서 실제로 저장한 기록과 그 식탁은 유지합니다.

이메일·비밀번호·소셜 로그인 화면이 없습니다. Firebase 익명 인증은 앱 내부에서 자동 처리합니다. 같은 기기에서 앱을 다시 열면 Firebase SDK가 보관한 익명 식별값을 복원합니다. 별도 계정 복구 기능은 없으며 기기 변경·앱 데이터 초기화 후에는 새로 초대받아야 할 수 있습니다. 기존 작성자 권한 복구도 보장하지 않습니다.

## 처음 실행

Flutter 3.47.7 / Dart 3.13.5 기준, iOS 15 이상 및 Xcode가 필요합니다.

GitHub: https://github.com/isla0x/mwomeogeo

맥에서 처음 내려받을 때:

```sh
cd ~/Documents
git clone https://github.com/isla0x/mwomeogeo.git
cd mwomeogeo
flutter pub get
open ios/Runner.xcworkspace
```

Xcode에서 Runner 타깃 → Signing & Capabilities → Team을 본인 Apple Developer Team으로 한 번 지정합니다. Bundle Identifier는 Firebase 설정과 같은 **com.chaen.mwomeogeo**를 유지합니다. App Store용 IPA에는 해당 Team의 배포 인증서와 프로비저닝 설정이 필요합니다.

그다음 빌드하거나, 이후 코드를 업데이트할 때:

```sh
cd ~/Documents/mwomeogeo
git pull --ff-only
flutter pub get
flutter build ipa
open build/ios/archive/Runner.xcarchive
```

빌드에 실패하면 먼저 해당 오류를 해결한 후 다음 명령을 실행합니다. Archive는 Xcode에서 검증·배포할 수 있으며 이 명령이 앱을 자동으로 심사 제출하지는 않습니다.

프로젝트 폴더의 run-ios.command를 실행하거나 터미널에서:

```sh
./run-ios.command
```

패키지를 준비하고 시뮬레이터를 엽니다. 시뮬레이터에는 실제 카메라가 없으므로 사진 선택 버튼을 사용합니다. 실기기는 Xcode의 Runner → Signing & Capabilities에서 본인 Team을 선택한 뒤 테스트합니다.

**매번 앱을 열 때 빌드하는 구조가 아닙니다.** 앱 설치·코드 업데이트·서버 설정 변경 시 빌드합니다. iPhone에서 개발 도구 없이 아이콘으로 실행할 앱은 연결한 iPhone을 대상으로 release 모드로 설치합니다.

```sh
flutter run --release
```

기기 목록이 뜨면 iPhone을 선택합니다. 현재 환경에서는 실제 iPhone 설치와 독립 실행을 검증하지 못했습니다.

## Firebase 최초 연결

제공받은 iOS 앱 설정을 **mwomeogeo** 프로젝트용 lib/firebase_options.dart에 반영했습니다. 원본 plist를 다시 복사할 필요는 없습니다. 익명 인증 활성화, 데이터베이스·버킷 준비와 서버 배포는 아직 확인하지 않았습니다. 아래 설정은 개발자가 처음 연결할 때 필요한 작업이며, 앱 사용자가 할 일은 아닙니다. 다른 Firebase 프로젝트를 사용할 경우 1~5번으로 앱 설정을 교체합니다.

1. Firebase Console에서 프로젝트를 만들거나 기존 프로젝트를 선택합니다.
2. iOS 앱을 Bundle ID **com.chaen.mwomeogeo**로 등록하고 GoogleService-Info.plist를 내려받습니다.
3. Authentication → Sign-in method에서 **Anonymous(익명)**만 활성화합니다. 이메일·비밀번호 로그인은 필요 없습니다. 익명 계정 자동 정리 기능을 켜면 식탁 멤버가 장기간 접속하지 않을 때 식별값이 삭제될 수 있으므로 이 앱의 익명 사용자 수명 정책을 먼저 정해야 합니다.
4. Cloud Firestore를 **Standard edition / Native mode / 기본 (default) 데이터베이스**로 만들고 Cloud Storage 기본 버킷을 준비합니다. Cloud Storage와 Cloud Functions 배포에는 결제 계정이 연결된 Blaze 요금제가 필요하며 사용량에 따라 요금이 발생합니다. 이 작업에서는 결제 설정을 변경하지 않았습니다.
5. iOS 앱 설정 파일을 반영합니다.

```sh
python3 tool/configure_ios_firebase.py /파일경로/GoogleService-Info.plist
```

이 스크립트는 공개 앱 식별값을 lib/firebase_options.dart에 작성합니다. 서비스 계정 키나 관리자 비밀 키는 사용하지 않습니다. 현재는 iOS 설정만 생성합니다. Android까지 연결하려면 FlutterFire CLI의 flutterfire configure로 각 플랫폼을 설정합니다.

6. Node.js 22 이상과 Firebase CLI를 준비하고, 프로젝트 소유자의 계정으로 최초 서버 설정을 배포합니다.

```sh
npm install -g firebase-tools
firebase login
npm install --prefix functions
firebase deploy --only firestore:rules,storage,functions --project mwomeogeo
```

Storage 규칙은 Firestore의 식탁 멤버십을 조회합니다. 최초 배포 때 이 조회를 위한 서비스 권한 설정을 완료해야 합니다. 기본 Functions 리전은 asia-northeast3이며 앱과 함수 설정이 같아야 합니다.

7. 앱을 다시 빌드·설치합니다. 이후 같은 서버에 연결된 두 기기에서 식탁 생성 → 초대 코드 참여 → 사진/댓글/반응 공유를 확인합니다.

SQL 파일이나 Supabase 설정은 이제 사용하지 않습니다. 최초 배포를 마친 후에는 앱을 켤 때마다 위 작업을 반복하지 않습니다.

## 구현한 기능

- 원본과 같은 흰 배경, 체리 #BF3954, 하늘색 #EAF2F9, Pretendard 및 목업 사진
- 우리 둘 / 가족 식탁, 아침·점심·저녁을 한 화면에서 순서대로 보는 하루 피드
- 실제 카메라/시스템 사진 선택, 80자 한마디, 식탁 선택 및 저장 완료
- 사진을 앱 전용 공간에 보관하고 시스템 사진첩에 자동 저장하지 않음
- 로컬 기록·댓글·반응 복원, 날짜별 달력과 기록 삭제, 시스템 공유 시트
- 식탁 0개로 시작하는 첫 화면과 사용자가 직접 만드는 식탁. 디자인 예시는 내부 검증에서만 사용
- Firebase 설정 시 자동 익명 식별, 이름 지정, 초대 코드 기반 공유 식탁
- 보고 있는 공유 식탁의 게시물·댓글·반응 자동 갱신
- 초대 검증·인원 제한·본인 기록 삭제를 처리하는 Callable Functions
- Firestore와 Storage에서 식탁 멤버만 데이터를 읽도록 제한
- 사진은 로그인된 SDK 요청으로 읽으며 외부 공개 다운로드 URL을 만들지 않음
- 기기 내부 식탁과 공유 식탁을 한 전송에 섞지 않음

## 검증 결과와 한계

- Dart/Flutter 정적 분석 및 debug 커널 컴파일
- tool/verify.dart에서 사진 분리 보관, 재시작 복원, 교차 식탁 표시, 댓글·반응, 날짜 필터, 삭제 및 주요 화면 렌더링 검증
- functions/authorization.test.cjs에서 실제 Callable 처리 코드를 메모리 저장소로 실행하여 인증 누락·초대 검증·중복 참여·인원 제한·다른 사람 기록 삭제 방지·하위 기록 삭제·경로 제한을 검사
- 서버 권한 단위 검사는 실제 Firebase 보안 규칙/에뮬레이터 실행을 대체하지 않습니다.
- **실제 Firebase 연동·배포는 아직 미검증**: iOS 앱 설정은 반영했으며 서버 배포와 두 기기 간 공유 확인이 남아 있습니다.
- **iOS 네이티브 빌드·설치는 미검증**: 이 작업 환경은 Xcode 캐시 쓰기와 CoreSimulator 접근을 제한합니다.
- Flutter 단위·화면 테스트와 별도 Flutter 엔진 검증기를 사용했습니다.
- 사진 촬영 및 권한 거부/재허용 동작은 실제 iPhone에서 확인해야 합니다.

화면 미리보기는 preview/에 있습니다. 상세 실행 결과는 preview/verification.json을 확인합니다.

## 현재 범위

푸시 알림, 기기 간 본인 식별값 복구, 탈퇴·식탁 나가기, 초대 코드 회전, 원격 사진 오프라인 저장, 신고·차단 및 App Store 제출은 아직 포함하지 않았습니다. 앱 안의 식탁 소식은 현재 불러온 기록을 표시하며 푸시 알림으로 표시하지 않습니다. 로컬 기록은 자동으로 공유 식탁으로 이전되지 않습니다.

Firebase 연결이 끊기면 자동 갱신 오류를 표시하고 수동 새로고침할 수 있습니다. 네트워크 오류로 전송 결과가 불확실한 경우 다시 보내기 전에 피드를 확인해야 하며, 현재는 서버가 수락한 요청에 대한 중복 방지 키를 구현하지 않았습니다.

## 주요 파일

- lib/main.dart: 홈·식탁·달력
- lib/compose.dart: 촬영·사진 선택·작성
- lib/settings.dart: 이름·식탁 관리. 회원가입/로그인 화면 없음
- lib/store.dart: 기기 기록과 실시간 식탁 상태
- lib/cloud.dart: Firebase 익명 인증·Firestore·Storage·Functions
- lib/firebase_options.dart: 제공받은 mwomeogeo 프로젝트의 공개 iOS 앱 식별값. 관리자 키는 포함하지 않음
- functions/: 식탁 생성·초대 참여·본인 게시물 삭제
- firestore.rules / storage.rules: 기본 비공개 접근 규칙
- tool/configure_ios_firebase.py: Firebase iOS 설정 반영
- test/: 로컬 저장/화면 테스트
- tool/verify.dart: 제한 환경용 별도 검증기

원본: https://mwomeogeo-concept.islaay.chatgpt.site/
공식 설정: https://firebase.google.com/docs/flutter/setup
서체: Pretendard, SIL Open Font License (assets/fonts/OFL.txt).
