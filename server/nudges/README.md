# 밥 안부 푸시 알림 — 연결 대기

식사별 종 버튼을 누르면 같은 식탁에서 알림을 켠 다른 사람에게 `아침 뭐 먹어!?`, `점심 뭐 먹어!?`, `저녁 뭐 먹어!?`를 즉시 보냅니다. 같은 식탁/식사에는 30분 제한을 적용합니다. 현재 이 브랜치는 서버 배포·Apple 푸시 키 연결·실기기 검증 전입니다. main의 빌드 9는 글씨 크기 변경까지 포함합니다.

## 처음 한 번 연결

1. Apple Developer의 `com.chaen.mwomeogeo` App ID에서 Push Notifications를 켭니다. Xcode 자동 서명으로 새 프로비저닝 프로필을 받습니다.
2. Apple Developer에서 해당 앱의 **production APNs** 전송이 가능한 `.p8` 키와 Key ID, Team ID를 준비합니다. 키는 로컬 보안 폴더에 보관하고 Git/Flutter/대화창에 넣지 않습니다. 키 권한은 이 앱에 필요한 범위로 제한합니다.
3. Cloudflare **Workers Free** 계정으로 로그인한 뒤 다음을 실행합니다. Firebase Spark 요금제를 바꾸지 않습니다. SQLite Durable Objects의 Free 한도 내에서 사용하며 한도 초과 시 요금제를 자동 변경하지 않습니다.

```sh
cd server/nudges
npm ci
npx wrangler login
npx wrangler deploy
npx wrangler secret put APNS_PRIVATE_KEY
npx wrangler secret put APNS_KEY_ID
npx wrangler secret put APNS_TEAM_ID
```

`APNS_PRIVATE_KEY`에는 `.p8` 파일의 전체 PEM 내용을 안전한 입력창에서 입력합니다. 나머지는 Apple의 해당 Key ID/Team ID입니다. 개인 키나 Firebase 관리자 키를 앱에 포함하지 않습니다.

4. 실제 배포된 `https://...workers.dev` 주소로 앱을 빌드합니다. 주소는 공개 설정이며 개인 키가 아닙니다.

```sh
flutter pub get
flutter build ipa --build-number=10 --dart-define=NUDGE_API_URL=https://실제배포주소.workers.dev
open build/ios/archive/Runner.xcarchive
```

5. 두 iPhone에 새 빌드를 설치하고 **내 정보 → 식사 알림 받기**를 켭니다. 같은 식탁에 참여한 뒤, 상대 기기를 잠근 상태에서 식사 옆 종 버튼으로 확인합니다. 권한 거절 시 iPhone 설정에서 앱 알림을 다시 허용할 수 있습니다. 앱이 열려 있어도 배너를 표시하며 알림을 누르면 멤버 권한이 있는 식탁의 오늘 피드를 선택합니다.

TestFlight/App Store는 production APNs를 사용합니다. Debug는 sandbox를 사용하므로 디버그 실험 시 해당 환경을 허용한 키/별도 서버 설정이 필요합니다. 시뮬레이터의 실제 APNs 수신을 검증한 것으로 간주하지 않습니다. 알림 도착은 OS 알림 설정·집중 모드·연결 상태의 영향을 받습니다.

## 보안과 동작

- 클라이언트는 Firebase 익명 인증 ID 토큰으로 요청합니다. 서버는 기존 Firestore 멤버 전용 규칙을 통과한 요청만 허용합니다. JSON 토큰을 단순 디코딩한 값만으로 인증하지 않습니다.
- 수신자는 서버가 읽은 현재 멤버 목록에서 결정합니다. 요청으로 받은 임의 메시지/수신자/작성자 필드는 사용하지 않습니다.
- APNs 토큰은 비공개 Durable Object에만 보관합니다. 클라이언트에 다른 사람의 토큰을 반환하지 않습니다. 한 사용자당 현재 토큰 하나를 유지하고 토큰이 새 사용자로 등록되면 예전 소유자 연결을 제거합니다.
- 알림 끄기, 토큰 변경, APNs 만료 응답을 처리합니다. 30일 이상 갱신되지 않은 토큰에는 전송하지 않습니다. 익명 식별값은 기기/앱 데이터 초기화 시 바뀔 수 있습니다.
- 원자적 30분 제한과 요청 ID로 동시 클릭/재시도를 처리합니다. 네트워크 타임아웃으로 수락 여부가 불명확하면 자동으로 재발송하지 않습니다.
- 전송 성공은 APNs가 요청을 수락한 경우만 반환합니다. 사용자 화면에서 실제 읽음/도착을 확인한 것으로 표시하지 않습니다.
- 운영 서버에 실제 알림을 보내는 테스트는 아직 실행하지 않았습니다.

## 검증

```sh
npm test
npx wrangler deploy --dry-run
```

Node 테스트 5개는 인증/권한/입력 경계, 본인 제외/문구/중복 방지, 동시 전송 제한, 토큰 교체/끄기/소유권, APNs 거절 처리를 모의합니다. iOS AppDelegate는 실제 iOS SDK와 Flutter 헤더로 Swift 타입 검사를 통과했습니다. 코드 서명·실제 빌드/배포·두 기기 수신은 별도 확인이 필요합니다.

공식 참고:
- https://firebase.google.com/docs/functions/get-started (Functions 배포에는 Blaze 필요)
- https://developers.cloudflare.com/durable-objects/platform/pricing/
- https://developer.apple.com/documentation/usernotifications/registering-your-app-with-apns
- https://developer.apple.com/documentation/usernotifications/sending-notification-requests-to-apns
