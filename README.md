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

**매번 앱을 열 때 빌드하는 구조가 아닙니다.** 앱 설치·코드 업데이트 시 빌드합니다. iPhone에서 개발 도구 없이 아이콘으로 실행할 앱은 연결한 iPhone을 대상으로 release 모드로 설치합니다.

```sh
flutter run --release
```

기기 목록이 뜨면 iPhone을 선택합니다. 현재 환경에서는 실제 iPhone 설치와 독립 실행을 검증하지 못했습니다.

## Firebase 무료 구성 (Spark)

결제 계정·Cloud Storage·Cloud Functions 없이 **익명 인증 + Firestore**만 사용합니다. mwomeogeo 프로젝트의 익명 인증과 서울(asia-northeast3) 기본 데이터베이스는 준비되어 있습니다. 무료 구성의 firestore.rules도 Firebase Console에 게시했습니다. 이후 규칙을 변경하면 다시 게시해야 합니다.

- 앱에서 식탁과 128비트 무작위 초대 코드(32자리)를 원자적으로 만듭니다. 초대 코드를 복사해 전달합니다.
- 초대 문서는 코드로 한 건만 조회할 수 있고 목록 조회는 금지합니다. 참여 시 본인만 멤버에 추가할 수 있으며 최대 20명입니다. 초대 코드는 방 열쇠이므로 공개하지 마세요.
- 사진은 앱에서 긴 변 최대 960px JPEG로 압축하며 최대 128KiB로 제한합니다. 피드 문서와 분리된 멤버 전용 Firestore 문서에 저장합니다. 공개 다운로드 URL은 없습니다.
- 작성자가 삭제할 때 댓글·반응 추가를 먼저 막고, 하위 기록을 정리한 다음 사진과 게시물을 함께 삭제합니다. 중단되면 피드에 남은 기록에서 삭제를 재시도할 수 있습니다.
- 무료 할당량: 저장 1GiB, 일일 읽기 50,000회·쓰기 20,000회·삭제 20,000회, 월 외부 전송 10GiB입니다. 프로젝트 전체가 공유하는 한도입니다. 보안 규칙의 조회와 실시간 갱신도 사용량에 포함됩니다. Spark에서는 한도를 넘으면 해당 작업이 제한되며 유료 전환하지 않습니다.
- 사진이 많은 공개 서비스용 구조는 아닙니다. 용량을 비우려면 본인의 오래된 기록을 삭제해야 합니다. 로그인 없는 익명 계정은 재설치 후 본인 권한을 복구하지 못할 수 있습니다.

Firebase Console → Firestore → 규칙에서 firestore.rules를 게시합니다. CLI를 사용하는 개발자는 아래처럼 **Firestore만** 배포합니다. Storage나 Functions를 활성화할 필요가 없습니다.

```sh
firebase login
firebase deploy --only firestore --project mwomeogeo
```

다른 프로젝트의 iOS 설정을 반영할 때만 다음 스크립트를 사용합니다.

```sh
python3 tool/configure_ios_firebase.py /파일경로/GoogleService-Info.plist
```

기존 빌드 3은 Functions·Storage를 사용하는 버전이므로 **빌드 4로 업데이트해야 합니다.** 앱을 열 때마다 빌드하는 것은 아닙니다. 서버 설정 변경만으로 앱 재빌드가 필요한 것은 아니지만, 이번에는 앱의 저장 방식을 바꾸었으므로 한 번 업데이트합니다.

공식 한도: https://firebase.google.com/docs/firestore/quotas

## 구현한 기능

- 원본과 같은 흰 배경, 체리 #BF3954, 하늘색 #EAF2F9, Pretendard 및 목업 사진
- 우리 둘 / 가족 식탁, 아침·점심·저녁을 한 화면에서 순서대로 보는 하루 피드
- 실제 카메라/시스템 사진 선택, 80자 한마디, 식탁 선택 및 저장 완료
- 사진을 앱 전용 공간에 보관하고 시스템 사진첩에 자동 저장하지 않음
- 로컬 기록·댓글·반응 복원, 날짜별 달력과 기록 삭제, 시스템 공유 시트
- 식탁 0개로 시작하는 첫 화면과 사용자가 직접 만드는 식탁. 디자인 예시는 내부 검증에서만 사용
- Firebase 설정 시 자동 익명 식별, 이름 지정, 초대 코드 기반 공유 식탁
- 보고 있는 공유 식탁의 게시물·댓글·반응 자동 갱신
- 보안 규칙으로 검증하는 초대 참여·인원 제한·본인 기록 삭제
- Firestore에서 식탁 멤버만 기록과 압축 사진을 읽도록 제한
- 사진은 로그인된 SDK 요청으로 읽으며 외부 공개 다운로드 URL을 만들지 않음
- 기기 내부 식탁과 공유 식탁을 한 전송에 섞지 않음

## 검증 결과와 한계

- Dart/Flutter 정적 분석 및 debug 커널 컴파일
- tool/verify.dart에서 사진 분리 보관, 재시작 복원, 교차 식탁 표시, 댓글·반응, 날짜 필터, 삭제 및 주요 화면 렌더링 검증
- test/shared_photo_test.dart에서 고해상도 사진 압축·크기 상한·비율 보존·잘못된 사진 입력을 검사
- tool/rules/firestore.test.cjs에서 실제 Firestore 에뮬레이터로 58개 권한·공유 검사를 통과했습니다. 초대 없는 접근, 멤버 위조, 사진 크기 초과, 타인 삭제, 삭제 중 댓글 추가를 거부하고 정상 생성·초대·중복 참여·사진 공유·작성자 삭제·20명 제한을 확인합니다. 운영 서버에 테스트 계정이나 데이터를 만들지 않습니다.
- Flutter 테스트 12개 통과, Dart 정적 분석 진단 0개입니다. 기본 분석 서버의 환경 제한 때문에 동일 analyzer 라이브러리로 lib/와 test/를 분석했습니다.
- 실제 iPhone 두 기기 사이의 공유 확인은 빌드 4 설치 후 필요합니다.
- **iOS 네이티브 빌드·설치는 미검증**: 이 작업 환경은 Xcode 캐시 쓰기와 CoreSimulator 접근을 제한합니다.
- Flutter 단위·화면 테스트와 별도 Flutter 엔진 검증기를 사용했습니다.
- 사진 촬영 및 권한 거부/재허용 동작은 실제 iPhone에서 확인해야 합니다.

화면 미리보기는 preview/에 있습니다. 상세 실행 결과는 preview/verification.json을 확인합니다.

보안 규칙 검사를 다시 실행하려면 Node.js 22+와 Java 21+에서:

```sh
cd tool/rules
npm install
npm test
```

## 현재 범위

푸시 알림, 기기 간 본인 식별값 복구, 탈퇴·식탁 나가기, 초대 코드 회전, 원격 사진 오프라인 저장, 신고·차단 및 App Store 제출은 아직 포함하지 않았습니다. 앱 안의 식탁 소식은 현재 불러온 기록을 표시하며 푸시 알림으로 표시하지 않습니다. 로컬 기록은 자동으로 공유 식탁으로 이전되지 않습니다.

Firebase 연결이 끊기면 자동 갱신 오류를 표시하고 수동 새로고침할 수 있습니다. 네트워크 오류로 전송 결과가 불확실한 경우 다시 보내기 전에 피드를 확인해야 하며, 현재는 서버가 수락한 요청에 대한 중복 방지 키를 구현하지 않았습니다.

## 주요 파일

- lib/main.dart: 홈·식탁·달력
- lib/compose.dart: 촬영·사진 선택·작성
- lib/settings.dart: 이름·식탁 관리. 회원가입/로그인 화면 없음
- lib/store.dart: 기기 기록과 실시간 식탁 상태
- lib/cloud.dart: Firebase 익명 인증·Firestore 무료 공유
- lib/shared_photo.dart: 별도 isolate에서 작은 JPEG로 사진 압축
- lib/firebase_options.dart: 제공받은 mwomeogeo 프로젝트의 공개 iOS 앱 식별값. 관리자 키는 포함하지 않음
- firestore.rules: 멤버·작성자·초대 코드·사진 크기를 검증하는 접근 규칙
- tool/configure_ios_firebase.py: Firebase iOS 설정 반영
- test/: 로컬 저장/화면 테스트
- tool/verify.dart: 제한 환경용 별도 검증기

원본: https://mwomeogeo-concept.islaay.chatgpt.site/
공식 설정: https://firebase.google.com/docs/flutter/setup
서체: Pretendard, SIL Open Font License (assets/fonts/OFL.txt).
